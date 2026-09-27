#import "Brook.h"

/// The bundled lists (Resources/blocklist-<name>.json), one WebKit rule list each.
static NSArray<NSString *> *const kLists = @[@"ads", @"trackers"];

@implementation ContentBlocker {
    NSMutableArray<WKContentRuleList *> *_ruleLists;
    NSInteger _pending;
    NSMutableArray<dispatch_block_t> *_waiting;
    BOOL _attached;
}

+ (ContentBlocker *)shared {
    static ContentBlocker *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ContentBlocker new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _ruleLists = [NSMutableArray array];
        _waiting = [NSMutableArray array];
    }
    return self;
}

- (void)load {
    WKContentRuleListStore *store = WKContentRuleListStore.defaultStore;
    NSMutableSet<NSString *> *current = [NSMutableSet set];
    for (NSString *name in kLists) {
        NSURL *file = [NSBundle.mainBundle URLForResource:[@"blocklist-" stringByAppendingString:name] withExtension:@"json"];
        if (!file) continue;
        // A new build ships a new file, so the identifier changes and the old compiled copy is dropped.
        NSDictionary *attrs = [file resourceValuesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey] error:nil];
        NSString *identifier = [NSString stringWithFormat:@"%@-%@-%.0f", name, attrs[NSURLFileSizeKey],
                                [attrs[NSURLContentModificationDateKey] timeIntervalSince1970]];
        [current addObject:identifier];
        _pending++;
        [store lookUpContentRuleListForIdentifier:identifier completionHandler:^(WKContentRuleList *list, NSError *error) {
            if (list) return [self finished:list];
            NSString *json = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil];
            [store compileContentRuleListForIdentifier:identifier encodedContentRuleList:json
                                     completionHandler:^(WKContentRuleList *compiled, NSError *compileError) {
                if (compileError) NSLog(@"Brook: couldn't compile %@ blocklist: %@", name, compileError);
                [self finished:compiled];
            }];
        }];
    }
    [store getAvailableContentRuleListIdentifiers:^(NSArray<NSString *> *identifiers) {
        for (NSString *identifier in identifiers) {
            if (![current containsObject:identifier]) [store removeContentRuleListForIdentifier:identifier completionHandler:^(NSError *) {}];
        }
    }];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged:)
                                               name:BrookSettingsDidChangeNotification object:nil];
    if (_pending == 0) [self finished:nil];
}

- (void)finished:(WKContentRuleList *)list {
    if (list) [_ruleLists addObject:list];
    if (--_pending > 0) return;
    [self apply];
    NSArray<dispatch_block_t> *waiting = _waiting;
    _waiting = nil;
    for (dispatch_block_t block in waiting) block();
}

/// Adds or removes the rule lists to match the setting. Open pages change on their next load.
- (void)apply {
    BOOL on = Settings.blockAds;
    if (on == _attached) return;
    _attached = on;
    WKUserContentController *ucc = WebViewFactory.userContentController;
    for (WKContentRuleList *list in _ruleLists) {
        if (on) [ucc addContentRuleList:list]; else [ucc removeContentRuleList:list];
    }
}

- (void)settingsChanged:(NSNotification *)note {
    NSString *key = note.userInfo[@"key"];
    if (!_waiting && ([key isEqual:@"blockAds"] || [key isEqual:@"*"])) [self apply];
}

- (void)whenReady:(dispatch_block_t)block {
    if (_waiting) [_waiting addObject:[block copy]]; else block();
}

@end
