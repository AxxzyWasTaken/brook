#import "Brook.h"
#import <objc/runtime.h>
#include <cassert>
#include <cstdio>
#include <malloc/malloc.h>
#include <sys/resource.h>
#include <pthread/qos.h>

@interface NSView (UICheck)
- (void)refresh:(BrowserTab *)tab;
- (void)updateEdgeFade;
- (instancetype)initWithTab:(BrowserTab *)tab;
- (instancetype)initWithContext:(WKWebExtensionContext *)context size:(CGFloat)size;
- (void)refresh;
- (void)refreshForTab:(BrowserTab *)tab;
@end

@interface ChromeMorph (UICheck)
- (void)tick:(CADisplayLink *)link;
@end

@interface CommandBarController (BrowserCheck)
- (void)rebuild;
- (void)layoutPanel;
@end

@interface TopBarView (SpaceCheck)
- (void)endEditingAddress;
@end

@interface BrowserWindowController (TimingCheck)
- (void)endChromeMorphAnimated:(BOOL)animated;
@end

@interface FixtureTab : BrowserTab
@property BOOL loading;
@end
@implementation FixtureTab
- (BOOL)isLoading { return _loading; }
- (BOOL)isLoaded { return YES; }
@end

@interface FixtureExtensionItem : NSObject
@property NSImage *icon;
@property NSString *label;
@property NSString *displayName;
@property NSString *badgeText;
@property (getter=isEnabled) BOOL enabled;
@end
@implementation FixtureExtensionItem
- (NSImage *)iconForSize:(NSSize)size { return self.icon; }
@end

@interface FixtureExtensionContext : NSObject
@property FixtureExtensionItem *action;
@property FixtureExtensionItem *webExtension;
@end
@implementation FixtureExtensionContext
- (id)actionForTab:(BrowserTab *)tab { return self.action; }
@end

static void ReplaceClassMethod(Class cls, SEL selector, id block) {
    Method method = class_getClassMethod(cls, selector);
    assert(method);
    method_setImplementation(method, imp_implementationWithBlock(block));
}

static int measuredRuns = 15, warmupRuns = 4;
static int settleTimeouts = 0;
static dispatch_block_t beforeSample;
static BOOL offscreen = NO;

static void BlockWindowPresentation(void) {
    auto replace = [](Class cls, SEL selector, id block) {
        Method method = class_getInstanceMethod(cls, selector);
        assert(method);
        method_setImplementation(method, imp_implementationWithBlock(block));
    };
    for (NSString *name in @[@"orderFront:", @"orderBack:", @"makeKeyAndOrderFront:"]) {
        replace(NSWindow.class, NSSelectorFromString(name), ^(id self, id sender) {});
    }
    for (NSString *name in @[@"orderFrontRegardless", @"makeKeyWindow", @"makeMainWindow"]) {
        replace(NSWindow.class, NSSelectorFromString(name), ^(id self) {});
    }
    replace(NSWindow.class, @selector(orderWindow:relativeTo:), ^(id self, NSWindowOrderingMode order, NSInteger other) {});
    replace(NSWindow.class, @selector(addChildWindow:ordered:), ^(id self, NSWindow *child, NSWindowOrderingMode order) {});
    replace(NSApplication.class, @selector(activate), ^(id self) {});
    replace(NSApplication.class, @selector(activateIgnoringOtherApps:), ^(id self, BOOL flag) {});
}

static void CheckNoVisibleWindows(void) {
    for (NSWindow *window in NSApp.windows) assert(!window.isVisible && !window.isKeyWindow);
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *window in windows) assert([window[(id)kCGWindowOwnerPID] intValue] != NSProcessInfo.processInfo.processIdentifier);
}

static NSArray<NSNumber *> *Measure(dispatch_block_t work, dispatch_block_t prepare = nil, int repetitions = 1) {
    NSMutableArray *samples = [NSMutableArray array];
    for (int run = 0; run < warmupRuns + measuredRuns; ++run) {
        @autoreleasepool {
            if (prepare) prepare();
            if (beforeSample) beforeSample();
            CFTimeInterval start = CACurrentMediaTime();
            for (int i = 0; i < repetitions; ++i) work();
            double ms = (CACurrentMediaTime() - start) * 1000 / repetitions;
            if (run >= warmupRuns) [samples addObject:@(ms)];
        }
    }
    return samples;
}

static void Capture(NSView *view, NSString *name, NSURL *directory);
static void CheckMotion(NSView *host, NSView *sibling);

static void CheckColors(NSMutableDictionary *results) {
    NSView *view = [NSView new];
    NSArray<NSColor *> *colors = @[NSColor.labelColor, NSColor.textBackgroundColor, NSColor.windowBackgroundColor,
                                  Palette.divider, Palette.well, NSColor.controlAccentColor];
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
                                   NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
        view.appearance = [NSAppearance appearanceNamed:appearance];
        NSAppearance *outer = NSAppearance.currentDrawingAppearance;
        for (NSColor *color in colors) {
            CGColorRef actual = [view brook_cg:color];
            [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
                assert(CGColorEqualToColor(actual, color.CGColor));
            }];
            assert(NSAppearance.currentDrawingAppearance == outer);
        }
        results[[@"color_resolution_10000_" stringByAppendingString:appearance]] = Measure(^{
            for (int i = 0; i < 10000; ++i) assert([view brook_cg:colors[i % colors.count]]);
        });
    }
}

static void CheckCommandBarRows(NSURL *directory, NSMutableDictionary *results) {
    CommandBarController *bar = [[CommandBarController alloc] initWithBrowser:nil];
    NSPanel *panel = [bar valueForKey:@"panel"];
    [panel setContentSize:NSMakeSize(660, 360)];
    NSTextField *input = [bar valueForKey:@"input"];
    NSTableView *table = [bar valueForKey:@"table"];
    input.stringValue = @"";
    [bar rebuild];
    [panel.contentView layoutSubtreeIfNeeded];
    assert(table.numberOfRows == 6);
    results[@"command_bar_recent_rows_100"] = Measure(^{
        for (int i = 0; i < 100; ++i) {
            [bar rebuild];
            [panel.contentView layoutSubtreeIfNeeded];
            assert(table.numberOfRows == 6 && table.selectedRow == 0);
        }
    });
    NSArray<BrowserTab *> *tabs = BrowserState.shared.visibleTabs;
    NSMutableArray *titles = [NSMutableArray array];
    for (BrowserTab *tab in tabs) {
        [titles addObject:tab.title ?: @""];
        [tab setValue:@"Updated suggestion title" forKey:@"title"];
    }
    [bar rebuild];
    [table layoutSubtreeIfNeeded];
    for (NSInteger row = 0; row < 6; ++row) {
        NSView *cell = [table viewAtColumn:0 row:row makeIfNecessary:YES];
        assert([[(NSTextField *)[cell valueForKey:@"title"] stringValue] isEqualToString:@"Updated suggestion title"]);
    }
    for (NSUInteger i = 0; i < tabs.count; ++i) [tabs[i] setValue:titles[i] forKey:@"title"];
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        panel.appearance = [NSAppearance appearanceNamed:appearance];
        for (NSString *query in @[@"", @"passwords", @"import passwords", @""]) {
            input.stringValue = query;
            [bar rebuild];
            [panel.contentView layoutSubtreeIfNeeded];
            assert(table.numberOfRows > 0 && table.selectedRow == 0);
            [table selectRowIndexes:[NSIndexSet indexSetWithIndex:table.numberOfRows - 1] byExtendingSelection:NO];
            [panel.contentView layoutSubtreeIfNeeded];
            Capture(panel.contentView, [NSString stringWithFormat:@"command-rows-%@-%@", appearance,
                                        query.length ? query : @"recent"], directory);
            for (NSInteger row = 0; row < table.numberOfRows; ++row) {
                NSTableRowView *view = [table rowViewAtRow:row makeIfNecessary:YES];
                assert(view.selected == (row == table.selectedRow));
            }
        }
    }
}

static void SaveCheckJSON(id object, NSURL *directory, NSString *name) {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    assert(json && !error);
    assert([json writeToURL:[directory URLByAppendingPathComponent:name] atomically:YES]);
}

static void CheckMenuItemBehavior(void) {
    const NSEventModifierFlags masks[] = {0, NSEventModifierFlagCommand, NSEventModifierFlagControl,
                                         NSEventModifierFlagShift | NSEventModifierFlagCommand};
    for (NSString *key in @[@"", @"a", @"1"]) {
        NSMenuItem *native = [[NSMenuItem alloc] initWithTitle:@"Default" action:nil keyEquivalent:key];
        assert(native.keyEquivalentModifierMask == NSEventModifierFlagCommand);
        for (NSEventModifierFlags modifiers : masks) {
            __block int calls = 0;
            ClosureMenuItem *item = [[ClosureMenuItem alloc] initWithTitle:@"Test" key:key modifiers:modifiers handler:^{ ++calls; }];
            assert([item.keyEquivalent isEqual:key] && item.keyEquivalentModifierMask == modifiers);
            assert([NSApp sendAction:item.action to:item.target from:item] && calls == 1);
        }
    }
}

static NSMutableDictionary<NSString *, HistoryEntry *> *HistoryFixture(NSUInteger count) {
    NSMutableDictionary *entries = [NSMutableDictionary dictionaryWithCapacity:count];
    for (NSUInteger i = 0; i < count; ++i) {
        HistoryEntry *entry = [HistoryEntry new];
        entry.url = [NSString stringWithFormat:@"https://www.site%05lu.example.test/docs/%lu?ref=www.test", i, i % 97];
        entry.title = [NSString stringWithFormat:@"%@ Guide %05lu Café 日本語", i % 3 ? @"Browser" : @"Reference", i];
        entry.visits = 1 + i % 101;
        entry.last = [NSDate dateWithTimeIntervalSince1970:1790726400 - i * 3600];
        entries[entry.url] = entry;
    }
    return entries;
}

static NSArray<HistoryEntry *> *ReferenceSearch(NSDictionary<NSString *, HistoryEntry *> *entries, NSString *query, NSInteger limit) {
    NSString *q = BrookTrim(query.lowercaseString);
    if (!q.length) return @[];
    NSDate *now = [NSDate date];
    std::vector<std::pair<HistoryEntry *, double>> scored;
    for (HistoryEntry *e in entries.objectEnumerator) {
        NSString *u = e.url.lowercaseString, *t = e.title.lowercaseString;
        NSString *stripped = [[[u stringByReplacingOccurrencesOfString:@"https://" withString:@""]
                                  stringByReplacingOccurrencesOfString:@"http://" withString:@""]
                                  stringByReplacingOccurrencesOfString:@"www." withString:@""];
        double score;
        if ([stripped hasPrefix:q]) score = 4;
        else if ([t hasPrefix:q]) score = 3;
        else if ([u containsString:q] || [t containsString:q]) score = 1;
        else continue;
        score *= log2((double)e.visits + 1) + 1;
        score /= 1 + [now timeIntervalSinceDate:e.last] / 86400 / 14;
        scored.emplace_back(e, score);
    }
    std::stable_sort(scored.begin(), scored.end(), [](const auto &a, const auto &b) { return a.second > b.second; });
    NSMutableArray *out = [NSMutableArray array];
    for (size_t i = 0; i < scored.size() && (NSInteger)i < limit; ++i) [out addObject:scored[i].first];
    return out;
}

