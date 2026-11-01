import Foundation
import WebKit
import AVFoundation

// Equivalent to 1.2's scheme allow-list. No host, provider, method, query,
// recovery state or AgeKey classification changes a legitimate HTTPS decision.
enum WebNavigationPolicy {
    static func allows(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return ["https", "about", "blob", "data"].contains(scheme)
    }
}

enum CaptureConsentPolicy {
    // 1.2 semantics: never auto-grant. iOS denial/restriction stays denied;
    // authorized and undetermined devices still require WebKit's per-site prompt.
    static func decision(_ statuses: [AVAuthorizationStatus]) -> WKPermissionDecision {
        statuses.contains(.denied) || statuses.contains(.restricted) ? .deny : .prompt
    }
}
