#import "Brook.h"

static NSError *ImportError(NSString *message) {
    return [NSError errorWithDomain:@"BrookPasswordImport" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

// MARK: - Browsers

@interface ChromiumBrowser ()
@property (readwrite) NSString *name;
@property (readwrite) NSString *bundleID;
@property (readwrite) NSURL *dataFolder;
@property (readwrite) NSString *keychainService;
@end

@implementation ChromiumBrowser

+ (NSArray<ChromiumBrowser *> *)known {
    // name, bundle ID, folder under Application Support, keychain service.
    static NSArray<NSArray<NSString *> *> *const table = @[
        @[@"Google Chrome", @"com.google.Chrome", @"Google/Chrome", @"Chrome Safe Storage"],
        @[@"Arc", @"company.thebrowser.Browser", @"Arc/User Data", @"Arc Safe Storage"],
        @[@"Brave", @"com.brave.Browser", @"BraveSoftware/Brave-Browser", @"Brave Safe Storage"],
        @[@"Microsoft Edge", @"com.microsoft.edgemac", @"Microsoft Edge", @"Microsoft Edge Safe Storage"],
        @[@"Vivaldi", @"com.vivaldi.Vivaldi", @"Vivaldi", @"Vivaldi Safe Storage"],
        @[@"Dia", @"company.thebrowser.dia", @"Dia/User Data", @"Dia Safe Storage"],
        @[@"Helium", @"net.imput.helium", @"net.imput.helium", @"Helium Storage Key"],
        @[@"Opera", @"com.operasoftware.Opera", @"com.operasoftware.Opera", @"Opera Safe Storage"],
        @[@"Comet", @"ai.perplexity.comet", @"Comet", @"Comet Safe Storage"],
        @[@"Chromium", @"org.chromium.Chromium", @"Chromium", @"Chromium Safe Storage"],
        @[@"Chrome Beta", @"com.google.Chrome.beta", @"Google/Chrome Beta", @"Chrome Safe Storage"],
        @[@"Chrome Dev", @"com.google.Chrome.dev", @"Google/Chrome Dev", @"Chrome Safe Storage"],
        @[@"Chrome Canary", @"com.google.Chrome.canary", @"Google/Chrome Canary", @"Chrome Safe Storage"],
    ];
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSMutableArray *all = [NSMutableArray array];
    for (NSArray<NSString *> *row in table) {
        ChromiumBrowser *b = [ChromiumBrowser new];
        b.name = row[0];
        b.bundleID = row[1];
        b.dataFolder = [support URLByAppendingPathComponent:row[2] isDirectory:YES];
        b.keychainService = row[3];
        [all addObject:b];
    }
    return all;
}

+ (NSArray<ChromiumBrowser *> *)installed {
    NSMutableArray *found = [NSMutableArray array];
    for (ChromiumBrowser *b in self.known) {
        // Only the folder itself is looked at: reading inside Chrome's and Edge's is protected,
        // and would ask the user for permission before they chose to import.
        BOOL dir = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:b.dataFolder.path isDirectory:&dir] && dir) [found addObject:b];
    }
    return found;
}

- (NSImage *)icon {
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:_bundleID];
    NSImage *icon = app ? [NSWorkspace.sharedWorkspace iconForFile:app.path] : nil;
    return icon ?: [NSWorkspace.sharedWorkspace iconForContentType:UTTypeApplicationBundle];
}

@end

@interface ChromiumProfile ()
@property (readwrite) NSString *name;
@property (readwrite) NSString *directory;
@property (readwrite) NSInteger passwordCount;
@end
@implementation ChromiumProfile
@end

@implementation BrowserImport
@end

// MARK: - Importer

@implementation PasswordImporter

