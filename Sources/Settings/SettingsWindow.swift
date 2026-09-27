import AppKit
import UniformTypeIdentifiers

/// The ⌘, window: a native toolbar-tabbed preferences window like Safari's.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        tabs.canPropagateSelectedChildViewControllerTitle = true
        let panes: [(String, String, NSViewController)] = [
            ("General", "gearshape", GeneralPane()),
            ("Appearance", "paintbrush", AppearancePane()),
            ("Tabs", "square.on.square", TabsPane()),
            ("Search", "magnifyingglass", SearchPane()),
            ("Websites", "globe", WebsitesPane()),
            ("Boosts", "wand.and.stars", BoostsPane()),
            ("Advanced", "gearshape.2", AdvancedPane())
        ]
        for (title, symbol, vc) in panes {
            vc.title = title
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("BrookSettings")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(pane: String? = nil) {
        if let pane, let tabs = window?.contentViewController as? NSTabViewController,
           let i = tabs.tabViewItems.firstIndex(where: { $0.label == pane }) {
            tabs.selectedTabViewItemIndex = i
        }
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - General

final class GeneralPane: RebuildingPane {
    override func makeContent() -> NSView {
        let f = SettingsForm()
        f.row("Appearance", Controls.segmented(ThemeMode.allCases, title: { $0.title }, selected: Settings.theme) { Settings.theme = $0 })

        let customURL = Controls.field(Settings.newTabURL, placeholder: "https://example.com") { Settings.newTabURL = $0 }
        customURL.isHidden = Settings.newTabPage != .custom
        let page = Controls.popup(NewTabPage.allCases, title: { $0.title }, selected: Settings.newTabPage) { v in
            Settings.newTabPage = v
            customURL.isHidden = v != .custom
        }
        f.row("New tabs show", page, customURL)

        let spaces = NSPopUpButton(frame: .zero, pullsDown: false)
        spaces.addItem(withTitle: "Current space")
        for s in BrowserState.shared.spaces {
            spaces.addItem(withTitle: s.name)
            spaces.lastItem?.representedObject = s.id
        }
        if let id = Settings.externalLinksSpace, let i = BrowserState.shared.spaces.firstIndex(where: { $0.id == id }) {
            spaces.selectItem(at: i + 1)
        }
        spaces.onAction { c in Settings.externalLinksSpace = (c as! NSPopUpButton).selectedItem?.representedObject as? UUID }
        f.row("Open links from apps in", spaces)

        f.separator()
        let folderLabel = NSPathControl()
        folderLabel.url = Settings.downloadFolder
        folderLabel.pathStyle = .popUp
        folderLabel.isEditable = false
        let choose = Controls.button("Choose…") { [weak self] in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = Settings.downloadFolder
            guard let window = self?.view.window else { return }
            panel.beginSheetModal(for: window) { r in
                guard r == .OK, let url = panel.url else { return }
                Settings.downloadFolder = url
                folderLabel.url = url
            }
        }
        let folderRow = NSStackView(views: [folderLabel, choose])
        folderRow.spacing = 8
        f.row("Save downloads to", folderRow,
              Controls.check("Ask where to save each download", Settings.askDownloadLocation) { Settings.askDownloadLocation = $0 })

        f.separator()
        f.row("Default browser", Controls.button("Make Brook the Default Browser") {
            let appURL = Bundle.main.bundleURL
            Task {
                try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
            }
        })
        return f.view()
    }
}

// MARK: - Appearance

final class AppearancePane: RebuildingPane {
    override func makeContent() -> NSView {
        let f = SettingsForm()
        f.row("Sidebar", Controls.segmented(SidebarPosition.allCases, title: { $0.title }, selected: Settings.sidebarPosition) {
            Settings.sidebarPosition = $0
        })
        f.row("Window margin", Controls.slider(min: 0, max: 20, value: Double(Settings.pageMargin), ticks: 11,
                                              format: { $0 == 0 ? "None" : "\(Int($0)) pt" }) { Settings.pageMargin = CGFloat($0) })
        f.row("Corner radius", Controls.slider(min: 0, max: 24, value: Double(Settings.cornerRadius), ticks: 13,
                                              format: { $0 == 0 ? "Square" : "\(Int($0)) pt" }) { Settings.cornerRadius = CGFloat($0) })
        f.note("Set both to zero for an edge-to-edge page with no floating card.")
        f.row("Space colour strength", Controls.slider(min: 0, max: 1.5, value: Double(Settings.tintStrength),
                                                      format: { "\(Int(($0 * 100).rounded()))%" }) { Settings.tintStrength = CGFloat($0) })
        f.note("Each space's colour can be any colour — right-click a space dot and choose Edit Space.")

        f.separator()
        f.row("Tab rows", Controls.segmented(TabDensity.allCases, title: { $0.title }, selected: Settings.tabDensity) {
            Settings.tabDensity = $0
        })
        f.row("Tab text size", Controls.slider(min: 11, max: 17, value: Double(Settings.tabFontSize), ticks: 7,
                                              format: { "\(Int($0)) pt" }) { Settings.tabFontSize = CGFloat($0) })
        f.row("Show in sidebar",
              Controls.check("Address bar", Settings.showAddressBar) { Settings.showAddressBar = $0 },
              Controls.check("Favorites", Settings.showFavorites) { Settings.showFavorites = $0 },
              Controls.check("Spaces and tools bar", Settings.showBottomBar) { Settings.showBottomBar = $0 })
        f.note("With the address bar hidden, press ⌘L to see or edit the address.")
        f.row("Favorites per row", Controls.slider(min: 2, max: 6, value: Double(Settings.favoritesColumns), ticks: 5,
                                                  format: { "\(Int($0))" }) { Settings.favoritesColumns = Int($0) })
        return f.view()
    }
}

// MARK: - Tabs

final class TabsPane: RebuildingPane, NSTableViewDataSource, NSTableViewDelegate {
    private var list: EditableList?

    override func makeContent() -> NSView {
        let f = SettingsForm()
        f.row("New tabs open", Controls.popup(NewTabPosition.allCases, title: { $0.title }, selected: Settings.newTabPosition) {
            Settings.newTabPosition = $0
        })
        f.row("Closing a pinned tab", Controls.popup(PinnedCloseBehavior.allCases, title: { $0.title }, selected: Settings.pinnedClose) {
            Settings.pinnedClose = $0
        })

        let unloadOptions = [0, 15, 30, 60, 240]
        f.row("Unload background tabs", Controls.popup(unloadOptions, title: { $0 == 0 ? "Never" : ($0 < 60 ? "After \($0) minutes" : "After \($0 / 60) hour\($0 == 60 ? "" : "s")") },
                                                     selected: unloadOptions.contains(Settings.hibernateMinutes) ? Settings.hibernateMinutes : 30) {
            Settings.hibernateMinutes = $0
        })
        f.note("Unloaded tabs stay in the sidebar and reload when you click them. Saves memory.")

        let archiveOptions = [0, 12, 24, 168, 720]
        let archiveTitle: (Int) -> String = {
            switch $0 {
            case 0: return "Never"
            case 12: return "After 12 hours"
            case 24: return "After 1 day"
            case 168: return "After 7 days"
            default: return "After 30 days"
            }
        }
        f.row("Archive unused tabs", Controls.popup(archiveOptions, title: archiveTitle,
                                                  selected: archiveOptions.contains(Settings.archiveHours) ? Settings.archiveHours : 0) {
            Settings.archiveHours = $0
        })
        f.note("Closes regular (unpinned) tabs you haven't looked at, like Arc. Tabs playing audio or video are kept. Archived tabs are listed below.")

        let l = EditableList(columns: [("title", "Archived Tab", 390), ("date", "Archived", 120)], height: 170)
        l.table.dataSource = self
        l.table.delegate = self
        l.table.doubleAction = #selector(restoreSelected)
        l.table.target = self
        l.segment.isHidden = true
        l.extra = [
            Controls.button("Restore") { [weak self] in self?.restoreSelected() },
            Controls.button("Clear Archive") { [weak self] in
                BrowserState.shared.clearArchive()
                self?.list?.reload()
            }
        ]
        l.container.widthAnchor.constraint(equalToConstant: 520).isActive = true
        l.emptyLabel.stringValue = "No archived tabs"
        list = l
        l.reload()
        f.row("", l.container)
        return f.view()
    }

    @objc private func restoreSelected() {
        guard let row = list?.table.selectedRow, row >= 0 else { return }
        BrowserState.shared.restoreArchived(at: row)
        list?.reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { BrowserState.shared.archived.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let a = BrowserState.shared.archived[row]
        let text: String
        if tableColumn?.identifier.rawValue == "date" {
            text = a.date.formatted(.relative(presentation: .named))
        } else {
            text = a.title
        }
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = a.url.absoluteString
        if tableColumn?.identifier.rawValue == "date" {
            label.textColor = .secondaryLabelColor
            return label
        }
        // Title cell: site icon + title, like the sidebar.
        let icon = NSImageView(image: FaviconStore.shared.cachedIcon(for: a.url.host() ?? "") ?? NSImage.symbol("globe", size: 12) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [icon, label])
        row.spacing = 6
        row.toolTip = a.url.absoluteString
        return row
    }
}

// MARK: - Search

final class SearchPane: RebuildingPane, NSTableViewDataSource, NSTableViewDelegate {
    private var list: EditableList?
    private var engines: [SearchEngine] = []

    override func makeContent() -> NSView {
        engines = SearchEngines.all
        let f = SettingsForm()
        let def = NSPopUpButton(frame: .zero, pullsDown: false)
        for e in engines { def.addItem(withTitle: e.name) }
        def.selectItem(at: engines.firstIndex { $0.id == SearchEngines.defaultEngine.id } ?? 0)
        def.onAction { [weak self] c in
            guard let self else { return }
            let i = (c as! NSPopUpButton).indexOfSelectedItem
            if self.engines.indices.contains(i) { Settings.defaultSearchEngine = self.engines[i].id }
        }
        f.row("Default search engine", def)
        f.note("Spaces can use a different engine: right-click a space dot → Edit Space.")

        let l = EditableList(columns: [("name", "Name", 130), ("keyword", "Keyword", 70), ("template", "URL (%s = search terms)", 340)], height: 200)
        l.table.dataSource = self
        l.table.delegate = self
        l.onAdd = { [weak self] in
            guard let self else { return }
            self.engines.append(SearchEngine(id: UUID().uuidString, name: "New Engine", template: "https://example.com/search?q=%s", keyword: ""))
            self.commit()
            self.list?.table.reloadData()
            let row = self.engines.count - 1
            self.list?.table.selectRowIndexes([row], byExtendingSelection: false)
            self.list?.table.editColumn(0, row: row, with: nil, select: true)
        }
        l.onRemove = { [weak self] row in
            guard let self, self.engines.count > 1, self.engines.indices.contains(row) else { NSSound.beep(); return }
            self.engines.remove(at: row)
            self.commit()
            self.rebuild()
        }
        l.extra = [Controls.button("Restore Defaults") { [weak self] in
            SearchEngines.all = SearchEngine.builtIn
            self?.rebuild()
        }]
        l.container.widthAnchor.constraint(equalToConstant: 560).isActive = true
        list = l
        f.row("Search engines", l.container)
        f.note("Type a keyword and a space in the command bar to search with that engine, e.g. “yt cats”. Double-click a cell to edit it.")
        return f.view(width: 740)
    }

    private func commit() {
        SearchEngines.all = engines
    }

    func numberOfRows(in tableView: NSTableView) -> Int { engines.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""
        let e = engines[row]
        let value = id == "name" ? e.name : id == "keyword" ? e.keyword : e.template
        let field = NSTextField(string: value)
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.lineBreakMode = .byTruncatingTail
        if id == "template" && !e.isValid { field.textColor = .systemRed; field.toolTip = "Must be a web address containing %s" }
        field.onAction { [weak self] c in
            guard let self, self.engines.indices.contains(row) else { return }
            let v = (c as! NSTextField).stringValue.trimmingCharacters(in: .whitespaces)
            switch id {
            case "name": self.engines[row].name = v.isEmpty ? "Untitled" : v
            case "keyword": self.engines[row].keyword = v.lowercased()
            default: self.engines[row].template = v
            }
            self.commit()
            (c as! NSTextField).textColor = (id == "template" && !self.engines[row].isValid) ? .systemRed : .labelColor
        }
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        return field
    }
}

// MARK: - Websites

final class WebsitesPane: RebuildingPane, NSTableViewDataSource, NSTableViewDelegate {
    private var list: EditableList?
    private var sites: [(String, SiteOverride)] = []

    override func makeContent() -> NSView {
        sites = SiteSettings.all.sorted { $0.key < $1.key }
        let f = SettingsForm()
        let zooms: [Double] = [0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5]
        f.row("Default page zoom", Controls.popup(zooms, title: { "\(Int($0 * 100))%" },
                                                 selected: zooms.min { abs($0 - Settings.defaultZoom) < abs($1 - Settings.defaultZoom) } ?? 1) {
            Settings.defaultZoom = $0
        })
        f.row("JavaScript", Controls.check("Allow JavaScript", Settings.javascriptEnabled) { Settings.javascriptEnabled = $0 })
        f.row("Autoplay", Controls.popup(AutoplayPolicy.allCases, title: { $0.title }, selected: Settings.autoplay) { Settings.autoplay = $0 })
        f.row("Cookie popups", Controls.check("Decline cookie popups automatically", Settings.blockCookiePopups) { Settings.blockCookiePopups = $0 })

        f.separator()
        let l = EditableList(columns: [("site", "Website", 160), ("zoom", "Zoom", 84), ("js", "JavaScript", 92),
                                       ("autoplay", "Autoplay", 160), ("cookies", "Cookie Popups", 124)], height: 190)
        l.table.dataSource = self
        l.table.delegate = self
        l.table.rowHeight = 24
        l.onAdd = { [weak self] in self?.promptAddSite() }
        l.onRemove = { [weak self] row in
            guard let self, self.sites.indices.contains(row) else { return }
            SiteSettings.remove(self.sites[row].0)
            self.rebuild()
        }
        l.container.widthAnchor.constraint(equalToConstant: 660).isActive = true
        l.emptyLabel.stringValue = "No sites yet. Click + or use the lock in the address bar."
        list = l
        l.reload()
        f.row("Per-site settings", l.container)
        f.note("Zooming a page with ⌘+ / ⌘− remembers the level for that site. Click the lock in the address bar to change settings for the site you're on.")
        return f.view(width: 880)
    }

    private func promptAddSite() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Add a website"
        alert.informativeText = "Settings apply to the site and its subdomains."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "example.com"
        if let host = BrowserState.shared.selectedTab?.url?.host() { field.stringValue = SiteSettings.key(for: host) }
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            var host = field.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
            if let u = URL(string: host), let h = u.host() { host = h }
            guard host.contains(".") else { return }
            SiteSettings.update(host) { $0.javascript = $0.javascript ?? Settings.javascriptEnabled }
            self?.rebuild()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sites.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (host, o) = sites[row]
        let id = tableColumn?.identifier.rawValue ?? ""
        switch id {
        case "site":
            return NSTextField(labelWithString: host)
        case "zoom":
            let zooms: [Double?] = [nil, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
            return cellPopup(zooms.map { $0.map { "\(Int(($0 * 100).rounded()))%" } ?? "Default" },
                             selected: zooms.firstIndex { $0 != nil && o.zoom != nil && abs($0! - o.zoom!) < 0.01 } ?? 0) { i in
                SiteSettings.update(host) { $0.zoom = zooms[i] }
            }
        case "js":
            let values: [Bool?] = [nil, true, false]
            return cellPopup(["Default", "Allow", "Block"], selected: values.firstIndex { $0 == o.javascript } ?? 0) { i in
                SiteSettings.update(host) { $0.javascript = values[i] }
            }
        case "autoplay":
            let values: [String?] = [nil] + AutoplayPolicy.allCases.map(\.rawValue)
            return cellPopup(["Default"] + AutoplayPolicy.allCases.map(\.title), selected: values.firstIndex { $0 == o.autoplay } ?? 0) { i in
                SiteSettings.update(host) { $0.autoplay = values[i] }
            }
        default:
            let values: [Bool?] = [nil, true, false]
            return cellPopup(["Default", "Decline", "Leave"], selected: values.firstIndex { $0 == o.cookiePopups } ?? 0) { i in
                SiteSettings.update(host) { $0.cookiePopups = values[i] }
            }
        }
    }

    private func cellPopup(_ titles: [String], selected: Int, onChange: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .small
        p.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        p.isBordered = false
        p.addItems(withTitles: titles)
        p.selectItem(at: selected)
        p.onAction { c in onChange((c as! NSPopUpButton).indexOfSelectedItem) }
        return p
    }
}

// MARK: - Boosts

final class BoostsPane: RebuildingPane, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private var list: EditableList?
    private var boosts: [Boost] = []
    private var selectedID: UUID?
    private let nameField = NSTextField()
    private let siteField = NSTextField()
    private let enabled = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let cssView = BoostsPane.codeView()
    private let jsView = BoostsPane.codeView()
    private var editor = NSStackView()

    override func makeContent() -> NSView {
        boosts = Boosts.all

        let l = EditableList(columns: [("name", "Boost", 190)], height: 300)
        l.emptyLabel.stringValue = "No Boosts"
        l.table.headerView = nil
        l.table.dataSource = self
        l.table.delegate = self
        l.onAdd = { [weak self] in
            guard let self else { return }
            let host = BrowserState.shared.selectedTab?.url?.host().map(SiteSettings.key(for:)) ?? ""
            let b = Boost(name: host.isEmpty ? "New Boost" : host, site: host.isEmpty ? "*" : host,
                          css: "/* CSS for this site */\n", js: "")
            Boosts.save(b)
            self.boosts = Boosts.all
            self.selectedID = b.id
            self.rebuild()
        }
        l.onRemove = { [weak self] row in
            guard let self, self.boosts.indices.contains(row) else { return }
            Boosts.delete(self.boosts[row].id)
            WebViewFactory.reloadBoosts()
            self.boosts = Boosts.all
            self.selectedID = self.boosts.first?.id
            self.rebuild()
        }
        l.container.widthAnchor.constraint(equalToConstant: 210).isActive = true
        list = l
        l.reload()

        nameField.placeholderString = "Name"
        siteField.placeholderString = "example.com, or * for every site"
        for f in [nameField, siteField] {
            f.widthAnchor.constraint(equalToConstant: 360).isActive = true
            (f.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
            f.onAction { [weak self] _ in self?.saveEditor() }
        }
        enabled.onAction { [weak self] _ in self?.saveEditor() }
        cssView.delegate = self
        jsView.delegate = self

        let form = SettingsForm()
        form.grid.columnSpacing = 8
        form.row("Name", nameField)
        form.row("Site", siteField)
        form.row("", enabled)
        form.row("CSS", Self.scroll(cssView, height: 130))
        form.row("JavaScript", Self.scroll(jsView, height: 100))
        form.finish()
        form.grid.column(at: 0).width = 70
        let apply = Controls.button("Apply & Reload Page") { [weak self] in
            self?.saveEditor()
            WebViewFactory.reloadBoosts()
            BrowserState.shared.selectedTab?.reload()
        }
        apply.keyEquivalent = "\r"
        let hint = NSTextField(wrappingLabelWithString: "Boosts restyle or script sites you choose, like Arc's Boosts. CSS applies instantly on the next load; JavaScript runs once the page starts loading.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 440
        editor = NSStackView(views: [form.grid, apply, hint])
        editor.orientation = .vertical
        editor.alignment = .trailing
        editor.spacing = 10
        hint.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let empty = NSTextField(wrappingLabelWithString: "Boosts restyle or script the sites you choose, like Arc's Boosts.\n\nClick + to make one for the site you're on.")
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        let emptyBox = NSView()
        empty.translatesAutoresizingMaskIntoConstraints = false
        emptyBox.addSubview(empty)
        NSLayoutConstraint.activate([
            emptyBox.widthAnchor.constraint(equalToConstant: 440),
            emptyBox.heightAnchor.constraint(equalToConstant: 330),
            empty.centerXAnchor.constraint(equalTo: emptyBox.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: emptyBox.centerYAnchor),
            empty.widthAnchor.constraint(equalToConstant: 300)
        ])

        let split = NSStackView(views: [l.container, boosts.isEmpty ? emptyBox : editor])
        split.alignment = .top
        split.spacing = 20
        split.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        split.widthAnchor.constraint(equalToConstant: 780).isActive = true
        if selectedID == nil || !boosts.contains(where: { $0.id == selectedID }) { selectedID = boosts.first?.id }
        selectCurrent()
        return split
    }

    private static func codeView() -> NSTextView {
        let tv = NSTextView()
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        return tv
    }

    private static func scroll(_ tv: NSTextView, height: CGFloat) -> NSScrollView {
        let s = NSScrollView()
        s.documentView = tv
        s.hasVerticalScroller = true
        s.borderType = .bezelBorder
        s.widthAnchor.constraint(equalToConstant: 360).isActive = true
        s.heightAnchor.constraint(equalToConstant: height).isActive = true
        return s
    }

    private func selectCurrent() {
        guard let id = selectedID, let i = boosts.firstIndex(where: { $0.id == id }) else {
            editor.isHidden = boosts.isEmpty
            return
        }
        editor.isHidden = false
        list?.table.selectRowIndexes([i], byExtendingSelection: false)
        let b = boosts[i]
        nameField.stringValue = b.name
        siteField.stringValue = b.site
        enabled.state = b.enabled ? .on : .off
        cssView.string = b.css
        jsView.string = b.js
    }

    private func saveEditor() {
        guard let id = selectedID, var b = boosts.first(where: { $0.id == id }) else { return }
        b.name = nameField.stringValue.isEmpty ? "Untitled" : nameField.stringValue
        b.site = siteField.stringValue.trimmingCharacters(in: .whitespaces)
        b.enabled = enabled.state == .on
        b.css = cssView.string
        b.js = jsView.string
        guard b != boosts.first(where: { $0.id == id }) else { return }
        Boosts.save(b)
        boosts = Boosts.all
        let row = list?.table.selectedRow ?? -1
        if row >= 0 { list?.table.reloadData(forRowIndexes: [row], columnIndexes: [0]) }
        saveDebounce.call { WebViewFactory.reloadBoosts() }
    }

    private let saveDebounce = Debouncer(delay: 0.6)

    func textDidChange(_ notification: Notification) { saveEditor() }

    func numberOfRows(in tableView: NSTableView) -> Int { boosts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let b = boosts[row]
        let title = NSTextField(labelWithString: b.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = b.enabled ? .labelColor : .tertiaryLabelColor
        let site = NSTextField(labelWithString: b.site == "*" ? "All sites" : b.site)
        site.font = .systemFont(ofSize: 11)
        site.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, site])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        return stack
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 36 }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let row = list?.table.selectedRow, boosts.indices.contains(row), boosts[row].id != selectedID else { return }
        saveEditor()
        selectedID = boosts[row].id
        selectCurrent()
    }
}

// MARK: - Advanced

final class AdvancedPane: RebuildingPane {
    override func makeContent() -> NSView {
        let f = SettingsForm()
        f.row("Keyboard shortcuts", Controls.button("Customise in System Settings…") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts") {
                NSWorkspace.shared.open(url)
            }
        })
        f.note("Every Brook command is a menu item, so you can give any of them your own shortcut: System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts → + → Brook, then type the exact menu title (e.g. “Pin Tab”).")

        f.separator()
        let export = Controls.button("Export Settings…") { [weak self] in self?.exportSettings() }
        let importB = Controls.button("Import Settings…") { [weak self] in self?.importSettings() }
        let row = NSStackView(views: [export, importB])
        row.spacing = 8
        f.row("Settings file", row)
        f.note("Includes appearance, behaviour, search engines, per-site settings and Boosts. Tabs and history are not included.")

        f.row("Reset", Controls.button("Reset All Settings…") { [weak self] in self?.resetSettings() })
        return f.view()
    }

    private func exportSettings() {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Brook Settings.json"
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { r in
            guard r == .OK, let url = panel.url else { return }
            do { try Settings.exportData().write(to: url, options: .atomic) } catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }

    private func importSettings() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { r in
            guard r == .OK, let url = panel.url else { return }
            do {
                try Settings.importData(Data(contentsOf: url))
            } catch {
                let alert = NSAlert()
                alert.messageText = "That isn't a Brook settings file."
                alert.beginSheetModal(for: window)
            }
        }
    }

    private func resetSettings() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Reset all settings?"
        alert.informativeText = "Appearance, behaviour, search engines, per-site settings and Boosts go back to their defaults. Your tabs, spaces and history are kept."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn { Settings.resetAll() }
        }
    }
}
