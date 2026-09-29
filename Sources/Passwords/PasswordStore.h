#import <AppKit/AppKit.h>

/// Posted on the main queue when saved logins are added, changed or removed, or the vault locks
/// or unlocks.
FOUNDATION_EXPORT NSNotificationName const PasswordStoreDidChangeNotification;

/// One saved sign-in. The password stays sealed until the store opens it.
@interface SavedLogin : NSObject
@property (readonly) NSString *identifier;
/// "https://example.com" or "https://example.com:8443": where the login was saved.
@property (readonly) NSString *origin;
/// Lower-case host of the origin.
@property (readonly) NSString *host;
/// May be "" (a password-only login).
@property (readonly) NSString *username;
@property (readonly) NSDate *created;
/// When the password last changed.
@property (readonly) NSDate *modified;
/// Last autofill, nil if never.
@property (readonly) NSDate *lastUsed;
/// Where it came from: "Brook", "Chrome", "CSV", …
@property (readonly) NSString *source;
@end

/// A login from another browser or a file, not saved yet.
@interface LoginCandidate : NSObject
@property (copy) NSString *url;
@property (copy) NSString *username;
@property (copy) NSString *password;
/// When the other browser last changed it; nil if unknown.
@property (strong) NSDate *modified;
@end

/// What an import did.
@interface PasswordImportResult : NSObject
@property NSInteger added;
/// Same site and username, a newer password replaced the saved one.
@property NSInteger updated;
/// Already saved, identical or older.
@property NSInteger unchanged;
/// No usable web address or password.
@property NSInteger skipped;
@end

/// Brook's saved passwords.
///
/// Stored in ~/Library/Application Support/Brook/passwords.json. Each password is sealed with a
/// Secure Enclave key (ECIES, AES-GCM) that only this Mac can use, and only after Touch ID or the
/// login password. Site names and usernames stay readable so lists and autofill work while locked.
@interface PasswordStore : NSObject
@property (class, readonly) PasswordStore *shared;
/// Sorted by site, then username.
@property (readonly) NSArray<SavedLogin *> *logins;
/// NO on a Mac without a Secure Enclave (some virtual machines): nothing can be saved.
@property (readonly) BOOL isAvailable;
/// Passwords can be opened without asking. Locks again after 5 idle minutes, on sleep and on screen lock.
@property (readonly) BOOL isUnlocked;

/// "https://host[:port]" for an http(s) URL string (a bare host gets https), nil for anything else.
+ (NSString *)originForURLString:(NSString *)string;

/// Logins to offer on a page: this exact origin first, then others on the same site
/// ("accounts.example.com" for "example.com"). Never an https login on an http page.
- (NSArray<SavedLogin *> *)loginsForPageURL:(NSURL *)url;
- (SavedLogin *)loginForOrigin:(NSString *)origin username:(NSString *)username;

/// Asks for Touch ID or the login password (once, then stays unlocked while in use).
- (void)unlockWithReason:(NSString *)reason completion:(void (^)(BOOL unlocked))completion;
- (void)lock;
/// Unlocks if needed, then opens the password. nil if cancelled or unreadable. Main queue.
- (void)openPassword:(SavedLogin *)login reason:(NSString *)reason completion:(void (^)(NSString *password))completion;

/// Adds a login, or replaces the password of the saved one with this origin and username.
/// Sealing needs no unlock. Returns nil and sets error on failure.
- (SavedLogin *)saveOrigin:(NSString *)origin username:(NSString *)username password:(NSString *)password
                    source:(NSString *)source error:(NSError **)error;
/// Changes a login in place. nil password keeps the old one.
- (BOOL)updateLogin:(SavedLogin *)login username:(NSString *)username password:(NSString *)password error:(NSError **)error;
- (void)removeLogins:(NSArray<SavedLogin *> *)logins;
- (void)markUsed:(SavedLogin *)login;

/// Sites where Brook never offers to save.
- (BOOL)neverSavesHost:(NSString *)host;
- (void)setNeverSaves:(BOOL)never host:(NSString *)host;

/// Saves every usable candidate. Same origin and username: the newer password wins, an identical
/// one is left alone. Sealing runs off the main queue; completion runs on it.
- (void)importCandidates:(NSArray<LoginCandidate *> *)candidates source:(NSString *)source
              completion:(void (^)(PasswordImportResult *result))completion;
@end
