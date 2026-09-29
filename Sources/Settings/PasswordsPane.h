#import <AppKit/AppKit.h>
#import "SettingsControls.h"

@interface PasswordsPane : RebuildingPane <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
- (void)beginImport;
@end
