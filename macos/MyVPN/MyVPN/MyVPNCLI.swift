import Darwin
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

    private static let abortLock = NSLock()
    private static var activePid: pid_t = 0
    private static var abortRequested = false
    /// Last `run` ended via killpg (timeout or abort). Helper is never in this group.
    static var lastKilled = false

    /// Wake / watchdog: SIGTERM then SIGKILL the in-flight CLI process group (doc-11).
    static func abortInFlight() {
        abortLock.lock()
        abortRequested = true
        let pid = activePid
        abortLock.unlock()
        guard pid > 1 else { return }
        killProcessGroup(pid)
    }

    private static func killProcessGroup(_ pid: pid_t) {
        _ = killpg(pid, SIGTERM)
        _ = Darwin.kill(pid, SIGTERM)
        Thread.sleep(forTimeInterval: 0.5)
        _ = killpg(pid, SIGKILL)
        _ = Darwin.kill(pid, SIGKILL)
    }

    @discardableResult
    static func run(_ args: [String], timeout: TimeInterval = 120, quiet: Bool = false) throws -> (stdout: String, stderr: String, status: Int32) {
        let path = binaryURL.path
        guard FileManager.default.isExecutableFile(atPath: path)
            || FileManager.default.fileExists(atPath: path) else {
            throw MyVPNCLIError.missingBinary(path)
        }

        lastKilled = false
        abortLock.lock()
        abortRequested = false
        abortLock.unlock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [path] + args
        var env = ProcessInfo.processInfo.environment
        // App owns UNUserNotifications — suppress CLI/osascript banners.
        if quiet {
            env["MYVPN_QUIET"] = "1"
            env["MYVPN_NO_NOTIFY"] = "1"
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        let pid = process.processIdentifier
        _ = setpgid(pid, pid)
        abortLock.lock()
        activePid = pid
        abortLock.unlock()
        defer {
            abortLock.lock()
            if activePid == pid { activePid = 0 }
            abortLock.unlock()
        }

        let box = process
        let wait = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.waitUntilExit()
            wait.signal()
        }
        // Wall-clock deadline (Date), not DispatchTime — sleep pauses mach time (doc-11).
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            abortLock.lock()
            let abort = abortRequested
            abortLock.unlock()
            if abort || Date() >= deadline {
                lastKilled = true
                killProcessGroup(pid)
                _ = wait.wait(timeout: .now() + 1)
                let reason = abort ? "abort" : "timeout"
                throw MyVPNCLIError.failed(command: args.joined(separator: " "), exitCode: -1, stderr: reason)
            }
            let remaining = deadline.timeIntervalSinceNow
            let slice = min(0.25, max(0.05, remaining))
            if wait.wait(timeout: .now() + slice) == .success {
                break
            }
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }

    /// Menu bar / timer: native probe (no zsh). `includePublicIP` only when menu is open.
    static func status(includePublicIP: Bool = false) -> StatusSnapshot {
        StatusSnapshot.probe(includePublicIP: includePublicIP)
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

    /// `safe: true` → CLI `--safe` (auto/wake: skip force if busy).
    /// `remount: true` → CLI `--remount` (UI «Перемонтировать»: unmount → mount).
    static func mountNAS(force: Bool = false, safe: Bool = false, remount: Bool = false) throws {
        var args = ["mount-nas"]
        if remount { args.append("--remount") }
        if force { args.append("--force") }
        if safe { args.append("--safe") }
        let result = try run(args, timeout: 120, quiet: true)
        if result.status != 0 {
            throw MyVPNCLIError.failed(command: "mount-nas", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    /// Re-pin WG endpoint /32 via LAN gateway (needs helper ≥0.5.1 or admin).
    /// Uses: helper `pin-endpoints` → CLI `pin-endpoints` → `myvpn_pin_endpoint_routes`.
    static func pinEndpoints() throws {
        if MyVPNHelper.isAvailable {
            do {
                _ = try MyVPNHelper.send("pin-endpoints", timeout: 20)
                return
            } catch {
                // Old helper without pin — fall through to CLI (may need admin).
            }
        }
        let result = try run(["pin-endpoints"], timeout: 30, quiet: true)
        if result.status != 0 {
            throw MyVPNCLIError.failed(
                command: "pin-endpoints",
                exitCode: result.status,
                stderr: result.stderr + result.stdout
            )
        }
    }

    static func updateRules() throws {
        let result = try run(["update-rules"], timeout: 300, quiet: true)
        if result.status != 0 {
            throw MyVPNCLIError.failed(command: "update-rules", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    /// L1 triage (default) or L2 `--deep`. Exit ≠ 0 OK for WARN/FAIL if latest.txt written.
    @discardableResult
    static func doctor(deep: Bool = false) throws -> String {
        var args = ["doctor"]
        if deep { args.append("--deep") }
        let timeout = deep ? AutoDoctor.l2DoctorTimeout : AutoDoctor.l1DoctorTimeout
        let result = try run(args, timeout: timeout, quiet: true)
        let combined = result.stdout + result.stderr
        let latest = DoctorStatus.latestURL.path
        if FileManager.default.fileExists(atPath: latest) {
            return (try? String(contentsOfFile: latest, encoding: .utf8)) ?? combined
        }
        if result.status != 0 {
            throw MyVPNCLIError.failed(command: "doctor", exitCode: result.status, stderr: combined)
        }
        return combined
    }

    static func flushDNS() throws {
        let result = try run(["flush-dns"], timeout: 30, quiet: true)
        if result.status != 0 {
            throw MyVPNCLIError.failed(command: "flush-dns", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    static func autostartEnabled() -> Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.config/myvpn/auto-up-on-launch")
    }

    static func setAutostart(_ on: Bool) throws {
        if on {
            try LoginItemController.setEnabled(true)
            LoginItemController.removeLegacyLaunchAgent()
        } else {
            try? LoginItemController.setEnabled(false)
        }
        let result = try run(["autostart", on ? "on" : "off"], timeout: 30, quiet: true)
        if result.status != 0 && on {
            throw MyVPNCLIError.failed(command: "autostart", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    static func autoNASEnabled() -> Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.config/myvpn/auto-mount-nas")
    }

    static func setAutoNAS(_ on: Bool) throws {
        let result = try run(["auto-nas", on ? "on" : "off"], timeout: 30, quiet: true)
        if result.status != 0 && on {
            throw MyVPNCLIError.failed(command: "auto-nas", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }

    static func helperInstalled() -> Bool {
        MyVPNHelper.isAvailable
    }

    /// Regenerate sing-box.json from WG confs + settings.json
    static func render() throws {
        let result = try run(["render"], timeout: 60, quiet: true)
        if result.status != 0 {
            throw MyVPNCLIError.failed(command: "render", exitCode: result.status, stderr: result.stderr + result.stdout)
        }
    }
}
