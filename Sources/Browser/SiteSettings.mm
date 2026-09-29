#import "Brook.h"

// MARK: - JSON helpers (strict typing)

/// A JSON boolean (plain numbers are rejected).
static BOOL IsJSONBool(id v) {
    return [v isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID();
}

/// A JSON number that isn't a boolean.
static BOOL IsJSONNumber(id v) {
    return [v isKindOfClass:NSNumber.class] && !IsJSONBool(v);
}

/// Missing or null (treated as nil).
static BOOL IsAbsent(id v) { return v == nil || v == NSNull.null; }

// MARK: - Per-site settings

/// Overrides for one site. `nil` means "use the global setting".
@implementation SiteOverride

- (BOOL)isEmpty {
    return _zoom == nil && _javascript == nil && _autoplay == nil && _cookiePopups == nil && _forceDark == nil &&
           _userAgent == nil && _blockAds == nil;
}

- (id)copyWithZone:(NSZone *)zone {
    SiteOverride *o = [SiteOverride new];
    o.zoom = _zoom;
    o.javascript = _javascript;
    o.autoplay = _autoplay;
    o.cookiePopups = _cookiePopups;
    o.forceDark = _forceDark;
    o.userAgent = _userAgent;
    o.blockAds = _blockAds;
    return o;
}

static BOOL Same(id a, id b) { return a == b || [a isEqual:b]; }

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:SiteOverride.class]) return NO;
    SiteOverride *o = other;
    return Same(_zoom, o.zoom) && Same(_javascript, o.javascript) && Same(_autoplay, o.autoplay) &&
           Same(_cookiePopups, o.cookiePopups) && Same(_forceDark, o.forceDark) && Same(_userAgent, o.userAgent) &&
           Same(_blockAds, o.blockAds);
}

- (NSUInteger)hash { return _zoom.hash ^ _javascript.hash ^ _autoplay.hash ^ _cookiePopups.hash ^ _userAgent.hash; }

/// nil when a present field has the wrong type.
+ (instancetype)fromJSON:(NSDictionary *)json {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    id zoom = json[@"zoom"], js = json[@"javascript"], autoplay = json[@"autoplay"], cookies = json[@"cookiePopups"];
    id dark = json[@"forceDark"], ua = json[@"userAgent"], ads = json[@"blockAds"];
    if (!IsAbsent(zoom) && !IsJSONNumber(zoom)) return nil;
    if (!IsAbsent(js) && !IsJSONBool(js)) return nil;
    if (!IsAbsent(autoplay) && ![autoplay isKindOfClass:NSString.class]) return nil;
    if (!IsAbsent(cookies) && !IsJSONBool(cookies)) return nil;
    if (!IsAbsent(dark) && !IsJSONBool(dark)) return nil;
    if (!IsAbsent(ua) && ![ua isKindOfClass:NSString.class]) return nil;
    if (!IsAbsent(ads) && !IsJSONBool(ads)) return nil;
    SiteOverride *o = [SiteOverride new];
    o.zoom = IsAbsent(zoom) ? nil : @([zoom doubleValue]);
    o.javascript = IsAbsent(js) ? nil : @([js boolValue]);
    o.autoplay = IsAbsent(autoplay) ? nil : autoplay;
    o.cookiePopups = IsAbsent(cookies) ? nil : @([cookies boolValue]);
    o.forceDark = IsAbsent(dark) ? nil : @([dark boolValue]);
    o.userAgent = IsAbsent(ua) ? nil : ua;
    o.blockAds = IsAbsent(ads) ? nil : @([ads boolValue]);
    return o;
}

- (NSDictionary *)toJSON {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (_zoom) d[@"zoom"] = @(_zoom.doubleValue);
    if (_javascript) d[@"javascript"] = @(_javascript.boolValue);
    if (_autoplay) d[@"autoplay"] = _autoplay;
    if (_cookiePopups) d[@"cookiePopups"] = @(_cookiePopups.boolValue);
    if (_forceDark) d[@"forceDark"] = @(_forceDark.boolValue);
    if (_userAgent) d[@"userAgent"] = _userAgent;
    if (_blockAds) d[@"blockAds"] = @(_blockAds.boolValue);
    return d;
}

@end

@implementation SiteSettings

static NSDictionary<NSString *, SiteOverride *> *sSiteCache;

/// Sites are keyed by host without a leading "www.".
+ (NSString *)keyForHost:(NSString *)host {
    NSString *h = host.lowercaseString ?: @"";
    return [h hasPrefix:@"www."] ? [h substringFromIndex:4] : h;
}

