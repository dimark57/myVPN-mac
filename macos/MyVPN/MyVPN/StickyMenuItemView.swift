import AppKit

/// Menu row that keeps NSMenu open on click. Optional gray detail on the right.
/// Hover uses selectedMenuItemColor (same blue as native NSMenuItem).
final class StickyMenuItemView: NSView {
    var onClick: (() -> Void)?
    var isActionEnabled: Bool = true {
        didSet { applyColors(); needsDisplay = true }
    }

    private let label = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var checked = false
    private let showsCheck: Bool

    init(
        title: String,
        detail: String? = nil,
        checked: Bool = false,
        showsCheck: Bool = false,
        width: CGFloat = 320
    ) {
        self.checked = checked
        self.showsCheck = showsCheck
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))

        configure(label, title, .labelColor, .left)
        configure(detailLabel, detail ?? "", .tertiaryLabelColor, .right)
        detailLabel.font = NSFont.menuFont(ofSize: 12)
        detailLabel.isHidden = (detail ?? "").isEmpty
        addSubview(label)
        addSubview(detailLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func setTitle(_ title: String) {
        label.stringValue = title
        needsLayout = true
    }

    func setDetail(_ detail: String?) {
        let text = detail ?? ""
        detailLabel.stringValue = text
        detailLabel.isHidden = text.isEmpty
        needsLayout = true
    }

    func setChecked(_ value: Bool) {
        checked = value
        needsDisplay = true
    }

    private func configure(_ field: NSTextField, _ text: String, _ color: NSColor, _ align: NSTextAlignment) {
        field.stringValue = text
        field.font = NSFont.menuFont(ofSize: 13)
        field.textColor = color
        field.alignment = align
        field.lineBreakMode = .byTruncatingTail
        field.isEditable = false
        field.isBordered = false
        field.drawsBackground = false
    }

    private var labelColor: NSColor {
        isActionEnabled ? .labelColor : .tertiaryLabelColor
    }

    private func applyColors() {
        if hovered, isActionEnabled {
            label.textColor = .selectedMenuItemTextColor
            detailLabel.textColor = .selectedMenuItemTextColor.withAlphaComponent(0.85)
        } else {
            label.textColor = labelColor
            detailLabel.textColor = .tertiaryLabelColor
        }
    }

    private func setHovered(_ value: Bool) {
        let next = value && isActionEnabled
        guard next != hovered else { return }
        hovered = next
        applyColors()
        needsDisplay = true
    }

    /// NSMenu custom views often miss mouseEntered — sync from window mouse location.
    private func refreshHoverFromMouse() {
        guard let window else {
            setHovered(false)
            return
        }
        let mouse = window.mouseLocationOutsideOfEventStream
        let local = convert(mouse, from: nil)
        setHovered(bounds.contains(local))
    }

    override func layout() {
        super.layout()
        let left: CGFloat = showsCheck ? 22 : 12
        let rightPad: CGFloat = 12
        let gap: CGFloat = 8
        let detailW: CGFloat
        if detailLabel.isHidden {
            detailW = 0
        } else {
            detailLabel.sizeToFit()
            detailW = min(detailLabel.fittingSize.width, bounds.width * 0.45)
        }
        let titleW = max(40, bounds.width - left - rightPad - (detailW > 0 ? detailW + gap : 0))
        label.frame = NSRect(x: left, y: 3, width: titleW, height: 18)
        if !detailLabel.isHidden {
            detailLabel.frame = NSRect(
                x: bounds.width - rightPad - detailW,
                y: 3,
                width: detailW,
                height: 18
            )
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // activeAlways + mouseMoved: menu windows often skip mouseEntered/Exited.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
        refreshHoverFromMouse()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    override func mouseMoved(with event: NSEvent) {
        refreshHoverFromMouse()
    }

    override func mouseDown(with event: NSEvent) {
        guard isActionEnabled else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered, isActionEnabled {
            // Same blue highlight as native menu items («Настройки»).
            NSColor.selectedMenuItemColor.setFill()
            bounds.fill()
        }
        applyColors()
        if showsCheck, checked {
            let check = "✓" as NSString
            check.draw(
                at: NSPoint(x: 6, y: 4),
                withAttributes: [
                    .font: NSFont.menuFont(ofSize: 12),
                    .foregroundColor: label.textColor ?? .labelColor
                ]
            )
        }
    }
}
