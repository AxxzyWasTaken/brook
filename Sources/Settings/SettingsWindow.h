#import <AppKit/AppKit.h>

// GeneralPane, AppearancePane, TabsPane, SearchPane, WebsitesPane, BoostsPane and AdvancedPane
// stay private to SettingsWindow.mm.

/// The ⌘, window: a native toolbar-tabbed preferences window like Safari's.
@interface SettingsWindowController : NSWindowController
@property (class, readonly) SettingsWindowController *shared;
/// Always go through +shared.
- (void)show;
/// Selects the pane whose label matches ("General", "Boosts", …), then shows.
- (void)showPane:(NSString *)pane;
- (void)importPasswords;
/// Shows the Boosts pane with the boost that has this identifier selected.
- (void)showBoost:(NSUUID *)identifier;
@end
