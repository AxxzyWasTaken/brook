#import "Brook.h"
#import <UserNotifications/UserNotifications.h>
#import <dlfcn.h>

// See SiteNotifications.h.
// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), Notifications.swift.

typedef const void *WKRef;

/// WebKit's C API, each function looked up by name (none is in a public header).
struct WebKitC {
    WKRef (*pageContext)(WKRef page);
    WKRef (*manager)(WKRef context);
    void (*setProvider)(WKRef manager, const void *provider);
    WKRef (*title)(WKRef note);
    WKRef (*body)(WKRef note);
    WKRef (*tag)(WKRef note);
    uint64_t (*noteID)(WKRef note);
    WKRef (*origin)(WKRef note);
    WKRef (*originString)(WKRef origin);
    CFStringRef (*cfString)(CFAllocatorRef, WKRef string);
    void (*didShow)(WKRef manager, uint64_t noteID);
    void (*didClick)(WKRef manager, uint64_t noteID);
    void (*didClose)(WKRef manager, WKRef ids);
    WKRef (*uint64)(uint64_t);
    uint64_t (*uint64Value)(WKRef);
    WKRef (*array)(WKRef *items, size_t count);
    size_t (*arraySize)(WKRef);
    WKRef (*arrayItem)(WKRef, size_t);
    WKRef (*dictionary)(void);
    bool (*setItem)(WKRef dictionary, WKRef key, WKRef value);
    WKRef (*boolean)(bool);
    WKRef (*string)(CFStringRef);
    void (*release)(WKRef);
    bool (*persistent)(WKRef note);   // optional
    WKRef (*originFromString)(WKRef string);                              // optional, with the two below
    void (*didUpdatePolicy)(WKRef manager, WKRef origin, bool allowed);
    void (*didRemovePolicies)(WKRef manager, WKRef origins);

    NSString *text(WKRef copied) const {
        if (!copied) return @"";
        CFStringRef s = cfString(NULL, copied);
        release(copied);
        return s ? (__bridge_transfer NSString *)s : @"";
    }
};

static const WebKitC *LoadedWebKitC(void) {
    static WebKitC c;
    static BOOL ok = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *wk = dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_NOW);
        if (!wk) return;
        BOOL all = YES;
        auto f = [&](const char *name) -> void * { void *p = dlsym(wk, name); if (!p) all = NO; return p; };
        c.pageContext = (WKRef (*)(WKRef))f("WKPageGetContext");
        c.manager = (WKRef (*)(WKRef))f("WKContextGetNotificationManager");
        c.setProvider = (void (*)(WKRef, const void *))f("WKNotificationManagerSetProvider");
        c.title = (WKRef (*)(WKRef))f("WKNotificationCopyTitle");
        c.body = (WKRef (*)(WKRef))f("WKNotificationCopyBody");
        c.tag = (WKRef (*)(WKRef))f("WKNotificationCopyTag");
        c.noteID = (uint64_t (*)(WKRef))f("WKNotificationGetID");
        c.origin = (WKRef (*)(WKRef))f("WKNotificationGetSecurityOrigin");
        c.originString = (WKRef (*)(WKRef))f("WKSecurityOriginCopyToString");
        c.cfString = (CFStringRef (*)(CFAllocatorRef, WKRef))f("WKStringCopyCFString");
        c.didShow = (void (*)(WKRef, uint64_t))f("WKNotificationManagerProviderDidShowNotification");
        c.didClick = (void (*)(WKRef, uint64_t))f("WKNotificationManagerProviderDidClickNotification");
        c.didClose = (void (*)(WKRef, WKRef))f("WKNotificationManagerProviderDidCloseNotifications");
        c.uint64 = (WKRef (*)(uint64_t))f("WKUInt64Create");
        c.uint64Value = (uint64_t (*)(WKRef))f("WKUInt64GetValue");
        c.array = (WKRef (*)(WKRef *, size_t))f("WKArrayCreate");
        c.arraySize = (size_t (*)(WKRef))f("WKArrayGetSize");
        c.arrayItem = (WKRef (*)(WKRef, size_t))f("WKArrayGetItemAtIndex");
        c.dictionary = (WKRef (*)(void))f("WKMutableDictionaryCreate");
        c.setItem = (bool (*)(WKRef, WKRef, WKRef))f("WKDictionarySetItem");
        c.boolean = (WKRef (*)(bool))f("WKBooleanCreate");
        c.string = (WKRef (*)(CFStringRef))f("WKStringCreateWithCFString");
        c.release = (void (*)(WKRef))f("WKRelease");
        c.persistent = (bool (*)(WKRef))dlsym(wk, "WKNotificationGetIsPersistent");
        c.originFromString = (WKRef (*)(WKRef))dlsym(wk, "WKSecurityOriginCreateFromString");
        c.didUpdatePolicy = (void (*)(WKRef, WKRef, bool))dlsym(wk, "WKNotificationManagerProviderDidUpdateNotificationPolicy");
        c.didRemovePolicies = (void (*)(WKRef, WKRef))dlsym(wk, "WKNotificationManagerProviderDidRemoveNotificationPolicies");
        ok = all;
    });
    return ok ? &c : nullptr;
}

