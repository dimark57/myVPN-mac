import Foundation

/// Routing/NAS prefs from ~/.config/myvpn/settings.json (no WG secrets).
/// Uses: lib/settings.py schema
struct AppSettings: Equatable, Sendable {
    var lanCidrs: [String] = []
    var nasHost: String = ""
    var nasShare: String = "Nas"
    var nasMount: String = "/Volumes/Nas"
    var nasUser: String = "NAS"
    var dnsHomeServer: String = ""
    var dnsSuffixes: [String] = []
    var homePing: String = ""
    var macbookPing: String = ""

    static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.config/myvpn/settings.json")
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AppSettings()
        }
        var s = AppSettings()
        if let v = obj["lan_cidrs"] as? [String] { s.lanCidrs = v }
        if let v = obj["nas_host"] as? String { s.nasHost = v }
        if let v = obj["nas_share"] as? String { s.nasShare = v }
        if let v = obj["nas_mount"] as? String { s.nasMount = v }
        if let v = obj["nas_user"] as? String { s.nasUser = v }
        if let v = obj["dns_home_server"] as? String { s.dnsHomeServer = v }
        if let v = obj["dns_suffixes"] as? [String] { s.dnsSuffixes = v }
        if let v = obj["home_ping"] as? String { s.homePing = v }
        if let v = obj["macbook_ping"] as? String { s.macbookPing = v }
        return s
    }

    func save() throws {
        let url = Self.fileURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let obj: [String: Any] = [
            "lan_cidrs": lanCidrs,
            "nas_host": nasHost,
            "nas_share": nasShare,
            "nas_mount": nasMount,
            "nas_user": nasUser,
            "dns_home_server": dnsHomeServer,
            "dns_suffixes": dnsSuffixes,
            "home_ping": homePing,
            "macbook_ping": macbookPing,
        ]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Peer probe targets written by render_config.py
struct ProbeHints: Equatable, Sendable {
    var homePing: String = ""
    var macbookPing: String = ""
    var nasHost: String = ""
    var nasMount: String = "/Volumes/Nas"

    static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.config/myvpn/probes.json")
    }

    static func load() -> ProbeHints {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ProbeHints()
        }
        var p = ProbeHints()
        if let v = obj["home_ping"] as? String { p.homePing = v }
        if let v = obj["macbook_ping"] as? String { p.macbookPing = v }
        if let v = obj["nas_host"] as? String { p.nasHost = v }
        if let v = obj["nas_mount"] as? String { p.nasMount = v }
        return p
    }
}
