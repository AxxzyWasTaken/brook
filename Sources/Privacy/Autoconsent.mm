#import "Brook.h"

/// Downloads DuckDuckGo's public privacy configuration, which carries the
/// cookie-popup rule list, and keeps a cached copy on disk.
@implementation PrivacyConfigStore {
    NSURL *_fileURL;
    NSTimeInterval _refreshInterval;
    NSSet<NSString *> *_exceptions;
}

static NSString *const kPrivacyConfigRemote = @"https://staticcdn.duckduckgo.com/trackerblocking/config/v4/macos-config.json";

+ (PrivacyConfigStore *)shared {
    static PrivacyConfigStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [PrivacyConfigStore new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _fileURL = [AppPaths.support URLByAppendingPathComponent:@"privacy-config.json"];
        _refreshInterval = 24 * 3600;
        _disabledCMPs = @[];
        _enabled = YES;
        _exceptions = [NSSet set];
    }
    return self;
}

- (void)load {
    NSData *data = [NSData dataWithContentsOfURL:_fileURL];
    if (data) [self apply:data];
    [self refreshIfNeeded];
}

- (void)refreshIfNeeded {
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:_fileURL.path error:nil];
    NSDate *modified = attrs[NSFileModificationDate];
    if ([modified isKindOfClass:NSDate.class] &&
        [NSDate.date timeIntervalSinceDate:modified] < _refreshInterval && _compactRules != nil) return;
    __weak PrivacyConfigStore *weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession
        dataTaskWithURL:[NSURL URLWithString:kPrivacyConfigRemote]
      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
          dispatch_async(dispatch_get_main_queue(), ^{
              PrivacyConfigStore *self_ = weakSelf;
              if (!self_ || !data || error) return;
              if (![response isKindOfClass:NSHTTPURLResponse.class] ||
                  ((NSHTTPURLResponse *)response).statusCode != 200) return;
              if ([self_ apply:data]) {
                  [data writeToURL:self_->_fileURL options:NSDataWritingAtomic error:nil];
              }
          });
      }];
    [task resume];
}

- (BOOL)apply:(NSData *)data {
    id rootObj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![rootObj isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *root = rootObj;
    NSDictionary *features = root[@"features"];
    if (![features isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *ac = features[@"autoconsent"];
    if (![ac isKindOfClass:NSDictionary.class]) return NO;

    NSString *state = [ac[@"state"] isKindOfClass:NSString.class] ? ac[@"state"] : @"enabled";
    _enabled = [state isEqualToString:@"enabled"];
    NSDictionary *settings = [ac[@"settings"] isKindOfClass:NSDictionary.class] ? ac[@"settings"] : @{};
    _compactRules = settings[@"compactRuleList"];
    NSArray *cmps = settings[@"disabledCMPs"];
    BOOL allStrings = [cmps isKindOfClass:NSArray.class];
    if (allStrings) {
        for (id c in cmps) if (![c isKindOfClass:NSString.class]) { allStrings = NO; break; }
    }
    _disabledCMPs = allStrings ? cmps : @[];

    NSMutableSet<NSString *> *ex = [NSMutableSet set];
    for (id list in @[ac[@"exceptions"] ?: NSNull.null, root[@"unprotectedTemporary"] ?: NSNull.null]) {
        if (![list isKindOfClass:NSArray.class]) continue;
        // All-or-nothing: one bad element rejects the whole list.
        BOOL allDicts = YES;
        for (id item in list) if (![item isKindOfClass:NSDictionary.class]) { allDicts = NO; break; }
        if (!allDicts) continue;
        for (NSDictionary *item in list) {
            NSString *d = item[@"domain"];
            if ([d isKindOfClass:NSString.class]) [ex addObject:d.lowercaseString];
        }
    }
    _exceptions = ex;
    return YES;
}

- (BOOL)isExceptedHost:(NSString *)host {
    NSString *h = host.lowercaseString;
    while (true) {
        if ([_exceptions containsObject:h]) return YES;
        NSRange dot = [h rangeOfString:@"."];
        if (dot.location == NSNotFound) return NO;
        h = [h substringFromIndex:NSMaxRange(dot)];
        if (![h containsString:@"."]) return NO;
    }
}

@end

/// Native side of DuckDuckGo's autoconsent script, which finds cookie consent
/// popups and clicks "reject" for you. Mirrors DuckDuckGo's AutoconsentUserScript.
@implementation AutoconsentHandler {
    NSMutableDictionary<NSString *, NSDate *> *_recentlyHandled;
    WKUserScript *_userScript;
    BOOL _userScriptLoaded;
}

+ (AutoconsentHandler *)shared {
    static AutoconsentHandler *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AutoconsentHandler new]; });
    return shared;
}

+ (NSArray<NSString *> *)messageNames {
    return @[@"init", @"eval", @"popupFound", @"optOutResult", @"optInResult",
             @"selfTestResult", @"autoconsentDone", @"autoconsentError", @"report", @"cmpDetected"];
}

