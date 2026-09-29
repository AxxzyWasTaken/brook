#import "Brook.h"

#include <cmath>
#include <map>
#include <optional>

@interface BrowserWindow : NSWindow
@end

@implementation BrowserWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

/// Transparent strip at the window's sidebar edge that reveals the hidden sidebar on hover.
@interface EdgeHotZone : NSView
@property (copy) void (^onEnter)(void);
@end

@implementation EdgeHotZone {
    NSTrackingArea *_tracking;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    // Moved as well as Entered: the pointer may already be resting in the strip when the sidebar hides.
    NSTrackingArea *t = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow |
                     NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:t];
    _tracking = t;
}

- (void)mouseEntered:(NSEvent *)event {
    if (self.onEnter) self.onEnter();
}

- (void)mouseMoved:(NSEvent *)event {
    if (self.onEnter) self.onEnter();
}

- (NSView *)hitTest:(NSPoint)point { return nil; }

@end

/// Traffic lights drawn in the sidebar's corner while in full screen. macOS moves the real ones
/// into its own title bar at the screen's top-left, shown only on hover, which is nowhere near a
/// sidebar on the right.
@interface FullScreenLights : NSView
@end

@implementation FullScreenLights {
    NSTrackingArea *_tracking;
    BOOL _hovering;
    NSInteger _pressed;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) _pressed = -1;
    return self;
}

static const CGFloat kLightSize = 14, kLightSlot = 16, kLightStep = 23;

- (NSSize)intrinsicContentSize { return NSMakeSize(kLightStep * 2 + kLightSlot, kLightSlot); }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (!self.window) return;
    for (NSNotificationName n in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyChanged:) name:n object:self.window];
    }
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)keyChanged:(NSNotification *)note { self.needsDisplay = YES; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)mouseEntered:(NSEvent *)event { _hovering = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { _hovering = NO; self.needsDisplay = YES; }

/// 0 close, 1 minimize (disabled in full screen), 2 leave full screen; -1 for none.
- (NSInteger)lightAt:(NSPoint)p {
    for (NSInteger i = 0; i < 3; i++) {
        NSRect slot = NSMakeRect(i * kLightStep, 0, kLightSlot, kLightSlot);
        if (NSPointInRect(p, NSInsetRect(slot, -3, -3))) return i;
    }
    return -1;
}

- (void)mouseDown:(NSEvent *)event {
    _pressed = [self lightAt:[self convertPoint:event.locationInWindow fromView:nil]];
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent *)event {
    NSInteger hit = [self lightAt:[self convertPoint:event.locationInWindow fromView:nil]];
    NSInteger pressed = _pressed;
    _pressed = -1;
    self.needsDisplay = YES;
    if (hit != pressed) return;
    if (hit == 0) [self.window performClose:nil];
    if (hit == 2) [self.window toggleFullScreen:nil];
}

- (void)drawRect:(NSRect)dirtyRect {
    BOOL active = self.window.isKeyWindow || _hovering;
    NSColor *fills[3] = {
        [NSColor colorWithSRGBRed:1.0 green:0.373 blue:0.341 alpha:1],   // #FF5F57
        [NSColor colorWithSRGBRed:0.996 green:0.737 blue:0.180 alpha:1], // #FEBC2E
        [NSColor colorWithSRGBRed:0.157 green:0.784 blue:0.251 alpha:1], // #28C840
    };
    NSColor *idle = [NSColor.labelColor colorWithAlphaComponent:0.18];
    CGFloat inset = (kLightSlot - kLightSize) / 2;
    for (NSInteger i = 0; i < 3; i++) {
        NSRect r = NSMakeRect(i * kLightStep + inset, inset, kLightSize, kLightSize);
        BOOL enabled = i != 1;
        NSColor *fill = active && enabled ? fills[i] : idle;
        if (i == _pressed) fill = [fill blendedColorWithFraction:0.25 ofColor:NSColor.blackColor] ?: fill;
        [fill setFill];
        [[NSBezierPath bezierPathWithOvalInRect:r] fill];
        if (!_hovering || !enabled) continue;
        // Glyphs on hover, like the real buttons: × to close, inward arrows to leave full screen.
        [[NSColor colorWithWhite:0 alpha:0.55] set];
        NSPoint c = NSMakePoint(NSMidX(r), NSMidY(r));
        if (i == 0) {
            NSBezierPath *x = [NSBezierPath bezierPath];
            x.lineWidth = 1.3;
            x.lineCapStyle = NSLineCapStyleRound;
            CGFloat d = 3.2;
            [x moveToPoint:NSMakePoint(c.x - d, c.y - d)];
            [x lineToPoint:NSMakePoint(c.x + d, c.y + d)];
            [x moveToPoint:NSMakePoint(c.x - d, c.y + d)];
            [x lineToPoint:NSMakePoint(c.x + d, c.y - d)];
            [x stroke];
        } else {
            NSBezierPath *a = [NSBezierPath bezierPath];
            CGFloat g = 0.8, s = 4.2;
            [a moveToPoint:NSMakePoint(c.x - g, c.y + g)];
            [a lineToPoint:NSMakePoint(c.x - g - s, c.y + g)];
            [a lineToPoint:NSMakePoint(c.x - g, c.y + g + s)];
            [a closePath];
            [a moveToPoint:NSMakePoint(c.x + g, c.y - g)];
            [a lineToPoint:NSMakePoint(c.x + g + s, c.y - g)];
            [a lineToPoint:NSMakePoint(c.x + g, c.y - g - s)];
            [a closePath];
            [a fill];
        }
    }
}

@end

/// Drag handle between the sidebar and the page.
@interface ResizeHandle : NSView
@property (copy) void (^onBegin)(void);
@property (copy) void (^onDrag)(CGFloat dx);
@property (copy) void (^onEnd)(void);
@end

@implementation ResizeHandle
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor]; }
- (void)mouseDown:(NSEvent *)event {
    if (self.onBegin) self.onBegin();
}
- (void)mouseDragged:(NSEvent *)event {
    if (self.onDrag) self.onDrag(event.deltaX);
}
- (void)mouseUp:(NSEvent *)event {
    if (self.onEnd) self.onEnd();
}
@end

// MARK: - Downloads popover (declared here, implemented at the bottom)

@interface DownloadsViewController : NSViewController
@end

// MARK: - Window controller

namespace {
/// Where macOS put a traffic light: x, and distance from the top of the titlebar.
struct LightDefault {
    CGFloat x;
    CGFloat fromTop;
};
}  // namespace

@implementation BrowserWindowController {
    BrowserState *_state;
    NSVisualEffectView *_root;
    NSView *_tint;
    NSGlassEffectView *_sidebarGlass;
    ResizeHandle *_handle;
    /// Where the pointer has dragged the sidebar's edge to, which can pass the width it shows.
    CGFloat _dragWidth;
    /// The sidebar's width when the drag began: what it springs back to after the rail.
    CGFloat _dragStartWidth;
    BOOL _catchingUp;   // just out of the icon rail, the sidebar is still gliding to the pointer
    /// Icon rail: the address field that pops out beside the selected tab.
    NSGlassEffectView *_railAddress;
    NSTextField *_railAddressField;
    EdgeHotZone *_hotZone;
    FullScreenLights *_fullScreenLights;
    NSArray<NSLayoutConstraint *> *_fullScreenLightsPlacement;
    CommandBarController *_commandBar;
    /// Made the first time tabs go on top, in a glass panel like the sidebar's.
    TopBarView *_topBar;
    NSGlassEffectView *_topGlass;
    /// Whichever of the sidebar or top bar is showing. Only it hears about tab changes; the other
    /// catches up with -reloadAll when it comes back.
    id<BrowserChrome> _chrome;

    CGFloat _sidebarWidth;
    NSLayoutConstraint *_sidebarWidthConstraint;
    /// Distance from the sidebar's outer edge to the window edge; negative slides it off-screen.
    NSLayoutConstraint *_sidebarEdge;
    NSLayoutConstraint *_contentToSidebar;
    CGFloat _cardEdge;   // the constant last given to _contentToSidebar (see -placeCardAnimated:)
    NSLayoutConstraint *_contentToEdge;
    NSLayoutConstraint *_contentTop;
    NSArray<NSLayoutConstraint *> *_positional;
    BOOL _peeking;
    BOOL _autoHideSuspended;
    BOOL _trafficLightsPlacementQueued;
    id _peekMonitor;
    /// Bumped on every sidebar show/hide so a stale fade can't undo a newer one.
    NSUInteger _lightsGeneration;
    CGFloat _inset;
    BOOL _onRight;

    /// Where macOS put each traffic light (x, and distance from the top of the titlebar), captured
    /// before we first move them. AppKit resets them on titlebar relayout, so we re-derive from here.
    std::map<NSWindowButton, LightDefault> _lightDefaults;
}