static void CheckHistory(NSURL *directory, NSMutableDictionary *results, NSMutableDictionary *details) {
    NSArray<NSString *> *queries = @[@"", @"  ", @" SITE000 ", @"browser", @"café", @"日本", @"no-match-zyx", @"https://", @"www."];
    HistoryStore *store = [HistoryStore new];
    NSMutableDictionary *entries = HistoryFixture(1000);
    [store setValue:entries forKey:@"entries"];
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1790812800];
    Method date = class_getClassMethod(NSDate.class, @selector(date));
    IMP frozen = imp_implementationWithBlock(^id(id self) { return now; });
    IMP original = method_setImplementation(date, frozen);
    auto verify = [&] {
        for (NSString *query in queries) {
            for (NSInteger limit : {-1, 0, 1, 5, 6, 2000}) {
                assert([[store search:query limit:limit] isEqualToArray:ReferenceSearch(entries, query, limit)]);
            }
        }
    };
    verify();
    HistoryEntry *entry = entries[@"https://www.site00000.example.test/docs/0?ref=www.test"];
    NSMutableString *title = [@"Browser changed Café" mutableCopy];
    entry.title = title;
    [title setString:@"mutation must not leak"];
    assert([entry.title isEqualToString:@"Browser changed Café"]);
    entry.url = @"http://www.site00099.example.test/https://www.path";
    entry.visits = 999;
    entry.last = now;
    verify();
    entry.title = nil;
    entry.url = nil;
    verify();
    [entries removeObjectForKey:@"https://www.site00000.example.test/docs/0?ref=www.test"];
    NSURL *url = [NSURL URLWithString:@"https://www.site00042.example.test/new"];
    [store recordURL:url title:@"Browser new Café"];
    verify();
    [store updateTitle:@"Reference new 日本語" forURL:url];
    verify();
    for (HistoryEntry *e in entries.objectEnumerator) { e.visits = 1; e.last = now; e.title = @"Browser tie"; }
    verify();
    [store setValue:@10 forKey:@"limit"];
    [store saveNow];
    BrookFinishBackgroundWrites();
    assert(entries.count == 10);
    verify();
    HistoryStore *reloaded = [HistoryStore new];
    assert([(NSDictionary *)[reloaded valueForKey:@"entries"] count] == 10);
    [store clear];
    BrookFinishBackgroundWrites();
    assert([store search:@"browser"].count == 0);
    assert([(NSDictionary *)[[HistoryStore new] valueForKey:@"entries"] count] == 0);
    method_setImplementation(date, original);
    imp_removeBlock(frozen);
    for (NSUInteger count : {1000, 20000}) {
        store = [HistoryStore new];
        [store setValue:HistoryFixture(count) forKey:@"entries"];
        for (NSString *query in @[@"site000", @"browser", @"café", @"no-match-zyx"]) {
            results[[NSString stringWithFormat:@"history_%lu_%@_query", count, query]] = Measure(^{
                NSArray *found = [store search:query limit:5];
                assert(found.count == ([query isEqualToString:@"no-match-zyx"] ? 0 : 5));
            });
        }
    }
    __block HistoryStore *cold;
    results[@"history_20000_first_query"] = Measure(^{
        assert([cold search:@"browser" limit:5].count == 5);
    }, ^{
        cold = [HistoryStore new];
        [cold setValue:HistoryFixture(20000) forKey:@"entries"];
    });
    HistoryStore *memory = [HistoryStore new];
    @autoreleasepool { [memory setValue:HistoryFixture(20000) forKey:@"entries"]; }
    malloc_statistics_t before{}, after{};
    malloc_zone_statistics(nullptr, &before);
    @autoreleasepool { assert([memory search:@"browser" limit:5].count == 5); }
    malloc_zone_statistics(nullptr, &after);
    details[@"history_first_search_allocator_delta_bytes"] = @((int64_t)after.size_in_use - (int64_t)before.size_in_use);
    details[@"history_entry_instance_bytes"] = @(class_getInstanceSize(HistoryEntry.class));
    details[@"history_correctness"] = @"Original ranking oracle: Unicode, whitespace, misses, limits, property replacement, mutable-string copying, visits/age changes, ties, record/update, prune, persistence and clear passed.";
    ReplaceClassMethod(HistoryStore.class, @selector(shared), ^id(id self) { return store; });
}

static void WaitFor(BOOL (^done)(void)) {
    CFTimeInterval deadline = CACurrentMediaTime() + 15;
    while (!done() && CACurrentMediaTime() < deadline) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:NSDate.distantPast
                                             inMode:NSDefaultRunLoopMode dequeue:YES];
        if (event) [NSApp sendEvent:event];
        [NSApp updateWindows];
    }
    assert(done());
}

static id PageScript(WKWebView *view, NSString *script) {
    __block BOOL finished = NO;
    __block id result;
    __block NSError *failure;
    [view callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
           completionHandler:^(id value, NSError *error) { result = value; failure = error; finished = YES; }];
    WaitFor(^BOOL { return finished; });
    if (failure) NSLog(@"Page script failed: %@", failure);
    assert(!failure);
    return result;
}

static void FlushBrowser(BrowserWindowController *browser) {
    [browser.window.contentView layoutSubtreeIfNeeded];
    [browser.window.contentView displayIfNeeded];
    [CATransaction flush];
}

static void PumpFor(NSTimeInterval duration) {
    CFTimeInterval end = CACurrentMediaTime() + duration;
    WaitFor(^BOOL { return CACurrentMediaTime() >= end; });
}

static void SettleBrowser(BrowserWindowController *browser) {
    CFTimeInterval end = CACurrentMediaTime() + 1.5;
    while ([browser valueForKey:@"morph"] && CACurrentMediaTime() < end) PumpFor(0.01);
    if ([browser valueForKey:@"morph"]) {
        ++settleTimeouts;
        [browser endChromeMorphAnimated:NO];
    }
    PumpFor(0.04);
    FlushBrowser(browser);
}

static void ConfigureBrowserCheck(NSUserDefaults *defaults, NSMutableDictionary *options) {
    for (Class cls in @[SiteNotifications.class, PasswordAutofill.class]) {
        ReplaceClassMethod(cls, @selector(shared), ^id(id self) { return nil; });
    }
    WKWebsiteDataStore *webData = [WKWebsiteDataStore nonPersistentDataStore];
    WKProcessPool *pool = [WKProcessPool new];
    ReplaceClassMethod(WebViewFactory.class, @selector(makeConfigurationWithProfileID:autoplay:),
                       ^id(id self, NSUUID *profile, AutoplayPolicy autoplay) {
        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        config.websiteDataStore = webData;
        config.processPool = pool;
        return config;
    });
    options[@"commandBarSuggestions"] = @NO;
    options[@"commandBarHistory"] = @YES;
    options[@"commandBarTabs"] = @YES;
    options[@"sidebarHidden"] = @NO;
    options[@"autoHide"] = @"never";
    options[@"launchBehavior"] = @"restore";
    options[@"appIcon"] = @"default";
    options[@"blockCookiePopups"] = @NO;
    [defaults setVolatileDomain:options forName:NSArgumentDomain];
    Method autosave = class_getInstanceMethod(NSWindow.class, @selector(setFrameAutosaveName:));
    method_setImplementation(autosave, imp_implementationWithBlock(^BOOL(id self, NSString *name) { return NO; }));
}

static void WriteSessionFixture(NSURL *directory) {
    NSMutableArray *spaces = [NSMutableArray array];
    for (int s = 0; s < 2; ++s) {
        NSMutableArray *tabs = [NSMutableArray array];
        for (int i = 0; i < 100; ++i) {
            [tabs addObject:@{@"id":NSUUID.UUID.UUIDString, @"title":[NSString stringWithFormat:@"Page %d-%d", s, i]}];
        }
        [spaces addObject:@{@"id":NSUUID.UUID.UUIDString, @"name":[NSString stringWithFormat:@"Space %d", s],
                            @"color":@"8B5CF6", @"tabs":tabs}];
    }
    SaveCheckJSON(@{@"spaces":spaces, @"currentSpace":@0}, directory, @"session.json");
}

static void CheckStartup(NSURL *directory, NSUserDefaults *defaults, NSMutableDictionary *options) {
    ConfigureBrowserCheck(defaults, options);
    WriteSessionFixture(directory);
    NSString *path = NSProcessInfo.processInfo.environment[@"BROOK_UI_CHECK_BUNDLE"];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    assert(bundle);
    ReplaceClassMethod(NSBundle.class, @selector(mainBundle), ^id(id self) { return bundle; });
    AppDelegate *delegate = [AppDelegate new];
    NSApp.delegate = delegate;
    NSNotification *willLaunch = [NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification object:NSApp];
    NSNotification *didLaunch = [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp];
    CFTimeInterval start = CACurrentMediaTime();
    [delegate applicationWillFinishLaunching:willLaunch];
    [delegate applicationDidFinishLaunching:didLaunch];
    BrowserWindowController *browser = [delegate valueForKey:@"windowController"];
    FlushBrowser(browser);
    double elapsed = (CACurrentMediaTime() - start) * 1000;
    assert(BrowserState.shared.allTabs.count == 200 && browser.window.visible == !offscreen);
    SaveCheckJSON(@{@"startup_to_first_window_submission_ms":@(elapsed)}, directory, @"startup.json");
    [browser.window orderOut:nil];
    NSApp.delegate = nil;
    if (offscreen) CheckNoVisibleWindows();
    puts("Fresh-process startup check passed.");
}

static void CheckSettings(NSURL *directory, NSMutableDictionary *results, NSMutableDictionary *details) {
    SettingsWindowController *settings = SettingsWindowController.shared;
    NSTabViewController *tabs = [settings valueForKey:@"tabs"];
    BOOL (^settled)(void) = ^BOOL {
        NSViewController *selected = tabs.tabView.selectedTabViewItem.viewController;
        if (!selected || selected.view.window != settings.window) return NO;
        for (NSTabViewItem *item in tabs.tabViewItems) {
            NSViewController *other = item.viewController;
            if (other != selected && other.isViewLoaded && other.view.window == settings.window) return NO;
        }
        return YES;
    };
    __block NSUInteger previousPending = 0, preparationPending = 0;
    BOOL focused = [NSProcessInfo.processInfo.environment[@"BROOK_CHECK_FOCUSED_SETTINGS"] isEqualToString:@"1"];
    for (NSString *pane in @[@"General", @"Appearance", @"Layout", @"Tabs", @"Search", @"Websites", @"Passwords", @"Boosts", @"Shortcuts", @"Advanced"]) {
        if (focused && ![pane isEqual:@"Appearance"] && ![pane isEqual:@"Layout"]) continue;
        results[[@"settings_" stringByAppendingString:pane.lowercaseString]] = Measure(^{
            [settings showPane:pane];
            [settings.window.contentView layoutSubtreeIfNeeded];
            [settings.window.contentView displayIfNeeded];
            assert(settings.window.visible == !offscreen);
            NSTabViewController *tabs = [settings valueForKey:@"tabs"];
            assert([tabs.tabViewItems[tabs.selectedTabViewItemIndex].label isEqualToString:pane]);
        }, ^{
            if (!settled()) ++previousPending;
            WaitFor(settled);
            [settings showPane:[pane isEqualToString:@"General"] ? @"Appearance" : @"General"];
            PumpFor(0.3);
            if (!settled()) ++preparationPending;
            WaitFor(settled);
            [settings.window.contentView layoutSubtreeIfNeeded];
            [settings.window.contentView displayIfNeeded];
        });
        WaitFor(settled);
        [settings.window.contentView layoutSubtreeIfNeeded];
        NSTabViewController *tabs = [settings valueForKey:@"tabs"];
        assert(tabs.tabView.selectedTabViewItem.viewController.view.window == settings.window);
        Capture(settings.window.contentView, [@"settings-" stringByAppendingString:pane.lowercaseString], directory);
        [settings.window orderOut:nil];
    }
    details[@"settings_pending_previous_request"] = @(previousPending);
    details[@"settings_pending_after_300ms"] = @(preparationPending);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *saved = [defaults volatileDomainForName:NSArgumentDomain];
    for (NSString *font in @[@"system", @"rounded", @"serif", @"mono"]) {
        NSMutableDictionary *options = [saved mutableCopy];
        options[@"uiFont"] = font;
        [defaults setVolatileDomain:options forName:NSArgumentDomain];
        [NSNotificationCenter.defaultCenter postNotificationName:BrookSettingsDidChangeNotification object:nil
                                                        userInfo:@{@"key":@"uiFont"}];
        [settings.window.contentView layoutSubtreeIfNeeded];
        Capture(settings.window.contentView, [@"settings-font-" stringByAppendingString:font], directory);
    }
    [defaults setVolatileDomain:saved forName:NSArgumentDomain];
    [NSNotificationCenter.defaultCenter postNotificationName:BrookSettingsDidChangeNotification object:nil
                                                    userInfo:@{@"key":@"uiFont"}];
}

static void CheckMenus(BrowserWindowController *browser, NSMutableDictionary *results, int repetitions) {
    BrowserState *state = BrowserState.shared;
    BrowserTab *first = state.selectedTab;
    results[@"tab_context_menu"] = Measure(^{ assert([browser menuForTab:first].numberOfItems > 0); }, nil, repetitions);
    results[@"space_context_menu"] = Measure(^{ assert([browser menuForSpace:state.currentSpace].numberOfItems > 0); }, nil, repetitions);
    results[@"spaces_menu"] = Measure(^{ assert(browser.spacesMenu.numberOfItems > 0); }, nil, repetitions);
}

