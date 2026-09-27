import AppKit

extension NSPasteboard.PasteboardType {
    static let brookTab = NSPasteboard.PasteboardType("app.brook.tab")
}

/// A lightweight clickable view with hover and press states, drawn with a single layer.
class HoverControl: NSControl {
    var onClick: (() -> Void)?
    var cornerRadius: CGFloat = 8 { didSet { needsDisplay = true } }
    var hoverColor: NSColor = Palette.rowHover
    var baseColor: NSColor = .clear { didSet { needsDisplay = true } }
    var isHighlightedState = false { didSet { needsDisplay = true } }
    var highlightColor: NSColor = Palette.rowSelected

    private(set) var isHovering = false { didSet { if oldValue != isHovering { hoverChanged(); needsDisplay = true } } }
    var isPressed = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func hoverChanged() {}

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        var color = baseColor
        if isHighlightedState { color = highlightColor }
        else if isHovering && isEnabled { color = hoverColor }
        layer.backgroundColor = cg(color)
        layer.opacity = isPressed ? 0.7 : 1
        if isHighlightedState {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0 : 0.08
            layer.shadowRadius = 2
            layer.shadowOffset = CGSize(width: 0, height: -1)
        } else {
            layer.shadowOpacity = 0
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        let p = convert(event.locationInWindow, from: nil)
        if bounds.contains(p) { fire() }
    }

    func fire() {
        onClick?()
        if let action { NSApp.sendAction(action, to: target, from: self) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// An SF Symbol button, Arc-style: no border, soft hover background.
final class IconButton: HoverControl {
    let imageView = NSImageView()

    init(symbol: String, size: CGFloat = 14, tooltip: String? = nil, dimension: CGFloat = 28,
         onClick: (() -> Void)? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: dimension, height: dimension))
        self.onClick = onClick
        self.toolTip = tooltip
        cornerRadius = 7
        imageView.image = NSImage.symbol(symbol, size: size)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: dimension),
            heightAnchor.constraint(equalToConstant: dimension),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ name: String, size: CGFloat = 14) {
        imageView.image = NSImage.symbol(name, size: size)
    }

    override var isEnabled: Bool {
        didSet { imageView.alphaValue = isEnabled ? 1 : 0.35 }
    }

    override func hoverChanged() {
        imageView.contentTintColor = isHovering ? .labelColor : .secondaryLabelColor
    }
}

/// Small rounded label that floats over the page for a moment.
final class ToastView: NSView {
    private let glass = NSGlassEffectView()
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alphaValue = 0
        glass.cornerRadius = 16
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        glass.pinEdges(to: self)
        let inner = NSView()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: inner.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -8)
        ])
        glass.contentView = inner
        inner.pinEdges(to: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ text: String) {
        label.stringValue = text
        hideWork?.cancel()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    self?.animator().alphaValue = 0
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}
