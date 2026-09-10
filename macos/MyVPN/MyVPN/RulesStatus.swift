import Foundation

/// Last-updated for RU rule sets (doc-7). Reads mtime only — no secrets.
struct RulesStatus: Equatable, Sendable {
    var geosite: Date?
    var geoip: Date?

    private static var rulesDir: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".config/myvpn/rules", isDirectory: true)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    static func load() -> RulesStatus {
        RulesStatus(
            geosite: mtime(stem: "geosite-ru"),
            geoip: mtime(stem: "geoip-ru")
        )
    }

    private static func mtime(stem: String) -> Date? {
        let dir = rulesDir
        let candidates = ["\(stem).srs", "\(stem).json"].map { dir.appendingPathComponent($0) }
        let fm = FileManager.default
        var best: Date?
        for url in candidates {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let date = attrs[.modificationDate] as? Date else { continue }
            if best == nil || date > best! { best = date }
        }
        return best
    }

    func line(name: String, date: Date?) -> String {
        if let date {
            return "\(name): \(Self.dateFormatter.string(from: date))"
        }
        return "\(name): нет"
    }

    var geositeLine: String { line(name: "geosite-ru", date: geosite) }
    var geoipLine: String { line(name: "geoip-ru", date: geoip) }

    var updatedSummary: String? {
        let dates = [geosite, geoip].compactMap { $0 }
        guard let latest = dates.max() else { return nil }
        return "Обновлено: \(Self.dateFormatter.string(from: latest))"
    }

    /// Short stamp for notification body after update-rules.
    var notifyStamp: String {
        let dates = [geosite, geoip].compactMap { $0 }
        guard let latest = dates.max() else { return "готово" }
        return Self.dateFormatter.string(from: latest)
    }

    /// Compact menu detail: `08.09` or `нет`.
    var menuBadge: String {
        let dates = [geosite, geoip].compactMap { $0 }
        guard let latest = dates.max() else { return "нет" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM"
        return f.string(from: latest)
    }
}
