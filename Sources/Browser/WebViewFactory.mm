#import "Brook.h"

@implementation WebViewFactory

static WKUserScript *sBoostScript;

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
        if (WKUserScript *s = AutoconsentHandler.shared.userScript) [ucc addUserScript:s];
        if (WKUserScript *s = ChromeWebStoreBridge.shared.userScript) [ucc addUserScript:s];
        sBoostScript = Boosts.userScript;
        if (sBoostScript) [ucc addUserScript:sBoostScript];
    });
    return ucc;
}

/// Swaps in the current Boosts script. WebKit can only remove all scripts at once, so every
/// other script (including ones web extensions added) is put back as it was.
/// Pages pick up the change on their next load.
+ (void)reloadBoosts {
    WKUserContentController *ucc = self.userContentController;
    WKUserScript *old = sBoostScript;
    NSMutableArray<WKUserScript *> *keep = [NSMutableArray array];
    for (WKUserScript *s in ucc.userScripts) if (s != old) [keep addObject:s];
    sBoostScript = Boosts.userScript;
    [ucc removeAllUserScripts];
    for (WKUserScript *s in keep) [ucc addUserScript:s];
    if (sBoostScript) [ucc addUserScript:sBoostScript];
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
