#import "Brook.h"

namespace {

/// One row in the suggestion list.
struct Suggestion {
    enum Kind { Open, Search, KeywordSearch, Tab, History };
    Kind kind;
    __strong NSURL *url = nil;              // Open
    __strong NSString *query = nil;         // Search, KeywordSearch
    __strong SearchEngine *engine = nil;    // KeywordSearch
    __strong BrowserTab *tab = nil;         // Tab
    __strong HistoryEntry *history = nil;   // History

    static Suggestion open(NSURL *u) { Suggestion s{Open}; s.url = u; return s; }
    static Suggestion search(NSString *q) { Suggestion s{Search}; s.query = q; return s; }
    static Suggestion keywordSearch(SearchEngine *e, NSString *q) {
        Suggestion s{KeywordSearch}; s.engine = e; s.query = q; return s;
    }
    static Suggestion tabSuggestion(BrowserTab *t) { Suggestion s{Tab}; s.tab = t; return s; }
    static Suggestion historySuggestion(HistoryEntry *h) { Suggestion s{History}; s.history = h; return s; }
};

/// Number of grapheme clusters (user-perceived characters).
NSInteger CharacterCount(NSString *s) {
    __block NSInteger n = 0;
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length)
                          options:NSStringEnumerationByComposedCharacterSequences | NSStringEnumerationSubstringNotRequired
                       usingBlock:^(NSString *, NSRange, NSRange, BOOL *) { n++; }];
    return n;
}

} // namespace

@implementation KeyPanel
- (BOOL)canBecomeKeyWindow { return !self.refusesKey; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// MARK: - Row + cell

@interface SuggestionRowView : NSTableRowView
@end

@implementation SuggestionRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 1) xRadius:10 yRadius:10];
    // The system colour for an emphasized selected row under white text; the raw accent is too
    // light for white text in some accents (Graphite) and matches the glass in dark mode.
    [[NSColor.selectedContentBackgroundColor colorWithAlphaComponent:0.85] setFill];
    [path fill];
}

- (NSBackgroundStyle)interiorBackgroundStyle {
    return self.isSelected ? NSBackgroundStyleEmphasized : NSBackgroundStyleNormal;
}

@end

@interface SuggestionCell : NSTableCellView
@property (class, readonly) NSUserInterfaceItemIdentifier reuseID;
- (void)configureIcon:(NSImage *)image title:(NSString *)t subtitle:(NSString *)s trailing:(NSString *)tr;
@end

@implementation SuggestionCell {
    NSImageView *_icon;
    NSTextField *_title;
    NSTextField *_subtitle;
    NSTextField *_trailing;
}