- (instancetype)init {
    BrowserWindow *window = [[BrowserWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1320, 860)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
                            NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.movableByWindowBackground = YES;
    window.minSize = NSMakeSize(640, 420);
    window.releasedWhenClosed = NO;
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    // An empty unified toolbar makes the titlebar taller, which drops the traffic lights
    // down to where the sidebar's nav row can sit level with them.
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"BrookToolbar"];
    window.toolbar = toolbar;
    window.toolbarStyle = NSWindowToolbarStyleUnified;

    if ((self = [super initWithWindow:window])) {
        _state = BrowserState.shared;
        _root = [NSVisualEffectView new];
        _tint = [NSView new];
        _sidebarGlass = [NSGlassEffectView new];
        _sidebar = [SidebarView new];
        _content = [ContentAreaView new];
        _handle = [ResizeHandle new];
        _hotZone = [EdgeHotZone new];
        _fullScreenLights = [FullScreenLights new];
        _sidebarWidth = Settings.sidebarWidth;
        _positional = @[];
        // Older builds saved ⌘S separately from Settings → Layout → Hide sidebar; fold it in.
        if (Settings.sidebarHidden) {
            if (Settings.autoHide == ChromeAutoHideNever) Settings.autoHide = ChromeAutoHideAlways;
            Settings.sidebarHidden = NO;
        }
        _peeking = NO;
        _lightsGeneration = 0;
        _inset = Settings.pageMargin;
        _onRight = Settings.sidebarPosition == SidebarPositionRight;
        _tabsOnTop = _state.currentSpace.effectiveTabLayout != TabLayoutSidebar;
        _chrome = _sidebar;

        window.delegate = self;
        [self buildLayout];
        [window center];
        [window setFrameAutosaveName:@"BrookMainWindow"];
        _state.observer = self;
    }
    return self;
}

/// Created on first use.
- (CommandBarController *)commandBar {
    if (!_commandBar) _commandBar = [[CommandBarController alloc] initWithBrowser:self];
    return _commandBar;
}

// MARK: Layout

/// The icon-only rail's narrowest width; it grows so the traffic lights above the icons fit.
static const CGFloat kRailWidth = 72;

/// Dragging the sidebar narrower than this turns it into the icon rail.
static const CGFloat kSnapToRailWidth = 150;
/// How long the sidebar takes to slide into or out of the icon rail.
static const CFTimeInterval kSnapDuration = 0.18;
/// Each drag step's glide while the sidebar catches up with the pointer after leaving the rail.
static const CFTimeInterval kCatchUpDuration = 0.08;

/// Width of the strip at the window edge that reveals a hidden sidebar.
static const CGFloat kHotZoneWidth = 24;
/// Distance from the sidebar's leading edge to the full-screen traffic lights (matches the real ones).
static const CGFloat kFullScreenLightsInset = 10;
/// Closest the row beside the traffic lights comes to the top of the sidebar or top panel.
static const CGFloat kTitleRowMinTop = 4;

- (void)buildLayout {
    _root.material = NSVisualEffectMaterialUnderWindowBackground;
    _root.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _root.state = NSVisualEffectStateFollowsWindowActiveState;
    self.window.contentView = _root;
    [self keepTrafficLightsPlaced];

    _tint.wantsLayer = YES;
    _tint.translatesAutoresizingMaskIntoConstraints = NO;
    [_root addSubview:_tint];
    [_tint brook_pinEdgesTo:_root];

    _content.translatesAutoresizingMaskIntoConstraints = NO;
    [_root addSubview:_content];

    _sidebarGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [_root addSubview:_sidebarGlass];
    _sidebar.browser = self;
    [self applySidebarSurface];

    _handle.translatesAutoresizingMaskIntoConstraints = NO;
    __weak BrowserWindowController *weakSelf = self;
    _handle.onBegin = ^{
        BrowserWindowController *self_ = weakSelf;
        if (!self_) return;
        self_->_dragWidth = self_.effectiveSidebarWidth;
        self_->_dragStartWidth = self_->_sidebarWidth;
        self_->_catchingUp = NO;
    };
    _handle.onDrag = ^(CGFloat dx) {
        BrowserWindowController *self_ = weakSelf;
        if (!self_) return;
        CGFloat delta = self_->_onRight ? -dx : dx;
        self_->_dragWidth += delta;
        // Past the snap point the sidebar becomes the icon rail, and dragged back out it returns
        // to the width it had. Each snap restarts from the width now showing, so the edge has to
        // travel back past the snap point before it flips again.
        BOOL rail = Settings.sidebarIconsOnly;
        if (rail != (self_->_dragWidth < kSnapToRailWidth)) {
            // Passing the minimum width on the way in mustn't become the width to return to. Only
            // remembered: the snap slides on from the width showing, not from this one.
            if (!rail) self_->_sidebarWidth = self_->_dragStartWidth;
            self_->_catchingUp = rail;
            Settings.sidebarIconsOnly = !rail;   // slides to the new width (settingsChanged:)
            self_->_dragWidth = self_.effectiveSidebarWidth;
            return;
        }
        if (rail) return;
        self_->_sidebarWidth = std::min<CGFloat>(420, std::max<CGFloat>(190, self_->_dragWidth));
        [self_ setSidebarWidthFollowingSnap:self_->_sidebarWidth];
        // On the right the sidebar's left edge (and the traffic lights in it) moves with the width.
        if (self_->_onRight) {
            [self_->_root layoutSubtreeIfNeeded];
            [self_ alignNavRow];
        }
    };
    _handle.onEnd = ^{
        BrowserWindowController *self_ = weakSelf;
        if (!self_) return;
        self_->_catchingUp = NO;   // any glide still running finishes at the last width
        Settings.sidebarWidth = self_->_sidebarWidth;
    };
    [_root addSubview:_handle];

    _hotZone.translatesAutoresizingMaskIntoConstraints = NO;
    _hotZone.onEnter = ^{
        [weakSelf peekSidebar];
    };
    [_root addSubview:_hotZone];

    _fullScreenLights.translatesAutoresizingMaskIntoConstraints = NO;
    _fullScreenLights.hidden = YES;

    _sidebarWidthConstraint = [_sidebarGlass.widthAnchor constraintEqualToConstant:self.effectiveSidebarWidth];
    [NSLayoutConstraint activateConstraints:@[
        _sidebarWidthConstraint,
        [_handle.topAnchor constraintEqualToAnchor:_sidebarGlass.topAnchor],
        [_handle.bottomAnchor constraintEqualToAnchor:_sidebarGlass.bottomAnchor],
        [_hotZone.topAnchor constraintEqualToAnchor:_root.topAnchor],
        [_hotZone.bottomAnchor constraintEqualToAnchor:_root.bottomAnchor],
        // Wide enough to find without aiming; it only reacts while the sidebar is hidden.
        [_hotZone.widthAnchor constraintEqualToConstant:kHotZoneWidth],
    ]];
    [self applyTabLayout];
    [self applyAppearanceSettings];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(settingsChanged:)
                                               name:BrookSettingsDidChangeNotification
                                             object:nil];
    // Increase Contrast toggled: redraw so the palette re-resolves (a theme forced to Light or
    // Dark keeps the same appearance object, so AppKit wouldn't on its own).
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                       selector:@selector(displayOptionsChanged:)
                                                           name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                                         object:nil];
}

- (void)displayOptionsChanged:(NSNotification *)note {
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:self.window.contentView.superview ?: self.window.contentView];
    while (views.count) {
        NSView *v = views.lastObject;
        [views removeLastObject];
        [v viewDidChangeEffectiveAppearance];
        v.needsDisplay = YES;
        v.needsLayout = YES;
        [views addObjectsFromArray:v.subviews];
    }
    [self applyAppearanceSettings];
}

/// Shows the sidebar or the top bar, following Settings → Appearance → Tab layout.
- (void)applyTabLayout {
    TabLayout layout = _state.currentSpace.effectiveTabLayout;
    BOOL top = layout != TabLayoutSidebar;
    _topBar.compact = layout == TabLayoutCompact;
    if (top == _tabsOnTop && _positional.count) return;   // built, and nothing changed
    if (!top) [_commandBar dismiss];
    if (_peeking) [self endPeek];
    _tabsOnTop = top;
    if (top && !_topBar) {
        _topBar = [TopBarView new];
        _topBar.browser = self;
        _topBar.compact = layout == TabLayoutCompact;
        _topGlass = [NSGlassEffectView new];
        _topGlass.translatesAutoresizingMaskIntoConstraints = NO;
        _topGlass.contentView = _topBar;
        _topBar.translatesAutoresizingMaskIntoConstraints = NO;
        [_root addSubview:_topGlass positioned:NSWindowAbove relativeTo:_content];
        [_topBar brook_pinEdgesTo:_topGlass];
        [self applyAppearanceSettings];
    }
    [self applySidebarSurface];
    _topGlass.hidden = !top;
    _chrome = top ? _topBar : _sidebar;
    [self attachFullScreenLights];
    [self rebuildPositionalConstraints];
    [_chrome applySettings];
    [_chrome reloadAll];
    [self applySidebarVisibilityAnimated:NO];
}

/// Our full-screen traffic lights ride at the start of the row beside them, so they move with it.
- (void)attachFullScreenLights {
    NSView *host = (NSView *)_chrome;
    [NSLayoutConstraint deactivateConstraints:_fullScreenLightsPlacement ?: @[]];
    if (_fullScreenLights.superview != host) [host addSubview:_fullScreenLights];
    _fullScreenLightsPlacement = @[
        [_fullScreenLights.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:kFullScreenLightsInset],
        [_fullScreenLights.centerYAnchor constraintEqualToAnchor:_chrome.titleRow.centerYAnchor],
    ];
    [NSLayoutConstraint activateConstraints:_fullScreenLightsPlacement];
}

/// The sidebar sits in one sheet of glass; the icon rail brings its own pieces (-railSurfaces), so
/// it moves out onto the window, still in the sheet's place, and the sheet hides.
- (void)applySidebarSurface {
    BOOL pieces = Settings.sidebarIconsOnly;
    _sidebarGlass.hidden = _tabsOnTop || pieces;
    _sidebar.hidden = _tabsOnTop;
    // The glass puts its content view inside a container of its own, so ask the glass, not the
    // sidebar's superview, whether it's already there.
    BOOL inGlass = _sidebarGlass.contentView == _sidebar;
    if (pieces ? _sidebar.superview == _root : inGlass) return;
    if (pieces) {
        _sidebarGlass.contentView = nil;
        [_root addSubview:_sidebar positioned:NSWindowAbove relativeTo:_sidebarGlass];
    } else {
        [_sidebar removeFromSuperview];
        _sidebarGlass.contentView = _sidebar;
    }
    [_sidebar brook_pinEdgesTo:_sidebarGlass];
}

