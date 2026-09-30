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
    [AppDelegate applyShortcuts];
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
    [AppDelegate applyAppIcon];
    [NSNotificationCenter.defaultCenter addObserverForName:BrookSettingsDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        id rawKey = note.userInfo[@"key"];
        NSString *key = [rawKey isKindOfClass:NSString.class] ? rawKey : @"*";
        // Cached settings blobs are re-read after an import/reset.
        if ([key isEqualToString:@"siteSettings"]) { [WebViewFactory reloadSiteScripts]; return; }
        if ([@[@"*", @"shortcuts"] containsObject:key]) [AppDelegate applyShortcuts];
        if ([@[@"*", @"appIcon", @"accentSource"] containsObject:key]) [AppDelegate applyAppIcon];
        if (![key isEqualToString:@"*"]) return;
        [SearchEngines invalidate];
        [SiteSettings invalidate];
        [Boosts invalidate];
        [WebViewFactory reloadSiteScripts];
    }];
    [NSApp activate];
}

/// Settings → General → Warn before quitting with this many tabs open.
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    NSInteger limit = Settings.quitWarningTabs;
    NSInteger open = 0;
    for (Space *s in self.state.spaces) open += (NSInteger)s.tabs.count;
    if (limit <= 0 || open < limit || !_windowController.window.isVisible) return NSTerminateNow;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Quit Brook with %ld tabs open?", (long)open];
    alert.informativeText = Settings.launchBehavior == LaunchBehaviorRestore
        ? @"They'll be back next time you open Brook."
        : @"Your tabs won't be reopened next time (Settings → General → On launch).";
    [alert addButtonWithTitle:@"Quit"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.showsSuppressionButton = YES;
    alert.suppressionButton.title = @"Don't ask again";
    NSModalResponse r = [alert runModal];
    if (alert.suppressionButton.state == NSControlStateValueOn) Settings.quitWarningTabs = 0;
    return r == NSAlertFirstButtonReturn ? NSTerminateNow : NSTerminateCancel;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.state saveNow];
    [HistoryStore.shared saveNow];
    [DownloadManager.shared discardUnfinished];   // nothing to resume them from after quitting
    BrookFinishBackgroundWrites();   // the saves above are queued; don't quit before they land
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
        BOOL perSpace = NO;
        for (Space *s in BrowserState.shared.spaces) perSpace = perSpace || s.archiveHours.integerValue > 0;
        if (hours > 0 || perSpace) [BrowserState.shared archiveOlderThan:(NSTimeInterval)(hours * 3600)];
    }];
    _hibernateTimer.tolerance = 60;
    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
        DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
        // A warning puts tabs unseen for five minutes to sleep; critical, every tab but the one on screen.
        BOOL critical = (dispatch_source_get_data(source) & DISPATCH_MEMORYPRESSURE_CRITICAL) != 0;
        [BrowserState.shared hibernateOlderThan:critical ? 0 : 300];
    });
    dispatch_resume(source);
    _memoryPressure = source;
}

// MARK: Menu actions

- (BrowserWindowController *)wc { return _windowController; }

- (void)newTab:(id)sender { [self.wc showWindow:nil]; [self.wc newTab]; }
- (void)importPasswords:(id)sender { [SettingsWindowController.shared importPasswords]; }
- (void)showPasswords:(id)sender { [SettingsWindowController.shared showPane:@"Passwords"]; }
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
- (void)toggleMute:(id)sender {
    BrowserTab *t = self.state.selectedTab;
    NSError *error = nil;
    if (t && ![t setMuted:!t.isMuted error:&error]) [self.wc showError:error];
}
- (void)toggleFavorite:(id)sender { BrowserTab *t = self.state.selectedTab; if (t) [self.state toggleFavorite:t]; }
- (void)duplicateTab:(id)sender { BrowserTab *t = self.state.selectedTab; if (t) [self.state duplicate:t]; }
- (void)copyURL:(id)sender { [self.wc copyURL]; }
- (void)toggleReader:(id)sender { [self.wc toggleReader]; }
- (void)togglePictureInPicture:(id)sender { [self.wc togglePictureInPicture]; }
- (void)toggleSidebarMenu:(id)sender { [self.wc toggleSidebar]; }
- (void)reload:(id)sender { [self.state.selectedTab reload]; }
- (void)hardReload:(id)sender { [self.state.selectedTab.webView reloadFromOrigin]; }
- (void)back:(id)sender { [self.wc goBack]; }
- (void)forward:(id)sender { [self.wc goForward]; }
- (void)zoomIn:(id)sender { [self.wc zoomBy:0.1]; }
- (void)zoomOut:(id)sender { [self.wc zoomBy:-0.1]; }
- (void)actualSize:(id)sender { [self.wc resetZoom]; }
- (void)find:(id)sender { [self.wc showFind]; }
- (void)findNext:(id)sender { [self.wc.content findAgain:YES]; }
- (void)findPrevious:(id)sender { [self.wc.content findAgain:NO]; }
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

