import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    private var snapshot = StatusSnapshot()
    private var rules = RulesStatus()
    private var busyKey: String?
    private var menuIsOpen = false
    private var mouseMonitor: Any?
    private var autostartOn = false
    private var autoNASOn = false
    private var helperOn = false
    private let workQueue = DispatchQueue(label: "local.myvpn.mac.cli", qos: .userInitiated)
    private let logURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/myvpn-menubar.log")
    private let menuWidth: CGFloat = 300

    private var isBusy: Bool { busyKey != nil }

    private func log(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("didFinishLaunching bundle=\(Bundle.main.bundlePath)")
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = menuWidth
        statusItem.menu = menu

        applyIcon()
        rules = RulesStatus.load()
        rebuildMenu()
        refreshStatus()
        refreshPrefs()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, !self.isBusy else { return }
            self.refreshStatus()
            self.refreshPrefs()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.maybeAutoUp()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        stopMouseExitMonitor()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        if !isBusy {
            rules = RulesStatus.load()
        }
        rebuildMenu()
        startMouseExitMonitor()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        stopMouseExitMonitor()
        if !isBusy {
            refreshStatus()
        }
    }

    // MARK: - Keep open on click / close on mouse leave

    private func startMouseExitMonitor() {
        stopMouseExitMonitor()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.closeMenuIfMouseOutside()
            return event
        }
    }

    private func stopMouseExitMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func closeMenuIfMouseOutside() {
        guard menuIsOpen else { return }
        let mouse = NSEvent.mouseLocation
        var safe = CGRect.null
        for window in visibleMenuWindows() {
            safe = safe.union(window.frame)
        }
        if let button = statusItem.button, let bw = button.window {
            let buttonScreen = bw.convertToScreen(button.convert(button.bounds, to: nil))
            safe = safe.union(buttonScreen.insetBy(dx: -4, dy: -4))
        }
        // Grace so cursor can move between status item and menu / submenu.
        safe = safe.insetBy(dx: -6, dy: -6)
        if safe.isNull || !safe.contains(mouse) {
            menu.cancelTracking()
        }
    }

    private func visibleMenuWindows() -> [NSWindow] {
        NSApp.windows.filter { window in
            guard window.isVisible, window.alphaValue > 0 else { return false }
            let name = String(describing: type(of: window))
            return name.contains("Menu") || name.contains("Popup")
        }
    }

    // MARK: - Menu build

    private func actionEnabled(_ key: String, _ otherwise: Bool = true) -> Bool {
        if busyKey == key { return false }
        return otherwise
    }

    private func actionTitle(_ key: String, _ base: String) -> String {
        busyKey == key ? "\(base) — выполняется" : base
    }

    private func addInfo(_ text: String) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addStickyAction(
        key: String,
        title: String,
        enabled: Bool,
        checked: Bool? = nil,
        action: @escaping () -> Void
    ) {
        let item = NSMenuItem()
        let showsCheck = checked != nil
        let view = StickyMenuItemView(
            title: actionTitle(key, title),
            checked: checked ?? false,
            showsCheck: showsCheck,
            width: menuWidth
        )
        view.isActionEnabled = enabled
        view.onClick = { [weak self] in
            guard let self, enabled else { return }
            action()
            // Refresh labels in-place while menu stays open.
            if self.menuIsOpen {
                self.rebuildMenu()
            }
        }
        item.view = view
        menu.addItem(item)
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        addInfo(snapshot.menuTitle)
        addInfo(helperOn ? "Помощник: установлен" : "Помощник: не установлен")
        menu.addItem(.separator())

        if busyKey == "up" || busyKey == "auto-up" {
            addStickyAction(key: busyKey!, title: "Включить", enabled: false) { }
        } else if busyKey == "down" {
            addStickyAction(key: "down", title: "Выключить", enabled: false) { }
        } else if snapshot.isOn {
            addStickyAction(key: "down", title: "Выключить", enabled: actionEnabled("down", helperOn)) { [weak self] in
                self?.turnOff()
            }
        } else {
            addStickyAction(key: "up", title: "Включить", enabled: actionEnabled("up", helperOn)) { [weak self] in
                self?.turnOn()
            }
        }

        menu.addItem(.separator())

        addStickyAction(
            key: "mount-nas",
            title: "Смонтировать NAS",
            enabled: actionEnabled("mount-nas")
        ) { [weak self] in
            self?.mountNAS()
        }

        addStickyAction(
            key: "update-rules",
            title: "Обновить списки RU",
            enabled: actionEnabled("update-rules")
        ) { [weak self] in
            self?.updateRules()
        }

        addInfo(rules.geositeLine)
        addInfo(rules.geoipLine)
        if let summary = rules.updatedSummary {
            addInfo(summary)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Настройки", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false
        settingsMenu.minimumWidth = menuWidth

        if helperOn {
            let rem = NSMenuItem()
            let view = StickyMenuItemView(
                title: actionTitle("helper-uninstall", "Удалить системный помощник"),
                width: menuWidth
            )
            view.isActionEnabled = actionEnabled("helper-uninstall")
            view.onClick = { [weak self] in self?.uninstallHelper() }
            rem.view = view
            settingsMenu.addItem(rem)
        } else {
            let ins = NSMenuItem()
            let view = StickyMenuItemView(
                title: actionTitle("helper-install", "Установить помощник (один пароль)"),
                width: menuWidth
            )
            view.isActionEnabled = actionEnabled("helper-install")
            view.onClick = { [weak self] in self?.installHelper() }
            ins.view = view
            settingsMenu.addItem(ins)
        }

        settingsMenu.addItem(.separator())

        let autoUp = NSMenuItem()
        let autoUpView = StickyMenuItemView(
            title: actionTitle("autostart", "Автоподнятие после перезагрузки"),
            checked: autostartOn,
            showsCheck: true,
            width: menuWidth
        )
        autoUpView.isActionEnabled = actionEnabled("autostart")
        autoUpView.onClick = { [weak self] in self?.toggleAutostart() }
        autoUp.view = autoUpView
        settingsMenu.addItem(autoUp)

        let autoNas = NSMenuItem()
        let autoNasView = StickyMenuItemView(
            title: actionTitle("auto-nas", "Автоподключение NAS после перезагрузки"),
            checked: autoNASOn,
            showsCheck: true,
            width: menuWidth
        )
        autoNasView.isActionEnabled = actionEnabled("auto-nas", autostartOn)
        autoNasView.onClick = { [weak self] in self?.toggleAutoNAS() }
        autoNas.view = autoNasView
        settingsMenu.addItem(autoNas)

        settings.submenu = settingsMenu
        menu.addItem(settings)

        menu.addItem(.separator())

        addStickyAction(key: "quit", title: "Выход", enabled: true) { [weak self] in
            self?.menu.cancelTracking()
            NSApp.terminate(nil)
        }
    }

    private func applyIcon() {
        let button = statusItem.button
        let image: NSImage?
        if let asset = NSImage(named: "MenuBarIcon") {
            image = asset
        } else {
            image = NSImage(
                systemSymbolName: snapshot.isOn ? "lock.shield.fill" : "lock.shield",
                accessibilityDescription: "myVPN"
            )
        }
        let icon = image?.copy() as? NSImage
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        button?.image = icon
        button?.title = ""
        button?.imagePosition = .imageOnly
        statusItem.length = NSStatusItem.squareLength
        statusItem.isVisible = true
        button?.toolTip = snapshot.menuTitle
    }

    // MARK: - Actions

    private func turnOn() {
        runCommand(key: "up", work: "Включаю VPN…") { try MyVPNCLI.up() }
    }

    private func turnOff() {
        runCommand(key: "down", work: "Выключаю VPN…") { try MyVPNCLI.down() }
    }

    private func mountNAS() {
        runCommand(key: "mount-nas", work: "Монтирую NAS…") { try MyVPNCLI.mountNAS() }
    }

    private func updateRules() {
        runCommand(key: "update-rules", work: "Обновляю списки RU…") {
            try MyVPNCLI.updateRules()
        } afterSuccess: { [weak self] in
            guard let self else { return }
            self.rules = RulesStatus.load()
            self.notify(title: "myVPN", body: "Списки RU обновлены · \(self.rules.notifyStamp)")
        }
    }

    private func installHelper() {
        runCommand(key: "helper-install", work: "Устанавливаю помощник…") {
            try MyVPNHelper.install()
        } afterSuccess: { [weak self] in
            self?.refreshPrefs()
            self?.notify(title: "myVPN", body: "Помощник установлен — Вкл/Выкл без пароля")
        }
    }

    private func uninstallHelper() {
        runCommand(key: "helper-uninstall", work: "Удаляю помощник…") {
            try MyVPNHelper.uninstall()
        } afterSuccess: { [weak self] in
            self?.refreshPrefs()
        }
    }

    private func toggleAutostart() {
        let next = !autostartOn
        runCommand(key: "autostart", work: next ? "Включаю автоподнятие…" : "Выключаю автоподнятие…") {
            try MyVPNCLI.setAutostart(next)
        } afterSuccess: { [weak self] in
            self?.refreshPrefs()
        }
    }

    private func toggleAutoNAS() {
        let next = !autoNASOn
        runCommand(key: "auto-nas", work: next ? "Включаю авто-NAS…" : "Выключаю авто-NAS…") {
            try MyVPNCLI.setAutoNAS(next)
        } afterSuccess: { [weak self] in
            self?.refreshPrefs()
        }
    }

    private func maybeAutoUp() {
        guard MyVPNCLI.autostartEnabled(), MyVPNHelper.isAvailable, !snapshot.isOn, !isBusy else { return }
        busyKey = "auto-up"
        workQueue.async { [weak self] in
            do {
                try MyVPNCLI.up()
                if MyVPNCLI.autoNASEnabled() {
                    try? MyVPNCLI.mountNAS()
                }
                DispatchQueue.main.async {
                    self?.busyKey = nil
                    self?.refreshStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.busyKey = nil
                    self?.notify(title: "myVPN auto-up", body: error.localizedDescription)
                    self?.refreshStatus()
                }
            }
        }
    }

    private func runCommand(
        key: String,
        work: String,
        body: @escaping () throws -> Void,
        afterSuccess: (() -> Void)? = nil
    ) {
        guard !isBusy else { return }
        busyKey = key
        if menuIsOpen { rebuildMenu() }
        notify(title: "myVPN", body: work)
        // Failsafe: never leave menu stuck busy if helper hangs.
        let watchdogKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 55) { [weak self] in
            guard let self, self.busyKey == watchdogKey else { return }
            self.busyKey = nil
            self.notify(title: "myVPN", body: "Таймаут операции — попробуйте ещё раз")
            if self.menuIsOpen { self.rebuildMenu() }
            self.refreshStatus()
        }
        workQueue.async { [weak self] in
            do {
                try body()
                DispatchQueue.main.async {
                    guard self?.busyKey == key else { return }
                    self?.busyKey = nil
                    afterSuccess?()
                    if self?.menuIsOpen == true {
                        self?.rules = RulesStatus.load()
                        self?.rebuildMenu()
                    }
                    self?.refreshStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    guard self?.busyKey == key else { return }
                    self?.busyKey = nil
                    self?.notify(title: "myVPN", body: error.localizedDescription)
                    if self?.menuIsOpen == true {
                        self?.rebuildMenu()
                    }
                    self?.refreshStatus()
                }
            }
        }
    }

    private func refreshPrefs() {
        workQueue.async { [weak self] in
            let up = MyVPNCLI.autostartEnabled() || LoginItemController.isEnabled
            let nas = MyVPNCLI.autoNASEnabled()
            let helper = MyVPNCLI.helperInstalled()
            DispatchQueue.main.async {
                guard let self else { return }
                self.autostartOn = up
                self.autoNASOn = nas
                self.helperOn = helper
                if self.menuIsOpen {
                    self.rebuildMenu()
                }
            }
        }
    }

    private func refreshStatus() {
        workQueue.async { [weak self] in
            let next: StatusSnapshot
            do {
                next = try MyVPNCLI.status()
            } catch {
                next = StatusSnapshot()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshot = next
                self.applyIcon()
                if self.menuIsOpen, !self.isBusy {
                    self.rules = RulesStatus.load()
                    self.rebuildMenu()
                }
            }
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(280))
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
