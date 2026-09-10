import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon RegisterEventHotKey (no Accessibility permission).
/// Defaults use ⌃⌥⌘ — rare system conflicts; ClashX-style ⌘⇧* often collide (Paste Style, etc.).
enum HotkeyAction: UInt32 {
    case toggleVPN = 1
    case mountNAS = 2
    case doctor = 3
    case settings = 4
}

struct HotkeyBinding {
    let action: HotkeyAction
    let title: String
    let keyEquivalent: String
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let nsModifiers: NSEvent.ModifierFlags

    /// Glyph string for menus / help: ⌃⌥⌘V
    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += keyEquivalent.uppercased()
        return s
    }
}

private func myVPNHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    return GlobalHotkeys.handle(event: event, userData: userData)
}

final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    /// Fixed defaults — research: toggle ≫ settings ≫ diagnostics; NAS is myVPN-specific.
    static let bindings: [HotkeyBinding] = [
        HotkeyBinding(
            action: .toggleVPN,
            title: "Вкл / Выкл VPN",
            keyEquivalent: "v",
            keyCode: UInt32(kVK_ANSI_V),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            nsModifiers: [.control, .option, .command]
        ),
        HotkeyBinding(
            action: .mountNAS,
            title: "Смонтировать NAS",
            keyEquivalent: "n",
            keyCode: UInt32(kVK_ANSI_N),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            nsModifiers: [.control, .option, .command]
        ),
        HotkeyBinding(
            action: .doctor,
            title: "Диагностика",
            keyEquivalent: "d",
            keyCode: UInt32(kVK_ANSI_D),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            nsModifiers: [.control, .option, .command]
        ),
        HotkeyBinding(
            action: .settings,
            title: "Настройки…",
            keyEquivalent: ",",
            keyCode: UInt32(kVK_ANSI_Comma),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            nsModifiers: [.control, .option, .command]
        ),
    ]

    var onAction: ((HotkeyAction) -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private let signature: OSType = 0x6D56504E // 'mVPN'

    private init() {}

    func start() {
        stop()
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            myVPNHotKeyHandler,
            1,
            &eventSpec,
            userData,
            &handlerRef
        )
        guard status == noErr else { return }

        for binding in Self.bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: binding.action.rawValue)
            let err = RegisterEventHotKey(
                binding.keyCode,
                binding.carbonModifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if err == noErr, let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    func stop() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    fileprivate static func handle(event: EventRef, userData: UnsafeMutableRawPointer) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard err == noErr else { return err }
        let me = Unmanaged<GlobalHotkeys>.fromOpaque(userData).takeUnretainedValue()
        guard hotKeyID.signature == me.signature,
              let action = HotkeyAction(rawValue: hotKeyID.id) else {
            return OSStatus(eventNotHandledErr)
        }
        DispatchQueue.main.async {
            me.onAction?(action)
        }
        return noErr
    }
}
