#import "Brook.h"

NSNotificationName const PasswordStoreDidChangeNotification = @"BrookPasswordStoreDidChange";

/// The Secure Enclave key's reference attribute (kSecAttrTokenOID, missing from the macOS headers).
/// With it a non-permanent key can be stored in our own file and rebuilt at launch.
static NSString *const kTokenOID = @"toid";
static const SecKeyAlgorithm kSealAlgorithm = kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM;
/// Unlocked passwords lock again after this long without one being opened.
static const NSTimeInterval kUnlockIdle = 5 * 60;

static NSError *PasswordError(NSString *message) {
    return [NSError errorWithDomain:@"BrookPasswords" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

// MARK: - Model

@interface SavedLogin () <NSCopying>
@property (readwrite) NSString *identifier;
@property (readwrite) NSString *origin;
@property (readwrite) NSString *host;
@property (readwrite) NSString *username;
@property (readwrite) NSDate *created;
@property (readwrite) NSDate *modified;
@property (readwrite) NSDate *lastUsed;
@property (readwrite) NSString *source;
/// ECIES ciphertext of the UTF-8 password.
@property (copy) NSData *sealed;
@end

@implementation SavedLogin

+ (instancetype)loginWithOrigin:(NSString *)origin username:(NSString *)username source:(NSString *)source {
    SavedLogin *login = [SavedLogin new];
    login.identifier = NSUUID.UUID.UUIDString;
    login.origin = origin;
    login.host = BrookHost([NSURL URLWithString:origin]).lowercaseString;
    login.username = username;
    login.created = login.modified = [NSDate date];
    login.source = source;
    return login;
}

- (id)copyWithZone:(NSZone *)zone {
    SavedLogin *copy = [[SavedLogin allocWithZone:zone] init];
    copy.identifier = _identifier;
    copy.origin = _origin;
    copy.host = _host;
    copy.username = _username;
    copy.created = _created;
    copy.modified = _modified;
    copy.lastUsed = _lastUsed;
    copy.source = _source;
    copy.sealed = _sealed;
    return copy;
}

static NSDate *DateFrom(id v) {
    return [v isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSinceReferenceDate:[v doubleValue]] : nil;
}

+ (instancetype)fromJSON:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    id identifier = d[@"id"], origin = d[@"origin"], username = d[@"username"], sealed = d[@"sealed"];
    if (![identifier isKindOfClass:NSString.class] || ![origin isKindOfClass:NSString.class] ||
        ![username isKindOfClass:NSString.class] || ![sealed isKindOfClass:NSString.class]) return nil;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:sealed options:0];
    NSString *host = BrookHost([NSURL URLWithString:origin]).lowercaseString;
    if (!data || !host) return nil;
    SavedLogin *l = [SavedLogin new];
    l.identifier = identifier;
    l.origin = origin;
    l.host = host;
    l.username = username;
    l.sealed = data;
    l.created = DateFrom(d[@"created"]) ?: [NSDate date];
    l.modified = DateFrom(d[@"modified"]) ?: l.created;
    l.lastUsed = DateFrom(d[@"lastUsed"]);
    l.source = [d[@"source"] isKindOfClass:NSString.class] ? d[@"source"] : @"Brook";
    return l;
}

- (NSDictionary *)toJSON {
    NSMutableDictionary *d = [@{@"id": _identifier, @"origin": _origin, @"username": _username,
                                @"sealed": [_sealed base64EncodedStringWithOptions:0],
                                @"created": @(_created.timeIntervalSinceReferenceDate),
                                @"modified": @(_modified.timeIntervalSinceReferenceDate),
                                @"source": _source ?: @"Brook"} mutableCopy];
    if (_lastUsed) d[@"lastUsed"] = @(_lastUsed.timeIntervalSinceReferenceDate);
    return d;
}

@end

@implementation LoginCandidate
@end

@implementation PasswordImportResult
@end

typedef NS_ENUM(NSInteger, ImportDecision) { ImportAdd, ImportReplace, ImportUnchanged, ImportConflict };

