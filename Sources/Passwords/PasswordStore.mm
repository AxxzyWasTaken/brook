#import "Brook.h"

NSNotificationName const PasswordStoreDidChangeNotification = @"BrookPasswordStoreDidChange";

/// The Secure Enclave key's reference attribute (kSecAttrTokenOID, missing from the macOS headers).
/// With it a non-permanent key can be stored in our own file and rebuilt at launch.
static NSString *const kTokenOID = @"toid";
static const SecKeyAlgorithm kSealAlgorithm = kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM;
/// Unlocked passwords lock again after this long without one being opened.
static const NSTimeInterval kUnlockIdle = 10 * 60;

static NSError *PasswordError(NSString *message) {
    return [NSError errorWithDomain:@"BrookPasswords" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

// MARK: - Model

@interface SavedLogin ()
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
    BOOL _noPresence;
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
#if DEBUG
    // Scratch test runs: a key that opens without Touch ID, so flows can run unattended.
    _noPresence = NSProcessInfo.processInfo.environment[@"BROOK_PASSWORDS_NO_PRESENCE"] != nil;
#endif
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
    if (![json isKindOfClass:NSDictionary.class]) return;
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
        for (id item in json[@"logins"]) if (SavedLogin *l = [SavedLogin fromJSON:item]) [_logins addObject:l];
    }
    if ([json[@"neverSave"] isKindOfClass:NSArray.class]) {
        for (id h in json[@"neverSave"]) if ([h isKindOfClass:NSString.class]) [_never addObject:h];
    }
}

- (void)saveAndNotify {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:_logins.count];
    for (SavedLogin *l in _logins) [list addObject:l.toJSON];
    NSMutableDictionary *json = [@{@"version": @1, @"logins": list,
                                   @"neverSave": [_never.allObjects sortedArrayUsingSelector:@selector(compare:)]} mutableCopy];
    if (_keyReference && _publicKey) {
        NSData *pub = CFBridgingRelease(SecKeyCopyExternalRepresentation(_publicKey, NULL));
        json[@"key"] = [_keyReference base64EncodedStringWithOptions:0];
        if (pub) json[@"publicKey"] = [pub base64EncodedStringWithOptions:0];
    }
    BrookWriteJSONInBackground(json, NSJSONWritingWithoutEscapingSlashes, _fileURL);
    _sorted = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:PasswordStoreDidChangeNotification object:self];
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
    if (_publicKey) return YES;
    CFErrorRef cfError = NULL;
    SecAccessControlCreateFlags flags = kSecAccessControlPrivateKeyUsage;
    if (!_noPresence) flags |= kSecAccessControlUserPresence;
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
    LAContext *context = [LAContext new];
    context.localizedReason = reason;
    void (^finish)(BOOL) = ^(BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                self->_context = context;
                [self touchUnlock];
                [NSNotificationCenter.defaultCenter postNotificationName:PasswordStoreDidChangeNotification object:self];
            }
            NSArray *waiters = self->_unlockWaiters;
            self->_unlockWaiters = [NSMutableArray array];
            for (void (^w)(BOOL) in waiters) w(ok);
        });
    };
    if (_noPresence) { finish(YES); return; }
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
            dispatch_async(dispatch_get_main_queue(), ^{ completion(password); });
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
    NSNumber *port = c.port;
    BOOL defaultPort = !port || ([scheme isEqualToString:@"https"] && port.integerValue == 443) ||
                       ([scheme isEqualToString:@"http"] && port.integerValue == 80);
    return defaultPort ? [NSString stringWithFormat:@"%@://%@", scheme, host]
                       : [NSString stringWithFormat:@"%@://%@:%@", scheme, host, port];
}

/// One host is the other, or one is a subdomain of the other (never two siblings, so a login saved
/// for one site on a shared domain like github.io is not offered on another).
static BOOL SameSite(NSString *a, NSString *b) {
    if ([a isEqualToString:b]) return YES;
    NSString *shorter = a.length < b.length ? a : b, *longer = a.length < b.length ? b : a;
    if ([shorter componentsSeparatedByString:@"."].count < 2) return NO;
    return [longer hasSuffix:[@"." stringByAppendingString:shorter]];
}

- (NSArray<SavedLogin *> *)loginsForPageURL:(NSURL *)url {
    NSString *origin = [PasswordStore originForURLString:url.absoluteString];
    NSString *host = BrookHost(url).lowercaseString;
    if (!origin || !host) return @[];
    BOOL pageSecure = [origin hasPrefix:@"https:"];
    NSString *site = [SiteSettings keyForHost:host];
    NSMutableArray<SavedLogin *> *exact = [NSMutableArray array], *related = [NSMutableArray array];
    for (SavedLogin *l in self.logins) {
        if (!pageSecure && [l.origin hasPrefix:@"https:"]) continue;
        if ([l.origin isEqualToString:origin]) [exact addObject:l];
        else if (SameSite([SiteSettings keyForHost:l.host], site)) [related addObject:l];
    }
    NSComparator recent = ^NSComparisonResult(SavedLogin *a, SavedLogin *b) {
        NSDate *da = a.lastUsed ?: a.modified, *db = b.lastUsed ?: b.modified;
        return [db compare:da];
    };
    [exact sortUsingComparator:recent];
    [related sortUsingComparator:recent];
    return [exact arrayByAddingObjectsFromArray:related];
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
    SavedLogin *l = [self loginForOrigin:o username:user];
    NSDate *now = [NSDate date];
    if (!l) {
        l = [SavedLogin new];
        l.identifier = NSUUID.UUID.UUIDString;
        l.origin = o;
        l.host = BrookHost([NSURL URLWithString:o]).lowercaseString;
        l.username = user;
        l.created = now;
        l.source = source ?: @"Brook";
        [_logins addObject:l];
    }
    l.sealed = sealed;
    l.modified = now;
    [self saveAndNotify];
    return l;
}

