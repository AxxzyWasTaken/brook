import AppKit
import WebKit

final class BrowserWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Transparent strip at the window's left edge that reveals the hidden sidebar on hover.
private final class EdgeHotZone: NSView {
    var onEnter: (() -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Drag handle between the sidebar and the page.
private final class ResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDragged(with event: NSEvent) { onDrag?(event.deltaX) }
    override func mouseUp(with event: NSEvent) { onEnd?() }
}

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, BrowserStateObserver {
    private let state = BrowserState.shared
    private let root = NSVisualEffectView()
    private let tint = NSView()
    private let sidebarGlass = NSGlassEffectView()
    let sidebar = SidebarView()
    let content = ContentAreaView()
    private let handle = ResizeHandle()
    private let hotZone = EdgeHotZone()
    private lazy var commandBar = CommandBarController(browser: self)

    private var sidebarWidth = Settings.sidebarWidth
    private var sidebarWidthConstraint: NSLayoutConstraint!
    /// Distance from the sidebar's outer edge to the window edge; negative slides it off-screen.
    private var sidebarEdge: NSLayoutConstraint!
    private var contentToSidebar: NSLayoutConstraint!
    private var contentToEdge: NSLayoutConstraint!
    private var contentTop: NSLayoutConstraint!
    private var positional: [NSLayoutConstraint] = []
    private(set) var sidebarHidden = Settings.sidebarHidden
    private var peeking = false
    private var peekMonitor: Any?
    private var inset: CGFloat = Settings.pageMargin
    private var onRight = Settings.sidebarPosition == .right

    init() {
        let window = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                   backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        // An empty unified toolbar makes the titlebar taller, which drops the traffic lights
        // down to where the sidebar's nav row can sit level with them.
        let toolbar = NSToolbar(identifier: "BrookToolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
        buildLayout()
        window.center()
        window.setFrameAutosaveName("BrookMainWindow")
        state.observer = self
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildLayout() {
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .followsWindowActiveState
        window?.contentView = root

        tint.wantsLayer = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tint)
        tint.pinEdges(to: root)

        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        sidebarGlass.translatesAutoresizingMaskIntoConstraints = false
        sidebarGlass.contentView = sidebar
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebarGlass)
        sidebar.pinEdges(to: sidebarGlass)
        sidebar.browser = self

        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.onDrag = { [weak self] dx in
            guard let self else { return }
            let delta = self.onRight ? -dx : dx
            self.sidebarWidth = min(420, max(190, self.sidebarWidth + delta))
            self.sidebarWidthConstraint.constant = self.sidebarWidth
        }
        handle.onEnd = { [weak self] in
            guard let self else { return }
            Settings.sidebarWidth = self.sidebarWidth
        }
        root.addSubview(handle)

        hotZone.translatesAutoresizingMaskIntoConstraints = false
        hotZone.onEnter = { [weak self] in self?.peekSidebar() }
        root.addSubview(hotZone)

        sidebarWidthConstraint = sidebarGlass.widthAnchor.constraint(equalToConstant: sidebarWidth)
        NSLayoutConstraint.activate([
            sidebarWidthConstraint,
            handle.topAnchor.constraint(equalTo: sidebarGlass.topAnchor),
            handle.bottomAnchor.constraint(equalTo: sidebarGlass.bottomAnchor),
            hotZone.topAnchor.constraint(equalTo: root.topAnchor),
            hotZone.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            hotZone.widthAnchor.constraint(equalToConstant: 10)
        ])
        rebuildPositionalConstraints()
        applyAppearanceSettings()
        applySidebarVisibility(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)),
                                               name: .brookSettingsDidChange, object: nil)
    }

    /// Constraints that depend on which side the sidebar is on and on the page margin.
    private func rebuildPositionalConstraints() {
        NSLayoutConstraint.deactivate(positional)
        // These two are toggled separately from `positional`, so retire the old side's copies too.
        contentToSidebar?.isActive = false
        contentToEdge?.isActive = false
        let m = inset
        let lead = root.leadingAnchor, trail = root.trailingAnchor
        if onRight {
            sidebarEdge = trail.constraint(equalTo: sidebarGlass.trailingAnchor, constant: m)
            contentToSidebar = sidebarGlass.leadingAnchor.constraint(equalTo: content.trailingAnchor, constant: m)
            contentToEdge = trail.constraint(equalTo: content.trailingAnchor, constant: m)
            positional = [
                content.leadingAnchor.constraint(equalTo: lead, constant: m),
                handle.trailingAnchor.constraint(equalTo: sidebarGlass.leadingAnchor),
                hotZone.trailingAnchor.constraint(equalTo: trail)
            ]
        } else {
            sidebarEdge = sidebarGlass.leadingAnchor.constraint(equalTo: lead, constant: m)
            contentToSidebar = content.leadingAnchor.constraint(equalTo: sidebarGlass.trailingAnchor, constant: m)
            contentToEdge = content.leadingAnchor.constraint(equalTo: lead, constant: m)
            positional = [
                content.trailingAnchor.constraint(equalTo: trail, constant: -m),
                handle.leadingAnchor.constraint(equalTo: sidebarGlass.trailingAnchor),
                hotZone.leadingAnchor.constraint(equalTo: lead)
            ]
        }
        contentTop = content.topAnchor.constraint(equalTo: root.topAnchor, constant: m)
        positional += [
            sidebarEdge, contentTop,
            sidebarGlass.topAnchor.constraint(equalTo: root.topAnchor, constant: m),
            sidebarGlass.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m),
            handle.widthAnchor.constraint(equalToConstant: max(6, m))
        ]
        NSLayoutConstraint.activate(positional)
        contentToSidebar.isActive = !sidebarHidden
        contentToEdge.isActive = sidebarHidden
    }

    // MARK: Settings

    @objc private func settingsChanged(_ note: Notification) {
        let key = note.userInfo?["key"] as? String ?? "*"
        let layoutKeys: Set<String> = ["*", "sidebarPosition", "pageMargin"]
        if layoutKeys.contains(key) {
            let right = Settings.sidebarPosition == .right
            let margin = Settings.pageMargin
            if right != onRight || margin != inset {
                onRight = right
                inset = margin
                if peeking { endPeek() }
                rebuildPositionalConstraints()
                applySidebarVisibility(animated: false)
            }
        }
        // Only redo the work a key actually affects: Boost edits save on every keystroke.
        let appearanceKeys: Set<String> = ["*", "theme", "cornerRadius", "tintStrength"]
        let sidebarKeys: Set<String> = ["*", "showAddressBar", "showFavorites", "showBottomBar",
                                        "favoritesColumns", "tabDensity", "tabFontSize"]
        if appearanceKeys.contains(key) { applyAppearanceSettings() }
        if sidebarKeys.contains(key) { sidebar.applySettings() }
        if ["*", "defaultZoom", "siteSettings"].contains(key) {
            for tab in state.allTabs {
                guard let wv = tab.webView else { continue }
                let z = SiteSettings.zoom(for: wv.url?.host())
                if abs(wv.pageZoom - z) > 0.001 { wv.pageZoom = z }
            }
        }
    }

    private func applyAppearanceSettings() {
        switch Settings.theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        let r = Settings.cornerRadius
        sidebarGlass.cornerRadius = r == 0 ? 0 : r + 2
        content.cornerRadius = r
        applySpaceColors()
    }

    func windowDidResize(_ notification: Notification) { alignNavRow() }
    func windowDidEnterFullScreen(_ notification: Notification) { alignNavRow() }
    func windowDidExitFullScreen(_ notification: Notification) { alignNavRow() }

    func windowDidBecomeKey(_ notification: Notification) {
        ExtensionManager.shared.controller.didFocusWindow(self)
    }

    /// Lines the back/forward buttons up with the traffic lights, whatever size macOS makes them.
    func alignNavRow() {
        guard let window else { return }
        guard let zoom = window.standardWindowButton(.zoomButton), !zoom.isHidden,
              let zoomSuper = zoom.superview, !window.styleMask.contains(.fullScreen) else {
            sidebar.navRowTop.constant = 8
            sidebar.navRowLeading.constant = 8
            contentTop.constant = inset
            return
        }
        // Measure against where the sidebar rests (inset from the top-left), not its current
        // frame: while it slides in, the frame is still off-screen and would push the row away.
        let zoomRect = zoomSuper.convert(zoom.frame, to: nil)
        let sidebarTop = root.bounds.height - inset
        let top = sidebarTop - zoomRect.midY - 14
        let leading = zoomRect.maxX - inset + 8
        sidebar.navRowTop.constant = max(4, top)
        sidebar.navRowLeading.constant = onRight ? 8 : max(8, leading)
        // With the sidebar on the right the traffic lights sit over the page's corner,
        // so the page starts just below them.
        let lightsVisible = !zoom.isHidden && onRight && !sidebarHidden
        contentTop.constant = lightsVisible ? max(inset, root.bounds.height - zoomRect.minY + 10) : inset
    }

    // MARK: Showing

    func start() {
        applySpaceColors()
        sidebar.reloadAll()
        content.show(state.selectedTab, spaceName: state.currentSpace.name)
        window?.title = state.selectedTab?.displayTitle ?? "Brook"
        showWindow(nil)
        alignNavRow()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.alignNavRow() }
        }
        ExtensionManager.shared.windowDidOpen(self)
        if state.selectedTab == nil { showCommandBar(editing: false) }
    }

    private func applySpaceColors() {
        let color = state.currentSpace.color
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.allowsImplicitAnimation = true
            tint.layer?.backgroundColor = color.withAlphaComponent(0.22 * Settings.tintStrength).cgColor
        }
        sidebarGlass.tintColor = color.withAlphaComponent(0.1 * Settings.tintStrength)
        content.accentColor = color
    }

    // MARK: BrowserStateObserver

    func browserStateDidChangeStructure() {
        sidebar.reloadAll()
    }

    func browserStateDidSelect(_ tab: BrowserTab?, previous: BrowserTab?) {
        content.show(tab, spaceName: state.currentSpace.name)
        sidebar.updateSelection()
        if let wv = tab?.webView, !commandBar.isVisible, !(window?.firstResponder is NSTextView) {
            window?.makeFirstResponder(wv)
        }
        window?.title = tab?.displayTitle ?? "Brook"
    }

    func browserStateTabDidChange(_ tab: BrowserTab, change: TabChange) {
        sidebar.tabChanged(tab, change: change)
        content.tabChanged(tab, change: change)
        if tab === state.selectedTab, change.contains(.title) { window?.title = tab.displayTitle }
    }

    func browserStateDidSwitchSpace(forward: Bool) {
        applySpaceColors()
        sidebar.reloadAll(spaceTransition: forward)
    }

    // MARK: Sidebar

    @objc func toggleSidebar() {
        sidebarHidden.toggle()
        Settings.sidebarHidden = sidebarHidden
        peeking = false
        applySidebarVisibility(animated: true)
    }

    private func applySidebarVisibility(animated: Bool) {
        let hidden = sidebarHidden && !peeking
        // On the right, a peeking sidebar is far from the traffic lights, so they stay hidden.
        let lightsHidden = sidebarHidden && (!peeking || onRight)
        let lights: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for b in lights { window?.standardWindowButton(b)?.isHidden = lightsHidden }
        contentToSidebar.isActive = !sidebarHidden
        contentToEdge.isActive = sidebarHidden
        handle.isHidden = sidebarHidden
        hotZone.isHidden = !sidebarHidden || peeking
        sidebarGlass.shadow = peeking ? {
            let s = NSShadow()
            s.shadowBlurRadius = 20
            s.shadowColor = NSColor.black.withAlphaComponent(0.3)
            return s
        }() : nil
        let leading = hidden ? -(sidebarWidth + inset * 2 + 24) : inset
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.25 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            sidebarEdge.animator().constant = leading
            root.layoutSubtreeIfNeeded()
        }
        alignNavRow()
    }

    private func peekSidebar() {
        guard sidebarHidden, !peeking else { return }
        peeking = true
        applySidebarVisibility(animated: true)
        peekMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.peeking, event.window === self.window else { return }
                let p = self.root.convert(event.locationInWindow, from: nil)
                let away = self.onRight ? p.x < self.sidebarGlass.frame.minX - 24 : p.x > self.sidebarGlass.frame.maxX + 24
                if away { self.endPeek() }
            }
            return event
        }
        window?.acceptsMouseMovedEvents = true
    }

    private func endPeek() {
        peeking = false
        if let m = peekMonitor { NSEvent.removeMonitor(m); peekMonitor = nil }
        applySidebarVisibility(animated: true)
    }

    // MARK: Commands

    func showCommandBar(editing: Bool) {
        commandBar.show(editingCurrent: editing && state.selectedTab != nil)
    }

    /// ⌘T and the sidebar's New Tab row, following Settings → General → New tabs show.
    func newTab() {
        switch Settings.newTabPage {
        case .commandBar:
            showCommandBar(editing: false)
        case .blank:
            state.openTab(url: nil, select: true)
            showCommandBar(editing: true)
        case .custom:
            if let url = URLParser.url(from: Settings.newTabURL) {
                state.openTab(url: url, select: true)
            } else {
                showCommandBar(editing: false)
            }
        }
    }

    @objc func goBack() { state.selectedTab?.webView?.goBack() }
    @objc func goForward() { state.selectedTab?.webView?.goForward() }

    @objc func reloadOrStop() {
        guard let tab = state.selectedTab else { return }
        if tab.isLoading { tab.webView?.stopLoading() } else { tab.reload() }
    }

    func fire() {
        Fire.confirmAndBurn(in: window, overlayHost: root)
    }

    func showToast(_ text: String) {
        content.toast.show(text)
    }

    func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window { alert.beginSheetModal(for: window, completionHandler: nil) } else { alert.runModal() }
    }

    func showFind() { content.showFind() }

    func copyURL() {
        guard let url = state.selectedTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast("Link copied")
    }

    /// Zooms the page and remembers the level for the site, like Safari.
    func zoom(by delta: CGFloat?) {
        guard let wv = state.selectedTab?.webView else { return }
        let levels: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
        let z: CGFloat
        if let delta {
            let current = wv.pageZoom
            z = delta > 0 ? (levels.first { $0 > current + 0.001 } ?? 3) : (levels.last { $0 < current - 0.001 } ?? 0.5)
        } else {
            z = Settings.defaultZoom
        }
        wv.pageZoom = z
        if let host = wv.url?.host() {
            SiteSettings.update(host) { $0.zoom = abs(z - Settings.defaultZoom) < 0.001 ? nil : Double(z) }
        }
        showToast("Zoom \(Int((z * 100).rounded()))%")
    }

    // MARK: Site settings

    func showSiteInfo() {
        guard let url = state.selectedTab?.url, let host = url.host() else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = SiteInfoViewController(host: host, secure: url.scheme == "https")
        if !sidebarHidden || peeking, Settings.showAddressBar {
            let anchor = sidebar.urlPill.siteButton
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: onRight ? .minX : .maxX)
        } else {
            popover.show(relativeTo: NSRect(x: content.bounds.midX, y: content.bounds.maxY - 4, width: 1, height: 1),
                         of: content, preferredEdge: .minY)
        }
    }

    // MARK: Downloads

    func showDownloads(from anchor: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = DownloadsViewController()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    // MARK: Extensions

    func showExtensionsMenu() {
        let anchor = sidebar.urlPill.extensionsButton
        let menu = NSMenu()
        let manager = ExtensionManager.shared
        let tab = state.selectedTab
        let contexts = manager.contexts
        if contexts.isEmpty {
            let empty = NSMenuItem(title: "No extensions yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for ctx in contexts {
            let action = ctx.action(for: tab)
            var title = ctx.webExtension.displayName ?? "Extension"
            if let badge = action?.badgeText, !badge.isEmpty { title += "  (\(badge))" }
            let item = ClosureMenuItem(title) { ctx.performAction(for: tab) }
            let size = NSSize(width: 16, height: 16)
            item.image = action?.icon(for: size) ?? ctx.webExtension.icon(for: size)
            item.image?.size = size
            item.isEnabled = action?.isEnabled ?? true
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Add from Chrome Web Store…") { [weak self] in self?.promptChromeWebStore() })
        menu.addItem(ClosureMenuItem("Browse Chrome Web Store") { [weak self] in
            self?.state.openTab(url: URL(string: "https://chromewebstore.google.com")!, select: true)
        })
        menu.addItem(ClosureMenuItem("Install from File or Folder…") { [weak self] in self?.promptInstallFile() })
        if !contexts.isEmpty {
            let remove = NSMenuItem(title: "Remove Extension", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for ctx in contexts {
                sub.addItem(ClosureMenuItem(ctx.webExtension.displayName ?? "Extension") { manager.uninstall(ctx) })
            }
            remove.submenu = sub
            menu.addItem(remove)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
    }

    func presentExtensionPopup(_ action: WKWebExtension.Action) {
        guard let popover = action.popupPopover else { return }
        let anchor = sidebar.urlPill.extensionsButton
        if sidebarHidden && !peeking, let wv = content.webView {
            popover.show(relativeTo: NSRect(x: 20, y: wv.bounds.height - 20, width: 1, height: 1), of: wv, preferredEdge: .maxY)
        } else {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        }
    }

    func promptChromeWebStore() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Add a Chrome extension"
        alert.informativeText = "Paste a Chrome Web Store link or extension ID. Tip: on the Chrome Web Store, Brook adds an “Add to Brook” button to each extension page."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://chromewebstore.google.com/detail/…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let input = field.stringValue
            Task { @MainActor in
                do {
                    try await ExtensionManager.shared.installFromChromeWebStore(input)
                    self?.showToast("Extension added")
                } catch ExtensionInstallError.cancelled {
                } catch {
                    self?.showError(error)
                }
            }
        }
    }

    func promptInstallFile() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.message = "Choose an unpacked extension folder, a .crx, or a .zip"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await ExtensionManager.shared.install(from: url)
                    self?.showToast("Extension added")
                } catch ExtensionInstallError.cancelled {
                } catch {
                    self?.showError(error)
                }
            }
        }
    }

    // MARK: Spaces

    func promptNewSpace() {
        let used = Set(state.spaces.map(\.colorHex))
        let color = Palette.spaceColors.first { !used.contains($0.hex) }?.hex ?? Palette.spaceColors[0].hex
        let draft = SpaceDraft(name: "", colorHex: color, searchEngineID: nil, separateProfile: false)
        showSpaceEditor(title: "New Space", draft: draft) { [weak self] d in
            guard let self else { return }
            self.state.addSpace(name: d.name.isEmpty ? "Space \(self.state.spaces.count + 1)" : d.name,
                                colorHex: d.colorHex, searchEngineID: d.searchEngineID, separateProfile: d.separateProfile)
        }
    }

    func promptEditSpace(_ space: Space) {
        let draft = SpaceDraft(name: space.name, colorHex: space.colorHex,
                               searchEngineID: space.searchEngineID, separateProfile: space.profileID != nil)
        showSpaceEditor(title: "Edit Space", draft: draft) { [weak self] d in
            self?.state.updateSpace(space, name: d.name.isEmpty ? space.name : d.name, colorHex: d.colorHex,
                                    searchEngineID: d.searchEngineID, separateProfile: d.separateProfile)
        }
    }

    func confirmDeleteSpace(_ space: Space) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(space.name)”?"
        alert.informativeText = "Its tabs will be closed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.state.deleteSpace(space) }
        }
    }

    private func showSpaceEditor(title: String, draft: SpaceDraft, completion: @escaping (SpaceDraft) -> Void) {
        guard let window else { return }
        let editor = SpaceEditorView(draft: draft)
        let alert = NSAlert()
        alert.messageText = title
        alert.accessoryView = editor
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = editor.nameField
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let result = editor.draft
            if draft.separateProfile && !result.separateProfile {
                // Turning a profile off deletes its cookies and logins; make sure that's intended.
                let confirm = NSAlert()
                confirm.messageText = "Stop using a separate profile?"
                confirm.informativeText = "This space’s cookies, logins and site data will be deleted, and its tabs will use your main profile."
                confirm.addButton(withTitle: "Delete Profile Data")
                confirm.addButton(withTitle: "Cancel")
                confirm.buttons.first?.hasDestructiveAction = true
                if confirm.runModal() != .alertFirstButtonReturn { return }
            }
            completion(result)
        }
    }

    // MARK: Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        state.saveNow()
        return true
    }
}

