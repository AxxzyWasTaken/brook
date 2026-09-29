#import "Brook.h"

// MARK: - Address pill

@implementation URLPillView {
    NSTextField *_label;
    IconButton *_ads;
    NSLayoutConstraint *_adsWidth;      // 0 while hidden, so it takes no room from the address
    NSImageView *_cookie;
    NSLayoutConstraint *_cookieWidth;   // 0 while hidden, so it takes no room from the address
}

- (instancetype)initWithFrame:(NSRect)frameRect { return [self initWithExtensions:NO]; }

- (instancetype)initWithExtensions:(BOOL)withExtensions {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _siteButton = [[IconButton alloc] initWithSymbol:@"magnifyingglass" size:11 tooltip:@"Site Settings"
                                               dimension:22 onClick:nil];
        _label = [NSTextField labelWithString:@""];
        _cookie = [NSImageView new];
        if (withExtensions) _extensionsBar = [[ExtensionsBar alloc] initWithButtonSize:22];
        else _reloadButton = [[IconButton alloc] initWithSymbol:@"arrow.clockwise" size:12 tooltip:@"Reload (⌘R)"
                                                      dimension:24 onClick:nil];

        self.cornerRadius = 10;
        self.baseColor = Palette.pill;
        self.hoverColor = [Palette.pill colorWithAlphaComponent:0.12];
        self.toolTip = @"Search or enter address (⌘L)";

        _label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
        _label.textColor = NSColor.labelColor;
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        [_label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _cookie.image = [NSImage brook_symbol:@"checkmark.shield" size:11];
        _cookie.contentTintColor = NSColor.systemGreenColor;
        _cookie.hidden = YES;
        _cookie.translatesAutoresizingMaskIntoConstraints = NO;
        _cookieWidth = [_cookie.widthAnchor constraintEqualToConstant:0];
        _ads = [[IconButton alloc] initWithSymbol:@"shield.lefthalf.filled" size:11 tooltip:nil dimension:22 onClick:nil];
        _ads.tint = NSColor.tertiaryLabelColor;
        _ads.hidden = YES;
        for (NSLayoutConstraint *c in _ads.constraints) {
            if (c.firstAttribute == NSLayoutAttributeWidth && c.firstItem == _ads) _adsWidth = c;
        }
        _adsWidth.constant = 0;
        for (NSView *v in @[_siteButton, _label, _ads, _cookie]) [self addSubview:v];

        // Both give way when the pill is collapsed to nothing (address bar off, or the icon rail).
        NSLayoutConstraint *height = [self.heightAnchor constraintEqualToConstant:34];
        height.priority = NSLayoutPriorityRequired - 1;
        [NSLayoutConstraint activateConstraints:@[
            height,
            [_siteButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [_siteButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:_siteButton.trailingAnchor constant:2],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_ads.leadingAnchor constraintGreaterThanOrEqualToAnchor:_label.trailingAnchor constant:4],
            [_ads.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_cookie.leadingAnchor constraintEqualToAnchor:_ads.trailingAnchor constant:2],
            [_cookie.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _cookieWidth,
        ]];
        if (ExtensionsBar *bar = _extensionsBar) {
            // The address keeps most of the pill; extension buttons get what's left (two at the
            // default sidebar width, more as it widens) and the rest move into "…".
            bar.translatesAutoresizingMaskIntoConstraints = NO;
            bar.buttonCornerRadius = 7;   // the same shape as the site and shield buttons beside it
            [self addSubview:bar];
            NSLayoutConstraint *minLabel = [_label.widthAnchor constraintGreaterThanOrEqualToConstant:110];
            // Below the sidebar's hold on the pill's right edge (Required - 1): at the narrowest
            // sidebar the address gives up a few points rather than the pill running past the edge.
            minLabel.priority = NSLayoutPriorityRequired - 2;
            [NSLayoutConstraint activateConstraints:@[
                minLabel,
                // "…" always shows: in a narrow sidebar the address gives way, not the last button.
                [bar.widthAnchor constraintGreaterThanOrEqualToConstant:22],
                [_cookie.trailingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:-2],
                [bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-5],
                [bar.topAnchor constraintEqualToAnchor:self.topAnchor],
                [bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            ]];
        } else {
            IconButton *reload = _reloadButton;
            reload.translatesAutoresizingMaskIntoConstraints = NO;
            reload.cornerRadius = 7;
            [self addSubview:reload];
            [NSLayoutConstraint activateConstraints:@[
                [_cookie.trailingAnchor constraintEqualToAnchor:reload.leadingAnchor constant:-4],
                [reload.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-5],
                [reload.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            ]];
        }
    }
    return self;
}

- (IconButton *)adsButton { return _ads; }

- (void)updateWithTab:(BrowserTab *)tab {
    _extensionsBar.tab = tab;
    BOOL loading = tab.isLoading == YES;
    _reloadButton.enabled = tab != nil;
    [_reloadButton setSymbol:loading ? @"xmark" : @"arrow.clockwise" size:12];
    _reloadButton.toolTip = loading ? @"Stop (⌘.)" : @"Reload (⌘R)";
    NSURL *url = tab.url;
    if (!tab || !url) {
        [_siteButton setSymbol:@"magnifyingglass" size:11];
        _siteButton.imageView.contentTintColor = NSColor.secondaryLabelColor;
        _siteButton.enabled = NO;
        _siteButton.imageView.alphaValue = 1;
        _siteButton.toolTip = nil;
        _siteButton.accessibilityValue = nil;
        _label.stringValue = @"Search or enter address";
        _label.textColor = NSColor.secondaryLabelColor;   // a prompt, like the placeholder in the address fields
        [self setCookieShown:NO];
        [self updateAdsForHost:nil];
        return;
    }
    BOOL secure = [url.scheme isEqualToString:@"https"];
    BOOL http = [url.scheme isEqualToString:@"http"];
    _label.textColor = NSColor.labelColor;
    [_siteButton setSymbol:secure ? @"lock.fill" : (http ? @"exclamationmark.triangle" : @"globe") size:10];
    _siteButton.tint = http ? NSColor.systemOrangeColor : NSColor.tertiaryLabelColor;
    BOOL hasHost = BrookHost(url) != nil;
    _siteButton.enabled = hasHost;
    _siteButton.imageView.alphaValue = 1;
    _siteButton.toolTip = hasHost ? @"Settings for this website" : nil;
    // The padlock or warning, for VoiceOver.
    _siteButton.accessibilityValue = secure ? @"Secure connection" : (http ? @"Not secure" : nil);
    // Settings → Layout → Address shows.
    switch (Settings.addressDisplay) {
        case AddressDisplayFull: _label.stringValue = url.absoluteString ?: @""; break;
        case AddressDisplayPageTitle: _label.stringValue = tab.displayTitle.length ? tab.displayTitle : [URLParser display:url]; break;
        default: _label.stringValue = [URLParser display:url]; break;
    }
    NSString *cmp = tab.consentCMP;
    [self setCookieShown:cmp != nil];
    if (cmp) _cookie.toolTip = [NSString stringWithFormat:@"Cookie popup declined for you (%@)", cmp];
    [self updateAdsForHost:BrookHost(url)];
}

/// The shield shows while ads and trackers are being blocked on this site, and nothing when they
/// aren't (off globally or for the site), so the pill only says what's true. With an ad-blocking
/// extension installed Brook's list is paused and the extension does the blocking; the tooltip names it.
- (void)updateAdsForHost:(NSString *)host {
    NSString *extension = ContentBlocker.shared.pausedFor;
    NSNumber *siteOverride = [SiteSettings overrideForHost:host].blockAds;
    BOOL brookBlocks = Settings.blockAds && (!siteOverride || siteOverride.boolValue);
    BOOL blocking = host && (extension || brookBlocks);
    _ads.hidden = !blocking;
    _adsWidth.constant = blocking ? 22 : 0;   // takes no room from the address while hidden
    if (blocking) {
        NSString *tip = extension ? [NSString stringWithFormat:@"Ads and trackers blocked by %@", extension]
                                  : @"Ads and trackers blocked";
        _ads.toolTip = [tip stringByAppendingString:@" — click for this site's settings"];
        _ads.accessibilityLabel = tip;
    }
}

- (void)setCookieShown:(BOOL)shown {
    _cookie.hidden = !shown;
    _cookieWidth.active = !shown;
}

/// "Address, example.com": the label names the control, the value is what it shows.
- (NSString *)accessibilityLabel { return @"Address"; }
- (id)accessibilityValue { return _label.stringValue; }

@end

// MARK: - Favorites grid

@interface FavoriteTile : HoverControl <NSDraggingSource>
@property (readonly) BrowserTab *tab;
- (instancetype)initWithTab:(BrowserTab *)tab;
- (void)refresh;
@end

@implementation FavoriteTile {
    NSImageView *_icon;
    NSPoint _dragStart;
    BOOL _hasDragStart;
}

- (instancetype)initWithTab:(BrowserTab *)tab {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _tab = tab;
        _icon = [NSImageView new];
        self.cornerRadius = 11;
        self.baseColor = Palette.tile;
        self.hoverColor = [Palette.rowSelected colorWithAlphaComponent:0.4];
        self.toolTip = tab.displayTitle;
        _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_icon];
        [NSLayoutConstraint activateConstraints:@[
            [_icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:20],
            [_icon.heightAnchor constraintEqualToConstant:20],
        ]];
        [self refresh];
    }
    return self;
}

- (void)refresh {
    _icon.image = self.tab.favicon ?: [NSImage brook_symbol:@"globe" size:16];
    _icon.contentTintColor = NSColor.secondaryLabelColor;
    _icon.alphaValue = self.tab.isLoaded ? 1 : 0.75;
    self.toolTip = self.tab.displayTitle;
}

- (void)mouseDown:(NSEvent *)event {
    _dragStart = event.locationInWindow;
    _hasDragStart = YES;
    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_hasDragStart) return;
    NSPoint start = _dragStart;
    if (hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) <= 4) return;
    _hasDragStart = NO;
    self.isPressed = NO;
    NSPasteboardItem *item = [NSPasteboardItem new];
    [item setString:self.tab.identifier.UUIDString forType:BrookTabPasteboardType];
    NSURL *url = self.tab.url;
    if (url) [item setString:url.absoluteString forType:NSPasteboardTypeURL];
    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:item];
    NSImage *favicon = _icon.image;
    NSImage *image = [NSImage imageWithSize:self.bounds.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [favicon drawInRect:NSMakeRect(NSMidX(rect) - 10, NSMidY(rect) - 10, 20, 20)];
        return YES;
    }];
    [dragItem setDraggingFrame:self.bounds contents:image];
    [self beginDraggingSessionWithItems:@[dragItem] event:event source:self];
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return context == NSDraggingContextWithinApplication ? NSDragOperationMove : NSDragOperationCopy;
}

