#import <AppKit/AppKit.h>

/// The app delegate: menu bar, lifecycle, memory management, links from other apps.
/// main() in main.mm creates it and runs the app.
/// Menu actions (newTab:, closeTab:, …) are private to AppDelegate.mm and reached via the responder chain.
@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>
/// Every menu command that can have a shortcut, in menu order: (section title, item).
+ (NSArray<NSArray *> *)shortcutItems;
/// Stable id for a menu command: its action, plus the tag for numbered ones ("selectTabN:3").
+ (NSString *)shortcutIDForItem:(NSMenuItem *)item;
/// The built-in shortcut, as a Settings.shortcuts-style string ("" = none).
+ (NSString *)defaultShortcutForItem:(NSMenuItem *)item;
/// Re-reads Settings.shortcuts into the menu bar.
+ (void)applyShortcuts;
/// Re-draws the Dock icon for Settings.appIcon.
+ (void)applyAppIcon;
@end