/// The browser's Safe Storage password. Reading it shows macOS's keychain prompt the first time.
static NSData *SafeStoragePassword(NSString *service, OSStatus *status) {
    NSDictionary *query = @{(id)kSecClass: (id)kSecClassGenericPassword, (id)kSecAttrService: service,
                            (id)kSecReturnData: @YES, (id)kSecMatchLimit: (id)kSecMatchLimitOne};
    CFTypeRef result = NULL;
    *status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    return *status == errSecSuccess ? CFBridgingRelease(result) : nil;
}

+ (NSString *)decryptChromiumValue:(NSData *)value safeStoragePassword:(NSData *)password {
    static const char prefix[] = "v10";
    if (value.length <= 3 || memcmp(value.bytes, prefix, 3) != 0 || password.length == 0) return nil;
    // Chromium on macOS: PBKDF2-SHA1 with salt "saltysalt", 1003 rounds, a 128-bit AES-CBC key and
    // an IV of 16 spaces (os_crypt_mac.mm).
    uint8_t key[kCCKeySizeAES128];
    if (CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)password.bytes, password.length, (const uint8_t *)"saltysalt", 9,
                             kCCPRFHmacAlgSHA1, 1003, key, sizeof key) != kCCSuccess) return nil;
    uint8_t iv[kCCBlockSizeAES128];
    memset(iv, ' ', sizeof iv);
    NSData *cipher = [value subdataWithRange:NSMakeRange(3, value.length - 3)];
    NSMutableData *plain = [NSMutableData dataWithLength:cipher.length + kCCBlockSizeAES128];
    size_t moved = 0;
    CCCryptorStatus s = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, sizeof key, iv,
                                cipher.bytes, cipher.length, plain.mutableBytes, plain.length, &moved);
    memset(key, 0, sizeof key);
    if (s != kCCSuccess) return nil;
    plain.length = moved;
    NSString *text = [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
    memset(plain.mutableBytes, 0, plain.length);
    return text;
}

/// Chromium time: microseconds since 1601-01-01. nil for 0.
static NSDate *ChromiumDate(sqlite3_int64 micros) {
    if (micros <= 0) return nil;
    return [NSDate dateWithTimeIntervalSince1970:(double)micros / 1e6 - 11644473600.0];
}