+ (NSDictionary<NSString *, SiteOverride *> *)all {
    if (sSiteCache) return sSiteCache;
    NSDictionary *json = [Settings jsonForKey:@"siteSettings"];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    BOOL ok = [json isKindOfClass:NSDictionary.class];
    if (ok) {
        for (id key in json) {
            SiteOverride *o = [key isKindOfClass:NSString.class] ? [SiteOverride fromJSON:json[key]] : nil;
            if (!o) { ok = NO; break; }   // one bad element rejects the whole list
            map[key] = o;
        }
    }
    sSiteCache = ok ? [map copy] : @{};
    return sSiteCache;
}

+ (void)setAll:(NSDictionary<NSString *, SiteOverride *> *)all {
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    [all enumerateKeysAndObjectsUsingBlock:^(NSString *key, SiteOverride *o, BOOL *stop) {
        if (o.isEmpty) return;
        kept[key] = o;
        json[key] = o.toJSON;
    }];
    sSiteCache = [kept copy];
    [Settings setJSON:json forKey:@"siteSettings"];
}

+ (void)invalidate { sSiteCache = nil; }

/// The override for a host. Each unset field comes from the nearest parent domain that sets it
/// ("m.example.com" → "example.com").
+ (SiteOverride *)overrideForHost:(NSString *)host {
    SiteOverride *r = [SiteOverride new];
    if (!host) return r;
    NSString *h = [self keyForHost:host];
    NSDictionary<NSString *, SiteOverride *> *map = self.all;
    while (true) {
        SiteOverride *o = map[h];
        if (o) {
            if (!r.zoom) r.zoom = o.zoom;
            if (!r.javascript) r.javascript = o.javascript;
            if (!r.autoplay) r.autoplay = o.autoplay;
            if (!r.cookiePopups) r.cookiePopups = o.cookiePopups;
            if (!r.forceDark) r.forceDark = o.forceDark;
            if (!r.userAgent) r.userAgent = o.userAgent;
            if (!r.blockAds) r.blockAds = o.blockAds;
        }
        NSRange dot = [h rangeOfString:@"."];
        if (dot.location == NSNotFound) return r;
        NSString *rest = [h substringFromIndex:dot.location + 1];
        if (![rest containsString:@"."]) return r;
        h = rest;
    }
}

+ (void)updateHost:(NSString *)host change:(void (^)(SiteOverride *o))change {
    NSString *k = [self keyForHost:host];
    NSMutableDictionary *map = [self.all mutableCopy];
    SiteOverride *o = [map[k] copy] ?: [SiteOverride new];
    change(o);
    map[k] = o;
    self.all = map;
}

+ (void)removeHost:(NSString *)host {
    NSMutableDictionary *map = [self.all mutableCopy];
    [map removeObjectForKey:[self keyForHost:host]];
    self.all = map;
}

// Resolved values

+ (double)zoomForHost:(NSString *)host {
    NSNumber *v = [self overrideForHost:host].zoom;
    return v ? v.doubleValue : Settings.defaultZoom;
}

+ (BOOL)javascriptForHost:(NSString *)host {
    NSNumber *v = [self overrideForHost:host].javascript;
    return v ? v.boolValue : Settings.javascriptEnabled;
}

+ (BOOL)cookiePopupsForHost:(NSString *)host {
    NSNumber *v = [self overrideForHost:host].cookiePopups;
    return v ? v.boolValue : Settings.blockCookiePopups;
}

+ (AutoplayPolicy)autoplayForHost:(NSString *)host {
    NSInteger raw = AutoplayPolicyFromRaw([self overrideForHost:host].autoplay);
    return raw >= 0 ? (AutoplayPolicy)raw : Settings.autoplay;
}

+ (BOOL)forceDarkForHost:(NSString *)host { return [self overrideForHost:host].forceDark.boolValue; }

+ (UserAgentChoice)userAgentForHost:(NSString *)host {
    NSInteger raw = UserAgentChoiceFromRaw([self overrideForHost:host].userAgent);
    return raw >= 0 ? (UserAgentChoice)raw : UserAgentChoiceSafari;
}

+ (BOOL)blockAdsForHost:(NSString *)host {
    NSNumber *v = [self overrideForHost:host].blockAds;
    return v ? v.boolValue : Settings.blockAds;
}

