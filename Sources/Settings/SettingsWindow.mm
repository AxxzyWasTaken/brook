#import "Brook.h"

// MARK: - Private panes

@interface GeneralPane : RebuildingPane
@end

@interface AppearancePane : RebuildingPane
@end

@interface LayoutPane : RebuildingPane
@end

@interface TabsPane : RebuildingPane <NSTableViewDataSource, NSTableViewDelegate>
@end

@interface SearchPane : RebuildingPane <NSTableViewDataSource, NSTableViewDelegate>
@end

@interface WebsitesPane : RebuildingPane <NSTableViewDataSource, NSTableViewDelegate>
@end

@interface BoostsPane : RebuildingPane <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@end

@interface AdvancedPane : RebuildingPane
@end

@interface ShortcutsPane : RebuildingPane
@end

/// Titles of every case of an enum that runs 0..<count.
static NSArray<NSString *> *EnumTitles(NSInteger count, NSString *(^title)(NSInteger)) {
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger i = 0; i < count; i++) [a addObject:title(i)];
    return a;
}

// MARK: - Window

/// Resizes the window itself, animated and as soon as a pane is picked, keeping the top edge put.
/// NSTabViewController's own resize waits for the crossfade to finish and then jumps.
@interface SettingsTabViewController : NSTabViewController <NSSearchFieldDelegate>
@end

static NSToolbarItemIdentifier const kSettingsSearchItem = @"BrookSettingsSearch";

/// One place a search hit: the pane it's in and the control or label that matched.
struct SettingsMatch {
    NSInteger pane;
    __weak NSView *view;
};

@implementation SettingsTabViewController {
    NSSearchToolbarItem *_searchItem;
    std::vector<SettingsMatch> _matches;
    size_t _matchIndex;
    NSMutableArray<NSView *> *_highlighted;
}

// MARK: Search

// The tab view controller is the toolbar's delegate; the search field goes at the trailing end.
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [[super toolbarDefaultItemIdentifiers:toolbar]
        arrayByAddingObjectsFromArray:@[NSToolbarFlexibleSpaceItemIdentifier, kSettingsSearchItem]];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [[super toolbarAllowedItemIdentifiers:toolbar]
        arrayByAddingObjectsFromArray:@[NSToolbarFlexibleSpaceItemIdentifier, kSettingsSearchItem]];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)flag {
    if (![identifier isEqualToString:kSettingsSearchItem]) {
        return [super toolbar:toolbar itemForItemIdentifier:identifier willBeInsertedIntoToolbar:flag];
    }
    if (!_searchItem) {
        _searchItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:kSettingsSearchItem];
        _searchItem.searchField.placeholderString = @"Search settings";
        _searchItem.searchField.delegate = self;
        _searchItem.searchField.sendsWholeSearchString = NO;
        _searchItem.preferredWidthForSearchField = 160;
    }
    return _searchItem;
}

/// Every piece of text a person might search for in a view: labels, checkbox and popup titles,
/// segment labels.
static void CollectText(NSView *view, void (^found)(NSView *view, NSString *text)) {
    if (view.isHidden) return;
    if ([view isKindOfClass:NSPopUpButton.class]) {
        NSPopUpButton *p = (NSPopUpButton *)view;
        found(view, [p.itemTitles componentsJoinedByString:@" "]);
        return;
    }
    if ([view isKindOfClass:NSSegmentedControl.class]) {
        NSSegmentedControl *c = (NSSegmentedControl *)view;
        NSMutableArray *labels = [NSMutableArray array];
        for (NSInteger i = 0; i < c.segmentCount; i++) if (NSString *l = [c labelForSegment:i]) [labels addObject:l];
        found(view, [labels componentsJoinedByString:@" "]);
        return;
    }
    if ([view isKindOfClass:NSButton.class]) { found(view, ((NSButton *)view).title); return; }
    if ([view isKindOfClass:NSTextField.class]) {
        NSTextField *f = (NSTextField *)view;
        if (!f.isEditable) found(view, f.stringValue);
        return;
    }
    if ([view isKindOfClass:NSTableView.class]) return;   // data rows, not settings
    for (NSView *sub in view.subviews) CollectText(sub, found);
}

- (void)controlTextDidChange:(NSNotification *)note { [self search:NO]; }

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (command == @selector(insertNewline:)) { [self search:YES]; return YES; }
    if (command == @selector(cancelOperation:)) {
        _searchItem.searchField.stringValue = @"";
        [self search:NO];
        return NO;
    }
    return NO;
}

/// Highlights what matches in the best pane; Return steps through the matches, pane by pane.
- (void)search:(BOOL)next {
    for (NSView *v in _highlighted) v.layer.backgroundColor = nil;
    _highlighted = [NSMutableArray array];
    NSString *query = BrookTrim(_searchItem.searchField.stringValue);
    if (!next) {
        _matches.clear();
        _matchIndex = 0;
        if (query.length == 0) return;
        NSArray<NSTabViewItem *> *items = self.tabViewItems;
        NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
            NSViewController *vc = items[(NSUInteger)i].viewController;
            NSString *paneTitle = items[(NSUInteger)i].label;
            CollectText(vc.view, ^(NSView *view, NSString *text) {
                NSString *haystack = [paneTitle stringByAppendingFormat:@" %@", text];
                for (NSString *w in words) {
                    if (w.length && [haystack rangeOfString:w options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) return;
                }
                // The text itself has to match something typed, not just the pane's name.
                BOOL own = NO;
                for (NSString *w in words) own = own || (w.length && [text rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound);
                if (own) self->_matches.push_back({i, view});
            });
        }
        // Stay on the current pane when it has a match.
        NSInteger current = self.selectedTabViewItemIndex;
        for (size_t m = 0; m < _matches.size(); m++) {
            if (_matches[m].pane == current) { _matchIndex = m; break; }
        }
    } else if (!_matches.empty()) {
        // Next pane that has matches.
        NSInteger pane = _matches[_matchIndex].pane;
        size_t m = _matchIndex;
        do { m = (m + 1) % _matches.size(); } while (_matches[m].pane == pane && m != _matchIndex);
        _matchIndex = m;
    }
    if (_matches.empty()) { if (query.length) NSBeep(); return; }
    NSInteger pane = _matches[_matchIndex].pane;
    if (self.selectedTabViewItemIndex != pane) {
        self.selectedTabViewItemIndex = pane;
        NSSearchField *field = _searchItem.searchField;
        dispatch_async(dispatch_get_main_queue(), ^{
            [field.window makeFirstResponder:field];
            field.currentEditor.selectedRange = NSMakeRange(field.stringValue.length, 0);
        });
    }
    NSColor *accent = [NSColor.controlAccentColor colorWithAlphaComponent:0.22];
    for (const SettingsMatch &m : _matches) {
        NSView *v = m.view;
        if (m.pane != pane || !v) continue;
        v.wantsLayer = YES;
        v.layer.cornerRadius = 5;
        v.layer.backgroundColor = accent.CGColor;
        [_highlighted addObject:v];
    }
    [_matches[_matchIndex].view scrollRectToVisible:_matches[_matchIndex].view.bounds];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item {
    [super tabView:tabView didSelectTabViewItem:item];
    [self fitWindowTo:item.viewController];
}

- (void)preferredContentSizeDidChangeForViewController:(NSViewController *)vc {
    if (vc == self.tabView.selectedTabViewItem.viewController) [self fitWindowTo:vc];
}

- (void)fitWindowTo:(NSViewController *)vc {
    NSWindow *w = self.view.window;
    NSSize size = vc.preferredContentSize;
    if (!w || size.width <= 0 || size.height <= 0) return;
    NSRect content = [w contentRectForFrameRect:w.frame];
    NSRect target = [w frameRectForContentRect:NSMakeRect(NSMinX(content), NSMaxY(content) - size.height,
                                                          size.width, size.height)];
    if (NSEqualRects(target, w.frame)) return;
    if (!w.isVisible) {
        [w setFrame:target display:NO];
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = [w animationResizeTime:target];
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [w.animator setFrame:target display:YES];
    }];
}

@end

/// The ⌘, window: a native toolbar-tabbed preferences window like Safari's.
@implementation SettingsWindowController

+ (SettingsWindowController *)shared {
    static SettingsWindowController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[SettingsWindowController alloc] initPrivate]; });
    return shared;
}

- (instancetype)initPrivate {
    NSTabViewController *tabs = [SettingsTabViewController new];
    tabs.tabStyle = NSTabViewControllerTabStyleToolbar;
    tabs.transitionOptions = NSViewControllerTransitionCrossfade | NSViewControllerTransitionAllowUserInteraction;
    tabs.canPropagateSelectedChildViewControllerTitle = YES;
    NSArray<NSArray *> *panes = @[
        @[@"General", @"gearshape", [GeneralPane new]],
        @[@"Appearance", @"paintbrush", [AppearancePane new]],
        @[@"Layout", @"sidebar.left", [LayoutPane new]],
        @[@"Tabs", @"square.on.square", [TabsPane new]],
        @[@"Search", @"magnifyingglass", [SearchPane new]],
        @[@"Websites", @"globe", [WebsitesPane new]],
        @[@"Boosts", @"wand.and.stars", [BoostsPane new]],
        @[@"Shortcuts", @"command", [ShortcutsPane new]],
        @[@"Advanced", @"gearshape.2", [AdvancedPane new]]
    ];
    for (NSArray *p in panes) {
        NSString *title = p[0];
        NSString *symbol = p[1];
        NSViewController *vc = p[2];
        vc.title = title;
        NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:vc];
        item.label = title;
        item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
        [tabs addTabViewItem:item];
    }
    NSWindow *window = [NSWindow windowWithContentViewController:tabs];
    window.styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    window.toolbarStyle = NSWindowToolbarStylePreference;
    window.releasedWhenClosed = NO;
    [window setFrameAutosaveName:@"BrookSettings"];
    return [super initWithWindow:window];
}