+ (NSUserInterfaceItemIdentifier)reuseID { return @"SuggestionCell"; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _icon = [NSImageView new];
        _title = [NSTextField labelWithString:@""];
        _subtitle = [NSTextField labelWithString:@""];
        _trailing = [NSTextField labelWithString:@""];
        self.identifier = SuggestionCell.reuseID;
        _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        _title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        _title.lineBreakMode = NSLineBreakByTruncatingTail;
        [_title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        _subtitle.font = [NSFont systemFontOfSize:12];
        _subtitle.textColor = NSColor.secondaryLabelColor;
        _subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
        [_subtitle setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];
        _trailing.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        _trailing.textColor = NSColor.tertiaryLabelColor;
        [_trailing setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];
        for (NSView *v in @[_icon, _title, _subtitle, _trailing]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:18],
            [_icon.heightAnchor constraintEqualToConstant:18],
            [_title.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:12],
            [_title.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_subtitle.leadingAnchor constraintEqualToAnchor:_title.trailingAnchor constant:8],
            [_subtitle.firstBaselineAnchor constraintEqualToAnchor:_title.firstBaselineAnchor],
            [_subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:_trailing.leadingAnchor constant:-10],
            [_trailing.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_trailing.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureIcon:(NSImage *)image title:(NSString *)t subtitle:(NSString *)s trailing:(NSString *)tr {
    _icon.image = image;
    _icon.contentTintColor = NSColor.secondaryLabelColor;
    _title.stringValue = t ?: @"";
    _subtitle.stringValue = s ? [NSString stringWithFormat:@"— %@", s] : @"";
    _trailing.stringValue = tr ?: @"";
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    [super setBackgroundStyle:backgroundStyle];
    BOOL selected = backgroundStyle == NSBackgroundStyleEmphasized;
    _title.textColor = selected ? NSColor.whiteColor : NSColor.labelColor;
    _subtitle.textColor = selected ? [NSColor.whiteColor colorWithAlphaComponent:0.75] : NSColor.secondaryLabelColor;
    _trailing.textColor = selected ? [NSColor.whiteColor colorWithAlphaComponent:0.8] : NSColor.tertiaryLabelColor;
    _icon.contentTintColor = selected ? NSColor.whiteColor : NSColor.secondaryLabelColor;
}

@end

// MARK: - Controller

/// Arc-style floating command bar: type a URL, a search, or the name of an open tab.
@implementation CommandBarController {
    __weak BrowserWindowController *_browser;
    KeyPanel *_panel;
    NSGlassEffectView *_glass;
    NSTextField *_field;
    NSImageView *_searchIcon;
    NSBox *_separator;
    NSLayoutConstraint *_scrollBelowField;
    NSLayoutConstraint *_scrollAtTop;
    /// Where the typing happens: our own field, or the tab's while attached.
    NSTextField *_input;
    NSTextField *_attachedField;
    __weak NSView *_anchor;
    __weak NSView *_bar;
    NSString *_initialText;   // the address as it was when editing began
    void (^_onEnd)(void);
    NSScrollView *_scroll;
    NSTableView *_table;
    std::vector<Suggestion> _suggestions;
    NSArray<NSString *> *_phrases;
    BOOL _editingCurrent;
    /// Bumping the generation cancels the pending autocomplete delay / request.
    NSUInteger _acGeneration;
    NSURLSessionDataTask *_acDataTask;
    CGFloat _width;
    CGFloat _rowHeight;
}

- (BOOL)isVisible { return _panel.isVisible || _attachedField != nil; }
- (BOOL)isAttached { return _attachedField != nil; }

- (instancetype)initWithBrowser:(BrowserWindowController *)browser {
    if ((self = [super init])) {
        _browser = browser;
        _glass = [NSGlassEffectView new];
        _field = [NSTextField new];
        _separator = [NSBox new];
        _scroll = [NSScrollView new];
        _table = [NSTableView new];
        _phrases = @[];
        _width = 660;
        _rowHeight = 42;
        _panel = [[KeyPanel alloc] initWithContentRect:NSMakeRect(0, 0, 660, 64)
                                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel |
                                                       NSWindowStyleMaskFullSizeContentView
                                               backing:NSBackingStoreBuffered
                                                 defer:YES];
        _panel.opaque = NO;
        _panel.backgroundColor = NSColor.clearColor;
        _panel.hasShadow = YES;
        _panel.level = NSFloatingWindowLevel;
        _panel.releasedWhenClosed = NO;
        _panel.delegate = self;
        _panel.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;

        NSView *root = [NSView new];
        // Clip to the glass's shape: the glass paints a faint square halo into its corners, and the
        // window shadow (traced from content alpha) would otherwise come out square.
        root.wantsLayer = YES;
        root.layer.cornerRadius = 20;
        root.layer.cornerCurve = kCACornerCurveContinuous;
        root.layer.masksToBounds = YES;
        _glass.cornerRadius = 20;
        _glass.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:_glass];
        [_glass brook_pinEdgesTo:root];

        NSView *content = [NSView new];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _glass.contentView = content;
        [content brook_pinEdgesTo:root];

        NSImageView *searchIcon = [NSImageView imageViewWithImage:[NSImage brook_symbol:@"magnifyingglass" size:17] ?: [NSImage new]];
        _searchIcon = searchIcon;
        _input = _field;
        searchIcon.contentTintColor = NSColor.secondaryLabelColor;
        searchIcon.translatesAutoresizingMaskIntoConstraints = NO;

        _field.bordered = NO;
        _field.drawsBackground = NO;
        _field.focusRingType = NSFocusRingTypeNone;
        _field.font = [NSFont systemFontOfSize:20 weight:NSFontWeightRegular];
        _field.placeholderString = @"Search or enter address";
        _field.delegate = self;
        _field.lineBreakMode = NSLineBreakByTruncatingTail;
        _field.cell.scrollable = YES;
        _field.cell.wraps = NO;
        _field.translatesAutoresizingMaskIntoConstraints = NO;

        _separator.boxType = NSBoxSeparator;
        _separator.translatesAutoresizingMaskIntoConstraints = NO;

        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"s"];
        column.resizingMask = NSTableColumnAutoresizingMask;
        [_table addTableColumn:column];
        _table.headerView = nil;
        _table.backgroundColor = NSColor.clearColor;
        _table.style = NSTableViewStylePlain;
        _table.rowHeight = _rowHeight;
        _table.intercellSpacing = NSMakeSize(0, 0);
        _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
        _table.dataSource = self;
        _table.delegate = self;
        _table.target = self;
        _table.action = @selector(rowClicked);
        _table.refusesFirstResponder = YES;
        _scroll.documentView = _table;
        _scroll.drawsBackground = NO;
        _scroll.hasVerticalScroller = NO;
        _scroll.translatesAutoresizingMaskIntoConstraints = NO;

        for (NSView *v in @[searchIcon, _field, _separator, _scroll]) [content addSubview:v];
        [NSLayoutConstraint activateConstraints:@[
            [searchIcon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
            [searchIcon.centerYAnchor constraintEqualToAnchor:content.topAnchor constant:32],
            [_field.leadingAnchor constraintEqualToAnchor:searchIcon.trailingAnchor constant:12],
            [_field.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
            [_field.centerYAnchor constraintEqualToAnchor:searchIcon.centerYAnchor],
            [_separator.topAnchor constraintEqualToAnchor:content.topAnchor constant:63],
            [_separator.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [_separator.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [_scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
            [_scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
            [_scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8],
        ]];
        _scrollBelowField = [_scroll.topAnchor constraintEqualToAnchor:_separator.bottomAnchor constant:6];
        _scrollAtTop = [_scroll.topAnchor constraintEqualToAnchor:content.topAnchor constant:8];
        _scrollBelowField.active = YES;
        _panel.contentView = root;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(iconLoaded:)
                                                   name:FaviconStoreDidLoadIconNotification object:nil];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

/// A suggestion's site icon arrived from the disk cache: redraw its rows (selection stays).
- (void)iconLoaded:(NSNotification *)note {
    if (!self.isVisible) return;
    NSString *host = note.object;
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (size_t i = 0; i < _suggestions.size(); i++) {
        const Suggestion &s = _suggestions[i];
        NSURL *url = s.kind == Suggestion::Open ? s.url
                   : s.kind == Suggestion::History ? [NSURL URLWithString:s.history.url] : nil;
        if (url && [BrookHost(url) isEqualToString:host]) [rows addIndex:i];
    }
    if (rows.count) [_table reloadDataForRowIndexes:rows columnIndexes:[NSIndexSet indexSetWithIndex:0]];
}

// MARK: Show / hide

- (void)showEditingCurrent:(BOOL)editingCurrent {
    NSWindow *parent = _browser.window;
    if (!parent) return;
    if (_attachedField) [self dismiss];
    [self useAttachedLayout:NO];
    _editingCurrent = editingCurrent;
    NSString *current = editingCurrent ? (BrowserState.shared.selectedTab.url.absoluteString ?: @"") : @"";
    _field.stringValue = current;
    _initialText = current;
    [self cancelAutocomplete];
    _phrases = @[];   // the last session's search suggestions don't belong to this one
    [self rebuild];
    if (!_panel.isVisible) {
        [parent addChildWindow:_panel ordered:NSWindowAbove];
        [self layoutPanel];
        _panel.alphaValue = 0;
        [_panel makeKeyAndOrderFront:nil];
        KeyPanel *panel = _panel;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.12;
            panel.animator.alphaValue = 1;
        }];
    } else {
        [self layoutPanel];
        [_panel makeKeyWindow];
    }
    [_panel makeFirstResponder:_field];
    [_field.currentEditor selectAll:nil];
}

/// Attached, the panel is just the suggestions list: the field it types into lives in the tab.
- (void)useAttachedLayout:(BOOL)attached {
    _input = attached ? _attachedField : _field;
    _panel.refusesKey = attached;
    _searchIcon.hidden = attached;
    _field.hidden = attached;
    // Off before on, or both pin the list at once and AppKit breaks one of them.
    (attached ? _scrollBelowField : _scrollAtTop).active = NO;
    (attached ? _scrollAtTop : _scrollBelowField).active = YES;
}

- (void)showAttachedToField:(NSTextField *)field alignedWith:(NSView *)anchor below:(NSView *)bar
                      onEnd:(void (^)(void))onEnd {
    NSWindow *parent = _browser.window;
    if (!parent || !field) return;
    [self dismiss];
    _attachedField = field;
    _anchor = anchor;
    _bar = bar;
    _initialText = field.stringValue;
    _phrases = @[];
    _onEnd = [onEnd copy];
    _editingCurrent = YES;
    [self useAttachedLayout:YES];
    _separator.hidden = YES;
    field.delegate = self;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(parentResignedKey:)
                                               name:NSWindowDidResignKeyNotification object:parent];
    [parent makeFirstResponder:field];
    [field.currentEditor selectAll:nil];
    [self rebuild];
}

- (void)parentResignedKey:(NSNotification *)note { [self dismiss]; }

/// Drops the list down under the bar, starting at the tab, at least wide enough to read and kept
/// inside the window.
- (void)layoutAttached {
    NSWindow *parent = _browser.window;
    NSView *anchor = _anchor, *bar = _bar ?: _anchor;
    if (!parent || !anchor.window) return;
    NSInteger rows = std::min<NSInteger>((NSInteger)_suggestions.size(), Settings.commandBarRows);
    if (rows == 0) {
        [parent removeChildWindow:_panel];
        [_panel orderOut:nil];
        return;
    }
    NSRect a = [parent convertRectToScreen:[anchor convertRect:anchor.bounds toView:nil]];
    NSRect b = [parent convertRectToScreen:[bar convertRect:bar.bounds toView:nil]];
    NSRect pf = parent.frame;
    CGFloat w = std::min<CGFloat>(std::max<CGFloat>(560, NSWidth(a)), NSWidth(pf) - 16);
    CGFloat x = std::clamp<CGFloat>(NSMinX(a), NSMinX(pf) + 8, NSMaxX(pf) - 8 - w);
    CGFloat h = (CGFloat)rows * _rowHeight + 16;
    [_panel setFrame:NSMakeRect(x, NSMinY(b) - 6 - h, w, h) display:YES];
    if (!_panel.isVisible) {
        [parent addChildWindow:_panel ordered:NSWindowAbove];
        _panel.alphaValue = 0;
        [_panel orderFront:nil];
        KeyPanel *panel = _panel;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.12;
            panel.animator.alphaValue = 1;
        }];
    }
    [_panel invalidateShadow];
    __weak KeyPanel *weakPanel = _panel;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakPanel invalidateShadow]; });
}

