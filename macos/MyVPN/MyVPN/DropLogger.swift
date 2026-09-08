import Foundation

/// Background health DIFF logger + AUTO_* journal. Uses: StatusSnapshot, DoctorStatus cache dir, AutoDoctor.
enum DropLogger {
    static var logURL: URL {
        URL(fileURLWithPath: DoctorStatus.cacheDir + "/drops.log")
    }

    static var stateURL: URL {
        URL(fileURLWithPath: DoctorStatus.cacheDir + "/drop-state.json")
    }

    /// Append a free-form journal line (AUTO_DOCTOR / AUTO_HEAL / …).
    static func logEvent(_ message: String) {
        let line = "[\(isoNow())] \(message)\n"
        append(line)
    }

    /// Last N lines of drops.log for Settings → Диагностика.
    static func tailLines(_ n: Int = 12) -> String {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8), !text.isEmpty else {
            return "(журнал пуст)"
        }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let slice = lines.suffix(max(1, n))
        return slice.joined(separator: "\n")
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

    /// Compare with previous sample; append DIFF lines. Returns user notify body if significant drop.
    static func observe(_ snap: StatusSnapshot) -> String? {
        let cur = Sample.from(snap)
        defer { cur.save() }
        guard let prev = Sample.load() else { return nil }
        guard prev != cur else { return nil }

        var diffs: [String] = []
        if prev.tun != cur.tun { diffs.append("tun \(prev.tun ? 1 : 0)→\(cur.tun ? 1 : 0)") }
        if prev.home != cur.home { diffs.append("home \(prev.home ? 1 : 0)→\(cur.home ? 1 : 0)") }
        if prev.macbook != cur.macbook { diffs.append("macbook \(prev.macbook ? 1 : 0)→\(cur.macbook ? 1 : 0)") }
        if prev.nas != cur.nas { diffs.append("nas \(prev.nas ? 1 : 0)→\(cur.nas ? 1 : 0)") }
        guard !diffs.isEmpty else { return nil }

        let stamp = DoctorStatus.nowStamp()
        let line = "[\(isoNow())] DIFF \(diffs.joined(separator: " · "))\n"
        append(line)

        // Notify only on real drops (1→0), not recoveries.
        var drops: [String] = []
        if prev.tun && !cur.tun { drops.append("VPN выключился") }
        if prev.home && !cur.home { drops.append("домашний канал пропал") }
        if prev.macbook && !cur.macbook { drops.append("macbook-peer не отвечает") }
        if prev.nas && !cur.nas { drops.append("NAS отключился") }
        guard !drops.isEmpty else { return nil }
        let hint: String
        if AutoDoctor.autoDoctorEnabled {
            hint = AutoDoctor.autoHealEnabled
                ? "автодиагностика + восстановление…"
                : "автодиагностика…"
        } else {
            hint = "Жми «Диагностика»."
        }
        return "\(drops.joined(separator: ", ")) · \(stamp). \(hint)"
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
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}
