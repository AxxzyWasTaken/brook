import AppKit

// MARK: - Tab row

final class TabCellView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("TabCell")

    private let background = HoverControl()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let closeButton = IconButton(symbol: "xmark", size: 10, tooltip: "Close Tab", dimension: 20)
    private let spinner = NSProgressIndicator()
    private(set) weak var tab: BrowserTab?
    var onClose: ((BrowserTab) -> Void)?
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { updateClose() } }
    private var selected = false
    var fontSize: CGFloat = 13 {
        didSet { if fontSize != oldValue { label.font = .systemFont(ofSize: fontSize, weight: .medium) } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.id

        background.cornerRadius = 9
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        closeButton.onClick = { [weak self] in
            guard let self, let tab = self.tab else { return }
            self.onClose?(tab)
        }
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            spinner.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let the table handle clicks and drags anywhere except the close button.
        let local = convert(point, from: superview)
        if !closeButton.isHidden, closeButton.frame.contains(local) {
            return closeButton.hitTest(convert(local, to: closeButton.superview))
        }
        return bounds.contains(local) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; background.baseColor = selected ? .clear : Palette.rowHover }
    override func mouseExited(with event: NSEvent) { hovering = false; background.baseColor = .clear }

    func configure(tab: BrowserTab, selected: Bool) {
        self.tab = tab
        self.selected = selected
        hovering = false
        background.baseColor = .clear
        background.isHighlightedState = selected
        update(tab: tab)
    }

    func update(tab: BrowserTab) {
        label.stringValue = tab.displayTitle
        label.textColor = tab.isLoaded || !tab.isPinned ? .labelColor : .secondaryLabelColor
        icon.image = tab.favicon ?? NSImage.symbol("globe", size: 13)
        icon.contentTintColor = .secondaryLabelColor
        icon.alphaValue = tab.isLoaded || tab.isPinned == false ? 1 : 0.6
        if tab.isLoading && tab.favicon == nil {
            spinner.startAnimation(nil); icon.isHidden = true
        } else {
            spinner.stopAnimation(nil); icon.isHidden = false
        }
        toolTip = tab.url?.absoluteString
        updateClose()
    }

    func setSelected(_ s: Bool) {
        selected = s
        background.isHighlightedState = s
        background.baseColor = (!s && hovering) ? Palette.rowHover : .clear
        updateClose()
    }

    private func updateClose() {
        closeButton.isHidden = !(hovering || selected)
        if let tab, tab.isPinned {
            closeButton.setSymbol(tab.isLoaded ? "minus" : "xmark", size: 10)
            closeButton.isHidden = closeButton.isHidden || !tab.isLoaded
            closeButton.toolTip = "Unload Pinned Tab"
        } else {
            closeButton.setSymbol("xmark", size: 10)
            closeButton.toolTip = "Close Tab"
        }
    }
}

// MARK: - "New Tab" row

final class NewTabCellView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("NewTabCell")
    private let background = HoverControl()
    private let label = NSTextField(labelWithString: "New Tab")
    var fontSize: CGFloat = 13 {
        didSet { if fontSize != oldValue { label.font = .systemFont(ofSize: fontSize, weight: .medium) } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.id
        background.cornerRadius = 9
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        let icon = NSImageView(image: NSImage.symbol("plus", size: 12, weight: .semibold) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 35),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { background.baseColor = Palette.rowHover }
    override func mouseExited(with event: NSEvent) { background.baseColor = .clear }
}

// MARK: - Divider between pinned and regular tabs

final class DividerCellView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("DividerCell")
    private let line = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.id
        line.wantsLayer = true
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        line.layer?.backgroundColor = cg(Palette.divider)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        line.layer?.backgroundColor = cg(Palette.divider)
    }
}

/// Row view that draws nothing itself; cells draw their own rounded backgrounds.
final class PlainRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}
    override var isEmphasized: Bool { get { false } set {} }
}

/// Table that reports middle-clicks and swallows horizontal swipes for space switching.
final class SidebarTableView: NSTableView {
    var onMiddleClick: ((Int) -> Void)?

    override func otherMouseUp(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if event.buttonNumber == 2, row >= 0 { onMiddleClick?(row) } else { super.otherMouseUp(with: event) }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool { true }
}

final class SidebarScrollView: NSScrollView {
    var onSwipe: ((Int) -> Void)?
    private var horizontal = false
    private var accumulated: CGFloat = 0
    private var swallowMomentum = false

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { super.scrollWheel(with: event); return }
        if event.phase == .began {
            horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.3
            accumulated = 0
            swallowMomentum = false
        }
        if horizontal {
            if event.phase == .changed || event.phase == .began { accumulated += event.scrollingDeltaX }
            if event.phase == .ended || event.phase == .cancelled {
                if accumulated < -60 { onSwipe?(1) } else if accumulated > 60 { onSwipe?(-1) }
                horizontal = false
                swallowMomentum = true
            }
            return
        }
        if swallowMomentum && !event.momentumPhase.isEmpty {
            if event.momentumPhase == .ended { swallowMomentum = false }
            return
        }
        super.scrollWheel(with: event)
    }
}