@end

static const CGFloat kTileHeight = 44;
static const CGFloat kGap = 8;

@implementation FavoritesGridView {
    NSMutableArray<FavoriteTile *> *_tiles;
    NSLayoutConstraint *_heightConstraint;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _tiles = [NSMutableArray array];
        _maxColumns = 4;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _heightConstraint = [self.heightAnchor constraintEqualToConstant:0];
        _heightConstraint.active = YES;
        [self registerForDraggedTypes:@[BrookTabPasteboardType]];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setMaxColumns:(NSInteger)maxColumns {
    NSInteger oldValue = _maxColumns;
    _maxColumns = maxColumns;
    if (maxColumns != oldValue) { [self updateHeight]; self.needsLayout = YES; }
}

- (NSInteger)columns {
    return std::max<NSInteger>(1, std::min<NSInteger>(_maxColumns, (NSInteger)_tiles.count));
}

- (void)reloadFavorites:(NSArray<BrowserTab *> *)favorites selected:(BrowserTab *)selected {
    NSMutableDictionary<NSUUID *, FavoriteTile *> *existing = [NSMutableDictionary dictionary];
    for (FavoriteTile *t in _tiles) existing[t.tab.identifier] = t;
    for (FavoriteTile *t in _tiles) [t removeFromSuperview];
    NSMutableArray<FavoriteTile *> *tiles = [NSMutableArray arrayWithCapacity:favorites.count];
    __weak FavoritesGridView *weakSelf = self;
    for (BrowserTab *tab in favorites) {
        FavoriteTile *tile = existing[tab.identifier] ?: [[FavoriteTile alloc] initWithTab:tab];
        tile.onClick = ^{
            FavoritesGridView *self = weakSelf;
            if (self.onSelect) self.onSelect(tab);
        };
        tile.menu = self.menuProvider ? self.menuProvider(tab) : nil;
        [tile refresh];
        [tiles addObject:tile];
    }
    _tiles = tiles;
    for (FavoriteTile *t in _tiles) [self addSubview:t];
    [self updateSelection:selected];
    [self updateHeight];
    self.needsLayout = YES;
}

- (void)updateHeight {
    NSInteger rows = _tiles.count == 0 ? 0 : (NSInteger)ceil((double)_tiles.count / (double)[self columns]);
    _heightConstraint.constant = rows == 0 ? 0 : (CGFloat)rows * kTileHeight + (CGFloat)(rows - 1) * kGap;
}

- (void)updateSelection:(BrowserTab *)selected {
    for (FavoriteTile *t in _tiles) t.isHighlightedState = t.tab == selected;
}

- (void)refresh:(BrowserTab *)tab {
    for (FavoriteTile *t in _tiles) {
        if (t.tab == tab) { [t refresh]; break; }
    }
}

- (NSView *)tileForTab:(BrowserTab *)tab {
    for (FavoriteTile *t in _tiles) {
        if (t.tab == tab) return t;
    }
    return nil;
}

- (void)layout {
    [super layout];
    if (_tiles.count == 0) return;
    NSInteger cols = [self columns];
    CGFloat w = (self.bounds.size.width - (CGFloat)(cols - 1) * kGap) / (CGFloat)cols;
    [_tiles enumerateObjectsUsingBlock:^(FavoriteTile *tile, NSUInteger i, BOOL *stop) {
        NSInteger r = (NSInteger)i / cols, c = (NSInteger)i % cols;
        tile.frame = NSMakeRect((CGFloat)c * (w + kGap), (CGFloat)r * (kTileHeight + kGap), w, kTileHeight);
    }];
}

// Accept tabs dragged in from the list.
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender { return NSDragOperationMove; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender { return NSDragOperationMove; }

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSString *s = [sender.draggingPasteboard stringForType:BrookTabPasteboardType];
    NSUUID *uuid = s ? [[NSUUID alloc] initWithUUIDString:s] : nil;
    if (!uuid) return NO;
    NSPoint p = [self convertPoint:sender.draggingLocation fromView:nil];
    NSInteger index = (NSInteger)_tiles.count;
    if (_tiles.count > 0) {
        NSInteger cols = [self columns];
        CGFloat w = (self.bounds.size.width - (CGFloat)(cols - 1) * kGap) / (CGFloat)cols;
        NSInteger c = std::min<NSInteger>(cols - 1, std::max<NSInteger>(0, (NSInteger)(p.x / (w + kGap))));
        NSInteger r = std::max<NSInteger>(0, (NSInteger)(p.y / (kTileHeight + kGap)));
        index = std::min<NSInteger>((NSInteger)_tiles.count, r * cols + c);
    }
    if (self.onDropTab) self.onDropTab(uuid, index);
    return YES;
}

@end

// MARK: - Space switcher

@implementation SpaceDot {
    CALayer *_dot;
    NSArray<NSLayoutConstraint *> *_size;
}

- (instancetype)initWithSpace:(Space *)space {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 24, 24)])) {
        _space = space;
        _dot = [CALayer layer];
        self.cornerRadius = 7;
        self.toolTip = space.name;
        [self.layer addSublayer:_dot];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _size = @[[self.widthAnchor constraintEqualToConstant:24], [self.heightAnchor constraintEqualToConstant:24]];
        [NSLayoutConstraint activateConstraints:_size];
    }
    return self;
}

