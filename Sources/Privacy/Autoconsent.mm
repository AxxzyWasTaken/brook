#import "Brook.h"

/// Where each kind of rule sits in a compact rule list ("index" in the list; [start, end) ranges).
struct CompactRuleIndex {
    NSUInteger genericStart, genericEnd, frameStart, frameEnd, specificStart, specificEnd;
    NSUInteger genericStringEnd, frameStringEnd;
};

/// The rule-step keys whose values are indexes into the list's strings (autoconsent's compactedRuleSteps).
static NSArray<NSString *> *StepStringKeys(void) {
    static NSArray<NSString *> *keys = @[@"e", @"v", @"c", @"k", @"w", @"wv", @"h", @"cc"];
    return keys;
}

static void CollectStringIDs(id steps, NSMutableIndexSet *used) {
    if (![steps isKindOfClass:NSArray.class]) return;
    for (NSDictionary *step in steps) {
        if (![step isKindOfClass:NSDictionary.class]) continue;
        for (NSString *key in StepStringKeys()) {
            if (NSNumber *n = [step[key] isKindOfClass:NSNumber.class] ? step[key] : nil) [used addIndex:n.unsignedIntegerValue];
        }
        if (id cond = step[@"if"]) CollectStringIDs(@[cond], used);
        CollectStringIDs(step[@"then"], used);
        CollectStringIDs(step[@"else"], used);
        CollectStringIDs(step[@"any"], used);
    }
}

/// autoconsent's clearUnusedStrings: blanks the strings no rule uses and drops the tail past the last one used.
static NSDictionary *ClearUnusedStrings(id version, NSArray *strings, NSArray *rules) {
    NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
    for (NSArray *rule in rules) {
        for (NSUInteger i = 6; i <= 9; i++) CollectStringIDs(rule[i], used);
        for (id n in [rule[5] isKindOfClass:NSArray.class] ? rule[5] : @[])
            if ([n isKindOfClass:NSNumber.class]) [used addIndex:[n unsignedIntegerValue]];
    }
    NSUInteger count = used.count ? std::min(strings.count, used.lastIndex + 1) : 0;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [kept addObject:[used containsIndex:i] ? strings[i] : @""];
    return @{@"v": version, @"s": kept, @"r": rules};
}

