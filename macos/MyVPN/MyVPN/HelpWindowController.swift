import AppKit

/// Back-compat name — help is a section inside ConnectionSettingsWindowController.
enum HelpWindowController {
    static func show(using prefs: inout ConnectionSettingsWindowController?) {
        if prefs == nil {
            prefs = ConnectionSettingsWindowController(section: .help)
        }
        prefs?.show(section: .help)
    }
}
