#import "Brook.h"

#include <memory>
#include <vector>

// MARK: - Errors

NSErrorDomain const ExtensionInstallErrorDomain = @"BrookExtensionInstallError";
NSNotificationName const ExtensionManagerDidChangeNotification = @"BrookExtensionsDidChange";
NSNotificationName const ExtensionManagerActionDidChangeNotification = @"BrookExtensionActionDidChange";

NSError *ExtensionInstallErrorMake(ExtensionInstallErrorCode code, NSString *reason) {
    NSString *message;
    switch (code) {
        case ExtensionInstallErrorInvalidInput:
            message = @"That doesn’t look like a Chrome Web Store link or extension ID.";
            break;
        case ExtensionInstallErrorBadPackage:
            message = @"The extension package couldn’t be read.";
            break;
        case ExtensionInstallErrorDownloadFailed:
            message = [NSString stringWithFormat:@"Couldn’t download the extension: %@", reason ?: @""];
            break;
        case ExtensionInstallErrorCancelled:
            message = @"Cancelled.";
            break;
    }
    return [NSError errorWithDomain:ExtensionInstallErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

BOOL ExtensionInstallErrorIsCancelled(NSError *error) {
    return [error.domain isEqualToString:ExtensionInstallErrorDomain] && error.code == ExtensionInstallErrorCancelled;
}

namespace {

/// One saved extension: {"id", "folder", "name", "chromeWebStoreID"?, "hiddenFromToolbar"?}.
struct ExtensionRecord {
    NSString *identifier;   // JSON key "id"
    NSString *folder;
    NSString *name;
    NSString *chromeWebStoreID;   // nil when not from the store
    bool hiddenFromToolbar = false;

    static std::optional<ExtensionRecord> fromJSON(id obj) {
        if (![obj isKindOfClass:NSDictionary.class]) return std::nullopt;
        NSDictionary *d = obj;
        id i = d[@"id"], f = d[@"folder"], n = d[@"name"], c = d[@"chromeWebStoreID"];
        if (![i isKindOfClass:NSString.class] || ![f isKindOfClass:NSString.class] || ![n isKindOfClass:NSString.class]) {
            return std::nullopt;
        }
        if (c && c != NSNull.null && ![c isKindOfClass:NSString.class]) return std::nullopt;
        id h = d[@"hiddenFromToolbar"];
        return ExtensionRecord{i, f, n, [c isKindOfClass:NSString.class] ? c : nil,
                               [h isKindOfClass:NSNumber.class] && [h boolValue]};
    }

    NSDictionary *json() const {
        NSMutableDictionary *d = [@{@"id": identifier, @"folder": folder, @"name": name} mutableCopy];
        if (chromeWebStoreID) d[@"chromeWebStoreID"] = chromeWebStoreID;
        if (hiddenFromToolbar) d[@"hiddenFromToolbar"] = @YES;
        return d;
    }
};

} // namespace

// MARK: - CRX packages

@interface CRX : NSObject
/// Chrome packages are a zip with a signed header in front. Returns just the zip.
+ (NSData *)zipPayloadOf:(NSData *)data;
/// Extracts a zip with /usr/bin/ditto. Completion runs on the main queue.
+ (void)unzip:(NSURL *)zip to:(NSURL *)dest completion:(void (^)(NSError *error))completion;
@end

@implementation CRX

+ (NSData *)zipPayloadOf:(NSData *)data {
    if (data.length <= 16) return nil;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    auto u32 = [bytes](NSInteger o) -> NSInteger {
        return (NSInteger)bytes[o] | (NSInteger)bytes[o + 1] << 8 | (NSInteger)bytes[o + 2] << 16 | (NSInteger)bytes[o + 3] << 24;
    };
    if (bytes[0] == 0x50 && bytes[1] == 0x4B) return data; // already a zip
    if (!(bytes[0] == 0x43 && bytes[1] == 0x72 && bytes[2] == 0x32 && bytes[3] == 0x34)) return nil; // "Cr24"
    NSInteger offset;
    switch (u32(4)) {
        case 3: offset = 12 + u32(8); break;
        case 2: offset = 16 + u32(8) + u32(12); break;
        default: return nil;
    }
    if (!(offset < (NSInteger)data.length)) return nil;
    return [data subdataWithRange:NSMakeRange((NSUInteger)offset, data.length - (NSUInteger)offset)];
}

+ (void)unzip:(NSURL *)zip to:(NSURL *)dest completion:(void (^)(NSError *error))completion {
    NSError *error;
    if (![NSFileManager.defaultManager createDirectoryAtURL:dest withIntermediateDirectories:YES attributes:nil error:&error]) {
        completion(error);
        return;
    }
    NSTask *process = [NSTask new];
    process.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    process.arguments = @[@"-x", @"-k", zip.path, dest.path];
    process.terminationHandler = ^(NSTask *p) {
        int status = p.terminationStatus;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(status == 0 ? nil : ExtensionInstallErrorMake(ExtensionInstallErrorBadPackage, nil));
        });
    };
    if (![process launchAndReturnError:&error]) {
        process.terminationHandler = nil;
        completion(error);
    }
}

