#import "Brook.h"
#import <objc/runtime.h>

NSNotificationName const BrookSettingsDidChangeNotification = @"BrookSettingsDidChange";

// MARK: - Option types

// Each enum's raw values, in case order. These are what's stored in defaults.
static NSArray<NSString *> *const kThemeRaw = @[@"system", @"light", @"dark"];
static NSArray<NSString *> *const kSidebarRaw = @[@"left", @"right"];
static NSArray<NSString *> *const kTabLayoutRaw = @[@"sidebar", @"top", @"compact"];
static NSArray<NSString *> *const kDensityRaw = @[@"compact", @"comfortable", @"roomy"];
static NSArray<NSString *> *const kNewTabPositionRaw = @[@"top", @"bottom", @"nextToCurrent"];
static NSArray<NSString *> *const kNewTabPageRaw = @[@"commandBar", @"blank", @"custom"];
static NSArray<NSString *> *const kPinnedCloseRaw = @[@"resetToHome", @"unloadOnly", @"unpin"];
static NSArray<NSString *> *const kAutoplayRaw = @[@"allow", @"blockAudio", @"blockAll"];
static NSArray<NSString *> *const kTabStyleRaw = @[@"card", @"flat", @"outline", @"accentBar", @"tinted"];
static NSArray<NSString *> *const kAccentRaw = @[@"system", @"space", @"custom"];
static NSArray<NSString *> *const kMaterialRaw = @[@"glass", @"clear", @"solid"];
static NSArray<NSString *> *const kShadowRaw = @[@"none", @"soft", @"strong"];
static NSArray<NSString *> *const kFontRaw = @[@"system", @"rounded", @"serif", @"mono"];
static NSArray<NSString *> *const kCloseRaw = @[@"hover", @"always", @"never"];
static NSArray<NSString *> *const kLoadingRaw = @[@"bar", @"spinner", @"none"];
static NSArray<NSString *> *const kAppIconRaw = @[@"default", @"mono", @"night", @"space"];
static NSArray<NSString *> *const kAutoHideRaw = @[@"never", @"always", @"fullScreen"];
static NSArray<NSString *> *const kAddressRaw = @[@"full", @"domain", @"title"];
static NSArray<NSString *> *const kLinkPreviewRaw = @[@"off", @"left", @"right"];
static NSArray<NSString *> *const kCloseSelectsRaw = @[@"below", @"above", @"lastUsed"];
static NSArray<NSString *> *const kLaunchRaw = @[@"restore", @"fresh", @"startPage"];
static NSArray<NSString *> *const kSwipeRaw = @[@"backForward", @"off"];
static NSArray<NSString *> *const kCommandBarPositionRaw = @[@"upperThird", @"top"];
static NSArray<NSString *> *const kToolbarRaw = @[@"back", @"forward", @"reload", @"share", @"copyLink", @"reader",
                                                  @"newTab", @"siteSettings"];
static NSArray<NSString *> *const kUserAgentRaw = @[@"safari", @"chrome", @"firefox", @"mobile"];

const NSInteger ThemeModeCount = 3, SidebarPositionCount = 2, TabLayoutCount = 3, TabDensityCount = 3,
    NewTabPositionCount = 3, NewTabPageCount = 3, PinnedCloseBehaviorCount = 3, AutoplayPolicyCount = 3,
    TabStyleCount = 5, AccentSourceCount = 3, ChromeMaterialCount = 3, CardShadowCount = 3, UIFontStyleCount = 4,
    CloseButtonVisibilityCount = 3, LoadingIndicatorCount = 3, AppIconStyleCount = 4, ChromeAutoHideCount = 3,
    AddressDisplayCount = 3, LinkPreviewCount = 3, CloseSelectsCount = 3, LaunchBehaviorCount = 3, PageSwipeCount = 2,
    CommandBarPositionCount = 2, ToolbarItemCount = 8, UserAgentChoiceCount = 4;

static NSString *BrookPick(NSArray<NSString *> *list, NSInteger i) {
    return (i >= 0 && i < (NSInteger)list.count) ? list[(NSUInteger)i] : list.firstObject;
}

static NSInteger BrookIndex(NSArray<NSString *> *list, NSString *raw) {
    NSUInteger i = [raw isKindOfClass:NSString.class] ? [list indexOfObject:raw] : NSNotFound;
    return i == NSNotFound ? -1 : (NSInteger)i;
}

