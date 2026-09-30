#import "Brook.h"

// MARK: - History

@interface HistoryEntry ()
+ (instancetype)fromJSON:(NSDictionary *)d;
- (NSDictionary *)toJSON;
@end

@implementation HistoryEntry

/// nil when a key is missing or has the wrong type.
+ (instancetype)fromJSON:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    id url = d[@"url"], title = d[@"title"], visits = d[@"visits"], last = d[@"last"];
    if (![url isKindOfClass:NSString.class] || ![title isKindOfClass:NSString.class] ||
        ![visits isKindOfClass:NSNumber.class] || ![last isKindOfClass:NSNumber.class]) return nil;
    double v = [visits doubleValue];
    if (v != floor(v)) return nil;   // integers only
    HistoryEntry *e = [HistoryEntry new];
    e.url = url;
    e.title = title;
    e.visits = (NSInteger)v;
    e.last = [NSDate dateWithTimeIntervalSinceReferenceDate:[last doubleValue]];
    return e;
}

/// `last` is seconds since the 2001 reference date.
- (NSDictionary *)toJSON {
    return @{@"url": _url ?: @"", @"title": _title ?: @"", @"visits": @(_visits),
             @"last": @(_last.timeIntervalSinceReferenceDate)};
}

@end

@implementation HistoryStore {
    NSMutableDictionary<NSString *, HistoryEntry *> *_entries;
    NSURL *_fileURL;
    Debouncer *_saver;
    NSInteger _limit;
}

+ (HistoryStore *)shared {
    static HistoryStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [HistoryStore new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _entries = [NSMutableDictionary dictionary];
        _fileURL = [AppPaths.support URLByAppendingPathComponent:@"history.json"];
        _saver = [[Debouncer alloc] initWithDelay:5];
        _limit = 20000;
        NSData *data = [NSData dataWithContentsOfURL:_fileURL];
        NSArray *list = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([list isKindOfClass:NSArray.class]) {
            NSMutableArray<HistoryEntry *> *decoded = [NSMutableArray array];
            BOOL ok = YES;
            for (id item in list) {
                HistoryEntry *e = [HistoryEntry fromJSON:item];
                if (!e) { ok = NO; break; }   // one bad element rejects the whole list
                [decoded addObject:e];
            }
            if (ok) for (HistoryEntry *e in decoded) _entries[e.url] = e;
        }
    }
    return self;
}