static ImportDecision ResolvePassword(NSString *incoming, NSDate *modified, NSString *current, NSDate *currentModified) {
    if (current && [incoming isEqualToString:current]) return ImportUnchanged;
    if (!modified || !currentModified) return ImportConflict;
    NSComparisonResult order = [modified compare:currentModified];
    if (order == NSOrderedDescending) return ImportReplace;
    return current && order == NSOrderedAscending ? ImportUnchanged : ImportConflict;
}

@interface PasswordImportEntry : NSObject
@property (strong) LoginCandidate *candidate;
@property (copy) SavedLogin *saved;
@property ImportDecision decision;
@property (copy) NSData *sealed;
@end
@implementation PasswordImportEntry
@end

static NSArray<PasswordImportEntry *> *ImportEntries(NSArray<LoginCandidate *> *candidates, PasswordImportResult *result) {
    NSMutableDictionary<NSString *, PasswordImportEntry *> *unique = [NSMutableDictionary dictionary];
    NSMutableArray<PasswordImportEntry *> *entries = [NSMutableArray array];
    for (LoginCandidate *input in candidates) {
        NSString *origin = [PasswordStore originForURLString:input.url];
        if (!origin || input.password.length == 0) { result.skipped++; continue; }
        LoginCandidate *candidate = [LoginCandidate new];
        candidate.url = origin;
        candidate.username = BrookTrimAll(input.username ?: @"");
        candidate.password = input.password;
        candidate.modified = input.modified;
        NSString *key = [NSString stringWithFormat:@"%@\n%@", origin, candidate.username];
        PasswordImportEntry *entry = unique[key];
        if (!entry) {
            entry = [PasswordImportEntry new];
            entry.candidate = candidate;
            unique[key] = entry;
            [entries addObject:entry];
            continue;
        }
        LoginCandidate *old = entry.candidate;
        if (ResolvePassword(candidate.password, candidate.modified, old.password, old.modified) == ImportConflict) {
            result.skipped++;
            continue;
        }
        result.duplicates++;
        if ([candidate.modified ?: NSDate.distantPast compare:old.modified ?: NSDate.distantPast] == NSOrderedDescending)
            entry.candidate = candidate;
    }
    return entries;
}

// MARK: - Store

@implementation PasswordStore {
    NSURL *_fileURL;
    NSMutableArray<SavedLogin *> *_logins;
    NSArray<SavedLogin *> *_sorted;
    NSMutableSet<NSString *> *_never;
    /// The Secure Enclave key's reference and public key, both nil until the first save.
    NSData *_keyReference;
    SecKeyRef _publicKey;
    /// Evaluated context while unlocked.
    LAContext *_context;
    NSTimer *_lockTimer;
    /// Unlock requests waiting on one prompt.
    NSMutableArray<void (^)(BOOL)> *_unlockWaiters;
    NSError *_loadError;
    NSUInteger _unlockGeneration;
}

+ (PasswordStore *)shared {
    static PasswordStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [PasswordStore new]; });
    return s;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _fileURL = [AppPaths.support URLByAppendingPathComponent:@"passwords.json"];
    _logins = [NSMutableArray array];
    _never = [NSMutableSet set];
    _unlockWaiters = [NSMutableArray array];
    [self load];
    NSNotificationCenter *ws = NSWorkspace.sharedWorkspace.notificationCenter;
    [ws addObserver:self selector:@selector(lock) name:NSWorkspaceWillSleepNotification object:nil];
    [ws addObserver:self selector:@selector(lock) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [NSDistributedNotificationCenter.defaultCenter addObserver:self selector:@selector(lock)
                                                          name:@"com.apple.screenIsLocked" object:nil];
    return self;
}

- (void)dealloc {
    if (_publicKey) CFRelease(_publicKey);
}

