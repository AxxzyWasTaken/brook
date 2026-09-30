#import "Brook.h"

// MARK: - Empty state

@interface EmptyStateView : NSView
@property (nonatomic, strong) NSColor *accent;
@property (nonatomic, copy) NSString *spaceName;
/// Re-reads the New Tab shortcut for the hint (Settings → Shortcuts).
- (void)updateHint;
@end

@implementation EmptyStateView {
    NSTextField *_title;
    NSTextField *_hint;
    NSButton *_importPasswords;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _title = [NSTextField labelWithString:@""];
        _hint = [NSTextField labelWithString:@""];
        [self updateHint];
        _accent = NSColor.controlAccentColor;
        _spaceName = @"";
        _title.font = [NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
        _title.textColor = NSColor.labelColor;
        // A long space name truncates inside the card, like the other one-line labels.
        _title.lineBreakMode = NSLineBreakByTruncatingTail;
        [_title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        _hint.font = [NSFont systemFontOfSize:14];
        _hint.textColor = NSColor.secondaryLabelColor;
        // A narrow page (a wide sidebar at the minimum window width) truncates the hint; it must not widen the window.
        _hint.lineBreakMode = NSLineBreakByTruncatingTail;
        [_hint setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        _importPasswords = [Controls button:@"Import Passwords…" action:^{ [SettingsWindowController.shared importPasswords]; }];
        _importPasswords.hidden = PasswordStore.shared.logins.count > 0;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateImport)
            name:PasswordStoreDidChangeNotification object:nil];
        NSStackView *stack = [NSStackView stackViewWithViews:@[_title, _hint, _importPasswords]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
            [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24]
        ]];
    }
    return self;
}

- (void)updateImport { _importPasswords.hidden = PasswordStore.shared.logins.count > 0; }

- (void)updateHint {
    NSString *shortcut = [AppDelegate shortcutDisplayForCommand:@"newTab:"];
    // A click on the card opens the command bar too (mouseDown:), so the hint still helps without a shortcut.
    _hint.stringValue = shortcut.length ? [NSString stringWithFormat:@"Press %@ to search or open a site", shortcut]
                                        : @"Click to search or open a site";
}

- (void)setAccent:(NSColor *)accent {
    _accent = accent;
    self.needsLayout = YES;
}

- (void)setSpaceName:(NSString *)spaceName {
    _spaceName = [spaceName copy];
    _title.stringValue = _spaceName;
}

- (void)mouseDown:(NSEvent *)event {
    id wc = self.window.windowController;
    if ([wc isKindOfClass:BrowserWindowController.class]) {
        [(BrowserWindowController *)wc showCommandBarEditing:NO];
    }
}

@end

// MARK: - Load error

@interface ErrorView : NSView
- (void)configureWithMessage:(NSString *)message url:(NSURL *)url onRetry:(void (^)(void))onRetry;
@end

@implementation ErrorView {
    NSTextField *_title;
    NSTextField *_detail;
    NSButton *_retry;
    void (^_onRetry)(void);
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _title = [NSTextField labelWithString:@"This page couldn’t load"];
        _detail = [NSTextField wrappingLabelWithString:@""];
        _retry = [NSButton buttonWithTitle:@"Try Again" target:nil action:nil];
        self.wantsLayer = YES;
        _title.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
        // Like the empty-state labels: a narrow page truncates the title, and the window keeps its width.
        _title.lineBreakMode = NSLineBreakByTruncatingTail;
        [_title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        _detail.font = [NSFont systemFontOfSize:13];
        _detail.textColor = NSColor.secondaryLabelColor;
        _detail.alignment = NSTextAlignmentCenter;
        // No fixed wrap width: the detail wraps to the room it has (at most 420), so a narrow window doesn't clip it.
        [_detail setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                          forOrientation:NSLayoutConstraintOrientationHorizontal];
        _retry.bezelStyle = NSBezelStyleGlass;
        _retry.controlSize = NSControlSizeLarge;
        _retry.target = self;
        _retry.action = @selector(retryTapped);
        NSImageView *icon = [NSImageView imageViewWithImage:
            [NSImage brook_symbol:@"wifi.exclamationmark" size:34 weight:NSFontWeightRegular] ?: [[NSImage alloc] init]];
        icon.contentTintColor = NSColor.tertiaryLabelColor;
        NSStackView *stack = [NSStackView stackViewWithViews:@[icon, _title, _detail, _retry]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.spacing = 10;
        [stack setCustomSpacing:18 afterView:_detail];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
            [stack.widthAnchor constraintLessThanOrEqualToConstant:440],
            [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24],
            [_detail.widthAnchor constraintLessThanOrEqualToConstant:420]
        ]];
    }
    return self;
}

- (void)layout {
    [super layout];
    self.layer.backgroundColor = [self brook_cg:NSColor.textBackgroundColor];
}

- (void)configureWithMessage:(NSString *)message url:(NSURL *)url onRetry:(void (^)(void))onRetry {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *s in @[[URLParser display:url] ?: @"", message ?: @""]) {
        if (s.length > 0) [parts addObject:s];
    }
    _detail.stringValue = [parts componentsJoinedByString:@"\n"];
    _onRetry = [onRetry copy];
}

- (void)retryTapped {
    if (_onRetry) _onRetry();
}

@end

// MARK: - Find in page