@end

// MARK: - Manager

/// Runs Chrome/Safari-style web extensions using WebKit's WKWebExtension API
/// (the same approach DuckDuckGo's browser uses).
/// Content blockers compile their rules and hand them to web views a moment after their
/// extension loads, and WebKit doesn't say when. -finishLoading watches for it by requesting
/// a tracker every blocker list covers, from a hidden web view, until the request is blocked.
static NSString *const kBlockProbeURL = @"https://www.google-analytics.com/collect?v=1&t=pageview";
static const NSTimeInterval kBlockProbeInterval = 0.1;
/// Stop waiting after this long (say, a blocker that doesn't list the probe, or no network).
static const NSTimeInterval kBlockProbeTimeout = 2;
/// How long to watch for a newly added blocker's rules (uBlock Origin Lite's first compile: ~10s).
static const NSTimeInterval kBlockVerifyTimeout = 60;
/// After the probe sees a new blocker block, wait this long before counting it, so tabs that were
/// already open have its rules too (they get them ~1s after a new web view). Overlap is harmless.
static const NSTimeInterval kBlockSettleDelay = 3;
/// An extension enabling at least this much declarativeNetRequest rule data counts as an ad blocker
/// (uBlock Origin Lite: ~5 MB).
static const unsigned long long kAdBlockerRulesetBytes = 100 * 1024;

@implementation ExtensionManager {
    std::vector<ExtensionRecord> _records;
    NSURL *_recordsURL;
    NSURL *_folder;
    BOOL _loaded;
    NSMutableArray<dispatch_block_t> *_waitingForLoad;
    WKWebView *_blockProbe;
    BOOL _blockingActive;   // a probe saw an extension block
    BOOL _verifying;
}

+ (ExtensionManager *)shared {
    static ExtensionManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ExtensionManager new]; });
    return shared;
}

- (instancetype)init {
    WKWebExtensionControllerConfiguration *config = WKWebExtensionControllerConfiguration.defaultConfiguration;
    config.webViewConfiguration.applicationNameForUserAgent = WebViewFactory.userAgentSuffix;
    WKWebExtensionController *controller = [[WKWebExtensionController alloc] initWithConfiguration:config];
    if ((self = [super init])) {
        _recordsURL = [AppPaths.support URLByAppendingPathComponent:@"extensions.json"];
        _folder = [AppPaths sub:@"Extensions"];
        _controller = controller;
        _controller.delegate = self;
    }
    return self;
}

- (NSArray<WKWebExtensionContext *> *)contexts {
    NSMutableArray *result = [NSMutableArray array];
    for (const auto &r : _records) {
        WKWebExtensionContext *c = [self contextForID:r.identifier];
        if (c) [result addObject:c];
    }
    return result;
}

- (WKWebExtensionContext *)contextForID:(NSString *)identifier {
    for (WKWebExtensionContext *c in _controller.extensionContexts) {
        if ([c.uniqueIdentifier isEqualToString:identifier]) return c;
    }
    return nil;
}

- (WKWebExtensionContext *)contextForChromeWebStoreID:(NSString *)chromeWebStoreID {
    for (const auto &r : _records) {
        if ([r.chromeWebStoreID isEqualToString:chromeWebStoreID]) return [self contextForID:r.identifier];
    }
    return nil;
}

// MARK: Loading