- (void)load {
    NSData *data = [NSData dataWithContentsOfURL:_fileURL];
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class] || ![json[@"logins"] isKindOfClass:NSArray.class] ||
        ![json[@"version"] isEqual:@1]) {
        if ([NSFileManager.defaultManager fileExistsAtPath:_fileURL.path])
            _loadError = PasswordError(@"The password vault couldn’t be read. Keep passwords.json and restore a valid copy before saving passwords.");
        return;
    }
    if ([json[@"key"] isKindOfClass:NSString.class] && [json[@"publicKey"] isKindOfClass:NSString.class]) {
        NSData *reference = [[NSData alloc] initWithBase64EncodedString:json[@"key"] options:0];
        NSData *pub = [[NSData alloc] initWithBase64EncodedString:json[@"publicKey"] options:0];
        SecKeyRef key = pub ? SecKeyCreateWithData((__bridge CFDataRef)pub, (__bridge CFDictionaryRef)@{
            (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom, (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPublic}, NULL) : NULL;
        if (reference && key) {
            _keyReference = reference;
            _publicKey = key;
        } else if (key) {
            CFRelease(key);
        }
    }
    if ([json[@"logins"] isKindOfClass:NSArray.class]) {
        for (id item in json[@"logins"]) {
            SavedLogin *l = [SavedLogin fromJSON:item];
            if (l) [_logins addObject:l];
            else _loadError = PasswordError(@"The password vault contains an unreadable login. Restore a valid copy before saving passwords.");
        }
        if (_logins.count && !_publicKey) _loadError = PasswordError(@"The password vault’s encryption key is missing. Restore a valid copy before saving passwords.");
    }
    if ([json[@"neverSave"] isKindOfClass:NSArray.class]) {
        for (id h in json[@"neverSave"]) if ([h isKindOfClass:NSString.class]) [_never addObject:h];
    }
}

- (BOOL)commitLogins:(NSArray<SavedLogin *> *)logins neverSave:(NSSet<NSString *> *)never error:(NSError **)error {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:logins.count];
    for (SavedLogin *l in logins) [list addObject:l.toJSON];
    NSMutableDictionary *json = [@{@"version": @1, @"logins": list,
                                   @"neverSave": [never.allObjects sortedArrayUsingSelector:@selector(compare:)]} mutableCopy];
    if (_keyReference && _publicKey) {
        NSData *pub = CFBridgingRelease(SecKeyCopyExternalRepresentation(_publicKey, NULL));
        json[@"key"] = [_keyReference base64EncodedStringWithOptions:0];
        if (pub) json[@"publicKey"] = [pub base64EncodedStringWithOptions:0];
    }
    NSError *failure = _loadError;
    NSData *data = !failure ? [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingWithoutEscapingSlashes error:&failure] : nil;
    BOOL ok = data && [data writeToURL:_fileURL options:NSDataWritingAtomic error:&failure];
    if (!ok) {
        if (error) *error = failure ?: PasswordError(@"The password vault couldn’t be saved. Keep the source file and try again.");
        return NO;
    }
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:_fileURL.path error:nil];
    NSMutableDictionary<NSString *, SavedLogin *> *current = [NSMutableDictionary dictionaryWithCapacity:_logins.count];
    for (SavedLogin *login in _logins) current[login.identifier] = login;
    NSMutableArray *committed = [NSMutableArray arrayWithCapacity:logins.count];
    for (SavedLogin *proposed in logins) {
        SavedLogin *login = current[proposed.identifier] ?: proposed;
        if (login != proposed) {
            login.username = proposed.username;
            login.sealed = proposed.sealed;
            login.modified = proposed.modified;
            login.lastUsed = proposed.lastUsed;
        }
        [committed addObject:login];
    }
    _logins = committed;
    _never = [never mutableCopy];
    _sorted = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:PasswordStoreDidChangeNotification object:self];
    return YES;
}

- (BOOL)commitLogin:(SavedLogin *)proposed replacing:(SavedLogin *)login error:(NSError **)error {
    NSMutableArray *logins = [_logins mutableCopy];
    if (login) logins[[_logins indexOfObjectIdenticalTo:login]] = proposed;
    else [logins addObject:proposed];
    return [self commitLogins:logins neverSave:_never error:error];
}

