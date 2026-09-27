import AppKit

private enum Suggestion {
    case open(URL)
    case search(String)
    case keywordSearch(SearchEngine, String)
    case tab(BrowserTab)
    case history(HistoryEntry)
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Arc-style floating command bar: type a URL, a search, or the name of an open tab.
@MainActor
final class CommandBarController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private weak var browser: BrowserWindowController?
    private let panel: KeyPanel
    private let glass = NSGlassEffectView()
    private let field = NSTextField()
    private let separator = NSBox()
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private var suggestions: [Suggestion] = []
    private var phrases: [String] = []
    private var editingCurrent = false
    private var acTask: Task<Void, Never>?
    private let width: CGFloat = 660
    private let rowHeight: CGFloat = 42

    var isVisible: Bool { panel.isVisible }

    init(browser: BrowserWindowController) {
        self.browser = browser
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 64),
                         styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                         backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.animationBehavior = .utilityWindow

        let root = NSView()
        // Clip to the glass's shape: the glass paints a faint square halo into its corners, and the
        // window shadow (traced from content alpha) would otherwise come out square.
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        glass.cornerRadius = 20
        glass.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(glass)
        glass.pinEdges(to: root)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content
        content.pinEdges(to: root)

        let searchIcon = NSImageView(image: NSImage.symbol("magnifyingglass", size: 17) ?? NSImage())
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.placeholderString = "Search or enter address"
        field.delegate = self
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("s"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.refusesFirstResponder = true
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        ([searchIcon, field, separator, scroll] as [NSView]).forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            searchIcon.centerYAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            field.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            field.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
            separator.topAnchor.constraint(equalTo: content.topAnchor, constant: 63),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])
        panel.contentView = root
    }

    // MARK: Show / hide

    func show(editingCurrent: Bool) {
        guard let parent = browser?.window else { return }
        self.editingCurrent = editingCurrent
        let current = editingCurrent ? BrowserState.shared.selectedTab?.url?.absoluteString ?? "" : ""
        field.stringValue = current
        rebuild()
        if !panel.isVisible {
            parent.addChildWindow(panel, ordered: .above)
            layoutPanel()
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            layoutPanel()
            panel.makeKey()
        }
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func dismiss() {
        guard panel.isVisible else { return }
        acTask?.cancel()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if let wv = browser?.content.webView { browser?.window?.makeFirstResponder(wv) }
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    private func layoutPanel() {
        guard let parent = browser?.window else { return }
        let visibleRows = min(suggestions.count, 8)
        let height: CGFloat = 64 + (visibleRows > 0 ? CGFloat(visibleRows) * rowHeight + 16 : 0)
        let pf = parent.frame
        let w = min(width, pf.width - 80)
        let top = pf.maxY - pf.height * 0.2
        panel.setFrame(NSRect(x: pf.midX - w / 2, y: top - height, width: w, height: height), display: true)
        separator.isHidden = visibleRows == 0
        // The window shadow is traced from the content's alpha. Retrace it once the glass has drawn
        // its rounded shape at the new size, or a square shadow shows outside the corners.
        panel.invalidateShadow()
        DispatchQueue.main.async { [weak panel] in panel?.invalidateShadow() }
    }

    // MARK: Suggestions

    func controlTextDidChange(_ obj: Notification) {
        rebuild()
        fetchPhrases()
    }

    private func rebuild() {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        var list: [Suggestion] = []
        let state = BrowserState.shared

        if text.isEmpty {
            let recent = state.visibleTabs.filter { $0 !== state.selectedTab && $0.url != nil }
                .sorted { $0.lastActive > $1.lastActive }.prefix(6)
            list = recent.map { .tab($0) }
        } else {
            if let (engine, query) = SearchEngines.keywordMatch(text) { list.append(.keywordSearch(engine, query)) }
            if let url = URLParser.url(from: text) { list.append(.open(url)) }
            list.append(.search(text))
            let q = text.lowercased()
            let tabs = state.allTabs.filter {
                $0 !== state.selectedTab &&
                ($0.displayTitle.lowercased().contains(q) || ($0.url?.absoluteString.lowercased().contains(q) ?? false))
            }.prefix(3)
            list += tabs.map { .tab($0) }
            let openURLs = Set(tabs.compactMap { $0.url?.absoluteString })
            list += HistoryStore.shared.search(text, limit: 5)
                .filter { !openURLs.contains($0.url) }
                .map { .history($0) }
            let searchPhrases = phrases.filter { $0.lowercased() != q }.prefix(4)
            if !searchPhrases.isEmpty {
                let lead = (URLParser.url(from: text) != nil ? 1 : 0) + (SearchEngines.keywordMatch(text) != nil ? 1 : 0)
                let insertAt = min(list.count, lead + 1)
                list.insert(contentsOf: searchPhrases.map { .search($0) }, at: insertAt)
            }
        }
        suggestions = list
        table.reloadData()
        if !list.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        if panel.isVisible { layoutPanel() }
    }

    /// Search suggestions from DuckDuckGo's autocomplete endpoint.
    private func fetchPhrases() {
        acTask?.cancel()
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, URLParser.url(from: text) == nil else { phrases = []; return }
        acTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled,
                  let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://duckduckgo.com/ac/?q=\(q)&type=list"),
                  let result = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let json = try? JSONSerialization.jsonObject(with: result.0) as? [Any],
                  json.count > 1, let list = json[1] as? [String],
                  let self, self.field.stringValue.trimmingCharacters(in: .whitespaces) == text else { return }
            self.phrases = list
            let selected = self.table.selectedRow
            self.rebuild()
            if selected > 0 && selected < self.suggestions.count {
                self.table.selectRowIndexes([selected], byExtendingSelection: false)
            }
        }
    }

    // MARK: Keyboard

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            move(1); return true
        case #selector(NSResponder.moveUp(_:)):
            move(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            commit(row: table.selectedRow); return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(); return true
        default:
            return false
        }
    }

    private func move(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        let next = max(0, min(suggestions.count - 1, table.selectedRow + delta))
        table.selectRowIndexes([next], byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    @objc private func rowClicked() {
        commit(row: table.clickedRow)
    }

    private func commit(row: Int) {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        let state = BrowserState.shared
        let destination: URL?
        if let s = suggestions[safe: row] {
            switch s {
            case .open(let url): destination = url
            case .search(let q): destination = SearchEngines.current.url(for: q)
            case .keywordSearch(let engine, let q): destination = engine.url(for: q)
            case .history(let e): destination = URL(string: e.url)
            case .tab(let tab):
                dismiss()
                state.select(tab)
                return
            }
        } else if !text.isEmpty {
            destination = URLParser.destination(for: text)
        } else {
            destination = nil
        }
        dismiss()
        guard let destination else { return }
        if editingCurrent, let tab = state.selectedTab {
            tab.load(destination)
        } else {
            state.openTab(url: destination, select: true)
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { suggestions.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SuggestionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: SuggestionCell.id, owner: self) as? SuggestionCell ?? SuggestionCell()
        switch suggestions[row] {
        case .open(let url):
            cell.configure(icon: FaviconStore.shared.cachedIcon(for: url.host() ?? "") ?? NSImage.symbol("globe", size: 14),
                           title: url.absoluteString, subtitle: nil, trailing: "Open")
        case .search(let q):
            cell.configure(icon: NSImage.symbol("magnifyingglass", size: 14), title: q, subtitle: nil,
                           trailing: SearchEngines.current.name)
        case .keywordSearch(let engine, let q):
            cell.configure(icon: NSImage.symbol("magnifyingglass", size: 14), title: q, subtitle: nil,
                           trailing: "Search \(engine.name)")
        case .tab(let tab):
            cell.configure(icon: tab.favicon ?? NSImage.symbol("globe", size: 14), title: tab.displayTitle,
                           subtitle: URLParser.display(tab.url), trailing: "Switch to Tab")
        case .history(let e):
            let url = URL(string: e.url)
            cell.configure(icon: FaviconStore.shared.cachedIcon(for: url?.host() ?? "") ?? NSImage.symbol("clock", size: 14),
                           title: e.title.isEmpty ? e.url : e.title, subtitle: URLParser.display(url), trailing: nil)
        }
        return cell
    }
}

private final class SuggestionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        path.fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }
}

private final class SuggestionCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("SuggestionCell")
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let trailing = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.id
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        trailing.font = .systemFont(ofSize: 12, weight: .medium)
        trailing.textColor = .tertiaryLabelColor
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        ([icon, title, subtitle, trailing] as [NSView]).forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            subtitle.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            subtitle.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -10),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(icon image: NSImage?, title t: String, subtitle s: String?, trailing tr: String?) {
        icon.image = image
        icon.contentTintColor = .secondaryLabelColor
        title.stringValue = t
        subtitle.stringValue = s.map { "— \($0)" } ?? ""
        trailing.stringValue = tr ?? ""
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let selected = backgroundStyle == .emphasized
            title.textColor = selected ? .white : .labelColor
            subtitle.textColor = selected ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
            trailing.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : .tertiaryLabelColor
            icon.contentTintColor = selected ? .white : .secondaryLabelColor
        }
    }
}
