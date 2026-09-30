#import "Brook.h"

/// Newer lists: published by .github/workflows/blocklist.yml once a day (only when they changed).
static NSString *const kUpdateURL = @"https://github.com/AxxzyWasTaken/brook/releases/download/blocklist/blocklist.lzfse";
static const NSTimeInterval kUpdateInterval = 24 * 60 * 60;
/// Wait this long after launch before the first check, so it never competes with startup.
static const NSTimeInterval kFirstCheckDelay = 60;
/// A download bigger than this is refused (the real list is ~1.7 MB).
static const unsigned long long kMaxDownload = 16 << 20;
static NSString *const kETagKey = @"blocklistETag";
static NSString *const kLastCheckKey = @"blocklistLastCheck";

/// A list's compiled copy is named after the file's size and date, so a new file gets a new copy.
static NSString *IdentifierFor(NSURL *file) {
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
    if (!attrs) return nil;
    return [NSString stringWithFormat:@"blocklist-%llu-%.0f", attrs.fileSize, attrs.fileModificationDate.timeIntervalSince1970];
}

static NSDate *ModificationDate(NSURL *file) {
    return file ? [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil].fileModificationDate : nil;
}

/// An HTTP date header ("Mon, 28 Sep 2026 19:06:31 GMT") as a date, or nil.
static NSDate *HTTPDate(NSString *value) {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        f.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
    });
    return value ? [f dateFromString:value] : nil;
}

@implementation ContentBlocker {
    WKContentRuleList *_list;       // the newest compiled list
    WKContentRuleList *_attached;   // what the content controller has (nil when off or paused)
    BOOL _compiling;
    BOOL _updating;
    NSMutableArray<dispatch_block_t> *_waiting;   // nil once ready
    NSTimer *_updateTimer;
}

+ (ContentBlocker *)shared {
    static ContentBlocker *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ContentBlocker new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) _waiting = [NSMutableArray array];
    return self;
}

- (NSURL *)bundledFile { return [NSBundle.mainBundle URLForResource:@"blocklist" withExtension:@"lzfse"]; }
- (NSURL *)blocklistFolder { return [AppPaths sub:@"Blocklist"]; }
- (NSURL *)downloadedFile { return [self.blocklistFolder URLByAppendingPathComponent:@"blocklist.lzfse"]; }

/// The downloaded list while it's newer than the app's own; an app update with a newer one deletes it.
- (NSURL *)currentFile {
    NSURL *bundled = self.bundledFile, *downloaded = self.downloadedFile;
    NSDate *d = ModificationDate(downloaded), *b = ModificationDate(bundled);
    if (!d) return bundled;
    if (!b || [d compare:b] == NSOrderedDescending) return downloaded;
    [NSFileManager.defaultManager removeItemAtURL:downloaded error:nil];
    return bundled;
}

- (void)load {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(settingsChanged:) name:BrookSettingsDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(extensionsChanged) name:ExtensionManagerDidChangeNotification object:nil];
    [self compileCurrent];
    [self scheduleUpdateCheck];
}

- (void)compileCurrent {
    if (_list || _compiling) return;
    NSURL *file = self.currentFile;
    if (!file) return [self becomeReady];
    _compiling = YES;
    [self compile:file completion:^(WKContentRuleList *list) {
        self->_compiling = NO;
        if (list && !self->_list) [self use:list];   // an update may have landed meanwhile
        [self becomeReady];
    }];
}

/// Looks up the file's compiled list, compiling it when there isn't one. Completion runs on the main queue.
- (void)compile:(NSURL *)file completion:(void (^)(WKContentRuleList *list))completion {
    NSString *identifier = IdentifierFor(file);
    if (!identifier) return completion(nil);
    WKContentRuleListStore *store = WKContentRuleListStore.defaultStore;
    [store lookUpContentRuleListForIdentifier:identifier completionHandler:^(WKContentRuleList *found, NSError *) {
        if (found) return completion(found);
        // Only a cold start gets here: reading the 17 MB of JSON off the main thread.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *json;
            @autoreleasepool {
                NSData *packed = [NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:nil];
                NSData *data = [packed decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
                json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!json) { NSLog(@"Brook: couldn't read blocklist %@", file.path); return completion(nil); }
                [store compileContentRuleListForIdentifier:identifier encodedContentRuleList:json
                                         completionHandler:^(WKContentRuleList *compiled, NSError *error) {
                    if (error) NSLog(@"Brook: couldn't compile blocklist: %@", error);
                    completion(compiled);
                }];
            });
        });
    }];
}