+ (NSDictionary *)ok {
    return @{@"type": @"ok"};
}

- (instancetype)init {
    if ((self = [super init])) {
        _recentlyHandled = [NSMutableDictionary dictionary];
    }
    return self;
}

- (WKUserScript *)userScript {
    if (!_userScriptLoaded) {
        _userScriptLoaded = YES;
        NSURL *url = [NSBundle.mainBundle URLForResource:@"autoconsent-bundle" withExtension:@"js"];
        NSString *source = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
        if (source) {
            _userScript = [[WKUserScript alloc] initWithSource:source
                                                 injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                              forMainFrameOnly:NO
                                                inContentWorld:WKContentWorld.defaultClientWorld];
        }
    }
    return _userScript;
}

- (void)installHandlersInto:(WKUserContentController *)ucc {
    for (NSString *name in AutoconsentHandler.messageNames) {
        [ucc addScriptMessageHandlerWithReply:self contentWorld:WKContentWorld.defaultClientWorld name:name];
    }
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
                 replyHandler:(void (^)(id reply, NSString *errorMessage))replyHandler {
    NSDictionary *body = [message.body isKindOfClass:NSDictionary.class] ? message.body : @{};
    NSString *name = message.name;
    if ([name isEqualToString:@"init"]) {
        replyHandler([self responseForInit:message body:body], nil);
    } else if ([name isEqualToString:@"eval"]) {
        [self evaluate:message body:body reply:replyHandler];
    } else if ([name isEqualToString:@"autoconsentDone"]) {
        BrowserTab *tab = [message.webView isKindOfClass:BrookWebView.class] ? ((BrookWebView *)message.webView).tab : nil;
        if (message.frameInfo.isMainFrame && tab) {
            BOOL cosmetic = [body[@"isCosmetic"] isKindOfClass:NSNumber.class] ? [body[@"isCosmetic"] boolValue] : NO;
            NSString *host = BrookHost(message.frameInfo.request.URL);
            if (!cosmetic && host) {
                _recentlyHandled[host] = [NSDate date];
            }
        }
        replyHandler(AutoconsentHandler.ok, nil);
    } else {
        replyHandler(AutoconsentHandler.ok, nil);
    }
}

- (NSDictionary *)responseForInit:(WKScriptMessage *)message body:(NSDictionary *)body {
    PrivacyConfigStore *config = PrivacyConfigStore.shared;
    if (!config.enabled) return AutoconsentHandler.ok;
    NSString *urlString = [body[@"url"] isKindOfClass:NSString.class] ? body[@"url"] : @"";
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *scheme = url.scheme;
    if (!url || !scheme || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        return AutoconsentHandler.ok;
    }
    NSString *host = BrookHost(url);
    if (!host) return AutoconsentHandler.ok;

    NSString *topHost = BrookHost(message.webView.URL) ?: host;
    if (![SiteSettings cookiePopupsForHost:topHost]) return AutoconsentHandler.ok;
    if ([config isExceptedHost:topHost]) return AutoconsentHandler.ok;

    // If we just handled a popup on this site and the page reloaded, don't loop.
    id autoAction = @"optOut";
    NSDate *last = _recentlyHandled[host];
    if (last && [NSDate.date timeIntervalSinceDate:last] < 10) {
        autoAction = NSNull.null;
    }

    NSMutableDictionary *rules = [NSMutableDictionary dictionary];
    if (config.compactRules) rules[@"compact"] = config.compactRules;

    return @{
        @"type": @"initResp",
        @"rules": rules,
        @"config": @{
            @"enabled": @YES,
            @"autoAction": autoAction,
            @"disabledCmps": config.disabledCMPs,
            @"enablePrehide": @YES,
            @"enableCosmeticRules": @YES,
            @"detectRetries": @20,
            @"isMainWorld": @NO,
            @"enableHeuristicDetection": @YES,
            @"heuristicMode": @"off"
        }
    };
}

- (void)evaluate:(WKScriptMessage *)message body:(NSDictionary *)body
           reply:(void (^)(id reply, NSString *errorMessage))reply {
    WKWebView *webView = message.webView;
    NSString *code = [body[@"code"] isKindOfClass:NSString.class] ? body[@"code"] : nil;
    if (!webView || !code) {
        reply(nil, @"missing frame target");
        return;
    }
    id identifier = body[@"id"] ?: @"";
    NSString *script = [NSString stringWithFormat:@"(() => { try { return !!(%@); } catch (e) { return false; } })();", code];
    WKFrameInfo *frame = message.frameInfo;
    [webView evaluateJavaScript:script inFrame:frame inContentWorld:WKContentWorld.pageWorld
              completionHandler:^(id value, NSError *error) {
        if (error) {
            reply(@{@"type": @"evalResp", @"id": identifier, @"result": @NO}, nil);
        } else {
            reply(@{@"type": @"evalResp", @"id": identifier, @"result": value ?: NSNull.null}, nil);
        }
    }];
}

@end
