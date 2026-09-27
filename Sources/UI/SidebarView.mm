#import "Brook.h"
#import <QuartzCore/QuartzCore.h>

namespace {

/// One row in the tab list.
struct Row {
    enum Kind { Pinned, Divider, NewTab, Tab };
    Kind kind;
    __strong BrowserTab *tabValue;   // Pinned and Tab only

    static Row pinned(BrowserTab *t) { return {Pinned, t}; }
    static Row divider() { return {Divider, nil}; }
    static Row newTab() { return {NewTab, nil}; }
    static Row tab(BrowserTab *t) { return {Tab, t}; }

    BrowserTab *tab() const {
        switch (kind) {
        case Pinned: case Tab: return tabValue;
        default: return nil;
        }
    }
};

} // namespace

@interface SidebarView () <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate>
@end

@implementation SidebarView {
    // Top
    NSView *_titleRow;
    NSLayoutConstraint *_titleRowTop;
    NSLayoutConstraint *_titleRowLeading;
    IconButton *_toggleButton;
    IconButton *_backButton;
    IconButton *_forwardButton;
    IconButton *_reloadButton;
    FavoritesGridView *_favoritesGrid;
    NSLayoutConstraint *_favoritesTop;
    NSLayoutConstraint *_pillTop;
    NSLayoutConstraint *_pillHeight;
    NSView *_bottomBar;
    NSLayoutConstraint *_bottomHeight;

    // Tabs
    SidebarScrollView *_scrollView;
    SidebarTableView *_table;
    std::vector<Row> _rows;

    // Bottom
    IconButton *_fireButton;
    IconButton *_downloadsButton;
    IconButton *_addSpaceButton;
    NSStackView *_spaceStack;

    TabDensity _rowDensity;
    CGFloat _rowFontSize;
}

- (BrowserState *)state { return BrowserState.shared; }

- (NSView *)titleRow { return _titleRow; }
- (CGFloat)titleRowHeight { return 28; }
- (NSLayoutConstraint *)titleRowTop { return _titleRowTop; }
- (NSLayoutConstraint *)titleRowLeading { return _titleRowLeading; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _titleRow = [NSView new];
        _urlPill = [URLPillView new];
        _favoritesGrid = [FavoritesGridView new];
        _bottomBar = [NSView new];
        _scrollView = [SidebarScrollView new];
        _table = [SidebarTableView new];
        _spaceStack = [NSStackView new];
        _rowDensity = Settings.tabDensity;
        _rowFontSize = Settings.tabFontSize;

        __weak SidebarView *weakSelf = self;
        _toggleButton = [[IconButton alloc] initWithSymbol:@"sidebar.left" tooltip:@"Hide Sidebar (⌘S)" onClick:^{
            [weakSelf.browser toggleSidebar];
        }];
        _backButton = [[IconButton alloc] initWithSymbol:@"arrow.left" tooltip:@"Back (⌘[)" onClick:^{
            [weakSelf.browser goBack];
        }];
        _forwardButton = [[IconButton alloc] initWithSymbol:@"arrow.right" tooltip:@"Forward (⌘])" onClick:^{
            [weakSelf.browser goForward];
        }];
        _reloadButton = [[IconButton alloc] initWithSymbol:@"arrow.clockwise" tooltip:@"Reload (⌘R)" onClick:^{
            [weakSelf.browser reloadOrStop];
        }];
        _fireButton = [[IconButton alloc] initWithSymbol:@"flame" tooltip:@"Burn Tabs & Data (⇧⌘⌫)" onClick:^{
            [weakSelf.browser fire];
        }];
        _downloadsButton = [[IconButton alloc] initWithSymbol:@"arrow.down.circle" tooltip:@"Downloads" onClick:^{
            SidebarView *strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.browser showDownloadsFromView:strongSelf->_downloadsButton];
        }];
        _addSpaceButton = [[IconButton alloc] initWithSymbol:@"plus" tooltip:@"New Space" onClick:^{
            [weakSelf.browser promptNewSpace];
        }];

        [self build];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(downloadsChanged)
                                                   name:DownloadManagerDidChangeNotification object:nil];
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow { return YES; }

