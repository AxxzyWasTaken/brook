#import "Brook.h"

NSPasteboardType const BrookTabPasteboardType = @"app.brook.tab";

// MARK: - HoverControl

@interface HoverControl ()
@property (nonatomic, readwrite) BOOL isHovering;
@end

/// A lightweight clickable view with hover and press states, drawn with a single layer.
@implementation HoverControl {
    NSTrackingArea *_tracking;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _cornerRadius = 8;
        _hoverColor = Palette.rowHover;
        _baseColor = NSColor.clearColor;
        _highlightColor = Palette.rowSelected;
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    }
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.needsDisplay = YES;
    [self noteFocusRingMaskChanged];
}

- (void)setBaseColor:(NSColor *)baseColor {
    _baseColor = baseColor;
    self.needsDisplay = YES;
}

- (void)setIsHighlightedState:(BOOL)isHighlightedState {
    _isHighlightedState = isHighlightedState;
    self.needsDisplay = YES;
}

- (void)setIsHovering:(BOOL)isHovering {
    BOOL oldValue = _isHovering;
    _isHovering = isHovering;
    if (oldValue != isHovering) {
        [self hoverChanged];
        self.needsDisplay = YES;
    }
}

- (void)setIsPressed:(BOOL)isPressed {
    _isPressed = isPressed;
    self.needsDisplay = YES;
}

- (BOOL)wantsUpdateLayer { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)hoverChanged {}

- (void)updateLayer {
    CALayer *layer = self.layer;
    if (!layer) return;
    layer.cornerRadius = self.cornerRadius;
    layer.cornerCurve = kCACornerCurveContinuous;
    NSColor *color = self.baseColor;
    if (self.isHighlightedState) color = self.highlightColor;
    else if (self.isHovering && self.isEnabled) color = self.hoverColor;
    layer.backgroundColor = [self brook_cg:color];
    layer.opacity = self.isPressed ? 0.7 : 1;
    if (self.isHighlightedState) {
        layer.shadowColor = NSColor.blackColor.CGColor;
        layer.shadowOpacity = BrookIsDark(self.effectiveAppearance) ? 0 : 0.08;
        layer.shadowRadius = 2;
        layer.shadowOffset = CGSizeMake(0, -1);
    } else {
        layer.shadowOpacity = 0;
    }
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

- (void)mouseEntered:(NSEvent *)event { self.isHovering = YES; }
- (void)mouseExited:(NSEvent *)event { self.isHovering = NO; }

- (void)mouseDown:(NSEvent *)event {
    if (!self.isEnabled) return;
    self.isPressed = YES;
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.isPressed) return;
    self.isPressed = NO;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, self.bounds)) [self fire];
}

- (void)fire {
    if (self.onClick) self.onClick();
    SEL action = self.action;
    if (action) [NSApp sendAction:action to:self.target from:self];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

// MARK: Keyboard

- (BOOL)isActionable { return self.onClick != nil || self.action != nil; }

/// Keyboard focus only with Full Keyboard Access on (like NSButton), and never from a click:
/// clicking a toolbar button must leave the page's focus where it was.
- (BOOL)acceptsFirstResponder {
    if (!NSApp.isFullKeyboardAccessEnabled || !self.isActionable || !self.isEnabled) return NO;
    switch (NSApp.currentEvent.type) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown: return NO;
        default: return YES;
    }
}

- (BOOL)canBecomeKeyView { return self.acceptsFirstResponder && !self.isHiddenOrHasHiddenAncestor; }

- (void)keyDown:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    if (self.isEnabled && ([key isEqualToString:@" "] || [key isEqualToString:@"\r"])) [self fire];
    else [super keyDown:event];
}

- (void)performClick:(id)sender {
    if (self.isEnabled) [self fire];
}

- (NSRect)focusRingMaskBounds { return self.bounds; }

- (void)drawFocusRingMask {
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.cornerRadius yRadius:self.cornerRadius] fill];
}

// MARK: Accessibility

/// Decorative instances (a tab row's background, the address pill's magnifying glass with no
/// page open) do nothing when pressed and stay out of the tree.
- (BOOL)isAccessibilityElement { return self.isActionable && self.accessibilityLabel.length > 0; }

- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityButtonRole; }

/// An explicit label, else the tooltip without its shortcut: "Reload (⌘R)" reads "Reload".
- (NSString *)accessibilityLabel {
    NSString *label = [super accessibilityLabel];
    if (label.length) return label;
    NSString *tip = self.toolTip;
    NSRange open = [tip rangeOfString:@" (" options:NSBackwardsSearch];
    if (open.location != NSNotFound && [tip hasSuffix:@")"]) {
        NSString *inside = [tip substringFromIndex:open.location];
        if ([inside rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"⌘⌃⌥⇧"]].location != NSNotFound ||
            [inside isEqualToString:@" (esc)"]) {
            return [tip substringToIndex:open.location];
        }
    }
    return tip;
}

/// The shortcut, which the label leaves out. (NSView's own help is the whole tooltip, which
/// would just repeat the label.)
- (NSString *)accessibilityHelp {
    NSString *tip = self.toolTip, *label = self.accessibilityLabel;
    return tip.length && ![tip isEqualToString:label] ? tip : nil;
}

