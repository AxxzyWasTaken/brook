#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
// Other-directory headers come in via Brook.h (import order there).
#import "Controls.h"

/// ⌘F bar floating over the page. (EmptyStateView and ErrorView stay private to ContentAreaView.mm.)
@interface FindBar : NSView <NSSearchFieldDelegate>
@property (weak) WKWebView *webView;
- (void)focus;
- (void)close;
/// Forget the cached match count (the page changed).
- (void)invalidateCount;
- (void)searchForward:(BOOL)forward;
@end

/// The rounded "card" that hosts the current page.
@interface ContentAreaView : NSView
@property (readonly) FindBar *findBar;
@property (readonly) ToastView *toast;
@property (nonatomic, readonly, weak) WKWebView *webView;
@property (nonatomic, strong) NSColor *accentColor;   // default controlAccentColor
@property (nonatomic) CGFloat cornerRadius;           // default 12
/// How far in from each side the browser's own glass covers the card (the icon rail floats over
/// its edge). The page lays out in the part left showing, and its edge is extended under the
/// glass (NSBackgroundExtensionView); the card's own messages stay in the part left showing too.
@property (nonatomic, readonly) NSEdgeInsets coveredInsets;
/// Animated: slides with the enclosing NSAnimationContext group.
- (void)setCoveredInsets:(NSEdgeInsets)insets animated:(BOOL)animated;
/// tab may be nil (shows the empty state). With a split, the page beside it shows too (Split View).
- (void)showTab:(BrowserTab *)tab split:(TabSplit *)split spaceName:(NSString *)spaceName;
/// The same, with the tab's own split as the state has it.
- (void)showTab:(BrowserTab *)tab spaceName:(NSString *)spaceName;
- (void)tabChanged:(BrowserTab *)tab change:(TabChange)change;
- (void)showFind;
/// ⌘G / ⇧⌘G: opens the find bar on the current page if it is closed, then goes to the next match.
- (void)findAgain:(BOOL)forward;
/// Re-reads the page shadow, accent and loading-indicator settings.
- (void)applySettings;
/// The card's drop shadow, drawn apart from the card so the owner can keep it under glass the
/// card itself sits above. The owner places it (a sibling of the card, just below it, pinned to
/// its edges); the card styles it.
@property (readonly) NSView *shadowView;
/// The soft shade Liquid Glass casts on what's beside it, drawn along one side of the card for
/// glass ordered under the card (which then can't cast it on the card). `gap` is the space
/// between the glass and the card.
- (void)setGlassShade:(BOOL)on onRight:(BOOL)right gap:(CGFloat)gap;
@end
