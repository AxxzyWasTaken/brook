#import <AppKit/AppKit.h>

/// The Fire button. (FireAnimationView stays private to Fire.mm.)
@interface Fire : NSObject
/// Asks, then closes regular tabs, resets pinned tabs, and wipes cookies, cache, storage and history.
/// window may be nil (runs the alert modally).
+ (void)confirmAndBurnInWindow:(NSWindow *)window overlayHost:(NSView *)overlayHost;
/// Burns without asking; plays the flame animation over overlayHost when non-nil.
+ (void)burnWithOverlayHost:(NSView *)overlayHost;
@end
