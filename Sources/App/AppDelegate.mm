#import "Brook.h"

/// The app delegate: menu bar, lifecycle, memory management, links from other apps.
@implementation AppDelegate {
    BrowserWindowController *_windowController;
    NSTimer *_hibernateTimer;
    dispatch_source_t _memoryPressure;
    NSMutableArray<NSURL *> *_pendingURLs;
}

- (instancetype)init {
    if ((self = [super init])) {
        _pendingURLs = [NSMutableArray array];
    }
    return self;
}

- (BrowserState *)state { return BrowserState.shared; }

// MARK: Lifecycle

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    NSApp.mainMenu = [self buildMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [PrivacyConfigStore.shared load];
    (void)WebViewFactory.userContentController;   // compile content scripts once, up front
    [ContentBlocker.shared load];
    [self.state load];
    _windowController = [BrowserWindowController new];
    [_windowController start];
    for (NSURL *url in _pendingURLs) [self.state openTabWithURL:url inSpace:self.externalLinksSpace select:YES];
    [_pendingURLs removeAllObjects];

    // Load extensions after this method returns.
    dispatch_async(dispatch_get_main_queue(), ^{
        [ExtensionManager.shared loadAll];
    });
    [self startMemoryManagement];
    [NSNotificationCenter.defaultCenter addObserverForName:BrookSettingsDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        id rawKey = note.userInfo[@"key"];
        NSString *key = [rawKey isKindOfClass:NSString.class] ? rawKey : @"*";
        // Cached settings blobs are re-read after an import/reset.
        if (![key isEqualToString:@"*"]) return;
        [SearchEngines invalidate];
        [SiteSettings invalidate];
        [Boosts invalidate];
        [WebViewFactory reloadBoosts];
    }];
    [NSApp activate];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.state saveNow];
    [HistoryStore.shared saveNow];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) [_windowController showWindow:nil];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }

/// Links opened from other apps when Brook is the default browser.
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    if (_windowController == nil) { [_pendingURLs addObjectsFromArray:urls]; return; }
    for (NSURL *url in urls) [self.state openTabWithURL:url inSpace:self.externalLinksSpace select:YES];
    [_windowController showWindow:nil];
}

/// Space chosen in Settings → General for links from other apps (nil = current space).
- (Space *)externalLinksSpace {
    NSUUID *identifier = Settings.externalLinksSpace;
    if (!identifier) return nil;
    for (Space *s in self.state.spaces) {
        if ([s.identifier isEqual:identifier]) return s;
    }
    return nil;
}

// MARK: Memory

- (void)startMemoryManagement {
    _hibernateTimer = [NSTimer scheduledTimerWithTimeInterval:300 repeats:YES block:^(NSTimer *timer) {
        NSInteger minutes = Settings.hibernateMinutes;
        if (minutes > 0) [BrowserState.shared hibernateOlderThan:(NSTimeInterval)(minutes * 60)];
        NSInteger hours = Settings.archiveHours;
        if (hours > 0) [BrowserState.shared archiveOlderThan:(NSTimeInterval)(hours * 3600)];
    }];
    _hibernateTimer.tolerance = 60;
    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
        DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
        [BrowserState.shared hibernateOlderThan:60];
    });
    dispatch_resume(source);
    _memoryPressure = source;
}

// MARK: Menu actions

- (BrowserWindowController *)wc { return _windowController; }

