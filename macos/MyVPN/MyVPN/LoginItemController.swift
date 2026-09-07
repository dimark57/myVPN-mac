import Foundation
import ServiceManagement

enum LoginItemController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Drop legacy zsh LaunchAgent so only myVPN.app appears in Login Items.
    static func removeLegacyLaunchAgent() {
        let label = "local.myvpn.mac.login"
        let plist = NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
        let uid = getuid()
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(uid)/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()
        try? FileManager.default.removeItem(atPath: plist)
    }
}