- (void)endAttached {
    NSTextField *field = _attachedField;
    void (^onEnd)(void) = _onEnd;
    _attachedField = nil;
    _onEnd = nil;
    _anchor = nil;
    _bar = nil;
    [self cancelAutocomplete];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
    [_panel.parentWindow removeChildWindow:_panel];
    [_panel orderOut:nil];
    [self useAttachedLayout:NO];
    field.delegate = nil;   // leaving the field below must not come back here
    WKWebView *wv = _browser.content.webView;
    [_browser.window makeFirstResponder:wv];
    if (onEnd) onEnd();
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    // Focus left the tab's field (a click on the page, say): stop editing, as Safari does.
    if (_attachedField && note.object == _attachedField) [self dismiss];
}

- (void)cancelAutocomplete {
    _acGeneration++;
    [_acDataTask cancel];
    _acDataTask = nil;
}

- (void)dismiss {
    if (_attachedField) {
        [self endAttached];
        return;
    }
    if (!_panel.isVisible) return;
    [self cancelAutocomplete];
    [_panel.parentWindow removeChildWindow:_panel];
    [_panel orderOut:nil];
    WKWebView *wv = _browser.content.webView;
    if (wv) [_browser.window makeFirstResponder:wv];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    [self dismiss];
}

- (void)layoutPanel {
    NSWindow *parent = _browser.window;
    if (!parent) return;
    NSInteger visibleRows = std::min<NSInteger>((NSInteger)_suggestions.size(), Settings.commandBarRows);
    CGFloat height = 64 + (visibleRows > 0 ? (CGFloat)visibleRows * _rowHeight + 16 : 0);
    NSRect pf = parent.frame;
    CGFloat w = std::min(_width, NSWidth(pf) - 80);
    // Settings → Search → Position: the upper third (Spotlight-like) or just under the toolbar.
    CGFloat top = NSMaxY(pf) - (Settings.commandBarPosition == CommandBarPositionTop ? 60 : NSHeight(pf) * 0.2);
    [_panel setFrame:NSMakeRect(NSMidX(pf) - w / 2, top - height, w, height) display:YES];
    _separator.hidden = visibleRows == 0;
    // The window shadow is traced from the content's alpha. Retrace it once the glass has drawn
    // its rounded shape at the new size, or a square shadow shows outside the corners.
    [_panel invalidateShadow];
    __weak KeyPanel *weakPanel = _panel;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakPanel invalidateShadow]; });
}

