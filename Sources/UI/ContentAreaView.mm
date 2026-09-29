#import "Brook.h"

// MARK: - Empty state

@interface EmptyStateView : NSView
@property (nonatomic, strong) NSColor *accent;
@property (nonatomic, copy) NSString *spaceName;
@end

@implementation EmptyStateView {
    NSTextField *_title;
    NSTextField *_hint;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _title = [NSTextField labelWithString:@""];
        _hint = [NSTextField labelWithString:@"Press ⌘T to search or open a site"];
        _accent = NSColor.controlAccentColor;
        _spaceName = @"";
        _title.font = [NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
        _title.textColor = NSColor.labelColor;
        _hint.font = [NSFont systemFontOfSize:14];
        _hint.textColor = NSColor.secondaryLabelColor;
        NSStackView *stack = [NSStackView stackViewWithViews:@[_title, _hint]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30]
        ]];
    }
    return self;
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

// MARK: - Content area

/// The card's background extension, flipped like the web view inside it: unflipped, it fills the
/// strip under the rail with the page upside down (the page's header showed at the rail's foot).
@interface PageExtensionView : NSBackgroundExtensionView
@end

@implementation PageExtensionView
- (BOOL)isFlipped { return YES; }
@end

@implementation ContentAreaView {
    NSView *_clip;
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
    NSView *_pageHost;
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
        self.layer.masksToBounds = NO;
        self.layer.shadowColor = NSColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.14f;
        self.layer.shadowRadius = 6;
        self.layer.shadowOffset = CGSizeMake(0, -1);

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

        _pageHost = [NSView new];
        _pageHost.translatesAutoresizingMaskIntoConstraints = NO;
        _extension = [PageExtensionView new];
        _extension.translatesAutoresizingMaskIntoConstraints = NO;
        _extension.automaticallyPlacesContentView = NO;
        _extension.contentView = _pageHost;
        [_clip addSubview:_extension];
        [_extension brook_pinEdgesTo:_clip];
        [self pin:_pageHost toGuide:_uncovered];

        _empty.translatesAutoresizingMaskIntoConstraints = NO;
        [_clip addSubview:_empty];
        [self pin:_empty toGuide:_uncovered];

        _errorView.hidden = YES;
        _errorView.translatesAutoresizingMaskIntoConstraints = NO;
        [_clip addSubview:_errorView];
        [self pin:_errorView toGuide:_uncovered];

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
    // Edge-to-edge (no rounding) drops the card border and shadow too.
    _clip.layer.borderWidth = cornerRadius == 0 ? 0 : 0.5;
    [self updateColors];
    self.needsLayout = YES;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat r = std::min({_cornerRadius, b.size.width / 2, b.size.height / 2});
    CGPathRef path = CGPathCreateWithRoundedRect(b, r, r, NULL);
    self.layer.shadowPath = path;
    CGPathRelease(path);
    [self updateProgressFrameAnimated:NO];
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
    self.layer.shadowRadius = shadow == CardShadowStrong ? 14 : 6;
    self.layer.shadowOffset = CGSizeMake(0, shadow == CardShadowStrong ? -4 : -1);
    self.layer.shadowOpacity = _cornerRadius == 0 ? 0 : _shadowStrength;
}

- (void)applySettings {
    [self updateColors];
    _progress.backgroundColor = BrookAccentColor().CGColor;
    [self updateProgress];
}

// MARK: Showing tabs

- (void)showTab:(BrowserTab *)tab spaceName:(NSString *)spaceName {
    _tab = tab;
    WKWebView *current = _webView;
    if (current && current != tab.webView) [current removeFromSuperview];
    _linkBox.hidden = YES;
    _empty.spaceName = spaceName;
    if (!tab) {
        _webView = nil;
        _empty.hidden = NO;
        _errorView.hidden = YES;
        _progress.opacity = 0;
        _findBar.hidden = YES;
        return;
    }
    _empty.hidden = YES;
    BrookWebView *wv = [tab materialize];
    if (wv.superview != _pageHost) {
        wv.frame = _pageHost.bounds;
        wv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_pageHost addSubview:wv];
    }
    _webView = wv;
    [self updateError];
    [self updateProgress];
    if (!_findBar.hidden) {
        _findBar.webView = wv;
        [_findBar invalidateCount];
        [_findBar searchForward:YES];
    }
}

- (void)tabChanged:(BrowserTab *)tab change:(TabChange)change {
    if (tab != _tab) return;
    // A new page never reports the old link as gone, so the preview ends when a load starts.
    if ((change & TabChangeLoading) && tab.isLoading) _linkBox.hidden = YES;
    if ((change & TabChangeProgress) || (change & TabChangeLoading)) [self updateProgress];
    if (change & TabChangeError) [self updateError];
    if (change & TabChangeURL) [_findBar invalidateCount];
    if ((change & TabChangeLoaded) && tab.webView != _webView) [self showTab:tab spaceName:_empty.spaceName];
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
    // Across the part of the page left showing, not under the rail.
    CGFloat x = _coveredInsets.left, w = std::max<CGFloat>(0, cb.size.width - x - _coveredInsets.right);
    _progress.frame = CGRectMake(x, cb.size.height - h, w * (CGFloat)_lastProgress, h);
    [CATransaction commit];
}

// MARK: Find

- (void)showFind {
    _findBar.webView = _webView;
    _findBar.hidden = NO;
    [_findBar focus];
}

@end
