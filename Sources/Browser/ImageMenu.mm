#import "Brook.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// See ImageMenu.h.
// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), ImageMenu.swift.

static const NSUInteger kLargestImage = 50'000'000;   // bytes: a small file can claim to be enormous
static const NSUInteger kMostPixels = 100'000'000;    // and it is Brook that would decode it

/// A menu item that runs a block (NSMenuItem wants a target; being its own is simplest).
@interface ImageMenuItem : NSMenuItem
@property (copy) void (^run)(void);
@end

@implementation ImageMenuItem
- (void)fire { if (_run) _run(); }
@end

static WKContentWorld *ImageWorld(void) { return [WKContentWorld worldWithName:@"BrookImages"]; }

static NSInteger IndexOf(NSMenu *menu, NSString *identifier) {
    for (NSInteger i = 0; i < menu.numberOfItems; i++) if ([[menu itemAtIndex:i].identifier isEqualToString:identifier]) return i;
    return -1;
}

@implementation ImageMenu

/// No cookies (not kept, not sent) and nothing cached: a copy is not a visit.
+ (NSURLSession *)fetcher {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *c = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        c.HTTPCookieStorage = nil;
        c.HTTPShouldSetCookies = NO;
        c.URLCache = nil;
        c.URLCredentialStorage = nil;
        c.timeoutIntervalForRequest = 30;
        session = [NSURLSession sessionWithConfiguration:c];
    });
    return session;
}

/// One of its frames at most kMostPixels, read from the header before anything is unpacked.
static BOOL Reasonable(NSData *data) {
    if (!data.length || data.length > kLargestImage) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data,
                                                          (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache: @NO});
    if (!source) return NO;
    BOOL ok = NO;
    if (CGImageSourceGetCount(source) > 0) {
        NSDictionary *p = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, nil);
        NSInteger w = [p[(id)kCGImagePropertyPixelWidth] integerValue], h = [p[(id)kCGImagePropertyPixelHeight] integerValue];
        ok = w > 0 && h > 0 && (NSUInteger)w * (NSUInteger)h <= kMostPixels;
    }
    CFRelease(source);
    return ok;
}

+ (void)imageDataAt:(NSURL *)url frame:(WKFrameInfo *)frame webView:(WKWebView *)webView
         completion:(void (^)(NSData *, NSString *))completion {
    NSString *scheme = url.scheme.lowercaseString;
    void (^done)(NSData *, NSString *) = ^(NSData *data, NSString *type) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(Reasonable(data) ? data : nil, type); });
    };
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"data"]) {
        NSURLSessionDataTask *task = [self.fetcher dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
            NSInteger status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 200;
            done(status >= 200 && status < 300 ? data : nil, r.MIMEType);
        }];
        [task resume];
        return;
    }
    if (![scheme isEqualToString:@"blob"] || !webView) { done(nil, nil); return; }
    // A blob: picture exists only in the page that made it, where no URLSession reaches: read it there, in the
    // frame it was right-clicked in, in Brook's own world (the page's scripts can't see or change the read).
    NSString *read = @"const found = await fetch(src);"
                      "const blob = await found.blob();"
                      "if (!blob.type.startsWith('image/') || blob.size > 50000000) return null;"
                      "const bytes = new Uint8Array(await blob.arrayBuffer());"
                      "let text = '';"
                      "for (let i = 0; i < bytes.length; i += 32768) text += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));"
                      "return [btoa(text), blob.type];";
    [webView callAsyncJavaScript:read arguments:@{@"src": url.absoluteString} inFrame:frame inContentWorld:ImageWorld()
               completionHandler:^(id result, NSError *error) {
        NSArray *pair = [result isKindOfClass:NSArray.class] && [result count] == 2 ? result : nil;
        NSData *data = [pair[0] isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:pair[0] options:0] : nil;
        done(data, [pair[1] isKindOfClass:NSString.class] ? pair[1] : nil);
    }];
}

static void Toast(NSString *text) {
    id wc = NSApp.mainWindow.windowController;
    if ([wc isKindOfClass:BrowserWindowController.class]) [(BrowserWindowController *)wc showToast:text];
}

/// A file name for the picture: the address's own if it has one, else "Image" with the type's extension.
static NSString *FileName(NSURL *url, NSString *suggested, NSString *mimeType) {
    NSString *name = suggested.length ? suggested : nil;
    NSString *scheme = url.scheme.lowercaseString;
    if (!name && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        NSString *last = url.lastPathComponent;
        if (last.length && ![last isEqualToString:@"/"]) name = last.stringByRemovingPercentEncoding ?: last;
    }
    if (!name) name = @"Image";
    if (!name.pathExtension.length && mimeType.length) {
        if (NSString *ext = [UTType typeWithMIMEType:mimeType].preferredFilenameExtension) name = [name stringByAppendingPathExtension:ext];
    }
    return name;
}