/// WKNotificationProviderV0, laid out as WebKit reads it: a version, the client's pointer, then seven callbacks.
struct NotificationProviderV0 {
    int version;
    const void *clientInfo;
    void (*show)(WKRef page, WKRef note, const void *clientInfo);
    void (*cancel)(WKRef note, const void *clientInfo);
    void (*didDestroy)(WKRef note, const void *clientInfo);
    void (*addManager)(WKRef manager, const void *clientInfo);
    void (*removeManager)(WKRef manager, const void *clientInfo);
    WKRef (*permissions)(const void *clientInfo);
    void (*clear)(WKRef ids, const void *clientInfo);
};

@interface SiteNotifications () <UNUserNotificationCenterDelegate>
- (void)showPageNotification:(WKRef)note page:(WKRef)page;
- (void)cancelPageNotification:(WKRef)note;
- (void)clearPageNotifications:(WKRef)ids;
- (WKRef)pagePermissions;
@end

static void ProviderShow(WKRef page, WKRef note, const void *) {
    if (page && note) [SiteNotifications.shared showPageNotification:note page:page];
}
static void ProviderCancel(WKRef note, const void *) { if (note) [SiteNotifications.shared cancelPageNotification:note]; }
static void ProviderIgnore(WKRef, const void *) {}
static WKRef ProviderPermissions(const void *) { return [SiteNotifications.shared pagePermissions]; }
static void ProviderClear(WKRef ids, const void *) { if (ids) [SiteNotifications.shared clearPageNotifications:ids]; }

static NotificationProviderV0 sProvider = {
    0, nullptr, ProviderShow, ProviderCancel, ProviderIgnore, ProviderIgnore, ProviderIgnore, ProviderPermissions, ProviderClear,
};

@implementation SiteNotifications {
    NSMutableSet<NSValue *> *_managers;                       // notification managers given the provider
    NSMutableDictionary<NSNumber *, NSValue *> *_shown;       // page notification id -> its manager
    NSMutableDictionary<NSString *, WKWebsiteDataStore *> *_stores;   // posted id -> store it came from
    NSMapTable<NSString *, WKWebView *> *_pages;                      // posted id -> the page that posted it
    BOOL _authorized;
}

+ (SiteNotifications *)shared {
    static SiteNotifications *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SiteNotifications new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _managers = [NSMutableSet set];
        _shown = [NSMutableDictionary dictionary];
        _stores = [NSMutableDictionary dictionary];
        _pages = [NSMapTable strongToWeakObjectsMapTable];
    }
    return self;
}

static BOOL AllowedOrigin(NSString *origin) {
    return Settings.siteNotifications && [SitePermissions decisionFor:SitePermissionNotifications origin:origin].boolValue;
}

