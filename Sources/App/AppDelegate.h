#import <AppKit/AppKit.h>

/// The app delegate: menu bar, lifecycle, memory management, links from other apps.
/// main() in main.mm creates it and runs the app.
/// Menu actions (newTab:, closeTab:, …) are private to AppDelegate.mm and reached via the responder chain.
@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>
@end