- (void)loadAll {
    NSData *data = [NSData dataWithContentsOfURL:_recordsURL];
    id list = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([list isKindOfClass:NSArray.class]) {
        // One malformed record rejects the whole file.
        std::vector<ExtensionRecord> decoded;
        bool ok = true;
        for (id item in (NSArray *)list) {
            auto r = ExtensionRecord::fromJSON(item);
            if (!r) { ok = false; break; }
            decoded.push_back(*r);
        }
        if (ok) _records = std::move(decoded);
    }
    if (!_records.empty()) [self makeBlockProbe];
    [self loadRecordAt:0 of:std::make_shared<std::vector<ExtensionRecord>>(_records)];
}

/// A hidden page for -probeBlockingSince:. Made before any extension loads, like the restored
/// tabs: web views that already exist get content blocker rules a good second later than new ones.
- (void)makeBlockProbe {
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    config.webExtensionController = _controller;
    _blockProbe = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10) configuration:config];
    [_blockProbe loadHTMLString:@"" baseURL:[NSURL URLWithString:@"https://brook.invalid/"]];
}

/// Loads records one at a time, yielding to the main queue between each.
- (void)loadRecordAt:(size_t)index of:(std::shared_ptr<std::vector<ExtensionRecord>>)records {
    if (index >= records->size()) {
        [self finishLoading];
        return;
    }
    ExtensionRecord r = (*records)[index];
    NSURL *base = [_folder URLByAppendingPathComponent:r.folder isDirectory:YES];
    __weak ExtensionManager *weakSelf = self;
    [WKWebExtension extensionWithResourceBaseURL:base completionHandler:^(WKWebExtension *ext, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ExtensionManager *self_ = weakSelf;
            if (!self_) return;
            NSError *loadError = error;
            if (ext) {
                [self_->_controller loadExtensionContext:[self_ makeContext:ext id:r.identifier] error:&loadError];
            }
            if (loadError) {
                NSLog(@"Brook: failed to load extension %@: %@", r.name, loadError);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf loadRecordAt:index + 1 of:records];
            });
        });
    }];
}

- (void)finishLoading {
    [self notify];
    // Asked of the extension, not the context: the context only reports rules once they're compiled.
    BOOL blocks = NO;
    for (WKWebExtensionContext *c in _controller.extensionContexts) {
        NSSet<WKWebExtensionPermission> *permissions = c.webExtension.requestedPermissions;
        blocks |= [permissions containsObject:WKWebExtensionPermissionDeclarativeNetRequest] ||
                  [permissions containsObject:WKWebExtensionPermissionDeclarativeNetRequestWithHostAccess];
    }
    if (!blocks) {
        [self markLoaded];
        return;
    }
    __weak ExtensionManager *weakSelf = self;
    [self probeBlockingSince:CACurrentMediaTime() timeout:kBlockProbeTimeout completion:^(BOOL blocked) {
        ExtensionManager *self_ = weakSelf;
        if (!self_) return;
        [self_ setBlockingActive:blocked];
        [self_ markLoaded];
        // Rules can take far longer on the first launch after an update (WebKit recompiles them).
        if (!blocked) [self_ verifyBlocking];
    }];
}

/// Watches (up to a minute) for extension blocking to take effect in a fresh web view: after an
/// extension is added, or when the launch probe timed out.
- (void)verifyBlocking {
    if (_verifying || _blockingActive || !self.adBlockerName) return;
    _verifying = YES;
    [self makeBlockProbe];
    __weak ExtensionManager *weakSelf = self;
    [self probeBlockingSince:CACurrentMediaTime() timeout:kBlockVerifyTimeout completion:^(BOOL blocked) {
        ExtensionManager *self_ = weakSelf;
        if (!self_) return;
        self_->_blockProbe = nil;
        if (!blocked) { self_->_verifying = NO; return; }
        // Web views that already existed get the rules a while after a new one like the probe.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBlockSettleDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ExtensionManager *s = weakSelf;
            if (!s) return;
            s->_verifying = NO;
            [s setBlockingActive:s.adBlockerName != nil];
        });
    }];
}

- (void)setBlockingActive:(BOOL)active {
    if (_blockingActive == active) return;
    _blockingActive = active;
    [self notify];
}