- (NSArray<SavedLogin *> *)logins {
    if (!_sorted) {
        _sorted = [_logins sortedArrayUsingComparator:^NSComparisonResult(SavedLogin *a, SavedLogin *b) {
            NSString *ha = [SiteSettings keyForHost:a.host], *hb = [SiteSettings keyForHost:b.host];
            NSComparisonResult r = [ha localizedStandardCompare:hb];
            return r != NSOrderedSame ? r : [a.username localizedStandardCompare:b.username];
        }];
    }
    return _sorted;
}

// MARK: Key

/// Creates the Secure Enclave key on first use. NO when this Mac has none.
- (BOOL)ensureKey:(NSError **)error {
    if (_loadError) { if (error) *error = _loadError; return NO; }
    if (_publicKey) return YES;
    CFErrorRef cfError = NULL;
    SecAccessControlCreateFlags flags = kSecAccessControlPrivateKeyUsage | kSecAccessControlUserPresence;
    SecAccessControlRef access = SecAccessControlCreateWithFlags(NULL, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &cfError);
    if (!access) {
        if (error) *error = CFBridgingRelease(cfError);
        return NO;
    }
    NSDictionary *attributes = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrKeySizeInBits: @256,
        (id)kSecAttrTokenID: (id)kSecAttrTokenIDSecureEnclave,
        (id)kSecPrivateKeyAttrs: @{(id)kSecAttrIsPermanent: @NO, (id)kSecAttrAccessControl: (__bridge id)access},
    };
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfError);
    CFRelease(access);
    NSDictionary *info = key ? CFBridgingRelease(SecKeyCopyAttributes(key)) : nil;
    NSData *reference = [info[kTokenOID] isKindOfClass:NSData.class] ? info[kTokenOID] : nil;
    SecKeyRef pub = key ? SecKeyCopyPublicKey(key) : NULL;
    if (key) CFRelease(key);
    if (!reference || !pub) {
        if (pub) CFRelease(pub);
        if (error) *error = cfError ? CFBridgingRelease(cfError) : PasswordError(@"This Mac can’t create a secure key for passwords.");
        return NO;
    }
    _keyReference = reference;
    _publicKey = pub;
    return YES;
}

- (BOOL)isAvailable {
    if (_publicKey) return YES;
    static BOOL checked, available;
    if (!checked) {
        checked = YES;
        available = [LAContext new] != nil && [self secureEnclavePresent];
    }
    return available;
}

/// A throwaway Secure Enclave key: the only reliable test for one.
- (BOOL)secureEnclavePresent {
    NSDictionary *attributes = @{(id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom, (id)kSecAttrKeySizeInBits: @256,
                                 (id)kSecAttrTokenID: (id)kSecAttrTokenIDSecureEnclave,
                                 (id)kSecPrivateKeyAttrs: @{(id)kSecAttrIsPermanent: @NO}};
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, NULL);
    if (key) CFRelease(key);
    return key != NULL;
}

- (NSData *)seal:(NSString *)password {
    NSData *plain = [password dataUsingEncoding:NSUTF8StringEncoding];
    if (!_publicKey || !plain) return nil;
    return CFBridgingRelease(SecKeyCreateEncryptedData(_publicKey, kSealAlgorithm, (__bridge CFDataRef)plain, NULL));
}

/// Needs an evaluated context (unlocked). Safe off the main queue.
static NSString *Open(NSData *sealed, NSData *reference, LAContext *context) {
    if (!sealed || !reference) return nil;
    NSMutableDictionary *attributes = [@{(id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
                                         (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPrivate,
                                         (id)kSecAttrTokenID: (id)kSecAttrTokenIDSecureEnclave,
                                         kTokenOID: reference} mutableCopy];
    if (context) attributes[(id)kSecUseAuthenticationContext] = context;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)NSData.data, (__bridge CFDictionaryRef)attributes, NULL);
    if (!key) return nil;
    NSData *plain = CFBridgingRelease(SecKeyCreateDecryptedData(key, kSealAlgorithm, (__bridge CFDataRef)sealed, NULL));
    CFRelease(key);
    return plain ? [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding] : nil;
}