NSString *ThemeModeTitle(ThemeMode v) { return BrookPick(@[@"System", @"Light", @"Dark"], v); }
NSString *SidebarPositionTitle(SidebarPosition v) { return BrookPick(@[@"Left", @"Right"], v); }
NSString *TabLayoutTitle(TabLayout v) { return BrookPick(@[@"Sidebar", @"Top", @"Compact"], v); }
NSString *TabDensityTitle(TabDensity v) { return BrookPick(@[@"Compact", @"Comfortable", @"Roomy"], v); }
CGFloat TabDensityRowHeight(TabDensity v) {
    switch (v) {
        case TabDensityCompact: return 28;
        case TabDensityRoomy: return 40;
        default: return 34;
    }
}
NSString *NewTabPositionTitle(NewTabPosition v) {
    return BrookPick(@[@"At the top", @"At the bottom", @"Next to the current tab"], v);
}
NSString *NewTabPageTitle(NewTabPage v) { return BrookPick(@[@"Command bar", @"Blank page", @"Custom page"], v); }
NSString *PinnedCloseBehaviorTitle(PinnedCloseBehavior v) {
    return BrookPick(@[@"Unload and go back to its pinned page", @"Unload, keep the current page",
                       @"Close it and remove the pin"], v);
}
NSString *AutoplayPolicyTitle(AutoplayPolicy v) {
    return BrookPick(@[@"Allow all autoplay", @"Stop media with sound", @"Never autoplay"], v);
}
NSString *AutoplayPolicyShortTitle(AutoplayPolicy v) { return BrookPick(@[@"Allow", @"Block sound", @"Block"], v); }
NSString *AutoplayPolicyRaw(AutoplayPolicy v) { return BrookPick(kAutoplayRaw, v); }
NSInteger AutoplayPolicyFromRaw(NSString *raw) {
    NSUInteger i = raw ? [kAutoplayRaw indexOfObject:raw] : NSNotFound;
    return i == NSNotFound ? -1 : (NSInteger)i;
}
NSString *TabStyleTitle(TabStyle v) { return BrookPick(@[@"Card", @"Flat", @"Outline", @"Accent bar", @"Tinted"], v); }
NSString *AccentSourceTitle(AccentSource v) { return BrookPick(@[@"System", @"Space colour", @"Custom"], v); }
NSString *ChromeMaterialTitle(ChromeMaterial v) { return BrookPick(@[@"Glass", @"Clear glass", @"Solid"], v); }
NSString *CardShadowTitle(CardShadow v) { return BrookPick(@[@"None", @"Soft", @"Strong"], v); }
NSString *UIFontStyleTitle(UIFontStyle v) { return BrookPick(@[@"System", @"Rounded", @"Serif", @"Monospaced"], v); }
NSString *CloseButtonVisibilityTitle(CloseButtonVisibility v) { return BrookPick(@[@"On hover", @"Always", @"Never"], v); }
NSString *LoadingIndicatorTitle(LoadingIndicator v) { return BrookPick(@[@"Bar", @"Spinning icon", @"None"], v); }
NSString *AppIconStyleTitle(AppIconStyle v) { return BrookPick(@[@"Default", @"Mono", @"Night", @"Space colour"], v); }
NSString *ChromeAutoHideTitle(ChromeAutoHide v) { return BrookPick(@[@"Never", @"Always", @"In full screen"], v); }
NSString *AddressDisplayTitle(AddressDisplay v) { return BrookPick(@[@"Full address", @"Domain only", @"Page title"], v); }
NSString *LinkPreviewTitle(LinkPreview v) { return BrookPick(@[@"Off", @"Bottom left", @"Bottom right"], v); }
NSString *CloseSelectsTitle(CloseSelects v) {
    return BrookPick(@[@"The tab below", @"The tab above", @"The last tab you used"], v);
}
NSString *LaunchBehaviorTitle(LaunchBehavior v) {
    return BrookPick(@[@"Reopen your tabs", @"Start fresh (keep pinned tabs)", @"Open a start page"], v);
}
NSString *PageSwipeTitle(PageSwipe v) { return BrookPick(@[@"Back and forward", @"Off"], v); }
NSString *CommandBarPositionTitle(CommandBarPosition v) { return BrookPick(@[@"Upper third", @"Near the top"], v); }
NSString *ToolbarItemTitle(ToolbarItem v) {
    return BrookPick(@[@"Back", @"Forward", @"Reload", @"Share", @"Copy Link", @"Reader", @"New Tab", @"Site Settings"], v);
}
NSString *ToolbarItemSymbol(ToolbarItem v) {
    return BrookPick(@[@"arrow.left", @"arrow.right", @"arrow.clockwise", @"square.and.arrow.up", @"link",
                       @"doc.plaintext", @"plus", @"slider.horizontal.3"], v);
}
NSString *ToolbarItemRaw(ToolbarItem v) { return BrookPick(kToolbarRaw, v); }
NSString *UserAgentChoiceTitle(UserAgentChoice v) { return BrookPick(@[@"Safari", @"Chrome", @"Firefox", @"Mobile Safari"], v); }
NSString *UserAgentChoiceRaw(UserAgentChoice v) { return BrookPick(kUserAgentRaw, v); }
NSInteger UserAgentChoiceFromRaw(NSString *raw) { return BrookIndex(kUserAgentRaw, raw); }
NSString *ThemeModeRaw(ThemeMode v) { return BrookPick(kThemeRaw, v); }
NSInteger ThemeModeFromRaw(NSString *raw) { return BrookIndex(kThemeRaw, raw); }
NSString *TabLayoutRaw(TabLayout v) { return BrookPick(kTabLayoutRaw, v); }
NSInteger TabLayoutFromRaw(NSString *raw) { return BrookIndex(kTabLayoutRaw, raw); }
NSString *PinnedCloseBehaviorRaw(PinnedCloseBehavior v) { return BrookPick(kPinnedCloseRaw, v); }
NSInteger PinnedCloseBehaviorFromRaw(NSString *raw) { return BrookIndex(kPinnedCloseRaw, raw); }