- (void)recordURL:(NSURL *)url title:(NSString *)title {
    NSString *scheme = url.scheme;
    if (!scheme || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return;
    NSString *key = url.absoluteString;
    HistoryEntry *e = _entries[key];
    if (!e) {
        e = [HistoryEntry new];
        e.url = key;
        e.title = @"";
        e.visits = 0;
        e.last = [NSDate date];
    }
    e.visits += 1;
    e.last = [NSDate date];
    if (title.length) e.title = title;
    _entries[key] = e;
    [self scheduleSave];
}

- (void)updateTitle:(NSString *)title forURL:(NSURL *)url {
    NSString *key = url.absoluteString;
    HistoryEntry *e = key ? _entries[key] : nil;
    if (!e || [e.title isEqualToString:title]) return;
    e.title = title;
    [self scheduleSave];
}

/// Simple frecency ranking: matches in the host or title, weighted by visits and recency.
- (NSArray<HistoryEntry *> *)search:(NSString *)query limit:(NSInteger)limit {
    NSString *q = BrookTrim(query.lowercaseString);
    if (q.length == 0) return @[];
    NSDate *now = [NSDate date];
    std::vector<std::pair<HistoryEntry *, double>> scored;
    for (HistoryEntry *e in _entries.objectEnumerator) {
        NSString *u = e.url.lowercaseString;
        NSString *t = e.title.lowercaseString;
        NSString *stripped = [[[u stringByReplacingOccurrencesOfString:@"https://" withString:@""]
                                  stringByReplacingOccurrencesOfString:@"http://" withString:@""]
                                  stringByReplacingOccurrencesOfString:@"www." withString:@""];
        double score;
        if ([stripped hasPrefix:q]) score = 4;
        else if ([t hasPrefix:q]) score = 3;
        else if ([u containsString:q] || [t containsString:q]) score = 1;
        else continue;
        double ageDays = [now timeIntervalSinceDate:e.last] / 86400;
        score *= log2((double)e.visits + 1) + 1;
        score /= (1 + ageDays / 14);
        scored.emplace_back(e, score);
    }
    std::stable_sort(scored.begin(), scored.end(), [](const auto &a, const auto &b) { return a.second > b.second; });
    NSMutableArray *out = [NSMutableArray array];
    for (size_t i = 0; i < scored.size() && (NSInteger)i < limit; i++) [out addObject:scored[i].first];
    return out;
}

- (NSArray<HistoryEntry *> *)search:(NSString *)query { return [self search:query limit:6]; }

- (void)clear {
    [_entries removeAllObjects];
    [_saver flush:^{ [self saveNow]; }];
}

- (void)scheduleSave {
    __weak HistoryStore *weakSelf = self;
    [_saver call:^{ [weakSelf saveNow]; }];
}

- (void)saveNow {
    NSMutableArray<HistoryEntry *> *list = [_entries.allValues mutableCopy];
    if ((NSInteger)list.count > _limit) {
        [list sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(HistoryEntry *a, HistoryEntry *b) {
            return [b.last compare:a.last];
        }];
        [list removeObjectsInRange:NSMakeRange((NSUInteger)_limit, list.count - (NSUInteger)_limit)];
        [_entries removeAllObjects];
        for (HistoryEntry *e in list) _entries[e.url] = e;
    }
    NSMutableArray *json = [NSMutableArray arrayWithCapacity:list.count];
    for (HistoryEntry *e in list) [json addObject:e.toJSON];
    BrookWriteJSONInBackground(json, NSJSONWritingWithoutEscapingSlashes, _fileURL);
}

@end

// MARK: - Favicons

NSNotificationName const FaviconStoreDidLoadIconNotification = @"BrookFaviconStoreDidLoadIcon";

@implementation FaviconStore {
    NSCache<NSString *, NSImage *> *_memory;
    NSMutableDictionary<NSString *, NSMutableArray<void (^)(NSImage *)> *> *_inflight;
    /// Disk reads under way, with whoever is waiting on each (nil blocks: just fill the cache).
    NSMutableDictionary<NSString *, NSMutableArray<void (^)(NSImage *)> *> *_reading;
    NSMutableSet<NSString *> *_misses;
    NSURL *_dir;
    dispatch_queue_t _io;
}

+ (FaviconStore *)shared {
    static FaviconStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FaviconStore new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _memory = [NSCache new];
        _inflight = [NSMutableDictionary dictionary];
        _reading = [NSMutableDictionary dictionary];
        _misses = [NSMutableSet set];
        _dir = [AppPaths sub:@"Favicons" in:AppPaths.caches];
        _io = dispatch_queue_create("app.brook.favicons",
                                    dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0));
    }
    return self;
}

