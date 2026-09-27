#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

/// Blocks ads and trackers with AdGuard's lists (Resources/blocklist.json, made by
/// scripts/blocklist.sh), compiled once into a WebKit content rule list and cached.
/// WebKit applies it out of process to every web view sharing the user content controller.
@interface ContentBlocker : NSObject
@property (class, readonly) ContentBlocker *shared;
/// Looks up the cached rule list, compiling it first when the bundled list changed (~4s, once).
- (void)load;
/// Runs the block once the rule list is attached (or failed to load), so restored tabs
/// never load before blocking is in place.
- (void)whenReady:(dispatch_block_t)block;
@end