// MARK: - Settings

@implementation Settings

static NSUserDefaults *D(void) { return NSUserDefaults.standardUserDefaults; }

+ (NSArray<NSString *> *)appearanceKeys {
    return @[@"theme", @"tabLayout", @"sidebarPosition", @"pageMargin", @"cornerRadius", @"spaceTint", @"tabDensity",
             @"tabFontSize", @"showAddressBar", @"showFavorites", @"showBottomBar", @"favoritesColumns", @"topTabsShrink",
             @"tabStyle", @"accentSource", @"accentColor", @"chromeMaterial", @"chromeOpacity", @"cardShadow", @"uiFont",
             @"closeButtons", @"tabSubtitles", @"sidebarIconsOnly", @"loadingIndicator", @"autoHide", @"addressDisplay",
             @"linkPreview", @"toolbarItems"];
}

+ (NSArray<NSString *> *)exportedKeys {
    NSArray *rest = @[@"appIcon", @"newTabPosition", @"newTabPage", @"newTabURL", @"pinnedClose", @"archiveHours",
                      @"hibernateMinutes", @"externalLinksSpace", @"closeSelects", @"linksOpenInBackground",
                      @"middleClickCloses", @"pageSwipe", @"swipeSwitchesSpaces", @"launchBehavior", @"startPageURL",
                      @"quitWarningTabs", @"commandBarTabs", @"commandBarHistory", @"commandBarSuggestions",
                      @"commandBarRows", @"commandBarPosition", @"downloadFolder", @"askDownloadLocation",
                      @"defaultZoom", @"javascriptEnabled", @"autoplay", @"blockCookiePopups", @"blockAds",
                      @"siteNotifications", @"sitePermissions",
                      @"offerToSavePasswords", @"autofillPasswords",
                      @"defaultSearchEngine", @"searchEngines", @"siteSettings", @"boosts", @"shortcuts",
                      @"appearancePresets"];
    return [self.appearanceKeys arrayByAddingObjectsFromArray:rest];
}

+ (void)notify:(NSString *)key {
    [NSNotificationCenter.defaultCenter postNotificationName:BrookSettingsDidChangeNotification
                                                      object:nil
                                                    userInfo:@{@"key": key}];
}

+ (void)store:(id)value key:(NSString *)key {
    if (value) [D() setObject:value forKey:key]; else [D() removeObjectForKey:key];
    [self notify:key];
}

/// Index of the stored raw string in `raws`, or `fallback`.
static NSInteger choice(NSString *key, NSArray<NSString *> *raws, NSInteger fallback) {
    NSString *s = [D() stringForKey:key];
    NSUInteger i = s ? [raws indexOfObject:s] : NSNotFound;
    return i == NSNotFound ? fallback : (NSInteger)i;
}

static double number(NSString *key, double fallback) {
    id v = [D() objectForKey:key];
    return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : fallback;
}

static BOOL flag(NSString *key, BOOL fallback) {
    id v = [D() objectForKey:key];
    return [v isKindOfClass:NSNumber.class] ? [v boolValue] : fallback;
}

/// Whole NSNumbers only.
static NSInteger integer(NSString *key, NSInteger fallback) {
    id v = [D() objectForKey:key];
    if (![v isKindOfClass:NSNumber.class]) return fallback;
    double d = [v doubleValue];
    return d == floor(d) ? (NSInteger)d : fallback;
}

static double clampD(double v, double lo, double hi) { return MIN(hi, MAX(lo, v)); }

// Appearance

+ (ThemeMode)theme { return (ThemeMode)choice(@"theme", kThemeRaw, ThemeModeSystem); }
+ (void)setTheme:(ThemeMode)v { [self store:BrookPick(kThemeRaw, v) key:@"theme"]; }

+ (TabLayout)tabLayout { return (TabLayout)choice(@"tabLayout", kTabLayoutRaw, TabLayoutSidebar); }
+ (void)setTabLayout:(TabLayout)v { [self store:BrookPick(kTabLayoutRaw, v) key:@"tabLayout"]; }

+ (SidebarPosition)sidebarPosition { return (SidebarPosition)choice(@"sidebarPosition", kSidebarRaw, SidebarPositionLeft); }
+ (void)setSidebarPosition:(SidebarPosition)v { [self store:BrookPick(kSidebarRaw, v) key:@"sidebarPosition"]; }

