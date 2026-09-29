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
/// How the selected and hovered tab are drawn. Every style shares one row layout.
typedef NS_ENUM(NSInteger, TabStyle) { TabStyleCard, TabStyleFlat, TabStyleOutline, TabStyleAccentBar, TabStyleTinted };
/// Where the accent (loading bar, accent-bar tabs, outlines, active downloads) comes from.
typedef NS_ENUM(NSInteger, AccentSource) { AccentSourceSystem, AccentSourceSpace, AccentSourceCustom };
typedef NS_ENUM(NSInteger, ChromeMaterial) { ChromeMaterialGlass, ChromeMaterialClear, ChromeMaterialSolid };
typedef NS_ENUM(NSInteger, CardShadow) { CardShadowNone, CardShadowSoft, CardShadowStrong };
typedef NS_ENUM(NSInteger, UIFontStyle) { UIFontStyleSystem, UIFontStyleRounded, UIFontStyleSerif, UIFontStyleMono };
typedef NS_ENUM(NSInteger, CloseButtonVisibility) {
    CloseButtonVisibilityHover, CloseButtonVisibilityAlways, CloseButtonVisibilityNever
};
typedef NS_ENUM(NSInteger, LoadingIndicator) { LoadingIndicatorBar, LoadingIndicatorSpinner, LoadingIndicatorNone };
typedef NS_ENUM(NSInteger, AppIconStyle) { AppIconStyleDefault, AppIconStyleMono, AppIconStyleNight, AppIconStyleSpace };
/// When the sidebar (or top bar) gets out of the way. Hidden chrome slides back in from the edge.
typedef NS_ENUM(NSInteger, ChromeAutoHide) { ChromeAutoHideNever, ChromeAutoHideAlways, ChromeAutoHideFullScreen };
typedef NS_ENUM(NSInteger, AddressDisplay) { AddressDisplayFull, AddressDisplayDomain, AddressDisplayPageTitle };
typedef NS_ENUM(NSInteger, LinkPreview) { LinkPreviewOff, LinkPreviewLeft, LinkPreviewRight };
/// Which tab is selected after the selected one closes.
typedef NS_ENUM(NSInteger, CloseSelects) { CloseSelectsBelow, CloseSelectsAbove, CloseSelectsLastUsed };
typedef NS_ENUM(NSInteger, LaunchBehavior) { LaunchBehaviorRestore, LaunchBehaviorFresh, LaunchBehaviorStartPage };
typedef NS_ENUM(NSInteger, PageSwipe) { PageSwipeBackForward, PageSwipeOff };
typedef NS_ENUM(NSInteger, CommandBarPosition) { CommandBarPositionUpperThird, CommandBarPositionTop };
/// Buttons the toolbar row can show (Settings → Layout → Toolbar), stored by raw id in order.
typedef NS_ENUM(NSInteger, ToolbarItem) {
    ToolbarItemBack, ToolbarItemForward, ToolbarItemReload, ToolbarItemShare, ToolbarItemCopyLink,
    ToolbarItemReader, ToolbarItemNewTab, ToolbarItemSiteSettings
};
/// A user agent a site can be shown with (Websites → per-site). Default = Brook's Safari UA.
typedef NS_ENUM(NSInteger, UserAgentChoice) {
    UserAgentChoiceSafari, UserAgentChoiceChrome, UserAgentChoiceFirefox, UserAgentChoiceMobile
};

