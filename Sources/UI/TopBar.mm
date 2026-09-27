#import "Brook.h"

namespace {
const CGFloat kToolbarHeight = 34;
const CGFloat kTrackHeight = 32;
const CGFloat kTrackInset = 2;                        // gap between the track's edge and a tab's fill
const CGFloat kTabHeight = kTrackHeight - 2 * kTrackInset;
const CGFloat kPinnedTabWidth = 40;
const CGFloat kTabMinWidth = 200;                     // keeps about 16 characters of title readable
const CGFloat kTabShrunkMinWidth = 36;                // "shrink to fit": down to just the icon
const CGFloat kCloseRoom = 26;                        // kept free on both sides so titles stay centred
const CGFloat kFavoriteSize = 28;
const CGFloat kFavoritePad = 3;
const CGFloat kDragThreshold = 4;

/// Where a drop lands in the strip: pinned or regular list, index in it, and x for the indicator.
struct Slot {
    bool pinned;
    NSInteger index;
    CGFloat x;
};
}  // namespace

// MARK: - Drag and drop helpers

/// Drag image for a tab or bookmark: icon and (optional) title on a rounded chip.
static NSImage *TabDragImage(NSSize size, NSImage *icon, NSString *title, NSFont *font) {
    return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor.windowBackgroundColor colorWithAlphaComponent:0.92] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:8 yRadius:8] fill];
        CGFloat x = title.length ? 10 : floor((rect.size.width - 16) / 2);
        [icon drawInRect:NSMakeRect(x, floor(NSMidY(rect) - 8), 16, 16)];
        if (title.length) {
            NSMutableParagraphStyle *para = [NSMutableParagraphStyle new];
            para.lineBreakMode = NSLineBreakByTruncatingTail;
            NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: NSColor.labelColor,
                                    NSParagraphStyleAttributeName: para};
            CGFloat h = ceil(font.ascender - font.descender);
            [title drawInRect:NSMakeRect(x + 23, floor(NSMidY(rect) - h / 2), rect.size.width - x - 33, h)
               withAttributes:attrs];
        }
        return YES;
    }];
}

/// Starts dragging a tab: its id (so Brook can move it) and its URL (for other apps).
static void BeginTabDrag(NSView<NSDraggingSource> *source, NSEvent *event, BrowserTab *tab, NSImage *image) {
    NSPasteboardItem *item = [NSPasteboardItem new];
    [item setString:tab.identifier.UUIDString forType:BrookTabPasteboardType];
    NSURL *url = tab.url;
    if (url) [item setString:url.absoluteString forType:NSPasteboardTypeURL];
    NSDraggingItem *drag = [[NSDraggingItem alloc] initWithPasteboardWriter:item];
    [drag setDraggingFrame:source.bounds contents:image];
    [source beginDraggingSessionWithItems:@[drag] event:event source:source];
}

static BrowserTab *DraggedTab(id<NSDraggingInfo> info) {
    NSString *s = [info.draggingPasteboard stringForType:BrookTabPasteboardType];
    NSUUID *uuid = s ? [[NSUUID alloc] initWithUUIDString:s] : nil;
    return uuid ? [BrowserState.shared tabWithID:uuid] : nil;
}

static NSURL *DraggedURL(id<NSDraggingInfo> info) {
    NSString *s = [info.draggingPasteboard stringForType:NSPasteboardTypeURL];
    return s ? [NSURL URLWithString:s] : nil;
}

/// The thin accent-coloured bar showing where a dragged tab will land.
static NSView *MakeDropIndicator(void) {
    NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
    v.wantsLayer = YES;
    v.layer.cornerRadius = 1;
    v.hidden = YES;
    return v;
}

static void ShowDropIndicator(NSView *indicator, NSView *host, NSRect frame) {
    if (indicator.superview != host || indicator != host.subviews.lastObject) {
        [host addSubview:indicator positioned:NSWindowAbove relativeTo:nil];
    }
    indicator.layer.backgroundColor = [indicator brook_cg:NSColor.controlAccentColor];
    indicator.frame = frame;
    indicator.hidden = NO;
}

/// A tab's icon: its favicon, or a globe. The globe is shared so unchanged icons compare equal.
static NSImage *TabIcon(BrowserTab *tab) {
    static NSImage *globe = [NSImage brook_symbol:@"globe" size:13];
    return tab.favicon ?: globe;
}

// MARK: - Tab

static NSColor *SelectedRimColor(void) {
    static NSColor *c = [NSColor brook_dynamicLight:[NSColor colorWithWhite:0 alpha:0.07]
                                               dark:[NSColor colorWithWhite:1 alpha:0.14]];
    return c;
}

/// One tab in the track, Safari-style: favicon and title centred, no fill until it's hovered or
/// selected; selected gets the sidebar's raised fill with a hairline rim. The close button shows
/// on hover. Pinned tabs show just the icon. Laid out with frames: a strip can hold a lot of tabs
/// and they all resize together.
@interface TopTabView : HoverControl <NSDraggingSource>
- (instancetype)initWithTab:(BrowserTab *)tab;
@property (readonly) BrowserTab *tab;
@property (nonatomic) BOOL pinnedStyle;
@property (nonatomic) BOOL selected;
@property (nonatomic) CGFloat fontSize;
@property (copy) void (^onSelect)(BrowserTab *tab);
@property (copy) void (^onClose)(BrowserTab *tab);
/// Hover changed; the strip hides the separators beside a hovered tab.
@property (copy) void (^onHoverChange)(void);
@property (copy) NSMenu *(^menuProvider)(BrowserTab *tab);
- (void)refresh;
@end

@implementation TopTabView {
    NSImageView *_icon;
    NSTextField *_label;
    CGFloat _labelWidth;
    CGFloat _labelHeight;
    IconButton *_closeButton;           // made the first time it's needed
    NSProgressIndicator *_spinner;      // made the first time a tab loads without a favicon
    NSPoint _dragStart;
    BOOL _mayDrag;
    BOOL _iconOnly;
}

