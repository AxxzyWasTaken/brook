import AppKit

struct SpaceDraft {
    var name: String
    var colorHex: String
    var searchEngineID: String?
    var separateProfile: Bool
}

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

/// Round colour swatch used in the space editor.
final class SwatchButton: HoverControl {
    let hex: String
    var isChosen = false { didSet { needsDisplay = true } }

    init(hex: String, name: String) {
        self.hex = hex
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        toolTip = name
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 11
        layer.backgroundColor = (NSColor(hex: hex) ?? .gray).cgColor
        layer.borderWidth = isChosen ? 2.5 : (isHovering ? 1.5 : 0)
        layer.borderColor = cg(isChosen ? .labelColor : .tertiaryLabelColor)
        layer.opacity = isPressed ? 0.7 : 1
    }
}

/// "Any colour" swatch: a conic rainbow ring; filled with the custom colour once one is picked.
@MainActor
final class RainbowSwatch: HoverControl {
    private let ring = CAGradientLayer()
    private let dot = CALayer()
    var chosenColor: NSColor? { didSet { needsDisplay = true } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        ring.type = .conic
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 0.5, y: 0)
        ring.colors = [NSColor.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal,
                       .systemBlue, .systemPurple, .systemPink, .systemRed].map(\.cgColor)
        ring.cornerRadius = 11
        ring.frame = bounds
        layer?.addSublayer(ring)
        dot.frame = bounds.insetBy(dx: 5, dy: 5)
        dot.cornerRadius = 6
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 11
        layer.borderWidth = chosenColor != nil ? 2.5 : (isHovering ? 1.5 : 0)
        layer.borderColor = cg(chosenColor != nil ? .labelColor : .tertiaryLabelColor)
        layer.opacity = isPressed ? 0.7 : 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dot.backgroundColor = (chosenColor ?? .windowBackgroundColor).cgColor
        CATransaction.commit()
    }
}

/// Accessory view for the New/Edit Space sheet.
@MainActor
final class SpaceEditorView: NSView {
    let nameField = NSTextField()
    private var swatches: [SwatchButton] = []
    private let custom = RainbowSwatch()
    private var colorPanelAttached = false
    private let engine = NSPopUpButton(frame: .zero, pullsDown: false)
    private let profile = NSButton(checkboxWithTitle: "Use a separate profile", target: nil, action: nil)
    private var colorHex: String

    init(draft: SpaceDraft) {
        colorHex = draft.colorHex
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 170))

        nameField.placeholderString = "Name"
        nameField.stringValue = draft.name

        let swatchRow = NSStackView()
        swatchRow.spacing = 6
        for c in Palette.spaceColors {
            let b = SwatchButton(hex: c.hex, name: c.name)
            b.onClick = { [weak self] in self?.choose(c.hex) }
            swatches.append(b)
            swatchRow.addArrangedSubview(b)
        }
        // A round rainbow swatch after the presets opens the system colour panel for any colour.
        custom.onClick = { [weak self] in self?.openColorPanel() }
        custom.toolTip = "Custom colour…"
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 4).isActive = true
        swatchRow.addArrangedSubview(spacer)
        swatchRow.addArrangedSubview(custom)

        engine.addItem(withTitle: "Default (\(SearchEngines.defaultEngine.name))")
        engine.lastItem?.representedObject = nil
        for e in SearchEngines.all {
            engine.addItem(withTitle: e.name)
            engine.lastItem?.representedObject = e.id
        }
        if let id = draft.searchEngineID, let i = SearchEngines.all.firstIndex(where: { $0.id == id }) {
            engine.selectItem(at: i + 1)
        }

        profile.state = draft.separateProfile ? .on : .off
        let profileNote = NSTextField(wrappingLabelWithString: "Keeps this space’s cookies, logins and site data apart from your other spaces. Favorites always use your main profile.")
        profileNote.font = .systemFont(ofSize: 11)
        profileNote.textColor = .secondaryLabelColor
        profileNote.preferredMaxLayoutWidth = 280

        let engineLabel = NSTextField(labelWithString: "Search with")
        let engineRow = NSStackView(views: [engineLabel, engine])
        engineRow.spacing = 8

        let stack = NSStackView(views: [nameField, swatchRow, engineRow, profile, profileNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: profile)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            nameField.widthAnchor.constraint(equalToConstant: 300),
            profileNote.widthAnchor.constraint(equalToConstant: 290)
        ])
        choose(colorHex)
        layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: 300, height: stack.fittingSize.height))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func choose(_ hex: String) {
        colorHex = hex
        var preset = false
        for s in swatches {
            s.isChosen = s.hex.caseInsensitiveCompare(hex) == .orderedSame
            preset = preset || s.isChosen
        }
        custom.chosenColor = preset ? nil : NSColor(hex: hex)
    }

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(hex: colorHex) ?? .systemPurple
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        colorPanelAttached = true
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ panel: NSColorPanel) { choose(panel.color.hexString) }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Detach from the shared panel when the sheet closes so it doesn't message a dead view.
        if newWindow == nil, colorPanelAttached {
            colorPanelAttached = false
            NSColorPanel.shared.setTarget(nil)
            NSColorPanel.shared.setAction(nil)
            NSColorPanel.shared.orderOut(nil)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    var draft: SpaceDraft {
        SpaceDraft(name: nameField.stringValue.trimmingCharacters(in: .whitespaces),
                   colorHex: colorHex,
                   searchEngineID: engine.selectedItem?.representedObject as? String,
                   separateProfile: profile.state == .on)
    }
}
