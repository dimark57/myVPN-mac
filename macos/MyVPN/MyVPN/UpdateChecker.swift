import AppKit
import Foundation

/// GitHub Releases updater for ~/Applications/myVPN.app
/// Uses: api.github.com/repos/dimark57/myVPN-mac/releases/latest
enum UpdateChecker {
    static let repo = "dimark57/myVPN-mac"
    static let assetName = "myVPN.app.zip"

    struct Result: Sendable {
        var current: String
        var latest: String?
        var releaseURL: URL?
        var assetURL: URL?
        var upToDate: Bool
        var message: String
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
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
                    upToDate: true,
                    message: "v\(current) · релизов на GitHub пока нет"
                )
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return Result(current: current, latest: nil, releaseURL: nil, assetURL: nil, upToDate: true,
                             message: "Не удалось проверить обновления")
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Result(current: current, latest: nil, releaseURL: nil, assetURL: nil, upToDate: true,
                             message: "Неверный ответ GitHub")
            }
            let tag = ((obj["tag_name"] as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let html = obj["html_url"] as? String
            var asset: URL?
            if let assets = obj["assets"] as? [[String: Any]] {
                for a in assets {
                    if let name = a["name"] as? String, name == assetName,
                       let u = a["browser_download_url"] as? String {
                        asset = URL(string: u)
                        break
                    }
                }
            }
            let newer = isNewer(tag, than: current)
            if !newer {
                return Result(current: current, latest: tag, releaseURL: html.flatMap(URL.init), assetURL: asset,
                              upToDate: true, message: "v\(current) · обновлений нет")
            }
            return Result(current: current, latest: tag, releaseURL: html.flatMap(URL.init), assetURL: asset,
                          upToDate: false,
                          message: "Доступна v\(tag) (сейчас v\(current))")
        } catch {
            return Result(current: current, latest: nil, releaseURL: nil, assetURL: nil, upToDate: true,
                          message: "Ошибка сети: \(error.localizedDescription)")
        }
    }

    /// Download zip, replace ~/Applications/myVPN.app, relaunch.
    static func install(from assetURL: URL) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("myvpn-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let zipURL = tmp.appendingPathComponent(assetName)
        let (bytes, resp) = try await URLSession.shared.data(from: assetURL)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
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

    enum UpdateError: LocalizedError {
        case downloadFailed, unzipFailed, missingApp
        var errorDescription: String? {
            switch self {
            case .downloadFailed: return "Не удалось скачать релиз"
            case .unzipFailed: return "Не удалось распаковать архив"
            case .missingApp: return "В архиве нет myVPN.app"
            }
        }
    }
}
