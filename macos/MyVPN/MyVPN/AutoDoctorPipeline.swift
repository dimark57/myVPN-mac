import Foundation

/// FDIR Detect→Isolate→Recover pipeline (doc-10). Extracted from AppDelegate.
/// Uses: MyVPNCLI, AutoDoctor, DesiredStateStore, HealCircuitBreaker, DropLogger, IncidentStore, DoctorStatus.
enum AutoDoctorPipeline {
    /// Dedicated queue — auto L1 must not share menu `runCommand` 55s busyKey.
    static let queue = DispatchQueue(label: "local.myvpn.mac.auto-doctor", qos: .utility)

    struct Callbacks {
        var onDoctorLoaded: (DoctorStatus) -> Void
        var onNotify: (_ title: String, _ body: String, _ key: String) -> Void
        var onBusyHeal: () -> Void
        var onFinished: () -> Void
        var onRefresh: (_ includePublicIP: Bool) -> Void
    }

    static func run(
        sessionCid: String,
        event: DropLogger.DropEvent,
        callbacks: Callbacks
    ) {
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
            finish(callbacks: callbacks)
            return
        }

        guard AutoDoctor.autoDoctorEnabled else {
            finish(callbacks: callbacks)
            return
        }

        if DesiredStateStore.isInGrace {
            DropLogger.logEvent("AUTO_DOCTOR skip=grace")
            IncidentStore.attachHeal(cid: event.cid, attempted: false, ok: nil, action: "none", skipped: "grace")
            finish(callbacks: callbacks)
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
                _ = try MyVPNCLI.doctor(deep: false)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let doc = DoctorStatus.load()
                IncidentStore.attachL1(
                    cid: event.cid,
                    primary: doc.primary,
                    overall: doc.overall,
                    ms: ms
                )
                DropLogger.logEvent(
                    "AUTO_DOCTOR primary=\(doc.primary.isEmpty ? "?" : doc.primary) overall=\(doc.overall.isEmpty ? "?" : doc.overall) layer=L1 ms=\(ms)"
                )
                DispatchQueue.main.async {
                    callbacks.onDoctorLoaded(doc)
                    let pair = doc.notificationPair
                    callbacks.onNotify(pair.title, pair.body, "auto-doctor")
                }

                guard AutoDoctor.autoHealEnabled else {
                    DropLogger.logEvent("AUTO_HEAL skip=disabled")
                    IncidentStore.attachHeal(cid: event.cid, attempted: false, ok: nil, action: "none", skipped: "disabled")
                    DispatchQueue.main.async { finish(callbacks: callbacks) }
                    return
                }

                // Force INTENTIONAL_OFF semantics if desired off mid-flight.
                if !DesiredStateStore.desiredOn {
                    DropLogger.logEvent("AUTO_HEAL skip=desired_off primary=\(doc.primary)")
                    IncidentStore.attachHeal(cid: event.cid, attempted: false, ok: nil, action: "none", skipped: "desired_off")
                    DispatchQueue.main.async { finish(callbacks: callbacks) }
                    return
                }

                var primary = doc.primary
                if primary == "TUN_DOWN", !DesiredStateStore.desiredOn {
                    primary = "INTENTIONAL_OFF"
                }

                let kind = AutoDoctor.healKind(for: primary)
                if case .none(let reason) = kind {
                    DropLogger.logEvent("AUTO_HEAL skip=\(reason) primary=\(primary)")
                    IncidentStore.attachHeal(cid: event.cid, attempted: false, ok: nil, action: "none", skipped: reason)
                    DispatchQueue.main.async {
                        callbacks.onNotify(
                            "myVPN · Без автовосстановления",
                            "\(doc.userHeadline): \(reason) · \(DoctorStatus.nowStamp())",
                            "auto-heal"
                        )
                        finish(callbacks: callbacks)
                    }
                    return
                }

                let gate = AutoDoctor.canHealNow(primary: primary, kind: kind)
                guard gate.ok else {
                    DropLogger.logEvent("AUTO_HEAL skip=\(gate.reason ?? "gate") primary=\(primary)")
                    IncidentStore.attachHeal(
                        cid: event.cid,
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
                        // Explicit matrix line for drops (0.5.11) — reason already in skip=.
                        finish(callbacks: callbacks)
                    }
                    return
                }

                let followUp = AutoDoctor.isFollowUpHeal(primary: primary, kind: kind)
                DispatchQueue.main.async {
                    callbacks.onBusyHeal()
                    callbacks.onNotify(
                        "myVPN · Автовосстановление",
                        "\(AutoDoctor.kindLabel(kind))\(followUp ? " · follow-up" : "") · \(DoctorStatus.nowStamp())",
                        "auto-heal"
                    )
                }

                do {
                    var healError: String?
                    do {
                        try AutoDoctor.performHeal(kind)
                    } catch {
                        healError = error.localizedDescription
                    }
                    DesiredStateStore.setDesiredOn()
                    let verified = healError == nil && AutoDoctor.verifyAfterHeal(kind: kind)
                    let softOK = AutoDoctor.isSoftHealOK(kind: kind)
                    // Soft-success (0.5.10): helper timeout / verify lag while L0 already green — same as wake 0.5.7.
                    if verified || softOK {
                        AutoDoctor.recordHeal(kind: kind, primary: primary, verified: true)
                        let softTag = (!verified || healError != nil) ? " soft=1" : ""
                        DropLogger.logEvent(
                            "AUTO_HEAL ok=1 verify=\(verified ? 1 : 0)\(softTag) action=\(AutoDoctor.kindLabel(kind)) primary=\(primary)\(followUp ? " follow-up=1" : "")\(healError.map { " err=\($0)" } ?? "")"
                        )
                        IncidentStore.attachHeal(
                            cid: event.cid,
                            attempted: true,
                            ok: 1,
                            action: AutoDoctor.kindLabel(kind),
                            skipped: softTag.isEmpty ? nil : "soft"
                        )
                        DispatchQueue.main.async {
                            callbacks.onNotify(
                                "myVPN ✓ Восстановлено",
                                "\(AutoDoctor.kindLabel(kind)) после \(primary) · \(DoctorStatus.nowStamp())",
                                "auto-heal"
                            )
                            finish(callbacks: callbacks)
                            callbacks.onRefresh(true)
                        }
                    } else {
                        HealCircuitBreaker.recordVerifyFail()
                        let msg = healError ?? "verify_fail"
                        DropLogger.logEvent(
                            "AUTO_HEAL ok=0 verify=0 action=\(AutoDoctor.kindLabel(kind)) primary=\(primary) err=\(msg)"
                        )
                        IncidentStore.attachHeal(
                            cid: event.cid,
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
                            finish(callbacks: callbacks)
                            callbacks.onRefresh(true)
                        }
                    }
                }
            } catch {
                // Soft-success (0.5.11): L1 doctor timeout while L0 already green — no false ✕.
                let softOK = AutoDoctor.isSoftHealOK(kind: .restart)
                if softOK {
                    DropLogger.logEvent(
                        "AUTO_DOCTOR ok=1 soft=1 err=\(error.localizedDescription) — L0 green, skip heal"
                    )
                    IncidentStore.attachHeal(
                        cid: event.cid,
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
                        finish(callbacks: callbacks)
                        callbacks.onRefresh(true)
                    }
                } else {
                    DropLogger.logEvent("AUTO_DOCTOR ok=0 err=\(error.localizedDescription)")
                    DispatchQueue.main.async {
                        callbacks.onNotify(
                            "myVPN ✕ Автодиагностика",
                            error.localizedDescription,
                            "auto-doctor"
                        )
                        finish(callbacks: callbacks)
                    }
                }
            }
        }
    }

    private static func finish(callbacks: Callbacks) {
        DropLogger.currentIncidentCid = nil
        callbacks.onFinished()
    }
}
