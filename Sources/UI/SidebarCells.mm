#import "Brook.h"

// MARK: - Row background

/// The rounded fill behind a tab, drawn in the Settings → Appearance → Tab style.
/// Card is HoverControl's own look; the others restyle only the selected state.
@interface TabRowBackground : HoverControl
@property (nonatomic) TabStyle style;
/// Accent bar: on the right (the page side of a left sidebar) or the left.
@property (nonatomic) BOOL barOnRight;
@end

@implementation TabRowBackground {
    CALayer *_bar;
}

- (void)setStyle:(TabStyle)style {
    _style = style;
    self.needsDisplay = YES;
}

- (void)setBarOnRight:(BOOL)barOnRight {
    _barOnRight = barOnRight;
    self.needsDisplay = YES;
}

- (void)layout {
    [super layout];
    self.needsDisplay = YES;   // the accent bar follows the height
}

- (void)updateLayer {
    [super updateLayer];
    CALayer *layer = self.layer;
    if (!layer) return;
    BOOL selected = self.isHighlightedState;
    layer.borderWidth = 0;
    BOOL showBar = selected && _style == TabStyleAccentBar;
    if (selected && _style != TabStyleCard) {
        layer.shadowOpacity = 0;
        NSColor *fill = NSColor.clearColor;
        switch (_style) {
            case TabStyleOutline:
                layer.borderWidth = 1;
                layer.borderColor = [self brook_cg:[BrookAccentColor() colorWithAlphaComponent:0.7]];
                break;
            case TabStyleAccentBar: fill = Palette.rowHover; break;
            case TabStyleTinted: {
                NSColor *space = BrowserState.shared.currentSpace.color ?: NSColor.controlAccentColor;
                CGFloat alpha = std::clamp<CGFloat>(0.22 * std::max<CGFloat>(Settings.tintStrength, 0.4), 0.08, 0.4);
                fill = [space colorWithAlphaComponent:alpha];
                break;
            }
            default: break;   // Flat: the title carries the selection
        }
        layer.backgroundColor = [self brook_cg:fill];
    }
    if (showBar && !_bar) {
        _bar = [CALayer layer];
        _bar.cornerRadius = 1.5;
        [layer addSublayer:_bar];
    }
    _bar.hidden = !showBar;
    if (showBar) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CGSize size = layer.bounds.size;
        CGFloat h = std::max<CGFloat>(12, size.height - 14);
        _bar.frame = CGRectMake(_barOnRight ? size.width - 3 : 0, (size.height - h) / 2, 3, h);
        _bar.backgroundColor = [self brook_cg:BrookAccentColor()];
        [CATransaction commit];
    }
}

@end

// MARK: - Tab row

/// One tab row in the sidebar: favicon, title (and site), spinner, close button.
@implementation TabCellView {
    TabRowBackground *_background;
    NSImageView *_icon;
    NSTextField *_label;
    NSTextField *_subtitle;
    NSStackView *_text;
    IconButton *_closeButton;
    NSProgressIndicator *_spinner;
    NSTrackingArea *_tracking;
    NSLayoutConstraint *_iconLeading;
    NSLayoutConstraint *_iconCentered;
    NSLayoutConstraint *_textTrailing;
    BOOL _hovering;
    BOOL _selected;
}

