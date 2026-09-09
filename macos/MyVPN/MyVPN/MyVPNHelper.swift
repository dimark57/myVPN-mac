import Foundation

enum MyVPNHelper {
    static let sockPath = "/var/run/myvpn-helper.sock"
    /// Uses: install-helper.zsh SUPPORT path
    static let supportBin = "/Library/Application Support/myVPN/myvpn-helper"
    static let launchPlist = "/Library/LaunchDaemons/local.myvpn.mac.helper.plist"

    static var isAvailable: Bool {
        var st = stat()
        guard stat(sockPath, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFSOCK
    }

    /// Installed files present but socket may be dead (needs reinstall / reload).
    static var filesPresent: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: supportBin) || fm.fileExists(atPath: launchPlist)
    }

    /// Login Item often starts before LaunchDaemon creates the socket — wait instead of giving up.
    static func waitUntilAvailable(timeout: TimeInterval = 45, poll: TimeInterval = 0.5) -> Bool {
        if isAvailable { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: poll)
            if isAvailable { return true }
        }
        return isAvailable
    }

    @discardableResult
    static func send(_ command: String, timeout: TimeInterval = 50) throws -> String {
        guard isAvailable else { throw HelperError.notInstalled }

        let sock = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { throw HelperError.connectFailed("socket()") }
        defer { Darwin.close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        sockPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                let bound = UnsafeMutableRawPointer(dst).assumingMemoryBound(to: CChar.self)
                strncpy(bound, src, 104)
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, len)
            }
        }
        guard ok == 0 else {
            throw HelperError.connectFailed(String(cString: strerror(errno)))
        }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let payload = Array((command + "\n").utf8)
        let sent = payload.withUnsafeBufferPointer { buf in
            Darwin.send(sock, buf.baseAddress, buf.count, 0)
        }
        guard sent == payload.count else {
            throw HelperError.connectFailed("send failed")
        }

        var buffer = [UInt8](repeating: 0, count: 8192)
        var collected = [UInt8]()
        while true {
            let n = Darwin.recv(sock, &buffer, buffer.count, 0)
            if n < 0 {
                throw HelperError.connectFailed(String(cString: strerror(errno)))
            }
            if n == 0 { break }
            collected.append(contentsOf: buffer.prefix(n))
            if collected.contains(UInt8(ascii: "\n")) { break }
        }

        let text = String(bytes: collected, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.hasPrefix("ok") {
            return text
        }
        let msg = text.hasPrefix("err")
            ? String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            : text
        throw HelperError.remote(msg.isEmpty ? "helper error" : msg)
    }

    /// One admin password dialog; then up/down are passwordless.
    static func install() throws {
        guard let script = RuntimePaths.helperInstallScript,
              FileManager.default.fileExists(atPath: script.path) else {
            throw HelperError.installFailed("нет install-helper.zsh в приложении")
        }
        let app = RuntimePaths.appBundleURL.path
        let user = NSUserName()
        let home = NSHomeDirectory()
        // Paths stay in the temp zsh — AppleScript must not embed shell-quoted paths (0.5.1 -2741).
        let cmd = "cd / && exec /bin/zsh \(shellQuote(script.path)) install \(shellQuote(app)) \(shellQuote(user)) \(shellQuote(home))"
        try runAdminShell(cmd)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if isAvailable { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw HelperError.installFailed("socket не появился — /var/log/myvpn-helper.err.log")
    }

    static func uninstall() throws {
        guard let script = RuntimePaths.helperInstallScript else {
            throw HelperError.installFailed("нет install-helper.zsh")
        }
        try runAdminShell("cd / && exec /bin/zsh \(shellQuote(script.path)) uninstall")
    }

    /// POSIX shell single-quote (for zsh body only — not AppleScript).
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Run `cmd` as root via osascript. Uses a temp .zsh so AppleScript only sees /var/folders ASCII.
    private static func runAdminShell(_ cmd: String) throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("myvpn-admin-\(UUID().uuidString).zsh")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let body = "#!/bin/zsh\nset -euo pipefail\n\(cmd)\n"
        try body.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tmp.path)

        // AppleScript string = double quotes; quoted form of handles spaces in tmp path.
        let asPath = tmp.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"/bin/zsh \" & quoted form of \"\(asPath)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", apple]
        let err = Pipe()
        let out = Pipe()
        process.standardError = err
        process.standardOutput = out
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? ""
            throw HelperError.installFailed(msg.isEmpty ? "osascript exit \(process.terminationStatus)" : msg)
        }
    }
}

enum HelperError: LocalizedError {
    case notInstalled
    case connectFailed(String)
    case remote(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Системный помощник не установлен — в меню нажми «Установить помощник» (один пароль)…"
        case .connectFailed(let s):
            return "Helper: \(s)"
        case .remote(let s):
            return s
        case .installFailed(let s):
            return "Установка helper: \(s)"
        }
    }
}
