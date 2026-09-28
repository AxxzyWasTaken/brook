#import "Brook.h"
#import <QuartzCore/QuartzCore.h>

/// A short warm flash that sweeps up the window.
@interface FireAnimationView : NSView
+ (void)playInHost:(NSView *)host;
@end

@implementation Fire

/// Asks, then closes regular tabs, resets pinned tabs, and wipes cookies, cache, storage and history.
+ (void)confirmAndBurnInWindow:(NSWindow *)window overlayHost:(NSView *)overlayHost {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Burn all tabs and browsing data?";
    alert.informativeText = @"Closes every open tab and clears cookies, site data, cache and history. Pinned tabs and favorites stay, but are signed out.";
    [alert addButtonWithTitle:@"Burn"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.buttons.firstObject.hasDestructiveAction = YES;
    void (^run)(NSModalResponse) = ^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [Fire burnWithOverlayHost:overlayHost];
    };
    if (window) [alert beginSheetModalForWindow:window completionHandler:run]; else run([alert runModal]);
}

/// Removes every kind of website data from each store in turn.
static void BrookRemoveAllData(NSArray<WKWebsiteDataStore *> *stores, NSUInteger index) {
    if (index >= stores.count) return;
    [stores[index] removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes
                       modifiedSince:NSDate.distantPast
                   completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{ BrookRemoveAllData(stores, index + 1); });
    }];
}

+ (void)burnWithOverlayHost:(NSView *)overlayHost {
    if (overlayHost) [FireAnimationView playInHost:overlayHost];
    [BrowserState.shared burnTabs];
    // Every profile: the main one plus each space's separate one.
    NSMutableArray<WKWebsiteDataStore *> *stores = [NSMutableArray arrayWithObject:WKWebsiteDataStore.defaultDataStore];
    for (Space *space in BrowserState.shared.spaces) {
        if (space.profileID) [stores addObject:[WebViewFactory dataStoreForProfileID:space.profileID]];
    }
    BrookRemoveAllData(stores, 0);
    [NSURLCache.sharedURLCache removeAllCachedResponses];
}

@end

@implementation FireAnimationView {
    CAGradientLayer *_gradient;
}

+ (void)playInHost:(NSView *)host {
    FireAnimationView *v = [[FireAnimationView alloc] initWithFrame:host.bounds];
    v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [host addSubview:v positioned:NSWindowAbove relativeTo:nil];
    [v run];
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _gradient = [CAGradientLayer layer];
        self.wantsLayer = YES;
        _gradient.colors = @[
            (__bridge id)[NSColor colorWithSRGBRed:1 green:0.32 blue:0.1 alpha:0.85].CGColor,
            (__bridge id)[NSColor colorWithSRGBRed:1 green:0.62 blue:0.1 alpha:0.55].CGColor,
            (__bridge id)[NSColor colorWithSRGBRed:1 green:0.85 blue:0.3 alpha:0].CGColor
        ];
        _gradient.startPoint = CGPointMake(0.5, 0);
        _gradient.endPoint = CGPointMake(0.5, 1);
        _gradient.frame = self.bounds;
        [self.layer addSublayer:_gradient];
        self.layer.opacity = 0;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    [NSException raise:NSInternalInconsistencyException format:@"init(coder:) has not been implemented"];
    return [super initWithCoder:coder];
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (void)run {
    CALayer *layer = self.layer;
    if (!layer) return;
    _gradient.frame = self.bounds;
    // Reduce Motion: the same warm wash glows in place at the bottom of the window, no sweep.
    BOOL still = BrookReduceMotion();
    CFTimeInterval duration = still ? 0.6 : 0.9;
    if (!still) {
        CABasicAnimation *rise = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
        rise.fromValue = @(-self.bounds.size.height);
        rise.toValue = @(self.bounds.size.height * 0.25);
        rise.duration = duration;
        rise.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_gradient addAnimation:rise forKey:@"rise"];
    }
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = still ? @[@0, @0.7, @0.7, @0] : @[@0, @1, @1, @0];
    fade.keyTimes = @[@0, @0.2, @0.55, @1];
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[fade];
    group.duration = duration;
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [CATransaction begin];
    __weak FireAnimationView *weakSelf = self;
    [CATransaction setCompletionBlock:^{
        [weakSelf removeFromSuperview];
    }];
    [layer addAnimation:group forKey:@"fade"];
    [CATransaction commit];
}

@end
