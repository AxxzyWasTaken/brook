#import "Brook.h"

// MARK: - Tab row

/// One tab row in the sidebar: favicon, title, spinner, close button on hover.
@implementation TabCellView {
    HoverControl *_background;
    NSImageView *_icon;
    NSTextField *_label;
    IconButton *_closeButton;
    NSProgressIndicator *_spinner;
    NSTrackingArea *_tracking;
    BOOL _hovering;
    BOOL _selected;
}

+ (NSUserInterfaceItemIdentifier)reuseID { return @"TabCell"; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _background = [HoverControl new];
        _icon = [NSImageView new];
        _label = [NSTextField labelWithString:@""];
        _closeButton = [[IconButton alloc] initWithSymbol:@"xmark" size:10 tooltip:@"Close Tab" dimension:20 onClick:nil];
        _spinner = [NSProgressIndicator new];
        _fontSize = 13;

        self.identifier = TabCellView.reuseID;

        _background.cornerRadius = 9;
        _background.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_background];

        _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_icon];

        _spinner.style = NSProgressIndicatorStyleSpinning;
        _spinner.controlSize = NSControlSizeSmall;
        _spinner.displayedWhenStopped = NO;
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_spinner];

        _label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        _label.cell.truncatesLastVisibleLine = YES;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [_label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_label];

        __weak TabCellView *weakSelf = self;
        _closeButton.onClick = ^{
            TabCellView *self = weakSelf;
            BrowserTab *tab = self.tab;
            if (!self || !tab) return;
            if (self.onClose) self.onClose(tab);
        };
        [self addSubview:_closeButton];

        [NSLayoutConstraint activateConstraints:@[
            [_background.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_background.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_background.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_background.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:16],
            [_icon.heightAnchor constraintEqualToConstant:16],
            [_spinner.centerXAnchor constraintEqualToAnchor:_icon.centerXAnchor],
            [_spinner.centerYAnchor constraintEqualToAnchor:_icon.centerYAnchor],
            [_spinner.widthAnchor constraintEqualToConstant:14],
            [_spinner.heightAnchor constraintEqualToConstant:14],
            [_label.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:9],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-4],
            [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setFontSize:(CGFloat)fontSize {
    CGFloat oldValue = _fontSize;
    _fontSize = fontSize;
    if (fontSize != oldValue) _label.font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightMedium];
}

- (void)setHovering:(BOOL)hovering {
    _hovering = hovering;
    [self updateClose];
}

- (NSView *)hitTest:(NSPoint)point {
    // Let the table handle clicks and drags anywhere except the close button.
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (!_closeButton.isHidden && NSPointInRect(local, _closeButton.frame)) {
        return [_closeButton hitTest:[self convertPoint:local toView:_closeButton.superview]];
    }
    return NSPointInRect(local, self.bounds) ? self : nil;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    NSTrackingArea *t = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:t];
    _tracking = t;
}

- (void)mouseEntered:(NSEvent *)event {
    [self setHovering:YES];
    _background.baseColor = _selected ? NSColor.clearColor : Palette.rowHover;
}

- (void)mouseExited:(NSEvent *)event {
    [self setHovering:NO];
    _background.baseColor = NSColor.clearColor;
}

- (void)configureWithTab:(BrowserTab *)tab selected:(BOOL)selected {
    _tab = tab;
    _selected = selected;
    [self setHovering:NO];
    _background.baseColor = NSColor.clearColor;
    _background.isHighlightedState = selected;
    [self updateWithTab:tab];
}

- (void)updateWithTab:(BrowserTab *)tab {
    _label.stringValue = tab.displayTitle;
    _label.textColor = tab.isLoaded || !tab.isPinned ? NSColor.labelColor : NSColor.secondaryLabelColor;
    _icon.image = tab.favicon ?: [NSImage brook_symbol:@"globe" size:13];
    _icon.contentTintColor = NSColor.secondaryLabelColor;
    _icon.alphaValue = tab.isLoaded || tab.isPinned == NO ? 1 : 0.6;
    if (tab.isLoading && tab.favicon == nil) {
        [_spinner startAnimation:nil]; _icon.hidden = YES;
    } else {
        [_spinner stopAnimation:nil]; _icon.hidden = NO;
    }
    self.toolTip = tab.url.absoluteString;
    [self updateClose];
}

- (void)setSelected:(BOOL)s {
    _selected = s;
    _background.isHighlightedState = s;
    _background.baseColor = (!s && _hovering) ? Palette.rowHover : NSColor.clearColor;
    [self updateClose];
}

