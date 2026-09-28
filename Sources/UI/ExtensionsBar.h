#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "Controls.h"

@class BrowserTab;

/// Extension buttons with their own icons and badges, followed by a "…" button for the rest
/// (hidden or crowded-out extensions, installing and removing). Sits inside the sidebar's address
/// pill, or in a glass capsule beside the top bar's. It asks for room for every button but can be
/// squeezed; buttons that don't fit move into "…". (ExtensionButton stays private to
/// ExtensionsBar.mm.)
@interface ExtensionsBar : NSView
- (instancetype)initWithButtonSize:(CGFloat)buttonSize;
/// Top to bottom instead of right-aligned in a row (the icon rail), showing at most `maxVisible`
/// buttons before "…".
@property (nonatomic) BOOL vertical;
@property (nonatomic) NSUInteger maxVisible;
/// The hover shape of each button. Default: round (half the button size), for the top bar's
/// capsule; the sidebar sets its own buttons' radius so extensions match them.
@property (nonatomic) CGFloat buttonCornerRadius;
/// The tab whose extension state (icons, badges, enabled) the buttons show.
@property (nonatomic, weak) BrowserTab *tab;
/// The extension's own button if it's showing, else "…". Popups open from here.
- (NSView *)anchorForContext:(WKWebExtensionContext *)context;
/// Opens the "…" menu.
- (void)showMoreMenu;
@end