// MARK: - WebKit

- (void)attachStore:(WKWebsiteDataStore *)store {
    static SEL setter = NSSelectorFromString(@"set_delegate:");
    if (!store.isPersistent || ![store respondsToSelector:setter]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(store, setter, self);
    if (!UNUserNotificationCenter.currentNotificationCenter.delegate)
        UNUserNotificationCenter.currentNotificationCenter.delegate = self;
}

- (void)authorize {
    if (_authorized) return;
    _authorized = YES;
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    center.delegate = self;
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge
                          completionHandler:^(BOOL granted, NSError *error) {}];
    UNNotificationCategory *site = [UNNotificationCategory categoryWithIdentifier:@"site" actions:@[] intentIdentifiers:@[]
                                                                          options:UNNotificationCategoryOptionCustomDismissAction];
    [center setNotificationCategories:[NSSet setWithObject:site]];
}

/// _WKWebsiteDataStoreDelegate: what each site was told, asked as a store opens.
- (NSDictionary<NSString *, NSNumber *> *)notificationPermissionsForWebsiteDataStore:(WKWebsiteDataStore *)store {
    return Settings.siteNotifications ? [SitePermissions decisionsFor:SitePermissionNotifications] : @{};
}

/// _WKWebsiteDataStoreDelegate: a service worker's notification (a _WKNotificationData).
- (void)websiteDataStore:(WKWebsiteDataStore *)store showNotification:(id)data {
    NSString *(^text)(NSString *) = ^NSString *(NSString *key) {
        if (![data respondsToSelector:NSSelectorFromString(key)]) return @"";
        id v = [data valueForKey:key];
        return [v isKindOfClass:NSString.class] ? v : @"";
    };
    NSString *origin = text(@"origin");
    if (!AllowedOrigin(origin)) return;
    id identifier = [data respondsToSelector:NSSelectorFromString(@"identifier")] ? [data valueForKey:@"identifier"] : nil;
    NSString *key = identifier ? [identifier description] : NSUUID.UUID.UUIDString;
    SEL dictSel = NSSelectorFromString(@"dictionaryRepresentation");
    NSDictionary *dictionary = [data respondsToSelector:dictSel] ? ((id (*)(id, SEL))objc_msgSend)(data, dictSel) : nil;
    _stores[key] = store;
    [self postID:key title:text(@"title") body:text(@"body") origin:origin tag:text(@"tag")
            info:@{@"brook.kind": @"worker", @"brook.origin": origin,
                   @"brook.data": [dictionary isKindOfClass:NSDictionary.class] ? dictionary : @{}}];
}

/// _WKWebsiteDataStoreDelegate: what a service worker's getNotifications() finds.
- (void)websiteDataStore:(WKWebsiteDataStore *)store getDisplayedNotificationsForWorkerOrigin:(WKSecurityOrigin *)origin
       completionHandler:(void (^)(NSArray<NSDictionary *> *))completionHandler {
    NSString *site = [SitePermissions originOf:origin];
    [UNUserNotificationCenter.currentNotificationCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *delivered) {
        NSMutableArray *found = [NSMutableArray array];
        for (UNNotification *n in delivered) {
            NSDictionary *info = n.request.content.userInfo;
            if ([info[@"brook.kind"] isEqual:@"worker"] && [info[@"brook.origin"] isEqual:site] && info[@"brook.data"])
                [found addObject:info[@"brook.data"]];
        }
        completionHandler(found);
    }];
}

/// _WKWebsiteDataStoreDelegate: clients.openWindow() from a notification's click, as a tab.
- (void)websiteDataStore:(WKWebsiteDataStore *)store openWindow:(NSURL *)url fromServiceWorkerOrigin:(WKSecurityOrigin *)origin
       completionHandler:(void (^)(WKWebView *))completionHandler {
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) { completionHandler(nil); return; }
    BrowserTab *tab = [BrowserState.shared openTabWithURL:url inSpace:nil select:YES];
    [NSApp activate];
    completionHandler(tab.webView);
}

