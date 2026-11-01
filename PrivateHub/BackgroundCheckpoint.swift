import UIKit
import WebKit

@MainActor final class BackgroundCheckpoint {
    private var identifier = UIBackgroundTaskIdentifier.invalid
    func start() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Web storage inspection") { [weak self] in
            Task { @MainActor in self?.finish() }
        }
    }
    func finish() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
extension WKHTTPCookieStore {
    @MainActor func phplusCookieSnapshot() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in getAllCookies { continuation.resume(returning: $0) } }
    }
}
