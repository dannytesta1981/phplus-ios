import XCTest
import WebKit
import AuthenticationServices
@testable import phplus

@MainActor final class AgeKeyPrivacyTests: XCTestCase {
    func testExternalOpeningUsesOnlyOriginalPortalAndNeverClaimsVerification() async {
        var received: URL?
        var completion: ((Bool) -> Void)?
        var opens = 0
        let controller = SystemBrowserController { url, done in received = url; completion = done; opens += 1 }
        let entry = URL(string: "https://portal.invalid/dashboard")!
        controller.open(portal: entry)
        controller.open(portal: entry)
        XCTAssertEqual(received, entry); XCTAssertEqual(opens, 1)
        controller.backgrounded() // External tabs are not cancelled on app background.
        completion?(true)
        await Task.yield(); await Task.yield()
        XCTAssertFalse(controller.active)
        XCTAssertTrue(controller.status?.contains("Non è un esito di verifica") ?? false)
        XCTAssertNil(SystemBrowserPolicy.entry(URL(string: "http://portal.invalid")))
        XCTAssertNil(SystemBrowserPolicy.entry(URL(string: "https://user:secret@portal.invalid")))
        XCTAssertTrue(SystemBrowserPolicy.isAgeProvider(URL(string: "https://ui.prod.ageapi.org/verify")))
        XCTAssertFalse(SystemBrowserPolicy.isAgeProvider(URL(string: "https://ui.prod.ageapi.org.attacker.invalid/verify")))
    }
    func testFailedExternalOpeningLeavesExplicitRecoveryStatus() async {
        let controller = SystemBrowserController { _, done in done(false) }
        controller.open(portal: URL(string: "https://portal.invalid"))
        await Task.yield(); await Task.yield()
        XCTAssertFalse(controller.active)
        XCTAssertTrue(controller.status?.contains("non aperto") ?? false)
    }
    func testCancelledVerificationStopsProviderLoopsButRetryIsExplicit() {
        let state = WebState(); defer { state.dispose() }
        let entry = URL(string: "https://portal.invalid/dashboard")!
        _ = state.prepareHost(url: entry)
        let original = state.view
        state.returnToPortal()
        XCTAssertTrue(state.recoveryVisible)
        XCTAssertTrue(state.cancellingVerification)
        XCTAssertFalse(state.coordinator().permitsRecoveryNavigation(URL(string: "https://ui.prod.ageapi.org/verify")))
        XCTAssertTrue(state.coordinator().permitsRecoveryNavigation(entry))
        state.setAuthorization(true); state.openEntry()
        XCTAssertFalse(state.cancellingVerification); XCTAssertFalse(state.recoveryVisible)
        XCTAssertTrue(state.coordinator().permitsRecoveryNavigation(URL(string: "https://ui.prod.ageapi.org/verify")))
        XCTAssertTrue(state.view === original)
        XCTAssertTrue(state.view!.configuration.websiteDataStore.isPersistent)
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
