import Foundation

/// FDIR Detect→Isolate→Recover pipeline (doc-10 / doc-11). Extracted from AppDelegate.
/// Uses: MyVPNCLI, AutoDoctor, DesiredStateStore, HealCircuitBreaker, DropLogger, IncidentStore, DoctorStatus.
enum AutoDoctorPipeline {
    /// Dedicated queue — auto L1 must not share menu `runCommand` 55s busyKey.
    static let queue = DispatchQueue(label: "local.myvpn.mac.auto-doctor", qos: .utility)

    /// Wake aborted in-flight doctor — pipeline must not heal (WakeRecover owns it).
    static var skipHealBecauseWake = false
    /// True while performHeal runs — WakeRecover must not double-restart.
    static var healInFlight = false

    static func noteWake() {
        skipHealBecauseWake = true
    }

    struct Callbacks {
        var onDoctorLoaded: (DoctorStatus) -> Void
        var onNotify: (_ title: String, _ body: String, _ key: String) -> Void
        var onBusyHeal: () -> Void
        var onFinished: (_ outcome: String, _ cid: String) -> Void
        var onRefresh: (_ includePublicIP: Bool) -> Void
    }

    static func run(
        sessionCid: String,
        event: DropLogger.DropEvent,
        callbacks: Callbacks
    ) {
        skipHealBecauseWake = false
        healInFlight = false
        IncidentStore.begin(cid: event.cid, channels: event.channels, sessionCid: sessionCid)
        DropLogger.currentIncidentCid = event.cid

        if event.intentionalOff {
            DropLogger.logEvent("AUTO_DOCTOR skip=desired_off primary=INTENTIONAL_OFF")
            IncidentStore.attachHeal(
                cid: event.cid,
                attempted: false,
                ok: nil,
                action: "none",
                skipped: "desired_off"
            )
            callbacks.onNotify(
                "myVPN · Off",
                "Желаемое состояние: выкл — автоheal отключён · \(DoctorStatus.nowStamp())",
                "auto-doctor"
            )
            finish(callbacks: callbacks, cid: event.cid, outcome: "skip_desired_off")
            return
        }

        guard AutoDoctor.autoDoctorEnabled else {
            IncidentStore.attachHeal(
                cid: event.cid,
                attempted: false,
                ok: nil,
                action: "none",
                skipped: "disabled"
            )
            finish(callbacks: callbacks, cid: event.cid, outcome: "skip_disabled")
            return
        }

        if DesiredStateStore.isInGrace {
            DropLogger.logEvent("AUTO_DOCTOR skip=grace")
            IncidentStore.attachHeal(cid: event.cid, attempted: false, ok: nil, action: "none", skipped: "grace")
            finish(callbacks: callbacks, cid: event.cid, outcome: "skip_grace")
            return
        }

        HealCircuitBreaker.armHalfOpenIfDue()
        callbacks.onNotify(
            "myVPN · Автодиагностика",
            "L1 triage · \(DoctorStatus.nowStamp())",
            "auto-doctor"
        )

        queue.async {
            let t0 = Date()
            do {
                if skipHealBecauseWake {
                    skipBecauseWake(cid: event.cid, callbacks: callbacks)
                    return
                }
                _ = try MyVPNCLI.doctor(deep: false)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let killed = MyVPNCLI.lastKilled
                let doc = DoctorStatus.load()
                IncidentStore.attachL1(
                    cid: event.cid,
                    primary: doc.primary,
                    overall: doc.overall,
                    ms: ms,
                    killed: killed
                )
                DropLogger.logEvent(
                    "AUTO_DOCTOR primary=\(doc.primary.isEmpty ? "?" : doc.primary) overall=\(doc.overall.isEmpty ? "?" : doc.overall) layer=L1 ms=\(ms) killed=\(killed ? 1 : 0)"
                )
                DispatchQueue.main.async {
                    callbacks.onDoctorLoaded(doc)
                    let pair = doc.notificationPair
                    callbacks.onNotify(pair.title, pair.body, "auto-doctor")
                }

                if skipHealBecauseWake {
                    skipBecauseWake(cid: event.cid, callbacks: callbacks)
                    return
                }

                guard AutoDoctor.autoHealEnabled else {
                    DropLogger.logEvent("AUTO_HEAL skip=disabled")
                    IncidentStore.attachHeal(cid: event.cid, attempted: false, ok: nil, action: "none", skipped: "disabled")
                    finish(callbacks: callbacks, cid: event.cid, outcome: "skip_disabled")
                    return
                }

                // Force INTENTIONAL_OFF semantics if desired off mid-flight.
                if !DesiredStateStore.desiredOn {
                    DropLogger.logEvent("AUTO_HEAL skip=desired_off primary=\(doc.primary)")
                    IncidentStore.attachHeal(cid: event.cid, attempted: false, ok: nil, action: "none", skipped: "desired_off")
                    finish(callbacks: callbacks, cid: event.cid, outcome: "skip_desired_off")
                    return
                }

                var primary = doc.primary
                if primary == "TUN_DOWN", !DesiredStateStore.desiredOn {
                    primary = "INTENTIONAL_OFF"
                }

                let kind = AutoDoctor.healKind(for: primary)
                if case .none(let reason) = kind {
                    let outcome = primary.hasPrefix("HEALTHY") ? "false_alarm" : "skip_\(sanitizeOutcome(reason))"
                    DropLogger.logEvent("AUTO_HEAL skip=\(reason) primary=\(primary)")
                    IncidentStore.attachHeal(cid: event.cid, attempted: false, ok: nil, action: "none", skipped: reason)
                    DispatchQueue.main.async {
                        callbacks.onNotify(
                            "myVPN · Без автовосстановления",
                            "\(doc.userHeadline): \(reason) · \(DoctorStatus.nowStamp())",
                            "auto-heal"
                        )
                    }
                    finish(callbacks: callbacks, cid: event.cid, outcome: outcome)
                    return
                }

                runHeal(
                    cid: event.cid,
                    primary: primary,
                    kind: kind,
                    outcomeIfOk: "heal_ok",
                    callbacks: callbacks
                )
            } catch {
                handleDoctorFailure(
                    cid: event.cid,
                    channels: event.channels,
                    started: t0,
                    error: error,
                    callbacks: callbacks
                )
            }
        }
    }

