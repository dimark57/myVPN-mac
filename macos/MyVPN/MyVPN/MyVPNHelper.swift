import Foundation

enum MyVPNHelper {
    static let sockPath = "/var/run/myvpn-helper.sock"

    static var isAvailable: Bool {
        var st = stat()
        guard stat(sockPath, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFSOCK
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
        let cmd = "cd / && /bin/zsh \(q(script.path)) install \(q(app)) \(q(user)) \(q(home))"
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
        try runAdminShell("cd / && /bin/zsh \(q(script.path)) uninstall")
    }

    private static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAdminShell(_ cmd: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \(q(cmd)) with administrator privileges"]
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
            return "Системный помощник не установлен — Настройки → Установить помощник (один пароль)…"
        case .connectFailed(let s):
            return "Helper: \(s)"
        case .remote(let s):
            return s
        case .installFailed(let s):
            return "Установка helper: \(s)"
        }
    }
}
