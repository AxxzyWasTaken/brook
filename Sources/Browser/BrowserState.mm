#import "Brook.h"

@implementation Space

- (instancetype)initWithID:(NSUUID *)identifier name:(NSString *)name colorHex:(NSString *)colorHex {
    if ((self = [super init])) {
        _identifier = identifier;
        _name = [name copy];
        _colorHex = [colorHex copy];
        _pinned = [NSMutableArray array];
        _tabs = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name colorHex:(NSString *)colorHex {
    return [self initWithID:[NSUUID UUID] name:name colorHex:colorHex];
}

- (NSColor *)color {
    return [NSColor brook_colorWithHex:_colorHex] ?: NSColor.systemPurpleColor;
}

- (ThemeMode)effectiveTheme { return _themeMode ? (ThemeMode)_themeMode.integerValue : Settings.theme; }
- (TabLayout)effectiveTabLayout { return _tabLayout ? (TabLayout)_tabLayout.integerValue : Settings.tabLayout; }
- (NSInteger)effectiveArchiveHours { return _archiveHours ? _archiveHours.integerValue : Settings.archiveHours; }
- (PinnedCloseBehavior)effectivePinnedClose {
    return _pinnedClose ? (PinnedCloseBehavior)_pinnedClose.integerValue : Settings.pinnedClose;
}

@end

@implementation ArchivedTab
@end

// MARK: - Persistence records

static NSString *const kDateKey = @"date";

static NSURL *URLFromJSON(id v) {
    return [v isKindOfClass:NSString.class] ? [NSURL URLWithString:v] : nil;
}

static NSUUID *UUIDFromJSON(id v) {
    return [v isKindOfClass:NSString.class] ? [[NSUUID alloc] initWithUUIDString:v] : nil;
}

static NSString *StringFromJSON(id v) {
    return [v isKindOfClass:NSString.class] ? v : nil;
}

/// Every site a saved session's favorites and tabs point at (not the archive, which only the
/// Settings list shows).
static NSSet<NSString *> *HostsInRecord(NSDictionary *record) {
    NSMutableSet<NSString *> *hosts = [NSMutableSet set];
    auto add = [&](id tabs) {
        if (![tabs isKindOfClass:NSArray.class]) return;
        for (NSDictionary *r in tabs) {
            if (![r isKindOfClass:NSDictionary.class]) continue;
            if (NSString *h = BrookHost(URLFromJSON(r[@"url"]) ?: URLFromJSON(r[@"homeURL"]))) [hosts addObject:h];
        }
    };
    add(record[@"favorites"]);
    for (NSDictionary *s in record[@"spaces"]) {
        if (![s isKindOfClass:NSDictionary.class]) continue;
        add(s[@"pinned"]);
        add(s[@"tabs"]);
    }
    return hosts;
}

static NSDictionary *TabRecord(BrowserTab *t) {
    NSMutableDictionary *d = [@{@"id": t.identifier.UUIDString, @"title": t.title ?: @""} mutableCopy];
    if (t.url) d[@"url"] = t.url.absoluteString;
    if (t.homeURL) d[@"homeURL"] = t.homeURL.absoluteString;
    return d;
}

static NSDictionary *ArchivedRecord(ArchivedTab *a) {
    return @{@"url": a.url.absoluteString, @"title": a.title ?: @"", @"spaceID": a.spaceID.UUIDString,
             kDateKey: @(a.date.timeIntervalSinceReferenceDate)};
}

static ArchivedTab *ArchivedFromRecord(NSDictionary *d) {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    NSURL *url = URLFromJSON(d[@"url"]);
    NSUUID *space = UUIDFromJSON(d[@"spaceID"]);
    if (!url || !space) return nil;
    ArchivedTab *a = [ArchivedTab new];
    a.url = url;
    a.title = StringFromJSON(d[@"title"]) ?: @"";
    a.spaceID = space;
    a.date = [NSDate dateWithTimeIntervalSinceReferenceDate:[d[kDateKey] doubleValue]];
    return a;
}

struct ClosedTab {
    NSURL *url;
    NSString *title;
    NSUUID *spaceID;
};

// MARK: - State

NSNotificationName const BrowserStateArchiveDidChangeNotification = @"BrookArchiveDidChange";

@implementation BrowserState {
    NSMutableArray<BrowserTab *> *_favorites;
    NSMutableArray<Space *> *_spaces;
    NSMutableArray<ArchivedTab *> *_archived;
    std::vector<ClosedTab> _recentlyClosed;
    Debouncer *_saver;
    NSURL *_fileURL;
}

+ (BrowserState *)shared {
    static BrowserState *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [BrowserState new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _favorites = [NSMutableArray array];
        _spaces = [NSMutableArray array];
        _archived = [NSMutableArray array];
        _saver = [[Debouncer alloc] initWithDelay:1.5];
        _fileURL = [AppPaths.support URLByAppendingPathComponent:@"session.json"];
    }
    return self;
}

- (NSArray<BrowserTab *> *)favorites { return _favorites; }
- (NSArray<Space *> *)spaces { return _spaces; }
- (NSArray<ArchivedTab *> *)archived { return _archived; }

- (Space *)currentSpace { return _spaces[(NSUInteger)_currentSpaceIndex]; }

- (NSArray<BrowserTab *> *)allTabs {
    NSMutableArray *all = [_favorites mutableCopy];
    for (Space *s in _spaces) {
        [all addObjectsFromArray:s.pinned];
        [all addObjectsFromArray:s.tabs];
    }
    return all;
}

- (NSArray<BrowserTab *> *)visibleTabs {
    Space *s = self.currentSpace;
    // Settings → Layout → Favorites off hides them in every layout, so ⌘1–9 and ⌃Tab skip them.
    NSArray<BrowserTab *> *favorites = Settings.showFavorites ? _favorites : @[];
    return [[favorites arrayByAddingObjectsFromArray:s.pinned] arrayByAddingObjectsFromArray:s.tabs];
}

- (BrowserTab *)tabWithID:(NSUUID *)identifier {
    for (BrowserTab *t in self.allTabs) if ([t.identifier isEqual:identifier]) return t;
    return nil;
}

// MARK: Load / save

- (void)load {
    NSData *data = [NSData dataWithContentsOfURL:_fileURL];
    NSDictionary *record = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray *spaceRecords = [record isKindOfClass:NSDictionary.class] ? record[@"spaces"] : nil;
    if ([spaceRecords isKindOfClass:NSArray.class] && spaceRecords.count > 0) {
        [FaviconStore.shared warmHosts:HostsInRecord(record)];   // restored tabs draw with their icons
        for (NSDictionary *r in record[@"favorites"]) {
            if (BrowserTab *t = [self makeTab:r favorite:YES pinned:NO]) [_favorites addObject:t];
        }
        for (NSDictionary *sr in spaceRecords) {
            if (![sr isKindOfClass:NSDictionary.class]) continue;
            Space *s = [[Space alloc] initWithID:UUIDFromJSON(sr[@"id"]) ?: [NSUUID UUID]
                                            name:StringFromJSON(sr[@"name"]) ?: @"Space"
                                        colorHex:StringFromJSON(sr[@"color"]) ?: Palette.spaceColors[0][1]];
            for (NSDictionary *r in sr[@"pinned"]) {
                if (BrowserTab *t = [self makeTab:r favorite:NO pinned:YES]) [s.pinned addObject:t];
            }
            for (NSDictionary *r in sr[@"tabs"]) {
                if (BrowserTab *t = [self makeTab:r favorite:NO pinned:NO]) [s.tabs addObject:t];
            }
            s.lastSelectedID = UUIDFromJSON(sr[@"lastSelected"]);
            s.searchEngineID = StringFromJSON(sr[@"searchEngine"]);
            s.profileID = UUIDFromJSON(sr[@"profile"]);
            NSInteger theme = ThemeModeFromRaw(StringFromJSON(sr[@"theme"]));
            NSInteger layout = TabLayoutFromRaw(StringFromJSON(sr[@"tabLayout"]));
            NSInteger pinnedClose = PinnedCloseBehaviorFromRaw(StringFromJSON(sr[@"pinnedClose"]));
            s.themeMode = theme >= 0 ? @(theme) : nil;
            s.tabLayout = layout >= 0 ? @(layout) : nil;
            s.pinnedClose = pinnedClose >= 0 ? @(pinnedClose) : nil;
            id hours = sr[@"archiveHours"];
            s.archiveHours = [hours isKindOfClass:NSNumber.class] ? @(std::max<NSInteger>(0, [hours integerValue])) : nil;
            [_spaces addObject:s];
        }
        _currentSpaceIndex = std::min(std::max<NSInteger>(0, [record[@"currentSpace"] integerValue]),
                                      (NSInteger)_spaces.count - 1);
        for (NSDictionary *a in record[@"archived"]) {
            if (ArchivedTab *t = ArchivedFromRecord(a)) [_archived addObject:t];
        }
        [self applyLaunchBehavior];
        NSUUID *sel = UUIDFromJSON(record[@"selected"]);
        BrowserTab *tab = sel ? [self tabWithID:sel] : nil;
        [self selectTab:tab ?: self.currentSpace.tabs.firstObject ?: self.currentSpace.pinned.firstObject];
    } else {
        [_spaces addObject:[[Space alloc] initWithName:@"Personal" colorHex:Palette.spaceColors[0][1]]];
        [self applyLaunchBehavior];
    }
}

/// Settings → General → On launch. Restore keeps everything; the others drop the unpinned tabs
/// (pinned tabs and favorites stay, like Arc) and the start page opens one tab.
- (void)applyLaunchBehavior {
    LaunchBehavior launch = Settings.launchBehavior;
    if (launch == LaunchBehaviorRestore) return;
    for (Space *s in _spaces) {
        [s.tabs removeAllObjects];
        s.lastSelectedID = nil;
    }
    if (launch != LaunchBehaviorStartPage) return;
    NSURL *start = [URLParser urlFromInput:Settings.startPageURL];
    if (!start) return;
    BrowserTab *t = [[BrowserTab alloc] initWithURL:start];
    t.state = self;
    [self.currentSpace.tabs addObject:t];
    self.currentSpace.lastSelectedID = t.identifier;
}

- (BrowserTab *)makeTab:(NSDictionary *)r favorite:(BOOL)favorite pinned:(BOOL)pinned {
    if (![r isKindOfClass:NSDictionary.class]) return nil;
    NSURL *url = URLFromJSON(r[@"url"]), *home = URLFromJSON(r[@"homeURL"]);
    BrowserTab *t = [[BrowserTab alloc] initWithID:UUIDFromJSON(r[@"id"]) ?: [NSUUID UUID]
                                               url:url ?: home
                                             title:StringFromJSON(r[@"title"]) ?: @""];
    t.homeURL = home;
    t.isFavorite = favorite;
    t.isPinned = pinned;
    t.state = self;
    return t;
}

- (void)scheduleSave {
    __weak BrowserState *weakSelf = self;
    [_saver call:^{ [weakSelf saveNow]; }];
}

- (void)saveNow {
    NSMutableArray *favs = [NSMutableArray array];
    for (BrowserTab *t in _favorites) [favs addObject:TabRecord(t)];
    NSMutableArray *spaces = [NSMutableArray array];
    for (Space *s in _spaces) {
        NSMutableArray *pinned = [NSMutableArray array], *tabs = [NSMutableArray array];
        for (BrowserTab *t in s.pinned) [pinned addObject:TabRecord(t)];
        for (BrowserTab *t in s.tabs) [tabs addObject:TabRecord(t)];
        NSMutableDictionary *d = [@{@"id": s.identifier.UUIDString, @"name": s.name, @"color": s.colorHex,
                                    @"pinned": pinned, @"tabs": tabs} mutableCopy];
        if (s.lastSelectedID) d[@"lastSelected"] = s.lastSelectedID.UUIDString;
        if (s.searchEngineID) d[@"searchEngine"] = s.searchEngineID;
        if (s.profileID) d[@"profile"] = s.profileID.UUIDString;
        if (s.themeMode) d[@"theme"] = ThemeModeRaw((ThemeMode)s.themeMode.integerValue);
        if (s.tabLayout) d[@"tabLayout"] = TabLayoutRaw((TabLayout)s.tabLayout.integerValue);
        if (s.pinnedClose) d[@"pinnedClose"] = PinnedCloseBehaviorRaw((PinnedCloseBehavior)s.pinnedClose.integerValue);
        if (s.archiveHours) d[@"archiveHours"] = s.archiveHours;
        [spaces addObject:d];
    }
    NSMutableArray *archived = [NSMutableArray array];
    for (ArchivedTab *a in _archived) [archived addObject:ArchivedRecord(a)];
    NSMutableDictionary *record = [@{@"favorites": favs, @"spaces": spaces, @"currentSpace": @(_currentSpaceIndex),
                                     @"archived": archived} mutableCopy];
    if (_selectedTab) record[@"selected"] = _selectedTab.identifier.UUIDString;
    // Built here from fresh objects, so the writer thread has the only reference to it.
    BrookWriteJSONInBackground(record, 0, _fileURL);
}

// MARK: Locating tabs

- (std::optional<TabPosition>)locationOf:(BrowserTab *)tab {
    NSUInteger i = [_favorites indexOfObjectIdenticalTo:tab];
    if (i != NSNotFound) return TabPosition{TabLocation::favorites(), (NSInteger)i};
    for (Space *s in _spaces) {
        if ((i = [s.pinned indexOfObjectIdenticalTo:tab]) != NSNotFound) return TabPosition{TabLocation::pinnedIn(s), (NSInteger)i};
        if ((i = [s.tabs indexOfObjectIdenticalTo:tab]) != NSNotFound) return TabPosition{TabLocation::tabsIn(s), (NSInteger)i};
    }
    return std::nullopt;
}

- (Space *)spaceOf:(BrowserTab *)tab {
    auto pos = [self locationOf:tab];
    return pos ? pos->location.space : nil;
}

- (NSMutableArray<BrowserTab *> *)listFor:(const TabLocation &)loc {
    switch (loc.kind) {
        case TabLocation::Favorites: return _favorites;
        case TabLocation::Pinned: return loc.space.pinned;
        case TabLocation::Tabs: return loc.space.tabs;
    }
}

- (std::optional<TabPosition>)detach:(BrowserTab *)tab {
    auto pos = [self locationOf:tab];
    if (pos) [[self listFor:pos->location] removeObjectAtIndex:(NSUInteger)pos->index];
    return pos;
}

static NSUInteger ClampIndex(NSInteger index, NSUInteger count) {
    return (NSUInteger)std::min<NSInteger>(std::max<NSInteger>(0, index), (NSInteger)count);
}

- (void)attach:(BrowserTab *)tab to:(const TabLocation &)destination at:(NSInteger)index {
    tab.state = self;
    switch (destination.kind) {
        case TabLocation::Favorites:
            tab.isFavorite = YES; tab.isPinned = NO;
            if (!tab.homeURL) tab.homeURL = tab.url;
            break;
        case TabLocation::Pinned:
            tab.isFavorite = NO; tab.isPinned = YES;
            if (!tab.homeURL) tab.homeURL = tab.url;
            break;
        case TabLocation::Tabs:
            tab.isFavorite = NO; tab.isPinned = NO;
            tab.homeURL = nil;
            break;
    }
    NSMutableArray *list = [self listFor:destination];
    [list insertObject:tab atIndex:ClampIndex(index, list.count)];
}

// MARK: Opening

- (BrowserTab *)openTabWithURL:(NSURL *)url {
    return [self openTabWithURL:url inSpace:nil after:nil select:YES loadNow:NO];
}

- (BrowserTab *)openTabWithURL:(NSURL *)url inSpace:(Space *)space select:(BOOL)select {
    return [self openTabWithURL:url inSpace:space after:nil select:select loadNow:NO];
}

- (BrowserTab *)openTabWithURL:(NSURL *)url inSpace:(Space *)space after:(BrowserTab *)parent
                        select:(BOOL)shouldSelect loadNow:(BOOL)loadNow {
    BrowserTab *tab = [[BrowserTab alloc] initWithURL:url];
    tab.state = self;
    Space *target = space ?: (parent ? [self spaceOf:parent] : nil) ?: self.currentSpace;
    NSUInteger i = parent ? [target.tabs indexOfObjectIdenticalTo:parent] : NSNotFound;
    if (i != NSNotFound) {
        [target.tabs insertObject:tab atIndex:i + 1];
    } else {
        [target.tabs insertObject:tab atIndex:[self newTabIndexIn:target]];
    }
    [_observer browserStateDidChangeStructure];
    if (shouldSelect) [self selectTab:tab]; else if (loadNow) [tab materialize];
    [self scheduleSave];
    return tab;
}

/// Where a new tab goes in a space's list (Settings → Tabs → New tabs open).
- (NSUInteger)newTabIndexIn:(Space *)space {
    switch (Settings.newTabPosition) {
        case NewTabPositionTop: return 0;
        case NewTabPositionBottom: return space.tabs.count;
        case NewTabPositionNextToCurrent: {
            NSUInteger i = _selectedTab ? [space.tabs indexOfObjectIdenticalTo:_selectedTab] : NSNotFound;
            return i != NSNotFound ? i + 1 : 0;
        }
    }
    return 0;
}

- (void)insertPopup:(BrowserTab *)tab after:(BrowserTab *)parent select:(BOOL)shouldSelect {
    tab.state = self;
    Space *target = [self spaceOf:parent] ?: self.currentSpace;
    NSUInteger i = [target.tabs indexOfObjectIdenticalTo:parent];
    if (i != NSNotFound) {
        [target.tabs insertObject:tab atIndex:i + 1];
    } else {
        [target.tabs insertObject:tab atIndex:[self newTabIndexIn:target]];
    }
    [_observer browserStateDidChangeStructure];
    if (shouldSelect) [self selectTab:tab];
    [self scheduleSave];
}

// MARK: Selection

- (void)selectTab:(BrowserTab *)tab {
    BrowserTab *previous = _selectedTab;
    Space *s = tab ? [self spaceOf:tab] : nil;
    if (s && s != self.currentSpace) {
        // Selecting a tab from another space switches to that space first.
        NSUInteger idx = [_spaces indexOfObjectIdenticalTo:s];
        if (idx != NSNotFound) {
            BOOL forward = (NSInteger)idx > _currentSpaceIndex;
            _currentSpaceIndex = (NSInteger)idx;
            [_observer browserStateDidSwitchSpace:forward];
        }
    }
    _selectedTab = tab;
    if (tab) {
        tab.lastActive = [NSDate date];
        [tab materialize];
        self.currentSpace.lastSelectedID = tab.identifier;
    }
    previous.lastActive = [NSDate date];
    [_observer browserStateDidSelect:tab previous:previous];
    [ExtensionManager.shared tabDidActivate:tab previous:previous];
    [self scheduleSave];
}

- (void)selectNext:(NSInteger)offset {
    NSArray *list = self.visibleTabs;
    if (list.count == 0) return;
    NSInteger n = (NSInteger)list.count;
    NSUInteger found = _selectedTab ? [list indexOfObjectIdenticalTo:_selectedTab] : NSNotFound;
    NSInteger i = found == NSNotFound ? -1 : (NSInteger)found;
    NSInteger next = ((i + offset) % n + n) % n;
    [self selectTab:list[(NSUInteger)next]];
}

- (void)selectIndex:(NSInteger)index {
    NSArray *list = self.visibleTabs;
    if (list.count == 0) return;
    [self selectTab:index >= 8 ? list.lastObject : list[(NSUInteger)std::min<NSInteger>(index, (NSInteger)list.count - 1)]];
}

// MARK: Closing

- (void)close:(BrowserTab *)tab {
    if (tab.isPinned || tab.isFavorite) {
        PinnedCloseBehavior behavior = tab.isPinned ? [self spaceOf:tab].effectivePinnedClose : Settings.pinnedClose;
        if (tab.isPinned && behavior == PinnedCloseBehaviorUnpin) { [self remove:tab]; return; }
        if (_selectedTab == tab) [self selectTab:[self neighborOf:tab]];
        if (behavior == PinnedCloseBehaviorUnloadOnly) [tab unload]; else [tab resetToHome];
        [_observer browserStateTabDidChange:tab change:TabChangeURL | TabChangeTitle | TabChangeLoaded];
        [self scheduleSave];
    } else {
        [self remove:tab];
    }
}

- (void)remove:(BrowserTab *)tab {
    BOOL wasSelected = _selectedTab == tab;
    BrowserTab *next = wasSelected ? [self neighborOf:tab] : nil;
    if (tab.url) {
        Space *s = [self spaceOf:tab] ?: self.currentSpace;
        _recentlyClosed.push_back({tab.url, tab.title, s.identifier});
        if (_recentlyClosed.size() > 30) _recentlyClosed.erase(_recentlyClosed.begin());
    }
    [self detach:tab];
    [tab unload];
    [_observer browserStateDidChangeStructure];
    if (wasSelected) [self selectTab:next];
    [self scheduleSave];
}

- (BrowserTab *)neighborOf:(BrowserTab *)tab {
    auto found = [self locationOf:tab];
    if (!found) return nil;
    NSArray<BrowserTab *> *list = [self listFor:found->location];
    NSInteger i = found->index;
    auto usable = [tab](BrowserTab *t) { return t != tab && (t.isLoaded || !t.isPinned); };
    // Settings → Tabs → After closing a tab: the one used most recently, from anywhere in the space.
    if (Settings.closeSelects == CloseSelectsLastUsed) {
        BrowserTab *best = nil;
        for (BrowserTab *t in self.visibleTabs) {
            if (!usable(t) || (t.isFavorite && !t.isLoaded)) continue;
            if (!best || [t.lastActive compare:best.lastActive] == NSOrderedDescending) best = t;
        }
        if (best.lastActive) return best;
    }
    BrowserTab *after = nil, *before = nil;
    for (NSInteger j = 0; j < (NSInteger)list.count; j++) {
        BrowserTab *t = list[(NSUInteger)j];
        if (!usable(t)) continue;
        if (j > i && !after) after = t;
        if (j < i) before = t;
    }
    BOOL above = Settings.closeSelects == CloseSelectsAbove;
    if (BrowserTab *first = above ? before : after) return first;
    if (BrowserTab *second = above ? after : before) return second;
    if (found->location.kind == TabLocation::Tabs) return nil;
    return self.currentSpace.tabs.firstObject;
}

- (BOOL)canReopenClosedTab { return !_recentlyClosed.empty(); }

- (void)reopenClosedTab {
    if (_recentlyClosed.empty()) return;
    ClosedTab last = _recentlyClosed.back();
    _recentlyClosed.pop_back();
    Space *space = self.currentSpace;
    for (Space *s in _spaces) if ([s.identifier isEqual:last.spaceID]) { space = s; break; }
    [self openTabWithURL:last.url inSpace:space select:YES];
}

// MARK: Organising

- (void)move:(BrowserTab *)tab to:(TabLocation)destination index:(NSInteger)index {
    auto from = [self locationOf:tab];
    if (!from) return;
    NSInteger idx = index;
    // Moving down within the same list: account for the removed slot.
    if (from->location == destination && from->index < index) idx -= 1;
    BOOL wasSelected = _selectedTab == tab;
    // The tab that takes over when the selected tab leaves this space, as when it is closed.
    BrowserTab *next = wasSelected ? [self neighborOf:tab] : nil;
    NSUUID *oldProfile = [self profileIDFor:tab];
    [self detach:tab];
    [self attach:tab to:destination at:idx];
    // A tab's web view is tied to its profile's data store; reload it in the new one.
    NSUUID *newProfile = [self profileIDFor:tab];
    if (tab.isLoaded && !(newProfile == oldProfile || [newProfile isEqual:oldProfile])) {
        [tab unload];
        if (wasSelected) [tab materialize];
    }
    [_observer browserStateDidChangeStructure];
    Space *s = [self spaceOf:tab];
    if (wasSelected && s && s != self.currentSpace) {
        [self selectTab:next ?: self.currentSpace.tabs.firstObject ?: self.currentSpace.pinned.firstObject];
    } else if (wasSelected) {
        [_observer browserStateDidSelect:tab previous:tab];
    }
    [self scheduleSave];
}

- (void)togglePin:(BrowserTab *)tab {
    Space *s = [self spaceOf:tab] ?: self.currentSpace;
    if (tab.isPinned) {
        [self move:tab to:TabLocation::tabsIn(s) index:0];
    } else {
        [self move:tab to:TabLocation::pinnedIn(s) index:(NSInteger)s.pinned.count];
    }
}

- (void)toggleFavorite:(BrowserTab *)tab {
    if (tab.isFavorite) {
        [self move:tab to:TabLocation::tabsIn(self.currentSpace) index:0];
    } else {
        [self move:tab to:TabLocation::favorites() index:(NSInteger)_favorites.count];
    }
}

- (void)duplicate:(BrowserTab *)tab {
    if (!tab.url) return;
    [self openTabWithURL:tab.url inSpace:nil after:(tab.isPinned || tab.isFavorite) ? nil : tab select:YES loadNow:NO];
}

// MARK: Spaces

- (void)switchToSpace:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_spaces.count || index == _currentSpaceIndex) return;
    BOOL forward = index > _currentSpaceIndex;
    _currentSpaceIndex = index;
    [_observer browserStateDidSwitchSpace:forward];
    Space *s = self.currentSpace;
    BrowserTab *target = nil;
    for (BrowserTab *t in [[s.pinned arrayByAddingObjectsFromArray:s.tabs] arrayByAddingObjectsFromArray:_favorites]) {
        if ([t.identifier isEqual:s.lastSelectedID]) { target = t; break; }
    }
    [self selectTab:target ?: s.tabs.firstObject ?: s.pinned.firstObject];
    [self scheduleSave];
}

