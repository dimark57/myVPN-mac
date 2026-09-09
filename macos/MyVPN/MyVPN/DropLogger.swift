import Foundation

/// Background health DIFF logger + AUTO_* journal (doc-10 FDIR).
/// Uses: StatusSnapshot, DoctorStatus, AutoDoctor, DesiredStateStore, IncidentStore.
/// Hard DROP only on tun/nas; ICMP peer flaps stay FLAP-only.
enum DropLogger {
    static var logURL: URL {
        URL(fileURLWithPath: DoctorStatus.cacheDir + "/drops.log")
    }

    static var stateURL: URL {
        URL(fileURLWithPath: DoctorStatus.cacheDir + "/drop-state.json")
    }

    private static let maxLogLines = 800
    private static let flapWindowSeconds: TimeInterval = 45

    private static var confirmBaseline: Sample?
    private static var confirmCount = 0
    private static var confirmStartedAt: TimeInterval = 0
    private static var lastFlapChannels: String = ""
    private static var lastFlapAt: TimeInterval = 0
    private static var lastFlapCount = 0

    /// Active incident id after DROP_CONFIRMED until pipeline finishes.
    static var currentIncidentCid: String?

    static func logEvent(_ message: String) {
        let suffix: String
        if let cid = currentIncidentCid, !message.contains("cid=") {
            suffix = " cid=\(cid)"
        } else {
            suffix = ""
        }
        append("[\(isoNow())] \(message)\(suffix)\n")
    }

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
        /// Public IP non-empty (only meaningful after probe with includePublicIP).
        var egress: Bool

        static func from(_ s: StatusSnapshot) -> Sample {
            Sample(tun: s.tun, home: s.home, macbook: s.macbook, nas: s.nas, egress: !s.ip.isEmpty)
        }

        var dict: [String: Int] {
            [
                "tun": tun ? 1 : 0,
                "home": home ? 1 : 0,
                "macbook": macbook ? 1 : 0,
                "nas": nas ? 1 : 0,
                "egress": egress ? 1 : 0,
            ]
        }

        func softDropFrom(_ prev: Sample) -> Bool {
            (prev.home && !home) || (prev.macbook && !macbook)
        }

        func hardDropFrom(_ prev: Sample) -> Bool {
            (prev.tun && !tun)
                || (prev.nas && !nas)
                || (prev.tun && tun && prev.egress && !egress)
        }

        func hasDropFrom(_ prev: Sample) -> Bool {
            hardDropFrom(prev) || softDropFrom(prev)
        }

        func dropLabels(from prev: Sample, hardOnly: Bool) -> [String] {
            var drops: [String] = []
            if prev.tun && !tun { drops.append("VPN выключился") }
            if prev.tun && tun && prev.egress && !egress { drops.append("нет интернета через VPN") }
            if !hardOnly {
                if prev.home && !home { drops.append("домашний канал пропал") }
                if prev.macbook && !macbook { drops.append("macbook-peer не отвечает") }
            }
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
                nas: (obj["nas"] as? Int) == 1,
                egress: (obj["egress"] as? Int) == 1
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

    struct DropEvent {
        let body: String
        let cid: String
        let channels: [String]
        let intentionalOff: Bool
    }

    static func observe(_ snap: StatusSnapshot) -> DropEvent? {
        let cur = Sample.from(snap)
        defer { cur.save() }
        guard let prev = Sample.load() else { return nil }

        if prev != cur {
            logDiffOrFlap(prev: prev, cur: cur)
        }

        let hardEdge = cur.hardDropFrom(prev)
        let softOnly = cur.softDropFrom(prev) && !hardEdge
        if softOnly {
            return nil
        }

        if let base = confirmBaseline, !cur.hardDropFrom(base) {
            if confirmCount > 0 {
                append("[\(isoNow())] RECOVERED after confirm \(confirmCount)/\(AutoDoctor.dropConfirmNeeded)\n")
            }
            confirmBaseline = nil
            confirmCount = 0
            confirmStartedAt = 0
            return nil
        }

        if DesiredStateStore.isInGrace {
            if hardEdge {
                append("[\(isoNow())] CONFIRM skip=grace\n")
            }
            return nil
        }

        // Manual Off — never escalate CONFIRM/DROP (wake+Off used to spam 3/2 4/2).
        if !DesiredStateStore.desiredOn {
            if hardEdge {
                append("[\(isoNow())] CONFIRM skip=desired_off\n")
            }
            confirmBaseline = nil
            confirmCount = 0
            confirmStartedAt = 0
            return nil
        }

        if hardEdge {
            if confirmBaseline == nil {
                confirmBaseline = prev
                confirmStartedAt = Date().timeIntervalSince1970
            }
            if confirmCount < AutoDoctor.dropConfirmNeeded {
                confirmCount += 1
            }
            return maybeFire(cur: cur)
        }

        if let base = confirmBaseline, cur.hardDropFrom(base) {
            if confirmCount < AutoDoctor.dropConfirmNeeded {
                confirmCount += 1
            }
            return maybeFire(cur: cur)
        }

        return nil
    }

    private static func maybeFire(cur: Sample) -> DropEvent? {
        guard let base = confirmBaseline else { return nil }
        let need = AutoDoctor.dropConfirmNeeded
        let elapsed = Date().timeIntervalSince1970 - confirmStartedAt
        if confirmCount < need || elapsed < AutoDoctor.dropConfirmMinSeconds {
            append(
                "[\(isoNow())] CONFIRM \(confirmCount)/\(need) wall=\(Int(elapsed))с/\(Int(AutoDoctor.dropConfirmMinSeconds))с\n"
            )
            return nil
        }

        let intentionalOff = !DesiredStateStore.desiredOn && (base.tun && !cur.tun)
        let drops = cur.dropLabels(from: base, hardOnly: true)
        confirmBaseline = nil
        confirmCount = 0
        confirmStartedAt = 0
        guard !drops.isEmpty else { return nil }

        let cid = IncidentStore.newCid()
        currentIncidentCid = cid
        let channels = drops.map { label -> String in
            if label.contains("VPN") { return "tun" }
            if label.contains("интернета") { return "egress" }
            if label.contains("NAS") { return "nas" }
            return "other"
        }

        let stamp = DoctorStatus.nowStamp()
        let hint: String
        if intentionalOff {
            hint = "ручной Off — без автовосстановления."
        } else if AutoDoctor.autoDoctorEnabled {
            hint = AutoDoctor.autoHealEnabled
                ? "автодиагностика + восстановление…"
                : "автодиагностика…"
        } else {
            hint = "Жми «Диагностика»."
        }
        append("[\(isoNow())] DROP_CONFIRMED \(drops.joined(separator: ", ")) cid=\(cid)\n")
        let body = "\(drops.joined(separator: ", ")) · \(stamp). \(hint)"
        return DropEvent(body: body, cid: cid, channels: channels, intentionalOff: intentionalOff)
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
