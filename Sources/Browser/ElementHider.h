#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

/// One thing taken off a site: a CSS selector, what it was in words, and its size and corner when hidden
/// (a hidden thing has no size to measure later).
@interface HiddenElement : NSObject
@property (copy) NSString *selector;
@property (copy) NSString *label;
@property (copy) NSString *note;
@end

/// Posted when the hidden elements change; userInfo "site" is the site key.
FOUNDATION_EXPORT NSNotificationName const ElementHiderDidChangeNotification;

/// Things taken off pages, for good (⇧⌘H: point at a cookie bar, an overlay, a rail of "related" links).
/// Kept per site (SiteSettings keyForHost:) in Settings key "hiddenElements" ({site: [{selector, label, note}]}),
/// and put back on by a stylesheet at document start, so nothing is seen appearing and then vanishing.
/// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), Curtain.swift.
@interface ElementHider : NSObject
@property (class, readonly) ElementHider *shared;
@property (class, readonly) WKContentWorld *world;
/// The picker, in world BrookHide on every main frame, asleep until asked.
@property (readonly) WKUserScript *pickerScript;
/// Every site's rules, applied at document start to the site it's for. nil when nothing is hidden anywhere.
- (WKUserScript *)styleScript;
- (NSArray<HiddenElement *> *)elementsForHost:(NSString *)host;
/// The stylesheet for a site, one rule per selector (a selector WebKit can't parse only loses its own rule),
/// optionally leaving one out: how the panel shows what it's offering to bring back.
- (NSString *)cssForHost:(NSString *)host without:(NSString *)spared;
- (void)hide:(NSString *)selector label:(NSString *)label note:(NSString *)note onHost:(NSString *)host;
- (void)restore:(NSString *)selector onHost:(NSString *)host;
/// The last one hidden, back (⌘Z while picking). Returns it, or nil.
- (HiddenElement *)undoOnHost:(NSString *)host;
- (void)restoreAllOnHost:(NSString *)host;

// The page in a web view.
- (void)startPickingIn:(WKWebView *)webView;
- (void)stopPickingIn:(WKWebView *)webView;
/// The site's current rules on the page now (the next load gets them from styleScript).
- (void)applyIn:(WKWebView *)webView host:(NSString *)host;
- (void)peek:(NSString *)selector in:(WKWebView *)webView host:(NSString *)host;
- (void)unpeekIn:(WKWebView *)webView host:(NSString *)host;
/// Picks the element at this point in CSS pixels (tests and keyboard use).
- (void)pickAtPoint:(CGPoint)point in:(WKWebView *)webView;
/// Messages from the picker: a pick, the picker turned off (Escape), or trouble.
@property (copy) void (^onPick)(WKWebView *webView, NSString *selector, NSString *label, NSString *note);
@property (copy) void (^onPickingEnded)(WKWebView *webView);
/// ⌘Z pressed while picking (the page gets the key before the Edit menu does).
@property (copy) void (^onUndo)(WKWebView *webView);
- (void)installHandlersInto:(WKUserContentController *)ucc;
@end