/// Makes `list` the one in use and drops every other compiled copy (older lists, the old per-list ones).
- (void)use:(WKContentRuleList *)list {
    _list = list;
    [self apply];
    WKContentRuleListStore *store = WKContentRuleListStore.defaultStore;
    NSString *keep = list.identifier;
    [store getAvailableContentRuleListIdentifiers:^(NSArray<NSString *> *identifiers) {
        for (NSString *identifier in identifiers) {
            if (![identifier isEqualToString:keep]) [store removeContentRuleListForIdentifier:identifier completionHandler:^(NSError *) {}];
        }
    }];
}

- (void)becomeReady {
    NSArray<dispatch_block_t> *waiting = _waiting;
    _waiting = nil;
    for (dispatch_block_t block in waiting) block();
}

- (void)whenReady:(dispatch_block_t)block {
    if (_waiting) [_waiting addObject:[block copy]]; else block();
}

/// Attaches the list while blocking is on and no extension blocks instead. A new list goes on before
/// the old one comes off, so swapping never leaves pages unblocked. Open pages change on their next load.
- (void)apply {
    WKContentRuleList *want = Settings.blockAds && !_pausedFor ? _list : nil;
    if (want == _attached) return;
    WKUserContentController *ucc = WebViewFactory.userContentController;
    if (want) [ucc addContentRuleList:want];
    if (_attached) [ucc removeContentRuleList:_attached];
    _attached = want;
}

- (void)settingsChanged:(NSNotification *)note {
    NSString *key = note.userInfo[@"key"];
    if ([key isEqual:@"blockAds"] || [key isEqual:@"*"]) [self apply];
    // The scriptlets follow the switch too (AppDelegate reloads the scripts for "*" and "siteSettings").
    if ([key isEqual:@"blockAds"]) [WebViewFactory reloadSiteScripts];
}

// MARK: Scriptlets

/// A bundle's source, read once. The files are ~0.7 and ~0.5 MB.
static NSString *ScriptletSource(NSString *world) {
    NSURL *url = [NSBundle.mainBundle URLForResource:[@"scriptlets-" stringByAppendingString:world] withExtension:@"js"];
    return url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
}

/// JS that's true when the top page's site has ad blocking turned off, resolved like SiteSettings (the nearest
/// parent domain with a setting wins). Frames go by the top page, as the content rule list does.
static NSString *SiteOffCheck() {
    NSMutableDictionary<NSString *, NSNumber *> *set = [NSMutableDictionary dictionary];
    [SiteSettings.all enumerateKeysAndObjectsUsingBlock:^(NSString *key, SiteOverride *o, BOOL *) {
        if (o.blockAds) set[key] = o.blockAds;
    }];
    if (![set.allValues containsObject:@NO]) return nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:set options:NSJSONWritingSortedKeys error:nil];
    return [NSString stringWithFormat:
        @"((s) => { const a = location.ancestorOrigins;"
         " let h = a && a.length ? new URL(a[a.length - 1]).hostname : location.hostname;"
         " for (;;) { if (h in s) return !s[h]; const i = h.indexOf('.'); if (i < 0) return false; h = h.slice(i + 1); }"
         " })(%@)", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
}

- (NSArray<WKUserScript *> *)scriptletScripts {
    static NSString *mainSource, *isolatedSource;
    static NSArray<WKUserScript *> *cached;
    static NSString *cachedCheck;
    if (!Settings.blockAds || _pausedFor) return @[];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mainSource = ScriptletSource(@"main");
        isolatedSource = ScriptletSource(@"isolated");
    });
    NSString *check = SiteOffCheck();
    if (cached && (check == cachedCheck || [check isEqualToString:cachedCheck])) return cached;
    // Each bundle is one IIFE that looks up the frame's hostname in its own table and runs only the scriptlets
    // listed for it, so it goes into every frame at document start, before the page's scripts. Main-world ones
    // patch the page's own functions (fetch, XHR, JSON.parse); isolated ones only touch the DOM and storage.
    WKUserScript *(^make)(NSString *, WKContentWorld *) = ^WKUserScript *(NSString *source, WKContentWorld *world) {
        if (!source) return nil;
        if (check) source = [NSString stringWithFormat:@"if (!%@) {\n%@\n}", check, source];
        return [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                   forMainFrameOnly:NO inContentWorld:world];
    };
    NSMutableArray<WKUserScript *> *scripts = [NSMutableArray array];
    if (WKUserScript *s = make(mainSource, WKContentWorld.pageWorld)) [scripts addObject:s];
    if (WKUserScript *s = make(isolatedSource, [WKContentWorld worldWithName:@"BrookScriptlets"])) [scripts addObject:s];
    cached = scripts;
    cachedCheck = check;
    return cached;
}

