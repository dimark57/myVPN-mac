import Foundation

/// Background health DIFF logger + AUTO_* journal. Uses: StatusSnapshot, DoctorStatus cache dir, AutoDoctor.
/// Hysteresis (N confirms across polls) + flap coalesce — Cloudflare WAN / MikroTik patterns.
enum DropLogger {
    static var logURL: URL {
        URL(fileURLWithPath: DoctorStatus.cacheDir + "/drops.log")
    }

    static var stateURL: URL {
        URL(fileURLWithPath: DoctorStatus.cacheDir + "/drop-state.json")
    }

    private static let maxLogLines = 800
    private static let flapWindowSeconds: TimeInterval = 45

    /// Healthy sample before the current drop streak (hysteresis baseline).
    private static var confirmBaseline: Sample?
    private static var confirmCount = 0
    private static var lastFlapChannels: String = ""
    private static var lastFlapAt: TimeInterval = 0
    private static var lastFlapCount = 0

    /// Append a free-form journal line (AUTO_DOCTOR / AUTO_HEAL / …).
    static func logEvent(_ message: String) {
        append("[\(isoNow())] \(message)\n")
    }

    /// Last N lines of drops.log for Settings → Диагностика.
    static func tailLines(_ n: Int = 12) -> String {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8), !text.isEmpty else {
            return "(журнал пуст)"
        }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return lines.suffix(max(1, n)).joined(separator: "\n")
    }

    struct Sample: Equatable {
        var tun: Bool
        var home: Bool
        var macbook: Bool
        var nas: Bool

        static func from(_ s: StatusSnapshot) -> Sample {
            Sample(tun: s.tun, home: s.home, macbook: s.macbook, nas: s.nas)
        }

        var dict: [String: Int] {
            ["tun": tun ? 1 : 0, "home": home ? 1 : 0, "macbook": macbook ? 1 : 0, "nas": nas ? 1 : 0]
        }

        func hasDropFrom(_ prev: Sample) -> Bool {
            (prev.tun && !tun) || (prev.home && !home) || (prev.macbook && !macbook) || (prev.nas && !nas)
        }

        func dropLabels(from prev: Sample) -> [String] {
            var drops: [String] = []
            if prev.tun && !tun { drops.append("VPN выключился") }
            if prev.home && !home { drops.append("домашний канал пропал") }
            if prev.macbook && !macbook { drops.append("macbook-peer не отвечает") }
            if prev.nas && !nas { drops.append("NAS отключился") }
            return drops
        }

        static func load() -> Sample? {
            guard let data = try? Data(contentsOf: stateURL),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return Sample(
                tun: (obj["tun"] as? Int) == 1,
                home: (obj["home"] as? Int) == 1,
                macbook: (obj["macbook"] as? Int) == 1,
                nas: (obj["nas"] as? Int) == 1
            )
        }

        func save() {
            try? FileManager.default.createDirectory(
                atPath: DoctorStatus.cacheDir,
                withIntermediateDirectories: true
            )
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
                try? data.write(to: stateURL, options: .atomic)
            }
        }
    }

    /// Compare with previous sample; coalesce flaps; notify only after N confirms (incl. stable-bad polls).
    static func observe(_ snap: StatusSnapshot) -> String? {
        let cur = Sample.from(snap)
        defer { cur.save() }
        guard let prev = Sample.load() else { return nil }

        if prev != cur {
            logDiffOrFlap(prev: prev, cur: cur)
        }

        // Recovery clears hysteresis.
        if let base = confirmBaseline, !cur.hasDropFrom(base) {
            if confirmCount > 0 {
                append("[\(isoNow())] RECOVERED after confirm \(confirmCount)/\(AutoDoctor.dropConfirmNeeded)\n")
            }
            confirmBaseline = nil
            confirmCount = 0
            return nil
        }

        // New drop vs last saved sample → start / continue streak.
        if cur.hasDropFrom(prev) {
            if confirmBaseline == nil {
                confirmBaseline = prev
            }
            confirmCount += 1
            return maybeFire(cur: cur)
        }

        // Still bad vs baseline on a stable poll (prev==cur) — counts toward N (Cloudflare retry).
        if let base = confirmBaseline, cur.hasDropFrom(base) {
            confirmCount += 1
            return maybeFire(cur: cur)
        }

        return nil
    }

    private static func maybeFire(cur: Sample) -> String? {
        guard let base = confirmBaseline else { return nil }
        let need = AutoDoctor.dropConfirmNeeded
        if confirmCount < need {
            append("[\(isoNow())] CONFIRM \(confirmCount)/\(need)\n")
            return nil
        }
        let drops = cur.dropLabels(from: base)
        confirmBaseline = nil
        confirmCount = 0
        guard !drops.isEmpty else { return nil }

        let stamp = DoctorStatus.nowStamp()
        let hint: String
        if AutoDoctor.autoDoctorEnabled {
            hint = AutoDoctor.autoHealEnabled
                ? "автодиагностика + восстановление…"
                : "автодиагностика…"
        } else {
            hint = "Жми «Диагностика»."
        }
        append("[\(isoNow())] DROP_CONFIRMED \(drops.joined(separator: ", "))\n")
        return "\(drops.joined(separator: ", ")) · \(stamp). \(hint)"
    }

    private static func logDiffOrFlap(prev: Sample, cur: Sample) {
        var diffs: [String] = []
        if prev.tun != cur.tun { diffs.append("tun \(prev.tun ? 1 : 0)→\(cur.tun ? 1 : 0)") }
        if prev.home != cur.home { diffs.append("home \(prev.home ? 1 : 0)→\(cur.home ? 1 : 0)") }
        if prev.macbook != cur.macbook { diffs.append("macbook \(prev.macbook ? 1 : 0)→\(cur.macbook ? 1 : 0)") }
        if prev.nas != cur.nas { diffs.append("nas \(prev.nas ? 1 : 0)→\(cur.nas ? 1 : 0)") }
        guard !diffs.isEmpty else { return }

        let channels = diffs.compactMap { $0.split(separator: " ").first.map(String.init) }.sorted().joined(separator: ",")
        let now = Date().timeIntervalSince1970
        let detail = diffs.joined(separator: " · ")
        if channels == lastFlapChannels, now - lastFlapAt < flapWindowSeconds {
            lastFlapCount += 1
            lastFlapAt = now
            rewriteLastAsFlap(channels: channels, count: lastFlapCount, detail: detail)
        } else {
            lastFlapChannels = channels
            lastFlapCount = 1
            lastFlapAt = now
            append("[\(isoNow())] DIFF \(detail)\n")
        }
    }

    private static func rewriteLastAsFlap(channels: String, count: Int, detail: String) {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8), !text.isEmpty else {
            append("[\(isoNow())] FLAP \(channels) ×\(count) · \(detail)\n")
            return
        }
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        if let last = lines.last,
           last.contains(" DIFF ") || last.contains(" FLAP ") || last.contains(" CONFIRM ") {
            lines.removeLast()
        }
        lines.append("[\(isoNow())] FLAP \(channels) ×\(count) · \(detail)")
        try? (lines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        trimIfNeeded()
    }

    private static func append(_ line: String) {
        try? FileManager.default.createDirectory(
            atPath: DoctorStatus.cacheDir,
            withIntermediateDirectories: true
        )
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
        trimIfNeeded()
    }

    private static func trimIfNeeded() {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard lines.count > maxLogLines else { return }
        let kept = Array(lines.suffix(maxLogLines)).joined(separator: "\n")
        try? ((kept.hasSuffix("\n") ? kept : kept + "\n")).write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}