+ (CGFloat)pageMargin { return clampD(number(@"pageMargin", 8), 0, 20); }
+ (void)setPageMargin:(CGFloat)v { [self store:@(v) key:@"pageMargin"]; }

+ (CGFloat)cornerRadius { return clampD(number(@"cornerRadius", 12), 0, 24); }
+ (void)setCornerRadius:(CGFloat)v { [self store:@(v) key:@"cornerRadius"]; }

// "tintStrength" was the same setting on a weaker scale: its 150% is 100% now.
static NSString *const kLegacyTintKey = @"tintStrength";
static const double kLegacyTintScale = 1.5;

+ (CGFloat)tintStrength {
    double legacy = number(kLegacyTintKey, kLegacyTintScale) / kLegacyTintScale;
    return clampD(number(@"spaceTint", legacy), 0, 1.5);
}
+ (void)setTintStrength:(CGFloat)v {
    [D() removeObjectForKey:kLegacyTintKey];
    [self store:@(v) key:@"spaceTint"];
}

+ (TabDensity)tabDensity { return (TabDensity)choice(@"tabDensity", kDensityRaw, TabDensityComfortable); }
+ (void)setTabDensity:(TabDensity)v { [self store:BrookPick(kDensityRaw, v) key:@"tabDensity"]; }

+ (CGFloat)tabFontSize { return clampD(number(@"tabFontSize", 13), 11, 17); }
+ (void)setTabFontSize:(CGFloat)v { [self store:@(v) key:@"tabFontSize"]; }

+ (BOOL)showAddressBar { return flag(@"showAddressBar", YES); }
+ (void)setShowAddressBar:(BOOL)v { [self store:@(v) key:@"showAddressBar"]; }

+ (BOOL)showFavorites { return flag(@"showFavorites", YES); }
+ (void)setShowFavorites:(BOOL)v { [self store:@(v) key:@"showFavorites"]; }

+ (BOOL)showBottomBar { return flag(@"showBottomBar", YES); }
+ (void)setShowBottomBar:(BOOL)v { [self store:@(v) key:@"showBottomBar"]; }

+ (NSInteger)favoritesColumns { return (NSInteger)clampD(number(@"favoritesColumns", 4), 2, 6); }
+ (void)setFavoritesColumns:(NSInteger)v { [self store:@(v) key:@"favoritesColumns"]; }

+ (BOOL)topTabsShrink { return flag(@"topTabsShrink", NO); }
+ (void)setTopTabsShrink:(BOOL)v { [self store:@(v) key:@"topTabsShrink"]; }

// One line per enum-backed setting: getter reads the raw string, setter stores it.
#define BROOK_CHOICE(TYPE, GETTER, SETTER, KEY, RAWS, FALLBACK)                              \
    +(TYPE)GETTER { return (TYPE)choice(KEY, RAWS, FALLBACK); }                              \
    +(void)SETTER:(TYPE)v { [self store:BrookPick(RAWS, v) key:KEY]; }
#define BROOK_FLAG(GETTER, SETTER, KEY, FALLBACK)                                            \
    +(BOOL)GETTER { return flag(KEY, FALLBACK); }                                            \
    +(void)SETTER:(BOOL)v { [self store:@(v) key:KEY]; }

BROOK_CHOICE(TabStyle, tabStyle, setTabStyle, @"tabStyle", kTabStyleRaw, TabStyleCard)
BROOK_CHOICE(AccentSource, accentSource, setAccentSource, @"accentSource", kAccentRaw, AccentSourceSpace)
BROOK_CHOICE(ChromeMaterial, chromeMaterial, setChromeMaterial, @"chromeMaterial", kMaterialRaw, ChromeMaterialGlass)
BROOK_CHOICE(CardShadow, cardShadow, setCardShadow, @"cardShadow", kShadowRaw, CardShadowSoft)
BROOK_CHOICE(UIFontStyle, uiFont, setUiFont, @"uiFont", kFontRaw, UIFontStyleSystem)
BROOK_CHOICE(CloseButtonVisibility, closeButtons, setCloseButtons, @"closeButtons", kCloseRaw, CloseButtonVisibilityHover)
BROOK_CHOICE(LoadingIndicator, loadingIndicator, setLoadingIndicator, @"loadingIndicator", kLoadingRaw, LoadingIndicatorBar)
BROOK_CHOICE(AppIconStyle, appIcon, setAppIcon, @"appIcon", kAppIconRaw, AppIconStyleDefault)
BROOK_CHOICE(ChromeAutoHide, autoHide, setAutoHide, @"autoHide", kAutoHideRaw, ChromeAutoHideNever)
BROOK_CHOICE(AddressDisplay, addressDisplay, setAddressDisplay, @"addressDisplay", kAddressRaw, AddressDisplayDomain)
BROOK_CHOICE(LinkPreview, linkPreview, setLinkPreview, @"linkPreview", kLinkPreviewRaw, LinkPreviewLeft)
BROOK_CHOICE(CloseSelects, closeSelects, setCloseSelects, @"closeSelects", kCloseSelectsRaw, CloseSelectsBelow)
BROOK_CHOICE(LaunchBehavior, launchBehavior, setLaunchBehavior, @"launchBehavior", kLaunchRaw, LaunchBehaviorRestore)
BROOK_CHOICE(PageSwipe, pageSwipe, setPageSwipe, @"pageSwipe", kSwipeRaw, PageSwipeBackForward)
BROOK_CHOICE(CommandBarPosition, commandBarPosition, setCommandBarPosition, @"commandBarPosition", kCommandBarPositionRaw,
             CommandBarPositionUpperThird)