- (instancetype)initWithTab:(BrowserTab *)tab {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, kTabMinWidth, kTabHeight)])) {
        _tab = tab;
        self.cornerRadius = 8;
        _icon = [NSImageView new];
        _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        _icon.contentTintColor = NSColor.secondaryLabelColor;
        [self addSubview:_icon];
        _label = [NSTextField labelWithString:@""];
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        _label.textColor = NSColor.secondaryLabelColor;
        [self addSubview:_label];
        self.fontSize = 13;
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityRadioButtonRole;
        [self refresh];
    }
    return self;
}

- (void)setFontSize:(CGFloat)fontSize {
    if (fontSize == _fontSize) return;
    _fontSize = fontSize;
    _label.font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightMedium];
    [self measureLabel];
}

- (void)measureLabel {
    NSSize size = _label.intrinsicContentSize;
    // A label exactly its intrinsic width still truncates its last glyph; give it a little room.
    _labelWidth = ceil(size.width) + 4;
    _labelHeight = ceil(size.height);
    self.needsLayout = YES;
}

- (void)setPinnedStyle:(BOOL)pinnedStyle {
    if (pinnedStyle == _pinnedStyle) return;
    _pinnedStyle = pinnedStyle;
    self.needsLayout = YES;
    [self updateClose];
}

- (void)setSelected:(BOOL)selected {
    if (selected == _selected) return;
    _selected = selected;
    self.isHighlightedState = selected;
    self.accessibilityValue = @(selected);
    [self refreshTextColor];
}

- (void)refreshTextColor {
    BOOL dim = _tab.isPinned && !_tab.isLoaded;
    _label.textColor = _selected ? NSColor.labelColor : NSColor.secondaryLabelColor;
    // In an icon-only tab the close button takes the icon's place on hover.
    BOOL covered = _iconOnly && !_pinnedStyle && self.isHovering;
    _icon.alphaValue = covered ? 0 : (dim ? 0.6 : 1);
}

- (void)refresh {
    BrowserTab *tab = _tab;
    NSString *title = tab.displayTitle ?: @"";
    // Skip no-op sets: titles and favicons are re-sent often while a page loads.
    if (![_label.stringValue isEqualToString:title]) {
        _label.stringValue = title;
        self.toolTip = title;
        self.accessibilityLabel = title;
        [self measureLabel];
    }
    NSImage *icon = TabIcon(tab);
    if (_icon.image != icon) _icon.image = icon;
    [self refreshTextColor];
    BOOL spin = tab.isLoading && tab.favicon == nil;
    if (spin && !_spinner) {
        _spinner = [NSProgressIndicator new];
        _spinner.style = NSProgressIndicatorStyleSpinning;
        _spinner.controlSize = NSControlSizeSmall;
        _spinner.displayedWhenStopped = NO;
        [self addSubview:_spinner];
        self.needsLayout = YES;
    }
    if (spin) [_spinner startAnimation:nil]; else [_spinner stopAnimation:nil];
    _icon.hidden = spin;
}

- (void)updateLayer {
    [super updateLayer];
    CALayer *layer = self.layer;
    layer.borderWidth = self.isHighlightedState ? 0.5 : 0;
    if (self.isHighlightedState) layer.borderColor = [self brook_cg:SelectedRimColor()];
}

- (void)hoverChanged {
    [self updateClose];
    if (self.onHoverChange) self.onHoverChange();
}

- (void)updateClose {
    BOOL show = !_pinnedStyle && self.isHovering;
    [self refreshTextColor];
    if (show && !_closeButton) {
        __weak TopTabView *weakSelf = self;
        _closeButton = [[IconButton alloc] initWithSymbol:@"xmark" size:9 tooltip:@"Close Tab (⌘W)" dimension:18
                                                  onClick:^{
            TopTabView *self_ = weakSelf;
            if (self_ && self_.onClose) self_.onClose(self_.tab);
        }];
        _closeButton.cornerRadius = 5;
        // Frame-positioned like the rest of the tab; its own 18×18 size constraints still hold.
        _closeButton.translatesAutoresizingMaskIntoConstraints = YES;
        [self addSubview:_closeButton];
        self.needsLayout = YES;
    }
    _closeButton.hidden = !show;
}

- (void)layout {
    [super layout];
    NSSize size = self.bounds.size;
    CGFloat cy = floor(size.height / 2);
    NSRect iconRect;
    // Too narrow for a readable title (only when tabs shrink to fit): just the icon, which the
    // close button replaces on hover.
    CGFloat room = std::max<CGFloat>(0, size.width - 2 * kCloseRoom - 22);
    BOOL iconOnly = _pinnedStyle || room < 24;
    _label.hidden = iconOnly;
    if (iconOnly) {
        iconRect = NSMakeRect(floor((size.width - 16) / 2), cy - 8, 16, 16);
        [_closeButton setFrameOrigin:NSMakePoint(floor((size.width - 18) / 2), cy - 9)];
    } else {
        // Icon and title centred as a group, clear of the close button on either side.
        CGFloat textWidth = std::min(_labelWidth, room);
        CGFloat x = floor((size.width - 22 - textWidth) / 2);
        iconRect = NSMakeRect(x, cy - 8, 16, 16);
        _label.frame = NSMakeRect(x + 22, floor(cy - _labelHeight / 2), textWidth, _labelHeight);
        [_closeButton setFrameOrigin:NSMakePoint(5, cy - 9)];
    }
    _icon.frame = iconRect;
    _spinner.frame = NSInsetRect(iconRect, 1, 1);
    _iconOnly = iconOnly;
    [self updateClose];
}

// Tabs select on mouse down, like Safari, and drag once the pointer moves a little.
- (void)mouseDown:(NSEvent *)event {
    _dragStart = event.locationInWindow;
    _mayDrag = YES;
    if (self.onSelect) self.onSelect(_tab);
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_mayDrag) return;
    NSPoint p = event.locationInWindow;
    if (hypot(p.x - _dragStart.x, p.y - _dragStart.y) <= kDragThreshold) return;
    _mayDrag = NO;
    NSImage *image = TabDragImage(self.bounds.size, _icon.image, _pinnedStyle ? nil : _label.stringValue, _label.font);
    BeginTabDrag(self, event, _tab, image);
}

- (void)mouseUp:(NSEvent *)event { _mayDrag = NO; }

