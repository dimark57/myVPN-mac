import AppKit
import Darwin
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    private var snapshot = StatusSnapshot()
    private var rules = RulesStatus()
    private var doctor = DoctorStatus()
    private var busyKey: String?
    private var menuIsOpen = false
    private var mouseMonitor: Any?
    private var autostartOn = false
    private var autoNASOn = false
    private var helperOn = false
    private var pidDirWatcher: DispatchSourceFileSystemObject?
    private var pidWatchDebounce: DispatchWorkItem?
    private let workQueue = DispatchQueue(label: "local.myvpn.mac.cli", qos: .userInitiated)
    private let logURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/myvpn-menubar.log")
    private let configDir = NSHomeDirectory() + "/.config/myvpn"
    private let menuWidth: CGFloat = 320
    private var connectionSettingsWC: ConnectionSettingsWindowController?
    private var helpWC: HelpWindowController?
    private var updateStatusLine = "Проверить обновление"

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
        doctor = DoctorStatus.load()
        rebuildMenu()
        refreshStatus()
        refreshPrefs()

        // Fallback only — primary updates: menu open + pid-file watcher (Alfred gv / CLI).
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, !self.isBusy else { return }
            self.refreshStatus(includePublicIP: false)
            self.refreshPrefs()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
        startPidDirWatcher()

        // Start immediately so an early menu open already shows «включаю…».
        beginAutoUpIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        stopPidDirWatcher()
        stopMouseExitMonitor()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        if !isBusy {
            rules = RulesStatus.load()
            doctor = DoctorStatus.load()
            // Force fresh status (e.g. after Alfred gv) — do not wait for timer.
            refreshStatus(includePublicIP: true)
            refreshPrefs()
        }
        rebuildMenu()
        startMouseExitMonitor()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        stopMouseExitMonitor()
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
        guard busyKey == key else { return base }
        // Busy titles already end with … / «выполняется» — don't append twice.
        if base.contains("выполняется") || base.hasSuffix("…") { return base }
        return "\(base) — выполняется"
    }

    private func addStickyAction(
        key: String,
        title: String,
        enabled: Bool,
        detail: String? = nil,
        checked: Bool? = nil,
        action: @escaping () -> Void
    ) {
        let item = NSMenuItem()
        let showsCheck = checked != nil
        let view = StickyMenuItemView(
            title: actionTitle(key, title),
            detail: detail,
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

        // VPN — status on the right of the action
        let vpnDetail: String = {
            switch busyKey {
            case "up", "auto-up": return "…"
            case "down": return "…"
            default: return snapshot.menuBadge
            }
        }()
        if busyKey == "up" || busyKey == "auto-up" {
            addStickyAction(key: busyKey!, title: "Включаю VPN…", enabled: false, detail: vpnDetail) { }
        } else if busyKey == "down" {
            addStickyAction(key: "down", title: "Выключаю VPN…", enabled: false, detail: vpnDetail) { }
        } else if snapshot.isOn {
            addStickyAction(
                key: "down",
                title: "Выключить",
                enabled: actionEnabled("down", helperOn),
                detail: vpnDetail
            ) { [weak self] in
                self?.turnOff()
            }
        } else {
            addStickyAction(
                key: "up",
                title: "Включить",
                enabled: actionEnabled("up", helperOn),
                detail: vpnDetail
            ) { [weak self] in
                self?.turnOn()
            }
        }

        // Helper only when missing / broken (hide when OK)
        if !helperOn {
            let title = MyVPNHelper.filesPresent
                ? "Переустановить помощника"
                : "Установить помощника"
            addStickyAction(
                key: "helper-install",
                title: title,
                enabled: actionEnabled("helper-install"),
                detail: MyVPNHelper.filesPresent ? "нет socket" : nil
            ) { [weak self] in
                self?.installHelper()
            }
        }

        menu.addItem(.separator())

        // NAS
        let nasDetail: String = {
            switch busyKey {
            case "mount-nas", "auto-nas": return "…"
            case "up", "auto-up": return autoNASOn ? "ожидание…" : snapshot.nasBadge
            default: return snapshot.nasBadge
            }
        }()
        if busyKey == "mount-nas" || busyKey == "auto-nas" {
            addStickyAction(key: busyKey!, title: "Монтирую NAS…", enabled: false, detail: nasDetail) { }
        } else {
            addStickyAction(
                key: "mount-nas",
                title: snapshot.nas ? "Перемонтировать NAS" : "Смонтировать NAS",
                enabled: actionEnabled("mount-nas"),
                detail: nasDetail
            ) { [weak self] in
                self?.mountNAS()
            }
        }

        // RU lists
        addStickyAction(
            key: "update-rules",
            title: "Обновить RU",
            enabled: actionEnabled("update-rules"),
            detail: busyKey == "update-rules" ? "…" : rules.menuBadge
        ) { [weak self] in
            self?.updateRules()
        }

        menu.addItem(.separator())

        // Doctor
        let doctorDetail = busyKey == "doctor" ? "…" : doctor.rowDetail
        addStickyAction(
            key: "doctor",
            title: "Диагностика",
            enabled: actionEnabled("doctor"),
            detail: doctorDetail
        ) { [weak self] in
            self?.runDoctor()
        }
        let reportExists = FileManager.default.fileExists(atPath: DoctorStatus.latestURL.path)
        addStickyAction(
            key: "open-report",
            title: "Открыть диагностический отчёт",
            enabled: reportExists && busyKey != "doctor"
        ) { [weak self] in
            self?.openDoctorReport()
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Настройки", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false
        settingsMenu.minimumWidth = menuWidth

        let conn = NSMenuItem()
        let connView = StickyMenuItemView(title: "Настройки подключения…", width: menuWidth)
        connView.isActionEnabled = true
        connView.onClick = { [weak self] in
            self?.menu.cancelTracking()
            self?.openConnectionSettings()
        }
        conn.view = connView
        settingsMenu.addItem(conn)

        // Uninstall only when helper is healthy; install/reinstall lives on root when broken
        if helperOn {
            settingsMenu.addItem(.separator())
            let rem = NSMenuItem()
            let view = StickyMenuItemView(
                title: actionTitle("helper-uninstall", "Удалить системный помощник"),
                width: menuWidth
            )
            view.isActionEnabled = actionEnabled("helper-uninstall")
            view.onClick = { [weak self] in self?.uninstallHelper() }
            rem.view = view
            settingsMenu.addItem(rem)
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

        addStickyAction(
            key: "check-update",
            title: updateStatusLine,
            enabled: actionEnabled("check-update"),
            detail: busyKey == "check-update" ? "…" : "v\(UpdateChecker.currentVersion)"
        ) { [weak self] in
            self?.checkForUpdate()
        }

        addStickyAction(key: "help", title: "Справка…", enabled: true) { [weak self] in
            self?.menu.cancelTracking()
            self?.openHelp()
        }

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
        button?.toolTip = statusHeaderTitle
    }

    private var statusHeaderTitle: String {
        switch busyKey {
        case "up", "auto-up": return "myVPN: включаю…"
        case "down": return "myVPN: выключаю…"
        case "mount-nas", "auto-nas": return snapshot.isOn ? snapshot.menuTitle : "myVPN: включаю…"
        default: return snapshot.menuTitle
        }
    }

    private var nasHeaderTitle: String {
        switch busyKey {
        case "mount-nas", "auto-nas": return "NAS: монтирую…"
        case "up", "auto-up": return autoNASOn ? "NAS: ожидание…" : snapshot.nasLine
        default: return snapshot.nasLine
        }
    }

    // MARK: - Actions

    private func turnOn() {
        runCommand(key: "up", work: "Включаю VPN") {
            try MyVPNCLI.up()
        } afterSuccess: { [weak self] in
            guard let self else { return }
            if self.autoNASOn {
                // Helper up bypasses CLI remount hook — remount as a visible second phase.
                self.runCommand(key: "mount-nas", work: "Монтирую NAS") {
                    try MyVPNCLI.mountNAS(force: true)
                } afterSuccess: { [weak self] in
                    self?.notify(
                        title: "myVPN ✓ Готово",
                        body: "VPN включён, NAS смонтирован · \(DoctorStatus.nowStamp())",
                        replacing: "mount-nas"
                    )
                }
            } else {
                self.notify(
                    title: "myVPN ✓ VPN",
                    body: "Включён · \(DoctorStatus.nowStamp())",
                    replacing: "up"
                )
            }
        }
    }

    private func turnOff() {
        runCommand(key: "down", work: "Выключаю VPN") {
            try MyVPNCLI.down()
        } afterSuccess: { [weak self] in
            self?.notify(
                title: "myVPN ✓ VPN",
                body: "Выключен · \(DoctorStatus.nowStamp())",
                replacing: "down"
            )
        }
    }

    private func mountNAS() {
        runCommand(key: "mount-nas", work: "Монтирую NAS") {
            try MyVPNCLI.mountNAS()
        } afterSuccess: { [weak self] in
            self?.notify(
                title: "myVPN ✓ NAS",
                body: "Смонтирован · \(DoctorStatus.nowStamp())",
                replacing: "mount-nas"
            )
        }
    }

    private func updateRules() {
        runCommand(key: "update-rules", work: "Обновляю списки RU…") {
            try MyVPNCLI.updateRules()
        } afterSuccess: { [weak self] in
            guard let self else { return }
            self.rules = RulesStatus.load()
            self.notify(title: "myVPN ✓ Списки RU", body: "Обновлены · \(self.rules.notifyStamp)", replacing: "update-rules")
        }
    }

    private func openDoctorReport() {
        let url = DoctorStatus.latestURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            notify(
                title: "myVPN",
                body: "Отчёта ещё нет — сначала «Диагностика» · \(DoctorStatus.nowStamp())",
                replacing: "open-report"
            )
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func runDoctor() {
        // No start banner — menu shows «выполняется»; one final user-facing notify.
        runCommand(key: "doctor", work: "Диагностика", timeout: 90, announceStart: false) {
            _ = try MyVPNCLI.doctor()
        } afterSuccess: { [weak self] in
            guard let self else { return }
            self.doctor = DoctorStatus.load()
            let pair = self.doctor.notificationPair
            self.notify(title: pair.title, body: pair.body, replacing: "doctor")
        }
    }

    private func installHelper() {
        runCommand(key: "helper-install", work: "Устанавливаю помощник…") {
            try MyVPNHelper.install()
        } afterSuccess: { [weak self] in
            self?.refreshPrefs()
            self?.notify(title: "myVPN ✓ Помощник", body: "Установлен — Вкл/Выкл без пароля · \(DoctorStatus.nowStamp())", replacing: "helper-install")
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

    private func openConnectionSettings() {
        if connectionSettingsWC == nil {
            connectionSettingsWC = ConnectionSettingsWindowController()
        }
        connectionSettingsWC?.show()
    }

    private func openHelp() {
        if helpWC == nil {
            helpWC = HelpWindowController()
        }
        helpWC?.show()
    }

    private func checkForUpdate() {
        guard !isBusy else { return }
        busyKey = "check-update"
        updateStatusLine = "Проверяю обновление…"
        if menuIsOpen { rebuildMenu() }
        Task { [weak self] in
            let result = await UpdateChecker.check()
            await MainActor.run {
                guard let self else { return }
                self.busyKey = nil
                self.updateStatusLine = result.upToDate ? "Проверить обновление" : "Обновить до v\(result.latest ?? "?")"
                if self.menuIsOpen { self.rebuildMenu() }
                if result.upToDate {
                    self.notify(title: "myVPN", body: result.message, replacing: "check-update")
                    return
                }
                let alert = NSAlert()
                alert.messageText = "Доступно обновление"
                alert.informativeText = result.message + "\n\nСкачать и установить из GitHub Releases?"
                alert.addButton(withTitle: "Обновить")
                alert.addButton(withTitle: "Открыть на GitHub")
                alert.addButton(withTitle: "Позже")
                NSApp.activate(ignoringOtherApps: true)
                let choice = alert.runModal()
                if choice == .alertFirstButtonReturn {
                    guard let url = result.assetURL else {
                        if let page = result.releaseURL { NSWorkspace.shared.open(page) }
                        self.notify(title: "myVPN", body: "В релизе нет myVPN.app.zip — открой страницу вручную", replacing: "check-update")
                        return
                    }
                    self.busyKey = "check-update"
                    self.updateStatusLine = "Скачиваю обновление…"
                    if self.menuIsOpen { self.rebuildMenu() }
                    Task {
                        do {
                            try await UpdateChecker.install(from: url)
                        } catch {
                            await MainActor.run {
                                self.busyKey = nil
                                self.updateStatusLine = "Проверить обновление"
                                if self.menuIsOpen { self.rebuildMenu() }
                                self.notify(title: "myVPN ✕ Обновление", body: error.localizedDescription, replacing: "check-update")
                            }
                        }
                    }
                } else if choice == .alertSecondButtonReturn, let page = result.releaseURL {
                    NSWorkspace.shared.open(page)
                }
            }
        }
    }

    private func beginAutoUpIfNeeded() {
        guard !isBusy else { return }
        // Do not require helper socket yet — at login LaunchDaemon often lags Login Item by ~10s.
        busyKey = "auto-up"
        applyIcon()
        workQueue.async { [weak self] in
            guard let self else { return }
            self.log("auto-up: start helperReady=\(MyVPNHelper.isAvailable)")
            guard MyVPNHelper.waitUntilAvailable(timeout: 45) else {
                self.log("auto-up: helper socket not ready after wait")
                DispatchQueue.main.async {
                    guard self.busyKey == "auto-up" else { return }
                    self.busyKey = nil
                    self.notify(title: "myVPN ✕ Помощник", body: "Ещё не готов — включи вручную · \(DoctorStatus.nowStamp())", replacing: "auto-up")
                    self.applyIcon()
                    if self.menuIsOpen { self.rebuildMenu() }
                    self.refreshStatus()
                }
                return
            }
            self.log("auto-up: helper ready")
            // Fresh status — may already be up from a previous session.
            let live = MyVPNCLI.status(includePublicIP: false)
            if live.isOn {
                self.log("auto-up: already on")
                DispatchQueue.main.async {
                    self.busyKey = nil
                    self.snapshot = live
                    self.applyIcon()
                    if self.menuIsOpen { self.rebuildMenu() }
                }
                return
            }
            let wantNas = MyVPNCLI.autoNASEnabled()
            DispatchQueue.main.async {
                self.autoNASOn = wantNas
                self.notify(title: "myVPN", body: "Включаю VPN · \(DoctorStatus.nowStamp())", replacing: "auto-up")
                if self.menuIsOpen { self.rebuildMenu() }
            }
            let watchdogKey = "auto-up"
            DispatchQueue.main.asyncAfter(deadline: .now() + 55) { [weak self] in
                guard let self, self.busyKey == watchdogKey || self.busyKey == "auto-nas" else { return }
                self.busyKey = nil
                self.notify(title: "myVPN ✕ Не успело", body: "Автозапуск не завершился · \(DoctorStatus.nowStamp()). Включи вручную.", replacing: "auto-up")
                if self.menuIsOpen { self.rebuildMenu() }
                self.refreshStatus()
            }
            do {
                try MyVPNCLI.up()
                self.log("auto-up: up ok")
                let afterUp = MyVPNCLI.status(includePublicIP: true)
                if wantNas {
                    DispatchQueue.main.async {
                        guard self.busyKey == "auto-up" else { return }
                        self.snapshot = afterUp
                        self.busyKey = "auto-nas"
                        self.applyIcon()
                        self.notify(title: "myVPN", body: "Монтирую NAS · \(DoctorStatus.nowStamp())", replacing: "auto-nas")
                        if self.menuIsOpen { self.rebuildMenu() }
                    }
                    try? MyVPNCLI.mountNAS(force: true)
                }
                let final = MyVPNCLI.status(includePublicIP: true)
                DispatchQueue.main.async {
                    guard self.busyKey == "auto-up" || self.busyKey == "auto-nas" else { return }
                    self.busyKey = nil
                    self.snapshot = final
                    self.applyIcon()
                    if self.menuIsOpen { self.rebuildMenu() }
                }
            } catch {
                self.log("auto-up: failed \(error.localizedDescription)")
                DispatchQueue.main.async {
                    guard self.busyKey == "auto-up" || self.busyKey == "auto-nas" else { return }
                    self.busyKey = nil
                    self.notify(title: "myVPN auto-up", body: error.localizedDescription)
                    if self.menuIsOpen { self.rebuildMenu() }
                    self.refreshStatus()
                }
            }
        }
    }

    private func runCommand(
        key: String,
        work: String,
        timeout: TimeInterval = 55,
        announceStart: Bool = true,
        body: @escaping () throws -> Void,
        afterSuccess: (() -> Void)? = nil
    ) {
        guard !isBusy else {
            let who = Self.busyLabel(busyKey ?? "операция")
            notify(
                title: "myVPN",
                body: "Уже выполняется: \(who) (\(DoctorStatus.nowStamp())). Дождись окончания.",
                replacing: "busy"
            )
            return
        }
        busyKey = key
        if menuIsOpen { rebuildMenu() }
        if announceStart {
            notify(title: "myVPN", body: "\(work) · \(DoctorStatus.nowStamp())", replacing: key)
        }
        let watchdogKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.busyKey == watchdogKey else { return }
            self.busyKey = nil
            let name = Self.busyLabel(watchdogKey)
            self.notify(
                title: "myVPN ✕ Не успело",
                body: "\(name) не завершилась за \(Int(timeout)) с (\(DoctorStatus.nowStamp())). Попробуй ещё раз.",
                replacing: key
            )
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
                        self?.doctor = DoctorStatus.load()
                        self?.rebuildMenu()
                    }
                    self?.refreshStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    guard self?.busyKey == key else { return }
                    self?.busyKey = nil
                    self?.doctor = DoctorStatus.load()
                    let name = Self.busyLabel(key)
                    self?.notify(
                        title: "myVPN ✕ \(name)",
                        body: "\(error.localizedDescription) (\(DoctorStatus.nowStamp()))",
                        replacing: key
                    )
                    if self?.menuIsOpen == true {
                        self?.rebuildMenu()
                    }
                    self?.refreshStatus()
                }
            }
        }
    }

    private static func busyLabel(_ key: String) -> String {
        switch key {
        case "up", "auto-up": return "включение VPN"
        case "down": return "выключение VPN"
        case "mount-nas", "auto-nas": return "монтирование NAS"
        case "update-rules": return "обновление списков RU"
        case "doctor": return "диагностика"
        case "helper-install": return "установка помощника"
        case "helper-uninstall": return "удаление помощника"
        case "autostart": return "автоподнятие"
        case "check-update": return "проверка обновления"
        default: return key
        }
    }

    // MARK: - Status refresh (menu open + pid changes from Alfred/CLI)

    private func startPidDirWatcher() {
        stopPidDirWatcher()
        try? FileManager.default.createDirectory(
            atPath: configDir,
            withIntermediateDirectories: true
        )
        let fd = open(configDir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleStatusRefreshFromPidWatch()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        pidDirWatcher = source
    }

    private func stopPidDirWatcher() {
        pidWatchDebounce?.cancel()
        pidWatchDebounce = nil
        pidDirWatcher?.cancel()
        pidDirWatcher = nil
    }

    private func scheduleStatusRefreshFromPidWatch() {
        pidWatchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isBusy else { return }
            self.refreshStatus(includePublicIP: false)
        }
        pidWatchDebounce = work
        // sing-box.pid create/delete after gv up/down — debounce burst of FS events.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func refreshPrefs() {
        autostartOn = MyVPNCLI.autostartEnabled() || LoginItemController.isEnabled
        autoNASOn = MyVPNCLI.autoNASEnabled()
        helperOn = MyVPNCLI.helperInstalled()
        if menuIsOpen {
            rebuildMenu()
        }
    }

    private func refreshStatus(includePublicIP: Bool = false) {
        workQueue.async { [weak self] in
            var next = MyVPNCLI.status(includePublicIP: includePublicIP)
            DispatchQueue.main.async {
                guard let self else { return }
                if !includePublicIP, next.ip.isEmpty {
                    next.ip = self.snapshot.ip
                }
                let changed = self.snapshot != next
                self.snapshot = next
                if let drop = DropLogger.observe(next) {
                    self.notify(title: "myVPN ⚠ Отвал", body: drop, replacing: "drop")
                }
                self.applyIcon()
                if self.menuIsOpen, !self.isBusy, changed {
                    self.rules = RulesStatus.load()
                    self.rebuildMenu()
                }
            }
        }
    }

    private func notify(title: String, body: String, replacing key: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(280))
        // Stable id → replaces previous banner for the same operation (no spam stack).
        let id = "local.myvpn.mac." + (key ?? UUID().uuidString)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
