import AppKit

enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Brook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let caches: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Brook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func sub(_ name: String, in base: URL = support) -> URL {
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Settings

enum SearchEngine: String, CaseIterable {
    case duckduckgo, google, bing, brave, kagi

    var title: String {
        switch self {
        case .duckduckgo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .brave: return "Brave Search"
        case .kagi: return "Kagi"
        }
    }

    func url(for query: String) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let q = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        let base: String
        switch self {
        case .duckduckgo: base = "https://duckduckgo.com/?q="
        case .google: base = "https://www.google.com/search?q="
        case .bing: base = "https://www.bing.com/search?q="
        case .brave: base = "https://search.brave.com/search?q="
        case .kagi: base = "https://kagi.com/search?q="
        }
        return URL(string: base + q)!
    }
}

enum Settings {
    private static let d = UserDefaults.standard

    static var searchEngine: SearchEngine {
        get { SearchEngine(rawValue: d.string(forKey: "searchEngine") ?? "") ?? .duckduckgo }
        set { d.set(newValue.rawValue, forKey: "searchEngine") }
    }

    static var blockCookiePopups: Bool {
        get { d.object(forKey: "blockCookiePopups") as? Bool ?? true }
        set { d.set(newValue, forKey: "blockCookiePopups") }
    }

    /// Minutes before a background tab is unloaded from memory. 0 = never.
    static var hibernateMinutes: Int {
        get { d.object(forKey: "hibernateMinutes") as? Int ?? 30 }
        set { d.set(newValue, forKey: "hibernateMinutes") }
    }

    static var sidebarWidth: CGFloat {
        get { CGFloat(d.object(forKey: "sidebarWidth") as? Double ?? 250) }
        set { d.set(Double(newValue), forKey: "sidebarWidth") }
    }

    static var sidebarHidden: Bool {
        get { d.bool(forKey: "sidebarHidden") }
        set { d.set(newValue, forKey: "sidebarHidden") }
    }
}

// MARK: - URL input

enum URLParser {
    static func url(from input: String) -> URL? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        let lower = s.lowercased()
        for scheme in ["http://", "https://", "file://", "about:", "data:", "webkit-extension://"] where lower.hasPrefix(scheme) {
            return URL(string: s)
        }
        if lower.hasPrefix("localhost") ||
            s.range(of: #"^\d{1,3}(\.\d{1,3}){3}(:\d+)?([/?#].*)?$"#, options: .regularExpression) != nil {
            return URL(string: "http://" + s)
        }
        if s.range(of: #"^[^\s/:?#@]+\.[a-zA-Z]{2,63}\.?(:\d+)?([/?#].*)?$"#, options: .regularExpression) != nil {
            return URL(string: "https://" + s)
        }
        return nil
    }

    static func destination(for input: String) -> URL {
        url(from: input) ?? Settings.searchEngine.url(for: input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Short, human friendly form of a URL for the address pill.
    static func display(_ url: URL?) -> String {
        guard let url else { return "" }
        if let host = url.host(percentEncoded: false) {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return url.absoluteString
    }
}

// MARK: - Colors

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

enum Palette {
    static let spaceColors: [(name: String, hex: String)] = [
        ("Violet", "#7B61FF"), ("Blue", "#2F80ED"), ("Teal", "#1AAE9F"), ("Green", "#34C759"),
        ("Orange", "#FF8A34"), ("Red", "#FF4D5E"), ("Pink", "#FF5DA2"), ("Graphite", "#8E8E93")
    ]

    static let rowSelected = NSColor.dynamic(light: NSColor(white: 1, alpha: 0.78), dark: NSColor(white: 1, alpha: 0.16))
    static let rowHover = NSColor.dynamic(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.07))
    static let pill = NSColor.dynamic(light: NSColor(white: 0, alpha: 0.055), dark: NSColor(white: 1, alpha: 0.08))
    static let tile = NSColor.dynamic(light: NSColor(white: 1, alpha: 0.45), dark: NSColor(white: 1, alpha: 0.07))
    static let divider = NSColor.dynamic(light: NSColor(white: 0, alpha: 0.1), dark: NSColor(white: 1, alpha: 0.1))
}

extension NSView {
    /// Resolves a dynamic color to a CGColor using this view's appearance.
    func cg(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            result = color.cgColor
        }
        return result
    }

    func pinEdges(to other: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: other.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -inset)
        ])
    }
}

extension NSImage {
    static func symbol(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .medium) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    }
}

/// Coalesces rapid calls into one, on the main actor.
@MainActor
final class Debouncer {
    private let delay: TimeInterval
    private var work: DispatchWorkItem?

    init(delay: TimeInterval) { self.delay = delay }

    func call(_ block: @escaping @MainActor () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated { block() } }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func flush(_ block: @MainActor () -> Void) {
        work?.cancel()
        work = nil
        block()
    }
}
