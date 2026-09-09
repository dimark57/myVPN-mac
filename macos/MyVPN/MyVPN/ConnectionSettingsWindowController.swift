import AppKit

/// Unified preferences: System Helper / Channels / Routes / Domain zones / Shares / Diagnostics / Update / Help.
/// Model: named channels (WG conf) + manual routes (Clash-style), not AllowedIPs.
final class ConnectionSettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Section: Int, CaseIterable {
        case systemHelper, channels, routes, domainZones, shares, diagnostics, update, help
        var title: String {
            switch self {
            case .systemHelper: return "System Helper"
            case .channels: return "Channels"
            case .routes: return "Routes"
            case .domainZones: return "Доменные зоны"
            case .shares: return "Shares"
            case .diagnostics: return "Диагностика"
            case .update: return "Update"
            case .help: return "Справка"
            }
        }
    }

    /// Menu-bar actions (doctor / RU / report) live on AppDelegate.
    weak var appDelegate: AppDelegate?

    private var settings = AppSettings.load()
    private var section: Section = .channels
    private var selectedChannelIndex: Int = 0
    private let workQueue = DispatchQueue(label: "local.myvpn.mac.settings", qos: .userInitiated)

    private var sidebar: NSTableView!
    private var contentBox: NSView!
    private var statusLabel: NSTextField!

    // Channels pane
    private var channelTable: NSTableView!
    private var nameField: NSTextField!
    private var idLabel: NSTextField!
    private var defaultCheck: NSButton!
    private var pingField: NSTextField!
    private var confEditor: NSTextView!
    private var channelDrafts: [String: String] = [:] // id → conf text
    private var autostartCheck: NSButton!

    // Routes pane
    private var routeTable: NSTableView!
    private var routeTypePopup: NSPopUpButton!
    private var routeMatchField: NSTextField!
    private var routeViaPopup: NSPopUpButton!
    private var routeNoteField: NSTextField!
    private var selectedRouteIndex: Int = 0

    // Shares pane
    private var nasHostField: NSTextField!
    private var nasShareField: NSTextField!
    private var dnsHomeField: NSTextField!
    private var dnsSuffixField: NSTextField!
    private var dnsViaPopup: NSPopUpButton!
    private var autoNasCheck: NSButton!

    // Domain zones / Diagnostics
    private var zonesStatusLabel: NSTextField!
    private var zonesActionButton: NSButton!
    private var diagStatusLabel: NSTextField!
    private var diagRunButton: NSButton!
    private var diagOpenButton: NSButton!
    private var diagSendButton: NSButton!
    private var autoDoctorCheck: NSButton!
    private var autoHealCheck: NSButton!
    private var diagJournalLabel: NSTextField!

    // System Helper / Update
    private var helperStatusLabel: NSTextField!
    private var helperActionButton: NSButton!
    private var helperUninstallButton: NSButton!
    private var updateStatusLabel: NSTextField!
    private var updateActionButton: NSButton!
    private var autoCheckBox: NSButton!
    private var autoInstallBox: NSButton!
    private var prefsBusy = false

    convenience init(section: Section = .channels) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки myVPN"
        window.minSize = NSSize(width: 700, height: 480)
        self.init(window: window)
        window.delegate = self
        window.center()
        self.section = section
        buildUI()
        reloadAll()
        selectSection(section)
    }

    func show(section: Section? = nil) {
        if let section {
            selectSection(section)
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Shell

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Fixed shell: header / body(sidebar+pane) / footer. Body height = window leftover,
        // so switching sections never moves the sidebar (same content frame for every item).
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .width
        header.spacing = 4
        header.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 12, right: 24)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.setContentHuggingPriority(.required, for: .vertical)
        header.setContentCompressionResistancePriority(.required, for: .vertical)
        let title = NSTextField(labelWithString: "Настройки")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let sub = Self.fillWidthLabel(
            "Каналы, маршруты, доменные зоны (RU), диагностика, обновление. Канал = WireGuard (.conf).")
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = .secondaryLabelColor
        header.addArrangedSubview(title)
        header.addArrangedSubview(sub)

        let headerLine = Self.hairline()
        let footerLine = Self.hairline()

        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.setContentHuggingPriority(.defaultLow, for: .vertical)
        body.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let sideScroll = NSScrollView()
        sideScroll.hasVerticalScroller = true
        sideScroll.borderType = .noBorder
        sideScroll.drawsBackground = false
        sideScroll.translatesAutoresizingMaskIntoConstraints = false

        sidebar = NSTableView()
        sidebar.headerView = nil
        sidebar.style = .sourceList
        sidebar.rowSizeStyle = .default
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("s"))
        sidebar.addTableColumn(col)
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.target = self
        sidebar.action = #selector(sidebarClicked)
        sideScroll.documentView = sidebar

        let divider = Self.vline()

        contentBox = NSView()
        contentBox.translatesAutoresizingMaskIntoConstraints = false
        contentBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentBox.setContentHuggingPriority(.defaultLow, for: .vertical)

        body.addSubview(sideScroll)
        body.addSubview(divider)
        body.addSubview(contentBox)
        NSLayoutConstraint.activate([
            sideScroll.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            sideScroll.topAnchor.constraint(equalTo: body.topAnchor),
            sideScroll.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            sideScroll.widthAnchor.constraint(equalToConstant: 160),

            divider.leadingAnchor.constraint(equalTo: sideScroll.trailingAnchor),
            divider.topAnchor.constraint(equalTo: body.topAnchor),
            divider.bottomAnchor.constraint(equalTo: body.bottomAnchor),

            contentBox.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            contentBox.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            contentBox.topAnchor.constraint(equalTo: body.topAnchor),
            contentBox.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        footer.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 16, right: 20)
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.setContentHuggingPriority(.required, for: .vertical)
        footer.setContentCompressionResistancePriority(.required, for: .vertical)

        let save = NSButton(title: "Сохранить", target: self, action: #selector(saveAll))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let folder = NSButton(title: "Папка конфигов", target: self, action: #selector(openWGFolder))
        folder.bezelStyle = .rounded
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let close = NSButton(title: "Закрыть", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"

        footer.addArrangedSubview(save)
        footer.addArrangedSubview(folder)
        footer.addArrangedSubview(statusLabel)
        let sp = NSView()
        sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(sp)
        footer.addArrangedSubview(close)

        root.addSubview(header)
        root.addSubview(headerLine)
        root.addSubview(body)
        root.addSubview(footerLine)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),

            headerLine.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerLine.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerLine.topAnchor.constraint(equalTo: header.bottomAnchor),

            body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.topAnchor.constraint(equalTo: headerLine.bottomAnchor),
            body.bottomAnchor.constraint(equalTo: footerLine.topAnchor),
            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 380),

            footerLine.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerLine.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    private static func hairline() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 1).isActive = true
        b.setContentHuggingPriority(.required, for: .vertical)
        b.setContentCompressionResistancePriority(.required, for: .vertical)
        return b
    }

    private static func vline() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return b
    }

    private func selectSection(_ s: Section) {
        commitChannelEditor()
        commitRouteEditor()
        section = s
        sidebar.reloadData()
        sidebar.selectRowIndexes(IndexSet(integer: s.rawValue), byExtendingSelection: false)
        rebuildContent()
    }

    @objc private func sidebarClicked() {
        let row = sidebar.clickedRow
        guard row >= 0, let s = Section(rawValue: row) else { return }
        selectSection(s)
    }

    private func rebuildContent() {
        contentBox.subviews.forEach { $0.removeFromSuperview() }
        let pane: NSView
        switch section {
        case .systemHelper: pane = makeSystemHelperPane()
        case .channels: pane = makeChannelsPane()
        case .routes: pane = makeRoutesPane()
        case .domainZones: pane = makeDomainZonesPane()
        case .shares: pane = makeSharesPane()
        case .diagnostics: pane = makeDiagnosticsPane()
        case .update: pane = makeUpdatePane()
        case .help: pane = makeHelpPane()
        }
        // Same content frame for every menu item. Channels/Routes/Help fill height;
        // short panes stay top-aligned via spacer so sidebar never jumps.
        let host: NSView
        switch section {
        case .channels, .routes, .help:
            host = pane
        case .systemHelper, .domainZones, .shares, .diagnostics, .update:
            let shell = NSStackView()
            shell.orientation = .vertical
            shell.alignment = .width
            shell.distribution = .fill
            shell.spacing = 0
            pane.setContentHuggingPriority(.required, for: .vertical)
            shell.addArrangedSubview(pane)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
            shell.addArrangedSubview(spacer)
            host = shell
        }
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.defaultLow, for: .vertical)
        host.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        contentBox.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: contentBox.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: contentBox.trailingAnchor),
            host.topAnchor.constraint(equalTo: contentBox.topAnchor),
            host.bottomAnchor.constraint(equalTo: contentBox.bottomAnchor),
        ])
    }

    // MARK: - Channels

    private func makeChannelsPane() -> NSView {
        let wrap = NSStackView()
        wrap.orientation = .vertical
        wrap.spacing = 8
        wrap.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 24)
        wrap.distribution = .fill
        wrap.setContentHuggingPriority(.defaultLow, for: .vertical)

        autostartCheck = NSButton(
            checkboxWithTitle: "Автоподнятие после перезагрузки",
            target: self,
            action: #selector(toggleAutostart)
        )
        autostartCheck.state = (MyVPNCLI.autostartEnabled() || LoginItemController.isEnabled) ? .on : .off
        autostartCheck.setContentHuggingPriority(.required, for: .vertical)
        wrap.addArrangedSubview(autostartCheck)

        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 12
        root.alignment = .top
        root.distribution = .fill
        root.setContentHuggingPriority(.defaultLow, for: .vertical)

        let left = NSStackView()
        left.orientation = .vertical
        left.spacing = 8
        left.distribution = .fill
        left.widthAnchor.constraint(equalToConstant: 180).isActive = true
        left.setContentHuggingPriority(.defaultLow, for: .vertical)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        channelTable = NSTableView()
        channelTable.headerView = nil
        channelTable.allowsEmptySelection = false
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ch"))
        channelTable.addTableColumn(c)
        channelTable.dataSource = self
        channelTable.delegate = self
        channelTable.target = self
        channelTable.action = #selector(channelClicked)
        scroll.documentView = channelTable
        left.addArrangedSubview(scroll)

        let btns = NSStackView()
        btns.orientation = .horizontal
        btns.spacing = 6
        btns.setContentHuggingPriority(.required, for: .vertical)
        let add = NSButton(title: "+", target: self, action: #selector(addChannel))
        add.bezelStyle = .rounded
        add.controlSize = .small
        let del = NSButton(title: "−", target: self, action: #selector(removeChannel))
        del.bezelStyle = .rounded
        del.controlSize = .small
        btns.addArrangedSubview(add)
        btns.addArrangedSubview(del)
        left.addArrangedSubview(btns)
        root.addArrangedSubview(left)

        let right = NSStackView()
        right.orientation = .vertical
        right.spacing = 8
        right.distribution = .fill
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)
        right.setContentHuggingPriority(.defaultLow, for: .vertical)

        let meta = NSGridView()
        meta.columnSpacing = 10
        meta.rowSpacing = 8
        nameField = field("", maxWidth: 240)
        nameField.placeholderString = "Имя канала"
        idLabel = NSTextField(labelWithString: "")
        idLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        idLabel.textColor = .secondaryLabelColor
        defaultCheck = NSButton(checkboxWithTitle: "Канал по умолчанию (final / egress)", target: self, action: #selector(defaultToggled))
        pingField = field("", maxWidth: 160)
        pingField.placeholderString = "10.8.0.1"
        meta.addRow(with: [lab("Имя"), nameField!])
        meta.addRow(with: [lab("id / файл"), idLabel!])
        meta.addRow(with: [lab("Ping"), pingField!])
        meta.column(at: 0).xPlacement = .trailing
        meta.column(at: 1).xPlacement = .leading
        for i in 0..<meta.numberOfRows {
            meta.row(at: i).yPlacement = .center
            meta.row(at: i).topPadding = 1
            meta.row(at: i).bottomPadding = 1
        }
        meta.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        meta.setContentHuggingPriority(.defaultHigh, for: .vertical)
        meta.setContentCompressionResistancePriority(.required, for: .vertical)
        right.addArrangedSubview(meta)
        right.addArrangedSubview(defaultCheck)

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.setContentHuggingPriority(.required, for: .vertical)
        let hint = NSTextField(labelWithString: "Шаблон WireGuard — одинаковый для всех каналов")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let imp = NSButton(title: "Импорт…", target: self, action: #selector(importConf))
        imp.bezelStyle = .rounded
        imp.controlSize = .small
        let paste = NSButton(title: "Из буфера", target: self, action: #selector(pasteConf))
        paste.bezelStyle = .rounded
        paste.controlSize = .small
        bar.addArrangedSubview(hint)
        let sp = NSView()
        sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(sp)
        bar.addArrangedSubview(imp)
        bar.addArrangedSubview(paste)
        right.addArrangedSubview(bar)

        confEditor = makeEditor()
        let escroll = NSScrollView()
        escroll.hasVerticalScroller = true
        escroll.borderType = .bezelBorder
        escroll.documentView = confEditor
        escroll.translatesAutoresizingMaskIntoConstraints = false
        escroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        escroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        right.addArrangedSubview(escroll)

        root.addArrangedSubview(right)
        wrap.addArrangedSubview(root)
        loadChannelSelection()
        return wrap
    }

    @objc private func channelClicked() {
        commitChannelEditor()
        let row = channelTable.clickedRow
        guard row >= 0, row < settings.channels.count else { return }
        selectedChannelIndex = row
        loadChannelSelection()
    }

    private func loadChannelSelection() {
        guard selectedChannelIndex < settings.channels.count else { return }
        let ch = settings.channels[selectedChannelIndex]
        nameField?.stringValue = ch.name
        idLabel?.stringValue = "\(ch.id) · \(ch.fileName)"
        defaultCheck?.state = ch.isDefault ? .on : .off
        pingField?.stringValue = ch.ping
        if channelDrafts[ch.id] == nil {
            channelDrafts[ch.id] = (try? WireGuardProfileStore.loadText(fileName: ch.fileName)) ?? WireGuardProfileStore.template()
        }
        confEditor?.string = channelDrafts[ch.id] ?? ""
        channelTable?.reloadData()
        channelTable?.selectRowIndexes(IndexSet(integer: selectedChannelIndex), byExtendingSelection: false)
    }

    private func commitChannelEditor() {
        guard section == .channels,
              selectedChannelIndex < settings.channels.count,
              nameField != nil else { return }
        var ch = settings.channels[selectedChannelIndex]
        ch.name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if ch.name.isEmpty { ch.name = ch.id }
        ch.ping = pingField.stringValue.trimmingCharacters(in: .whitespaces)
        settings.channels[selectedChannelIndex] = ch
        channelDrafts[ch.id] = confEditor.string
    }

    @objc private func defaultToggled() {
        guard selectedChannelIndex < settings.channels.count else { return }
        let on = defaultCheck.state == .on
        for i in settings.channels.indices {
            settings.channels[i].isDefault = on && i == selectedChannelIndex
        }
        if !settings.channels.contains(where: \.isDefault) {
            settings.channels[selectedChannelIndex].isDefault = true
            defaultCheck.state = .on
        }
        channelTable.reloadData()
    }

    @objc private func addChannel() {
        commitChannelEditor()
        let existing = settings.channels.map(\.id)
        let id = AppSettings.slugify("channel", existing: existing)
        let ch = VPNChannel(id: id, name: "Channel", file: "\(id).conf", isDefault: false, ping: "")
        settings.channels.append(ch)
        channelDrafts[id] = WireGuardProfileStore.template()
        selectedChannelIndex = settings.channels.count - 1
        channelTable.reloadData()
        loadChannelSelection()
        nameField.becomeFirstResponder()
    }

    @objc private func removeChannel() {
        guard settings.channels.count > 1, selectedChannelIndex < settings.channels.count else {
            setStatus("Нужен хотя бы один канал", ok: false)
            return
        }
        let ch = settings.channels[selectedChannelIndex]
        let wasDefault = ch.isDefault
        channelDrafts.removeValue(forKey: ch.id)
        settings.channels.remove(at: selectedChannelIndex)
        settings.routes = settings.routes.map { r in
            var x = r
            if x.via == ch.id { x.via = "direct" }
            return x
        }
        if wasDefault, let i = settings.channels.indices.first {
            settings.channels[i].isDefault = true
        }
        selectedChannelIndex = min(selectedChannelIndex, settings.channels.count - 1)
        channelTable.reloadData()
        loadChannelSelection()
    }

    @objc private func importConf() {
        guard selectedChannelIndex < settings.channels.count else { return }
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                self.confEditor.string = text
                let id = self.settings.channels[self.selectedChannelIndex].id
                self.channelDrafts[id] = text
                self.setStatus("Импортирован \(url.lastPathComponent)", ok: true)
            }
        }
    }

    @objc private func pasteConf() {
        guard selectedChannelIndex < settings.channels.count,
              let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            setStatus("Буфер пуст", ok: false)
            return
        }
        confEditor.string = text
        channelDrafts[settings.channels[selectedChannelIndex].id] = text
        setStatus("Вставлено из буфера", ok: true)
    }

    // MARK: - Routes

    private func makeRoutesPane() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 24)
        root.distribution = .fill
        root.alignment = .width
        root.setContentHuggingPriority(.defaultLow, for: .vertical)

        let intro = Self.fillWidthLabel(
            "Порядок сверху вниз. via = id канала или direct. Rule-set: geosite-ru / geoip-ru после «Доменные зоны → Обновить RU».")
        intro.font = .systemFont(ofSize: 11)
        intro.textColor = .secondaryLabelColor
        intro.setContentHuggingPriority(.required, for: .vertical)
        root.addArrangedSubview(intro)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        routeTable = NSTableView()
        for (id, title, w) in [("m", "Match", 280), ("v", "Via", 100), ("n", "Note", 140)] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = w
            routeTable.addTableColumn(col)
        }
        routeTable.dataSource = self
        routeTable.delegate = self
        routeTable.target = self
        routeTable.action = #selector(routeClicked)
        scroll.documentView = routeTable
        root.addArrangedSubview(scroll)

        let btns = NSStackView()
        btns.orientation = .horizontal
        btns.spacing = 6
        btns.setContentHuggingPriority(.required, for: .vertical)
        for (t, a) in [("+", #selector(addRoute)), ("−", #selector(removeRoute)), ("↑", #selector(moveRouteUp)), ("↓", #selector(moveRouteDown))] as [(String, Selector)] {
            let b = NSButton(title: t, target: self, action: a)
            b.bezelStyle = .rounded
            b.controlSize = .small
            btns.addArrangedSubview(b)
        }
        root.addArrangedSubview(btns)

        let form = NSGridView()
        form.columnSpacing = 10
        form.rowSpacing = 8
        routeTypePopup = NSPopUpButton()
        routeTypePopup.addItems(withTitles: ["CIDR", "rule_set"])
        routeMatchField = field("", maxWidth: 420)
        routeMatchField.placeholderString = "10.57.0.0/24, 10.13.13.0/24  или  geosite-ru"
        routeViaPopup = NSPopUpButton()
        refillViaPopup()
        routeNoteField = field("", maxWidth: 280)
        form.addRow(with: [lab("Тип"), routeTypePopup!])
        form.addRow(with: [lab("Match"), routeMatchField!])
        form.addRow(with: [lab("Via"), routeViaPopup!])
        form.addRow(with: [lab("Заметка"), routeNoteField!])
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .leading
        for i in 0..<form.numberOfRows {
            form.row(at: i).yPlacement = .center
            form.row(at: i).topPadding = 1
            form.row(at: i).bottomPadding = 1
        }
        form.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        form.setContentHuggingPriority(.defaultHigh, for: .vertical)
        form.setContentCompressionResistancePriority(.required, for: .vertical)
        root.addArrangedSubview(form)

        loadRouteSelection()
        return root
    }

    private func refillViaPopup() {
        routeViaPopup?.removeAllItems()
        routeViaPopup?.addItem(withTitle: "direct")
        for ch in settings.channels {
            routeViaPopup?.addItem(withTitle: "\(ch.id) — \(ch.name)")
            routeViaPopup?.lastItem?.representedObject = ch.id
        }
        // first item direct has representedObject nil → treat as direct
        routeViaPopup?.item(at: 0)?.representedObject = "direct"
    }

    @objc private func routeClicked() {
        commitRouteEditor()
        let row = routeTable.clickedRow
        guard row >= 0, row < settings.routes.count else { return }
        selectedRouteIndex = row
        loadRouteSelection()
    }

    private func loadRouteSelection() {
        guard selectedRouteIndex < settings.routes.count else { return }
        refillViaPopup()
        let r = settings.routes[selectedRouteIndex]
        routeTypePopup?.selectItem(at: r.kind == .cidr ? 0 : 1)
        routeMatchField?.stringValue = r.matchDisplay
        if let idx = routeViaPopup?.indexOfItem(withTitle: viaTitle(for: r.via)) {
            routeViaPopup?.selectItem(at: idx)
        } else {
            // find by representedObject
            if let items = routeViaPopup?.itemArray {
                for (i, item) in items.enumerated() {
                    if (item.representedObject as? String) == r.via {
                        routeViaPopup?.selectItem(at: i)
                        break
                    }
                }
            }
        }
        routeNoteField?.stringValue = r.note
        routeTable?.reloadData()
        routeTable?.selectRowIndexes(IndexSet(integer: selectedRouteIndex), byExtendingSelection: false)
    }

    private func viaTitle(for id: String) -> String {
        if id == "direct" { return "direct" }
        if let ch = settings.channels.first(where: { $0.id == id }) {
            return "\(ch.id) — \(ch.name)"
        }
        return id
    }

    private func commitRouteEditor() {
        guard section == .routes,
              selectedRouteIndex < settings.routes.count,
              routeMatchField != nil else { return }
        var r = settings.routes[selectedRouteIndex]
        r.kind = routeTypePopup.indexOfSelectedItem == 0 ? .cidr : .ruleSet
        let raw = routeMatchField.stringValue
        if r.kind == .ruleSet {
            r.match = [raw.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }
        } else {
            r.match = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let via = routeViaPopup.selectedItem?.representedObject as? String {
            r.via = via
        } else {
            r.via = "direct"
        }
        r.note = routeNoteField.stringValue.trimmingCharacters(in: .whitespaces)
        settings.routes[selectedRouteIndex] = r
        routeTable.reloadData()
    }

    @objc private func addRoute() {
        commitRouteEditor()
        let r = VPNRoute(
            id: String(UUID().uuidString.prefix(8)),
            kind: .cidr,
            match: ["10.0.0.0/24"],
            via: settings.channels.first(where: { !$0.isDefault })?.id ?? "direct",
            note: ""
        )
        settings.routes.append(r)
        selectedRouteIndex = settings.routes.count - 1
        routeTable.reloadData()
        loadRouteSelection()
    }

    @objc private func removeRoute() {
        guard selectedRouteIndex < settings.routes.count else { return }
        settings.routes.remove(at: selectedRouteIndex)
        selectedRouteIndex = min(selectedRouteIndex, max(0, settings.routes.count - 1))
        routeTable.reloadData()
        if !settings.routes.isEmpty { loadRouteSelection() }
    }

    @objc private func moveRouteUp() {
        commitRouteEditor()
        guard selectedRouteIndex > 0 else { return }
        settings.routes.swapAt(selectedRouteIndex, selectedRouteIndex - 1)
        selectedRouteIndex -= 1
        routeTable.reloadData()
        loadRouteSelection()
    }

    @objc private func moveRouteDown() {
        commitRouteEditor()
        guard selectedRouteIndex + 1 < settings.routes.count else { return }
        settings.routes.swapAt(selectedRouteIndex, selectedRouteIndex + 1)
        selectedRouteIndex += 1
        routeTable.reloadData()
        loadRouteSelection()
    }

    // MARK: - System Helper / Shares / Update / Help

    private func makeSystemHelperPane() -> NSView {
        let root = prefsColumn()

        root.addArrangedSubview(sectionTitle("Системный помощник"))
        let intro = Self.fillWidthLabel(
            "LaunchDaemon для On/Off без пароля. Установка — один раз, с паролем администратора.")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        root.addArrangedSubview(intro)

        helperStatusLabel = NSTextField(labelWithString: "")
        helperStatusLabel.font = .systemFont(ofSize: 13)
        root.addArrangedSubview(helperStatusLabel)

        let btns = NSStackView()
        btns.orientation = .horizontal
        btns.spacing = 10
        btns.alignment = .centerY
        helperActionButton = NSButton(title: "Установить", target: self, action: #selector(helperInstallOrReinstall))
        helperActionButton.bezelStyle = .rounded
        helperUninstallButton = NSButton(title: "Удалить", target: self, action: #selector(helperUninstall))
        helperUninstallButton.bezelStyle = .rounded
        btns.addArrangedSubview(helperActionButton)
        btns.addArrangedSubview(helperUninstallButton)
        let btnSpacer = NSView()
        btnSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        btns.addArrangedSubview(btnSpacer)
        root.addArrangedSubview(btns)

        refreshHelperPane()
        return root
    }

    private func refreshHelperPane() {
        let ok = MyVPNCLI.helperInstalled()
        if ok {
            helperStatusLabel?.stringValue = "Статус: установлен · socket OK"
            helperStatusLabel?.textColor = .secondaryLabelColor
            helperActionButton?.title = "Переустановить…"
            helperUninstallButton?.isEnabled = !prefsBusy
        } else if MyVPNHelper.filesPresent {
            helperStatusLabel?.stringValue = "Статус: файлы есть, socket нет — нужна переустановка"
            helperStatusLabel?.textColor = .systemOrange
            helperActionButton?.title = "Переустановить…"
            helperUninstallButton?.isEnabled = !prefsBusy
        } else {
            helperStatusLabel?.stringValue = "Статус: не установлен"
            helperStatusLabel?.textColor = .secondaryLabelColor
            helperActionButton?.title = "Установить…"
            helperUninstallButton?.isEnabled = false
        }
        helperActionButton?.isEnabled = !prefsBusy
    }

    @objc private func helperInstallOrReinstall() {
        guard !prefsBusy else { return }
        prefsBusy = true
        refreshHelperPane()
        setStatus("Устанавливаю помощник…", ok: true)
        workQueue.async { [weak self] in
            do {
                try MyVPNHelper.install()
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.refreshHelperPane()
                    self?.setStatus("Помощник установлен", ok: true)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.refreshHelperPane()
                    self?.setStatus(error.localizedDescription, ok: false)
                }
            }
        }
    }

    @objc private func helperUninstall() {
        guard !prefsBusy else { return }
        prefsBusy = true
        refreshHelperPane()
        setStatus("Удаляю помощник…", ok: true)
        workQueue.async { [weak self] in
            do {
                try MyVPNHelper.uninstall()
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.refreshHelperPane()
                    self?.setStatus("Помощник удалён", ok: true)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.refreshHelperPane()
                    self?.setStatus(error.localizedDescription, ok: false)
                }
            }
        }
    }

    // MARK: - Domain zones / Diagnostics

    private func makeDomainZonesPane() -> NSView {
        let root = prefsColumn()

        root.addArrangedSubview(sectionTitle("Доменные зоны (RU)"))
        let intro = Self.fillWidthLabel(
            "Rule-set geosite-ru / geoip-ru для маршрутов. Обновление скачивает свежие списки в ~/.config/myvpn/rules.")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        root.addArrangedSubview(intro)

        let rules = appDelegate?.settingsRulesStatus() ?? RulesStatus.load()
        zonesStatusLabel = NSTextField(labelWithString: "\(rules.geositeLine)  ·  \(rules.geoipLine)")
        zonesStatusLabel.font = .systemFont(ofSize: 13)
        zonesStatusLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(zonesStatusLabel)

        zonesActionButton = NSButton(title: "Обновить RU", target: self, action: #selector(updateDomainZones))
        zonesActionButton.bezelStyle = .rounded
        root.addArrangedSubview(zonesActionButton)
        return root
    }

    @objc private func updateDomainZones() {
        guard !prefsBusy else { return }
        prefsBusy = true
        zonesActionButton?.isEnabled = false
        zonesStatusLabel?.stringValue = "Обновляю…"
        setStatus("Обновляю списки RU…", ok: true)
        workQueue.async { [weak self] in
            do {
                try MyVPNCLI.updateRules()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.prefsBusy = false
                    self.zonesActionButton?.isEnabled = true
                    self.appDelegate?.settingsReloadRules()
                    let rules = self.appDelegate?.settingsRulesStatus() ?? RulesStatus.load()
                    self.zonesStatusLabel?.stringValue = "\(rules.geositeLine)  ·  \(rules.geoipLine)"
                    self.setStatus("Списки RU обновлены · \(rules.notifyStamp)", ok: true)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.zonesActionButton?.isEnabled = true
                    self?.setStatus(error.localizedDescription, ok: false)
                }
            }
        }
    }

    private func makeDiagnosticsPane() -> NSView {
        let root = prefsColumn(spacing: 12)

        root.addArrangedSubview(sectionTitle("Автодоктор"))
        let intro = Self.fillWidthLabel(
            "FDIR 0.5: L0 полётный журнал → L1 triage (≤8с) → heal с verify. Ручной Off = desired OFF (без auto-heal). Safe Mode останавливает thrash.")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        root.addArrangedSubview(intro)

        autoDoctorCheck = NSButton(
            checkboxWithTitle: "Автодиагностика при отвале",
            target: self,
            action: #selector(autoDoctorToggled)
        )
        autoDoctorCheck.state = AutoDoctor.autoDoctorEnabled ? .on : .off
        root.addArrangedSubview(autoDoctorCheck)

        autoHealCheck = NSButton(
            checkboxWithTitle: "Автовосстановление (down→up / mount-nas / flush-dns)",
            target: self,
            action: #selector(autoHealToggled)
        )
        autoHealCheck.state = AutoDoctor.autoHealEnabled ? .on : .off
        autoHealCheck.isEnabled = AutoDoctor.autoDoctorEnabled
        root.addArrangedSubview(autoHealCheck)

        if HealCircuitBreaker.isSafeMode {
            let safeBtn = NSButton(
                title: "Выйти из Safe Mode (Resume автоheal)",
                target: self,
                action: #selector(resumeSafeModeFromSettings)
            )
            safeBtn.bezelStyle = .rounded
            root.addArrangedSubview(safeBtn)
        }

        let doc = appDelegate?.settingsDoctorStatus() ?? DoctorStatus.load()
        diagStatusLabel = Self.fillWidthLabel(diagStatusText(doc))
        diagStatusLabel.font = .systemFont(ofSize: 13)
        root.addArrangedSubview(diagStatusLabel)

        let btns = NSStackView()
        btns.orientation = .horizontal
        btns.spacing = 10
        btns.alignment = .centerY
        diagRunButton = NSButton(title: "Провести (L1)", target: self, action: #selector(runDiagnosticsFromSettings))
        diagRunButton.bezelStyle = .rounded
        let deepBtn = NSButton(title: "Полная (L2)", target: self, action: #selector(runDeepDiagnosticsFromSettings))
        deepBtn.bezelStyle = .rounded
        diagOpenButton = NSButton(title: "Открыть отчёт", target: self, action: #selector(openDiagnosticsReport))
        diagOpenButton.bezelStyle = .rounded
        diagSendButton = NSButton(title: "Отправить разработчику", target: self, action: #selector(sendDiagnosticsReport))
        diagSendButton.bezelStyle = .rounded
        btns.addArrangedSubview(diagRunButton)
        btns.addArrangedSubview(deepBtn)
        btns.addArrangedSubview(diagOpenButton)
        btns.addArrangedSubview(diagSendButton)
        let btnSpacer = NSView()
        btnSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        btns.addArrangedSubview(btnSpacer)
        root.addArrangedSubview(btns)

        root.addArrangedSubview(sectionTitle("Коды отвалов"))
        let codes = Self.fillWidthLabel(AutoDoctor.catalog.map {
            "\($0.code) — \($0.symptom) → \($0.action)"
        }.joined(separator: "\n"))
        codes.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        codes.textColor = .secondaryLabelColor
        root.addArrangedSubview(codes)

        root.addArrangedSubview(sectionTitle("Журнал (drops.log)"))
        diagJournalLabel = Self.fillWidthLabel(DropLogger.tailLines(14))
        diagJournalLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagJournalLabel.textColor = .labelColor
        root.addArrangedSubview(diagJournalLabel)

        refreshDiagnosticsButtons()
        return root
    }

    @objc private func autoDoctorToggled() {
        let on = autoDoctorCheck.state == .on
        AutoDoctor.autoDoctorEnabled = on
        if !on {
            AutoDoctor.autoHealEnabled = false
            autoHealCheck?.state = .off
        }
        autoHealCheck?.isEnabled = on
        setStatus(on ? "Автодиагностика вкл" : "Автодиагностика выкл", ok: true)
    }

    @objc private func autoHealToggled() {
        guard AutoDoctor.autoDoctorEnabled else {
            autoHealCheck.state = .off
            return
        }
        let on = autoHealCheck.state == .on
        AutoDoctor.autoHealEnabled = on
        setStatus(on ? "Автовосстановление вкл" : "Автовосстановление выкл", ok: true)
    }

    private func diagStatusText(_ doc: DoctorStatus) -> String {
        if !doc.hasResult {
            return "Последний результат: нет данных — нажми «Провести диагностику»."
        }
        return "Последний результат: \(doc.severityLabel)\n\(doc.userHeadline) · \(doc.displayStamp)"
    }

    private func refreshDiagnosticsButtons() {
        let exists = FileManager.default.fileExists(atPath: DoctorStatus.latestURL.path)
        diagOpenButton?.isEnabled = exists && !prefsBusy
        diagSendButton?.isEnabled = exists && !prefsBusy
        diagRunButton?.isEnabled = !prefsBusy
    }

    @objc private func runDiagnosticsFromSettings() {
        guard !prefsBusy else { return }
        prefsBusy = true
        refreshDiagnosticsButtons()
        setStatus("Диагностика L1…", ok: true)
        workQueue.async { [weak self] in
            do {
                _ = try MyVPNCLI.doctor(deep: false)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.prefsBusy = false
                    self.appDelegate?.settingsReloadDoctor()
                    let doc = self.appDelegate?.settingsDoctorStatus() ?? DoctorStatus.load()
                    self.diagStatusLabel?.stringValue = self.diagStatusText(doc)
                    self.diagJournalLabel?.stringValue = DropLogger.tailLines(14)
                    self.refreshDiagnosticsButtons()
                    self.setStatus(doc.severityLabel, ok: doc.overall != "FAIL")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.refreshDiagnosticsButtons()
                    self?.setStatus(error.localizedDescription, ok: false)
                }
            }
        }
    }

    @objc private func runDeepDiagnosticsFromSettings() {
        appDelegate?.settingsRunDoctorDeep()
        setStatus("L2 запущена — смотри уведомление", ok: true)
    }

    @objc private func resumeSafeModeFromSettings() {
        appDelegate?.settingsResumeSafeMode()
        setStatus("Safe Mode снят", ok: true)
    }

    @objc private func openDiagnosticsReport() {
        if let appDelegate {
            appDelegate.settingsOpenDoctorReport()
            return
        }
        let url = DoctorStatus.latestURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            setStatus("Отчёта ещё нет", ok: false)
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func sendDiagnosticsReport() {
        if let appDelegate {
            appDelegate.settingsSendDoctorReport()
            setStatus("Отчёт в буфере · GitHub Issues", ok: true)
            return
        }
        setStatus("Нет связи с menu bar", ok: false)
    }

    private func makeSharesPane() -> NSView {
        let root = prefsColumn()

        autoNasCheck = NSButton(
            checkboxWithTitle: "Автоподключение NAS после перезагрузки",
            target: self,
            action: #selector(toggleAutoNAS)
        )
        let autoUp = MyVPNCLI.autostartEnabled() || LoginItemController.isEnabled
        autoNasCheck.state = MyVPNCLI.autoNASEnabled() ? .on : .off
        autoNasCheck.isEnabled = autoUp
        root.addArrangedSubview(autoNasCheck)
        if !autoUp {
            let hint = NSTextField(labelWithString: "Сначала включи автоподнятие в Channels.")
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = .tertiaryLabelColor
            root.addArrangedSubview(hint)
        }

        root.addArrangedSubview(sectionTitle("NAS (SMB)"))
        nasHostField = field(settings.nasHost, maxWidth: 220)
        nasHostField.placeholderString = "10.57.0.100"
        nasShareField = field(settings.nasShare, maxWidth: 220)
        nasShareField.placeholderString = "Nas"
        root.addArrangedSubview(row("Хост", nasHostField))
        root.addArrangedSubview(row("Шара", nasShareField))

        root.addArrangedSubview(sectionTitle("DNS (опционально)"))
        dnsHomeField = field(settings.dnsHomeServer, maxWidth: 220)
        dnsHomeField.placeholderString = "10.57.0.1"
        dnsSuffixField = field(settings.dnsSuffixes.joined(separator: ", "), maxWidth: 320)
        dnsSuffixField.placeholderString = "home.arpa"
        dnsViaPopup = NSPopUpButton()
        for ch in settings.channels {
            dnsViaPopup.addItem(withTitle: "\(ch.id) — \(ch.name)")
            dnsViaPopup.lastItem?.representedObject = ch.id
        }
        if let i = dnsViaPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == settings.dnsVia }) {
            dnsViaPopup.selectItem(at: i)
        }
        root.addArrangedSubview(row("DNS home", dnsHomeField))
        root.addArrangedSubview(row("Суффиксы", dnsSuffixField))
        root.addArrangedSubview(row("Через канал", dnsViaPopup))

        let note = Self.fillWidthLabel("LAN CIDR больше не отдельное поле — добавь direct-маршрут на вкладке Routes.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        root.addArrangedSubview(note)
        return root
    }

    private func makeUpdatePane() -> NSView {
        let root = prefsColumn()

        root.addArrangedSubview(sectionTitle("Обновление приложения"))
        let intro = Self.fillWidthLabel(
            "Источник: GitHub Releases (myVPN.app.zip). Галочки — поведение в фоне; кнопка — вручную.")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        root.addArrangedSubview(intro)

        let ver = NSTextField(labelWithString: "Текущая версия: v\(UpdateChecker.currentVersion)")
        ver.font = .systemFont(ofSize: 13)
        root.addArrangedSubview(ver)

        autoCheckBox = NSButton(
            checkboxWithTitle: "Автопроверка при запуске и каждый час",
            target: self,
            action: #selector(autoCheckToggled)
        )
        autoCheckBox.state = UpdateChecker.autoCheckEnabled ? .on : .off
        root.addArrangedSubview(autoCheckBox)

        autoInstallBox = NSButton(
            checkboxWithTitle: "Автоустановка, если найдена новая версия",
            target: self,
            action: #selector(autoInstallToggled)
        )
        autoInstallBox.state = UpdateChecker.autoInstallEnabled ? .on : .off
        autoInstallBox.isEnabled = UpdateChecker.autoCheckEnabled
        root.addArrangedSubview(autoInstallBox)

        let hint = Self.fillWidthLabel(
            "Если автоустановка выкл., при новой версии будет только уведомление.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        root.addArrangedSubview(hint)

        updateStatusLabel = NSTextField(labelWithString: "")
        updateStatusLabel.font = .systemFont(ofSize: 12)
        updateStatusLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(updateStatusLabel)

        updateActionButton = NSButton(title: "Проверить обновление", target: self, action: #selector(checkForUpdate))
        updateActionButton.bezelStyle = .rounded
        updateActionButton.keyEquivalent = ""
        root.addArrangedSubview(updateActionButton)
        return root
    }

    @objc private func autoCheckToggled() {
        let on = autoCheckBox.state == .on
        UpdateChecker.autoCheckEnabled = on
        autoInstallBox?.isEnabled = on
        updateStatusLabel?.stringValue = on ? "Автопроверка включена" : "Автопроверка выключена"
    }

    @objc private func autoInstallToggled() {
        let on = autoInstallBox.state == .on
        UpdateChecker.autoInstallEnabled = on
        updateStatusLabel?.stringValue = on ? "Автоустановка включена" : "Автоустановка выключена (только уведомление)"
    }

    @objc private func checkForUpdate() {
        guard !prefsBusy else { return }
        prefsBusy = true
        updateActionButton?.isEnabled = false
        updateStatusLabel?.stringValue = "Проверяю…"
        Task { [weak self] in
            let result = await UpdateChecker.check()
            await MainActor.run {
                guard let self else { return }
                self.prefsBusy = false
                self.updateActionButton?.isEnabled = true
                if result.upToDate {
                    self.updateStatusLabel?.stringValue = result.message
                    return
                }
                self.updateStatusLabel?.stringValue = result.message
                let alert = NSAlert()
                alert.messageText = "Доступно обновление"
                alert.informativeText = result.message + "\n\nСкачать и установить из GitHub Releases?"
                alert.addButton(withTitle: "Обновить")
                alert.addButton(withTitle: "Открыть на GitHub")
                alert.addButton(withTitle: "Позже")
                let choice = alert.runModal()
                if choice == .alertFirstButtonReturn {
                    guard let url = result.assetURL else {
                        if let page = result.releaseURL { NSWorkspace.shared.open(page) }
                        self.updateStatusLabel?.stringValue = "В релизе нет myVPN.app.zip"
                        return
                    }
                    self.prefsBusy = true
                    self.updateActionButton?.isEnabled = false
                    self.updateStatusLabel?.stringValue = "Скачиваю…"
                    Task {
                        do {
                            try await UpdateChecker.install(from: url)
                        } catch {
                            await MainActor.run {
                                self.prefsBusy = false
                                self.updateActionButton?.isEnabled = true
                                self.updateStatusLabel?.stringValue = error.localizedDescription
                            }
                        }
                    }
                } else if choice == .alertSecondButtonReturn, let page = result.releaseURL {
                    NSWorkspace.shared.open(page)
                }
            }
        }
    }

    @objc private func toggleAutostart() {
        guard !prefsBusy, let autostartCheck else { return }
        let next = autostartCheck.state == .on
        prefsBusy = true
        autostartCheck.isEnabled = false
        workQueue.async { [weak self] in
            do {
                try MyVPNCLI.setAutostart(next)
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.autostartCheck?.isEnabled = true
                    self?.setStatus(next ? "Автоподнятие включено" : "Автоподнятие выключено", ok: true)
                    if self?.section == .shares { self?.rebuildContent() }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.autostartCheck?.state = next ? .off : .on
                    self?.autostartCheck?.isEnabled = true
                    self?.setStatus(error.localizedDescription, ok: false)
                }
            }
        }
    }

    @objc private func toggleAutoNAS() {
        guard !prefsBusy, let autoNasCheck else { return }
        let next = autoNasCheck.state == .on
        prefsBusy = true
        autoNasCheck.isEnabled = false
        workQueue.async { [weak self] in
            do {
                try MyVPNCLI.setAutoNAS(next)
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.autoNasCheck?.isEnabled = true
                    self?.setStatus(next ? "Авто-NAS включён" : "Авто-NAS выключен", ok: true)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.prefsBusy = false
                    self?.autoNasCheck?.state = next ? .off : .on
                    self?.autoNasCheck?.isEnabled = true
                    self?.setStatus(error.localizedDescription, ok: false)
                }
            }
        }
    }

    private func makeHelpPane() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let tv = NSTextView()
        tv.isEditable = false
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 13)
        tv.string = Self.helpText
        tv.textContainerInset = NSSize(width: 16, height: 12)
        tv.backgroundColor = .clear
        scroll.documentView = tv
        return scroll
    }

    private static let helpText = """
    Модель (как Clash / sing-box / Surge)

    1. Каналы — именованные WireGuard-туннели. Имя задаёшь сам; id = тег в sing-box.
       Один шаблон .conf на все каналы. Ключи только в ~/.config/wireguard.

    2. Маршруты — отдельная таблица «условие → via».
       • CIDR → канал или direct (LAN, домашние сети, NAS)
       • rule_set → geosite-ru / geoip-ru → обычно direct
       • Канал с галкой «по умолчанию» = final (остальной интернет)

    3. AllowedIPs в .conf на маршруты myVPN не влияют (в отличие от WireGuard.app).

    Настройки
    • System Helper — установка/удаление privileged helper
    • Channels — conf + автоподнятие после перезагрузки
    • Routes — таблица маршрутов
    • Доменные зоны — Обновить RU (geosite/geoip)
    • Shares — NAS/DNS + автоподключение NAS
    • Диагностика — автодоктор/heal (галочки), коды отвалов, журнал drops.log, отчёт + GitHub Issues
    • Update — автопроверка при запуске и каждый час; кнопка вручную

    Menu bar
    • Вкл/Выкл, NAS, Провести диагностику, Проверка обновления, Настройки…
    • Горячие клавиши (глобальные ⌃⌥⌘): V = VPN, N = NAS, D = диагностика, , = настройки
    • При отвале каналов (если галочки ON): авто doctor → журнал → heal с cooldown

    Установка приложения
    • Только из GitHub Releases (myVPN.app.zip) или Настройки → Update
    • Сборка из исходников в ~/Applications не поддерживается

    Первый запуск
    • System Helper → Установить (если пункта нет в меню)
    • Channels → импорт/вставка conf, имя, кто default
    • Routes → LAN direct, домашние сети → home, RU packs
    • Доменные зоны → Обновить RU
    • Сохранить → Включить
    """

    // MARK: - Shared widgets

    /// Left-aligned column: text starts at the left, wraps to full pane width with room on the right.
    private func prefsColumn(spacing: CGFloat = 14) -> NSStackView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = spacing
        // More trailing inset so long mono lines don't kiss the window edge.
        root.edgeInsets = NSEdgeInsets(top: 16, left: 12, bottom: 16, right: 24)
        root.alignment = .width
        return root
    }

    private static func fillWidthLabel(_ t: String) -> FillWidthLabel {
        FillWidthLabel(wrappingLabelWithString: t)
    }

    private func lab(_ t: String) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = .systemFont(ofSize: 12)
        f.textColor = .secondaryLabelColor
        f.alignment = .right
        f.widthAnchor.constraint(equalToConstant: 88).isActive = true
        return f
    }

    private func field(_ v: String, maxWidth: CGFloat? = nil) -> NSTextField {
        let f = NSTextField(string: v)
        f.controlSize = .regular
        f.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        f.bezelStyle = .roundedBezel
        // Rounded bezel clips glyphs if Auto Layout squeezes below ~24pt.
        f.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        f.setContentHuggingPriority(.required, for: .vertical)
        f.setContentCompressionResistancePriority(.required, for: .vertical)
        if let maxWidth {
            f.widthAnchor.constraint(equalToConstant: maxWidth).isActive = true
            f.setContentHuggingPriority(.required, for: .horizontal)
            f.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        return f
    }

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let s = NSStackView()
        s.orientation = .horizontal
        s.spacing = 12
        s.alignment = .centerY
        s.setHuggingPriority(.defaultHigh, for: .horizontal)
        s.addArrangedSubview(lab(title))
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        s.addArrangedSubview(control)
        return s
    }

    private func sectionTitle(_ t: String) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = .systemFont(ofSize: 12, weight: .semibold)
        f.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return f
    }

    private func makeEditor() -> NSTextView {
        let tv = NSTextView()
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        return tv
    }

    // MARK: - Tables

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === sidebar { return Section.allCases.count }
        if tableView === channelTable { return settings.channels.count }
        if tableView === routeTable { return settings.routes.count }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.drawsBackground = false
            tf.isBordered = false
            tf.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(tf)
            c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()

        if tableView === sidebar {
            cell.textField?.stringValue = Section(rawValue: row)?.title ?? ""
            cell.textField?.font = .systemFont(ofSize: 13)
        } else if tableView === channelTable {
            let ch = settings.channels[row]
            let mark = ch.isDefault ? "★ " : ""
            cell.textField?.stringValue = "\(mark)\(ch.name)"
            cell.textField?.font = .systemFont(ofSize: 12)
        } else if tableView === routeTable {
            let r = settings.routes[row]
            switch tableColumn?.identifier.rawValue {
            case "m": cell.textField?.stringValue = r.matchDisplay
            case "v": cell.textField?.stringValue = r.via
            case "n": cell.textField?.stringValue = r.note
            default: cell.textField?.stringValue = ""
            }
            cell.textField?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        }
        return cell
    }

    // MARK: - Persist

    private func reloadAll() {
        settings = AppSettings.load()
        if settings.routes.isEmpty || settings.channels.isEmpty {
            // Persist topology migration (lan_cidrs / home AllowedIPs → routes[])
            try? MyVPNCLI.render()
            settings = AppSettings.load()
        }
        channelDrafts.removeAll()
        for ch in settings.channels {
            channelDrafts[ch.id] = (try? WireGuardProfileStore.loadText(fileName: ch.fileName))
                ?? WireGuardProfileStore.template()
        }
        selectedChannelIndex = 0
        selectedRouteIndex = 0
        setStatus("Готово", ok: true)
    }

    @objc private func saveAll() {
        commitChannelEditor()
        commitRouteEditor()
        if section == .shares {
            settings.nasHost = nasHostField?.stringValue.trimmingCharacters(in: .whitespaces) ?? settings.nasHost
            settings.nasShare = nasShareField?.stringValue.trimmingCharacters(in: .whitespaces) ?? settings.nasShare
            if settings.nasShare.isEmpty { settings.nasShare = "Nas" }
            settings.dnsHomeServer = dnsHomeField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
            settings.dnsSuffixes = (dnsSuffixField?.stringValue ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let via = dnsViaPopup?.selectedItem?.representedObject as? String {
                settings.dnsVia = via
            }
        }
        do {
            for ch in settings.channels {
                let text = channelDrafts[ch.id] ?? WireGuardProfileStore.template()
                try WireGuardProfileStore.saveText(fileName: ch.fileName, text: text)
            }
            try settings.save()
            try MyVPNCLI.render()
            setStatus("Сохранено · render OK · каналов \(settings.channels.count)", ok: true)
        } catch {
            setStatus(error.localizedDescription, ok: false)
            let alert = NSAlert()
            alert.messageText = "Не удалось сохранить"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func setStatus(_ text: String, ok: Bool) {
        statusLabel?.stringValue = text
        statusLabel?.textColor = ok ? .secondaryLabelColor : .systemRed
    }

    @objc private func openWGFolder() {
        try? FileManager.default.createDirectory(at: WireGuardProfileStore.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(WireGuardProfileStore.directory)
    }

    @objc private func closeWindow() {
        window?.close()
    }
}

/// Wrapping label that always wraps to its laid-out width (no fixed 520pt that eats the right margin).
private final class FillWidthLabel: NSTextField {
    convenience init(wrappingLabelWithString string: String) {
        self.init(labelWithString: string)
        maximumNumberOfLines = 0
        lineBreakMode = .byWordWrapping
        cell?.wraps = true
        cell?.usesSingleLineMode = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preferredMaxLayoutWidth = 480
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        guard w > 1, abs(preferredMaxLayoutWidth - w) > 0.5 else { return }
        preferredMaxLayoutWidth = w
        invalidateIntrinsicContentSize()
    }
}
