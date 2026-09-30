#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

// MARK: - History

/// One history.json record. JSON keys: "url", "title", "visits", "last".
/// `last` is seconds since 2001-01-01 (timeIntervalSinceReferenceDate).
@interface HistoryEntry : NSObject
@property (copy) NSString *url;      // absolute string
@property (copy) NSString *title;
@property NSInteger visits;
@property (strong) NSDate *last;
@end

@interface HistoryStore : NSObject
@property (class, readonly) HistoryStore *shared;
/// Records a visit (http/https only).
- (void)recordURL:(NSURL *)url title:(NSString *)title;
- (void)updateTitle:(NSString *)title forURL:(NSURL *)url;
/// Simple frecency ranking: matches in the host or title, weighted by visits and recency.
- (NSArray<HistoryEntry *> *)search:(NSString *)query limit:(NSInteger)limit;
/// limit 6.
- (NSArray<HistoryEntry *> *)search:(NSString *)query;
- (void)clear;
/// Snapshots history now; the file is written on a background queue.
- (void)saveNow;
@end

// MARK: - Favicons

/// Posted on the main queue when an icon arrives in memory (read from disk or fetched); the
/// object is its host. Lists that showed a placeholder from -cachedIconForHost: reload on it.
FOUNDATION_EXPORT NSNotificationName const FaviconStoreDidLoadIconNotification;

@interface FaviconStore : NSObject
@property (class, readonly) FaviconStore *shared;
/// Memory cache only, so it's cheap enough for table cells. On a miss it returns nil and reads
/// the disk cache in the background, posting FaviconStoreDidLoadIconNotification if it finds one.
- (NSImage *)cachedIconForHost:(NSString *)host;
/// Memory, else the disk cache read in the background; never the network. Completion runs on
/// the main queue (at once on a memory hit), with nil if it isn't cached.
- (void)cachedIconForHost:(NSString *)host completion:(void (^)(NSImage *icon))completion;
/// Reads these hosts' icons from disk into memory, in parallel, before returning. For restoring
/// a session before the window first draws, so its tabs don't flash a placeholder.
- (void)warmHosts:(NSSet<NSString *> *)hosts;
/// Cached icon (memory, then disk), or fetches it (DuckDuckGo's icon service). Completion runs on
/// the main queue, with nil on failure. Concurrent requests for one host share a fetch; misses
/// are remembered.
- (void)iconForHost:(NSString *)host completion:(void (^)(NSImage *icon))completion;
/// Forgets every icon, in memory and on disk, except those of the given hosts.
- (void)clearKeepingHosts:(NSSet<NSString *> *)keep;
@end

// MARK: - Downloads

typedef NS_ENUM(NSInteger, DownloadStatus) {
    DownloadStatusActive, DownloadStatusFinished, DownloadStatusFailed, DownloadStatusPaused
};

@interface DownloadItem : NSObject
- (instancetype)initWithDownload:(WKDownload *)download;
/// The download running now: a resumed or retried download is a new WKDownload under the same item.
@property (readonly) WKDownload *download;
@property (copy) NSString *filename;     // default "Download"
@property (copy) NSURL *destination;
@property DownloadStatus status;
@property (readonly) double fraction;
/// Paused, or failed partway: where WebKit can carry on from. nil when it has to start again.
@property (readonly) NSData *resumeData;
@end

/// Posted when downloads change ("BrookDownloadsDidChange"), object = the manager.
FOUNDATION_EXPORT NSNotificationName const DownloadManagerDidChangeNotification;

@interface DownloadManager : NSObject <WKDownloadDelegate>
@property (class, readonly) DownloadManager *shared;
/// Newest first.
@property (readonly) NSArray<DownloadItem *> *items;
@property (readonly) BOOL hasActive;
- (void)track:(WKDownload *)download;
/// Saves bytes Brook already has (an image read from inside its page) as a finished download, under the same
/// folder and naming as any other. Completion gets the file, or nil if it couldn't be written.
- (void)saveData:(NSData *)data suggestedFilename:(NSString *)name completion:(void (^)(NSURL *file))completion;
- (void)clearFinished;
/// Stops a running download, keeping what it has so far to resume from.
- (void)pause:(DownloadItem *)item;
/// Carries on a paused or failed download from where it stopped, or starts it again if it can't.
- (void)resume:(DownloadItem *)item;
/// Deletes the partial files of downloads that never finished (at quit: resume data doesn't outlive the app).
- (void)discardUnfinished;
@end
