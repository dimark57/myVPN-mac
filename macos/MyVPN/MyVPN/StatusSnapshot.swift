import Foundation

/// Parsed `myvpn status` lines (doc-3 / doc-4). No secrets.
struct StatusSnapshot: Equatable, Sendable {
    var tun: Bool = false
    var macbook: Bool = false
    var home: Bool = false
    var nas: Bool = false
    var ip: String = ""

    var isOn: Bool { tun }

    var menuTitle: String {
        if !isOn {
            return "myVPN: Off"
        }
        var parts = ["myVPN: On"]
        if !ip.isEmpty {
            parts.append("ip \(ip)")
        }
        var peers: [String] = []
        if macbook { peers.append("macbook") }
        if home { peers.append("home") }
        if nas { peers.append("nas") }
        if !peers.isEmpty {
            parts.append(peers.joined(separator: "+"))
        }
        return parts.joined(separator: " · ")
    }

    static func parse(stdout: String) -> StatusSnapshot {
        var s = StatusSnapshot()
        for raw in stdout.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq])
            let value = String(line[line.index(after: eq)...])
            switch key {
            case "tun": s.tun = value == "1"
            case "macbook": s.macbook = value == "1"
            case "home": s.home = value == "1"
            case "nas": s.nas = value == "1"
            case "ip": s.ip = value
            default: break
            }
        }
        return s
    }
}
