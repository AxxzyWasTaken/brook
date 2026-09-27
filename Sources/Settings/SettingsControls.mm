#import "Brook.h"

// MARK: - Form building blocks

/// A two-column settings form (label on the right-aligned left column, control on the right),
/// laid out like System Settings / Safari's preference panes.
@implementation SettingsForm {
    NSGridView *_grid;
    NSInteger _rowCount;
}

- (instancetype)init {
    if ((self = [super init])) {
        _grid = [NSGridView new];
        _grid.rowSpacing = 10;
        _grid.columnSpacing = 12;
        _grid.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (NSGridView *)grid { return _grid; }
- (NSInteger)rowCount { return _rowCount; }

- (NSGridRow *)row:(NSString *)title views:(NSArray<NSView *> *)views {
    NSTextField *label = [NSTextField labelWithString:title.length == 0 ? @"" : [title stringByAppendingString:@":"]];
    label.alignment = NSTextAlignmentRight;
    NSView *right;
    if (views.count == 1) {
        right = views[0];
    } else {
        NSStackView *stack = [NSStackView stackViewWithViews:views];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 6;
        right = stack;
    }
    NSGridRow *r = [_grid addRowWithViews:@[label, right]];
    r.rowAlignment = NSGridRowAlignmentFirstBaseline;
    _rowCount += 1;
    return r;
}

- (NSGridRow *)row:(NSString *)title view:(NSView *)view {
    return [self row:title views:@[view]];
}

- (void)note:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = NSColor.secondaryLabelColor;
    label.preferredMaxLayoutWidth = 360;
    NSGridRow *r = [_grid addRowWithViews:@[NSGridCell.emptyContentView, label]];
    r.topPadding = -4;
}

- (void)separator {
    NSGridRow *r = [_grid addRowWithViews:@[NSGridCell.emptyContentView, NSGridCell.emptyContentView]];
    r.topPadding = 8;
}

- (void)finish {
    if (_grid.numberOfColumns != 2) return;
    [_grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [_grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
}

- (NSView *)view { return [self viewWithWidth:620]; }

/// Wraps the form in a padded container view.
- (NSView *)viewWithWidth:(CGFloat)width {
    [self finish];
    NSView *v = [NSView new];
    [v addSubview:_grid];
    // Centred (nudged left, like Safari's panes), but never closer than 24pt to an edge:
    // wide panes grow the window instead of clipping.
    NSLayoutConstraint *center = [_grid.centerXAnchor constraintEqualToAnchor:v.centerXAnchor constant:-30];
    center.priority = NSLayoutPriorityDefaultHigh;
    NSLayoutConstraint *minWidth = [v.widthAnchor constraintEqualToConstant:width];
    minWidth.priority = NSLayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        [_grid.topAnchor constraintEqualToAnchor:v.topAnchor constant:24],
        [_grid.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-24],
        [_grid.leadingAnchor constraintGreaterThanOrEqualToAnchor:v.leadingAnchor constant:24],
        [_grid.trailingAnchor constraintLessThanOrEqualToAnchor:v.trailingAnchor constant:-24],
        [v.widthAnchor constraintGreaterThanOrEqualToConstant:width],
        center, minWidth
    ]];
    return v;
}

@end

// MARK: - Controls

@implementation Controls

+ (NSPopUpButton *)popupWithTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)selected
                          onChange:(void (^)(NSInteger index))onChange {
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSString *t in titles) [p addItemWithTitle:t];
    [p selectItemAtIndex:(selected >= 0 && selected < (NSInteger)titles.count) ? selected : 0];
    NSInteger count = (NSInteger)titles.count;
    [p brook_onAction:^(id c) {
        NSInteger i = ((NSPopUpButton *)c).indexOfSelectedItem;
        if (i >= 0 && i < count) onChange(i);
    }];
    return p;
}

+ (NSButton *)check:(NSString *)title on:(BOOL)on onChange:(void (^)(BOOL on))onChange {
    NSButton *b = [NSButton checkboxWithTitle:title target:nil action:nil];
    b.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    [b brook_onAction:^(id c) { onChange(((NSButton *)c).state == NSControlStateValueOn); }];
    return b;
}

/// Slider with a live value label.
+ (NSView *)sliderWithMin:(double)min max:(double)max value:(double)value width:(CGFloat)width ticks:(NSInteger)ticks
                   format:(NSString * (^)(double value))format onChange:(void (^)(double value))onChange {
    NSSlider *s = [NSSlider sliderWithValue:value minValue:min maxValue:max target:nil action:nil];
    s.continuous = YES;
    if (ticks > 1) {
        s.numberOfTickMarks = ticks;
        s.allowsTickMarkValuesOnly = YES;
    }
    [s.widthAnchor constraintEqualToConstant:width].active = YES;
    NSTextField *label = [NSTextField labelWithString:format(value)];
    label.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    label.textColor = NSColor.secondaryLabelColor;
    [label.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [s brook_onAction:^(id c) {
        double v = ((NSSlider *)c).doubleValue;
        label.stringValue = format(v);
        onChange(v);
    }];
    NSStackView *row = [NSStackView stackViewWithViews:@[s, label]];
    row.spacing = 8;
    return row;
}

+ (NSSegmentedControl *)segmentedWithTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)selected
                                   onChange:(void (^)(NSInteger index))onChange {
    NSSegmentedControl *seg = [NSSegmentedControl segmentedControlWithLabels:titles
                                                                trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                      target:nil action:nil];
    seg.selectedSegment = (selected >= 0 && selected < (NSInteger)titles.count) ? selected : 0;
    NSInteger count = (NSInteger)titles.count;
    [seg brook_onAction:^(id c) {
        NSInteger i = ((NSSegmentedControl *)c).selectedSegment;
        if (i >= 0 && i < count) onChange(i);
    }];
    return seg;
}

