#import <AppKit/AppKit.h>

@class BrowserTab;

/// One tab row in the sidebar: favicon, title, spinner, close button on hover.
@interface TabCellView : NSTableCellView
/// Reuse identifier ("TabCell").
@property (class, readonly) NSUserInterfaceItemIdentifier reuseID;
@property (nonatomic, readonly, weak) BrowserTab *tab;
@property (copy) void (^onClose)(BrowserTab *tab);
@property (nonatomic) CGFloat fontSize;   // default 13
- (void)configureWithTab:(BrowserTab *)tab selected:(BOOL)selected;
/// Refreshes title/icon/spinner from the tab.
- (void)updateWithTab:(BrowserTab *)tab;
- (void)setSelected:(BOOL)selected;
@end

/// The "New Tab" row.
@interface NewTabCellView : NSTableCellView
@property (class, readonly) NSUserInterfaceItemIdentifier reuseID;   // "NewTabCell"
@property (nonatomic) CGFloat fontSize;   // default 13
@end

/// Hairline between pinned and regular tabs.
@interface DividerCellView : NSTableCellView
@property (class, readonly) NSUserInterfaceItemIdentifier reuseID;   // "DividerCell"
@end

/// Row view that draws no selection or background.
@interface PlainRowView : NSTableRowView
@end

@interface SidebarTableView : NSTableView
/// Middle-click on a row (row index).
@property (copy) void (^onMiddleClick)(NSInteger row);
@end

/// Scroll view that turns a horizontal two-finger swipe into a space switch (+1 / -1).
@interface SidebarScrollView : NSScrollView
@property (copy) void (^onSwipe)(NSInteger delta);
@end