@implementation FindBar {
    NSGlassEffectView *_glass;
    NSSearchField *_field;
    NSTextField *_status;
    IconButton *_prev;
    IconButton *_next;
    IconButton *_done;

    /// Safari-style "3 of 12". WebKit's find API reports only found/not found, so the total is
    /// counted once per query in an isolated JS world and the index is tracked here.
    NSInteger _total;
    NSInteger _index;
    NSString *_countedQuery;
    dispatch_block_t _countWork;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _glass = [[NSGlassEffectView alloc] init];
        _field = [[NSSearchField alloc] init];
        _status = [NSTextField labelWithString:@""];
        _countedQuery = @"";
        __weak FindBar *weakSelf = self;
        _prev = [[IconButton alloc] initWithSymbol:@"chevron.up" size:11 tooltip:@"Previous (⇧⌘G)" dimension:24
                                           onClick:^{ [weakSelf searchForward:NO]; }];
        _next = [[IconButton alloc] initWithSymbol:@"chevron.down" size:11 tooltip:@"Next (⌘G)" dimension:24
                                           onClick:^{ [weakSelf searchForward:YES]; }];
        _done = [[IconButton alloc] initWithSymbol:@"xmark" size:11 tooltip:@"Done (esc)" dimension:24
                                           onClick:^{ [weakSelf close]; }];
        // Round, concentric with the capsule's ends (18 − 6 inset), like buttons in the top bar's capsules.
        for (IconButton *b in @[_prev, _next, _done]) b.cornerRadius = 12;

        _glass.cornerRadius = 18;
        _glass.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_glass];
        [_glass brook_pinEdgesTo:self];

        _field.placeholderString = @"Find on page";
        _field.delegate = self;
        _field.focusRingType = NSFocusRingTypeNone;
        _field.sendsSearchStringImmediately = YES;
        _field.target = self;
        _field.action = @selector(fieldChanged);
        _status.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
        _status.textColor = NSColor.secondaryLabelColor;
        _status.alignment = NSTextAlignmentRight;
        [_status setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        // Room for the longest usual status, so the bar (pinned at its right edge) keeps one width
        // and the field does not move while the user types.
        _status.stringValue = @"No matches";
        [_status.widthAnchor constraintGreaterThanOrEqualToConstant:ceil(_status.intrinsicContentSize.width)].active = YES;
        _status.stringValue = @"";
        NSStackView *stack = [NSStackView stackViewWithViews:@[_field, _status, _prev, _next, _done]];
        stack.spacing = 4;
        [stack setCustomSpacing:8 afterView:_status];
        stack.edgeInsets = NSEdgeInsetsMake(4, 6, 4, 6);
        // 200 wide, but narrower (to 100) in a narrow page so the bar keeps its left margin.
        NSLayoutConstraint *fieldWidth = [_field.widthAnchor constraintEqualToConstant:200];
        fieldWidth.priority = NSLayoutPriorityDragThatCannotResizeWindow - 10;
        fieldWidth.active = YES;
        [_field.widthAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;
        _glass.contentView = stack;
        [stack brook_pinEdgesTo:self];
        [self.heightAnchor constraintEqualToConstant:36].active = YES;
    }
    return self;
}

- (void)focus {
    [self.window makeFirstResponder:_field];
    [_field.currentEditor selectAll:nil];
}

- (void)close {
    self.hidden = YES;
    WKWebView *webView = self.webView;
    [webView evaluateJavaScript:@"window.getSelection().removeAllRanges()" inFrame:nil
                 inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
    if (webView) [self.window makeFirstResponder:webView];
}

/// The page changed underneath (navigation or tab switch): recount on the next search.
- (void)invalidateCount {
    _countedQuery = @"";
}

- (void)fieldChanged {
    [self searchForward:YES];
}

- (void)searchForward:(BOOL)forward {
    NSString *query = _field.stringValue;
    WKWebView *webView = self.webView;
    if (!webView || query.length == 0) {
        _total = 0; _index = 0; [self showStatus];
        return;
    }
    BOOL fresh = ![query isEqualToString:_countedQuery];
    WKFindConfiguration *config = [[WKFindConfiguration alloc] init];
    config.backwards = !forward;
    config.wraps = YES;
    config.caseSensitive = NO;
    __weak FindBar *weakSelf = self;
    [webView findString:query withConfiguration:config completionHandler:^(WKFindResult *result) {
        FindBar *self = weakSelf;
        if (!self || ![self->_field.stringValue isEqualToString:query]) return;
        if (!result.matchFound) {
            self->_total = 0; self->_index = 0; self->_countedQuery = query;
            [self showStatus];
            return;
        }
        if (fresh) {
            self->_index = 1;
            [self scheduleCount:query];
        } else if (self->_total > 0) {
            NSInteger total = self->_total, index = self->_index;
            self->_index = forward ? index % total + 1 : (index + total - 2) % total + 1;
        }
        [self showStatus];
    }];
}

/// Counting walks the page text, so wait for typing to pause.
- (void)scheduleCount:(NSString *)query {
    if (_countWork) dispatch_block_cancel(_countWork);
    __weak FindBar *weakSelf = self;
    dispatch_block_t work = dispatch_block_create((dispatch_block_flags_t)0, ^{
        FindBar *self = weakSelf;
        WKWebView *webView = self.webView;
        if (!self || !webView || ![self->_field.stringValue isEqualToString:query]) return;
        NSString *js =
            @"const q = needle.toLocaleLowerCase(), t = (document.body ? document.body.innerText : '').toLocaleLowerCase();\n"
            @"let n = 0, i = 0;\n"
            @"while (n < 10000 && (i = t.indexOf(q, i)) !== -1) { n++; i += q.length; }\n"
            @"return n;";
        [webView callAsyncJavaScript:js arguments:@{@"needle": query} inFrame:nil
                      inContentWorld:WKContentWorld.defaultClientWorld
                   completionHandler:^(id result, NSError *error) {
            FindBar *self = weakSelf;
            if (!self || ![self->_field.stringValue isEqualToString:query]) return;
            NSInteger n = (!error && [result isKindOfClass:NSNumber.class]) ? [(NSNumber *)result integerValue] : 0;
            self->_countedQuery = query;
            // innerText can miss text WebKit still finds (e.g. in form fields); never show "2 of 1".
            self->_total = std::max(n, self->_index);
            [self showStatus];
        }];
    });
    _countWork = work;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), work);
}