static void CheckBrowserFeatures(BrowserWindowController *browser, NSURL *directory,
                                 NSMutableDictionary *results, NSMutableDictionary *details) {
    BrowserState *state = BrowserState.shared;
    BrowserTab *first = state.selectedTab;
    NSUInteger count = state.allTabs.count;
    CheckMenus(browser, results, 100);
    results[@"command_bar_open_close"] = Measure(^{
        [browser.commandBar showEditingCurrent:YES];
        assert(browser.commandBar.isVisible == !offscreen);
        [browser.commandBar dismiss];
        assert(!browser.commandBar.isVisible);
    });
    results[@"find_bar_open_close"] = Measure(^{
        [browser showFind];
        FlushBrowser(browser);
        assert(!browser.content.findBar.hidden);
        [browser.content.findBar close];
        assert(browser.content.findBar.hidden);
    });
    results[@"pin_unpin_tab"] = Measure(^{
        [state togglePin:first];
        FlushBrowser(browser);
        assert(first.isPinned && [state.currentSpace.pinned containsObject:first]);
        [state togglePin:first];
        FlushBrowser(browser);
        assert(!first.isPinned && [state.currentSpace.tabs containsObject:first]);
    });
    results[@"favorite_unfavorite_tab"] = Measure(^{
        [state toggleFavorite:first];
        FlushBrowser(browser);
        assert(first.isFavorite && [state.favorites containsObject:first]);
        [state toggleFavorite:first];
        FlushBrowser(browser);
        assert(!first.isFavorite && [state.currentSpace.tabs containsObject:first]);
    });
    BrowserTab *second = state.currentSpace.tabs[1];
    results[@"split_open_swap_close"] = Measure(^{
        [state openInSplit:second];
        FlushBrowser(browser);
        TabSplit *split = state.activeSplit;
        assert(split && [split contains:first] && [split contains:second]);
        BrowserTab *left = split.left;
        [state swapSplit];
        assert(split.right == left);
        [state focusPaneOnLeft:YES];
        assert(state.selectedTab == split.left);
        [state setSplitFraction:0.01];
        assert(split.fraction == 0.2);
        [state setSplitFraction:0.99];
        assert(split.fraction == 0.8);
        [state separateSplit];
        [state selectTab:first];
        FlushBrowser(browser);
        assert(!state.activeSplit);
    });
    [state selectIndex:0];
    assert(state.selectedTab == state.visibleTabs.firstObject);
    [state selectNext:1];
    assert(state.selectedTab == state.visibleTabs[1]);
    [state selectNext:-1];
    assert(state.selectedTab == state.visibleTabs.firstObject);
    [state selectIndex:8];
    assert(state.selectedTab == state.visibleTabs.lastObject);
    [state selectTab:first];
    BrowserTab *temporary = [state openTabWithURL:nil];
    [temporary setValue:[NSURL URLWithString:@"https://fixture.example.test/reopen"] forKey:@"url"];
    [state close:temporary];
    assert(state.canReopenClosedTab && state.allTabs.count == count);
    [state reopenClosedTab];
    assert([state.selectedTab.url.absoluteString isEqualToString:@"https://fixture.example.test/reopen"]);
    [state remove:state.selectedTab];
    [state selectTab:first];
    assert(state.allTabs.count == count);
    CheckSettings(directory, results, details);
    [browser.window makeKeyAndOrderFront:nil];
    details[@"additional_correctness"] = @"Tab/space menus, command-bar editing and dismissal, find-bar opening and closing, pin/unpin, favorite/unfavorite, split creation/swap/focus/clamping/separation, keyboard tab order, close/reopen, and the requested settings panes passed using isolated data.";
}

static void CheckLiveMotion(BrowserWindowController *browser, NSUserDefaults *defaults,
                            NSMutableDictionary *options, NSMutableDictionary *details) {
    __block BOOL reduced = NO, recording = NO;
    __block NSMutableArray *intervals, *costs;
    __block CFTimeInterval last = 0;
    Method preference = class_getInstanceMethod(NSWorkspace.class, @selector(accessibilityDisplayShouldReduceMotion));
    IMP preferenceBlock = imp_implementationWithBlock(^BOOL(id self) { return reduced; });
    IMP oldPreference = method_setImplementation(preference, preferenceBlock);
    Method tick = class_getInstanceMethod(ChromeMorph.class, @selector(tick:));
    IMP oldTick = method_getImplementation(tick);
    IMP tickBlock = imp_implementationWithBlock(^(ChromeMorph *self, CADisplayLink *link) {
        CFTimeInterval start = CACurrentMediaTime();
        if (recording && last) [intervals addObject:@((start - last) * 1000)];
        if (recording) last = start;
        ((void (*)(id, SEL, CADisplayLink *))oldTick)(self, @selector(tick:), link);
        if (recording) [costs addObject:@((CACurrentMediaTime() - start) * 1000)];
    });
    method_setImplementation(tick, tickBlock);
    auto layout = [&](int value) {
        options[@"tabLayout"] = TabLayoutRaw((TabLayout)value);
        [defaults setVolatileDomain:options forName:NSArgumentDomain];
        [NSNotificationCenter.defaultCenter postNotificationName:BrookSettingsDidChangeNotification object:nil
                                                        userInfo:@{@"key":@"tabLayout"}];
        FlushBrowser(browser);
    };
    NSMutableDictionary *motions = [NSMutableDictionary dictionary];
    for (BOOL reduce : {NO, YES}) {
        reduced = reduce;
        for (int from = 0; from < 3; ++from) for (int to = 0; to < 3; ++to) {
            if (from == to) continue;
            layout(from);
            SettleBrowser(browser);
            intervals = [NSMutableArray array];
            costs = [NSMutableArray array];
            last = 0;
            recording = YES;
            CFTimeInterval start = CACurrentMediaTime();
            layout(to);
            while ([browser valueForKey:@"morph"] && CACurrentMediaTime() - start < 2) PumpFor(0.002);
            recording = NO;
            BOOL completed = [browser valueForKey:@"morph"] == nil && costs.count > 0;
            motions[[NSString stringWithFormat:@"%@_to_%@_%@", TabLayoutRaw((TabLayout)from),
                     TabLayoutRaw((TabLayout)to), reduce ? @"reduced" : @"normal"]] = @{
                @"completed":@(completed), @"duration_ms":@((CACurrentMediaTime() - start) * 1000),
                @"callback_intervals_ms":intervals, @"callback_work_ms":costs,
                @"occlusion_visible":@((browser.window.occlusionState & NSWindowOcclusionStateVisible) != 0)};
            if (!completed) [browser endChromeMorphAnimated:NO];
        }
    }
    method_setImplementation(tick, oldTick);
    imp_removeBlock(tickBlock);
    method_setImplementation(preference, oldPreference);
    imp_removeBlock(preferenceBlock);
    details[@"live_motions"] = motions;
}

static void CheckFivePaths(BrowserWindowController *browser, NSURL *directory, NSUserDefaults *defaults,
                           NSMutableDictionary *options, NSMutableDictionary *results, NSMutableDictionary *details) {
    assert(offscreen);
    BOOL paired = [NSProcessInfo.processInfo.environment[@"BROOK_CHECK_PAIRED_METHODS"] isEqualToString:@"1"];
    BOOL control = [NSProcessInfo.processInfo.environment[@"BROOK_CHECK_PAIRED_CONTROL"] isEqualToString:@"1"];
    struct Implementation { Method method; IMP before; IMP after; };
    std::vector<Implementation> implementations;
    if (paired) {
        NSDictionary<NSString *, NSArray<NSString *> *> *selectors = @{
            @"SidebarView": @[@"tabChanged:change:"], @"TopBarView": @[@"tabChanged:change:"],
            @"CommandBarController": @[@"showEditingCurrent:", @"layoutPanel"], @"FindBar": @[@"focus"],
            @"TabStripView": @[@"updateEdgeFade"]};
        for (NSString *name in selectors) {
            Class current = NSClassFromString(name), original = NSClassFromString([@"BrookBefore" stringByAppendingString:name]);
            assert(current && original && class_getInstanceSize(current) == class_getInstanceSize(original));
            unsigned count = 0;
            Ivar *ivars = class_copyIvarList(current, &count);
            for (unsigned i = 0; i < count; ++i) {
                Ivar other = class_getInstanceVariable(original, ivar_getName(ivars[i]));
                assert(other && ivar_getOffset(other) == ivar_getOffset(ivars[i]));
            }
            free(ivars);
            for (NSString *selector in selectors[name]) {
                Method method = class_getInstanceMethod(current, NSSelectorFromString(selector));
                Method previous = class_getInstanceMethod(original, NSSelectorFromString(selector));
                assert(method && previous && strcmp(method_getTypeEncoding(method), method_getTypeEncoding(previous)) == 0);
                IMP currentImplementation = method_getImplementation(method);
                implementations.push_back({method, control ? currentImplementation : method_getImplementation(previous), currentImplementation});
            }
        }
    }
    auto activate = [&](BOOL original) {
        for (const Implementation &item : implementations) method_setImplementation(item.method, original ? item.before : item.after);
    };
    auto measure = [&](NSString *key, dispatch_block_t work, dispatch_block_t prepare = nil, int repetitions = 1) {
        if (!paired) { results[key] = Measure(work, prepare, repetitions); return; }
        NSMutableArray *before = [NSMutableArray array], *after = [NSMutableArray array];
        for (int run = 0; run < warmupRuns + measuredRuns; ++run) {
            for (int position = 0; position < 2; ++position) {
                @autoreleasepool {
                    BOOL original = (run + position) % 2 == 0;
                    activate(original);
                    if (prepare) prepare();
                    if (beforeSample) beforeSample();
                    CFTimeInterval start = CACurrentMediaTime();
                    for (int i = 0; i < repetitions; ++i) work();
                    double ms = (CACurrentMediaTime() - start) * 1000 / repetitions;
                    if (run >= warmupRuns) [(original ? before : after) addObject:@(ms)];
                }
            }
        }
        results[[key stringByAppendingString:@"_before"]] = before;
        results[[key stringByAppendingString:@"_after"]] = after;
        activate(NO);
    };
    BrowserState *state = BrowserState.shared;
    BrowserTab *tab = state.selectedTab;
    WKWebView *page = [tab materialize];
    [page loadHTMLString:@"<!doctype html><title>Targeted checks</title><p id='text'>Brook target Brook</p>" baseURL:nil];
    WaitFor(^BOOL { return !page.isLoading && [page.title isEqual:@"Targeted checks"]; });
    SettleBrowser(browser);
    beforeSample = ^{ SettleBrowser(browser); };
    measure(@"command_bar_open_close", ^{
        [browser.commandBar showEditingCurrent:YES];
        assert(!browser.commandBar.isVisible);
        [browser.commandBar dismiss];
    });
    measure(@"find_bar_open_close", ^{
        [browser showFind];
        FlushBrowser(browser);
        assert(!browser.content.findBar.hidden);
        [browser.content.findBar close];
        assert(browser.content.findBar.hidden);
    });
    FindBar *find = browser.content.findBar;
    NSSearchField *findField = [find valueForKey:@"field"];
    findField.stringValue = @"Brook";
    [browser showFind];
    assert(findField.currentEditor && browser.window.firstResponder == findField.currentEditor);
    assert(NSEqualRanges(findField.currentEditor.selectedRange, NSMakeRange(0, 5)));
    findField.currentEditor.selectedRange = NSMakeRange(1, 1);
    [browser showFind];
    assert(NSEqualRanges(findField.currentEditor.selectedRange, NSMakeRange(0, 5)));
    [find searchForward:YES];
    WaitFor(^BOOL { return [[find valueForKey:@"countedQuery"] isEqual:@"Brook"]; });
    assert([[find valueForKey:@"total"] integerValue] == 2);
    [find close];
    assert(find.hidden && browser.window.firstResponder == page);
    assert([[PageScript(page, @"return getSelection().toString()") description] length] == 0);
    findField.stringValue = @"";
    NSPanel *commandPanel = [browser.commandBar valueForKey:@"panel"];
    NSTextField *commandField = [browser.commandBar valueForKey:@"field"];
    [browser.commandBar showEditingCurrent:YES];
    assert(commandField.currentEditor && commandPanel.firstResponder == commandField.currentEditor);
    assert(NSEqualRanges(commandField.currentEditor.selectedRange, NSMakeRange(0, commandField.stringValue.length)));
    details[@"command_panel_frame"] = NSStringFromRect(commandPanel.frame);
    details[@"command_parent_frame"] = NSStringFromRect(browser.window.frame);
    details[@"command_content_min_size"] = NSStringFromSize(commandPanel.contentMinSize);
    [(NSTextView *)commandField.currentEditor setMarkedText:@"input" selectedRange:NSMakeRange(0, 5)
                                          replacementRange:NSMakeRange(NSNotFound, 0)];
    [browser.commandBar showEditingCurrent:YES];
    assert([commandField.stringValue isEqualToString:tab.url.absoluteString ?: @""]);
    assert(![(NSTextView *)commandField.currentEditor hasMarkedText]);
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
                                   NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
        browser.window.appearance = [NSAppearance appearanceNamed:appearance];
        [browser showFind];
        FlushBrowser(browser);
        Capture(browser.content.findBar, [@"five-find-" stringByAppendingString:appearance], directory);
        [browser.content.findBar close];
        NSPanel *panel = [browser.commandBar valueForKey:@"panel"];
        panel.appearance = browser.window.appearance;
        [browser.commandBar showEditingCurrent:YES];
        [panel.contentView layoutSubtreeIfNeeded];
        Capture(panel.contentView, [@"five-command-" stringByAppendingString:appearance], directory);
    }
    browser.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    SidebarView *sidebar = browser.sidebar;
    measure(@"sidebar_progress_1000", ^{
        for (int i = 0; i < 1000; ++i) [sidebar tabChanged:tab change:TabChangeProgress];
    }, nil, 1000);
    options[@"tabLayout"] = @"compact";
    [defaults setVolatileDomain:options forName:NSArgumentDomain];
    [NSNotificationCenter.defaultCenter postNotificationName:BrookSettingsDidChangeNotification object:nil
                                                    userInfo:@{@"key":@"tabLayout"}];
    SettleBrowser(browser);
    TopBarView *top = [browser valueForKey:@"chrome"];
    measure(@"top_progress_1000", ^{
        for (int i = 0; i < 1000; ++i) [top tabChanged:tab change:TabChangeProgress];
    }, nil, 1000);
    NSView *strip = [top valueForKey:@"strip"];
    NSScrollView *scroller = [strip valueForKey:@"scroll"];
    measure(@"compact_tab_list_scroll_main_thread", ^{
        [scroller.contentView scrollToPoint:NSMakePoint(300, 0)];
        [scroller reflectScrolledClipView:scroller.contentView];
        FlushBrowser(browser);
        assert(scroller.contentView.bounds.origin.x == 300);
    }, ^{
        [scroller.contentView scrollToPoint:NSZeroPoint];
        [scroller reflectScrolledClipView:scroller.contentView];
    });
    for (CGFloat x : {0., 300., 800., 0.}) {
        [scroller.contentView scrollToPoint:NSMakePoint(x, 0)];
        [scroller reflectScrolledClipView:scroller.contentView];
        FlushBrowser(browser);
        Capture(strip, [NSString stringWithFormat:@"five-scroll-%.0f", x], directory);
    }
    beforeSample = nil;
    if ([NSProcessInfo.processInfo.environment[@"BROOK_CHECK_FIVE_COMPONENTS"] isEqualToString:@"1"]) {
        for (NSString *query in @[@"", @"Brook search query"]) {
            findField.stringValue = query;
            [browser showFind];
            FlushBrowser(browser);
            measure(query.length ? @"find_focus_populated" : @"find_focus_empty", ^{ [find focus]; }, nil, 100);
            [find close];
        }
        NSClipView *clip = scroller.contentView;
        BOOL notifications = clip.postsBoundsChangedNotifications;
        clip.postsBoundsChangedNotifications = NO;
        measure(@"compact_edge_mask_update", ^{ [strip updateEdgeFade]; }, ^{
            [clip scrollToPoint:NSZeroPoint];
            [strip updateEdgeFade];
            [clip scrollToPoint:NSMakePoint(300, 0)];
            assert(![[strip valueForKey:@"fadesLeft"] boolValue]);
        });
        assert([[strip valueForKey:@"fadesLeft"] boolValue]);
        clip.postsBoundsChangedNotifications = notifications;
    }
    if ([NSProcessInfo.processInfo.environment[@"BROOK_CHECK_FIVE_VISUALS"] isEqualToString:@"1"]) {
        NSView *pageHost = [browser.content valueForKey:@"pageHost"];
        NSView *backdrop = [[NSView alloc] initWithFrame:pageHost.bounds];
        backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        backdrop.wantsLayer = YES;
        backdrop.layer.backgroundColor = NSColor.whiteColor.CGColor;
        [pageHost addSubview:backdrop];
        details[@"expanded_visual_fixture"] = @"Native controls over a solid white AppKit backdrop; WebKit behavior checked separately";
        NSTextField *attached = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 10, 400, 30)];
        [browser.window.contentView addSubview:attached];
        attached.stringValue = @"https://example.test/attached";
        __block int ended = 0;
        [browser.commandBar showAttachedToField:attached alignedWith:attached below:attached onEnd:^{ ++ended; }];
        assert(browser.commandBar.isAttached);
        [browser.commandBar showEditingCurrent:YES];
        assert(!browser.commandBar.isAttached && ended == 1 && attached.delegate == nil);
        assert(commandPanel.firstResponder == commandField.currentEditor);
        [attached removeFromSuperview];
        NSString *longQuery = [@"Brook long search query " stringByPaddingToLength:200 withString:@"0123456789" startingAtIndex:0];
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
                                       NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
            browser.window.appearance = [NSAppearance appearanceNamed:appearance];
            for (CGFloat width : {500., 900., 1280.}) {
                [browser.window setContentSize:NSMakeSize(width, 860)];
                SettleBrowser(browser);
                for (NSString *query in @[@"", @"Brook", longQuery]) {
                    findField.stringValue = query;
                    [browser showFind];
                    assert(NSEqualRanges(findField.currentEditor.selectedRange, NSMakeRange(0, query.length)));
                    FlushBrowser(browser);
                    Capture(browser.content, [NSString stringWithFormat:@"five-find-content-%@-%.0f-%lu", appearance, width,
                                              (unsigned long)query.length], directory);
                    [find close];
                }
                NSPanel *panel = [browser.commandBar valueForKey:@"panel"];
                panel.appearance = browser.window.appearance;
                [browser.commandBar showEditingCurrent:YES];
                [panel.contentView layoutSubtreeIfNeeded];
                Capture(panel.contentView, [NSString stringWithFormat:@"five-command-size-%@-%.0f", appearance, width], directory);
                CGFloat end = std::max<CGFloat>(0, NSWidth(scroller.documentView.frame) - NSWidth(scroller.contentView.bounds));
                for (CGFloat x : {0., 300., end}) {
                    [scroller.contentView scrollToPoint:NSMakePoint(x, 0)];
                    [scroller reflectScrolledClipView:scroller.contentView];
                    FlushBrowser(browser);
                    Capture(strip, [NSString stringWithFormat:@"five-scroll-%@-%.0f-%.0f", appearance, width, x], directory);
                }
            }
        }
    }
    details[@"progress_batches_per_sample"] = @1000;
    details[@"progress_calls_per_batch"] = @1000;
    details[@"progress_timing_unit"] = @"milliseconds per 1,000 calls; averaged over 1,000 batches";
    details[@"visible_windows"] = @0;
    details[@"thermal_state_at_end"] = @(NSProcessInfo.processInfo.thermalState);
    details[@"paired_implementations"] = @(paired);
    details[@"identical_implementation_control"] = @(control);
    CheckNoVisibleWindows();
    puts("Five focused offscreen paths passed.");
}