// MARK: Suggestions

- (void)controlTextDidChange:(NSNotification *)obj {
    [self rebuild];
    [self fetchPhrases];
}

- (void)rebuild {
    NSString *text = BrookTrim(_input.stringValue);
    std::vector<Suggestion> list;
    BrowserState *state = BrowserState.shared;

    // Nothing typed yet (or the current address, untouched): offer recently used tabs.
    if (text.length == 0 || (_editingCurrent && [text isEqualToString:BrookTrim(_initialText ?: @"")])) {
        BrowserTab *selected = state.selectedTab;
        NSMutableArray<BrowserTab *> *candidates = [NSMutableArray array];
        for (BrowserTab *t in state.visibleTabs) {
            if (t != selected && t.url != nil) [candidates addObject:t];
        }
        NSArray<BrowserTab *> *recent = [candidates sortedArrayWithOptions:NSSortStable
                                                           usingComparator:^NSComparisonResult(BrowserTab *a, BrowserTab *b) {
            // Descending by lastActive.
            return [b.lastActive compare:a.lastActive];
        }];
        if (Settings.commandBarTabs) {
            for (NSUInteger i = 0; i < recent.count && i < 6; i++) list.push_back(Suggestion::tabSuggestion(recent[i]));
        }
    } else {
        NSString *kwQuery = nil;
        SearchEngine *engine = [SearchEngines keywordMatch:text query:&kwQuery];
        if (engine) list.push_back(Suggestion::keywordSearch(engine, kwQuery));
        NSURL *url = [URLParser urlFromInput:text];
        if (url) list.push_back(Suggestion::open(url));
        list.push_back(Suggestion::search(text));
        NSString *q = text.lowercaseString;
        BrowserTab *selected = state.selectedTab;
        NSMutableArray<BrowserTab *> *tabs = [NSMutableArray array];
        for (BrowserTab *t in Settings.commandBarTabs ? state.allTabs : @[]) {
            if (tabs.count >= 3) break;
            if (t == selected) continue;
            NSString *urlString = t.url.absoluteString.lowercaseString;
            if ([t.displayTitle.lowercaseString containsString:q] || (urlString && [urlString containsString:q])) {
                [tabs addObject:t];
            }
        }
        for (BrowserTab *t in tabs) list.push_back(Suggestion::tabSuggestion(t));
        NSMutableSet<NSString *> *openURLs = [NSMutableSet set];
        for (BrowserTab *t in tabs) {
            if (t.url.absoluteString) [openURLs addObject:t.url.absoluteString];
        }
        for (HistoryEntry *e in Settings.commandBarHistory ? [HistoryStore.shared search:text limit:5] : @[]) {
            if (![openURLs containsObject:e.url]) list.push_back(Suggestion::historySuggestion(e));
        }
        std::vector<Suggestion> searchPhrases;
        for (NSString *p in _phrases) {
            if (searchPhrases.size() >= 4) break;
            if (![p.lowercaseString isEqualToString:q]) searchPhrases.push_back(Suggestion::search(p));
        }
        if (!searchPhrases.empty()) {
            NSInteger lead = ([URLParser urlFromInput:text] != nil ? 1 : 0) +
                             ([SearchEngines keywordMatch:text query:NULL] != nil ? 1 : 0);
            NSInteger insertAt = std::min<NSInteger>((NSInteger)list.size(), lead + 1);
            list.insert(list.begin() + insertAt, searchPhrases.begin(), searchPhrases.end());
        }
    }
    _suggestions = std::move(list);
    [_table reloadData];
    // Make the rows before selecting one: a row made already selected keeps a non-vibrant look
    // after the selection moves on, so its labels draw dimmer than every other row's.
    [_table layoutSubtreeIfNeeded];
    if (!_suggestions.empty()) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    if (_attachedField) [self layoutAttached];
    else if (_panel.isVisible) [self layoutPanel];
}