/// Blocked requests fail at once without touching the network; anything slower got through.
/// Tries every 0.1s, then (past the launch timeout) slows towards once a second.
- (void)probeBlockingSince:(CFTimeInterval)start timeout:(NSTimeInterval)timeout completion:(void (^)(BOOL blocked))completion {
    NSString *js = @"const t = performance.now();"
                    "return await new Promise(done => {"
                    "  const img = new Image();"
                    "  img.onload = () => done(false);"
                    "  img.onerror = () => done(performance.now() - t < 30);"
                    "  img.src = url + '&z=' + Math.random();"
                    "});";
    __weak ExtensionManager *weakSelf = self;
    [_blockProbe callAsyncJavaScript:js arguments:@{@"url": kBlockProbeURL} inFrame:nil inContentWorld:WKContentWorld.defaultClientWorld
                   completionHandler:^(id result, NSError *error) {
        ExtensionManager *self_ = weakSelf;
        if (!self_ || !self_->_blockProbe) return;
        // `error` is expected while the probe page is still loading; just try again.
        CFTimeInterval elapsed = CACurrentMediaTime() - start;
        if ([result isEqual:@YES] || elapsed > timeout) {
            completion([result isEqual:@YES]);
            return;
        }
        NSTimeInterval interval = elapsed < kBlockProbeTimeout ? kBlockProbeInterval : std::min(1.0, elapsed / 10);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf probeBlockingSince:start timeout:timeout completion:completion];
        });
    }];
}

- (void)markLoaded {
    _loaded = YES;
    _blockProbe = nil;
    NSArray<dispatch_block_t> *waiting = _waitingForLoad;
    _waitingForLoad = nil;
    for (dispatch_block_t block in waiting) block();
}

- (void)whenLoaded:(dispatch_block_t)block {
    if (_loaded) {
        block();
        return;
    }
    if (!_waitingForLoad) _waitingForLoad = [NSMutableArray array];
    [_waitingForLoad addObject:[block copy]];
}

- (NSString *)activeAdBlockerName { return _blockingActive ? self.adBlockerName : nil; }

/// The first loaded extension that looks like an ad blocker (enables sizeable declarativeNetRequest
/// rule files), whether or not its rules are in force yet.
- (NSString *)adBlockerName {
    for (const auto &r : _records) {
        WKWebExtensionContext *c = [self contextForID:r.identifier];
        if (!c || ![c.webExtension.requestedPermissions containsObject:WKWebExtensionPermissionDeclarativeNetRequest]) continue;
        if ([self rulesetBytes:c.webExtension in:[_folder URLByAppendingPathComponent:r.folder isDirectory:YES]] >= kAdBlockerRulesetBytes) {
            return c.webExtension.displayName ?: r.name;
        }
    }
    return nil;
}

/// Total size of the rule files an extension enables by default. Ad blockers ship megabytes of them;
/// extensions that only tweak headers or redirect a few URLs ship little or none.
- (unsigned long long)rulesetBytes:(WKWebExtension *)ext in:(NSURL *)base {
    id dnr = ext.manifest[@"declarative_net_request"];
    id resources = [dnr isKindOfClass:NSDictionary.class] ? dnr[@"rule_resources"] : nil;
    if (![resources isKindOfClass:NSArray.class]) return 0;
    unsigned long long total = 0;
    for (id item in (NSArray *)resources) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"enabled"] isEqual:@YES]) continue;
        id path = item[@"path"];
        if (![path isKindOfClass:NSString.class]) continue;
        NSURL *file = [base URLByAppendingPathComponent:[path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]];
        // Standardized so "../" can't point outside the extension's folder.
        if (![file.URLByStandardizingPath.path hasPrefix:base.URLByStandardizingPath.path]) continue;
        total += [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil].fileSize;
    }
    return total;
}

- (WKWebExtensionContext *)makeContext:(WKWebExtension *)ext id:(NSString *)identifier {
    WKWebExtensionContext *context = [WKWebExtensionContext contextForExtension:ext];
    context.uniqueIdentifier = identifier;
    for (WKWebExtensionMatchPattern *pattern in ext.allRequestedMatchPatterns) {
        [context setPermissionStatus:WKWebExtensionContextPermissionStatusGrantedExplicitly forMatchPattern:pattern expirationDate:nil];
    }
    for (WKWebExtensionPermission permission in ext.requestedPermissions) {
        [context setPermissionStatus:WKWebExtensionContextPermissionStatusGrantedExplicitly forPermission:permission expirationDate:nil];
    }
    context.inspectable = YES;
    context.hasAccessToPrivateData = YES;
    return context;
}

- (void)saveRecords {
    NSMutableArray *list = [NSMutableArray array];
    for (const auto &r : _records) [list addObject:r.json()];
    NSData *data = [NSJSONSerialization dataWithJSONObject:list options:0 error:nil];
    if (data) [data writeToURL:_recordsURL options:NSDataWritingAtomic error:nil];
}