/// Raw values ("system", "left", "nextToCurrent", "blockAudio", …) and display titles.
/// Every enum's cases run 0..<count, so `for (NSInteger i = 0; i < count; i++)` lists them all.
FOUNDATION_EXPORT const NSInteger ThemeModeCount, SidebarPositionCount, TabLayoutCount, TabDensityCount,
    NewTabPositionCount, NewTabPageCount, PinnedCloseBehaviorCount, AutoplayPolicyCount, TabStyleCount,
    AccentSourceCount, ChromeMaterialCount, CardShadowCount, UIFontStyleCount, CloseButtonVisibilityCount,
    LoadingIndicatorCount, AppIconStyleCount, ChromeAutoHideCount, AddressDisplayCount, LinkPreviewCount,
    CloseSelectsCount, LaunchBehaviorCount, PageSwipeCount, CommandBarPositionCount, ToolbarItemCount,
    UserAgentChoiceCount;
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
FOUNDATION_EXPORT NSString *TabStyleTitle(TabStyle v);
FOUNDATION_EXPORT NSString *AccentSourceTitle(AccentSource v);
FOUNDATION_EXPORT NSString *ChromeMaterialTitle(ChromeMaterial v);
FOUNDATION_EXPORT NSString *CardShadowTitle(CardShadow v);
FOUNDATION_EXPORT NSString *UIFontStyleTitle(UIFontStyle v);
FOUNDATION_EXPORT NSString *CloseButtonVisibilityTitle(CloseButtonVisibility v);
FOUNDATION_EXPORT NSString *LoadingIndicatorTitle(LoadingIndicator v);
FOUNDATION_EXPORT NSString *AppIconStyleTitle(AppIconStyle v);
FOUNDATION_EXPORT NSString *ChromeAutoHideTitle(ChromeAutoHide v);
FOUNDATION_EXPORT NSString *AddressDisplayTitle(AddressDisplay v);
FOUNDATION_EXPORT NSString *LinkPreviewTitle(LinkPreview v);
FOUNDATION_EXPORT NSString *CloseSelectsTitle(CloseSelects v);
FOUNDATION_EXPORT NSString *LaunchBehaviorTitle(LaunchBehavior v);
FOUNDATION_EXPORT NSString *PageSwipeTitle(PageSwipe v);
FOUNDATION_EXPORT NSString *CommandBarPositionTitle(CommandBarPosition v);
FOUNDATION_EXPORT NSString *ToolbarItemTitle(ToolbarItem v);
FOUNDATION_EXPORT NSString *ToolbarItemSymbol(ToolbarItem v);
FOUNDATION_EXPORT NSString *ToolbarItemRaw(ToolbarItem v);
FOUNDATION_EXPORT NSString *UserAgentChoiceTitle(UserAgentChoice v);
FOUNDATION_EXPORT NSString *UserAgentChoiceRaw(UserAgentChoice v);
/// -1 when the string isn't a known raw value.
FOUNDATION_EXPORT NSInteger UserAgentChoiceFromRaw(NSString *raw);
/// Theme / tab layout / pinned-close raw strings, for per-space overrides. -1 when unknown or nil.
FOUNDATION_EXPORT NSString *ThemeModeRaw(ThemeMode v);
FOUNDATION_EXPORT NSInteger ThemeModeFromRaw(NSString *raw);
FOUNDATION_EXPORT NSString *TabLayoutRaw(TabLayout v);
FOUNDATION_EXPORT NSInteger TabLayoutFromRaw(NSString *raw);
FOUNDATION_EXPORT NSString *PinnedCloseBehaviorRaw(PinnedCloseBehavior v);
FOUNDATION_EXPORT NSInteger PinnedCloseBehaviorFromRaw(NSString *raw);

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
@property (class) TabStyle tabStyle;
@property (class) AccentSource accentSource;
@property (class, copy) NSString *accentColorHex;   // AccentSourceCustom; default system blue
/// Sidebar / top bar surface, and how opaque it is (0.3…1, only for Solid).
@property (class) ChromeMaterial chromeMaterial;
@property (class) CGFloat chromeOpacity;       // default 0.85
@property (class) CardShadow cardShadow;
@property (class) UIFontStyle uiFont;
@property (class) CloseButtonVisibility closeButtons;
/// Sidebar tabs show the site under the title.
@property (class) BOOL tabSubtitles;           // default NO
/// The sidebar shrinks to a rail of icons.
@property (class) BOOL sidebarIconsOnly;       // default NO
@property (class) LoadingIndicator loadingIndicator;
@property (class) AppIconStyle appIcon;
@property (class) ChromeAutoHide autoHide;
@property (class) AddressDisplay addressDisplay;
@property (class) LinkPreview linkPreview;     // default left
/// Toolbar buttons beside the traffic lights, in order (ToolbarItem values).
@property (class, copy) NSArray<NSNumber *> *toolbarItems;