static void CheckCompactScrolling(BrowserWindowController *browser, NSURL *directory, NSUserDefaults *defaults,
                                  NSMutableDictionary *options, NSMutableDictionary *results, NSMutableDictionary *details) {
    assert(offscreen);
    WKWebView *page = [BrowserState.shared.selectedTab materialize];
    [page loadHTMLString:@"<!doctype html><title>Compact scroll check</title><p>Brook</p>" baseURL:nil];
    WaitFor(^BOOL { return !page.isLoading && [page.title isEqualToString:@"Compact scroll check"]; });
    NSString *layout = NSProcessInfo.processInfo.environment[@"BROOK_CHECK_SCROLL_LAYOUT"] ?: @"compact";
    assert([layout isEqualToString:@"compact"] || [layout isEqualToString:@"top"]);
    NSString *key = [layout stringByAppendingString:@"_tab_list_scroll_main_thread"];
    details[@"scroll_layout"] = layout;
    options[@"tabLayout"] = layout;
    [defaults setVolatileDomain:options forName:NSArgumentDomain];
    [NSNotificationCenter.defaultCenter postNotificationName:BrookSettingsDidChangeNotification object:nil
                                                    userInfo:@{@"key":@"tabLayout"}];
    SettleBrowser(browser);
    NSView *strip = [[browser valueForKey:@"chrome"] valueForKey:@"strip"];
    NSScrollView *scroll = [strip valueForKey:@"scroll"];
    NSArray<NSView *> *tabs = [strip valueForKey:@"tabViews"];
    details[@"label_clips_to_bounds"] = @([[tabs.firstObject valueForKey:@"label"] clipsToBounds]);
    beforeSample = ^{ SettleBrowser(browser); };
    dispatch_block_t work = ^{
        [scroll.contentView scrollToPoint:NSMakePoint(300, 0)];
        [scroll reflectScrolledClipView:scroll.contentView];
        FlushBrowser(browser);
        assert(scroll.contentView.bounds.origin.x == 300);
    };
    dispatch_block_t prepare = ^{
        [scroll.contentView scrollToPoint:NSZeroPoint];
        [scroll reflectScrolledClipView:scroll.contentView];
    };
    if ([NSProcessInfo.processInfo.environment[@"BROOK_CHECK_SCROLL_PAIRED"] isEqualToString:@"1"]) {
        BOOL control = [NSProcessInfo.processInfo.environment[@"BROOK_CHECK_PAIRED_CONTROL"] isEqualToString:@"1"];
        NSMutableArray *before = [NSMutableArray array], *after = [NSMutableArray array];
        for (int run = 0; run < warmupRuns + measuredRuns; ++run) {
            for (int position = 0; position < 2; ++position) {
                @autoreleasepool {
                    BOOL optimized = (run + position) % 2 != 0;
                    for (NSView *tab in tabs) [[tab valueForKey:@"label"] setClipsToBounds:optimized || control];
                    prepare();
                    beforeSample();
                    CFTimeInterval start = CACurrentMediaTime();
                    work();
                    double ms = (CACurrentMediaTime() - start) * 1000;
                    if (run >= warmupRuns) [(optimized ? after : before) addObject:@(ms)];
                }
            }
        }
        results[[key stringByAppendingString:@"_before"]] = before;
        results[[key stringByAppendingString:@"_after"]] = after;
        for (NSView *tab in tabs) [[tab valueForKey:@"label"] setClipsToBounds:YES];
        details[@"paired_configuration"] = control ? @"Both labels use clipping enabled" : @"Same production instances; label clipping disabled/enabled, settled outside timing";
    } else results[key] = Measure(work, prepare);
    beforeSample = nil;
    if ([NSProcessInfo.processInfo.environment[@"BROOK_CHECK_SCROLL_STAGES"] isEqualToString:@"1"]) {
        NSMutableDictionary *stages = [NSMutableDictionary dictionary];
        NSArray *names = @[@"scroll", @"reflect", @"layout", @"display", @"commit"];
        for (NSString *name in names) stages[name] = [NSMutableArray array];
        for (int run = 0; run < warmupRuns + measuredRuns; ++run) {
            @autoreleasepool {
                [scroll.contentView scrollToPoint:NSZeroPoint];
                [scroll reflectScrolledClipView:scroll.contentView];
                SettleBrowser(browser);
                CFTimeInterval start = CACurrentMediaTime();
                [scroll.contentView scrollToPoint:NSMakePoint(300, 0)];
                CFTimeInterval scrolled = CACurrentMediaTime();
                [scroll reflectScrolledClipView:scroll.contentView];
                CFTimeInterval reflected = CACurrentMediaTime();
                [browser.window.contentView layoutSubtreeIfNeeded];
                CFTimeInterval laidOut = CACurrentMediaTime();
                [browser.window.contentView displayIfNeeded];
                CFTimeInterval displayed = CACurrentMediaTime();
                [CATransaction flush];
                CFTimeInterval committed = CACurrentMediaTime();
                double values[] = {scrolled-start, reflected-scrolled, laidOut-reflected, displayed-laidOut, committed-displayed};
                if (run >= warmupRuns) for (int i = 0; i < 5; ++i) [stages[names[i]] addObject:@(values[i]*1000)];
            }
        }
        details[@"scroll_stages_ms"] = stages;
        [scroll.contentView scrollToPoint:NSZeroPoint];
        SettleBrowser(browser);
        [scroll.contentView scrollToPoint:NSMakePoint(300, 0)];
        NSMutableArray *dirty = [NSMutableArray array];
        NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:browser.window.contentView];
        while (pending.count) {
            NSView *view = pending.lastObject;
            [pending removeLastObject];
            [pending addObjectsFromArray:view.subviews];
            if (view.layer.needsDisplay) [dirty addObject:@{@"class":NSStringFromClass(view.class),
                @"frame":NSStringFromRect(view.frame), @"update_layer":@(view.wantsUpdateLayer)}];
        }
        details[@"dirty_layers_after_scroll"] = dirty;
        FlushBrowser(browser);
    }
    for (CGFloat x : {0., 300., 800., 0.}) {
        [scroll.contentView scrollToPoint:NSMakePoint(x, 0)];
        [scroll reflectScrolledClipView:scroll.contentView];
        FlushBrowser(browser);
        Capture(strip, [NSString stringWithFormat:@"compact-scroll-%.0f", x], directory);
    }
    details[@"tabs"] = @([[strip valueForKey:@"tabViews"] count]);
    details[@"document_frame"] = NSStringFromRect(scroll.documentView.frame);
    if ([NSProcessInfo.processInfo.environment[@"BROOK_CHECK_SCROLL_VISUALS"] isEqualToString:@"1"]) {
        NSArray *titles = @[@"Brook", @"An extremely long title that must fade at the edge of a narrow tab",
                           @"Café — 日本語 — العربية — 👨‍👩‍👧‍👦 — gypq"];
        for (NSUInteger i = 0; i < tabs.count; ++i) {
            BrowserTab *tab = [tabs[i] valueForKey:@"tab"];
            [tab setValue:titles[i % titles.count] forKey:@"title"];
        }
        TopBarView *top = [browser valueForKey:@"chrome"];
        [top reloadAll];
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
                                      NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
            browser.window.appearance = [NSAppearance appearanceNamed:appearance];
            for (CGFloat width : {500., 900., 1280.}) {
                NSRect frame = browser.window.frame;
                frame.size.width = width;
                [browser.window setFrame:frame display:YES];
                for (CGFloat font : {11., 13., 17.}) {
                    [strip setValue:@(font) forKey:@"fontSize"];
                    FlushBrowser(browser);
                    for (int position = 0; position < 3; ++position) {
                        CGFloat maximum = NSWidth(scroll.documentView.frame) - NSWidth(scroll.contentView.bounds);
                        [scroll.contentView scrollToPoint:NSMakePoint(position == 0 ? 0 : position == 1 ? 137 : maximum, 0)];
                        [scroll reflectScrolledClipView:scroll.contentView];
                        HoverControl *hover = (HoverControl *)tabs[1];
                        [hover setValue:@(position == 1) forKey:@"isHovering"];
                        FlushBrowser(browser);
                        Capture(strip, [NSString stringWithFormat:@"scroll-labels-%@-%.0f-%.0f-%d", appearance, width, font, position], directory);
                    }
                }
            }
        }
    }
    CheckNoVisibleWindows();
}