    private static func skipBecauseWake(cid: String, callbacks: Callbacks) {
        DropLogger.logEvent("AUTO_DOCTOR skip=wake")
        IncidentStore.attachHeal(cid: cid, attempted: false, ok: nil, action: "none", skipped: "wake")
        finish(callbacks: callbacks, cid: cid, outcome: "skip_wake", killed: MyVPNCLI.lastKilled)
    }

    private static func handleDoctorFailure(
        cid: String,
        channels: [String],
        started: Date,
        error: Error,
        callbacks: Callbacks
    ) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let killed = MyVPNCLI.lastKilled
        IncidentStore.attachL1(
            cid: cid,
            primary: "?",
            overall: "?",
            ms: ms,
            killed: killed
        )
        DropLogger.logEvent(
            "AUTO_DOCTOR ok=0 err=\(error.localizedDescription) ms=\(ms) killed=\(killed ? 1 : 0)"
        )

        if skipHealBecauseWake {
            skipBecauseWake(cid: cid, callbacks: callbacks)
            return
        }

        // Soft-success (0.5.11): L1 doctor timeout while L0 already green — no false ✕.
        let softOK = AutoDoctor.isSoftHealOK(kind: .restart)
        if softOK {
            DropLogger.logEvent(
                "AUTO_DOCTOR ok=1 soft=1 err=\(error.localizedDescription) — L0 green, skip heal"
            )
            IncidentStore.attachHeal(
                cid: cid,
                attempted: false,
                ok: 1,
                action: "none",
                skipped: "doctor_soft"
            )
            DispatchQueue.main.async {
                callbacks.onNotify(
                    "myVPN · Автодиагностика",
                    "L0 ок (doctor soft) · \(DoctorStatus.nowStamp())",
                    "auto-doctor"
                )
                callbacks.onRefresh(true)
            }
            finish(callbacks: callbacks, cid: cid, outcome: "soft", killed: killed)
            return
        }

        // doc-12 / 0.5.19: timeout→restart only for VPN hard channels. NAS-only never down→up.
        let vpnChannels = channels.contains(where: { $0 == "egress" || $0 == "tun" })
        if !vpnChannels {
            if channels.contains("nas") {
                DropLogger.logEvent("AUTO_HEAL timeout→mount-only channels=\(channels.joined(separator: ","))")
                runHeal(
                    cid: cid,
                    primary: "NAS_MOUNT_ONLY",
                    kind: .mountNAS,
                    outcomeIfOk: "timeout_mount",
                    callbacks: callbacks
                )
                return
            }
            DropLogger.logEvent(
                "AUTO_HEAL skip=timeout_no_vpn_channel channels=\(channels.joined(separator: ","))"
            )
            IncidentStore.attachHeal(
                cid: cid,
                attempted: false,
                ok: nil,
                action: "none",
                skipped: "timeout_no_vpn_channel"
            )
            finish(callbacks: callbacks, cid: cid, outcome: "skip_timeout_no_vpn", killed: killed)
            return
        }

