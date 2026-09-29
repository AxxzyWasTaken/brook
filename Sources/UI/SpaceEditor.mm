#import "Brook.h"

// NSColor.hexString lives in Utilities.mm as -[NSColor brook_hexString].

/// Round colour swatch used in the space editor.
@interface SwatchButton : HoverControl
@property (readonly, copy) NSString *hex;
@property (nonatomic) BOOL isChosen;
- (instancetype)initWithHex:(NSString *)hex name:(NSString *)name;
@end

@implementation SwatchButton

- (instancetype)initWithHex:(NSString *)hex name:(NSString *)name {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 22, 22)])) {
        _hex = [hex copy];
        self.toolTip = name;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self.widthAnchor constraintEqualToConstant:22].active = YES;
        [self.heightAnchor constraintEqualToConstant:22].active = YES;
    }
    return self;
}

- (void)setIsChosen:(BOOL)isChosen {
    _isChosen = isChosen;
    self.needsDisplay = YES;
}

- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityRadioButtonRole; }
- (id)accessibilityValue { return @(_isChosen); }

- (void)updateLayer {
    CALayer *layer = self.layer;
    if (!layer) return;
    layer.cornerRadius = 11;
    layer.backgroundColor = ([NSColor brook_colorWithHex:_hex] ?: NSColor.grayColor).CGColor;
    layer.borderWidth = _isChosen ? 2.5 : (self.isHovering ? 1.5 : 0);
    layer.borderColor = [self brook_cg:_isChosen ? NSColor.labelColor : NSColor.tertiaryLabelColor];
    layer.opacity = self.isPressed ? 0.7f : 1;
}

@end

/// "Any colour" swatch: a conic rainbow ring; filled with the custom colour once one is picked.
@interface RainbowSwatch : HoverControl
@property (nonatomic, strong) NSColor *chosenColor;
@end

@implementation RainbowSwatch {
    CAGradientLayer *_ring;
    CALayer *_dot;
}

- (instancetype)init {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 22, 22)])) {
        _ring = [CAGradientLayer layer];
        _dot = [CALayer layer];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self.widthAnchor constraintEqualToConstant:22].active = YES;
        [self.heightAnchor constraintEqualToConstant:22].active = YES;
        _ring.type = kCAGradientLayerConic;
        _ring.startPoint = CGPointMake(0.5, 0.5);
        _ring.endPoint = CGPointMake(0.5, 0);
        NSMutableArray *colors = [NSMutableArray array];
        for (NSColor *c in @[NSColor.systemRedColor, NSColor.systemOrangeColor, NSColor.systemYellowColor,
                             NSColor.systemGreenColor, NSColor.systemTealColor, NSColor.systemBlueColor,
                             NSColor.systemPurpleColor, NSColor.systemPinkColor, NSColor.systemRedColor]) {
            [colors addObject:(__bridge id)c.CGColor];
        }
        _ring.colors = colors;
        _ring.cornerRadius = 11;
        _ring.frame = self.bounds;
        [self.layer addSublayer:_ring];
        _dot.frame = NSInsetRect(self.bounds, 5, 5);
        _dot.cornerRadius = 6;
        [self.layer addSublayer:_dot];
    }
    return self;
}

- (void)setChosenColor:(NSColor *)chosenColor {
    _chosenColor = chosenColor;
    self.needsDisplay = YES;
}

- (void)updateLayer {
    CALayer *layer = self.layer;
    if (!layer) return;
    layer.cornerRadius = 11;
    layer.borderWidth = _chosenColor ? 2.5 : (self.isHovering ? 1.5 : 0);
    layer.borderColor = [self brook_cg:_chosenColor ? NSColor.labelColor : NSColor.tertiaryLabelColor];
    layer.opacity = self.isPressed ? 0.7f : 1;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _dot.backgroundColor = (_chosenColor ?: NSColor.windowBackgroundColor).CGColor;
    [CATransaction commit];
}

@end

/// Accessory view for the New/Edit Space sheet.
@implementation SpaceEditorView {
    NSMutableArray<SwatchButton *> *_swatches;
    RainbowSwatch *_custom;
    BOOL _colorPanelAttached;
    NSPopUpButton *_engine;
    NSButton *_profile;
    NSString *_colorHex;
    NSPopUpButton *_theme;
    NSPopUpButton *_layout;
    NSPopUpButton *_pinnedClose;
    NSPopUpButton *_archive;
}

static const NSInteger kArchiveChoices[] = {12, 24, 72, 168, 720};