/// Downloads DuckDuckGo's public privacy configuration, which carries the
/// cookie-popup rule list, and keeps a cached copy on disk.
@implementation PrivacyConfigStore {
    NSURL *_fileURL;
    NSTimeInterval _refreshInterval;
    NSSet<NSString *> *_exceptions;
    std::optional<CompactRuleIndex> _ruleIndex;   // nil: the list can't be filtered, so it's sent whole
    NSDictionary *_genericRules;                  // the main-frame list for a site with no rules of its own
    NSMutableDictionary<NSString *, id> *_patterns;   // url pattern -> NSRegularExpression, or NSNull if it won't compile
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
    [self indexRules];
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

// MARK: Filtering the rules per frame

/// Checks the list's shape once, so filtering never has to. Anything unexpected leaves the list unfiltered.
- (void)indexRules {
    _ruleIndex.reset();
    _genericRules = nil;
    _patterns = [NSMutableDictionary dictionary];
    NSDictionary *list = [_compactRules isKindOfClass:NSDictionary.class] ? _compactRules : nil;
    NSArray *strings = list[@"s"], *rules = list[@"r"];
    NSDictionary *index = list[@"index"];
    if (![strings isKindOfClass:NSArray.class] || ![rules isKindOfClass:NSArray.class] ||
        ![index isKindOfClass:NSDictionary.class] || !list[@"v"]) return;
    for (NSArray *rule in rules) {
        if (![rule isKindOfClass:NSArray.class] || rule.count < 10 || ![rule[3] isKindOfClass:NSString.class] ||
            ![rule[4] isKindOfClass:NSNumber.class]) return;
    }
    auto range = [&](NSString *key, NSUInteger &start, NSUInteger &end) {
        NSArray *r = index[key];
        if (![r isKindOfClass:NSArray.class] || r.count != 2 || ![r[0] isKindOfClass:NSNumber.class] ||
            ![r[1] isKindOfClass:NSNumber.class]) return false;
        start = [r[0] unsignedIntegerValue];
        end = [r[1] unsignedIntegerValue];
        return start <= end && end <= rules.count;
    };
    auto bound = [&](NSString *key, NSUInteger &value) {
        NSNumber *n = index[key];
        if (![n isKindOfClass:NSNumber.class]) return false;
        value = n.unsignedIntegerValue;
        return value <= strings.count;
    };
    CompactRuleIndex i{};
    if (!range(@"genericRuleRange", i.genericStart, i.genericEnd) || !range(@"frameRuleRange", i.frameStart, i.frameEnd) ||
        !range(@"specificRuleRange", i.specificStart, i.specificEnd) || !bound(@"genericStringEnd", i.genericStringEnd) ||
        !bound(@"frameStringEnd", i.frameStringEnd)) return;
    _ruleIndex = i;
    NSArray *generic = [rules subarrayWithRange:NSMakeRange(i.genericStart, i.genericEnd - i.genericStart)];
    _genericRules = @{@"v": list[@"v"], @"s": [strings subarrayWithRange:NSMakeRange(0, i.genericStringEnd)], @"r": generic};
}

/// autoconsent's shouldRunRuleInContext. The script checks every rule it gets the same way, so leaving one
/// out here changes nothing on the page; a pattern that won't compile is kept, to let the script decide.
- (BOOL)rule:(NSArray *)rule runsAt:(NSString *)url mainFrame:(BOOL)mainFrame {
    NSInteger context = [rule[4] integerValue];   // tens digit: main frame, units: sub-frames (1 yes, 0 no, 2 default)
    if (mainFrame && context == 1) return NO;
    if (!mainFrame && (context == 20 || context == 22 || context == 10 || context == 12)) return NO;
    NSString *pattern = rule[3];
    if (!pattern.length) return YES;
    id regex = _patterns[pattern];
    if (!regex) {
        regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil] ?: (id)NSNull.null;
        _patterns[pattern] = regex;
    }
    if (regex == NSNull.null) return YES;
    return [regex firstMatchInString:url options:0 range:NSMakeRange(0, url.length)] != nil;
}

/// Sub-frames get only the few frame rules; a main frame gets the generic rules plus its site's own. This is
/// what DuckDuckGo's extension sends: the whole ~290 KB list, parsed again in every ad and embed, went to 3 KB.
- (id)compactRulesForURL:(NSString *)url mainFrame:(BOOL)mainFrame {
    if (!_ruleIndex) return _compactRules;
    const CompactRuleIndex &i = *_ruleIndex;
    NSDictionary *list = _compactRules;
    NSArray *strings = list[@"s"], *rules = list[@"r"];
    auto matching = [&](NSUInteger start, NSUInteger end, BOOL main) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSUInteger k = start; k < end; k++) if ([self rule:rules[k] runsAt:url mainFrame:main]) [out addObject:rules[k]];
        return out;
    };
    if (!mainFrame) {
        NSArray *frameStrings = [strings subarrayWithRange:NSMakeRange(0, i.frameStringEnd)];
        return ClearUnusedStrings(list[@"v"], frameStrings, matching(i.frameStart, i.frameEnd, NO));
    }
    NSArray *specific = matching(i.specificStart, i.specificEnd, YES);
    if (!specific.count) return _genericRules;
    return ClearUnusedStrings(list[@"v"], strings, [_genericRules[@"r"] arrayByAddingObjectsFromArray:specific]);
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
    if (id compact = [config compactRulesForURL:urlString mainFrame:message.frameInfo.isMainFrame]) rules[@"compact"] = compact;

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