/// Running both would block twice and, worse, one blocker's exceptions can't override the other's
/// blocks, so a site the extension allows (or the user allowed in it) still breaks. The extension is the
/// user's explicit choice, so it wins while installed; Brook's list comes back when it's removed.
/// ExtensionManager only reports it once its rules are seen blocking (a fresh uBlock Origin Lite takes
/// ~10s to compile), so there's no moment with neither blocking.
- (void)extensionsChanged {
    NSString *name = ExtensionManager.shared.activeAdBlockerName;
    if (name == _pausedFor || [name isEqualToString:_pausedFor]) return;
    _pausedFor = name;
    [self apply];
    [WebViewFactory reloadSiteScripts];
    [Settings notify:@"contentBlocker"];
}

// MARK: Updates

- (void)scheduleUpdateCheck {
    NSDate *last = [NSUserDefaults.standardUserDefaults objectForKey:kLastCheckKey];
    NSTimeInterval wait = [last isKindOfClass:NSDate.class] ? kUpdateInterval + last.timeIntervalSinceNow : 0;
    [_updateTimer invalidate];
    __weak ContentBlocker *weakSelf = self;
    _updateTimer = [NSTimer scheduledTimerWithTimeInterval:std::max(wait, kFirstCheckDelay) repeats:NO block:^(NSTimer *) {
        [weakSelf checkForUpdate];
    }];
    _updateTimer.tolerance = 600;   // lets macOS batch the wake-up with others
}

/// Asks for the list with the last ETag (GitHub answers 304 Not Modified when unchanged), then compiles
/// a newer one before swapping it in. Any failure keeps the current list; the next try is a day later.
- (void)checkForUpdate {
    if (_updating || _compiling) return [self scheduleUpdateCheck];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // Nothing to fetch while paused: the list isn't used, and the extension updates its own.
    if (_pausedFor) {
        [defaults setObject:NSDate.date forKey:kLastCheckKey];
        return [self scheduleUpdateCheck];
    }
    _updating = YES;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kUpdateURL]];
    request.timeoutInterval = 60;
    request.networkServiceType = NSURLNetworkServiceTypeBackground;
    NSString *etag = [defaults stringForKey:kETagKey];
    if (etag) [request setValue:etag forHTTPHeaderField:@"If-None-Match"];
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.URLCache = nil;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSURL *staged = [self.blocklistFolder URLByAppendingPathComponent:@"download.lzfse"];
    [[session downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        // `location` is deleted when this returns, so move it now.
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSFileManager *fm = NSFileManager.defaultManager;
        BOOL ok = NO;
        if (!error && http.statusCode == 200 && location) {
            unsigned long long size = [fm attributesOfItemAtPath:location.path error:nil].fileSize;
            [fm removeItemAtURL:staged error:nil];
            ok = size > 0 && size <= kMaxDownload && [fm moveItemAtURL:location toURL:staged error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [session finishTasksAndInvalidate];
            [defaults setObject:NSDate.date forKey:kLastCheckKey];
            [self receivedUpdate:ok ? staged : nil response:http];
        });
    }] resume];
}

- (void)receivedUpdate:(NSURL *)staged response:(NSHTTPURLResponse *)http {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDate *published = HTTPDate([http valueForHTTPHeaderField:@"Last-Modified"]);
    NSDate *current = ModificationDate(self.currentFile);
    BOOL newer = staged && published && (!current || [published compare:current] == NSOrderedDescending);
    // Stamped with its publish date, which currentFile compares and the compiled copy is named after.
    if (!newer || ![fm setAttributes:@{NSFileModificationDate: published} ofItemAtPath:staged.path error:nil]) {
        // No newer than ours (say, the list this build shipped with): skip it until it changes.
        if (staged && published) [self rememberETag:http];
        if (staged) [fm removeItemAtURL:staged error:nil];
        return [self finishUpdate];
    }
    [self compile:staged completion:^(WKContentRuleList *list) {
        // Only a list that compiled replaces the current one (rename swaps it in atomically).
        if (list && rename(staged.fileSystemRepresentation, self.downloadedFile.fileSystemRepresentation) == 0) {
            [self rememberETag:http];
            [self use:list];
        } else {
            [fm removeItemAtURL:staged error:nil];
            if (list) [WKContentRuleListStore.defaultStore removeContentRuleListForIdentifier:list.identifier completionHandler:^(NSError *) {}];
        }
        [self finishUpdate];
    }];
}

- (void)rememberETag:(NSHTTPURLResponse *)http {
    NSString *etag = [http valueForHTTPHeaderField:@"ETag"];
    if (etag) [NSUserDefaults.standardUserDefaults setObject:etag forKey:kETagKey];
}

- (void)finishUpdate {
    _updating = NO;
    [self scheduleUpdateCheck];
}

@end
