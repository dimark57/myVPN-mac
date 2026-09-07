import Foundation

enum RuntimePaths {
    static var bundledMyVPN: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("myvpn")
    }

    static var homeMyVPN: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/myvpn")
    }

    /// Prefer app-bundled runtime; fall back to local CLI install.
    static var myvpnBinary: URL {
        if let bundled = bundledMyVPN,
           FileManager.default.isExecutableFile(atPath: bundled.path)
            || FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return homeMyVPN
    }

    static var helperInstallScript: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("helper", isDirectory: true)
            .appendingPathComponent("install-helper.zsh")
    }

    static var appBundleURL: URL {
        Bundle.main.bundleURL
    }
}
