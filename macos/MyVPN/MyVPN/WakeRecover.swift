import Foundation

/// Soft recover after `NSWorkspace.didWake` (doc-10 / 0.5.7).
/// Uses: DesiredStateStore, AutoDoctor, MyVPNCLI, DropLogger, FlightRecorder, StatusSnapshot.
/// Channel-first: L0 → restart (no mount in helper) if egress dead → pin → always NAS remount if channel live.
/// Soft-success if helper times out but L0 already green.
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

            // L0 after settle — channel probe before any NAS work (0.5.4).
            var snap = MyVPNCLI.status(includePublicIP: true)
            FlightRecorder.append(sample: snap, sessionCid: sessionCid, wake: true)
            DropLogger.logEvent(
                "WAKE_L0 tun=\(snap.tun ? 1 : 0) home=\(snap.home ? 1 : 0) macbook=\(snap.macbook ? 1 : 0) nas=\(snap.nas ? 1 : 0) ip=\(snap.ip.isEmpty ? "-" : "ok")"
            )
            DispatchQueue.main.async { callbacks.onSnapshot(snap) }

            // SLEEP_WAKE_STALE: tun up but no usable internet (need both ip empty AND macbook down).
            // Do not restart on macbook-ICMP-only flaps when public IP already ok (0.5.7).
            var didRestart = false
            let egressDead = snap.tun && snap.ip.isEmpty && !snap.macbook
            if AutoDoctor.autoHealEnabled, egressDead {
                didRestart = performWakeHeal(callbacks: callbacks)
                snap = MyVPNCLI.status(includePublicIP: true)
                DispatchQueue.main.async { callbacks.onSnapshot(snap) }
            } else if snap.tun, !snap.ip.isEmpty, !snap.macbook {
                // Old criterion (ip empty OR !macbook) would have restarted — skip ICMP-only flap.
                DropLogger.logEvent("WAKE_HEAL skip=ip_ok_icmp_flap")
            }

            // Pin only if we did not just restart (up already pins).
            if !didRestart {
                do {
                    try MyVPNCLI.pinEndpoints()
                    DropLogger.logEvent("WAKE_PIN ok=1")
                } catch {
                    DropLogger.logEvent("WAKE_PIN ok=0 err=\(error.localizedDescription)")
                }
            }

            // NAS when channel alive — always remount (0.5.6): L0 nas=1 can be stale SMB ghost.
            let channelLive = snap.tun && (snap.home || snap.macbook)
            let wantNAS = MyVPNCLI.autoNASEnabled() || AutoDoctor.autoHealEnabled
            if wantNAS {
                if !channelLive {
                    DropLogger.logEvent("WAKE_NAS skip=no_channel")
                } else {
                    let reason = snap.nas ? "remount_stale_ok" : "missing"
                    DropLogger.logEvent("WAKE_NAS mount-nas --safe reason=\(reason)")
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
                            } else {
                                callbacks.onNotify(
                                    "myVPN · NAS после сна",
                                    "mount выполнен, том ещё не виден · \(DoctorStatus.nowStamp())",
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
            }

            DispatchQueue.main.async { callbacks.onRefresh(true) }
        }
    }

    /// One SLEEP_WAKE_STALE restart (tunnel only — NAS remounted after). Returns true if heal ran.
    @discardableResult
    private static func performWakeHeal(callbacks: Callbacks) -> Bool {
        let primary = "SLEEP_WAKE_STALE"
        // Mount is WakeRecover's job after channel is up — keep helper call short (0.5.7).
        let kind = AutoDoctor.HealKind.restart
        let gate = AutoDoctor.canHealNow(primary: primary, kind: kind)
        guard gate.ok else {
            DropLogger.logEvent("WAKE_HEAL skip=\(gate.reason ?? "gate") primary=\(primary)")
            DispatchQueue.main.async {
                callbacks.onNotify(
                    "myVPN · Wake heal отложен",
                    "\(gate.reason ?? "cooldown") · \(DoctorStatus.nowStamp())",
                    "wake-heal"
                )
            }
            return false
        }

        DropLogger.logEvent("WAKE_HEAL primary=\(primary) action=\(AutoDoctor.kindLabel(kind))")
        DispatchQueue.main.async {
            callbacks.onNotify(
                "myVPN · После сна",
                "Восстанавливаю туннель · \(DoctorStatus.nowStamp())",
                "wake-heal"
            )
        }

        var healError: String?
        do {
            try AutoDoctor.performHeal(kind)
        } catch {
            healError = error.localizedDescription
        }

        DesiredStateStore.setDesiredOn()
        // Soft-success: helper may timeout (45s) after tunnel is already green (0.5.7).
        let snap = MyVPNCLI.status(includePublicIP: true)
        let softOK = snap.tun && (!snap.ip.isEmpty || snap.macbook)

        if softOK {
            AutoDoctor.recordHeal(kind: kind, primary: primary, verified: true)
            let softTag = healError != nil ? " soft=1" : ""
            DropLogger.logEvent(
                "WAKE_HEAL ok=1 verify=1\(softTag) primary=\(primary)\(healError.map { " err=\($0)" } ?? "")"
            )
            DispatchQueue.main.async {
                callbacks.onNotify(
                    "myVPN ✓ После сна",
                    "Туннель восстановлен · \(DoctorStatus.nowStamp())",
                    "wake-heal"
                )
            }
            return true
        }

        HealCircuitBreaker.recordVerifyFail()
        let msg = healError ?? "Heal не подтвердился"
        DropLogger.logEvent("WAKE_HEAL ok=0 verify=0 primary=\(primary) err=\(msg)")
        DispatchQueue.main.async {
            callbacks.onNotify(
                "myVPN ✕ После сна",
                "\(msg) · \(DoctorStatus.nowStamp())",
                "wake-heal"
            )
        }
        return true
    }
}