- (NSURL *)fileForHost:(NSString *)host {
    return [_dir URLByAppendingPathComponent:
        [[host stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByAppendingString:@".img"]];
}

static NSImage *ReadIcon(NSURL *file) {
    NSData *data = [NSData dataWithContentsOfURL:file];
    return data ? [[NSImage alloc] initWithData:data] : nil;
}

- (void)warmHosts:(NSSet<NSString *> *)hosts {
    NSMutableArray<NSString *> *wanted = [NSMutableArray array];
    for (NSString *h in hosts) if (h.length && ![_memory objectForKey:h]) [wanted addObject:h];
    if (wanted.count == 0) return;
    std::vector<NSImage *> found(wanted.count);
    NSImage * __strong *slots = found.data();
    NSArray<NSString *> *list = wanted;
    // A few small files read side by side: a couple of milliseconds, before the first frame.
    dispatch_apply(list.count, _io, ^(size_t i) { slots[i] = ReadIcon([self fileForHost:list[i]]); });
    for (NSUInteger i = 0; i < list.count; i++) if (found[i]) [_memory setObject:found[i] forKey:list[i]];
}

- (NSImage *)cachedIconForHost:(NSString *)host {
    if (!host.length) return nil;
    if (NSImage *img = [_memory objectForKey:host]) return img;
    [self readHost:host then:nil];
    return nil;
}

- (void)cachedIconForHost:(NSString *)host completion:(void (^)(NSImage *icon))completion {
    if (!host.length) { completion(nil); return; }
    if (NSImage *img = [_memory objectForKey:host]) { completion(img); return; }
    [self readHost:host then:completion];
}

/// Reads the host's icon file off the main thread, into memory. `then` runs on the main queue.
- (void)readHost:(NSString *)host then:(void (^)(NSImage *))then {
    if (NSMutableArray *waiters = _reading[host]) {
        if (then) [waiters addObject:[then copy]];
        return;
    }
    _reading[host] = then ? [NSMutableArray arrayWithObject:[then copy]] : [NSMutableArray array];
    NSURL *file = [self fileForHost:host];
    dispatch_async(_io, ^{
        NSImage *img = ReadIcon(file);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<void (^)(NSImage *)> *waiters = self->_reading[host];
            [self->_reading removeObjectForKey:host];
            if (img) {
                [self->_memory setObject:img forKey:host];
                [NSNotificationCenter.defaultCenter postNotificationName:FaviconStoreDidLoadIconNotification object:host];
            }
            for (void (^w)(NSImage *) in waiters) w(img);
        });
    });
}

- (void)iconForHost:(NSString *)host completion:(void (^)(NSImage *icon))completion {
    if (!host.length) { completion(nil); return; }
    if (NSImage *img = [_memory objectForKey:host]) { completion(img); return; }
    if ([_misses containsObject:host]) { completion(nil); return; }
    if (NSMutableArray *waiters = _inflight[host]) { [waiters addObject:[completion copy]]; return; }
    _inflight[host] = [NSMutableArray arrayWithObject:[completion copy]];

    void (^finish)(NSImage *) = ^(NSImage *img) {
        NSArray<void (^)(NSImage *)> *waiters = self->_inflight[host];
        [self->_inflight removeObjectForKey:host];
        if (img) [self->_memory setObject:img forKey:host]; else [self->_misses addObject:host];
        for (void (^w)(NSImage *) in waiters) w(img);
    };

    // Disk first, then DuckDuckGo's icon service.
    NSURL *dest = [self fileForHost:host];
    [self readHost:host then:^(NSImage *cached) {
        if (cached) { finish(cached); return; }
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://icons.duckduckgo.com/ip3/%@.ico", host]];
        if (!url) { finish(nil); return; }
        [[NSURLSession.sharedSession dataTaskWithURL:url
                                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            BOOL ok = data && [response isKindOfClass:NSHTTPURLResponse.class] &&
                      ((NSHTTPURLResponse *)response).statusCode == 200;
            // Still on the session's queue: decode and save here, hand the image to the main queue.
            NSImage *img = ok ? [[NSImage alloc] initWithData:data] : nil;
            if (img) [data writeToURL:dest options:NSDataWritingAtomic error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                finish(img);
                if (img) [NSNotificationCenter.defaultCenter postNotificationName:FaviconStoreDidLoadIconNotification object:host];
            });
        }] resume];
    }];
}

