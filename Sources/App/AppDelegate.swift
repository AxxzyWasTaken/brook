import AppKit
import WebKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private static var retained: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private var windowController: BrowserWindowController!
    private var hibernateTimer: Timer?
    private var memoryPressure: DispatchSourceMemoryPressure?
    private var pendingURLs: [URL] = []
    private var state: BrowserState { BrowserState.shared }

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        PrivacyConfigStore.shared.load()
        _ = WebViewFactory.userContentController   // compile content scripts once, up front
        state.load()
        windowController = BrowserWindowController()
        windowController.start()
        for url in pendingURLs { state.openTab(url: url, select: true) }
        pendingURLs.removeAll()

        Task { await ExtensionManager.shared.loadAll() }
        startMemoryManagement()
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.saveNow()
        HistoryStore.shared.saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController?.showWindow(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Links opened from other apps when Drift is the default browser.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard windowController != nil else { pendingURLs += urls; return }
        for url in urls { state.openTab(url: url, select: true) }
        windowController.showWindow(nil)
    }

    // MARK: Memory

    private func startMemoryManagement() {
        hibernateTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated {
                let minutes = Settings.hibernateMinutes
                if minutes > 0 { BrowserState.shared.hibernate(olderThan: TimeInterval(minutes * 60)) }
            }
        }
        hibernateTimer?.tolerance = 60
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                BrowserState.shared.hibernate(olderThan: 60)
            }
        }
        source.resume()
        memoryPressure = source
    }

    // MARK: Menu actions

    private var wc: BrowserWindowController { windowController }

    @objc func newTab(_ sender: Any?) { wc.showWindow(nil); wc.showCommandBar(editing: false) }
    @objc func openLocation(_ sender: Any?) { wc.showWindow(nil); wc.showCommandBar(editing: true) }
    @objc func closeTab(_ sender: Any?) {
        if let key = NSApp.keyWindow, key !== wc.window, !(key is KeyPanel) { key.performClose(nil); return }
        if let tab = state.selectedTab { state.close(tab) } else { wc.window?.performClose(nil) }
    }
    @objc func reopenTab(_ sender: Any?) { state.reopenClosedTab() }
    @objc func togglePin(_ sender: Any?) { if let t = state.selectedTab { state.togglePin(t) } }
    @objc func toggleFavorite(_ sender: Any?) { if let t = state.selectedTab { state.toggleFavorite(t) } }
    @objc func duplicateTab(_ sender: Any?) { if let t = state.selectedTab { state.duplicate(t) } }
    @objc func copyURL(_ sender: Any?) { wc.copyURL() }
    @objc func toggleSidebarMenu(_ sender: Any?) { wc.toggleSidebar() }
    @objc func reload(_ sender: Any?) { state.selectedTab?.reload() }
    @objc func hardReload(_ sender: Any?) { state.selectedTab?.webView?.reloadFromOrigin() }
    @objc func back(_ sender: Any?) { wc.goBack() }
    @objc func forward(_ sender: Any?) { wc.goForward() }
    @objc func zoomIn(_ sender: Any?) { wc.zoom(by: 0.1) }
    @objc func zoomOut(_ sender: Any?) { wc.zoom(by: -0.1) }
    @objc func actualSize(_ sender: Any?) { wc.zoom(by: nil) }
    @objc func find(_ sender: Any?) { wc.showFind() }
    @objc func findNext(_ sender: Any?) { wc.content.findBar.search(forward: true) }
    @objc func findPrevious(_ sender: Any?) { wc.content.findBar.search(forward: false) }
    @objc func nextTab(_ sender: Any?) { state.selectNext(offset: 1) }
    @objc func previousTab(_ sender: Any?) { state.selectNext(offset: -1) }
    @objc func selectTabN(_ sender: NSMenuItem) { state.select(index: sender.tag) }
    @objc func selectSpaceN(_ sender: NSMenuItem) { state.switchToSpace(sender.tag) }
    @objc func nextSpace(_ sender: Any?) { state.switchSpace(by: 1) }
    @objc func previousSpace(_ sender: Any?) { state.switchSpace(by: -1) }
    @objc func newSpace(_ sender: Any?) { wc.promptNewSpace() }
    @objc func editSpace(_ sender: Any?) { wc.promptEditSpace(state.currentSpace) }
    @objc func fire(_ sender: Any?) { wc.fire() }
    @objc func toggleCookiePopups(_ sender: Any?) {
        Settings.blockCookiePopups.toggle()
        wc.showToast(Settings.blockCookiePopups ? "Cookie popups will be declined" : "Cookie popup blocking off")
    }
    @objc func setSearchEngine(_ sender: NSMenuItem) {
        if let e = SearchEngine(rawValue: sender.representedObject as? String ?? "") { Settings.searchEngine = e }
    }
    @objc func setHibernate(_ sender: NSMenuItem) { Settings.hibernateMinutes = sender.tag }
    @objc func addExtensionFromStore(_ sender: Any?) { wc.promptChromeWebStore() }
    @objc func installExtensionFile(_ sender: Any?) { wc.promptInstallFile() }
    @objc func showMainWindow(_ sender: Any?) { wc.showWindow(nil) }
    @objc func setAsDefaultBrowser(_ sender: Any?) {
        let appURL = Bundle.main.bundleURL
        Task {
            try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleCookiePopups(_:)):
            menuItem.state = Settings.blockCookiePopups ? .on : .off
        case #selector(setSearchEngine(_:)):
            menuItem.state = (menuItem.representedObject as? String) == Settings.searchEngine.rawValue ? .on : .off
        case #selector(setHibernate(_:)):
            menuItem.state = menuItem.tag == Settings.hibernateMinutes ? .on : .off
        case #selector(togglePin(_:)):
            menuItem.title = state.selectedTab?.isPinned == true ? "Unpin Tab" : "Pin Tab"
            return state.selectedTab != nil
        case #selector(toggleFavorite(_:)):
            menuItem.title = state.selectedTab?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites"
            return state.selectedTab != nil
        case #selector(back(_:)):
            return state.selectedTab?.webView?.canGoBack ?? false
        case #selector(forward(_:)):
            return state.selectedTab?.webView?.canGoForward ?? false
        case #selector(toggleSidebarMenu(_:)):
            menuItem.title = windowController?.sidebarHidden == true ? "Show Sidebar" : "Hide Sidebar"
        case #selector(selectSpaceN(_:)):
            menuItem.state = menuItem.tag == state.currentSpaceIndex ? .on : .off
            return menuItem.tag < state.spaces.count
        default:
            break
        }
        return true
    }

    // MARK: Menu bar

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.tag = tag
            return i
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            items.forEach { m.addItem($0) }
            top.submenu = m
            main.addItem(top)
            return top
        }

        // App
        let engines = NSMenu()
        for e in SearchEngine.allCases {
            let i = item(e.title, #selector(setSearchEngine(_:)))
            i.representedObject = e.rawValue
            engines.addItem(i)
        }
        let engineItem = NSMenuItem(title: "Search Engine", action: nil, keyEquivalent: "")
        engineItem.submenu = engines
        let hibernate = NSMenu()
        for (title, minutes) in [("After 15 Minutes", 15), ("After 30 Minutes", 30), ("After 1 Hour", 60), ("After 4 Hours", 240), ("Never", 0)] {
            hibernate.addItem(item(title, #selector(setHibernate(_:)), tag: minutes))
        }
        let hibernateItem = NSMenuItem(title: "Unload Background Tabs", action: nil, keyEquivalent: "")
        hibernateItem.submenu = hibernate
        _ = submenu("Drift", [
            item("About Drift", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            engineItem,
            hibernateItem,
            item("Set as Default Browser", #selector(setAsDefaultBrowser(_:))),
            .separator(),
            item("Hide Drift", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Drift", #selector(NSApplication.terminate(_:)), "q")
        ])

        _ = submenu("File", [
            item("New Tab", #selector(newTab(_:)), "t"),
            item("Open Location…", #selector(openLocation(_:)), "l"),
            item("Reopen Closed Tab", #selector(reopenTab(_:)), "t", [.command, .shift]),
            .separator(),
            item("Close Tab", #selector(closeTab(_:)), "w"),
            .separator(),
            item("Pin Tab", #selector(togglePin(_:)), "d"),
            item("Add to Favorites", #selector(toggleFavorite(_:)), "d", [.command, .shift]),
            item("Duplicate Tab", #selector(duplicateTab(_:)), "k", [.command, .option]),
            item("Copy Link", #selector(copyURL(_:)), "c", [.command, .shift])
        ])

        _ = submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(find(_:)), "f"),
            item("Find Next", #selector(findNext(_:)), "g"),
            item("Find Previous", #selector(findPrevious(_:)), "g", [.command, .shift])
        ])

        _ = submenu("View", [
            item("Hide Sidebar", #selector(toggleSidebarMenu(_:)), "s"),
            .separator(),
            item("Reload Page", #selector(reload(_:)), "r"),
            item("Reload Ignoring Cache", #selector(hardReload(_:)), "r", [.command, .shift]),
            .separator(),
            item("Actual Size", #selector(actualSize(_:)), "0"),
            item("Zoom In", #selector(zoomIn(_:)), "="),
            item("Zoom Out", #selector(zoomOut(_:)), "-"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        ])

        var spaceItems: [NSMenuItem] = [
            item("Next Space", #selector(nextSpace(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option]),
            item("Previous Space", #selector(previousSpace(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option]),
            .separator(),
            item("New Space…", #selector(newSpace(_:)), "n", [.command, .shift]),
            item("Edit Space…", #selector(editSpace(_:))),
            .separator()
        ]
        for i in 0..<9 {
            spaceItems.append(item("Space \(i + 1)", #selector(selectSpaceN(_:)), "\(i + 1)", [.control], tag: i))
        }
        _ = submenu("Spaces", spaceItems)

        var tabItems: [NSMenuItem] = [
            item("Back", #selector(back(_:)), "["),
            item("Forward", #selector(forward(_:)), "]"),
            .separator(),
            item("Next Tab", #selector(nextTab(_:)), "\t", [.control]),
            item("Previous Tab", #selector(previousTab(_:)), "\t", [.control, .shift]),
            .separator()
        ]
        for i in 0..<9 {
            tabItems.append(item(i == 8 ? "Last Tab" : "Tab \(i + 1)", #selector(selectTabN(_:)), "\(i + 1)", tag: i))
        }
        _ = submenu("Tabs", tabItems)

        _ = submenu("Privacy", [
            item("Burn Tabs & Data…", #selector(fire(_:)), String(UnicodeScalar(NSBackspaceCharacter)!), [.command, .shift]),
            .separator(),
            item("Decline Cookie Popups", #selector(toggleCookiePopups(_:)))
        ])

        _ = submenu("Extensions", [
            item("Add from Chrome Web Store…", #selector(addExtensionFromStore(_:))),
            item("Install from File or Folder…", #selector(installExtensionFile(_:)))
        ])

        let windowMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Drift", #selector(showMainWindow(_:)), "1", [.command, .option])
        ])
        NSApp.windowsMenu = windowMenu.submenu
        return main
    }
}