+ (NSButton *)button:(NSString *)title action:(void (^)(void))action {
    NSButton *b = [NSButton buttonWithTitle:title target:nil action:nil];
    b.bezelStyle = NSBezelStylePush;
    [b brook_onAction:^(id) { action(); }];
    return b;
}

/// Text field that commits when editing ends (return or focus change).
+ (NSTextField *)field:(NSString *)value placeholder:(NSString *)placeholder width:(CGFloat)width
              onCommit:(void (^)(NSString *value))onCommit {
    NSTextField *f = [NSTextField textFieldWithString:value];
    f.placeholderString = placeholder;
    [f.widthAnchor constraintEqualToConstant:width].active = YES;
    [f brook_onAction:^(id c) { onCommit(BrookTrim(((NSTextField *)c).stringValue)); }];
    if ([f.cell isKindOfClass:NSTextFieldCell.class]) ((NSTextFieldCell *)f.cell).sendsActionOnEndEditing = YES;
    return f;
}

@end

// MARK: - EditableList

/// Plain table with a scroll view and +/- buttons underneath, used by the list-style panes.
@implementation EditableList {
    NSStackView *_buttonRow;
}

- (instancetype)initWithColumns:(const std::vector<EditableListColumn> &)columns height:(CGFloat)height {
    if (!(self = [super init])) return nil;
    _table = [NSTableView new];
    _scroll = [NSScrollView new];
    _segment = [NSSegmentedControl new];
    _container = [NSStackView new];
    _emptyLabel = [NSTextField labelWithString:@""];
    _extra = @[];
    _buttonRow = [NSStackView new];

    for (const auto &c : columns) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c.identifier];
        col.title = c.title;
        col.width = c.width;
        [_table addTableColumn:col];
    }
    _table.style = NSTableViewStyleFullWidth;
    _table.allowsMultipleSelection = NO;
    _table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _emptyLabel.textColor = NSColor.tertiaryLabelColor;
    _emptyLabel.alignment = NSTextAlignmentCenter;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.documentView = _table;
    _scroll.hasVerticalScroller = YES;
    _scroll.borderType = NSBezelBorder;
    [_scroll.heightAnchor constraintEqualToConstant:height].active = YES;
    // Overlay the empty message on the scroll view (above its clip view, so it's visible).
    [_scroll addSubview:_emptyLabel positioned:NSWindowAbove relativeTo:nil];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:_scroll.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:_scroll.centerYAnchor constant:10]
    ]];

    _segment.segmentCount = 2;
    [_segment setImage:[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add"] forSegment:0];
    [_segment setImage:[NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Remove"] forSegment:1];
    _segment.trackingMode = NSSegmentSwitchTrackingMomentary;
    _segment.segmentStyle = NSSegmentStyleSmallSquare;
    __weak EditableList *weakSelf = self;
    [_segment brook_onAction:^(id c) {
        EditableList *self = weakSelf;
        if (!self) return;
        if (((NSSegmentedControl *)c).selectedSegment == 0) {
            if (self.onAdd) self.onAdd();
        } else if (self.table.selectedRow >= 0) {
            if (self.onRemove) self.onRemove(self.table.selectedRow);
        }
    }];
    [_buttonRow addArrangedSubview:_segment];
    _buttonRow.spacing = 8;

    _container.orientation = NSUserInterfaceLayoutOrientationVertical;
    _container.alignment = NSLayoutAttributeLeading;
    _container.spacing = 6;
    [_container addArrangedSubview:_scroll];
    [_container addArrangedSubview:_buttonRow];
    [_scroll.widthAnchor constraintEqualToAnchor:_container.widthAnchor].active = YES;
    return self;
}

- (void)setExtra:(NSArray<NSView *> *)extra {
    _extra = [extra copy] ?: @[];
    NSArray<NSView *> *arranged = _buttonRow.arrangedSubviews;
    for (NSUInteger i = 1; i < arranged.count; i++) [arranged[i] removeFromSuperview];
    for (NSView *v in _extra) [_buttonRow addArrangedSubview:v];
}

/// Reloads the table and shows the empty message when there's nothing in it.
- (void)reload {
    [_table reloadData];
    _emptyLabel.hidden = _table.numberOfRows > 0;
}

@end

// MARK: - RebuildingPane

/// View controller whose content is rebuilt from scratch, used for panes whose rows depend on data.
@implementation RebuildingPane {
    id<NSObject> _observer;
}

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        _rebuildKeys = [NSSet setWithObject:@"*"];
    }
    return self;
}

- (void)loadView {
    self.view = [NSView new];
    [self rebuild];
    __weak RebuildingPane *weakSelf = self;
    _observer = [NSNotificationCenter.defaultCenter addObserverForName:BrookSettingsDidChangeNotification
                                                                object:nil
                                                                 queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
        id raw = note.userInfo[@"key"];
        NSString *key = [raw isKindOfClass:NSString.class] ? raw : @"*";
        RebuildingPane *self = weakSelf;
        if (!self || ![self.rebuildKeys containsObject:key]) return;
        [self rebuild];
    }];
}

- (void)dealloc {
    if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer];
}

- (NSView *)makeContent { return [NSView new]; }

- (void)rebuild {
    for (NSView *v in [self.view.subviews copy]) [v removeFromSuperview];
    NSView *content = [self makeContent];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:content];
    // Pinned top-centre only, never edge to edge: the content's size then can't force the window,
    // which resizes solely through NSTabViewController's animation to preferredContentSize.
    // (Edge pinning made switching to a bigger pane snap the window before that animation ran.)
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [content.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
    self.preferredContentSize = content.fittingSize;
}

@end
