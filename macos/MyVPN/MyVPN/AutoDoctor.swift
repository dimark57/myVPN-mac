import Foundation

/// Auto doctor/heal prefs + decision table (doc-9 / doc-10 FDIR).
/// Uses: DoctorStatus, DropLogger, MyVPNCLI, DesiredStateStore, HealCircuitBreaker.
enum AutoDoctor {
    private static let doctorKey = "local.myvpn.mac.autoDoctor"
    private static let healKey = "local.myvpn.mac.autoHeal"
    private static let lastHealKey = "local.myvpn.mac.autoHeal.last"
    private static let lastHealKindKey = "local.myvpn.mac.autoHeal.lastKind"
    private static let lastHealPrimaryKey = "local.myvpn.mac.autoHeal.lastPrimary"
    private static let lastRestartHealKey = "local.myvpn.mac.autoHeal.lastRestart"
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
    static let followUpWindowSeconds: TimeInterval = 120
    /// Zombie UDP can recur ~10–15 мин на Batt — 3/ч мало (0.5.17).
    static let maxHealsPerHour = 6
    static let dropConfirmNeeded = 2
    /// Wall-clock between first CONFIRM and DROP_CONFIRMED (doc-10).
    static let dropConfirmMinSeconds: TimeInterval = 20
    /// Suppress DropLogger→pipeline *restart* heal after up/down/heal/wake.
    /// WakeRecover may still pin + mount-nas during grace (0.5.1 carve-out).
    static let postChangeGraceSeconds: TimeInterval = 60
    /// Network settle after didWake before L0 / NAS / egress check.
    static let wakeSettleSeconds: TimeInterval = 10
    static let verifyFailsToSafeMode = 2
    static let safeModeHoldSeconds: TimeInterval = 300
    /// L1 doctor process budget (auto + default CLI).
    static let l1DoctorTimeout: TimeInterval = 10
    static let l2DoctorTimeout: TimeInterval = 90
    static let mountUITimeout: TimeInterval = 120

    enum HealKind: Equatable {
        case up
        case restart
        case restartAndMount
        case mountNAS
        case flushDNS
        case none(reason: String)
    }

    /// Compact catalog for Settings → Диагностика (doc-9 §2 + doc-10).
    static let catalog: [(code: String, symptom: String, action: String)] = [
        ("TUN_DOWN", "VPN выкл (desired ON)", "myvpn up"),
        ("INTENTIONAL_OFF", "Ручной Off", "не heal"),
        ("UNDERLAY_DOWN", "Wi‑Fi/default/Errno 49", "ждать сеть · не restart"),
        ("MACBOOK_EGRESS_DOWN", "Нет интернета, underlay ок", "down→up + mount"),
        ("HOME_PEER_DOWN", "Нет home / NAS / Hub", "down→up + mount-nas"),
        ("HOME_DOWN_MACBOOK_OK", "Интернет ок, home мёртв", "down→up + mount-nas"),
        ("NAS_MOUNT_ONLY", "Том NAS не смонтирован", "mount-nas (safe)"),
        ("NAS_STALE", "SMB half-open", "mount-nas (safe)"),
        ("NAS_BUSY", "NAS занят open files", "не force · notify"),
        ("DNS_STALE", "DNS не на TUN", "flush-dns"),
        ("CONFLICT_WG_APP", "Конфликт с WireGuard.app", "вручную выключить WG.app"),
        ("HEALTHY_ICMP_FALSE_ALARM", "ICMP filter, egress жив", "не heal"),
        ("HEALTHY_BUT_ENDPOINT_VIA_TUN", "Риск после sleep", "не heal (warn)"),
        ("SLEEP_WAKE_STALE", "После wake egress мёртв", "down→up + re-pin"),
        ("EGRESS_NOT_VIA_MACBOOK", "IP не через macbook", "только doctor"),
        ("MIXED", "Смешанная картина", "только отчёт"),
    ]

