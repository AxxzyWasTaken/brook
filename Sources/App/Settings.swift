import AppKit

extension Notification.Name {
    /// Posted whenever a setting changes. `userInfo["key"]` names the setting.
    static let brookSettingsDidChange = Notification.Name("BrookSettingsDidChange")
}

// MARK: - Option types

enum ThemeMode: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum SidebarPosition: String, CaseIterable {
    case left, right
    var title: String { self == .left ? "Left" : "Right" }
}

enum TabDensity: String, CaseIterable {
    case compact, comfortable, roomy
    var title: String {
        switch self {
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        case .roomy: return "Roomy"
        }
    }
    var rowHeight: CGFloat {
        switch self {
        case .compact: return 28
        case .comfortable: return 34
        case .roomy: return 40
        }
    }
}

enum NewTabPosition: String, CaseIterable {
    case top, bottom, nextToCurrent
    var title: String {
        switch self {
        case .top: return "At the top"
        case .bottom: return "At the bottom"
        case .nextToCurrent: return "Next to the current tab"
        }
    }
}

enum NewTabPage: String, CaseIterable {
    case commandBar, blank, custom
    var title: String {
        switch self {
        case .commandBar: return "Command bar"
        case .blank: return "Blank page"
        case .custom: return "Custom page"
        }
    }
}

enum PinnedCloseBehavior: String, CaseIterable {
    case resetToHome, unloadOnly, unpin
    var title: String {
        switch self {
        case .resetToHome: return "Unload and go back to its pinned page"
        case .unloadOnly: return "Unload, keep the current page"
        case .unpin: return "Close it and remove the pin"
        }
    }
}

enum AutoplayPolicy: String, CaseIterable {
    case allow, blockAudio, blockAll
    var title: String {
        switch self {
        case .allow: return "Allow all autoplay"
        case .blockAudio: return "Stop media with sound"
        case .blockAll: return "Never autoplay"
        }
    }
    /// Compact form for tight popups.
    var shortTitle: String {
        switch self {
        case .allow: return "Allow"
        case .blockAudio: return "Block sound"
        case .blockAll: return "Block"
        }
    }
}

// MARK: - Settings

/// Every user preference, backed by UserDefaults. Setting a value posts `.brookSettingsDidChange`.
enum Settings {
    private static let d = UserDefaults.standard

    /// Keys included in settings export/import. Window state (sidebar width/hidden) is left out.
    static let exportedKeys = [
        "theme", "sidebarPosition", "pageMargin", "cornerRadius", "tintStrength", "tabDensity", "tabFontSize",
        "showAddressBar", "showFavorites", "showBottomBar", "favoritesColumns",
        "newTabPosition", "newTabPage", "newTabURL", "pinnedClose", "archiveHours", "hibernateMinutes",
        "externalLinksSpace", "downloadFolder", "askDownloadLocation",
        "defaultZoom", "javascriptEnabled", "autoplay", "blockCookiePopups",
        "defaultSearchEngine", "searchEngines", "siteSettings", "boosts"
    ]

    static func notify(_ key: String) {
        NotificationCenter.default.post(name: .brookSettingsDidChange, object: nil, userInfo: ["key": key])
    }

    private static func store(_ value: Any?, _ key: String) {
        if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        notify(key)
    }

    private static func choice<E: RawRepresentable>(_ key: String, _ fallback: E) -> E where E.RawValue == String {
        E(rawValue: d.string(forKey: key) ?? "") ?? fallback
    }