/// A popup whose first item is "Default (<global value>)" and the rest are titles; -1 = default.
static NSPopUpButton *OverridePopup(NSString *defaultTitle, NSArray<NSString *> *titles, NSInteger selected) {
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [p addItemWithTitle:[NSString stringWithFormat:@"Default (%@)", defaultTitle]];
    for (NSString *t in titles) [p addItemWithTitle:t];
    [p selectItemAtIndex:selected + 1];
    p.controlSize = NSControlSizeSmall;
    p.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    return p;
}

static NSString *ArchiveTitle(NSInteger hours) {
    if (hours == 0) return @"Never";
    if (hours % 24 == 0) return hours == 24 ? @"After a day" : [NSString stringWithFormat:@"After %ld days", (long)(hours / 24)];
    return [NSString stringWithFormat:@"After %ld hours", (long)hours];
}

- (instancetype)initWithDraft:(SpaceDraft)draft {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 300, 170)])) {
        _nameField = [[NSTextField alloc] init];
        _swatches = [NSMutableArray array];
        _custom = [[RainbowSwatch alloc] init];
        _engine = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        _profile = [NSButton checkboxWithTitle:@"Use a separate profile" target:nil action:nil];
        _colorHex = [draft.colorHex copy] ?: @"";

        _nameField.placeholderString = @"Name";
        _nameField.stringValue = draft.name ?: @"";

        __weak SpaceEditorView *weakSelf = self;
        NSStackView *swatchRow = [[NSStackView alloc] init];
        swatchRow.spacing = 6;
        for (NSArray<NSString *> *c in Palette.spaceColors) {
            NSString *name = c[0], *hex = c[1];
            SwatchButton *b = [[SwatchButton alloc] initWithHex:hex name:name];
            b.onClick = ^{ [weakSelf choose:hex]; };
            [_swatches addObject:b];
            [swatchRow addArrangedSubview:b];
        }
        // A round rainbow swatch after the presets opens the system colour panel for any colour.
        _custom.onClick = ^{ [weakSelf openColorPanel]; };
        _custom.toolTip = @"Custom colour…";
        NSView *spacer = [[NSView alloc] init];
        [spacer.widthAnchor constraintEqualToConstant:4].active = YES;
        [swatchRow addArrangedSubview:spacer];
        [swatchRow addArrangedSubview:_custom];

        [_engine addItemWithTitle:[NSString stringWithFormat:@"Default (%@)", SearchEngines.defaultEngine.name]];
        _engine.lastItem.representedObject = nil;
        // Items go into the menu directly: NSPopUpButton's addItemWithTitle: drops an earlier item with the
        // same title, and two engines can have the same name.
        for (SearchEngine *e in SearchEngines.all) {
            NSMenuItem *item = [_engine.menu addItemWithTitle:e.name action:nil keyEquivalent:@""];
            item.representedObject = e.identifier;
            if (draft.searchEngineID && [e.identifier isEqualToString:draft.searchEngineID]) [_engine selectItem:item];
        }

        _profile.state = draft.separateProfile ? NSControlStateValueOn : NSControlStateValueOff;
        NSTextField *profileNote = [NSTextField wrappingLabelWithString:
            @"Keeps this space’s cookies, logins and site data apart from your other spaces. Favorites always use your main profile."];
        profileNote.font = [NSFont systemFontOfSize:11];
        profileNote.textColor = NSColor.secondaryLabelColor;
        profileNote.preferredMaxLayoutWidth = 280;

        NSTextField *engineLabel = [NSTextField labelWithString:@"Search with"];
        NSStackView *engineRow = [NSStackView stackViewWithViews:@[engineLabel, _engine]];
        engineRow.spacing = 8;

        // Per-space overrides of the global settings.
        NSMutableArray<NSString *> *themes = [NSMutableArray array], *layouts = [NSMutableArray array],
                                   *closes = [NSMutableArray array], *archives = [NSMutableArray arrayWithObject:@"Never"];
        for (NSInteger i = 0; i < ThemeModeCount; i++) [themes addObject:ThemeModeTitle((ThemeMode)i)];
        for (NSInteger i = 0; i < TabLayoutCount; i++) [layouts addObject:TabLayoutTitle((TabLayout)i)];
        for (NSInteger i = 0; i < PinnedCloseBehaviorCount; i++) [closes addObject:PinnedCloseBehaviorTitle((PinnedCloseBehavior)i)];
        NSInteger archiveIndex = draft.archiveHours == 0 ? 0 : -1;
        for (size_t i = 0; i < std::size(kArchiveChoices); i++) {
            [archives addObject:ArchiveTitle(kArchiveChoices[i])];
            if (kArchiveChoices[i] == draft.archiveHours) archiveIndex = (NSInteger)i + 1;
        }
        _theme = OverridePopup(ThemeModeTitle(Settings.theme), themes, draft.theme);
        _layout = OverridePopup(TabLayoutTitle(Settings.tabLayout), layouts, draft.tabLayout);
        _pinnedClose = OverridePopup(PinnedCloseBehaviorTitle(Settings.pinnedClose), closes, draft.pinnedClose);
        _archive = OverridePopup(ArchiveTitle(Settings.archiveHours), archives, archiveIndex);
        NSGridView *overrides = [NSGridView gridViewWithViews:@[
            @[[NSTextField labelWithString:@"Appearance"], _theme],
            @[[NSTextField labelWithString:@"Tabs"], _layout],
            @[[NSTextField labelWithString:@"Closing a pinned tab"], _pinnedClose],
            @[[NSTextField labelWithString:@"Archive tabs"], _archive],
        ]];
        overrides.rowSpacing = 6;
        overrides.columnSpacing = 8;
        [overrides columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
        for (NSInteger r = 0; r < overrides.numberOfRows; r++) {
            [overrides rowAtIndex:r].rowAlignment = NSGridRowAlignmentFirstBaseline;
            NSTextField *label = (NSTextField *)[overrides cellAtColumnIndex:0 rowIndex:r].contentView;
            label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
            label.textColor = NSColor.secondaryLabelColor;
            // Labels keep their full width; the popups give way (with an ellipsis) instead.
            [label setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];
        }
        for (NSPopUpButton *p in @[_theme, _layout, _pinnedClose, _archive]) {
            [p.cell setLineBreakMode:NSLineBreakByTruncatingTail];
            [p setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
            [p.widthAnchor constraintLessThanOrEqualToConstant:190].active = YES;
        }

        NSStackView *stack = [NSStackView stackViewWithViews:@[_nameField, swatchRow, engineRow, _profile, profileNote, overrides]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 10;
        [stack setCustomSpacing:4 afterView:_profile];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_nameField.widthAnchor constraintEqualToConstant:300],
            [profileNote.widthAnchor constraintEqualToConstant:290]
        ]];
        [self choose:_colorHex];
        [self layoutSubtreeIfNeeded];
        [self setFrameSize:NSMakeSize(300, stack.fittingSize.height)];
    }
    return self;
}