// MARK: - A page's own notifications

- (WKRef)pageRefOf:(WKWebView *)webView {
    static SEL sel = NSSelectorFromString(@"_pageRefForTransitionToWKWebView");
    return [webView respondsToSelector:sel] ? ((WKRef (*)(id, SEL))objc_msgSend)(webView, sel) : nullptr;
}

- (void)providePageNotificationsFor:(WKWebView *)webView {
    const WebKitC *c = LoadedWebKitC();
    if (!c || !webView.configuration.websiteDataStore.isPersistent) return;
    WKRef page = [self pageRefOf:webView];
    WKRef context = page ? c->pageContext(page) : nullptr;
    WKRef manager = context ? c->manager(context) : nullptr;
    if (!manager) return;
    NSValue *key = [NSValue valueWithPointer:manager];
    if ([_managers containsObject:key]) return;
    [_managers addObject:key];
    c->setProvider(manager, &sProvider);
}

- (void)policyChangedFor:(NSString *)origin {
    const WebKitC *c = LoadedWebKitC();
    if (!c || !c->originFromString || !c->didUpdatePolicy || !c->didRemovePolicies || !_managers.count) return;
    WKRef string = c->string((__bridge CFStringRef)origin);
    WKRef security = string ? c->originFromString(string) : nullptr;
    if (string) c->release(string);
    if (!security) return;
    NSNumber *allowed = Settings.siteNotifications ? [SitePermissions decisionFor:SitePermissionNotifications origin:origin] : nil;
    WKRef items[1] = {security};
    WKRef list = allowed ? nullptr : c->array(items, 1);
    for (NSValue *manager in _managers) {
        if (allowed) c->didUpdatePolicy(manager.pointerValue, security, allowed.boolValue);
        else if (list) c->didRemovePolicies(manager.pointerValue, list);
    }
    if (list) c->release(list);
    c->release(security);
}

- (NSString *)originOfNote:(WKRef)note c:(const WebKitC *)c {
    WKRef origin = c->origin(note);
    NSURL *url = origin ? [NSURL URLWithString:c->text(c->originString(origin))] : nil;
    return url.host ? [SitePermissions originForScheme:url.scheme host:url.host port:url.port.integerValue] : @"";
}

- (void)showPageNotification:(WKRef)note page:(WKRef)page {
    const WebKitC *c = LoadedWebKitC();
    if (!c || (c->persistent && c->persistent(note))) return;   // a worker's comes through the store's delegate
    WKRef context = c->pageContext(page);
    WKRef manager = context ? c->manager(context) : nullptr;
    if (!manager) return;
    NSString *origin = [self originOfNote:note c:c];
    WKWebView *webView = nil;
    for (BrowserTab *t in BrowserState.shared.allTabs) {
        if (t.webView && [self pageRefOf:t.webView] == page) { webView = t.webView; break; }
    }
    if (!AllowedOrigin(origin) || !webView.configuration.websiteDataStore.isPersistent) return;
    uint64_t noteID = c->noteID(note);
    NSString *key = [NSString stringWithFormat:@"page|%llu", noteID];
    _shown[@(noteID)] = [NSValue valueWithPointer:manager];
    _stores[key] = webView.configuration.websiteDataStore;
    [_pages setObject:webView forKey:key];
    [self postID:key title:c->text(c->title(note)) body:c->text(c->body(note)) origin:origin tag:c->text(c->tag(note))
            info:@{@"brook.kind": @"page", @"brook.id": @(noteID).stringValue, @"brook.origin": origin}];
    c->didShow(manager, noteID);
}