- (void)clearKeepingHosts:(NSSet<NSString *> *)keep {
    NSMutableDictionary<NSString *, NSImage *> *kept = [NSMutableDictionary dictionary];
    for (NSString *h in keep) if (NSImage *img = [_memory objectForKey:h]) kept[h] = img;
    [_memory removeAllObjects];
    [kept enumerateKeysAndObjectsUsingBlock:^(NSString *h, NSImage *img, BOOL *) { [self->_memory setObject:img forKey:h]; }];
    [_misses removeAllObjects];
    NSMutableSet<NSString *> *keepNames = [NSMutableSet set];
    for (NSString *h in keep) [keepNames addObject:[self fileForHost:h].lastPathComponent];
    NSURL *dir = _dir;
    dispatch_barrier_async(_io, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *error = nil;
        NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:&error];
        if (!files) { NSLog(@"Brook: could not list the favicon cache: %@", error); return; }
        for (NSURL *f in files) {
            if ([keepNames containsObject:f.lastPathComponent]) continue;
            NSError *removeError = nil;
            if (![fm removeItemAtURL:f error:&removeError]) NSLog(@"Brook: could not remove %@: %@", f.path, removeError);
        }
    });
}

@end

// MARK: - Downloads

NSNotificationName const DownloadManagerDidChangeNotification = @"BrookDownloadsDidChange";

@implementation DownloadItem {
    @public
    WKDownload *_download;
    NSData *_resumeData;
    NSURLRequest *_request;       // for Retry when there's nothing to resume from
    __weak WKWebView *_webView;   // started from; WebKit resumes a download through a web view
}

- (instancetype)initWithDownload:(WKDownload *)download {
    if ((self = [super init])) {
        _download = download;
        _request = download.originalRequest;
        _webView = download.webView;
        _filename = @"Download";
        _status = DownloadStatusActive;
    }
    return self;
}

- (WKDownload *)download { return _download; }
- (NSData *)resumeData { return _resumeData; }
- (double)fraction { return _download.progress.fractionCompleted; }

@end

@implementation DownloadManager {
    NSMutableArray<DownloadItem *> *_items;
}

+ (DownloadManager *)shared {
    static DownloadManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [DownloadManager new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) _items = [NSMutableArray array];
    return self;
}

- (NSArray<DownloadItem *> *)items { return [_items copy]; }

- (BOOL)hasActive {
    for (DownloadItem *i in _items) if (i.status == DownloadStatusActive) return YES;
    return NO;
}

- (void)track:(WKDownload *)download {
    download.delegate = self;
    [_items insertObject:[[DownloadItem alloc] initWithDownload:download] atIndex:0];
    [self notify];
}

- (void)clearFinished {
    NSMutableArray *gone = [NSMutableArray array];
    [_items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DownloadItem *i, NSDictionary *b) {
        if (i.status != DownloadStatusActive) [gone addObject:i];
        return i.status == DownloadStatusActive;
    }]];
    // A paused or failed download cleared from the list can't be resumed any more: its part goes too.
    for (DownloadItem *i in gone) if (i.status != DownloadStatusFinished) [self removePartial:i];
    [self notify];
}

- (DownloadItem *)itemFor:(WKDownload *)d {
    for (DownloadItem *i in _items) if (i->_download == d) return i;
    return nil;
}

- (void)removePartial:(DownloadItem *)item {
    NSURL *partial = item.destination;
    if (!partial || ![partial checkResourceIsReachableAndReturnError:nil]) return;
    NSError *error = nil;
    if (![NSFileManager.defaultManager removeItemAtURL:partial error:&error])
        NSLog(@"Brook: couldn't remove unfinished download %@: %@", partial.path, error);
}

- (void)pause:(DownloadItem *)item {
    if (item.status != DownloadStatusActive) return;
    WKDownload *download = item->_download;
    // Paused before the cancel: WebKit reports the cancel as a failure too, and that path would
    // otherwise delete the part this pause keeps.
    item.status = DownloadStatusPaused;
    [self notify];
    [download cancel:^(NSData *resumeData) {
        if (item->_download != download) return;
        item->_resumeData = resumeData;
        [self notify];
    }];
}

