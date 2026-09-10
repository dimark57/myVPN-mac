import Foundation

/// Per-DROP incident bundle for RCA (doc-10). Uses: DoctorStatus, FlightRecorder, DropLogger.
enum IncidentStore {
    static var dir: String { DoctorStatus.cacheDir + "/incidents" }

    private static let maxIncidents = 50

    static func newCid() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let hex = String(format: "%04x", UInt16.random(in: 0...0xFFFF))
        return "inc_\(f.string(from: Date()))_\(hex)"
    }

    static func begin(cid: String, channels: [String], sessionCid: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let obj: [String: Any] = [
            "cid": cid,
            "session_cid": sessionCid,
            "ts_start": f.string(from: Date()),
            "trigger": "DROP_CONFIRMED",
            "channels": channels,
            "l0_window": FlightRecorder.recentWindow(20),
            "l1": NSNull(),
            "heal": NSNull(),
            "l2_ref": NSNull(),
            "report_path": DoctorStatus.latestURL.path,
        ]
        write(cid: cid, obj: obj)
        DropLogger.logEvent("INCIDENT begin cid=\(cid)")
        trimOld()
    }

    static func attachL1(
        cid: String,
        primary: String,
        overall: String,
        ms: Int,
        layer: String = "L1",
        killed: Bool = false
    ) {
        var obj = load(cid: cid) ?? ["cid": cid]
        obj["l1"] = [
            "primary": primary,
            "overall": overall,
            "layer": layer,
            "ms": ms,
            "killed": killed ? 1 : 0,
        ]
        obj["report_path"] = DoctorStatus.latestURL.path
        write(cid: cid, obj: obj)
    }

    static func attachHeal(cid: String, attempted: Bool, ok: Int?, action: String, skipped: String?) {
        var obj = load(cid: cid) ?? ["cid": cid]
        var heal: [String: Any] = [
            "attempted": attempted,
            "action": action,
        ]
        if let ok { heal["ok"] = ok }
        if let skipped { heal["skipped"] = skipped }
        obj["heal"] = heal
        write(cid: cid, obj: obj)
    }

    /// Wall-clock ms since INCIDENT begin (DROP → end, or until L0 green if already recovered).
    static func elapsedMs(cid: String) -> Int {
        guard let obj = load(cid: cid), let ts = obj["ts_start"] as? String else { return 0 }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let start = f.date(from: ts) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    /// Close incident: ts_end, outcome, recovery_ms, l1.killed. Never leave heal: null after begin.
    static func end(cid: String, outcome: String, recoveryMs: Int, killed: Bool = false) {
        var obj = load(cid: cid) ?? ["cid": cid]
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        obj["ts_end"] = f.string(from: Date())
        obj["outcome"] = outcome
        obj["recovery_ms"] = recoveryMs
        let alreadyKilled = ((obj["l1"] as? [String: Any])?["killed"] as? Int) == 1
        let flag = killed || alreadyKilled
        if var l1 = obj["l1"] as? [String: Any] {
            l1["killed"] = flag ? 1 : 0
            obj["l1"] = l1
        } else if flag {
            obj["l1"] = ["killed": 1]
        }
        if obj["heal"] == nil || obj["heal"] is NSNull {
            obj["heal"] = [
                "attempted": false,
                "action": "none",
                "skipped": outcome,
            ]
        }
        write(cid: cid, obj: obj)
        DropLogger.logEvent("INCIDENT end cid=\(cid) outcome=\(outcome) recovery_ms=\(recoveryMs)")
    }

    static func path(cid: String) -> String {
        "\(dir)/\(cid).json"
    }

    private static func load(cid: String) -> [String: Any]? {
        let p = path(cid: cid)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private static func write(cid: String, obj: [String: Any]) {
        let p = path(cid: cid)
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: p), options: .atomic)
        }
    }

    private static func trimOld() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }
        let jsons = files.filter { $0.hasSuffix(".json") }.sorted()
        guard jsons.count > maxIncidents else { return }
        for name in jsons.prefix(jsons.count - maxIncidents) {
            try? fm.removeItem(atPath: "\(dir)/\(name)")
        }
    }
}
