import Foundation

/// Operator desired VPN state (doc-10 FDIR). Uses: DropLogger, AutoDoctor.
/// Commanded OFF = DNR — never auto-heal until user/auto-up wants ON.
enum DesiredStateStore {
    private static let desiredKey = "local.myvpn.mac.desiredOn"
    private static let graceUntilKey = "local.myvpn.mac.graceUntil"
    private static let intentionalOffAtKey = "local.myvpn.mac.intentionalOffAt"

    /// Default ON (nil → true) so first launch / upgrade keeps auto-up behavior.
    static var desiredOn: Bool {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: desiredKey) == nil { return true }
            return d.bool(forKey: desiredKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: desiredKey) }
    }

    static var graceUntil: TimeInterval {
        get { UserDefaults.standard.double(forKey: graceUntilKey) }
        set { UserDefaults.standard.set(newValue, forKey: graceUntilKey) }
    }

    static var isInGrace: Bool {
        let until = graceUntil
        return until > 0 && Date().timeIntervalSince1970 < until
    }

    /// Mark user/CLI wants VPN on (menu On, auto-up, successful heal up).
    static func setDesiredOn(graceSeconds: TimeInterval = AutoDoctor.postChangeGraceSeconds) {
        desiredOn = true
        UserDefaults.standard.removeObject(forKey: intentionalOffAtKey)
        enterGrace(seconds: graceSeconds)
        DropLogger.logEvent("DESIRED on=1 grace=\(Int(graceSeconds))с")
    }

    /// Mark intentional Off — inhibit TUN_DOWN auto-heal.
    static func setDesiredOff(graceSeconds: TimeInterval = AutoDoctor.postChangeGraceSeconds) {
        desiredOn = false
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: intentionalOffAtKey)
        enterGrace(seconds: graceSeconds)
        DropLogger.logEvent("DESIRED on=0 intentional_off=1 grace=\(Int(graceSeconds))с")
    }

    static func enterGrace(seconds: TimeInterval) {
        graceUntil = Date().timeIntervalSince1970 + max(0, seconds)
    }

    static func clearGrace() {
        graceUntil = 0
    }
}
