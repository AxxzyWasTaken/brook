import AppKit
import WebKit

@MainActor
enum WebViewFactory {
    /// Makes sites treat Drift like Safari (same engine), so nothing serves a degraded page.
    static let userAgentSuffix = "Version/26.0 Safari/605.1.15"

    /// One shared content controller: scripts are compiled once and reused by every tab.
    static let userContentController: WKUserContentController = {
        let ucc = WKUserContentController()
        AutoconsentHandler.shared.install(into: ucc)
        ChromeWebStoreBridge.shared.install(into: ucc)
        return ucc
    }()

    static func makeConfiguration() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        c.userContentController = userContentController
        c.applicationNameForUserAgent = userAgentSuffix
        c.preferences.isElementFullscreenEnabled = true
        c.preferences.isFraudulentWebsiteWarningEnabled = true
        c.preferences.javaScriptCanOpenWindowsAutomatically = false
        c.allowsAirPlayForMediaPlayback = true
        c.webExtensionController = ExtensionManager.shared.controller
        return c
    }
}

final class DriftWebView: WKWebView {
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
