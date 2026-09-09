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
    private var helperStale = false
    private var helperUpgradePromptShown = false
    private var pidDirWatcher: DispatchSourceFileSystemObject?
    private var pidWatchDebounce: DispatchWorkItem?
    private let workQueue = DispatchQueue(label: "local.myvpn.mac.cli", qos: .userInitiated)
    private let logURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/myvpn-menubar.log")
    private let configDir = NSHomeDirectory() + "/.config/myvpn"
    private let menuWidth: CGFloat = 360
    private var connectionSettingsWC: ConnectionSettingsWindowController?
    private var updateTimer: Timer?
    private var updateInFlight = false
    /// Last known GitHub release check for menu detail.
    private var lastUpdateCheck: UpdateChecker.Result?
    /// Prevent overlapping auto-doctor/heal pipelines.
    private var autoDoctorInFlight = false
    private var sessionCid = "sess_" + String(UUID().uuidString.prefix(8))
    private var egressPollCounter = 0
    private var wakeObserver: NSObjectProtocol?

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
        // Single-instance before status item (0.5.8). Uses: SingleInstance, DropLogger.
        if !SingleInstance.claimOrYield(sessionCid: sessionCid) {
            log("single-instance: yield → terminate")
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = menuWidth
        // Manual popUp: hang menu left of the icon so banners to the right stay visible.
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseDown])
        }

        applyIcon()
        rules = RulesStatus.load()
        doctor = DoctorStatus.load()
        DesiredStateStore.ensureFlagFile()
        rebuildMenu()
        refreshStatus()
        refreshPrefs()
        startGlobalHotkeys()
        registerWakeHandler()

        // Fallback only — primary updates: menu open + pid-file watcher (Alfred gv / CLI).
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, !self.isBusy else { return }
            // Every 4th tick (~60s): egress probe for hard DROP (doc-10).
            self.egressPollCounter += 1
            let wantIP = self.egressPollCounter % 4 == 0
            self.refreshStatus(includePublicIP: wantIP)
            self.refreshPrefs()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
        startPidDirWatcher()

        // Start immediately so an early menu open already shows «включаю…».
        beginAutoUpIfNeeded()

        // App updates: on launch (after VPN settle) + every hour; auto-install if newer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.runAutoUpdate(reason: "launch")
        }
        // Helper protocol bump (pin-endpoints etc.) — alert once if daemon older than app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.promptHelperUpgradeIfNeeded()
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.runAutoUpdate(reason: "hourly")
        }
        if let updateTimer {
            RunLoop.main.add(updateTimer, forMode: .common)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        updateTimer?.invalidate()
        GlobalHotkeys.shared.stop()
        stopPidDirWatcher()
        stopMouseExitMonitor()
    }

    // MARK: - Global hotkeys (Carbon — no Accessibility)

    private func startGlobalHotkeys() {
        let hk = GlobalHotkeys.shared
        hk.onAction = { [weak self] action in
            self?.handleHotkey(action)
        }
        hk.start()
        log("global hotkeys: registered \(GlobalHotkeys.bindings.count)")
    }

    private func handleHotkey(_ action: HotkeyAction) {
        switch action {
        case .toggleVPN:
            guard helperOn, !isBusy else {
                if !helperOn {
                    notify(title: "myVPN", body: "Сначала установи помощника · \(DoctorStatus.nowStamp())", replacing: "hotkey")
                }
                return
            }
            if snapshot.isOn { turnOff() } else { turnOn() }
        case .mountNAS:
            guard !isBusy else { return }
            mountNAS()
        case .doctor:
            guard !isBusy else { return }
            runDoctor()
        case .settings:
            openConnectionSettings()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        statusItem.button?.highlight(true)
        // Do NOT rebuildMenu here: with manual popUp, removeAllItems during open
        // leaves NSMenu scrolled (top ^ caret + first rows clipped).
        if !isBusy {
            // Async refresh; rebuild only if snapshot actually changes.
            refreshStatus(includePublicIP: true)
        }
        startMouseExitMonitor()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        statusItem.button?.highlight(false)
        stopMouseExitMonitor()
    }

    /// Pop menu with right edge under the status button (body to the left).
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if menuIsOpen {
            menu.cancelTracking()
            return
        }
        // Rebuild BEFORE popUp (not in menuWillOpen) so the first row stays pinned.
        if !isBusy {
            rules = RulesStatus.load()
            doctor = DoctorStatus.load()
            refreshPrefs()
        }
        rebuildMenu()
        // Pin first custom row under the button — nil positioning + all-custom-views
        // often shows a scroll-up caret and hides «Выключить».
        let pin = menu.items.first { $0.view != nil }
        let origin = NSPoint(x: sender.bounds.width - menuWidth, y: 0)
        menu.popUp(positioning: pin, at: origin, in: sender)
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
        // Grace so cursor can move between status item and menu.
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

    private enum MenuSlot {
        case sticky(
            key: String,
            title: String,
            enabled: Bool,
            detail: String?,
            checked: Bool?,
            action: () -> Void
        )
        case hotkeysSubmenu
        case separator
    }

    private func menuSlots() -> [MenuSlot] {
        var slots: [MenuSlot] = []

        // Status badge (info)
        slots.append(.sticky(
            key: "status",
            title: statusHeaderTitle,
            enabled: false,
            detail: nil,
            checked: nil,
            action: {}
        ))
        slots.append(.separator)

        // VPN — global ⌃⌥⌘V
        let vpnDetail: String = {
            switch busyKey {
            case "up", "auto-up": return "…"
            case "down": return "…"
            default: return snapshot.menuBadge
            }
        }()
        if busyKey == "up" || busyKey == "auto-up" {
            slots.append(.sticky(key: busyKey!, title: "Включаю VPN…", enabled: false, detail: vpnDetail, checked: nil, action: {}))
        } else if busyKey == "down" {
            slots.append(.sticky(key: "down", title: "Выключаю VPN…", enabled: false, detail: vpnDetail, checked: nil, action: {}))
        } else if snapshot.isOn {
            slots.append(.sticky(
                key: "down",
                title: "Выключить",
                enabled: actionEnabled("down", helperOn),
                detail: vpnDetail,
                checked: nil,
                action: { [weak self] in self?.turnOff() }
            ))
        } else {
            slots.append(.sticky(
                key: "up",
                title: "Включить",
                enabled: actionEnabled("up", helperOn),
                detail: vpnDetail,
                checked: nil,
                action: { [weak self] in self?.turnOn() }
            ))
        }

        // Helper missing / broken / outdated protocol
        if !helperOn {
            let title = MyVPNHelper.filesPresent
                ? "Переустановить помощника"
                : "Установить помощника"
            slots.append(.sticky(
                key: "helper-install",
                title: title,
                enabled: actionEnabled("helper-install"),
                detail: MyVPNHelper.filesPresent ? "нет socket" : nil,
                checked: nil,
                action: { [weak self] in self?.installHelper() }
            ))
        } else if helperStale {
            slots.append(.sticky(
                key: "helper-install",
                title: "Обновить помощника…",
                enabled: actionEnabled("helper-install"),
                detail: "устарел",
                checked: nil,
                action: { [weak self] in self?.installHelper() }
            ))
        }

        slots.append(.separator)

        // NAS — global ⌃⌥⌘N
        let nasDetail: String = {
            switch busyKey {
            case "mount-nas", "auto-nas": return "…"
            case "up", "auto-up": return autoNASOn ? "ожидание…" : snapshot.nasBadge
            default: return snapshot.nasBadge
            }
        }()
        if busyKey == "mount-nas" || busyKey == "auto-nas" {
            slots.append(.sticky(key: busyKey!, title: "Монтирую NAS…", enabled: false, detail: nasDetail, checked: nil, action: {}))
        } else {
            slots.append(.sticky(
                key: "mount-nas",
                title: snapshot.nas ? "Перемонтировать NAS" : "Смонтировать NAS",
                enabled: actionEnabled("mount-nas"),
                detail: nasDetail,
                checked: nil,
                action: { [weak self] in self?.mountNAS() }
            ))
        }

        slots.append(.separator)

        // Doctor — global ⌃⌥⌘D
        let doctorDetail = busyKey == "doctor" ? "…" : doctor.menuSeverityDetail
        slots.append(.sticky(
            key: "doctor",
            title: "Провести диагностику",
            enabled: actionEnabled("doctor"),
            detail: doctorDetail,
            checked: nil,
            action: { [weak self] in self?.runDoctor() }
        ))

        // Update check
        let updateDetail = busyKey == "check-update" ? "…" : UpdateChecker.menuDetail(from: lastUpdateCheck)
        slots.append(.sticky(
            key: "check-update",
            title: "Проверка обновления",
            enabled: actionEnabled("check-update", !updateInFlight),
            detail: updateDetail,
            checked: nil,
            action: { [weak self] in self?.checkUpdateFromMenu() }
        ))

        slots.append(.separator)

        slots.append(.sticky(
            key: "settings",
            title: "Настройки…",
            enabled: true,
            detail: "⌃⌥⌘,",
            checked: nil,
            action: { [weak self] in
                self?.menu.cancelTracking()
                self?.openConnectionSettings()
            }
        ))
        slots.append(.hotkeysSubmenu)

        slots.append(.separator)

        slots.append(.sticky(
            key: "quit",
            title: "Выход",
            enabled: true,
            detail: nil,
            checked: nil,
            action: { [weak self] in
                self?.menu.cancelTracking()
                NSApp.terminate(nil)
            }
        ))

        return slots
    }

    private func makeHotkeysSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Горячие клавиши", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Горячие клавиши")
        for binding in GlobalHotkeys.bindings {
            let row = NSMenuItem(
                title: binding.title,
                action: #selector(hotkeyMenuAction(_:)),
                keyEquivalent: binding.keyEquivalent
            )
            row.keyEquivalentModifierMask = binding.nsModifiers
            row.target = self
            row.representedObject = binding.action.rawValue
            row.isEnabled = true
            sub.addItem(row)
        }
        sub.addItem(.separator())
        let note = NSMenuItem(
            title: "Глобальные · ⌃⌥⌘",
            action: nil,
            keyEquivalent: ""
        )
        note.isEnabled = false
        sub.addItem(note)
        item.submenu = sub
        return item
    }

    @objc private func hotkeyMenuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? UInt32,
              let action = HotkeyAction(rawValue: raw) else { return }
        menu.cancelTracking()
        handleHotkey(action)
    }

    private func addStickyItem(
        key: String,
        title: String,
        enabled: Bool,
        detail: String?,
        checked: Bool?,
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
            if self.menuIsOpen {
                self.rebuildMenu()
            }
        }
        item.view = view
        menu.addItem(item)
    }

    /// Same slot layout as current items? Then patch StickyMenuItemView in place
    /// (removeAllItems while open → scroll caret ^ + clipped top rows).
    private func syncOpenMenu(with slots: [MenuSlot]) -> Bool {
        guard menu.items.count == slots.count else { return false }
        for (item, slot) in zip(menu.items, slots) {
            switch slot {
            case .separator:
                guard item.isSeparatorItem else { return false }
            case .hotkeysSubmenu:
                guard item.submenu != nil, item.view == nil, !item.isSeparatorItem else { return false }
            case let .sticky(key, title, enabled, detail, checked, action):
                guard let view = item.view as? StickyMenuItemView else { return false }
                view.setTitle(actionTitle(key, title))
                view.setDetail(detail)
                if let checked { view.setChecked(checked) }
                view.isActionEnabled = enabled
                view.onClick = { [weak self] in
                    guard let self, enabled else { return }
                    action()
                    if self.menuIsOpen {
                        self.rebuildMenu()
                    }
                }
            }
        }
        return true
    }

    private func rebuildMenu() {
        let slots = menuSlots()
        if menuIsOpen, syncOpenMenu(with: slots) {
            return
        }

        menu.removeAllItems()
        for slot in slots {
            switch slot {
            case .separator:
                menu.addItem(.separator())
            case .hotkeysSubmenu:
                menu.addItem(makeHotkeysSubmenuItem())
            case let .sticky(key, title, enabled, detail, checked, action):
                addStickyItem(
                    key: key,
                    title: title,
                    enabled: enabled,
                    detail: detail,
                    checked: checked,
                    action: action
                )
            }
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
        DesiredStateStore.setDesiredOn()
        HealCircuitBreaker.resume(reason: "user_on")
        runCommand(key: "up", work: "Включаю VPN", timeout: 35) {
            try MyVPNCLI.up()
        } afterSuccess: { [weak self] in
            guard let self else { return }
            DesiredStateStore.setDesiredOn()
            if self.autoNASOn {
                // Helper up bypasses CLI remount hook — remount as a visible second phase.
                self.runCommand(key: "mount-nas", work: "Монтирую NAS", timeout: AutoDoctor.mountUITimeout) {
                    try MyVPNCLI.mountNAS(force: false, safe: true)
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
        DesiredStateStore.setDesiredOff()
        runCommand(key: "down", work: "Выключаю VPN", timeout: 35) {
            try MyVPNCLI.down()
        } afterSuccess: { [weak self] in
            DesiredStateStore.setDesiredOff()
            self?.notify(
                title: "myVPN ✓ VPN",
                body: "Выключен · \(DoctorStatus.nowStamp())",
                replacing: "down"
            )
        }
    }

    private func mountNAS() {
        runCommand(key: "mount-nas", work: "Монтирую NAS", timeout: AutoDoctor.mountUITimeout) {
            try MyVPNCLI.mountNAS(safe: true)
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
                body: "Отчёта ещё нет — сначала «Провести диагностику» · \(DoctorStatus.nowStamp())",
                replacing: "open-report"
            )
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Copy latest doctor report + open GitHub Issues (Настройки → Диагностика).
    private func sendDoctorReportToDeveloper() {
        let url = DoctorStatus.latestURL
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            notify(
                title: "myVPN",
                body: "Отчёта ещё нет — сначала «Провести диагностику» · \(DoctorStatus.nowStamp())",
                replacing: "send-report"
            )
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        var comps = URLComponents(string: "https://github.com/dimark57/myVPN-mac/issues/new")!
        comps.queryItems = [
            URLQueryItem(name: "title", value: "Диагностика myVPN v\(UpdateChecker.currentVersion)"),
            URLQueryItem(
                name: "body",
                value: """
                <!-- Отчёт уже в буфере обмена — вставь ниже между ``` -->

                **Версия:** v\(UpdateChecker.currentVersion)
                **PRIMARY:** \(doctor.primary.isEmpty ? "—" : doctor.primary)
                **OVERALL:** \(doctor.overall.isEmpty ? "—" : doctor.overall)

                ```
                (вставь ~/.cache/myvpn-doctor/latest.txt из буфера)
                ```
                """
            ),
        ]
        if let issueURL = comps.url {
            NSWorkspace.shared.open(issueURL)
        }
        notify(
            title: "myVPN · Отчёт",
            body: "Скопирован в буфер · открой GitHub Issues и вставь · \(DoctorStatus.nowStamp())",
            replacing: "send-report"
        )
    }

    private func runDoctor() {
        runCommand(key: "doctor", work: "Диагностика L1", timeout: 25, announceStart: false) {
            _ = try MyVPNCLI.doctor(deep: false)
        } afterSuccess: { [weak self] in
            guard let self else { return }
            self.doctor = DoctorStatus.load()
            let pair = self.doctor.notificationPair
            self.notify(title: pair.title, body: pair.body, replacing: "doctor")
        }
    }

    private func runDoctorDeep() {
        runCommand(key: "doctor", work: "Полная диагностика", timeout: AutoDoctor.l2DoctorTimeout, announceStart: true) {
            _ = try MyVPNCLI.doctor(deep: true)
        } afterSuccess: { [weak self] in
            guard let self else { return }
            self.doctor = DoctorStatus.load()
            let pair = self.doctor.notificationPair
            self.notify(title: pair.title, body: pair.body + " · L2", replacing: "doctor")
        }
    }

    private func checkUpdateFromMenu() {
        guard !updateInFlight, busyKey == nil else { return }
        busyKey = "check-update"
        rebuildMenu()
        applyIcon()
        Task { [weak self] in
            let result = await UpdateChecker.check()
            await MainActor.run {
                guard let self else { return }
                self.busyKey = nil
                self.lastUpdateCheck = result
                self.rebuildMenu()
                self.applyIcon()
                if result.upToDate {
                    self.notify(
                        title: "myVPN · Обновление",
                        body: result.message,
                        replacing: "check-update"
                    )
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
                        return
                    }
                    self.updateInFlight = true
                    self.notify(
                        title: "myVPN · Обновляю",
                        body: "Ставлю v\(result.latest ?? "?") · \(DoctorStatus.nowStamp())",
                        replacing: "check-update"
                    )
                    Task {
                        do {
                            try await UpdateChecker.install(from: url)
                        } catch {
                            await MainActor.run {
                                self.updateInFlight = false
                                self.notify(
                                    title: "myVPN ✕ Обновление",
                                    body: error.localizedDescription,
                                    replacing: "check-update"
                                )
                            }
                        }
                    }
                } else if choice == .alertSecondButtonReturn, let page = result.releaseURL {
                    NSWorkspace.shared.open(page)
                }
            }
        }
    }

    private func installHelper() {
        runCommand(key: "helper-install", work: "Устанавливаю помощник…") {
            try MyVPNHelper.install()
            MyVPNHelper.clearDismissedUpgrade()
        } afterSuccess: { [weak self] in
            self?.refreshPrefs()
            self?.notify(
                title: "myVPN ✓ Помощник",
                body: "Обновлён (proto \(MyVPNHelper.requiredProtocol)) · \(DoctorStatus.nowStamp())",
                replacing: "helper-install"
            )
        }
    }

    /// NSAlert when LaunchDaemon protocol < app required (after Update without helper reinstall).
    private func promptHelperUpgradeIfNeeded() {
        guard !helperUpgradePromptShown, !isBusy else { return }
        workQueue.async { [weak self] in
            let stale = MyVPNHelper.needsReinstall
            let dismissed = MyVPNHelper.dismissedUpgradeForCurrentProto
            DispatchQueue.main.async {
                guard let self, stale, !dismissed, !self.helperUpgradePromptShown else { return }
                self.helperUpgradePromptShown = true
                self.helperStale = true
                if self.menuIsOpen { self.rebuildMenu() }

                let alert = NSAlert()
                alert.messageText = "Обновить системный помощник?"
                alert.informativeText =
                    "После обновления myVPN помощник устарел (нужны новые команды). VPN можно не выключать. Один пароль администратора."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Переустановить сейчас")
                alert.addButton(withTitle: "Позже")
                NSApp.activate(ignoringOtherApps: true)
                let choice = alert.runModal()
                if choice == .alertFirstButtonReturn {
                    self.installHelper()
                } else {
                    MyVPNHelper.dismissedUpgradeForCurrentProto = true
                }
            }
        }
    }

    private func openConnectionSettings(section: ConnectionSettingsWindowController.Section = .channels) {
        if connectionSettingsWC == nil {
            connectionSettingsWC = ConnectionSettingsWindowController(section: section)
        }
        connectionSettingsWC?.appDelegate = self
        connectionSettingsWC?.show(section: section)
    }

    private func openHelp() {
        openConnectionSettings(section: .help)
    }

    // MARK: - Settings bridge

    func settingsRunDoctor() { runDoctor() }
    func settingsRunDoctorDeep() { runDoctorDeep() }
    func settingsResumeSafeMode() {
        HealCircuitBreaker.resume(reason: "settings_resume")
        notify(
            title: "myVPN · Safe Mode",
            body: "Автоheal снова разрешён · \(DoctorStatus.nowStamp())",
            replacing: "safe-mode"
        )
    }
    func settingsUpdateRules() { updateRules() }
    func settingsOpenDoctorReport() { openDoctorReport() }
    func settingsSendDoctorReport() { sendDoctorReportToDeveloper() }
    func settingsDoctorStatus() -> DoctorStatus { doctor }
    func settingsRulesStatus() -> RulesStatus { rules }
    func settingsReloadRules() {
        rules = RulesStatus.load()
        if menuIsOpen { rebuildMenu() }
    }
    func settingsReloadDoctor() {
        doctor = DoctorStatus.load()
        if menuIsOpen { rebuildMenu() }
    }

    /// Silent check + optional auto-install (launch + hourly), gated by Update prefs.
    private func runAutoUpdate(reason: String) {
        guard UpdateChecker.autoCheckEnabled else {
            log("auto-update: skipped (\(reason)) — auto-check off")
            return
        }
        guard !updateInFlight else { return }
        updateInFlight = true
        log("auto-update: check (\(reason))")
        Task { [weak self] in
            let result = await UpdateChecker.check()
            await MainActor.run {
                guard let self else { return }
                if result.upToDate {
                    self.log("auto-update: up to date — \(result.message)")
                    self.lastUpdateCheck = result
                    self.updateInFlight = false
                    if self.menuIsOpen { self.rebuildMenu() }
                    return
                }
                self.lastUpdateCheck = result
                if self.menuIsOpen { self.rebuildMenu() }
                guard let url = result.assetURL else {
                    self.log("auto-update: newer but no asset — \(result.message)")
                    self.notify(
                        title: "myVPN · Обновление",
                        body: "\(result.message). Меню → Проверка обновления.",
                        replacing: "auto-update"
                    )
                    self.updateInFlight = false
                    return
                }
                let ver = result.latest ?? "?"
                guard UpdateChecker.autoInstallEnabled else {
                    self.log("auto-update: available v\(ver) — auto-install off")
                    self.notify(
                        title: "myVPN · Доступно v\(ver)",
                        body: "Автоустановка выкл. Настройки → Update · \(DoctorStatus.nowStamp())",
                        replacing: "auto-update"
                    )
                    self.updateInFlight = false
                    return
                }
                self.notify(
                    title: "myVPN · Обновляю",
                    body: "Ставлю v\(ver) · \(DoctorStatus.nowStamp())",
                    replacing: "auto-update"
                )
                self.log("auto-update: installing v\(ver)")
                Task {
                    do {
                        try await UpdateChecker.install(from: url)
                    } catch {
                        await MainActor.run {
                            self.updateInFlight = false
                            self.log("auto-update: failed \(error.localizedDescription)")
                            self.notify(
                                title: "myVPN ✕ Обновление",
                                body: error.localizedDescription,
                                replacing: "auto-update"
                            )
                        }
                    }
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
                DesiredStateStore.setDesiredOn()
                DispatchQueue.main.async {
                    self.busyKey = nil
                    self.snapshot = live
                    self.applyIcon()
                    if self.menuIsOpen { self.rebuildMenu() }
                }
                return
            }
            let wantNas = MyVPNCLI.autoNASEnabled()
            DesiredStateStore.setDesiredOn()
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
                    try? MyVPNCLI.mountNAS(force: true, safe: true)
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
        case "doctor", "auto-doctor": return "диагностика"
        case "auto-heal": return "автовосстановление"
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
        // Proto check is sync socket I/O — keep off main if menu spam; cache via workQueue when stale unknown.
        if helperOn {
            workQueue.async { [weak self] in
                let stale = MyVPNHelper.needsReinstall
                DispatchQueue.main.async {
                    guard let self else { return }
                    let changed = self.helperStale != stale
                    self.helperStale = stale
                    if changed, self.menuIsOpen { self.rebuildMenu() }
                }
            }
        } else {
            helperStale = false
        }
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
                FlightRecorder.append(sample: next, sessionCid: self.sessionCid)
                if let drop = DropLogger.observe(next) {
                    self.handleChannelDrop(drop)
                }
                self.applyIcon()
                if self.menuIsOpen, !self.isBusy, changed {
                    self.rules = RulesStatus.load()
                    self.rebuildMenu()
                }
            }
        }
    }

    /// DropLogger hard DROP → FDIR pipeline (doc-10). Auto L1 on dedicated queue (no 55s busy).
    private func handleChannelDrop(_ event: DropLogger.DropEvent) {
        notify(title: "myVPN ⚠ Отвал", body: event.body, replacing: "drop")
        guard AutoDoctor.autoDoctorEnabled || event.intentionalOff else { return }
        guard !autoDoctorInFlight else {
            DropLogger.logEvent("AUTO_DOCTOR skip=in_flight")
            return
        }
        if let busyKey, busyKey != "auto-doctor", busyKey != "auto-heal" {
            DropLogger.logEvent("AUTO_DOCTOR skip=busy:\(busyKey)")
            return
        }
        autoDoctorInFlight = true
        AutoDoctorPipeline.run(
            sessionCid: sessionCid,
            event: event,
            callbacks: AutoDoctorPipeline.Callbacks(
                onDoctorLoaded: { [weak self] doc in
                    self?.doctor = doc
                    if self?.menuIsOpen == true { self?.rebuildMenu() }
                },
                onNotify: { [weak self] title, body, key in
                    self?.notify(title: title, body: body, replacing: key)
                },
                onBusyHeal: { [weak self] in
                    self?.busyKey = "auto-heal"
                    if self?.menuIsOpen == true { self?.rebuildMenu() }
                    self?.applyIcon()
                },
                onFinished: { [weak self] in
                    self?.finishAutoDoctor()
                },
                onRefresh: { [weak self] includeIP in
                    self?.refreshStatus(includePublicIP: includeIP)
                }
            )
        )
    }

    private func finishAutoDoctor() {
        autoDoctorInFlight = false
        if busyKey == "auto-doctor" || busyKey == "auto-heal" {
            busyKey = nil
        }
        doctor = DoctorStatus.load()
        applyIcon()
        if menuIsOpen { rebuildMenu() }
    }

    private func registerWakeHandler() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            FlightRecorder.append(sample: self.snapshot, sessionCid: self.sessionCid, wake: true)
            // Soft recover: settle → L0 → pin → mount-nas; restart only if SLEEP_WAKE_STALE.
            WakeRecover.schedule(
                sessionCid: self.sessionCid,
                callbacks: WakeRecover.Callbacks(
                    onSnapshot: { [weak self] snap in
                        guard let self else { return }
                        self.snapshot = snap
                        self.applyIcon()
                        if self.menuIsOpen { self.rebuildMenu() }
                    },
                    onNotify: { [weak self] title, body, key in
                        self?.notify(title: title, body: body, replacing: key)
                    },
                    onRefresh: { [weak self] includeIP in
                        self?.refreshStatus(includePublicIP: includeIP)
                    }
                )
            )
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
