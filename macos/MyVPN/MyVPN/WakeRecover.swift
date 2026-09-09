import Foundation

/// Soft recover after `NSWorkspace.didWake` (doc-10 / 0.5.1).
/// Uses: DesiredStateStore, AutoDoctor, MyVPNCLI, DropLogger, FlightRecorder, StatusSnapshot.
/// Grace still blocks DropLogger→pipeline restart-heal; this path may pin + mount-nas and,
/// only if egress is dead, one SLEEP_WAKE_STALE restart (cooldown still applies).
enum WakeRecover {
    static let queue = DispatchQueue(label: "local.myvpn.mac.wake-recover", qos: .utility)

    /// Prevent overlapping wake recoveries (double didWake / rapid lid).
    private static var inFlight = false
    private static let lock = NSLock()

    struct Callbacks {
        var onSnapshot: (StatusSnapshot) -> Void
        var onNotify: (_ title: String, _ body: String, _ key: String) -> Void
        var onRefresh: (_ includePublicIP: Bool) -> Void
    }

    static func schedule(sessionCid: String, callbacks: Callbacks) {
        DesiredStateStore.enterGrace(seconds: AutoDoctor.postChangeGraceSeconds)
        DropLogger.logEvent("WAKE grace=\(Int(AutoDoctor.postChangeGraceSeconds))с settle=\(Int(AutoDoctor.wakeSettleSeconds))с")

        let settle = AutoDoctor.wakeSettleSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            run(sessionCid: sessionCid, callbacks: callbacks)
        }
    }

    static func run(sessionCid: String, callbacks: Callbacks) {
        lock.lock()
        if inFlight {
            lock.unlock()
            DropLogger.logEvent("WAKE_RECOVER skip=in_flight")
            return
        }
        inFlight = true
        lock.unlock()

        queue.async {
            defer {
                lock.lock()
                inFlight = false
                lock.unlock()
            }

            guard DesiredStateStore.desiredOn else {
                DropLogger.logEvent("WAKE_RECOVER skip=desired_off")
                let snap = MyVPNCLI.status(includePublicIP: false)
                FlightRecorder.append(sample: snap, sessionCid: sessionCid, wake: true)
                DispatchQueue.main.async {
                    callbacks.onSnapshot(snap)
                    callbacks.onRefresh(true)
                }
                return
            }

            // L0 after settle
            var snap = MyVPNCLI.status(includePublicIP: true)
            FlightRecorder.append(sample: snap, sessionCid: sessionCid, wake: true)
            DropLogger.logEvent(
                "WAKE_L0 tun=\(snap.tun ? 1 : 0) home=\(snap.home ? 1 : 0) macbook=\(snap.macbook ? 1 : 0) nas=\(snap.nas ? 1 : 0) ip=\(snap.ip.isEmpty ? "-" : "ok")"
            )
            DispatchQueue.main.async { callbacks.onSnapshot(snap) }

            // Re-pin WG endpoints via LAN gw (best-effort; needs helper ≥0.5.1).
            do {
                try MyVPNCLI.pinEndpoints()
                DropLogger.logEvent("WAKE_PIN ok=1")
            } catch {
                DropLogger.logEvent("WAKE_PIN ok=0 err=\(error.localizedDescription)")
            }

            // NAS fast-path — not blocked by grace (doc-10 carve-out).
            let wantNAS = MyVPNCLI.autoNASEnabled() || AutoDoctor.autoHealEnabled
            if wantNAS, snap.tun, !snap.nas {
                DropLogger.logEvent("WAKE_NAS mount-nas --safe")
                DispatchQueue.main.async {
                    callbacks.onNotify(
                        "myVPN · После сна",
                        "Монтирую NAS · \(DoctorStatus.nowStamp())",
                        "wake-nas"
                    )
                }
                do {
                    try MyVPNCLI.mountNAS(force: false, safe: true)
                    snap = MyVPNCLI.status(includePublicIP: false)
                    DropLogger.logEvent("WAKE_NAS ok=\(snap.nas ? 1 : 0)")
                    DispatchQueue.main.async {
                        callbacks.onSnapshot(snap)
                        if snap.nas {
                            callbacks.onNotify(
                                "myVPN ✓ NAS",
                                "Смонтирован после wake · \(DoctorStatus.nowStamp())",
                                "wake-nas"
                            )
                        }
                    }
                } catch {
                    DropLogger.logEvent("WAKE_NAS ok=0 err=\(error.localizedDescription)")
                    DispatchQueue.main.async {
                        callbacks.onNotify(
                            "myVPN · NAS после сна",
                            error.localizedDescription,
                            "wake-nas"
                        )
                    }
                }
            }

            // SLEEP_WAKE_STALE: tun alive, egress dead after settle → one restart.
            snap = MyVPNCLI.status(includePublicIP: true)
            let egressDead = snap.tun && snap.ip.isEmpty && !snap.macbook
            guard AutoDoctor.autoHealEnabled, egressDead else {
                DispatchQueue.main.async { callbacks.onRefresh(true) }
                return
            }

            let primary = "SLEEP_WAKE_STALE"
            let kind = AutoDoctor.healKind(for: primary)
            let gate = AutoDoctor.canHealNow(primary: primary, kind: kind)
            guard gate.ok else {
                DropLogger.logEvent("WAKE_HEAL skip=\(gate.reason ?? "gate") primary=\(primary)")
                DispatchQueue.main.async {
                    callbacks.onNotify(
                        "myVPN · Wake heal отложен",
                        "\(gate.reason ?? "cooldown") · \(DoctorStatus.nowStamp())",
                        "wake-heal"
                    )
                    callbacks.onRefresh(true)
                }
                return
            }

            DropLogger.logEvent("WAKE_HEAL primary=\(primary) action=\(AutoDoctor.kindLabel(kind))")
            DispatchQueue.main.async {
                callbacks.onNotify(
                    "myVPN · После сна",
                    "Восстанавливаю туннель · \(DoctorStatus.nowStamp())",
                    "wake-heal"
                )
            }

            do {
                try AutoDoctor.performHeal(kind)
                DesiredStateStore.setDesiredOn()
                let verified = AutoDoctor.verifyAfterHeal(kind: kind)
                if verified {
                    AutoDoctor.recordHeal(kind: kind, primary: primary, verified: true)
                    DropLogger.logEvent("WAKE_HEAL ok=1 verify=1 primary=\(primary)")
                    DispatchQueue.main.async {
                        callbacks.onNotify(
                            "myVPN ✓ После сна",
                            "Туннель восстановлен · \(DoctorStatus.nowStamp())",
                            "wake-heal"
                        )
                        callbacks.onRefresh(true)
                    }
                } else {
                    HealCircuitBreaker.recordVerifyFail()
                    DropLogger.logEvent("WAKE_HEAL ok=0 verify=0 primary=\(primary)")
                    DispatchQueue.main.async {
                        callbacks.onNotify(
                            "myVPN ✕ После сна",
                            "Heal не подтвердился · \(DoctorStatus.nowStamp())",
                            "wake-heal"
                        )
                        callbacks.onRefresh(true)
                    }
                }
            } catch {
                HealCircuitBreaker.recordVerifyFail()
                DropLogger.logEvent("WAKE_HEAL ok=0 err=\(error.localizedDescription)")
                DispatchQueue.main.async {
                    callbacks.onNotify(
                        "myVPN ✕ После сна",
                        error.localizedDescription,
                        "wake-heal"
                    )
                    callbacks.onRefresh(true)
                }
            }
        }
    }
}
