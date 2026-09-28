#import <AppKit/AppKit.h>

@class BrowserTab;

/// One tab row in the sidebar: favicon, title (and site), spinner, close button.
/// Reads the tab style, close-button, subtitle, loading and font settings when configured.
@interface TabCellView : NSTableCellView
/// Reuse identifier ("TabCell").
@property (class, readonly) NSUserInterfaceItemIdentifier reuseID;
@property (nonatomic, readonly, weak) BrowserTab *tab;
@property (copy) void (^onClose)(BrowserTab *tab);
/// Pressed through accessibility (VoiceOver, Voice Control); clicks go through the table.
@property (copy) void (^onSelect)(BrowserTab *tab);
@property (nonatomic) CGFloat fontSize;   // default 13
/// The icon-only sidebar rail: just the favicon, centred.
@property (nonatomic) BOOL iconOnly;
- (void)configureWithTab:(BrowserTab *)tab selected:(BOOL)selected;
/// Refreshes title/icon/spinner from the tab.
- (void)updateWithTab:(BrowserTab *)tab;
- (void)setSelected:(BOOL)selected;
@end

/// The "New Tab" row.
@interface NewTabCellView : NSTableCellView
@property (class, readonly) NSUserInterfaceItemIdentifier reuseID;   // "NewTabCell"
@property (nonatomic) CGFloat fontSize;   // default 13
@property (nonatomic) BOOL iconOnly;
/// Pressed through accessibility; clicks go through the table.
@property (copy) void (^onPress)(void);
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

/// The tab list's scroll view. Scroll events go to `swipeHandler` first, which takes the sideways
/// two-finger swipes that switch spaces (returning YES); the rest scroll the list.
@interface SidebarScrollView : NSScrollView
@property (copy) BOOL (^swipeHandler)(NSEvent *event);
@end
