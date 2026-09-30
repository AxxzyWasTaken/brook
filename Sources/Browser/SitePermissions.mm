#import "Brook.h"

// Location and notifications, asked site by site and remembered per origin, as Safari does. Before this,
// nobody answered WebKit's questions, and it refuses a page whose question goes unanswered.

@implementation SitePermissions

static BOOL sAsking = NO;

+ (NSString *)keyFor:(SitePermission)permission {
    switch (permission) {
        case SitePermissionLocation: return @"location";
        case SitePermissionNotifications: return @"notifications";
    }
    return @"";
}

static NSString *What(SitePermission permission) {
    switch (permission) {
        case SitePermissionLocation: return @"know your location";
        case SitePermissionNotifications: return @"send you notifications";
    }
    return @"";
}

+ (NSString *)originForScheme:(NSString *)scheme host:(NSString *)host port:(NSInteger)port {
    NSString *s = scheme.lowercaseString ?: @"", *h = host.lowercaseString ?: @"";
    BOOL standard = port == 0 || ([s isEqualToString:@"https"] && port == 443) || ([s isEqualToString:@"http"] && port == 80);
    return standard ? [NSString stringWithFormat:@"%@://%@", s, h] : [NSString stringWithFormat:@"%@://%@:%ld", s, h, (long)port];
}

+ (NSString *)originOf:(WKSecurityOrigin *)origin {
    return [self originForScheme:origin.protocol host:origin.host port:origin.port];
}

+ (NSDictionary *)all {
    NSDictionary *json = [Settings jsonForKey:@"sitePermissions"];
    return [json isKindOfClass:NSDictionary.class] ? json : @{};
}

+ (NSNumber *)decisionFor:(SitePermission)permission origin:(NSString *)origin {
    NSDictionary *site = self.all[origin];
    id v = [site isKindOfClass:NSDictionary.class] ? site[[self keyFor:permission]] : nil;
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

+ (void)setDecision:(NSNumber *)allowed for:(SitePermission)permission origin:(NSString *)origin {
    NSMutableDictionary *all = [self.all mutableCopy];
    NSMutableDictionary *site = [all[origin] isKindOfClass:NSDictionary.class] ? [all[origin] mutableCopy] : [NSMutableDictionary dictionary];
    site[[self keyFor:permission]] = allowed ? @(allowed.boolValue) : nil;
    all[origin] = site.count ? site : nil;
    [Settings setJSON:all forKey:@"sitePermissions"];
    if (permission == SitePermissionNotifications) [SiteNotifications.shared policyChangedFor:origin];
}

+ (NSDictionary<NSString *, NSNumber *> *)decisionsFor:(SitePermission)permission {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSString *key = [self keyFor:permission];
    [self.all enumerateKeysAndObjectsUsingBlock:^(NSString *origin, NSDictionary *site, BOOL *stop) {
        id v = [site isKindOfClass:NSDictionary.class] ? site[key] : nil;
        if ([v isKindOfClass:NSNumber.class]) out[origin] = v;
    }];
    return out;
}

+ (void)forgetAll {
    NSArray *origins = self.all.allKeys;
    [Settings setJSON:@{} forKey:@"sitePermissions"];
    for (NSString *origin in origins) [SiteNotifications.shared policyChangedFor:origin];
}

+ (void)ask:(SitePermission)permission origin:(NSString *)origin host:(NSString *)host
     webView:(WKWebView *)webView completion:(void (^)(BOOL))completion {
    if (NSNumber *kept = [self decisionFor:permission origin:origin]) { completion(kept.boolValue); return; }
    NSWindow *window = webView.window;
    if (!window || sAsking || window.attachedSheet) { completion(NO); return; }
    sAsking = YES;
    BOOL once = permission == SitePermissionLocation;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Allow %@ to %@?", host.length ? host : origin, What(permission)];
    if (once) {
        alert.informativeText = @"Allow Once lets it ask again next time.";
        [alert addButtonWithTitle:@"Allow Once"];
        [alert addButtonWithTitle:@"Always Allow"];
    } else {
        [alert addButtonWithTitle:@"Allow"];
    }
    [alert addButtonWithTitle:@"Don’t Allow"];
    // A page can time a click to land where Allow is about to appear: take no answer for half a second.
    NSArray<NSButton *> *buttons = alert.buttons;
    for (NSButton *b in buttons) b.enabled = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (NSButton *b in buttons) b.enabled = YES;
    });
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        sAsking = NO;
        NSInteger index = r - NSAlertFirstButtonReturn;
        BOOL deny = index == (NSInteger)buttons.count - 1;
        BOOL keep = !(once && index == 0);   // Allow Once isn't kept
        if (keep) [self setDecision:@(!deny) for:permission origin:origin];
        completion(!deny);
    }];
}

@end