- (BOOL)isAccessibilityEnabled { return self.isEnabled; }

/// Buttons nested inside (the address pill's Site Settings and extensions, a tab's close
/// button). Only those: the icon and title are this button's label already.
- (NSArray *)accessibilityChildren {
    NSMutableArray *buttons = [NSMutableArray array];
    NSMutableArray<NSView *> *queue = [self.subviews mutableCopy];
    while (queue.count) {
        NSView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.isHidden) continue;
        if ([v isKindOfClass:HoverControl.class] || [v isKindOfClass:NSButton.class]) {
            if (v.isAccessibilityElement) [buttons addObject:v];
        } else {
            [queue addObjectsFromArray:v.subviews];
        }
    }
    return buttons;
}

- (BOOL)accessibilityPerformPress {
    if (!self.isEnabled) return NO;
    [self fire];
    return YES;
}

/// VoiceOver's "show menu" (VO-Shift-M) opens the same menu a right-click would.
- (BOOL)accessibilityPerformShowMenu {
    NSMenu *menu = [self menuForEvent:NSApp.currentEvent];
    if (!menu) return NO;
    // Below the control, like the other anchored menus, so the menu does not cover it.
    CGFloat y = self.isFlipped ? NSHeight(self.bounds) + 4 : -4;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, y) inView:self];
    return YES;
}

@end

// MARK: - IconButton

/// An SF Symbol button, Arc-style: no border, soft hover background.
@implementation IconButton

- (instancetype)initWithSymbol:(NSString *)symbol size:(CGFloat)size tooltip:(NSString *)tooltip
                     dimension:(CGFloat)dimension onClick:(void (^)(void))onClick {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, dimension, dimension)])) {
        _imageView = [NSImageView new];
        _tint = NSColor.secondaryLabelColor;
        self.onClick = onClick;
        self.toolTip = tooltip;
        self.cornerRadius = 7;
        _imageView.image = [NSImage brook_symbol:symbol size:size];
        _imageView.contentTintColor = NSColor.secondaryLabelColor;
        _imageView.imageScaling = NSImageScaleNone;
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_imageView];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:dimension],
            [self.heightAnchor constraintEqualToConstant:dimension],
            [_imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (instancetype)initWithSymbol:(NSString *)symbol tooltip:(NSString *)tooltip onClick:(void (^)(void))onClick {
    return [self initWithSymbol:symbol size:14 tooltip:tooltip dimension:28 onClick:onClick];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithSymbol:@"" size:14 tooltip:nil dimension:28 onClick:nil];
}

- (void)setTint:(NSColor *)tint {
    _tint = tint;
    [self hoverChanged];
}

- (void)setSymbol:(NSString *)name {
    [self setSymbol:name size:14];
}

- (void)setSymbol:(NSString *)name size:(CGFloat)size {
    self.imageView.image = [NSImage brook_symbol:name size:size];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.imageView.alphaValue = self.isEnabled ? 1 : 0.35;
}

- (void)hoverChanged {
    self.imageView.contentTintColor = self.isHovering && self.isEnabled ? NSColor.labelColor : self.tint;
}

@end

// MARK: - ToastView

/// Small rounded label that floats over the page for a moment.
@implementation ToastView {
    NSGlassEffectView *_glass;
    NSTextField *_label;
    dispatch_block_t _hideWork;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _glass = [NSGlassEffectView new];
        _label = [NSTextField labelWithString:@""];
        self.alphaValue = 0;
        _glass.cornerRadius = 16;
        _glass.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_glass];
        [_glass brook_pinEdgesTo:self];
        NSView *inner = [NSView new];
        _label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _label.textColor = NSColor.labelColor;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [inner addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:inner.leadingAnchor constant:16],
            [_label.trailingAnchor constraintEqualToAnchor:inner.trailingAnchor constant:-16],
            [_label.topAnchor constraintEqualToAnchor:inner.topAnchor constant:8],
            [_label.bottomAnchor constraintEqualToAnchor:inner.bottomAnchor constant:-8],
        ]];
        _glass.contentView = inner;
        [inner brook_pinEdgesTo:self];
    }
    return self;
}

- (NSView *)hitTest:(NSPoint)point { return nil; }

// The label shows only for a moment and holds the last message after; VoiceOver hears each
// message as an announcement instead of finding a stale label.
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren { return nil; }

- (void)showText:(NSString *)text {
    _label.stringValue = text;
    NSAccessibilityPostNotificationWithUserInfo(NSApp, NSAccessibilityAnnouncementRequestedNotification, @{
        NSAccessibilityAnnouncementKey: text ?: @"",
        NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium),
    });
    if (_hideWork) dispatch_block_cancel(_hideWork);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.18;
        self.animator.alphaValue = 1;
    }];
    __weak ToastView *weakSelf = self;
    dispatch_block_t work = dispatch_block_create((dispatch_block_flags_t)0, ^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.3;
            weakSelf.animator.alphaValue = 0;
        }];
    });
    _hideWork = work;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), work);
}

@end
