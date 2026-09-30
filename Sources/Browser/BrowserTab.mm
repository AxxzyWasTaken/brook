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

NSErrorDomain const BrowserTabErrorDomain = @"BrookTabError";

NSError *BrowserTabError(NSString *message) {
    return [NSError errorWithDomain:BrowserTabErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// WebKit's private page mute (the same one Safari uses). The value is a _WKMediaMutedState bit set:
/// bit 0 is page audio; the other bits are camera, microphone and screen capture.
static SEL PageMutedStateSelector(void) {
    static SEL sel = NSSelectorFromString(@"_mediaMutedState");
    return sel;
}

static SEL SetPageMutedSelector(void) {
    static SEL sel = NSSelectorFromString(@"_setPageMuted:");
    return sel;
}

static const NSUInteger kMediaAudioMuted = 1 << 0;

/// _WKRenderingProgressEventFirstVisuallyNonEmptyLayout: the moment Safari takes down the picture it shows
/// while a page comes back.
static const NSUInteger kFirstVisuallyNonEmptyLayout = 1 << 1;

@implementation BrowserTab {
    /// The web view whose properties we observe (nil when nothing is observed).
    WKWebView *_observed;
    WKWebViewConfiguration *_pendingConfiguration;
    NSMutableDictionary<NSString *, NSNumber *> *_mediaPermissions;   // WKPermissionDecision
    NSDate *_lastCrash;          // web content process crashes in a row, each soon after the one before
    NSInteger _crashesInARow;
    id _sleepState;              // the web view's interactionState when it hibernated; used by the next materialize
    NSData *_sleepPicture;       // JPEG of the page when it hibernated
}

- (instancetype)initWithID:(NSUUID *)identifier url:(NSURL *)url title:(NSString *)title {
    if ((self = [super init])) {
        _identifier = identifier;
        _url = url;
        _title = [title copy] ?: @"";
        _lastActive = [NSDate date];
        _progress = 0;
        _painted = YES;
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

// MARK: Mute

+ (BOOL)canMute {
    return [WKWebView instancesRespondToSelector:PageMutedStateSelector()] &&
           [WKWebView instancesRespondToSelector:SetPageMutedSelector()];
}

- (BOOL)setMuted:(BOOL)muted error:(NSError **)error {
    if (!BrowserTab.canMute) {
        if (error) *error = BrowserTabError(@"This version of WebKit cannot mute a tab.");
        return NO;
    }
    if (_isMuted == muted) return YES;
    _isMuted = muted;
    if (_webView) [self applyMuteTo:_webView];
    [_state tabDidChange:self change:TabChangeMuted];
    return YES;
}

/// Sets only the page audio bit, so a muted camera or microphone stays muted.
- (void)applyMuteTo:(WKWebView *)webView {
    NSUInteger current = ((NSUInteger (*)(id, SEL))objc_msgSend)(webView, PageMutedStateSelector());
    NSUInteger next = (current & ~kMediaAudioMuted) | (_isMuted ? kMediaAudioMuted : 0);
    if (next != current) ((void (*)(id, SEL, NSUInteger))objc_msgSend)(webView, SetPageMutedSelector(), next);
}

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
    wv.allowsBackForwardNavigationGestures = Settings.pageSwipe == PageSwipeBackForward;
    wv.allowsMagnification = YES;
    wv.inspectable = YES;
    wv.underPageBackgroundColor = NSColor.textBackgroundColor;
    wv.pageZoom = [SiteSettings zoomForHost:BrookHost(_url)];
    _webView = wv;
    [self observe:wv];
    // Web notifications: a worker's come through the store's delegate, a page's through the pool's provider.
    [SiteNotifications.shared attachStore:config.websiteDataStore];
    [SiteNotifications.shared providePageNotificationsFor:wv];
    // A new web view starts with sound; a tab muted before it unloaded stays muted.
    if (_isMuted && BrowserTab.canMute) [self applyMuteTo:wv];
    // A view that is about to load a page stays transparent until WebKit says it has drawn something, so
    // the card's background shows instead of a white flash (idea from Search by Office Commun, MIT).
    _painted = YES;
    static SEL observeProgress = NSSelectorFromString(@"_setObservedRenderingProgressEvents:");
    if ((isPopup || _url) && [wv respondsToSelector:observeProgress]) {
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(wv, observeProgress, kFirstVisuallyNonEmptyLayout);
        _painted = NO;
        wv.alphaValue = 0;
        // A page that never lays anything out (or a WebKit that never reports it) still comes in.
        __weak BrowserTab *weakSelf = self;
        __weak BrookWebView *weakWV = wv;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            BrowserTab *self_ = weakSelf;
            if (self_ && weakWV && self_.webView == weakWV) [self_ showPainted];
        });
    }
    // A tab waking from hibernate goes back to the same page, history and scroll position. Only a tab
    // that is still at the address it slept on: anything that sent it elsewhere drops the saved state.
    id sleepState = _sleepState;
    NSData *picture = _sleepPicture;
    _sleepState = nil;
    _sleepPicture = nil;
    if (picture && !isPopup) {
        _wakeCover = [[NSImage alloc] initWithData:picture];
    }
    if (!isPopup && _url) {
        NSURL *url = _url;
        __weak BrookWebView *weakWV = wv;
        // Restored tabs wait for the blocklist and for extensions' blocking rules.
        [ContentBlocker.shared whenReady:^{
            [ExtensionManager.shared whenLoaded:^{
                BrookWebView *w = weakWV;
                // Skip if the tab was unloaded or has already been sent somewhere else meanwhile.
                if (!w || w.URL || w.isLoading) return;
                if (sleepState) {
                    w.interactionState = sleepState;
                    // A state WebKit couldn't use leaves the view empty; load the address instead.
                    if (w.URL || w.isLoading) return;
                }
                [w loadRequest:[NSURLRequest requestWithURL:url]];
            }];
        }];
    }
    [ExtensionManager.shared tabDidOpen:self];
    [_state tabDidChange:self change:TabChangeLoaded];
    return wv;
}

/// Frees the web content process memory. The tab stays in the sidebar and reloads on demand.
- (void)unload {
    [self forgetSleep];
    [self dropWebView];
}

/// Pinned tabs and favorites return to their home page when closed. Unload already forgot any sleep state.
- (void)resetToHome {
    [self unload];
    if (_homeURL) _url = _homeURL;
    _loadError = nil;
}

- (void)forgetSleep {
    _sleepState = nil;
    _sleepPicture = nil;
    if (_wakeCover) {
        _wakeCover = nil;
        [_state tabDidChange:self change:TabChangePainted];
    }
}

- (void)dropWebView {
    BrookWebView *wv = _webView;
    if (!wv) return;
    [PasswordAutofill.shared dismissForWebView:wv];
    [ExtensionManager.shared tabWillClose:self];
    [self stopObserving];
    [wv stopLoading];
    wv.navigationDelegate = nil;
    wv.UIDelegate = nil;
    [wv removeFromSuperview];
    _webView = nil;
    _isLoading = NO;
    _progress = 0;
    _readerOn = NO;
    _painted = YES;
    [_state tabDidChange:self change:TabChangeLoading | TabChangeLoaded];
}

/// Takes the page's picture off the main thread as a JPEG, as Search does (small, and decoded only on wake).
static void SnapshotJPEG(WKWebView *wv, void (^done)(NSData *jpeg)) {
    [wv takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) {
        CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
        if (!cg) { done(nil); return; }
        CGImageRetain(cg);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
            NSData *data = [rep representationUsingType:NSBitmapImageFileTypeJPEG
                                             properties:@{NSImageCompressionFactor: @0.55}];
            CGImageRelease(cg);
            dispatch_async(dispatch_get_main_queue(), ^{ done(data); });
        });
    }];
}