- (void)updateClose {
    _closeButton.hidden = !(_hovering || _selected);
    BrowserTab *tab = self.tab;
    if (tab && tab.isPinned) {
        [_closeButton setSymbol:tab.isLoaded ? @"minus" : @"xmark" size:10];
        _closeButton.hidden = _closeButton.isHidden || !tab.isLoaded;
        _closeButton.toolTip = @"Unload Pinned Tab";
    } else {
        [_closeButton setSymbol:@"xmark" size:10];
        _closeButton.toolTip = @"Close Tab";
    }
}

@end

// MARK: - "New Tab" row

@implementation NewTabCellView {
    HoverControl *_background;
    NSTextField *_label;
    NSTrackingArea *_tracking;
}

+ (NSUserInterfaceItemIdentifier)reuseID { return @"NewTabCell"; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _background = [HoverControl new];
        _label = [NSTextField labelWithString:@"New Tab"];
        _fontSize = 13;
        self.identifier = NewTabCellView.reuseID;
        _background.cornerRadius = 9;
        _background.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_background];
        NSImageView *icon = [NSImageView imageViewWithImage:
            [NSImage brook_symbol:@"plus" size:12 weight:NSFontWeightSemibold] ?: [NSImage new]];
        icon.contentTintColor = NSColor.secondaryLabelColor;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _label.textColor = NSColor.secondaryLabelColor;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:icon];
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_background.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_background.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_background.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_background.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:11],
            [icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:35],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setFontSize:(CGFloat)fontSize {
    CGFloat oldValue = _fontSize;
    _fontSize = fontSize;
    if (fontSize != oldValue) _label.font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightMedium];
}

- (NSView *)hitTest:(NSPoint)point {
    NSPoint local = [self convertPoint:point fromView:self.superview];
    return NSPointInRect(local, self.bounds) ? self : nil;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    NSTrackingArea *t = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:t];
    _tracking = t;
}

- (void)mouseEntered:(NSEvent *)event { _background.baseColor = Palette.rowHover; }
- (void)mouseExited:(NSEvent *)event { _background.baseColor = NSColor.clearColor; }

@end

// MARK: - Divider between pinned and regular tabs

@implementation DividerCellView {
    NSView *_line;
}

+ (NSUserInterfaceItemIdentifier)reuseID { return @"DividerCell"; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _line = [NSView new];
        self.identifier = DividerCellView.reuseID;
        _line.wantsLayer = YES;
        _line.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_line];
        [NSLayoutConstraint activateConstraints:@[
            [_line.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_line.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_line.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_line.heightAnchor constraintEqualToConstant:1],
        ]];
    }
    return self;
}

- (void)layout {
    [super layout];
    _line.layer.backgroundColor = [self brook_cg:Palette.divider];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    _line.layer.backgroundColor = [self brook_cg:Palette.divider];
}

@end

/// Row view that draws nothing itself; cells draw their own rounded backgrounds.
@implementation PlainRowView
- (void)drawSelectionInRect:(NSRect)dirtyRect {}
- (void)drawBackgroundInRect:(NSRect)dirtyRect {}
- (BOOL)isEmphasized { return NO; }
- (void)setEmphasized:(BOOL)emphasized {}
@end

/// Table that reports middle-clicks and swallows horizontal swipes for space switching.
@implementation SidebarTableView

- (void)otherMouseUp:(NSEvent *)event {
    NSInteger row = [self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (event.buttonNumber == 2 && row >= 0) {
        if (self.onMiddleClick) self.onMiddleClick(row);
    } else {
        [super otherMouseUp:event];
    }
}

- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)validateProposedFirstResponder:(NSResponder *)responder forEvent:(NSEvent *)event { return YES; }

@end

@implementation SidebarScrollView {
    BOOL _horizontal;
    CGFloat _accumulated;
    BOOL _swallowMomentum;
}

- (void)scrollWheel:(NSEvent *)event {
    if (!event.hasPreciseScrollingDeltas) { [super scrollWheel:event]; return; }
    if (event.phase == NSEventPhaseBegan) {
        _horizontal = std::abs(event.scrollingDeltaX) > std::abs(event.scrollingDeltaY) * 1.3;
        _accumulated = 0;
        _swallowMomentum = NO;
    }
    if (_horizontal) {
        if (event.phase == NSEventPhaseChanged || event.phase == NSEventPhaseBegan) _accumulated += event.scrollingDeltaX;
        if (event.phase == NSEventPhaseEnded || event.phase == NSEventPhaseCancelled) {
            if (_accumulated < -60) { if (self.onSwipe) self.onSwipe(1); }
            else if (_accumulated > 60) { if (self.onSwipe) self.onSwipe(-1); }
            _horizontal = NO;
            _swallowMomentum = YES;
        }
        return;
    }
    if (_swallowMomentum && event.momentumPhase != NSEventPhaseNone) {
        if (event.momentumPhase == NSEventPhaseEnded) _swallowMomentum = NO;
        return;
    }
    [super scrollWheel:event];
}

@end
