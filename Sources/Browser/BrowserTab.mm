#import "Brook.h"

/// Equal when both are nil or both hold the same text.
static BOOL SameHost(NSString *a, NSString *b) {
    return a == b || [a isEqualToString:b];
}

/// The web view properties the tab watches.
static NSArray<NSString *> *ObservedKeyPaths(void) {
    return @[@"title", @"URL", @"loading", @"estimatedProgress", @"canGoBack", @"canGoForward"];
}

static void *kTabKVOContext = &kTabKVOContext;

@implementation BrowserTab {
    /// The web view whose properties we observe (nil when nothing is observed).
    WKWebView *_observed;
    WKWebViewConfiguration *_pendingConfiguration;
    NSMutableDictionary<NSString *, NSNumber *> *_mediaPermissions;   // WKPermissionDecision
}

- (instancetype)initWithID:(NSUUID *)identifier url:(NSURL *)url title:(NSString *)title {
    if ((self = [super init])) {
        _identifier = identifier;
        _url = url;
        _title = [title copy] ?: @"";
        _lastActive = [NSDate date];
        _progress = 0;
        _mediaPermissions = [NSMutableDictionary dictionary];
        if (NSString *host = BrookHost(url)) {
            _favicon = [FaviconStore.shared cachedIconForHost:host];
            // Restored tabs that were never loaded still deserve their site icon, not a globe.
            if (!_favicon) [self refreshFavicon];
        }
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)url {
    return [self initWithID:[NSUUID UUID] url:url title:@""];
}

/// A tab created by a page (window.open). WebKit loads it, so we must use its configuration.
+ (instancetype)popupWithConfiguration:(WKWebViewConfiguration *)configuration {
    BrowserTab *tab = [[self alloc] initWithURL:nil];
    tab->_pendingConfiguration = configuration;
    return tab;
}

- (void)dealloc {
    [self stopObserving];
}

- (NSString *)displayTitle {
    if (_title.length) return _title;
    if (_url) return [URLParser display:_url];
    return @"New Tab";
}

- (BOOL)isLoaded { return _webView != nil; }

// MARK: Lifecycle

- (BrookWebView *)materialize {
    if (_webView) return _webView;
    WKWebViewConfiguration *config = _pendingConfiguration ?: [WebViewFactory
        makeConfigurationWithProfileID:[_state profileIDFor:self]
                              autoplay:[SiteSettings autoplayForHost:BrookHost(_url)]];
    BOOL isPopup = _pendingConfiguration != nil;
    _pendingConfiguration = nil;

    BrookWebView *wv = [[BrookWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600) configuration:config];
    wv.tab = self;
    wv.navigationDelegate = self;
    wv.UIDelegate = self;
    wv.allowsBackForwardNavigationGestures = YES;
    wv.allowsMagnification = YES;
    wv.inspectable = YES;
    wv.underPageBackgroundColor = NSColor.textBackgroundColor;
    wv.pageZoom = [SiteSettings zoomForHost:BrookHost(_url)];
    _webView = wv;
    [self observe:wv];
    if (!isPopup && _url) {
        NSURL *url = _url;
        __weak BrookWebView *weakWV = wv;
        // Restored tabs wait for the blocklist and for extensions' blocking rules.
        [ContentBlocker.shared whenReady:^{
            [ExtensionManager.shared whenLoaded:^{
                BrookWebView *w = weakWV;
                // Skip if the tab was unloaded or has already been sent somewhere else meanwhile.
                if (w && !w.URL && !w.isLoading) [w loadRequest:[NSURLRequest requestWithURL:url]];
            }];
        }];
    }
    [ExtensionManager.shared tabDidOpen:self];
    [_state tabDidChange:self change:TabChangeLoaded];
    return wv;
}

/// Frees the web content process memory. The tab stays in the sidebar and reloads on demand.
- (void)unload {
    BrookWebView *wv = _webView;
    if (!wv) return;
    [ExtensionManager.shared tabWillClose:self];
    [self stopObserving];
    [wv stopLoading];
    wv.navigationDelegate = nil;
    wv.UIDelegate = nil;
    [wv removeFromSuperview];
    _webView = nil;
    _isLoading = NO;
    _progress = 0;
    [_state tabDidChange:self change:TabChangeLoading | TabChangeLoaded];
}

/// Pinned tabs and favorites return to their home page when closed.
- (void)resetToHome {
    [self unload];
    if (_homeURL) _url = _homeURL;
    _loadError = nil;
    _consentCMP = nil;
}

- (void)load:(NSURL *)url {
    _url = url;
    _loadError = nil;
    BrookWebView *wv = [self materialize];
    [wv loadRequest:[NSURLRequest requestWithURL:url]];
    [_state tabDidChange:self change:TabChangeURL | TabChangeError];
}

- (void)reload {
    _loadError = nil;
    [_state tabDidChange:self change:TabChangeError];
    if (BrookWebView *wv = _webView) {
        if (!wv.URL && _url) [wv loadRequest:[NSURLRequest requestWithURL:_url]]; else [wv reload];
    } else {
        [self materialize];
    }
}

/// Calls back with YES if the tab is doing something the user would notice if we unloaded it.
- (void)isBusy:(void (^)(BOOL busy))completion {
    BrookWebView *wv = _webView;
    if (!wv) { completion(NO); return; }
    if (wv.cameraCaptureState != WKMediaCaptureStateNone || wv.microphoneCaptureState != WKMediaCaptureStateNone) {
        completion(YES);
        return;
    }
    [wv requestMediaPlaybackStateWithCompletionHandler:^(WKMediaPlaybackState state) {
        completion(state == WKMediaPlaybackStatePlaying);
    }];
}

- (void)observe:(WKWebView *)wv {
    [self stopObserving];
    _observed = wv;
    for (NSString *keyPath in ObservedKeyPaths()) {
        [wv addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:kTabKVOContext];
    }
}

- (void)stopObserving {
    if (!_observed) return;
    for (NSString *keyPath in ObservedKeyPaths()) {
        [_observed removeObserver:self forKeyPath:keyPath context:kTabKVOContext];
    }
    _observed = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context != kTabKVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    WKWebView *wv = object;
    if ([keyPath isEqualToString:@"title"]) {
        NSString *t = wv.title;
        if (!t.length) return;
        _title = [t copy];
        if (NSURL *url = wv.URL) [HistoryStore.shared updateTitle:t forURL:url];
        [_state tabDidChange:self change:TabChangeTitle];
    } else if ([keyPath isEqualToString:@"URL"]) {
        NSURL *u = wv.URL;
        if (!u) return;
        NSString *host = BrookHost(u);
        BOOL hostChanged = !SameHost(host, BrookHost(_url));
        _url = u;
        if (hostChanged && host) {
            self.favicon = [FaviconStore.shared cachedIconForHost:host];
            [_state tabDidChange:self change:TabChangeFavicon];
        }
        [_state tabDidChange:self change:TabChangeURL];
    } else if ([keyPath isEqualToString:@"loading"]) {
        _isLoading = wv.isLoading;
        [_state tabDidChange:self change:TabChangeLoading];
    } else if ([keyPath isEqualToString:@"estimatedProgress"]) {
        _progress = wv.estimatedProgress;
        [_state tabDidChange:self change:TabChangeProgress];
    } else if ([keyPath isEqualToString:@"canGoBack"] || [keyPath isEqualToString:@"canGoForward"]) {
        [_state tabDidChange:self change:TabChangeNavigation];
    }
}

- (void)refreshFavicon {
    NSString *host = BrookHost(_url);
    if (!host) return;
    __weak BrowserTab *weakSelf = self;
    [FaviconStore.shared iconForHost:host completion:^(NSImage *icon) {
        BrowserTab *self_ = weakSelf;
        if (!self_ || !icon || !SameHost(BrookHost(self_.url), host)) return;
        self_.favicon = icon;
        [self_.state tabDidChange:self_ change:TabChangeFavicon];
    }];
}

// MARK: - Navigation

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
            preferences:(WKWebpagePreferences *)preferences
        decisionHandler:(void (^)(WKNavigationActionPolicy, WKWebpagePreferences *))decisionHandler {
    WKNavigationActionPolicy policy = [self decidePolicyFor:navigationAction];
    BOOL mainFrame = navigationAction.targetFrame ? navigationAction.targetFrame.isMainFrame : YES;
    NSString *host = BrookHost(navigationAction.request.URL);
    if (policy == WKNavigationActionPolicyAllow && mainFrame && host) {
        preferences.allowsContentJavaScript = [SiteSettings javascriptForHost:host];
    }
    decisionHandler(policy, preferences);
}

- (WKNavigationActionPolicy)decidePolicyFor:(WKNavigationAction *)navigationAction {
    NSURL *url = navigationAction.request.URL;
    if (!url) return WKNavigationActionPolicyAllow;

    if (navigationAction.shouldPerformDownload) return WKNavigationActionPolicyDownload;

    NSString *scheme = url.scheme.lowercaseString ?: @"";
    static NSSet<NSString *> *webSchemes = [NSSet setWithArray:@[
        @"http", @"https", @"about", @"data", @"blob", @"file", @"javascript",
        @"webkit-extension", @"safari-web-extension"]];
    if (![webSchemes containsObject:scheme]) {
        [NSWorkspace.sharedWorkspace openURL:url];
        return WKNavigationActionPolicyCancel;
    }

    // ⌘-click or middle-click opens a background tab, like every other browser.
    BOOL isMainFrameLink = navigationAction.navigationType == WKNavigationTypeLinkActivated;
    if (isMainFrameLink && ((navigationAction.modifierFlags & NSEventModifierFlagCommand) || navigationAction.buttonNumber == 2)) {
        BOOL foreground = (navigationAction.modifierFlags & NSEventModifierFlagShift) != 0;
        [_state openTabWithURL:url inSpace:nil after:self select:foreground loadNow:YES];
        return WKNavigationActionPolicyCancel;
    }
    return WKNavigationActionPolicyAllow;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (!navigationResponse.canShowMIMEType) { decisionHandler(WKNavigationResponsePolicyDownload); return; }
    if ([navigationResponse.response isKindOfClass:NSHTTPURLResponse.class]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)navigationResponse.response;
        NSString *disposition = [http valueForHTTPHeaderField:@"Content-Disposition"];
        if (disposition && [disposition.lowercaseString hasPrefix:@"attachment"] && navigationResponse.isForMainFrame) {
            decisionHandler(WKNavigationResponsePolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction
    didBecomeDownload:(WKDownload *)download {
    [DownloadManager.shared track:download];
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse
    didBecomeDownload:(WKDownload *)download {
    [DownloadManager.shared track:download];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    _consentCMP = nil;
    if (_loadError) {
        _loadError = nil;
        [_state tabDidChange:self change:TabChangeError];
    }
    [_state tabDidChange:self change:TabChangeConsent];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    // Per-site zoom, remembered like Safari does.
    double zoom = [SiteSettings zoomForHost:BrookHost(webView.URL)];
    if (fabs(webView.pageZoom - zoom) > 0.001) webView.pageZoom = zoom;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (NSURL *url = webView.URL) [HistoryStore.shared recordURL:url title:webView.title];
    [self refreshFavicon];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self handleError:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self handleError:error];
}

- (void)handleError:(NSError *)ns {
    // Cancelled loads, and "frame load interrupted" (downloads, policy changes), aren't errors.
    if ([ns.domain isEqualToString:NSURLErrorDomain] && ns.code == NSURLErrorCancelled) return;
    if ([ns.domain isEqualToString:@"WebKitErrorDomain"] && (ns.code == 102 || ns.code == 204)) return;
    _loadError = [ns.localizedDescription copy];
    [_state tabDidChange:self change:TabChangeError];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [webView reload];
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    NSString *method = challenge.protectionSpace.authenticationMethod;
    NSWindow *window = webView.window;
    if (!([method isEqualToString:NSURLAuthenticationMethodHTTPBasic] ||
          [method isEqualToString:NSURLAuthenticationMethodHTTPDigest]) ||
        challenge.previousFailureCount >= 3 || !window) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Log in to %@", challenge.protectionSpace.host];
    alert.informativeText = challenge.protectionSpace.realm ?: @"This site requires a username and password.";
    [alert addButtonWithTitle:@"Log In"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *user = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 30, 260, 24)];
    user.placeholderString = @"Username";
    NSSecureTextField *pass = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    pass.placeholderString = @"Password";
    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 54)];
    [box addSubview:user];
    [box addSubview:pass];
    alert.accessoryView = box;
    alert.window.initialFirstResponder = user;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) {
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
            return;
        }
        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialWithUser:user.stringValue password:pass.stringValue
                                                  persistence:NSURLCredentialPersistenceForSession]);
    }];
}

