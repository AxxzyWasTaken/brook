#import "Brook.h"

NSNotificationName const BrookHoveredLinkNotification = @"BrookHoveredLink";

/// Reports the link under the pointer, for the link preview.
@interface HoveredLinkHandler : NSObject <WKScriptMessageHandler>
@end

@implementation HoveredLinkHandler
- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    NSString *url = [message.body isKindOfClass:NSString.class] ? message.body : @"";
    [NSNotificationCenter.defaultCenter postNotificationName:BrookHoveredLinkNotification object:message.webView
                                                    userInfo:@{@"url": url}];
}
@end

@implementation WebViewFactory

static WKUserScript *sBoostScript;
static WKUserScript *sDarkScript;

/// Makes sites treat Brook like Safari (same engine), so nothing serves a degraded page.
+ (NSString *)userAgentSuffix { return @"Version/26.0 Safari/605.1.15"; }

/// One shared content controller: scripts are compiled once and reused by every tab.
+ (WKUserContentController *)userContentController {
    static WKUserContentController *ucc;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ucc = [WKUserContentController new];
        [AutoconsentHandler.shared installHandlersInto:ucc];
        [ChromeWebStoreBridge.shared installHandlersInto:ucc];
        WKContentWorld *linkWorld = [WKContentWorld worldWithName:@"BrookLinks"];
        [ucc addScriptMessageHandler:[HoveredLinkHandler new] contentWorld:linkWorld name:@"brookLink"];
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:
            @"(function () {\n"
             "  var last = '';\n"
             "  function send(u) { if (u !== last) { last = u; webkit.messageHandlers.brookLink.postMessage(u); } }\n"
             "  document.addEventListener('mouseover', function (e) {\n"
             "    var a = e.target.closest && e.target.closest('a[href]');\n"
             "    send(a && a.href && !a.href.startsWith('javascript:') ? a.href : '');\n"
             "  }, true);\n"
             "  document.addEventListener('mouseleave', function () { send(''); });\n"
             "})();"
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES inContentWorld:linkWorld]];
        if (WKUserScript *s = AutoconsentHandler.shared.userScript) [ucc addUserScript:s];
        if (WKUserScript *s = ChromeWebStoreBridge.shared.userScript) [ucc addUserScript:s];
        sBoostScript = Boosts.userScript;
        sDarkScript = SiteSettings.forceDarkScript;
        if (sBoostScript) [ucc addUserScript:sBoostScript];
        if (sDarkScript) [ucc addUserScript:sDarkScript];
    });
    return ucc;
}

/// Swaps in the current Boosts and force-dark scripts. WebKit can only remove all scripts at once,
/// so every other script (including ones web extensions added) is put back as it was.
/// Pages pick up the change on their next load.
+ (void)reloadSiteScripts {
    WKUserContentController *ucc = self.userContentController;
    NSMutableArray<WKUserScript *> *keep = [NSMutableArray array];
    for (WKUserScript *s in ucc.userScripts) if (s != sBoostScript && s != sDarkScript) [keep addObject:s];
    sBoostScript = Boosts.userScript;
    sDarkScript = SiteSettings.forceDarkScript;
    [ucc removeAllUserScripts];
    for (WKUserScript *s in keep) [ucc addUserScript:s];
    if (sBoostScript) [ucc addUserScript:sBoostScript];
    if (sDarkScript) [ucc addUserScript:sDarkScript];
}

/// Website data for a space: its own store when it has a separate profile, otherwise the shared one.
+ (WKWebsiteDataStore *)dataStoreForProfileID:(NSUUID *)profileID {
    if (!profileID) return WKWebsiteDataStore.defaultDataStore;
    return [WKWebsiteDataStore dataStoreForIdentifier:profileID];
}

+ (WKWebViewConfiguration *)makeConfigurationWithProfileID:(NSUUID *)profileID autoplay:(AutoplayPolicy)autoplay {
    WKWebViewConfiguration *c = [WKWebViewConfiguration new];
    c.websiteDataStore = [self dataStoreForProfileID:profileID];
    c.userContentController = self.userContentController;
    c.applicationNameForUserAgent = self.userAgentSuffix;
    c.preferences.elementFullscreenEnabled = YES;
    c.preferences.fraudulentWebsiteWarningEnabled = YES;
    c.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    c.mediaTypesRequiringUserActionForPlayback = AutoplayPolicyMediaTypes(autoplay);
    c.allowsAirPlayForMediaPlayback = YES;
    c.webExtensionController = ExtensionManager.shared.controller;
    return c;
}

@end

@implementation BrookWebView

// The menu's Reload goes to the first responder, and WKWebView answers it itself. Route it through the tab,
// so that a page that failed to load is loaded again instead of the last page that did load.
- (IBAction)reload:(id)sender {
    if (BrowserTab *tab = self.tab) [tab reload];
    else [super reload:sender];
}

- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
    [super willOpenMenu:menu withEvent:event];
    for (NSMenuItem *item in menu.itemArray) {
        NSString *identifier = item.identifier;
        if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenLinkInNewWindow"]) item.title = @"Open Link in New Tab";
        else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenImageInNewWindow"]) item.title = @"Open Image in New Tab";
        else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenMediaInNewWindow"]) item.title = @"Open Video in New Tab";
        else if ([identifier isEqualToString:@"WKMenuItemIdentifierOpenFrameInNewWindow"]) item.title = @"Open Frame in New Tab";
    }
}

@end