// MARK: Build

- (void)build {
    __weak SidebarView *weakSelf = self;

    // Nav row
    _titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_titleRow];
    NSStackView *navStack = [NSStackView stackViewWithViews:@[_backButton, _forwardButton, _reloadButton]];
    navStack.spacing = 2;
    navStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_titleRow addSubview:_toggleButton];
    [_titleRow addSubview:navStack];

    _urlPill.translatesAutoresizingMaskIntoConstraints = NO;
    _urlPill.onClick = ^{ [weakSelf.browser showCommandBarEditing:YES]; };
    _urlPill.extensionsButton.onClick = ^{ [weakSelf.browser showExtensionsMenu]; };
    _urlPill.siteButton.onClick = ^{ [weakSelf.browser showSiteInfo]; };
    [self addSubview:_urlPill];

    _favoritesGrid.onSelect = ^(BrowserTab *tab) { [weakSelf.state selectTab:tab]; };
    _favoritesGrid.onDropTab = ^(NSUUID *tabID, NSInteger index) {
        SidebarView *strongSelf = weakSelf;
        if (!strongSelf) return;
        BrowserTab *tab = nil;
        for (BrowserTab *t in strongSelf.state.allTabs) {
            if ([t.identifier isEqual:tabID]) { tab = t; break; }
        }
        if (!tab) return;
        [strongSelf.state move:tab to:TabLocation::favorites() index:index];
    };
    _favoritesGrid.menuProvider = ^NSMenu *(BrowserTab *tab) {
        return [weakSelf.browser menuForTab:tab] ?: [NSMenu new];
    };
    [self addSubview:_favoritesGrid];

    // Tab list
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    _table.headerView = nil;
    _table.backgroundColor = NSColor.clearColor;
    _table.style = NSTableViewStylePlain;
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    _table.intercellSpacing = NSMakeSize(0, 2);
    _table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    _table.focusRingType = NSFocusRingTypeNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.action = @selector(rowClicked);
    [_table registerForDraggedTypes:@[BrookTabPasteboardType, NSPasteboardTypeURL]];
    [_table setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    _table.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleGap;
    _table.onMiddleClick = ^(NSInteger row) {
        SidebarView *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (row < 0 || row >= (NSInteger)strongSelf->_rows.size()) return;
        BrowserTab *tab = strongSelf->_rows[row].tab();
        if (!tab) return;
        [strongSelf.state close:tab];
    };
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    _table.menu = menu;

    _scrollView.documentView = _table;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.scrollerStyle = NSScrollerStyleOverlay;
    _scrollView.automaticallyAdjustsContentInsets = NO;
    _scrollView.contentInsets = NSEdgeInsetsMake(0, 0, 8, 0);
    _scrollView.wantsLayer = YES;
    _scrollView.onSwipe = ^(NSInteger delta) { [weakSelf.state switchSpaceBy:delta]; };
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_scrollView];

    // Bottom bar
    _spaceStack.spacing = 2;
    _spaceStack.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *bottom = _bottomBar;
    bottom.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:bottom];
    for (NSView *v in @[_fireButton, _downloadsButton, _spaceStack, _addSpaceButton]) [bottom addSubview:v];
    _downloadsButton.hidden = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_titleRow.heightAnchor constraintEqualToConstant:self.titleRowHeight],
        [_titleRow.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_toggleButton.leadingAnchor constraintEqualToAnchor:_titleRow.leadingAnchor],
        [_toggleButton.centerYAnchor constraintEqualToAnchor:_titleRow.centerYAnchor],
        [navStack.trailingAnchor constraintEqualToAnchor:_titleRow.trailingAnchor],
        [navStack.centerYAnchor constraintEqualToAnchor:_titleRow.centerYAnchor],

        [_urlPill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_urlPill.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],

        [_favoritesGrid.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_favoritesGrid.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],

        [_scrollView.topAnchor constraintEqualToAnchor:_favoritesGrid.bottomAnchor constant:10],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [_scrollView.bottomAnchor constraintEqualToAnchor:bottom.topAnchor constant:-4],

        [bottom.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [bottom.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [bottom.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        [_fireButton.leadingAnchor constraintEqualToAnchor:bottom.leadingAnchor],
        [_fireButton.centerYAnchor constraintEqualToAnchor:bottom.centerYAnchor],
        [_downloadsButton.leadingAnchor constraintEqualToAnchor:_fireButton.trailingAnchor constant:2],
        [_downloadsButton.centerYAnchor constraintEqualToAnchor:bottom.centerYAnchor],
        [_spaceStack.centerXAnchor constraintEqualToAnchor:bottom.centerXAnchor],
        [_spaceStack.centerYAnchor constraintEqualToAnchor:bottom.centerYAnchor],
        [_addSpaceButton.trailingAnchor constraintEqualToAnchor:bottom.trailingAnchor],
        [_addSpaceButton.centerYAnchor constraintEqualToAnchor:bottom.centerYAnchor],
    ]];
    _titleRowTop = [_titleRow.topAnchor constraintEqualToAnchor:self.topAnchor constant:8];
    _titleRowLeading = [_titleRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:78];
    _favoritesTop = [_favoritesGrid.topAnchor constraintEqualToAnchor:_urlPill.bottomAnchor constant:12];
    _pillTop = [_urlPill.topAnchor constraintEqualToAnchor:_titleRow.bottomAnchor constant:10];
    _pillHeight = [_urlPill.heightAnchor constraintEqualToConstant:0];
    _bottomHeight = [bottom.heightAnchor constraintEqualToConstant:28];
    [NSLayoutConstraint activateConstraints:@[_titleRowTop, _titleRowLeading, _favoritesTop, _pillTop, _bottomHeight]];
    [self applySettings];
}