// Tabs
@property (class) NewTabPosition newTabPosition;
@property (class) NewTabPage newTabPage;
@property (class, copy) NSString *newTabURL;
@property (class) PinnedCloseBehavior pinnedClose;
@property (class) NSInteger archiveHours;      // 0 = never
@property (class) NSInteger hibernateMinutes;  // default 30, 0 = never
/// Space that links from other apps open in. nil = the current space.
@property (class, copy) NSUUID *externalLinksSpace;
@property (class) CloseSelects closeSelects;
/// ⌘-click opens links in a background tab (⇧ flips it). NO = foreground.
@property (class) BOOL linksOpenInBackground;  // default YES
/// Middle-clicking a tab closes it.
@property (class) BOOL middleClickCloses;      // default YES
@property (class) PageSwipe pageSwipe;
/// Two-finger swipe across the tab list switches spaces.
@property (class) BOOL swipeSwitchesSpaces;    // default YES
@property (class) LaunchBehavior launchBehavior;
@property (class, copy) NSString *startPageURL;
/// Ask before quitting with at least this many open tabs. 0 = never.
@property (class) NSInteger quitWarningTabs;   // default 0

// Command bar
@property (class) BOOL commandBarTabs;         // default YES
@property (class) BOOL commandBarHistory;      // default YES
@property (class) BOOL commandBarSuggestions;  // default YES
@property (class) NSInteger commandBarRows;    // 4…12, default 8
@property (class) CommandBarPosition commandBarPosition;

// Downloads
@property (class, copy) NSURL *downloadFolder;
@property (class) BOOL askDownloadLocation;

// Websites
@property (class) double defaultZoom;          // 0.5…3, default 1
@property (class) BOOL javascriptEnabled;
@property (class) AutoplayPolicy autoplay;
@property (class) BOOL blockCookiePopups;
@property (class) BOOL blockAds;             // default YES

// Passwords
/// Offer to save a password after signing in to a site.
@property (class) BOOL offerToSavePasswords;  // default YES
/// Offer saved logins when a sign-in field is clicked.
@property (class) BOOL autofillPasswords;     // default YES

// Search
@property (class, copy) NSString *defaultSearchEngine;

/// JSON blobs stored as strings (so export is plain JSON). Returns the parsed JSON object (array/dict) or nil.
+ (id)jsonForKey:(NSString *)key;
/// Serialises a JSON-compatible object and stores it under key (posts a change).
+ (void)setJSON:(id)object forKey:(NSString *)key;

// Window state (not exported, no notification)
@property (class) CGFloat sidebarWidth;        // default 250
@property (class) BOOL sidebarHidden;

/// Menu shortcut overrides: menu action selector name → "⌘⇧K"-style string ("" = no shortcut).
@property (class, copy) NSDictionary<NSString *, NSString *> *shortcuts;

// Appearance presets
/// The keys a preset captures (everything under Appearance).
@property (class, readonly) NSArray<NSString *> *appearanceKeys;
/// Saved presets, name → values of appearanceKeys.
@property (class, copy) NSDictionary<NSString *, NSDictionary *> *appearancePresets;
@property (class, readonly) NSDictionary *currentAppearance;
/// Sets every appearance key from the dictionary (missing ones go back to default).
/// NO, with nothing changed, if a value can't be stored.
+ (BOOL)applyAppearance:(NSDictionary *)values;

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

@interface NSMenuItem (BrookAction)
/// A menu item that runs a block (retained by the item).
+ (instancetype)brook_itemWithTitle:(NSString *)title action:(void (^)(void))handler;
@end