+ (void)copyImageAt:(NSURL *)url frame:(WKFrameInfo *)frame webView:(WKWebView *)webView {
    [self imageDataAt:url frame:frame webView:webView completion:^(NSData *data, NSString *type) {
        NSImage *image = data ? [[NSImage alloc] initWithData:data] : nil;
        if (!image) { Toast(@"Couldn’t copy that image"); return; }
        // Real bytes, not a promise: a receiving app picks TIFF, PNG or whatever it asks for.
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard writeObjects:@[image]];
        Toast(@"Image copied");
    }];
}

+ (void)downloadImageAt:(NSURL *)url suggested:(NSString *)suggested frame:(WKFrameInfo *)frame webView:(WKWebView *)webView {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        // The same WKDownload any other download is, asked for directly (the menu's own never reached Brook).
        [webView startDownloadUsingRequest:[NSURLRequest requestWithURL:url] completionHandler:^(WKDownload *download) {
            [DownloadManager.shared track:download];
        }];
        return;
    }
    // data: and blob: can't be downloaded from outside the page: read the bytes and save them.
    [self imageDataAt:url frame:frame webView:webView completion:^(NSData *data, NSString *type) {
        if (!data) { Toast(@"Couldn’t download that image"); return; }
        [DownloadManager.shared saveData:data suggestedFilename:FileName(url, suggested, type) completion:^(NSURL *file) {
            if (!file) Toast(@"Couldn’t download that image");
        }];
    }];
}

+ (void)adjustMenu:(NSMenu *)menu element:(id)element webView:(WKWebView *)webView {
    static SEL hitSel = NSSelectorFromString(@"hitTestResult");
    id hit = [element respondsToSelector:hitSel] ? ((id (*)(id, SEL))objc_msgSend)(element, hitSel) : nil;
    NSURL *url = [hit respondsToSelector:@selector(absoluteImageURL)] ? [hit valueForKey:@"absoluteImageURL"] : nil;
    NSString *scheme = url.scheme.lowercaseString;
    if (!url || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"data"] ||
                  [scheme isEqualToString:@"blob"])) return;
    WKFrameInfo *frame = [hit respondsToSelector:@selector(frameInfo)] ? [hit valueForKey:@"frameInfo"] : nil;
    NSString *suggested = [hit respondsToSelector:NSSelectorFromString(@"imageSuggestedFilename")] ? [hit valueForKey:@"imageSuggestedFilename"] : nil;
    __weak WKWebView *weakView = webView;
    for (NSInteger i = 0; i < menu.numberOfItems; i++) {
        NSMenuItem *item = [menu itemAtIndex:i];
        NSString *identifier = item.identifier;
        void (^run)(void) = nil;
        if ([identifier isEqualToString:@"WKMenuItemIdentifierDownloadImage"]) {
            run = ^{ [ImageMenu downloadImageAt:url suggested:suggested frame:frame webView:weakView]; };
        } else if ([identifier isEqualToString:@"WKMenuItemIdentifierCopyImage"]) {
            run = ^{ [ImageMenu copyImageAt:url frame:frame webView:weakView]; };
        }
        if (!run) continue;
        ImageMenuItem *mine = [[ImageMenuItem alloc] initWithTitle:item.title action:@selector(fire) keyEquivalent:@""];
        mine.target = mine;
        mine.run = run;
        mine.identifier = identifier;
        mine.image = item.image;
        [menu removeItemAtIndex:i];
        [menu insertItem:mine atIndex:i];
    }
    // Copy Image Address, which WebKit's menu doesn't have.
    NSInteger copy = IndexOf(menu, @"WKMenuItemIdentifierCopyImage");
    if (copy >= 0 && IndexOf(menu, @"brook.copyImageAddress") < 0 && ![scheme isEqualToString:@"blob"]) {
        ImageMenuItem *address = [[ImageMenuItem alloc] initWithTitle:@"Copy Image Address" action:@selector(fire) keyEquivalent:@""];
        address.target = address;
        address.identifier = @"brook.copyImageAddress";
        address.run = ^{
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:url.absoluteString forType:NSPasteboardTypeString];
        };
        [menu insertItem:address atIndex:copy + 1];
    }
}

@end
