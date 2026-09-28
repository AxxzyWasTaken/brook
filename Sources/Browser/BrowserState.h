#import <AppKit/AppKit.h>
#import "BrowserTab.h"

@interface Space : NSObject
- (instancetype)initWithID:(NSUUID *)identifier name:(NSString *)name colorHex:(NSString *)colorHex;
- (instancetype)initWithName:(NSString *)name colorHex:(NSString *)colorHex;
@property (readonly) NSUUID *identifier;
@property (copy) NSString *name;
@property (copy) NSString *colorHex;
@property (strong) NSMutableArray<BrowserTab *> *pinned;
@property (strong) NSMutableArray<BrowserTab *> *tabs;
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
@end

/// A tab closed automatically after sitting unused (Settings → Tabs → Archive).
@interface ArchivedTab : NSObject
@property (copy) NSURL *url;
@property (copy) NSString *title;
@property (strong) NSUUID *spaceID;
@property (strong) NSDate *date;
@end

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
- (void)saveNow;

- (std::optional<TabPosition>)locationOf:(BrowserTab *)tab;
- (Space *)spaceOf:(BrowserTab *)tab;
- (BrowserTab *)tabWithID:(NSUUID *)identifier;

- (BrowserTab *)openTabWithURL:(NSURL *)url;
- (BrowserTab *)openTabWithURL:(NSURL *)url inSpace:(Space *)space select:(BOOL)select;
- (BrowserTab *)openTabWithURL:(NSURL *)url inSpace:(Space *)space after:(BrowserTab *)parent
                        select:(BOOL)select loadNow:(BOOL)loadNow;
- (void)insertPopup:(BrowserTab *)tab after:(BrowserTab *)parent select:(BOOL)select;

- (void)selectTab:(BrowserTab *)tab;
- (void)selectNext:(NSInteger)offset;
- (void)selectIndex:(NSInteger)index;

/// ⌘W behaviour: regular tabs are closed; pinned tabs and favorites follow Settings → Tabs.
- (void)close:(BrowserTab *)tab;
/// Removes a tab entirely, whatever kind it is.
- (void)remove:(BrowserTab *)tab;
- (void)reopenClosedTab;

- (void)move:(BrowserTab *)tab to:(TabLocation)destination index:(NSInteger)index;
- (void)togglePin:(BrowserTab *)tab;
- (void)toggleFavorite:(BrowserTab *)tab;
- (void)duplicate:(BrowserTab *)tab;

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