BROOK_FLAG(tabSubtitles, setTabSubtitles, @"tabSubtitles", NO)
BROOK_FLAG(sidebarIconsOnly, setSidebarIconsOnly, @"sidebarIconsOnly", NO)
BROOK_FLAG(linksOpenInBackground, setLinksOpenInBackground, @"linksOpenInBackground", YES)
BROOK_FLAG(middleClickCloses, setMiddleClickCloses, @"middleClickCloses", YES)
BROOK_FLAG(swipeSwitchesSpaces, setSwipeSwitchesSpaces, @"swipeSwitchesSpaces", YES)
BROOK_FLAG(commandBarTabs, setCommandBarTabs, @"commandBarTabs", YES)
BROOK_FLAG(commandBarHistory, setCommandBarHistory, @"commandBarHistory", YES)
BROOK_FLAG(commandBarSuggestions, setCommandBarSuggestions, @"commandBarSuggestions", YES)

#undef BROOK_CHOICE
#undef BROOK_FLAG

+ (NSString *)accentColorHex {
    NSString *s = [D() stringForKey:@"accentColor"];
    return [NSColor brook_colorWithHex:s] ? s : @"#007AFF";
}
+ (void)setAccentColorHex:(NSString *)v { [self store:v key:@"accentColor"]; }

+ (CGFloat)chromeOpacity { return clampD(number(@"chromeOpacity", 0.85), 0.3, 1); }
+ (void)setChromeOpacity:(CGFloat)v { [self store:@(v) key:@"chromeOpacity"]; }

+ (NSArray<NSNumber *> *)toolbarItems {
    id raw = [D() objectForKey:@"toolbarItems"];
    if (![raw isKindOfClass:NSArray.class]) return @[@(ToolbarItemBack), @(ToolbarItemForward), @(ToolbarItemReload)];
    NSMutableArray *items = [NSMutableArray array];
    for (id s in raw) {
        NSInteger i = BrookIndex(kToolbarRaw, s);
        if (i >= 0 && ![items containsObject:@(i)]) [items addObject:@(i)];
    }
    return items;
}
+ (void)setToolbarItems:(NSArray<NSNumber *> *)v {
    NSMutableArray *raw = [NSMutableArray array];
    for (NSNumber *n in v) [raw addObject:ToolbarItemRaw((ToolbarItem)n.integerValue)];
    [self store:raw key:@"toolbarItems"];
}

// Tabs

+ (NewTabPosition)newTabPosition { return (NewTabPosition)choice(@"newTabPosition", kNewTabPositionRaw, NewTabPositionTop); }
+ (void)setNewTabPosition:(NewTabPosition)v { [self store:BrookPick(kNewTabPositionRaw, v) key:@"newTabPosition"]; }

+ (NewTabPage)newTabPage { return (NewTabPage)choice(@"newTabPage", kNewTabPageRaw, NewTabPageCommandBar); }
+ (void)setNewTabPage:(NewTabPage)v { [self store:BrookPick(kNewTabPageRaw, v) key:@"newTabPage"]; }

+ (NSString *)newTabURL { return [D() stringForKey:@"newTabURL"] ?: @""; }
+ (void)setNewTabURL:(NSString *)v { [self store:v key:@"newTabURL"]; }

+ (PinnedCloseBehavior)pinnedClose {
    return (PinnedCloseBehavior)choice(@"pinnedClose", kPinnedCloseRaw, PinnedCloseBehaviorResetToHome);
}
+ (void)setPinnedClose:(PinnedCloseBehavior)v { [self store:BrookPick(kPinnedCloseRaw, v) key:@"pinnedClose"]; }

+ (NSInteger)archiveHours { return integer(@"archiveHours", 0); }
+ (void)setArchiveHours:(NSInteger)v { [self store:@(v) key:@"archiveHours"]; }

+ (NSInteger)hibernateMinutes { return integer(@"hibernateMinutes", 30); }
+ (void)setHibernateMinutes:(NSInteger)v { [self store:@(v) key:@"hibernateMinutes"]; }