- (void)otherMouseUp:(NSEvent *)event {
    if (event.buttonNumber == 2 && self.onClose) self.onClose(_tab);
    else [super otherMouseUp:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event { return self.menuProvider ? self.menuProvider(_tab) : nil; }

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return context == NSDraggingContextWithinApplication ? NSDragOperationMove : NSDragOperationCopy;
}

@end

// MARK: - Tab strip

/// Scroll view for the strip. A mouse wheel only scrolls vertically, so turn it sideways.
@interface TabScrollView : NSScrollView
@end

@implementation TabScrollView

- (BOOL)mouseDownCanMoveWindow { return YES; }

- (void)scrollWheel:(NSEvent *)event {
    if (!event.hasPreciseScrollingDeltas && event.scrollingDeltaX == 0 && event.scrollingDeltaY != 0) {
        NSClipView *clip = self.contentView;
        CGFloat maxX = std::max<CGFloat>(0, NSWidth(self.documentView.frame) - NSWidth(clip.bounds));
        NSPoint origin = clip.bounds.origin;
        origin.x = std::clamp<CGFloat>(origin.x - event.scrollingDeltaY * 10, 0, maxX);
        [clip scrollToPoint:origin];
        [self reflectScrolledClipView:clip];
        return;
    }
    [super scrollWheel:event];
}

@end

/// The tab track: the current space's pinned tabs (icons) then its regular tabs, sharing the
/// width equally like Safari and scrolling sideways once they reach their minimum width. Hairline
/// separators sit between tabs, except beside the selected or hovered one. Tab views are reused
/// across reloads and found through a map, so a title change or a selection touches only the
/// views involved.
@interface TabStripView : NSView
@property (weak) BrowserWindowController *browser;
@property (nonatomic) CGFloat fontSize;
/// Squeeze tabs down to icons rather than scroll (Settings → Appearance → Many top tabs).
@property (nonatomic) BOOL shrinkToFit;
- (void)reloadSpace:(Space *)space selected:(BrowserTab *)selected;
- (void)updateSelection:(BrowserTab *)selected;
- (void)refresh:(BrowserTab *)tab;
@end

@implementation TabStripView {
    TabScrollView *_scroll;
    NSView *_document;
    NSView *_indicator;
    NSArray<TopTabView *> *_tabViews;   // pinned first
    NSMapTable<BrowserTab *, TopTabView *> *_byTab;
    NSMutableArray<CALayer *> *_separators;
    NSUInteger _pinnedCount;
    __weak BrowserTab *_selected;
}

static const CGFloat kTabGap = 2;

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _fontSize = 13;
        _tabViews = @[];
        _byTab = [NSMapTable strongToStrongObjectsMapTable];
        _separators = [NSMutableArray array];
        self.wantsLayer = YES;
        self.layer.cornerRadius = 8 + kTrackInset;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _document = [NSView new];
        _document.wantsLayer = YES;
        _indicator = MakeDropIndicator();
        _scroll = [TabScrollView new];
        _scroll.documentView = _document;
        _scroll.drawsBackground = NO;
        _scroll.hasHorizontalScroller = NO;
        _scroll.hasVerticalScroller = NO;
        _scroll.verticalScrollElasticity = NSScrollElasticityNone;
        _scroll.automaticallyAdjustsContentInsets = NO;
        _scroll.contentView.wantsLayer = YES;
        _scroll.contentView.layer.cornerRadius = 8;
        _scroll.contentView.layer.masksToBounds = YES;
        [self addSubview:_scroll];
        [self registerForDraggedTypes:@[BrookTabPasteboardType, NSPasteboardTypeURL]];
        [self applyColors];
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow { return YES; }

- (void)applyColors {
    self.layer.backgroundColor = [self brook_cg:Palette.pill];
    CGColorRef divider = [self brook_cg:Palette.divider];
    for (CALayer *l in _separators) l.backgroundColor = divider;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self applyColors];
}

- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = fontSize;
    for (TopTabView *v in _tabViews) v.fontSize = fontSize;
}

- (void)setShrinkToFit:(BOOL)shrinkToFit {
    if (shrinkToFit == _shrinkToFit) return;
    _shrinkToFit = shrinkToFit;
    self.needsLayout = YES;
    [self scrollToSelected];
}

- (TopTabView *)makeViewForTab:(BrowserTab *)tab {
    TopTabView *v = [[TopTabView alloc] initWithTab:tab];
    __weak TabStripView *weakSelf = self;
    v.onSelect = ^(BrowserTab *t) { [BrowserState.shared selectTab:t]; };
    v.onClose = ^(BrowserTab *t) { [BrowserState.shared close:t]; };
    v.onHoverChange = ^{ [weakSelf updateSeparators]; };
    v.menuProvider = ^NSMenu *(BrowserTab *t) { return [weakSelf.browser menuForTab:t]; };
    return v;
}

- (void)reloadSpace:(Space *)space selected:(BrowserTab *)selected {
    NSMapTable<BrowserTab *, TopTabView *> *old = _byTab;
    NSMapTable<BrowserTab *, TopTabView *> *next = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableArray<TopTabView *> *views = [NSMutableArray arrayWithCapacity:space.pinned.count + space.tabs.count];
    auto take = [&](BrowserTab *tab, BOOL pinned) {
        TopTabView *v = [old objectForKey:tab];
        if (v) {
            [old removeObjectForKey:tab];
            [v refresh];   // pinning changes how an unloaded tab looks
        } else {
            v = [self makeViewForTab:tab];
            [_document addSubview:v];
        }
        v.pinnedStyle = pinned;
        v.fontSize = _fontSize;
        v.selected = tab == selected;
        [next setObject:v forKey:tab];
        [views addObject:v];
    };
    for (BrowserTab *t in space.pinned) take(t, YES);
    for (BrowserTab *t in space.tabs) take(t, NO);
    for (TopTabView *v in old.objectEnumerator) [v removeFromSuperview];
    _tabViews = views;
    _byTab = next;
    _pinnedCount = space.pinned.count;
    _selected = selected;
    self.needsLayout = YES;
    [self scrollToSelected];
}