// MARK: - UI

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    BrowserState *state = _state;
    if (!state) return nil;
    BrowserTab *tab = [BrowserTab popupWithConfiguration:configuration];
    BOOL background = (navigationAction.modifierFlags & NSEventModifierFlagCommand) || navigationAction.buttonNumber == 2;
    [state insertPopup:tab after:self select:!background];
    return [tab materialize];
}

- (void)webViewDidClose:(WKWebView *)webView {
    [_state close:self];
}

/// "<host> says", or "This page says" when the frame has no host.
static NSString *SaysTitle(WKFrameInfo *frame) {
    NSString *host = frame.securityOrigin.host;
    return host.length == 0 ? @"This page says" : [NSString stringWithFormat:@"%@ says", host];
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    NSWindow *window = webView.window;
    if (!window) { completionHandler(); return; }
    NSAlert *alert = [NSAlert new];
    alert.messageText = SaysTitle(frame);
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) { completionHandler(); }];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    NSWindow *window = webView.window;
    if (!window) { completionHandler(NO); return; }
    NSAlert *alert = [NSAlert new];
    alert.messageText = SaysTitle(frame);
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        completionHandler(r == NSAlertFirstButtonReturn);
    }];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
    defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(NSString *))completionHandler {
    NSWindow *window = webView.window;
    if (!window) { completionHandler(nil); return; }
    NSAlert *alert = [NSAlert new];
    alert.messageText = prompt;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.stringValue = defaultText ?: @"";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        completionHandler(r == NSAlertFirstButtonReturn ? field.stringValue : nil);
    }];
}

- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> *))completionHandler {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    panel.canChooseDirectories = parameters.allowsDirectories;
    panel.canChooseFiles = YES;
    NSWindow *window = webView.window;
    if (!window) { completionHandler(nil); return; }
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        completionHandler(r == NSModalResponseOK ? panel.URLs : nil);
    }];
}

- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
    initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type
    decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    NSString *key = [NSString stringWithFormat:@"%@#%ld", origin.host, (long)type];
    if (NSNumber *remembered = _mediaPermissions[key]) {
        decisionHandler((WKPermissionDecision)remembered.integerValue);
        return;
    }
    NSWindow *window = webView.window;
    if (!window) { decisionHandler(WKPermissionDecisionDeny); return; }
    NSString *what;
    switch (type) {
        case WKMediaCaptureTypeCamera: what = @"your camera"; break;
        case WKMediaCaptureTypeMicrophone: what = @"your microphone"; break;
        default: what = @"your camera and microphone"; break;
    }
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Allow %@ to use %@?", origin.host, what];
    [alert addButtonWithTitle:@"Allow"];
    [alert addButtonWithTitle:@"Don’t Allow"];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        WKPermissionDecision decision = r == NSAlertFirstButtonReturn ? WKPermissionDecisionGrant : WKPermissionDecisionDeny;
        self->_mediaPermissions[key] = @(decision);
        decisionHandler(decision);
    }];
}

@end
