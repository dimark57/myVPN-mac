import Darwin
import Foundation

/// Parsed `myvpn status` lines (doc-3 / doc-4). No secrets.
struct StatusSnapshot: Equatable, Sendable {
    var tun: Bool = false
    var macbook: Bool = false
    var home: Bool = false
    var nas: Bool = false
    var ip: String = ""

    init(tun: Bool = false, macbook: Bool = false, home: Bool = false, nas: Bool = false, ip: String = "") {
        self.tun = tun
        self.macbook = macbook
        self.home = home
        self.nas = nas
        self.ip = ip
    }

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
        if !peers.isEmpty {
            parts.append(peers.joined(separator: "+"))
        }
        return parts.joined(separator: " · ")
    }

    /// Compact status for menu row (right side).
    var menuBadge: String {
        if !isOn { return "Off" }
        var peers: [String] = []
        if home { peers.append("home") }
        if macbook { peers.append("mb") }
        if peers.isEmpty { return "On" }
        return "On · \(peers.joined(separator: "+"))"
    }

    /// SMB mount at /Volumes/Nas — separate from WG peers in the title.
    var nasLine: String {
        nas ? "NAS: смонтирован" : "NAS: не смонтирован"
    }

    var nasBadge: String {
        nas ? "смонтирован" : "нет"
    }

    /// Live probe without spawning `myvpn` (uses: pid file, probes.json, /sbin/ping, mount dir, curl).
    static func probe(includePublicIP: Bool) -> StatusSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pidFile = home + "/.config/myvpn/sing-box.pid"
        let hints = ProbeHints.load()
        let nasMount = hints.nasMount.isEmpty ? "/Volumes/Nas" : hints.nasMount
        let homePing = hints.homePing.isEmpty ? "10.13.13.1" : hints.homePing
        let macPing = hints.macbookPing.isEmpty ? "10.8.0.1" : hints.macbookPing
        var s = StatusSnapshot()
        s.tun = pidAlive(pidFile)
        s.nas = FileManager.default.fileExists(atPath: nasMount + "/Project")
            || FileManager.default.fileExists(atPath: nasMount + "/data")
            || (FileManager.default.fileExists(atPath: nasMount)
                && (try? FileManager.default.contentsOfDirectory(atPath: nasMount))?.isEmpty == false)

        let group = DispatchGroup()
        var homeOK = false
        var macOK = false
        var pub = ""
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            homeOK = ping(homePing)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            macOK = ping(macPing)
            group.leave()
        }
        if includePublicIP {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                pub = publicIP()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 2.5)
        s.home = homeOK
        s.macbook = macOK
        s.ip = pub
        return s
    }

    private static func pidAlive(_ path: String) -> Bool {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return false }
        // Helper starts sing-box as root → kill(0) returns EPERM while process is alive.
        // Match CLI myvpn_is_running: treat EPERM as present; only ESRCH = gone.
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func ping(_ host: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/ping")
        p.arguments = ["-c", "1", "-W", "400", host]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func publicIP() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["-4", "-sS", "--max-time", "2", "https://ifconfig.me"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return ""
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