static void CheckBrowser(NSURL *directory, NSUserDefaults *defaults, NSMutableDictionary *options) {
    NSMutableDictionary *results = [NSMutableDictionary dictionary], *details = [NSMutableDictionary dictionary];
    details[@"main_thread_qos"] = @(qos_class_self());
    details[@"thermal_state"] = @(NSProcessInfo.processInfo.thermalState);
    BOOL settingsOnly = [NSProcessInfo.processInfo.environment[@"BROOK_CHECK_SETTINGS_ONLY"] isEqualToString:@"1"];
    BOOL modelOnly = [NSProcessInfo.processInfo.environment[@"BROOK_CHECK_MODEL_ONLY"] isEqualToString:@"1"];
    BOOL fiveOnly = [NSProcessInfo.processInfo.environment[@"BROOK_CHECK_FIVE_PATHS_ONLY"] isEqualToString:@"1"];
    BOOL compactOnly = [NSProcessInfo.processInfo.environment[@"BROOK_CHECK_COMPACT_ONLY"] isEqualToString:@"1"];
    if (!settingsOnly && !modelOnly && !fiveOnly && !compactOnly) CheckHistory(directory, results, details);
    puts("History/setup checks passed."); fflush(stdout);
    ConfigureBrowserCheck(defaults, options);
    auto setLayout = [&](TabLayout layout) {
        options[@"tabLayout"] = TabLayoutRaw(layout);
        [defaults setVolatileDomain:options forName:NSArgumentDomain];
        [NSNotificationCenter.defaultCenter postNotificationName:BrookSettingsDidChangeNotification object:nil
                                                        userInfo:@{@"key":@"tabLayout"}];
    };
    WriteSessionFixture(directory);
    __block BrowserState *state;
    ReplaceClassMethod(BrowserState.class, @selector(shared), ^id(id self) { return state; });
    results[@"session_restore_200_tabs"] = Measure(^{
        state = [BrowserState new];
        [state setValue:nil forKey:@"saver"];
        [state load];
        assert(state.allTabs.count == 200 && state.selectedTab);
    }, ^{ [state.selectedTab unload]; }, modelOnly ? 100 : 1);
    CFTimeInterval start = CACurrentMediaTime();
    BrowserWindowController *browser = [BrowserWindowController new];
    [browser start];
    [browser.window setFrame:NSMakeRect(60, 60, 1280, 860) display:YES];
    [NSApp activate];
    [browser.window makeKeyAndOrderFront:nil];
    browser.window.level = NSFloatingWindowLevel;
    [browser.window orderFrontRegardless];
    SettleBrowser(browser);
    FlushBrowser(browser);
    details[@"first_window_construction_and_layout_ms"] = @((CACurrentMediaTime() - start) * 1000);
    puts("Session restore and window construction checks passed."); fflush(stdout);
    if (fiveOnly || compactOnly) {
        [results removeAllObjects];
        if (compactOnly) CheckCompactScrolling(browser, directory, defaults, options, results, details);
        else CheckFivePaths(browser, directory, defaults, options, results, details);
        SaveCheckJSON(results, directory, @"browser-timings.json");
        SaveCheckJSON(details, directory, @"browser-details.json");
        state.observer = nil;
        for (BrowserTab *tab in state.allTabs) [tab unload];
        BrookFinishBackgroundWrites();
        return;
    }
    if (settingsOnly || modelOnly) {
        if (modelOnly) {
            WKWebView *page = [state.selectedTab materialize];
            [page loadHTMLString:@"<!doctype html><title>Menu fixture</title>" baseURL:nil];
            WaitFor(^BOOL { return !page.isLoading && [page.title isEqual:@"Menu fixture"]; });
            SettleBrowser(browser);
            CheckMenus(browser, results, 2000);
        }
        else CheckSettings(directory, results, details);
        if (offscreen) CheckNoVisibleWindows();
        SaveCheckJSON(results, directory, @"browser-timings.json");
        SaveCheckJSON(details, directory, @"browser-details.json");
        [browser.window orderOut:nil];
        state.observer = nil;
        for (BrowserTab *tab in state.allTabs) [tab unload];
        BrookFinishBackgroundWrites();
        puts("Focused browser checks passed.");
        return;
    }
    BrowserTab *first = state.currentSpace.tabs[0], *second = state.currentSpace.tabs[1];
    [second materialize];
    beforeSample = ^{ SettleBrowser(browser); };
    __block int sequence = 0;
    results[@"local_page_load_to_title"] = Measure(^{
        NSString *title = [NSString stringWithFormat:@"Local page %d", sequence++];
        NSString *html = [NSString stringWithFormat:@"<!doctype html><title>%@</title><style>body{margin:0;background:#eef2ff}div{height:100px;padding:16px;border-bottom:1px solid #888}</style><main></main><script>document.querySelector('main').innerHTML=Array.from({length:250},(_,i)=>'<div>Local row '+i+'</div>').join('')</script>", title];
        [first.webView loadHTMLString:html baseURL:nil];
        WaitFor(^BOOL { return !first.webView.isLoading && [first.webView.title isEqualToString:title]; });
        FlushBrowser(browser);
    });
    puts("Local WebKit navigation checks passed."); fflush(stdout);
    for (NSInteger layout = 0; layout < 3; ++layout) {
        setLayout((TabLayout)layout);
        FlushBrowser(browser);
        NSString *name = TabLayoutRaw((TabLayout)layout);
        results[[name stringByAppendingString:@"_tab_switch_main_thread"]] = Measure(^{
            [state selectTab:first];
            FlushBrowser(browser);
        }, ^{ [state selectTab:second]; });
        results[[name stringByAppendingString:@"_tab_open_close_main_thread"]] = Measure(^{
            BrowserTab *opened = [state openTabWithURL:nil];
            FlushBrowser(browser);
            [state close:opened];
            FlushBrowser(browser);
            assert(state.allTabs.count == 200);
        }, ^{ [state selectTab:first]; });
        results[[name stringByAppendingString:@"_space_switch_main_thread"]] = Measure(^{
            [state switchToSpace:1];
            FlushBrowser(browser);
        }, ^{ [state switchToSpace:0]; });
        [state switchToSpace:0];
        [state selectTab:first];
        NSView *chrome = [browser valueForKey:@"chrome"];
        NSScrollView *scroller = layout == 0 ? [browser.sidebar valueForKey:@"scrollView"] :
                                              [[chrome valueForKey:@"strip"] valueForKey:@"scroll"];
        results[[name stringByAppendingString:@"_tab_list_scroll_main_thread"]] = Measure(^{
            NSPoint origin = layout == 0 ? NSMakePoint(0, 300) : NSMakePoint(300, 0);
            [scroller.contentView scrollToPoint:origin];
            [scroller reflectScrolledClipView:scroller.contentView];
            FlushBrowser(browser);
        }, ^{
            [scroller.contentView scrollToPoint:NSZeroPoint];
            [scroller reflectScrolledClipView:scroller.contentView];
        });
    }
    setLayout(TabLayoutSidebar);
    [state selectTab:first];
    results[@"window_resize_main_thread"] = Measure(^{
        [browser.window setContentSize:NSMakeSize(1100, 860)];
        FlushBrowser(browser);
    }, ^{ [browser.window setContentSize:NSMakeSize(1320, 860)]; });
    [state openInSplit:second];
    results[@"split_resize_main_thread"] = Measure(^{
        [state setSplitFraction:0.6];
        FlushBrowser(browser);
        assert(state.activeSplit);
    }, ^{ [state setSplitFraction:0.4]; });
    [state separateSplit];
    [state selectTab:first];
    results[@"layout_transition_setup_main_thread"] = Measure(^{
        setLayout(TabLayoutTop);
        FlushBrowser(browser);
    }, ^{ setLayout(TabLayoutSidebar); });
    setLayout(TabLayoutSidebar);
    [state selectTab:first];
    puts("Browser action checks passed; checking page frame callbacks."); fflush(stdout);
    SaveCheckJSON(results, directory, @"browser-timings.json");
    [NSApp activate];
    [browser.window makeKeyAndOrderFront:nil];
    SettleBrowser(browser);
    details[@"frame_fixture"] = @{@"selected":@(state.selectedTab == first),
        @"attached":@(first.webView.window == browser.window), @"hidden":@(first.webView.isHiddenOrHasHiddenAncestor),
        @"window_visible":@(browser.window.visible), @"occlusion_visible":@((browser.window.occlusionState & NSWindowOcclusionStateVisible) != 0),
        @"web_frame":NSStringFromRect(first.webView.frame), @"screen_frame":NSStringFromRect(browser.window.screen.frame)};
    SaveCheckJSON(details, directory, @"browser-details.json");
    results[@"local_page_scroll_script_round_trip"] = Measure(^{
        NSNumber *offset = PageScript(first.webView, @"scrollTo(0,scrollY>500?0:1000);return scrollY");
        assert(offset && (offset.integerValue == 0 || offset.integerValue == 1000));
    });
    if (!offscreen) details[@"page_frame_observation"] = PageScript(first.webView,
        @"return await new Promise(resolve=>{const samples=[];let last,done=false;const finish=timeout=>{if(done)return;done=true;resolve({samples_ms:samples,timed_out:timeout,visibility:document.visibilityState})};const timer=setTimeout(()=>finish(true),3000);function frame(t){if(done)return;if(last!==undefined)samples.push(t-last);last=t;scrollBy(0,20);if(samples.length<60)requestAnimationFrame(frame);else{clearTimeout(timer);finish(false)}}requestAnimationFrame(frame)})");
    if ([details[@"page_frame_observation"][@"timed_out"] boolValue]) {
        puts("Frame timing INCONCLUSIVE: the page did not deliver 60 frames within the observation window.");
    }
    CommandBarController *bar = browser.commandBar;
    [bar showEditingCurrent:NO];
    NSTextField *input = [bar valueForKey:@"input"];
    results[@"address_bar_keystroke_20000_history"] = Measure(^{
        [bar controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:input]];
        [bar layoutPanel];
        NSPanel *panel = [bar valueForKey:@"panel"];
        [panel.contentView layoutSubtreeIfNeeded];
        [panel.contentView displayIfNeeded];
        [CATransaction flush];
    }, ^{ input.stringValue = @"browser"; });
    input.stringValue = @"browser";
    [bar rebuild];
    [bar layoutPanel];
    Capture([(NSPanel *)[bar valueForKey:@"panel"] contentView], @"browser-history-suggestions", directory);
    [bar dismiss];
    CheckBrowserFeatures(browser, directory, results, details);
    beforeSample = nil;
    if (!offscreen) CheckLiveMotion(browser, defaults, options, details);
    CheckMotion(browser.window.contentView, browser.content);
    details[@"scope"] = @"Real BrowserState, browser window, command bar, tab layouts and WebKit using local HTML and a nonpersistent data store. External extensions, network stores, password and notification services are disabled. Session restore uses 200 blank tabs. UI action timings end at layout/display submission, not physical presentation or animation completion. Local load includes WebKit but excludes network. A bounded 60-frame observation may time out when the window is occluded; it is not an FPS guarantee.";
    if (offscreen) {
        CheckNoVisibleWindows();
        details[@"scope"] = @"Offscreen production-code checks. Window ordering, child-window ordering and application activation are blocked. Real visibility remains false. Timings cover hidden views, model operations and WebKit IPC; they do not measure visible presentation, window activation, command-bar dismissal or live frame pacing. Settings captures wait for pane selection to settle. Simulated native motion is checked separately.";
        details[@"no_visible_windows"] = @YES;
    }
    SaveCheckJSON(results, directory, @"browser-timings.json");
    struct rusage usage{};
    assert(getrusage(RUSAGE_SELF, &usage) == 0);
    details[@"fixture_peak_rss_bytes"] = @(usage.ru_maxrss);
    details[@"settle_timeouts"] = @(settleTimeouts);
    SaveCheckJSON(details, directory, @"browser-details.json");
    [browser.window orderOut:nil];
    state.observer = nil;
    for (BrowserTab *tab in state.allTabs) [tab unload];
    BrookFinishBackgroundWrites();
    printf("Browser checks passed; %d measured samples after %d warmups per workload.\n", measuredRuns, warmupRuns);
}

