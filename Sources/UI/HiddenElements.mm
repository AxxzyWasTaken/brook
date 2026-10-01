#import "Brook.h"

// See HiddenElements.h.
// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), Hidden.swift.

/// The list's document view: rows run down from the top.
@interface HiddenListView : NSView
@end
@implementation HiddenListView
- (BOOL)isFlipped { return YES; }
@end

/// One hidden thing: its name and shape, and a Restore button that shows while the pointer is on the row.
/// Pointing at the row tells the panel, which shows that thing on the page again.
@interface HiddenElementRow : NSView
@property (readonly) HiddenElement *element;
@property (copy) void (^onEnter)(HiddenElement *element);
@property (copy) void (^onRestore)(HiddenElement *element);
- (instancetype)initWithElement:(HiddenElement *)element;
@end

@implementation HiddenElementRow {
    NSTrackingArea *_tracking;
    NSButton *_restore;
    BOOL _hovering;
}

- (instancetype)initWithElement:(HiddenElement *)element {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _element = element;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;
        NSTextField *label = [NSTextField labelWithString:element.label];
        label.font = [NSFont systemFontOfSize:13];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.toolTip = element.selector;
        NSTextField *note = [NSTextField labelWithString:element.note ?: @""];
        note.font = [NSFont systemFontOfSize:11];
        note.textColor = NSColor.secondaryLabelColor;
        note.hidden = element.note.length == 0;
        NSStackView *text = [NSStackView stackViewWithViews:@[label, note]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
        text.spacing = 1;
        text.detachesHiddenViews = YES;
        [text setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        _restore = [NSButton buttonWithTitle:@"Restore" target:self action:@selector(restore)];
        _restore.bezelStyle = NSBezelStyleInline;
        _restore.controlSize = NSControlSizeSmall;
        _restore.alphaValue = 0;
        // Reachable without a pointer: VoiceOver and Full Keyboard Access see it whatever its alpha.
        _restore.accessibilityLabel = [@"Restore " stringByAppendingString:element.label];
        NSStackView *row = [NSStackView stackViewWithViews:@[text, _restore]];
        row.spacing = 8;
        row.edgeInsets = NSEdgeInsetsMake(6, 10, 6, 8);
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:self.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) return;
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                           options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                             owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)setHovering:(BOOL)on {
    _hovering = on;
    _restore.animator.alphaValue = on ? 1 : 0;
    self.layer.backgroundColor = on ? [NSColor.labelColor colorWithAlphaComponent:0.06].CGColor : nil;
}

- (void)mouseEntered:(NSEvent *)event {
    [self setHovering:YES];
    if (_onEnter) _onEnter(_element);
}

- (void)mouseExited:(NSEvent *)event { [self setHovering:NO]; }

- (void)restore { if (_onRestore) _onRestore(_element); }

@end

@implementation HiddenElementsViewController {
    NSString *_host;
    __weak WKWebView *_webView;
    void (^_onHideMore)(void);
    NSStackView *_list;
    NSTextField *_empty;
    NSTextField *_caption;
    NSButton *_restoreAll;
    NSScrollView *_scroll;
    NSLayoutConstraint *_scrollHeight;
}

- (instancetype)initWithHost:(NSString *)host webView:(WKWebView *)webView onHideMore:(void (^)(void))onHideMore {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = host;
        _webView = webView;
        _onHideMore = [onHideMore copy];
    }
    return self;
}

- (void)loadView {
    NSTextField *title = [NSTextField labelWithString:[SiteSettings keyForHost:_host]];
    title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    NSTextField *caption = _caption = [NSTextField labelWithString:@"Hidden on this site. Point at one to see it."];
    caption.font = [NSFont systemFontOfSize:11];
    caption.textColor = NSColor.secondaryLabelColor;
    _empty = [NSTextField labelWithString:@"Nothing is hidden on this site."];
    _empty.textColor = NSColor.secondaryLabelColor;

    _list = [NSStackView new];
    _list.orientation = NSUserInterfaceLayoutOrientationVertical;
    _list.alignment = NSLayoutAttributeLeading;
    _list.spacing = 0;
    _list.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *doc = [[HiddenListView alloc] initWithFrame:NSZeroRect];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:_list];
    _scroll = [NSScrollView new];
    _scroll.drawsBackground = NO;
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.documentView = doc;
    [NSLayoutConstraint activateConstraints:@[
        [_list.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor],
        [_list.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor],
        [_list.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [_list.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor],
        [doc.widthAnchor constraintEqualToAnchor:_scroll.contentView.widthAnchor],
    ]];
    _scrollHeight = [_scroll.heightAnchor constraintEqualToConstant:0];
    _scrollHeight.active = YES;

    __weak HiddenElementsViewController *weakSelf = self;
    NSButton *hideMore = [NSButton buttonWithTitle:@"Hide Something…" target:self action:@selector(hideMore)];
    hideMore.keyEquivalent = @"\r";
    _restoreAll = [NSButton buttonWithTitle:@"Restore All" target:self action:@selector(restoreAll)];
    NSStackView *foot = [NSStackView stackViewWithViews:@[hideMore, _restoreAll]];
    foot.spacing = 8;

    NSStackView *stack = [NSStackView stackViewWithViews:@[title, caption, _empty, _scroll, foot]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.detachesHiddenViews = YES;
    stack.edgeInsets = NSEdgeInsetsMake(16, 16, 14, 16);
    [stack setCustomSpacing:12 afterView:_scroll];
    [stack.widthAnchor constraintEqualToConstant:340].active = YES;
    [_scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
    [title.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor constant:-32].active = YES;
    self.view = stack;
    [self rebuild];
    [NSNotificationCenter.defaultCenter addObserverForName:ElementHiderDidChangeNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        [weakSelf rebuild];
    }];
}

- (void)rebuild {
    for (NSView *v in _list.arrangedSubviews.copy) [v removeFromSuperview];
    NSArray<HiddenElement *> *elements = [ElementHider.shared elementsForHost:_host];
    __weak HiddenElementsViewController *weakSelf = self;
    for (HiddenElement *e in elements) {
        HiddenElementRow *row = [[HiddenElementRow alloc] initWithElement:e];
        row.onEnter = ^(HiddenElement *el) { [weakSelf peek:el]; };
        row.onRestore = ^(HiddenElement *el) { [weakSelf restore:el]; };
        [_list addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:_list.widthAnchor].active = YES;
    }
    BOOL none = elements.count == 0;
    _empty.hidden = !none;
    _scroll.hidden = none;
    _restoreAll.hidden = none;
    _caption.hidden = none;
    [_list layoutSubtreeIfNeeded];
    _scrollHeight.constant = MIN(_list.fittingSize.height, 320);
}

- (void)peek:(HiddenElement *)element {
    if (WKWebView *wv = _webView) [ElementHider.shared peek:element.selector in:wv host:_host];
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    // Leaving the panel puts the page back the way it was.
    if (WKWebView *wv = _webView) [ElementHider.shared unpeekIn:wv host:_host];
}

- (void)restore:(HiddenElement *)element {
    [ElementHider.shared restore:element.selector onHost:_host];
    if (WKWebView *wv = _webView) [ElementHider.shared applyIn:wv host:_host];
}

- (void)restoreAll {
    [ElementHider.shared restoreAllOnHost:_host];
    if (WKWebView *wv = _webView) [ElementHider.shared applyIn:wv host:_host];
}

- (void)hideMore {
    void (^start)(void) = _onHideMore;
    [self.view.window close];
    if (start) start();
}

@end