- (void)showStatus {
    NSString *text = _field.stringValue;
    if (text.length == 0) {
        _status.stringValue = @"";
    } else if (_total == 0 && [_countedQuery isEqualToString:text]) {
        _status.stringValue = @"No matches";
    } else if (_total == 0) {
        _status.stringValue = @"";
    } else {
        _status.stringValue = [NSString stringWithFormat:@"%ld of %ld", (long)_index, (long)_total];
    }
    _status.textColor = [_status.stringValue isEqualToString:@"No matches"] ? NSColor.systemRedColor
                                                                           : NSColor.secondaryLabelColor;
    _prev.enabled = _total != 0 || ![_countedQuery isEqualToString:text];
    _next.enabled = _prev.enabled;
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (selector == @selector(insertNewline:)) {
        BOOL shift = NSApp.currentEvent ? (NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift) != 0 : NO;
        [self searchForward:!shift];
        return YES;
    }
    if (selector == @selector(cancelOperation:)) {
        [self close];
        return YES;
    }
    return NO;
}

@end

// MARK: - Split View stage
// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), PaneStage.swift.

static const CGFloat kSplitGutter = 7;      // between the pages: room for the divider, off the left page's scroller
static const CGFloat kSplitNarrowest = 250; // narrower than this a page is no use: the focused one shows alone
static const CGFloat kSplitSnap = 15;       // how close to even the divider comes before it settles there
static const CGFloat kSplitUnsnap = 20;     // and how far past it the pointer goes before it lets go

@class PageHostView;

/// The line between two pages: a hairline in a narrow gutter that thickens under the pointer. Dragged, the
/// pages follow it; double-clicked, they even out; right-clicked, it offers what can be done with the pair.
@interface PaneDivider : NSView
@property (weak) PageHostView *host;
@end

/// A hairline round the page the keys go to, with two up. Takes no clicks.
@interface FocusCue : NSView
@end

@implementation FocusCue
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor.secondaryLabelColor colorWithAlphaComponent:0.55] setStroke];
    NSBezierPath *line = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 0.5, 0.5)];
    line.lineWidth = 1;
    [line stroke];
}
@end

/// Holds the page on screen, or two side by side. One view for both, never rebuilt, so moving from one page
/// to two (or back) moves web views, it doesn't reload them.
@interface PageHostView : NSView
/// One or two pages, left to right; `focused` indexes the one with the keys.
- (void)showPages:(NSArray<NSView *> *)pages focused:(NSInteger)focused fraction:(double)fraction;
@property (readonly) NSRect focusedFrame;
@property (readonly) BOOL paired;
@property (readonly) double share;
@property (copy) void (^onFocus)(NSInteger index);
@property (copy) void (^onFraction)(double fraction);
@property (copy) void (^onAction)(SEL action);
/// Laid out over the focused page: the hibernated picture under it, the error over it.
@property (weak) NSView *under;
@property (weak) NSView *over;
- (void)dividerBegan;
- (void)dividerMovedTo:(CGFloat)x;
- (void)dividerEnded;
@end

@implementation PageHostView {
    NSArray<NSView *> *_pages;
    NSInteger _focused;
    double _fraction;
    std::optional<double> _live;   // the left page's share while the divider is held
    BOOL _snapped;
    PaneDivider *_divider;
    FocusCue *_cue;
    id _monitor;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _pages = @[];
        _fraction = 0.5;
        _divider = [PaneDivider new];
        _divider.host = self;
        _divider.hidden = YES;
        [self addSubview:_divider];
        _cue = [FocusCue new];
        _cue.hidden = YES;
        [self addSubview:_cue];
    }
    return self;
}

- (void)dealloc { if (_monitor) [NSEvent removeMonitor:_monitor]; }

- (BOOL)isFlipped { return YES; }

- (double)share { return _live ? *_live : _fraction; }

- (BOOL)paired { return _pages.count == 2 && self.bounds.size.width - kSplitGutter >= 2 * kSplitNarrowest; }

- (void)showPages:(NSArray<NSView *> *)pages focused:(NSInteger)focused fraction:(double)fraction {
    for (NSView *v in self.subviews.copy) {
        if ([v isKindOfClass:WKWebView.class] && [pages indexOfObjectIdenticalTo:v] == NSNotFound) [v removeFromSuperview];
    }
    for (NSView *page in pages) {
        if (page.superview != self) {
            page.autoresizingMask = NSViewNotSizable;
            [self addSubview:page positioned:NSWindowBelow relativeTo:_divider];
        }
    }
    _pages = [pages copy];
    _focused = std::min<NSInteger>(std::max<NSInteger>(0, focused), (NSInteger)pages.count - 1);
    if (pages.count < 2) _live.reset();
    _fraction = fraction;
    [self watchClicks];
    self.needsLayout = YES;
    [self layoutSubtreeIfNeeded];
}

- (CGFloat)clampLeft:(CGFloat)left room:(CGFloat)room {
    return std::min(std::max(left, kSplitNarrowest), room - kSplitNarrowest);
}

- (NSRect)frameAt:(NSInteger)index {
    NSRect area = self.bounds;
    if (!self.paired) return index == _focused ? area : NSZeroRect;
    CGFloat room = area.size.width - kSplitGutter;
    CGFloat left = std::round([self clampLeft:room * (CGFloat)self.share room:room]);
    return index == 0 ? NSMakeRect(0, 0, left, area.size.height)
                      : NSMakeRect(left + kSplitGutter, 0, room - left, area.size.height);
}

