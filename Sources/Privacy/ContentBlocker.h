#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

/// Blocks ads and trackers with the lists uBlock Origin Lite enables by default
/// (Resources/blocklist.lzfse, made by scripts/blocklist.sh), compiled once into one WebKit content rule list and cached.
/// WebKit matches it out of process for every web view sharing the user content controller.
/// A newer list from the "blocklist" release (refreshed daily by CI) is fetched at most once a
/// day and swapped in once compiled. The list is paused while an ad-blocking extension is installed.
@interface ContentBlocker : NSObject
@property (class, readonly) ContentBlocker *shared;
/// The installed extension the list is paused for (ExtensionManager.activeAdBlockerName), or nil.
@property (readonly) NSString *pausedFor;
/// uBlock Origin Lite's scriptlets (Resources/scriptlets-*.js, made by scripts/scriptlets.sh): page scripts for
/// what a URL rule can't block, such as YouTube's in-player ads. Empty while blocking is off or paused; sites with
/// blocking turned off skip them. WebViewFactory installs them with the other site scripts.
@property (readonly) NSArray<WKUserScript *> *scriptletScripts;
/// Looks up the cached rule list, compiling it first when the list changed (~4s, once).
- (void)load;
/// Runs the block once the rule list is attached (or failed to load, or is paused), so restored
/// tabs never load before blocking is in place.
- (void)whenReady:(dispatch_block_t)block;
@end
