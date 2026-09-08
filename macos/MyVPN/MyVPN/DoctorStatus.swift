import Foundation

/// Last `myvpn doctor` snapshot for menu + user-facing notifications.
/// Uses: ~/.cache/myvpn-doctor/state.json, latest.txt
struct DoctorStatus: Equatable, Sendable {
    var primary: String = ""
    var overall: String = ""
    var confidence: String = ""
    var ts: String = ""
    var home: Bool = false
    var nas: Bool = false
    var egressMacbook: Bool = false

    var hasResult: Bool { !primary.isEmpty }

    /// App-layer codes: menu «Незначительные», heal всё равно по PRIMARY (doc-9).
    static let warnPrimaries: Set<String> = [
        "NAS_STALE", "NAS_MOUNT_ONLY", "DNS_STALE", "EGRESS_NOT_VIA_MACBOOK",
    ]

    /// Short menu badge (not the long notification headline).
    var primaryLine: String {
        if primary.isEmpty { return "—" }
        return menuBadge
    }

    var detailLine: String? {
        guard hasResult else { return nil }
        let stamp = displayStamp
        return stamp.isEmpty ? nil : stamp
    }

    /// One-line right status (legacy/tech). Prefer `menuSeverityDetail` in menu bar.
    var rowDetail: String { menuSeverityDetail }

    private static func clockOnly(_ stamp: String) -> String {
        // "08.09 11:43" → "11:43"
        if let sp = stamp.split(separator: " ").last, sp.contains(":") {
            return String(sp)
        }
        return stamp
    }

    /// Menu detail under «Провести диагностику»: Без ошибок / Незначительные… / Значительные…
    var severityLabel: String {
        if primary.isEmpty { return "нет данных" }
        switch overall {
        case "PASS": return "Без ошибок"
        case "WARN": return "Незначительные ошибки"
        case "FAIL": return "Значительные ошибки"
        default:
            if primary.hasPrefix("HEALTHY_BUT") { return "Незначительные ошибки" }
            if primary.hasPrefix("HEALTHY") { return "Без ошибок" }
            return "Значительные ошибки"
        }
    }

    /// Compact technical badge (settings / logs).
    var menuBadge: String {
        switch primary {
        case "HEALTHY", "HEALTHY_ICMP_FALSE_ALARM":
            return "ок"
        case "HEALTHY_BUT_ENDPOINT_VIA_TUN":
            return "WARN · endpoint→utun"
        case "TUN_DOWN":
            return "FAIL · VPN off"
        case "MACBOOK_EGRESS_DOWN":
            return "FAIL · нет интернета"
        case "HOME_PEER_DOWN":
            return "FAIL · home down"
        case "HOME_DOWN_MACBOOK_OK":
            return "FAIL · home down"
        case "NAS_STALE":
            return "WARN · NAS stale"
        case "NAS_MOUNT_ONLY":
            return "WARN · NAS unmounted"
        case "DNS_STALE":
            return "WARN · DNS"
        case "CONFLICT_WG_APP":
            return "FAIL · WG.app conflict"
        case "EGRESS_NOT_VIA_MACBOOK":
            return "WARN · egress"
        case "MIXED":
            return "WARN · mixed"
        default:
            return overall.isEmpty ? primary : "\(overall) · \(String(primary.prefix(24)))"
        }
    }

    /// Right-side menu detail: severity (+ time if known).
    var menuSeverityDetail: String {
        if primary.isEmpty { return severityLabel }
        let time = detailLine.map(Self.clockOnly) ?? ""
        return time.isEmpty ? severityLabel : "\(severityLabel) · \(time)"
    }

    var displayStamp: String {
        if !ts.isEmpty { return Self.shortStamp(ts) }
        return Self.nowStamp()
    }

    var userHeadline: String {
        switch primary {
        case "HEALTHY", "HEALTHY_ICMP_FALSE_ALARM":
            return "Всё в порядке"
        case "HEALTHY_BUT_ENDPOINT_VIA_TUN":
            return "Работает, есть риск отвала"
        case "TUN_DOWN":
            return "VPN выключен"
        case "MACBOOK_EGRESS_DOWN":
            return "Нет интернета через VPN"
        case "HOME_PEER_DOWN", "HOME_DOWN_MACBOOK_OK":
            return "Домашний канал недоступен"
        case "NAS_STALE", "NAS_MOUNT_ONLY":
            return "Проблема с NAS"
        case "DNS_STALE":
            return "Сбились DNS"
        case "CONFLICT_WG_APP":
            return "Конфликт с WireGuard.app"
        case "EGRESS_NOT_VIA_MACBOOK":
            return "Необычный маршрут интернета"
        case "MIXED":
            return "Смешанная картина"
        default:
            return primary.isEmpty ? "Нет данных" : "Нужна проверка"
        }
    }

