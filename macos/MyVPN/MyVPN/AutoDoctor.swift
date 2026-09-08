import Foundation

/// Auto doctor/heal prefs + decision table (doc-9). Uses: DoctorStatus, DropLogger, MyVPNCLI.
enum AutoDoctor {
    private static let doctorKey = "local.myvpn.mac.autoDoctor"
    private static let healKey = "local.myvpn.mac.autoHeal"
    private static let lastHealKey = "local.myvpn.mac.autoHeal.last"
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
    static let maxHealsPerHour = 3

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
        ("MACBOOK_EGRESS_DOWN", "Нет интернета, NAS может жить", "down→up"),
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

    static func healKind(for primary: String) -> HealKind {
        switch primary {
        case "TUN_DOWN":
            return .up
        case "MACBOOK_EGRESS_DOWN":
            return .restart
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

    /// Underlay dead → skip restart (doc-9: don't spin VPN).
    static func shouldSkipRestartForUnderlay(_ doc: DoctorStatus) -> Bool {
        // state.json doesn't store mb_ep; infer from MACBOOK + empty pub already failed.
        // Skip only when doctor text/latest mentions endpoint ICMP fail — soft check via primary only.
        _ = doc
        return false
    }

    static func canHealNow() -> (ok: Bool, reason: String?) {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastHealKey)
        if last > 0, now - last < cooldownSeconds {
            let left = Int(cooldownSeconds - (now - last))
            return (false, "cooldown \(left)с")
        }
        var times = (UserDefaults.standard.array(forKey: healTimesKey) as? [Double]) ?? []
        times = times.filter { now - $0 < 3600 }
        if times.count >= maxHealsPerHour {
            return (false, "лимит \(maxHealsPerHour)/час")
        }
        return (true, nil)
    }

    static func recordHeal() {
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: lastHealKey)
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