- (void)newTab:(id)sender { [self.wc showWindow:nil]; [self.wc newTab]; }
- (void)showSettings:(id)sender { [SettingsWindowController.shared show]; }
- (void)showSiteSettings:(id)sender { [self.wc showSiteInfo]; }
- (void)stopLoading:(id)sender { [self.state.selectedTab.webView stopLoading]; }
- (void)printPage:(id)sender {
    WKWebView *wv = self.state.selectedTab.webView;
    NSWindow *window = self.wc.window;
    if (!wv || !window) return;
    NSPrintOperation *op = [wv printOperationWithPrintInfo:NSPrintInfo.sharedPrintInfo];
    op.view.frame = wv.bounds;
    [op runOperationModalForWindow:window delegate:nil didRunSelector:nil contextInfo:nil];
}
- (void)openLocation:(id)sender { [self.wc showWindow:nil]; [self.wc showCommandBarEditing:YES]; }
- (void)closeTab:(id)sender {
    NSWindow *key = NSApp.keyWindow;
    if (key && key != self.wc.window && ![key isKindOfClass:KeyPanel.class]) { [key performClose:nil]; return; }
    BrowserTab *tab = self.state.selectedTab;
    if (tab) [self.state close:tab]; else [self.wc.window performClose:nil];
}
- (void)reopenTab:(id)sender { [self.state reopenClosedTab]; }
- (void)togglePin:(id)sender { BrowserTab *t = self.state.selectedTab; if (t) [self.state togglePin:t]; }
- (void)toggleFavorite:(id)sender { BrowserTab *t = self.state.selectedTab; if (t) [self.state toggleFavorite:t]; }
- (void)duplicateTab:(id)sender { BrowserTab *t = self.state.selectedTab; if (t) [self.state duplicate:t]; }
- (void)copyURL:(id)sender { [self.wc copyURL]; }
- (void)toggleSidebarMenu:(id)sender { [self.wc toggleSidebar]; }
- (void)reload:(id)sender { [self.state.selectedTab reload]; }
- (void)hardReload:(id)sender { [self.state.selectedTab.webView reloadFromOrigin]; }
- (void)back:(id)sender { [self.wc goBack]; }
- (void)forward:(id)sender { [self.wc goForward]; }
- (void)zoomIn:(id)sender { [self.wc zoomBy:0.1]; }
- (void)zoomOut:(id)sender { [self.wc zoomBy:-0.1]; }
- (void)actualSize:(id)sender { [self.wc resetZoom]; }
- (void)find:(id)sender { [self.wc showFind]; }
- (void)findNext:(id)sender { [self.wc.content.findBar searchForward:YES]; }
- (void)findPrevious:(id)sender { [self.wc.content.findBar searchForward:NO]; }
- (void)nextTab:(id)sender { [self.state selectNext:1]; }
- (void)previousTab:(id)sender { [self.state selectNext:-1]; }
- (void)selectTabN:(NSMenuItem *)sender { [self.state selectIndex:sender.tag]; }
- (void)selectSpaceN:(NSMenuItem *)sender { [self.state switchToSpace:sender.tag]; }
- (void)nextSpace:(id)sender { [self.state switchSpaceBy:1]; }
- (void)previousSpace:(id)sender { [self.state switchSpaceBy:-1]; }
- (void)newSpace:(id)sender { [self.wc promptNewSpace]; }
- (void)editSpace:(id)sender { [self.wc promptEditSpace:self.state.currentSpace]; }
- (void)fire:(id)sender { [self.wc fire]; }
- (void)toggleCookiePopups:(id)sender {
    Settings.blockCookiePopups = !Settings.blockCookiePopups;
    [self.wc showToast:Settings.blockCookiePopups ? @"Cookie popups will be declined" : @"Cookie popup blocking off"];
}
- (void)addExtensionFromStore:(id)sender { [self.wc promptChromeWebStore]; }
- (void)installExtensionFile:(id)sender { [self.wc promptInstallFile]; }
- (void)showMainWindow:(id)sender { [self.wc showWindow:nil]; }

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    BrowserTab *tab = self.state.selectedTab;
    if (action == @selector(toggleCookiePopups:)) {
        menuItem.state = Settings.blockCookiePopups ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (action == @selector(stopLoading:)) {
        return tab.isLoading == YES;
    } else if (action == @selector(showSiteSettings:) || action == @selector(printPage:)) {
        return BrookHost(tab.url) != nil;
    } else if (action == @selector(togglePin:)) {
        menuItem.title = tab.isPinned == YES ? @"Unpin Tab" : @"Pin Tab";
        return tab != nil;
    } else if (action == @selector(toggleFavorite:)) {
        menuItem.title = tab.isFavorite == YES ? @"Remove from Favorites" : @"Add to Favorites";
        return tab != nil;
    } else if (action == @selector(back:)) {
        return tab.webView ? tab.webView.canGoBack : NO;
    } else if (action == @selector(forward:)) {
        return tab.webView ? tab.webView.canGoForward : NO;
    } else if (action == @selector(toggleSidebarMenu:)) {
        menuItem.title = _windowController.sidebarHidden == YES ? @"Show Sidebar" : @"Hide Sidebar";
    } else if (action == @selector(selectSpaceN:)) {
        menuItem.state = menuItem.tag == self.state.currentSpaceIndex ? NSControlStateValueOn : NSControlStateValueOff;
        return menuItem.tag < (NSInteger)self.state.spaces.count;
    }
    return YES;
}