- (NSRect)focusedFrame { return _pages.count ? [self frameAt:_focused] : self.bounds; }

- (void)layout {
    [super layout];
    BOOL paired = self.paired;
    for (NSInteger i = 0; i < (NSInteger)_pages.count; i++) {
        NSView *page = _pages[(NSUInteger)i];
        NSRect f = [self frameAt:i];
        // A window too narrow for two takes the other page off, and gives it back once there's room.
        page.hidden = NSIsEmptyRect(f);
        if (!page.hidden && !NSEqualRects(page.frame, f)) page.frame = f;
    }
    NSRect focused = self.focusedFrame;
    if (NSView *under = _under) under.frame = focused;
    if (NSView *over = _over; over && focused.size.width >= 100 && focused.size.height >= 100) over.frame = focused;
    if (paired) {
        NSRect left = [self frameAt:0];
        _divider.frame = NSMakeRect(NSMaxX(left), 0, kSplitGutter, self.bounds.size.height);
        _cue.frame = focused;
    }
    _divider.hidden = !paired;
    _cue.hidden = !paired;
    [_cue setNeedsDisplay:YES];
    [self.window invalidateCursorRectsForView:_divider];
}

// The divider, held.
- (void)dividerBegan {
    _live = _fraction;
    _snapped = std::abs(_fraction - 0.5) < 0.0001;
}

- (void)dividerMovedTo:(CGFloat)x {
    if (!_live) return;
    CGFloat room = self.bounds.size.width - kSplitGutter;
    if (room <= 0) return;
    CGFloat left = [self clampLeft:x - kSplitGutter / 2 room:room];
    CGFloat even = room / 2;
    if (_snapped) {
        if (std::abs(left - even) > kSplitUnsnap) _snapped = NO; else left = even;
    } else if (std::abs(left - even) <= kSplitSnap) {
        _snapped = YES;
        left = even;
        [NSHapticFeedbackManager.defaultPerformer performFeedbackPattern:NSHapticFeedbackPatternAlignment
                                                         performanceTime:NSHapticFeedbackPerformanceTimeNow];
    }
    double fraction = left / room;
    if (fraction == *_live) return;
    _live = fraction;
    // Now, not on the next pass: the pages keep up with the hand.
    self.needsLayout = YES;
    [self layoutSubtreeIfNeeded];
}

- (void)dividerEnded {
    if (!_live) return;
    double fraction = *_live;
    _live.reset();
    _fraction = fraction;
    self.needsLayout = YES;
    if (_onFraction) _onFraction(fraction);
}

// A click in the page without the keys gives them to it, and is still the page's click: watched, not taken.
- (void)watchClicks {
    BOOL wanted = _pages.count == 2 && self.window != nil;
    if (wanted && !_monitor) {
        __weak PageHostView *weakSelf = self;
        _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown |
                                                                 NSEventMaskOtherMouseDown
                                                         handler:^NSEvent *(NSEvent *event) {
            [weakSelf clicked:event];
            return event;
        }];
    } else if (!wanted && _monitor) {
        [NSEvent removeMonitor:_monitor];
        _monitor = nil;
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self watchClicks];
}

- (void)clicked:(NSEvent *)event {
    NSWindow *window = self.window;
    if (!window || event.window != window || !self.paired) return;
    NSView *hit = [window.contentView hitTest:[window.contentView.superview convertPoint:event.locationInWindow fromView:nil]];
    for (NSInteger i = 0; i < (NSInteger)_pages.count; i++) {
        NSView *page = _pages[(NSUInteger)i];
        // What's over the page (the find bar, a toast, a panel) isn't the page: a click there moves nothing.
        if (i == _focused || !hit || !(hit == page || [hit isDescendantOf:page])) continue;
        void (^focus)(NSInteger) = _onFocus;
        dispatch_async(dispatch_get_main_queue(), ^{ if (focus) focus(i); });
        return;
    }
}

- (void)act:(SEL)action { if (_onAction) _onAction(action); }

@end

@implementation PaneDivider {
    CALayer *_line;
    BOOL _hovering;
    BOOL _dragging;
    dispatch_block_t _dwell;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.wantsLayer = YES;
        _line = [CALayer layer];
        _line.actions = @{@"bounds": NSNull.null, @"position": NSNull.null};
        [self.layer addSublayer:_line];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self->_line.backgroundColor = (self->_hovering || self->_dragging ? NSColor.secondaryLabelColor
                                                                          : NSColor.quaternaryLabelColor).CGColor;
    }];
}

- (void)layout {
    [super layout];
    [self place];
}

- (void)place {
    CGFloat width = _hovering || _dragging ? 3 : 1;
    _line.frame = CGRectMake((self.bounds.size.width - width) / 2, 0, width, self.bounds.size.height);
    _line.cornerRadius = width / 2;
}

- (void)light:(BOOL)on {
    if (_hovering == on) return;
    _hovering = on;
    [CATransaction begin];
    [CATransaction setAnimationDuration:NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.14];
    [self place];
    [self updateLayer];
    [CATransaction commit];
}

- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor]; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in self.trackingAreas) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow |
                                                               NSTrackingInVisibleRect
                                                         owner:self userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)event {
    // A moment's rest first, so passing over it doesn't flicker.
    if (_dwell) dispatch_block_cancel(_dwell);
    __weak PaneDivider *weakSelf = self;
    _dwell = dispatch_block_create((dispatch_block_flags_t)0, ^{ [weakSelf light:YES]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), _dwell);
}

