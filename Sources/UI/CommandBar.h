#import <AppKit/AppKit.h>

@class BrowserWindowController;

/// Borderless panel that can still become key (so the command bar field takes typing).
@interface KeyPanel : NSPanel
@end

/// The ⌘T / ⌘L floating command bar: type a URL or search, pick from tabs, history and suggestions.
@interface CommandBarController : NSObject <NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithBrowser:(BrowserWindowController *)browser NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (readonly) BOOL isVisible;
/// YES pre-fills the current tab's URL and navigates it in place.
- (void)showEditingCurrent:(BOOL)editingCurrent;
- (void)dismiss;
@end
