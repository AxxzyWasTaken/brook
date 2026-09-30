#import <AppKit/AppKit.h>
#import "BrowserTab.h"

/// Two tabs of one space shown side by side (Split View). Both are regular tabs of that space; the
/// pair comes apart by itself once either stops being one (closed, pinned, moved to another space).
/// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), Split.swift.
@interface TabSplit : NSObject
@property (strong) BrowserTab *left;
@property (strong) BrowserTab *right;
/// The left page's share of the card, kept between 0.2 and 0.8.
@property (nonatomic) double fraction;
- (BOOL)contains:(BrowserTab *)tab;
- (BrowserTab *)partnerOf:(BrowserTab *)tab;
@end

@interface Space : NSObject
- (instancetype)initWithID:(NSUUID *)identifier name:(NSString *)name colorHex:(NSString *)colorHex;
- (instancetype)initWithName:(NSString *)name colorHex:(NSString *)colorHex;
@property (readonly) NSUUID *identifier;
@property (copy) NSString *name;
@property (copy) NSString *colorHex;
@property (strong) NSMutableArray<BrowserTab *> *pinned;
@property (strong) NSMutableArray<BrowserTab *> *tabs;
@property (strong) NSMutableArray<TabSplit *> *splits;
@property (strong) NSUUID *lastSelectedID;
/// Overrides the default search engine for this space.
@property (copy) NSString *searchEngineID;
/// When set, the space keeps its own cookies, logins and site data in this store.
@property (strong) NSUUID *profileID;
/// Per-space overrides of global settings (nil = use the global one).
@property (strong) NSNumber *themeMode;        // ThemeMode
@property (strong) NSNumber *tabLayout;        // TabLayout
@property (strong) NSNumber *archiveHours;     // 0 = never
@property (strong) NSNumber *pinnedClose;      // PinnedCloseBehavior
@property (readonly) ThemeMode effectiveTheme;
@property (readonly) TabLayout effectiveTabLayout;
@property (readonly) NSInteger effectiveArchiveHours;
@property (readonly) PinnedCloseBehavior effectivePinnedClose;
@property (readonly) NSColor *color;
@end

/// Where a tab lives: the favorites grid, or a space's pinned or regular list.
struct TabLocation {
    enum Kind { Favorites, Pinned, Tabs };
    Kind kind;
    __strong Space *space;   // nil for favorites

    static TabLocation favorites() { return {Favorites, nil}; }
    static TabLocation pinnedIn(Space *s) { return {Pinned, s}; }
    static TabLocation tabsIn(Space *s) { return {Tabs, s}; }
    bool operator==(const TabLocation &o) const { return kind == o.kind && space == o.space; }
};

struct TabPosition {
    TabLocation location;
    NSInteger index;
};

@protocol BrowserStateObserver <NSObject>
- (void)browserStateDidChangeStructure;
- (void)browserStateDidSelect:(BrowserTab *)tab previous:(BrowserTab *)previous;
- (void)browserStateTabDidChange:(BrowserTab *)tab change:(TabChange)change;
- (void)browserStateDidSwitchSpace:(BOOL)forward;
/// The current space's name, colour or settings changed; the space itself did not change.
- (void)browserStateDidEditCurrentSpace;
@end

/// A tab closed automatically after sitting unused (Settings → Tabs → Archive).
@interface ArchivedTab : NSObject
@property (copy) NSURL *url;
@property (copy) NSString *title;
@property (strong) NSUUID *spaceID;
@property (strong) NSDate *date;
@end

/// Posted when the archive list changes ("BrookArchiveDidChange"), object = the state.
FOUNDATION_EXPORT NSNotificationName const BrowserStateArchiveDidChangeNotification;

/// All windows' tabs and spaces, plus the session file.
@interface BrowserState : NSObject

@property (class, readonly) BrowserState *shared;

@property (readonly) NSArray<BrowserTab *> *favorites;
@property (readonly) NSArray<Space *> *spaces;
@property (readonly) NSInteger currentSpaceIndex;
@property (readonly) BrowserTab *selectedTab;
@property (weak) id<BrowserStateObserver> observer;
@property (readonly) NSArray<ArchivedTab *> *archived;

@property (readonly) Space *currentSpace;
@property (readonly) NSArray<BrowserTab *> *allTabs;
/// Tabs in visual order for the current space (used by ⌘1–9 and ⌃Tab).
@property (readonly) NSArray<BrowserTab *> *visibleTabs;

- (void)load;
- (void)scheduleSave;
/// Snapshots the session now; the file is written on a background queue (see
/// BrookFinishBackgroundWrites).
- (void)saveNow;

