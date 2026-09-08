import Foundation

/// Auto doctor/heal prefs + decision table (doc-9). Uses: DoctorStatus, DropLogger, MyVPNCLI.
/// Patterns: Cloudflare WAN hysteresis, k8s failureThreshold, follow-up heal (no cascade cooldown).
enum AutoDoctor {
    private static let doctorKey = "local.myvpn.mac.autoDoctor"
    private static let healKey = "local.myvpn.mac.autoHeal"
    private static let lastHealKey = "local.myvpn.mac.autoHeal.last"
    private static let lastHealKindKey = "local.myvpn.mac.autoHeal.lastKind"
    private static let healTimesKey = "local.myvpn.mac.autoHeal.times"

    /// Default ON (nil → true).
    static var autoDoctorEnabled: Bool {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: doctorKey) == nil { return true }
            return d.bool(forKey: doctorKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: doctorKey) }
    }

    static var autoHealEnabled: Bool {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: healKey) == nil { return true }
            return d.bool(forKey: healKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: healKey) }
    }

    static let cooldownSeconds: TimeInterval = 300
    /// After down→up, allow mount/flush without waiting full cooldown (cascade fix).
    static let followUpWindowSeconds: TimeInterval = 120
    static let maxHealsPerHour = 3
    /// Cloudflare-style: N consecutive bad samples before auto-doctor (DropLogger).
    static let dropConfirmNeeded = 2

    enum HealKind: Equatable {
        case up
        case restart
        case restartAndMount
        case mountNAS
        case flushDNS
        case none(reason: String)
    }

    /// Compact catalog for Settings → Диагностика (doc-9 §2).
    static let catalog: [(code: String, symptom: String, action: String)] = [
        ("TUN_DOWN", "VPN выкл", "myvpn up"),
        ("UNDERLAY_DOWN", "Wi‑Fi/default/Errno 49", "ждать сеть · не restart"),
        ("MACBOOK_EGRESS_DOWN", "Нет интернета, underlay ок", "down→up + mount"),
        ("HOME_PEER_DOWN", "Нет home / NAS / Hub", "down→up + mount-nas"),
        ("HOME_DOWN_MACBOOK_OK", "Интернет ок, home мёртв", "down→up + mount-nas"),
        ("NAS_MOUNT_ONLY", "Том NAS не смонтирован", "mount-nas --force"),
        ("NAS_STALE", "SMB half-open", "mount-nas --force"),
        ("DNS_STALE", "DNS не на TUN", "flush-dns"),
        ("CONFLICT_WG_APP", "Конфликт с WireGuard.app", "вручную выключить WG.app"),
        ("HEALTHY_ICMP_FALSE_ALARM", "ICMP filter, egress жив", "не heal"),
        ("HEALTHY_BUT_ENDPOINT_VIA_TUN", "Риск после sleep", "не heal (warn)"),
        ("EGRESS_NOT_VIA_MACBOOK", "IP не через macbook", "только doctor"),
        ("MIXED", "Смешанная картина", "только отчёт"),
    ]

    /// PRIMARY → heal. WARN/FAIL в меню не отменяет действие (doc-9).
    static func healKind(for primary: String) -> HealKind {
        switch primary {
        case "TUN_DOWN":
            return .up
        case "UNDERLAY_DOWN":
            return .none(reason: "underlay — ждать Wi‑Fi/WAN")
        case "MACBOOK_EGRESS_DOWN":
            // Opportunistic mount after restart — avoids NAS_MOUNT_ONLY + cooldown trap.
            return .restartAndMount
        case "HOME_PEER_DOWN", "HOME_DOWN_MACBOOK_OK":
            return .restartAndMount
        case "NAS_STALE", "NAS_MOUNT_ONLY":
            return .mountNAS
        case "DNS_STALE":
            return .flushDNS
        case "CONFLICT_WG_APP":
            return .none(reason: "выключи WireGuard.app")
        case "HEALTHY", "HEALTHY_ICMP_FALSE_ALARM", "HEALTHY_BUT_ENDPOINT_VIA_TUN":
            return .none(reason: "healthy")
        case "EGRESS_NOT_VIA_MACBOOK", "MIXED":
            return .none(reason: "нужен ручной разбор")
        default:
            if primary.hasPrefix("HEALTHY") {
                return .none(reason: "healthy")
            }
            return .none(reason: "нет правила heal для \(primary)")
        }
    }

    /// Soft follow-up after a restart heal (mount/flush) — skip cooldown, still rate-limit.
    static func isFollowUpHeal(primary: String, kind: HealKind) -> Bool {
        switch kind {
        case .mountNAS, .flushDNS:
            break
        default:
            return false
        }
        guard ["NAS_STALE", "NAS_MOUNT_ONLY", "DNS_STALE"].contains(primary) else { return false }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastHealKey)
        guard last > 0, now - last < followUpWindowSeconds else { return false }
        let lastKind = UserDefaults.standard.string(forKey: lastHealKindKey) ?? ""
        return lastKind == "down→up" || lastKind == "down→up+mount" || lastKind == "up"
    }

    static func canHealNow(primary: String = "", kind: HealKind = .none(reason: "")) -> (ok: Bool, reason: String?) {
        let now = Date().timeIntervalSince1970
        let followUp = isFollowUpHeal(primary: primary, kind: kind)
        if !followUp {
            let last = UserDefaults.standard.double(forKey: lastHealKey)
            if last > 0, now - last < cooldownSeconds {
                let left = Int(cooldownSeconds - (now - last))
                return (false, "cooldown \(left)с")
            }
        }
        var times = (UserDefaults.standard.array(forKey: healTimesKey) as? [Double]) ?? []
        times = times.filter { now - $0 < 3600 }
        // Follow-up mount doesn't burn the hourly budget (cascade after restart).
        if !followUp, times.count >= maxHealsPerHour {
            return (false, "лимит \(maxHealsPerHour)/час")
        }
        return (true, nil)
    }

    static func recordHeal(kind: HealKind, primary: String = "") {
        // Snapshot follow-up BEFORE bumping lastHeal timestamps.
        let skipHourly = isFollowUpHeal(primary: primary.isEmpty ? "NAS_MOUNT_ONLY" : primary, kind: kind)
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: lastHealKey)
        UserDefaults.standard.set(kindLabel(kind), forKey: lastHealKindKey)
        if skipHourly { return }
        var times = (UserDefaults.standard.array(forKey: healTimesKey) as? [Double]) ?? []
        times = times.filter { now - $0 < 3600 }
        times.append(now)
        UserDefaults.standard.set(times, forKey: healTimesKey)
    }

    /// Run heal action on caller queue (background). Uses: MyVPNCLI.
    static func performHeal(_ kind: HealKind) throws {
        switch kind {
        case .up:
            try MyVPNCLI.up()
        case .restart:
            try? MyVPNCLI.down()
            Thread.sleep(forTimeInterval: 1.0)
            try MyVPNCLI.up()
        case .restartAndMount:
            try? MyVPNCLI.down()
            Thread.sleep(forTimeInterval: 1.0)
            try MyVPNCLI.up()
            // Brief settle so SMB path exists before force-mount.
            Thread.sleep(forTimeInterval: 1.5)
            try? MyVPNCLI.mountNAS(force: true)
        case .mountNAS:
            try MyVPNCLI.mountNAS(force: true)
        case .flushDNS:
            try MyVPNCLI.flushDNS()
        case .none:
            break
        }
    }

    static func kindLabel(_ kind: HealKind) -> String {
        switch kind {
        case .up: return "up"
        case .restart: return "down→up"
        case .restartAndMount: return "down→up+mount"
        case .mountNAS: return "mount-nas"
        case .flushDNS: return "flush-dns"
        case .none(let r): return "skip(\(r))"
        }
    }
}