- (void)setOpensMenu:(BOOL)opensMenu {
    _opensMenu = opensMenu;
    for (NSLayoutConstraint *c in _size) c.active = !opensMenu;
}

- (void)setIsCurrent:(BOOL)isCurrent {
    _isCurrent = isCurrent;
    self.needsLayout = YES;
    self.needsDisplay = YES;
}

// A space is a radio button; the rail's single dot opens the spaces menu instead.
- (NSAccessibilityRole)accessibilityRole {
    return _opensMenu ? NSAccessibilityMenuButtonRole : NSAccessibilityRadioButtonRole;
}
- (NSString *)accessibilityLabel { return _space.name; }
- (id)accessibilityValue { return _opensMenu ? nil : @(_isCurrent); }

// The rail's dot is sized by its glass after it's built, so the dot is placed on every layout,
// not only when the colours are drawn.
- (void)layout {
    [super layout];
    CGFloat d = self.isCurrent ? 10 : 7;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _dot.frame = CGRectMake((self.bounds.size.width - d) / 2, (self.bounds.size.height - d) / 2, d, d);
    _dot.cornerRadius = d / 2;
    [CATransaction commit];
}

- (void)updateLayer {
    [super updateLayer];
    _dot.backgroundColor = [self.space.color colorWithAlphaComponent:self.isCurrent ? 1 : 0.55].CGColor;
    _dot.borderWidth = self.isCurrent ? 2 : 0;
    _dot.borderColor = [self brook_cg:[NSColor brook_dynamicLight:[NSColor colorWithWhite:1 alpha:0.9]
                                                             dark:[NSColor colorWithWhite:1 alpha:0.35]]];
}

