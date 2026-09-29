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
    TabChangeMuted = 1 << 9,
};

/// Errors from tab actions that Brook cannot do ("BrookTabError").
FOUNDATION_EXPORT NSErrorDomain const BrowserTabErrorDomain;
/// Builds a BrowserTabErrorDomain error with this message.
NSError *BrowserTabError(NSString *message);

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
/// The tab that opened this one (a link, a popup, Duplicate Tab or an extension). Extensions read it as openerTabId.
@property (weak) BrowserTab *parentTab;
/// YES when the user or an extension muted the tab. The value stays when the tab unloads and applies again when it loads.
@property (readonly) BOOL isMuted;
/// NO when this WebKit has no page mute. Then setMuted:error: always fails.
@property (class, readonly) BOOL canMute;

@property (readonly) NSString *displayTitle;
@property (readonly) BOOL isLoaded;

/// Mutes or unmutes the page audio. Returns NO and sets `error` when WebKit has no page mute.
- (BOOL)setMuted:(BOOL)muted error:(NSError **)error;
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
