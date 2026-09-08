import Foundation

/// One WireGuard channel (sing-box endpoint tag = id).
struct VPNChannel: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var file: String
    var isDefault: Bool
    var ping: String

    var fileName: String { file.hasSuffix(".conf") ? file : file + ".conf" }
}

/// Manual route row — Clash/sing-box style (match → via), not WG AllowedIPs.
struct VPNRoute: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case cidr
        case ruleSet = "rule_set"
    }

    var id: String
    var kind: Kind
    /// CIDR list or single rule_set tag
    var match: [String]
    var via: String
    var note: String

    var matchDisplay: String {
        match.joined(separator: ", ")
    }
}

/// Routing/NAS + named channels from ~/.config/myvpn/settings.json (no WG secrets).
/// Uses: lib/settings.py, lib/channels.py
struct AppSettings: Equatable, Sendable {
    var channels: [VPNChannel] = []
    var routes: [VPNRoute] = []
    var dnsVia: String = "home"
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
            return migrateLegacy(AppSettings()).ensuringDefaults()
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
        if let v = obj["dns_via"] as? String { s.dnsVia = v }
        if let arr = obj["channels"] as? [[String: Any]] {
            s.channels = arr.compactMap(Self.parseChannel)
        }
        if let arr = obj["routes"] as? [[String: Any]] {
            s.routes = arr.compactMap(Self.parseRoute)
        }
        return migrateLegacy(s).ensuringDefaults()
    }

    func save() throws {
        let url = Self.fileURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var existing: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existing = obj
        }
        var s = ensuringDefaults()
        // Sync lan_cidrs from direct CIDR routes
        s.lanCidrs = s.routes.filter { $0.kind == .cidr && $0.via == "direct" }.flatMap(\.match)
        if let def = s.channels.first(where: { $0.isDefault }) {
            s.macbookPing = def.ping
        }
        if let home = s.channels.first(where: { $0.id == "home" }) {
            s.homePing = home.ping
        }
        existing["lan_cidrs"] = s.lanCidrs
        existing["nas_host"] = s.nasHost
        existing["nas_share"] = s.nasShare
        existing["nas_mount"] = s.nasMount
        existing["nas_user"] = s.nasUser
        existing["dns_home_server"] = s.dnsHomeServer
        existing["dns_suffixes"] = s.dnsSuffixes
        existing["home_ping"] = s.homePing
        existing["macbook_ping"] = s.macbookPing
        existing["dns_via"] = s.dnsVia
        existing["channels"] = s.channels.map { ch -> [String: Any] in
            [
                "id": ch.id,
                "name": ch.name,
                "file": ch.fileName,
                "is_default": ch.isDefault,
                "ping": ch.ping,
            ]
        }
        existing["routes"] = s.routes.map { r -> [String: Any] in
            var row: [String: Any] = [
                "id": r.id,
                "type": r.kind.rawValue,
                "via": r.via,
                "note": r.note,
            ]
            if r.kind == .ruleSet {
                row["match"] = r.match.first ?? ""
            } else {
                row["match"] = r.match
            }
            return row
        }
        let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func ensuringDefaults() -> AppSettings {
        var s = self
        if s.channels.isEmpty {
            s.channels = [
                VPNChannel(id: "macbook", name: "Egress", file: "macbook.conf", isDefault: true, ping: s.macbookPing),
                VPNChannel(id: "home", name: "Home", file: "home.conf", isDefault: false, ping: s.homePing),
            ]
        }
        if !s.channels.contains(where: \.isDefault), let idx = s.channels.indices.first {
            s.channels[idx].isDefault = true
        }
        // Exactly one default
        var seen = false
        for i in s.channels.indices {
            if s.channels[i].isDefault {
                if seen { s.channels[i].isDefault = false }
                seen = true
            }
        }
        // routes[] empty → leave empty; lib/channels.py migrate on render seeds from lan + home AllowedIPs
        if s.dnsVia.isEmpty {
            s.dnsVia = s.channels.first(where: { $0.id == "home" })?.id
                ?? s.channels.first(where: { !$0.isDefault })?.id
                ?? s.channels.first?.id
                ?? "home"
        }
        return s
    }

    private static func migrateLegacy(_ s: AppSettings) -> AppSettings {
        // Channel/route migration for empty topology is in ensuringDefaults + render channels.py
        s
    }

    private static func parseChannel(_ obj: [String: Any]) -> VPNChannel? {
        guard let id = obj["id"] as? String, !id.isEmpty else { return nil }
        let name = (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        let file = (obj["file"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(id).conf"
        let isDefault = obj["is_default"] as? Bool ?? false
        let ping = obj["ping"] as? String ?? ""
        return VPNChannel(id: id, name: name, file: file, isDefault: isDefault, ping: ping)
    }

    private static func parseRoute(_ obj: [String: Any]) -> VPNRoute? {
        let id = (obj["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let typeRaw = obj["type"] as? String ?? "cidr"
        let kind = VPNRoute.Kind(rawValue: typeRaw) ?? .cidr
        let via = (obj["via"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "direct"
        let note = obj["note"] as? String ?? ""
        let match: [String]
        if let arr = obj["match"] as? [String] {
            match = arr.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } else if let s = obj["match"] as? String {
            match = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } else {
            match = []
        }
        guard !match.isEmpty else { return nil }
        return VPNRoute(id: id, kind: kind, match: match, via: via, note: note)
    }

    static func slugify(_ name: String, existing: [String]) -> String {
        let base = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        var slug = base
        if slug.isEmpty || !(slug.first?.isLetter ?? false) {
            slug = "ch-" + (slug.isEmpty ? "new" : slug)
        }
        slug = String(slug.prefix(32))
        if !existing.contains(slug) { return slug }
        var i = 2
        while existing.contains("\(String(slug.prefix(28)))-\(i)") { i += 1 }
        return "\(String(slug.prefix(28)))-\(i)"
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