+ (WKUserScript *)forceDarkScript {
    NSMutableArray<NSString *> *hosts = [NSMutableArray array];
    [self.all enumerateKeysAndObjectsUsingBlock:^(NSString *key, SiteOverride *o, BOOL *stop) {
        if (o.forceDark.boolValue) [hosts addObject:key];
    }];
    if (hosts.count == 0) return nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:hosts options:0 error:nil];
    // Inverts the page and flips media back, unless the page turns out to be dark already.
    NSString *source = [NSString stringWithFormat:
        @"(function () {\n"
         "  if (window.top !== window) return;\n"
         "  var h = location.hostname.toLowerCase().replace(/^www\\./, '');\n"
         "  var hosts = %@;\n"
         "  if (!hosts.some(function (p) { return h === p || h.endsWith('.' + p); })) return;\n"
         "  var s = document.createElement('style');\n"
         "  s.id = 'brook-force-dark';\n"
         "  s.textContent = 'html{filter:invert(1) hue-rotate(180deg)!important;background:#fff!important}'\n"
         "    + 'img,video,picture,canvas,svg image,iframe,embed,object,[style*=\"background-image\"]'\n"
         "    + '{filter:invert(1) hue-rotate(180deg)!important}';\n"
         "  (document.head || document.documentElement).appendChild(s);\n"
         "  function lum(c) {\n"
         "    var m = c.match(/[\\d.]+/g); if (!m || (m.length > 3 && +m[3] === 0)) return null;\n"
         "    return 0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2];\n"
         "  }\n"
         "  document.addEventListener('DOMContentLoaded', function () {\n"
         "    s.disabled = true;\n"
         "    var l = lum(getComputedStyle(document.body || document.documentElement).backgroundColor);\n"
         "    if (l === null) l = lum(getComputedStyle(document.documentElement).backgroundColor);\n"
         "    s.disabled = l !== null && l < 110;\n"
         "  });\n"
         "})();", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    return [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                               forMainFrameOnly:YES inContentWorld:Boosts.world];
}

@end

NSString *UserAgentString(UserAgentChoice choice) {
    switch (choice) {
        case UserAgentChoiceChrome:
            return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
                   @"Chrome/140.0.0.0 Safari/537.36";
        case UserAgentChoiceFirefox:
            return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0";
        case UserAgentChoiceMobile:
            return @"Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
                   @"Version/26.0 Mobile/15E148 Safari/604.1";
        default: return nil;
    }
}

WKAudiovisualMediaTypes AutoplayPolicyMediaTypes(AutoplayPolicy policy) {
    switch (policy) {
        case AutoplayPolicyAllow: return WKAudiovisualMediaTypeNone;
        case AutoplayPolicyBlockAudio: return WKAudiovisualMediaTypeAudio;
        case AutoplayPolicyBlockAll: return WKAudiovisualMediaTypeAll;
    }
    return WKAudiovisualMediaTypeNone;
}

// MARK: - Boosts

/// Custom CSS and JavaScript applied to matching sites, like Arc's Boosts.
@implementation Boost

- (instancetype)init {
    if ((self = [super init])) {
        _identifier = [NSUUID UUID];
        _name = @"";
        _site = @"";
        _css = @"";
        _js = @"";
        _enabled = YES;
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name site:(NSString *)site css:(NSString *)css js:(NSString *)js {
    if ((self = [self init])) {
        _name = [name copy];
        _site = [site copy];
        _css = [css copy] ?: @"";
        _js = [js copy] ?: @"";
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    Boost *b = [Boost new];
    b.identifier = _identifier;
    b.name = _name;
    b.site = _site;
    b.css = _css;
    b.js = _js;
    b.enabled = _enabled;
    return b;
}

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:Boost.class]) return NO;
    Boost *b = other;
    return [_identifier isEqual:b.identifier] && [_name isEqualToString:b.name] && [_site isEqualToString:b.site] &&
           [_css isEqualToString:b.css] && [_js isEqualToString:b.js] && _enabled == b.enabled;
}

- (NSUInteger)hash { return _identifier.hash; }

- (BOOL)matchesHost:(NSString *)host {
    NSString *pattern = BrookTrim(_site).lowercaseString;
    if ([pattern isEqualToString:@"*"]) return YES;
    if (!host || pattern.length == 0) return NO;
    NSString *h = host.lowercaseString;
    NSString *p = [pattern hasPrefix:@"www."] ? [pattern substringFromIndex:4] : pattern;
    return [h isEqualToString:p] || [h hasSuffix:[@"." stringByAppendingString:p]];
}

/// nil when a key is missing or has the wrong type.
+ (instancetype)fromJSON:(NSDictionary *)json {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    id i = json[@"id"], n = json[@"name"], s = json[@"site"], c = json[@"css"], j = json[@"js"], e = json[@"enabled"];
    NSUUID *uuid = [i isKindOfClass:NSString.class] ? [[NSUUID alloc] initWithUUIDString:i] : nil;
    if (!uuid || ![n isKindOfClass:NSString.class] || ![s isKindOfClass:NSString.class] ||
        ![c isKindOfClass:NSString.class] || ![j isKindOfClass:NSString.class] || !IsJSONBool(e)) return nil;
    Boost *b = [[Boost alloc] initWithName:n site:s css:c js:j];
    b.identifier = uuid;
    b.enabled = [e boolValue];
    return b;
}

