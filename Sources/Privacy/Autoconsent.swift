import AppKit
import WebKit

/// Downloads DuckDuckGo's public privacy configuration, which carries the
/// cookie-popup rule list, and keeps a cached copy on disk.
@MainActor
final class PrivacyConfigStore {
    static let shared = PrivacyConfigStore()

    private static let remote = URL(string: "https://staticcdn.duckduckgo.com/trackerblocking/config/v4/macos-config.json")!
    private let fileURL = AppPaths.support.appendingPathComponent("privacy-config.json")
    private let refreshInterval: TimeInterval = 24 * 3600

    private(set) var compactRules: Any?
    private(set) var disabledCMPs: [String] = []
    private(set) var enabled = true
    private var exceptions: Set<String> = []

    func load() {
        if let data = try? Data(contentsOf: fileURL) { apply(data) }
        Task { await refreshIfNeeded() }
    }

    func refreshIfNeeded() async {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let modified = attrs?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < refreshInterval, compactRules != nil { return }
        guard let result = try? await URLSession.shared.data(from: Self.remote),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return }
        if apply(result.0) {
            try? result.0.write(to: fileURL, options: .atomic)
        }
    }

    @discardableResult
    private func apply(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [String: Any],
              let ac = features["autoconsent"] as? [String: Any] else { return false }
        enabled = (ac["state"] as? String ?? "enabled") == "enabled"
        let settings = ac["settings"] as? [String: Any] ?? [:]
        compactRules = settings["compactRuleList"]
        disabledCMPs = settings["disabledCMPs"] as? [String] ?? []
        var ex = Set<String>()
        for list in [ac["exceptions"], root["unprotectedTemporary"]] {
            for item in list as? [[String: Any]] ?? [] {
                if let d = item["domain"] as? String { ex.insert(d.lowercased()) }
            }
        }
        exceptions = ex
        return true
    }

    func isExcepted(host: String) -> Bool {
        var h = host.lowercased()
        while true {
            if exceptions.contains(h) { return true }
            guard let dot = h.firstIndex(of: ".") else { return false }
            h = String(h[h.index(after: dot)...])
            if !h.contains(".") { return false }
        }
    }
}

/// Native side of DuckDuckGo's autoconsent script, which finds cookie consent
/// popups and clicks "reject" for you. Mirrors DuckDuckGo's AutoconsentUserScript.
@MainActor
final class AutoconsentHandler: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = AutoconsentHandler()

    private static let messageNames = ["init", "eval", "popupFound", "optOutResult", "optInResult",
                                       "selfTestResult", "autoconsentDone", "autoconsentError", "report", "cmpDetected"]
    private var recentlyHandled: [String: Date] = [:]

    func install(into ucc: WKUserContentController) {
        guard let url = Bundle.main.url(forResource: "autoconsent-bundle", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false, in: .defaultClient)
        ucc.addUserScript(script)
        for name in Self.messageNames {
            ucc.addScriptMessageHandler(self, contentWorld: .defaultClient, name: name)
        }
    }

    private static let ok: [String: Any] = ["type": "ok"]

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        let body = message.body as? [String: Any] ?? [:]
        switch message.name {
        case "init":
            return (initResponse(message, body), nil)
        case "eval":
            return await evaluate(message, body)
        case "autoconsentDone":
            if message.frameInfo.isMainFrame,
               let tab = (message.webView as? DriftWebView)?.tab {
                tab.consentCMP = body["cmp"] as? String ?? "cookie popup"
                tab.state?.tabDidChange(tab, .consent)
                let cosmetic = body["isCosmetic"] as? Bool ?? false
                if !cosmetic, let host = message.frameInfo.request.url?.host() {
                    recentlyHandled[host] = Date()
                }
            }
            return (Self.ok, nil)
        default:
            return (Self.ok, nil)
        }
    }

    private func initResponse(_ message: WKScriptMessage, _ body: [String: Any]) -> [String: Any] {
        let config = PrivacyConfigStore.shared
        guard Settings.blockCookiePopups, config.enabled,
              let url = URL(string: body["url"] as? String ?? ""),
              let scheme = url.scheme, scheme == "http" || scheme == "https",
              let host = url.host() else { return Self.ok }

        let topHost = message.webView?.url?.host() ?? host
        if config.isExcepted(host: topHost) { return Self.ok }

        // If we just handled a popup on this site and the page reloaded, don't loop.
        var autoAction: Any = "optOut"
        if let last = recentlyHandled[host], Date().timeIntervalSince(last) < 10 {
            autoAction = NSNull()
        }

        var rules: [String: Any] = [:]
        if let compact = config.compactRules { rules["compact"] = compact }

        return [
            "type": "initResp",
            "rules": rules,
            "config": [
                "enabled": true,
                "autoAction": autoAction,
                "disabledCmps": config.disabledCMPs,
                "enablePrehide": true,
                "enableCosmeticRules": true,
                "detectRetries": 20,
                "isMainWorld": false,
                "enableHeuristicDetection": true,
                "heuristicMode": "off"
            ] as [String: Any]
        ]
    }

    private func evaluate(_ message: WKScriptMessage, _ body: [String: Any]) async -> (Any?, String?) {
        guard let webView = message.webView, let code = body["code"] as? String else {
            return (nil, "missing frame target")
        }
        let id = body["id"] ?? ""
        let script = "(() => { try { return !!(\(code)); } catch (e) { return false; } })();"
        let frame = message.frameInfo
        return await withCheckedContinuation { (cont: CheckedContinuation<(Any?, String?), Never>) in
            webView.evaluateJavaScript(script, in: frame, in: .page) { result in
                switch result {
                case .success(let value):
                    cont.resume(returning: (["type": "evalResp", "id": id, "result": value] as [String: Any], nil))
                case .failure:
                    cont.resume(returning: (["type": "evalResp", "id": id, "result": false] as [String: Any], nil))
                }
            }
        }
    }
}
