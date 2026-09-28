#import "Brook.h"

// MARK: - Extension button

/// One extension's toolbar button: its icon for the current tab, with the badge text it sets
/// (uBlock's blocked count, and so on) in a small capsule at the bottom-right.
@interface ExtensionButton : HoverControl
- (instancetype)initWithContext:(WKWebExtensionContext *)context size:(CGFloat)size;
@property (readonly) WKWebExtensionContext *context;
- (void)refreshForTab:(BrowserTab *)tab;
@end

@implementation ExtensionButton {
    NSImageView *_icon;
    CALayer *_badge;
    CATextLayer *_badgeText;
    NSString *_badgeString;
}

static const CGFloat kIconSize = 16;

- (instancetype)initWithContext:(WKWebExtensionContext *)context size:(CGFloat)size {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, size, size)])) {
        _context = context;
        self.cornerRadius = size / 2;
        CGFloat inset = floor((size - kIconSize) / 2);
        _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(inset, inset, kIconSize, kIconSize)];
        _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_icon];
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow { return NO; }

- (void)updateLayer {
    [super updateLayer];
    // The badge hangs past the round hover shape; the corner radius alone rounds the background.
    self.layer.masksToBounds = NO;
}

- (void)refreshForTab:(BrowserTab *)tab {
    WKWebExtensionContext *ctx = _context;
    WKWebExtensionAction *action = [ctx actionForTab:tab];
    NSSize size = NSMakeSize(kIconSize, kIconSize);
    NSImage *image = [action iconForSize:size] ?: [ctx.webExtension iconForSize:size];
    if (_icon.image != image) _icon.image = image ?: [NSImage brook_symbol:@"puzzlepiece.extension" size:13];
    _icon.contentTintColor = image ? nil : NSColor.secondaryLabelColor;
    BOOL enabled = action ? action.isEnabled : YES;
    _icon.alphaValue = enabled ? 1 : 0.4;
    NSString *name = action.label.length ? action.label : (ctx.webExtension.displayName ?: @"Extension");
    if (![self.toolTip isEqualToString:name]) {
        self.toolTip = name;
        self.accessibilityLabel = name;
    }
    [self setBadge:action.badgeText];
}

- (void)setBadge:(NSString *)text {
    if (text.length == 0) text = nil;
    if (text == _badgeString || [text isEqualToString:_badgeString]) return;
    _badgeString = [text copy];
    if (!text) {
        _badge.hidden = YES;
        return;
    }
    if (!_badge) {
        _badge = [CALayer layer];
        _badge.cornerCurve = kCACornerCurveContinuous;
        _badge.zPosition = 1;   // over the icon's layer, which is a sibling
        _badgeText = [CATextLayer layer];
        _badgeText.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:8 weight:NSFontWeightBold];
        _badgeText.fontSize = 8;
        _badgeText.alignmentMode = kCAAlignmentCenter;
        [_badge addSublayer:_badgeText];
        [self.layer addSublayer:_badge];
        [self applyBadgeColors];
    }
    // Up to four characters, like Chrome.
    NSString *shown = text.length > 4 ? [text substringToIndex:4] : text;
    _badgeText.string = shown;
    CGFloat scale = self.window.backingScaleFactor ?: 2;
    _badgeText.contentsScale = scale;
    NSSize textSize = [shown sizeWithAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:8 weight:NSFontWeightBold]}];
    CGFloat h = 11, w = std::max<CGFloat>(h, ceil(textSize.width) + 5);
    NSSize bounds = self.bounds.size;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _badge.hidden = NO;
    _badge.cornerRadius = h / 2;
    _badge.frame = CGRectMake(std::min<CGFloat>(bounds.width - w, NSMaxX(_icon.frame) - w + 5), NSMinY(_icon.frame) - 3, w, h);
    _badgeText.frame = CGRectMake(0, (h - ceil(textSize.height)) / 2 + 0.5, w, ceil(textSize.height));
    [CATransaction commit];
}

