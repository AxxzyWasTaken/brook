#import "Brook.h"

/// Leading-aligned vertical stack with 1pt spacing.
static NSStackView *BrookVerticalStack(NSStackView *stack) {
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 1;
    return stack;
}

/// Popover shown from the lock icon in the address pill: this site's settings, one click away.
@implementation SiteInfoViewController {
    NSString *_host;
    BOOL _secure;
}

- (instancetype)initWithHost:(NSString *)host secure:(BOOL)secure {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _host = [SiteSettings keyForHost:host];
        _secure = secure;
    }
    return self;
}

- (void)loadView {
    NSString *host = _host;
    BOOL secure = _secure;
    SiteOverride *o = [SiteSettings overrideForHost:host];

    NSTextField *title = [NSTextField labelWithString:host];
    title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    // A long host ends with an ellipsis inside the 330-pt popover (like the Websites list), full host in the tooltip.
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    title.toolTip = host;
    [title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *status = [NSTextField labelWithString:secure ? @"Connection is secure" : @"Connection is not secure"];
    status.font = [NSFont systemFontOfSize:11];
    status.textColor = secure ? NSColor.secondaryLabelColor : NSColor.systemOrangeColor;
    NSImageView *icon = [NSImageView imageViewWithImage:
        [NSImage brook_symbol:secure ? @"lock.fill" : @"exclamationmark.triangle.fill" size:13] ?: [[NSImage alloc] init]];
    icon.contentTintColor = secure ? NSColor.secondaryLabelColor : NSColor.systemOrangeColor;
    NSStackView *header = [NSStackView stackViewWithViews:@[icon, BrookVerticalStack([NSStackView stackViewWithViews:@[title, status]])]];
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 8;

    SettingsForm *form = [[SettingsForm alloc] init];
    form.grid.rowSpacing = 8;

    // Zoom: nil (default) then fixed levels.
    std::vector<std::optional<double>> zooms = {std::nullopt, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 2};
    NSMutableArray<NSString *> *zoomTitles = [NSMutableArray array];
    NSInteger zoomSelected = 0;
    bool zoomFound = false;
    for (size_t i = 0; i < zooms.size(); i++) {
        const auto &z = zooms[i];
        if (z) {
            [zoomTitles addObject:[NSString stringWithFormat:@"%ld%%", (long)(NSInteger)(*z * 100)]];
            if (!zoomFound && o.zoom && std::abs(*z - o.zoom.doubleValue) < 0.01) {
                zoomSelected = (NSInteger)i;
                zoomFound = true;
            }
        } else {
            [zoomTitles addObject:[NSString stringWithFormat:@"Default (%ld%%)", (long)(NSInteger)(Settings.defaultZoom * 100)]];
        }
    }
    [form row:@"Zoom" view:[self popup:zoomTitles selected:zoomSelected onChange:^(NSInteger i) {
        std::optional<double> z = zooms[(size_t)i];
        [SiteSettings updateHost:host change:^(SiteOverride *ov) { ov.zoom = z ? @(*z) : nil; }];
    }]];

    // Tri-state: nil (default), true, false.
    NSArray *tri = @[NSNull.null, @YES, @NO];
    NSInteger (^triIndex)(NSNumber *) = ^NSInteger(NSNumber *v) {
        if (!v) return 0;
        return v.boolValue ? 1 : 2;
    };
    NSNumber * (^triValue)(NSInteger) = ^NSNumber *(NSInteger i) {
        id v = tri[(NSUInteger)i];
        return v == NSNull.null ? nil : v;
    };

    [form row:@"JavaScript" view:[self popup:@[[NSString stringWithFormat:@"Default (%@)", Settings.javascriptEnabled ? @"Allow" : @"Block"],
                                              @"Allow", @"Block"]
                                    selected:triIndex(o.javascript) onChange:^(NSInteger i) {
        [SiteSettings updateHost:host change:^(SiteOverride *ov) { ov.javascript = triValue(i); }];
    }]];

    NSMutableArray *autoplay = [NSMutableArray arrayWithObject:NSNull.null];
    NSMutableArray<NSString *> *autoplayTitles =
        [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"Default (%@)", AutoplayPolicyShortTitle(Settings.autoplay)]];
    for (NSInteger p = 0; p < AutoplayPolicyCount; p++) {
        [autoplay addObject:AutoplayPolicyRaw((AutoplayPolicy)p)];
        [autoplayTitles addObject:AutoplayPolicyShortTitle((AutoplayPolicy)p)];
    }
    NSInteger autoplaySelected = 0;
    for (NSUInteger i = 0; i < autoplay.count; i++) {
        id v = autoplay[i];
        if ((v == NSNull.null && !o.autoplay) || (v != NSNull.null && [o.autoplay isEqualToString:v])) {
            autoplaySelected = (NSInteger)i;
            break;
        }
    }
    [form row:@"Autoplay" view:[self popup:autoplayTitles selected:autoplaySelected onChange:^(NSInteger i) {
        id v = autoplay[(NSUInteger)i];
        [SiteSettings updateHost:host change:^(SiteOverride *ov) { ov.autoplay = v == NSNull.null ? nil : v; }];
    }]];

    [form row:@"Cookie popups" view:[self popup:@[[NSString stringWithFormat:@"Default (%@)", Settings.blockCookiePopups ? @"Decline" : @"Leave"],
                                                 @"Decline", @"Leave"]
                                       selected:triIndex(o.cookiePopups) onChange:^(NSInteger i) {
        [SiteSettings updateHost:host change:^(SiteOverride *ov) { ov.cookiePopups = triValue(i); }];
    }]];
    [form row:@"Ad blocking" view:[self popup:@[[NSString stringWithFormat:@"Default (%@)", Settings.blockAds ? @"On" : @"Off"],
                                               @"On", @"Off for this site"]
                                     selected:triIndex(o.blockAds) onChange:^(NSInteger i) {
        [SiteSettings updateHost:host change:^(SiteOverride *ov) { ov.blockAds = triValue(i); }];
    }]];
    [form row:@"Dark mode" view:[self popup:@[@"As the site draws it", @"Force dark"]
                                   selected:o.forceDark.boolValue ? 1 : 0 onChange:^(NSInteger i) {
        [SiteSettings updateHost:host change:^(SiteOverride *ov) { ov.forceDark = i == 1 ? @YES : nil; }];
    }]];
    NSMutableArray<NSString *> *agents = [NSMutableArray array];
    for (NSInteger a = 0; a < UserAgentChoiceCount; a++) [agents addObject:UserAgentChoiceTitle((UserAgentChoice)a)];
    agents[0] = @"Safari (default)";
    [form row:@"Identify as" view:[self popup:agents selected:[SiteSettings userAgentForHost:host] onChange:^(NSInteger i) {
        [SiteSettings updateHost:host change:^(SiteOverride *ov) {
            ov.userAgent = i == UserAgentChoiceSafari ? nil : UserAgentChoiceRaw((UserAgentChoice)i);
        }];
    }]];
    [form finish];
    [form.grid columnAtIndex:0].width = 96;
    // One width for every popup, filling the column so the right edge lines up with the Reload
    // button: the 330 stack less its 16 insets, the 96 label column and the grid's 12 spacing.
    const CGFloat popupWidth = 330 - 2 * 16 - 96 - form.grid.columnSpacing;
    for (NSView *v in form.grid.subviews) {
        if ([v isKindOfClass:NSPopUpButton.class]) {
            [v.widthAnchor constraintEqualToConstant:popupWidth].active = YES;
        }
    }

    NSMutableArray<Boost *> *boosts = [NSMutableArray array];
    for (Boost *b in [Boosts boostsForHost:host]) {
        if (![b.site isEqualToString:@"*"]) [boosts addObject:b];
    }
    BOOL noBoosts = boosts.count == 0;
    NSString *boostTitle = noBoosts ? @"Boost This Site…"
                                    : [NSString stringWithFormat:@"Edit Boost (%lu)…", (unsigned long)boosts.count];
    __weak SiteInfoViewController *weakSelf = self;
    NSButton *boost = [Controls button:boostTitle action:^{
        SiteInfoViewController *self = weakSelf;
        if (!self) return;
        if (noBoosts) {
            [Boosts save:[[Boost alloc] initWithName:self->_host site:self->_host
                                                 css:[NSString stringWithFormat:@"/* CSS for %@ */\n", self->_host]
                                                  js:@""]];
        }
        [self dismissController:nil];
        [SettingsWindowController.shared showPane:@"Boosts"];
    }];
    NSButton *reload = [Controls button:@"Reload" action:^{
        [weakSelf dismissController:nil];
        [BrowserState.shared.selectedTab reload];
    }];
    reload.keyEquivalent = @"\r";
    NSStackView *buttons = [NSStackView stackViewWithViews:@[boost, [[NSView alloc] init], reload]];
    buttons.distribution = NSStackViewDistributionFill;

    NSTextField *note = [NSTextField labelWithString:@"Changes apply when the page reloads."];
    note.font = [NSFont systemFontOfSize:11];
    note.textColor = NSColor.secondaryLabelColor;

    NSStackView *stack = [NSStackView stackViewWithViews:@[header, form.grid, note, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [buttons.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32].active = YES;
    [stack.widthAnchor constraintEqualToConstant:330].active = YES;
    self.view = stack;
}

- (NSPopUpButton *)popup:(NSArray<NSString *> *)titles selected:(NSInteger)selected onChange:(void (^)(NSInteger))onChange {
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [p addItemsWithTitles:titles];
    [p selectItemAtIndex:selected];
    [p brook_onAction:^(id c) { onChange([(NSPopUpButton *)c indexOfSelectedItem]); }];
    return p;
}

@end