- (void)updateSelection:(BrowserTab *)selected {
    BrowserTab *previous = _selected;
    if (previous == selected) return;
    if (previous) [_byTab objectForKey:previous].selected = NO;
    _selected = selected;
    if (selected) [_byTab objectForKey:selected].selected = YES;
    [self updateSeparators];
    [self scrollToSelected];
}

- (void)refresh:(BrowserTab *)tab {
    [[_byTab objectForKey:tab] refresh];
}

- (void)scrollToSelected {
    BrowserTab *selected = _selected;
    TopTabView *v = selected ? [_byTab objectForKey:selected] : nil;
    if (!v || !self.window) return;
    [self layoutSubtreeIfNeeded];
    [_document scrollRectToVisible:NSInsetRect(v.frame, -kTabMinWidth / 3, 0)];
}

- (void)layout {
    [super layout];
    NSRect inner = NSInsetRect(self.bounds, kTrackInset, kTrackInset);
    if (!NSEqualRects(_scroll.frame, inner)) _scroll.frame = inner;
    CGFloat width = inner.size.width, height = inner.size.height;
    NSUInteger count = _tabViews.count, pinned = std::min(_pinnedCount, count), regular = count - pinned;
    auto place = [](NSView *v, NSRect r) {
        if (!NSEqualRects(v.frame, r)) v.frame = r;
    };
    CGFloat x = 0;
    for (NSUInteger i = 0; i < pinned; i++) {
        place(_tabViews[i], NSMakeRect(x, 0, kPinnedTabWidth, height));
        x += kPinnedTabWidth + kTabGap;
    }
    if (regular) {
        CGFloat share = (width - x - (CGFloat)(regular - 1) * kTabGap) / (CGFloat)regular;
        CGFloat w = std::max(_shrinkToFit ? kTabShrunkMinWidth : kTabMinWidth, share);
        for (NSUInteger i = pinned; i < count; i++) {
            // Round each edge, not each width, so the last tab ends flush with the track.
            CGFloat left = round(x), right = round(x + w);
            place(_tabViews[i], NSMakeRect(left, 0, right - left, height));
            x += w + kTabGap;
        }
    }
    CGFloat contentWidth = count ? x - kTabGap : 0;
    place(_document, NSMakeRect(0, 0, std::max(width, contentWidth), height));
    [self updateSeparators];
}

/// One hairline in each gap, hidden beside the selected or hovered tab where a fill already
/// marks the edge.
- (void)updateSeparators {
    NSUInteger needed = _tabViews.count > 1 ? _tabViews.count - 1 : 0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    while (_separators.count < needed) {
        CALayer *l = [CALayer layer];
        l.backgroundColor = [self brook_cg:Palette.divider];
        l.contentsScale = self.window.backingScaleFactor ?: 2;
        [_document.layer addSublayer:l];
        [_separators addObject:l];
    }
    while (_separators.count > needed) {
        [_separators.lastObject removeFromSuperlayer];
        [_separators removeLastObject];
    }
    CGFloat h = 14, y = floor((kTabHeight - h) / 2);
    for (NSUInteger i = 0; i < needed; i++) {
        TopTabView *a = _tabViews[i], *b = _tabViews[i + 1];
        CALayer *l = _separators[i];
        l.frame = CGRectMake(NSMaxX(a.frame) + kTabGap / 2 - 0.5, y, 1, h);
        l.hidden = a.selected || b.selected || a.isHovering || b.isHovering;
    }
    [CATransaction commit];
}

// Drops: tabs move (among the pinned icons pins them); links open as new tabs.

- (Slot)slotAt:(CGFloat)x {
    NSUInteger count = _tabViews.count, pinned = std::min(_pinnedCount, count);
    for (NSUInteger i = 0; i < count; i++) {
        NSRect f = _tabViews[i].frame;
        if (x < NSMidX(f)) {
            BOOL isPinned = i < pinned;
            return {(bool)isPinned, (NSInteger)(isPinned ? i : i - pinned), NSMinX(f) - kTabGap / 2};
        }
        if (i + 1 == pinned && x < NSMaxX(f) + kTabGap) return {true, (NSInteger)pinned, NSMaxX(f) + kTabGap / 2};
    }
    CGFloat end = count ? NSMaxX(_tabViews.lastObject.frame) + kTabGap / 2 : 2;
    return {false, (NSInteger)(count - pinned), end};
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return [self draggingUpdated:info]; }

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
    BOOL isTab = [info.draggingPasteboard stringForType:BrookTabPasteboardType] != nil;
    if (!isTab && !DraggedURL(info)) return NSDragOperationNone;
    Slot slot = [self slotAt:[_document convertPoint:info.draggingLocation fromView:nil].x];
    ShowDropIndicator(_indicator, _document, NSMakeRect(slot.x - 1, 5, 2, kTabHeight - 10));
    return isTab ? NSDragOperationMove : NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)info { _indicator.hidden = YES; }
- (void)draggingEnded:(id<NSDraggingInfo>)info { _indicator.hidden = YES; }

- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    _indicator.hidden = YES;
    Slot slot = [self slotAt:[_document convertPoint:info.draggingLocation fromView:nil].x];
    BrowserState *state = BrowserState.shared;
    Space *space = state.currentSpace;
    TabLocation destination = slot.pinned ? TabLocation::pinnedIn(space) : TabLocation::tabsIn(space);
    if (BrowserTab *tab = DraggedTab(info)) {
        [state move:tab to:destination index:slot.index];
        return YES;
    }
    NSURL *url = DraggedURL(info);
    if (!url) return NO;
    BrowserTab *tab = [state openTabWithURL:url inSpace:nil select:YES];
    [state move:tab to:destination index:slot.index];
    return YES;
}

@end

// MARK: - Space switcher

static NSImage *SpaceDotImage(NSColor *color) {
    return [NSImage imageWithSize:NSMakeSize(12, 12) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1.5, 1.5)] fill];
        return YES;
    }];
}

/// The current space's colour and name at the start of the strip. Click for the list of spaces.
@interface SpaceChip : HoverControl
@property (weak) BrowserWindowController *browser;
- (void)showSpace:(Space *)space;
@end