+ (NSUUID *)externalLinksSpace {
    NSString *s = [D() stringForKey:@"externalLinksSpace"];
    return s ? [[NSUUID alloc] initWithUUIDString:s] : nil;
}
+ (void)setExternalLinksSpace:(NSUUID *)v { [self store:v.UUIDString key:@"externalLinksSpace"]; }

+ (NSString *)startPageURL { return [D() stringForKey:@"startPageURL"] ?: @""; }
+ (void)setStartPageURL:(NSString *)v { [self store:v key:@"startPageURL"]; }

+ (NSInteger)quitWarningTabs { return MAX(0, integer(@"quitWarningTabs", 0)); }
+ (void)setQuitWarningTabs:(NSInteger)v { [self store:@(v) key:@"quitWarningTabs"]; }

+ (NSInteger)commandBarRows { return (NSInteger)clampD(integer(@"commandBarRows", 8), 4, 12); }
+ (void)setCommandBarRows:(NSInteger)v { [self store:@(v) key:@"commandBarRows"]; }

// Downloads

+ (NSURL *)downloadFolder {
    NSString *path = [D() stringForKey:@"downloadFolder"];
    if (path) return [NSURL fileURLWithPath:path isDirectory:YES];
    return [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
}
+ (void)setDownloadFolder:(NSURL *)v { [self store:v.path key:@"downloadFolder"]; }

+ (BOOL)askDownloadLocation { return flag(@"askDownloadLocation", NO); }
+ (void)setAskDownloadLocation:(BOOL)v { [self store:@(v) key:@"askDownloadLocation"]; }

// Websites

+ (double)defaultZoom { return clampD(number(@"defaultZoom", 1), 0.5, 3); }
+ (void)setDefaultZoom:(double)v { [self store:@(v) key:@"defaultZoom"]; }

+ (BOOL)javascriptEnabled { return flag(@"javascriptEnabled", YES); }
+ (void)setJavascriptEnabled:(BOOL)v { [self store:@(v) key:@"javascriptEnabled"]; }

+ (AutoplayPolicy)autoplay { return (AutoplayPolicy)choice(@"autoplay", kAutoplayRaw, AutoplayPolicyAllow); }
+ (void)setAutoplay:(AutoplayPolicy)v { [self store:AutoplayPolicyRaw(v) key:@"autoplay"]; }

+ (BOOL)blockCookiePopups { return flag(@"blockCookiePopups", YES); }
+ (void)setBlockCookiePopups:(BOOL)v { [self store:@(v) key:@"blockCookiePopups"]; }

+ (BOOL)blockAds { return flag(@"blockAds", YES); }
+ (void)setBlockAds:(BOOL)v { [self store:@(v) key:@"blockAds"]; }
+ (BOOL)siteNotifications { return flag(@"siteNotifications", YES); }
+ (void)setSiteNotifications:(BOOL)v { [self store:@(v) key:@"siteNotifications"]; }

// Passwords

+ (BOOL)offerToSavePasswords { return flag(@"offerToSavePasswords", YES); }
+ (void)setOfferToSavePasswords:(BOOL)v { [self store:@(v) key:@"offerToSavePasswords"]; }

+ (BOOL)autofillPasswords { return flag(@"autofillPasswords", YES); }
+ (void)setAutofillPasswords:(BOOL)v { [self store:@(v) key:@"autofillPasswords"]; }

// Search

+ (NSString *)defaultSearchEngine {
    return [D() stringForKey:@"defaultSearchEngine"] ?: [D() stringForKey:@"searchEngine"] ?: @"duckduckgo";
}
+ (void)setDefaultSearchEngine:(NSString *)v { [self store:v key:@"defaultSearchEngine"]; }

// JSON blobs

+ (id)jsonForKey:(NSString *)key {
    NSData *data = [[D() stringForKey:key] dataUsingEncoding:NSUTF8StringEncoding];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

+ (void)setJSON:(id)object forKey:(NSString *)key {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingWithoutEscapingSlashes error:nil];
    if (!data) return;
    [self store:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] key:key];
}

// Window state

+ (CGFloat)sidebarWidth { return number(@"sidebarWidth", 250); }
+ (void)setSidebarWidth:(CGFloat)v { [D() setDouble:v forKey:@"sidebarWidth"]; }

+ (BOOL)sidebarHidden { return [D() boolForKey:@"sidebarHidden"]; }
+ (void)setSidebarHidden:(BOOL)v { [D() setBool:v forKey:@"sidebarHidden"]; }

+ (NSDictionary<NSString *, NSString *> *)shortcuts {
    id v = [D() objectForKey:@"shortcuts"];
    if (![v isKindOfClass:NSDictionary.class]) return @{};
    for (id key in v) {   // one bad entry rejects the whole dictionary, like the other stored lists
        if (![key isKindOfClass:NSString.class] || ![v[key] isKindOfClass:NSString.class]) return @{};
    }
    return v;
}
+ (void)setShortcuts:(NSDictionary<NSString *, NSString *> *)v { [self store:v.count ? v : nil key:@"shortcuts"]; }