/// Re-reads the appearance settings that affect the sidebar.
- (void)applySettings {
    BOOL showPill = Settings.showAddressBar;
    _urlPill.hidden = !showPill;
    _pillHeight.active = !showPill;
    _pillTop.constant = showPill ? 10 : 0;
    BOOL showBottom = Settings.showBottomBar;
    _bottomBar.hidden = !showBottom;
    _bottomHeight.constant = showBottom ? 28 : 0;
    _favoritesGrid.maxColumns = Settings.favoritesColumns;
    TabDensity density = Settings.tabDensity;
    CGFloat font = Settings.tabFontSize;
    if (density != _rowDensity || font != _rowFontSize) {
        _rowDensity = density;
        _rowFontSize = font;
        [_table reloadData];
        [self updateSelection];
    }
    [self reloadFavorites];
}

- (void)reloadFavorites {
    BrowserState *state = self.state;
    BOOL show = Settings.showFavorites && state.favorites.count > 0;
    _favoritesGrid.hidden = !show;
    [_favoritesGrid reloadFavorites:show ? state.favorites : @[] selected:state.selectedTab];
    _favoritesTop.constant = show ? 12 : 0;
}

// MARK: Updates from the window controller

- (void)reloadAll {
    [self reloadAllTransition:std::nullopt];
}

- (void)reloadAllWithSpaceTransition:(BOOL)forward {
    [self reloadAllTransition:std::optional<bool>(forward)];
}

- (void)reloadAllTransition:(std::optional<bool>)forward {
    [self rebuildRows];
    if (forward) {
        CATransition *t = [CATransition animation];
        t.type = kCATransitionPush;
        t.subtype = *forward ? kCATransitionFromRight : kCATransitionFromLeft;
        t.duration = 0.28;
        t.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_scrollView.layer addAnimation:t forKey:@"spaceSwitch"];
    }
    [_table reloadData];
    [self reloadFavorites];
    [self rebuildSpaceDots];
    [self updateSelection];
}

- (void)rebuildRows {
    Space *s = self.state.currentSpace;
    std::vector<Row> r;
    for (BrowserTab *t in s.pinned) r.push_back(Row::pinned(t));
    if (s.pinned.count > 0) r.push_back(Row::divider());
    r.push_back(Row::newTab());
    for (BrowserTab *t in s.tabs) r.push_back(Row::tab(t));
    _rows = std::move(r);
}

