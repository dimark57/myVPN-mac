import AppKit
import CryptoKit
import Foundation

/// GitHub Releases updater for ~/Applications/myVPN.app
/// Uses: api.github.com/repos/dimark57/myVPN-mac/releases/latest, DropLogger, SingleInstance
enum UpdateChecker {
    static let repo = "dimark57/myVPN-mac"
    static let assetName = "myVPN.app.zip"
    static let checksumAssetName = "myVPN.app.zip.sha256"

    private static let autoCheckKey = "local.myvpn.mac.update.autoCheck"
    private static let autoInstallKey = "local.myvpn.mac.update.autoInstall"

    /// Check on launch + hourly. Default on.
    static var autoCheckEnabled: Bool {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: autoCheckKey) == nil { return true }
            return d.bool(forKey: autoCheckKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    /// If newer found during auto-check, install without prompt. Default on.
    static var autoInstallEnabled: Bool {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: autoInstallKey) == nil { return true }
            return d.bool(forKey: autoInstallKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoInstallKey) }
    }

    struct Result: Sendable {
        var current: String
        var latest: String?
        var releaseURL: URL?
        var assetURL: URL?
        /// Lowercase hex SHA-256 of zip (from sidecar or GitHub digest). Nil = not published.
        var sha256: String?
        var upToDate: Bool
        var message: String
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Menu detail: `v0.3.1` or `v0.3.1 (доступна v0.4.0)`.
    static func menuDetail(latest: String?, upToDate: Bool) -> String {
        let cur = "v\(currentVersion)"
        guard let latest, !latest.isEmpty, !upToDate else { return cur }
        return "\(cur) (доступна v\(latest))"
    }

    static func menuDetail(from result: Result?) -> String {
        guard let result else { return "v\(currentVersion)" }
        return menuDetail(latest: result.latest, upToDate: result.upToDate)
    }

    static func check() async -> Result {
        let current = currentVersion
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: api, timeoutInterval: 20)
        req.setValue("myVPN/\(current)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return Result(
                    current: current,
                    latest: nil,
                    releaseURL: URL(string: "https://github.com/\(repo)/releases"),
                    assetURL: nil,
                    sha256: nil,
                    upToDate: true,
                    message: "v\(current) · релизов на GitHub пока нет"
                )
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return Result(current: current, latest: nil, releaseURL: nil, assetURL: nil, sha256: nil, upToDate: true,
                             message: "Не удалось проверить обновления")
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Result(current: current, latest: nil, releaseURL: nil, assetURL: nil, sha256: nil, upToDate: true,
                             message: "Неверный ответ GitHub")
            }
            let tag = ((obj["tag_name"] as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let html = obj["html_url"] as? String
            var asset: URL?
            var shaURL: URL?
            var digestSHA: String?
            if let assets = obj["assets"] as? [[String: Any]] {
                for a in assets {
                    guard let name = a["name"] as? String else { continue }
                    if name == assetName, let u = a["browser_download_url"] as? String {
                        asset = URL(string: u)
                        digestSHA = normalizeSHA256(a["digest"] as? String)
                    } else if name == checksumAssetName, let u = a["browser_download_url"] as? String {
                        shaURL = URL(string: u)
                    }
                }
            }
            var sha256 = digestSHA
            if sha256 == nil, let shaURL {
                sha256 = await fetchSidecarSHA256(shaURL)
            }
            let newer = isNewer(tag, than: current)
            if !newer {
                return Result(current: current, latest: tag, releaseURL: html.flatMap(URL.init), assetURL: asset,
                              sha256: sha256, upToDate: true, message: "v\(current) · обновлений нет")
            }
            return Result(current: current, latest: tag, releaseURL: html.flatMap(URL.init), assetURL: asset,
                          sha256: sha256, upToDate: false,
                          message: "Доступна v\(tag) (сейчас v\(current))")
        } catch {
            return Result(current: current, latest: nil, releaseURL: nil, assetURL: nil, sha256: nil, upToDate: true,
                          message: "Ошибка сети: \(error.localizedDescription)")
        }
    }

    /// Download zip, verify SHA-256 when known, replace ~/Applications/myVPN.app, relaunch.
    static func install(from assetURL: URL, expectedSHA256: String? = nil) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("myvpn-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let zipURL = tmp.appendingPathComponent(assetName)
        let (bytes, resp) = try await URLSession.shared.data(from: assetURL)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }

        let got = sha256Hex(bytes)
        if let expected = expectedSHA256, !expected.isEmpty {
            guard got == expected.lowercased() else {
                DropLogger.logEvent("UI_UPDATE checksum_fail want=\(expected.prefix(12))… got=\(got.prefix(12))…")
                throw UpdateError.checksumMismatch
            }
            DropLogger.logEvent("UI_UPDATE checksum_ok sha256=\(got.prefix(12))…")
        } else {
            // Pre-0.5.9 releases had no sidecar; still log for flight recorder.
            DropLogger.logEvent("UI_UPDATE checksum_skip reason=no_digest sha256=\(got.prefix(12))…")
        }

        try bytes.write(to: zipURL)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, tmp.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw UpdateError.unzipFailed }

        let extracted = tmp.appendingPathComponent("myVPN.app")
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw UpdateError.missingApp
        }

        let dest = URL(fileURLWithPath: NSHomeDirectory() + "/Applications/myVPN.app")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: extracted, to: dest)

        // Ad-hoc re-sign (Gatekeeper may still warn without Developer ID).
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--deep", "--sign", "-", dest.path]
        try? sign.run()
        sign.waitUntilExit()

        // UI-only handoff (0.5.8): quit other menu-bar processes, then open new binary.
        let killed = SingleInstance.terminatePeers(timeout: 2.0)
        DropLogger.logEvent("UI_UPDATE relaunch dest=\(dest.path) killed_peers=\(killed)")

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", dest.path]
        try open.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        let n = max(l.count, c.count)
        for i in 0..<n {
            let a = i < l.count ? l[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `sha256:HEX` or bare hex → lowercase hex.
    private static func normalizeSHA256(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let r = s.range(of: "sha256:", options: .caseInsensitive) {
            s = String(s[r.upperBound...])
        }
        s = s.lowercased()
        guard s.count == 64, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return s
    }

    private static func fetchSidecarSHA256(_ url: URL) async -> String? {
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            let first = text.split(whereSeparator: { $0.isWhitespace || $0 == "\n" }).first.map(String.init)
            return normalizeSHA256(first)
        } catch {
            return nil
        }
    }

    enum UpdateError: LocalizedError {
        case downloadFailed, unzipFailed, missingApp, checksumMismatch
        var errorDescription: String? {
            switch self {
            case .downloadFailed: return "Не удалось скачать релиз"
            case .unzipFailed: return "Не удалось распаковать архив"
            case .missingApp: return "В архиве нет myVPN.app"
            case .checksumMismatch: return "Контрольная сумма ZIP не совпала — установка отменена"
            }
        }
    }
}
