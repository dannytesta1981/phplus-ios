import Foundation

// Deliberately narrow: an arbitrary GET path can still repeat an operation or
// contain a secret. Unknown routes, all queries/fragments and foreign origins
// fall back to the user-configured entry page, never a guessed cleaned URL.
enum RestorationPolicy {
    static let safeSegments: Set<String> = ["home", "dashboard", "overview", "index", "index.html", "index.php", "app", "web", "portal", "portale", "main", "welcome", "feed", "news", "notizie", "it", "en", "de", "fr", "es"]
    static func restorable(_ url: URL?, entry: URL, method: String = "GET") -> URL? {
        guard method.uppercased() == "GET", let url = url,
              let candidate = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let base = URLComponents(url: entry, resolvingAgainstBaseURL: false),
              candidate.scheme?.lowercased() == "https", base.scheme?.lowercased() == "https",
              candidate.host?.lowercased() == base.host?.lowercased(),
              (candidate.port ?? 443) == (base.port ?? 443), candidate.user == nil, candidate.password == nil,
              candidate.query == nil, candidate.fragment == nil,
              !candidate.percentEncodedPath.contains("%"),
              candidate.path.split(separator: "/").allSatisfy({ safeSegments.contains(String($0).lowercased()) }) else { return nil }
        return url
    }
}
struct ResumeRecord: Codable {
    let portalID: Int
    let url: String?
}
struct StorageEvidence: Codable {
    let origin: String
    let cookies: Int
    let persistentCookies: Int
    let localKeys: Int?
    let databases: Int?
}
struct ResumeState: Codable {
    var activePortal: Int?
    var pages: [Int: String] = [:]
    var evidence: [Int: StorageEvidence] = [:]
}
struct ProtectedFiles {
    let directory: URL
    static var application: ProtectedFiles {
        ProtectedFiles(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("phplus", isDirectory: true))
    }
    func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    func write<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
