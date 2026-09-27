import AppKit
import WebKit

@MainActor
final class Space {
    let id: UUID
    var name: String
    var colorHex: String
    var pinned: [BrowserTab] = []
    var tabs: [BrowserTab] = []
    var lastSelectedID: UUID?
    /// Overrides the default search engine for this space.
    var searchEngineID: String?
    /// When set, the space keeps its own cookies, logins and site data in this store.
    var profileID: UUID?

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    var color: NSColor { NSColor(hex: colorHex) ?? .systemPurple }
}

enum TabLocation {
    case favorites
    case pinned(Space)
    case tabs(Space)
}

@MainActor
protocol BrowserStateObserver: AnyObject {
    func browserStateDidChangeStructure()
    func browserStateDidSelect(_ tab: BrowserTab?, previous: BrowserTab?)
    func browserStateTabDidChange(_ tab: BrowserTab, change: TabChange)
    func browserStateDidSwitchSpace(forward: Bool)
}

// MARK: - Persistence records

private struct TabRecord: Codable {
    var id: UUID
    var url: URL?
    var title: String
    var homeURL: URL?
}

private struct SpaceRecord: Codable {
    var id: UUID
    var name: String
    var color: String
    var pinned: [TabRecord]
    var tabs: [TabRecord]
    var lastSelected: UUID?
    var searchEngine: String?
    var profile: UUID?
}

struct ArchivedTab: Codable {
    var url: URL
    var title: String
    var spaceID: UUID
    var date: Date
}

private struct StateRecord: Codable {
    var favorites: [TabRecord]
    var spaces: [SpaceRecord]
    var currentSpace: Int
    var selected: UUID?
    var archived: [ArchivedTab]?
}

// MARK: - State

@MainActor
final class BrowserState {
    static let shared = BrowserState()

    private(set) var favorites: [BrowserTab] = []
    private(set) var spaces: [Space] = []
    private(set) var currentSpaceIndex = 0
    private(set) var selectedTab: BrowserTab?
    weak var observer: BrowserStateObserver?

    private var recentlyClosed: [(url: URL, title: String, spaceID: UUID)] = []
    /// Tabs closed automatically after sitting unused (Settings → Tabs → Archive).
    private(set) var archived: [ArchivedTab] = []
    private let saver = Debouncer(delay: 1.5)
    private let fileURL = AppPaths.support.appendingPathComponent("session.json")

    var currentSpace: Space { spaces[currentSpaceIndex] }

    var allTabs: [BrowserTab] { favorites + spaces.flatMap { $0.pinned + $0.tabs } }

    /// Tabs in visual order for the current space (used by ⌘1–9 and ⌃Tab).
    var visibleTabs: [BrowserTab] { favorites + currentSpace.pinned + currentSpace.tabs }