- (void)switchSpaceBy:(NSInteger)delta {
    NSInteger i = _currentSpaceIndex + delta;
    if (i < 0 || i >= (NSInteger)_spaces.count) return;
    [self switchToSpace:i];
}

- (NSUUID *)profileIDFor:(BrowserTab *)tab {
    return tab.isFavorite ? nil : [self spaceOf:tab].profileID;
}

- (void)addSpaceNamed:(NSString *)name colorHex:(NSString *)colorHex searchEngineID:(NSString *)engineID
      separateProfile:(BOOL)separateProfile {
    Space *s = [[Space alloc] initWithName:name colorHex:colorHex];
    s.searchEngineID = engineID;
    s.profileID = separateProfile ? [NSUUID UUID] : nil;
    [_spaces addObject:s];
    [self switchToSpace:(NSInteger)_spaces.count - 1];
    [_observer browserStateDidChangeStructure];
}

- (void)updateSpace:(Space *)space name:(NSString *)name colorHex:(NSString *)colorHex
     searchEngineID:(NSString *)engineID separateProfile:(BOOL)separateProfile {
    space.name = name;
    space.colorHex = colorHex;
    space.searchEngineID = engineID;
    if (separateProfile != (space.profileID != nil)) {
        // Switching profile: every tab in the space has to reload in the other data store.
        NSUUID *old = space.profileID;
        space.profileID = separateProfile ? [NSUUID UUID] : nil;
        for (BrowserTab *t in [space.pinned arrayByAddingObjectsFromArray:space.tabs]) {
            if (!t.isLoaded) continue;
            [t unload];
            if (t == _selectedTab) [t materialize];
        }
        if (old) [BrowserState removeProfileData:old];
    }
    NSUInteger i = [_spaces indexOfObjectIdenticalTo:space];
    if (i != NSNotFound && (NSInteger)i == _currentSpaceIndex) [_observer browserStateDidEditCurrentSpace];
    [_observer browserStateDidChangeStructure];
    // Also with no tab: the empty page shows the space name.
    [_observer browserStateDidSelect:_selectedTab previous:_selectedTab];
    [self scheduleSave];
}