/// The sidebar's glass and the rail's pieces, styled alike.
- (NSArray<NSGlassEffectView *> *)sidebarSurfaces {
    return [@[_sidebarGlass] arrayByAddingObjectsFromArray:_sidebar.railSurfaces];
}

/// Constraints that depend on the tab layout, which side the sidebar is on and the page margin.
/// The sidebar keeps its place while tabs are on top, ready to come back.
- (void)rebuildPositionalConstraints {
    [NSLayoutConstraint deactivateConstraints:_positional];
    // These two are toggled separately from `positional`, so retire the old side's copies too.
    _contentToSidebar.active = NO;
    _contentToEdge.active = NO;
    CGFloat m = _inset;
    NSLayoutXAxisAnchor *lead = _root.leadingAnchor, *trail = _root.trailingAnchor;
    NSMutableArray<NSLayoutConstraint *> *positional = [NSMutableArray array];
    if (_onRight) {
        _sidebarEdge = [trail constraintEqualToAnchor:_sidebarGlass.trailingAnchor constant:m];
        _contentToSidebar = [_sidebarGlass.leadingAnchor constraintEqualToAnchor:_content.trailingAnchor constant:m];
        _cardEdge = m;
        _contentToEdge = [trail constraintEqualToAnchor:_content.trailingAnchor constant:m];
        [positional addObjectsFromArray:@[
            [_content.leadingAnchor constraintEqualToAnchor:lead constant:m],
            [_handle.trailingAnchor constraintEqualToAnchor:_sidebarGlass.leadingAnchor],
            [_hotZone.trailingAnchor constraintEqualToAnchor:trail],
        ]];
    } else {
        _sidebarEdge = [_sidebarGlass.leadingAnchor constraintEqualToAnchor:lead constant:m];
        _contentToSidebar = [_content.leadingAnchor constraintEqualToAnchor:_sidebarGlass.trailingAnchor constant:m];
        _cardEdge = m;
        _contentToEdge = [_content.leadingAnchor constraintEqualToAnchor:lead constant:m];
        [positional addObjectsFromArray:@[
            [_content.trailingAnchor constraintEqualToAnchor:trail constant:-m],
            [_handle.leadingAnchor constraintEqualToAnchor:_sidebarGlass.trailingAnchor],
            [_hotZone.leadingAnchor constraintEqualToAnchor:lead],
        ]];
    }
    if (_tabsOnTop) {
        // A floating panel across the top, spaced from the window and the page like the sidebar.
        _contentTop = [_content.topAnchor constraintEqualToAnchor:_topGlass.bottomAnchor constant:m];
        [positional addObjectsFromArray:@[
            [_topGlass.topAnchor constraintEqualToAnchor:_root.topAnchor constant:m],
            [_topGlass.leadingAnchor constraintEqualToAnchor:lead constant:m],
            [trail constraintEqualToAnchor:_topGlass.trailingAnchor constant:m],
        ]];
    } else {
        _contentTop = [_content.topAnchor constraintEqualToAnchor:_root.topAnchor constant:m];
    }
    [positional addObjectsFromArray:@[
        _sidebarEdge, _contentTop,
        [_sidebarGlass.topAnchor constraintEqualToAnchor:_root.topAnchor constant:m],
        [_sidebarGlass.bottomAnchor constraintEqualToAnchor:_root.bottomAnchor constant:-m],
        [_content.bottomAnchor constraintEqualToAnchor:_root.bottomAnchor constant:-m],
        [_handle.widthAnchor constraintEqualToConstant:std::max<CGFloat>(6, m)],
    ]];
    _positional = [positional copy];
    [NSLayoutConstraint activateConstraints:_positional];
    [self updateContentEdge];
}

/// The icon rail floats over the page card's edge instead of sitting beside it: the card starts
/// where the rail does, just as it would with no sidebar, and the page inside lays out clear of
/// the rail. Animated inside the snap's group, the card's edge and the page's inset move by
/// equal and opposite amounts, so the card slides under (or out from under) the rail while the
/// page itself only follows the rail's width.
- (void)placeCardAnimated:(BOOL)animated {
    BOOL underRail = !_tabsOnTop && !self.sidebarHidden && Settings.sidebarIconsOnly;
    CGFloat rail = self.railWidth;
    CGFloat edge = underRail ? -rail : _inset;
    CGFloat covered = underRail ? rail + _inset : 0;
    // The animator's constant reads back mid-slide, so compare against the target set last:
    // setting it again outright would cut a running slide short.
    if (edge != _cardEdge) {
        _cardEdge = edge;
        (animated ? _contentToSidebar.animator : _contentToSidebar).constant = edge;
    }
    [_content setCoveredInsets:NSEdgeInsetsMake(0, _onRight ? 0 : covered, 0, _onRight ? covered : 0) animated:animated];
}

/// The page meets the sidebar only while the sidebar is showing (peeking floats over the page).
- (void)updateContentEdge {
    BOOL besideSidebar = !_tabsOnTop && !self.sidebarHidden;
    [self placeCardAnimated:NO];
    // Switch off the old edge before switching on the new one: for a moment both would pin the
    // page, and AppKit settles that clash by dropping the sidebar's width constraint.
    NSLayoutConstraint *on = besideSidebar ? _contentToSidebar : _contentToEdge;
    NSLayoutConstraint *off = besideSidebar ? _contentToEdge : _contentToSidebar;
    off.active = NO;
    on.active = YES;
}

// MARK: Settings

- (void)settingsChanged:(NSNotification *)note {
    id rawKey = note.userInfo[@"key"];
    NSString *key = [rawKey isKindOfClass:NSString.class] ? rawKey : @"*";
    if ([@[@"*", @"tabLayout", @"spaces"] containsObject:key]) [self applyTabLayout];
    NSSet<NSString *> *layoutKeys = [NSSet setWithArray:@[@"*", @"sidebarPosition", @"pageMargin"]];
    if ([layoutKeys containsObject:key]) {
        BOOL right = Settings.sidebarPosition == SidebarPositionRight;
        CGFloat margin = Settings.pageMargin;
        if (right != _onRight || margin != _inset) {
            _onRight = right;
            _inset = margin;
            if (_peeking) [self endPeek];
            [self rebuildPositionalConstraints];
            [self applySidebarVisibilityAnimated:NO];
        }
    }
    // Only redo the work a key actually affects: Boost edits save on every keystroke.
    NSSet<NSString *> *appearanceKeys = [NSSet setWithArray:@[@"*", @"theme", @"cornerRadius", @"spaceTint", @"chromeMaterial",
                                                              @"chromeOpacity", @"accentSource", @"accentColor", @"spaces"]];
    NSSet<NSString *> *sidebarKeys = [NSSet setWithArray:@[@"*", @"showAddressBar", @"showFavorites", @"showBottomBar",
                                                           @"favoritesColumns", @"tabDensity", @"tabFontSize", @"topTabsShrink",
                                                           @"tabStyle", @"accentSource", @"accentColor", @"uiFont", @"closeButtons",
                                                           @"tabSubtitles", @"sidebarIconsOnly", @"loadingIndicator",
                                                           @"toolbarItems", @"addressDisplay", @"spaceTint", @"sidebarPosition",
                                                           @"pageMargin"]];
    if ([appearanceKeys containsObject:key]) [self applyAppearanceSettings];
    if ([sidebarKeys containsObject:key]) [_chrome applySettings];
    if ([@[@"*", @"cardShadow", @"accentSource", @"accentColor", @"loadingIndicator", @"linkPreview"] containsObject:key]) {
        [_content applySettings];
    }
    if ([@[@"*", @"sidebarIconsOnly", @"pageMargin", @"cornerRadius"] containsObject:key]) {
        [self endRailAddressEditing];
        [self applySidebarSurface];
        NSLayoutConstraint *width = _sidebarWidthConstraint;
        CGFloat target = self.effectiveSidebarWidth;
        // Animate the constant alone, so every frame is laid out from the live constraints. An
        // implicit animation of the laid-out frames would pin the page to the end frame it had
        // worked out, and a drag or window resize during it left the page short of its edge.
        CFTimeInterval duration = [key isEqual:@"sidebarIconsOnly"] ? kSnapDuration : 0;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = duration;
            ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            width.animator.constant = target;
            [self placeCardAnimated:YES];
        }];
    }
    if ([@[@"*", @"autoHide", @"sidebarIconsOnly"] containsObject:key]) {
        _autoHideSuspended = NO;
        if (_peeking) [self endPeek];
        [self applySidebarVisibilityAnimated:YES];
    }
    if ([@[@"*", @"pageSwipe"] containsObject:key]) {
        for (BrowserTab *tab in _state.allTabs) {
            tab.webView.allowsBackForwardNavigationGestures = Settings.pageSwipe == PageSwipeBackForward;
        }
    }
    // Traffic lights (and the row beside them) follow the layout, margin and corner radius.
    if ([@[@"*", @"tabLayout", @"sidebarPosition", @"pageMargin", @"cornerRadius", @"sidebarIconsOnly", @"spaces"]
            containsObject:key]) {
        [_root layoutSubtreeIfNeeded];
        [self alignNavRow];
    }
    if ([@[@"*", @"defaultZoom", @"siteSettings"] containsObject:key]) {
        for (BrowserTab *tab in _state.allTabs) {
            WKWebView *wv = tab.webView;
            if (!wv) continue;
            CGFloat z = [SiteSettings zoomForHost:BrookHost(wv.URL)];
            if (std::abs(wv.pageZoom - z) > 0.001) wv.pageZoom = z;
        }
    }
    // The shield in the address pill follows the ad blocking switches and an ad-blocking extension.
    if ([@[@"*", @"blockAds", @"siteSettings", @"contentBlocker"] containsObject:key]) [_chrome updateChrome];
}

