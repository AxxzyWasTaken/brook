#import <AppKit/AppKit.h>
// Other-directory headers come in via Brook.h (import order there).
#import "SidebarParts.h"

@class BrowserWindowController;

/// The sidebar: nav row, address pill, favorites, the tab list and the spaces bar.
@interface SidebarView : NSView
@property (weak) BrowserWindowController *browser;

// Top
@property (readonly) NSView *navRow;
/// Adjusted by the window controller to line the nav row up with the traffic lights.
@property (readonly) NSLayoutConstraint *navRowTop;
@property (readonly) NSLayoutConstraint *navRowLeading;
@property (readonly) URLPillView *urlPill;

/// Re-reads the appearance settings that affect the sidebar.
- (void)applySettings;
/// Reloads without a transition.
- (void)reloadAll;
/// Slides the tab list in from the right (forward) or left.
- (void)reloadAllWithSpaceTransition:(BOOL)forward;
- (void)updateSelection;
- (void)tabChanged:(BrowserTab *)tab change:(TabChange)change;
/// Back/forward/reload state and the address pill.
- (void)updateChrome;
/// Context menu for a tab (also used by the favorites grid).
- (NSMenu *)menuForTab:(BrowserTab *)tab;
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