- (void)mouseExited:(NSEvent *)event {
    if (_dwell) dispatch_block_cancel(_dwell);
    if (!_dragging) [self light:NO];
}

- (void)mouseDown:(NSEvent *)event {
    PageHostView *host = _host;
    if (!host) return;
    if (event.clickCount == 2) { [host act:@selector(evenSplit:)]; return; }
    _dragging = YES;
    if (_dwell) dispatch_block_cancel(_dwell);
    [self light:YES];
    [host dividerBegan];
}

- (void)mouseDragged:(NSEvent *)event {
    PageHostView *host = _host;
    if (!_dragging || !host) return;
    [NSCursor.resizeLeftRightCursor set];
    [host dividerMovedTo:[host convertPoint:event.locationInWindow fromView:nil].x];
}

- (void)mouseUp:(NSEvent *)event {
    if (!_dragging) return;
    _dragging = NO;
    [_host dividerEnded];
    BOOL inside = NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
    _hovering = !inside;
    [self light:inside];
}

/// What can be done with the pair, from the page area itself (the tabs may be hidden).
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [NSMenu new];
    for (NSArray *entry in @[@[@"Swap Pages", @"swapSplit:"], @[@"Even Out", @"evenSplit:"], @[@""],
                             @[@"Separate Pages", @"separateSplit:"], @[@"Close Both Pages", @"closeSplit:"]]) {
        if (entry.count == 1) { [menu addItem:NSMenuItem.separatorItem]; continue; }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[0] action:@selector(chose:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = entry[1];
        [menu addItem:item];
    }
    return menu;
}

- (void)chose:(NSMenuItem *)item { [_host act:NSSelectorFromString(item.representedObject)]; }

// VoiceOver: a splitter with the left page's share, stepped 5% at a time.
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilitySplitterRole; }
- (NSString *)accessibilityLabel { return @"Divider between the pages"; }
- (id)accessibilityValue { return @(std::lround((_host ? _host.share : 0.5) * 100)); }
- (BOOL)accessibilityPerformIncrement { return [self step:0.05]; }
- (BOOL)accessibilityPerformDecrement { return [self step:-0.05]; }
- (BOOL)step:(double)by {
    PageHostView *host = _host;
    if (!host || !host.onFraction) return NO;
    host.onFraction(std::min(0.8, std::max(0.2, host.share + by)));
    return YES;
}

@end

// MARK: - Content area

/// The card's background extension, flipped like the web view inside it: unflipped, it fills the
/// strip under the rail with the page upside down (the page's header showed at the rail's foot).
@interface PageExtensionView : NSBackgroundExtensionView
@end

@implementation PageExtensionView
- (BOOL)isFlipped { return YES; }
@end

/// The card's shadow on its own: an empty layer that only casts it, along the card's outline.
@interface CardShadowView : NSView
@property (nonatomic) CGFloat cornerRadius;
@end

@implementation CardShadowView
- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.wantsLayer = YES;
        self.layer.shadowColor = NSColor.blackColor.CGColor;
    }
    return self;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.needsLayout = YES;
}
- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat r = std::min({_cornerRadius, b.size.width / 2, b.size.height / 2});
    CGPathRef path = CGPathCreateWithRoundedRect(b, r, r, NULL);
    self.layer.shadowPath = path;
    CGPathRelease(path);
}
@end