- (void)show { [self showPane:nil]; }

- (void)showPane:(NSString *)pane {
    NSTabViewController *tabs = [self.window.contentViewController isKindOfClass:NSTabViewController.class]
        ? (NSTabViewController *)self.window.contentViewController : nil;
    if (pane && tabs) {
        NSArray<NSTabViewItem *> *items = tabs.tabViewItems;
        for (NSUInteger i = 0; i < items.count; i++) {
            if ([items[i].label isEqualToString:pane]) {
                tabs.selectedTabViewItemIndex = (NSInteger)i;
                break;
            }
        }
    }
    if (!self.window.isVisible) [self.window center];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
}

@end

// MARK: - General

@implementation GeneralPane

- (NSView *)makeContent {
    SettingsForm *f = [SettingsForm new];
    NSTextField *startURL = [Controls field:Settings.startPageURL placeholder:@"https://example.com" width:260
                                   onCommit:^(NSString *v) { Settings.startPageURL = v; }];
    startURL.enabled = Settings.launchBehavior == LaunchBehaviorStartPage;
    __weak NSTextField *weakStart = startURL;
    [f row:@"On launch" views:@[
        [Controls popupWithTitles:EnumTitles(LaunchBehaviorCount, ^(NSInteger i) { return LaunchBehaviorTitle((LaunchBehavior)i); })
                    selectedIndex:Settings.launchBehavior
                         onChange:^(NSInteger i) {
            Settings.launchBehavior = (LaunchBehavior)i;
            weakStart.enabled = i == LaunchBehaviorStartPage;
        }],
        startURL
    ]];
    [f note:@"Pinned tabs and favorites always come back."];
    static const std::vector<NSInteger> quitOptions = {0, 2, 5, 10, 20, 50};
    NSMutableArray<NSString *> *quitTitles = [NSMutableArray array];
    for (NSInteger n : quitOptions) {
        [quitTitles addObject:n == 0 ? @"Never" : [NSString stringWithFormat:@"With %ld or more tabs open", (long)n]];
    }
    auto quitIt = std::find(quitOptions.begin(), quitOptions.end(), Settings.quitWarningTabs);
    [f row:@"Ask before quitting" view:[Controls popupWithTitles:quitTitles
                                                   selectedIndex:quitIt == quitOptions.end() ? 0 : quitIt - quitOptions.begin()
                                                        onChange:^(NSInteger i) { Settings.quitWarningTabs = quitOptions[(size_t)i]; }]];

    [f separator];
    NSTextField *customURL = [Controls field:Settings.newTabURL placeholder:@"https://example.com" width:260
                                    onCommit:^(NSString *v) { Settings.newTabURL = v; }];
    // Disabled rather than hidden, so picking an option doesn't resize the window.
    customURL.enabled = Settings.newTabPage == NewTabPageCustom;
    __weak NSTextField *weakURL = customURL;
    NSPopUpButton *page = [Controls popupWithTitles:EnumTitles(NewTabPageCount, ^(NSInteger i) { return NewTabPageTitle((NewTabPage)i); })
                                      selectedIndex:Settings.newTabPage
                                           onChange:^(NSInteger i) {
        Settings.newTabPage = (NewTabPage)i;
        weakURL.enabled = i == NewTabPageCustom;
    }];
    [f row:@"New tabs show" views:@[page, customURL]];

    NSPopUpButton *spaces = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [spaces addItemWithTitle:@"Current space"];
    NSArray<Space *> *allSpaces = BrowserState.shared.spaces;
    for (Space *s in allSpaces) {
        [spaces addItemWithTitle:s.name];
        spaces.lastItem.representedObject = s.identifier;
    }
    NSUUID *linkSpace = Settings.externalLinksSpace;
    if (linkSpace) {
        NSUInteger i = [allSpaces indexOfObjectPassingTest:^BOOL(Space *s, NSUInteger, BOOL *) {
            return [s.identifier isEqual:linkSpace];
        }];
        if (i != NSNotFound) [spaces selectItemAtIndex:(NSInteger)i + 1];
    }
    [spaces brook_onAction:^(id c) {
        id obj = ((NSPopUpButton *)c).selectedItem.representedObject;
        Settings.externalLinksSpace = [obj isKindOfClass:NSUUID.class] ? obj : nil;
    }];
    [f row:@"Open links from apps in" view:spaces];

    [f separator];
    NSPathControl *folderLabel = [NSPathControl new];
    folderLabel.URL = Settings.downloadFolder;
    folderLabel.pathStyle = NSPathStylePopUp;
    folderLabel.editable = NO;
    __weak GeneralPane *weakSelf = self;
    __weak NSPathControl *weakFolder = folderLabel;
    NSButton *choose = [Controls button:@"Choose…" action:^{
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseDirectories = YES;
        panel.canChooseFiles = NO;
        panel.canCreateDirectories = YES;
        panel.directoryURL = Settings.downloadFolder;
        NSWindow *window = weakSelf.view.window;
        if (!window) return;
        [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
            NSURL *url = panel.URL;
            if (r != NSModalResponseOK || !url) return;
            Settings.downloadFolder = url;
            weakFolder.URL = url;
        }];
    }];
    NSStackView *folderRow = [NSStackView stackViewWithViews:@[folderLabel, choose]];
    folderRow.spacing = 8;
    [f row:@"Save downloads to" views:@[
        folderRow,
        [Controls check:@"Ask where to save each download" on:Settings.askDownloadLocation
               onChange:^(BOOL on) { Settings.askDownloadLocation = on; }]
    ]];

    [f separator];
    [f row:@"Default browser" view:[Controls button:@"Make Brook the Default Browser" action:^{
        NSURL *appURL = NSBundle.mainBundle.bundleURL;
        [NSWorkspace.sharedWorkspace setDefaultApplicationAtURL:appURL toOpenURLsWithScheme:@"http"
                                              completionHandler:^(NSError *) {}];
    }]];
    return [f view];
}

@end

// MARK: - Appearance

/// A small colour well that reports its colour as hex while it's being picked.
static NSColorWell *HexWell(NSString *hex, void (^onChange)(NSString *hex)) {
    NSColorWell *well = [NSColorWell colorWellWithStyle:NSColorWellStyleMinimal];
    well.color = [NSColor brook_colorWithHex:hex] ?: NSColor.controlAccentColor;
    [well.widthAnchor constraintEqualToConstant:44].active = YES;
    [well brook_onAction:^(id c) { onChange(((NSColorWell *)c).color.brook_hexString); }];
    return well;
}

@implementation AppearancePane

- (instancetype)initWithNibName:(NSNibName)nib bundle:(NSBundle *)bundle {
    if ((self = [super initWithNibName:nib bundle:bundle])) self.rebuildKeys = [NSSet setWithObjects:@"*", @"appearancePresets", nil];
    return self;
}