- (void)hibernate {
    BrookWebView *wv = _webView;
    if (!wv || self == _state.selectedTab) return;
    __weak BrowserTab *weakSelf = self;
    __weak BrookWebView *weakWV = wv;
    SnapshotJPEG(wv, ^(NSData *jpeg) {
        BrowserTab *self_ = weakSelf;
        // Selected again, or already unloaded, while the picture was taken: leave it.
        if (!self_ || !weakWV || self_.webView != weakWV || self_ == self_.state.selectedTab) return;
        [self_ sleepWithPicture:jpeg];
    });
}

- (void)sleepWithPicture:(NSData *)jpeg {
    BrookWebView *wv = _webView;
    // A page still loading has no settled state; it reloads from its address instead.
    id state = wv.isLoading || _loadError ? nil : wv.interactionState;
    [self dropWebView];
    _sleepState = state;
    _sleepPicture = state ? jpeg : nil;
}

- (void)load:(NSURL *)url {
    _url = url;
    _loadError = nil;
    [self forgetSleep];
    BrookWebView *wv = [self materialize];
    [wv loadRequest:[NSURLRequest requestWithURL:url]];
    [_state tabDidChange:self change:TabChangeURL | TabChangeError];
}

- (void)reload {
    // After a failed navigation, retry the address that failed, not the page still on screen.
    BOOL failed = _loadError != nil;
    _loadError = nil;
    [_state tabDidChange:self change:TabChangeError];
    if (BrookWebView *wv = _webView) {
        if (_url && (!wv.URL || (failed && ![wv.URL isEqual:_url]))) {
            [wv loadRequest:[NSURLRequest requestWithURL:_url]];
        } else {
            [wv reload];
        }
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
    for (DownloadItem *item in DownloadManager.shared.items) {
        if (item.status == DownloadStatusActive && item.download.webView == wv) { completion(YES); return; }
    }
    // A sign-in popup (or any page this tab opened) on screen may still hand its answer back here.
    if (_state.selectedTab.parentTab == self) { completion(YES); return; }
    __weak BrookWebView *weakWV = wv;
    [wv requestMediaPlaybackStateWithCompletionHandler:^(WKMediaPlaybackState state) {
        BrookWebView *w = weakWV;
        if (state == WKMediaPlaybackStatePlaying || !w) { completion(state == WKMediaPlaybackStatePlaying); return; }
        // Text typed and not sent can't come back after a reload; nor can a (paused) video out in PiP.
        [w evaluateJavaScript:@"!!(globalThis.brookHoldsTyping && brookHoldsTyping()) || !!document.pictureInPictureElement"
                      inFrame:nil inContentWorld:WebViewFactory.typingWorld completionHandler:^(id result, NSError *error) {
            completion([result isKindOfClass:NSNumber.class] && [result boolValue]);
        }];
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
        [PasswordAutofill.shared pageChangedForWebView:wv];
        if (hostChanged && host) {
            self.favicon = [FaviconStore.shared cachedIconForHost:host];
            [_state tabDidChange:self change:TabChangeFavicon];
            if (!self.favicon) {   // maybe on disk: read it in the background
                __weak BrowserTab *weakSelf = self;
                [FaviconStore.shared cachedIconForHost:host completion:^(NSImage *icon) {
                    BrowserTab *self_ = weakSelf;
                    if (!self_ || !icon || !SameHost(BrookHost(self_.url), host)) return;
                    self_.favicon = icon;
                    [self_.state tabDidChange:self_ change:TabChangeFavicon];
                }];
            }
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

/// WKNavigationDelegatePrivate: called only for the events asked for in materialize.
- (void)_webView:(WKWebView *)webView renderingProgressDidChange:(NSUInteger)events {
    if (webView == _webView && (events & kFirstVisuallyNonEmptyLayout)) [self showPainted];
}

/// The page has drawn: fade the web view in, then take the wake picture down once the fade is over.
- (void)showPainted {
    BrookWebView *wv = _webView;
    if (!wv || _painted) return;
    _painted = YES;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.12;
        wv.animator.alphaValue = 1;
    }];
    [_state tabDidChange:self change:TabChangePainted];
    if (!_wakeCover) return;
    __weak BrowserTab *weakSelf = self;
    NSImage *cover = _wakeCover;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BrowserTab *self_ = weakSelf;
        if (!self_ || self_->_wakeCover != cover) return;
        self_->_wakeCover = nil;
        [self_.state tabDidChange:self_ change:TabChangePainted];
    });
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
            preferences:(WKWebpagePreferences *)preferences
        decisionHandler:(void (^)(WKNavigationActionPolicy, WKWebpagePreferences *))decisionHandler {
    WKNavigationActionPolicy policy = [self decidePolicyFor:navigationAction];
    BOOL mainFrame = navigationAction.targetFrame ? navigationAction.targetFrame.isMainFrame : YES;
    NSString *host = BrookHost(navigationAction.request.URL);
    if (policy == WKNavigationActionPolicyAllow && mainFrame && host) {
        preferences.allowsContentJavaScript = [SiteSettings javascriptForHost:host];
        [self applySitePreferences:preferences host:host];
    }
    decisionHandler(policy, preferences);
}

/// Per-site user agent, content blocking and autoplay. WebKit only exposes these per navigation through
/// the same preferences Safari uses; skipped (site gets the defaults) if WebKit ever drops them.
/// An empty user agent means WebKit's own. The web view's configuration only has the autoplay policy
/// of the site it was created for, so a reload or a move to another site needs the policy here too.
- (void)applySitePreferences:(WKWebpagePreferences *)preferences host:(NSString *)host {
    static SEL setUA = NSSelectorFromString(@"_setCustomUserAgent:");
    static SEL setBlockers = NSSelectorFromString(@"_setContentBlockersEnabled:");
    static SEL setAutoplay = NSSelectorFromString(@"_setAutoplayPolicy:");
    if ([preferences respondsToSelector:setUA]) {
        NSString *ua = UserAgentString([SiteSettings userAgentForHost:host]) ?: @"";
        ((void (*)(id, SEL, NSString *))objc_msgSend)(preferences, setUA, ua);
    }
    if ([preferences respondsToSelector:setBlockers]) {
        // Only an explicit "off" for this site turns blocking off; the global switch works on the lists.
        NSNumber *v = [SiteSettings overrideForHost:host].blockAds;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(preferences, setBlockers, v ? v.boolValue : YES);
    }
    if ([preferences respondsToSelector:setAutoplay]) {
        // _WKWebsiteAutoplayPolicy: 1 Allow, 2 AllowWithoutSound, 3 Deny.
        AutoplayPolicy policy = [SiteSettings autoplayForHost:host];
        NSInteger value = policy == AutoplayPolicyBlockAll ? 3 : policy == AutoplayPolicyBlockAudio ? 2 : 1;
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(preferences, setAutoplay, value);
    }
}

/// ⌘-click or middle-click asks for a new tab. WKNavigationAction.buttonNumber is a button mask
/// (left 1, right 2, middle 4), unlike NSEvent.buttonNumber, where the middle button is 2.
static BOOL WantsNewTab(WKNavigationAction *action) {
    return (action.modifierFlags & NSEventModifierFlagCommand) || (action.buttonNumber & (1 << 2));
}

/// Such a tab opens in the background by default (Settings); ⇧ flips it.
static BOOL NewTabSelects(WKNavigationAction *action) {
    BOOL shift = (action.modifierFlags & NSEventModifierFlagShift) != 0;
    return Settings.linksOpenInBackground ? shift : !shift;
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

    // A tab's first page always loads in that tab. "Open Link in New Tab" arrives in the new tab as a link
    // click carrying the right-click; sending it on again would leave the new tab empty.
    BOOL hasPage = _webView.backForwardList.currentItem != nil;
    if (hasPage && navigationAction.navigationType == WKNavigationTypeLinkActivated && WantsNewTab(navigationAction)) {
        [_state openTabWithURL:url inSpace:nil after:self select:NewTabSelects(navigationAction) loadNow:YES];
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

/// WKNavigationDelegatePrivate: the right-click menu's Download Linked File. Unanswered, WebKit
/// starts the download with nobody to ask where it goes, and nothing arrives.
- (void)_webView:(WKWebView *)webView contextMenuDidCreateDownload:(WKDownload *)download {
    [DownloadManager.shared track:download];
}

/// WKUIDelegatePrivate: WebKit's right-click menu, before it shows. Its Download Image and Copy Image are
/// swapped for Brook's (see ImageMenu); everything else stays WebKit's.
- (void)_webView:(WKWebView *)webView getContextMenuFromProposedMenu:(NSMenu *)menu forElement:(id)element
        userInfo:(id)userInfo completionHandler:(void (^)(NSMenu *))completionHandler {
    [ImageMenu adjustMenu:menu element:element webView:webView];
    completionHandler(menu);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [PasswordAutofill.shared navigationStartedForWebView:webView];
    if (_loadError) {
        _loadError = nil;
        [_state tabDidChange:self change:TabChangeError];
    }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    [PasswordAutofill.shared pageChangedForWebView:webView];
    // Per-site zoom, remembered like Safari does.
    double zoom = [SiteSettings zoomForHost:BrookHost(webView.URL)];
    if (fabs(webView.pageZoom - zoom) > 0.001) webView.pageZoom = zoom;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // A page with nothing to lay out never reports a first frame; done is done, and it is shown.
    [self showPainted];
    if (NSURL *url = webView.URL) [HistoryStore.shared recordURL:url title:webView.title];
    // A page from the back-forward cache keeps its reader overlay, so ask the page, not the last toggle.
    _readerOn = NO;
    __weak BrowserTab *weakSelf = self;
    [webView evaluateJavaScript:@"!!document.getElementById('brook-reader')" inFrame:nil
                 inContentWorld:WKContentWorld.defaultClientWorld completionHandler:^(id result, NSError *error) {
        if ([result isKindOfClass:NSNumber.class]) weakSelf.readerOn = [result boolValue];
    }];
    // A page with no <title> keeps the last page's title otherwise; drop it so the URL shows.
    if (!webView.title.length && _title.length) {
        _title = @"";
        [_state tabDidChange:self change:TabChangeTitle];
    }
    [self refreshFavicon];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self handleError:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self handleError:error];
}

- (void)handleError:(NSError *)ns {
    [self showPainted];
    // Cancelled loads, and "frame load interrupted" (downloads, policy changes), aren't errors.
    if ([ns.domain isEqualToString:NSURLErrorDomain] && ns.code == NSURLErrorCancelled) return;
    if ([ns.domain isEqualToString:@"WebKitErrorDomain"] && (ns.code == 102 || ns.code == 204)) return;
    // A page that fails before it commits leaves the web view on the previous page; name the
    // address that failed so the pill, the tab and Try Again all refer to it.
    NSURL *failing = ns.userInfo[NSURLErrorFailingURLErrorKey];
    if ([failing isKindOfClass:NSURL.class] && ![failing isEqual:_url]) {
        BOOL hostChanged = !SameHost(BrookHost(failing), BrookHost(_url));
        _url = failing;
        _title = @"";
        TabChange change = TabChangeURL | TabChangeTitle;
        if (hostChanged) {
            self.favicon = [FaviconStore.shared cachedIconForHost:BrookHost(failing)];
            change |= TabChangeFavicon;
        }
        [_state tabDidChange:self change:change];
    }
    _loadError = [ns.localizedDescription copy];
    [_state tabDidChange:self change:TabChangeError];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self showPainted];
    // Reload after a crash, but not without end: a page that crashes on each load stops after the
    // third crash in a row and shows the error view, whose Try Again reloads it.
    NSDate *now = [NSDate date];
    BOOL soon = _lastCrash && [now timeIntervalSinceDate:_lastCrash] < 10;
    _crashesInARow = soon ? _crashesInARow + 1 : 1;
    _lastCrash = now;
    if (_crashesInARow < 3) {
        [webView reload];
        return;
    }
    _crashesInARow = 0;
    _lastCrash = nil;
    _loadError = @"A problem repeatedly occurred with this page.";
    [_state tabDidChange:self change:TabChangeError];
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
    tab.parentTab = self;
    BOOL select = WantsNewTab(navigationAction) ? NewTabSelects(navigationAction) : YES;
    [state insertPopup:tab after:self select:select];
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
    alert.messageText = SaysTitle(frame);
    alert.informativeText = prompt;
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

/// The page's own origin, when the asking origin (and the frame asking) is that page: frames from elsewhere
/// don't get to borrow the page's answer. nil otherwise.
- (NSString *)pageOriginAskingFrom:(WKSecurityOrigin *)origin frame:(WKFrameInfo *)frame webView:(WKWebView *)webView {
    NSURL *page = webView.URL;
    if (!page.host.length || !origin.host.length) return nil;
    NSString *site = [SitePermissions originForScheme:page.scheme host:page.host port:page.port.integerValue];
    if (![[SitePermissions originOf:origin] isEqualToString:site]) return nil;
    if (frame && ![[SitePermissions originOf:frame.securityOrigin] isEqualToString:site]) return nil;
    return site;
}

/// WKUIDelegatePrivate: a page asking where you are. Unanswered, WebKit refuses every page. Only the tab
/// on screen is asked, and only for itself; the question sits over the page, as Safari's does.
- (void)_webView:(WKWebView *)webView requestGeolocationPermissionForOrigin:(WKSecurityOrigin *)origin
    initiatedByFrame:(WKFrameInfo *)frame decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    NSString *site = [self pageOriginAskingFrom:origin frame:frame webView:webView];
    if (!site || self != _state.selectedTab) { decisionHandler(WKPermissionDecisionDeny); return; }
    [SitePermissions ask:SitePermissionLocation origin:site host:origin.host webView:webView completion:^(BOOL allowed) {
        decisionHandler(allowed ? WKPermissionDecisionGrant : WKPermissionDecisionDeny);
    }];
}

/// WKUIDelegatePrivate: a page asking to send notifications (Notification.requestPermission()).
- (void)_webView:(WKWebView *)webView requestNotificationPermissionForSecurityOrigin:(WKSecurityOrigin *)origin
    decisionHandler:(void (^)(BOOL))decisionHandler {
    NSString *site = [self pageOriginAskingFrom:origin frame:nil webView:webView];
    if (!site || !Settings.siteNotifications || !webView.configuration.websiteDataStore.isPersistent) {
        decisionHandler(NO);
        return;
    }
    [SitePermissions ask:SitePermissionNotifications origin:site host:origin.host webView:webView completion:^(BOOL allowed) {
        if (allowed) [SiteNotifications.shared authorize];
        decisionHandler(allowed);
    }];
}

@end
