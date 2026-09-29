#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

@class BrowserState, BrowserTab;

typedef NS_OPTIONS(NSUInteger, TabChange) {
    TabChangeTitle = 1 << 0,
    TabChangeURL = 1 << 1,
    TabChangeFavicon = 1 << 2,
    TabChangeLoading = 1 << 3,
    TabChangeProgress = 1 << 4,
    TabChangeNavigation = 1 << 5,
    TabChangeConsent = 1 << 6,
    TabChangeError = 1 << 7,
    TabChangeLoaded = 1 << 8,
};

/// The web view class every tab uses. Knows its tab, and renames "New Window" menu items to "New Tab".
@interface BrookWebView : WKWebView
@property (weak) BrowserTab *tab;
@end

/// One tab. Its web view is created lazily (materialize) and dropped to save memory (unload).
@interface BrowserTab : NSObject <WKNavigationDelegate, WKUIDelegate>

- (instancetype)initWithID:(NSUUID *)identifier url:(NSURL *)url title:(NSString *)title NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)init NS_UNAVAILABLE;
/// A tab created by a page (window.open). WebKit loads it, so we must use its configuration.
+ (instancetype)popupWithConfiguration:(WKWebViewConfiguration *)configuration;

@property (readonly) NSUUID *identifier;
@property (readonly) NSURL *url;
@property (readonly, copy) NSString *title;
/// For pinned tabs and favorites: where the tab goes back to when it is closed.
@property (copy) NSURL *homeURL;
@property BOOL isPinned;
@property BOOL isFavorite;
@property (strong) NSImage *favicon;
@property (strong) NSDate *lastActive;
@property (readonly) BrookWebView *webView;
@property (readonly) BOOL isLoading;
@property (readonly) double progress;
@property (readonly, copy) NSString *loadError;
@property (copy) NSString *consentCMP;
/// YES while the reader overlay covers the page. The View menu reads it for its Show or Hide title.
@property BOOL readerOn;
@property (weak) BrowserState *state;

@property (readonly) NSString *displayTitle;
@property (readonly) BOOL isLoaded;

- (BrookWebView *)materialize;
/// Frees the web content process memory. The tab stays in the sidebar and reloads on demand.
- (void)unload;
/// Pinned tabs and favorites return to their home page when closed.
- (void)resetToHome;
- (void)load:(NSURL *)url;
- (void)reload;
/// Calls back with YES if the tab is doing something the user would notice if we unloaded it.
- (void)isBusy:(void (^)(BOOL busy))completion;
- (void)refreshFavicon;

@end
