#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The window's behind-window blur, drawn only where it can be seen: four strips around the page
/// card instead of one sheet across the whole window. A sheet under the card still makes the
/// WindowServer capture and blur the desktop behind all of it on every frame the desktop moves
/// (a dynamic wallpaper, a video behind the window), though the opaque card hides that part.
@interface MarginBlurView : NSView
/// Lays the strips out around `card`, which must share this view's superview.
- (void)frameCard:(NSView *)card;
/// How far the card's corners curve in from its edges; the strips reach this far under the card
/// so the blur still fills the corners the card rounds off.
@property (nonatomic) CGFloat cornerRadius;
@end

NS_ASSUME_NONNULL_END