@implementation ContentAreaView {
    NSView *_clip;
    CardShadowView *_shadowView;
    CAGradientLayer *_glassShade;
    BOOL _glassShadeOn;
    BOOL _glassShadeOnRight;
    CGFloat _glassShadeGap;
    CALayer *_progress;
    EmptyStateView *_empty;
    ErrorView *_errorView;
    __weak BrowserTab *_tab;
    float _shadowStrength;
    double _lastProgress;
    NSView *_linkBox;
    NSTextField *_linkLabel;
    NSLayoutConstraint *_linkLeading;
    NSLayoutConstraint *_linkTrailing;
    // The part of the card not under the browser's glass (see coveredInsets). The page sits in
    // it, inside `_extension`, which fills the covered strip with the page's own edge.
    NSLayoutGuide *_uncovered;
    NSBackgroundExtensionView *_extension;
    PageHostView *_pageHost;
    __weak BrowserTab *_partner;   // the page beside _tab, in Split View
    NSImageView *_wakeCover;   // a hibernated tab's picture, under its web view until the page draws
    NSLayoutConstraint *_uncoveredLeading;
    NSLayoutConstraint *_uncoveredTrailing;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _clip = [[NSView alloc] init];
        _progress = [CALayer layer];
        _empty = [[EmptyStateView alloc] initWithFrame:NSZeroRect];
        _errorView = [[ErrorView alloc] initWithFrame:NSZeroRect];
        _findBar = [[FindBar alloc] initWithFrame:NSZeroRect];
        _toast = [[ToastView alloc] initWithFrame:NSZeroRect];
        _accentColor = NSColor.controlAccentColor;
        _cornerRadius = 12;
        _shadowStrength = 0.14f;
        _lastProgress = 0;

        self.wantsLayer = YES;
        _shadowView = [CardShadowView new];
        _shadowView.translatesAutoresizingMaskIntoConstraints = NO;

        _clip.wantsLayer = YES;
        _clip.layer.cornerRadius = 12;
        _clip.layer.cornerCurve = kCACornerCurveContinuous;
        _clip.layer.masksToBounds = YES;
        _clip.layer.borderWidth = 0.5;
        [self addSubview:_clip];
        [_clip brook_pinEdgesTo:self];

        _uncovered = [NSLayoutGuide new];
        [_clip addLayoutGuide:_uncovered];
        _uncoveredLeading = [_uncovered.leadingAnchor constraintEqualToAnchor:_clip.leadingAnchor];
        _uncoveredTrailing = [_clip.trailingAnchor constraintEqualToAnchor:_uncovered.trailingAnchor];
        [NSLayoutConstraint activateConstraints:@[
            _uncoveredLeading, _uncoveredTrailing,
            [_uncovered.topAnchor constraintEqualToAnchor:_clip.topAnchor],
            [_uncovered.bottomAnchor constraintEqualToAnchor:_clip.bottomAnchor],
        ]];

        _pageHost = [PageHostView new];
        _pageHost.translatesAutoresizingMaskIntoConstraints = NO;
        _pageHost.onFocus = ^(NSInteger index) {
            TabSplit *pair = BrowserState.shared.activeSplit;
            if (BrowserTab *tab = index == 0 ? pair.left : pair.right) [BrowserState.shared selectTab:tab];
        };
        _pageHost.onFraction = ^(double fraction) { [BrowserState.shared setSplitFraction:fraction]; };
        _pageHost.onAction = ^(SEL action) { [NSApp sendAction:action to:nil from:nil]; };
        _extension = [PageExtensionView new];
        _extension.translatesAutoresizingMaskIntoConstraints = NO;
        _extension.automaticallyPlacesContentView = NO;
        _extension.contentView = _pageHost;
        [_clip addSubview:_extension];
        [_extension brook_pinEdgesTo:_clip];
        [self pin:_pageHost toGuide:_uncovered];

        _wakeCover = [NSImageView new];
        _wakeCover.imageScaling = NSImageScaleAxesIndependently;
        _wakeCover.hidden = YES;
        [_pageHost addSubview:_wakeCover positioned:NSWindowBelow relativeTo:nil];
        _pageHost.under = _wakeCover;

        _empty.translatesAutoresizingMaskIntoConstraints = NO;
        [_clip addSubview:_empty];
        [self pin:_empty toGuide:_uncovered];

        // Over the page it's about: with two up, only that page. Placed by frame (see PageHostView layout); never
        // zero-sized, or its own margins can't be met.
        _errorView.hidden = YES;
        _errorView.translatesAutoresizingMaskIntoConstraints = YES;
        _errorView.frame = NSMakeRect(0, 0, 800, 600);
        [_pageHost addSubview:_errorView];
        _pageHost.over = _errorView;

        _progress.backgroundColor = _accentColor.CGColor;
        _progress.opacity = 0;
        _progress.anchorPoint = CGPointZero;
        // Web views are added as subviews later; their layers would otherwise cover the bar.
        _progress.zPosition = 100;
        [_clip.layer addSublayer:_progress];

        _findBar.hidden = YES;
        _findBar.translatesAutoresizingMaskIntoConstraints = NO;
        [_clip addSubview:_findBar];
        _toast.translatesAutoresizingMaskIntoConstraints = NO;
        [_clip addSubview:_toast];
        // The same 12 pt margin on the left while the page is wide enough for the narrowest bar.
        // Below NSLayoutPriorityWindowSizeStayPut, so the bar never widens the window.
        NSLayoutConstraint *findLeading = [_findBar.leadingAnchor constraintGreaterThanOrEqualToAnchor:_uncovered.leadingAnchor
                                                                                             constant:12];
        findLeading.priority = NSLayoutPriorityDragThatCannotResizeWindow;
        [NSLayoutConstraint activateConstraints:@[
            findLeading,
            [_findBar.topAnchor constraintEqualToAnchor:_clip.topAnchor constant:10],
            [_findBar.trailingAnchor constraintEqualToAnchor:_uncovered.trailingAnchor constant:-12],
            [_toast.centerXAnchor constraintEqualToAnchor:_uncovered.centerXAnchor],
            [_toast.bottomAnchor constraintEqualToAnchor:_clip.bottomAnchor constant:-18]
        ]];
        // The label sits centred in a rounded box: a text field draws at the top of a taller frame.
        _linkBox = [NSView new];
        _linkBox.wantsLayer = YES;
        _linkBox.layer.cornerRadius = 6;
        _linkBox.hidden = YES;
        _linkBox.translatesAutoresizingMaskIntoConstraints = NO;
        _linkLabel = [NSTextField labelWithString:@""];
        _linkLabel.font = [NSFont systemFontOfSize:11];
        _linkLabel.textColor = NSColor.secondaryLabelColor;
        _linkLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _linkLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_linkLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_linkBox addSubview:_linkLabel];
        [_clip addSubview:_linkBox];
        _linkLeading = [_linkBox.leadingAnchor constraintEqualToAnchor:_uncovered.leadingAnchor constant:6];
        _linkTrailing = [_uncovered.trailingAnchor constraintEqualToAnchor:_linkBox.trailingAnchor constant:6];
        [NSLayoutConstraint activateConstraints:@[
            [_linkBox.bottomAnchor constraintEqualToAnchor:_clip.bottomAnchor constant:-6],
            [_linkBox.widthAnchor constraintLessThanOrEqualToAnchor:_uncovered.widthAnchor multiplier:0.6],
            [_linkBox.heightAnchor constraintEqualToConstant:20],
            [_linkLabel.leadingAnchor constraintEqualToAnchor:_linkBox.leadingAnchor constant:6],
            [_linkBox.trailingAnchor constraintEqualToAnchor:_linkLabel.trailingAnchor constant:6],
            [_linkLabel.centerYAnchor constraintEqualToAnchor:_linkBox.centerYAnchor],
        ]];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(hoveredLink:)
                                                   name:BrookHoveredLinkNotification object:nil];
        [self updateColors];
    }
    return self;
}

