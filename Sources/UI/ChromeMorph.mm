#import "Brook.h"

/// A critically damped spring's step response (Apple's damping 1.0): no overshoot.
static CGFloat Spring(CFTimeInterval t, CFTimeInterval response) {
    if (t <= 0) return 0;
    CGFloat w = 2 * M_PI / response;
    return 1 - (1 + w * t) * std::exp(-w * t);
}

static CGFloat Ramp(CFTimeInterval t, CFTimeInterval start, CFTimeInterval length) {
    CGFloat x = std::clamp<CGFloat>((t - start) / length, 0, 1);
    return x * x * (3 - 2 * x);
}

/// How quickly each dimension reaches its new size.
static const CFTimeInterval kResponse = 0.28;
/// The dimension that grows waits this long for the one that shrinks, so a sidebar draws up into
/// its corner before stretching across, and a top bar narrows into the corner before dropping.
static const CFTimeInterval kLag = 0.07;
/// The outgoing picture fades out over the first stretch; the incoming one overlaps it slightly.
static const CFTimeInterval kFadeOut = 0.16;
static const CFTimeInterval kFadeInStart = 0.07, kFadeIn = 0.2;
/// Reduce Motion: no travel, a cross-fade in place.
static const CFTimeInterval kCrossFade = 0.22;

@interface ChromeMorphContainer : NSView
@end
@implementation ChromeMorphContainer
- (NSView *)hitTest:(NSPoint)point { return nil; }   // passes clicks through while it plays
@end

@implementation ChromeMorph {
    NSView *_host;
    NSGlassEffectView *_glass;
    NSView *_clip;
    NSImageView *_outgoing, *_incoming;
    NSRect _outgoingFrame, _incomingFrame;
    CGFloat _outgoingAlpha;
    NSRect _from;
    BOOL _reduceMotion;
    CADisplayLink *_link;
    CFTimeInterval _start;
    NSRect (^_target)(void);
    NSImage * (^_incomingPicture)(void);
    NSRect (^_incomingFrameBlock)(void);
    void (^_progress)(CGFloat, CGFloat);
    void (^_completion)(void);
    CFTimeInterval _widthDelay, _heightDelay;
}

- (instancetype)initInView:(NSView *)host
                     above:(NSView *)below
                     frame:(NSRect)frame
                   picture:(NSImage *)picture
              pictureFrame:(NSRect)pictureFrame
                     alpha:(CGFloat)alpha
              cornerRadius:(CGFloat)radius {
    if ((self = [super init])) {
        _host = host;
        _from = frame;
        _outgoingFrame = pictureFrame;
        _outgoingAlpha = alpha;
        _reduceMotion = BrookReduceMotion();
        _glass = [[NSGlassEffectView alloc] initWithFrame:frame];
        _glass.cornerRadius = radius;
        _clip = [ChromeMorphContainer new];
        _clip.wantsLayer = YES;
        _clip.layer.masksToBounds = YES;
        _clip.layer.cornerRadius = radius;
        _glass.contentView = _clip;
        [host addSubview:_glass positioned:NSWindowAbove relativeTo:below];
        _outgoing = [self imageViewWith:picture];
        _outgoing.alphaValue = alpha;
        // Reduce Motion: the old chrome fades where it stood, not clipped by the new glass.
        if (_reduceMotion) {
            [_outgoing removeFromSuperview];
            [host addSubview:_outgoing positioned:NSWindowAbove relativeTo:_glass];
            _outgoing.frame = pictureFrame;
        }
        _incoming = [self imageViewWith:nil];
        _incoming.alphaValue = 0;
        [self layoutPictures];
    }
    return self;
}

- (NSImageView *)imageViewWith:(NSImage *)image {
    NSImageView *v = [NSImageView imageViewWithImage:image ?: [NSImage new]];
    v.imageScaling = NSImageScaleNone;
    v.imageAlignment = NSImageAlignTopLeft;
    [_clip addSubview:v];
    return v;
}

- (NSGlassEffectView *)glass { return _glass; }
- (NSRect)frame { return _glass.frame; }

- (BOOL)incomingShowsMore { return _incoming.image.isValid && _incoming.alphaValue > _outgoing.alphaValue; }
- (NSImage *)visiblePicture { return self.incomingShowsMore ? _incoming.image : (_outgoing.image.isValid ? _outgoing.image : nil); }
- (NSRect)visiblePictureFrame { return self.incomingShowsMore ? _incomingFrame : _outgoingFrame; }
- (CGFloat)visiblePictureAlpha { return self.incomingShowsMore ? _incoming.alphaValue : _outgoing.alphaValue; }