    // MARK: Load / save

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let record = try? JSONDecoder().decode(StateRecord.self, from: data),
           !record.spaces.isEmpty {
            favorites = record.favorites.map { makeTab($0, favorite: true, pinned: false) }
            spaces = record.spaces.map { sr in
                let s = Space(id: sr.id, name: sr.name, colorHex: sr.color)
                s.pinned = sr.pinned.map { makeTab($0, favorite: false, pinned: true) }
                s.tabs = sr.tabs.map { makeTab($0, favorite: false, pinned: false) }
                s.lastSelectedID = sr.lastSelected
                s.searchEngineID = sr.searchEngine
                s.profileID = sr.profile
                return s
            }
            currentSpaceIndex = min(max(0, record.currentSpace), spaces.count - 1)
            archived = record.archived ?? []
            if let sel = record.selected, let tab = allTabs.first(where: { $0.id == sel }) {
                select(tab)
            } else {
                select(currentSpace.tabs.first ?? currentSpace.pinned.first)
            }
        } else {
            spaces = [Space(name: "Personal", colorHex: Palette.spaceColors[0].hex)]
        }
    }

    private func makeTab(_ r: TabRecord, favorite: Bool, pinned: Bool) -> BrowserTab {
        let t = BrowserTab(id: r.id, url: r.url ?? r.homeURL, title: r.title)
        t.homeURL = r.homeURL
        t.isFavorite = favorite
        t.isPinned = pinned
        t.state = self
        return t
    }

    func scheduleSave() {
        saver.call { [weak self] in self?.saveNow() }
    }

    func saveNow() {
        func rec(_ t: BrowserTab) -> TabRecord {
            TabRecord(id: t.id, url: t.url, title: t.title, homeURL: t.homeURL)
        }
        let record = StateRecord(
            favorites: favorites.map(rec),
            spaces: spaces.map {
                SpaceRecord(id: $0.id, name: $0.name, color: $0.colorHex,
                            pinned: $0.pinned.map(rec), tabs: $0.tabs.map(rec), lastSelected: $0.lastSelectedID,
                            searchEngine: $0.searchEngineID, profile: $0.profileID)
            },
            currentSpace: currentSpaceIndex,
            selected: selectedTab?.id,
            archived: archived)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Locating tabs

    func location(of tab: BrowserTab) -> (TabLocation, Int)? {
        if let i = favorites.firstIndex(where: { $0 === tab }) { return (.favorites, i) }
        for s in spaces {
            if let i = s.pinned.firstIndex(where: { $0 === tab }) { return (.pinned(s), i) }
            if let i = s.tabs.firstIndex(where: { $0 === tab }) { return (.tabs(s), i) }
        }
        return nil
    }

    func space(of tab: BrowserTab) -> Space? {
        switch location(of: tab)?.0 {
        case .pinned(let s), .tabs(let s): return s
        default: return nil
        }
    }

    @discardableResult
    private func detach(_ tab: BrowserTab) -> (TabLocation, Int)? {
        guard let loc = location(of: tab) else { return nil }
        switch loc.0 {
        case .favorites: favorites.remove(at: loc.1)
        case .pinned(let s): s.pinned.remove(at: loc.1)
        case .tabs(let s): s.tabs.remove(at: loc.1)
        }
        return loc
    }

    private func attach(_ tab: BrowserTab, to destination: TabLocation, at index: Int) {
        tab.state = self
        switch destination {
        case .favorites:
            tab.isFavorite = true; tab.isPinned = false
            if tab.homeURL == nil { tab.homeURL = tab.url }
            favorites.insert(tab, at: min(max(0, index), favorites.count))
        case .pinned(let s):
            tab.isFavorite = false; tab.isPinned = true
            if tab.homeURL == nil { tab.homeURL = tab.url }
            s.pinned.insert(tab, at: min(max(0, index), s.pinned.count))
        case .tabs(let s):
            tab.isFavorite = false; tab.isPinned = false
            tab.homeURL = nil
            s.tabs.insert(tab, at: min(max(0, index), s.tabs.count))
        }
    }

    // MARK: Opening

    @discardableResult
    func openTab(url: URL?, in space: Space? = nil, after parent: BrowserTab? = nil,
                 select shouldSelect: Bool = true, loadNow: Bool = false) -> BrowserTab {
        let tab = BrowserTab(url: url)
        tab.state = self
        let target = space ?? (parent.flatMap { self.space(of: $0) }) ?? currentSpace
        if let parent, let i = target.tabs.firstIndex(where: { $0 === parent }) {
            target.tabs.insert(tab, at: i + 1)
        } else {
            target.tabs.insert(tab, at: newTabIndex(in: target))
        }
        observer?.browserStateDidChangeStructure()
        if shouldSelect { select(tab) } else if loadNow { tab.materialize() }
        scheduleSave()
        return tab
    }

    /// Where a new tab goes in a space's list (Settings → Tabs → New tabs open).
    private func newTabIndex(in space: Space) -> Int {
        switch Settings.newTabPosition {
        case .top: return 0
        case .bottom: return space.tabs.count
        case .nextToCurrent:
            if let sel = selectedTab, let i = space.tabs.firstIndex(where: { $0 === sel }) { return i + 1 }
            return 0
        }
    }

    func insert(popup tab: BrowserTab, after parent: BrowserTab, select shouldSelect: Bool) {
        tab.state = self
        let target = space(of: parent) ?? currentSpace
        if let i = target.tabs.firstIndex(where: { $0 === parent }) {
            target.tabs.insert(tab, at: i + 1)
        } else {
            target.tabs.insert(tab, at: newTabIndex(in: target))
        }
        observer?.browserStateDidChangeStructure()
        if shouldSelect { select(tab) }
        scheduleSave()
    }

    // MARK: Selection

    func select(_ tab: BrowserTab?) {
        let previous = selectedTab
        if let tab, let s = space(of: tab), s !== currentSpace,
           let idx = spaces.firstIndex(where: { $0 === s }) {
            // Selecting a tab from another space switches to that space first.
            let forward = idx > currentSpaceIndex
            currentSpaceIndex = idx
            observer?.browserStateDidSwitchSpace(forward: forward)
        }
        selectedTab = tab
        if let tab {
            tab.lastActive = Date()
            tab.materialize()
            currentSpace.lastSelectedID = tab.id
        }
        previous?.lastActive = Date()
        observer?.browserStateDidSelect(tab, previous: previous)
        ExtensionManager.shared.tabDidActivate(tab, previous: previous)
        scheduleSave()
    }

    func selectNext(offset: Int) {
        let list = visibleTabs
        guard !list.isEmpty else { return }
        let i = selectedTab.flatMap { t in list.firstIndex(where: { $0 === t }) } ?? -1
        let next = ((i + offset) % list.count + list.count) % list.count
        select(list[next])
    }

    func select(index: Int) {
        let list = visibleTabs
        guard !list.isEmpty else { return }
        select(index >= 8 ? list.last : list[min(index, list.count - 1)])
    }

    // MARK: Closing

    /// ⌘W behaviour: regular tabs are closed; pinned tabs and favorites follow Settings → Tabs.
    func close(_ tab: BrowserTab) {
        if tab.isPinned || tab.isFavorite {
            if tab.isPinned && Settings.pinnedClose == .unpin { remove(tab); return }
            if selectedTab === tab { select(neighbor(of: tab)) }
            if Settings.pinnedClose == .unloadOnly { tab.unload() } else { tab.resetToHome() }
            observer?.browserStateTabDidChange(tab, change: [.url, .title, .loaded])
            scheduleSave()
        } else {
            remove(tab)
        }
    }

    /// Removes a tab entirely, whatever kind it is.
    func remove(_ tab: BrowserTab) {
        let wasSelected = selectedTab === tab
        let next = wasSelected ? neighbor(of: tab) : nil
        if let url = tab.url {
            let s = space(of: tab) ?? currentSpace
            recentlyClosed.append((url, tab.title, s.id))
            if recentlyClosed.count > 30 { recentlyClosed.removeFirst() }
        }
        detach(tab)
        tab.unload()
        observer?.browserStateDidChangeStructure()
        if wasSelected { select(next) }
        scheduleSave()
    }

    private func neighbor(of tab: BrowserTab) -> BrowserTab? {
        guard let found = location(of: tab) else { return nil }
        let (loc, i) = found
        let list: [BrowserTab]
        switch loc {
        case .favorites: list = favorites
        case .pinned(let s): list = s.pinned
        case .tabs(let s): list = s.tabs
        }
        let others = list.enumerated().filter { $0.element !== tab && ($0.element.isLoaded || !$0.element.isPinned) }
        if let after = others.first(where: { $0.offset > i }) { return after.element }
        if let before = others.last(where: { $0.offset < i }) { return before.element }
        if case .tabs = loc { return nil }
        return currentSpace.tabs.first
    }

    func reopenClosedTab() {
        guard let last = recentlyClosed.popLast() else { return }
        let space = spaces.first(where: { $0.id == last.spaceID }) ?? currentSpace
        openTab(url: last.url, in: space)
    }

    // MARK: Organising

    func move(_ tab: BrowserTab, to destination: TabLocation, index: Int) {
        guard let from = location(of: tab) else { return }
        var idx = index
        // Moving down within the same list: account for the removed slot.
        switch (from.0, destination) {
        case (.favorites, .favorites) where from.1 < index: idx -= 1
        case (.pinned(let a), .pinned(let b)) where a === b && from.1 < index: idx -= 1
        case (.tabs(let a), .tabs(let b)) where a === b && from.1 < index: idx -= 1
        default: break
        }
        let wasSelected = selectedTab === tab
        let oldProfile = profileID(for: tab)
        detach(tab)
        attach(tab, to: destination, at: idx)
        // A tab's web view is tied to its profile's data store; reload it in the new one.
        if tab.isLoaded && profileID(for: tab) != oldProfile {
            tab.unload()
            if wasSelected { tab.materialize() }
        }
        observer?.browserStateDidChangeStructure()
        if wasSelected, let s = space(of: tab), s !== currentSpace {
            select(currentSpace.tabs.first)
        } else if wasSelected {
            observer?.browserStateDidSelect(tab, previous: tab)
        }
        scheduleSave()
    }

    func togglePin(_ tab: BrowserTab) {
        let s = space(of: tab) ?? currentSpace
        if tab.isPinned || tab.isFavorite {
            move(tab, to: .tabs(s), index: 0)
        } else {
            move(tab, to: .pinned(s), index: s.pinned.count)
        }
    }

    func toggleFavorite(_ tab: BrowserTab) {
        if tab.isFavorite {
            move(tab, to: .tabs(currentSpace), index: 0)
        } else {
            move(tab, to: .favorites, index: favorites.count)
        }
    }

    func duplicate(_ tab: BrowserTab) {
        guard let url = tab.url else { return }
        openTab(url: url, after: tab.isPinned || tab.isFavorite ? nil : tab)
    }

    // MARK: Spaces

    func switchToSpace(_ index: Int) {
        guard spaces.indices.contains(index), index != currentSpaceIndex else { return }
        let forward = index > currentSpaceIndex
        currentSpaceIndex = index
        observer?.browserStateDidSwitchSpace(forward: forward)
        let s = currentSpace
        let target = (s.pinned + s.tabs + favorites).first(where: { $0.id == s.lastSelectedID })
            ?? s.tabs.first ?? s.pinned.first
        select(target)
        scheduleSave()
    }

    func switchSpace(by delta: Int) {
        let i = currentSpaceIndex + delta
        guard spaces.indices.contains(i) else { return }
        switchToSpace(i)
    }

    /// The data store profile a tab belongs to. Favorites always use the shared one.
    func profileID(for tab: BrowserTab) -> UUID? {
        tab.isFavorite ? nil : space(of: tab)?.profileID
    }

    func addSpace(name: String, colorHex: String, searchEngineID: String? = nil, separateProfile: Bool = false) {
        let s = Space(name: name, colorHex: colorHex)
        s.searchEngineID = searchEngineID
        s.profileID = separateProfile ? UUID() : nil
        spaces.append(s)
        switchToSpace(spaces.count - 1)
        observer?.browserStateDidChangeStructure()
    }

    func updateSpace(_ space: Space, name: String, colorHex: String, searchEngineID: String?, separateProfile: Bool) {
        space.name = name
        space.colorHex = colorHex
        space.searchEngineID = searchEngineID
        if separateProfile != (space.profileID != nil) {
            // Switching profile: every tab in the space has to reload in the other data store.
            let old = space.profileID
            space.profileID = separateProfile ? UUID() : nil
            for t in space.pinned + space.tabs where t.isLoaded {
                t.unload()
                if t === selectedTab { t.materialize() }
            }
            if let old { Self.removeProfileData(old) }
        }
        if let i = spaces.firstIndex(where: { $0 === space }), i == currentSpaceIndex {
            observer?.browserStateDidSwitchSpace(forward: true)
        }
        observer?.browserStateDidChangeStructure()
        if let sel = selectedTab { observer?.browserStateDidSelect(sel, previous: sel) }
        scheduleSave()
    }

    func moveSpace(from: Int, to: Int) {
        guard spaces.indices.contains(from), spaces.indices.contains(to), from != to else { return }
        let current = currentSpace
        let s = spaces.remove(at: from)
        spaces.insert(s, at: to)
        currentSpaceIndex = spaces.firstIndex(where: { $0 === current }) ?? 0
        observer?.browserStateDidChangeStructure()
        scheduleSave()
    }

    /// Deletes a profile's cookies and site data once no web view is using it.
    static func removeProfileData(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            try? await WKWebsiteDataStore.remove(forIdentifier: id)
        }
    }

    func deleteSpace(_ space: Space) {
        guard spaces.count > 1, let idx = spaces.firstIndex(where: { $0 === space }) else { return }
        for t in space.pinned + space.tabs { t.unload() }
        spaces.remove(at: idx)
        if let profile = space.profileID { Self.removeProfileData(profile) }
        if currentSpaceIndex >= spaces.count || idx <= currentSpaceIndex {
            currentSpaceIndex = max(0, min(currentSpaceIndex - (idx <= currentSpaceIndex ? 1 : 0), spaces.count - 1))
        }
        observer?.browserStateDidSwitchSpace(forward: false)
        observer?.browserStateDidChangeStructure()
        select(currentSpace.tabs.first ?? currentSpace.pinned.first)
    }

    // MARK: Fire

    /// Closes every regular tab, resets pinned tabs and favorites, and forgets history.
    func burnTabs() {
        for s in spaces {
            for t in s.tabs { t.unload() }
            s.tabs.removeAll()
            for t in s.pinned { t.resetToHome() }
            s.lastSelectedID = nil
        }
        for t in favorites { t.resetToHome() }
        recentlyClosed.removeAll()
        archived.removeAll()
        HistoryStore.shared.clear()
        observer?.browserStateDidChangeStructure()
        select(nil)
        saveNow()
    }

    // MARK: Memory

    /// Unloads background tabs that haven't been looked at for a while.
    func hibernate(olderThan seconds: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-seconds)
        for tab in allTabs where tab.isLoaded && tab !== selectedTab && tab.lastActive < cutoff {
            Task {
                if await tab.isBusy() { return }
                if tab !== self.selectedTab { tab.unload() }
            }
        }
    }

    /// Closes regular tabs nobody has looked at for a while, keeping them in the archive.
    /// Tabs playing media or using the camera/microphone are left alone.
    func archive(olderThan seconds: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-seconds)
        let candidates = spaces.flatMap { s in s.tabs.map { (s, $0) } }
            .filter { $0.1 !== selectedTab && $0.1.lastActive < cutoff }
        guard !candidates.isEmpty else { return }
        Task {
            var changed = false
            for (space, tab) in candidates {
                if await tab.isBusy() { continue }
                guard tab !== self.selectedTab, let i = space.tabs.firstIndex(where: { $0 === tab }) else { continue }
                if let url = tab.url {
                    self.archived.insert(ArchivedTab(url: url, title: tab.displayTitle, spaceID: space.id, date: Date()), at: 0)
                }
                space.tabs.remove(at: i)
                tab.unload()
                changed = true
            }
            guard changed else { return }
            if self.archived.count > 300 { self.archived.removeLast(self.archived.count - 300) }
            self.observer?.browserStateDidChangeStructure()
            self.scheduleSave()
        }
    }

    func restoreArchived(at index: Int) {
        guard archived.indices.contains(index) else { return }
        let a = archived.remove(at: index)
        let space = spaces.first(where: { $0.id == a.spaceID }) ?? currentSpace
        openTab(url: a.url, in: space)
    }

    func clearArchive() {
        archived.removeAll()
        scheduleSave()
    }

    // MARK: Change fan-out

    func tabDidChange(_ tab: BrowserTab, _ change: TabChange) {
        observer?.browserStateTabDidChange(tab, change: change)
        var props: WKWebExtension.TabChangedProperties = []
        if change.contains(.title) { props.insert(.title) }
        if change.contains(.url) { props.insert(.URL) }
        if change.contains(.loading) { props.insert(.loading) }
        if !props.isEmpty { ExtensionManager.shared.tabDidChange(tab, properties: props) }
        if change.contains(.url) || change.contains(.title) { scheduleSave() }
    }
}
