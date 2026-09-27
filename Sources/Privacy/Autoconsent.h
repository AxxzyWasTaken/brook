#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

/// Downloads DuckDuckGo's public privacy configuration, which carries the
/// cookie-popup rule list, and keeps a cached copy on disk.
@interface PrivacyConfigStore : NSObject
@property (class, readonly) PrivacyConfigStore *shared;
/// The "compactRuleList" JSON object, if any.
@property (readonly) id compactRules;
@property (readonly) NSArray<NSString *> *disabledCMPs;
@property (readonly) BOOL enabled;   // default YES
/// Applies the cached copy, then refreshes in the background.
- (void)load;
/// Re-downloads when the cache is older than a day (async, fire and forget).
- (void)refreshIfNeeded;
- (BOOL)isExceptedHost:(NSString *)host;
@end

/// Native side of DuckDuckGo's autoconsent script, which finds cookie consent
/// popups and clicks "reject" for you. Mirrors DuckDuckGo's AutoconsentUserScript.
@interface AutoconsentHandler : NSObject <WKScriptMessageHandlerWithReply>
@property (class, readonly) AutoconsentHandler *shared;
/// autoconsent-bundle.js from the app bundle (lazy; nil if missing).
@property (readonly) WKUserScript *userScript;
- (void)installHandlersInto:(WKUserContentController *)ucc;
@end