/// The pictures sit where the chrome they show stands in the window; the glass moving around
/// them reveals or crops them.
- (void)layoutPictures {
    NSPoint o = _glass.frame.origin;
    _clip.frame = _glass.bounds;
    if (!_reduceMotion) _outgoing.frame = NSOffsetRect(_outgoingFrame, -o.x, -o.y);
    _incoming.frame = NSOffsetRect(_incomingFrame, -o.x, -o.y);
}

- (void)runToTarget:(NSRect (^)(void))target
           incoming:(NSImage *(^)(void))incoming
      incomingFrame:(NSRect (^)(void))incomingFrame
           progress:(void (^)(CGFloat, CGFloat))progress
         completion:(void (^)(void))completion {
    _target = [target copy];
    _incomingPicture = [incoming copy];
    _incomingFrameBlock = [incomingFrame copy];
    _progress = [progress copy];
    _completion = [completion copy];
    NSRect to = target();
    BOOL widthShrinks = NSWidth(to) < NSWidth(_from) - 0.5, heightShrinks = NSHeight(to) < NSHeight(_from) - 0.5;
    BOOL widthGrows = NSWidth(to) > NSWidth(_from) + 0.5, heightGrows = NSHeight(to) > NSHeight(_from) + 0.5;
    _widthDelay = widthGrows && heightShrinks ? kLag : 0;
    _heightDelay = heightGrows && widthShrinks ? kLag : 0;
    _start = CACurrentMediaTime();
    _link = [_host displayLinkWithTarget:self selector:@selector(tick:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval t = CACurrentMediaTime() - _start;
    if (_incomingPicture) {
        // Asked on the first frame, once the new chrome has been laid out and filled.
        _incoming.image = _incomingPicture() ?: [NSImage new];
        _incomingFrame = _incomingFrameBlock();
        _incomingPicture = nil;
    }
    NSRect to = _target();
    CGFloat pw, ph;
    BOOL settled;
    if (_reduceMotion) {
        pw = ph = 1;
        CGFloat f = Ramp(t, 0, kCrossFade);
        _outgoing.alphaValue = _outgoingAlpha * (1 - f);
        _incoming.alphaValue = f;
        _glass.alphaValue = NSIsEmptyRect(_from) ? f : 1;
        settled = t >= kCrossFade;
    } else {
        pw = Spring(t - _widthDelay, kResponse);
        ph = Spring(t - _heightDelay, kResponse);
        _outgoing.alphaValue = _outgoingAlpha * (1 - Ramp(t, 0, kFadeOut));
        _incoming.alphaValue = Ramp(t, kFadeInStart, kFadeIn);
        // Landed once every edge is within half a point: the hand-off to the real chrome can't jump.
        CGFloat left = std::max(std::abs(NSWidth(to) - NSWidth(_from)) * (1 - pw),
                                std::abs(NSHeight(to) - NSHeight(_from)) * (1 - ph));
        left = std::max<CGFloat>({left, std::abs(NSMinX(to) - NSMinX(_from)) * (1 - pw),
                                  std::abs(NSMaxY(to) - NSMaxY(_from)) * (1 - ph)});
        settled = t > kFadeInStart + kFadeIn && left < 0.5;
        if (settled) pw = ph = 1;
    }
    // Each edge travels with its own dimension, so whichever corner the two frames share stays put.
    auto mix = [](CGFloat a, CGFloat b, CGFloat p) { return a + (b - a) * p; };
    CGFloat minX = mix(NSMinX(_from), NSMinX(to), pw), maxX = mix(NSMaxX(_from), NSMaxX(to), pw);
    CGFloat minY = mix(NSMinY(_from), NSMinY(to), ph), maxY = mix(NSMaxY(_from), NSMaxY(to), ph);
    _glass.frame = NSMakeRect(minX, minY, std::max<CGFloat>(0, maxX - minX), std::max<CGFloat>(0, maxY - minY));
    [self layoutPictures];
    // The page moves with whichever dimension leads, in one motion, sliding under the glass.
    if (_progress) _progress(std::max(pw, ph), _incoming.alphaValue);
    if (settled) {
        void (^completion)(void) = _completion;
        [self stop];
        if (completion) completion();
    }
}

- (void)stop {
    [_link invalidate];
    _link = nil;
    _completion = nil;
    _progress = nil;
    _target = nil;
    _incomingPicture = nil;
    _incomingFrameBlock = nil;
    [_glass removeFromSuperview];
    if (_outgoing.superview != _clip) [_outgoing removeFromSuperview];
}

+ (NSImage *)pictureOf:(NSView *)view {
    NSRect b = view.bounds;
    if (!view.window || NSIsEmptyRect(b) || view.isHiddenOrHasHiddenAncestor) return nil;
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:b];
    if (!rep) return nil;
    [view cacheDisplayInRect:b toBitmapImageRep:rep];
    NSImage *image = [[NSImage alloc] initWithSize:b.size];
    [image addRepresentation:rep];
    return image;
}

@end