    static func healKind(for primary: String) -> HealKind {
        switch primary {
        case "TUN_DOWN":
            return .up
        case "INTENTIONAL_OFF":
            return .none(reason: "desired_off")
        case "UNDERLAY_DOWN":
            return .none(reason: "underlay — ждать Wi‑Fi/WAN")
        case "MACBOOK_EGRESS_DOWN", "SLEEP_WAKE_STALE":
            return .restartAndMount
        case "HOME_PEER_DOWN", "HOME_DOWN_MACBOOK_OK":
            return .restartAndMount
        case "NAS_STALE", "NAS_MOUNT_ONLY":
            return .mountNAS
        case "NAS_BUSY":
            return .none(reason: "NAS_BUSY — не force")
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

    static func isRestartKind(_ kind: HealKind) -> Bool {
        switch kind {
        case .restart, .restartAndMount: return true
        default: return false
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

    /// TUN_DOWN→up when desiredOn bypasses shared restart cooldown (doc-10).
    /// New DROP with a *different* PRIMARY may bypass restart cooldown once (0.5.11).
    static func canHealNow(primary: String = "", kind: HealKind = .none(reason: "")) -> (ok: Bool, reason: String?) {
        if !DesiredStateStore.desiredOn {
            return (false, "desired_off")
        }
        if primary == "TUN_DOWN" || primary == "INTENTIONAL_OFF" {
            if !DesiredStateStore.desiredOn {
                return (false, "desired_off")
            }
        }
        let breaker = HealCircuitBreaker.canAttemptHeal()
        guard breaker.ok else {
            return (false, "safe_mode reason=\(breaker.reason ?? "open")")
        }

        let now = Date().timeIntervalSince1970
        let followUp = isFollowUpHeal(primary: primary, kind: kind)
        let tunUpExempt = (kind == .up && primary == "TUN_DOWN" && DesiredStateStore.desiredOn)
        let lastPrimary = UserDefaults.standard.string(forKey: lastHealPrimaryKey) ?? ""
        let lastKind = UserDefaults.standard.string(forKey: lastHealKindKey) ?? ""

        if !followUp, !tunUpExempt, isRestartKind(kind) {
            let lastRestart = UserDefaults.standard.double(forKey: lastRestartHealKey)
            if lastRestart > 0, now - lastRestart < cooldownSeconds {
                let left = Int(cooldownSeconds - (now - lastRestart))
                // Different PRIMARY after a new DROP — allow one restart (cascade morning bug).
                if !primary.isEmpty, !lastPrimary.isEmpty, primary != lastPrimary {
                    DropLogger.logEvent(
                        "HEAL_GATE cooldown_bypass=new_primary last=\(lastPrimary) new=\(primary) left_would=\(left)с"
                    )
                    // fall through
                } else {
                    return (
                        false,
                        "cooldown \(left)с block=restart last_primary=\(lastPrimary.isEmpty ? "?" : lastPrimary) last_kind=\(lastKind.isEmpty ? "?" : lastKind) new=\(primary.isEmpty ? "?" : primary)"
                    )
                }
            }
        } else if !followUp, !tunUpExempt, !isRestartKind(kind), kind != .up {
            let last = UserDefaults.standard.double(forKey: lastHealKey)
            if last > 0, now - last < cooldownSeconds {
                let left = Int(cooldownSeconds - (now - last))
                return (
                    false,
                    "cooldown \(left)с block=soft last_kind=\(lastKind.isEmpty ? "?" : lastKind) new=\(primary.isEmpty ? "?" : primary)"
                )
            }
        }

        var times = (UserDefaults.standard.array(forKey: healTimesKey) as? [Double]) ?? []
        times = times.filter { now - $0 < 3600 }
        if !followUp, times.count >= maxHealsPerHour {
            HealCircuitBreaker.recordBudgetExhausted()
            return (false, "лимит \(maxHealsPerHour)/час")
        }
        return (true, nil)
    }

    /// Record only after verify PASS (doc-10).
    static func recordHeal(kind: HealKind, primary: String = "", verified: Bool) {
        guard verified else { return }
        let skipHourly = isFollowUpHeal(primary: primary.isEmpty ? "NAS_MOUNT_ONLY" : primary, kind: kind)
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: lastHealKey)
        UserDefaults.standard.set(kindLabel(kind), forKey: lastHealKindKey)
        if !primary.isEmpty {
            UserDefaults.standard.set(primary, forKey: lastHealPrimaryKey)
        }
        if isRestartKind(kind) {
            UserDefaults.standard.set(now, forKey: lastRestartHealKey)
        }
        if skipHourly { return }
        var times = (UserDefaults.standard.array(forKey: healTimesKey) as? [Double]) ?? []
        times = times.filter { now - $0 < 3600 }
        times.append(now)
        UserDefaults.standard.set(times, forKey: healTimesKey)
        HealCircuitBreaker.recordVerifyPass()
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
            Thread.sleep(forTimeInterval: 1.5)
            // Surface mount errors in drops (was try? silent — wake 0.5.5 false "ok").
            do {
                try MyVPNCLI.mountNAS(force: false, safe: true)
                DropLogger.logEvent("HEAL_NAS ok=1")
            } catch {
                DropLogger.logEvent("HEAL_NAS ok=0 err=\(error.localizedDescription)")
            }
        case .mountNAS:
            try MyVPNCLI.mountNAS(force: false, safe: true)
        case .flushDNS:
            try MyVPNCLI.flushDNS()
        case .none:
            break
        }
    }

    /// Mini post-heal verify: tun up + (for restart) public IP non-empty when includeIP.
    static func verifyAfterHeal(kind: HealKind) -> Bool {
        let snap = MyVPNCLI.status(includePublicIP: isRestartKind(kind) || kind == .up)
        switch kind {
        case .up, .restart, .restartAndMount:
            guard snap.tun else { return false }
            if isRestartKind(kind) {
                // Soft: empty IP still counts as fail for egress heals.
                return !snap.ip.isEmpty || snap.macbook
            }
            return true
        case .mountNAS:
            return snap.nas
        case .flushDNS:
            return snap.tun
        case .none:
            return true
        }
    }

    /// L0 soft-success after helper timeout / strict verify lag (0.5.7 wake, 0.5.10 pipeline).
    /// Uses: MyVPNCLI.status — tun live and (public IP or macbook ICMP).
    static func isSoftHealOK(kind: HealKind, snap: StatusSnapshot? = nil) -> Bool {
        let s = snap ?? MyVPNCLI.status(includePublicIP: isRestartKind(kind) || kind == .up)
        switch kind {
        case .up, .restart, .restartAndMount:
            return s.tun && (!s.ip.isEmpty || s.macbook)
        case .mountNAS:
            return s.nas
        case .flushDNS:
            return s.tun
        case .none:
            return true
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
