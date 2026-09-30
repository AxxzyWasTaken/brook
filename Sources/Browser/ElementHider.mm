#import "Brook.h"

// See ElementHider.h.
// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), Curtain.swift.

NSNotificationName const ElementHiderDidChangeNotification = @"BrookElementHiderDidChange";

@implementation HiddenElement
@end

/// JSON for a value, used as a JavaScript literal (JSON is valid JavaScript).
static NSString *JSLiteral(id value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value ?: @""] options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    return json.length >= 2 ? [json substringWithRange:NSMakeRange(1, json.length - 2)] : @"\"\"";
}

@interface ElementHider () <WKScriptMessageHandler>
@end

@implementation ElementHider {
    WKUserScript *_picker;
}

+ (ElementHider *)shared {
    static ElementHider *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ElementHider new]; });
    return s;
}

+ (WKContentWorld *)world {
    static WKContentWorld *world = [WKContentWorld worldWithName:@"BrookHide"];
    return world;
}

- (WKUserScript *)pickerScript {
    if (_picker) return _picker;
    NSURL *file = [NSBundle.mainBundle URLForResource:@"hide-elements" withExtension:@"js"];
    NSString *source = file ? [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!source) return nil;
    _picker = [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                  forMainFrameOnly:YES inContentWorld:ElementHider.world];
    return _picker;
}

// MARK: - The list

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)all {
    NSDictionary *json = [Settings jsonForKey:@"hiddenElements"];
    return [json isKindOfClass:NSDictionary.class] ? json : @{};
}

- (void)setList:(NSArray<NSDictionary *> *)list forSite:(NSString *)site {
    NSMutableDictionary *all = [self.all mutableCopy];
    all[site] = list.count ? list : nil;
    [Settings setJSON:all forKey:@"hiddenElements"];
    [WebViewFactory reloadSiteScripts];
    [NSNotificationCenter.defaultCenter postNotificationName:ElementHiderDidChangeNotification object:self
                                                    userInfo:@{@"site": site}];
}

- (NSArray<NSDictionary *> *)rawForSite:(NSString *)site {
    id list = self.all[site];
    if (![list isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id e in list) if ([e isKindOfClass:NSDictionary.class] && [e[@"selector"] isKindOfClass:NSString.class]) [out addObject:e];
    return out;
}

- (NSArray<HiddenElement *> *)elementsForHost:(NSString *)host {
    if (!host.length) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *e in [self rawForSite:[SiteSettings keyForHost:host]]) {
        HiddenElement *h = [HiddenElement new];
        h.selector = e[@"selector"];
        h.label = [e[@"label"] isKindOfClass:NSString.class] ? e[@"label"] : h.selector;
        h.note = [e[@"note"] isKindOfClass:NSString.class] ? e[@"note"] : @"";
        [out addObject:h];
    }
    return out;
}

static NSString *RulesFor(NSArray<NSDictionary *> *list, NSString *spared) {
    NSMutableArray *rules = [NSMutableArray array];
    for (NSDictionary *e in list) {
        NSString *sel = e[@"selector"];
        // A selector can't close the rule and start another: the braces would let one hide more than itself.
        if ([sel isEqualToString:spared] || [sel rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"{}"]].location != NSNotFound) continue;
        [rules addObject:[sel stringByAppendingString:@" { display: none !important; }"]];
    }
    return [rules componentsJoinedByString:@"\n"];
}

- (NSString *)cssForHost:(NSString *)host without:(NSString *)spared {
    return host.length ? RulesFor([self rawForSite:[SiteSettings keyForHost:host]], spared) : @"";
}

- (void)hide:(NSString *)selector label:(NSString *)label note:(NSString *)note onHost:(NSString *)host {
    if (!selector.length || !host.length) return;
    NSString *site = [SiteSettings keyForHost:host];
    NSMutableArray *list = [[self rawForSite:site] mutableCopy];
    for (NSDictionary *e in list) if ([e[@"selector"] isEqualToString:selector]) return;
    [list addObject:@{@"selector": selector, @"label": label.length ? label : selector, @"note": note ?: @""}];
    [self setList:list forSite:site];
}

- (void)restore:(NSString *)selector onHost:(NSString *)host {
    NSString *site = [SiteSettings keyForHost:host];
    NSMutableArray *list = [[self rawForSite:site] mutableCopy];
    [list filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, NSDictionary *b) {
        return ![e[@"selector"] isEqualToString:selector];
    }]];
    [self setList:list forSite:site];
}

