import AppKit
import WebKit

enum ExtensionAPIError: Error {
    case notSupported
}

// MARK: - Tabs, as seen by extensions

extension BrowserTab: WKWebExtensionTab {

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        ExtensionManager.shared.window
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        webView
    }

    func title(for context: WKWebExtensionContext) -> String? {
        title
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        isPinned || isFavorite
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        webView?.url ?? url
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !isLoading
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        state?.selectedTab === self
    }

    func size(for context: WKWebExtensionContext) -> CGSize {
        webView?.frame.size ?? .zero
    }

    func zoomFactor(for context: WKWebExtensionContext) -> Double {
        Double(webView?.pageZoom ?? 1)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        load(url)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        if fromOrigin { webView?.reloadFromOrigin() } else { reload() }
    }

    func goBack(for context: WKWebExtensionContext) async throws {
        webView?.goBack()
    }

    func goForward(for context: WKWebExtensionContext) async throws {
        webView?.goForward()
    }

    func activate(for context: WKWebExtensionContext) async throws {
        state?.select(self)
    }

    func setSelected(_ selected: Bool, for context: WKWebExtensionContext) async throws {
        if selected { state?.select(self) }
    }

    func close(for context: WKWebExtensionContext) async throws {
        state?.remove(self)
    }

    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool {
        true
    }
}

// MARK: - The browser window, as seen by extensions

extension BrowserWindowController: WKWebExtensionWindow {

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        // Only tabs with live web views exist as far as extensions are concerned.
        BrowserState.shared.allTabs.filter { $0.isLoaded }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let tab = BrowserState.shared.selectedTab, tab.isLoaded else { return nil }
        return tab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        if window.isMiniaturized { return .minimized }
        return .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        false
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        window?.screen?.frame ?? .zero
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        window?.frame ?? .zero
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext) async throws {
        window?.setFrame(frame, display: true)
    }

    func focus(for context: WKWebExtensionContext) async throws {
        window?.makeKeyAndOrderFront(nil)
    }

    func close(for context: WKWebExtensionContext) async throws {
        window?.performClose(nil)
    }
}
