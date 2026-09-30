#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

typedef NS_ENUM(NSInteger, SitePermission) {
    SitePermissionLocation,
    SitePermissionNotifications,
};

/// What each site was told when it asked for your location or to send notifications, kept per origin
/// ("https://host[:port]") in Settings key "sitePermissions" ({origin: {"location": bool, ...}}), and the
/// question itself. (Camera and microphone answers stay with the tab that asked; see BrowserTab.)
@interface SitePermissions : NSObject
/// "scheme://host[:port]", the default port left out.
+ (NSString *)originForScheme:(NSString *)scheme host:(NSString *)host port:(NSInteger)port;
+ (NSString *)originOf:(WKSecurityOrigin *)origin;
/// @YES / @NO when the site was answered and the answer kept, else nil.
+ (NSNumber *)decisionFor:(SitePermission)permission origin:(NSString *)origin;
+ (void)setDecision:(NSNumber *)allowed for:(SitePermission)permission origin:(NSString *)origin;
/// Every origin with a kept answer for this permission.
+ (NSDictionary<NSString *, NSNumber *> *)decisionsFor:(SitePermission)permission;
/// Forgets every kept answer, so each site asks again.
+ (void)forgetAll;
/// Asks over the web view's window unless a kept answer decides it. Location offers Allow Once (not kept).
/// One question at a time: a second one while the first is up is refused.
+ (void)ask:(SitePermission)permission origin:(NSString *)origin host:(NSString *)host
     webView:(WKWebView *)webView completion:(void (^)(BOOL allowed))completion;
/// "location" or "notifications" (the JSON key).
+ (NSString *)keyFor:(SitePermission)permission;
@end
