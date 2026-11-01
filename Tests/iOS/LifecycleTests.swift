import XCTest
import WebKit
@testable import phplus

@MainActor final class FakeAuthenticator: DeviceAuthenticating {
    var calls: [(Bool, String?) -> Void] = []
    var cancellations = 0
    func evaluate(reason: String, completion: @escaping (Bool, String?) -> Void) { calls.append(completion) }
    func cancel() { cancellations += 1 }
}
@MainActor final class LifecycleTests: XCTestCase {
    let fixture = URL(string: "https://localhost:8843/dashboard")!
    func isolatedDefaults() -> UserDefaults {
        let name = "phplus.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
    func testAutomaticUnlockAndNoDuplicateInactiveCallbacks() {
        let fake = FakeAuthenticator()
        let security = SecurityController(defaults: isolatedDefaults(), authenticator: fake)
        XCTAssertTrue(security.enabled); XCTAssertFalse(security.unlocked)
        security.becameActive(); security.becameActive()
        XCTAssertEqual(fake.calls.count, 1)
        fake.calls[0](true, nil)
        security.becameActive(); XCTAssertEqual(fake.calls.count, 1)
        XCTAssertTrue(security.unlocked)
        security.backgrounded(); XCTAssertFalse(security.unlocked)
        security.becameActive(); security.becameActive()
        XCTAssertEqual(fake.calls.count, 2)
        fake.calls[1](false, "Cancelled")
        security.becameActive(); XCTAssertEqual(fake.calls.count, 2)
        XCTAssertFalse(security.unlocked); XCTAssertNotNil(security.errorMessage)
        security.unlock(); XCTAssertEqual(fake.calls.count, 3)
    }
    func testDisableEnableRequireSuccessfulAuthenticationAndPersist() {
        let defaults = isolatedDefaults(); let fake = FakeAuthenticator()
        let security = SecurityController(defaults: defaults, authenticator: fake)
        security.setEnabled(false); XCTAssertTrue(security.enabled)
        fake.calls[0](false, "Denied"); XCTAssertTrue(security.enabled)
        security.setEnabled(false); fake.calls[1](true, nil)
        XCTAssertFalse(security.enabled); XCTAssertTrue(security.unlocked)
        security.backgrounded(); security.becameActive(); XCTAssertEqual(fake.calls.count, 2)
        let relaunched = SecurityController(defaults: defaults, authenticator: FakeAuthenticator())
        XCTAssertFalse(relaunched.enabled); XCTAssertTrue(relaunched.unlocked)
        security.setEnabled(true); XCTAssertFalse(security.enabled)
        fake.calls[2](true, nil); XCTAssertTrue(security.enabled)
        security.backgrounded(); security.becameActive(); XCTAssertEqual(fake.calls.count, 4)
    }
    func testStaleAuthenticationCannotUnlockOrChangeSettingsAfterBackground() {
        let fake = FakeAuthenticator(); let security = SecurityController(defaults: isolatedDefaults(), authenticator: fake)
        security.becameActive(); security.backgrounded(); security.becameActive()
        fake.calls[0](true, nil); XCTAssertFalse(security.unlocked)
        fake.calls[1](true, nil); XCTAssertTrue(security.unlocked)
        security.setEnabled(false); security.backgrounded()
        fake.calls[2](true, nil); XCTAssertTrue(security.enabled); XCTAssertFalse(security.unlocked)
    }
    func testRestorationRejectsSensitiveUnknownForeignAndNonGETRoutes() {
        let entry = URL(string: "https://portal.invalid/")!
        for suffix in ["dashboard?token=private", "dashboard#private", "checkout", "pay", "payment/confirm", "transfer", "oauth/callback", "logout", "users/12345", "unknown", "%64ashboard"] {
            XCTAssertNil(RestorationPolicy.restorable(URL(string: suffix, relativeTo: entry)?.absoluteURL, entry: entry), suffix)
        }
        XCTAssertNotNil(RestorationPolicy.restorable(URL(string: "dashboard", relativeTo: entry)?.absoluteURL, entry: entry))
        XCTAssertNil(RestorationPolicy.restorable(entry, entry: entry, method: "POST"))
        XCTAssertNil(RestorationPolicy.restorable(URL(string: "https://elsewhere.invalid/dashboard"), entry: entry))
        XCTAssertNil(RestorationPolicy.restorable(URL(string: "https://portal.invalid:444/dashboard"), entry: entry))
        XCTAssertNil(RestorationPolicy.restorable(URL(string: "https://user:pass@portal.invalid/dashboard"), entry: entry))
    }
    func testLegacyPortalsMigrateAndColdStartRestoresOnlyAllowedPage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = ProtectedFiles(directory: directory); let defaults = isolatedDefaults()
        let configured = [Portal(id: 1, title: "Fixture", url: fixture.absoluteString)]
        defaults.set(try JSONEncoder().encode(configured), forKey: "privatehub.portals.v1")
        let store = PortalStore(files: files, defaults: defaults)
        XCTAssertEqual(store.portals, configured)
        XCTAssertNil(defaults.data(forKey: "privatehub.portals.v1"))
        store.activate(1)
        let state = store.session(for: configured[0])
        state.onCheckpoint?(fixture, nil)
        let reopened = PortalStore(files: files, defaults: defaults)
        XCTAssertEqual(reopened.restoredPortal?.id, 1)
        XCTAssertEqual(reopened.session(for: configured[0]).restoredURL, fixture)
        var malicious = ResumeState(); malicious.activePortal = 1; malicious.pages[1] = fixture.absoluteString + "?token=secret"
        try files.write(malicious, name: "resume.json")
        XCTAssertNil(PortalStore(files: files, defaults: defaults).session(for: configured[0]).restoredURL)
        XCTAssertNil(defaults.object(forKey: "phplus.resume"))
        try? FileManager.default.removeItem(at: directory)
    }
    func testSameWebViewAndSingleLoadAcrossLocksAndPortalSwitches() {
        let state = WebState(); state.entry = fixture
        let host = state.prepareHost(url: fixture); let webView = state.view
        XCTAssertEqual(state.initialLoadCount, 0, "No navigation behind the initial auth screen")
        state.setAuthorization(true)
        XCTAssertEqual(state.initialLoadCount, 1)
        let other = WebState(); _ = other.prepareHost(url: fixture)
        state.setAuthorization(false); state.suspendAndCheckpoint(); state.setAuthorization(true)
        XCTAssertTrue(state.prepareHost(url: fixture) === host)
        XCTAssertTrue(state.view === webView)
        XCTAssertEqual(state.creationCount, 1); XCTAssertEqual(state.initialLoadCount, 1)
        XCTAssertTrue(state.view?.configuration.websiteDataStore.isPersistent == true)
        state.dispose(); other.dispose()
    }
    func ready(_ view: WKWebView, path: String = "/dashboard") async throws {
        for _ in 0..<200 {
            if let value = try? await view.evaluateJavaScript("document.readyState === 'complete' && location.pathname === '\(path)' && document.getElementById('fixtureReady') !== null"), value as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("HTTPS fixture did not become ready")
        throw NSError(domain: "FixtureTimeout", code: 1)
    }
    func makeFixtureState() -> WebState {
        let state = WebState(); state.entry = fixture; state.setAuthorization(true)
        _ = state.prepareHost(url: fixture)
        return state
    }
    func testRealWebViewKeepsHistoryScrollAndDOMWhileLocked() async throws {
        let state = makeFixtureState(); defer { state.dispose() }
        let view = try XCTUnwrap(state.view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController(); window.rootViewController = root
        let host = try XCTUnwrap(state.retainedHost); host.frame = root.view.bounds; root.view.addSubview(host)
        window.makeKeyAndVisible(); defer { window.isHidden = true }
        try await ready(view)
        _ = try await view.evaluateJavaScript("history.pushState({}, '', '/overview'); window.fixtureVolatile = 'retained'; window.scrollTo(0, 700)")
        try await Task.sleep(nanoseconds: 200_000_000)
        let before = try await view.evaluateJavaScript("window.scrollY") as? Double
        state.setAuthorization(false); state.suspendAndCheckpoint(); state.setAuthorization(true)
        XCTAssertTrue(state.view === view); XCTAssertEqual(state.initialLoadCount, 1)
        let volatile = try await view.evaluateJavaScript("window.fixtureVolatile") as? String
        XCTAssertEqual(volatile, "retained")
        XCTAssertEqual(view.url?.path, "/overview")
        XCTAssertTrue(view.canGoBack)
        let after = try await view.evaluateJavaScript("window.scrollY") as? Double
        XCTAssertEqual(before, after)
    }
    func testRecoveryReturnsToRetainedPortalAndClosesProviderPopup() async throws {
        let state = makeFixtureState(); defer { state.dispose() }
        let view = try XCTUnwrap(state.view); try await ready(view)
        let coordinator = state.coordinator()
        _ = try await view.evaluateJavaScript("window.fixtureVolatile = 'no-reload'; document.cookie = 'recovery=ok; Path=/; Secure'")
        state.returnToPortal() // Already on the portal must not reload it.
        let marker = try await view.evaluateJavaScript("window.fixtureVolatile") as? String
        XCTAssertEqual(marker, "no-reload")
        coordinator.embeddedProvider = true
        state.returnToPortal()
        XCTAssertTrue(state.recoveryVisible, "An iframe with no history must offer native recovery")
        XCTAssertTrue(state.view === view)
        let retained = try await view.evaluateJavaScript("window.fixtureVolatile") as? String
        XCTAssertEqual(retained, "no-reload")
        coordinator.embeddedProvider = false; state.recoveryVisible = false
        state.cancellingVerification = false
        view.load(URLRequest(url: URL(string: "https://localhost:8843/provider-error")!))
        try await ready(view, path: "/provider-error")
        XCTAssertNotNil(coordinator.portalItem)
        state.returnToPortal()
        try await ready(view)
        XCTAssertFalse(state.recoveryVisible)
        XCTAssertTrue(state.view === view)
        let cookie = try await view.evaluateJavaScript("document.cookie.includes('recovery=ok')") as? Bool
        XCTAssertEqual(cookie, true)
        let popup = WKWebView(frame: .zero, configuration: view.configuration)
        coordinator.attach(popup, to: try XCTUnwrap(state.retainedHost))
        XCTAssertTrue(state.hasPopup)
        state.returnToPortal()
        XCTAssertFalse(state.hasPopup); XCTAssertTrue(state.view === view)
        XCTAssertEqual(coordinator.windows.count, 1)
        state.navigateBack() // Native action remains callable after popup close/cancel.
        XCTAssertTrue(state.view === view)
        state.recoveryVisible = true
        coordinator.suspendCapture()
        state.setAuthorization(false); state.setAuthorization(true)
        XCTAssertTrue(state.mediaSuspended, "Recovery overlay must not allow media to resume on unlock")
    }
    func testWriteWebStorageAndObserveCameraAPIOnHTTPS() async throws {
        let state = makeFixtureState(); defer { state.dispose() }
        let view = try XCTUnwrap(state.view); try await ready(view)
        let secure = try await view.evaluateJavaScript("window.isSecureContext") as? Bool
        let cameraAPI = try await view.evaluateJavaScript("typeof navigator.mediaDevices?.getUserMedia") as? String
        XCTAssertEqual(secure, true); XCTAssertEqual(cameraAPI, "function")
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription"))
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription"))
        XCTAssertTrue(state.coordinator().responds(to: NSSelectorFromString("webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:")))
        let result = try await view.callAsyncJavaScript("""
        document.cookie = 'phplus_fixture=ok; Max-Age=3600; Path=/; Secure; SameSite=Lax';
        localStorage.setItem('phplus_fixture', 'ok');
        await new Promise((resolve,reject) => { const request = indexedDB.open('phplus_fixture', 1); request.onupgradeneeded = () => request.result.createObjectStore('markers'); request.onerror = () => reject(new Error('fixture db')); request.onsuccess = () => { const db = request.result; const tx = db.transaction('markers','readwrite'); tx.objectStore('markers').put('ok','persisted'); tx.oncomplete = () => { db.close(); resolve(); }; tx.onerror = () => reject(new Error('fixture tx')); }; });
        return localStorage.getItem('phplus_fixture');
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(result as? String, "ok")
        let cookies = await view.configuration.websiteDataStore.httpCookieStore.phplusCookieSnapshot()
        XCTAssertTrue(cookies.contains { $0.name == "phplus_fixture" && !$0.isSessionOnly })
        UserDefaults.standard.set(true, forKey: "phplus.tests.fixtureWasWritten")
        let observed = expectation(description: "Cookie and web-data checkpoint")
        var done = false
        state.onCheckpoint = { _, evidence in if evidence?.localKeys != nil && !done { done = true; observed.fulfill() } }
        state.checkpoint()
        await fulfillment(of: [observed], timeout: 15)
    }
    func testReadWebStorageAfterRelaunch() async throws {
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "phplus.tests.fixtureWasWritten"), "This test must run in the second xcodebuild test invocation")
        let state = makeFixtureState(); defer { state.dispose() }
        let view = try XCTUnwrap(state.view); try await ready(view)
        let local = try await view.evaluateJavaScript("localStorage.getItem('phplus_fixture')") as? String
        let cookie = try await view.evaluateJavaScript("document.cookie.includes('phplus_fixture=ok')") as? Bool
        XCTAssertEqual(local, "ok"); XCTAssertEqual(cookie, true)
        let indexed = try await view.callAsyncJavaScript("""
        return await new Promise((resolve,reject) => { const request=indexedDB.open('phplus_fixture',1); request.onerror=()=>reject(new Error('fixture')); request.onsuccess=()=>{const db=request.result; if(!db.objectStoreNames.contains('markers')) { db.close(); resolve(null); return; } const tx=db.transaction('markers','readonly');const get=tx.objectStore('markers').get('persisted'); get.onsuccess=()=>resolve(get.result); get.onerror=()=>reject(new Error('fixture read')); tx.oncomplete=()=>db.close(); }; });
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(indexed as? String, "ok")
    }
}