static void Capture(NSView *view, NSString *name, NSURL *directory) {
    [view layoutSubtreeIfNeeded];
    [view displayIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    assert(bitmap);
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    assert(png.length);
    assert([png writeToURL:[directory URLByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES]);
}

static void CheckSidebarEdits(SidebarView *sidebar, NSUserDefaults *defaults, NSMutableDictionary *options,
                              NSURL *directory, BOOL optimized) {
    BrowserState *state = BrowserState.shared;
    Space *space = state.currentSpace;
    SidebarTableView *table = [sidebar valueForKey:@"table"];
    NSScrollView *scroll = [sidebar valueForKey:@"scrollView"];
    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    NSMutableArray<BrowserTab *> *base = [NSMutableArray array];
    auto tab = [&](NSString *title) {
        FixtureTab *t = [[FixtureTab alloc] initWithID:NSUUID.UUID url:[NSURL URLWithString:@"https://example.test/page"] title:title];
        t.state = state;
        return t;
    };
    for (int i = 0; i < 100; ++i) [base addObject:tab([NSString stringWithFormat:@"Row %03d", i])];
    NSArray<BrowserTab *> *pinnedTabs = @[tab(@"Pinned one"), tab(@"Pinned two")];
    for (BrowserTab *t in pinnedTabs) t.isPinned = YES;
    NSUInteger reloads = 0;
    NSUInteger *counter = &reloads;
    Method method = class_getInstanceMethod(NSTableView.class, @selector(reloadData));
    IMP original = method_getImplementation(method);
    IMP counting = imp_implementationWithBlock(^(NSTableView *self) {
        if (self == table) ++*counter;
        ((void (*)(id, SEL))original)(self, @selector(reloadData));
    });
    method_setImplementation(method, counting);
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        sidebar.window.appearance = [NSAppearance appearanceNamed:appearance];
        for (BOOL rail : {NO, YES}) {
            options[@"sidebarIconsOnly"] = @(rail);
            options[@"uiFont"] = @"system";
            options[@"closeButtons"] = @"hover";
            [defaults setVolatileDomain:options forName:NSArgumentDomain];
            [sidebar setFrameSize:NSMakeSize(rail ? 52 : 240, 700)];
            [sidebar applySettings];
            auto prepare = [&](NSUInteger count, BOOL pinned = NO) {
                [space.pinned removeAllObjects];
                if (pinned) [space.pinned addObjectsFromArray:pinnedTabs];
                [space.tabs setArray:[base subarrayWithRange:NSMakeRange(0, count)]];
                for (BrowserTab *t in base) t.isPinned = NO;
                [state setValue:count ? base[std::min<NSUInteger>(40, count - 1)] : nil forKey:@"selectedTab"];
                [sidebar reloadAll];
                [scroll.layer removeAnimationForKey:@"spaceSwitch"];
                [sidebar layoutSubtreeIfNeeded];
                [table enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *row, NSInteger index) {
                    id cell = [row viewAtColumn:0];
                    if ([cell isKindOfClass:TabCellView.class]) [cell setValue:@YES forKey:@"hovering"];
                }];
                reloads = 0;
            };
            auto check = [&](NSString *name, BOOL incremental, BOOL transition = NO, BOOL checkReloads = YES) {
                if (transition) {
                    __block CATransition *animation;
                    Method add = class_getInstanceMethod(CALayer.class, @selector(addAnimation:forKey:));
                    IMP addOriginal = method_getImplementation(add);
                    IMP capture = imp_implementationWithBlock(^(CALayer *self, CAAnimation *value, NSString *key) {
                        if (self == scroll.layer && [key isEqualToString:@"spaceSwitch"]) animation = (CATransition *)[value copy];
                        ((void (*)(id, SEL, CAAnimation *, NSString *))addOriginal)(self, @selector(addAnimation:forKey:), value, key);
                    });
                    method_setImplementation(add, capture);
                    [sidebar reloadAllWithSpaceTransition:YES];
                    method_setImplementation(add, addOriginal);
                    imp_removeBlock(capture);
                    assert([animation.type isEqualToString:BrookReduceMotion() ? kCATransitionFade : kCATransitionPush]);
                    assert(animation.duration == (BrookReduceMotion() ? 0.2 : 0.28));
                } else [sidebar reloadAll];
                NSUInteger actualReloads = reloads;
                if (checkReloads) {
                    if (optimized) assert(incremental ? actualReloads == 0 : actualReloads > 0);
                    else assert(actualReloads > 0);
                }
                NSString *key = [NSString stringWithFormat:@"%@-%@-%@", appearance, rail ? @"rail" : @"sidebar", name];
                Capture(sidebar, [@"edit-" stringByAppendingString:key], directory);
                NSPoint origin = scroll.contentView.bounds.origin;
                NSUInteger offset = space.pinned.count + (space.pinned.count ? 1 : 0) + 1;
                assert(table.numberOfRows == (NSInteger)(offset + space.tabs.count));
                [table enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *row, NSInteger index) {
                    id cell = [row viewAtColumn:0];
                    if (![cell isKindOfClass:TabCellView.class]) return;
                    BrowserTab *expected = index < (NSInteger)space.pinned.count ? space.pinned[index] : space.tabs[index - offset];
                    assert([(TabCellView *)cell tab] == expected);
                    assert([[cell accessibilityLabel] isEqualToString:expected.displayTitle]);
                    assert([[cell accessibilityValue] boolValue] == (expected == state.selectedTab));
                    assert(![[cell valueForKey:@"hovering"] boolValue]);
                }];
                [sidebar reloadAll];
                Capture(sidebar, [@"reference-" stringByAppendingString:key], directory);
                assert(NSEqualPoints(origin, scroll.contentView.bounds.origin));
                NSData *actual = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"edit-%@.png", key]]];
                NSData *reference = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"reference-%@.png", key]]];
                if (![actual isEqualToData:reference]) NSLog(@"Sidebar capture differs from full reload: %@", key);
                assert([actual isEqualToData:reference]);
                evidence[key] = @{@"full_reloads":@(actualReloads), @"rows":@(table.numberOfRows),
                                  @"scroll_x":@(origin.x), @"scroll_y":@(origin.y), @"matches_full_reload":@YES};
            };
            for (NSUInteger index : {40, 0, 100}) {
                prepare(100);
                [space.tabs insertObject:tab(@"Inserted tab") atIndex:index];
                check([NSString stringWithFormat:@"insert-%lu", index], index == 40);
            }
            for (NSUInteger index : {0, 40, 99}) {
                prepare(100);
                [space.tabs removeObjectAtIndex:index];
                if (index == 40) [state setValue:space.tabs[40] forKey:@"selectedTab"];
                check([NSString stringWithFormat:@"remove-%lu", index], index == 40);
            }
            prepare(0);
            [space.tabs addObject:tab(@"Only tab")];
            [state setValue:space.tabs.firstObject forKey:@"selectedTab"];
            check(@"first-tab", YES);
            prepare(1);
            [space.tabs removeAllObjects];
            [state setValue:nil forKey:@"selectedTab"];
            check(@"last-tab", YES);
            prepare(100);
            [space.tabs exchangeObjectAtIndex:0 withObjectAtIndex:40];
            check(@"reorder", NO);
            prepare(100);
            [space.tabs addObjectsFromArray:@[tab(@"Bulk one"), tab(@"Bulk two")]];
            check(@"bulk-insert", NO);
            prepare(100);
            BrowserTab *pinned = space.tabs.firstObject;
            [space.tabs removeObjectAtIndex:0];
            pinned.isPinned = YES;
            [space.pinned addObject:pinned];
            check(@"pin-divider", NO);
            prepare(100, YES);
            [space.tabs insertObject:tab(@"Inserted beside pinned rows") atIndex:40];
            check(@"insert-with-pinned", YES);
            prepare(100, YES);
            [space.tabs removeObjectAtIndex:40];
            [state setValue:space.tabs[40] forKey:@"selectedTab"];
            check(@"remove-with-pinned", YES);
            prepare(100);
            [table hideRowsAtIndexes:[NSIndexSet indexSetWithIndex:1] withAnimation:NSTableViewAnimationEffectNone];
            [space.tabs insertObject:tab(@"Insert during drag") atIndex:40];
            check(@"hidden-drag-row", NO);
            prepare(100);
            [space.tabs insertObject:tab(@"Insert with space transition") atIndex:40];
            check(@"space-transition", NO, YES);
            for (BOOL pinned : {NO, YES}) {
                prepare(100, pinned);
                for (NSUInteger i = 0; i < space.tabs.count; ++i)
                    space.tabs[i] = tab([NSString stringWithFormat:@"Other space %lu", i]);
                [state setValue:space.tabs[40] forKey:@"selectedTab"];
                check(pinned ? @"same-shape-pinned-space" : @"same-shape-space", YES, YES, NO);
            }
        }
    }
    method_setImplementation(method, original);
    imp_removeBlock(counting);
    __weak BrowserTab *released;
    @autoreleasepool {
        BrowserTab *closed = tab(@"Release after closing");
        released = closed;
        [space.pinned removeAllObjects];
        [space.tabs setArray:@[closed]];
        [state setValue:nil forKey:@"selectedTab"];
        [sidebar reloadAll];
        [sidebar layoutSubtreeIfNeeded];
        [table viewAtColumn:0 row:1 makeIfNecessary:YES];
        [space.tabs removeAllObjects];
        [sidebar reloadAll];
    }
    assert(!released);
    SaveCheckJSON(evidence, directory, @"sidebar-edits.json");
}

static NSArray<NSTrackingArea *> *OwnedTracking(NSView *view) {
    return [view.trackingAreas filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSTrackingArea *area, NSDictionary *bindings) {
        return area.owner == view;
    }]];
}

static void CheckSymbols(void) {
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
                                   NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
        [[NSAppearance appearanceNamed:appearance] performAsCurrentDrawingAppearance:^{
            for (NSString *name in @[@"xmark", @"globe", @"arrow.clockwise", @"sidebar.left"]) {
                for (CGFloat size : {9.0, 13.0, 34.0}) {
                    for (NSFontWeight weight : {NSFontWeightRegular, NSFontWeightMedium, NSFontWeightBold}) {
                        NSImage *reference = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]
                            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
                        NSImage *actual = [NSImage brook_symbol:name size:size weight:weight];
                        assert(NSEqualSizes(actual.size, reference.size));
                        assert(actual.isTemplate == reference.isTemplate);
                        assert([actual.TIFFRepresentation isEqual:reference.TIFFRepresentation]);
                        actual.size = NSMakeSize(70, 80);
                        [actual setTemplate:!reference.isTemplate];
                        NSImage *again = [NSImage brook_symbol:name size:size weight:weight];
                        assert(NSEqualSizes(again.size, reference.size));
                        assert(again.isTemplate == reference.isTemplate);
                    }
                }
            }
        }];
    }
    NSMutableString *name = [@"xmark" mutableCopy];
    (void)[NSImage brook_symbol:name size:17];
    [name setString:@"globe"];
    NSImage *globe = [NSImage brook_symbol:name size:17];
    assert([globe.TIFFRepresentation isEqual:[NSImage brook_symbol:@"globe" size:17].TIFFRepresentation]);
    assert([NSImage brook_symbol:@"brook.symbol.that.does.not.exist" size:13] == nil);
}

static void CheckTopSpaceReuse(TopBarView *top, NSURL *directory) {
    [top endEditingAddress];
    BrowserState *state = BrowserState.shared;
    Space *space = state.currentSpace;
    [space.pinned removeAllObjects];
    [space.tabs removeAllObjects];
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        top.window.appearance = [NSAppearance appearanceNamed:appearance];
        for (BOOL compact : {NO, YES}) {
            top.compact = compact;
            for (int phase = 0; phase < 6; ++phase) {
                @autoreleasepool {
                    NSMapTable *previous = [[top valueForKey:@"strip"] valueForKey:@"byTab"];
                    NSView *focused = phase == 5 ? [previous objectForKey:state.selectedTab] : nil;
                    BrowserTab *focusedTab = [focused valueForKey:@"tab"];
                    if (focused) assert([top.window makeFirstResponder:focused]);
                    NSView *pressed = phase == 1 ? [previous objectForKey:state.selectedTab] : nil;
                    BrowserTab *pressedTab = [pressed valueForKey:@"tab"];
                    [space.tabs removeAllObjects];
                    [space.pinned removeAllObjects];
                    NSUInteger count = phase == 2 ? 8 : phase == 3 ? 25 : 20;
                    for (NSUInteger i = 0; i < count; ++i) {
                        FixtureTab *tab = [[FixtureTab alloc] initWithID:NSUUID.UUID
                            url:phase % 2 ? [NSURL URLWithString:@"https://example.test/other-space"] : nil
                            title:[NSString stringWithFormat:@"Space %d · tab %lu", phase, i]];
                        tab.state = state;
                        [space.tabs addObject:tab];
                    }
                    if (phase == 2 || phase == 4) {
                        FixtureTab *pinned = [[FixtureTab alloc] initWithID:NSUUID.UUID
                            url:[NSURL URLWithString:@"https://pinned.example.test"] title:@"Pinned in other space"];
                        pinned.isPinned = YES;
                        pinned.state = state;
                        [space.pinned addObject:pinned];
                    }
                    [state setValue:phase == 4 ? space.pinned.firstObject : space.tabs[phase % 2 ? count - 1 : 0]
                            forKey:@"selectedTab"];
                    Method buttons = class_getClassMethod(NSEvent.class, @selector(pressedMouseButtons));
                    IMP originalButtons = method_getImplementation(buttons);
                    IMP held = pressed ? imp_implementationWithBlock(^NSUInteger(id self) { return 1; }) : nullptr;
                    if (held) method_setImplementation(buttons, held);
                    [top reloadAllWithSpaceTransition:phase % 2 == 0];
                    if (held) { method_setImplementation(buttons, originalButtons); imp_removeBlock(held); }
                    [top updateSelection];
                    [top layoutSubtreeIfNeeded];
                    NSView *strip = [top valueForKey:@"strip"];
                    NSMapTable *byTab = [strip valueForKey:@"byTab"];
                    if (focused) assert([focused valueForKey:@"tab"] == focusedTab);
                    if (pressed) assert([pressed valueForKey:@"tab"] == pressedTab);
                    assert(byTab.count == count + space.pinned.count);
                    for (BrowserTab *tab in [space.pinned arrayByAddingObjectsFromArray:space.tabs]) {
                        HoverControl *view = [byTab objectForKey:tab];
                        assert([view valueForKey:@"tab"] == tab);
                        assert([view.accessibilityLabel isEqualToString:tab.displayTitle]);
                        assert([view.accessibilityValue boolValue] == (tab == state.selectedTab));
                        assert(!view.isHovering && !view.isPressed);
                    }
                    Capture(top, [NSString stringWithFormat:@"space-%@-%@-%d", appearance,
                                  compact ? @"compact" : @"top", phase], directory);
                    HoverControl *selected = [byTab objectForKey:state.selectedTab];
                    [selected setValue:@YES forKey:@"isHovering"];
                    if (compact && phase == 3) assert([top beginEditingAddress]);
                }
            }
        }
    }
    __weak BrowserTab *released;
    @autoreleasepool {
        TopBarView *isolated = [[TopBarView alloc] initWithFrame:top.frame];
        [top.superview addSubview:isolated];
        FixtureTab *tab = [[FixtureTab alloc] initWithID:NSUUID.UUID url:nil title:@"Released tab"];
        released = tab;
        [space.tabs setArray:@[tab]];
        [state setValue:tab forKey:@"selectedTab"];
        [isolated reloadAll];
        [isolated layoutSubtreeIfNeeded];
        [space.tabs removeAllObjects];
        [state setValue:nil forKey:@"selectedTab"];
        [isolated reloadAll];
        [isolated layoutSubtreeIfNeeded];
        [isolated removeFromSuperview];
    }
    assert(!released);
}