@end

// MARK: - Toolbar buttons

@implementation ToolbarButtons {
    std::vector<std::pair<ToolbarItem, IconButton *>> _buttons;
    IconButton *_moreButton;
    NSUInteger _shown;   // with `overflows`, how many buttons fit before "»"
}

static const CGFloat kToolbarButtonSize = 28;
/// "»" is narrower than a button, like Safari's toolbar overflow, so it takes less of the row.
static const CGFloat kMoreButtonWidth = 18;

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.spacing = 2;
        self.detachesHiddenViews = YES;
        __weak ToolbarButtons *weakSelf = self;
        _moreButton = [[IconButton alloc] initWithSymbol:@"chevron.right.2" size:12 tooltip:@"More"
                                               dimension:kToolbarButtonSize onClick:^{ [weakSelf showMoreMenu]; }];
        for (NSLayoutConstraint *c in _moreButton.constraints) {
            if (c.firstItem == _moreButton && c.firstAttribute == NSLayoutAttributeWidth) c.constant = kMoreButtonWidth;
        }
        _shown = NSUIntegerMax;
        [self rebuild];
    }
    return self;
}

- (void)setOverflows:(BOOL)overflows {
    _overflows = overflows;
    // The row's width comes from outside; the buttons keep to its trailing end, and may be cut
    // off (then moved into "»" by -layout) rather than push the row wider.
    [self setHuggingPriority:overflows ? NSLayoutPriorityDefaultLow - 1 : NSLayoutPriorityDefaultHigh
              forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setClippingResistancePriority:overflows ? NSLayoutPriorityDefaultLow : NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.needsLayout = YES;
}

- (void)layout {
    [super layout];
    if (!_overflows || _columns) return;
    // Every button if they fit, else as many as fit beside "»".
    CGFloat width = NSWidth(self.bounds), step = kToolbarButtonSize + self.spacing;
    NSUInteger count = _buttons.size();
    NSUInteger shown = count;
    if (count * step - self.spacing > width) {
        shown = (NSUInteger)std::max<CGFloat>(0, floor((width - kMoreButtonWidth) / step));
    }
    if (shown == _shown) return;
    _shown = shown;
    for (NSUInteger i = 0; i < count; i++) _buttons[i].second.hidden = i >= shown;
    _moreButton.hidden = shown == count;
}

- (void)showMoreMenu {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    for (auto &[item, button] : _buttons) {
        if (!button.isHidden) continue;
        IconButton *b = button;
        ClosureMenuItem *mi = [[ClosureMenuItem alloc] initWithTitle:ToolbarItemTitle(item) handler:^{
            if (b.onClick) b.onClick();
        }];
        [mi brook_setVisibleImage:[NSImage brook_symbol:ToolbarItemSymbol(item) size:13]];
        mi.enabled = b.isEnabled;
        [menu addItem:mi];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, -4) inView:_moreButton];
}