// MARK: Lock

- (BOOL)isUnlocked { return _context != nil; }

- (void)unlockWithReason:(NSString *)reason completion:(void (^)(BOOL))completion {
    if (_context) {
        [self touchUnlock];
        completion(YES);
        return;
    }
    [_unlockWaiters addObject:[completion copy]];
    if (_unlockWaiters.count > 1) return;   // a prompt is already up
    NSUInteger generation = _unlockGeneration;
    LAContext *context = [LAContext new];
    context.localizedReason = reason;
    void (^finish)(BOOL) = ^(BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL accepted = ok && generation == self->_unlockGeneration;
            if (accepted) {
                self->_context = context;
                [self touchUnlock];
                [NSNotificationCenter.defaultCenter postNotificationName:PasswordStoreDidChangeNotification object:self];
            }
            NSArray *waiters = self->_unlockWaiters;
            self->_unlockWaiters = [NSMutableArray array];
            for (void (^w)(BOOL) in waiters) w(accepted);
        });
    };
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication localizedReason:reason
                      reply:^(BOOL success, NSError *) { finish(success); }];
}

/// Restarts the idle timer.
- (void)touchUnlock {
    [_lockTimer invalidate];
    __weak PasswordStore *weakSelf = self;
    _lockTimer = [NSTimer scheduledTimerWithTimeInterval:kUnlockIdle repeats:NO block:^(NSTimer *) { [weakSelf lock]; }];
}

- (void)lock {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self lock]; });
        return;
    }
    _unlockGeneration++;
    [_lockTimer invalidate];
    _lockTimer = nil;
    if (!_context) return;
    [_context invalidate];
    _context = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:PasswordStoreDidChangeNotification object:self];
}

- (void)openPassword:(SavedLogin *)login reason:(NSString *)reason completion:(void (^)(NSString *))completion {
    NSData *sealed = login.sealed, *reference = _keyReference;
    [self unlockWithReason:reason completion:^(BOOL ok) {
        if (!ok) { completion(nil); return; }
        LAContext *context = self->_context;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *password = Open(sealed, reference, context);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(self->_context == context && [self->_logins containsObject:login] &&
                           [login.sealed isEqualToData:sealed] ? password : nil);
            });
        });
    }];
}

// MARK: Lookup