- (NSView *)makeContent {
    SettingsForm *f = [SettingsForm new];
    [f row:@"Appearance" view:[Controls segmentedWithTitles:EnumTitles(ThemeModeCount, ^(NSInteger i) { return ThemeModeTitle((ThemeMode)i); })
                                              selectedIndex:Settings.theme
                                                   onChange:^(NSInteger i) { Settings.theme = (ThemeMode)i; }]];
    [f note:@"A space can have its own: right-click its dot and choose Edit Space."];

    // Presets: every look-related setting in one go.
    NSDictionary<NSString *, NSDictionary *> *presets = Settings.appearancePresets;
    NSArray<NSString *> *names = [presets.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSPopUpButton *presetMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    [presetMenu addItemWithTitle:@"Presets"];
    NSMenu *menu = presetMenu.menu;
    __weak AppearancePane *weakSelf = self;
    for (NSString *name in names) {
        NSDictionary *values = presets[name];
        [menu addItem:[NSMenuItem brook_itemWithTitle:name action:^{ [Settings applyAppearance:values]; }]];
    }
    if (names.count) [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[NSMenuItem brook_itemWithTitle:@"Save Current Look…" action:^{ [weakSelf promptSavePreset]; }]];
    [menu addItem:[NSMenuItem brook_itemWithTitle:@"Copy Current Look" action:^{
        NSData *json = [NSJSONSerialization dataWithJSONObject:Settings.currentAppearance options:NSJSONWritingSortedKeys error:nil];
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]
                                          forType:NSPasteboardTypeString];
    }]];
    [menu addItem:[NSMenuItem brook_itemWithTitle:@"Paste Look" action:^{
        NSString *s = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
        id v = s ? [NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        if ([v isKindOfClass:NSDictionary.class]) [Settings applyAppearance:v]; else NSBeep();
    }]];
    if (names.count) {
        NSMenu *remove = [NSMenu new];
        for (NSString *name in names) {
            [remove addItem:[NSMenuItem brook_itemWithTitle:name action:^{
                NSMutableDictionary *all = [Settings.appearancePresets mutableCopy];
                [all removeObjectForKey:name];
                Settings.appearancePresets = all;
            }]];
        }
        NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:@"Delete Preset" action:nil keyEquivalent:@""];
        removeItem.submenu = remove;
        [menu addItem:removeItem];
    }
    [f row:@"Look" view:presetMenu];
    [f note:@"Save the current look to switch back later, or copy it to share."];

    [f separator];
    [f row:@"Tab style" view:[Controls popupWithTitles:EnumTitles(TabStyleCount, ^(NSInteger i) { return TabStyleTitle((TabStyle)i); })
                                         selectedIndex:Settings.tabStyle
                                              onChange:^(NSInteger i) { Settings.tabStyle = (TabStyle)i; }]];
    NSColorWell *accentWell = HexWell(Settings.accentColorHex, ^(NSString *hex) { Settings.accentColorHex = hex; });
    accentWell.enabled = Settings.accentSource == AccentSourceCustom;
    __weak NSColorWell *weakWell = accentWell;
    NSSegmentedControl *accent = [Controls segmentedWithTitles:EnumTitles(AccentSourceCount, ^(NSInteger i) { return AccentSourceTitle((AccentSource)i); })
                                                 selectedIndex:Settings.accentSource
                                                      onChange:^(NSInteger i) {
        Settings.accentSource = (AccentSource)i;
        weakWell.enabled = i == AccentSourceCustom;
    }];
    NSStackView *accentRow = [NSStackView stackViewWithViews:@[accent, accentWell]];
    accentRow.spacing = 8;
    [f row:@"Accent" view:accentRow];
    [f note:@"Used for the loading bar, outlines and accent-bar tabs."];
    [f row:@"Font" view:[Controls popupWithTitles:EnumTitles(UIFontStyleCount, ^(NSInteger i) { return UIFontStyleTitle((UIFontStyle)i); })
                                    selectedIndex:Settings.uiFont
                                         onChange:^(NSInteger i) { Settings.uiFont = (UIFontStyle)i; }]];
    [f row:@"Space colour strength" view:[Controls sliderWithMin:0 max:1.5 value:(double)Settings.tintStrength width:220 ticks:0
                                                          format:^NSString *(double v) {
        return [NSString stringWithFormat:@"%ld%%", (long)round(v * 100)];
    } onChange:^(double v) { Settings.tintStrength = (CGFloat)v; }]];

    [f separator];
    NSView *opacity = [Controls sliderWithMin:0.3 max:1 value:(double)Settings.chromeOpacity width:160 ticks:0
                                       format:^NSString *(double v) { return [NSString stringWithFormat:@"%ld%%", (long)round(v * 100)]; }
                                     onChange:^(double v) { Settings.chromeOpacity = (CGFloat)v; }];
    for (NSView *v in opacity.subviews) if ([v isKindOfClass:NSControl.class]) ((NSControl *)v).enabled = Settings.chromeMaterial == ChromeMaterialSolid;
    __weak NSView *weakOpacity = opacity;
    [f row:@"Sidebar material" views:@[
        [Controls segmentedWithTitles:EnumTitles(ChromeMaterialCount, ^(NSInteger i) { return ChromeMaterialTitle((ChromeMaterial)i); })
                        selectedIndex:Settings.chromeMaterial
                             onChange:^(NSInteger i) {
            Settings.chromeMaterial = (ChromeMaterial)i;
            for (NSView *v in weakOpacity.subviews) if ([v isKindOfClass:NSControl.class]) ((NSControl *)v).enabled = i == ChromeMaterialSolid;
        }],
        opacity
    ]];
    [f row:@"Window margin" view:[Controls sliderWithMin:0 max:20 value:(double)Settings.pageMargin width:220 ticks:11
                                                  format:^NSString *(double v) {
        return v == 0 ? @"None" : [NSString stringWithFormat:@"%ld pt", (long)v];
    } onChange:^(double v) { Settings.pageMargin = (CGFloat)v; }]];
    [f row:@"Corner radius" view:[Controls sliderWithMin:0 max:24 value:(double)Settings.cornerRadius width:220 ticks:13
                                                  format:^NSString *(double v) {
        return v == 0 ? @"Square" : [NSString stringWithFormat:@"%ld pt", (long)v];
    } onChange:^(double v) { Settings.cornerRadius = (CGFloat)v; }]];
    [f row:@"Page shadow" view:[Controls segmentedWithTitles:EnumTitles(CardShadowCount, ^(NSInteger i) { return CardShadowTitle((CardShadow)i); })
                                               selectedIndex:Settings.cardShadow
                                                    onChange:^(NSInteger i) { Settings.cardShadow = (CardShadow)i; }]];
    [f note:@"Set margin and radius to zero for an edge-to-edge page with no floating card."];

    [f separator];
    [f row:@"App icon" view:[Controls popupWithTitles:EnumTitles(AppIconStyleCount, ^(NSInteger i) { return AppIconStyleTitle((AppIconStyle)i); })
                                        selectedIndex:Settings.appIcon
                                             onChange:^(NSInteger i) { Settings.appIcon = (AppIconStyle)i; }]];
    return [f view];
}

- (void)promptSavePreset {
    NSWindow *window = self.view.window;
    if (!window) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Save the current look";
    alert.informativeText = @"Saves everything under Appearance and Layout. A preset with the same name is replaced.";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    field.placeholderString = @"Name";
    alert.accessoryView = field;
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.window.initialFirstResponder = field;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        NSString *name = BrookTrim(field.stringValue);
        if (r != NSAlertFirstButtonReturn || name.length == 0) return;
        NSMutableDictionary *all = [Settings.appearancePresets mutableCopy];
        all[name] = Settings.currentAppearance;
        Settings.appearancePresets = all;
    }];
}

@end

// MARK: - Layout

@implementation LayoutPane {
    NSPopUpButton *_hidePopup;
    id<NSObject> _hideObserver;
}

- (void)dealloc {
    if (_hideObserver) [NSNotificationCenter.defaultCenter removeObserver:_hideObserver];
}

