import AppKit
import WebKit

@MainActor
enum WebViewFactory {
    /// Makes sites treat Brook like Safari (same engine), so nothing serves a degraded page.
    static let userAgentSuffix = "Version/26.0 Safari/605.1.15"

    private static var boostScript: WKUserScript?

    /// One shared content controller: scripts are compiled once and reused by every tab.
    static let userContentController: WKUserContentController = {
        let ucc = WKUserContentController()
        AutoconsentHandler.shared.installHandlers(into: ucc)
        ChromeWebStoreBridge.shared.installHandlers(into: ucc)
        if let s = AutoconsentHandler.shared.userScript { ucc.addUserScript(s) }
        if let s = ChromeWebStoreBridge.shared.userScript { ucc.addUserScript(s) }
        boostScript = Boosts.userScript()
        if let boostScript { ucc.addUserScript(boostScript) }
        return ucc
    }()

    /// Swaps in the current Boosts script. WebKit can only remove all scripts at once, so every
    /// other script (including ones web extensions added) is put back as it was.
    /// Pages pick up the change on their next load.
    static func reloadBoosts() {
        let ucc = userContentController
        let old = boostScript
        let keep = ucc.userScripts.filter { $0 !== old }
        boostScript = Boosts.userScript()
        ucc.removeAllUserScripts()
        keep.forEach { ucc.addUserScript($0) }
        if let boostScript { ucc.addUserScript(boostScript) }
    }

    /// Website data for a space: its own store when it has a separate profile, otherwise the shared one.
    static func dataStore(for profileID: UUID?) -> WKWebsiteDataStore {
        guard let profileID else { return .default() }
        return WKWebsiteDataStore(forIdentifier: profileID)
    }

    static func makeConfiguration(profileID: UUID?, autoplay: AutoplayPolicy) -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = dataStore(for: profileID)
        c.userContentController = userContentController
        c.applicationNameForUserAgent = userAgentSuffix
        c.preferences.isElementFullscreenEnabled = true
        c.preferences.isFraudulentWebsiteWarningEnabled = true
        c.preferences.javaScriptCanOpenWindowsAutomatically = false
        c.mediaTypesRequiringUserActionForPlayback = autoplay.mediaTypes
        c.allowsAirPlayForMediaPlayback = true
        c.webExtensionController = ExtensionManager.shared.controller
        return c
    }
}

final class BrookWebView: WKWebView {
    weak var tab: BrowserTab?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "WKMenuItemIdentifierOpenLinkInNewWindow": item.title = "Open Link in New Tab"
            case "WKMenuItemIdentifierOpenImageInNewWindow": item.title = "Open Image in New Tab"
            case "WKMenuItemIdentifierOpenMediaInNewWindow": item.title = "Open Video in New Tab"
            case "WKMenuItemIdentifierOpenFrameInNewWindow": item.title = "Open Frame in New Tab"
            default: break
            }
        }
    }
}