    private static func number(_ key: String, _ fallback: Double) -> Double {
        (d.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
    }

    private static func flag(_ key: String, _ fallback: Bool) -> Bool {
        d.object(forKey: key) as? Bool ?? fallback
    }

    // Appearance

    static var theme: ThemeMode {
        get { choice("theme", .system) }
        set { store(newValue.rawValue, "theme") }
    }

    static var sidebarPosition: SidebarPosition {
        get { choice("sidebarPosition", .left) }
        set { store(newValue.rawValue, "sidebarPosition") }
    }

    /// Gap around the sidebar and page, in points. 0 = edge to edge.
    static var pageMargin: CGFloat {
        get { CGFloat(min(20, max(0, number("pageMargin", 8)))) }
        set { store(Double(newValue), "pageMargin") }
    }

    static var cornerRadius: CGFloat {
        get { CGFloat(min(24, max(0, number("cornerRadius", 12)))) }
        set { store(Double(newValue), "cornerRadius") }
    }

    /// How strongly the space colour tints the window, 0…1.5.
    static var tintStrength: CGFloat {
        get { CGFloat(min(1.5, max(0, number("tintStrength", 1)))) }
        set { store(Double(newValue), "tintStrength") }
    }

    static var tabDensity: TabDensity {
        get { choice("tabDensity", .comfortable) }
        set { store(newValue.rawValue, "tabDensity") }
    }

    static var tabFontSize: CGFloat {
        get { CGFloat(min(17, max(11, number("tabFontSize", 13)))) }
        set { store(Double(newValue), "tabFontSize") }
    }

    static var showAddressBar: Bool {
        get { flag("showAddressBar", true) }
        set { store(newValue, "showAddressBar") }
    }

    static var showFavorites: Bool {
        get { flag("showFavorites", true) }
        set { store(newValue, "showFavorites") }
    }

    static var showBottomBar: Bool {
        get { flag("showBottomBar", true) }
        set { store(newValue, "showBottomBar") }
    }

    static var favoritesColumns: Int {
        get { Int(min(6, max(2, number("favoritesColumns", 4)))) }
        set { store(newValue, "favoritesColumns") }
    }

    // Tabs

    static var newTabPosition: NewTabPosition {
        get { choice("newTabPosition", .top) }
        set { store(newValue.rawValue, "newTabPosition") }
    }

    static var newTabPage: NewTabPage {
        get { choice("newTabPage", .commandBar) }
        set { store(newValue.rawValue, "newTabPage") }
    }

    static var newTabURL: String {
        get { d.string(forKey: "newTabURL") ?? "" }
        set { store(newValue, "newTabURL") }
    }

    static var pinnedClose: PinnedCloseBehavior {
        get { choice("pinnedClose", .resetToHome) }
        set { store(newValue.rawValue, "pinnedClose") }
    }

    /// Hours of inactivity before a regular tab is archived. 0 = never.
    static var archiveHours: Int {
        get { d.object(forKey: "archiveHours") as? Int ?? 0 }
        set { store(newValue, "archiveHours") }
    }

    /// Minutes before a background tab is unloaded from memory. 0 = never.
    static var hibernateMinutes: Int {
        get { d.object(forKey: "hibernateMinutes") as? Int ?? 30 }
        set { store(newValue, "hibernateMinutes") }
    }

    /// Space that links from other apps open in. nil = the current space.
    static var externalLinksSpace: UUID? {
        get { d.string(forKey: "externalLinksSpace").flatMap(UUID.init(uuidString:)) }
        set { store(newValue?.uuidString, "externalLinksSpace") }
    }

    // Downloads

    static var downloadFolder: URL {
        get {
            if let path = d.string(forKey: "downloadFolder") { return URL(fileURLWithPath: path, isDirectory: true) }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        set { store(newValue.path, "downloadFolder") }
    }

    static var askDownloadLocation: Bool {
        get { flag("askDownloadLocation", false) }
        set { store(newValue, "askDownloadLocation") }
    }

    // Websites

    static var defaultZoom: Double {
        get { min(3, max(0.5, number("defaultZoom", 1))) }
        set { store(newValue, "defaultZoom") }
    }

    static var javascriptEnabled: Bool {
        get { flag("javascriptEnabled", true) }
        set { store(newValue, "javascriptEnabled") }
    }

    static var autoplay: AutoplayPolicy {
        get { choice("autoplay", .allow) }
        set { store(newValue.rawValue, "autoplay") }
    }

    static var blockCookiePopups: Bool {
        get { flag("blockCookiePopups", true) }
        set { store(newValue, "blockCookiePopups") }
    }

    // Search

    static var defaultSearchEngine: String {
        get { d.string(forKey: "defaultSearchEngine") ?? d.string(forKey: "searchEngine") ?? "duckduckgo" }
        set { store(newValue, "defaultSearchEngine") }
    }

    // Stored JSON blobs (kept as strings so export is plain JSON)

    static func json<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let s = d.string(forKey: key), let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func setJSON<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        store(String(decoding: data, as: UTF8.self), key)
    }

    // Window state (not exported)

    static var sidebarWidth: CGFloat {
        get { CGFloat(d.object(forKey: "sidebarWidth") as? Double ?? 250) }
        set { d.set(Double(newValue), forKey: "sidebarWidth") }
    }

    static var sidebarHidden: Bool {
        get { d.bool(forKey: "sidebarHidden") }
        set { d.set(newValue, forKey: "sidebarHidden") }
    }

    // MARK: Export / import

    static func exportData() throws -> Data {
        var out: [String: Any] = ["brookSettingsVersion": 1]
        for key in exportedKeys {
            if let v = d.object(forKey: key) { out[key] = v }
        }
        return try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }

    static func importData(_ data: Data) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["brookSettingsVersion"] != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for key in exportedKeys {
            if let v = obj[key] { d.set(v, forKey: key) } else { d.removeObject(forKey: key) }
        }
        notify("*")
    }

