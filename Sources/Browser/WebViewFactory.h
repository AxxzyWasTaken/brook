#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
// Needs Settings.h (AutoplayPolicy); included via Brook.h.

// BrookWebView is declared in BrowserTab.h and implemented in WebViewFactory.mm.

/// Posted with the web view as object and @{@"url": the link under the pointer, "" when none}.
FOUNDATION_EXPORT NSNotificationName const BrookHoveredLinkNotification;

@interface WebViewFactory : NSObject
/// Makes sites treat Brook like Safari (same engine), so nothing serves a degraded page.
@property (class, readonly) NSString *userAgentSuffix;   // "Version/26.0 Safari/605.1.15"
/// One shared content controller: scripts are compiled once and reused by every tab.
/// Created on first access (installs Autoconsent + Chrome Web Store handlers/scripts and Boosts).
@property (class, readonly) WKUserContentController *userContentController;
/// Swaps in the current Boosts and force-dark scripts. WebKit can only remove all scripts at once, so every
/// other script (including ones web extensions added) is put back as it was.
/// Pages pick up the change on their next load.
+ (void)reloadSiteScripts;
/// The one process pool every tab's configuration uses.
@property (class, readonly) WKProcessPool *processPool;
/// Website data for a space: its own store when it has a separate profile (non-nil), otherwise the shared one.
+ (WKWebsiteDataStore *)dataStoreForProfileID:(NSUUID *)profileID;
+ (WKWebViewConfiguration *)makeConfigurationWithProfileID:(NSUUID *)profileID autoplay:(AutoplayPolicy)autoplay;
@end
