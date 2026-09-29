#import <AppKit/AppKit.h>

/// Popover shown from the lock icon in the address pill: this site's settings, one click away.
@interface SiteInfoViewController : NSViewController
/// host is normalised with +[SiteSettings keyForHost:].
- (instancetype)initWithHost:(NSString *)host secure:(BOOL)secure NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

/// Popover shown from the shield in the address pill: ad blocking for this site, and a switch to turn it off.
@interface AdBlockViewController : NSViewController
/// host is normalised with +[SiteSettings keyForHost:].
- (instancetype)initWithHost:(NSString *)host NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end
