#import <AppKit/AppKit.h>
#import "Controls.h"

@class BrowserTab, Space;

/// The address pill at the top of the sidebar.
@interface URLPillView : HoverControl
@property (readonly) IconButton *siteButton;
@property (readonly) IconButton *extensionsButton;
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
@end

/// A space's coloured dot in the sidebar's bottom bar.
@interface SpaceDot : HoverControl
- (instancetype)initWithSpace:(Space *)space;
@property (readonly) Space *space;
@property (nonatomic) BOOL isCurrent;
@end
