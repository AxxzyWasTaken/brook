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
static NSArray<WKUserScript *> *sScriptlets = @[];

/// Makes sites treat Brook like Safari (same engine), so nothing serves a degraded page.
+ (NSString *)userAgentSuffix { return @"Version/26.0 Safari/605.1.15"; }

+ (WKContentWorld *)typingWorld {
    static WKContentWorld *world = [WKContentWorld worldWithName:@"BrookTyping"];
    return world;
}

/// A bundled script, or nil if it's missing from the app.
static WKUserScript *BundledScript(NSString *name, WKUserScriptInjectionTime time, BOOL mainFrameOnly, WKContentWorld *world) {
    NSURL *file = [NSBundle.mainBundle URLForResource:name withExtension:@"js"];
    NSString *source = file ? [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!source) return nil;
    return [[WKUserScript alloc] initWithSource:source injectionTime:time forMainFrameOnly:mainFrameOnly inContentWorld:world];
}

/// One process pool for every tab. The property is deprecated and documented as doing nothing, but a
/// configuration without it still gets a pool of its own when its web view is made, and each new pool
/// starts its web content process cold. Sharing one lets WebKit keep the next process warm: a new tab's
/// first commit went from ~62 ms to ~55 ms in a standalone probe, and the web view init from ~8 ms to ~3 ms
/// (measured Sept 2026). Idea from Search by Office Commun (MIT).
+ (WKProcessPool *)processPool {
    static WKProcessPool *pool = [WKProcessPool new];
    return pool;
}

/// One shared content controller: scripts are compiled once and reused by every tab.
+ (WKUserContentController *)userContentController {
    static WKUserContentController *ucc;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ucc = [WKUserContentController new];
        // Scriptlets first: at document start they must patch the page before anything else runs.
        sScriptlets = ContentBlocker.shared.scriptletScripts;
        for (WKUserScript *s in sScriptlets) [ucc addUserScript:s];
        [AutoconsentHandler.shared installHandlersInto:ucc];
        [ChromeWebStoreBridge.shared installHandlersInto:ucc];
        [PasswordAutofill.shared installInto:ucc];
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
        // In the page's own world, before its scripts: live players set playbackRate through the prototype.
        if (WKUserScript *s = BundledScript(@"live-rate", WKUserScriptInjectionTimeAtDocumentStart, NO,
                                            WKContentWorld.pageWorld)) [ucc addUserScript:s];
        if (WKUserScript *s = BundledScript(@"typed-text", WKUserScriptInjectionTimeAtDocumentStart, YES,
                                            self.typingWorld)) [ucc addUserScript:s];
        if (WKUserScript *s = AutoconsentHandler.shared.userScript) [ucc addUserScript:s];
        if (WKUserScript *s = ChromeWebStoreBridge.shared.userScript) [ucc addUserScript:s];
        sBoostScript = Boosts.userScript;
        sDarkScript = SiteSettings.forceDarkScript;
        if (sBoostScript) [ucc addUserScript:sBoostScript];
        if (sDarkScript) [ucc addUserScript:sDarkScript];
    });
    return ucc;
}

/// Swaps in the current ad-blocking scriptlets, Boosts and force-dark scripts. WebKit can only remove all
/// scripts at once, so every other script (including ones web extensions added) is put back as it was.
/// Pages pick up the change on their next load.
+ (void)reloadSiteScripts {
    WKUserContentController *ucc = self.userContentController;
    NSMutableArray<WKUserScript *> *keep = [NSMutableArray array];
    for (WKUserScript *s in ucc.userScripts)
        if (s != sBoostScript && s != sDarkScript && ![sScriptlets containsObject:s]) [keep addObject:s];
    sScriptlets = ContentBlocker.shared.scriptletScripts;
    sBoostScript = Boosts.userScript;
    sDarkScript = SiteSettings.forceDarkScript;
    [ucc removeAllUserScripts];
    // Scriptlets first: at document start they must patch the page before anything else runs.
    for (WKUserScript *s in sScriptlets) [ucc addUserScript:s];
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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    c.processPool = self.processPool;
#pragma clang diagnostic pop
    c.userContentController = self.userContentController;
    c.applicationNameForUserAgent = self.userAgentSuffix;
    c.preferences.elementFullscreenEnabled = YES;
    c.preferences.fraudulentWebsiteWarningEnabled = YES;
    c.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    // Picture in Picture is off by default in a Mac WKWebView (the public switch is iOS-only); Safari turns it
    // on through the same preference. Skipped if WebKit ever drops it.
    static SEL setPiP = NSSelectorFromString(@"_setAllowsPictureInPictureMediaPlayback:");
    if ([c.preferences respondsToSelector:setPiP])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(c.preferences, setPiP, YES);
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

// WKWebView sends every key equivalent to the page first, and the page's default Tab handling uses
// up Control-Tab, so Next Tab / Previous Tab never reach the menu while a page has focus. Give the
// menu the first chance at Control-Tab, as other browsers do.
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption);
    NSString *chars = event.charactersIgnoringModifiers;
    unichar c = chars.length ? [chars characterAtIndex:0] : 0;
    if (mods == NSEventModifierFlagControl && (c == NSTabCharacter || c == NSBackTabCharacter) &&
        [NSApp.mainMenu performKeyEquivalent:event])
        return YES;
    return [super performKeyEquivalent:event];
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
