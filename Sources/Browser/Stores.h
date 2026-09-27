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
- (void)saveNow;
@end

// MARK: - Favicons

@interface FaviconStore : NSObject
@property (class, readonly) FaviconStore *shared;
/// Memory or disk cache only; nil if we don't have it yet.
- (NSImage *)cachedIconForHost:(NSString *)host;
/// Cached icon, or fetches it (DuckDuckGo's icon service). Completion runs on the main queue,
/// with nil on failure. Concurrent requests for one host share a fetch; misses are remembered.
- (void)iconForHost:(NSString *)host completion:(void (^)(NSImage *icon))completion;
@end

// MARK: - Downloads

typedef NS_ENUM(NSInteger, DownloadStatus) { DownloadStatusActive, DownloadStatusFinished, DownloadStatusFailed };

@interface DownloadItem : NSObject
- (instancetype)initWithDownload:(WKDownload *)download;
@property (readonly) WKDownload *download;
@property (copy) NSString *filename;     // default "Download"
@property (copy) NSURL *destination;
@property DownloadStatus status;
@property (readonly) double fraction;
@end

/// Posted when downloads change ("BrookDownloadsDidChange"), object = the manager.
FOUNDATION_EXPORT NSNotificationName const DownloadManagerDidChangeNotification;

@interface DownloadManager : NSObject <WKDownloadDelegate>
@property (class, readonly) DownloadManager *shared;
/// Newest first.
@property (readonly) NSArray<DownloadItem *> *items;
@property (readonly) BOOL hasActive;
- (void)track:(WKDownload *)download;
- (void)clearFinished;
@end