static void CheckFallbackIcons(NSView *host, FixtureTab *tab, NSURL *directory,
                               NSMutableDictionary *results, BOOL optimized) {
    TabCellView *row = [[TabCellView alloc] initWithFrame:NSMakeRect(0, 0, 236, 34)];
    [row configureWithTab:tab selected:NO];
    NSView *tile = [[NSClassFromString(@"FavoriteTile") alloc] initWithTab:tab];
    tile.frame = NSMakeRect(0, 40, 44, 44);
    FixtureExtensionContext *context = [FixtureExtensionContext new];
    context.action = [FixtureExtensionItem new];
    context.action.enabled = YES;
    context.webExtension = [FixtureExtensionItem new];
    context.webExtension.displayName = @"Fixture extension";
    NSView *extension = [[NSClassFromString(@"ExtensionButton") alloc] initWithContext:(id)context size:28];
    extension.frame = NSMakeRect(0, 90, 28, 28);
    NSArray<NSView *> *views = @[row, tile, extension];
    NSArray<NSString *> *names = @[@"sidebar", @"favorite", @"extension"];
    NSArray<dispatch_block_t> *refreshes = @[
        ^{ [row updateWithTab:tab]; }, ^{ [tile refresh]; }, ^{ [extension refreshForTab:tab]; }
    ];
    for (NSView *view in views) [host addSubview:view];
    [extension refreshForTab:tab];
    assert([(NSImageView *)[extension valueForKey:@"icon"] image] == nil);
    NSImage *favicon = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.systemBlueColor setFill];
        NSRectFill(rect);
        [NSColor.whiteColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 4, 4)] fill];
        return YES;
    }];
    NSImage *actionIcon = [NSImage brook_symbol:@"star.fill" size:16];
    context.action.icon = actionIcon;
    [extension refreshForTab:tab];
    context.action.icon = nil;
    for (NSUInteger index = 0; index < views.count; ++index) {
        dispatch_block_t refresh = refreshes[index];
        for (int mode = 0; mode < 3; ++mode) {
            tab.favicon = mode == 1 ? favicon : nil;
            context.action.icon = mode == 1 ? actionIcon : nil;
            refresh();
            NSString *kind = @[@"fallback", @"provided", @"transition"][mode];
            results[[NSString stringWithFormat:@"%@_icon_%@_1000", names[index], kind]] = Measure(^{
                for (int i = 0; i < 1000; ++i) {
                    if (mode == 2) {
                        tab.favicon = i % 2 ? favicon : nil;
                        context.action.icon = i % 2 ? actionIcon : nil;
                    }
                    refresh();
                }
            });
        }
    }
    tab.favicon = nil;
    context.action.icon = nil;
    NSMutableDictionary *factoryCalls = [NSMutableDictionary dictionary];
    Method factory = class_getClassMethod(NSImage.class, @selector(brook_symbol:size:));
    IMP original = method_getImplementation(factory);
    __block NSUInteger calls = 0;
    IMP counter = imp_implementationWithBlock(^NSImage *(id self, NSString *name, CGFloat size) {
        ++calls;
        return ((NSImage *(*)(id, SEL, NSString *, CGFloat))original)(self, @selector(brook_symbol:size:), name, size);
    });
    for (NSUInteger index = 0; index < views.count; ++index) {
        dispatch_block_t refresh = refreshes[index];
        refresh();
        NSImageView *icon = [views[index] valueForKey:@"icon"];
        NSImage *fallback = icon.image;
        assert(fallback);
        calls = 0;
        method_setImplementation(factory, counter);
        for (int i = 0; i < 100; ++i) refresh();
        method_setImplementation(factory, original);
        factoryCalls[names[index]] = @(calls);
        if (optimized) assert(calls == 0 && icon.image == fallback);
    }
    imp_removeBlock(counter);
    NSData *counts = [NSJSONSerialization dataWithJSONObject:factoryCalls options:NSJSONWritingPrettyPrinted error:nil];
    assert([counts writeToURL:[directory URLByAppendingPathComponent:@"fallback-factory-calls.json"] atomically:YES]);
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
                                   NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
        host.window.appearance = [NSAppearance appearanceNamed:appearance];
        for (int phase = 0; phase < 3; ++phase) {
            tab.favicon = phase == 1 ? favicon : nil;
            context.action.icon = phase == 1 ? actionIcon : nil;
            for (NSUInteger index = 0; index < views.count; ++index) {
                refreshes[index]();
                NSImageView *icon = [views[index] valueForKey:@"icon"];
                assert(icon.image);
                if (phase == 1) assert(icon.image == (index == 2 ? actionIcon : favicon));
                else {
                    NSImage *expected = [NSImage brook_symbol:index == 2 ? @"puzzlepiece.extension" : @"globe"
                                                        size:index == 1 ? 16 : 13];
                    assert(NSEqualSizes(icon.image.size, expected.size));
                    assert([icon.image.TIFFRepresentation isEqual:expected.TIFFRepresentation]);
                }
                assert(icon.alphaValue == 1);
                assert(index == 2 && phase == 1 ? icon.contentTintColor == nil :
                       [icon.contentTintColor isEqual:NSColor.secondaryLabelColor]);
                Capture(views[index], [NSString stringWithFormat:@"%@-%@-icon-%d", appearance, names[index], phase], directory);
            }
        }
    }
    NSImageView *extensionIcon = [extension valueForKey:@"icon"];
    context.webExtension.icon = favicon;
    [extension refreshForTab:tab];
    assert(extensionIcon.image == favicon && extensionIcon.contentTintColor == nil);
    context.action.icon = actionIcon;
    context.action.enabled = NO;
    context.action.label = @"Action label";
    context.action.badgeText = @"12345";
    [extension refreshForTab:tab];
    assert(extensionIcon.image == actionIcon && extensionIcon.alphaValue == 0.4);
    assert([extension.toolTip isEqualToString:@"Action label"]);
    assert([extension.accessibilityLabel isEqualToString:@"Action label"]);
    assert([[(CATextLayer *)[extension valueForKey:@"badgeText"] string] isEqual:@"1234"]);
    context.action = nil;
    [extension refreshForTab:tab];
    assert(extensionIcon.image == favicon && extensionIcon.alphaValue == 1);
    assert([extension.toolTip isEqualToString:@"Fixture extension"]);
    assert([(CALayer *)[extension valueForKey:@"badge"] isHidden]);
    context.webExtension.icon = nil;
    [extension refreshForTab:tab];
    assert(extensionIcon.image != favicon && [extensionIcon.contentTintColor isEqual:NSColor.secondaryLabelColor]);
    tab.favicon = nil;
    for (NSView *view in views) [view removeFromSuperview];
}