- (void)notify {
    [NSNotificationCenter.defaultCenter postNotificationName:ExtensionManagerDidChangeNotification object:self];
}

// MARK: Installing

/// Accepts a Chrome Web Store URL or a bare 32-letter extension ID.
- (void)installFromChromeWebStore:(NSString *)input completion:(void (^)(NSError *error))completion {
    NSString *identifier = [ExtensionManager chromeIDInInput:input];
    if (!identifier) {
        completion(ExtensionInstallErrorMake(ExtensionInstallErrorInvalidInput, nil));
        return;
    }
    if ([self contextForChromeWebStoreID:identifier]) { completion(nil); return; }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://clients2.google.com/service/update2/crx?response=redirect&prodversion=138.0.0.0&acceptformat=crx2,crx3&x=id%%3D%@%%26uc",
        identifier]];
    __weak ExtensionManager *weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(ExtensionInstallErrorMake(ExtensionInstallErrorDownloadFailed, error.localizedDescription));
                return;
            }
            BOOL ok200 = [response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode == 200;
            if (!ok200 || data.length == 0) {
                completion(ExtensionInstallErrorMake(ExtensionInstallErrorDownloadFailed, @"the store didn’t return a package"));
                return;
            }
            NSURL *tmp = [NSFileManager.defaultManager.temporaryDirectory
                          URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.crx", identifier]];
            NSError *writeError;
            if (![data writeToURL:tmp options:0 error:&writeError]) {
                completion(writeError);
                return;
            }
            ExtensionManager *self_ = weakSelf;
            if (!self_) {
                [NSFileManager.defaultManager removeItemAtURL:tmp error:nil];
                return;
            }
            [self_ installFromURL:tmp chromeWebStoreID:identifier completion:^(NSError *installError) {
                [NSFileManager.defaultManager removeItemAtURL:tmp error:nil];
                completion(installError);
            }];
        });
    }];
    [task resume];
}

+ (NSString *)chromeIDInInput:(NSString *)input {
    NSRange r = [input rangeOfString:@"[a-p]{32}" options:NSRegularExpressionSearch];
    if (r.location == NSNotFound) return nil;
    return [input substringWithRange:r];
}

/// Installs from an unpacked folder, a .crx, or a .zip.
- (void)installFromURL:(NSURL *)source chromeWebStoreID:(NSString *)chromeWebStoreID
            completion:(void (^)(NSError *error))completion {
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSURL *dest = [_folder URLByAppendingPathComponent:identifier isDirectory:YES];
    NSFileManager *fm = NSFileManager.defaultManager;

    __weak ExtensionManager *weakSelf = self;
    void (^afterUnpack)(void) = ^{
        ExtensionManager *self_ = weakSelf;
        if (!self_) return;
        [self_ finishInstallAt:dest identifier:identifier chromeWebStoreID:chromeWebStoreID completion:completion];
    };

    BOOL isDir = NO;
    [fm fileExistsAtPath:source.path isDirectory:&isDir];
    if (isDir) {
        NSError *error;
        if (![fm copyItemAtURL:source toURL:dest error:&error]) { completion(error); return; }
        afterUnpack();
    } else {
        NSURL *zipURL;
        if ([source.pathExtension.lowercaseString isEqualToString:@"crx"]) {
            NSError *error;
            NSData *raw = [NSData dataWithContentsOfURL:source options:0 error:&error];
            if (!raw) { completion(error); return; }
            NSData *zip = [CRX zipPayloadOf:raw];
            if (!zip) { completion(ExtensionInstallErrorMake(ExtensionInstallErrorBadPackage, nil)); return; }
            zipURL = [fm.temporaryDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.zip", identifier]];
            if (![zip writeToURL:zipURL options:0 error:&error]) { completion(error); return; }
        } else {
            zipURL = source;
        }
        [CRX unzip:zipURL to:dest completion:^(NSError *error) {
            if (error) { completion(error); return; }
            if (![zipURL isEqual:source]) [NSFileManager.defaultManager removeItemAtURL:zipURL error:nil];
            afterUnpack();
        }];
    }
}

- (void)finishInstallAt:(NSURL *)dest identifier:(NSString *)identifier chromeWebStoreID:(NSString *)chromeWebStoreID
             completion:(void (^)(NSError *error))completion {
    NSFileManager *fm = NSFileManager.defaultManager;

    // Some zips wrap everything in one top-level folder.
    NSURL *root = dest;
    if (![fm fileExistsAtPath:[dest URLByAppendingPathComponent:@"manifest.json"].path]) {
        NSArray<NSURL *> *items = [fm contentsOfDirectoryAtURL:dest includingPropertiesForKeys:nil options:0 error:nil];
        if (items.count == 1 && [fm fileExistsAtPath:[items[0] URLByAppendingPathComponent:@"manifest.json"].path]) {
            root = items[0];
        }
    }
    [fm removeItemAtURL:[root URLByAppendingPathComponent:@"_metadata"] error:nil];

    __weak ExtensionManager *weakSelf = self;
    [WKWebExtension extensionWithResourceBaseURL:root completionHandler:^(WKWebExtension *ext, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ExtensionManager *self_ = weakSelf;
            if (!ext) {
                [NSFileManager.defaultManager removeItemAtURL:dest error:nil];
                completion(error ?: ExtensionInstallErrorMake(ExtensionInstallErrorBadPackage, nil));
                return;
            }
            if (!self_) return;
            [self_ confirmInstall:ext completion:^(BOOL confirmed) {
                ExtensionManager *strong = weakSelf;
                if (!confirmed) {
                    [NSFileManager.defaultManager removeItemAtURL:dest error:nil];
                    completion(ExtensionInstallErrorMake(ExtensionInstallErrorCancelled, nil));
                    return;
                }
                if (!strong) return;
                NSError *loadError;
                if (![strong->_controller loadExtensionContext:[strong makeContext:ext id:identifier] error:&loadError]) {
                    completion(loadError);
                    return;
                }
                NSString *relative = [root.path stringByReplacingOccurrencesOfString:[strong->_folder.path stringByAppendingString:@"/"]
                                                                          withString:@""];
                strong->_records.push_back(ExtensionRecord{identifier, relative, ext.displayName ?: @"Extension",
                                                           chromeWebStoreID});
                [strong saveRecords];
                [strong notify];
                [strong verifyBlocking];   // an ad blocker counts once its rules are seen blocking
                completion(nil);
            }];
        });
    }];
}