+ (NSString *)originForURLString:(NSString *)string {
    NSString *s = BrookTrimAll(string ?: @"");
    if (s.length == 0) return nil;
    if (![s containsString:@"://"]) s = [@"https://" stringByAppendingString:s];
    NSURLComponents *c = [NSURLComponents componentsWithString:s];
    NSString *scheme = c.scheme.lowercaseString, *host = c.percentEncodedHost.lowercaseString;
    if (!([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) || host.length == 0) return nil;
    if (![host containsString:@"."] && ![host isEqualToString:@"localhost"]) return nil;
    if (c.user.length || c.password.length || [host hasSuffix:@"."]) return nil;
    NSNumber *port = c.port;
    if (port && (port.integerValue <= 0 || port.integerValue > 65535)) return nil;
    BOOL defaultPort = !port || ([scheme isEqualToString:@"https"] && port.integerValue == 443) ||
                       ([scheme isEqualToString:@"http"] && port.integerValue == 80);
    return defaultPort ? [NSString stringWithFormat:@"%@://%@", scheme, host]
                       : [NSString stringWithFormat:@"%@://%@:%@", scheme, host, port];
}

- (NSArray<SavedLogin *> *)loginsForPageURL:(NSURL *)url {
    NSString *origin = [PasswordStore originForURLString:url.absoluteString];
    if (!origin) return @[];
    NSMutableArray<SavedLogin *> *matches = [NSMutableArray array];
    for (SavedLogin *login in self.logins) if ([login.origin isEqualToString:origin]) [matches addObject:login];
    [matches sortUsingComparator:^NSComparisonResult(SavedLogin *a, SavedLogin *b) {
        return [b.lastUsed ?: b.modified compare:a.lastUsed ?: a.modified];
    }];
    return matches;
}

- (SavedLogin *)loginForOrigin:(NSString *)origin username:(NSString *)username {
    for (SavedLogin *l in _logins) {
        if ([l.origin isEqualToString:origin] && [l.username isEqualToString:username ?: @""]) return l;
    }
    return nil;
}

// MARK: Changes

- (SavedLogin *)saveOrigin:(NSString *)origin username:(NSString *)username password:(NSString *)password
                    source:(NSString *)source error:(NSError **)error {
    NSString *o = [PasswordStore originForURLString:origin];
    if (!o) {
        if (error) *error = PasswordError(@"That isn’t a website address.");
        return nil;
    }
    if (password.length == 0) {
        if (error) *error = PasswordError(@"The password is empty.");
        return nil;
    }
    if (![self ensureKey:error]) return nil;
    NSData *sealed = [self seal:password];
    if (!sealed) {
        if (error) *error = PasswordError(@"The password couldn’t be encrypted.");
        return nil;
    }
    NSString *user = BrookTrimAll(username ?: @"");
    SavedLogin *login = [self loginForOrigin:o username:user];
    SavedLogin *proposed = [login copy] ?: [SavedLogin loginWithOrigin:o username:user source:source ?: @"Brook"];
    proposed.sealed = sealed;
    proposed.modified = [NSDate date];
    return [self commitLogin:proposed replacing:login error:error] ? (login ?: proposed) : nil;
}

- (BOOL)updateLogin:(SavedLogin *)login username:(NSString *)username password:(NSString *)password error:(NSError **)error {
    if (![_logins containsObject:login]) {
        if (error) *error = PasswordError(@"This login no longer exists. Select a saved login and try again.");
        return NO;
    }
    NSString *user = BrookTrimAll(username ?: @"");
    SavedLogin *clash = [self loginForOrigin:login.origin username:user];
    if (clash && clash != login) {
        if (error) *error = PasswordError([NSString stringWithFormat:@"%@ already has a saved login for “%@”.", login.host, user]);
        return NO;
    }
    SavedLogin *proposed = [login copy];
    if (password) {
        if (password.length == 0) {
            if (error) *error = PasswordError(@"The password is empty.");
            return NO;
        }
        NSData *sealed = [self seal:password];
        if (!sealed) {
            if (error) *error = PasswordError(@"The password couldn’t be encrypted.");
            return NO;
        }
        proposed.sealed = sealed;
        proposed.modified = [NSDate date];
    }
    proposed.username = user;
    return [self commitLogin:proposed replacing:login error:error];
}

- (BOOL)removeLogins:(NSArray<SavedLogin *> *)logins error:(NSError **)error {
    if (logins.count == 0) return YES;
    NSMutableArray *proposed = [_logins mutableCopy];
    [proposed removeObjectsInArray:logins];
    return [self commitLogins:proposed neverSave:_never error:error];
}

- (void)markUsed:(SavedLogin *)login {
    if (![_logins containsObject:login]) return;
    SavedLogin *proposed = [login copy];
    proposed.lastUsed = [NSDate date];
    [self commitLogin:proposed replacing:login error:nil];
}

- (BOOL)neverSavesHost:(NSString *)host {
    return host && [_never containsObject:[SiteSettings keyForHost:host]];
}

- (void)setNeverSaves:(BOOL)never host:(NSString *)host {
    if (!host) return;
    NSString *key = [SiteSettings keyForHost:host];
    NSMutableSet *proposed = [_never mutableCopy];
    if (never) [proposed addObject:key]; else [proposed removeObject:key];
    [self commitLogins:_logins neverSave:proposed error:nil];
}

// MARK: Import

- (void)applyImportEntries:(NSArray<PasswordImportEntry *> *)entries source:(NSString *)source result:(PasswordImportResult *)result {
    NSMutableArray *proposed = [_logins mutableCopy];
    for (PasswordImportEntry *entry in entries) {
        LoginCandidate *candidate = entry.candidate;
        SavedLogin *current = [self loginForOrigin:candidate.url username:candidate.username];
        SavedLogin *snapshot = entry.saved;
        BOOL unchanged = !current && !snapshot;
        if (current && snapshot) unchanged = [current.identifier isEqualToString:snapshot.identifier] &&
            [current.sealed isEqualToData:snapshot.sealed] && [current.modified isEqualToDate:snapshot.modified];
        if (!unchanged || entry.decision == ImportConflict) { result.skipped++; continue; }
        if (entry.decision == ImportUnchanged) { result.unchanged++; continue; }
        SavedLogin *login = [current copy] ?: [SavedLogin loginWithOrigin:candidate.url username:candidate.username source:source ?: @"Import"];
        login.sealed = entry.sealed;
        login.modified = candidate.modified ?: login.created;
        if (entry.decision == ImportReplace) {
            proposed[[_logins indexOfObjectIdenticalTo:current]] = login;
            result.updated++;
        } else {
            [proposed addObject:login];
            result.added++;
        }
    }
    if (result.added || result.updated) {
        NSError *error = nil;
        if (![self commitLogins:proposed neverSave:_never error:&error]) {
            result.skipped += result.added + result.updated;
            result.added = result.updated = 0;
            result.error = error;
        }
    }
}

- (void)importCandidates:(NSArray<LoginCandidate *> *)candidates source:(NSString *)source
              completion:(void (^)(PasswordImportResult *))completion {
    PasswordImportResult *result = [PasswordImportResult new];
    NSArray<PasswordImportEntry *> *entries = ImportEntries(candidates, result);
    void (^finish)(NSError *) = ^(NSError *error) {
        if (error) result.error = error;
        for (LoginCandidate *candidate in candidates) candidate.password = nil;
        for (PasswordImportEntry *entry in entries) entry.candidate.password = nil;
        completion(result);
    };
    NSError *error = nil;
    if (entries.count == 0 || ![self ensureKey:&error]) {
        result.skipped += (NSInteger)entries.count;
        finish(error);
        return;
    }
    BOOL needsUnlock = NO;
    for (PasswordImportEntry *entry in entries) {
        entry.saved = [self loginForOrigin:entry.candidate.url username:entry.candidate.username];
        needsUnlock |= entry.saved != nil;
    }
    void (^run)(BOOL) = ^(BOOL unlocked) {
        if (needsUnlock && (!unlocked || !self->_context)) {
            finish(PasswordError(@"Import cancelled. Your saved passwords haven’t changed."));
            return;
        }
        LAContext *context = unlocked ? self->_context : nil;
        NSData *reference = self->_keyReference;
        SecKeyRef pub = (SecKeyRef)CFRetain(self->_publicKey);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            for (PasswordImportEntry *entry in entries) {
                LoginCandidate *candidate = entry.candidate;
                SavedLogin *saved = entry.saved;
                entry.decision = saved ? ResolvePassword(candidate.password, candidate.modified,
                    Open(saved.sealed, reference, context), saved.modified) : ImportAdd;
                if (entry.decision != ImportAdd && entry.decision != ImportReplace) continue;
                NSData *plain = [candidate.password dataUsingEncoding:NSUTF8StringEncoding];
                entry.sealed = plain ? CFBridgingRelease(SecKeyCreateEncryptedData(pub, kSealAlgorithm, (__bridge CFDataRef)plain, NULL)) : nil;
                if (!entry.sealed) entry.decision = ImportConflict;
            }
            CFRelease(pub);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (needsUnlock && self->_context != context) {
                    finish(PasswordError(@"The password vault locked during import. Keep the source file and try again."));
                    return;
                }
                [self applyImportEntries:entries source:source result:result];
                finish(nil);
            });
        });
    };
    if (needsUnlock) [self unlockWithReason:@"compare the imported passwords with the ones you’ve saved" completion:run];
    else run(NO);
}

@end