    static func resetAll() {
        for key in exportedKeys { d.removeObject(forKey: key) }
        notify("*")
    }
}

// MARK: - Search engines

struct SearchEngine: Codable, Equatable {
    var id: String
    var name: String
    /// URL with `%s` where the query goes.
    var template: String
    /// Type this, a space, then a query in the command bar to search with this engine.
    var keyword: String

    func url(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let q = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: template.replacingOccurrences(of: "%s", with: q))
    }

    var isValid: Bool {
        template.contains("%s") && URL(string: template.replacingOccurrences(of: "%s", with: "x"))?.host() != nil
    }

    static let builtIn: [SearchEngine] = [
        SearchEngine(id: "duckduckgo", name: "DuckDuckGo", template: "https://duckduckgo.com/?q=%s", keyword: "d"),
        SearchEngine(id: "google", name: "Google", template: "https://www.google.com/search?q=%s", keyword: "g"),
        SearchEngine(id: "bing", name: "Bing", template: "https://www.bing.com/search?q=%s", keyword: "b"),
        SearchEngine(id: "brave", name: "Brave Search", template: "https://search.brave.com/search?q=%s", keyword: "br"),
        SearchEngine(id: "kagi", name: "Kagi", template: "https://kagi.com/search?q=%s", keyword: "k"),
        SearchEngine(id: "youtube", name: "YouTube", template: "https://www.youtube.com/results?search_query=%s", keyword: "yt"),
        SearchEngine(id: "wikipedia", name: "Wikipedia", template: "https://en.wikipedia.org/wiki/Special:Search?search=%s", keyword: "w")
    ]
}

@MainActor
enum SearchEngines {
    private static var cache: [SearchEngine]?

    static var all: [SearchEngine] {
        get {
            if let cache { return cache }
            let list = Settings.json("searchEngines", as: [SearchEngine].self) ?? SearchEngine.builtIn
            cache = list.isEmpty ? SearchEngine.builtIn : list
            return cache!
        }
        set {
            cache = newValue
            Settings.setJSON(newValue, "searchEngines")
        }
    }

    static func invalidate() { cache = nil }

    static func engine(id: String?) -> SearchEngine? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static var defaultEngine: SearchEngine {
        engine(id: Settings.defaultSearchEngine) ?? all.first ?? SearchEngine.builtIn[0]
    }

    /// The engine for the current space (spaces can override the default).
    static var current: SearchEngine {
        engine(id: BrowserState.shared.currentSpace.searchEngineID) ?? defaultEngine
    }

    /// Splits "g cats" into (Google, "cats") when "g" is an engine keyword.
    static func keywordMatch(_ input: String) -> (SearchEngine, String)? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard let space = text.firstIndex(of: " ") else { return nil }
        let word = text[..<space].lowercased()
        let rest = text[space...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty, let engine = all.first(where: { !$0.keyword.isEmpty && $0.keyword.lowercased() == word }) else { return nil }
        return (engine, rest)
    }

    static func searchURL(for input: String) -> URL {
        if let (engine, query) = keywordMatch(input), let url = engine.url(for: query) { return url }
        return current.url(for: input) ?? SearchEngine.builtIn[0].url(for: input)!
    }
}

// MARK: - Small AppKit helpers for settings UI

private var controlActionKey: UInt8 = 0

private final class ControlAction: NSObject {
    let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func run(_ sender: NSControl) { handler(sender) }
}

extension NSControl {
    /// Sets the control's action to a closure (retained by the control).
    func onAction(_ handler: @escaping (NSControl) -> Void) {
        let action = ControlAction(handler)
        objc_setAssociatedObject(self, &controlActionKey, action, .OBJC_ASSOCIATION_RETAIN)
        target = action
        self.action = #selector(ControlAction.run(_:))
    }
}
