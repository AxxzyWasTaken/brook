#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Carries the tab chrome from one shape to another when the tab layout changes (sidebar, top
/// bar, compact bar). A stand-in sheet of glass reshapes from the old panel's frame into the new
/// one, each edge on a critically damped spring. When one dimension shrinks and the other grows,
/// the shrinking one leads: a sidebar draws up into its corner, then stretches across the top.
/// Pictures of the old and new chrome sit where that chrome stands, so the moving glass crops
/// one away and reveals the other while they cross-fade. With Reduce Motion it only cross-fades.
/// The caller keeps the real chrome hidden until `completion` and moves the page along with
/// `progress`.
@interface ChromeMorph : NSObject

/// Adds the glass to `host` above `below`, at `frame` (host coordinates), showing `picture` at
/// `pictureFrame` (host coordinates) and `alpha`.
- (instancetype)initInView:(NSView *)host
                     above:(NSView *)below
                     frame:(NSRect)frame
                   picture:(nullable NSImage *)picture
              pictureFrame:(NSRect)pictureFrame
                     alpha:(CGFloat)alpha
              cornerRadius:(CGFloat)radius;
- (instancetype)init NS_UNAVAILABLE;

/// The stand-in glass, for the caller to style like the real chrome.
@property (readonly) NSGlassEffectView *glass;
/// Where the glass is now, and whichever picture shows more (with its frame and opacity): where
/// a morph that interrupts this one starts from.
@property (readonly) NSRect frame;
@property (readonly, nullable) NSImage *visiblePicture;
@property (readonly) NSRect visiblePictureFrame;
@property (readonly) CGFloat visiblePictureAlpha;

/// Runs to `target` (asked every frame, so a window resize mid-way is followed). The new
/// chrome's picture and frame are asked for once, on the first frame, after it has laid out.
/// `progress` gets, each frame, how far the page should have moved (0...1, following whichever
/// dimension leads) and how far the new chrome has faded in.
- (void)runToTarget:(NSRect (^)(void))target
           incoming:(NSImage *_Nullable (^)(void))incoming
      incomingFrame:(NSRect (^)(void))incomingFrame
           progress:(void (^)(CGFloat move, CGFloat reveal))progress
         completion:(void (^)(void))completion;

/// Ends it where it is and removes the glass, without calling `completion`.
- (void)stop;

/// What `view` draws now, at the window's scale; nil when it isn't in a window or has no size.
+ (nullable NSImage *)pictureOf:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