- (void)forgetPage:(uint64_t)noteID {
    NSString *wanted = @(noteID).stringValue;
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *delivered) {
        NSMutableArray *gone = [NSMutableArray array];
        for (UNNotification *n in delivered) {
            NSDictionary *info = n.request.content.userInfo;
            if ([info[@"brook.kind"] isEqual:@"page"] && [info[@"brook.id"] isEqual:wanted]) [gone addObject:n.request.identifier];
        }
        [center removeDeliveredNotificationsWithIdentifiers:gone];
    }];
}

/// notification.close() from the page.
- (void)cancelPageNotification:(WKRef)note {
    const WebKitC *c = LoadedWebKitC();
    if (!c) return;
    uint64_t noteID = c->noteID(note);
    [self forgetPage:noteID];
    NSString *key = [NSString stringWithFormat:@"page|%llu", noteID];
    [_stores removeObjectForKey:key];
    [_pages removeObjectForKey:key];
    [self pageClosed:noteID];
}

/// Notifications WebKit is done with (their page went away).
- (void)clearPageNotifications:(WKRef)ids {
    const WebKitC *c = LoadedWebKitC();
    if (!c) return;
    for (size_t i = 0; i < c->arraySize(ids); i++) {
        WKRef item = c->arrayItem(ids, i);
        if (!item) continue;
        uint64_t noteID = c->uint64Value(item);
        [self forgetPage:noteID];
        [_shown removeObjectForKey:@(noteID)];
        NSString *key = [NSString stringWithFormat:@"page|%llu", noteID];
        [_stores removeObjectForKey:key];
        [_pages removeObjectForKey:key];
    }
}

/// What each site was told, as WebKit asks for it (the dictionary is WebKit's from here).
- (WKRef)pagePermissions {
    const WebKitC *c = LoadedWebKitC();
    WKRef dictionary = c ? c->dictionary() : nullptr;
    if (!dictionary || !Settings.siteNotifications) return dictionary;
    [[SitePermissions decisionsFor:SitePermissionNotifications] enumerateKeysAndObjectsUsingBlock:^(NSString *origin, NSNumber *allowed, BOOL *stop) {
        WKRef key = c->string((__bridge CFStringRef)origin);
        WKRef value = c->boolean(allowed.boolValue);
        if (key && value) c->setItem(dictionary, key, value);
        if (key) c->release(key);
        if (value) c->release(value);
    }];
    return dictionary;
}

- (void)pageClicked:(uint64_t)noteID {
    const WebKitC *c = LoadedWebKitC();
    NSValue *manager = _shown[@(noteID)];
    if (c && manager) c->didClick(manager.pointerValue, noteID);
}

- (void)pageClosed:(uint64_t)noteID {
    const WebKitC *c = LoadedWebKitC();
    NSValue *manager = _shown[@(noteID)];
    if (!c || !manager) return;
    [_shown removeObjectForKey:@(noteID)];
    WKRef one = c->uint64(noteID);
    if (!one) return;
    WKRef items[1] = {one};
    WKRef ids = c->array(items, 1);
    c->release(one);
    if (!ids) return;
    c->didClose(manager.pointerValue, ids);
    c->release(ids);
}

// MARK: - Posting

/// Posts through the user notification center. Separate so a test build can see what would be posted.
- (void)deliver:(UNMutableNotificationContent *)content identifier:(NSString *)identifier {
    [UNUserNotificationCenter.currentNotificationCenter
        addNotificationRequest:[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil]
         withCompletionHandler:nil];
}