- (void)resume:(DownloadItem *)item {
    if (item.status != DownloadStatusPaused && item.status != DownloadStatusFailed) return;
    WKWebView *wv = item->_webView ?: BrowserState.shared.selectedTab.webView;
    if (!wv) return;
    NSData *data = item->_resumeData;
    item->_resumeData = nil;
    item.status = DownloadStatusActive;
    [self notify];
    void (^adopt)(WKDownload *) = ^(WKDownload *download) {
        if (!download) { item.status = DownloadStatusFailed; [self notify]; return; }
        download.delegate = self;
        item->_download = download;
        item->_webView = download.webView ?: wv;
        [self notify];
    };
    if (data) {
        // Carries on into the file it was writing: WebKit doesn't ask for a destination again.
        [wv resumeDownloadFromResumeData:data completionHandler:adopt];
    } else if (item->_request) {
        [self removePartial:item];
        [wv startDownloadUsingRequest:item->_request completionHandler:adopt];
    } else {
        item.status = DownloadStatusFailed;
        [self notify];
    }
}

- (void)discardUnfinished {
    for (DownloadItem *i in _items) {
        if (i.status == DownloadStatusPaused || i.status == DownloadStatusFailed) [self removePartial:i];
    }
}

- (void)notify {
    [NSNotificationCenter.defaultCenter postNotificationName:DownloadManagerDidChangeNotification object:self];
}

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response
        suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL *))completionHandler {
    NSString *name = suggestedFilename.length == 0 ? @"Download" : suggestedFilename;
    if (Settings.askDownloadLocation) {
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.nameFieldStringValue = name;
        panel.directoryURL = Settings.downloadFolder;
        panel.canCreateDirectories = YES;
        void (^handle)(NSModalResponse) = ^(NSModalResponse result) {
            NSURL *chosen = panel.URL;
            if (result != NSModalResponseOK || !chosen) {
                [self->_items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DownloadItem *i, NSDictionary *b) {
                    return i.download != download;
                }]];
                [self notify];
                completionHandler(nil);
                return;
            }
            // The save panel already asked about replacing an existing file.
            [NSFileManager.defaultManager removeItemAtURL:chosen error:nil];
            if (DownloadItem *item = [self itemFor:download]) {
                item.filename = chosen.lastPathComponent;
                item.destination = chosen;
            }
            [self notify];
            completionHandler(chosen);
        };
        if (NSWindow *window = NSApp.mainWindow) [panel beginSheetModalForWindow:window completionHandler:handle];
        else handle([panel runModal]);
        return;
    }
    NSURL *folder = Settings.downloadFolder;
    if (![folder checkResourceIsReachableAndReturnError:nil]) {
        folder = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask][0];
    }
    // WebKit fails the download outright if the folder is missing.
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *base = name.stringByDeletingPathExtension;
    NSString *ext = name.pathExtension;
    NSURL *candidate = [folder URLByAppendingPathComponent:name];
    NSInteger n = 1;
    while ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
        NSString *file = ext.length == 0 ? [NSString stringWithFormat:@"%@ (%ld)", base, (long)n]
                                         : [NSString stringWithFormat:@"%@ (%ld).%@", base, (long)n, ext];
        candidate = [folder URLByAppendingPathComponent:file];
        n += 1;
    }
    if (DownloadItem *item = [self itemFor:download]) {
        item.filename = candidate.lastPathComponent;
        item.destination = candidate;
    }
    [self notify];
    completionHandler(candidate);
}

- (void)downloadDidFinish:(WKDownload *)download {
    DownloadItem *item = [self itemFor:download];
    if (!item) return;
    item.status = DownloadStatusFinished;
    if (NSString *path = item.destination.path) {
        // Makes the Downloads stack in the Dock bounce, like Safari.
        [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"com.apple.DownloadFileFinished" object:path];
    }
    [self notify];
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    DownloadItem *item = [self itemFor:download];
    if (!item || item.status == DownloadStatusPaused) return;   // paused: the cancel answer handles it
    item.status = DownloadStatusFailed;
    item->_resumeData = resumeData;
    // Without resume data, WebKit's part under the final name is only a broken copy that looks complete
    // and takes the name from the next try. With it, the part is what Resume carries on from.
    if (!resumeData) [self removePartial:item];
    [self notify];
}

@end