/// Sets the sidebar's width during a drag. Coming out of the rail the sidebar is still sliding
/// behind the pointer: setting the width outright cut the slide short and jumped the edge to the
/// pointer, so until it has caught up it glides after it instead.
- (void)setSidebarWidthFollowingSnap:(CGFloat)width {
    NSLayoutConstraint *c = _sidebarWidthConstraint;
    // The animated constant is the width showing (AppKit steps it frame by frame).
    if (_catchingUp && std::abs(c.constant - width) < 2) _catchingUp = NO;
    if (!_catchingUp) {
        c.constant = width;
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = kCatchUpDuration;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        c.animator.constant = width;
    }];
}

- (CGFloat)effectiveSidebarWidth { return Settings.sidebarIconsOnly ? self.railWidth : _sidebarWidth; }

/// The icon rail sits under the traffic lights, so it's as wide as they are plus the same
/// padding either side that -placeTrafficLights gives them.
- (CGFloat)railWidth {
    NSButton *close = [self.window standardWindowButton:NSWindowCloseButton];
    NSButton *zoom = [self.window standardWindowButton:NSWindowZoomButton];
    if (!close || !zoom) return kRailWidth;
    // macOS's own spots, before -placeTrafficLights moves them (it records them the first time).
    auto closeIt = _lightDefaults.find(NSWindowCloseButton), zoomIt = _lightDefaults.find(NSWindowZoomButton);
    BOOL recorded = closeIt != _lightDefaults.end() && zoomIt != _lightDefaults.end();
    CGFloat closeX = recorded ? closeIt->second.x : NSMinX(close.frame);
    CGFloat zoomMaxX = (recorded ? zoomIt->second.x : NSMinX(zoom.frame)) + NSWidth(zoom.frame);
    CGFloat r = Settings.cornerRadius == 0 ? 0 : Settings.cornerRadius + 2;
    CGFloat pad = std::max<CGFloat>(closeX, _inset + std::max<CGFloat>(closeX - 8, r * 0.55)) - _inset;
    return std::max<CGFloat>(kRailWidth, std::ceil(zoomMaxX - closeX + pad * 2));
}

/// Sidebar/top bar surface: glass, clearer glass, or a solid colour at the chosen opacity.
- (void)applyChromeMaterial {
    ChromeMaterial material = Settings.chromeMaterial;
    NSColor *color = _state.currentSpace.color;
    CGFloat strength = Settings.tintStrength;
    NSColor *glassTint = nil;
    switch (material) {
        case ChromeMaterialClear: glassTint = [color colorWithAlphaComponent:0.06 * strength]; break;
        case ChromeMaterialSolid: {
            // A solid panel: the window background, lightly coloured by the space.
            NSColor *base = [NSColor.windowBackgroundColor blendedColorWithFraction:std::min<CGFloat>(0.25, 0.12 * strength)
                                                                             ofColor:color] ?: NSColor.windowBackgroundColor;
            glassTint = [base colorWithAlphaComponent:Settings.chromeOpacity];
            break;
        }
        default: glassTint = [color colorWithAlphaComponent:0.15 * strength]; break;
    }
    NSArray<NSGlassEffectView *> *surfaces = [self.sidebarSurfaces arrayByAddingObjectsFromArray:_topGlass ? @[_topGlass] : @[]];
    for (NSGlassEffectView *g in surfaces) g.tintColor = glassTint;
    if (@available(macOS 26.1, *)) {
        NSGlassEffectViewStyle style = material == ChromeMaterialClear ? NSGlassEffectViewStyleClear : NSGlassEffectViewStyleRegular;
        for (NSGlassEffectView *g in surfaces) g.style = style;
        // A hidden sidebar only shows peeking over the page, and clear glass let the page's own
        // text read through the tabs (no tint covers it). It peeks as regular glass instead.
        if (!_tabsOnTop && self.sidebarHidden)
            for (NSGlassEffectView *g in self.sidebarSurfaces) g.style = NSGlassEffectViewStyleRegular;
    }
}

- (void)applyAppearanceSettings {
    switch (_state.currentSpace.effectiveTheme) {
        case ThemeModeSystem: NSApp.appearance = nil; break;
        case ThemeModeLight: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; break;
        case ThemeModeDark: NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; break;
    }
    CGFloat r = Settings.cornerRadius;
    for (NSGlassEffectView *g in self.sidebarSurfaces) g.cornerRadius = r == 0 ? 0 : r + 2;
    [_sidebar railSurfacesDidChangeCornerRadius];
    _topGlass.cornerRadius = _sidebarGlass.cornerRadius;
    _content.cornerRadius = r;
    [self applySpaceColors];
}

- (void)windowDidResize:(NSNotification *)notification { [self alignNavRow]; }
// The empty toolbar only exists to size the titlebar for the traffic lights. In full screen
// macOS draws it as its own opaque strip above the content, so drop it there.
- (void)windowWillEnterFullScreen:(NSNotification *)notification { self.window.toolbar.visible = NO; }
- (void)windowDidFailToEnterFullScreen:(NSWindow *)window { window.toolbar.visible = YES; }
- (void)windowWillExitFullScreen:(NSNotification *)notification {
    self.window.toolbar.visible = YES;
    _fullScreenLights.hidden = YES;
}
- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    _fullScreenLights.hidden = NO;
    _autoHideSuspended = NO;
    if (Settings.autoHide == ChromeAutoHideFullScreen) [self applySidebarVisibilityAnimated:YES];
    [self alignNavRow];
}
- (void)windowDidExitFullScreen:(NSNotification *)notification {
    // AppKit re-applies the toolbar state it saved on entry after willExit, so set it again.
    self.window.toolbar.visible = YES;
    _fullScreenLights.hidden = YES;
    _autoHideSuspended = NO;
    [self.window.contentView layoutSubtreeIfNeeded];
    // AppKit also un-hides the traffic lights on exit; re-apply ours (hidden with the sidebar).
    [self applySidebarVisibilityAnimated:NO];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [ExtensionManager.shared.controller didFocusWindow:self];
}

/// Left edge of the sidebar (or top panel) at rest, in window coordinates. The traffic lights live
/// in its top-left corner on either side, like Arc, so the page never has to make room for them.
- (CGFloat)sidebarRestingMinX {
    return _onRight && !_tabsOnTop ? _root.bounds.size.width - _inset - self.effectiveSidebarWidth : _inset;
}

/// Moves the traffic lights into the sidebar's top-left corner however big the window margin
/// and corner radius are. Never closer to the corner than macOS's own position, which keeps
/// them clear of the rounded window corner at small margins.
- (void)placeTrafficLights {
    NSWindow *window = self.window;
    if (!window || (window.styleMask & NSWindowStyleMaskFullScreen)) return;
    const NSWindowButton types[] = {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton};
    // `types` and `buttons` line up because all three buttons are present (checked below).
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (NSWindowButton t : types) {
        NSButton *b = [window standardWindowButton:t];
        if (b) [buttons addObject:b];
    }
    if (buttons.count != 3) return;
    NSView *bar = buttons[0].superview;
    if (!bar) return;
    if (_lightDefaults.empty()) {
        for (NSUInteger i = 0; i < 3; i++) {
            NSButton *b = buttons[i];
            _lightDefaults[types[i]] = {NSMinX(b.frame), bar.bounds.size.height - NSMaxY(b.frame)};
        }
    }
    auto closeIt = _lightDefaults.find(NSWindowCloseButton);
    if (closeIt == _lightDefaults.end()) return;
    LightDefault close = closeIt->second;
    CGFloat r = _sidebarGlass.cornerRadius;
    CGFloat padX = std::max<CGFloat>(close.x - 8, r * 0.55);
    CGFloat padTop = std::max<CGFloat>(close.fromTop - 8, r * 0.55);
    CGFloat height = buttons[0].frame.size.height;
    // The top panel's corner is where a left sidebar's would be.
    // Only the left side keeps macOS's position as a floor; on the right it just follows the sidebar.
    CGFloat dx = _onRight && !_tabsOnTop ? self.sidebarRestingMinX + padX - close.x
                                         : std::max<CGFloat>(0, _inset + padX - close.x);
    // The row beside the lights can't come closer to the top than kTitleRowMinTop (-alignNavRow);
    // a taller row (the top panel's toolbar) brings the lights down so they stay level with it.
    CGFloat rowCentre = _inset + kTitleRowMinTop + _chrome.titleRowHeight / 2;
    CGFloat level = rowCentre - height / 2 - close.fromTop;
    // Stay inside the titlebar, or the buttons get clipped and stop taking clicks.
    CGFloat dy = std::min<CGFloat>(std::max<CGFloat>({0, _inset + padTop - close.fromTop, level}),
                                   bar.bounds.size.height - close.fromTop - height - 2);
    for (NSUInteger i = 0; i < 3; i++) {
        NSButton *b = buttons[i];
        auto it = _lightDefaults.find(types[i]);
        if (it == _lightDefaults.end()) continue;
        LightDefault d = it->second;
        NSPoint origin = NSMakePoint(d.x + dx, bar.bounds.size.height - d.fromTop - dy - b.frame.size.height);
        if (!NSEqualPoints(b.frame.origin, origin)) [b setFrameOrigin:origin];
    }
}