/// Settings → Layout → Link previews: the address of the link under the pointer, in a corner.
- (void)hoveredLink:(NSNotification *)note {
    if (note.object != _webView) return;
    NSString *url = note.userInfo[@"url"];
    LinkPreview where = Settings.linkPreview;
    if (where == LinkPreviewOff || url.length == 0) { _linkBox.hidden = YES; return; }
    // Off before on, so the two edges never pin the label at once.
    (where == LinkPreviewLeft ? _linkTrailing : _linkLeading).active = NO;
    (where == LinkPreviewLeft ? _linkLeading : _linkTrailing).active = YES;
    _linkLabel.stringValue = url;
    _linkBox.hidden = NO;
}

- (void)pin:(NSView *)view toGuide:(NSLayoutGuide *)guide {
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];
}

- (void)setCoveredInsets:(NSEdgeInsets)insets animated:(BOOL)animated {
    if (NSEdgeInsetsEqual(insets, _coveredInsets)) return;
    _coveredInsets = insets;
    // Only the sides: the rail covers the card's edge, never its top or bottom.
    (animated ? _uncoveredLeading.animator : _uncoveredLeading).constant = insets.left;
    (animated ? _uncoveredTrailing.animator : _uncoveredTrailing).constant = insets.right;
    [self updateProgressFrameAnimated:NO];
}

- (void)setAccentColor:(NSColor *)accentColor {
    _accentColor = accentColor;
    _progress.backgroundColor = BrookAccentColor().CGColor;
    _empty.accent = accentColor;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    _clip.layer.cornerRadius = cornerRadius;
    _shadowView.cornerRadius = cornerRadius;
    // Edge-to-edge (no rounding) drops the card border and shadow too.
    _clip.layer.borderWidth = cornerRadius == 0 ? 0 : 0.5;
    [self updateColors];
    self.needsLayout = YES;
}

- (void)layout {
    [super layout];
    [self placeGlassShade];
    [self updateProgressFrameAnimated:NO];
}

- (NSView *)shadowView { return _shadowView; }

// How the Liquid Glass shade falls off beside the glass, measured against the real one: an
// edge blurred by a Gaussian of this spread, set this far out from the glass.
static const CGFloat kGlassShadeSigma = 14.75;
static const CGFloat kGlassShadeOffset = 4.75;

- (void)setGlassShade:(BOOL)on onRight:(BOOL)right gap:(CGFloat)gap {
    if (on == _glassShadeOn && right == _glassShadeOnRight && gap == _glassShadeGap) return;
    _glassShadeOn = on;
    _glassShadeOnRight = right;
    _glassShadeGap = gap;
    [self drawGlassShade];
}

- (void)drawGlassShade {
    if (!_glassShadeOn) {
        _glassShade.hidden = YES;
        return;
    }
    // Measured off the real glass beside a white page.
    CGFloat opacity = BrookIsDark(self.effectiveAppearance) ? 0.138 : 0.093;
    BOOL right = _glassShadeOnRight;
    CGFloat gap = _glassShadeGap;
    if (!_glassShade) {
        _glassShade = [CAGradientLayer layer];
        _glassShade.zPosition = 99;   // over the page, under the loading bar
        [_clip.layer addSublayer:_glassShade];
    }
    // Sampled finely enough that the steps stay under one level of 8-bit colour.
    const int n = 24;
    CGFloat reach = kGlassShadeOffset + 3 * kGlassShadeSigma - gap;
    NSMutableArray *colors = [NSMutableArray array];
    NSMutableArray<NSNumber *> *stops = [NSMutableArray array];
    for (int i = 0; i <= n; i++) {
        CGFloat t = (CGFloat)i / n, fromGlass = gap + t * std::max<CGFloat>(1, reach);
        CGFloat a = opacity * 0.5 * std::erfc((fromGlass - kGlassShadeOffset) / (kGlassShadeSigma * std::sqrt(2.0)));
        [colors addObject:(__bridge id)[NSColor.blackColor colorWithAlphaComponent:a].CGColor];
        [stops addObject:@(right ? 1 - t : t)];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glassShade.colors = right ? colors.reverseObjectEnumerator.allObjects : colors;
    _glassShade.locations = right ? stops.reverseObjectEnumerator.allObjects : stops;
    _glassShade.startPoint = CGPointMake(0, 0.5);
    _glassShade.endPoint = CGPointMake(1, 0.5);
    _glassShade.hidden = NO;
    [CATransaction commit];
    [self placeGlassShade];
}

- (void)placeGlassShade {
    if (!_glassShade || _glassShade.hidden) return;
    NSRect b = _clip.bounds;
    CGFloat w = std::min(b.size.width, std::max<CGFloat>(1, kGlassShadeOffset + 3 * kGlassShadeSigma - _glassShadeGap));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glassShade.frame = CGRectMake(_glassShadeOnRight ? NSMaxX(b) - w : 0, 0, w, b.size.height);
    [CATransaction commit];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateColors];
}

- (void)updateColors {
    _clip.layer.backgroundColor = [self brook_cg:NSColor.textBackgroundColor];
    _clip.layer.borderColor = [self brook_cg:BrookFill(0, 0.08, 1, 0.1)];
    _linkBox.layer.backgroundColor = [self brook_cg:NSColor.windowBackgroundColor];
    // Settings → Appearance → Page shadow.
    BOOL dark = BrookIsDark(self.effectiveAppearance);
    CardShadow shadow = Settings.cardShadow;
    _shadowStrength = shadow == CardShadowNone ? 0 : shadow == CardShadowStrong ? (dark ? 0.55f : 0.28f) : (dark ? 0.35f : 0.14f);
    [self drawGlassShade];
    CALayer *s = _shadowView.layer;
    s.shadowRadius = shadow == CardShadowStrong ? 14 : 6;
    s.shadowOffset = CGSizeMake(0, shadow == CardShadowStrong ? -4 : -1);
    s.shadowOpacity = _cornerRadius == 0 ? 0 : _shadowStrength;
}

