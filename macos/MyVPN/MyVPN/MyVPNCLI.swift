import Foundation

enum MyVPNCLIError: LocalizedError {
    case missingBinary(String)
    case failed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .missingBinary(let path):
            return "Нет \(path) — переустановите myVPN.app"
        case .failed(let command, let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "myvpn \(command) exit \(code)"
            }
            return detail
        }
    }
}

/// Thin wrapper around bundled (or ~/.local/bin) myvpn. Privileged up/down via helper when present.
enum MyVPNCLI {
    static var binaryURL: URL { RuntimePaths.myvpnBinary }

    @discardableResult
    static func run(_ args: [String], timeout: TimeInterval = 120) throws -> (stdout: String, stderr: String, status: Int32) {
        let path = binaryURL.path
        guard FileManager.default.isExecutableFile(atPath: path)
            || FileManager.default.fileExists(atPath: path) else {
            throw MyVPNCLIError.missingBinary(path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [path] + args
        var env = ProcessInfo.processInfo.environment
        // Menu status must stay snappy — skip public IP curl.
        if args.first == "status" {
            env["MYVPN_STATUS_SKIP_IP"] = "1"
            env["MYVPN_PING_WAIT"] = "300"
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw MyVPNCLIError.failed(command: args.joined(separator: " "), exitCode: -1, stderr: "timeout")
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }

    static func status() throws -> StatusSnapshot {
        let result = try run(["status"], timeout: 8)
        return StatusSnapshot.parse(stdout: result.stdout)
    }

    static func up() throws {
        if MyVPNHelper.isAvailable {
            _ = try MyVPNHelper.send("up")
            return
        }
        throw HelperError.notInstalled
    }

    static func down() throws {
        if MyVPNHelper.isAvailable {
            _ = try MyVPNHelper.send("down")
            return
        }
        throw HelperError.notInstalled
    }

    static func mountNAS() throws {
        let result = try run(["mount-nas"], timeout: 120)
        if result.status != 0 {
            throw MyVPNCLIError.failed(command: "mount-nas", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    static func updateRules() throws {
        let result = try run(["update-rules"], timeout: 300)
        if result.status != 0 {
            throw MyVPNCLIError.failed(command: "update-rules", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    static func autostartEnabled() -> Bool {
        (try? run(["autostart", "status"], timeout: 10))?.status == 0
    }

    static func setAutostart(_ on: Bool) throws {
        if on {
            try LoginItemController.setEnabled(true)
            LoginItemController.removeLegacyLaunchAgent()
        } else {
            try? LoginItemController.setEnabled(false)
        }
        let result = try run(["autostart", on ? "on" : "off"], timeout: 30)
        if result.status != 0 && on {
            throw MyVPNCLIError.failed(command: "autostart", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    static func autoNASEnabled() -> Bool {
        (try? run(["auto-nas", "status"], timeout: 10))?.status == 0
    }

    static func setAutoNAS(_ on: Bool) throws {
        let result = try run(["auto-nas", on ? "on" : "off"], timeout: 30)
        if result.status != 0 && on {
            throw MyVPNCLIError.failed(command: "auto-nas", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    static func helperInstalled() -> Bool {
        MyVPNHelper.isAvailable
    }
}