- (NSView *)makeContent {
    SettingsForm *f = [SettingsForm new];
    [f row:@"Tabs" view:[Controls segmentedWithTitles:EnumTitles(TabLayoutCount, ^(NSInteger i) { return TabLayoutTitle((TabLayout)i); })
                                        selectedIndex:Settings.tabLayout
                                             onChange:^(NSInteger i) { Settings.tabLayout = (TabLayout)i; }]];
    [f note:@"Top puts the address bar and tabs above the page, with favorites beside the address bar. Compact fits it all in one row: click the selected tab to see and edit its address."];
    [f row:@"Many top tabs" view:[Controls check:@"Shrink to fit instead of scrolling" on:Settings.topTabsShrink
                                         onChange:^(BOOL on) { Settings.topTabsShrink = on; }]];
    [f row:@"Sidebar" view:[Controls segmentedWithTitles:EnumTitles(SidebarPositionCount, ^(NSInteger i) { return SidebarPositionTitle((SidebarPosition)i); })
                                           selectedIndex:Settings.sidebarPosition
                                                onChange:^(NSInteger i) { Settings.sidebarPosition = (SidebarPosition)i; }]];
    _hidePopup = [Controls popupWithTitles:EnumTitles(ChromeAutoHideCount, ^(NSInteger i) { return ChromeAutoHideTitle((ChromeAutoHide)i); })
                             selectedIndex:Settings.autoHide
                                  onChange:^(NSInteger i) { Settings.autoHide = (ChromeAutoHide)i; }];
    [f row:@"Hide sidebar" view:_hidePopup];
    [f note:@"Same as View → Hide Sidebar (⌘S). A hidden sidebar slides back when the pointer reaches the window's edge. Drag the sidebar's edge in far enough and it becomes a narrow rail of icons."];
    // ⌘S changes this setting too; keep the menu in step without rebuilding the pane.
    if (!_hideObserver) {
        __weak LayoutPane *weakSelf = self;
        _hideObserver = [NSNotificationCenter.defaultCenter addObserverForName:BrookSettingsDidChangeNotification
                                                                        object:nil
                                                                         queue:NSOperationQueue.mainQueue
                                                                    usingBlock:^(NSNotification *note) {
            if (![note.userInfo[@"key"] isEqual:@"autoHide"]) return;
            LayoutPane *self_ = weakSelf;
            if (self_) [self_->_hidePopup selectItemAtIndex:Settings.autoHide];
        }];
    }

    [f separator];
    [f row:@"Tab rows" view:[Controls segmentedWithTitles:EnumTitles(TabDensityCount, ^(NSInteger i) { return TabDensityTitle((TabDensity)i); })
                                            selectedIndex:Settings.tabDensity
                                                 onChange:^(NSInteger i) { Settings.tabDensity = (TabDensity)i; }]];
    [f row:@"Tab text size" view:[Controls sliderWithMin:11 max:17 value:(double)Settings.tabFontSize width:220 ticks:7
                                                  format:^NSString *(double v) {
        return [NSString stringWithFormat:@"%ld pt", (long)v];
    } onChange:^(double v) { Settings.tabFontSize = (CGFloat)v; }]];
    [f row:@"" view:[Controls check:@"Show the site under each tab's title" on:Settings.tabSubtitles
                           onChange:^(BOOL on) { Settings.tabSubtitles = on; }]];
    [f row:@"Close buttons" view:[Controls segmentedWithTitles:EnumTitles(CloseButtonVisibilityCount, ^(NSInteger i) { return CloseButtonVisibilityTitle((CloseButtonVisibility)i); })
                                                 selectedIndex:Settings.closeButtons
                                                      onChange:^(NSInteger i) { Settings.closeButtons = (CloseButtonVisibility)i; }]];
    [f row:@"While loading" view:[Controls segmentedWithTitles:EnumTitles(LoadingIndicatorCount, ^(NSInteger i) { return LoadingIndicatorTitle((LoadingIndicator)i); })
                                                 selectedIndex:Settings.loadingIndicator
                                                      onChange:^(NSInteger i) { Settings.loadingIndicator = (LoadingIndicator)i; }]];

    [f separator];
    [f row:@"Show in sidebar" views:@[
        [Controls check:@"Address bar" on:Settings.showAddressBar onChange:^(BOOL on) { Settings.showAddressBar = on; }],
        [Controls check:@"Favorites" on:Settings.showFavorites onChange:^(BOOL on) { Settings.showFavorites = on; }],
        [Controls check:@"Spaces and tools bar" on:Settings.showBottomBar onChange:^(BOOL on) { Settings.showBottomBar = on; }]
    ]];
    [f row:@"Favorites per row" view:[Controls sliderWithMin:2 max:6 value:(double)Settings.favoritesColumns width:220 ticks:5
                                                      format:^NSString *(double v) {
        return [NSString stringWithFormat:@"%ld", (long)v];
    } onChange:^(double v) { Settings.favoritesColumns = (NSInteger)v; }]];
    [f row:@"Address shows" view:[Controls popupWithTitles:EnumTitles(AddressDisplayCount, ^(NSInteger i) { return AddressDisplayTitle((AddressDisplay)i); })
                                             selectedIndex:Settings.addressDisplay
                                                  onChange:^(NSInteger i) { Settings.addressDisplay = (AddressDisplay)i; }]];
    [f row:@"Link previews" view:[Controls segmentedWithTitles:EnumTitles(LinkPreviewCount, ^(NSInteger i) { return LinkPreviewTitle((LinkPreview)i); })
                                                 selectedIndex:Settings.linkPreview
                                                      onChange:^(NSInteger i) { Settings.linkPreview = (LinkPreview)i; }]];
    [f note:@"Where a link's address shows while the pointer is over it."];

    // Toolbar: a checkbox per button, in its saved order; the rest follow in their default order.
    NSArray<NSNumber *> *items = Settings.toolbarItems;
    NSMutableArray<NSNumber *> *order = [items mutableCopy];
    for (NSInteger i = 0; i < ToolbarItemCount; i++) if (![order containsObject:@(i)]) [order addObject:@(i)];
    NSMutableArray<NSView *> *checks = [NSMutableArray array];
    for (NSNumber *n in order) {
        ToolbarItem item = (ToolbarItem)n.integerValue;
        [checks addObject:[Controls check:ToolbarItemTitle(item) on:[items containsObject:n] onChange:^(BOOL on) {
            NSMutableArray *now = [Settings.toolbarItems mutableCopy];
            if (on) [now addObject:@(item)]; else [now removeObject:@(item)];
            Settings.toolbarItems = now;
        }]];
    }
    NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:4 rows:0];
    for (NSUInteger i = 0; i < checks.count; i += 4) {
        NSMutableArray *row = [NSMutableArray array];
        for (NSUInteger j = i; j < i + 4; j++) [row addObject:j < checks.count ? checks[j] : NSGridCell.emptyContentView];
        [grid addRowWithViews:row];
    }
    grid.rowSpacing = 6;
    grid.columnSpacing = 14;
    // A nested grid has no text baseline, so first-baseline alignment would put the label's
    // baseline at the grid's top edge. The label and the checkboxes share a font and height,
    // so top-aligning them lines up their text.
    NSGridRow *toolbarRow = [f row:@"Toolbar buttons" view:grid];
    toolbarRow.rowAlignment = NSGridRowAlignmentNone;
    toolbarRow.yPlacement = NSGridCellPlacementTop;
    [f note:@"Shown in the order you turn them on, beside the traffic lights."];
    return [f view];
}

@end

// MARK: - Tabs

@implementation TabsPane {
    EditableList *_list;
    Debouncer *_iconReload;
}

- (NSView *)makeContent {
    // Site icons come in from the disk cache after the rows first draw; refresh them together.
    [NSNotificationCenter.defaultCenter removeObserver:self name:FaviconStoreDidLoadIconNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(iconLoaded:)
                                               name:FaviconStoreDidLoadIconNotification object:nil];
    SettingsForm *f = [SettingsForm new];
    [f row:@"New tabs open" view:[Controls popupWithTitles:EnumTitles(NewTabPositionCount, ^(NSInteger i) { return NewTabPositionTitle((NewTabPosition)i); })
                                             selectedIndex:Settings.newTabPosition
                                                  onChange:^(NSInteger i) { Settings.newTabPosition = (NewTabPosition)i; }]];
    [f row:@"Closing a pinned tab" view:[Controls popupWithTitles:EnumTitles(PinnedCloseBehaviorCount, ^(NSInteger i) { return PinnedCloseBehaviorTitle((PinnedCloseBehavior)i); })
                                                    selectedIndex:Settings.pinnedClose
                                                         onChange:^(NSInteger i) { Settings.pinnedClose = (PinnedCloseBehavior)i; }]];
    [f row:@"After closing a tab, go to" view:[Controls popupWithTitles:EnumTitles(CloseSelectsCount, ^(NSInteger i) { return CloseSelectsTitle((CloseSelects)i); })
                                                          selectedIndex:Settings.closeSelects
                                                               onChange:^(NSInteger i) { Settings.closeSelects = (CloseSelects)i; }]];
    [f row:@"Links" views:@[
        [Controls check:@"⌘-click opens links in the background" on:Settings.linksOpenInBackground
               onChange:^(BOOL on) { Settings.linksOpenInBackground = on; }],
        [Controls check:@"Middle-click closes a tab" on:Settings.middleClickCloses
               onChange:^(BOOL on) { Settings.middleClickCloses = on; }]
    ]];
    [f note:@"Hold ⇧ to do the opposite. Middle-clicking a link always opens it in a new tab."];
    [f row:@"Swipe on the page" view:[Controls popupWithTitles:EnumTitles(PageSwipeCount, ^(NSInteger i) { return PageSwipeTitle((PageSwipe)i); })
                                                 selectedIndex:Settings.pageSwipe
                                                      onChange:^(NSInteger i) { Settings.pageSwipe = (PageSwipe)i; }]];
    [f row:@"" view:[Controls check:@"Swipe sideways on the sidebar to switch spaces" on:Settings.swipeSwitchesSpaces
                           onChange:^(BOOL on) { Settings.swipeSwitchesSpaces = on; }]];
    [f note:@"Spaces can also override pinned-tab closing and archiving: right-click a space dot → Edit Space."];

    [f separator];
    static const std::vector<NSInteger> unloadOptions = {0, 15, 30, 60, 240};
    NSMutableArray<NSString *> *unloadTitles = [NSMutableArray array];
    for (NSInteger m : unloadOptions) {
        [unloadTitles addObject:m == 0 ? @"Never"
            : (m < 60 ? [NSString stringWithFormat:@"After %ld minutes", (long)m]
                      : [NSString stringWithFormat:@"After %ld hour%@", (long)(m / 60), m == 60 ? @"" : @"s"])];
    }
    NSInteger hibernate = Settings.hibernateMinutes;
    auto unloadIt = std::find(unloadOptions.begin(), unloadOptions.end(), hibernate);
    NSInteger unloadSelected = unloadIt != unloadOptions.end() ? hibernate : 30;
    NSInteger unloadIndex = std::find(unloadOptions.begin(), unloadOptions.end(), unloadSelected) - unloadOptions.begin();
    [f row:@"Unload background tabs" view:[Controls popupWithTitles:unloadTitles selectedIndex:unloadIndex
                                                           onChange:^(NSInteger i) { Settings.hibernateMinutes = unloadOptions[(size_t)i]; }]];
    [f note:@"Unloaded tabs stay in the sidebar and reload when you click them. Saves memory."];

    static const std::vector<NSInteger> archiveOptions = {0, 12, 24, 168, 720};
    NSString *(^archiveTitle)(NSInteger) = ^NSString *(NSInteger h) {
        switch (h) {
            case 0: return @"Never";
            case 12: return @"After 12 hours";
            case 24: return @"After 1 day";
            case 168: return @"After 7 days";
            default: return @"After 30 days";
        }
    };
    NSMutableArray<NSString *> *archiveTitles = [NSMutableArray array];
    for (NSInteger h : archiveOptions) [archiveTitles addObject:archiveTitle(h)];
    NSInteger archiveHours = Settings.archiveHours;
    auto archiveIt = std::find(archiveOptions.begin(), archiveOptions.end(), archiveHours);
    NSInteger archiveIndex = archiveIt != archiveOptions.end() ? archiveIt - archiveOptions.begin() : 0;
    [f row:@"Archive unused tabs" view:[Controls popupWithTitles:archiveTitles selectedIndex:archiveIndex
                                                        onChange:^(NSInteger i) { Settings.archiveHours = archiveOptions[(size_t)i]; }]];
    [f note:@"Closes regular (unpinned) tabs you haven't looked at, like Arc. Tabs playing audio or video are kept. Archived tabs are listed below."];

    EditableList *l = [[EditableList alloc] initWithColumns:{{@"title", @"Archived Tab", 390}, {@"date", @"Archived", 120}}
                                                     height:170];
    l.table.dataSource = self;
    l.table.delegate = self;
    l.table.doubleAction = @selector(restoreSelected);
    l.table.target = self;
    l.segment.hidden = YES;
    __weak TabsPane *weakSelf = self;
    l.extra = @[
        [Controls button:@"Restore" action:^{ [weakSelf restoreSelected]; }],
        [Controls button:@"Clear Archive" action:^{
            [BrowserState.shared clearArchive];
            TabsPane *self = weakSelf;
            if (self) [self->_list reload];
        }]
    ];
    [l.container.widthAnchor constraintEqualToConstant:520].active = YES;
    l.emptyLabel.stringValue = @"No archived tabs";
    _list = l;
    [l reload];
    [f row:@"" view:l.container];
    return [f view];
}

