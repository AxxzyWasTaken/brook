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
@end