- (void)postID:(NSString *)postID title:(NSString *)title body:(NSString *)body origin:(NSString *)origin tag:(NSString *)tag
          info:(NSDictionary *)info {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    NSMutableDictionary *userInfo = [info mutableCopy];
    userInfo[@"brook.key"] = postID;
    content.title = title;
    content.body = body;
    NSString *host = [NSURL URLWithString:origin].host;
    content.subtitle = host ? [SiteSettings keyForHost:host] : origin;
    content.threadIdentifier = origin;
    content.categoryIdentifier = @"site";
    content.sound = UNNotificationSound.defaultSound;
    content.userInfo = userInfo;
    if (NSImage *icon = host ? [FaviconStore.shared cachedIconForHost:host] : nil) {
        // Its own file each time: macOS moves an attachment's file into its own keeping.
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:icon.TIFFRepresentation];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSURL *folder = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:@"Brook notifications"];
        [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *file = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", host, NSUUID.UUID.UUIDString]];
        if ([png writeToURL:file atomically:YES]) {
            UNNotificationAttachment *a = [UNNotificationAttachment attachmentWithIdentifier:@"icon" URL:file options:nil error:nil];
            if (a) content.attachments = @[a];
        }
    }
    // A tag names a notification its site means to replace.
    NSString *identifier = tag.length ? [NSString stringWithFormat:@"tag|%@|%@", origin, tag] : postID;
    [self deliver:content identifier:identifier];
}

// MARK: - Answered

typedef void (*DeliverToWorker)(id, SEL, NSDictionary *, void (^)(BOOL));

static void TellWorker(WKWebsiteDataStore *store, NSString *name, NSDictionary *data) {
    SEL sel = NSSelectorFromString(name);
    if (![store respondsToSelector:sel]) return;
    ((DeliverToWorker)objc_msgSend)(store, sel, data, ^(BOOL done) {});
}

/// The tab that posted it in front, else one showing the site (using the store it came from if there is one).
- (void)bringForward:(NSString *)origin store:(WKWebsiteDataStore *)store page:(WKWebView *)page {
    BrowserTab *found = nil;
    for (BrowserTab *t in BrowserState.shared.allTabs) {
        if (page && t.webView == page) { found = t; break; }
    }
    for (BrowserTab *t in found ? @[] : BrowserState.shared.allTabs) {
        NSURL *u = t.url;
        if (!u.host || ![[SitePermissions originForScheme:u.scheme host:u.host port:u.port.integerValue] isEqualToString:origin]) continue;
        if (!found || (store && t.webView.configuration.websiteDataStore == store)) found = t;
    }
    if (found) [BrowserState.shared selectTab:found];
    [NSApp activate];
    [(id)NSApp.delegate performSelector:@selector(showMainWindow:) withObject:nil];
}

- (void)clicked:(NSDictionary *)info {
    NSString *key = info[@"brook.key"];
    WKWebsiteDataStore *from = key ? _stores[key] : nil;
    WKWebView *page = key ? [_pages objectForKey:key] : nil;
    if (key) { [_stores removeObjectForKey:key]; [_pages removeObjectForKey:key]; }
    [self bringForward:info[@"brook.origin"] ?: @"" store:from page:page];
    if ([info[@"brook.kind"] isEqual:@"page"]) { [self pageClicked:[info[@"brook.id"] longLongValue]]; return; }
    if ([info[@"brook.kind"] isEqual:@"worker"] && info[@"brook.data"])
        TellWorker(from ?: WKWebsiteDataStore.defaultDataStore, @"_processPersistentNotificationClick:completionHandler:", info[@"brook.data"]);
}

- (void)closed:(NSDictionary *)info {
    NSString *key = info[@"brook.key"];
    WKWebsiteDataStore *from = key ? _stores[key] : nil;
    if (key) { [_stores removeObjectForKey:key]; [_pages removeObjectForKey:key]; }
    if ([info[@"brook.kind"] isEqual:@"page"]) { [self pageClosed:[info[@"brook.id"] longLongValue]]; return; }
    if ([info[@"brook.kind"] isEqual:@"worker"] && info[@"brook.data"])
        TellWorker(from ?: WKWebsiteDataStore.defaultDataStore, @"_processPersistentNotificationClose:completionHandler:", info[@"brook.data"]);
}

/// Shown even with Brook in front, as a browser's are.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    NSDictionary *info = response.notification.request.content.userInfo;
    BOOL dismissed = [response.actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (dismissed) [self closed:info]; else [self clicked:info];
        completionHandler();
    });
}

@end