        // doc-11: timeout + L0 red → .restart (the 07:22 hole). Respect desiredOff / grace / Safe Mode / cooldown.
        DispatchQueue.main.async {
            callbacks.onNotify(
                "myVPN ✕ Автодиагностика",
                error.localizedDescription,
                "auto-doctor"
            )
        }
        runHeal(
            cid: cid,
            primary: "MACBOOK_EGRESS_DOWN",
            kind: .restart,
            outcomeIfOk: "timeout_heal",
            callbacks: callbacks
        )
    }

    private static func runHeal(
        cid: String,
        primary: String,
        kind: AutoDoctor.HealKind,
        outcomeIfOk: String,
        callbacks: Callbacks
    ) {
        if skipHealBecauseWake {
            skipBecauseWake(cid: cid, callbacks: callbacks)
            return
        }
        if DesiredStateStore.isInGrace {
            DropLogger.logEvent("AUTO_HEAL skip=grace primary=\(primary)")
            IncidentStore.attachHeal(cid: cid, attempted: false, ok: nil, action: AutoDoctor.kindLabel(kind), skipped: "grace")
            finish(callbacks: callbacks, cid: cid, outcome: "skip_grace")
            return
        }
        if !DesiredStateStore.desiredOn {
            DropLogger.logEvent("AUTO_HEAL skip=desired_off primary=\(primary)")
            IncidentStore.attachHeal(cid: cid, attempted: false, ok: nil, action: "none", skipped: "desired_off")
            finish(callbacks: callbacks, cid: cid, outcome: "skip_desired_off")
            return
        }

        let gate = AutoDoctor.canHealNow(primary: primary, kind: kind)
        guard gate.ok else {
            DropLogger.logEvent("AUTO_HEAL skip=\(gate.reason ?? "gate") primary=\(primary)")
            IncidentStore.attachHeal(
                cid: cid,
                attempted: false,
                ok: nil,
                action: AutoDoctor.kindLabel(kind),
                skipped: gate.reason
            )
            DispatchQueue.main.async {
                callbacks.onNotify(
                    "myVPN · Heal отложен",
                    "\(gate.reason ?? "cooldown") · \(DoctorStatus.nowStamp())",
                    "auto-heal"
                )
            }
            finish(callbacks: callbacks, cid: cid, outcome: "skip_\(sanitizeOutcome(gate.reason ?? "gate"))")
            return
        }

        let followUp = AutoDoctor.isFollowUpHeal(primary: primary, kind: kind)

        // doc-12 / 0.5.19: last chance — never down→up if L0 already green (probe lag / race).
        if AutoDoctor.isRestartKind(kind), AutoDoctor.isSoftHealOK(kind: kind) {
            DropLogger.logEvent("AUTO_HEAL skip=l0_already_ok primary=\(primary)")
            IncidentStore.attachHeal(
                cid: cid,
                attempted: false,
                ok: 1,
                action: "none",
                skipped: "l0_already_ok"
            )
            DispatchQueue.main.async {
                callbacks.onNotify(
                    "myVPN · Без restart",
                    "L0 уже ок — \(primary) · \(DoctorStatus.nowStamp())",
                    "auto-heal"
                )
                callbacks.onRefresh(true)
            }
            finish(callbacks: callbacks, cid: cid, outcome: "skip_l0_ok")
            return
        }

        DispatchQueue.main.async {
            callbacks.onBusyHeal()
            callbacks.onNotify(
                "myVPN · Автовосстановление",
                "\(AutoDoctor.kindLabel(kind))\(followUp ? " · follow-up" : "") · \(DoctorStatus.nowStamp())",
                "auto-heal"
            )
        }

        healInFlight = true
        defer { healInFlight = false }

        var healError: String?
        do {
            try AutoDoctor.performHeal(kind)
        } catch {
            healError = error.localizedDescription
        }
        DesiredStateStore.setDesiredOn()
        let verified = healError == nil && AutoDoctor.verifyAfterHeal(kind: kind)
        let softOK = AutoDoctor.isSoftHealOK(kind: kind)
        if verified || softOK {
            AutoDoctor.recordHeal(kind: kind, primary: primary, verified: true)
            let softTag = (!verified || healError != nil) ? " soft=1" : ""
            DropLogger.logEvent(
                "AUTO_HEAL ok=1 verify=\(verified ? 1 : 0)\(softTag) action=\(AutoDoctor.kindLabel(kind)) primary=\(primary)\(followUp ? " follow-up=1" : "")\(healError.map { " err=\($0)" } ?? "")"
            )
            IncidentStore.attachHeal(
                cid: cid,
                attempted: true,
                ok: 1,
                action: AutoDoctor.kindLabel(kind),
                skipped: softTag.isEmpty ? nil : "soft"
            )
            if kind == .restart, primary == "MACBOOK_EGRESS_DOWN" {
                followUpMountIfNASDown()
            }
            DispatchQueue.main.async {
                callbacks.onNotify(
                    "myVPN ✓ Восстановлено",
                    "\(AutoDoctor.kindLabel(kind)) после \(primary) · \(DoctorStatus.nowStamp())",
                    "auto-heal"
                )
                callbacks.onRefresh(true)
            }
            finish(callbacks: callbacks, cid: cid, outcome: outcomeIfOk)
        } else {
            HealCircuitBreaker.recordVerifyFail()
            let msg = healError ?? "verify_fail"
            DropLogger.logEvent(
                "AUTO_HEAL ok=0 verify=0 action=\(AutoDoctor.kindLabel(kind)) primary=\(primary) err=\(msg)"
            )
            IncidentStore.attachHeal(
                cid: cid,
                attempted: true,
                ok: 0,
                action: AutoDoctor.kindLabel(kind),
                skipped: msg
            )
            DispatchQueue.main.async {
                let title = HealCircuitBreaker.isSafeMode
                    ? "myVPN · Safe Mode"
                    : "myVPN ✕ Verify"
                let body = HealCircuitBreaker.isSafeMode
                    ? "Автоheal остановлен — Resume в Настройки · \(DoctorStatus.nowStamp())"
                    : "\(msg) · \(DoctorStatus.nowStamp())"
                callbacks.onNotify(title, body, "auto-heal")
                callbacks.onRefresh(true)
            }
            finish(callbacks: callbacks, cid: cid, outcome: "verify_fail")
        }
    }

    /// After egress `.restart` + verify PASS: mount-nas --safe if L0 nas=0 (120s follow-up window).
    private static func followUpMountIfNASDown() {
        let snap = MyVPNCLI.status(includePublicIP: false)
        guard !snap.nas else { return }
        let gate = AutoDoctor.canHealNow(primary: "NAS_MOUNT_ONLY", kind: .mountNAS)
        guard gate.ok else {
            DropLogger.logEvent("AUTO_HEAL skip=\(gate.reason ?? "gate") follow-up=mount")
            return
        }
        DropLogger.logEvent("AUTO_HEAL follow-up mount-nas --safe nas=0")
        do {
            try AutoDoctor.performHeal(.mountNAS)
            let ok = AutoDoctor.verifyAfterHeal(kind: .mountNAS) || AutoDoctor.isSoftHealOK(kind: .mountNAS)
            AutoDoctor.recordHeal(kind: .mountNAS, primary: "NAS_MOUNT_ONLY", verified: ok)
            DropLogger.logEvent("HEAL_NAS ok=\(ok ? 1 : 0) follow-up=1")
        } catch {
            DropLogger.logEvent("HEAL_NAS ok=0 err=\(error.localizedDescription) follow-up=1")
        }
    }

    private static func sanitizeOutcome(_ reason: String) -> String {
        let trimmed = reason.split(separator: " ").first.map(String.init) ?? reason
        return String(trimmed.prefix(24))
    }

    private static func finish(
        callbacks: Callbacks,
        cid: String,
        outcome: String,
        killed: Bool = false
    ) {
        let recovery = IncidentStore.elapsedMs(cid: cid)
        IncidentStore.end(cid: cid, outcome: outcome, recoveryMs: recovery, killed: killed)
        DropLogger.currentIncidentCid = nil
        let go = {
            callbacks.onFinished(outcome, cid)
        }
        if Thread.isMainThread {
            go()
        } else {
            DispatchQueue.main.async(execute: go)
        }
    }
}