- (std::optional<TabPosition>)locationOf:(BrowserTab *)tab;
- (Space *)spaceOf:(BrowserTab *)tab;
- (BrowserTab *)tabWithID:(NSUUID *)identifier;

- (BrowserTab *)openTabWithURL:(NSURL *)url;
- (BrowserTab *)openTabWithURL:(NSURL *)url inSpace:(Space *)space select:(BOOL)select;
- (BrowserTab *)openTabWithURL:(NSURL *)url inSpace:(Space *)space after:(BrowserTab *)parent
                        select:(BOOL)select loadNow:(BOOL)loadNow;
/// Opens a loaded tab for an extension. With a `neighbor`, the tab goes just before it (in the neighbor's
/// space); pinned tabs always stay before regular tabs. With no neighbor, the tab goes after `opener`, or
/// where Settings puts new tabs. A pinned tab goes at the end of the pinned tabs. A muted tab is muted
/// before it loads. Returns nil and sets `error` when the tab cannot be muted.
- (BrowserTab *)openTabWithURL:(NSURL *)url opener:(BrowserTab *)opener before:(BrowserTab *)neighbor
                        pinned:(BOOL)pinned muted:(BOOL)muted select:(BOOL)select error:(NSError **)error;
- (void)insertPopup:(BrowserTab *)tab after:(BrowserTab *)parent select:(BOOL)select;

- (void)selectTab:(BrowserTab *)tab;
- (void)selectNext:(NSInteger)offset;
- (void)selectIndex:(NSInteger)index;

/// ⌘W behaviour: regular tabs are closed; pinned tabs and favorites follow Settings → Tabs.
- (void)close:(BrowserTab *)tab;
/// Removes a tab entirely, whatever kind it is.
- (void)remove:(BrowserTab *)tab;
/// YES when Reopen Closed Tab has a tab to bring back.
@property (readonly) BOOL canReopenClosedTab;
- (void)reopenClosedTab;

- (void)move:(BrowserTab *)tab to:(TabLocation)destination index:(NSInteger)index;
- (void)togglePin:(BrowserTab *)tab;
- (void)toggleFavorite:(BrowserTab *)tab;
- (void)duplicate:(BrowserTab *)tab;

// Split View. Selecting either tab of a pair shows both; the selected one has the keys.
- (TabSplit *)splitFor:(BrowserTab *)tab;
/// The pair on screen, if the selected tab is in one.
@property (readonly) TabSplit *activeSplit;
/// The selected tab, or the one beside it.
- (BOOL)isShowing:(BrowserTab *)tab;
/// A new empty page beside the selected one, selected (its address is typed next). Already split: the
/// right page gets the keys. Returns the new tab, or nil.
- (BrowserTab *)startSplit;
/// `tab` beside the selected page (a pinned tab or favorite goes in as a new tab with its page).
- (void)openInSplit:(BrowserTab *)tab;
- (void)separateSplit;
- (void)swapSplit;
- (void)closeSplit;
- (void)setSplitFraction:(double)fraction;
- (void)focusPaneOnLeft:(BOOL)left;

- (void)switchToSpace:(NSInteger)index;
- (void)switchSpaceBy:(NSInteger)delta;
/// The data store profile a tab belongs to. Favorites always use the shared one.
- (NSUUID *)profileIDFor:(BrowserTab *)tab;
- (void)addSpaceNamed:(NSString *)name colorHex:(NSString *)colorHex searchEngineID:(NSString *)engineID
      separateProfile:(BOOL)separateProfile;
- (void)updateSpace:(Space *)space name:(NSString *)name colorHex:(NSString *)colorHex
     searchEngineID:(NSString *)engineID separateProfile:(BOOL)separateProfile;
- (void)moveSpaceFrom:(NSInteger)from to:(NSInteger)to;
- (void)deleteSpace:(Space *)space;
/// Deletes a profile's cookies and site data once no web view is using it.
+ (void)removeProfileData:(NSUUID *)identifier;

/// Closes every regular tab, resets pinned tabs and favorites, and forgets history.
- (void)burnTabs;

/// Unloads background tabs that haven't been looked at for a while.
- (void)hibernateOlderThan:(NSTimeInterval)seconds;
/// Closes regular tabs nobody has looked at for a while, keeping them in the archive.
- (void)archiveOlderThan:(NSTimeInterval)seconds;
- (void)restoreArchivedAt:(NSInteger)index;
- (void)clearArchive;

/// Called by tabs whenever something about them changes.
- (void)tabDidChange:(BrowserTab *)tab change:(TabChange)change;

@end