// Appearance presets

+ (NSDictionary<NSString *, NSDictionary *> *)appearancePresets {
    id v = [D() objectForKey:@"appearancePresets"];
    if (![v isKindOfClass:NSDictionary.class]) return @{};
    for (id key in v) {   // one bad entry rejects the whole dictionary, like the other stored lists
        if (![key isKindOfClass:NSString.class] || ![v[key] isKindOfClass:NSDictionary.class]) return @{};
    }
    return v;
}
+ (void)setAppearancePresets:(NSDictionary<NSString *, NSDictionary *> *)v {
    [self store:v.count ? v : nil key:@"appearancePresets"];
}

+ (NSDictionary *)currentAppearance {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *key in self.appearanceKeys) {
        if (id v = [D() objectForKey:key]) d[key] = v;
    }
    return d;
}

/// NO if a value for one of `keys` can't be stored (a null nested in it), so nothing is written halfway.
static BOOL storable(NSDictionary *values, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id v = values[key];
        if (v && v != NSNull.null &&
            ![NSPropertyListSerialization propertyList:v isValidForFormat:NSPropertyListBinaryFormat_v1_0]) return NO;
    }
    return YES;
}

+ (BOOL)applyAppearance:(NSDictionary *)values {
    if (!storable(values, self.appearanceKeys)) return NO;
    for (NSString *key in self.appearanceKeys) {
        id v = values[key];
        if (v && v != NSNull.null) [D() setObject:v forKey:key]; else [D() removeObjectForKey:key];
    }
    [D() removeObjectForKey:kLegacyTintKey];
    [self notify:@"*"];
    return YES;
}

// Export / import

+ (NSData *)exportData:(NSError **)error {
    NSMutableDictionary *out = [@{@"brookSettingsVersion": @1} mutableCopy];
    for (NSString *key in self.exportedKeys) {
        id v = [D() objectForKey:key];
        if (v) out[key] = v;
    }
    return [NSJSONSerialization dataWithJSONObject:out
                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                             error:error];
}

+ (BOOL)importData:(NSData *)data error:(NSError **)error {
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![obj isKindOfClass:NSDictionary.class] || !obj[@"brookSettingsVersion"]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
        return NO;
    }
    // Check every value before writing any: a value that isn't a property list would throw
    // halfway through the loop below and leave a partial import.
    if (!storable(obj, self.exportedKeys)) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
        return NO;
    }
    for (NSString *key in self.exportedKeys) {
        id v = obj[key];
        if (v && v != NSNull.null) [D() setObject:v forKey:key]; else [D() removeObjectForKey:key];
    }
    id legacyTint = obj[kLegacyTintKey];
    if (!obj[@"spaceTint"] && [legacyTint isKindOfClass:NSNumber.class]) {
        [D() setObject:@([legacyTint doubleValue] / kLegacyTintScale) forKey:@"spaceTint"];
    }
    [D() removeObjectForKey:kLegacyTintKey];
    [self notify:@"*"];
    return YES;
}

+ (void)resetAll {
    for (NSString *key in self.exportedKeys) [D() removeObjectForKey:key];
    [self notify:@"*"];
}

@end

// MARK: - Search engines

@implementation SearchEngine

+ (instancetype)engineWithID:(NSString *)identifier name:(NSString *)name urlTemplate:(NSString *)t keyword:(NSString *)k {
    SearchEngine *e = [self new];
    e.identifier = identifier;
    e.name = name;
    e.urlTemplate = t;
    e.keyword = k;
    return e;
}

- (id)copyWithZone:(NSZone *)zone {
    return [SearchEngine engineWithID:_identifier name:_name urlTemplate:_urlTemplate keyword:_keyword];
}

- (NSURL *)urlForQuery:(NSString *)query {
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&+=?#"];
    NSString *q = [query stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: query;
    return [NSURL URLWithString:[_urlTemplate stringByReplacingOccurrencesOfString:@"%s" withString:q]];
}

- (BOOL)isValid {
    if (![_urlTemplate containsString:@"%s"]) return NO;
    NSURL *u = [NSURL URLWithString:[_urlTemplate stringByReplacingOccurrencesOfString:@"%s" withString:@"x"]];
    return BrookHost(u) != nil;
}

+ (NSArray<SearchEngine *> *)builtIn {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            [self engineWithID:@"duckduckgo" name:@"DuckDuckGo" urlTemplate:@"https://duckduckgo.com/?q=%s" keyword:@"d"],
            [self engineWithID:@"google" name:@"Google" urlTemplate:@"https://www.google.com/search?q=%s" keyword:@"g"],
            [self engineWithID:@"bing" name:@"Bing" urlTemplate:@"https://www.bing.com/search?q=%s" keyword:@"b"],
            [self engineWithID:@"brave" name:@"Brave Search" urlTemplate:@"https://search.brave.com/search?q=%s" keyword:@"br"],
            [self engineWithID:@"kagi" name:@"Kagi" urlTemplate:@"https://kagi.com/search?q=%s" keyword:@"k"],
            [self engineWithID:@"youtube" name:@"YouTube" urlTemplate:@"https://www.youtube.com/results?search_query=%s" keyword:@"yt"],
            [self engineWithID:@"wikipedia" name:@"Wikipedia" urlTemplate:@"https://en.wikipedia.org/wiki/Special:Search?search=%s" keyword:@"w"],
        ];
    });
    return list;
}