// Web Inspector: WebKit's own, through the private `_inspector` (_WKInspector), the one Safari's Develop
// menu drives. Each selector is checked first, so a WebKit without them leaves the items doing nothing.
- (id)selectedInspector {
    WKWebView *wv = self.state.selectedTab.webView;
    static SEL get = NSSelectorFromString(@"_inspector");
    return [wv respondsToSelector:get] ? ((id (*)(id, SEL))objc_msgSend)(wv, get) : nil;
}
static void InspectorSend(id inspector, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if ([inspector respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(inspector, sel);
}
static BOOL InspectorVisible(id inspector) {
    static SEL sel = NSSelectorFromString(@"isVisible");
    return [inspector respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(inspector, sel);
}
- (void)toggleWebInspector:(id)sender {
    id inspector = self.selectedInspector;
    InspectorSend(inspector, InspectorVisible(inspector) ? @"close" : @"show");
}
- (void)showJavaScriptConsole:(id)sender { InspectorSend(self.selectedInspector, @"showConsole"); }
- (void)inspectElement:(id)sender {
    id inspector = self.selectedInspector;
    if (!InspectorVisible(inspector)) InspectorSend(inspector, @"show");
    InspectorSend(inspector, @"toggleElementSelection");
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    BrowserTab *tab = self.state.selectedTab;
    NSWindow *sheet = _windowController.window.attachedSheet;
    NSWindow *key = NSApp.keyWindow;
    // Close Tab closes another key window (Settings) itself; see closeTab:.
    BOOL closesOtherWindow = action == @selector(closeTab:) && key && key != _windowController.window &&
                             key != sheet && ![key isKindOfClass:KeyPanel.class];
    if (sheet != nil && !closesOtherWindow && action != @selector(showSettings:) &&
        action != @selector(showMainWindow:) && action != @selector(toggleCookiePopups:)) {
        // A sheet is modal to the browser window: its tabs, spaces and page stay untouched until it closes.
        return NO;
    }
    if (action == @selector(toggleCookiePopups:)) {
        menuItem.state = Settings.blockCookiePopups ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (action == @selector(stopLoading:)) {
        return tab.isLoading == YES;
    } else if (action == @selector(toggleReader:)) {
        menuItem.title = tab.readerOn == YES ? @"Hide Reader" : @"Show Reader";
        return BrookHost(tab.url) != nil;
    } else if (action == @selector(showSiteSettings:) || action == @selector(printPage:) ||
               action == @selector(togglePictureInPicture:)) {
        return BrookHost(tab.url) != nil;
    } else if (action == @selector(toggleWebInspector:)) {
        menuItem.title = InspectorVisible(self.selectedInspector) ? @"Hide Web Inspector" : @"Show Web Inspector";
        return self.selectedInspector != nil;
    } else if (action == @selector(showJavaScriptConsole:) || action == @selector(inspectElement:)) {
        return self.selectedInspector != nil;
    } else if (action == @selector(reload:) || action == @selector(hardReload:) ||
               action == @selector(actualSize:) || action == @selector(zoomIn:) ||
               action == @selector(zoomOut:) || action == @selector(find:) ||
               action == @selector(findNext:) || action == @selector(findPrevious:)) {
        // These act on the selected tab; an empty space has none.
        return tab != nil;
    } else if (action == @selector(copyURL:) || action == @selector(duplicateTab:)) {
        // A new tab with no address has nothing to copy or duplicate.
        return tab.url != nil;
    } else if (action == @selector(reopenTab:)) {
        return self.state.canReopenClosedTab;
    } else if (action == @selector(selectTabN:) || action == @selector(nextTab:) ||
               action == @selector(previousTab:)) {
        // These pick from the space's visible tabs; an empty space has none to pick.
        return self.state.visibleTabs.count > 0;
    } else if (action == @selector(togglePin:)) {
        menuItem.title = tab.isPinned == YES ? @"Unpin Tab" : @"Pin Tab";
        return tab != nil;
    } else if (action == @selector(toggleMute:)) {
        menuItem.title = tab.isMuted ? @"Unmute Tab" : @"Mute Tab";
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
        return _windowController.tabsOnTop != YES;
    } else if (action == @selector(selectSpaceN:)) {
        menuItem.state = menuItem.tag == self.state.currentSpaceIndex ? NSControlStateValueOn : NSControlStateValueOff;
        return menuItem.tag < (NSInteger)self.state.spaces.count;
    } else if (action == @selector(nextSpace:)) {
        return self.state.currentSpaceIndex + 1 < (NSInteger)self.state.spaces.count;
    } else if (action == @selector(previousSpace:)) {
        return self.state.currentSpaceIndex > 0;
    }
    return YES;
}

// MARK: App icon

/// Settings → Appearance → App icon: the Dock icon, recoloured from the bundled one. The Finder
/// keeps the bundle's icon (changing that would modify the signed app).
+ (void)applyAppIcon {
    static NSImage *original = [NSApp.applicationIconImage copy];
    AppIconStyle style = Settings.appIcon;
    if (style == AppIconStyleDefault || !original) { NSApp.applicationIconImage = nil; return; }
    CGImageRef cg = [original CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cg) return;
    CIImage *image = [CIImage imageWithCGImage:cg];
    CIFilter *filter = nil;
    switch (style) {
        case AppIconStyleMono:
            filter = [CIFilter filterWithName:@"CIColorControls"
                          withInputParameters:@{kCIInputImageKey: image, kCIInputSaturationKey: @0, kCIInputContrastKey: @1.1}];
            break;
        case AppIconStyleNight: {
            // Keep the hue, drop the lightness: a dimmed icon for dark desktops. The white waves
            // stay light because exposure scales, and the gamma curve holds the highlights up.
            CIFilter *dim = [CIFilter filterWithName:@"CIExposureAdjust"
                                 withInputParameters:@{kCIInputImageKey: image, kCIInputEVKey: @(-1.6)}];
            filter = [CIFilter filterWithName:@"CIGammaAdjust"
                          withInputParameters:@{kCIInputImageKey: dim.outputImage, @"inputPower": @0.75}];
            break;
        }
        default: {
            NSColor *c = [(BrowserState.shared.currentSpace.color ?: NSColor.systemPurpleColor)
                          colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            CIFilter *mono = [CIFilter filterWithName:@"CIColorMonochrome"
                                  withInputParameters:@{kCIInputImageKey: image, kCIInputIntensityKey: @0.85,
                                                        kCIInputColorKey: [[CIColor alloc] initWithColor:c]}];
            filter = mono;
            break;
        }
    }
    CIImage *out = [filter.outputImage imageByCroppingToRect:image.extent];
    if (!out) return;
    NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage:out];
    NSImage *icon = [[NSImage alloc] initWithSize:original.size];
    [icon addRepresentation:rep];
    NSApp.applicationIconImage = icon;
}

// MARK: Shortcuts

static NSMutableDictionary<NSString *, NSString *> *sDefaultShortcuts;
/// The built-in menu titles. Validation renames some items ("Pin Tab" → "Unpin Tab"), so Settings uses these.
static NSMutableDictionary<NSString *, NSString *> *sShortcutTitles;

+ (NSString *)shortcutIDForItem:(NSMenuItem *)item {
    NSString *name = NSStringFromSelector(item.action);
    return item.tag ? [NSString stringWithFormat:@"%@%ld", name, (long)item.tag] : name;
}

+ (NSArray<NSArray *> *)shortcutItems {
    // Brook's own items, recorded once. AppKit adds its own items later (a hidden "Enter Full Screen"), which
    // Settings must not list twice and which applyShortcuts must not change.
    static NSArray<NSArray *> *sItems;
    if (sItems) return sItems;
    NSMutableArray *list = [NSMutableArray array];
    for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
        for (NSMenuItem *item in top.submenu.itemArray) {
            // Standard Edit/window commands stay as macOS has them.
            if (item.isSeparatorItem || !item.action || item.submenu) continue;
            if ([@[@"Edit", @"Window"] containsObject:top.title]) continue;
            [list addObject:@[top.title.length ? top.title : @"Brook", item]];
        }
    }
    sItems = [list copy];
    return sItems;
}

+ (NSString *)defaultShortcutForItem:(NSMenuItem *)item {
    return sDefaultShortcuts[[self shortcutIDForItem:item]] ?: @"";
}

/// The command's name for Settings → Shortcuts: its built-in title, not the current state-dependent one.
+ (NSString *)shortcutTitleForItem:(NSMenuItem *)item {
    return sShortcutTitles[[self shortcutIDForItem:item]] ?: item.title;
}

/// Settings → Shortcuts: overrides replace the built-in key equivalents ("" removes one).
+ (void)applyShortcuts {
    BOOL first = sDefaultShortcuts == nil;
    if (first) {
        sDefaultShortcuts = [NSMutableDictionary dictionary];
        sShortcutTitles = [NSMutableDictionary dictionary];
    }
    NSDictionary<NSString *, NSString *> *overrides = Settings.shortcuts;
    for (NSArray *pair in self.shortcutItems) {
        NSMenuItem *item = pair[1];
        NSString *identifier = [self shortcutIDForItem:item];
        if (first) {
            sDefaultShortcuts[identifier] = BrookShortcutString(item.keyEquivalent, item.keyEquivalentModifierMask);
            sShortcutTitles[identifier] = item.title;
        }
        NSString *shortcut = overrides[identifier] ?: sDefaultShortcuts[identifier];
        NSString *key = nil;
        NSEventModifierFlags mods = 0;
        if (BrookParseShortcut(shortcut, &key, &mods)) {
            item.keyEquivalent = key;
            item.keyEquivalentModifierMask = mods;
        } else {
            item.keyEquivalent = @"";
            item.keyEquivalentModifierMask = 0;
        }
    }
}

/// Read from the settings, not the menu, so the answer is right whichever settings observer runs first.
+ (NSString *)shortcutDisplayForCommand:(NSString *)identifier {
    for (NSArray *pair in self.shortcutItems) {
        if (![[self shortcutIDForItem:pair[1]] isEqualToString:identifier]) continue;
        return BrookShortcutDisplay(Settings.shortcuts[identifier] ?: sDefaultShortcuts[identifier] ?: @"");
    }
    return @"";
}

+ (NSString *)tooltip:(NSString *)title command:(NSString *)identifier {
    NSString *shortcut = [self shortcutDisplayForCommand:identifier];
    return shortcut.length ? [NSString stringWithFormat:@"%@ (%@)", title, shortcut] : title;
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
        item(@"Saved Passwords…", @selector(showPasswords:)),
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
        item(@"Import Passwords…", @selector(importPasswords:)),
        separator(),
        item(@"Close Tab", @selector(closeTab:), @"w"),
        separator(),
        item(@"Pin Tab", @selector(togglePin:), @"d"),
        item(@"Mute Tab", @selector(toggleMute:)),
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
        item(@"Show Reader", @selector(toggleReader:), @"r", cmd | opt),
        item(@"Picture in Picture", @selector(togglePictureInPicture:), @"p", cmd | opt),
        item(@"Actual Size", @selector(actualSize:), @"0"),
        item(@"Zoom In", @selector(zoomIn:), @"="),
        item(@"Zoom Out", @selector(zoomOut:), @"-"),
        separator(),
        item(@"Settings for This Website…", @selector(showSiteSettings:)),
        separator(),
        item(@"Show Web Inspector", @selector(toggleWebInspector:), @"i", cmd | opt),
        item(@"Show JavaScript Console", @selector(showJavaScriptConsole:), @"j", cmd | opt),
        item(@"Inspect Element", @selector(inspectElement:), @"c", cmd | opt),
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