static NSURL *PrivateCopy(NSURL *file, NSURL *dir, NSString *name) {
    NSURL *copy = [dir URLByAppendingPathComponent:name];
    sqlite3 *source = NULL, *destination = NULL;
    BOOL ok = sqlite3_open_v2(file.fileSystemRepresentation, &source, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK;
    if (ok) ok = sqlite3_open(copy.fileSystemRepresentation, &destination) == SQLITE_OK;
    if (ok) {
        sqlite3_busy_timeout(source, 2000);
        sqlite3_backup *backup = sqlite3_backup_init(destination, "main", source, "main");
        ok = backup && sqlite3_backup_step(backup, -1) == SQLITE_DONE;
        if (backup) ok = sqlite3_backup_finish(backup) == SQLITE_OK && ok;
        if (ok) ok = sqlite3_exec(destination, "PRAGMA journal_mode=DELETE", NULL, NULL, NULL) == SQLITE_OK;
    }
    sqlite3_close(destination);
    sqlite3_close(source);
    return ok ? copy : nil;
}

/// HTML-form logins in one "Login Data" file. Returns NO if it couldn't be opened.
static BOOL ReadLoginData(NSURL *file, NSData *key, NSMutableArray<LoginCandidate *> *out, NSInteger *undecryptable) {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(file.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        sqlite3_close(db);
        return NO;
    }
    // scheme 0 = a web form (not HTTP auth); blacklisted rows are "Never save" entries.
    const char *sql = "SELECT origin_url, signon_realm, username_value, password_value, date_created, "
                      "date_password_modified FROM logins WHERE blacklisted_by_user = 0 AND scheme = 0";
    sqlite3_stmt *stmt = NULL;
    BOOL ok = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK;
    if (!ok) {
        // Older schemas have no date_password_modified.
        sql = "SELECT origin_url, signon_realm, username_value, password_value, date_created, 0 FROM logins "
              "WHERE blacklisted_by_user = 0 AND scheme = 0";
        ok = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK;
    }
    if (ok) {
        auto text = [](sqlite3_stmt *s, int col) -> NSString * {
            const unsigned char *t = sqlite3_column_text(s, col);
            return t ? @((const char *)t) : @"";
        };
        int step;
        while ((step = sqlite3_step(stmt)) == SQLITE_ROW) {
            NSString *origin = text(stmt, 0);
            if (origin.length == 0) origin = text(stmt, 1);
            const void *blob = sqlite3_column_blob(stmt, 3);
            int length = sqlite3_column_bytes(stmt, 3);
            if (!blob || length <= 0) continue;
            NSData *value = [NSData dataWithBytes:blob length:(NSUInteger)length];
            NSString *password = [PasswordImporter decryptChromiumValue:value safeStoragePassword:key];
            if (!password) {
                (*undecryptable)++;
                continue;
            }
            LoginCandidate *c = [LoginCandidate new];
            c.url = origin;
            c.username = text(stmt, 2);
            c.password = password;
            c.modified = ChromiumDate(sqlite3_column_int64(stmt, 5)) ?: ChromiumDate(sqlite3_column_int64(stmt, 4));
            [out addObject:c];
        }
        ok = step == SQLITE_DONE;
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return ok;
}

+ (NSArray<ChromiumProfile *> *)profilesForBrowser:(ChromiumBrowser *)browser error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *folders = [fm contentsOfDirectoryAtPath:browser.dataFolder.path error:error];
    if (!folders) return nil;
    NSData *stateData = [NSData dataWithContentsOfURL:[browser.dataFolder URLByAppendingPathComponent:@"Local State"]];
    id state = stateData ? [NSJSONSerialization JSONObjectWithData:stateData options:0 error:nil] : nil;
    id profile = [state isKindOfClass:NSDictionary.class] ? state[@"profile"] : nil;
    id cache = [profile isKindOfClass:NSDictionary.class] ? profile[@"info_cache"] : nil;
    NSMutableArray<ChromiumProfile *> *profiles = [NSMutableArray array];
    NSMutableArray *directories = [[folders sortedArrayUsingSelector:@selector(localizedStandardCompare:)] mutableCopy];
    [directories insertObject:@"" atIndex:0];
    for (NSString *directory in directories) {
        NSURL *folder = directory.length ? [browser.dataFolder URLByAppendingPathComponent:directory] : browser.dataFolder;
        BOOL found = NO;
        NSInteger count = 0;
        for (NSString *name in @[@"Login Data", @"Login Data For Account"]) {
            NSURL *file = [folder URLByAppendingPathComponent:name];
            if (![fm fileExistsAtPath:file.path]) continue;
            found = YES;
            sqlite3 *db = NULL;
            if (sqlite3_open_v2(file.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
                sqlite3_stmt *stmt = NULL;
                if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM logins WHERE blacklisted_by_user=0 AND scheme=0", -1, &stmt, NULL) == SQLITE_OK &&
                    sqlite3_step(stmt) == SQLITE_ROW) count += sqlite3_column_int(stmt, 0);
                sqlite3_finalize(stmt);
            }
            sqlite3_close(db);
        }
        if (!found) continue;
        id info = [cache isKindOfClass:NSDictionary.class] ? cache[directory] : nil;
        ChromiumProfile *p = [ChromiumProfile new];
        p.directory = directory;
        p.name = [info isKindOfClass:NSDictionary.class] && [info[@"name"] isKindOfClass:NSString.class]
            ? info[@"name"] : (directory.length ? directory : @"Default");
        p.passwordCount = count;
        [profiles addObject:p];
    }
    return profiles;
}

+ (BrowserImport *)readBrowser:(ChromiumBrowser *)browser {
    NSError *error = nil;
    NSArray *profiles = [self profilesForBrowser:browser error:&error];
    if (!profiles) {
        BrowserImport *result = [BrowserImport new];
        result.browser = browser;
        result.logins = @[];
        result.profiles = @[];
        result.failure = error.localizedDescription;
        return result;
    }
    return [self readBrowser:browser profiles:profiles];
}

+ (BrowserImport *)readBrowser:(ChromiumBrowser *)browser profiles:(NSArray<ChromiumProfile *> *)profiles {
    BrowserImport *result = [BrowserImport new];
    result.browser = browser;
    result.logins = @[];
    result.profiles = @[];
    if (profiles.count == 0) {
        result.failure = @"Choose at least one browser profile to import.";
        return result;
    }
    OSStatus status = errSecSuccess;
    NSData *key = SafeStoragePassword(browser.keychainService, &status);
    if (!key) {
        result.failure = status == errSecUserCanceled || status == errSecAuthFailed
            ? [NSString stringWithFormat:@"Access to %@’s password key was cancelled. Try again and choose Allow when macOS asks, or import a CSV export.", browser.name]
            : [NSString stringWithFormat:@"%@’s password key isn’t available. Open %@ once, then try again, or import a CSV export.", browser.name, browser.name];
        return result;
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    if (![fm createDirectoryAtURL:tmp withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil]) {
        result.failure = @"Brook couldn’t create a private copy of the browser database. Try importing a CSV export.";
        return result;
    }
    NSMutableArray<LoginCandidate *> *logins = [NSMutableArray array];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSInteger undecryptable = 0, index = 0, unreadable = 0;
    for (ChromiumProfile *profile in profiles) {
        NSURL *folder = profile.directory.length ? [browser.dataFolder URLByAppendingPathComponent:profile.directory] : browser.dataFolder;
        [names addObject:profile.name];
        for (NSString *name in @[@"Login Data", @"Login Data For Account"]) {
            NSURL *db = [folder URLByAppendingPathComponent:name];
            if (![fm fileExistsAtPath:db.path]) continue;
            NSURL *copy = PrivateCopy(db, tmp, [NSString stringWithFormat:@"%ld", (long)index++]);
            if (!copy || !ReadLoginData(copy, key, logins, &undecryptable)) unreadable++;
        }
    }
    [fm removeItemAtURL:tmp error:nil];
    result.logins = logins;
    result.profiles = names;
    result.undecryptable = undecryptable;
    if (unreadable) result.failure = @"Some browser databases couldn’t be read. Close the source browser and try again, or import a CSV export.";
    else if (logins.count == 0 && undecryptable > 0) result.failure = @"These passwords use an encryption format Brook can’t read. Export them as CSV and import that file.";
    else if (logins.count == 0) result.failure = @"The selected profiles have no usable saved passwords.";
    return result;
}

// MARK: CSV

/// RFC 4180 rows: quoted fields may hold commas, quotes ("") and line breaks.
static std::vector<std::vector<NSString *>> ParseCSV(NSString *text, BOOL *valid) {
    *valid = YES;
    std::vector<std::vector<NSString *>> rows;
    std::vector<NSString *> row;
    NSMutableString *field = [NSMutableString string];
    BOOL quoted = NO, fieldStarted = NO, closed = NO;
    NSUInteger n = text.length;
    std::vector<unichar> buffer(n);
    [text getCharacters:buffer.data() range:NSMakeRange(0, n)];
    auto endField = [&] {
        row.push_back([field copy]);
        [field setString:@""];
        fieldStarted = NO;
        closed = NO;
    };
    auto endRow = [&] {
        endField();
        BOOL empty = row.size() == 1 && row[0].length == 0;
        if (!empty) rows.push_back(row);
        row.clear();
    };
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = buffer[i];
        if (quoted) {
            if (c == '"') {
                if (i + 1 < n && buffer[i + 1] == '"') { [field appendString:@"\""]; i++; }
                else { quoted = NO; closed = YES; }
            } else {
                [field appendFormat:@"%C", c];
            }
            continue;
        }
        if ((closed && c != ',' && c != '\r' && c != '\n') || (c == '"' && fieldStarted)) { *valid = NO; return {}; }
        if (c == '"' && !fieldStarted) { quoted = YES; fieldStarted = YES; }
        else if (c == ',') endField();
        else if (c == '\r') { endRow(); if (i + 1 < n && buffer[i + 1] == '\n') i++; }
        else if (c == '\n') endRow();
        else { [field appendFormat:@"%C", c]; fieldStarted = YES; }
    }
    if (quoted) { *valid = NO; return {}; }
    if (field.length || !row.empty() || fieldStarted) endRow();
    std::fill(buffer.begin(), buffer.end(), 0);
    return rows;
}

+ (NSArray<LoginCandidate *> *)candidatesFromCSV:(NSData *)data error:(NSError **)error {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                  ?: [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];
    if ([text hasPrefix:@"\uFEFF"]) text = [text substringFromIndex:1];
    BOOL valid = YES;
    auto rows = text ? ParseCSV(text, &valid) : std::vector<std::vector<NSString *>>{};
    if (!valid) {
        if (error) *error = ImportError(@"The CSV has an incomplete or invalid quoted field. Export the passwords again and choose the new file.");
        return nil;
    }
    if (rows.empty()) {
        if (error) *error = ImportError(@"The file is empty.");
        return nil;
    }
    // Column names as each app writes them (compared lower-case).
    NSInteger url = -1, user = -1, pass = -1, changed = -1, type = -1;
    const auto &header = rows[0];
    for (size_t i = 0; i < header.size(); i++) {
        NSString *h = BrookTrimAll(header[i]).lowercaseString;
        NSInteger col = (NSInteger)i;
        if (url < 0 && [@[@"url", @"login_uri", @"website", @"web site", @"login url", @"origin", @"uri", @"address"] containsObject:h]) url = col;
        else if (user < 0 && [@[@"username", @"login_username", @"user name", @"user", @"login", @"email", @"e-mail", @"login name"] containsObject:h]) user = col;
        else if (pass < 0 && [@[@"password", @"login_password", @"pass"] containsObject:h]) pass = col;
        else if (changed < 0 && [h isEqualToString:@"timepasswordchanged"]) changed = col;   // Firefox, ms since 1970
        else if (type < 0 && [h isEqualToString:@"type"]) type = col;                          // Bitwarden: login, note, card…
    }
    if (url < 0 || pass < 0) {
        if (error) *error = ImportError(@"This CSV file has no website and password columns. Export passwords from your "
                                        @"browser or password manager as CSV, then choose that file.");
        return nil;
    }
    NSMutableArray<LoginCandidate *> *out = [NSMutableArray array];
    auto cell = [](const std::vector<NSString *> &r, NSInteger col) -> NSString * {
        return col >= 0 && (size_t)col < r.size() ? r[(size_t)col] : @"";
    };
    for (size_t i = 1; i < rows.size(); i++) {
        const auto &r = rows[i];
        if (r.size() != header.size()) {
            if (error) *error = ImportError([NSString stringWithFormat:@"CSV row %zu has the wrong number of columns. Export the passwords again.", i + 1]);
            return nil;
        }
        if (type >= 0 && cell(r, type).length && ![cell(r, type).lowercaseString isEqualToString:@"login"]) continue;
        LoginCandidate *c = [LoginCandidate new];
        c.url = BrookTrimAll(cell(r, url));
        c.username = cell(r, user);
        c.password = cell(r, pass);
        double ms = cell(r, changed).doubleValue;
        if (ms > 0) c.modified = [NSDate dateWithTimeIntervalSince1970:ms / 1000];
        [out addObject:c];
    }
    return out;
}

@end