// MARK: - Downloads popover

@MainActor
final class DownloadsViewController: NSViewController {
    private let stack = NSStackView()
    private var timer: Timer?
    private var helpers: [ClosureButtonTarget] = []

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        stack.pinEdges(to: v)
        v.widthAnchor.constraint(equalToConstant: 320).isActive = true
        view = v
        rebuild()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        timer?.invalidate()
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        helpers.removeAll()
        let items = DownloadManager.shared.items
        if items.isEmpty {
            stack.addArrangedSubview(NSTextField(labelWithString: "No downloads"))
            return
        }
        for item in items.prefix(8) {
            let name = NSTextField(labelWithString: item.filename)
            name.font = .systemFont(ofSize: 13, weight: .medium)
            name.lineBreakMode = .byTruncatingMiddle
            name.widthAnchor.constraint(equalToConstant: 250).isActive = true
            let row = NSStackView(views: [name])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 4
            switch item.status {
            case .active:
                let bar = NSProgressIndicator()
                bar.isIndeterminate = false
                bar.doubleValue = item.fraction * 100
                bar.controlSize = .small
                bar.widthAnchor.constraint(equalToConstant: 250).isActive = true
                row.addArrangedSubview(bar)
            case .finished:
                let reveal = NSButton(title: "Show in Finder", target: nil, action: nil)
                reveal.bezelStyle = .inline
                reveal.controlSize = .small
                let dest = item.destination
                let helper = ClosureButtonTarget { if let dest { NSWorkspace.shared.activateFileViewerSelecting([dest]) } }
                reveal.target = helper
                reveal.action = #selector(ClosureButtonTarget.run)
                helpers.append(helper)
                row.addArrangedSubview(reveal)
            case .failed:
                let failed = NSTextField(labelWithString: "Failed")
                failed.textColor = .systemRed
                failed.font = .systemFont(ofSize: 11)
                row.addArrangedSubview(failed)
            }
            stack.addArrangedSubview(row)
        }
        if items.contains(where: { $0.status != .active }) {
            let clear = NSButton(title: "Clear", target: self, action: #selector(clear))
            clear.bezelStyle = .inline
            clear.controlSize = .small
            stack.addArrangedSubview(clear)
        }
    }

    @objc private func clear() {
        DownloadManager.shared.clearFinished()
        rebuild()
    }
}

final class ClosureButtonTarget: NSObject {
    private let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func run() { block() }
}