    var userBody: String {
        let t = displayStamp
        switch primary {
        case "HEALTHY", "HEALTHY_ICMP_FALSE_ALARM":
            return "VPN и NAS работают нормально. \(t)"
        case "HEALTHY_BUT_ENDPOINT_VIA_TUN":
            return "Сейчас всё доступно, но маршрут к серверам VPN идёт через туннель. После сна или смены сети соединение может отвалиться. \(t)"
        case "TUN_DOWN":
            return "Sing-box не запущен. Нажми «Включить». \(t)"
        case "MACBOOK_EGRESS_DOWN":
            return "Туннель есть, но интернет через macbook не проходит. Попробуй Выключить → Включить. \(t)"
        case "HOME_DOWN_MACBOOK_OK":
            return "Интернет есть, а домашний канал (NAS/Hub) нет. Часто после сна. Выключить → Включить. \(t)"
        case "HOME_PEER_DOWN":
            return "Домашний VPN-peer не отвечает — NAS и внутренние сервисы недоступны. \(t)"
        case "NAS_STALE":
            return "Диск NAS «завис». Нажми «Перемонтировать NAS». \(t)"
        case "NAS_MOUNT_ONLY":
            return "Сеть до NAS есть, том не смонтирован. Нажми «Смонтировать NAS». \(t)"
        case "DNS_STALE":
            return "DNS Wi‑Fi не указывает на VPN. В терминале: myvpn flush-dns. \(t)"
        case "CONFLICT_WG_APP":
            return "Одновременно включены WireGuard.app и myVPN — выключи туннели в WireGuard.app. \(t)"
        case "EGRESS_NOT_VIA_MACBOOK":
            return "Интернет идёт не через ожидаемый VPN-сервер. Повтори диагностику. \(t)"
        case "MIXED":
            return "Смотри отчёт в Настройки → Диагностика / ~/.cache/myvpn-doctor/latest.txt. \(t)"
        default:
            return "Код: \(primary.isEmpty ? "—" : primary). \(t)"
        }
    }

    /// Notification title + body for Notification Center.
    var notificationPair: (title: String, body: String) {
        let mark: String
        switch overall {
        case "PASS": mark = "✓"
        case "WARN": mark = "⚠"
        case "FAIL": mark = "✕"
        default: mark = "·"
        }
        return ("myVPN \(mark) \(userHeadline)", userBody)
    }

    static var cacheDir: String {
        NSHomeDirectory() + "/.cache/myvpn-doctor"
    }

    static var stateURL: URL {
        URL(fileURLWithPath: cacheDir + "/state.json")
    }

    static var latestURL: URL {
        URL(fileURLWithPath: cacheDir + "/latest.txt")
    }

    static func load() -> DoctorStatus {
        let url = stateURL
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DoctorStatus()
        }
        var s = DoctorStatus()
        s.primary = obj["primary"] as? String ?? ""
        s.ts = obj["ts"] as? String ?? ""
        s.home = (obj["home"] as? Int).map { $0 == 1 } ?? false
        s.nas = (obj["nas"] as? Int).map { $0 == 1 } ?? false
        s.egressMacbook = (obj["egress_via_macbook"] as? Int).map { $0 == 1 } ?? false
        if s.primary.hasPrefix("HEALTHY_BUT") {
            s.overall = "WARN"
            s.confidence = "medium"
        } else if s.primary.hasPrefix("HEALTHY") {
            s.overall = "PASS"
            s.confidence = "high"
        } else if Self.warnPrimaries.contains(s.primary) {
            s.overall = "WARN"
            s.confidence = "medium"
        } else if !s.primary.isEmpty {
            s.overall = "FAIL"
            s.confidence = "—"
        }
        if let latest = try? String(contentsOf: latestURL, encoding: .utf8) {
            for raw in latest.split(whereSeparator: \.isNewline) {
                let line = String(raw).trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("PRIMARY:") {
                    s.primary = line.replacingOccurrences(of: "PRIMARY:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("CONFIDENCE:") {
                    s.confidence = line.replacingOccurrences(of: "CONFIDENCE:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("OVERALL:") {
                    let rest = line.replacingOccurrences(of: "OVERALL:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    s.overall = rest.split(separator: " ").first.map(String.init) ?? rest
                }
            }
        }
        return s
    }

    static func nowStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private static func shortStamp(_ iso: String) -> String {
        let parts = iso.split(separator: "T")
        guard parts.count == 2 else { return iso }
        let d = parts[0].split(separator: "-")
        guard d.count == 3 else { return iso }
        let time = parts[1].prefix(5)
        return "\(d[2]).\(d[1]) \(time)"
    }
}