/// AppKit puts the traffic lights back at the window's top-left whenever it re-tiles the title
/// bar: showing or fading them, retitling the window, resizing. Put them back in the sidebar
/// each time, or they're left stranded away from a right-hand sidebar.
- (void)keepTrafficLightsPlaced {
    NSButton *close = [self.window standardWindowButton:NSWindowCloseButton];
    if (!close) return;
    close.postsFrameChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(trafficLightsMoved:)
                                               name:NSViewFrameDidChangeNotification
                                             object:close];
}

- (void)trafficLightsMoved:(NSNotification *)notification {
    // AppKit ignores moves made while it's still positioning them, so wait a turn. Coalesced:
    // one retile moves all three buttons, and placing them posts this again.
    if (_trafficLightsPlacementQueued) return;
    _trafficLightsPlacementQueued = YES;
    __weak BrowserWindowController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        BrowserWindowController *self_ = weakSelf;
        if (!self_) return;
        [self_ placeTrafficLights];
        self_->_trafficLightsPlacementQueued = NO;
    });
}

/// Lines the row beside the traffic lights (the sidebar's back/forward buttons, or the tab strip)
/// up with them, whatever size macOS makes them.
- (void)alignNavRow {
    NSWindow *window = self.window;
    if (!window) return;
    [self placeTrafficLights];
    id<BrowserChrome> chrome = _chrome;
    // Keep the row's spot beside the lights even while the sidebar is hidden, so it doesn't
    // jump sideways as the sidebar slides away or back.
    NSButton *zoom = [window standardWindowButton:NSWindowZoomButton];
    NSView *zoomSuper = zoom.superview;
    if (!zoom || !zoomSuper || (window.styleMask & NSWindowStyleMaskFullScreen)) {
        chrome.titleRowTop.constant = 8;
        // In full screen our own lights sit at the start of the row; leave room for them.
        chrome.titleRowLeading.constant = _fullScreenLights.isHidden
            ? 8
            : kFullScreenLightsInset + _fullScreenLights.intrinsicContentSize.width + 8;
        return;
    }
    // Measure against where the sidebar rests, not its current frame: while it slides in,
    // the frame is still off-screen and would push the row away.
    NSRect zoomRect = [zoomSuper convertRect:zoom.frame toView:nil];
    CGFloat chromeTop = _root.bounds.size.height - _inset;
    CGFloat top = chromeTop - NSMidY(zoomRect) - chrome.titleRowHeight / 2;
    CGFloat leading = NSMaxX(zoomRect) - self.sidebarRestingMinX + 8;
    chrome.titleRowTop.constant = std::max<CGFloat>(kTitleRowMinTop, top);
    chrome.titleRowLeading.constant = std::max<CGFloat>(8, leading);
}

// MARK: Showing

- (void)start {
    [self applySpaceColors];
    [_chrome reloadAll];
    [_content showTab:_state.selectedTab spaceName:_state.currentSpace.name];
    self.window.title = _state.selectedTab.displayTitle ?: @"Brook";
    [self showWindow:nil];
    [self alignNavRow];
    __weak BrowserWindowController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf alignNavRow];
    });
    [ExtensionManager.shared windowDidOpen:self];
    if (_state.selectedTab == nil) [self showCommandBarEditing:NO];
}

- (void)applySpaceColors {
    NSColor *color = _state.currentSpace.color;
    NSView *tint = _tint;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.3;
        ctx.allowsImplicitAnimation = YES;
        tint.layer.backgroundColor = [color colorWithAlphaComponent:0.33 * Settings.tintStrength].CGColor;
    }];
    [self applyChromeMaterial];
    _content.accentColor = color;
}

// MARK: BrowserStateObserver

- (void)browserStateDidChangeStructure {
    [_chrome reloadAll];
}

- (void)browserStateDidSelect:(BrowserTab *)tab previous:(BrowserTab *)previous {
    if (tab != previous) [self endRailAddressEditing];   // editing belongs to the tab it started in
    [_content showTab:tab spaceName:_state.currentSpace.name];
    [_chrome updateSelection];
    WKWebView *wv = tab.webView;
    if (wv && !self.commandBar.isVisible && ![self.window.firstResponder isKindOfClass:NSTextView.class]) {
        [self.window makeFirstResponder:wv];
    }
    self.window.title = tab.displayTitle ?: @"Brook";
}

- (void)browserStateTabDidChange:(BrowserTab *)tab change:(TabChange)change {
    [_chrome tabChanged:tab change:change];
    [_content tabChanged:tab change:change];
    if (tab == _state.selectedTab && (change & TabChangeTitle)) self.window.title = tab.displayTitle;
}

- (void)browserStateDidSwitchSpace:(BOOL)forward {
    [self applyCurrentSpace];
    [_chrome reloadAllWithSpaceTransition:forward];
    [_root layoutSubtreeIfNeeded];
    [self alignNavRow];
}

- (void)browserStateDidEditCurrentSpace {
    // Same refresh as a switch, but no slide: the tabs stay where they are.
    [self applyCurrentSpace];
    [_chrome reloadAll];
    [_root layoutSubtreeIfNeeded];
    [self alignNavRow];
}

- (void)applyCurrentSpace {
    // A space may bring its own theme and tab layout.
    [self applyTabLayout];
    [self applyAppearanceSettings];
    // Settings → Appearance → App icon "Space colour" follows the current space.
    if (Settings.appIcon == AppIconStyleSpace) [AppDelegate applyAppIcon];
}

// MARK: Sidebar

/// Settings → Layout → Hide sidebar: always (it peeks from the edge), or only in full screen.
- (BOOL)autoHidden {
    if (_autoHideSuspended) return NO;
    switch (Settings.autoHide) {
        case ChromeAutoHideAlways: return YES;
        case ChromeAutoHideFullScreen: return (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
        default: return NO;
    }
}

- (BOOL)sidebarHidden { return self.autoHidden; }

/// ⌘S flips Settings → Layout → Hide sidebar between Never and Always, so the menu and the
/// setting always agree. "In full screen" stays set: there ⌘S just shows or hides the sidebar
/// until you leave full screen.
- (void)toggleSidebar {
    if (_tabsOnTop) return;
    if (Settings.autoHide == ChromeAutoHideFullScreen && (self.window.styleMask & NSWindowStyleMaskFullScreen)) {
        _autoHideSuspended = !_autoHideSuspended;
        _peeking = NO;
        [self applySidebarVisibilityAnimated:YES];
        return;
    }
    // Applied by -settingsChanged: like a change made in Settings.
    Settings.autoHide = self.sidebarHidden ? ChromeAutoHideNever : ChromeAutoHideAlways;
}

- (void)applySidebarVisibilityAnimated:(BOOL)animated {
    BOOL hidden = _tabsOnTop || (self.sidebarHidden && !_peeking);
    // The traffic lights ride in the sidebar's corner, so they come and go with it. With tabs on
    // top they stay put.
    BOOL lightsHidden = !_tabsOnTop && self.sidebarHidden && !_peeking;
    NSMutableArray<NSButton *> *lightsM = [NSMutableArray array];
    for (NSWindowButton t : {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton}) {
        NSButton *b = [self.window standardWindowButton:t];
        if (b) [lightsM addObject:b];
    }
    NSArray<NSButton *> *lights = [lightsM copy];
    // Lights appear only once the sidebar has landed (fading in), and leave straight away
    // (fading out) as it slides off, so they never float over an empty corner.
    _lightsGeneration += 1;  // unsigned: wraps on overflow
    NSUInteger generation = _lightsGeneration;
    BOOL wasHidden = lights.firstObject ? lights.firstObject.isHidden : YES;
    __weak BrowserWindowController *weakSelf = self;
    if (lightsHidden) {
        if (animated && !wasHidden) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
                ctx.duration = 0.1;
                for (NSButton *b in lights) b.animator.alphaValue = 0;
            } completionHandler:^{
                BrowserWindowController *self_ = weakSelf;
                if (!self_ || self_->_lightsGeneration != generation) return;
                for (NSButton *b in lights) {
                    b.hidden = YES;
                    b.alphaValue = 1;
                }
            }];
        } else {
            for (NSButton *b in lights) {
                b.hidden = YES;
                b.alphaValue = 1;
            }
        }
    } else if (animated && wasHidden) {
        // Stay fully hidden (not just transparent) for the slide: AppKit redraws the buttons
        // on hover and key changes, which can flash them in early. Revealed on landing below.
        for (NSButton *b in lights) b.hidden = YES;
    } else {
        for (NSButton *b in lights) {
            b.hidden = NO;
            b.alphaValue = 1;
        }
    }
    [self updateContentEdge];
    _handle.hidden = _tabsOnTop || self.sidebarHidden;
    if (hidden) [self endRailAddressEditing];
    _hotZone.hidden = _tabsOnTop || !self.sidebarHidden || _peeking;
    [self applyChromeMaterial];   // a hidden sidebar peeks as regular glass, never clear
    if (_peeking) {
        NSShadow *s = [NSShadow new];
        s.shadowBlurRadius = 20;
        s.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.3];
        for (NSGlassEffectView *g in self.sidebarSurfaces) g.shadow = s;
    } else {
        for (NSGlassEffectView *g in self.sidebarSurfaces) g.shadow = nil;
    }
    CGFloat leading = hidden ? -(self.effectiveSidebarWidth + _inset * 2 + 24) : _inset;
    NSLayoutConstraint *sidebarEdge = _sidebarEdge;
    // Reduce Motion: the sidebar fades out where it is, or appears in place and fades in, instead
    // of sliding. In the icon rail the sidebar sits on the root, outside its (hidden) glass.
    BOOL fade = animated && BrookReduceMotion() && std::abs(sidebarEdge.constant - leading) > 0.5;
    NSView *fading = _sidebarGlass.contentView == _sidebar ? _sidebarGlass : _sidebar;
    fading.alphaValue = 1;   // an interrupted fade doesn't leave it faint
    if (fade && hidden) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.15;
            fading.animator.alphaValue = 0;
        } completionHandler:^{
            BrowserWindowController *self_ = weakSelf;
            if (!self_ || self_->_lightsGeneration != generation) return;
            fading.alphaValue = 1;
            sidebarEdge.constant = leading;
        }];
        [self alignNavRow];
        return;
    }
    if (fade) fading.alphaValue = 0;
    // Constant only, not implicit frame animation: see settingsChanged: for why.
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = animated && !fade ? 0.25 : 0;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        sidebarEdge.animator.constant = leading;
    } completionHandler:^{
        BrowserWindowController *self_ = weakSelf;
        if (fade) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
                ctx.duration = 0.2;
                fading.animator.alphaValue = 1;
            }];
        }
        if (!self_ || self_->_lightsGeneration != generation || lightsHidden) return;
        for (NSButton *b in lights) {
            if (b.isHidden) {
                b.alphaValue = 0;
                b.hidden = NO;
            }
        }
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = animated ? 0.15 : 0;
            for (NSButton *b in lights) b.animator.alphaValue = 1;
        }];
    }];
    [self alignNavRow];
}