- (void)iconLoaded:(NSNotification *)note {
    if (!_list.table.window) return;
    if (!_iconReload) _iconReload = [[Debouncer alloc] initWithDelay:0.1];
    __weak TabsPane *weakSelf = self;
    [_iconReload call:^{
        TabsPane *self_ = weakSelf;
        if (self_) [self_->_list.table reloadData];
    }];
}

- (void)restoreSelected {
    if (!_list) return;
    NSInteger row = _list.table.selectedRow;
    if (row < 0) return;
    [BrowserState.shared restoreArchivedAt:row];
    [_list reload];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)BrowserState.shared.archived.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    ArchivedTab *a = BrowserState.shared.archived[(NSUInteger)row];
    BOOL isDate = [tableColumn.identifier isEqualToString:@"date"];
    NSString *text;
    if (isDate) {
        text = BrookRelativeNamed(a.date, [NSDate date]);
    } else {
        text = a.title ?: @"";
    }
    NSTextField *label = [NSTextField labelWithString:text];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.toolTip = a.url.absoluteString;
    if (isDate) {
        label.textColor = NSColor.secondaryLabelColor;
        return label;
    }
    // Title cell: site icon + title, like the sidebar.
    NSImage *image = [FaviconStore.shared cachedIconForHost:BrookHost(a.url) ?: @""]
        ?: [NSImage brook_symbol:@"globe" size:12] ?: [NSImage new];
    NSImageView *icon = [NSImageView imageViewWithImage:image];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [icon.widthAnchor constraintEqualToConstant:16].active = YES;
    [icon.heightAnchor constraintEqualToConstant:16].active = YES;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *stack = [NSStackView stackViewWithViews:@[icon, label]];
    stack.spacing = 6;
    stack.toolTip = a.url.absoluteString;
    return stack;
}

@end

// MARK: - Search

@implementation SearchPane {
    EditableList *_list;
    NSMutableArray<SearchEngine *> *_engines;
}

/// Keep private copies of the engines so edits don't touch the shared cache.
static NSMutableArray<SearchEngine *> *CopyEngines(NSArray<SearchEngine *> *engines) {
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:engines.count];
    for (SearchEngine *e in engines) [a addObject:[e copy]];
    return a;
}

- (NSView *)makeContent {
    _engines = CopyEngines(SearchEngines.all);
    SettingsForm *f = [SettingsForm new];
    NSPopUpButton *def = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (SearchEngine *e in _engines) [def addItemWithTitle:e.name];
    NSString *defaultID = SearchEngines.defaultEngine.identifier;
    NSUInteger defIndex = [_engines indexOfObjectPassingTest:^BOOL(SearchEngine *e, NSUInteger, BOOL *) {
        return [e.identifier isEqualToString:defaultID];
    }];
    [def selectItemAtIndex:defIndex != NSNotFound ? (NSInteger)defIndex : 0];
    __weak SearchPane *weakSelf = self;
    [def brook_onAction:^(id c) {
        SearchPane *self = weakSelf;
        if (!self) return;
        NSInteger i = ((NSPopUpButton *)c).indexOfSelectedItem;
        if (i >= 0 && i < (NSInteger)self->_engines.count) Settings.defaultSearchEngine = self->_engines[(NSUInteger)i].identifier;
    }];
    [f row:@"Default search engine" view:def];
    [f note:@"Spaces can use a different engine: right-click a space dot → Edit Space."];

    EditableList *l = [[EditableList alloc] initWithColumns:{{@"name", @"Name", 130}, {@"keyword", @"Keyword", 70},
                                                             {@"template", @"URL (%s = search terms)", 340}}
                                                     height:200];
    l.table.dataSource = self;
    l.table.delegate = self;
    l.onAdd = ^{
        SearchPane *self = weakSelf;
        if (!self) return;
        [self->_engines addObject:[SearchEngine engineWithID:NSUUID.UUID.UUIDString name:@"New Engine"
                                                 urlTemplate:@"https://example.com/search?q=%s" keyword:@""]];
        [self commit];
        [self->_list.table reloadData];
        NSInteger row = (NSInteger)self->_engines.count - 1;
        [self->_list.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self->_list.table editColumn:0 row:row withEvent:nil select:YES];
    };
    l.onRemove = ^(NSInteger row) {
        SearchPane *self = weakSelf;
        if (!self || self->_engines.count <= 1 || row < 0 || row >= (NSInteger)self->_engines.count) { NSBeep(); return; }
        [self->_engines removeObjectAtIndex:(NSUInteger)row];
        [self commit];
        [self rebuild];
    };
    l.extra = @[[Controls button:@"Restore Defaults" action:^{
        SearchEngines.all = SearchEngine.builtIn;
        [weakSelf rebuild];
    }]];
    [l.container.widthAnchor constraintEqualToConstant:560].active = YES;
    _list = l;
    // The list has no text baseline (as with Layout's toolbar grid): top-align the label with it.
    NSGridRow *enginesRow = [f row:@"Search engines" view:l.container];
    enginesRow.rowAlignment = NSGridRowAlignmentNone;
    enginesRow.yPlacement = NSGridCellPlacementTop;
    [f note:@"Type a keyword and a space in the command bar to search with that engine, e.g. “yt cats”. Double-click a cell to edit it."];

    [f separator];
    [f row:@"Command bar shows" views:@[
        [Controls check:@"Open tabs" on:Settings.commandBarTabs onChange:^(BOOL on) { Settings.commandBarTabs = on; }],
        [Controls check:@"History" on:Settings.commandBarHistory onChange:^(BOOL on) { Settings.commandBarHistory = on; }],
        [Controls check:@"Search suggestions" on:Settings.commandBarSuggestions onChange:^(BOOL on) { Settings.commandBarSuggestions = on; }]
    ]];
    [f row:@"Results" view:[Controls sliderWithMin:4 max:12 value:(double)Settings.commandBarRows width:220 ticks:9
                                            format:^NSString *(double v) { return [NSString stringWithFormat:@"%ld", (long)v]; }
                                          onChange:^(double v) { Settings.commandBarRows = (NSInteger)v; }]];
    [f row:@"Position" view:[Controls segmentedWithTitles:EnumTitles(CommandBarPositionCount, ^(NSInteger i) { return CommandBarPositionTitle((CommandBarPosition)i); })
                                            selectedIndex:Settings.commandBarPosition
                                                 onChange:^(NSInteger i) { Settings.commandBarPosition = (CommandBarPosition)i; }]];
    return [f viewWithWidth:740];
}

- (void)commit {
    SearchEngines.all = CopyEngines(_engines);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)_engines.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier ?: @"";
    SearchEngine *e = _engines[(NSUInteger)row];
    NSString *value = [identifier isEqualToString:@"name"] ? e.name
        : [identifier isEqualToString:@"keyword"] ? e.keyword : e.urlTemplate;
    NSTextField *field = [NSTextField textFieldWithString:value ?: @""];
    field.bordered = NO;
    field.drawsBackground = NO;
    field.editable = YES;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    if ([identifier isEqualToString:@"template"] && !e.isValid) {
        field.textColor = NSColor.systemRedColor;
        field.toolTip = @"Must be a web address containing %s";
    }
    __weak SearchPane *weakSelf = self;
    [field brook_onAction:^(id c) {
        SearchPane *self = weakSelf;
        if (!self || row < 0 || row >= (NSInteger)self->_engines.count) return;
        NSString *v = BrookTrim(((NSTextField *)c).stringValue);
        SearchEngine *engine = self->_engines[(NSUInteger)row];
        if ([identifier isEqualToString:@"name"]) engine.name = v.length == 0 ? @"Untitled" : v;
        else if ([identifier isEqualToString:@"keyword"]) engine.keyword = v.lowercaseString;
        else engine.urlTemplate = v;
        [self commit];
        ((NSTextField *)c).textColor = ([identifier isEqualToString:@"template"] && !engine.isValid)
            ? NSColor.systemRedColor : NSColor.labelColor;
    }];
    if ([field.cell isKindOfClass:NSTextFieldCell.class]) ((NSTextFieldCell *)field.cell).sendsActionOnEndEditing = YES;
    return field;
}

