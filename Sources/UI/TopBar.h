#import <AppKit/AppKit.h>
// Other-directory headers come in via Brook.h (import order there).
#import "SidebarParts.h"

@class BrowserWindowController;

/// The tabs along the top (Settings → Appearance → Tabs → Top), shown in a glass panel like the
/// sidebar: a toolbar row beside the traffic lights (navigation, space, favorites capsule, address,
/// tools) and a Safari-style tab track below it. (TopTabView, TabStripView, SpaceChip,
/// FavoriteButton and FavoritesCapsule stay private to TopBar.mm.)
@interface TopBarView : NSView <BrowserChrome>
@property (nonatomic, weak) BrowserWindowController *browser;
@property (readonly) URLPillView *urlPill;
@property (readonly) ExtensionsBar *extensionsBar;
/// One row (Settings → Appearance → Tabs → Compact): no address pill; clicking the selected tab
/// edits its address in place.
@property (nonatomic) BOOL compact;
/// Compact: turns the selected tab into the address field. NO if it can't (then use the command bar).
- (BOOL)beginEditingAddress;
/// Where the site info popover points: the pill's site button, or (compact) the selected tab.
@property (readonly) NSView *siteInfoAnchor;
@end