- (void)applyBadgeColors {
    // A neutral badge that reads on glass in both appearances.
    _badge.backgroundColor = [self brook_cg:[NSColor brook_dynamicLight:[NSColor colorWithWhite:0.18 alpha:0.9]
                                                                   dark:[NSColor colorWithWhite:0.92 alpha:0.95]]];
    _badgeText.foregroundColor = [self brook_cg:[NSColor brook_dynamicLight:NSColor.whiteColor
                                                                       dark:[NSColor colorWithWhite:0.1 alpha:1]]];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (_badge) [self applyBadgeColors];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    _badgeText.contentsScale = self.window.backingScaleFactor ?: 2;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    WKWebExtensionContext *ctx = _context;
    ExtensionManager *manager = ExtensionManager.shared;
    NSMenu *menu = [NSMenu new];
    NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:ctx.webExtension.displayName ?: @"Extension" action:nil keyEquivalent:@""];
    header.enabled = NO;
    [menu addItem:header];
    // The extension's own items (chrome.contextMenus with the "action" context).
    NSArray<NSMenuItem *> *own = [ctx actionForTab:BrowserState.shared.selectedTab].menuItems;
    if (own.count) {
        [menu addItem:NSMenuItem.separatorItem];
        for (NSMenuItem *item in own) [menu addItem:[item copy]];   // an item can't be in two menus
    }
    [menu addItem:NSMenuItem.separatorItem];
    if (NSURL *options = ctx.optionsPageURL) {
        [menu addItem:[[ClosureMenuItem alloc] initWithTitle:@"Options" handler:^{
            [BrowserState.shared openTabWithURL:options inSpace:nil select:YES];
        }]];
    }
    [menu addItem:[[ClosureMenuItem alloc] initWithTitle:@"Hide from Toolbar" handler:^{
        [manager setInToolbar:NO forContext:ctx];
    }]];
    [menu addItem:[[ClosureMenuItem alloc] initWithTitle:@"Remove Extension" handler:^{
        [manager uninstall:ctx];
    }]];
    return menu;
}

@end

// MARK: - Bar

@implementation ExtensionsBar {
    CGFloat _buttonSize;
    NSArray<ExtensionButton *> *_buttons;   // toolbar extensions, in install order
    NSMapTable<WKWebExtensionContext *, ExtensionButton *> *_byContext;
    IconButton *_moreButton;
}

