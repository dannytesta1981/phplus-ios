import Foundation

@main struct CapturePolicyChecks {
    static func main() {
        func check(_ scheme: String = "https", _ host: String = "identity.invalid", _ port: Int = 443, _ frameScheme: String = "https", _ frameHost: String = "identity.invalid", _ framePort: Int = 443, _ pageScheme: String? = "https", _ active: Bool = true) -> Bool {
            CapturePolicy.allows(requestScheme: scheme, requestHost: host, requestPort: port, frameScheme: frameScheme, frameHost: frameHost, framePort: framePort, pageScheme: pageScheme, active: active)
        }
        precondition(check(), "HTTPS matching requester/frame should reach WebKit prompt")
        precondition(!check("http"), "HTTP rejected")
        precondition(!check("https", ""), "Opaque origin rejected")
        precondition(!check("https", "attacker.invalid"), "Mismatched frame rejected")
        precondition(!check("https", "identity.invalid", 444), "Mismatched port rejected")
        precondition(!check("https", "identity.invalid", 443, "http"), "Insecure frame rejected")
        precondition(!check("https", "identity.invalid", 443, "https", "identity.invalid", 443, "http"), "Insecure page rejected")
        precondition(!check("https", "identity.invalid", 443, "https", "identity.invalid", 443, nil), "Missing page rejected")
        precondition(!check("https", "identity.invalid", 443, "https", "identity.invalid", 443, "https", false), "Inactive app rejected")
        print("Capture origin policy: 9 checks passed. These checks do not simulate iPhone capture consent.")
    }
}
