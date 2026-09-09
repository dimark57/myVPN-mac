import AppKit
import Darwin
import Foundation

/// Exactly one menu-bar UI for `local.myvpn.mac` (0.5.8).
/// Uses: DropLogger. Does not touch helper / sing-box / VPN.
/// Preferred install path: `~/Applications/myVPN.app` (beats DerivedData / stage).
enum SingleInstance {
    static let bundleIdentifier = "local.myvpn.mac"

    static var preferredAppURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/Applications/myVPN.app")
            .standardizedFileURL
    }

    /// Other live UI processes (same bundle id, not self). Not helper/sing-box.
    static func peerUIApplications() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// Ask peers to quit (UI only). Waits briefly; does not kill helper.
    @discardableResult
    static func terminatePeers(timeout: TimeInterval = 2.0) -> Int {
        let peers = peerUIApplications()
        for app in peers {
            app.terminate()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let left = peerUIApplications()
            if left.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // Failsafe: SIGTERM peer PIDs only — never `pkill -x myVPN` from inside UI (would kill self).
        let left = peerUIApplications()
        for app in left {
            kill(app.processIdentifier, SIGTERM)
        }
        if !left.isEmpty {
            Thread.sleep(forTimeInterval: 0.2)
        }
        return peers.count
    }

    private static func isPreferred(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL?.standardizedFileURL else { return false }
        return url.path == preferredAppURL.path
    }

    private static func isPreferredSelf() -> Bool {
        Bundle.main.bundleURL.standardizedFileURL.path == preferredAppURL.path
    }

    /// Claim sole UI ownership. `false` → caller must `NSApp.terminate` (no status item).
    /// Policy: preferred path wins; if both preferred (update handoff), newer `launchDate` keeps.
    static func claimOrYield(sessionCid: String) -> Bool {
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let peers = peerUIApplications()
        guard !peers.isEmpty else {
            DropLogger.logEvent("UI_LAUNCH ok=1 pid=\(pid) path=\(path) sess=\(sessionCid)")
            return true
        }

        let mePreferred = isPreferredSelf()
        let preferredPeers = peers.filter(isPreferred)

        if mePreferred {
            // ~/Applications (or equal) — evict DerivedData / stale UIs; if peer also preferred, keep newer.
            let meDate = NSRunningApplication.current.launchDate ?? .distantFuture
            var keep = true
            for peer in peers {
                if isPreferred(peer), let peerDate = peer.launchDate, peerDate > meDate {
                    keep = false
                    break
                }
            }
            if keep {
                for peer in peers {
                    peer.terminate()
                }
                DropLogger.logEvent(
                    "UI_LAUNCH ok=1 keep=preferred pid=\(pid) path=\(path) sess=\(sessionCid) killed_peers=\(peers.count)"
                )
                return true
            }
            preferredPeers.first?.activate(options: [.activateIgnoringOtherApps])
            DropLogger.logEvent(
                "UI_LAUNCH skip=older_preferred pid=\(pid) path=\(path) sess=\(sessionCid)"
            )
            return false
        }

        // Not preferred (DerivedData / stage) while any peer exists → yield.
        let activate = preferredPeers.first ?? peers.first
        activate?.activate(options: [.activateIgnoringOtherApps])
        DropLogger.logEvent(
            "UI_LAUNCH skip=duplicate pid=\(pid) path=\(path) sess=\(sessionCid) peer=\(activate?.bundleURL?.path ?? "?")"
        )
        return false
    }
}