- (void)moveSpaceFrom:(NSInteger)from to:(NSInteger)to {
    NSInteger n = (NSInteger)_spaces.count;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
    Space *current = self.currentSpace;
    Space *s = _spaces[(NSUInteger)from];
    [_spaces removeObjectAtIndex:(NSUInteger)from];
    [_spaces insertObject:s atIndex:(NSUInteger)to];
    NSUInteger i = [_spaces indexOfObjectIdenticalTo:current];
    _currentSpaceIndex = i == NSNotFound ? 0 : (NSInteger)i;
    [_observer browserStateDidChangeStructure];
    [self scheduleSave];
}

+ (void)removeProfileData:(NSUUID *)identifier {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [WKWebsiteDataStore removeDataStoreForIdentifier:identifier completionHandler:^(NSError *error) {}];
    });
}

- (void)deleteSpace:(Space *)space {
    NSUInteger found = [_spaces indexOfObjectIdenticalTo:space];
    if (_spaces.count <= 1 || found == NSNotFound) return;
    NSInteger idx = (NSInteger)found;
    BOOL wasCurrent = idx == _currentSpaceIndex;
    for (BrowserTab *t in [space.pinned arrayByAddingObjectsFromArray:space.tabs]) [t unload];
    [_spaces removeObjectAtIndex:found];
    if (space.profileID) [BrowserState removeProfileData:space.profileID];
    NSInteger count = (NSInteger)_spaces.count;
    if (_currentSpaceIndex >= count || idx <= _currentSpaceIndex) {
        _currentSpaceIndex = std::max<NSInteger>(0, std::min<NSInteger>(_currentSpaceIndex - (idx <= _currentSpaceIndex ? 1 : 0),
                                                                         count - 1));
    }
    if (!wasCurrent) {
        // Another space went away: the current space and its selected tab stay as they are.
        [_observer browserStateDidChangeStructure];
        [self scheduleSave];
        return;
    }
    [_observer browserStateDidSwitchSpace:NO];
    [_observer browserStateDidChangeStructure];
    [self selectTab:self.currentSpace.tabs.firstObject ?: self.currentSpace.pinned.firstObject];
}

