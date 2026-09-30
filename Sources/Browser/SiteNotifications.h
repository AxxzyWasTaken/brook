#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

/// Web notifications, posted as Mac notifications named by the site and wearing its icon.
///
/// A site asks (Notification.requestPermission) and is answered once, per origin, through SitePermissions.
/// What an allowed site then sends reaches Brook two ways, both outside WebKit's public API and each looked
/// up by name first, so a WebKit without them posts nothing and breaks nothing:
///  - a service worker's, through the website data store's private delegate (`_delegate`);
///  - a page's own `new Notification(...)`, through WebKit's C notification provider on the process pool.
/// A click brings the site's tab to the front and is passed back to the page or its worker, as in Chrome.
@interface SiteNotifications : NSObject
@property (class, readonly) SiteNotifications *shared;
/// Made the delegate of each persistent store tabs use.
- (void)attachStore:(WKWebsiteDataStore *)store;
/// Installs the page provider on the web view's process pool (once per pool).
- (void)providePageNotificationsFor:(WKWebView *)webView;
/// The first site allowed: macOS asks, once, whether Brook may notify.
- (void)authorize;
/// Tells pages already open what this origin is now allowed (Notification.permission), without a reload.
- (void)policyChangedFor:(NSString *)origin;
@end
