import AppKit

/// Unified preferences: Channels / Routes / NAS·DNS / Help — one chrome.
/// Model: named channels (WG conf) + manual routes (Clash-style), not AllowedIPs.
final class ConnectionSettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Section: Int, CaseIterable {
        case channels, routes, nas, help
        var title: String {
            switch self {
            case .channels: return "Каналы"
            case .routes: return "Маршруты"
            case .nas: return "NAS / DNS"
            case .help: return "Справка"
            }
        }
    }

    private var settings = AppSettings.load()
    private var section: Section = .channels
    private var selectedChannelIndex: Int = 0

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

    // Routes pane
    private var routeTable: NSTableView!
    private var routeTypePopup: NSPopUpButton!
    private var routeMatchField: NSTextField!
    private var routeViaPopup: NSPopUpButton!
    private var routeNoteField: NSTextField!
    private var selectedRouteIndex: Int = 0

    // NAS pane
    private var nasHostField: NSTextField!
    private var nasShareField: NSTextField!
    private var dnsHomeField: NSTextField!
    private var dnsSuffixField: NSTextField!
    private var dnsViaPopup: NSPopUpButton!

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

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 12, right: 20)
        let title = NSTextField(labelWithString: "Каналы и маршруты")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let sub = NSTextField(wrappingLabelWithString:
            "Канал = именованный WireGuard-туннель (один шаблон .conf). Маршруты собираются вручную: условие → канал или direct. AllowedIPs в conf на маршрутизацию не влияют.")
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = .secondaryLabelColor
        sub.preferredMaxLayoutWidth = 740
        header.addArrangedSubview(title)
        header.addArrangedSubview(sub)
        root.addArrangedSubview(header)
        root.addArrangedSubview(Self.hairline())

        let body = NSStackView()
        body.orientation = .horizontal
        body.spacing = 0
        body.alignment = .top
        body.translatesAutoresizingMaskIntoConstraints = false

        let sideScroll = NSScrollView()
        sideScroll.hasVerticalScroller = true
        sideScroll.borderType = .noBorder
        sideScroll.drawsBackground = false
        sideScroll.translatesAutoresizingMaskIntoConstraints = false
        sideScroll.widthAnchor.constraint(equalToConstant: 148).isActive = true

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
        body.addArrangedSubview(sideScroll)

        body.addArrangedSubview(Self.vline())

        contentBox = NSView()
        contentBox.translatesAutoresizingMaskIntoConstraints = false
        contentBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        body.addArrangedSubview(contentBox)
        root.addArrangedSubview(body)
        body.heightAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true

        root.addArrangedSubview(Self.hairline())

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        footer.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 16, right: 20)

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
        root.addArrangedSubview(footer)
    }

    private static func hairline() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return b
    }

    private static func vline() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
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
        case .channels: pane = makeChannelsPane()
        case .routes: pane = makeRoutesPane()
        case .nas: pane = makeNasPane()
        case .help: pane = makeHelpPane()
        }
        pane.translatesAutoresizingMaskIntoConstraints = false
        contentBox.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: contentBox.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: contentBox.trailingAnchor),
            pane.topAnchor.constraint(equalTo: contentBox.topAnchor),
            pane.bottomAnchor.constraint(equalTo: contentBox.bottomAnchor),
        ])
    }

    // MARK: - Channels

    private func makeChannelsPane() -> NSView {
        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.alignment = .top

        let left = NSStackView()
        left.orientation = .vertical
        left.spacing = 8
        left.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
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
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let meta = NSGridView()
        meta.columnSpacing = 10
        meta.rowSpacing = 6
        nameField = field("")
        nameField.placeholderString = "Имя канала"
        idLabel = NSTextField(labelWithString: "")
        idLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        idLabel.textColor = .secondaryLabelColor
        defaultCheck = NSButton(checkboxWithTitle: "Канал по умолчанию (final / egress)", target: self, action: #selector(defaultToggled))
        pingField = field("")
        pingField.placeholderString = "10.8.0.1"
        meta.addRow(with: [lab("Имя"), nameField!])
        meta.addRow(with: [lab("id / файл"), idLabel!])
        meta.addRow(with: [lab("Ping"), pingField!])
        meta.column(at: 0).xPlacement = .trailing
        right.addArrangedSubview(meta)
        right.addArrangedSubview(defaultCheck)

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
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
        escroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        right.addArrangedSubview(escroll)

        root.addArrangedSubview(right)
        loadChannelSelection()
        return root
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
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let intro = NSTextField(wrappingLabelWithString:
            "Порядок сверху вниз. via = id канала или direct. Rule-set: geosite-ru / geoip-ru после «Обновить RU».")
        intro.font = .systemFont(ofSize: 11)
        intro.textColor = .secondaryLabelColor
        intro.preferredMaxLayoutWidth = 580
        root.addArrangedSubview(intro)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
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
        for (t, a) in [("+", #selector(addRoute)), ("−", #selector(removeRoute)), ("↑", #selector(moveRouteUp)), ("↓", #selector(moveRouteDown))] as [(String, Selector)] {
            let b = NSButton(title: t, target: self, action: a)
            b.bezelStyle = .rounded
            b.controlSize = .small
            btns.addArrangedSubview(b)
        }
        root.addArrangedSubview(btns)

        let form = NSGridView()
        form.columnSpacing = 10
        form.rowSpacing = 6
        routeTypePopup = NSPopUpButton()
        routeTypePopup.addItems(withTitles: ["CIDR", "rule_set"])
        routeMatchField = field("")
        routeMatchField.placeholderString = "10.57.0.0/24, 10.13.13.0/24  или  geosite-ru"
        routeViaPopup = NSPopUpButton()
        refillViaPopup()
        routeNoteField = field("")
        form.addRow(with: [lab("Тип"), routeTypePopup!])
        form.addRow(with: [lab("Match"), routeMatchField!])
        form.addRow(with: [lab("Via"), routeViaPopup!])
        form.addRow(with: [lab("Заметка"), routeNoteField!])
        form.column(at: 0).xPlacement = .trailing
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

    // MARK: - NAS / Help

    private func makeNasPane() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.alignment = .leading

        root.addArrangedSubview(sectionTitle("NAS (SMB)"))
        nasHostField = field(settings.nasHost)
        nasHostField.placeholderString = "10.57.0.100"
        nasShareField = field(settings.nasShare)
        nasShareField.placeholderString = "Nas"
        root.addArrangedSubview(row("Хост", nasHostField))
        root.addArrangedSubview(row("Шара", nasShareField))

        root.addArrangedSubview(sectionTitle("DNS (опционально)"))
        dnsHomeField = field(settings.dnsHomeServer)
        dnsHomeField.placeholderString = "10.57.0.1"
        dnsSuffixField = field(settings.dnsSuffixes.joined(separator: ", "))
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

        let note = NSTextField(wrappingLabelWithString: "LAN CIDR больше не отдельное поле — добавь direct-маршрут на вкладке «Маршруты».")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.preferredMaxLayoutWidth = 520
        root.addArrangedSubview(note)
        return root
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

    Первый запуск
    • Установить помощника (если пункт в меню)
    • Каналы → импорт/вставка conf, имя, кто default
    • Маршруты → LAN direct, домашние сети → home, RU packs
    • Сохранить → Включить

    Диагностика и обновления — в меню строки.
    """

    // MARK: - Shared widgets

    private func lab(_ t: String) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = .systemFont(ofSize: 12)
        f.textColor = .secondaryLabelColor
        f.alignment = .right
        f.widthAnchor.constraint(equalToConstant: 88).isActive = true
        return f
    }

    private func field(_ v: String) -> NSTextField {
        let f = NSTextField(string: v)
        f.font = .systemFont(ofSize: 13)
        f.bezelStyle = .roundedBezel
        return f
    }

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let s = NSStackView()
        s.orientation = .horizontal
        s.spacing = 12
        s.alignment = .centerY
        s.addArrangedSubview(lab(title))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        s.addArrangedSubview(control)
        return s
    }

    private func sectionTitle(_ t: String) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = .systemFont(ofSize: 12, weight: .semibold)
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
        if section == .nas {
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