// MARK: Menu bar

static NSMenuItem *BrookItem(NSString *title, SEL action, NSString *key = @"",
                             NSEventModifierFlags mods = NSEventModifierFlagCommand, NSInteger tag = 0) {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    i.keyEquivalentModifierMask = mods;
    i.tag = tag;
    return i;
}

static NSString *BrookKey(unichar c) {
    return [NSString stringWithCharacters:&c length:1];
}

- (NSMenu *)buildMenu {
    NSMenu *main = [NSMenu new];

    auto item = [](NSString *title, SEL action, NSString *key = @"",
                   NSEventModifierFlags mods = NSEventModifierFlagCommand, NSInteger tag = 0) {
        return BrookItem(title, action, key, mods, tag);
    };
    auto separator = [] { return NSMenuItem.separatorItem; };
    auto submenu = [main](NSString *title, NSArray<NSMenuItem *> *items) {
        NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        NSMenu *m = [[NSMenu alloc] initWithTitle:title];
        for (NSMenuItem *i in items) [m addItem:i];
        top.submenu = m;
        [main addItem:top];
        return top;
    };
    const NSEventModifierFlags cmd = NSEventModifierFlagCommand;
    const NSEventModifierFlags opt = NSEventModifierFlagOption;
    const NSEventModifierFlags shift = NSEventModifierFlagShift;
    const NSEventModifierFlags ctrl = NSEventModifierFlagControl;

    // App
    submenu(@"Brook", @[
        item(@"About Brook", @selector(orderFrontStandardAboutPanel:), @""),
        separator(),
        item(@"Settings…", @selector(showSettings:), @","),
        separator(),
        item(@"Hide Brook", @selector(hide:), @"h"),
        item(@"Hide Others", @selector(hideOtherApplications:), @"h", cmd | opt),
        item(@"Show All", @selector(unhideAllApplications:)),
        separator(),
        item(@"Quit Brook", @selector(terminate:), @"q"),
    ]);

    submenu(@"File", @[
        item(@"New Tab", @selector(newTab:), @"t"),
        item(@"Open Location…", @selector(openLocation:), @"l"),
        item(@"Reopen Closed Tab", @selector(reopenTab:), @"t", cmd | shift),
        separator(),
        item(@"Close Tab", @selector(closeTab:), @"w"),
        separator(),
        item(@"Pin Tab", @selector(togglePin:), @"d"),
        item(@"Add to Favorites", @selector(toggleFavorite:), @"d", cmd | shift),
        item(@"Duplicate Tab", @selector(duplicateTab:), @"k", cmd | opt),
        item(@"Copy Link", @selector(copyURL:), @"c", cmd | shift),
        separator(),
        item(@"Print…", @selector(printPage:), @"p"),
    ]);

    submenu(@"Edit", @[
        item(@"Undo", NSSelectorFromString(@"undo:"), @"z"),
        item(@"Redo", NSSelectorFromString(@"redo:"), @"z", cmd | shift),
        separator(),
        item(@"Cut", @selector(cut:), @"x"),
        item(@"Copy", @selector(copy:), @"c"),
        item(@"Paste", @selector(paste:), @"v"),
        item(@"Paste and Match Style", @selector(pasteAsPlainText:), @"v", cmd | opt | shift),
        item(@"Select All", @selector(selectAll:), @"a"),
        separator(),
        item(@"Find…", @selector(find:), @"f"),
        item(@"Find Next", @selector(findNext:), @"g"),
        item(@"Find Previous", @selector(findPrevious:), @"g", cmd | shift),
    ]);

    submenu(@"View", @[
        item(@"Hide Sidebar", @selector(toggleSidebarMenu:), @"s"),
        separator(),
        item(@"Reload Page", @selector(reload:), @"r"),
        item(@"Reload Ignoring Cache", @selector(hardReload:), @"r", cmd | shift),
        item(@"Stop", @selector(stopLoading:), @"."),
        separator(),
        item(@"Actual Size", @selector(actualSize:), @"0"),
        item(@"Zoom In", @selector(zoomIn:), @"="),
        item(@"Zoom Out", @selector(zoomOut:), @"-"),
        separator(),
        item(@"Settings for This Website…", @selector(showSiteSettings:)),
        separator(),
        item(@"Enter Full Screen", @selector(toggleFullScreen:), @"f", cmd | ctrl),
    ]);

    NSMutableArray<NSMenuItem *> *spaceItems = [NSMutableArray arrayWithArray:@[
        item(@"Next Space", @selector(nextSpace:), BrookKey(NSRightArrowFunctionKey), cmd | opt),
        item(@"Previous Space", @selector(previousSpace:), BrookKey(NSLeftArrowFunctionKey), cmd | opt),
        separator(),
        item(@"New Space…", @selector(newSpace:), @"n", cmd | shift),
        item(@"Edit Space…", @selector(editSpace:)),
        separator(),
    ]];
    for (NSInteger i = 0; i < 9; i++) {
        [spaceItems addObject:item([NSString stringWithFormat:@"Space %ld", (long)(i + 1)], @selector(selectSpaceN:),
                                   [NSString stringWithFormat:@"%ld", (long)(i + 1)], ctrl, i)];
    }
    submenu(@"Spaces", spaceItems);

    NSMutableArray<NSMenuItem *> *tabItems = [NSMutableArray arrayWithArray:@[
        item(@"Back", @selector(back:), @"["),
        item(@"Forward", @selector(forward:), @"]"),
        separator(),
        item(@"Next Tab", @selector(nextTab:), @"\t", ctrl),
        item(@"Previous Tab", @selector(previousTab:), @"\t", ctrl | shift),
        separator(),
    ]];
    for (NSInteger i = 0; i < 9; i++) {
        NSString *title = i == 8 ? @"Last Tab" : [NSString stringWithFormat:@"Tab %ld", (long)(i + 1)];
        [tabItems addObject:item(title, @selector(selectTabN:), [NSString stringWithFormat:@"%ld", (long)(i + 1)], cmd, i)];
    }
    submenu(@"Tabs", tabItems);

    submenu(@"Privacy", @[
        item(@"Burn Tabs & Data…", @selector(fire:), BrookKey(NSBackspaceCharacter), cmd | shift),
        separator(),
        item(@"Decline Cookie Popups", @selector(toggleCookiePopups:)),
    ]);

    submenu(@"Extensions", @[
        item(@"Add from Chrome Web Store…", @selector(addExtensionFromStore:)),
        item(@"Install from File or Folder…", @selector(installExtensionFile:)),
    ]);

    NSMenuItem *windowMenu = submenu(@"Window", @[
        item(@"Minimize", @selector(performMiniaturize:), @"m"),
        item(@"Zoom", @selector(performZoom:)),
        separator(),
        item(@"Brook", @selector(showMainWindow:), @"1", cmd | opt),
    ]);
    NSApp.windowsMenu = windowMenu.submenu;
    return main;
}

@end