@end

// MARK: - Websites

@implementation WebsitesPane {
    EditableList *_list;
    NSArray<NSString *> *_hosts;
    NSDictionary<NSString *, SiteOverride *> *_sites;
}

- (instancetype)initWithNibName:(NSNibName)nib bundle:(NSBundle *)bundle {
    // "contentBlocker": an ad-blocking extension was added or removed (the ad blocking note).
    if ((self = [super initWithNibName:nib bundle:bundle])) self.rebuildKeys = [NSSet setWithObjects:@"*", @"contentBlocker", nil];
    return self;
}

- (NSView *)makeContent {
    _sites = SiteSettings.all;
    _hosts = [_sites.allKeys sortedArrayUsingSelector:@selector(compare:)];
    SettingsForm *f = [SettingsForm new];
    static const std::vector<double> zooms = {0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5};
    NSMutableArray<NSString *> *zoomTitles = [NSMutableArray array];
    for (double z : zooms) [zoomTitles addObject:[NSString stringWithFormat:@"%ld%%", (long)(z * 100)]];
    double current = Settings.defaultZoom;
    auto nearest = std::min_element(zooms.begin(), zooms.end(), [current](double a, double b) {
        return std::abs(a - current) < std::abs(b - current);
    });
    [f row:@"Default page zoom" view:[Controls popupWithTitles:zoomTitles selectedIndex:nearest - zooms.begin()
                                                      onChange:^(NSInteger i) { Settings.defaultZoom = zooms[(size_t)i]; }]];
    [f row:@"JavaScript" view:[Controls check:@"Allow JavaScript" on:Settings.javascriptEnabled
                                     onChange:^(BOOL on) { Settings.javascriptEnabled = on; }]];
    [f row:@"Autoplay" view:[Controls popupWithTitles:EnumTitles(AutoplayPolicyCount, ^(NSInteger i) { return AutoplayPolicyTitle((AutoplayPolicy)i); })
                                        selectedIndex:Settings.autoplay
                                             onChange:^(NSInteger i) { Settings.autoplay = (AutoplayPolicy)i; }]];
    [f row:@"Cookie popups" view:[Controls check:@"Decline cookie popups automatically" on:Settings.blockCookiePopups
                                        onChange:^(BOOL on) { Settings.blockCookiePopups = on; }]];
    [f row:@"Ads" view:[Controls check:@"Block ads and trackers" on:Settings.blockAds
                              onChange:^(BOOL on) { Settings.blockAds = on; }]];
    if (NSString *blocker = ContentBlocker.shared.pausedFor) {
        [f note:[NSString stringWithFormat:@"Paused while “%@” is installed, so the two don’t block twice "
                                           "or undo each other’s exceptions.", blocker]];
    }

    [f separator];
    EditableList *l = [[EditableList alloc] initWithColumns:{{@"site", @"Website", 160}, {@"zoom", @"Zoom", 84}, {@"js", @"JavaScript", 92},
                                                             {@"autoplay", @"Autoplay", 160}, {@"cookies", @"Cookie Popups", 124}}
                                                     height:190];
    l.table.dataSource = self;
    l.table.delegate = self;
    l.table.rowHeight = 24;
    __weak WebsitesPane *weakSelf = self;
    l.onAdd = ^{ [weakSelf promptAddSite]; };
    l.onRemove = ^(NSInteger row) {
        WebsitesPane *self = weakSelf;
        if (!self || row < 0 || row >= (NSInteger)self->_hosts.count) return;
        [SiteSettings removeHost:self->_hosts[(NSUInteger)row]];
        [self rebuild];
    };
    [l.container.widthAnchor constraintEqualToConstant:660].active = YES;
    l.emptyLabel.stringValue = @"No sites yet. Click + or use the lock in the address bar.";
    _list = l;
    [l reload];
    // The list has no text baseline (as with Layout's toolbar grid): top-align the label with it.
    NSGridRow *sitesRow = [f row:@"Per-site settings" view:l.container];
    sitesRow.rowAlignment = NSGridRowAlignmentNone;
    sitesRow.yPlacement = NSGridCellPlacementTop;
    [f note:@"Zooming a page with ⌘+ / ⌘− remembers the level for that site. Click the lock in the address bar to change settings for the site you're on."];
    return [f viewWithWidth:880];
}

- (void)promptAddSite {
    NSWindow *window = self.view.window;
    if (!window) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Add a website";
    alert.informativeText = @"Settings apply to the site and its subdomains.";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.placeholderString = @"example.com";
    NSString *host = BrookHost(BrowserState.shared.selectedTab.url);
    if (host) field.stringValue = [SiteSettings keyForHost:host];
    alert.accessoryView = field;
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.window.initialFirstResponder = field;
    __weak WebsitesPane *weakSelf = self;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn) return;
        NSString *h = BrookTrim(field.stringValue).lowercaseString;
        NSURL *u = [NSURL URLWithString:h];
        NSString *parsed = BrookHost(u);
        if (parsed) h = parsed;
        if (![h containsString:@"."]) return;
        [SiteSettings updateHost:h change:^(SiteOverride *o) {
            o.javascript = o.javascript ?: @(Settings.javascriptEnabled);
        }];
        [weakSelf rebuild];
    }];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)_hosts.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *host = _hosts[(NSUInteger)row];
    SiteOverride *o = _sites[host];
    NSString *identifier = tableColumn.identifier ?: @"";
    if ([identifier isEqualToString:@"site"]) {
        return [NSTextField labelWithString:host];
    }
    if ([identifier isEqualToString:@"zoom"]) {
        // NaN stands for "Default" (no override).
        static const std::vector<double> zooms = {NAN, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3};
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        NSInteger selected = -1;
        for (size_t i = 0; i < zooms.size(); i++) {
            double z = zooms[i];
            [titles addObject:std::isnan(z) ? @"Default" : [NSString stringWithFormat:@"%ld%%", (long)round(z * 100)]];
            if (selected < 0 && !std::isnan(z) && o.zoom && std::abs(z - o.zoom.doubleValue) < 0.01) selected = (NSInteger)i;
        }
        return [self cellPopup:titles selected:selected < 0 ? 0 : selected onChange:^(NSInteger i) {
            double z = zooms[(size_t)i];
            [SiteSettings updateHost:host change:^(SiteOverride *s) { s.zoom = std::isnan(z) ? nil : @(z); }];
        }];
    }
    if ([identifier isEqualToString:@"js"]) {
        NSInteger selected = !o.javascript ? 0 : (o.javascript.boolValue ? 1 : 2);
        return [self cellPopup:@[@"Default", @"Allow", @"Block"] selected:selected onChange:^(NSInteger i) {
            [SiteSettings updateHost:host change:^(SiteOverride *s) { s.javascript = i == 0 ? nil : @(i == 1); }];
        }];
    }
    if ([identifier isEqualToString:@"autoplay"]) {
        NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:@"Default"];
        NSMutableArray *values = [NSMutableArray arrayWithObject:NSNull.null];
        for (NSInteger i = 0; i < AutoplayPolicyCount; i++) {
            [titles addObject:AutoplayPolicyTitle((AutoplayPolicy)i)];
            [values addObject:AutoplayPolicyRaw((AutoplayPolicy)i)];
        }
        NSUInteger found = o.autoplay ? [values indexOfObject:o.autoplay] : 0;
        NSInteger selected = found == NSNotFound ? 0 : (NSInteger)found;
        return [self cellPopup:titles selected:selected onChange:^(NSInteger i) {
            id v = values[(NSUInteger)i];
            [SiteSettings updateHost:host change:^(SiteOverride *s) { s.autoplay = v == NSNull.null ? nil : v; }];
        }];
    }
    NSInteger selected = !o.cookiePopups ? 0 : (o.cookiePopups.boolValue ? 1 : 2);
    return [self cellPopup:@[@"Default", @"Decline", @"Leave"] selected:selected onChange:^(NSInteger i) {
        [SiteSettings updateHost:host change:^(SiteOverride *s) { s.cookiePopups = i == 0 ? nil : @(i == 1); }];
    }];
}

- (NSPopUpButton *)cellPopup:(NSArray<NSString *> *)titles selected:(NSInteger)selected
                    onChange:(void (^)(NSInteger))onChange {
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    p.controlSize = NSControlSizeSmall;
    p.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    p.bordered = NO;
    [p addItemsWithTitles:titles];
    [p selectItemAtIndex:selected];
    [p brook_onAction:^(id c) { onChange(((NSPopUpButton *)c).indexOfSelectedItem); }];
    return p;
}

@end

// MARK: - Boosts

/// Field-by-field Boost equality.
static BOOL BoostsEqual(Boost *a, Boost *b) {
    if (a == b) return YES;
    if (!a || !b) return NO;
    return [a.identifier isEqual:b.identifier] && [a.name isEqualToString:b.name] && [a.site isEqualToString:b.site]
        && [a.css isEqualToString:b.css] && [a.js isEqualToString:b.js] && a.enabled == b.enabled;
}

