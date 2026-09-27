#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
// Other-directory headers come in via Brook.h (import order there).
#import "SidebarView.h"
#import "ContentAreaView.h"

// BrowserWindow, EdgeHotZone, ResizeHandle, DownloadsViewController and ClosureButtonTarget
// stay private to BrowserWindowController.mm.

/// The main browser window: sidebar + content card, and the app's commands.
@interface BrowserWindowController : NSWindowController <NSWindowDelegate, BrowserStateObserver>

/// Builds the window and becomes BrowserState.shared's observer.
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (readonly) SidebarView *sidebar;
@property (readonly) ContentAreaView *content;
@property (readonly) BOOL sidebarHidden;

/// Shows the window and the current tab (call once after BrowserState is loaded).
- (void)start;
/// Lines the back/forward buttons up with the traffic lights, whatever size macOS makes them.
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
/// Steps to the next/previous zoom level and remembers it for the site, like Safari.
- (void)zoomBy:(CGFloat)delta;
/// Back to the default zoom.
- (void)resetZoom;

// Site settings, downloads, extensions
- (void)showSiteInfo;
- (void)showDownloadsFromView:(NSView *)anchor;
- (void)showExtensionsMenu;
- (void)presentExtensionPopup:(WKWebExtensionAction *)action;
- (void)promptChromeWebStore;
- (void)promptInstallFile;

// Spaces
- (void)promptNewSpace;
- (void)promptEditSpace:(Space *)space;
- (void)confirmDeleteSpace:(Space *)space;
@end

/// The browser window, as seen by extensions. Implemented in ExtensionConformances.mm.
@interface BrowserWindowController (Extensions) <WKWebExtensionWindow>
@end