@implementation SpaceChip {
    NSView *_dot;
    NSTextField *_label;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.cornerRadius = 8;
        self.toolTip = @"Spaces";
        _dot = [NSView new];
        _dot.wantsLayer = YES;
        _dot.layer.cornerRadius = 4.5;
        _label = [NSTextField labelWithString:@""];
        _label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        NSImageView *chevron = [NSImageView imageViewWithImage:
            [NSImage brook_symbol:@"chevron.down" size:8 weight:NSFontWeightBold] ?: [NSImage new]];
        chevron.contentTintColor = NSColor.tertiaryLabelColor;
        for (NSView *v in @[_dot, _label, chevron]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:v];
        }
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:26],
            [_dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
            [_dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_dot.widthAnchor constraintEqualToConstant:9],
            [_dot.heightAnchor constraintEqualToConstant:9],
            [_label.leadingAnchor constraintEqualToAnchor:_dot.trailingAnchor constant:6],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.widthAnchor constraintLessThanOrEqualToConstant:110],
            [chevron.leadingAnchor constraintEqualToAnchor:_label.trailingAnchor constant:5],
            [chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:0.5],
            [self.trailingAnchor constraintEqualToAnchor:chevron.trailingAnchor constant:8],
        ]];
        __weak SpaceChip *weakSelf = self;
        self.onClick = ^{
            SpaceChip *self_ = weakSelf;
            if (!self_) return;
            [[self_ spacesMenu] popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, -4) inView:self_];
        };
    }
    return self;
}

- (void)showSpace:(Space *)space {
    _dot.layer.backgroundColor = space.color.CGColor;
    _label.stringValue = space.name ?: @"";
}

- (NSMenu *)menuForEvent:(NSEvent *)event { return [self spacesMenu]; }

- (NSMenu *)spacesMenu {
    BrowserState *state = BrowserState.shared;
    BrowserWindowController *browser = self.browser;
    NSMenu *m = [NSMenu new];
    NSArray<Space *> *spaces = state.spaces;
    for (NSInteger i = 0; i < (NSInteger)spaces.count; i++) {
        Space *space = spaces[(NSUInteger)i];
        NSString *key = i < 9 ? [NSString stringWithFormat:@"%ld", (long)(i + 1)] : @"";
        ClosureMenuItem *item = [[ClosureMenuItem alloc] initWithTitle:space.name key:key
                                                             modifiers:NSEventModifierFlagControl
                                                               handler:^{ [BrowserState.shared switchToSpace:i]; }];
        [item brook_setVisibleImage:SpaceDotImage(space.color)];
        item.state = i == state.currentSpaceIndex ? NSControlStateValueOn : NSControlStateValueOff;
        [m addItem:item];
    }
    [m addItem:NSMenuItem.separatorItem];
    __weak BrowserWindowController *weakBrowser = browser;
    [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"New Space…" handler:^{ [weakBrowser promptNewSpace]; }]];
    NSMenu *current = [browser menuForSpace:state.currentSpace];
    if (current.numberOfItems) [m addItem:NSMenuItem.separatorItem];
    for (NSMenuItem *item in [current.itemArray copy]) {
        [current removeItem:item];
        [m addItem:item];
    }
    return m;
}

@end

// MARK: - Favorites

/// A favorite in the glass capsule: just its icon. Click to open, drag to reorder.
@interface FavoriteButton : HoverControl <NSDraggingSource>
- (instancetype)initWithTab:(BrowserTab *)tab;
@property (readonly) BrowserTab *tab;
@property (copy) NSMenu *(^menuProvider)(BrowserTab *tab);
- (void)refresh;
@end

@implementation FavoriteButton {
    NSImageView *_icon;
    NSPoint _dragStart;
    BOOL _hasDragStart;
}

- (instancetype)initWithTab:(BrowserTab *)tab {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, kFavoriteSize, kFavoriteSize)])) {
        _tab = tab;
        self.cornerRadius = kFavoriteSize / 2;
        _icon = [[NSImageView alloc] initWithFrame:NSMakeRect((kFavoriteSize - 16) / 2, (kFavoriteSize - 16) / 2, 16, 16)];
        _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        _icon.contentTintColor = NSColor.secondaryLabelColor;
        [self addSubview:_icon];
        [self refresh];
    }
    return self;
}

- (void)refresh {
    BrowserTab *tab = _tab;
    NSImage *icon = TabIcon(tab);
    if (_icon.image != icon) _icon.image = icon;
    _icon.alphaValue = tab.isLoaded ? 1 : 0.7;
    NSString *title = tab.displayTitle ?: @"";
    if (![self.toolTip isEqualToString:title]) {
        self.toolTip = title;
        self.accessibilityLabel = title;
    }
}

- (void)mouseDown:(NSEvent *)event {
    _dragStart = event.locationInWindow;
    _hasDragStart = YES;
    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_hasDragStart) return;
    NSPoint p = event.locationInWindow;
    if (hypot(p.x - _dragStart.x, p.y - _dragStart.y) <= kDragThreshold) return;
    _hasDragStart = NO;
    self.isPressed = NO;   // no click on mouse up
    BeginTabDrag(self, event, _tab, TabDragImage(self.bounds.size, _icon.image, nil, nil));
}

- (NSMenu *)menuForEvent:(NSEvent *)event { return self.menuProvider ? self.menuProvider(_tab) : nil; }

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return context == NSDraggingContextWithinApplication ? NSDragOperationMove : NSDragOperationCopy;
}

@end

/// Favorites as icons in a small liquid-glass capsule beside the address pill. It asks for room
/// for every icon but can be squeezed; whatever doesn't fit goes in a » menu at its end.
@interface FavoritesCapsule : NSView
@property (weak) BrowserWindowController *browser;
- (void)reloadFavorites:(NSArray<BrowserTab *> *)favorites selected:(BrowserTab *)selected;
- (void)updateSelection:(BrowserTab *)selected;
- (void)refresh:(BrowserTab *)tab;
@end