static void CheckMotion(NSView *host, NSView *sibling) {
    __block BOOL reduced = NO;
    Method preference = class_getInstanceMethod(NSWorkspace.class, @selector(accessibilityDisplayShouldReduceMotion));
    IMP original = method_setImplementation(preference, imp_implementationWithBlock(^BOOL(id self) { return reduced; }));
    NSRect frames[] = {NSMakeRect(0, 0, 240, 700), NSMakeRect(0, 610, 1040, 90), NSMakeRect(0, 660, 1040, 40)};
    for (BOOL reduce : {NO, YES}) {
        reduced = reduce;
        for (int rate : {60, 120}) {
            for (int from = 0; from < 3; ++from) {
                for (int to = 0; to < 3; ++to) {
                    if (from == to) continue;
                    ChromeMorph *morph = [[ChromeMorph alloc] initInView:host above:sibling frame:frames[from] picture:nil
                                                           pictureFrame:frames[from] alpha:1 cornerRadius:16];
                    __block int pictures = 0, completions = 0;
                    __block CGFloat last = 0;
                    NSRect target = frames[to];
                    [morph runToTarget:^NSRect { return target; } incoming:^NSImage * { ++pictures; return nil; }
                          incomingFrame:^NSRect { return target; } progress:^(CGFloat move, CGFloat reveal) {
                        assert(move >= last && move <= 1 && reveal >= 0 && reveal <= 1);
                        last = move;
                    } completion:^{ ++completions; }];
                    for (int frame = 0; frame <= rate && !completions; ++frame) {
                        [morph setValue:@(CACurrentMediaTime() - (double)frame / rate) forKey:@"start"];
                        [morph tick:nil];
                        assert(NSWidth(morph.frame) >= 0 && NSHeight(morph.frame) >= 0);
                    }
                    assert(pictures == 1 && completions == 1 && NSEqualRects(morph.frame, target));
                    assert(morph.glass.superview == nil);
                }
            }
        }
    }
    method_setImplementation(preference, original);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc >= 2 && argc <= 5);
        NSString *runs = NSProcessInfo.processInfo.environment[@"BROOK_CHECK_RUNS"];
        NSString *warmups = NSProcessInfo.processInfo.environment[@"BROOK_CHECK_WARMUPS"];
        if (runs) { measuredRuns = runs.intValue; assert(measuredRuns >= 1 && measuredRuns <= 1000); }
        if (warmups) { warmupRuns = warmups.intValue; assert(warmupRuns >= 0 && warmupRuns <= 100); }
        BOOL optimized = YES, browserMode = NO, startupMode = NO;
        for (int i = 2; i < argc; ++i) {
            if (strcmp(argv[i], "--baseline") == 0) optimized = NO;
            else if (strcmp(argv[i], "--browser") == 0) browserMode = YES;
            else if (strcmp(argv[i], "--startup") == 0) startupMode = YES;
            else if (strcmp(argv[i], "--offscreen") == 0) offscreen = YES;
            else assert(false);
        }
        if ((browserMode || startupMode) && !offscreen && ![NSProcessInfo.processInfo.environment[@"BROOK_ALLOW_VISIBLE_TESTS"] isEqualToString:@"1"]) {
            fputs("Visible browser/startup tests are disabled. Explicit approval is required.\n", stderr);
            return 2;
        }
        if (offscreen || (!browserMode && !startupMode)) BlockWindowPresentation();
        NSURL *directory = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        assert([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]);
        ReplaceClassMethod(AppPaths.class, @selector(support), ^id(id self) { return directory; });
        ReplaceClassMethod(AppPaths.class, @selector(caches), ^id(id self) { return directory; });
        for (Class cls in @[FaviconStore.class, DownloadManager.class, ExtensionManager.class, ContentBlocker.class]) {
            ReplaceClassMethod(cls, @selector(shared), ^id(id self) { return nil; });
        }
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"app.brook.ui-check"];
        ReplaceClassMethod(NSUserDefaults.class, @selector(standardUserDefaults), ^id(id self) { return defaults; });
        NSMutableDictionary *options = [@{@"blockAds": @NO, @"loadingIndicator": @"none", @"tabLayout": @"sidebar",
                                           @"tabSubtitles": @YES, @"addressDisplay": @"full", @"topTabsShrink": @NO} mutableCopy];
        [defaults setVolatileDomain:options forName:NSArgumentDomain];
        [NSApplication sharedApplication];
        id activity = [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep | NSActivityLatencyCritical
                                                                  reason:@"Repeatable offscreen performance measurements"];
        [NSApp setActivationPolicy:!offscreen && (browserMode || startupMode) ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyProhibited];
        if (offscreen) {
            NSWindow *probe = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                         styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            [probe orderFront:nil];
            [probe orderBack:nil];
            [probe makeKeyAndOrderFront:nil];
            [probe orderFrontRegardless];
            [probe makeKeyWindow];
            [probe makeMainWindow];
            [probe orderWindow:NSWindowAbove relativeTo:0];
            [NSApp activate];
            [NSApp activateIgnoringOtherApps:YES];
            CheckNoVisibleWindows();
        }
        if (startupMode) {
            [NSApp finishLaunching];
            CheckStartup(directory, defaults, options);
            [NSProcessInfo.processInfo endActivity:activity];
            return 0;
        }
        CheckMenuItemBehavior();
        if ([NSProcessInfo.processInfo.environment[@"BROOK_CHECK_COLORS_ONLY"] isEqualToString:@"1"]) {
            NSMutableDictionary *results = [NSMutableDictionary dictionary];
            CheckColors(results);
            SaveCheckJSON(results, directory, @"timings.json");
            CheckNoVisibleWindows();
            [NSProcessInfo.processInfo endActivity:activity];
            return 0;
        }
        if (browserMode) {
            [NSApp finishLaunching];
            CheckBrowser(directory, defaults, options);
            [NSProcessInfo.processInfo endActivity:activity];
            return 0;
        }
        CheckSymbols();
        BrowserState *state = BrowserState.shared;
        Space *space = [[Space alloc] initWithName:@"UI checks" colorHex:@"8B5CF6"];
        [(NSMutableArray *)state.spaces addObject:space];
        for (int i = 0; i < 200; ++i) {
            FixtureTab *tab = [[FixtureTab alloc] initWithID:NSUUID.UUID url:[NSURL URLWithString:@"https://example.test/path"]
                                                     title:[NSString stringWithFormat:@"Tab %d — A long title for fading and layout", i]];
            tab.state = state;
            [space.tabs addObject:tab];
        }
        FixtureTab *tab = (FixtureTab *)space.tabs.firstObject;
        [state setValue:tab forKey:@"selectedTab"];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 800)
                                                      styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        NSView *host = window.contentView;
        IconButton *button = [[IconButton alloc] initWithSymbol:@"arrow.clockwise" size:12 tooltip:@"Reload" dimension:28 onClick:nil];
        [host addSubview:button];
        SidebarView *sidebar = [[SidebarView alloc] initWithFrame:NSMakeRect(0, 0, 240, 700)];
        [host addSubview:sidebar];
        [sidebar reloadAll];
        TopBarView *top = [[TopBarView alloc] initWithFrame:NSMakeRect(240, 700, 1040, 90)];
        [host addSubview:top];
        [top reloadAll];
        [host layoutSubtreeIfNeeded];
        [host displayIfNeeded];
        NSView *strip = [top valueForKey:@"strip"];
        NSScrollView *scroll = [strip valueForKey:@"scroll"];
        NSMutableDictionary *results = [NSMutableDictionary dictionary];
        results[@"symbol_repeat_10000"] = Measure(^{
            for (int i = 0; i < 10000; ++i) [button setSymbol:@"arrow.clockwise" size:12];
        });
        results[@"symbol_change_1000"] = Measure(^{
            for (int i = 0; i < 1000; ++i) [button setSymbol:i % 2 ? @"xmark" : @"arrow.clockwise" size:12];
        });
        results[@"tracking_repeat_10000"] = Measure(^{
            for (int i = 0; i < 10000; ++i) [button updateTrackingAreas];
        });
        results[@"hover_state_repeat_1000"] = Measure(^{
            for (int i = 0; i < 1000; ++i) {
                button.isHighlightedState = NO;
                button.isPressed = NO;
                button.baseColor = NSColor.clearColor;
                button.cornerRadius = 7;
                [button displayIfNeeded];
            }
        });
        results[@"sidebar_progress_1000"] = Measure(^{
            for (int i = 0; i < 1000; ++i) [sidebar tabChanged:tab change:TabChangeProgress];
        });
        results[@"top_progress_1000"] = Measure(^{
            for (int i = 0; i < 1000; ++i) [top tabChanged:tab change:TabChangeProgress];
        });
        [scroll.contentView scrollToPoint:NSMakePoint(50, 0)];
        results[@"edge_fade_repeat_10000"] = Measure(^{
            for (int i = 0; i < 10000; ++i) [strip updateEdgeFade];
        });
        top.compact = YES;
        [host layoutSubtreeIfNeeded];
        results[@"compact_refresh_layout_300"] = Measure(^{
            for (int i = 0; i < 300; ++i) { [strip refresh:tab]; [strip layoutSubtreeIfNeeded]; }
        });
        top.compact = NO;
        CheckFallbackIcons(host, tab, directory, results, optimized);
        if ([NSProcessInfo.processInfo.environment[@"BROOK_CHECK_UI_TIMINGS_ONLY"] isEqualToString:@"1"]) {
            SaveCheckJSON(results, directory, @"timings.json");
            CheckNoVisibleWindows();
            [NSProcessInfo.processInfo endActivity:activity];
            return 0;
        }
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
                                       NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
            window.appearance = [NSAppearance appearanceNamed:appearance];
            Capture(sidebar, [appearance stringByAppendingString:@"-sidebar"], directory);
            Capture(top, [appearance stringByAppendingString:@"-top"], directory);
            top.compact = YES;
            Capture(top, [appearance stringByAppendingString:@"-compact"], directory);
            top.compact = NO;
            for (NSString *style in @[@"card", @"flat", @"outline", @"accentBar", @"tinted"]) {
                options[@"tabStyle"] = style;
                [defaults setVolatileDomain:options forName:NSArgumentDomain];
                [sidebar applySettings];
                Capture(sidebar, [NSString stringWithFormat:@"%@-%@", appearance, style], directory);
            }
            options[@"tabStyle"] = @"card";
            [defaults setVolatileDomain:options forName:NSArgumentDomain];
            [sidebar applySettings];
        }
        for (NSString *font in @[@"system", @"rounded", @"serif", @"mono"]) {
            options[@"uiFont"] = font;
            [defaults setVolatileDomain:options forName:NSArgumentDomain];
            [sidebar applySettings];
            [top applySettings];
            Capture(sidebar, [font stringByAppendingString:@"-sidebar"], directory);
            Capture(top, [font stringByAppendingString:@"-top"], directory);
        }
        for (NSString *close in @[@"hover", @"always", @"never"]) {
            options[@"closeButtons"] = close;
            [defaults setVolatileDomain:options forName:NSArgumentDomain];
            [sidebar applySettings];
            [top applySettings];
            Capture(sidebar, [close stringByAppendingString:@"-close-sidebar"], directory);
            Capture(top, [close stringByAppendingString:@"-close-top"], directory);
        }
        CGFloat end = NSWidth(scroll.documentView.frame) - NSWidth(scroll.contentView.bounds);
        for (CGFloat x : {0.0, 40.0, end, 40.0, 0.0}) {
            [scroll.contentView scrollToPoint:NSMakePoint(x, 0)];
            [strip updateEdgeFade];
            CAGradientLayer *mask = (CAGradientLayer *)scroll.layer.mask;
            assert(mask && mask.colors.count == 4 && mask.locations.count == 4);
            assert(CGColorEqualToColor((__bridge CGColorRef)mask.colors.firstObject,
                                      x > 0.5 ? NSColor.clearColor.CGColor : NSColor.blackColor.CGColor));
            assert(CGColorEqualToColor((__bridge CGColorRef)mask.colors.lastObject,
                                      x < end - 0.5 ? NSColor.clearColor.CGColor : NSColor.blackColor.CGColor));
            NSArray *colors = mask.colors;
            [strip updateEdgeFade];
            if (optimized) assert(mask.colors == colors);
        }
        NSSize scrollSize = scroll.frame.size;
        [scroll setFrameSize:NSMakeSize(40, scrollSize.height)];
        [scroll tile];
        [strip updateEdgeFade];
        assert(scroll.layer.mask == nil);
        [scroll setFrameSize:scrollSize];
        [scroll tile];
        [strip updateEdgeFade];
        assert(scroll.layer.mask != nil);
        NSImage *original = button.imageView.image;
        [button setSymbol:@"globe" size:12];
        assert(button.imageView.image && button.imageView.image != original);
        [button setSymbol:@"xmark" size:18];
        assert(NSEqualSizes(button.imageView.image.size, [NSImage brook_symbol:@"xmark" size:18].size));
        button.imageView.image = [NSImage brook_symbol:@"globe" size:13];
        [button setSymbol:@"xmark" size:18];
        assert([button.imageView.image.TIFFRepresentation isEqual:[NSImage brook_symbol:@"xmark" size:18].TIFFRepresentation]);
        original = button.imageView.image;
        [button setSymbol:@"xmark" size:18];
        if (optimized) assert(button.imageView.image == original);
        NSMutableString *symbol = [@"xmark" mutableCopy];
        [button setSymbol:symbol size:18];
        [symbol setString:@"globe"];
        [button setSymbol:symbol size:18];
        assert([button.imageView.image.TIFFRepresentation isEqual:[NSImage brook_symbol:@"globe" size:18].TIFFRepresentation]);
        [button updateTrackingAreas];
        assert(OwnedTracking(button).count == 1);
        assert(OwnedTracking(button).firstObject.options & NSTrackingInVisibleRect);
        [button setFrameSize:NSMakeSize(40, 40)];
        [button updateTrackingAreas];
        assert(OwnedTracking(button).count == 1);
        NSEvent *entered = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered location:NSZeroPoint modifierFlags:0
                                               timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0
                                          trackingNumber:0 userData:nullptr];
        [button mouseEntered:entered];
        assert(button.isHovering);
        NSEvent *exited = [NSEvent enterExitEventWithType:NSEventTypeMouseExited location:NSZeroPoint modifierFlags:0
                                              timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0
                                         trackingNumber:0 userData:nullptr];
        [button mouseExited:exited];
        assert(!button.isHovering);
        for (NSString *name in @[@"HoverControl", @"TabCellView", @"NewTabCellView", @"EdgeHotZone", @"FullScreenLights",
                                 @"PaneDivider", @"HiddenElementRow"]) {
            Class cls = NSClassFromString(name);
            assert(cls);
            NSView *view = [[cls alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
            [view updateTrackingAreas];
            NSTrackingArea *area = OwnedTracking(view).firstObject;
            assert(area && (area.options & NSTrackingInVisibleRect));
            [view setFrameSize:NSMakeSize(200, 40)];
            [view updateTrackingAreas];
            assert(OwnedTracking(view).count == 1);
            if (optimized) assert(OwnedTracking(view).firstObject == area);
        }
        __block int clicks = 0;
        button.onClick = ^{ ++clicks; };
        assert([button accessibilityPerformPress] && clicks == 1);
        button.enabled = NO;
        assert(![button accessibilityPerformPress] && clicks == 1);
        tab.loading = YES;
        [sidebar tabChanged:tab change:TabChangeLoading | TabChangeProgress];
        [top tabChanged:tab change:TabChangeLoading | TabChangeProgress];
        assert(sidebar.urlPill.siteButton.isEnabled);
        assert([sidebar.urlPill.accessibilityValue isEqualToString:tab.url.absoluteString]);
        CheckMotion(host, sidebar);
        tab.loading = NO;
        [tab setValue:@"Changed title" forKey:@"title"];
        [sidebar tabChanged:tab change:TabChangeTitle];
        [top tabChanged:tab change:TabChangeTitle];
        NSMapTable *byTab = [strip valueForKey:@"byTab"];
        NSView *tabView = [byTab objectForKey:tab];
        assert([tabView.accessibilityLabel isEqualToString:@"Changed title"]);
        top.compact = YES;
        [host layoutSubtreeIfNeeded];
        [tab setValue:[NSURL URLWithString:@"http://example.test/a/longer/path/that/changes/the/selected/tab/width"] forKey:@"url"];
        [sidebar tabChanged:tab change:TabChangeURL | TabChangeProgress];
        [top tabChanged:tab change:TabChangeURL | TabChangeProgress];
        assert(strip.needsLayout);
        [host layoutSubtreeIfNeeded];
        assert([sidebar.urlPill.siteButton.accessibilityValue isEqualToString:@"Not secure"]);
        assert([sidebar.urlPill.accessibilityValue isEqualToString:tab.url.absoluteString]);
        assert([top beginEditingAddress]);
        NSTextField *field = [tabView valueForKey:@"editField"];
        assert(field && field.superview == tabView);
        field.stringValue = @"https://example.test/an/address/being/edited";
        [top tabChanged:tab change:TabChangeTitle];
        assert(strip.needsLayout);
        [host layoutSubtreeIfNeeded];
        [tabView layout];
        assert(NSWidth(field.frame) > 0);
        options[@"commandBarTabs"] = @YES;
        options[@"commandBarHistory"] = @NO;
        [defaults setVolatileDomain:options forName:NSArgumentDomain];
        CheckCommandBarRows(directory, results);
        CheckSidebarEdits(sidebar, defaults, options, directory, optimized);
        CheckTopSpaceReuse(top, directory);
        NSData *json = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        assert([json writeToURL:[directory URLByAppendingPathComponent:@"timings.json"] atomically:YES]);
        printf("UI checks passed; %d measured samples after %d warmups per workload.\n", measuredRuns, warmupRuns);
        CheckNoVisibleWindows();
        [NSProcessInfo.processInfo endActivity:activity];
    }
    return 0;
}