- (void)confirmInstall:(WKWebExtension *)ext completion:(void (^)(BOOL confirmed))completion {
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Add “%@”?", ext.displayName ?: @"this extension"];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSArray<NSString *> *perms = [ext.requestedPermissions.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSLiteralSearch];
    }];
    if (perms.count) [lines addObject:[@"Permissions: " stringByAppendingString:[perms componentsJoinedByString:@", "]]];
    NSMutableArray<NSString *> *hosts = [NSMutableArray array];
    for (WKWebExtensionMatchPattern *p in ext.allRequestedMatchPatterns) [hosts addObject:p.description];
    BOOL all = NO;
    for (NSString *h in hosts) {
        if ([h containsString:@"<all_urls>"] || [h hasPrefix:@"*://*/"]) { all = YES; break; }
    }
    if (all) {
        [lines addObject:@"It can read and change your data on all websites."];
    } else if (hosts.count) {
        NSArray *prefix = [hosts subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)6, hosts.count))];
        [lines addObject:[NSString stringWithFormat:@"Sites: %@%@", [prefix componentsJoinedByString:@", "],
                          hosts.count > 6 ? @"…" : @""]];
    }
    alert.informativeText = [lines componentsJoinedByString:@"\n\n"];
    [alert addButtonWithTitle:@"Add Extension"];
    [alert addButtonWithTitle:@"Cancel"];
    NSImage *icon = [ext iconForSize:NSMakeSize(64, 64)];
    if (icon) alert.icon = icon;
    NSWindow *w = self.window.window;
    if (w) {
        [alert beginSheetModalForWindow:w completionHandler:^(NSModalResponse response) {
            completion(response == NSAlertFirstButtonReturn);
        }];
        return;
    }
    completion([alert runModal] == NSAlertFirstButtonReturn);
}

- (void)uninstall:(WKWebExtensionContext *)context {
    [_controller unloadExtensionContext:context error:nil];
    for (auto it = _records.begin(); it != _records.end(); ++it) {
        if ([it->identifier isEqualToString:context.uniqueIdentifier]) {
            ExtensionRecord rec = *it;
            _records.erase(it);
            // Drop empty pieces.
            NSString *top = rec.folder;
            for (NSString *piece in [rec.folder componentsSeparatedByString:@"/"]) {
                if (piece.length) { top = piece; break; }
            }
            [NSFileManager.defaultManager removeItemAtURL:[_folder URLByAppendingPathComponent:top] error:nil];
            break;
        }
    }
    [self saveRecords];
    // Whatever blocked may be gone; another installed blocker has to prove itself again.
    _blockingActive = NO;
    [self notify];
    [self verifyBlocking];
}

