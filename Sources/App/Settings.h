#import <AppKit/AppKit.h>

/// Posted whenever a setting changes. userInfo[@"key"] names the setting ("*" = everything).
FOUNDATION_EXPORT NSNotificationName const BrookSettingsDidChangeNotification;

// MARK: - Option types (stored in defaults as their raw string)

typedef NS_ENUM(NSInteger, ThemeMode) { ThemeModeSystem, ThemeModeLight, ThemeModeDark };
typedef NS_ENUM(NSInteger, SidebarPosition) { SidebarPositionLeft, SidebarPositionRight };
/// Where the tabs live: a sidebar (Arc-style), a strip along the top of the window under the
/// toolbar, or (compact, like Safari's) one row where the selected tab doubles as the address field.
typedef NS_ENUM(NSInteger, TabLayout) { TabLayoutSidebar, TabLayoutTop, TabLayoutCompact };
typedef NS_ENUM(NSInteger, TabDensity) { TabDensityCompact, TabDensityComfortable, TabDensityRoomy };
typedef NS_ENUM(NSInteger, NewTabPosition) { NewTabPositionTop, NewTabPositionBottom, NewTabPositionNextToCurrent };
typedef NS_ENUM(NSInteger, NewTabPage) { NewTabPageCommandBar, NewTabPageBlank, NewTabPageCustom };
typedef NS_ENUM(NSInteger, PinnedCloseBehavior) {
    PinnedCloseBehaviorResetToHome, PinnedCloseBehaviorUnloadOnly, PinnedCloseBehaviorUnpin
};
typedef NS_ENUM(NSInteger, AutoplayPolicy) { AutoplayPolicyAllow, AutoplayPolicyBlockAudio, AutoplayPolicyBlockAll };

/// Raw values ("system", "left", "nextToCurrent", "blockAudio", …) and display titles.
/// Every enum's cases run 0..<count, so `for (NSInteger i = 0; i < count; i++)` lists them all.
FOUNDATION_EXPORT const NSInteger ThemeModeCount, SidebarPositionCount, TabLayoutCount, TabDensityCount,
    NewTabPositionCount, NewTabPageCount, PinnedCloseBehaviorCount, AutoplayPolicyCount;
FOUNDATION_EXPORT NSString *ThemeModeTitle(ThemeMode v);
FOUNDATION_EXPORT NSString *SidebarPositionTitle(SidebarPosition v);
FOUNDATION_EXPORT NSString *TabLayoutTitle(TabLayout v);
FOUNDATION_EXPORT NSString *TabDensityTitle(TabDensity v);
FOUNDATION_EXPORT CGFloat TabDensityRowHeight(TabDensity v);
FOUNDATION_EXPORT NSString *NewTabPositionTitle(NewTabPosition v);
FOUNDATION_EXPORT NSString *NewTabPageTitle(NewTabPage v);
FOUNDATION_EXPORT NSString *PinnedCloseBehaviorTitle(PinnedCloseBehavior v);
FOUNDATION_EXPORT NSString *AutoplayPolicyTitle(AutoplayPolicy v);
FOUNDATION_EXPORT NSString *AutoplayPolicyShortTitle(AutoplayPolicy v);
FOUNDATION_EXPORT NSString *AutoplayPolicyRaw(AutoplayPolicy v);
/// -1 when the string isn't a known policy.
FOUNDATION_EXPORT NSInteger AutoplayPolicyFromRaw(NSString *raw);

// MARK: - Settings

/// Every user preference, backed by NSUserDefaults. Setting a value posts BrookSettingsDidChangeNotification
/// with the key.
@interface Settings : NSObject

/// Keys included in settings export/import.
@property (class, readonly) NSArray<NSString *> *exportedKeys;
+ (void)notify:(NSString *)key;

