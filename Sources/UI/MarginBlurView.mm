#import "Brook.h"

/// How far a continuous (squircle) corner of radius r reaches in from the card's straight edges.
static const CGFloat kContinuousCornerReach = 1.53;

/// One strip, in a backdrop group of its own. AppKit gives every behind-window blur in a window
/// the same capture group, so the WindowServer captures one rectangle spanning every strip: the
/// whole window again. A group per strip keeps each capture to its own strip. Core Animation's
/// backdrop group has no public setter, so it's set by key; if that key ever goes, the strips
/// share a capture, as before. AppKit makes the backdrop layer lazily (and may remake it), so
/// the name is checked after every window update: a pointer check once it's found.
@interface MarginStrip : NSVisualEffectView
@property (nonatomic, copy) NSString *groupName;
@end

@implementation MarginStrip {
    __weak CALayer *_backdrop;
}
- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    [super viewWillMoveToWindow:newWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidUpdateNotification object:nil];
    if (newWindow)
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(nameBackdrop) name:NSWindowDidUpdateNotification object:newWindow];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)layout {
    [super layout];
    [self nameBackdrop];
}
- (void)nameBackdrop {
    CALayer *found = _backdrop;
    if (!found || found.superlayer == nil) {
        found = nil;
        static Class backdrop = NSClassFromString(@"CABackdropLayer");
        if (!backdrop || !_groupName) return;
        NSMutableArray<CALayer *> *stack = [NSMutableArray array];
        if (CALayer *l = self.layer) [stack addObject:l];
        while (stack.count && !found) {
            CALayer *l = stack.lastObject;
            [stack removeLastObject];
            if ([l isKindOfClass:backdrop]) found = l;
            if (l.sublayers) [stack addObjectsFromArray:l.sublayers];
        }
        _backdrop = found;
    }
    if (!found) return;
    @try {
        if (![[found valueForKey:@"groupName"] isEqual:_groupName]) [found setValue:_groupName forKey:@"groupName"];
    } @catch (NSException *) {
    }
}
@end

@implementation MarginBlurView {
    NSArray<MarginStrip *> *_strips;   // leading, trailing, bottom, top
    __weak NSView *_card;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        NSMutableArray *strips = [NSMutableArray array];
        for (int i = 0; i < 4; i++) {
            MarginStrip *v = [MarginStrip new];
            v.groupName = [NSString stringWithFormat:@"BrookMargin.%p.%d", (__bridge void *)self, i];
            v.material = NSVisualEffectMaterialUnderWindowBackground;
            v.blendingMode = NSVisualEffectBlendingModeBehindWindow;
            v.state = NSVisualEffectStateFollowsWindowActiveState;
            [self addSubview:v];
            [strips addObject:v];
        }
        _strips = [strips copy];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)frameCard:(NSView *)card {
    if (NSView *old = _card) [NSNotificationCenter.defaultCenter removeObserver:self name:NSViewFrameDidChangeNotification object:old];
    _card = card;
    // The card slides (rail snap, layout morphs) by animated constraints: follow every step.
    card.postsFrameChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cardMoved:) name:NSViewFrameDidChangeNotification object:card];
    self.needsLayout = YES;
}

- (void)cardMoved:(NSNotification *)note { [self placeStrips]; }

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.needsLayout = YES;
}

- (void)layout {
    [super layout];
    [self placeStrips];
}

- (void)placeStrips {
    NSView *card = _card;
    NSRect b = self.bounds;
    NSRect c = card && card.superview ? [self convertRect:card.frame fromView:card.superview] : NSZeroRect;
    c = NSIntersectionRect(c, b);
    if (NSIsEmptyRect(c)) {
        _strips[0].frame = b;
        for (NSUInteger i = 1; i < _strips.count; i++) _strips[i].frame = NSZeroRect;
    } else {
        // The side strips run the full height and reach in under the card's rounded corners; top
        // and bottom fill between them.
        CGFloat k = std::ceil(_cornerRadius * kContinuousCornerReach);
        CGFloat left = std::min(NSMaxX(b), NSMinX(c) + k), right = std::max(NSMinX(b), NSMaxX(c) - k);
        NSRect frames[] = {
            NSMakeRect(NSMinX(b), NSMinY(b), left - NSMinX(b), b.size.height),
            NSMakeRect(right, NSMinY(b), NSMaxX(b) - right, b.size.height),
            NSMakeRect(left, NSMinY(b), std::max<CGFloat>(0, right - left), NSMinY(c) + k - NSMinY(b)),
            NSMakeRect(left, NSMaxY(c) - k, std::max<CGFloat>(0, right - left), NSMaxY(b) - NSMaxY(c) + k),
        };
        for (NSUInteger i = 0; i < _strips.count; i++) {
            NSRect f = NSIntersectionRect(frames[i], b);
            if (!NSEqualRects(_strips[i].frame, f)) _strips[i].frame = f;
        }
    }
    for (NSVisualEffectView *v in _strips) v.hidden = NSIsEmptyRect(v.frame);
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsLayout = YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    self.needsLayout = YES;
}

@end