/// Search suggestions from DuckDuckGo's autocomplete endpoint.
- (void)fetchPhrases {
    [self cancelAutocomplete];
    NSString *text = BrookTrim(_input.stringValue);
    if (!(Settings.commandBarSuggestions && CharacterCount(text) >= 2 && [URLParser urlFromInput:text] == nil)) {
        _phrases = @[];
        return;
    }
    NSUInteger generation = _acGeneration;
    __weak CommandBarController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        CommandBarController *strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_acGeneration != generation) return;
        NSString *q = [text stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        if (!q) return;
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://duckduckgo.com/ac/?q=%@&type=list", q]];
        if (!url) return;
        NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                               completionHandler:^(NSData *data, NSURLResponse *, NSError *error) {
            if (!data || error) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                CommandBarController *s = weakSelf;
                if (!s || s->_acGeneration != generation) return;
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (![json isKindOfClass:NSArray.class] || [json count] <= 1) return;
                id raw = json[1];
                if (![raw isKindOfClass:NSArray.class]) return;
                for (id item in raw) {
                    if (![item isKindOfClass:NSString.class]) return;
                }
                if (![BrookTrim(s->_input.stringValue) isEqualToString:text]) return;
                s->_phrases = raw;
                NSInteger selected = s->_table.selectedRow;
                [s rebuild];
                if (selected > 0 && selected < (NSInteger)s->_suggestions.size()) {
                    [s->_table selectRowIndexes:[NSIndexSet indexSetWithIndex:selected] byExtendingSelection:NO];
                }
            });
        }];
        strongSelf->_acDataTask = task;
        [task resume];
    });
}

