#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

/// Download Image and Copy Image on a page's right-click menu, done by Brook rather than WebKit.
///
/// WebKit's own two either do nothing or write a pasteboard promise some apps can't paste from, and a
/// blob: picture (WhatsApp Web, most chat apps) can't be fetched from outside the page that made it.
/// WebKit's proposed menu (WKUIDelegatePrivate) is kept as it is (Copy Subject, Look Up and the rest stay) and
/// only those two items are pointed here, with the hit-tested image address and frame.
/// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), ImageMenu.swift.
@interface ImageMenu : NSObject
/// Retargets the image items in WebKit's proposed menu for this element (a _WKContextMenuElementInfo).
+ (void)adjustMenu:(NSMenu *)menu element:(id)element webView:(WKWebView *)webView;
/// The picture's bytes: fetched without cookies or a cache for http(s), decoded for data:, read inside the
/// frame for blob:. nil past 50 MB, if it isn't an image, or if it would decode to more than 100M pixels.
+ (void)imageDataAt:(NSURL *)url frame:(WKFrameInfo *)frame webView:(WKWebView *)webView
         completion:(void (^)(NSData *data, NSString *mimeType))completion;
@end