- (HiddenElement *)undoOnHost:(NSString *)host {
    NSArray<HiddenElement *> *elements = [self elementsForHost:host];
    HiddenElement *last = elements.lastObject;
    if (last) [self restore:last.selector onHost:host];
    return last;
}

- (void)restoreAllOnHost:(NSString *)host {
    [self setList:@[] forSite:[SiteSettings keyForHost:host]];
}

- (WKUserScript *)styleScript {
    NSMutableDictionary<NSString *, NSString *> *bySite = [NSMutableDictionary dictionary];
    [self.all enumerateKeysAndObjectsUsingBlock:^(NSString *site, id list, BOOL *stop) {
        NSString *css = RulesFor([self rawForSite:site], nil);
        if (css.length) bySite[site] = css;
    }];
    if (!bySite.count) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:bySite options:0 error:nil];
    NSString *map = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
    // Only this site's rules reach the page: the map itself stays in Brook's own world.
    NSString *source = [NSString stringWithFormat:
        @"(function () {\n"
         "  if (window.top !== window) return;\n"
         "  var h = location.hostname.toLowerCase();\n"
         "  if (h.indexOf('www.') === 0) h = h.slice(4);\n"
         "  var css = (%@)[h];\n"
         "  if (!css) return;\n"
         "  var s = document.createElement('style');\n"
         "  s.id = 'brook-hide';\n"
         "  s.textContent = css;\n"
         "  (document.head || document.documentElement).appendChild(s);\n"
         "})();", map];
    return [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                               forMainFrameOnly:YES inContentWorld:ElementHider.world];
}

// MARK: - The page

- (void)run:(NSString *)js in:(WKWebView *)webView {
    [webView evaluateJavaScript:js inFrame:nil inContentWorld:ElementHider.world completionHandler:nil];
}

- (void)startPickingIn:(WKWebView *)webView { [self run:@"window.__brookHide && window.__brookHide.on()" in:webView]; }
- (void)stopPickingIn:(WKWebView *)webView { [self run:@"window.__brookHide && window.__brookHide.off()" in:webView]; }

- (void)applyIn:(WKWebView *)webView host:(NSString *)host {
    [self run:[NSString stringWithFormat:@"window.__brookHide && window.__brookHide.apply(%@)",
               JSLiteral([self cssForHost:host without:nil])] in:webView];
}

- (void)peek:(NSString *)selector in:(WKWebView *)webView host:(NSString *)host {
    [self run:[NSString stringWithFormat:@"window.__brookHide && window.__brookHide.peek(%@, %@)",
               JSLiteral([self cssForHost:host without:selector]), JSLiteral(selector)] in:webView];
}

- (void)unpeekIn:(WKWebView *)webView host:(NSString *)host {
    [self run:[NSString stringWithFormat:@"window.__brookHide && window.__brookHide.unpeek(%@)",
               JSLiteral([self cssForHost:host without:nil])] in:webView];
}

- (void)pickAtPoint:(CGPoint)point in:(WKWebView *)webView {
    [self run:[NSString stringWithFormat:@"window.__brookHide && window.__brookHide.pickAt(%f, %f)", point.x, point.y] in:webView];
}

- (void)installHandlersInto:(WKUserContentController *)ucc {
    [ucc addScriptMessageHandler:self contentWorld:ElementHider.world name:@"brookHide"];
}

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *body = [message.body isKindOfClass:NSDictionary.class] ? message.body : nil;
    if (!body || !message.frameInfo.isMainFrame) return;
    WKWebView *webView = message.webView;
    if ([body[@"undo"] isEqual:@YES]) {
        if (_onUndo) _onUndo(webView);
        return;
    }
    if ([body[@"off"] isEqual:@YES]) {
        if (_onPickingEnded) _onPickingEnded(webView);
        return;
    }
    NSString *selector = [body[@"selector"] isKindOfClass:NSString.class] ? body[@"selector"] : nil;
    if (!selector.length || selector.length > 1000) {
        if (body[@"trouble"]) NSLog(@"Brook: couldn't pick that element: %@", body[@"trouble"]);
        return;
    }
    NSString *label = [body[@"label"] isKindOfClass:NSString.class] ? body[@"label"] : selector;
    NSString *note = [body[@"note"] isKindOfClass:NSString.class] ? body[@"note"] : @"";
    if (_onPick) _onPick(webView, selector, label, note);
}

@end