// MARK: Keyboard

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (selector == @selector(moveDown:)) {
        [self move:1]; return YES;
    } else if (selector == @selector(moveUp:)) {
        [self move:-1]; return YES;
    } else if (selector == @selector(insertNewline:)) {
        [self commitRow:_table.selectedRow]; return YES;
    } else if (selector == @selector(cancelOperation:)) {
        [self dismiss]; return YES;
    }
    return NO;
}

- (void)move:(NSInteger)delta {
    if (_suggestions.empty()) return;
    NSInteger next = std::max<NSInteger>(0, std::min<NSInteger>((NSInteger)_suggestions.size() - 1, _table.selectedRow + delta));
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:next] byExtendingSelection:NO];
    [_table scrollRowToVisible:next];
}

- (void)rowClicked {
    [self commitRow:_table.clickedRow];
}

- (void)commitRow:(NSInteger)row {
    NSString *text = BrookTrim(_input.stringValue);
    BrowserState *state = BrowserState.shared;
    NSURL *destination = nil;
    if (row >= 0 && row < (NSInteger)_suggestions.size()) {
        Suggestion s = _suggestions[row];
        switch (s.kind) {
        case Suggestion::Open: destination = s.url; break;
        case Suggestion::Search: destination = [SearchEngines.current urlForQuery:s.query]; break;
        case Suggestion::KeywordSearch: destination = [s.engine urlForQuery:s.query]; break;
        case Suggestion::History: destination = [NSURL URLWithString:s.history.url]; break;
        case Suggestion::Tab:
            [self dismiss];
            [state selectTab:s.tab];
            return;
        }
    } else if (text.length > 0) {
        destination = [URLParser destinationForInput:text];
    } else {
        destination = nil;
    }
    [self dismiss];
    if (!destination) return;
    BrowserTab *tab = state.selectedTab;
    if (_editingCurrent && tab) {
        [tab load:destination];
    } else {
        [state openTabWithURL:destination inSpace:nil select:YES];
    }
}

