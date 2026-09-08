import AppKit

/// Connection settings: import / paste / edit WG confs + routing/NAS prefs.
/// Uses: WireGuardProfileStore, AppSettings, MyVPNCLI.render
final class ConnectionSettingsWindowController: NSWindowController, NSWindowDelegate {
    private var macbookEditor: NSTextView!
    private var homeEditor: NSTextView!
    private var lanField: NSTextField!
    private var nasHostField: NSTextField!
    private var nasShareField: NSTextField!
    private var dnsHomeField: NSTextField!
    private var dnsSuffixField: NSTextField!
    private var statusLabel: NSTextField!
    private var badgeMacbook: NSTextField!
    private var badgeHome: NSTextField!
    private var tabView: NSTabView!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки подключения"
        window.minSize = NSSize(width: 640, height: 480)
        window.titlebarAppearsTransparent = false
        self.init(window: window)
        window.delegate = self
        window.center()
        buildUI()
        reloadFromDisk()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Header
        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 12, right: 20)

        let title = NSTextField(labelWithString: "Профили WireGuard и маршруты")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(wrappingLabelWithString:
            "Файлы только на этом Mac: ~/.config/wireguard. Home AllowedIPs задают, что идёт в домашнюю сеть; остальной интернет — через Egress.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = 680

        let badges = NSStackView()
        badges.orientation = .horizontal
        badges.spacing = 8
        badges.alignment = .centerY
        badgeMacbook = makeBadge(title: "macbook.conf")
        badgeHome = makeBadge(title: "home.conf")
        badges.addArrangedSubview(badgeMacbook)
        badges.addArrangedSubview(badgeHome)
        let badgeSpacer = NSView()
        badgeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        badges.addArrangedSubview(badgeSpacer)

        header.addArrangedSubview(title)
        header.addArrangedSubview(subtitle)
        header.addArrangedSubview(badges)
        root.addArrangedSubview(header)

        root.addArrangedSubview(hairline())

        // Tabs
        let tabWrap = NSView()
        tabWrap.translatesAutoresizingMaskIntoConstraints = false
        tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        tabView.controlSize = .regular
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabWrap.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: tabWrap.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: tabWrap.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: tabWrap.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: tabWrap.bottomAnchor, constant: -4),
            tabWrap.heightAnchor.constraint(greaterThanOrEqualToConstant: 340),
        ])

        macbookEditor = makeEditor()
        homeEditor = makeEditor()
        tabView.addTabViewItem(makeConfTab(
            label: "Egress",
            blurb: "Выход в интернет (профиль macbook).",
            editor: macbookEditor,
            profile: .macbook
        ))
        tabView.addTabViewItem(makeConfTab(
            label: "Home",
            blurb: "Домашняя сеть / NAS (AllowedIPs = split).",
            editor: homeEditor,
            profile: .home
        ))

        let routing = NSTabViewItem(identifier: "routing")
        routing.label = "Маршруты"
        routing.view = makeRoutingPane()
        tabView.addTabViewItem(routing)
        root.addArrangedSubview(tabWrap)

        root.addArrangedSubview(hairline())

        // Footer
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        footer.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 16, right: 20)

        let save = NSButton(title: "Сохранить", target: self, action: #selector(saveAll))
        save.keyEquivalent = "\r"
        if #available(macOS 11.0, *) {
            save.hasDestructiveAction = false
        }
        save.bezelStyle = .rounded
        // Primary action look
        save.keyEquivalentModifierMask = []

        let openFolder = NSButton(title: "Папка конфигов", target: self, action: #selector(openWGFolder))
        openFolder.bezelStyle = .rounded

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let close = NSButton(title: "Закрыть", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"

        footer.addArrangedSubview(save)
        footer.addArrangedSubview(openFolder)
        footer.addArrangedSubview(statusLabel)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(close)
        root.addArrangedSubview(footer)
    }

    private func hairline() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }

    private func makeBadge(title: String) -> NSTextField {
        let f = NSTextField(labelWithString: title)
        f.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        f.textColor = .secondaryLabelColor
        f.drawsBackground = true
        f.backgroundColor = NSColor.controlBackgroundColor
        f.isBezeled = false
        f.isBordered = false
        f.wantsLayer = true
        f.layer?.cornerRadius = 4
        f.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25).cgColor
        return f
    }

    private func setBadge(_ field: NSTextField, name: String, ok: Bool) {
        field.stringValue = "  \(name): \(ok ? "есть" : "нет")  "
        field.textColor = ok ? .systemGreen : .secondaryLabelColor
        field.toolTip = ok
            ? "~/.config/wireguard/\(name)"
            : "Файл ещё не сохранён"
    }

    private func makeEditor() -> NSTextView {
        let tv = NSTextView()
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.allowsUndo = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        return tv
    }

    private func makeConfTab(
        label: String,
        blurb: String,
        editor: NSTextView,
        profile: WireGuardProfileStore.Profile
    ) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: profile.rawValue)
        item.label = label

        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            stack.topAnchor.constraint(equalTo: pane.topAnchor),
            stack.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])

        let top = NSStackView()
        top.orientation = .horizontal
        top.spacing = 8
        top.alignment = .centerY

        let hint = NSTextField(labelWithString: blurb)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let imp = NSButton(title: "Импорт…", target: self, action: #selector(importConf(_:)))
        imp.bezelStyle = .rounded
        imp.controlSize = .small
        imp.tag = profile == .macbook ? 0 : 1

        let paste = NSButton(title: "Из буфера", target: self, action: #selector(pasteConf(_:)))
        paste.bezelStyle = .rounded
        paste.controlSize = .small
        paste.tag = profile == .macbook ? 0 : 1

        top.addArrangedSubview(hint)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(spacer)
        top.addArrangedSubview(imp)
        top.addArrangedSubview(paste)
        stack.addArrangedSubview(top)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = editor
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        stack.addArrangedSubview(scroll)

        item.view = pane
        return item
    }

    private func makeRoutingPane() -> NSView {
        let pane = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            stack.topAnchor.constraint(equalTo: pane.topAnchor),
            stack.widthAnchor.constraint(equalTo: pane.widthAnchor),
        ])

        stack.addArrangedSubview(sectionHeader("Локальная сеть"))
        lanField = makeField(placeholder: "192.168.0.0/16, 10.0.0.0/8")
        stack.addArrangedSubview(labeledRow("LAN CIDR", field: lanField, help: "Через запятую. Прямой доступ без VPN."))

        stack.addArrangedSubview(sectionHeader("NAS (SMB)"))
        nasHostField = makeField(placeholder: "10.57.0.100")
        nasShareField = makeField(placeholder: "Nas")
        stack.addArrangedSubview(labeledRow("Хост", field: nasHostField, help: nil))
        stack.addArrangedSubview(labeledRow("Шара", field: nasShareField, help: nil))

        stack.addArrangedSubview(sectionHeader("DNS (опционально)"))
        dnsHomeField = makeField(placeholder: "10.57.0.1")
        dnsSuffixField = makeField(placeholder: "home.arpa, local")
        stack.addArrangedSubview(labeledRow("DNS home", field: dnsHomeField, help: nil))
        stack.addArrangedSubview(labeledRow("Суффиксы", field: dnsSuffixField, help: "Через запятую"))

        let note = NSTextField(wrappingLabelWithString: "Пустое поле = функция выключена. «Сохранить» пересоберёт sing-box.json (render).")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.preferredMaxLayoutWidth = 640
        stack.addArrangedSubview(note)

        return pane
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 12, weight: .semibold)
        f.textColor = .labelColor
        return f
    }

    private func makeField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.font = .systemFont(ofSize: 13)
        f.controlSize = .regular
        f.isEditable = true
        f.isBordered = true
        f.bezelStyle = .roundedBezel
        return f
    }

    private func labeledRow(_ title: String, field: NSTextField, help: String?) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 88).isActive = true

        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)

        if let help, !help.isEmpty {
            let h = NSTextField(labelWithString: help)
            h.font = .systemFont(ofSize: 11)
            h.textColor = .tertiaryLabelColor
            h.lineBreakMode = .byTruncatingTail
            h.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(h)
            h.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        }
        return row
    }

    private func reloadFromDisk() {
        macbookEditor.string = (try? WireGuardProfileStore.loadText(.macbook)) ?? ""
        homeEditor.string = (try? WireGuardProfileStore.loadText(.home)) ?? ""
        let s = AppSettings.load()
        lanField.stringValue = s.lanCidrs.joined(separator: ", ")
        nasHostField.stringValue = s.nasHost
        nasShareField.stringValue = s.nasShare
        dnsHomeField.stringValue = s.dnsHomeServer
        dnsSuffixField.stringValue = s.dnsSuffixes.joined(separator: ", ")
        refreshBadges()
        statusLabel.stringValue = "Готово к правке"
        statusLabel.textColor = .secondaryLabelColor
    }

    private func refreshBadges() {
        setBadge(badgeMacbook, name: "macbook.conf", ok: WireGuardProfileStore.exists(.macbook))
        setBadge(badgeHome, name: "home.conf", ok: WireGuardProfileStore.exists(.home))
    }

    private func statusLine() -> String {
        let mb = WireGuardProfileStore.exists(.macbook) ? "есть" : "нет"
        let hm = WireGuardProfileStore.exists(.home) ? "есть" : "нет"
        return "macbook.conf: \(mb) · home.conf: \(hm)"
    }

    private func profile(tag: Int) -> WireGuardProfileStore.Profile {
        tag == 0 ? .macbook : .home
    }

    private func editor(for profile: WireGuardProfileStore.Profile) -> NSTextView {
        profile == .macbook ? macbookEditor : homeEditor
    }

    @objc private func importConf(_ sender: NSButton) {
        let profile = profile(tag: sender.tag)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .data]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Импорт \(profile.fileName)"
        panel.message = "Выберите WireGuard .conf"
        panel.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                self.editor(for: profile).string = text
                self.setStatus("Импортирован \(url.lastPathComponent) → \(profile.fileName) (не сохранён)", ok: true)
            } catch {
                self.setStatus(error.localizedDescription, ok: false)
            }
        }
    }

    @objc private func pasteConf(_ sender: NSButton) {
        let profile = profile(tag: sender.tag)
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            setStatus("Буфер пуст", ok: false)
            return
        }
        editor(for: profile).string = text
        setStatus("Вставлено в \(profile.fileName) (не сохранено)", ok: true)
    }

    @objc private func saveAll() {
        do {
            try WireGuardProfileStore.saveText(.macbook, text: macbookEditor.string)
            try WireGuardProfileStore.saveText(.home, text: homeEditor.string)
            var s = AppSettings.load()
            s.lanCidrs = lanField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            s.nasHost = nasHostField.stringValue.trimmingCharacters(in: .whitespaces)
            s.nasShare = nasShareField.stringValue.trimmingCharacters(in: .whitespaces)
            if s.nasShare.isEmpty { s.nasShare = "Nas" }
            s.dnsHomeServer = dnsHomeField.stringValue.trimmingCharacters(in: .whitespaces)
            s.dnsSuffixes = dnsSuffixField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            try s.save()
            try MyVPNCLI.render()
            refreshBadges()
            setStatus("Сохранено · \(statusLine()) · render OK", ok: true)
        } catch {
            setStatus("Ошибка: \(error.localizedDescription)", ok: false)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Не удалось сохранить"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func setStatus(_ text: String, ok: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = ok ? .secondaryLabelColor : .systemRed
    }

    @objc private func openWGFolder() {
        try? FileManager.default.createDirectory(at: WireGuardProfileStore.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(WireGuardProfileStore.directory)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
