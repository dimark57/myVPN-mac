import AppKit

/// Menu row that keeps NSMenu open on click (standard items dismiss the menu).
final class StickyMenuItemView: NSView {
    var onClick: (() -> Void)?
    var isActionEnabled: Bool = true {
        didSet { needsDisplay = true; label.textColor = labelColor }
    }

    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var checked = false
    private let showsCheck: Bool

    init(title: String, checked: Bool = false, showsCheck: Bool = false, width: CGFloat = 280) {
        self.checked = checked
        self.showsCheck = showsCheck
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        label.stringValue = title
        label.font = NSFont.menuFont(ofSize: 13)
        label.textColor = labelColor
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func setTitle(_ title: String) {
        label.stringValue = title
    }

    func setChecked(_ value: Bool) {
        checked = value
        needsDisplay = true
    }

    private var labelColor: NSColor {
        isActionEnabled ? .labelColor : .tertiaryLabelColor
    }

    override func layout() {
        super.layout()
        let left: CGFloat = showsCheck ? 22 : 12
        label.frame = NSRect(x: left, y: 3, width: bounds.width - left - 10, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = isActionEnabled
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isActionEnabled else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered, isActionEnabled {
            NSColor.selectedContentBackgroundColor.setFill()
            dirtyRect.intersection(bounds).fill()
            label.textColor = .selectedMenuItemTextColor
        } else {
            label.textColor = labelColor
        }
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
