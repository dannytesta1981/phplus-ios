import XCTest
import WebKit
import AuthenticationServices
@testable import phplus

@MainActor final class MockBrowserSession: BrowserAuthenticationSession {
    var prefersEphemeralWebBrowserSession = true
    weak var presentationContextProvider: ASWebAuthenticationPresentationContextProviding?
    var starts = 0
    var cancels = 0
    var startsSuccessfully = true
    func start() -> Bool { starts += 1; return startsSuccessfully }
    func cancel() { cancels += 1 }
}
@MainActor final class AgeKeyPrivacyTests: XCTestCase {
    func testSystemBrowserIsNonEphemeralAndUsesUnmodifiedPortalEntry() {
        let mock = MockBrowserSession()
        var received: URL?
        let controller = SystemBrowserController { url, _ in received = url; return mock }
        let entry = URL(string: "https://portal.invalid/dashboard")!
        controller.open(portal: entry, anchor: UIWindow())
        XCTAssertEqual(received, entry)
        XCTAssertFalse(mock.prefersEphemeralWebBrowserSession)
        XCTAssertTrue(controller.active)
        XCTAssertTrue(mock.presentationContextProvider === controller)
        controller.open(portal: entry, anchor: UIWindow())
        XCTAssertEqual(mock.starts, 1)
        controller.close(); XCTAssertEqual(mock.cancels, 1)
        XCTAssertFalse(controller.active)
        XCTAssertNil(SystemBrowserPolicy.entry(URL(string: "http://portal.invalid")))
        XCTAssertNil(SystemBrowserPolicy.entry(URL(string: "https://user:secret@portal.invalid")))
        XCTAssertTrue(SystemBrowserPolicy.isAgeProvider(URL(string: "https://ui.prod.ageapi.org/verify")))
        XCTAssertFalse(SystemBrowserPolicy.isAgeProvider(URL(string: "https://ui.prod.ageapi.org.attacker.invalid/verify")))
        XCTAssertFalse(SystemBrowserPolicy.isAgeProvider(URL(string: "http://ui.prod.ageapi.org/verify")))
    }
    func testBrowserClosesOnBackgroundAndNeverTreatsCallbackAsVerified() async {
        let mock = MockBrowserSession()
        var callback: ((URL?, Error?) -> Void)?
        let controller = SystemBrowserController { _, completion in callback = completion; return mock }
        controller.open(portal: URL(string: "https://portal.invalid"), anchor: UIWindow())
        controller.backgrounded()
        XCTAssertFalse(controller.active); XCTAssertEqual(mock.cancels, 1)
        let status = controller.status
        callback?(URL(string: "phplus://callback?token=SYNTHETIC_PRIVATE&result=PASS"), nil)
        await Task.yield()
        XCTAssertEqual(controller.status, status, "Stale callbacks cannot report verification or change a later session")
        XCTAssertFalse(controller.status?.contains("SYNTHETIC_PRIVATE") ?? true)
        let failure = MockBrowserSession(); failure.startsSuccessfully = false
        let failing = SystemBrowserController { _, _ in failure }
        failing.open(portal: URL(string: "https://portal.invalid"), anchor: UIWindow())
        XCTAssertFalse(failing.active); XCTAssertNotNil(failing.status)
    }
    func testNeutralCurtainCoversEntireApplicationScene() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let curtain = PrivacyCurtain()
        curtain.hide(in: scene)
        defer { curtain.reveal(in: scene) }
        let cover = try XCTUnwrap(curtain.curtains[ObjectIdentifier(scene)])
        XCTAssertFalse(cover.isHidden)
        XCTAssertEqual(cover.frame, scene.coordinateSpace.bounds)
        XCTAssertGreaterThan(cover.windowLevel, .normal)
        XCTAssertFalse(cover.isKeyWindow)
        XCTAssertEqual(cover.rootViewController?.view.backgroundColor?.cgColor.alpha, 1)
        let labels = cover.rootViewController?.view.subviews.compactMap { ($0 as? UILabel)?.text }
        XCTAssertEqual(labels, ["phplus"])
        curtain.reveal(in: scene)
        XCTAssertTrue(curtain.curtains.isEmpty)
        // Checks the UIKit covering window; not a capture of the real iOS app switcher.
    }
    func testMediaPrivacySuspendsAndRetainsTheExistingBrowser() {
        let state = WebState()
        let entry = URL(string: "https://portal.invalid/dashboard")!
        let host = state.prepareHost(url: entry)
        let view = state.view
        XCTAssertFalse(view!.configuration.allowsPictureInPictureMediaPlayback)
        XCTAssertFalse(view!.configuration.allowsAirPlayForMediaPlayback)
        MediaPrivacyHub.shared.suspendAll()
        XCTAssertTrue(state.mediaSuspended)
        XCTAssertTrue(state.view === view)
        XCTAssertTrue(state.prepareHost(url: entry) === host)
        XCTAssertEqual(state.creationCount, 1)
        XCTAssertEqual(state.initialLoadCount, 0)
        XCTAssertTrue(state.view!.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool ?? false)
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes"))
        state.dispose()
        // No real audio playback, camera, Dynamic Island or Live Activity was exercised.
    }
}