// MARK: Fire

- (void)burnTabs {
    for (Space *s in _spaces) {
        for (BrowserTab *t in s.tabs) [t unload];
        [s.tabs removeAllObjects];
        for (BrowserTab *t in s.pinned) [t resetToHome];
        s.lastSelectedID = nil;
    }
    for (BrowserTab *t in _favorites) [t resetToHome];
    _recentlyClosed.clear();
    [_archived removeAllObjects];
    [NSNotificationCenter.defaultCenter postNotificationName:BrowserStateArchiveDidChangeNotification object:self];
    [HistoryStore.shared clear];
    [_observer browserStateDidChangeStructure];
    [self selectTab:nil];
    [self saveNow];
}

// MARK: Memory

- (void)hibernateOlderThan:(NSTimeInterval)seconds {
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-seconds];
    for (BrowserTab *tab in self.allTabs) {
        if (!tab.isLoaded || tab == _selectedTab || [tab.lastActive compare:cutoff] != NSOrderedAscending) continue;
        __weak BrowserState *weakSelf = self;
        [tab isBusy:^(BOOL busy) {
            if (busy) return;
            if (tab != weakSelf.selectedTab) [tab unload];
        }];
    }
}

/// Tabs playing media or using the camera/microphone are left alone. Each space may set its
/// own limit (0 = never); `seconds` is the global one.
- (void)archiveOlderThan:(NSTimeInterval)seconds {
    struct Candidate { Space *space; BrowserTab *tab; };
    auto candidates = std::make_shared<std::vector<Candidate>>();
    for (Space *s in _spaces) {
        NSTimeInterval limit = s.archiveHours ? s.archiveHours.integerValue * 3600.0 : seconds;
        if (limit <= 0) continue;
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-limit];
        for (BrowserTab *t in s.tabs) {
            if (t != _selectedTab && [t.lastActive compare:cutoff] == NSOrderedAscending) candidates->push_back({s, t});
        }
    }
    if (candidates->empty()) return;
    // Ask every tab whether it's busy, then archive the idle ones in list order.
    auto busy = std::make_shared<std::vector<bool>>(candidates->size(), false);
    dispatch_group_t group = dispatch_group_create();
    for (size_t i = 0; i < candidates->size(); i++) {
        dispatch_group_enter(group);
        [(*candidates)[i].tab isBusy:^(BOOL b) {
            (*busy)[i] = b;
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        BOOL changed = NO;
        for (size_t i = 0; i < candidates->size(); i++) {
            if ((*busy)[i]) continue;
            Space *space = (*candidates)[i].space;
            BrowserTab *tab = (*candidates)[i].tab;
            NSUInteger idx = [space.tabs indexOfObjectIdenticalTo:tab];
            if (tab == self->_selectedTab || idx == NSNotFound) continue;
            if (tab.url) {
                ArchivedTab *a = [ArchivedTab new];
                a.url = tab.url;
                a.title = tab.displayTitle;
                a.spaceID = space.identifier;
                a.date = [NSDate date];
                [self->_archived insertObject:a atIndex:0];
            }
            [space.tabs removeObjectAtIndex:idx];
            [tab unload];
            changed = YES;
        }
        if (!changed) return;
        if (self->_archived.count > 300) {
            [self->_archived removeObjectsInRange:NSMakeRange(300, self->_archived.count - 300)];
        }
        [self->_observer browserStateDidChangeStructure];
        [NSNotificationCenter.defaultCenter postNotificationName:BrowserStateArchiveDidChangeNotification object:self];
        [self scheduleSave];
    });
}

