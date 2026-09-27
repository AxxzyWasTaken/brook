#import "Brook.h"

// MARK: - Address pill

@implementation URLPillView {
    NSTextField *_label;
    NSImageView *_cookie;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _siteButton = [[IconButton alloc] initWithSymbol:@"magnifyingglass" size:11 tooltip:@"Site Settings"
                                               dimension:22 onClick:nil];
        _label = [NSTextField labelWithString:@""];
        _cookie = [NSImageView new];
        _extensionsButton = [[IconButton alloc] initWithSymbol:@"puzzlepiece.extension" size:12 tooltip:@"Extensions"
                                                     dimension:24 onClick:nil];

        self.cornerRadius = 10;
        self.baseColor = Palette.pill;
        self.hoverColor = [Palette.pill colorWithAlphaComponent:0.12];
        self.toolTip = @"Search or enter address (⌘L)";

        _label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
        _label.textColor = NSColor.secondaryLabelColor;
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        [_label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _cookie.image = [NSImage brook_symbol:@"checkmark.shield" size:11];
        _cookie.contentTintColor = NSColor.systemGreenColor;
        _cookie.hidden = YES;
        _cookie.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSView *v in @[_siteButton, _label, _cookie, _extensionsButton]) [self addSubview:v];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:34],
            [_siteButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [_siteButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:_siteButton.trailingAnchor constant:2],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_cookie.leadingAnchor constraintGreaterThanOrEqualToAnchor:_label.trailingAnchor constant:4],
            [_cookie.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_cookie.trailingAnchor constraintEqualToAnchor:_extensionsButton.leadingAnchor constant:-4],
            [_extensionsButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-5],
            [_extensionsButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)updateWithTab:(BrowserTab *)tab {
    NSURL *url = tab.url;
    if (!tab || !url) {
        [_siteButton setSymbol:@"magnifyingglass" size:11];
        _siteButton.imageView.contentTintColor = NSColor.secondaryLabelColor;
        _siteButton.enabled = NO;
        _siteButton.imageView.alphaValue = 1;
        _siteButton.toolTip = nil;
        _label.stringValue = @"Search or enter address";
        _cookie.hidden = YES;
        return;
    }
    BOOL secure = [url.scheme isEqualToString:@"https"];
    BOOL http = [url.scheme isEqualToString:@"http"];
    [_siteButton setSymbol:secure ? @"lock.fill" : (http ? @"exclamationmark.triangle" : @"globe") size:10];
    _siteButton.tint = http ? NSColor.systemOrangeColor : NSColor.tertiaryLabelColor;
    BOOL hasHost = BrookHost(url) != nil;
    _siteButton.enabled = hasHost;
    _siteButton.imageView.alphaValue = 1;
    _siteButton.toolTip = hasHost ? @"Settings for this website" : nil;
    _label.stringValue = [URLParser display:url];
    NSString *cmp = tab.consentCMP;
    if (cmp) {
        _cookie.hidden = NO;
        _cookie.toolTip = [NSString stringWithFormat:@"Cookie popup declined for you (%@)", cmp];
    } else {
        _cookie.hidden = YES;
    }
}

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
}

- (instancetype)initWithSpace:(Space *)space {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 24, 24)])) {
        _space = space;
        _dot = [CALayer layer];
        self.cornerRadius = 7;
        self.toolTip = space.name;
        [self.layer addSublayer:_dot];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self.widthAnchor constraintEqualToConstant:24].active = YES;
        [self.heightAnchor constraintEqualToConstant:24].active = YES;
    }
    return self;
}

- (void)setIsCurrent:(BOOL)isCurrent {
    _isCurrent = isCurrent;
    self.needsLayout = YES;
    self.needsDisplay = YES;
}

- (void)updateLayer {
    [super updateLayer];
    CGFloat d = self.isCurrent ? 10 : 7;
    _dot.frame = CGRectMake((self.bounds.size.width - d) / 2, (self.bounds.size.height - d) / 2, d, d);
    _dot.cornerRadius = d / 2;
    _dot.backgroundColor = [self.space.color colorWithAlphaComponent:self.isCurrent ? 1 : 0.55].CGColor;
    _dot.borderWidth = self.isCurrent ? 2 : 0;
    _dot.borderColor = [self brook_cg:[NSColor brook_dynamicLight:[NSColor colorWithWhite:1 alpha:0.9]
                                                             dark:[NSColor colorWithWhite:1 alpha:0.35]]];
}

@end