@implementation BoostsPane {
    EditableList *_list;
    NSArray<Boost *> *_boosts;
    NSUUID *_selectedID;
    NSTextField *_nameField;
    NSTextField *_siteField;
    NSButton *_enabled;
    NSTextView *_cssView;
    NSTextView *_jsView;
    NSStackView *_editor;
    Debouncer *_saveDebounce;
}

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        _boosts = @[];
        _nameField = [NSTextField new];
        _siteField = [NSTextField new];
        _enabled = [NSButton checkboxWithTitle:@"Enabled" target:nil action:nil];
        _cssView = [BoostsPane codeView];
        _jsView = [BoostsPane codeView];
        _editor = [NSStackView new];
        _saveDebounce = [[Debouncer alloc] initWithDelay:0.6];
    }
    return self;
}

- (NSView *)makeContent {
    _boosts = Boosts.all;

    EditableList *l = [[EditableList alloc] initWithColumns:{{@"name", @"Boost", 190}} height:300];
    l.emptyLabel.stringValue = @"No Boosts";
    l.table.headerView = nil;
    l.table.dataSource = self;
    l.table.delegate = self;
    __weak BoostsPane *weakSelf = self;
    l.onAdd = ^{
        BoostsPane *self = weakSelf;
        if (!self) return;
        NSString *h = BrookHost(BrowserState.shared.selectedTab.url);
        NSString *host = h ? [SiteSettings keyForHost:h] : @"";
        Boost *b = [[Boost alloc] initWithName:host.length == 0 ? @"New Boost" : host
                                          site:host.length == 0 ? @"*" : host
                                           css:@"/* CSS for this site */\n" js:@""];
        [Boosts save:b];
        self->_boosts = Boosts.all;
        self->_selectedID = b.identifier;
        [self rebuild];
    };
    l.onRemove = ^(NSInteger row) {
        BoostsPane *self = weakSelf;
        if (!self || row < 0 || row >= (NSInteger)self->_boosts.count) return;
        [Boosts deleteID:self->_boosts[(NSUInteger)row].identifier];
        [WebViewFactory reloadSiteScripts];
        self->_boosts = Boosts.all;
        self->_selectedID = self->_boosts.firstObject.identifier;
        [self rebuild];
    };
    [l.container.widthAnchor constraintEqualToConstant:210].active = YES;
    _list = l;
    [l reload];

    _nameField.placeholderString = @"Name";
    _siteField.placeholderString = @"example.com, or * for every site";
    for (NSTextField *f in @[_nameField, _siteField]) {
        [f.widthAnchor constraintEqualToConstant:360].active = YES;
        if ([f.cell isKindOfClass:NSTextFieldCell.class]) ((NSTextFieldCell *)f.cell).sendsActionOnEndEditing = YES;
        [f brook_onAction:^(id) { [weakSelf saveEditor]; }];
    }
    [_enabled brook_onAction:^(id) { [weakSelf saveEditor]; }];
    _cssView.delegate = self;
    _jsView.delegate = self;

    SettingsForm *form = [SettingsForm new];
    form.grid.columnSpacing = 8;
    [form row:@"Name" view:_nameField];
    [form row:@"Site" view:_siteField];
    [form row:@"" view:_enabled];
    [form row:@"CSS" view:[BoostsPane scroll:_cssView height:130]];
    [form row:@"JavaScript" view:[BoostsPane scroll:_jsView height:100]];
    [form finish];
    [form.grid columnAtIndex:0].width = 70;
    NSButton *apply = [Controls button:@"Apply & Reload Page" action:^{
        [weakSelf saveEditor];
        [WebViewFactory reloadSiteScripts];
        [BrowserState.shared.selectedTab reload];
    }];
    apply.keyEquivalent = @"\r";
    NSTextField *hint = [NSTextField wrappingLabelWithString:@"Boosts restyle or script sites you choose, like Arc's Boosts. CSS applies instantly on the next load; JavaScript runs once the page starts loading."];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = NSColor.secondaryLabelColor;
    hint.preferredMaxLayoutWidth = 440;
    _editor = [NSStackView stackViewWithViews:@[form.grid, apply, hint]];
    _editor.orientation = NSUserInterfaceLayoutOrientationVertical;
    _editor.alignment = NSLayoutAttributeTrailing;
    _editor.spacing = 10;
    [hint.widthAnchor constraintEqualToConstant:440].active = YES;

    NSTextField *empty = [NSTextField wrappingLabelWithString:@"Boosts restyle or script the sites you choose, like Arc's Boosts.\n\nClick + to make one for the site you're on."];
    empty.textColor = NSColor.secondaryLabelColor;
    empty.alignment = NSTextAlignmentCenter;
    NSView *emptyBox = [NSView new];
    empty.translatesAutoresizingMaskIntoConstraints = NO;
    [emptyBox addSubview:empty];
    [NSLayoutConstraint activateConstraints:@[
        [emptyBox.widthAnchor constraintEqualToConstant:440],
        [emptyBox.heightAnchor constraintEqualToConstant:330],
        [empty.centerXAnchor constraintEqualToAnchor:emptyBox.centerXAnchor],
        [empty.centerYAnchor constraintEqualToAnchor:emptyBox.centerYAnchor],
        [empty.widthAnchor constraintEqualToConstant:300]
    ]];

    NSStackView *split = [NSStackView stackViewWithViews:@[l.container, _boosts.count == 0 ? emptyBox : _editor]];
    split.alignment = NSLayoutAttributeTop;
    split.spacing = 20;
    split.edgeInsets = NSEdgeInsetsMake(24, 24, 24, 24);
    [split.widthAnchor constraintEqualToConstant:780].active = YES;
    if (!_selectedID || [self indexOfID:_selectedID] == NSNotFound) _selectedID = _boosts.firstObject.identifier;
    [self selectCurrent];
    return split;
}

+ (NSTextView *)codeView {
    NSTextView *tv = [NSTextView new];
    tv.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    tv.automaticQuoteSubstitutionEnabled = NO;
    tv.automaticDashSubstitutionEnabled = NO;
    tv.automaticTextReplacementEnabled = NO;
    tv.automaticSpellingCorrectionEnabled = NO;
    tv.continuousSpellCheckingEnabled = NO;
    tv.richText = NO;
    tv.allowsUndo = YES;
    tv.textContainerInset = NSMakeSize(4, 6);
    tv.verticallyResizable = YES;
    tv.autoresizingMask = NSViewWidthSizable;
    tv.textContainer.widthTracksTextView = YES;
    return tv;
}

+ (NSScrollView *)scroll:(NSTextView *)tv height:(CGFloat)height {
    NSScrollView *s = [NSScrollView new];
    s.documentView = tv;
    s.hasVerticalScroller = YES;
    s.borderType = NSBezelBorder;
    [s.widthAnchor constraintEqualToConstant:360].active = YES;
    [s.heightAnchor constraintEqualToConstant:height].active = YES;
    return s;
}

- (NSUInteger)indexOfID:(NSUUID *)identifier {
    if (!identifier) return NSNotFound;
    return [_boosts indexOfObjectPassingTest:^BOOL(Boost *b, NSUInteger, BOOL *) { return [b.identifier isEqual:identifier]; }];
}

- (void)selectCurrent {
    NSUInteger i = [self indexOfID:_selectedID];
    if (i == NSNotFound) {
        _editor.hidden = _boosts.count == 0;
        return;
    }
    _editor.hidden = NO;
    [_list.table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
    Boost *b = _boosts[i];
    _nameField.stringValue = b.name ?: @"";
    _siteField.stringValue = b.site ?: @"";
    _enabled.state = b.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    _cssView.string = b.css ?: @"";
    _jsView.string = b.js ?: @"";
}

- (void)saveEditor {
    NSUInteger i = [self indexOfID:_selectedID];
    if (i == NSNotFound) return;
    Boost *original = _boosts[i];
    Boost *b = [original copy];
    b.name = _nameField.stringValue.length == 0 ? @"Untitled" : _nameField.stringValue;
    b.site = BrookTrim(_siteField.stringValue);
    b.enabled = _enabled.state == NSControlStateValueOn;
    b.css = [_cssView.string copy];
    b.js = [_jsView.string copy];
    if (BoostsEqual(b, original)) return;
    [Boosts save:b];
    _boosts = Boosts.all;
    NSInteger row = _list ? _list.table.selectedRow : -1;
    if (row >= 0) [_list.table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                                         columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [_saveDebounce call:^{ [WebViewFactory reloadSiteScripts]; }];
}

- (void)textDidChange:(NSNotification *)notification { [self saveEditor]; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)_boosts.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    Boost *b = _boosts[(NSUInteger)row];
    NSTextField *title = [NSTextField labelWithString:b.name ?: @""];
    title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    title.textColor = b.enabled ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    NSTextField *site = [NSTextField labelWithString:[b.site isEqualToString:@"*"] ? @"All sites" : (b.site ?: @"")];
    site.font = [NSFont systemFontOfSize:11];
    site.textColor = NSColor.secondaryLabelColor;
    NSStackView *stack = [NSStackView stackViewWithViews:@[title, site]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 1;
    return stack;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row { return 36; }

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (!_list) return;
    NSInteger row = _list.table.selectedRow;
    if (row < 0 || row >= (NSInteger)_boosts.count || [_boosts[(NSUInteger)row].identifier isEqual:_selectedID]) return;
    [self saveEditor];
    _selectedID = _boosts[(NSUInteger)row].identifier;
    [self selectCurrent];
}

@end

// MARK: - Advanced

@implementation AdvancedPane

- (NSView *)makeContent {
    SettingsForm *f = [SettingsForm new];
    [f row:@"Keyboard shortcuts" view:[Controls button:@"Customise in System Settings…" action:^{
        NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"];
        if (url) [NSWorkspace.sharedWorkspace openURL:url];
    }]];
    [f note:@"Every Brook command is a menu item, so you can give any of them your own shortcut: System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts → + → Brook, then type the exact menu title (e.g. “Pin Tab”)."];

    [f separator];
    __weak AdvancedPane *weakSelf = self;
    NSButton *exportB = [Controls button:@"Export Settings…" action:^{ [weakSelf exportSettings]; }];
    NSButton *importB = [Controls button:@"Import Settings…" action:^{ [weakSelf importSettings]; }];
    NSStackView *row = [NSStackView stackViewWithViews:@[exportB, importB]];
    row.spacing = 8;
    [f row:@"Settings file" view:row];
    [f note:@"Includes appearance, behaviour, search engines, per-site settings and Boosts. Tabs and history are not included."];

    [f row:@"Reset" view:[Controls button:@"Reset All Settings…" action:^{ [weakSelf resetSettings]; }]];
    return [f view];
}

- (void)exportSettings {
    NSWindow *window = self.view.window;
    if (!window) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"Brook Settings.json";
    panel.allowedContentTypes = @[UTTypeJSON];
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        NSURL *url = panel.URL;
        if (r != NSModalResponseOK || !url) return;
        NSError *error = nil;
        NSData *data = [Settings exportData:&error];
        if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
            if (!error) error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
            [[NSAlert alertWithError:error] beginSheetModalForWindow:window completionHandler:nil];
        }
    }];
}