@implementation FavoritesCapsule {
    NSGlassEffectView *_glass;
    NSView *_row;
    NSArray<FavoriteButton *> *_items;
    NSMapTable<BrowserTab *, FavoriteButton *> *_byTab;
    IconButton *_overflow;
    NSUInteger _visibleCount;
    NSView *_indicator;
    __weak BrowserTab *_selected;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _items = @[];
        _byTab = [NSMapTable strongToStrongObjectsMapTable];
        _row = [NSView new];
        _glass = [NSGlassEffectView new];
        _glass.cornerRadius = kToolbarHeight / 2;
        _glass.contentView = _row;
        [self addSubview:_glass];
        __weak FavoritesCapsule *weakSelf = self;
        _overflow = [[IconButton alloc] initWithSymbol:@"chevron.right.2" size:10 tooltip:@"More Favorites"
                                             dimension:kFavoriteSize onClick:^{ [weakSelf showOverflow]; }];
        _overflow.cornerRadius = kFavoriteSize / 2;
        _overflow.translatesAutoresizingMaskIntoConstraints = YES;
        [_row addSubview:_overflow];
        _indicator = MakeDropIndicator();
        [self setContentCompressionResistancePriority:300 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self registerForDraggedTypes:@[BrookTabPasteboardType]];
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow { return YES; }

static CGFloat CapsuleWidth(NSUInteger icons) {
    return icons ? 2 * kFavoritePad + (CGFloat)icons * kFavoriteSize : 0;
}

- (NSSize)intrinsicContentSize { return NSMakeSize(CapsuleWidth(_items.count), kToolbarHeight); }

- (void)reloadFavorites:(NSArray<BrowserTab *> *)favorites selected:(BrowserTab *)selected {
    NSMapTable<BrowserTab *, FavoriteButton *> *old = _byTab;
    NSMapTable<BrowserTab *, FavoriteButton *> *next = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableArray<FavoriteButton *> *items = [NSMutableArray arrayWithCapacity:favorites.count];
    __weak FavoritesCapsule *weakSelf = self;
    for (BrowserTab *tab in favorites) {
        FavoriteButton *item = [old objectForKey:tab];
        if (item) {
            [old removeObjectForKey:tab];
            [item refresh];
        } else {
            item = [[FavoriteButton alloc] initWithTab:tab];
            item.onClick = ^{ [BrowserState.shared selectTab:tab]; };
            item.menuProvider = ^NSMenu *(BrowserTab *t) { return [weakSelf.browser menuForTab:t]; };
            [_row addSubview:item];
        }
        item.isHighlightedState = tab == selected;
        [next setObject:item forKey:tab];
        [items addObject:item];
    }
    for (FavoriteButton *item in old.objectEnumerator) [item removeFromSuperview];
    BOOL countChanged = items.count != _items.count;
    _items = items;
    _byTab = next;
    _selected = selected;
    if (countChanged) [self invalidateIntrinsicContentSize];
    self.needsLayout = YES;
}

- (void)updateSelection:(BrowserTab *)selected {
    BrowserTab *previous = _selected;
    if (previous == selected) return;
    if (previous) [_byTab objectForKey:previous].isHighlightedState = NO;
    _selected = selected;
    if (selected) [_byTab objectForKey:selected].isHighlightedState = YES;
}

- (void)refresh:(BrowserTab *)tab { [[_byTab objectForKey:tab] refresh]; }

- (void)layout {
    [super layout];
    NSSize size = self.bounds.size;
    NSUInteger count = _items.count;
    // As many icons as fit; if not all do, the last slot becomes the » button.
    NSUInteger slots = (NSUInteger)std::max<CGFloat>(0, floor((size.width - 2 * kFavoritePad) / kFavoriteSize));
    NSUInteger visible = slots >= count ? count : (slots > 0 ? slots - 1 : 0);
    BOOL overflow = visible < count;
    NSUInteger shown = visible + (overflow && slots > 0 ? 1 : 0);
    // The capsule hugs its icons and sits against the address pill (trailing edge).
    CGFloat w = CapsuleWidth(shown);
    NSRect glass = NSMakeRect(size.width - w, 0, w, size.height);
    if (!NSEqualRects(_glass.frame, glass)) _glass.frame = glass;
    _glass.hidden = shown == 0;
    CGFloat y = floor((size.height - kFavoriteSize) / 2);
    for (NSUInteger i = 0; i < count; i++) {
        FavoriteButton *item = _items[i];
        item.hidden = i >= visible;
        if (i < visible) [item setFrameOrigin:NSMakePoint(kFavoritePad + (CGFloat)i * kFavoriteSize, y)];
    }
    _overflow.hidden = !(overflow && slots > 0);
    [_overflow setFrameOrigin:NSMakePoint(kFavoritePad + (CGFloat)visible * kFavoriteSize, y)];
    _visibleCount = visible;
}

- (void)showOverflow {
    NSMenu *menu = [NSMenu new];
    for (NSUInteger i = _visibleCount; i < _items.count; i++) {
        BrowserTab *tab = _items[i].tab;
        ClosureMenuItem *item = [[ClosureMenuItem alloc] initWithTitle:tab.displayTitle ?: @""
                                                               handler:^{ [BrowserState.shared selectTab:tab]; }];
        NSImage *icon = [TabIcon(tab) copy];
        icon.size = NSMakeSize(16, 16);
        [item brook_setVisibleImage:icon];
        item.state = tab == _selected ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, -4) inView:_overflow];
}

/// Index to insert a dropped tab at, and the indicator's x (in this view).
- (NSInteger)dropIndexAt:(CGFloat)x indicatorX:(CGFloat *)indicatorX {
    CGFloat origin = NSMinX(_glass.frame);
    for (NSUInteger i = 0; i < _visibleCount; i++) {
        CGFloat left = origin + kFavoritePad + (CGFloat)i * kFavoriteSize;
        if (x < left + kFavoriteSize / 2) {
            *indicatorX = left;
            return (NSInteger)i;
        }
    }
    *indicatorX = origin + kFavoritePad + (CGFloat)_visibleCount * kFavoriteSize;
    return (NSInteger)_visibleCount;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return [self draggingUpdated:info]; }

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
    if (![info.draggingPasteboard stringForType:BrookTabPasteboardType]) return NSDragOperationNone;
    CGFloat ix = 0;
    [self dropIndexAt:[self convertPoint:info.draggingLocation fromView:nil].x indicatorX:&ix];
    ShowDropIndicator(_indicator, self, NSMakeRect(ix - 1, 8, 2, NSHeight(self.bounds) - 16));
    return NSDragOperationMove;
}

