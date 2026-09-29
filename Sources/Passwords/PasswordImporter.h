#import <AppKit/AppKit.h>

@class LoginCandidate;

/// A Chromium-based browser whose saved passwords Brook can read directly.
@interface ChromiumBrowser : NSObject
@property (readonly) NSString *name;
@property (readonly) NSString *bundleID;
/// ~/Library/Application Support/<…>: holds "Local State" and one folder per profile.
@property (readonly) NSURL *dataFolder;
/// Keychain item (generic password) holding the key its passwords are encrypted with.
@property (readonly) NSString *keychainService;
/// The app's icon, or a generic one when the app isn't where Launch Services can find it.
@property (readonly) NSImage *icon;
/// Browsers with a data folder on this Mac, in a fixed order (Chrome first).
+ (NSArray<ChromiumBrowser *> *)installed;
@end

/// Passwords read from one browser.
@interface BrowserImport : NSObject
@property (strong) ChromiumBrowser *browser;
@property (copy) NSArray<LoginCandidate *> *logins;
/// Profile names read, e.g. @[@"Personal", @"Work"].
@property (copy) NSArray<NSString *> *profiles;
/// Rows that didn't decrypt (a different key, or a format Brook doesn't know).
@property NSInteger undecryptable;
/// Set when nothing could be read; a sentence for the user.
@property (copy) NSString *failure;
@end

@interface PasswordImporter : NSObject
/// Reads every profile's saved passwords. Blocks (keychain and file prompts from macOS included):
/// call it off the main queue.
+ (BrowserImport *)readBrowser:(ChromiumBrowser *)browser;
/// Decrypts one Chromium "v10" value with a Safe Storage password. nil if it isn't one.
+ (NSString *)decryptChromiumValue:(NSData *)value safeStoragePassword:(NSData *)password;
/// Parses a password CSV from Chrome, Safari, Firefox, Edge, 1Password, Bitwarden and similar.
/// nil and *error if it has no URL and password columns.
+ (NSArray<LoginCandidate *> *)candidatesFromCSV:(NSData *)data error:(NSError **)error;
@end
