#import <AppKit/AppKit.h>
// Other-directory headers come in via Brook.h (import order there).
#import "SidebarParts.h"

@class BrowserWindowController;

/// The sidebar: nav row (its titleRow), address pill, favorites, the tab list and the spaces bar.
@interface SidebarView : NSView <BrowserChrome>
@property (weak) BrowserWindowController *browser;
@property (readonly) URLPillView *urlPill;
@end

/// NSMenuItem that runs a block.
@interface ClosureMenuItem : NSMenuItem
/// No key equivalent.
- (instancetype)initWithTitle:(NSString *)title handler:(void (^)(void))handler;
- (instancetype)initWithTitle:(NSString *)title key:(NSString *)key modifiers:(NSEventModifierFlags)modifiers
                      handler:(void (^)(void))handler NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithTitle:(NSString *)string action:(SEL)selector keyEquivalent:(NSString *)charCode NS_UNAVAILABLE;
@end

@interface NSArray <ObjectType> (BrookSafe)
/// nil when out of range (including negative).
- (ObjectType)brook_objectAtSafeIndex:(NSInteger)index;
@end
