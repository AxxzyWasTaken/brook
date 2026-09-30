#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

/// What's hidden on a site (⇧⌘H) and the way back. Pointing at a row shows that one thing on the page again,
/// outlined and scrolled to, so you pick what to restore by looking at it rather than decoding a selector.
/// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), Hidden.swift.
@interface HiddenElementsViewController : NSViewController
/// host is the page's host; onHideMore starts picking (the popover closes first).
- (instancetype)initWithHost:(NSString *)host webView:(WKWebView *)webView onHideMore:(void (^)(void))onHideMore NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end
