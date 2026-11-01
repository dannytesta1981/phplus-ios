import XCTest
import WebKit
import AVFoundation
@testable import phplus

@MainActor private final class FrameCollector: NSObject, WKScriptMessageHandler {
    var frames: [WKFrameInfo] = []
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        frames.append(message.frameInfo)
    }
}

@MainActor final class FaceScanRegressionTests: XCTestCase {
    func waitFor(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<200 {
            if (try? await condition()) == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Synthetic HTTPS condition timed out")
        throw NSError(domain: "FixtureTimeout", code: 2)
    }
    func ready(_ view: WKWebView, path: String) async throws {
        try await waitFor {
            guard !view.isLoading else { return false }
            return (try await view.evaluateJavaScript("document.readyState === 'complete' && location.pathname === '\(path)' && !!document.getElementById('fixtureReady')")) as? Bool == true
        }
    }
    func visibleState() async throws -> (WebState, UIWindow) {
        try await waitFor { UIApplication.shared.applicationState == .active }
        let state = WebState()
        state.entry = URL(string: "https://localhost:8843/dashboard")!
        state.setAuthorization(true)
        let host = state.prepareHost(url: state.entry!)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController(); window.rootViewController = root
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.frame = window.bounds; root.view.addSubview(host)
        window.makeKeyAndVisible()
        return (state, window)
    }
    func permission(_ state: WebState, view: WKWebView, origin: WKSecurityOrigin, frame: WKFrameInfo, type: WKMediaCaptureType = .camera) -> WKPermissionDecision {
        var decision: WKPermissionDecision?
        state.coordinator().webView(view, requestMediaCapturePermissionFor: origin, initiatedByFrame: frame, type: type) { decision = $0 }
        XCTAssertNotNil(decision)
        if decision == .deny {
            print("SYNTHETIC capture context: authorized=\(state.authorized) recovery=\(state.recoveryVisible) application=\(UIApplication.shared.applicationState.rawValue) window=\(view.window != nil) hidden=\(String(describing: view.window?.isHidden)) top=\(state.coordinator().windows.last === view) scheme=\(view.url?.scheme ?? "nil") request=\(origin.protocol):\(origin.host):\(origin.port) frame=\(frame.securityOrigin.protocol):\(frame.securityOrigin.host):\(frame.securityOrigin.port) events=\(state.events.suffix(2))")
        }
        return decision ?? .deny
    }
    func testDeviceDenialsStillDenyAndAllOtherStatesRequireSitePrompt() {
        XCTAssertEqual(CaptureConsentPolicy.decision([.authorized]), .prompt)
        XCTAssertEqual(CaptureConsentPolicy.decision([.notDetermined]), .prompt)
        XCTAssertEqual(CaptureConsentPolicy.decision([.authorized, .notDetermined]), .prompt)
        XCTAssertEqual(CaptureConsentPolicy.decision([.denied]), .deny)
        XCTAssertEqual(CaptureConsentPolicy.decision([.restricted]), .deny)
        XCTAssertEqual(CaptureConsentPolicy.decision([.authorized, .denied]), .deny)
        XCTAssertEqual(CaptureConsentPolicy.decision([.restricted, .authorized]), .deny)
    }
    func testOpenAgeHTTPSHasNoSpecialVetoBeforeOrAfterRecovery() {
        let state = WebState(); defer { state.dispose() }
        for _ in 0..<3 {
            state.returnToPortal()
            for path in ["face-scan", "agekey", "callback?state=synthetic", ""] {
                XCTAssertTrue(WebNavigationPolicy.allows(URL(string: "https://ui.prod.ageapi.org/" + path)))
            }
            state.resumePage()
        }
        XCTAssertFalse(WebNavigationPolicy.allows(URL(string: "http://insecure.invalid")))
        XCTAssertFalse(WebNavigationPolicy.allows(URL(string: "javascript:alert(1)")))
        XCTAssertFalse(WebNavigationPolicy.allows(URL(string: "phplus://callback")))
        XCTAssertTrue(WebNavigationPolicy.allows(URL(string: "about:blank")))
        XCTAssertTrue(WebNavigationPolicy.allows(URL(string: "blob:https://portal.invalid/fixture")))
        XCTAssertTrue(WebNavigationPolicy.allows(URL(string: "data:text/html,fixture")))
    }
    func testCaptureDelegateWithRealMainAndCrossOriginFrameContexts() async throws {
        let (state, window) = try await visibleState()
        defer { state.dispose(); window.isHidden = true }
        let view = try XCTUnwrap(state.view)
        let collector = FrameCollector()
        view.configuration.userContentController.add(collector, name: "fixtureCapture")
        defer { view.configuration.userContentController.removeScriptMessageHandler(forName: "fixtureCapture") }
        view.load(URLRequest(url: URL(string: "https://localhost:8843/capture-context")!))
        try await ready(view, path: "/capture-context")
        try await waitFor { collector.frames.count >= 2 }
        let main = try XCTUnwrap(collector.frames.first { $0.isMainFrame })
        let child = try XCTUnwrap(collector.frames.first { !$0.isMainFrame })
        XCTAssertEqual(main.securityOrigin.host, "localhost")
        XCTAssertEqual(child.securityOrigin.host, "127.0.0.1")
        let expected = CaptureConsentPolicy.decision([AVCaptureDevice.authorizationStatus(for: .video)])
        XCTAssertEqual(permission(state, view: view, origin: main.securityOrigin, frame: main), expected)
        XCTAssertEqual(permission(state, view: view, origin: child.securityOrigin, frame: child), expected)
        XCTAssertEqual(permission(state, view: view, origin: main.securityOrigin, frame: child), .deny)
        state.returnToPortal()
        XCTAssertEqual(permission(state, view: view, origin: main.securityOrigin, frame: main), .deny)
        state.resumePage()
        XCTAssertEqual(permission(state, view: view, origin: child.securityOrigin, frame: child), expected)
        state.setAuthorization(false)
        XCTAssertEqual(permission(state, view: view, origin: main.securityOrigin, frame: main), .deny)
        state.setAuthorization(true)
        XCTAssertEqual(permission(state, view: view, origin: main.securityOrigin, frame: main), expected)
        let host = try XCTUnwrap(state.retainedHost)
        let parent = try XCTUnwrap(host.superview)
        host.removeFromSuperview()
        XCTAssertEqual(permission(state, view: view, origin: main.securityOrigin, frame: main), .deny)
        parent.addSubview(host)
        await Task.yield()
        XCTAssertFalse(state.mediaSuspended, "Immediate reattachment must not leave capture stopped")
        XCTAssertEqual(permission(state, view: view, origin: main.securityOrigin, frame: main), expected)
        let both = CaptureConsentPolicy.decision([AVCaptureDevice.authorizationStatus(for: .video), AVCaptureDevice.authorizationStatus(for: .audio)])
        XCTAssertEqual(permission(state, view: view, origin: child.securityOrigin, frame: child, type: .cameraAndMicrophone), both)
        XCTAssertEqual(state.creationCount, 1)
        // Calls the production delegate with real HTTPS frame contexts. It does
        // not grant OS consent, obtain a camera stream or perform a facial scan.
    }
    func testPreviewPlaybackSurvivesInactiveEventsAndCanRestartAfterBackground() async throws {
        let (state, window) = try await visibleState()
        defer { state.dispose(); window.isHidden = true }
        let view = try XCTUnwrap(state.view)
        view.load(URLRequest(url: URL(string: "https://localhost:8843/preview")!))
        try await ready(view, path: "/preview")
        let play = "const v=document.getElementById('preview'); v.muted=true; await Promise.race([v.play(),new Promise((_,reject)=>setTimeout(()=>reject(new Error('synthetic preview play timeout')),10000))]); return !v.paused && v.readyState>=2;"
        let initial = try await view.callAsyncJavaScript(play, arguments: [:], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(initial, true)
        _ = try await view.evaluateJavaScript("Object.defineProperty(document,'visibilityState',{configurable:true,get:()=> 'hidden'}); document.dispatchEvent(new Event('visibilitychange')); window.dispatchEvent(new Event('pagehide')); delete document.visibilityState")
        let scene = try XCTUnwrap(window.windowScene)
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
        XCTAssertFalse(state.mediaSuspended, "A system permission prompt must not stop capture")
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        let stillPlaying = try await view.evaluateJavaScript("!document.getElementById('preview').paused") as? Bool
        XCTAssertEqual(stillPlaying, true)
        state.suspendAndCheckpoint() // Synthetic real-background transition.
        XCTAssertTrue(state.mediaSuspended)
        state.setAuthorization(true)
        XCTAssertFalse(state.mediaSuspended)
        let restarted = try await view.callAsyncJavaScript(play, arguments: [:], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(restarted, true, "No persistent WebKit playback suspension may remain")
        XCTAssertTrue(state.view === view)
        XCTAssertEqual(view.url?.path, "/preview")
        XCTAssertEqual(state.initialLoadCount, 1)
        // Ordinary synthetic video, not camera/video identity verification.
    }
    func testHTTPSRedirectsPOSTAndPopupStillWorkAfterRepeatedRecovery() async throws {
        let (state, window) = try await visibleState()
        defer { state.dispose(); window.isHidden = true }
        let view = try XCTUnwrap(state.view)
        try await ready(view, path: "/dashboard")
        _ = try await view.evaluateJavaScript("document.cookie='scan_fixture=ok; Path=/; Secure'; localStorage.setItem('scan_fixture','ok')")
        for _ in 0..<3 {
            state.returnToPortal()
            XCTAssertTrue(state.recoveryVisible)
            state.resumePage()
            view.load(URLRequest(url: URL(string: "https://localhost:8843/verify-start")!))
            try await ready(view, path: "/scan-complete")
            XCTAssertTrue(state.view === view)
            XCTAssertNil(state.error)
        }
        var post = URLRequest(url: URL(string: "https://127.0.0.1:8843/verify-submit")!)
        post.httpMethod = "POST"; post.httpBody = Data("synthetic=only".utf8)
        view.load(post)
        try await ready(view, path: "/scan-complete")
        state.returnToPortal(); state.reloadPage()
        XCTAssertFalse(state.recoveryVisible, "Explicit Reload must leave the native recovery panel")
        try await ready(view, path: "/scan-complete")
        // Test-only preference permits scripted popup creation without a UI tap.
        view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let opened = try await view.evaluateJavaScript("window.open('https://127.0.0.1:8843/verify-start','scanFixture') !== null") as? Bool
        XCTAssertEqual(opened, true)
        try await waitFor { state.hasPopup }
        let popup = try XCTUnwrap(state.view)
        XCTAssertFalse(popup === view)
        try await ready(popup, path: "/scan-complete")
        state.returnToPortal()
        XCTAssertFalse(state.hasPopup); XCTAssertTrue(state.view === view)
        XCTAssertFalse(state.recoveryVisible)
        let cookie = try await view.evaluateJavaScript("document.cookie.includes('scan_fixture=ok') && localStorage.getItem('scan_fixture')==='ok'") as? Bool
        XCTAssertEqual(cookie, true)
        XCTAssertEqual(state.creationCount, 1)
        XCTAssertEqual(state.initialLoadCount, 1)
    }
    func testNetworkFailureOffersRecoveryWithoutAutomaticHomepageReload() async throws {
        let (state, window) = try await visibleState()
        defer { state.dispose(); window.isHidden = true }
        let view = try XCTUnwrap(state.view)
        try await ready(view, path: "/dashboard")
        view.load(URLRequest(url: URL(string: "https://localhost:8843/network-error")!))
        try await waitFor { state.error != nil }
        state.returnToPortal()
        XCTAssertTrue(state.recoveryVisible)
        let before = state.initialLoadCount
        state.resumePage()
        XCTAssertFalse(state.recoveryVisible)
        XCTAssertEqual(state.initialLoadCount, before)
        XCTAssertTrue(state.view === view)
        XCTAssertTrue(WebNavigationPolicy.allows(URL(string: "https://ui.prod.ageapi.org/face-scan")))
    }
}