- (BOOL)updateLogin:(SavedLogin *)login username:(NSString *)username password:(NSString *)password error:(NSError **)error {
    if (![_logins containsObject:login]) return NO;
    NSString *user = BrookTrimAll(username ?: @"");
    SavedLogin *clash = [self loginForOrigin:login.origin username:user];
    if (clash && clash != login) {
        if (error) *error = PasswordError([NSString stringWithFormat:@"%@ already has a saved login for “%@”.", login.host, user]);
        return NO;
    }
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
        login.sealed = sealed;
        login.modified = [NSDate date];
    }
    login.username = user;
    [self saveAndNotify];
    return YES;
}

- (void)removeLogins:(NSArray<SavedLogin *> *)logins {
    if (logins.count == 0) return;
    [_logins removeObjectsInArray:logins];
    [self saveAndNotify];
}

- (void)markUsed:(SavedLogin *)login {
    if (![_logins containsObject:login]) return;
    login.lastUsed = [NSDate date];
    [self saveAndNotify];
}

- (BOOL)neverSavesHost:(NSString *)host {
    return host && [_never containsObject:[SiteSettings keyForHost:host]];
}

- (void)setNeverSaves:(BOOL)never host:(NSString *)host {
    if (!host) return;
    NSString *key = [SiteSettings keyForHost:host];
    if (never) [_never addObject:key]; else [_never removeObject:key];
    [self saveAndNotify];
}

// MARK: Import

- (void)importCandidates:(NSArray<LoginCandidate *> *)candidates source:(NSString *)source
              completion:(void (^)(PasswordImportResult *))completion {
    PasswordImportResult *result = [PasswordImportResult new];
    // Usable candidates, one per origin and username (the most recently changed wins).
    NSMutableDictionary<NSString *, LoginCandidate *> *unique = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (LoginCandidate *c in candidates) {
        NSString *origin = [PasswordStore originForURLString:c.url];
        if (!origin || c.password.length == 0) { result.skipped++; continue; }
        c.url = origin;
        c.username = BrookTrimAll(c.username ?: @"");
        NSString *key = [NSString stringWithFormat:@"%@\n%@", origin, c.username];
        LoginCandidate *old = unique[key];
        if (!old) [order addObject:key];
        else result.unchanged++;
        if (!old || [c.modified ?: NSDate.distantPast compare:old.modified ?: NSDate.distantPast] != NSOrderedAscending) unique[key] = c;
    }
    NSError *error = nil;
    if (unique.count == 0 || ![self ensureKey:&error]) {
        result.skipped += (NSInteger)unique.count;
        completion(result);
        return;
    }
    // Already-saved logins need their password compared: that takes one unlock, and only then.
    NSMutableDictionary<NSString *, SavedLogin *> *existing = [NSMutableDictionary dictionary];
    for (NSString *key in order) {
        LoginCandidate *c = unique[key];
        if (SavedLogin *l = [self loginForOrigin:c.url username:c.username]) existing[key] = l;
    }
    void (^run)(BOOL) = ^(BOOL unlocked) {
        LAContext *context = unlocked ? self->_context : nil;
        NSData *reference = self->_keyReference;
        SecKeyRef pub = (SecKeyRef)CFRetain(self->_publicKey);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            // Work out every change off the main queue: sealing and opening take a few ms each.
            NSMutableDictionary<NSString *, NSData *> *sealedByKey = [NSMutableDictionary dictionary];
            for (NSString *key in order) {
                LoginCandidate *c = unique[key];
                SavedLogin *saved = existing[key];
                if (saved) {
                    NSString *current = context ? Open(saved.sealed, reference, context) : nil;
                    BOOL same = current && [current isEqualToString:c.password];
                    // Without the saved password to compare, only a known-newer one replaces it.
                    BOOL newer = c.modified && [c.modified compare:saved.modified] == NSOrderedDescending;
                    if (same || (!current && !newer) || (current && c.modified && !newer)) continue;
                }
                NSData *plain = [c.password dataUsingEncoding:NSUTF8StringEncoding];
                NSData *sealed = plain ? CFBridgingRelease(SecKeyCreateEncryptedData(pub, kSealAlgorithm, (__bridge CFDataRef)plain, NULL)) : nil;
                if (sealed) sealedByKey[key] = sealed;
            }
            CFRelease(pub);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSDate *now = [NSDate date];
                for (NSString *key in order) {
                    LoginCandidate *c = unique[key];
                    NSData *sealed = sealedByKey[key];
                    SavedLogin *saved = [self loginForOrigin:c.url username:c.username];
                    if (!sealed) {
                        if (saved) result.unchanged++; else result.skipped++;
                        continue;
                    }
                    if (saved) {
                        saved.sealed = sealed;
                        saved.modified = c.modified ?: now;
                        result.updated++;
                    } else {
                        SavedLogin *l = [SavedLogin new];
                        l.identifier = NSUUID.UUID.UUIDString;
                        l.origin = c.url;
                        l.host = BrookHost([NSURL URLWithString:c.url]).lowercaseString;
                        l.username = c.username;
                        l.sealed = sealed;
                        l.created = now;
                        l.modified = c.modified ?: now;
                        l.source = source ?: @"Import";
                        [self->_logins addObject:l];
                        result.added++;
                    }
                }
                if (result.added || result.updated) [self saveAndNotify];
                completion(result);
            });
        });
    };
    if (existing.count == 0) {
        run(NO);
    } else {
        [self unlockWithReason:@"compare the imported passwords with the ones you’ve saved" completion:run];
    }
}

@end
