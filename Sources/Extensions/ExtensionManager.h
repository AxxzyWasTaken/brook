#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
// Other-directory headers come in via Brook.h (import order there).

@class BrowserWindowController;

// MARK: - Errors

/// Extension install failures. localizedDescription carries the user-facing message.
FOUNDATION_EXPORT NSErrorDomain const ExtensionInstallErrorDomain;
typedef NS_ERROR_ENUM(ExtensionInstallErrorDomain, ExtensionInstallErrorCode) {
    ExtensionInstallErrorInvalidInput = 1,  // "That doesn’t look like a Chrome Web Store link or extension ID."
    ExtensionInstallErrorBadPackage,        // "The extension package couldn’t be read."
    ExtensionInstallErrorDownloadFailed,    // "Couldn’t download the extension: <reason>"
    ExtensionInstallErrorCancelled,         // "Cancelled."
};
/// Builds an ExtensionInstallErrorDomain error with the right message. `reason` is only used by DownloadFailed.
FOUNDATION_EXPORT NSError *ExtensionInstallErrorMake(ExtensionInstallErrorCode code, NSString *reason);
/// YES for the user-cancelled error (callers show nothing in that case).
FOUNDATION_EXPORT BOOL ExtensionInstallErrorIsCancelled(NSError *error);

/// Posted when extensions change ("BrookExtensionsDidChange"), object = the manager.
FOUNDATION_EXPORT NSNotificationName const ExtensionManagerDidChangeNotification;
/// Posted when an extension changes its toolbar button (icon, badge, label, enabled), object = its
/// WKWebExtensionContext.
FOUNDATION_EXPORT NSNotificationName const ExtensionManagerActionDidChangeNotification;

// MARK: - Manager

/// Runs Chrome/Safari-style web extensions using WebKit's WKWebExtension API
/// (the same approach DuckDuckGo's browser uses).
@interface ExtensionManager : NSObject <WKWebExtensionControllerDelegate>
@property (class, readonly) ExtensionManager *shared;

@property (readonly) WKWebExtensionController *controller;
/// The (single) browser window, as seen by extensions.
@property (weak) BrowserWindowController *window;
/// Loaded contexts, in install order.
@property (readonly) NSArray<WKWebExtensionContext *> *contexts;
- (WKWebExtensionContext *)contextForID:(NSString *)identifier;
/// The loaded extension installed from the Chrome Web Store with this ID, or nil.
- (WKWebExtensionContext *)contextForChromeWebStoreID:(NSString *)chromeWebStoreID;

/// Loads every installed extension (async; posts ExtensionManagerDidChangeNotification when done).
- (void)loadAll;
/// Runs `block` on the main queue once installed extensions have loaded (straight away if they
/// already have). Pages loaded before then would skip content blockers such as uBlock Origin Lite.
- (void)whenLoaded:(dispatch_block_t)block;
/// The installed ad-blocking extension (enables sizeable declarativeNetRequest rule files, like
/// uBlock Origin Lite or AdGuard) once a probe has seen its rules block, or nil. Posts
/// ExtensionManagerDidChangeNotification when it changes. ContentBlocker pauses Brook's list for it.
@property (readonly) NSString *activeAdBlockerName;

/// Accepts a Chrome Web Store URL or a bare 32-letter extension ID. Completion runs on the main
/// queue; error is nil on success (also when the extension is already installed).
- (void)installFromChromeWebStore:(NSString *)input completion:(void (^)(NSError *error))completion;
/// The 32-letter [a-p] Chrome extension ID in a URL or string, or nil.
+ (NSString *)chromeIDInInput:(NSString *)input;
/// Installs from an unpacked folder, a .crx, or a .zip (asks the user first). chromeWebStoreID may be nil.
- (void)installFromURL:(NSURL *)source chromeWebStoreID:(NSString *)chromeWebStoreID
            completion:(void (^)(NSError *error))completion;
- (void)uninstall:(WKWebExtensionContext *)context;
/// Whether the extension's button shows in the toolbar (default YES); hidden ones stay in the
/// "…" menu. Setting it saves and posts ExtensionManagerDidChangeNotification.
- (BOOL)isInToolbar:(WKWebExtensionContext *)context;
- (void)setInToolbar:(BOOL)shown forContext:(WKWebExtensionContext *)context;

// Tab & window events
- (void)windowDidOpen:(BrowserWindowController *)window;
- (void)tabDidOpen:(BrowserTab *)tab;
- (void)tabWillClose:(BrowserTab *)tab;
/// Either may be nil; ignored unless `tab` is loaded.
- (void)tabDidActivate:(BrowserTab *)tab previous:(BrowserTab *)previous;
- (void)tabDidChange:(BrowserTab *)tab properties:(WKWebExtensionTabChangedProperties)properties;
@end

// MARK: - "Add to Brook" button on the Chrome Web Store

/// Backs the store page's "Add to Brook" / "Remove from Brook" button (chrome-web-store.js).
/// The page posts {action: status|install|remove, id} to "brookStore" and gets back
/// "installed" or "not-installed".
@interface ChromeWebStoreBridge : NSObject <WKScriptMessageHandlerWithReply>
@property (class, readonly) ChromeWebStoreBridge *shared;
/// chrome-web-store.js from the app bundle (lazy; nil if missing), in the "BrookStore" world.
@property (readonly) WKUserScript *userScript;
- (void)installHandlersInto:(WKUserContentController *)ucc;
@end

// MARK: - Conformances (ExtensionConformances.mm)

/// Tabs, as seen by extensions. Implemented in ExtensionConformances.mm.
@interface BrowserTab (Extensions) <WKWebExtensionTab>
@end

// `BrowserWindowController (Extensions) <WKWebExtensionWindow>` is declared at the end of
// BrowserWindowController.h (the class must be defined first) and also implemented in ExtensionConformances.mm.
