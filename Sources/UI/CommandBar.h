#import <AppKit/AppKit.h>

@class BrowserWindowController;

/// Borderless panel that can still become key (so the command bar field takes typing).
@interface KeyPanel : NSPanel
/// Stay out of the key window (the attached suggestions list: typing goes to the tab's field).
@property BOOL refusesKey;
@end

/// The ⌘T / ⌘L floating command bar: type a URL or search, pick from tabs, history and suggestions.
@interface CommandBarController : NSObject <NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithBrowser:(BrowserWindowController *)browser NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (readonly) BOOL isVisible;
/// YES pre-fills the current tab's URL and navigates it in place.
- (void)showEditingCurrent:(BOOL)editingCurrent;
/// Compact tabs: `field` (in the selected tab) takes the typing, the suggestions drop down under
/// `bar`, lined up with `anchor` (the tab), and Return navigates the current tab. `onEnd` runs once when editing ends: committed,
/// cancelled with Escape, or focus left the field.
- (void)showAttachedToField:(NSTextField *)field alignedWith:(NSView *)anchor below:(NSView *)bar
                      onEnd:(void (^)(void))onEnd;
@property (readonly) BOOL isAttached;
- (void)dismiss;
@end