- (void)choose:(NSString *)hex {
    _colorHex = [hex copy];
    BOOL preset = NO;
    for (SwatchButton *s in _swatches) {
        s.isChosen = [s.hex caseInsensitiveCompare:hex] == NSOrderedSame;
        preset = preset || s.isChosen;
    }
    _custom.chosenColor = preset ? nil : [NSColor brook_colorWithHex:hex];
}

- (void)openColorPanel {
    NSColorPanel *panel = NSColorPanel.sharedColorPanel;
    panel.showsAlpha = NO;
    panel.color = [NSColor brook_colorWithHex:_colorHex] ?: NSColor.systemPurpleColor;
    [panel setTarget:self];
    [panel setAction:@selector(colorPanelChanged:)];
    _colorPanelAttached = YES;
    [panel orderFront:nil];
}

- (void)colorPanelChanged:(NSColorPanel *)panel {
    [self choose:panel.color.brook_hexString];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    // Detach from the shared panel when the sheet closes so it doesn't message a dead view.
    if (!newWindow && _colorPanelAttached) {
        _colorPanelAttached = NO;
        [NSColorPanel.sharedColorPanel setTarget:nil];
        [NSColorPanel.sharedColorPanel setAction:nil];
        [NSColorPanel.sharedColorPanel orderOut:nil];
    }
    [super viewWillMoveToWindow:newWindow];
}

- (SpaceDraft)draft {
    id rep = _engine.selectedItem.representedObject;
    SpaceDraft d;
    d.name = BrookTrim(_nameField.stringValue);
    d.colorHex = _colorHex;
    d.searchEngineID = [rep isKindOfClass:NSString.class] ? rep : nil;
    d.separateProfile = _profile.state == NSControlStateValueOn;
    d.theme = _theme.indexOfSelectedItem - 1;
    d.tabLayout = _layout.indexOfSelectedItem - 1;
    d.pinnedClose = _pinnedClose.indexOfSelectedItem - 1;
    NSInteger a = _archive.indexOfSelectedItem;   // 0 default, 1 never, then the choices
    d.archiveHours = a <= 0 ? -1 : a == 1 ? 0 : kArchiveChoices[a - 2];
    return d;
}

@end
