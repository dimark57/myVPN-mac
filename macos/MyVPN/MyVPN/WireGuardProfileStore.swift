import Foundation

/// Read/write named WireGuard .conf under ~/.config/wireguard (secrets stay local).
/// One template for every channel — routing lives in settings.routes, not AllowedIPs.
enum WireGuardProfileStore {
    static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.config/wireguard", isDirectory: true)
    }

    static func url(fileName: String) -> URL {
        let name = fileName.hasSuffix(".conf") ? fileName : fileName + ".conf"
        return directory.appendingPathComponent(name)
    }

    static func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(fileName: fileName).path)
    }

    static func loadText(fileName: String) throws -> String {
        let path = url(fileName: fileName).path
        guard FileManager.default.fileExists(atPath: path) else {
            return template()
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    static func saveText(fileName: String, text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("[Interface]"), trimmed.contains("[Peer]") else {
            throw StoreError.invalid("Нужны секции [Interface] и [Peer]")
        }
        guard trimmed.contains("PrivateKey"), trimmed.contains("Address"),
              trimmed.contains("PublicKey"), trimmed.contains("Endpoint") else {
            throw StoreError.invalid("Нужны PrivateKey, Address, PublicKey, Endpoint")
        }
        let dest = url(fileName: fileName)
        try trimmed.write(to: dest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
    }

    static func delete(fileName: String) throws {
        let path = url(fileName: fileName).path
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    /// Single template — same for egress, home, or any extra channel.
    static func template(address: String = "10.0.0.2/32") -> String {
        """
        [Interface]
        PrivateKey =
        Address = \(address)
        MTU = 1280

        [Peer]
        PublicKey =
        Endpoint = 203.0.113.10:51820
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 25
        """
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