+ (NSUserInterfaceItemIdentifier)reuseID { return @"TabCell"; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _background = [TabRowBackground new];
        _icon = [NSImageView new];
        _label = [NSTextField labelWithString:@""];
        _subtitle = [NSTextField labelWithString:@""];
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

        for (NSTextField *f in @[_label, _subtitle]) {
            f.lineBreakMode = NSLineBreakByTruncatingTail;
            f.cell.truncatesLastVisibleLine = YES;
            [f setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        }
        _subtitle.textColor = NSColor.secondaryLabelColor;
        _subtitle.hidden = YES;
        _text = [NSStackView stackViewWithViews:@[_label, _subtitle]];
        _text.orientation = NSUserInterfaceLayoutOrientationVertical;
        _text.alignment = NSLayoutAttributeLeading;
        _text.spacing = 0;
        _text.detachesHiddenViews = YES;
        _text.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_text];

        __weak TabCellView *weakSelf = self;
        _closeButton.onClick = ^{
            TabCellView *self = weakSelf;
            BrowserTab *tab = self.tab;
            if (!self || !tab) return;
            if (self.onClose) self.onClose(tab);
        };
        [self addSubview:_closeButton];

        _iconLeading = [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10];
        _iconCentered = [_icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor];
        [NSLayoutConstraint activateConstraints:@[
            [_background.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_background.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_background.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_background.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            _iconLeading,
            [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:16],
            [_icon.heightAnchor constraintEqualToConstant:16],
            [_spinner.centerXAnchor constraintEqualToAnchor:_icon.centerXAnchor],
            [_spinner.centerYAnchor constraintEqualToAnchor:_icon.centerYAnchor],
            [_spinner.widthAnchor constraintEqualToConstant:14],
            [_spinner.heightAnchor constraintEqualToConstant:14],
            [_text.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:9],
            [_text.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        // Off in the icon rail (see -setIconOnly:): a 52pt cell has no room for text beside a
        // centred icon, and the clash would make AppKit drop constraints on every row.
        // Leaving the rail, the rows show their text while still rail-wide for a frame or two of
        // the slide, so the text's end gives way then rather than a required constraint.
        _textTrailing = [_text.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-4];
        _textTrailing.priority = NSLayoutPriorityRequired - 1;
        _textTrailing.active = YES;
        [self applyFont];
    }
    return self;
}

- (void)applyFont {
    BOOL bold = _selected && Settings.tabStyle == TabStyleFlat;
    _label.font = BrookUIFont(_fontSize, bold ? NSFontWeightSemibold : NSFontWeightMedium);
    _subtitle.font = BrookUIFont(std::max<CGFloat>(10, _fontSize - 2.5), NSFontWeightRegular);
}

- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = fontSize;
    [self applyFont];
}

- (void)setIconOnly:(BOOL)iconOnly {
    _iconOnly = iconOnly;
    _text.hidden = iconOnly;
    // Deactivate before activating so the old and new placements never clash.
    if (iconOnly) {
        _textTrailing.active = NO;
        _iconLeading.active = NO;
        _iconCentered.active = YES;
    } else {
        _iconCentered.active = NO;
        _iconLeading.active = YES;
        _textTrailing.active = YES;
    }
    [self updateClose];
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
    _background.style = Settings.tabStyle;
    _background.barOnRight = Settings.sidebarPosition != SidebarPositionRight;
    [self setHovering:NO];
    _background.baseColor = NSColor.clearColor;
    _background.isHighlightedState = selected;
    [self applyFont];
    [self updateWithTab:tab];
}

- (void)updateWithTab:(BrowserTab *)tab {
    _label.stringValue = tab.displayTitle;
    [self refreshTextColor];
    NSString *host = BrookHost(tab.url);
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    _subtitle.stringValue = host ?: @"";
    _subtitle.hidden = !(Settings.tabSubtitles && host.length);
    _icon.image = tab.favicon ?: [NSImage brook_symbol:@"globe" size:13];
    _icon.contentTintColor = NSColor.secondaryLabelColor;
    _icon.alphaValue = tab.isLoaded || tab.isPinned == NO ? 1 : 0.6;
    // Settings → Layout → While loading: the bar only spins icons that have none yet.
    LoadingIndicator indicator = Settings.loadingIndicator;
    BOOL spin = tab.isLoading && (indicator == LoadingIndicatorSpinner ||
                                  (indicator == LoadingIndicatorBar && tab.favicon == nil));
    if (spin) {
        [_spinner startAnimation:nil]; _icon.hidden = YES;
    } else {
        [_spinner stopAnimation:nil]; _icon.hidden = NO;
    }
    self.toolTip = _iconOnly ? tab.displayTitle : tab.url.absoluteString;
    [self updateClose];
}

/// Flat tabs show the selection in the title alone: the others are dimmed.
- (void)refreshTextColor {
    BrowserTab *tab = _tab;
    BOOL dim = !(tab.isLoaded || !tab.isPinned) || (Settings.tabStyle == TabStyleFlat && !_selected);
    _label.textColor = dim ? NSColor.secondaryLabelColor : NSColor.labelColor;
}

- (void)setSelected:(BOOL)s {
    _selected = s;
    _background.isHighlightedState = s;
    _background.baseColor = (!s && _hovering) ? Palette.rowHover : NSColor.clearColor;
    [self applyFont];
    [self refreshTextColor];
    [self updateClose];
}

- (void)updateClose {
    BOOL show = NO;
    switch (Settings.closeButtons) {
        case CloseButtonVisibilityAlways: show = YES; break;
        case CloseButtonVisibilityNever: show = NO; break;
        default: show = _hovering || _selected; break;
    }
    BrowserTab *tab = self.tab;
    if (_iconOnly) show = NO;   // the rail has no room; middle-click or ⌘W closes
    if (tab && tab.isPinned) {
        [_closeButton setSymbol:tab.isLoaded ? @"minus" : @"xmark" size:10];
        show = show && tab.isLoaded;
        _closeButton.toolTip = @"Unload Pinned Tab";
    } else {
        [_closeButton setSymbol:@"xmark" size:10];
        _closeButton.toolTip = @"Close Tab";
    }
    _closeButton.hidden = !show;
}

// MARK: Accessibility: one radio button per tab, its title as the label.

- (BOOL)isAccessibilityElement { return _tab != nil; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityRadioButtonRole; }
- (NSString *)accessibilityLabel { return _tab.displayTitle; }
- (id)accessibilityValue { return @(_selected); }
- (NSString *)accessibilityHelp {
    NSString *host = BrookHost(_tab.url);
    return _tab.isLoading ? [NSString stringWithFormat:@"Loading %@", host ?: @""] : host;
}

- (NSArray *)accessibilityChildren { return nil; }   // the title and icon are the label

- (BOOL)accessibilityPerformPress {
    BrowserTab *tab = _tab;
    if (!tab || !self.onSelect) return NO;
    self.onSelect(tab);
    return YES;
}

- (NSArray<NSAccessibilityCustomAction *> *)accessibilityCustomActions {
    BrowserTab *tab = _tab;
    if (!tab || !self.onClose) return nil;
    __weak TabCellView *weakSelf = self;
    NSString *name = tab.isPinned ? @"Unload Pinned Tab" : @"Close Tab";
    return @[[[NSAccessibilityCustomAction alloc] initWithName:name handler:^BOOL {
        TabCellView *self_ = weakSelf;
        BrowserTab *t = self_.tab;
        if (!t || !self_.onClose) return NO;
        self_.onClose(t);
        return YES;
    }]];
}

@end

// MARK: - "New Tab" row

@implementation NewTabCellView {
    HoverControl *_background;
    NSTextField *_label;
    NSImageView *_icon;
    NSTrackingArea *_tracking;
    NSLayoutConstraint *_iconLeading;
    NSLayoutConstraint *_iconCentered;
}

+ (NSUserInterfaceItemIdentifier)reuseID { return @"NewTabCell"; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _background = [HoverControl new];
        _label = [NSTextField labelWithString:@"New Tab"];
        _fontSize = 13;
        self.identifier = NewTabCellView.reuseID;
        self.toolTip = @"New Tab (⌘T)";
        _background.cornerRadius = 9;
        _background.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_background];
        _icon = [NSImageView imageViewWithImage:
            [NSImage brook_symbol:@"plus" size:12 weight:NSFontWeightSemibold] ?: [NSImage new]];
        _icon.contentTintColor = NSColor.secondaryLabelColor;
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = BrookUIFont(13, NSFontWeightMedium);
        _label.textColor = NSColor.secondaryLabelColor;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_icon];
        [self addSubview:_label];
        _iconLeading = [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:11];
        _iconCentered = [_icon.centerXAnchor constraintEqualToAnchor:self.centerXAnchor];
        [NSLayoutConstraint activateConstraints:@[
            [_background.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_background.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_background.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_background.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            _iconLeading,
            [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:35],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = fontSize;
    _label.font = BrookUIFont(fontSize, NSFontWeightMedium);
}

- (void)setIconOnly:(BOOL)iconOnly {
    _iconOnly = iconOnly;
    _label.hidden = iconOnly;
    if (iconOnly) {
        _iconLeading.active = NO;
        _iconCentered.active = YES;
    } else {
        _iconCentered.active = NO;
        _iconLeading.active = YES;
    }
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

- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityButtonRole; }
- (NSString *)accessibilityLabel { return @"New Tab"; }
- (NSString *)accessibilityHelp { return @"⌘T"; }
- (NSArray *)accessibilityChildren { return nil; }
- (BOOL)accessibilityPerformPress {
    if (!self.onPress) return NO;
    self.onPress();
    return YES;
}

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
    if (event.buttonNumber == 2 && row >= 0 && Settings.middleClickCloses) {
        if (self.onMiddleClick) self.onMiddleClick(row);
    } else {
        [super otherMouseUp:event];
    }
}

- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)validateProposedFirstResponder:(NSResponder *)responder forEvent:(NSEvent *)event { return YES; }

@end

@implementation SidebarScrollView

- (void)scrollWheel:(NSEvent *)event {
    if (self.swipeHandler && self.swipeHandler(event)) return;
    [super scrollWheel:event];
}

@end
