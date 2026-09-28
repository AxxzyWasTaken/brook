#import <AppKit/AppKit.h>
#import "Controls.h"

@class BrowserTab, Space, ExtensionsBar;

/// The address pill at the top of the sidebar or in the top bar's toolbar row.
@interface URLPillView : HoverControl
/// With extensions: the extension buttons sit inside the pill's trailing end (the sidebar).
/// Without: the top bar shows them in their own capsule beside the pill, and a reload button
/// takes the pill's trailing end instead, like Safari's.
- (instancetype)initWithExtensions:(BOOL)withExtensions;
@property (readonly) IconButton *siteButton;
/// Reload / stop at the trailing end; nil when made -initWithExtensions:YES.
@property (readonly) IconButton *reloadButton;
/// nil unless made -initWithExtensions:YES.
@property (readonly) ExtensionsBar *extensionsBar;
/// tab may be nil.
- (void)updateWithTab:(BrowserTab *)tab;
@end

/// Favorites as a grid of tiles above the tab list. (FavoriteTile stays private to SidebarParts.mm.)
@interface FavoritesGridView : NSView
@property (copy) void (^onSelect)(BrowserTab *tab);
/// A tab dropped onto the grid: its id and the index to insert at.
@property (copy) void (^onDropTab)(NSUUID *tabID, NSInteger index);
@property (copy) NSMenu *(^menuProvider)(BrowserTab *tab);
@property (nonatomic) NSInteger maxColumns;   // default 4
- (void)reloadFavorites:(NSArray<BrowserTab *> *)favorites selected:(BrowserTab *)selected;
- (void)updateSelection:(BrowserTab *)selected;
/// Redraws the tile for one tab.
- (void)refresh:(BrowserTab *)tab;
/// The tile showing a tab, if it's a favorite here.
- (NSView *)tileForTab:(BrowserTab *)tab;
@end

/// A space's coloured dot in the sidebar's bottom bar.
@interface SpaceDot : HoverControl
- (instancetype)initWithSpace:(Space *)space;
@property (readonly) Space *space;
@property (nonatomic) BOOL isCurrent;
/// The rail's single dot: clicking lists the spaces rather than switching to this one. It's then
/// sized by whoever places it (the whole glass piece is the button), not a fixed 24pt square.
@property (nonatomic) BOOL opensMenu;
@end

/// What the window controller needs from whichever tab UI is showing: the sidebar or the top bar.
@protocol BrowserChrome <NSObject>
@property (readonly) URLPillView *urlPill;
/// Extension buttons; popups open from them.
@property (readonly) ExtensionsBar *extensionsBar;
/// The row the traffic lights sit beside, its height, and the constraints the window controller
/// adjusts to line it up with them (distance from the top, and room left for the lights).
@property (readonly) NSView *titleRow;
@property (readonly) CGFloat titleRowHeight;
@property (readonly) NSLayoutConstraint *titleRowTop;
@property (readonly) NSLayoutConstraint *titleRowLeading;
/// Re-reads the appearance settings that affect it.
- (void)applySettings;
- (void)reloadAll;
/// Reloads with the tabs sliding in from the right (forward) or left.
- (void)reloadAllWithSpaceTransition:(BOOL)forward;
- (void)updateSelection;
- (void)tabChanged:(BrowserTab *)tab change:(TabChange)change;
/// Back/forward/reload state and the address pill.
- (void)updateChrome;
@end

/// The buttons beside the traffic lights (Settings → Layout → Toolbar buttons), in the chosen
/// order. Shared by the sidebar and the top bar.
@interface ToolbarButtons : NSStackView
@property (weak) BrowserWindowController *browser;
/// For a row given its width from outside: buttons that don't fit move, from the end, into a "»"
/// menu after the rest (the sidebar's nav row, which the toggle and sidebar edge bound).
@property (nonatomic) BOOL overflows;
/// Buttons per row (the icon rail's grid); set before -rebuild. 0 lays them out in one line.
@property (nonatomic) NSUInteger columns;
/// Adds site settings when it isn't one of the chosen items (the rail has no address pill).
@property (nonatomic) BOOL includesSiteSettings;
/// Rebuilds from Settings.toolbarItems.
- (void)rebuild;
/// Enabled state and the reload/stop symbol.
- (void)updateWithTab:(BrowserTab *)tab;
/// The button for an item, when it's showing.
- (IconButton *)buttonForItem:(ToolbarItem)item;
@end
