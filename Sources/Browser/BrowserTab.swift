import AppKit
import WebKit

struct TabChange: OptionSet {
    let rawValue: Int
    static let title = TabChange(rawValue: 1 << 0)
    static let url = TabChange(rawValue: 1 << 1)
    static let favicon = TabChange(rawValue: 1 << 2)
    static let loading = TabChange(rawValue: 1 << 3)
    static let progress = TabChange(rawValue: 1 << 4)
    static let navigation = TabChange(rawValue: 1 << 5)
    static let consent = TabChange(rawValue: 1 << 6)
    static let error = TabChange(rawValue: 1 << 7)
    static let loaded = TabChange(rawValue: 1 << 8)
}

@MainActor
final class BrowserTab: NSObject {
    let id: UUID
    private(set) var url: URL?
    private(set) var title: String
    /// For pinned tabs and favorites: where the tab goes back to when it is closed.
    var homeURL: URL?
    var isPinned = false
    var isFavorite = false
    var favicon: NSImage?
    var lastActive = Date()
    private(set) var webView: BrookWebView?
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var loadError: String?
    var consentCMP: String?
    weak var state: BrowserState?

    private var observations: [NSKeyValueObservation] = []
    private var pendingConfiguration: WKWebViewConfiguration?
    private var mediaPermissions: [String: WKPermissionDecision] = [:]

    init(id: UUID = UUID(), url: URL?, title: String = "") {
        self.id = id
        self.url = url
        self.title = title
        super.init()
        if let host = url?.host() {
            favicon = FaviconStore.shared.cachedIcon(for: host)
            // Restored tabs that were never loaded still deserve their site icon, not a globe.
            if favicon == nil { refreshFavicon() }
        }
    }

    /// A tab created by a page (window.open). WebKit loads it, so we must use its configuration.
    static func popup(configuration: WKWebViewConfiguration) -> BrowserTab {
        let tab = BrowserTab(url: nil)
        tab.pendingConfiguration = configuration
        return tab
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let url { return URLParser.display(url) }
        return "New Tab"
    }

    var isLoaded: Bool { webView != nil }

    // MARK: Lifecycle

    @discardableResult
    func materialize() -> BrookWebView {
        if let webView { return webView }
        let config = pendingConfiguration ?? WebViewFactory.makeConfiguration(
            profileID: state?.profileID(for: self),
            autoplay: SiteSettings.autoplay(for: url?.host()))
        let isPopup = pendingConfiguration != nil
        pendingConfiguration = nil

        let wv = BrookWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        wv.tab = self
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        wv.isInspectable = true
        wv.underPageBackgroundColor = .textBackgroundColor
        wv.pageZoom = SiteSettings.zoom(for: url?.host())
        webView = wv
        observe(wv)
        if !isPopup, let url { wv.load(URLRequest(url: url)) }
        ExtensionManager.shared.tabDidOpen(self)
        state?.tabDidChange(self, .loaded)
        return wv
    }

    /// Frees the web content process memory. The tab stays in the sidebar and reloads on demand.
    func unload() {
        guard let wv = webView else { return }
        ExtensionManager.shared.tabWillClose(self)
        observations.removeAll()
        wv.stopLoading()
        wv.navigationDelegate = nil
        wv.uiDelegate = nil
        wv.removeFromSuperview()
        webView = nil
        isLoading = false
        progress = 0
        state?.tabDidChange(self, [.loading, .loaded])
    }

    /// Pinned tabs and favorites return to their home page when closed.
    func resetToHome() {
        unload()
        if let homeURL { url = homeURL }
        loadError = nil
        consentCMP = nil
    }

    func load(_ url: URL) {
        self.url = url
        loadError = nil
        let wv = materialize()
        wv.load(URLRequest(url: url))
        state?.tabDidChange(self, [.url, .error])
    }

    func reload() {
        loadError = nil
        state?.tabDidChange(self, .error)
        if let wv = webView {
            if wv.url == nil, let url { wv.load(URLRequest(url: url)) } else { wv.reload() }
        } else {
            materialize()
        }
    }

    /// Returns true if the tab is doing something the user would notice if we unloaded it.
    func isBusy() async -> Bool {
        guard let wv = webView else { return false }
        if wv.cameraCaptureState != .none || wv.microphoneCaptureState != .none { return true }
        let playing: Bool = await withCheckedContinuation { cont in
            wv.requestMediaPlaybackState(completionHandler: { state in cont.resume(returning: state == .playing) })
        }
        return playing
    }

