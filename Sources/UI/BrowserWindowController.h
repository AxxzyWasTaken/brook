#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
// Other-directory headers come in via Brook.h (import order there).
#import "SidebarView.h"
#import "TopBar.h"
#import "ContentAreaView.h"

@class CommandBarController;

// BrowserWindow, EdgeHotZone, ResizeHandle and the downloads popover stay private to
// BrowserWindowController.mm.

/// The main browser window: sidebar (or top bar) + content card, and the app's commands.
@interface BrowserWindowController : NSWindowController <NSWindowDelegate, BrowserStateObserver>

/// Builds the window and becomes BrowserState.shared's observer.
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (readonly) SidebarView *sidebar;
@property (readonly) ContentAreaView *content;
@property (readonly) BOOL sidebarHidden;
/// The icon rail's address field is open beside the selected tab.
@property (readonly) BOOL railAddressEditing;
/// Settings → Appearance → Tab layout is Top or Compact: the top bar shows instead of the sidebar.
@property (readonly) BOOL tabsOnTop;
/// The ⌘T / ⌘L bar; compact tabs also use its suggestions list under the tab being edited.
@property (readonly) CommandBarController *commandBar;

/// Shows the window and the current tab (call once after BrowserState is loaded).
- (void)start;
/// Lines the row beside the traffic lights up with them, whatever size macOS makes them.
- (void)alignNavRow;

// Sidebar
- (void)toggleSidebar;

// Commands
- (void)showCommandBarEditing:(BOOL)editing;
/// ⌘T and the sidebar's New Tab row, following Settings → General → New tabs show.
- (void)newTab;
- (void)goBack;
- (void)goForward;
- (void)reloadOrStop;
- (void)fire;
- (void)showToast:(NSString *)text;
- (void)showError:(NSError *)error;
- (void)showFind;
- (void)copyURL;
/// The share menu for the current page, under anchor.
- (void)shareFromView:(NSView *)anchor;
/// Shows the page's article in a clean reading view, or goes back to the page.
- (void)toggleReader;
/// Steps to the next/previous zoom level and remembers it for the site, like Safari.
- (void)zoomBy:(CGFloat)delta;
/// Back to the default zoom.
- (void)resetZoom;

// Site settings, downloads, extensions
- (void)showSiteInfo;
- (void)showDownloadsFromView:(NSView *)anchor;
- (void)presentExtensionPopup:(WKWebExtensionAction *)action;
- (void)promptChromeWebStore;
- (void)promptInstallFile;

// Context menus, shared by the sidebar and the top bar
- (NSMenu *)menuForTab:(BrowserTab *)tab;
/// Edit, move and delete one space.
- (NSMenu *)menuForSpace:(Space *)space;
/// Every space to switch to, New Space, then the current space's own items.
- (NSMenu *)spacesMenu;

// Spaces
- (void)promptNewSpace;
- (void)promptEditSpace:(Space *)space;
- (void)confirmDeleteSpace:(Space *)space;
@end

/// The browser window, as seen by extensions. Implemented in ExtensionConformances.mm.
@interface BrowserWindowController (Extensions) <WKWebExtensionWindow>
@end