- (BOOL)isInToolbar:(WKWebExtensionContext *)context {
    for (const auto &r : _records) {
        if ([r.identifier isEqualToString:context.uniqueIdentifier]) return !r.hiddenFromToolbar;
    }
    return YES;
}

- (void)setInToolbar:(BOOL)shown forContext:(WKWebExtensionContext *)context {
    for (auto &r : _records) {
        if (![r.identifier isEqualToString:context.uniqueIdentifier]) continue;
        if (r.hiddenFromToolbar == !shown) return;
        r.hiddenFromToolbar = !shown;
        [self saveRecords];
        [self notify];
        return;
    }
}

// MARK: Tab & window events

- (void)windowDidOpen:(BrowserWindowController *)w {
    self.window = w;
    [_controller didOpenWindow:w];
    [_controller didFocusWindow:w];
}

- (void)tabDidOpen:(BrowserTab *)tab {
    [_controller didOpenTab:tab];
}

- (void)tabWillClose:(BrowserTab *)tab {
    [_controller didCloseTab:tab windowIsClosing:NO];
}

- (void)tabDidActivate:(BrowserTab *)tab previous:(BrowserTab *)previous {
    if (!tab || !tab.isLoaded) return;
    id<WKWebExtensionTab> prev = (previous && previous.isLoaded) ? previous : nil;
    [_controller didActivateTab:tab previousActiveTab:prev];
}

- (void)tabDidChange:(BrowserTab *)tab properties:(WKWebExtensionTabChangedProperties)properties {
    if (!tab.isLoaded) return;
    [_controller didChangeTabProperties:properties forTab:tab];
}

// MARK: WKWebExtensionControllerDelegate

- (NSArray<id<WKWebExtensionWindow>> *)webExtensionController:(WKWebExtensionController *)controller
                               openWindowsForExtensionContext:(WKWebExtensionContext *)extensionContext {
    BrowserWindowController *window = self.window;
    if (!window) return @[];
    return @[window];
}

- (id<WKWebExtensionWindow>)webExtensionController:(WKWebExtensionController *)controller
                  focusedWindowForExtensionContext:(WKWebExtensionContext *)extensionContext {
    return self.window;
}

- (void)webExtensionController:(WKWebExtensionController *)controller
  openNewTabUsingConfiguration:(WKWebExtensionTabConfiguration *)configuration
           forExtensionContext:(WKWebExtensionContext *)extensionContext
             completionHandler:(void (^)(id<WKWebExtensionTab> newTab, NSError *error))completionHandler {
    BrowserTab *tab = [BrowserState.shared openTabWithURL:configuration.url inSpace:nil after:nil select:YES loadNow:NO];
    [tab materialize];
    completionHandler(tab, nil);
}

- (void)webExtensionController:(WKWebExtensionController *)controller
openNewWindowUsingConfiguration:(WKWebExtensionWindowConfiguration *)configuration
           forExtensionContext:(WKWebExtensionContext *)extensionContext
             completionHandler:(void (^)(id<WKWebExtensionWindow> newWindow, NSError *error))completionHandler {
    for (NSURL *url in configuration.tabURLs) {
        [BrowserState.shared openTabWithURL:url inSpace:nil after:nil select:YES loadNow:NO];
    }
    completionHandler(self.window, nil);
}

- (void)webExtensionController:(WKWebExtensionController *)controller
openOptionsPageForExtensionContext:(WKWebExtensionContext *)extensionContext
             completionHandler:(void (^)(NSError *error))completionHandler {
    NSURL *url = extensionContext.optionsPageURL;
    if (url) [BrowserState.shared openTabWithURL:url inSpace:nil after:nil select:YES loadNow:NO];
    completionHandler(nil);
}

- (void)webExtensionController:(WKWebExtensionController *)controller
               didUpdateAction:(WKWebExtensionAction *)action
           forExtensionContext:(WKWebExtensionContext *)context {
    [NSNotificationCenter.defaultCenter postNotificationName:ExtensionManagerActionDidChangeNotification object:context];
}