- (void)peekSidebar {
    if (_tabsOnTop || !self.sidebarHidden || _peeking) return;
    _peeking = YES;
    [self applySidebarVisibilityAnimated:YES];
    __weak BrowserWindowController *weakSelf = self;
    _peekMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved | NSEventMaskLeftMouseDown
                                                         handler:^NSEvent *(NSEvent *event) {
        BrowserWindowController *self_ = weakSelf;
        if (!self_ || !self_->_peeking || event.window != self_.window) return event;
        NSPoint p = [self_->_root convertPoint:event.locationInWindow fromView:nil];
        NSRect glass = self_->_sidebarGlass.frame;
        BOOL away = self_->_onRight ? p.x < NSMinX(glass) - 24 : p.x > NSMaxX(glass) + 24;
        if (away && !self_.railAddressEditing) [self_ endPeek];
        return event;
    }];
    self.window.acceptsMouseMovedEvents = YES;
}

- (void)endPeek {
    _peeking = NO;
    if (_peekMonitor) {
        [NSEvent removeMonitor:_peekMonitor];
        _peekMonitor = nil;
    }
    [self applySidebarVisibilityAnimated:YES];
}

// MARK: Icon rail address

- (BOOL)railAddressEditing { return _railAddress && !_railAddress.isHidden; }

- (BOOL)beginRailAddressEditing {
    BrowserTab *tab = _state.selectedTab;
    if (_tabsOnTop || !Settings.sidebarIconsOnly || (self.sidebarHidden && !_peeking) || !tab) return NO;
    NSView *row = [_sidebar viewForSelectedTab];
    if (!row.window) return NO;
    if (!_railAddress) {
        NSTextField *f = [NSTextField new];
        f.bordered = NO;
        f.drawsBackground = NO;
        f.focusRingType = NSFocusRingTypeNone;
        f.font = BrookUIFont(13, NSFontWeightRegular);
        f.textColor = NSColor.labelColor;
        f.placeholderString = @"Search or enter address";
        f.lineBreakMode = NSLineBreakByTruncatingTail;
        f.cell.scrollable = YES;
        f.cell.wraps = NO;
        f.translatesAutoresizingMaskIntoConstraints = NO;
        NSView *holder = [NSView new];
        [holder addSubview:f];
        [NSLayoutConstraint activateConstraints:@[
            [f.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:12],
            [f.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-12],
            [f.centerYAnchor constraintEqualToAnchor:holder.centerYAnchor],
        ]];
        NSGlassEffectView *glass = [NSGlassEffectView new];
        glass.cornerRadius = 12;
        glass.contentView = holder;
        glass.hidden = YES;
        NSShadow *s = [NSShadow new];
        s.shadowBlurRadius = 16;
        s.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.25];
        glass.shadow = s;
        _railAddress = glass;
        _railAddressField = f;
    }
    // Over the page, beside the rail, level with the tab.
    [_root layoutSubtreeIfNeeded];
    NSRect rowRect = [row convertRect:row.bounds toView:_root];
    NSRect rail = _sidebarGlass.frame;
    // As wide as the suggestions list under it (which is never narrower than 560), so they line up.
    CGFloat h = 36, w = std::min<CGFloat>(560, NSWidth(_root.bounds) - NSWidth(rail) - 3 * _inset - 16);
    CGFloat x = _onRight ? NSMinX(rail) - 8 - w : NSMaxX(rail) + 8;
    CGFloat y = std::clamp<CGFloat>(NSMidY(rowRect) - h / 2, _inset, NSMaxY(_root.bounds) - _inset - h);
    _railAddress.frame = NSMakeRect(x, y, w, h);
    _railAddress.tintColor = _sidebarGlass.tintColor;
    [_root addSubview:_railAddress positioned:NSWindowAbove relativeTo:nil];   // over the page and the handle
    _railAddress.hidden = NO;
    _railAddressField.stringValue = tab.url.absoluteString ?: @"";
    __weak BrowserWindowController *weakSelf = self;
    [self.commandBar showAttachedToField:_railAddressField alignedWith:_railAddress below:_railAddress onEnd:^{
        BrowserWindowController *self_ = weakSelf;
        if (self_) self_->_railAddress.hidden = YES;
    }];
    return YES;
}

- (void)endRailAddressEditing {
    if (self.railAddressEditing && self.commandBar.isAttached) [self.commandBar dismiss];
    _railAddress.hidden = YES;
}

// MARK: Commands

- (void)showCommandBarEditing:(BOOL)editing {
    // Compact tabs edit the address in the selected tab itself (⌘L and clicks on the tab).
    if (editing && _tabsOnTop && _topBar.compact && [_topBar beginEditingAddress]) return;
    // The icon rail has no address bar: edit it in a field beside the selected tab instead.
    if (editing && [self beginRailAddressEditing]) return;
    [self.commandBar showEditingCurrent:editing && _state.selectedTab != nil];
}

/// ⌘T and the sidebar's New Tab row, following Settings → General → New tabs show.
- (void)newTab {
    switch (Settings.newTabPage) {
        case NewTabPageCommandBar:
            [self showCommandBarEditing:NO];
            break;
        case NewTabPageBlank:
            [_state openTabWithURL:nil inSpace:nil select:YES];
            [self showCommandBarEditing:YES];
            break;
        case NewTabPageCustom: {
            NSURL *url = [URLParser urlFromInput:Settings.newTabURL];
            if (url) {
                [_state openTabWithURL:url inSpace:nil select:YES];
            } else {
                [self showCommandBarEditing:NO];
            }
            break;
        }
    }
}

- (void)goBack { [_state.selectedTab.webView goBack]; }
- (void)goForward { [_state.selectedTab.webView goForward]; }

- (void)reloadOrStop {
    BrowserTab *tab = _state.selectedTab;
    if (!tab) return;
    if (tab.isLoading) [tab.webView stopLoading];
    else [tab reload];
}

- (void)fire {
    [Fire confirmAndBurnInWindow:self.window overlayHost:_root];
}

- (void)showToast:(NSString *)text {
    [_content.toast showText:text];
}

- (void)showError:(NSError *)error {
    NSAlert *alert = [NSAlert alertWithError:error];
    NSWindow *window = self.window;
    if (window) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}

- (void)showFind { [_content showFind]; }

- (void)copyURL {
    NSURL *url = _state.selectedTab.url;
    if (!url) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:url.absoluteString forType:NSPasteboardTypeString];
    [self showToast:@"Link copied"];
}

- (void)shareFromView:(NSView *)anchor {
    NSURL *url = _state.selectedTab.url;
    if (!url) return;
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:@[url]];
    [picker showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMinY];
}

- (void)toggleReader {
    WKWebView *wv = _state.selectedTab.webView;
    if (!wv) return;
    static NSString *source;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *file = [NSBundle.mainBundle URLForResource:@"reader" withExtension:@"js"];
        source = file ? [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] : nil;
    });
    if (!source) return;
    static WKContentWorld *world = [WKContentWorld worldWithName:@"BrookReader"];
    __weak BrowserWindowController *weakSelf = self;
    __weak BrowserTab *tab = _state.selectedTab;
    [wv evaluateJavaScript:source inFrame:nil inContentWorld:world completionHandler:^(id result, NSError *error) {
        if ([result isKindOfClass:NSString.class]) tab.readerOn = [result isEqual:@"on"];
        if ([result isEqual:@"none"]) [weakSelf showToast:@"No article found on this page"];
    }];
}

- (void)zoomBy:(CGFloat)delta { [self zoomWithDelta:delta]; }
- (void)resetZoom { [self zoomWithDelta:std::nullopt]; }

