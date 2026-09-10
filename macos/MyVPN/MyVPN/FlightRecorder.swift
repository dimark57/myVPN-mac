import Foundation

/// L0 flight recorder ring (doc-10). Uses: StatusSnapshot, DoctorStatus.cacheDir.
enum FlightRecorder {
    static var url: URL {
        URL(fileURLWithPath: DoctorStatus.cacheDir + "/flight.jsonl")
    }

    private static let maxLines = 2000

    static func append(sample: StatusSnapshot, sessionCid: String, wake: Bool = false, pubEmpty: Bool = false) {
        try? FileManager.default.createDirectory(
            atPath: DoctorStatus.cacheDir,
            withIntermediateDirectories: true
        )
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        var obj: [String: Any] = [
            "ts": f.string(from: Date()),
            "cid": sessionCid,
            "layer": "L0",
            "tun": sample.tun ? 1 : 0,
            "home": sample.home ? 1 : 0,
            "macbook": sample.macbook ? 1 : 0,
            "nas": sample.nas ? 1 : 0,
            "wake": wake ? 1 : 0,
        ]
        if !sample.ip.isEmpty {
            obj["pub_cached"] = sample.ip
        }
        if pubEmpty {
            obj["pub_empty"] = 1
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        guard let bytes = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: bytes)
        } else {
            try? bytes.write(to: url)
        }
        trimIfNeeded()
    }

    /// Last N L0 samples for incident bundle.
    static func recentWindow(_ n: Int = 20) -> [[String: Any]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            return []
        }
        let lines = text.split(whereSeparator: \.isNewline).suffix(max(1, n))
        var out: [[String: Any]] = []
        for line in lines {
            if let data = String(line).data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                out.append(obj)
            }
        }
        return out
    }

    private static func trimIfNeeded() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard lines.count > maxLines else { return }
        let kept = Array(lines.suffix(maxLines)).joined(separator: "\n")
        try? ((kept.hasSuffix("\n") ? kept : kept + "\n")).write(to: url, atomically: true, encoding: .utf8)
    }
}