    private func observe(_ wv: WKWebView) {
        observations = [
            wv.observe(\.title, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated {
                    guard let self, let t = wv.title, !t.isEmpty else { return }
                    self.title = t
                    if let url = wv.url { HistoryStore.shared.updateTitle(t, for: url) }
                    self.state?.tabDidChange(self, .title)
                }
            },
            wv.observe(\.url, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated {
                    guard let self, let u = wv.url else { return }
                    let hostChanged = u.host() != self.url?.host()
                    self.url = u
                    if hostChanged, let host = u.host() {
                        self.favicon = FaviconStore.shared.cachedIcon(for: host)
                        self.state?.tabDidChange(self, .favicon)
                    }
                    self.state?.tabDidChange(self, .url)
                }
            },
            wv.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isLoading = wv.isLoading
                    self.state?.tabDidChange(self, .loading)
                }
            },
            wv.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.progress = wv.estimatedProgress
                    self.state?.tabDidChange(self, .progress)
                }
            },
            wv.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.state?.tabDidChange(self, .navigation)
                }
            },
            wv.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.state?.tabDidChange(self, .navigation)
                }
            }
        ]
    }

    func refreshFavicon() {
        guard let host = url?.host() else { return }
        Task { [weak self] in
            let icon = await FaviconStore.shared.icon(for: host)
            guard let self, let icon, self.url?.host() == host else { return }
            self.favicon = icon
            self.state?.tabDidChange(self, .favicon)
        }
    }
}

// MARK: - Navigation

extension BrowserTab: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        let policy = decidePolicy(for: navigationAction)
        if policy == .allow, navigationAction.targetFrame?.isMainFrame ?? true,
           let host = navigationAction.request.url?.host() {
            preferences.allowsContentJavaScript = SiteSettings.javascript(for: host)
        }
        return (policy, preferences)
    }

    private func decidePolicy(for navigationAction: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        if navigationAction.shouldPerformDownload { return .download }

        let scheme = url.scheme?.lowercased() ?? ""
        let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript",
                                       "webkit-extension", "safari-web-extension"]
        if !webSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
            return .cancel
        }

        // ⌘-click or middle-click opens a background tab, like every other browser.
        let isMainFrameLink = navigationAction.navigationType == .linkActivated
        if isMainFrameLink && (navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2) {
            let foreground = navigationAction.modifierFlags.contains(.shift)
            state?.openTab(url: url, after: self, select: foreground, loadNow: true)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !navigationResponse.canShowMIMEType { return .download }
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment"), navigationResponse.isForMainFrame {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        DownloadManager.shared.track(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        DownloadManager.shared.track(download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        consentCMP = nil
        if loadError != nil {
            loadError = nil
            state?.tabDidChange(self, .error)
        }
        state?.tabDidChange(self, .consent)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Per-site zoom, remembered like Safari does.
        let zoom = SiteSettings.zoom(for: webView.url?.host())
        if abs(webView.pageZoom - zoom) > 0.001 { webView.pageZoom = zoom }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { HistoryStore.shared.record(url: url, title: webView.title) }
        refreshFavicon()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        let ns = error as NSError
        // Cancelled loads, and "frame load interrupted" (downloads, policy changes), aren't errors.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 204) { return }
        loadError = ns.localizedDescription
        state?.tabDidChange(self, .error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest,
              challenge.previousFailureCount < 3,
              let window = webView.window else {
            return (.performDefaultHandling, nil)
        }
        let alert = NSAlert()
        alert.messageText = "Log in to \(challenge.protectionSpace.host)"
        alert.informativeText = challenge.protectionSpace.realm ?? "This site requires a username and password."
        alert.addButton(withTitle: "Log In")
        alert.addButton(withTitle: "Cancel")
        let user = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        user.placeholderString = "Username"
        let pass = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        pass.placeholderString = "Password"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        box.addSubview(user)
        box.addSubview(pass)
        alert.accessoryView = box
        alert.window.initialFirstResponder = user
        let response = await alert.beginSheetModal(for: window)
        guard response == .alertFirstButtonReturn else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(user: user.stringValue, password: pass.stringValue, persistence: .forSession))
    }
}

// MARK: - UI

extension BrowserTab: WKUIDelegate {

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let state else { return nil }
        let tab = BrowserTab.popup(configuration: configuration)
        let background = navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2
        state.insert(popup: tab, after: self, select: !background)
        return tab.materialize()
    }

    func webViewDidClose(_ webView: WKWebView) {
        state?.close(self)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        guard let window = webView.window else { return }
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page says" : "\(frame.securityOrigin.host) says"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = await alert.beginSheetModal(for: window)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        guard let window = webView.window else { return false }
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page says" : "\(frame.securityOrigin.host) says"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        guard let window = webView.window else { return nil }
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        guard let window = webView.window else { return nil }
        let response = await panel.beginSheetModal(for: window)
        return response == .OK ? panel.urls : nil
    }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        let key = "\(origin.host)#\(type.rawValue)"
        if let remembered = mediaPermissions[key] { return remembered }
        guard let window = webView.window else { return .deny }
        let what: String
        switch type {
        case .camera: what = "your camera"
        case .microphone: what = "your microphone"
        default: what = "your camera and microphone"
        }
        let alert = NSAlert()
        alert.messageText = "Allow \(origin.host) to use \(what)?"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        let decision: WKPermissionDecision = await alert.beginSheetModal(for: window) == .alertFirstButtonReturn ? .grant : .deny
        mediaPermissions[key] = decision
        return decision
    }
}