/// Zooms the page and remembers the level for the site, like Safari.
- (void)zoomWithDelta:(std::optional<CGFloat>)delta {
    WKWebView *wv = _state.selectedTab.webView;
    if (!wv) return;
    static const CGFloat levels[] = {0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3};
    CGFloat z;
    if (delta) {
        CGFloat current = wv.pageZoom;
        if (*delta > 0) {
            z = 3;
            for (CGFloat l : levels) {
                if (l > current + 0.001) { z = l; break; }
            }
        } else {
            z = 0.5;
            for (auto it = std::rbegin(levels); it != std::rend(levels); ++it) {
                if (*it < current - 0.001) { z = *it; break; }
            }
        }
    } else {
        z = Settings.defaultZoom;
    }
    wv.pageZoom = z;
    NSString *host = BrookHost(wv.URL);
    if (host) {
        [SiteSettings updateHost:host change:^(SiteOverride *o) {
            o.zoom = std::abs(z - Settings.defaultZoom) < 0.001 ? nil : @((double)z);
        }];
    }
    [self showToast:[NSString stringWithFormat:@"Zoom %ld%%", (long)std::round(z * 100)]];
}

// MARK: Site settings

/// Whether the address pill is on screen to anchor popovers to. The top bar always shows it.
- (BOOL)urlPillVisible {
    return _tabsOnTop || ((!self.sidebarHidden || _peeking) && Settings.showAddressBar);
}

/// Popovers from the pill open towards the page: below the top bar, or beside the sidebar.
- (NSRectEdge)pillPopoverEdge {
    if (_tabsOnTop) return NSRectEdgeMinY;
    return _onRight ? NSRectEdgeMinX : NSRectEdgeMaxX;
}

- (void)showSiteInfo { [self showSiteInfoFromView:nil]; }

/// from: the pill icon that was clicked (the popover points at it); nil uses the usual anchor.
- (void)showSiteInfoFromView:(NSView *)from {
    NSURL *url = _state.selectedTab.url;
    NSString *host = BrookHost(url);
    if (!url || !host) return;
    NSPopover *popover = [NSPopover new];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.contentViewController = [[SiteInfoViewController alloc] initWithHost:host
                                                                          secure:[url.scheme isEqualToString:@"https"]];
    NSView *anchor = from ?: (_tabsOnTop ? _topBar.siteInfoAnchor : _sidebar.siteInfoAnchor);
    NSRect anchorRect = anchor.bounds;
    // The ads shield hides when blocking is turned off for the site, and AppKit closes a popover
    // whose view hides. Point at the shield's place in the pill, so the popover stays open.
    if (from.superview) {
        anchorRect = [from convertRect:from.bounds toView:from.superview];
        anchor = from.superview;
    }
    BOOL rail = !_tabsOnTop && Settings.sidebarIconsOnly && (!self.sidebarHidden || _peeking);
    if ((self.urlPillVisible || rail) && anchor.window) {
        [popover showRelativeToRect:anchorRect ofView:anchor preferredEdge:self.pillPopoverEdge];
    } else {
        [popover showRelativeToRect:NSMakeRect(NSMidX(_content.bounds), NSMaxY(_content.bounds) - 4, 1, 1)
                             ofView:_content
                      preferredEdge:NSRectEdgeMinY];
    }
}

// MARK: Downloads

- (void)showDownloadsFromView:(NSView *)anchor {
    NSPopover *popover = [NSPopover new];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.contentViewController = [DownloadsViewController new];
    [popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
}

// MARK: Extensions

- (void)presentExtensionPopup:(WKWebExtensionAction *)action {
    NSPopover *popover = action.popupPopover;
    if (!popover) return;
    NSView *anchor = [_chrome.extensionsBar anchorForContext:action.webExtensionContext];
    WKWebView *wv = _content.webView;
    BOOL rail = !_tabsOnTop && Settings.sidebarIconsOnly && (!self.sidebarHidden || _peeking);
    if (!self.urlPillVisible && !rail && wv) {
        [popover showRelativeToRect:NSMakeRect(20, wv.bounds.size.height - 20, 1, 1) ofView:wv preferredEdge:NSRectEdgeMaxY];
    } else {
        [popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:self.pillPopoverEdge];
    }
}

- (void)promptChromeWebStore {
    NSWindow *window = self.window;
    if (!window) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Add a Chrome extension";
    alert.informativeText = @"Paste a Chrome Web Store link or extension ID. Tip: on the Chrome Web Store, Brook adds an “Add to Brook” button to each extension page.";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    field.placeholderString = @"https://chromewebstore.google.com/detail/…";
    alert.accessoryView = field;
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.window.initialFirstResponder = field;
    __weak BrowserWindowController *weakSelf = self;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSString *input = field.stringValue;
        [ExtensionManager.shared installFromChromeWebStore:input completion:^(NSError *error) {
            if (!error) {
                [weakSelf showToast:@"Extension added"];
            } else if (!ExtensionInstallErrorIsCancelled(error)) {
                [weakSelf showError:error];
            }
        }];
    }];
}

- (void)promptInstallFile {
    NSWindow *window = self.window;
    if (!window) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.allowedContentTypes = @[];
    panel.message = @"Choose an unpacked extension folder, a .crx, or a .zip";
    __weak BrowserWindowController *weakSelf = self;
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        NSURL *url = panel.URL;
        if (response != NSModalResponseOK || !url) return;
        [ExtensionManager.shared installFromURL:url chromeWebStoreID:nil completion:^(NSError *error) {
            if (!error) {
                [weakSelf showToast:@"Extension added"];
            } else if (!ExtensionInstallErrorIsCancelled(error)) {
                [weakSelf showError:error];
            }
        }];
    }];
}

// MARK: Context menus

- (NSMenu *)menuForTab:(BrowserTab *)tab {
    BrowserState *state = _state;
    NSMenu *m = [NSMenu new];
    [m addItem:[[ClosureMenuItem alloc] initWithTitle:tab.isPinned ? @"Unpin Tab" : @"Pin Tab" handler:^{
        [state togglePin:tab];
    }]];
    [m addItem:[[ClosureMenuItem alloc] initWithTitle:tab.isFavorite ? @"Remove from Favorites" : @"Add to Favorites"
                                              handler:^{ [state toggleFavorite:tab]; }]];
    [m addItem:[NSMenuItem separatorItem]];
    NSInteger middleStart = m.numberOfItems;
    // A new tab with no address has nothing to copy or duplicate.
    if (tab.url) {
        [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Copy Link" handler:^{
            NSURL *url = tab.url;
            if (!url) return;
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:url.absoluteString forType:NSPasteboardTypeString];
        }]];
        [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Duplicate Tab" handler:^{ [state duplicate:tab]; }]];
    }
    if (tab.isLoaded && tab != state.selectedTab) {
        [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Unload to Save Memory" handler:^{ [tab unload]; }]];
    }
    if (state.spaces.count > 1) {
        NSMenuItem *moveItem = [[NSMenuItem alloc] initWithTitle:@"Move to Space" action:nil keyEquivalent:@""];
        NSMenu *sub = [NSMenu new];
        Space *tabSpace = [state spaceOf:tab];
        for (Space *space in state.spaces) {
            if (space == tabSpace) continue;
            [sub addItem:[[ClosureMenuItem alloc] initWithTitle:space.name handler:^{
                // A pinned tab stays pinned in the new space (as a drag does), at the end like Pin Tab.
                if (tab.isPinned) {
                    [state move:tab to:TabLocation::pinnedIn(space) index:(NSInteger)space.pinned.count];
                } else {
                    [state move:tab to:TabLocation::tabsIn(space) index:0];
                }
            }]];
        }
        moveItem.submenu = sub;
        [m addItem:moveItem];
    }
    // Keep one separator when the middle group is empty.
    if (m.numberOfItems > middleStart) [m addItem:[NSMenuItem separatorItem]];
    if (tab.isPinned || tab.isFavorite) {
        [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Remove" handler:^{ [state remove:tab]; }]];
    } else {
        [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Close Tab" handler:^{ [state close:tab]; }]];
    }
    return m;
}

static NSImage *SpaceDotImage(NSColor *color) {
    return [NSImage imageWithSize:NSMakeSize(12, 12) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1.5, 1.5)] fill];
        return YES;
    }];
}

- (NSMenu *)spacesMenu {
    BrowserState *state = _state;
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
    __weak BrowserWindowController *weakSelf = self;
    [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"New Space…" handler:^{ [weakSelf promptNewSpace]; }]];
    NSMenu *current = [self menuForSpace:state.currentSpace];
    if (current.numberOfItems) [m addItem:NSMenuItem.separatorItem];
    for (NSMenuItem *item in [current.itemArray copy]) {
        [current removeItem:item];
        [m addItem:item];
    }
    return m;
}

- (NSMenu *)menuForSpace:(Space *)space {
    BrowserState *state = _state;
    __weak BrowserWindowController *weakSelf = self;
    NSMenu *m = [NSMenu new];
    [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Edit Space…" handler:^{
        [weakSelf promptEditSpace:space];
    }]];
    NSUInteger found = [state.spaces indexOfObjectIdenticalTo:space];
    if (found != NSNotFound) {
        NSInteger i = (NSInteger)found;
        if (i > 0) {
            [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Move Left" handler:^{
                [state moveSpaceFrom:i to:i - 1];
            }]];
        }
        if (i < (NSInteger)state.spaces.count - 1) {
            [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Move Right" handler:^{
                [state moveSpaceFrom:i to:i + 1];
            }]];
        }
    }
    if (state.spaces.count > 1) {
        [m addItem:[[ClosureMenuItem alloc] initWithTitle:@"Delete Space" handler:^{
            [weakSelf confirmDeleteSpace:space];
        }]];
    }
    return m;
}