+ (instancetype)fromJSON:(NSDictionary *)json {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    NSString *i = json[@"id"], *n = json[@"name"], *t = json[@"template"], *k = json[@"keyword"];
    if (![i isKindOfClass:NSString.class] || ![n isKindOfClass:NSString.class] ||
        ![t isKindOfClass:NSString.class] || ![k isKindOfClass:NSString.class]) return nil;
    return [self engineWithID:i name:n urlTemplate:t keyword:k];
}

- (NSDictionary *)toJSON {
    return @{@"id": _identifier ?: @"", @"name": _name ?: @"", @"template": _urlTemplate ?: @"", @"keyword": _keyword ?: @""};
}

@end

@implementation SearchEngines

static NSArray<SearchEngine *> *sEngineCache;

+ (NSArray<SearchEngine *> *)all {
    if (sEngineCache) return sEngineCache;
    NSArray *json = [Settings jsonForKey:@"searchEngines"];
    NSMutableArray *list = [NSMutableArray array];
    BOOL ok = [json isKindOfClass:NSArray.class];
    for (id item in ok ? json : @[]) {
        SearchEngine *e = [SearchEngine fromJSON:item];
        if (!e) { ok = NO; break; }   // one bad element rejects the whole list
        [list addObject:e];
    }
    sEngineCache = (ok && list.count) ? [list copy] : SearchEngine.builtIn;
    return sEngineCache;
}

+ (void)setAll:(NSArray<SearchEngine *> *)all {
    sEngineCache = [all copy];
    NSMutableArray *json = [NSMutableArray array];
    for (SearchEngine *e in all) [json addObject:e.toJSON];
    [Settings setJSON:json forKey:@"searchEngines"];
}

+ (void)invalidate { sEngineCache = nil; }

+ (SearchEngine *)engineWithID:(NSString *)identifier {
    if (!identifier) return nil;
    for (SearchEngine *e in self.all) if ([e.identifier isEqualToString:identifier]) return e;
    return nil;
}

+ (SearchEngine *)defaultEngine {
    return [self engineWithID:Settings.defaultSearchEngine] ?: self.all.firstObject ?: SearchEngine.builtIn[0];
}

+ (SearchEngine *)current {
    return [self engineWithID:BrowserState.shared.currentSpace.searchEngineID] ?: self.defaultEngine;
}

+ (SearchEngine *)keywordMatch:(NSString *)input query:(NSString **)query {
    NSString *text = BrookTrim(input);
    NSRange space = [text rangeOfString:@" "];
    if (space.location == NSNotFound) return nil;
    NSString *word = [text substringToIndex:space.location].lowercaseString;
    NSString *rest = BrookTrim([text substringFromIndex:space.location]);
    if (rest.length == 0) return nil;
    for (SearchEngine *e in self.all) {
        if (e.keyword.length && [e.keyword.lowercaseString isEqualToString:word]) {
            if (query) *query = rest;
            return e;
        }
    }
    return nil;
}

+ (NSURL *)searchURLForInput:(NSString *)input {
    NSString *query;
    SearchEngine *engine = [self keywordMatch:input query:&query];
    NSURL *url = engine ? [engine urlForQuery:query] : nil;
    if (url) return url;
    return [self.current urlForQuery:input] ?: [SearchEngine.builtIn[0] urlForQuery:input];
}

@end

// MARK: - Closure actions for controls

@interface BrookControlAction : NSObject
@property (copy) void (^handler)(id sender);
@end

@implementation BrookControlAction
- (void)run:(id)sender { if (_handler) _handler(sender); }
@end

static char kControlActionKey;

@implementation NSControl (BrookAction)

- (void)brook_onAction:(void (^)(id sender))handler {
    BrookControlAction *action = [BrookControlAction new];
    action.handler = handler;
    objc_setAssociatedObject(self, &kControlActionKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.target = action;
    self.action = @selector(run:);
}

@end

@implementation NSMenuItem (BrookAction)

+ (instancetype)brook_itemWithTitle:(NSString *)title action:(void (^)(void))handler {
    NSMenuItem *item = [[self alloc] initWithTitle:title action:@selector(run:) keyEquivalent:@""];
    BrookControlAction *action = [BrookControlAction new];
    action.handler = ^(id) { handler(); };
    objc_setAssociatedObject(item, &kControlActionKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    item.target = action;
    return item;
}

@end