- (NSDictionary *)toJSON {
    return @{@"id": _identifier.UUIDString, @"name": _name ?: @"", @"site": _site ?: @"",
             @"css": _css ?: @"", @"js": _js ?: @"", @"enabled": @(_enabled)};
}

@end

/// A JavaScript string literal for `s` (JSON-encoded).
static NSString *JSString(NSString *s) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[s ?: @""] options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (json.length < 2) return @"\"\"";
    return [json substringWithRange:NSMakeRange(1, json.length - 2)];
}

@implementation Boosts

static NSArray<Boost *> *sBoostCache;

+ (WKContentWorld *)world {
    static WKContentWorld *w;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ w = [WKContentWorld worldWithName:@"BrookBoosts"]; });
    return w;
}

+ (NSArray<Boost *> *)all {
    if (sBoostCache) return sBoostCache;
    NSArray *json = [Settings jsonForKey:@"boosts"];
    NSMutableArray *list = [NSMutableArray array];
    BOOL ok = [json isKindOfClass:NSArray.class];
    for (id item in ok ? json : @[]) {
        Boost *b = [Boost fromJSON:item];
        if (!b) { ok = NO; break; }   // one bad element rejects the whole list
        [list addObject:b];
    }
    sBoostCache = ok ? [list copy] : @[];
    return sBoostCache;
}

+ (void)setAll:(NSArray<Boost *> *)all {
    sBoostCache = [all copy];
    NSMutableArray *json = [NSMutableArray array];
    for (Boost *b in all) [json addObject:b.toJSON];
    [Settings setJSON:json forKey:@"boosts"];
}

+ (void)invalidate { sBoostCache = nil; }

+ (NSArray<Boost *> *)boostsForHost:(NSString *)host {
    NSMutableArray *out = [NSMutableArray array];
    for (Boost *b in self.all) if ([b matchesHost:host]) [out addObject:b];
    return out;
}

+ (void)save:(Boost *)boost {
    NSMutableArray *list = [self.all mutableCopy];
    NSUInteger i = [list indexOfObjectPassingTest:^BOOL(Boost *b, NSUInteger idx, BOOL *stop) {
        return [b.identifier isEqual:boost.identifier];
    }];
    if (i != NSNotFound) list[i] = boost; else [list addObject:boost];
    self.all = list;
}

+ (void)deleteID:(NSUUID *)identifier {
    NSMutableArray *list = [NSMutableArray array];
    for (Boost *b in self.all) if (![b.identifier isEqual:identifier]) [list addObject:b];
    self.all = list;
}

/// One user script for all enabled boosts. Each boost checks the hostname itself, so the
/// script is compiled once and shared by every tab.
+ (WKUserScript *)userScript {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (Boost *b in self.all) {
        if (!b.enabled || (b.css.length == 0 && b.js.length == 0)) continue;
        NSString *site = JSString(BrookTrim(b.site).lowercaseString);
        NSString *css = JSString(b.css);
        NSString *js = b.js.length == 0 ? @"" : [NSString stringWithFormat:
            @"try { (function(){\n%@\n})(); } catch (e) { console.error('Brook Boost', e); }", b.js];
        [parts addObject:[NSString stringWithFormat:
            @"if (m(%@)) {\n"
             "  if (%@.length) addCSS(%@);\n"
             "  %@\n"
             "}", site, css, css, js]];
    }
    if (parts.count == 0) return nil;
    NSString *source = [NSString stringWithFormat:
        @"(function () {\n"
         "  if (window.top !== window) return;\n"
         "  var h = location.hostname.toLowerCase();\n"
         "  function m(p) {\n"
         "    if (p === '*') return true;\n"
         "    if (p.indexOf('www.') === 0) p = p.slice(4);\n"
         "    return h === p || h.endsWith('.' + p);\n"
         "  }\n"
         "  function addCSS(css) {\n"
         "    try {\n"
         "      var sheet = new CSSStyleSheet();\n"
         "      sheet.replaceSync(css);\n"
         "      document.adoptedStyleSheets = document.adoptedStyleSheets.concat([sheet]);\n"
         "    } catch (e) {\n"
         "      var s = document.createElement('style');\n"
         "      s.textContent = css;\n"
         "      (document.head || document.documentElement).appendChild(s);\n"
         "    }\n"
         "  }\n"
         "  %@\n"
         "})();", [parts componentsJoinedByString:@"\n"]];
    return [[WKUserScript alloc] initWithSource:source
                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                               forMainFrameOnly:YES
                                 inContentWorld:self.world];
}

@end