static NSString *ToolbarItemTooltip(ToolbarItem item) {
    switch (item) {
        case ToolbarItemBack: return @"Back (⌘[)";
        case ToolbarItemForward: return @"Forward (⌘])";
        case ToolbarItemReload: return @"Reload (⌘R)";
        case ToolbarItemCopyLink: return @"Copy Link (⇧⌘C)";
        case ToolbarItemNewTab: return @"New Tab (⌘T)";
        default: return ToolbarItemTitle(item);
    }
}

- (void)rebuild {
    for (NSView *v in [self.arrangedSubviews copy]) [v removeFromSuperview];
    _buttons.clear();
    __weak ToolbarButtons *weakSelf = self;
    NSArray<NSNumber *> *items = Settings.toolbarItems;
    if (_includesSiteSettings && ![items containsObject:@(ToolbarItemSiteSettings)]) {
        items = [items arrayByAddingObject:@(ToolbarItemSiteSettings)];
    }
    NSStackView *row = nil;
    for (NSNumber *n in items) {
        ToolbarItem item = (ToolbarItem)n.integerValue;
        __block IconButton *button = nil;
        button = [[IconButton alloc] initWithSymbol:ToolbarItemSymbol(item) tooltip:ToolbarItemTooltip(item) onClick:^{
            ToolbarButtons *self_ = weakSelf;
            BrowserWindowController *b = self_.browser;
            if (!b) return;
            switch (item) {
                case ToolbarItemBack: [b goBack]; break;
                case ToolbarItemForward: [b goForward]; break;
                case ToolbarItemReload: [b reloadOrStop]; break;
                case ToolbarItemShare: {
                    // From "»" when the button itself is crowded out.
                    NSView *anchor = [self_ buttonForItem:ToolbarItemShare];
                    [b shareFromView:anchor.window ? anchor : self_->_moreButton.window ? self_->_moreButton : self_];
                    break;
                }
                case ToolbarItemCopyLink: [b copyURL]; break;
                case ToolbarItemReader: [b toggleReader]; break;
                case ToolbarItemNewTab: [b newTab]; break;
                case ToolbarItemSiteSettings: [b showSiteInfo]; break;
            }
        }];
        _buttons.emplace_back(item, button);
        if (_columns == 0) {
            [self addView:button inGravity:NSStackViewGravityTrailing];
            continue;
        }
        // Rows of `columns`, leading-aligned, so a short last row lines up with the ones above.
        if (!row || row.arrangedSubviews.count == _columns) {
            row = [NSStackView new];
            row.spacing = self.spacing;
            [self addArrangedSubview:row];
        }
        [row addArrangedSubview:button];
    }
    _moreButton.hidden = YES;
    _shown = NSUIntegerMax;   // worked out afresh on the next layout
    if (_columns == 0) [self addView:_moreButton inGravity:NSStackViewGravityTrailing];
    self.needsLayout = YES;
    [self updateWithTab:BrowserState.shared.selectedTab];
}

- (IconButton *)buttonForItem:(ToolbarItem)item {
    for (auto &[i, b] : _buttons) if (i == item) return b;
    return nil;
}

- (void)updateWithTab:(BrowserTab *)tab {
    WKWebView *wv = tab.webView;
    BOOL loading = tab.isLoading == YES;
    for (auto &[item, b] : _buttons) {
        switch (item) {
            case ToolbarItemBack: b.enabled = wv ? wv.canGoBack : NO; break;
            case ToolbarItemForward: b.enabled = wv ? wv.canGoForward : NO; break;
            case ToolbarItemReload:
                b.enabled = tab != nil;
                [b setSymbol:loading ? @"xmark" : @"arrow.clockwise"];
                b.toolTip = loading ? @"Stop (⌘.)" : @"Reload (⌘R)";
                break;
            case ToolbarItemNewTab: break;
            default: b.enabled = tab.url != nil; break;
        }
    }
}

@end