- (void)importSettings {
    NSWindow *window = self.view.window;
    if (!window) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeJSON];
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        NSURL *url = panel.URL;
        if (r != NSModalResponseOK || !url) return;
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:nil];
        if (!data || ![Settings importData:data error:nil]) {
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"That isn't a Brook settings file.";
            [alert beginSheetModalForWindow:window completionHandler:nil];
        }
    }];
}

- (void)resetSettings {
    NSWindow *window = self.view.window;
    if (!window) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Reset all settings?";
    alert.informativeText = @"Appearance, behaviour, search engines, per-site settings and Boosts go back to their defaults. Your tabs, spaces and history are kept.";
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.buttons.firstObject.hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertFirstButtonReturn) [Settings resetAll];
    }];
}

@end

// MARK: - Shortcuts

/// A button that records the next key combination pressed while it's active.
@interface ShortcutRecorder : NSButton
@property (nonatomic, copy) NSString *shortcut;            // "" = none
@property (copy) BOOL (^onRecord)(NSString *shortcut);     // NO = refused (already used)
@end

@implementation ShortcutRecorder {
    id _monitor;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.bezelStyle = NSBezelStyleFlexiblePush;
        self.controlSize = NSControlSizeSmall;
        self.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        self.target = self;
        self.action = @selector(startRecording);
        [self.widthAnchor constraintEqualToConstant:110].active = YES;
    }
    return self;
}

- (void)setShortcut:(NSString *)shortcut {
    _shortcut = [shortcut copy];
    NSString *display = BrookShortcutDisplay(shortcut);
    self.title = display.length ? display : @"None";
}

- (void)startRecording {
    if (_monitor) { [self stopRecording]; return; }
    self.title = @"Type shortcut…";
    __weak ShortcutRecorder *weakSelf = self;
    _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        ShortcutRecorder *self_ = weakSelf;
        if (!self_) return event;
        NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                                                            NSEventModifierFlagShift | NSEventModifierFlagControl);
        NSString *key = [event charactersByApplyingModifiers:0].lowercaseString;
        if (event.keyCode == 53 && mods == 0) { [self_ stopRecording]; return nil; }                // esc: cancel
        if ((event.keyCode == 51 || event.keyCode == 117) && mods == 0) { [self_ finish:@""]; return nil; }   // delete: clear
        unichar c = key.length ? [key characterAtIndex:0] : 0;
        BOOL functionKey = c >= 0xF700 && c <= 0xF8FF;
        if (!key.length || (!(mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) && !functionKey)) {
            NSBeep();   // needs ⌘, ⌃ or ⌥ so it can't swallow typing
            return nil;
        }
        [self_ finish:BrookShortcutString(key, mods)];
        return nil;
    }];
}

- (void)finish:(NSString *)shortcut {
    [self stopRecording];
    if (self.onRecord && !self.onRecord(shortcut)) { NSBeep(); return; }
    self.shortcut = shortcut;
}

- (void)stopRecording {
    if (_monitor) [NSEvent removeMonitor:_monitor];
    _monitor = nil;
    self.shortcut = _shortcut;
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    if (!newWindow) [self stopRecording];
    [super viewWillMoveToWindow:newWindow];
}

@end

@implementation ShortcutsPane

- (instancetype)initWithNibName:(NSNibName)nib bundle:(NSBundle *)bundle {
    if ((self = [super initWithNibName:nib bundle:bundle])) self.rebuildKeys = [NSSet setWithObjects:@"*", @"shortcuts", nil];
    return self;
}

- (NSView *)makeContent {
    NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:3 rows:0];
    grid.rowSpacing = 6;
    grid.columnSpacing = 10;
    NSDictionary<NSString *, NSString *> *overrides = Settings.shortcuts;
    NSString *section = nil;
    for (NSArray *pair in AppDelegate.shortcutItems) {
        NSString *menu = pair[0];
        NSMenuItem *item = pair[1];
        if (![menu isEqualToString:section]) {
            section = menu;
            NSTextField *header = [NSTextField labelWithString:menu];
            header.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
            NSGridRow *r = [grid addRowWithViews:@[header, NSGridCell.emptyContentView, NSGridCell.emptyContentView]];
            r.topPadding = grid.numberOfRows > 1 ? 10 : 0;
        }
        NSString *identifier = [AppDelegate shortcutIDForItem:item];
        NSString *fallback = [AppDelegate defaultShortcutForItem:item];
        ShortcutRecorder *recorder = [ShortcutRecorder new];
        recorder.shortcut = overrides[identifier] ?: fallback;
        recorder.onRecord = ^BOOL(NSString *shortcut) {
            // Refuse a combination another command already uses.
            if (shortcut.length) {
                NSDictionary *now = Settings.shortcuts;
                for (NSArray *other in AppDelegate.shortcutItems) {
                    NSString *otherID = [AppDelegate shortcutIDForItem:other[1]];
                    if ([otherID isEqualToString:identifier]) continue;
                    NSString *used = now[otherID] ?: [AppDelegate defaultShortcutForItem:other[1]];
                    if ([used isEqualToString:shortcut]) return NO;
                }
            }
            NSMutableDictionary *all = [Settings.shortcuts mutableCopy];
            if ([shortcut isEqualToString:fallback]) [all removeObjectForKey:identifier]; else all[identifier] = shortcut;
            Settings.shortcuts = all;
            return YES;
        };
        NSButton *reset = [Controls button:@"Default" action:^{
            NSMutableDictionary *all = [Settings.shortcuts mutableCopy];
            [all removeObjectForKey:identifier];
            Settings.shortcuts = all;
        }];
        reset.controlSize = NSControlSizeSmall;
        reset.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        NSTextField *label = [NSTextField labelWithString:item.title];
        // Only changed shortcuts get a Default button (NSGridView ignores `hidden` on its cells).
        NSView *third = overrides[identifier] ? reset : NSGridCell.emptyContentView;
        NSGridRow *r = [grid addRowWithViews:@[label, recorder, third]];
        r.rowAlignment = NSGridRowAlignmentFirstBaseline;
    }
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    grid.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *document = [NSView new];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:grid];
    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = document;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *note = [NSTextField wrappingLabelWithString:
        @"Click a shortcut, then press the new keys. Delete removes it, Esc cancels. A combination already in use is refused."];
    note.font = [NSFont systemFontOfSize:11];
    note.textColor = NSColor.secondaryLabelColor;
    note.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *resetAll = [Controls button:@"Restore All Defaults" action:^{ Settings.shortcuts = @{}; }];
    resetAll.translatesAutoresizingMaskIntoConstraints = NO;
    resetAll.enabled = overrides.count > 0;

    NSView *v = [NSView new];
    for (NSView *sub in @[scroll, note, resetAll]) [v addSubview:sub];
    [NSLayoutConstraint activateConstraints:@[
        [v.widthAnchor constraintEqualToConstant:620],
        [scroll.topAnchor constraintEqualToAnchor:v.topAnchor constant:16],
        [scroll.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:24],
        [scroll.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-24],
        [scroll.heightAnchor constraintEqualToConstant:440],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [grid.topAnchor constraintEqualToAnchor:document.topAnchor constant:8],
        [grid.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-8],
        [grid.centerXAnchor constraintEqualToAnchor:document.centerXAnchor constant:-20],
        [note.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:12],
        [note.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [note.trailingAnchor constraintLessThanOrEqualToAnchor:resetAll.leadingAnchor constant:-12],
        [resetAll.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [resetAll.firstBaselineAnchor constraintEqualToAnchor:note.firstBaselineAnchor],
        [note.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-20],
    ]];
    return v;
}

@end