- (void)rebuildSpaceDots {
    for (NSView *v in [_spaceStack.arrangedSubviews copy]) [v removeFromSuperview];
    BrowserState *state = self.state;
    __weak SidebarView *weakSelf = self;
    NSArray<Space *> *spaces = state.spaces;
    for (NSInteger i = 0; i < (NSInteger)spaces.count; i++) {
        Space *space = spaces[i];
        SpaceDot *dot = [[SpaceDot alloc] initWithSpace:space];
        dot.isCurrent = i == state.currentSpaceIndex;
        dot.onClick = ^{ [weakSelf.state switchToSpace:i]; };
        dot.menu = [self.browser menuForSpace:space];
        [_spaceStack addArrangedSubview:dot];
    }
}

- (NSInteger)rowIndexOfTab:(BrowserTab *)tab {
    for (size_t i = 0; i < _rows.size(); i++) {
        if (_rows[i].tab() == tab) return (NSInteger)i;
    }
    return -1;
}

- (void)updateSelection {
    BrowserTab *selected = self.state.selectedTab;
    [_favoritesGrid updateSelection:selected];
    [_table enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
        id cell = [rowView viewAtColumn:0];
        if ([cell isKindOfClass:TabCellView.class]) {
            TabCellView *tc = cell;
            [tc setSelected:tc.tab == selected];
        }
    }];
    if (selected) {
        NSInteger idx = [self rowIndexOfTab:selected];
        if (idx >= 0) [_table scrollRowToVisible:idx];
    }
    [self updateChrome];
}

- (void)tabChanged:(BrowserTab *)tab change:(TabChange)change {
    if (tab.isFavorite) {
        [_favoritesGrid refresh:tab];
    } else {
        NSInteger idx = [self rowIndexOfTab:tab];
        if (idx >= 0) {
            id cell = [_table viewAtColumn:0 row:idx makeIfNecessary:NO];
            if ([cell isKindOfClass:TabCellView.class]) [(TabCellView *)cell updateWithTab:tab];
        }
    }
    if (tab == self.state.selectedTab) [self updateChrome];
}

/// Back/forward/reload state and the address pill.
- (void)updateChrome {
    BrowserTab *tab = self.state.selectedTab;
    _backButton.enabled = tab.webView ? tab.webView.canGoBack : NO;
    _forwardButton.enabled = tab.webView ? tab.webView.canGoForward : NO;
    _reloadButton.enabled = tab != nil;
    BOOL loading = tab.isLoading == YES;
    [_reloadButton setSymbol:loading ? @"xmark" : @"arrow.clockwise"];
    _reloadButton.toolTip = loading ? @"Stop (⌘.)" : @"Reload (⌘R)";
    [_urlPill updateWithTab:tab];
}

- (void)downloadsChanged {
    DownloadManager *dm = DownloadManager.shared;
    _downloadsButton.hidden = dm.items.count == 0;
    [_downloadsButton setSymbol:dm.hasActive ? @"arrow.down.circle.dotted" : @"arrow.down.circle"];
    _downloadsButton.tint = dm.hasActive ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
}

// MARK: Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_rows.size();
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    if (_rows[row].kind == Row::Divider) return 11;
    return TabDensityRowHeight(_rowDensity);
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [PlainRowView new];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    const Row &r = _rows[row];
    switch (r.kind) {
    case Row::Pinned:
    case Row::Tab: {
        BrowserTab *tab = r.tabValue;
        id made = [tableView makeViewWithIdentifier:TabCellView.reuseID owner:self];
        TabCellView *cell = [made isKindOfClass:TabCellView.class] ? made : [TabCellView new];
        __weak SidebarView *weakSelf = self;
        cell.onClose = ^(BrowserTab *t) { [weakSelf.state close:t]; };
        cell.fontSize = _rowFontSize;
        [cell configureWithTab:tab selected:tab == self.state.selectedTab];
        return cell;
    }
    case Row::Divider: {
        id made = [tableView makeViewWithIdentifier:DividerCellView.reuseID owner:self];
        return [made isKindOfClass:DividerCellView.class] ? made : [DividerCellView new];
    }
    case Row::NewTab: {
        id made = [tableView makeViewWithIdentifier:NewTabCellView.reuseID owner:self];
        NewTabCellView *cell = [made isKindOfClass:NewTabCellView.class] ? made : [NewTabCellView new];
        cell.fontSize = _rowFontSize;
        return cell;
    }
    }
    return nil;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return NO;
}