- (instancetype)initWithButtonSize:(CGFloat)buttonSize {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _buttonSize = buttonSize;
        _buttonCornerRadius = buttonSize / 2;
        _maxVisible = NSUIntegerMax;
        _buttons = @[];
        _byContext = [NSMapTable strongToStrongObjectsMapTable];
        __weak ExtensionsBar *weakSelf = self;
        _moreButton = [[IconButton alloc] initWithSymbol:@"ellipsis" size:12 tooltip:@"Extensions"
                                               dimension:buttonSize onClick:^{ [weakSelf showMoreMenu]; }];
        _moreButton.cornerRadius = buttonSize / 2;
        _moreButton.translatesAutoresizingMaskIntoConstraints = YES;
        [self addSubview:_moreButton];
        [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:300 forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(extensionsChanged) name:ExtensionManagerDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(actionChanged:) name:ExtensionManagerActionDidChangeNotification object:nil];
        [self extensionsChanged];
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow { return YES; }

- (NSSize)intrinsicContentSize {
    CGFloat length = (CGFloat)(std::min(_buttons.count, _maxVisible) + 1) * _buttonSize;
    return _vertical ? NSMakeSize(_buttonSize, length) : NSMakeSize(length, _buttonSize);
}

- (void)setVertical:(BOOL)vertical {
    _vertical = vertical;
    [self invalidateIntrinsicContentSize];
    self.needsLayout = YES;
}

- (void)setMaxVisible:(NSUInteger)maxVisible {
    _maxVisible = maxVisible;
    [self invalidateIntrinsicContentSize];
    self.needsLayout = YES;
}

- (void)setButtonCornerRadius:(CGFloat)buttonCornerRadius {
    _buttonCornerRadius = buttonCornerRadius;
    _moreButton.cornerRadius = buttonCornerRadius;
    for (ExtensionButton *b in _buttons) b.cornerRadius = buttonCornerRadius;
}

- (void)setTab:(BrowserTab *)tab {
    _tab = tab;
    for (ExtensionButton *b in _buttons) [b refreshForTab:tab];
}

- (void)extensionsChanged {
    ExtensionManager *manager = ExtensionManager.shared;
    NSMapTable<WKWebExtensionContext *, ExtensionButton *> *old = _byContext;
    NSMapTable<WKWebExtensionContext *, ExtensionButton *> *next = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableArray<ExtensionButton *> *buttons = [NSMutableArray array];
    NSArray<WKWebExtensionContext *> *contexts = manager.contexts;
    for (WKWebExtensionContext *ctx in contexts) {
        if (![manager isInToolbar:ctx]) continue;
        ExtensionButton *b = [old objectForKey:ctx];
        if (b) {
            [old removeObjectForKey:ctx];
        } else {
            b = [[ExtensionButton alloc] initWithContext:ctx size:_buttonSize];
            b.cornerRadius = _buttonCornerRadius;
            b.onClick = ^{ [ctx performActionForTab:BrowserState.shared.selectedTab]; };
            [self addSubview:b];
        }
        [b refreshForTab:_tab];
        [next setObject:b forKey:ctx];
        [buttons addObject:b];
    }
    for (ExtensionButton *b in old.objectEnumerator) [b removeFromSuperview];
    BOOL countChanged = buttons.count != _buttons.count;
    _buttons = buttons;
    _byContext = next;
    // With nothing installed, "…" is where extensions come from: show that.
    [_moreButton setSymbol:contexts.count ? @"ellipsis" : @"puzzlepiece.extension" size:12];
    if (countChanged) [self invalidateIntrinsicContentSize];
    self.needsLayout = YES;
}

- (void)actionChanged:(NSNotification *)note {
    [[_byContext objectForKey:note.object] refreshForTab:_tab];
}

- (void)layout {
    [super layout];
    NSSize size = self.bounds.size;
    CGFloat step = _buttonSize;
    if (_vertical) {
        // Top down; AppKit's y grows upwards, so count from the top edge.
        NSUInteger fit = (NSUInteger)std::max<CGFloat>(0, floor((size.height - _buttonSize) / step));
        NSUInteger visible = std::min({fit, _buttons.count, _maxVisible});
        CGFloat x = floor((size.width - _buttonSize) / 2);
        CGFloat top = size.height;
        for (NSUInteger i = 0; i < _buttons.count; i++) {
            ExtensionButton *b = _buttons[i];
            b.hidden = i >= visible;
            if (i < visible) {
                top -= step;
                NSRect r = NSMakeRect(x, top, _buttonSize, _buttonSize);
                if (!NSEqualRects(b.frame, r)) b.frame = r;
            }
        }
        NSRect more = NSMakeRect(x, top - step, _buttonSize, _buttonSize);
        if (!NSEqualRects(_moreButton.frame, more)) _moreButton.frame = more;
        return;
    }
    // As many buttons as fit before "…", which always shows at the end.
    NSUInteger fit = (NSUInteger)std::max<CGFloat>(0, floor((size.width - _buttonSize) / step));
    NSUInteger visible = std::min({fit, _buttons.count, _maxVisible});
    CGFloat y = floor((size.height - _buttonSize) / 2);
    // Right-aligned, in install order; when squeezed the last ones move into "…", like Chrome.
    CGFloat x = size.width - (CGFloat)(visible + 1) * step;
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        ExtensionButton *b = _buttons[i];
        b.hidden = i >= visible;
        if (i < visible) {
            NSRect r = NSMakeRect(x, y, _buttonSize, _buttonSize);
            if (!NSEqualRects(b.frame, r)) b.frame = r;
            x += step;
        }
    }
    NSRect more = NSMakeRect(x, y, _buttonSize, _buttonSize);
    if (!NSEqualRects(_moreButton.frame, more)) _moreButton.frame = more;
}

- (NSView *)anchorForContext:(WKWebExtensionContext *)context {
    ExtensionButton *b = context ? [_byContext objectForKey:context] : nil;
    return b && !b.isHidden ? b : _moreButton;
}