- (void)draggingExited:(id<NSDraggingInfo>)info { _indicator.hidden = YES; }
- (void)draggingEnded:(id<NSDraggingInfo>)info { _indicator.hidden = YES; }

- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    _indicator.hidden = YES;
    BrowserTab *tab = DraggedTab(info);
    if (!tab) return NO;
    CGFloat ix = 0;
    NSInteger index = [self dropIndexAt:[self convertPoint:info.draggingLocation fromView:nil].x indicatorX:&ix];
    [BrowserState.shared move:tab to:TabLocation::favorites() index:index];
    return YES;
}

@end

// MARK: - Top bar

@implementation TopBarView {
    NSView *_toolbar;
    NSLayoutConstraint *_titleRowTop;
    NSLayoutConstraint *_titleRowLeading;
    IconButton *_backButton;
    IconButton *_forwardButton;
    IconButton *_reloadButton;
    SpaceChip *_spaceChip;
    FavoritesCapsule *_favorites;
    NSGlassEffectView *_extensionsGlass;
    IconButton *_newTabButton;
    IconButton *_downloadsButton;
    IconButton *_fireButton;
    TabStripView *_strip;
    CGFloat _fontSize;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        __weak TopBarView *weakSelf = self;
        _toolbar = [NSView new];
        _backButton = [[IconButton alloc] initWithSymbol:@"arrow.left" tooltip:@"Back (⌘[)" onClick:^{
            [weakSelf.browser goBack];
        }];
        _forwardButton = [[IconButton alloc] initWithSymbol:@"arrow.right" tooltip:@"Forward (⌘])" onClick:^{
            [weakSelf.browser goForward];
        }];
        _reloadButton = [[IconButton alloc] initWithSymbol:@"arrow.clockwise" tooltip:@"Reload (⌘R)" onClick:^{
            [weakSelf.browser reloadOrStop];
        }];
        _spaceChip = [SpaceChip new];
        _favorites = [FavoritesCapsule new];
        _urlPill = [[URLPillView alloc] initWithExtensions:NO];
        _extensionsBar = [[ExtensionsBar alloc] initWithButtonSize:kFavoriteSize];
        _newTabButton = [[IconButton alloc] initWithSymbol:@"plus" tooltip:@"New Tab (⌘T)" onClick:^{
            [weakSelf.browser newTab];
        }];
        _downloadsButton = [[IconButton alloc] initWithSymbol:@"arrow.down.circle" tooltip:@"Downloads" onClick:^{
            TopBarView *self_ = weakSelf;
            if (self_) [self_.browser showDownloadsFromView:self_->_downloadsButton];
        }];
        _fireButton = [[IconButton alloc] initWithSymbol:@"flame" tooltip:@"Burn Tabs & Data (⇧⌘⌫)" onClick:^{
            [weakSelf.browser fire];
        }];
        _strip = [TabStripView new];
        _fontSize = Settings.tabFontSize;
        _strip.fontSize = _fontSize;
        [self build];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(downloadsChanged)
                                                   name:DownloadManagerDidChangeNotification object:nil];
        [self downloadsChanged];
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow { return YES; }

- (void)setBrowser:(BrowserWindowController *)browser {
    _browser = browser;
    _spaceChip.browser = browser;
    _favorites.browser = browser;
    _strip.browser = browser;
}

