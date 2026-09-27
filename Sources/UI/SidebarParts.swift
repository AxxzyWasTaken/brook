import AppKit

// MARK: - Address pill

final class URLPillView: HoverControl {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let cookie = NSImageView()
    let extensionsButton = IconButton(symbol: "puzzlepiece.extension", size: 12, tooltip: "Extensions", dimension: 24)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cornerRadius = 10
        baseColor = Palette.pill
        hoverColor = Palette.pill.withAlphaComponent(0.12)
        toolTip = "Search or enter address (⌘L)"

        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        cookie.image = NSImage.symbol("checkmark.shield", size: 11)
        cookie.contentTintColor = .systemGreen
        cookie.isHidden = true
        cookie.translatesAutoresizingMaskIntoConstraints = false
        ([icon, label, cookie, extensionsButton] as [NSView]).forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            cookie.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4),
            cookie.centerYAnchor.constraint(equalTo: centerYAnchor),
            cookie.trailingAnchor.constraint(equalTo: extensionsButton.leadingAnchor, constant: -4),
            extensionsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            extensionsButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(tab: BrowserTab?) {
        guard let tab, let url = tab.url else {
            icon.image = NSImage.symbol("magnifyingglass", size: 11)
            label.stringValue = "Search or enter address"
            cookie.isHidden = true
            return
        }
        let secure = url.scheme == "https"
        icon.image = NSImage.symbol(secure ? "lock.fill" : (url.scheme == "http" ? "exclamationmark.triangle" : "globe"), size: 10)
        icon.contentTintColor = url.scheme == "http" ? .systemOrange : .tertiaryLabelColor
        label.stringValue = URLParser.display(url)
        if let cmp = tab.consentCMP {
            cookie.isHidden = false
            cookie.toolTip = "Cookie popup declined for you (\(cmp))"
        } else {
            cookie.isHidden = true
        }
    }
}

// MARK: - Favorites grid

final class FavoriteTile: HoverControl, NSDraggingSource {
    let tab: BrowserTab
    private let icon = NSImageView()
    private var dragStart: NSPoint?

    init(tab: BrowserTab) {
        self.tab = tab
        super.init(frame: .zero)
        cornerRadius = 11
        baseColor = Palette.tile
        hoverColor = Palette.rowSelected.withAlphaComponent(0.4)
        toolTip = tab.displayTitle
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        icon.image = tab.favicon ?? NSImage.symbol("globe", size: 16)
        icon.contentTintColor = .secondaryLabelColor
        icon.alphaValue = tab.isLoaded ? 1 : 0.75
        toolTip = tab.displayTitle
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        dragStart = nil
        isPressed = false
        let item = NSPasteboardItem()
        item.setString(tab.id.uuidString, forType: .driftTab)
        if let url = tab.url { item.setString(url.absoluteString, forType: .URL) }
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let favicon = icon.image
        let image = NSImage(size: bounds.size, flipped: false) { rect in
            favicon?.draw(in: NSRect(x: rect.midX - 10, y: rect.midY - 10, width: 20, height: 20))
            return true
        }
        dragItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }
}

final class FavoritesGridView: NSView {
    var onSelect: ((BrowserTab) -> Void)?
    var onDropTab: ((UUID, Int) -> Void)?
    var menuProvider: ((BrowserTab) -> NSMenu)?
    private(set) var tiles: [FavoriteTile] = []
    private var heightConstraint: NSLayoutConstraint!
    private let tileHeight: CGFloat = 44
    private let gap: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        registerForDraggedTypes([.driftTab])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var columns: Int { max(1, min(4, tiles.count)) }

    func reload(favorites: [BrowserTab], selected: BrowserTab?) {
        let existing = Dictionary(uniqueKeysWithValues: tiles.map { ($0.tab.id, $0) })
        tiles.forEach { $0.removeFromSuperview() }
        tiles = favorites.map { tab in
            let tile = existing[tab.id] ?? FavoriteTile(tab: tab)
            tile.onClick = { [weak self] in self?.onSelect?(tab) }
            tile.menu = menuProvider?(tab)
            tile.refresh()
            return tile
        }
        tiles.forEach { addSubview($0) }
        updateSelection(selected)
        let rows = tiles.isEmpty ? 0 : Int(ceil(Double(tiles.count) / Double(columns)))
        heightConstraint.constant = rows == 0 ? 0 : CGFloat(rows) * tileHeight + CGFloat(rows - 1) * gap
        needsLayout = true
    }

    func updateSelection(_ selected: BrowserTab?) {
        for t in tiles { t.isHighlightedState = t.tab === selected }
    }

    func refresh(_ tab: BrowserTab) {
        tiles.first { $0.tab === tab }?.refresh()
    }

    override func layout() {
        super.layout()
        guard !tiles.isEmpty else { return }
        let cols = columns
        let w = (bounds.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        for (i, tile) in tiles.enumerated() {
            let r = i / cols, c = i % cols
            tile.frame = NSRect(x: CGFloat(c) * (w + gap), y: CGFloat(r) * (tileHeight + gap), width: w, height: tileHeight)
        }
    }

    // Accept tabs dragged in from the list.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .move }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let s = sender.draggingPasteboard.string(forType: .driftTab), let id = UUID(uuidString: s) else { return false }
        let p = convert(sender.draggingLocation, from: nil)
        var index = tiles.count
        if !tiles.isEmpty {
            let cols = columns
            let w = (bounds.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
            let c = min(cols - 1, max(0, Int(p.x / (w + gap))))
            let r = max(0, Int(p.y / (tileHeight + gap)))
            index = min(tiles.count, r * cols + c)
        }
        onDropTab?(id, index)
        return true
    }
}

// MARK: - Space switcher

final class SpaceDot: HoverControl {
    let space: Space
    private let dot = CALayer()
    var isCurrent = false { didSet { needsLayout = true; needsDisplay = true } }

    init(space: Space) {
        self.space = space
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        cornerRadius = 7
        toolTip = space.name
        layer?.addSublayer(dot)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        let d: CGFloat = isCurrent ? 10 : 7
        dot.frame = CGRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        dot.cornerRadius = d / 2
        dot.backgroundColor = space.color.withAlphaComponent(isCurrent ? 1 : 0.55).cgColor
        dot.borderWidth = isCurrent ? 2 : 0
        dot.borderColor = cg(NSColor.dynamic(light: NSColor(white: 1, alpha: 0.9), dark: NSColor(white: 1, alpha: 0.35)))
    }
}
