import AppKit
import WebKit

// MARK: - Per-site settings

/// Overrides for one site. `nil` means "use the global setting".
struct SiteOverride: Codable, Equatable {
    var zoom: Double?
    var javascript: Bool?
    var autoplay: String?
    var cookiePopups: Bool?

    var isEmpty: Bool { zoom == nil && javascript == nil && autoplay == nil && cookiePopups == nil }
}

@MainActor
enum SiteSettings {
    private static var cache: [String: SiteOverride]?

    /// Sites are keyed by host without a leading "www.".
    static func key(for host: String) -> String {
        let h = host.lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    static var all: [String: SiteOverride] {
        get {
            if let cache { return cache }
            cache = Settings.json("siteSettings", as: [String: SiteOverride].self) ?? [:]
            return cache!
        }
        set {
            cache = newValue.filter { !$0.value.isEmpty }
            Settings.setJSON(cache!, "siteSettings")
        }
    }

    static func invalidate() { cache = nil }

    /// The override for a host, falling back to its parent domains ("m.example.com" → "example.com").
    static func override(for host: String?) -> SiteOverride {
        guard let host else { return SiteOverride() }
        var h = key(for: host)
        let map = all
        while true {
            if let o = map[h] { return o }
            guard let dot = h.firstIndex(of: "."), h[h.index(after: dot)...].contains(".") else { return SiteOverride() }
            h = String(h[h.index(after: dot)...])
        }
    }

    static func update(_ host: String, _ change: (inout SiteOverride) -> Void) {
        let k = key(for: host)
        var map = all
        var o = map[k] ?? SiteOverride()
        change(&o)
        map[k] = o
        all = map
    }

    static func remove(_ host: String) {
        var map = all
        map[key(for: host)] = nil
        all = map
    }

    // Resolved values

    static func zoom(for host: String?) -> Double { override(for: host).zoom ?? Settings.defaultZoom }
    static func javascript(for host: String?) -> Bool { override(for: host).javascript ?? Settings.javascriptEnabled }
    static func cookiePopups(for host: String?) -> Bool { override(for: host).cookiePopups ?? Settings.blockCookiePopups }
    static func autoplay(for host: String?) -> AutoplayPolicy {
        override(for: host).autoplay.flatMap(AutoplayPolicy.init(rawValue:)) ?? Settings.autoplay
    }
}

extension AutoplayPolicy {
    var mediaTypes: WKAudiovisualMediaTypes {
        switch self {
        case .allow: return []
        case .blockAudio: return .audio
        case .blockAll: return .all
        }
    }
}

// MARK: - Boosts

/// Custom CSS and JavaScript applied to matching sites, like Arc's Boosts.
struct Boost: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    /// Domain the boost applies to (subdomains included), or "*" for every site.
    var site: String
    var css: String = ""
    var js: String = ""
    var enabled = true

    func matches(host: String?) -> Bool {
        let pattern = site.trimmingCharacters(in: .whitespaces).lowercased()
        if pattern == "*" { return true }
        guard let host = host?.lowercased(), !pattern.isEmpty else { return false }
        let p = pattern.hasPrefix("www.") ? String(pattern.dropFirst(4)) : pattern
        return host == p || host.hasSuffix("." + p)
    }
}

@MainActor
enum Boosts {
    static let world = WKContentWorld.world(name: "BrookBoosts")
    private static var cache: [Boost]?

    static var all: [Boost] {
        get {
            if let cache { return cache }
            cache = Settings.json("boosts", as: [Boost].self) ?? []
            return cache!
        }
        set {
            cache = newValue
            Settings.setJSON(newValue, "boosts")
        }
    }

    static func invalidate() { cache = nil }

    static func boosts(for host: String?) -> [Boost] { all.filter { $0.matches(host: host) } }

    static func save(_ boost: Boost) {
        var list = all
        if let i = list.firstIndex(where: { $0.id == boost.id }) { list[i] = boost } else { list.append(boost) }
        all = list
    }

    static func delete(_ id: UUID) {
        all = all.filter { $0.id != id }
    }

    /// One user script for all enabled boosts. Each boost checks the hostname itself, so the
    /// script is compiled once and shared by every tab.
    static func userScript() -> WKUserScript? {
        let enabled = all.filter { $0.enabled && (!$0.css.isEmpty || !$0.js.isEmpty) }
        guard !enabled.isEmpty else { return nil }
        var parts: [String] = []
        for b in enabled {
            let site = jsString(b.site.trimmingCharacters(in: .whitespaces).lowercased())
            let css = jsString(b.css)
            let js = b.js.isEmpty ? "" : "try { (function(){\n\(b.js)\n})(); } catch (e) { console.error('Brook Boost', e); }"
            parts.append("""
            if (m(\(site))) {
              if (\(css).length) addCSS(\(css));
              \(js)
            }
            """)
        }
        let source = """
        (function () {
          if (window.top !== window) return;
          var h = location.hostname.toLowerCase();
          function m(p) {
            if (p === '*') return true;
            if (p.indexOf('www.') === 0) p = p.slice(4);
            return h === p || h.endsWith('.' + p);
          }
          function addCSS(css) {
            try {
              var sheet = new CSSStyleSheet();
              sheet.replaceSync(css);
              document.adoptedStyleSheets = document.adoptedStyleSheets.concat([sheet]);
            } catch (e) {
              var s = document.createElement('style');
              s.textContent = css;
              (document.head || document.documentElement).appendChild(s);
            }
          }
          \(parts.joined(separator: "\n"))
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world)
    }

    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }
}