- (void)showMoreMenu {
    ExtensionManager *manager = ExtensionManager.shared;
    BrowserWindowController *browser = manager.window;
    BrowserTab *tab = BrowserState.shared.selectedTab;
    NSArray<WKWebExtensionContext *> *contexts = manager.contexts;
    NSMenu *menu = [NSMenu new];
    NSSize iconSize = NSMakeSize(16, 16);
    auto iconFor = [&](WKWebExtensionContext *ctx) {
        NSImage *image = [[[ctx actionForTab:tab] iconForSize:iconSize] ?: [ctx.webExtension iconForSize:iconSize] copy];
        image.size = iconSize;
        return image;
    };

    // Extensions without a button showing: hidden ones and any the bar had no room for.
    BOOL listed = NO;
    for (WKWebExtensionContext *ctx in contexts) {
        ExtensionButton *b = [_byContext objectForKey:ctx];
        if (b && !b.isHidden) continue;
        WKWebExtensionAction *action = [ctx actionForTab:tab];
        NSString *title = ctx.webExtension.displayName ?: @"Extension";
        if (action.badgeText.length) title = [title stringByAppendingFormat:@"  (%@)", action.badgeText];
        ClosureMenuItem *item = [[ClosureMenuItem alloc] initWithTitle:title handler:^{
            [ctx performActionForTab:BrowserState.shared.selectedTab];
        }];
        [item brook_setVisibleImage:iconFor(ctx)];
        item.enabled = action ? action.isEnabled : YES;
        [menu addItem:item];
        listed = YES;
    }
    if (contexts.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No extensions yet" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
        listed = YES;
    }
    if (listed) [menu addItem:NSMenuItem.separatorItem];

    if (contexts.count) {
        NSMenuItem *toolbar = [[NSMenuItem alloc] initWithTitle:@"Show in Toolbar" action:nil keyEquivalent:@""];
        NSMenu *sub = [NSMenu new];
        for (WKWebExtensionContext *ctx in contexts) {
            BOOL shown = [manager isInToolbar:ctx];
            ClosureMenuItem *item = [[ClosureMenuItem alloc] initWithTitle:ctx.webExtension.displayName ?: @"Extension"
                                                                   handler:^{ [manager setInToolbar:!shown forContext:ctx]; }];
            [item brook_setVisibleImage:iconFor(ctx)];
            item.state = shown ? NSControlStateValueOn : NSControlStateValueOff;
            [sub addItem:item];
        }
        toolbar.submenu = sub;
        [menu addItem:toolbar];
        [menu addItem:NSMenuItem.separatorItem];
    }

    __weak BrowserWindowController *weakBrowser = browser;
    [menu addItem:[[ClosureMenuItem alloc] initWithTitle:@"Add from Chrome Web Store…" handler:^{
        [weakBrowser promptChromeWebStore];
    }]];
    [menu addItem:[[ClosureMenuItem alloc] initWithTitle:@"Browse Chrome Web Store" handler:^{
        [BrowserState.shared openTabWithURL:[NSURL URLWithString:@"https://chromewebstore.google.com"] inSpace:nil select:YES];
    }]];
    [menu addItem:[[ClosureMenuItem alloc] initWithTitle:@"Install from File or Folder…" handler:^{
        [weakBrowser promptInstallFile];
    }]];
    if (contexts.count) {
        NSMenuItem *remove = [[NSMenuItem alloc] initWithTitle:@"Remove Extension" action:nil keyEquivalent:@""];
        NSMenu *sub = [NSMenu new];
        for (WKWebExtensionContext *ctx in contexts) {
            ClosureMenuItem *item = [[ClosureMenuItem alloc] initWithTitle:ctx.webExtension.displayName ?: @"Extension"
                                                                   handler:^{ [manager uninstall:ctx]; }];
            [item brook_setVisibleImage:iconFor(ctx)];
            [sub addItem:item];
        }
        remove.submenu = sub;
        [menu addItem:remove];
    }
    // Beside the button in the rail (the page is to that side), below it in a row.
    NSPoint at = _vertical ? NSMakePoint(NSWidth(_moreButton.bounds) + 4, NSHeight(_moreButton.bounds)) : NSMakePoint(0, -4);
    [menu popUpMenuPositioningItem:nil atLocation:at inView:_moreButton];
}

@end
