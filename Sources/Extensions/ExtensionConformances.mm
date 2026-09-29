#import "Brook.h"

// MARK: - Tabs, as seen by extensions

@implementation BrowserTab (Extensions)

- (id<WKWebExtensionWindow>)windowForWebExtensionContext:(WKWebExtensionContext *)context {
    return ExtensionManager.shared.window;
}

- (WKWebView *)webViewForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.webView;
}

- (NSString *)titleForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.title;
}

- (BOOL)isPinnedForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.isPinned || self.isFavorite;
}

- (void)setPinned:(BOOL)pinned forWebExtensionContext:(WKWebExtensionContext *)context
 completionHandler:(void (^)(NSError *error))completionHandler {
    // A favorite counts as pinned. Only the user can remove it from Favorites.
    if (self.isFavorite) {
        completionHandler(pinned ? nil : BrowserTabError(@"The tab is a favorite. Remove it from Favorites to unpin it."));
        return;
    }
    if (!self.state) { completionHandler(BrowserTabError(@"The tab is not open.")); return; }
    if (pinned != self.isPinned) [self.state togglePin:self];
    completionHandler(nil);
}

- (id<WKWebExtensionTab>)parentTabForWebExtensionContext:(WKWebExtensionContext *)context {
    BrowserTab *parent = self.parentTab;
    // Extensions only know loaded tabs that are still open.
    return parent.isLoaded && [parent.state locationOf:parent] ? parent : nil;
}

- (void)setParentTab:(id<WKWebExtensionTab>)parentTab forWebExtensionContext:(WKWebExtensionContext *)context
   completionHandler:(void (^)(NSError *error))completionHandler {
    if (parentTab && ![(id)parentTab isKindOfClass:BrowserTab.class]) {
        completionHandler(BrowserTabError(@"The opener tab is not a Brook tab."));
        return;
    }
    BrowserTab *parent = (BrowserTab *)parentTab;
    if (parent == self) { completionHandler(BrowserTabError(@"A tab cannot be its own opener.")); return; }
    self.parentTab = parent;
    completionHandler(nil);
}

- (BOOL)isMutedForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.isMuted;
}

- (void)setMuted:(BOOL)muted forWebExtensionContext:(WKWebExtensionContext *)context
 completionHandler:(void (^)(NSError *error))completionHandler {
    NSError *error = nil;
    [self setMuted:muted error:&error];
    completionHandler(error);
}

- (NSURL *)urlForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.webView.URL ?: self.url;
}

- (BOOL)isLoadingCompleteForWebExtensionContext:(WKWebExtensionContext *)context {
    return !self.isLoading;
}

- (BOOL)isSelectedForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.state.selectedTab == self;
}

- (CGSize)sizeForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.webView ? self.webView.frame.size : CGSizeZero;
}

- (double)zoomFactorForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.webView ? (double)self.webView.pageZoom : 1;
}

- (void)loadURL:(NSURL *)url forWebExtensionContext:(WKWebExtensionContext *)context
    completionHandler:(void (^)(NSError *error))completionHandler {
    [self load:url];
    completionHandler(nil);
}

- (void)reloadFromOrigin:(BOOL)fromOrigin forWebExtensionContext:(WKWebExtensionContext *)context
       completionHandler:(void (^)(NSError *error))completionHandler {
    if (fromOrigin) [self.webView reloadFromOrigin]; else [self reload];
    completionHandler(nil);
}

- (void)goBackForWebExtensionContext:(WKWebExtensionContext *)context
                   completionHandler:(void (^)(NSError *error))completionHandler {
    [self.webView goBack];
    completionHandler(nil);
}

- (void)goForwardForWebExtensionContext:(WKWebExtensionContext *)context
                      completionHandler:(void (^)(NSError *error))completionHandler {
    [self.webView goForward];
    completionHandler(nil);
}

- (void)activateForWebExtensionContext:(WKWebExtensionContext *)context
                     completionHandler:(void (^)(NSError *error))completionHandler {
    [self.state selectTab:self];
    completionHandler(nil);
}

- (void)setSelected:(BOOL)selected forWebExtensionContext:(WKWebExtensionContext *)context
  completionHandler:(void (^)(NSError *error))completionHandler {
    if (selected) [self.state selectTab:self];
    completionHandler(nil);
}

- (void)closeForWebExtensionContext:(WKWebExtensionContext *)context
                  completionHandler:(void (^)(NSError *error))completionHandler {
    [self.state remove:self];
    completionHandler(nil);
}

- (BOOL)shouldGrantPermissionsOnUserGestureForWebExtensionContext:(WKWebExtensionContext *)context {
    return YES;
}

@end

// MARK: - The browser window, as seen by extensions

@implementation BrowserWindowController (Extensions)

- (NSArray<id<WKWebExtensionTab>> *)tabsForWebExtensionContext:(WKWebExtensionContext *)context {
    // Only tabs with live web views exist as far as extensions are concerned.
    NSMutableArray<id<WKWebExtensionTab>> *tabs = [NSMutableArray array];
    for (BrowserTab *tab in BrowserState.shared.allTabs) {
        if (tab.isLoaded) [tabs addObject:tab];
    }
    return tabs;
}

- (id<WKWebExtensionTab>)activeTabForWebExtensionContext:(WKWebExtensionContext *)context {
    BrowserTab *tab = BrowserState.shared.selectedTab;
    if (!tab || !tab.isLoaded) return nil;
    return tab;
}

- (WKWebExtensionWindowType)windowTypeForWebExtensionContext:(WKWebExtensionContext *)context {
    return WKWebExtensionWindowTypeNormal;
}

- (WKWebExtensionWindowState)windowStateForWebExtensionContext:(WKWebExtensionContext *)context {
    NSWindow *window = self.window;
    if (!window) return WKWebExtensionWindowStateNormal;
    if (window.styleMask & NSWindowStyleMaskFullScreen) return WKWebExtensionWindowStateFullscreen;
    if (window.isMiniaturized) return WKWebExtensionWindowStateMinimized;
    return WKWebExtensionWindowStateNormal;
}

- (BOOL)isPrivateForWebExtensionContext:(WKWebExtensionContext *)context {
    return NO;
}

- (CGRect)screenFrameForWebExtensionContext:(WKWebExtensionContext *)context {
    NSScreen *screen = self.window.screen;
    return screen ? screen.frame : CGRectZero;
}

- (CGRect)frameForWebExtensionContext:(WKWebExtensionContext *)context {
    return self.window ? self.window.frame : CGRectZero;
}

- (void)setFrame:(CGRect)frame forWebExtensionContext:(WKWebExtensionContext *)context
    completionHandler:(void (^)(NSError *error))completionHandler {
    [self.window setFrame:frame display:YES];
    completionHandler(nil);
}

- (void)focusForWebExtensionContext:(WKWebExtensionContext *)context
                  completionHandler:(void (^)(NSError *error))completionHandler {
    [self.window makeKeyAndOrderFront:nil];
    completionHandler(nil);
}

- (void)closeForWebExtensionContext:(WKWebExtensionContext *)context
                  completionHandler:(void (^)(NSError *error))completionHandler {
    [self.window performClose:nil];
    completionHandler(nil);
}

@end
