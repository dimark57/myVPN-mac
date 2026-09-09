import Foundation

/// Heal circuit breaker / Safe Mode (doc-10 FDIR). Uses: DropLogger, AutoDoctor.
/// Closed → allow heals; Open (Safe Mode) → inhibit until human resume / user On.
enum HealCircuitBreaker {
    private static let stateKey = "local.myvpn.mac.healBreaker"
    private static let verifyFailsKey = "local.myvpn.mac.healVerifyFails"
    private static let openedAtKey = "local.myvpn.mac.healBreakerOpenedAt"

    enum State: String {
        case closed
        case open
        case halfOpen
    }

    static var state: State {
        get {
            let raw = UserDefaults.standard.string(forKey: stateKey) ?? State.closed.rawValue
            return State(rawValue: raw) ?? .closed
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: stateKey)
            if newValue == .open {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: openedAtKey)
            }
        }
    }

    static var isSafeMode: Bool { state == .open }

    private static var verifyFails: Int {
        get { UserDefaults.standard.integer(forKey: verifyFailsKey) }
        set { UserDefaults.standard.set(newValue, forKey: verifyFailsKey) }
    }

    /// Whether auto-heal may run (not Safe Mode, or half-open probe).
    static func canAttemptHeal() -> (ok: Bool, reason: String?) {
        switch state {
        case .closed:
            return (true, nil)
        case .halfOpen:
            return (true, nil)
        case .open:
            return (false, "safe_mode")
        }
    }

    static func recordVerifyPass() {
        verifyFails = 0
        if state != .closed {
            DropLogger.logEvent("SAFE_MODE exit=verify_pass")
        }
        state = .closed
    }

    /// After heal CLI ok but data-plane still bad, or heal threw.
    static func recordVerifyFail() {
        verifyFails += 1
        DropLogger.logEvent("HEAL_VERIFY fail=\(verifyFails)/\(AutoDoctor.verifyFailsToSafeMode)")
        if verifyFails >= AutoDoctor.verifyFailsToSafeMode {
            enterSafeMode(reason: "verify_fail_\(verifyFails)")
        } else if state == .halfOpen {
            state = .open
            DropLogger.logEvent("SAFE_MODE reentry=half_open_fail")
        }
    }

    static func recordBudgetExhausted() {
        enterSafeMode(reason: "heal_budget")
    }

    static func enterSafeMode(reason: String) {
        state = .open
        DropLogger.logEvent("SAFE_MODE enter reason=\(reason)")
    }

    /// Human resume from Settings or successful user On.
    static func resume(reason: String) {
        verifyFails = 0
        state = .closed
        DropLogger.logEvent("SAFE_MODE exit=\(reason)")
    }

    /// After cooldown, allow one probe heal.
    static func armHalfOpenIfDue() {
        guard state == .open else { return }
        let opened = UserDefaults.standard.double(forKey: openedAtKey)
        guard opened > 0 else { return }
        let elapsed = Date().timeIntervalSince1970 - opened
        if elapsed >= AutoDoctor.safeModeHoldSeconds {
            state = .halfOpen
            DropLogger.logEvent("SAFE_MODE half_open after=\(Int(elapsed))с")
        }
    }
}