// MARK: Spaces

- (void)promptNewSpace {
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (Space *s in _state.spaces) [used addObject:s.colorHex];
    NSString *color = Palette.spaceColors[0][1];
    for (NSArray<NSString *> *c in Palette.spaceColors) {
        if (![used containsObject:c[1]]) { color = c[1]; break; }
    }
    SpaceDraft draft = {@"", color, nil, false};
    __weak BrowserWindowController *weakSelf = self;
    [self showSpaceEditorWithTitle:@"New Space" draft:draft completion:^(SpaceDraft d) {
        BrowserWindowController *self_ = weakSelf;
        if (!self_) return;
        NSString *name = d.name.length == 0
            ? [NSString stringWithFormat:@"Space %ld", (long)self_->_state.spaces.count + 1]
            : d.name;
        [self_->_state addSpaceNamed:name colorHex:d.colorHex searchEngineID:d.searchEngineID
                     separateProfile:d.separateProfile];
    }];
}

- (void)promptEditSpace:(Space *)space {
    SpaceDraft draft = {space.name, space.colorHex, space.searchEngineID, space.profileID != nil};
    draft.theme = space.themeMode ? space.themeMode.integerValue : -1;
    draft.tabLayout = space.tabLayout ? space.tabLayout.integerValue : -1;
    draft.pinnedClose = space.pinnedClose ? space.pinnedClose.integerValue : -1;
    draft.archiveHours = space.archiveHours ? space.archiveHours.integerValue : -1;
    __weak BrowserWindowController *weakSelf = self;
    [self showSpaceEditorWithTitle:@"Edit Space" draft:draft completion:^(SpaceDraft d) {
        BrowserWindowController *self_ = weakSelf;
        if (!self_) return;
        auto number = [](NSInteger v) { return v < 0 ? nil : @(v); };
        space.themeMode = number(d.theme);
        space.tabLayout = number(d.tabLayout);
        space.pinnedClose = number(d.pinnedClose);
        space.archiveHours = number(d.archiveHours);
        [self_->_state updateSpace:space name:d.name.length == 0 ? space.name : d.name colorHex:d.colorHex
                    searchEngineID:d.searchEngineID separateProfile:d.separateProfile];
        // A changed theme or tab layout applies straight away.
        if (space == self_->_state.currentSpace) {
            [self_ applyTabLayout];
            [self_ applyAppearanceSettings];
            [self_->_root layoutSubtreeIfNeeded];
            [self_ alignNavRow];
        }
    }];
}

- (void)confirmDeleteSpace:(Space *)space {
    NSWindow *window = self.window;
    if (!window) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Delete “%@”?", space.name];
    alert.informativeText = @"Its tabs will be closed.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.buttons.firstObject.hasDestructiveAction = YES;
    __weak BrowserWindowController *weakSelf = self;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        BrowserWindowController *self_ = weakSelf;
        if (response == NSAlertFirstButtonReturn && self_) [self_->_state deleteSpace:space];
    }];
}

- (void)showSpaceEditorWithTitle:(NSString *)title draft:(SpaceDraft)draft completion:(void (^)(SpaceDraft))completion {
    NSWindow *window = self.window;
    if (!window) return;
    SpaceEditorView *editor = [[SpaceEditorView alloc] initWithDraft:draft];
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.accessoryView = editor;
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.window.initialFirstResponder = editor.nameField;
    BOOL hadProfile = draft.separateProfile;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        SpaceDraft result = editor.draft;
        if (hadProfile && !result.separateProfile) {
            // Turning a profile off deletes its cookies and logins; make sure that's intended.
            NSAlert *confirm = [NSAlert new];
            confirm.messageText = @"Stop using a separate profile?";
            confirm.informativeText = @"This space’s cookies, logins and site data will be deleted, and its tabs will use your main profile.";
            [confirm addButtonWithTitle:@"Delete Profile Data"];
            [confirm addButtonWithTitle:@"Cancel"];
            confirm.buttons.firstObject.hasDestructiveAction = YES;
            if ([confirm runModal] != NSAlertFirstButtonReturn) return;
        }
        completion(result);
    }];
}

// MARK: Window

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [_state saveNow];
    return YES;
}

@end

// MARK: - Downloads popover

/// One download: its name, then a progress bar, a Show in Finder button or "Failed". Kept for the
/// download's lifetime and updated in place, so VoiceOver and keyboard focus stay put while the
/// progress ticks.
@interface DownloadRowView : NSStackView
@property (readonly) DownloadItem *item;
- (instancetype)initWithItem:(DownloadItem *)item;
- (void)refresh;
@end

@implementation DownloadRowView {
    NSTextField *_name;
    NSProgressIndicator *_bar;
    NSButton *_reveal;
    NSTextField *_failed;
}

- (instancetype)initWithItem:(DownloadItem *)item {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _item = item;
        // The popover's 320 less its 14 insets, so the name and the bar use the full width.
        [self.widthAnchor constraintEqualToConstant:320 - 2 * 14].active = YES;
        _name = [NSTextField labelWithString:@""];
        _name.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _bar = [NSProgressIndicator new];
        _bar.indeterminate = NO;
        _bar.controlSize = NSControlSizeSmall;
        _reveal = [NSButton buttonWithTitle:@"Show in Finder" target:self action:@selector(revealInFinder)];
        _reveal.bezelStyle = NSBezelStyleInline;
        _reveal.controlSize = NSControlSizeSmall;
        _failed = [NSTextField labelWithString:@"Failed"];
        _failed.textColor = NSColor.systemRedColor;
        _failed.font = [NSFont systemFontOfSize:11];
        for (NSView *v in @[_name, _bar, _reveal, _failed]) [self addArrangedSubview:v];
        [_name.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
        [_bar.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
        self.orientation = NSUserInterfaceLayoutOrientationVertical;
        self.alignment = NSLayoutAttributeLeading;
        self.spacing = 4;
        self.detachesHiddenViews = YES;
        [self refresh];
    }
    return self;
}

- (void)refresh {
    DownloadItem *item = _item;
    if (![_name.stringValue isEqualToString:item.filename ?: @""]) _name.stringValue = item.filename ?: @"";
    DownloadStatus status = item.status;
    _bar.hidden = status != DownloadStatusActive;
    _reveal.hidden = status != DownloadStatusFinished;
    _failed.hidden = status != DownloadStatusFailed;
    if (status == DownloadStatusActive) _bar.doubleValue = item.fraction * 100;
}

- (void)revealInFinder {
    if (NSURL *dest = _item.destination) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[dest]];
}

@end

@implementation DownloadsViewController {
    NSStackView *_stack;
    NSTimer *_timer;
    NSTextField *_empty;
    NSButton *_clear;
    NSMapTable<DownloadItem *, DownloadRowView *> *_rows;
}

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        _stack = [NSStackView new];
        _rows = [NSMapTable strongToStrongObjectsMapTable];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_timer invalidate];
}

- (void)loadView {
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 60)];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeLeading;
    _stack.spacing = 10;
    _stack.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_stack];
    [_stack brook_pinEdgesTo:v];
    [v.widthAnchor constraintEqualToConstant:320].active = YES;
    _empty = [NSTextField labelWithString:@"No downloads"];
    _clear = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clear)];
    _clear.bezelStyle = NSBezelStyleInline;
    _clear.controlSize = NSControlSizeSmall;
    self.view = v;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync)
                                               name:DownloadManagerDidChangeNotification object:nil];
    [self sync];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    // Progress has no change notification; tick it while the popover is open.
    __weak DownloadsViewController *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshProgress];
    }];
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    [_timer invalidate];
    _timer = nil;
}

- (void)refreshProgress {
    for (DownloadRowView *row in _rows.objectEnumerator) {
        if (row.item.status == DownloadStatusActive) [row refresh];
    }
}

/// Matches the rows to the download list (newest first, up to 8), reusing each download's row.
- (void)sync {
    NSArray<DownloadItem *> *all = DownloadManager.shared.items;
    NSArray<DownloadItem *> *items = all.count > 8 ? [all subarrayWithRange:NSMakeRange(0, 8)] : all;
    NSMutableArray<NSView *> *wanted = [NSMutableArray array];
    NSMapTable<DownloadItem *, DownloadRowView *> *next = [NSMapTable strongToStrongObjectsMapTable];
    BOOL anyDone = NO;
    for (DownloadItem *item in all) {
        if (item.status != DownloadStatusActive) { anyDone = YES; break; }
    }
    for (DownloadItem *item in items) {
        DownloadRowView *row = [_rows objectForKey:item] ?: [[DownloadRowView alloc] initWithItem:item];
        [row refresh];
        [next setObject:row forKey:item];
        [wanted addObject:row];
    }
    _rows = next;
    if (items.count == 0) [wanted addObject:_empty];
    if (anyDone) [wanted addObject:_clear];
    if ([_stack.arrangedSubviews isEqualToArray:wanted]) return;
    // Only views that leave are removed; the rest are re-ordered where they stand.
    for (NSView *v in [_stack.arrangedSubviews copy]) {
        if (![wanted containsObject:v]) [v removeFromSuperview];
    }
    [wanted enumerateObjectsUsingBlock:^(NSView *v, NSUInteger i, BOOL *stop) {
        NSArray<NSView *> *current = self->_stack.arrangedSubviews;
        if (i < current.count && current[i] == v) return;
        if (v.superview == self->_stack) [self->_stack removeArrangedSubview:v];
        [self->_stack insertArrangedSubview:v atIndex:i];
    }];
}

- (void)clear {
    [DownloadManager.shared clearFinished];   // notifies, which syncs
}

@end