- (void)rowClicked {
    NSInteger row = _table.clickedRow;
    if (row < 0 || row >= (NSInteger)_rows.size()) return;
    const Row &r = _rows[row];
    switch (r.kind) {
    case Row::Pinned:
    case Row::Tab: [self.state selectTab:r.tabValue]; break;
    case Row::NewTab: [self.browser newTab]; break;
    case Row::Divider: break;
    }
}

// Drag & drop

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    BrowserTab *tab = _rows[row].tab();
    if (!tab) return nil;
    NSPasteboardItem *item = [NSPasteboardItem new];
    [item setString:tab.identifier.UUIDString forType:BrookTabPasteboardType];
    if (tab.url) [item setString:tab.url.absoluteString forType:NSPasteboardTypeURL];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    if (dropOperation == NSTableViewDropOn) [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return [info.draggingPasteboard stringForType:BrookTabPasteboardType] != nil ? NSDragOperationMove
                                                                                 : NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    BrowserState *state = self.state;
    Space *s = state.currentSpace;
    NSInteger pinnedCount = (NSInteger)s.pinned.count;
    NSInteger firstTabRow = pinnedCount + (pinnedCount > 0 ? 1 : 0) + 1;
    TabLocation destination;
    NSInteger index;
    // Dropping above the divider (or above "New Tab" when nothing is pinned) pins the tab.
    if (row <= pinnedCount) {
        destination = TabLocation::pinnedIn(s); index = row;
    } else {
        destination = TabLocation::tabsIn(s); index = std::max<NSInteger>(0, row - firstTabRow);
    }

    NSString *idString = [info.draggingPasteboard stringForType:BrookTabPasteboardType];
    NSUUID *identifier = idString ? [[NSUUID alloc] initWithUUIDString:idString] : nil;
    if (identifier) {
        for (BrowserTab *tab in state.allTabs) {
            if ([tab.identifier isEqual:identifier]) {
                [state move:tab to:destination index:index];
                return YES;
            }
        }
    }
    NSString *urlString = [info.draggingPasteboard stringForType:NSPasteboardTypeURL];
    NSURL *url = urlString ? [NSURL URLWithString:urlString] : nil;
    if (url) {
        BrowserTab *tab = [state openTabWithURL:url inSpace:nil select:YES];
        [state move:tab to:destination index:index];
        return YES;
    }
    return NO;
}

// MARK: Menus

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSInteger row = _table.clickedRow;
    if (row < 0 || row >= (NSInteger)_rows.size()) return;
    BrowserTab *tab = _rows[row].tab();
    if (!tab) return;
    for (NSMenuItem *item in [[self.browser menuForTab:tab].itemArray copy]) {
        [item.menu removeItem:item];
        [menu addItem:item];
    }
}

@end

/// NSMenuItem that runs a closure.
@implementation ClosureMenuItem {
    void (^_handler)(void);
}

- (instancetype)initWithTitle:(NSString *)title handler:(void (^)(void))handler {
    return [self initWithTitle:title key:@"" modifiers:NSEventModifierFlagCommand handler:handler];
}

- (instancetype)initWithTitle:(NSString *)title key:(NSString *)key modifiers:(NSEventModifierFlags)modifiers
                      handler:(void (^)(void))handler {
    if ((self = [super initWithTitle:title action:@selector(run) keyEquivalent:key])) {
        _handler = [handler copy];
        self.keyEquivalentModifierMask = modifiers;
        self.target = self;
    }
    return self;
}

- (void)run {
    if (_handler) _handler();
}

@end

@implementation NSArray (BrookSafe)

- (id)brook_objectAtSafeIndex:(NSInteger)index {
    return (index >= 0 && index < (NSInteger)self.count) ? self[index] : nil;
}

@end
