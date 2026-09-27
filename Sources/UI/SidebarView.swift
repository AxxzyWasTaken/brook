import AppKit
import WebKit

private enum Row {
    case pinned(BrowserTab)
    case divider
    case newTab
    case tab(BrowserTab)

    var tab: BrowserTab? {
        switch self {
        case .pinned(let t), .tab(let t): return t
        default: return nil
        }
    }
}

@MainActor
final class SidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    weak var browser: BrowserWindowController?
    private var state: BrowserState { BrowserState.shared }

    // Top
    let navRow = NSView()
    var navRowTop: NSLayoutConstraint!
    var navRowLeading: NSLayoutConstraint!
    private lazy var toggleButton = IconButton(symbol: "sidebar.left", tooltip: "Hide Sidebar (⌘S)") { [weak self] in self?.browser?.toggleSidebar() }
    private lazy var backButton = IconButton(symbol: "arrow.left", tooltip: "Back (⌘[)") { [weak self] in self?.browser?.goBack() }
    private lazy var forwardButton = IconButton(symbol: "arrow.right", tooltip: "Forward (⌘])") { [weak self] in self?.browser?.goForward() }
    private lazy var reloadButton = IconButton(symbol: "arrow.clockwise", tooltip: "Reload (⌘R)") { [weak self] in self?.browser?.reloadOrStop() }
    let urlPill = URLPillView()
    private let favoritesGrid = FavoritesGridView()
    private var favoritesTop: NSLayoutConstraint!

    // Tabs
    private let scrollView = SidebarScrollView()
    private let table = SidebarTableView()
    private var rows: [Row] = []

    // Bottom
    private lazy var fireButton = IconButton(symbol: "flame", tooltip: "Burn Tabs & Data (⇧⌘⌫)") { [weak self] in self?.browser?.fire() }
    private lazy var downloadsButton = IconButton(symbol: "arrow.down.circle", tooltip: "Downloads") { [weak self] in
        guard let self else { return }
        self.browser?.showDownloads(from: self.downloadsButton)
    }
    private lazy var addSpaceButton = IconButton(symbol: "plus", tooltip: "New Space") { [weak self] in self?.browser?.promptNewSpace() }
    private let spaceStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsChanged),
                                               name: DownloadManager.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    // MARK: Build

    private func build() {
        // Nav row
        navRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(navRow)
        let navStack = NSStackView(views: [backButton, forwardButton, reloadButton])
        navStack.spacing = 2
        navStack.translatesAutoresizingMaskIntoConstraints = false
        navRow.addSubview(toggleButton)
        navRow.addSubview(navStack)

        urlPill.translatesAutoresizingMaskIntoConstraints = false
        urlPill.onClick = { [weak self] in self?.browser?.showCommandBar(editing: true) }
        urlPill.extensionsButton.onClick = { [weak self] in self?.browser?.showExtensionsMenu() }
        addSubview(urlPill)

        favoritesGrid.onSelect = { [weak self] tab in self?.state.select(tab) }
        favoritesGrid.onDropTab = { [weak self] id, index in
            guard let self, let tab = self.state.allTabs.first(where: { $0.id == id }) else { return }
            self.state.move(tab, to: .favorites, index: index)
        }
        favoritesGrid.menuProvider = { [weak self] tab in self?.menu(for: tab) ?? NSMenu() }
        addSubview(favoritesGrid)

        // Tab list
        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.registerForDraggedTypes([.brookTab, .URL])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap
        table.onMiddleClick = { [weak self] row in
            guard let self, let tab = self.rows[safe: row]?.tab else { return }
            self.state.close(tab)
        }
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu

        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        scrollView.wantsLayer = true
        scrollView.onSwipe = { [weak self] delta in self?.state.switchSpace(by: delta) }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Bottom bar
        spaceStack.spacing = 2
        spaceStack.translatesAutoresizingMaskIntoConstraints = false
        let bottom = NSView()
        bottom.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottom)
        ([fireButton, downloadsButton, spaceStack, addSpaceButton] as [NSView]).forEach { bottom.addSubview($0) }
        downloadsButton.isHidden = true

        NSLayoutConstraint.activate([
            navRow.heightAnchor.constraint(equalToConstant: 28),
            navRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            toggleButton.leadingAnchor.constraint(equalTo: navRow.leadingAnchor),
            toggleButton.centerYAnchor.constraint(equalTo: navRow.centerYAnchor),
            navStack.trailingAnchor.constraint(equalTo: navRow.trailingAnchor),
            navStack.centerYAnchor.constraint(equalTo: navRow.centerYAnchor),

            urlPill.topAnchor.constraint(equalTo: navRow.bottomAnchor, constant: 10),
            urlPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            urlPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            favoritesGrid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            favoritesGrid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: favoritesGrid.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -4),

            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            bottom.heightAnchor.constraint(equalToConstant: 28),
            fireButton.leadingAnchor.constraint(equalTo: bottom.leadingAnchor),
            fireButton.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            downloadsButton.leadingAnchor.constraint(equalTo: fireButton.trailingAnchor, constant: 2),
            downloadsButton.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            spaceStack.centerXAnchor.constraint(equalTo: bottom.centerXAnchor),
            spaceStack.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            addSpaceButton.trailingAnchor.constraint(equalTo: bottom.trailingAnchor),
            addSpaceButton.centerYAnchor.constraint(equalTo: bottom.centerYAnchor)
        ])
        navRowTop = navRow.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        navRowLeading = navRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 78)
        favoritesTop = favoritesGrid.topAnchor.constraint(equalTo: urlPill.bottomAnchor, constant: 12)
        NSLayoutConstraint.activate([navRowTop, navRowLeading, favoritesTop])
    }

    // MARK: Updates from the window controller

    func reloadAll(spaceTransition forward: Bool? = nil) {
        rebuildRows()
        if let forward {
            let t = CATransition()
            t.type = .push
            t.subtype = forward ? .fromRight : .fromLeft
            t.duration = 0.28
            t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.layer?.add(t, forKey: "spaceSwitch")
        }
        table.reloadData()
        favoritesGrid.reload(favorites: state.favorites, selected: state.selectedTab)
        favoritesTop.constant = state.favorites.isEmpty ? 0 : 12
        rebuildSpaceDots()
        updateSelection()
    }

    private func rebuildRows() {
        let s = state.currentSpace
        var r: [Row] = s.pinned.map { .pinned($0) }
        if !s.pinned.isEmpty { r.append(.divider) }
        r.append(.newTab)
        r += s.tabs.map { .tab($0) }
        rows = r
    }

    private func rebuildSpaceDots() {
        spaceStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, space) in state.spaces.enumerated() {
            let dot = SpaceDot(space: space)
            dot.isCurrent = i == state.currentSpaceIndex
            dot.onClick = { [weak self] in self?.state.switchToSpace(i) }
            dot.menu = spaceMenu(for: space)
            spaceStack.addArrangedSubview(dot)
        }
    }

    func updateSelection() {
        let selected = state.selectedTab
        favoritesGrid.updateSelection(selected)
        table.enumerateAvailableRowViews { rowView, row in
            if let cell = rowView.view(atColumn: 0) as? TabCellView {
                cell.setSelected(cell.tab === selected)
            }
        }
        if let selected, let idx = rows.firstIndex(where: { $0.tab === selected }) {
            table.scrollRowToVisible(idx)
        }
        updateChrome()
    }

    func tabChanged(_ tab: BrowserTab, change: TabChange) {
        if tab.isFavorite {
            favoritesGrid.refresh(tab)
        } else if let idx = rows.firstIndex(where: { $0.tab === tab }),
                  let cell = table.view(atColumn: 0, row: idx, makeIfNecessary: false) as? TabCellView {
            cell.update(tab: tab)
        }
        if tab === state.selectedTab { updateChrome() }
    }

    /// Back/forward/reload state and the address pill.
    func updateChrome() {
        let tab = state.selectedTab
        backButton.isEnabled = tab?.webView?.canGoBack ?? false
        forwardButton.isEnabled = tab?.webView?.canGoForward ?? false
        reloadButton.isEnabled = tab != nil
        reloadButton.setSymbol(tab?.isLoading == true ? "xmark" : "arrow.clockwise")
        urlPill.update(tab: tab)
    }

    @objc private func downloadsChanged() {
        let dm = DownloadManager.shared
        downloadsButton.isHidden = dm.items.isEmpty
        downloadsButton.setSymbol(dm.hasActive ? "arrow.down.circle.dotted" : "arrow.down.circle")
        downloadsButton.imageView.contentTintColor = dm.hasActive ? .controlAccentColor : .secondaryLabelColor
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .divider = rows[row] { return 11 }
        return 34
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PlainRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .pinned(let tab), .tab(let tab):
            let cell = tableView.makeView(withIdentifier: TabCellView.id, owner: self) as? TabCellView ?? TabCellView()
            cell.onClose = { [weak self] t in self?.state.close(t) }
            cell.configure(tab: tab, selected: tab === state.selectedTab)
            return cell
        case .divider:
            return tableView.makeView(withIdentifier: DividerCellView.id, owner: self) as? DividerCellView ?? DividerCellView()
        case .newTab:
            return tableView.makeView(withIdentifier: NewTabCellView.id, owner: self) as? NewTabCellView ?? NewTabCellView()
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count else { return }
        switch rows[row] {
        case .pinned(let t), .tab(let t): state.select(t)
        case .newTab: browser?.showCommandBar(editing: false)
        case .divider: break
        }
    }

    // Drag & drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let tab = rows[row].tab else { return nil }
        let item = NSPasteboardItem()
        item.setString(tab.id.uuidString, forType: .brookTab)
        if let url = tab.url { item.setString(url.absoluteString, forType: .URL) }
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .on { tableView.setDropRow(row, dropOperation: .above) }
        return info.draggingPasteboard.string(forType: .brookTab) != nil ? .move : .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let s = state.currentSpace
        let pinnedCount = s.pinned.count
        let firstTabRow = pinnedCount + (pinnedCount > 0 ? 1 : 0) + 1
        let destination: TabLocation
        let index: Int
        // Dropping above the divider (or above "New Tab" when nothing is pinned) pins the tab.
        if row <= pinnedCount {
            destination = .pinned(s); index = row
        } else {
            destination = .tabs(s); index = max(0, row - firstTabRow)
        }

        if let idString = info.draggingPasteboard.string(forType: .brookTab),
           let id = UUID(uuidString: idString),
           let tab = state.allTabs.first(where: { $0.id == id }) {
            state.move(tab, to: destination, index: index)
            return true
        }
        if let urlString = info.draggingPasteboard.string(forType: .URL), let url = URL(string: urlString) {
            let tab = state.openTab(url: url, select: true)
            state.move(tab, to: destination, index: index)
            return true
        }
        return false
    }

    // MARK: Menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let tab = rows[safe: table.clickedRow]?.tab else { return }
        for item in self.menu(for: tab).items {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    func menu(for tab: BrowserTab) -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem(tab.isPinned ? "Unpin Tab" : "Pin Tab") { [weak self] in self?.state.togglePin(tab) })
        m.addItem(ClosureMenuItem(tab.isFavorite ? "Remove from Favorites" : "Add to Favorites") { [weak self] in self?.state.toggleFavorite(tab) })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem("Copy Link") {
            guard let url = tab.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        })
        m.addItem(ClosureMenuItem("Duplicate") { [weak self] in self?.state.duplicate(tab) })
        if tab.isLoaded && tab !== state.selectedTab {
            m.addItem(ClosureMenuItem("Unload to Save Memory") { tab.unload() })
        }
        if state.spaces.count > 1 {
            let moveItem = NSMenuItem(title: "Move to Space", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for space in state.spaces where space !== state.space(of: tab) {
                sub.addItem(ClosureMenuItem(space.name) { [weak self] in self?.state.move(tab, to: .tabs(space), index: 0) })
            }
            moveItem.submenu = sub
            m.addItem(moveItem)
        }
        m.addItem(.separator())
        if tab.isPinned || tab.isFavorite {
            m.addItem(ClosureMenuItem("Remove") { [weak self] in self?.state.remove(tab) })
        } else {
            m.addItem(ClosureMenuItem("Close Tab") { [weak self] in self?.state.close(tab) })
        }
        return m
    }

    private func spaceMenu(for space: Space) -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem("Edit Space…") { [weak self] in self?.browser?.promptEditSpace(space) })
        if state.spaces.count > 1 {
            m.addItem(ClosureMenuItem("Delete Space") { [weak self] in self?.browser?.confirmDeleteSpace(space) })
        }
        return m
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