- (void)restoreArchivedAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_archived.count) return;
    ArchivedTab *a = _archived[(NSUInteger)index];
    [_archived removeObjectAtIndex:(NSUInteger)index];
    [NSNotificationCenter.defaultCenter postNotificationName:BrowserStateArchiveDidChangeNotification object:self];
    Space *space = self.currentSpace;
    for (Space *s in _spaces) if ([s.identifier isEqual:a.spaceID]) { space = s; break; }
    [self openTabWithURL:a.url inSpace:space select:YES];
}

- (void)clearArchive {
    [_archived removeAllObjects];
    [NSNotificationCenter.defaultCenter postNotificationName:BrowserStateArchiveDidChangeNotification object:self];
    [self scheduleSave];
}

// MARK: Change fan-out

- (void)tabDidChange:(BrowserTab *)tab change:(TabChange)change {
    [_observer browserStateTabDidChange:tab change:change];
    WKWebExtensionTabChangedProperties props = 0;
    if (change & TabChangeTitle) props |= WKWebExtensionTabChangedPropertiesTitle;
    if (change & TabChangeURL) props |= WKWebExtensionTabChangedPropertiesURL;
    if (change & TabChangeLoading) props |= WKWebExtensionTabChangedPropertiesLoading;
    if (props) [ExtensionManager.shared tabDidChange:tab properties:props];
    if (change & (TabChangeURL | TabChangeTitle)) [self scheduleSave];
}

@end
