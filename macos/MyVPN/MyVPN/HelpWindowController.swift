import AppKit

/// Back-compat name — help is a section inside ConnectionSettingsWindowController.
enum HelpWindowController {
    static func show(using prefs: inout ConnectionSettingsWindowController?) {
        if prefs == nil {
            prefs = ConnectionSettingsWindowController(section: .help)
        }
        if let app = NSApp.delegate as? AppDelegate {
            prefs?.appDelegate = app
        }
        prefs?.show(section: .help)
    }
}