- (void)build {
    __weak TopBarView *weakSelf = self;
    // Row 1, beside the traffic lights: navigation, space | favorites, address, new tab | tools.
    _toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_toolbar];
    NSStackView *nav = [NSStackView stackViewWithViews:@[_backButton, _forwardButton, _reloadButton]];
    nav.spacing = 2;
    nav.translatesAutoresizingMaskIntoConstraints = NO;
    // Stack views drop hidden views from the layout, so Downloads takes no room until needed.
    NSStackView *tools = [NSStackView stackViewWithViews:@[_downloadsButton, _fireButton]];
    tools.spacing = 2;
    tools.translatesAutoresizingMaskIntoConstraints = NO;
    _downloadsButton.hidden = YES;
    _urlPill.translatesAutoresizingMaskIntoConstraints = NO;
    _urlPill.onClick = ^{ [weakSelf.browser showCommandBarEditing:YES]; };
    _urlPill.siteButton.onClick = ^{ [weakSelf.browser showSiteInfo]; };
    _favorites.translatesAutoresizingMaskIntoConstraints = NO;
    // Extensions in a glass capsule on the pill's right, mirroring favorites on its left.
    NSView *extensionsHolder = [NSView new];
    _extensionsBar.translatesAutoresizingMaskIntoConstraints = NO;
    [extensionsHolder addSubview:_extensionsBar];
    _extensionsGlass = [NSGlassEffectView new];
    _extensionsGlass.cornerRadius = kToolbarHeight / 2;
    _extensionsGlass.contentView = extensionsHolder;
    _extensionsGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [extensionsHolder brook_pinEdgesTo:_extensionsGlass];
    for (NSView *v in @[nav, _spaceChip, _favorites, _urlPill, _extensionsGlass, _newTabButton, tools]) [_toolbar addSubview:v];

    // Row 2: the tab track.
    _strip.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_strip];

    auto withPriority = [](NSLayoutConstraint *c, NSLayoutPriority p) {
        c.priority = p;
        return c;
    };
    _titleRowTop = [_toolbar.topAnchor constraintEqualToAnchor:self.topAnchor constant:8];
    _titleRowLeading = [_toolbar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:78];
    [NSLayoutConstraint activateConstraints:@[
        _titleRowTop, _titleRowLeading,
        [_toolbar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_toolbar.heightAnchor constraintEqualToConstant:kToolbarHeight],

        [nav.leadingAnchor constraintEqualToAnchor:_toolbar.leadingAnchor],
        [nav.centerYAnchor constraintEqualToAnchor:_toolbar.centerYAnchor],
        [_spaceChip.leadingAnchor constraintEqualToAnchor:nav.trailingAnchor constant:6],
        [_spaceChip.centerYAnchor constraintEqualToAnchor:_toolbar.centerYAnchor],

        // Favorites hug the pill's left; when space runs out the pill leaves the centre first,
        // then narrows, then favorites spill into their » menu.
        [_favorites.leadingAnchor constraintGreaterThanOrEqualToAnchor:_spaceChip.trailingAnchor constant:10],
        [_favorites.trailingAnchor constraintEqualToAnchor:_urlPill.leadingAnchor constant:-8],
        [_favorites.topAnchor constraintEqualToAnchor:_toolbar.topAnchor],
        [_favorites.bottomAnchor constraintEqualToAnchor:_toolbar.bottomAnchor],
        withPriority([_urlPill.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], 250),
        withPriority([_urlPill.widthAnchor constraintEqualToConstant:600], 260),
        [_urlPill.widthAnchor constraintGreaterThanOrEqualToConstant:220],
        [_urlPill.centerYAnchor constraintEqualToAnchor:_toolbar.centerYAnchor],
        [_extensionsGlass.leadingAnchor constraintEqualToAnchor:_urlPill.trailingAnchor constant:8],
        [_extensionsGlass.topAnchor constraintEqualToAnchor:_toolbar.topAnchor],
        [_extensionsGlass.bottomAnchor constraintEqualToAnchor:_toolbar.bottomAnchor],
        [_extensionsBar.leadingAnchor constraintEqualToAnchor:extensionsHolder.leadingAnchor constant:kFavoritePad],
        [_extensionsBar.trailingAnchor constraintEqualToAnchor:extensionsHolder.trailingAnchor constant:-kFavoritePad],
        [_extensionsBar.topAnchor constraintEqualToAnchor:extensionsHolder.topAnchor],
        [_extensionsBar.bottomAnchor constraintEqualToAnchor:extensionsHolder.bottomAnchor],
        [_newTabButton.leadingAnchor constraintEqualToAnchor:_extensionsGlass.trailingAnchor constant:4],
        [_newTabButton.centerYAnchor constraintEqualToAnchor:_toolbar.centerYAnchor],
        [tools.leadingAnchor constraintGreaterThanOrEqualToAnchor:_newTabButton.trailingAnchor constant:10],
        [tools.trailingAnchor constraintEqualToAnchor:_toolbar.trailingAnchor],
        [tools.centerYAnchor constraintEqualToAnchor:_toolbar.centerYAnchor],

        [_strip.topAnchor constraintEqualToAnchor:_toolbar.bottomAnchor constant:6],
        [_strip.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_strip.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_strip.heightAnchor constraintEqualToConstant:kTrackHeight],
        [_strip.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
    ]];
    [self applySettings];
}

// MARK: BrowserChrome

- (NSView *)titleRow { return _toolbar; }
- (CGFloat)titleRowHeight { return kToolbarHeight; }
- (NSLayoutConstraint *)titleRowTop { return _titleRowTop; }
- (NSLayoutConstraint *)titleRowLeading { return _titleRowLeading; }

- (void)applySettings {
    CGFloat font = Settings.tabFontSize;
    if (font != _fontSize) {
        _fontSize = font;
        _strip.fontSize = font;
    }
    _strip.shrinkToFit = Settings.topTabsShrink;
    [self reloadFavorites];
}

- (void)reloadFavorites {
    BrowserState *state = BrowserState.shared;
    BOOL show = Settings.showFavorites && state.favorites.count > 0;
    _favorites.hidden = !show;
    [_favorites reloadFavorites:show ? state.favorites : @[] selected:state.selectedTab];
}

- (void)reloadAll { [self reloadAllTransition:std::nullopt]; }

- (void)reloadAllWithSpaceTransition:(BOOL)forward { [self reloadAllTransition:std::optional<bool>(forward)]; }

- (void)reloadAllTransition:(std::optional<bool>)forward {
    BrowserState *state = BrowserState.shared;
    if (forward) {
        CATransition *t = [CATransition animation];
        t.type = kCATransitionPush;
        t.subtype = *forward ? kCATransitionFromRight : kCATransitionFromLeft;
        t.duration = 0.28;
        t.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_strip.layer addAnimation:t forKey:@"spaceSwitch"];
    }
    [_strip reloadSpace:state.currentSpace selected:state.selectedTab];
    [_spaceChip showSpace:state.currentSpace];
    [self reloadFavorites];
    [self updateChrome];
}

- (void)updateSelection {
    BrowserTab *selected = BrowserState.shared.selectedTab;
    [_strip updateSelection:selected];
    [_favorites updateSelection:selected];
    [self updateChrome];
}

- (void)tabChanged:(BrowserTab *)tab change:(TabChange)change {
    // Tabs show only these; URL, navigation and consent changes matter to the toolbar alone.
    if (change & (TabChangeTitle | TabChangeFavicon | TabChangeLoading | TabChangeLoaded)) {
        if (tab.isFavorite) [_favorites refresh:tab];
        else [_strip refresh:tab];
    }
    if (tab == BrowserState.shared.selectedTab) [self updateChrome];
}

- (void)updateChrome {
    BrowserTab *tab = BrowserState.shared.selectedTab;
    _backButton.enabled = tab.webView ? tab.webView.canGoBack : NO;
    _forwardButton.enabled = tab.webView ? tab.webView.canGoForward : NO;
    _reloadButton.enabled = tab != nil;
    BOOL loading = tab.isLoading == YES;
    [_reloadButton setSymbol:loading ? @"xmark" : @"arrow.clockwise"];
    _reloadButton.toolTip = loading ? @"Stop (⌘.)" : @"Reload (⌘R)";
    [_urlPill updateWithTab:tab];
    _extensionsBar.tab = tab;
}

- (void)downloadsChanged {
    DownloadManager *dm = DownloadManager.shared;
    _downloadsButton.hidden = dm.items.count == 0;
    [_downloadsButton setSymbol:dm.hasActive ? @"arrow.down.circle.dotted" : @"arrow.down.circle"];
    _downloadsButton.tint = dm.hasActive ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
}

@end