- (void)applySettings {
    [self updateColors];
    [_empty updateHint];
    _progress.backgroundColor = BrookAccentColor().CGColor;
    [self updateProgress];
}

// MARK: Showing tabs

- (void)showTab:(BrowserTab *)tab split:(TabSplit *)split spaceName:(NSString *)spaceName {
    _tab = tab;
    BrowserTab *partner = [split partnerOf:tab];
    _partner = partner;
    _linkBox.hidden = YES;
    _empty.spaceName = spaceName;
    if (!tab) {
        _webView = nil;
        [_pageHost showPages:@[] focused:0 fraction:0.5];
        _empty.hidden = NO;
        _errorView.hidden = YES;
        _progress.opacity = 0;
        _findBar.hidden = YES;
        [self updateWakeCover];
        return;
    }
    _empty.hidden = YES;
    BrookWebView *wv = [tab materialize];
    if (partner) {
        BrookWebView *other = [partner materialize];
        BOOL onLeft = tab == split.left;
        [_pageHost showPages:onLeft ? @[wv, other] : @[other, wv] focused:onLeft ? 0 : 1 fraction:split.fraction];
    } else {
        [_pageHost showPages:@[wv] focused:0 fraction:0.5];
    }
    // The keys' page on top of the other's cover and error: they're laid over the focused page.
    [_pageHost addSubview:_wakeCover positioned:NSWindowBelow relativeTo:wv];
    [_pageHost addSubview:_errorView positioned:NSWindowAbove relativeTo:wv];
    _webView = wv;
    [self updateWakeCover];
    [self updateError];
    [self updateProgress];
    [self updateProgressFrameAnimated:NO];
    if (!_findBar.hidden) {
        _findBar.webView = wv;
        [_findBar invalidateCount];
        [_findBar searchForward:YES];
    }
}

- (void)showTab:(BrowserTab *)tab spaceName:(NSString *)spaceName {
    [self showTab:tab split:[BrowserState.shared splitFor:tab] spaceName:spaceName];
}

- (void)tabChanged:(BrowserTab *)tab change:(TabChange)change {
    // The page beside: only a new web view (after a crash or a wake) matters here.
    if (tab && tab == _partner && (change & TabChangeLoaded) && tab.webView && tab.webView.superview != _pageHost) {
        [self showTab:_tab spaceName:_empty.spaceName];
        return;
    }
    if (tab != _tab) return;
    // A new page never reports the old link as gone, so the preview ends when a load starts.
    if ((change & TabChangeLoading) && tab.isLoading) _linkBox.hidden = YES;
    if ((change & TabChangeProgress) || (change & TabChangeLoading)) [self updateProgress];
    if (change & TabChangeError) [self updateError];
    if (change & TabChangeURL) [_findBar invalidateCount];
    if (change & TabChangePainted) [self updateWakeCover];
    // Only a new web view is shown here. An unload is followed by a new selection, and showing the tab
    // again would load a closed tab back into memory.
    if ((change & TabChangeLoaded) && tab.webView && tab.webView != _webView) [self showTab:tab spaceName:_empty.spaceName];
}

- (void)updateWakeCover {
    NSImage *cover = _tab.wakeCover;
    _wakeCover.image = cover;
    _wakeCover.hidden = cover == nil;
}

- (void)updateError {
    BrowserTab *tab = _tab;
    NSString *message = tab.loadError;
    if (!tab || !message) { _errorView.hidden = YES; return; }
    __weak BrowserTab *weakTab = tab;
    [_errorView configureWithMessage:message url:tab.url onRetry:^{ [weakTab reload]; }];
    _errorView.hidden = NO;
}

- (void)updateProgress {
    BrowserTab *tab = _tab;
    if (!tab) return;
    double p = tab.isLoading ? std::max(0.08, tab.progress) : 1;
    if (tab.isLoading && Settings.loadingIndicator != LoadingIndicatorBar) {
        _progress.opacity = 0;   // the tab's icon spins instead, or nothing shows
        _lastProgress = 0;
        return;
    }
    if (tab.isLoading) {
        _progress.opacity = 1;
        if (p < _lastProgress) _lastProgress = 0;
        _lastProgress = p;
        [self updateProgressFrameAnimated:YES];
    } else if (_lastProgress > 0) {
        _lastProgress = 1;
        [self updateProgressFrameAnimated:YES];
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.4];
        _progress.opacity = 0;
        [CATransaction commit];
        _lastProgress = 0;
    }
}

- (void)updateProgressFrameAnimated:(BOOL)animated {
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:0.2];
    CGFloat h = 2.5;
    NSRect cb = _clip.bounds;
    // Across the part of the page left showing, not under the rail; with two up, across the focused one.
    CGFloat x = _coveredInsets.left, w = std::max<CGFloat>(0, cb.size.width - x - _coveredInsets.right);
    if (_pageHost.paired) {
        NSRect f = _pageHost.focusedFrame;
        x += f.origin.x;
        w = f.size.width;
    }
    _progress.frame = CGRectMake(x, cb.size.height - h, w * (CGFloat)_lastProgress, h);
    [CATransaction commit];
}

// MARK: Find

- (void)showFind {
    _findBar.webView = _webView;
    _findBar.hidden = NO;
    [_findBar focus];
}

- (void)findAgain:(BOOL)forward {
    // A closed bar still holds the page it last searched, which may no longer be in front.
    if (_findBar.hidden) {
        [self showFind];
        [_findBar invalidateCount];
    }
    [_findBar searchForward:forward];
}

@end
