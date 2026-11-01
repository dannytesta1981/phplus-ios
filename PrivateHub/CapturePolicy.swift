import Foundation

enum CapturePolicy {
    static func allows(requestScheme: String, requestHost: String, requestPort: Int, frameScheme: String, frameHost: String, framePort: Int, pageScheme: String?, active: Bool) -> Bool {
        return active && pageScheme?.lowercased() == "https" && requestScheme.lowercased() == "https" && !requestHost.isEmpty && requestScheme.lowercased() == frameScheme.lowercased() && requestHost.lowercased() == frameHost.lowercased() && requestPort == framePort
    }
}
