import Foundation

/// Read/write WireGuard .conf under ~/.config/wireguard (secrets stay local).
enum WireGuardProfileStore {
    enum Profile: String, CaseIterable {
        case macbook
        case home

        var fileName: String { rawValue + ".conf" }

        var displayName: String {
            switch self {
            case .macbook: return "Egress (macbook)"
            case .home: return "Home (split)"
            }
        }
    }

    static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.config/wireguard", isDirectory: true)
    }

    static func url(for profile: Profile) -> URL {
        directory.appendingPathComponent(profile.fileName)
    }

    static func exists(_ profile: Profile) -> Bool {
        FileManager.default.fileExists(atPath: url(for: profile).path)
    }

    static func loadText(_ profile: Profile) throws -> String {
        let path = url(for: profile).path
        guard FileManager.default.fileExists(atPath: path) else {
            return Self.template(for: profile)
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    static func saveText(_ profile: Profile, text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("[Interface]"), trimmed.contains("[Peer]") else {
            throw StoreError.invalid("Нужны секции [Interface] и [Peer]")
        }
        guard trimmed.contains("PrivateKey"), trimmed.contains("Address"),
              trimmed.contains("PublicKey"), trimmed.contains("Endpoint") else {
            throw StoreError.invalid("Нужны PrivateKey, Address, PublicKey, Endpoint")
        }
        let dest = url(for: profile)
        try trimmed.write(to: dest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
    }

    static func importFile(from source: URL, to profile: Profile) throws {
        let text = try String(contentsOf: source, encoding: .utf8)
        try saveText(profile, text: text)
    }

    static func template(for profile: Profile) -> String {
        switch profile {
        case .macbook:
            return """
            [Interface]
            PrivateKey =
            Address = 10.8.0.2/32
            MTU = 1280

            [Peer]
            PublicKey =
            Endpoint = 203.0.113.10:51820
            AllowedIPs = 0.0.0.0/0
            PersistentKeepalive = 25
            """
        case .home:
            return """
            [Interface]
            PrivateKey =
            Address = 10.13.13.2/32
            MTU = 1280

            [Peer]
            PublicKey =
            Endpoint = 203.0.113.20:51820
            AllowedIPs = 10.13.13.0/24
            PersistentKeepalive = 25
            """
        }
    }

    enum StoreError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self {
            case .invalid(let s): return s
            }
        }
    }
}