// MARK: Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_suggestions.size();
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [SuggestionRowView new];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    id made = [tableView makeViewWithIdentifier:SuggestionCell.reuseID owner:self];
    SuggestionCell *cell = [made isKindOfClass:SuggestionCell.class] ? made : [SuggestionCell new];
    const Suggestion &s = _suggestions[row];
    switch (s.kind) {
    case Suggestion::Open:
        [cell configureIcon:[FaviconStore.shared cachedIconForHost:BrookHost(s.url) ?: @""]
                                ?: [NSImage brook_symbol:@"globe" size:14]
                      title:s.url.absoluteString subtitle:nil trailing:@"Open"];
        break;
    case Suggestion::Search:
        [cell configureIcon:[NSImage brook_symbol:@"magnifyingglass" size:14] title:s.query subtitle:nil
                   trailing:SearchEngines.current.name];
        break;
    case Suggestion::KeywordSearch:
        [cell configureIcon:[NSImage brook_symbol:@"magnifyingglass" size:14] title:s.query subtitle:nil
                   trailing:[NSString stringWithFormat:@"Search %@", s.engine.name]];
        break;
    case Suggestion::Tab:
        [cell configureIcon:s.tab.favicon ?: [NSImage brook_symbol:@"globe" size:14] title:s.tab.displayTitle
                   subtitle:[URLParser display:s.tab.url] trailing:@"Switch to Tab"];
        break;
    case Suggestion::History: {
        HistoryEntry *e = s.history;
        NSURL *url = [NSURL URLWithString:e.url];
        [cell configureIcon:[FaviconStore.shared cachedIconForHost:BrookHost(url) ?: @""]
                                ?: [NSImage brook_symbol:@"clock" size:14]
                      title:e.title.length == 0 ? e.url : e.title
                   subtitle:[URLParser display:url]
                   trailing:nil];
        break;
    }
    }
    return cell;
}

@end