- (void)webExtensionController:(WKWebExtensionController *)controller
         presentPopupForAction:(WKWebExtensionAction *)action
           forExtensionContext:(WKWebExtensionContext *)context
             completionHandler:(void (^)(NSError *error))completionHandler {
    [self.window presentExtensionPopup:action];
    completionHandler(nil);
}

- (void)webExtensionController:(WKWebExtensionController *)controller
          promptForPermissions:(NSSet<WKWebExtensionPermission> *)permissions
                         inTab:(id<WKWebExtensionTab>)tab
           forExtensionContext:(WKWebExtensionContext *)extensionContext
             completionHandler:(void (^)(NSSet<WKWebExtensionPermission> *allowedPermissions, NSDate *expirationDate))completionHandler {
    completionHandler(permissions, nil);
}

- (void)webExtensionController:(WKWebExtensionController *)controller
promptForPermissionToAccessURLs:(NSSet<NSURL *> *)urls
                         inTab:(id<WKWebExtensionTab>)tab
           forExtensionContext:(WKWebExtensionContext *)extensionContext
             completionHandler:(void (^)(NSSet<NSURL *> *allowedURLs, NSDate *expirationDate))completionHandler {
    completionHandler(urls, nil);
}

- (void)webExtensionController:(WKWebExtensionController *)controller
promptForPermissionMatchPatterns:(NSSet<WKWebExtensionMatchPattern *> *)matchPatterns
                         inTab:(id<WKWebExtensionTab>)tab
           forExtensionContext:(WKWebExtensionContext *)extensionContext
             completionHandler:(void (^)(NSSet<WKWebExtensionMatchPattern *> *allowedMatchPatterns, NSDate *expirationDate))completionHandler {
    completionHandler(matchPatterns, nil);
}

@end

// MARK: - "Add to Brook" button on the Chrome Web Store

@implementation ChromeWebStoreBridge {
    WKContentWorld *_world;
    WKUserScript *_userScript;
    BOOL _userScriptLoaded;
}

+ (ChromeWebStoreBridge *)shared {
    static ChromeWebStoreBridge *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ChromeWebStoreBridge new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _world = [WKContentWorld worldWithName:@"BrookStore"];
    }
    return self;
}

- (WKUserScript *)userScript {
    if (!_userScriptLoaded) {
        _userScriptLoaded = YES;
        NSURL *url = [NSBundle.mainBundle URLForResource:@"chrome-web-store" withExtension:@"js"];
        NSString *source = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
        if (source) {
            _userScript = [[WKUserScript alloc] initWithSource:source
                                                 injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                              forMainFrameOnly:YES
                                                inContentWorld:_world];
        }
    }
    return _userScript;
}

- (void)installHandlersInto:(WKUserContentController *)ucc {
    [ucc addScriptMessageHandlerWithReply:self contentWorld:_world name:@"brookStore"];
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
                 replyHandler:(void (^)(id reply, NSString *errorMessage))replyHandler {
    NSDictionary *body = [message.body isKindOfClass:NSDictionary.class] ? message.body : nil;
    NSString *action = [body[@"action"] isKindOfClass:NSString.class] ? body[@"action"] : nil;
    NSString *identifier = [body[@"id"] isKindOfClass:NSString.class] ? [ExtensionManager chromeIDInInput:body[@"id"]] : nil;
    if (![BrookHost(message.webView.URL) isEqualToString:@"chromewebstore.google.com"] || !action || !identifier) {
        replyHandler(nil, @"Bad request");
        return;
    }
    ExtensionManager *manager = ExtensionManager.shared;
    void (^replyState)(void) = ^{
        replyHandler([manager contextForChromeWebStoreID:identifier] ? @"installed" : @"not-installed", nil);
    };
    if ([action isEqualToString:@"install"]) {
        [manager installFromChromeWebStore:identifier completion:^(NSError *error) {
            if (!error) {
                [manager.window showToast:@"Extension added"];
            } else if (!ExtensionInstallErrorIsCancelled(error)) {
                [manager.window showError:error];
            }
            replyState();
        }];
    } else if ([action isEqualToString:@"remove"]) {
        if (WKWebExtensionContext *context = [manager contextForChromeWebStoreID:identifier]) {
            [manager uninstall:context];
            [manager.window showToast:@"Extension removed"];
        }
        replyState();
    } else {
        replyState();
    }
}

@end