// Appearance
@property (class) ThemeMode theme;
@property (class) TabLayout tabLayout;
@property (class) SidebarPosition sidebarPosition;
@property (class) CGFloat pageMargin;          // 0…20, default 8
@property (class) CGFloat cornerRadius;        // 0…24, default 12
@property (class) CGFloat tintStrength;        // 0…1.5, default 1 (stored as "spaceTint")
@property (class) TabDensity tabDensity;
@property (class) CGFloat tabFontSize;         // 11…17, default 13
@property (class) BOOL showAddressBar;
@property (class) BOOL showFavorites;
@property (class) BOOL showBottomBar;
@property (class) NSInteger favoritesColumns;  // 2…6, default 4
/// Top tabs squeeze down to icons to fit, instead of keeping readable titles and scrolling.
@property (class) BOOL topTabsShrink;          // default NO

// Tabs
@property (class) NewTabPosition newTabPosition;
@property (class) NewTabPage newTabPage;
@property (class, copy) NSString *newTabURL;
@property (class) PinnedCloseBehavior pinnedClose;
@property (class) NSInteger archiveHours;      // 0 = never
@property (class) NSInteger hibernateMinutes;  // default 30, 0 = never
/// Space that links from other apps open in. nil = the current space.
@property (class, copy) NSUUID *externalLinksSpace;

// Downloads
@property (class, copy) NSURL *downloadFolder;
@property (class) BOOL askDownloadLocation;

// Websites
@property (class) double defaultZoom;          // 0.5…3, default 1
@property (class) BOOL javascriptEnabled;
@property (class) AutoplayPolicy autoplay;
@property (class) BOOL blockCookiePopups;
@property (class) BOOL blockAds;             // default YES

// Search
@property (class, copy) NSString *defaultSearchEngine;

/// JSON blobs stored as strings (so export is plain JSON). Returns the parsed JSON object (array/dict) or nil.
+ (id)jsonForKey:(NSString *)key;
/// Serialises a JSON-compatible object and stores it under key (posts a change).
+ (void)setJSON:(id)object forKey:(NSString *)key;

// Window state (not exported, no notification)
@property (class) CGFloat sidebarWidth;        // default 250
@property (class) BOOL sidebarHidden;

// Export / import
+ (NSData *)exportData:(NSError **)error;
+ (BOOL)importData:(NSData *)data error:(NSError **)error;
+ (void)resetAll;
@end

// MARK: - Search engines

@interface SearchEngine : NSObject <NSCopying>
@property (copy) NSString *identifier;   // JSON key "id"
@property (copy) NSString *name;
/// URL with %s where the query goes.
@property (copy) NSString *urlTemplate;  // JSON key "template"
/// Type this, a space, then a query in the command bar to search with this engine.
@property (copy) NSString *keyword;
+ (instancetype)engineWithID:(NSString *)identifier name:(NSString *)name urlTemplate:(NSString *)t keyword:(NSString *)k;
- (NSURL *)urlForQuery:(NSString *)query;
@property (readonly) BOOL isValid;
@property (class, readonly) NSArray<SearchEngine *> *builtIn;
+ (instancetype)fromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;
@end

@interface SearchEngines : NSObject
/// The user's list (built-ins when unset). Setting it saves.
@property (class, copy) NSArray<SearchEngine *> *all;
+ (void)invalidate;
+ (SearchEngine *)engineWithID:(NSString *)identifier;
@property (class, readonly) SearchEngine *defaultEngine;
/// The engine for the current space (spaces can override the default).
@property (class, readonly) SearchEngine *current;
/// Splits "g cats" into (Google, "cats") when "g" is an engine keyword. Returns nil if no match;
/// otherwise sets *query.
+ (SearchEngine *)keywordMatch:(NSString *)input query:(NSString **)query;
+ (NSURL *)searchURLForInput:(NSString *)input;
@end

// MARK: - Closure actions for controls

@interface NSControl (BrookAction)
/// Sets the control's target/action to a block (retained by the control).
- (void)brook_onAction:(void (^)(id sender))handler;
@end
