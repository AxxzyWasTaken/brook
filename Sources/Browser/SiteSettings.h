#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
// Needs Settings.h (AutoplayPolicy); included via Brook.h.

// MARK: - Per-site settings

/// Overrides for one site. nil means "use the global setting".
/// Treat instances as values (copy before mutating a shared one).
/// JSON (stored in Settings key "siteSettings" as {host: override}) uses the keys
/// "zoom" (number), "javascript" (bool), "autoplay" (AutoplayPolicy raw string), "cookiePopups" (bool),
/// "forceDark" (bool), "userAgent" (UserAgentChoice raw string), "blockAds" (bool);
/// nil fields are omitted.
@interface SiteOverride : NSObject <NSCopying>
@property (strong) NSNumber *zoom;          // double
@property (strong) NSNumber *javascript;    // BOOL
@property (copy) NSString *autoplay;        // AutoplayPolicy raw value ("allow", "blockAudio", "blockAll")
@property (strong) NSNumber *cookiePopups;  // BOOL
@property (strong) NSNumber *forceDark;     // BOOL (nil = off)
@property (copy) NSString *userAgent;       // UserAgentChoice raw value (nil = Safari)
@property (strong) NSNumber *blockAds;      // BOOL (nil = the global setting)
@property (readonly) BOOL isEmpty;
+ (instancetype)fromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;
@end

/// Per-site overrides, cached from Settings' "siteSettings" JSON blob.
@interface SiteSettings : NSObject
/// Sites are keyed by host without a leading "www." (lowercased).
+ (NSString *)keyForHost:(NSString *)host;
/// Every override, keyed by site. Setting it drops empty overrides and saves (posts "siteSettings").
@property (class, copy) NSDictionary<NSString *, SiteOverride *> *all;
+ (void)invalidate;
/// The override for a host. Each unset field comes from the nearest parent domain that sets it
/// ("m.example.com" → "example.com").
/// Never nil (an empty override when nothing matches or host is nil).
+ (SiteOverride *)overrideForHost:(NSString *)host;
/// Mutates (a copy of) the host's override and saves.
+ (void)updateHost:(NSString *)host change:(void (^)(SiteOverride *o))change;
+ (void)removeHost:(NSString *)host;

// Resolved values (override, else the global setting). host may be nil.
+ (double)zoomForHost:(NSString *)host;
+ (BOOL)javascriptForHost:(NSString *)host;
+ (BOOL)cookiePopupsForHost:(NSString *)host;
+ (AutoplayPolicy)autoplayForHost:(NSString *)host;
+ (BOOL)forceDarkForHost:(NSString *)host;
+ (UserAgentChoice)userAgentForHost:(NSString *)host;
+ (BOOL)blockAdsForHost:(NSString *)host;
/// Dims every site with forceDark set (nil when none). Shared by every tab, like Boosts.
+ (WKUserScript *)forceDarkScript;
@end

/// The full user-agent string for a choice (nil = WebKit's own, with Brook's Safari suffix).
FOUNDATION_EXPORT NSString *UserAgentString(UserAgentChoice choice);

/// Media types that need a user gesture to play.
FOUNDATION_EXPORT WKAudiovisualMediaTypes AutoplayPolicyMediaTypes(AutoplayPolicy policy);

// MARK: - Boosts

/// Custom CSS and JavaScript applied to matching sites, like Arc's Boosts.
/// JSON (Settings key "boosts", an array) keys: "id" (UUID string), "name", "site", "css", "js", "enabled".
@interface Boost : NSObject <NSCopying>
@property (strong) NSUUID *identifier;   // JSON "id"
@property (copy) NSString *name;
/// Domain the boost applies to (subdomains included), or "*" for every site.
@property (copy) NSString *site;
@property (copy) NSString *css;          // default ""
@property (copy) NSString *js;           // default ""
@property BOOL enabled;                  // default YES
/// New boost with a fresh id, enabled.
- (instancetype)initWithName:(NSString *)name site:(NSString *)site css:(NSString *)css js:(NSString *)js;
- (BOOL)matchesHost:(NSString *)host;
+ (instancetype)fromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;
@end

@interface Boosts : NSObject
/// Content world "BrookBoosts" the boost script runs in.
@property (class, readonly) WKContentWorld *world;
/// Setting it saves (posts "boosts").
@property (class, copy) NSArray<Boost *> *all;
+ (void)invalidate;
+ (NSArray<Boost *> *)boostsForHost:(NSString *)host;
/// Replaces the boost with the same id, or appends it.
+ (void)save:(Boost *)boost;
+ (void)deleteID:(NSUUID *)identifier;
/// One user script for all enabled boosts (nil when there are none). Each boost checks the
/// hostname itself, so the script is compiled once and shared by every tab.
+ (WKUserScript *)userScript;
@end
