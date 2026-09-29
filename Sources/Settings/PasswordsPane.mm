#import "Brook.h"

@interface PasswordDropView : NSView
@property (copy) void (^onFile)(NSURL *);
@end
@implementation PasswordDropView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    return self;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return self.onFile ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *files = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (files.count != 1 || !self.onFile) return NO;
    self.onFile(files.firstObject);
    return YES;
}
@end

@interface PasswordImportController : NSWindowController
- (void)beginForWindow:(NSWindow *)parent completion:(void (^)(void))completion;
@end

@implementation PasswordImportController {
    NSPopUpButton *_source;
    NSStackView *_profiles;
    NSArray<ChromiumBrowser *> *_browsers;
    NSArray<ChromiumProfile *> *_foundProfiles;
    NSMutableArray<NSButton *> *_checks;
    NSTextField *_instructions;
    NSTextField *_status;
    NSButton *_import;
    NSButton *_cancel;
    NSProgressIndicator *_progress;
    PasswordDropView *_root;
    BOOL _busy;
    NSUInteger _generation;
    void (^_completion)(void);
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 420)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    if (!(self = [super initWithWindow:window])) return nil;
    window.title = @"Import Passwords";
    window.releasedWhenClosed = NO;
    _browsers = ChromiumBrowser.installed;
    _checks = [NSMutableArray array];
    _root = [PasswordDropView new];
    window.contentView = _root;
    _source = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_source addItemWithTitle:@"CSV file (any browser or password manager)"];
    for (ChromiumBrowser *browser in _browsers) {
        [_source addItemWithTitle:browser.name];
        _source.lastItem.image = [browser.icon copy];
        _source.lastItem.image.size = NSMakeSize(18, 18);
    }
    _source.accessibilityLabel = @"Import passwords from";
    _instructions = [NSTextField wrappingLabelWithString:@""];
    _instructions.textColor = NSColor.secondaryLabelColor;
    _instructions.font = [NSFont systemFontOfSize:12];
    _status = [NSTextField wrappingLabelWithString:@""];
    _status.font = [NSFont systemFontOfSize:12];
    _status.accessibilityLabel = @"Import status";
    _profiles = [NSStackView new];
    _profiles.orientation = NSUserInterfaceLayoutOrientationVertical;
    _profiles.alignment = NSLayoutAttributeLeading;
    _profiles.spacing = 10;
    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = _profiles;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    _progress = [NSProgressIndicator new];
    _progress.style = NSProgressIndicatorStyleSpinning;
    _progress.displayedWhenStopped = NO;
    __weak PasswordImportController *weakSelf = self;
    _import = [Controls button:@"Choose CSV…" action:^{ [weakSelf startImport]; }];
    _import.keyEquivalent = @"\r";
    _cancel = [Controls button:@"Cancel" action:^{ [weakSelf finish]; }];
    _cancel.keyEquivalent = @"\033";
    [_source brook_onAction:^(id) { [weakSelf sourceChanged]; }];
    _root.onFile = ^(NSURL *url) { [weakSelf importCSV:url]; };
    NSTextField *title = [NSTextField labelWithString:@"Bring your passwords to Brook"];
    title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    for (NSView *view in @[title, _source, _instructions, scroll, _status, _progress, _cancel, _import]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_root addSubview:view];
    }
    _profiles.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:_root.topAnchor constant:22],
        [title.leadingAnchor constraintEqualToAnchor:_root.leadingAnchor constant:24],
        [_source.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
        [_source.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_source.trailingAnchor constraintEqualToAnchor:_root.trailingAnchor constant:-24],
        [_instructions.topAnchor constraintEqualToAnchor:_source.bottomAnchor constant:12],
        [_instructions.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_instructions.trailingAnchor constraintEqualToAnchor:_source.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:_instructions.bottomAnchor constant:16],
        [scroll.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_source.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_status.topAnchor constant:-12],
        [_profiles.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [_profiles.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [_profiles.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [_status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_status.trailingAnchor constraintEqualToAnchor:_source.trailingAnchor],
        [_status.bottomAnchor constraintEqualToAnchor:_import.topAnchor constant:-16],
        [_status.heightAnchor constraintGreaterThanOrEqualToConstant:38],
        [_import.trailingAnchor constraintEqualToAnchor:_source.trailingAnchor],
        [_import.bottomAnchor constraintEqualToAnchor:_root.bottomAnchor constant:-20],
        [_cancel.trailingAnchor constraintEqualToAnchor:_import.leadingAnchor constant:-8],
        [_cancel.centerYAnchor constraintEqualToAnchor:_import.centerYAnchor],
        [_progress.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_progress.centerYAnchor constraintEqualToAnchor:_import.centerYAnchor]
    ]];
    [self sourceChanged];
    return self;
}

- (void)beginForWindow:(NSWindow *)parent completion:(void (^)(void))completion {
    _completion = [completion copy];
    [parent beginSheet:self.window completionHandler:^(NSModalResponse) {}];
}

- (void)finish {
    if (_busy) return;
    _generation++;
    [self.window.sheetParent endSheet:self.window];
    [self.window orderOut:nil];
    void (^completion)(void) = _completion;
    _completion = nil;
    if (completion) completion();
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    if (busy) _cancel.title = @"Cancel";
    _source.enabled = !busy;
    _import.enabled = !busy;
    _cancel.enabled = !busy;
    for (NSButton *check in _checks) check.enabled = !busy;
    if (busy) [_progress startAnimation:nil]; else [_progress stopAnimation:nil];
}

- (void)sourceChanged {
    NSUInteger generation = ++_generation;
    for (NSView *view in _profiles.arrangedSubviews.copy) [view removeFromSuperview];
    [_checks removeAllObjects];
    _foundProfiles = nil;
    _status.stringValue = @"";
    if (_source.indexOfSelectedItem == 0) {
        _import.title = @"Choose CSV…";
        _instructions.stringValue = @"Export passwords as CSV from Safari, Apple Passwords, Firefox, Zen, Orion, Chrome, 1Password or Bitwarden. Choose the file below, or drop it here. CSV files contain readable passwords.";
        return;
    }
    ChromiumBrowser *browser = _browsers[(NSUInteger)_source.indexOfSelectedItem - 1];
    _import.title = @"Import";
    _instructions.stringValue = [NSString stringWithFormat:@"Choose profiles from %@. macOS may ask to let Brook read the browser’s data and its “%@” key. Choose Allow to continue.", browser.name, browser.keychainService];
    [self setBusy:YES];
    _status.stringValue = @"Looking for browser profiles…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray<ChromiumProfile *> *profiles = [PasswordImporter profilesForBrowser:browser error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            [self setBusy:NO];
            self->_foundProfiles = profiles;
            self->_status.stringValue = error ? @"Brook couldn’t read these profiles. Allow access when macOS asks, or choose CSV file above."
                : profiles.count ? @"" : @"No saved passwords found. Choose CSV file above to import an export.";
            for (ChromiumProfile *profile in profiles) {
                NSButton *check = [NSButton checkboxWithTitle:[NSString stringWithFormat:@"%@ · %ld passwords", profile.name, (long)profile.passwordCount]
                    target:nil action:nil];
                check.state = NSControlStateValueOn;
                check.lineBreakMode = NSLineBreakByTruncatingTail;
                [self->_profiles addArrangedSubview:check];
                [self->_checks addObject:check];
            }
            self->_import.enabled = profiles.count > 0;
        });
    });
}

- (void)startImport {
    if (_busy) return;
    if (_source.indexOfSelectedItem == 0) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.allowedContentTypes = @[UTTypeCommaSeparatedText];
        panel.allowsMultipleSelection = NO;
        panel.message = @"Choose the password CSV you exported from your browser or password manager.";
        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response == NSModalResponseOK) [self importCSV:panel.URL];
        }];
        return;
    }
    NSMutableArray *profiles = [NSMutableArray array];
    for (NSUInteger i = 0; i < _checks.count; i++) if (_checks[i].state == NSControlStateValueOn) [profiles addObject:_foundProfiles[i]];
    if (profiles.count == 0) { _status.stringValue = @"Choose at least one profile."; return; }
    ChromiumBrowser *browser = _browsers[(NSUInteger)_source.indexOfSelectedItem - 1];
    [self setBusy:YES];
    _status.stringValue = [NSString stringWithFormat:@"Reading %@ passwords…", browser.name];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BrowserImport *read = [PasswordImporter readBrowser:browser profiles:profiles];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (read.failure) {
                for (LoginCandidate *login in read.logins) login.password = nil;
                [self setBusy:NO];
                self->_status.stringValue = read.failure;
                return;
            }
            self->_status.stringValue = @"Saving passwords securely…";
            [PasswordStore.shared importCandidates:read.logins source:browser.name completion:^(PasswordImportResult *result) {
                result.skipped += read.undecryptable;
                [self showResult:result file:nil];
            }];
        });
    });
}

- (void)importCSV:(NSURL *)file {
    if (_busy || !file.isFileURL || self.window.attachedSheet) return;
    [self setBusy:YES];
    _status.stringValue = @"Reading CSV…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:&error];
        NSData *data = nil;
        if ([attributes[NSFileSize] unsignedLongLongValue] > 32 * 1024 * 1024)
            error = [NSError errorWithDomain:@"BrookPasswordImport" code:1 userInfo:@{NSLocalizedDescriptionKey: @"This CSV is larger than 32 MB. Export passwords only, or split the file before importing."}];
        else if (attributes) data = [NSData dataWithContentsOfURL:file options:0 error:&error];
        NSArray *candidates = data ? [PasswordImporter candidatesFromCSV:data error:&error] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!candidates) {
                [self setBusy:NO];
                self->_status.stringValue = error.localizedDescription ?: @"The file couldn’t be read. Choose a password CSV export.";
                return;
            }
            self->_status.stringValue = @"Saving passwords securely…";
            [PasswordStore.shared importCandidates:candidates source:@"CSV" completion:^(PasswordImportResult *result) {
                [self showResult:result file:file];
            }];
        });
    });
}

- (void)showResult:(PasswordImportResult *)result file:(NSURL *)file {
    [self setBusy:NO];
    if (result.error) { _status.stringValue = result.error.localizedDescription; return; }
    NSString *summary = [NSString stringWithFormat:@"Imported %ld · Updated %ld · Already saved %ld · Duplicate rows %ld · Skipped %ld",
        (long)result.added, (long)result.updated, (long)result.unchanged, (long)result.duplicates, (long)result.skipped];
    if (result.skipped) summary = [summary stringByAppendingString:@"\nKeep the source file. Invalid rows and conflicting passwords without a newer timestamp were skipped."];
    _status.stringValue = summary;
    _cancel.title = @"Done";
    if (!file || result.skipped || !(result.added || result.updated || result.unchanged)) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Move the password CSV to the Bin?";
    alert.informativeText = [summary stringByAppendingString:@"\n\nThe CSV contains readable passwords. Brook has saved the imported passwords securely on this Mac."];
    [alert addButtonWithTitle:@"Keep File"];
    [alert addButtonWithTitle:@"Move to Bin"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertSecondButtonReturn) return;
        NSError *error = nil;
        if (![NSFileManager.defaultManager trashItemAtURL:file resultingItemURL:nil error:&error])
            self->_status.stringValue = [summary stringByAppendingFormat:@"\nThe CSV couldn’t be moved to the Bin: %@", error.localizedDescription];
        else self->_status.stringValue = [summary stringByAppendingString:@"\nCSV moved to the Bin."];
    }];
}
@end

@implementation PasswordsPane {
    EditableList *_list;
    NSSearchField *_search;
    NSArray<SavedLogin *> *_rows;
    NSTextField *_password;
    NSTextField *_details;
    NSTextField *_status;
    NSButton *_reveal;
    NSButton *_copy;
    NSButton *_lock;
    NSButton *_edit;
    NSButton *_import;
    PasswordImportController *_importController;
    id _observer;
    BOOL _revealed;
    BOOL _showing;
}

- (NSView *)makeContent {
    self.rebuildKeys = [NSSet setWithArray:@[@"*", @"autofillPasswords", @"offerToSavePasswords"]];
    __weak PasswordsPane *weakSelf = self;
    SettingsForm *form = [SettingsForm new];
    [form row:@"Passwords" views:@[
        [Controls check:@"Offer to save passwords" on:Settings.offerToSavePasswords onChange:^(BOOL on) { Settings.offerToSavePasswords = on; }],
        [Controls check:@"Offer saved passwords on sign-in fields" on:Settings.autofillPasswords onChange:^(BOOL on) { Settings.autofillPasswords = on; }]
    ]];
    [form note:@"Passwords are encrypted for this Mac. Touch ID or your login password unlocks them for five minutes."];
    _search = [NSSearchField new];
    _search.placeholderString = @"Search websites and usernames";
    _search.accessibilityLabel = @"Search saved passwords";
    _search.delegate = self;
    _search.sendsWholeSearchString = NO;
    [_search.widthAnchor constraintEqualToConstant:510].active = YES;
    [form row:@"Saved logins" view:_search];
    _list = [[EditableList alloc] initWithColumns:{{@"site", @"Website", 275}, {@"user", @"Username", 235}} height:220];
    _list.table.dataSource = self;
    _list.table.delegate = self;
    _list.table.rowHeight = 30;
    _list.table.allowsMultipleSelection = YES;
    _list.emptyLabel.textColor = NSColor.secondaryLabelColor;
    _list.emptyLabel.stringValue = @"No saved passwords. Import or add a login.";
    [_list.container.widthAnchor constraintEqualToConstant:510].active = YES;
    _list.onAdd = ^{ [weakSelf editLogin:nil]; };
    _list.onRemove = ^(NSInteger) { [weakSelf deleteSelected]; };
    _edit = [Controls button:@"Edit…" action:^{ [weakSelf editLogin:weakSelf.selectedLogin]; }];
    _import = [Controls button:@"Import…" action:^{ [weakSelf beginImport]; }];
    _lock = [Controls button:@"Lock" action:^{ [PasswordStore.shared lock]; }];
    _list.extra = @[_edit, _import, _lock];
    [form row:@"" view:_list.container];
    _password = [NSTextField labelWithString:@"••••••••"];
    _password.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    _password.lineBreakMode = NSLineBreakByTruncatingTail;
    [_password.widthAnchor constraintEqualToConstant:260].active = YES;
    _reveal = [Controls button:@"Reveal" action:^{ [weakSelf reveal]; }];
    _copy = [Controls button:@"Copy Password" action:^{ [weakSelf copyPassword]; }];
    NSStackView *actions = [NSStackView stackViewWithViews:@[_password, _reveal, _copy]];
    actions.spacing = 8;
    [form row:@"Password" view:actions];
    _details = [NSTextField labelWithString:@"Select a saved login to view its details."];
    _details.font = [NSFont systemFontOfSize:11];
    _details.textColor = NSColor.secondaryLabelColor;
    _details.lineBreakMode = NSLineBreakByTruncatingTail;
    [_details.widthAnchor constraintEqualToConstant:510].active = YES;
    [form row:@"" view:_details];
    _status = [NSTextField wrappingLabelWithString:@""];
    _status.font = [NSFont systemFontOfSize:12];
    _status.accessibilityLabel = @"Password status";
    [_status.widthAnchor constraintEqualToConstant:510].active = YES;
    [_status.heightAnchor constraintGreaterThanOrEqualToConstant:30].active = YES;
    [form row:@"" view:_status];
    if (!_observer) {
        _observer = [NSNotificationCenter.defaultCenter addObserverForName:PasswordStoreDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *) { [weakSelf refresh]; }];
    }
    [self refresh];
    return [form viewWithWidth:700];
}

- (void)dealloc { if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer]; }
- (void)viewDidAppear { [super viewDidAppear]; _showing = YES; }
- (void)viewWillDisappear { [super viewWillDisappear]; _showing = NO; [self hidePassword]; }

- (SavedLogin *)selectedLogin {
    NSInteger row = _list.table.selectedRow;
    return _list.table.numberOfSelectedRows == 1 && row >= 0 && row < (NSInteger)_rows.count ? _rows[(NSUInteger)row] : nil;
}

- (void)hidePassword {
    _revealed = NO;
    _password.stringValue = @"••••••••";
    _password.selectable = NO;
    _reveal.title = @"Reveal";
}

- (void)refresh {
    NSString *selected = self.selectedLogin.identifier;
    [self hidePassword];
    NSMutableArray *rows = [NSMutableArray array];
    NSString *query = BrookTrimAll(_search.stringValue);
    for (SavedLogin *login in PasswordStore.shared.logins) {
        NSString *text = [login.origin stringByAppendingFormat:@" %@", login.username];
        if (query.length == 0 || [text rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound)
            [rows addObject:login];
    }
    _rows = rows;
    [_list reload];
    [_list.table deselectAll:nil];
    for (NSUInteger i = 0; i < _rows.count; i++) if ([_rows[i].identifier isEqualToString:selected])
        [_list.table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
    _list.emptyLabel.stringValue = query.length ? @"No matching saved passwords." : @"No saved passwords. Import or add a login.";
    BOOL available = PasswordStore.shared.isAvailable;
    [_list.segment setEnabled:available forSegment:0];
    _import.enabled = available;
    _lock.enabled = PasswordStore.shared.isUnlocked;
    if (!available) _status.stringValue = @"Password storage requires the Secure Enclave on an Apple silicon Mac.";
    [self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:_list.table]];
}

- (void)controlTextDidChange:(NSNotification *)note { [self refresh]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)_rows.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    SavedLogin *login = _rows[(NSUInteger)row];
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, column.width, 30)];
    NSTextField *text = [NSTextField labelWithString:[column.identifier isEqualToString:@"site"] ? login.host : (login.username.length ? login.username : @"No username")];
    text.lineBreakMode = NSLineBreakByTruncatingTail;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:text];
    cell.textField = text;
    CGFloat leading = 8;
    if ([column.identifier isEqualToString:@"site"]) {
        NSImageView *icon = [NSImageView new];
        icon.image = [FaviconStore.shared cachedIconForHost:login.host] ?: [NSImage brook_symbol:@"globe" size:16];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:icon];
        cell.imageView = icon;
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:16], [icon.heightAnchor constraintEqualToConstant:16]
        ]];
        leading = 32;
    }
    [NSLayoutConstraint activateConstraints:@[
        [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:leading],
        [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
        [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
    ]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    [self hidePassword];
    SavedLogin *login = self.selectedLogin;
    _reveal.enabled = _copy.enabled = _edit.enabled = login != nil;
    [_list.segment setEnabled:_list.table.numberOfSelectedRows > 0 forSegment:1];
    _details.stringValue = login ? [NSString stringWithFormat:@"%@ · %@ · Updated %@", login.origin, login.source, [NSDateFormatter localizedStringFromDate:login.modified dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterNoStyle]]
        : @"Select a saved login to view its details.";
}

- (void)reveal {
    if (_revealed) { [self hidePassword]; return; }
    SavedLogin *login = self.selectedLogin;
    if (!login) return;
    [PasswordStore.shared openPassword:login reason:@"reveal this saved password" completion:^(NSString *password) {
        if (!self->_showing || self.selectedLogin != login || self.view.window.isVisible == NO || self.view.window.attachedSheet != nil) return;
        if (!password) { self->_status.stringValue = @"Password wasn’t unlocked. Try again to reveal it."; return; }
        self->_revealed = YES;
        self->_password.stringValue = password;
        self->_password.selectable = YES;
        self->_reveal.title = @"Hide";
    }];
}

- (void)copyPassword {
    SavedLogin *login = self.selectedLogin;
    if (!login) return;
    [PasswordStore.shared openPassword:login reason:@"copy this saved password" completion:^(NSString *password) {
        if (!self->_showing || self.selectedLogin != login || !password || !self.view.window.isVisible) return;
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        [pasteboard prepareForNewContentsWithOptions:NSPasteboardContentsCurrentHostOnly];
        [pasteboard setString:password forType:NSPasteboardTypeString];
        [pasteboard setData:NSData.data forType:@"org.nspasteboard.ConcealedType"];
        NSInteger count = pasteboard.changeCount;
        self->_status.stringValue = @"Password copied. Clipboard clears in 30 seconds unless you copy something else.";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (pasteboard.changeCount == count) [pasteboard clearContents];
        });
    }];
}

- (void)deleteSelected {
    NSMutableArray *selected = [NSMutableArray array];
    [_list.table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *) {
        if (index < self->_rows.count) [selected addObject:self->_rows[index]];
    }];
    if (selected.count == 0) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Delete %lu saved login%@?", selected.count, selected.count == 1 ? @"" : @"s"];
    alert.informativeText = @"The passwords will be removed from Brook on this Mac.";
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Delete"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertSecondButtonReturn) return;
        NSError *error = nil;
        [PasswordStore.shared removeLogins:selected error:&error];
        self->_status.stringValue = error ? error.localizedDescription : @"Saved logins deleted.";
    }];
}

- (void)editLogin:(SavedLogin *)login {
    if (self.view.window.attachedSheet) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = login ? @"Edit saved login" : @"Add a saved login";
    alert.informativeText = login ? @"Leave the password blank to keep the saved password." : @"Enter the website, username and password.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *website = [NSTextField textFieldWithString:login.origin ?: @""];
    website.placeholderString = @"https://example.com";
    website.editable = login == nil;
    NSTextField *username = [NSTextField textFieldWithString:login.username ?: @""];
    NSSecureTextField *password = [NSSecureTextField new];
    password.placeholderString = login ? @"Keep current password" : @"Password";
    SettingsForm *form = [SettingsForm new];
    for (NSView *field in @[website, username, password]) [field.widthAnchor constraintEqualToConstant:280].active = YES;
    [form row:@"Website" view:website];
    [form row:@"Username" view:username];
    [form row:@"Password" view:password];
    [form finish];
    alert.accessoryView = form.grid;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) { password.stringValue = @""; return; }
        if (!login && [PasswordStore.shared loginForOrigin:[PasswordStore originForURLString:website.stringValue]
            username:BrookTrimAll(username.stringValue)]) {
            password.stringValue = @"";
            self->_status.stringValue = @"This website and username already have a saved login. Select it and choose Edit to change the password.";
            return;
        }
        NSError *error = nil;
        if (login) [PasswordStore.shared updateLogin:login username:username.stringValue password:password.stringValue.length ? password.stringValue : nil error:&error];
        else [PasswordStore.shared saveOrigin:website.stringValue username:username.stringValue password:password.stringValue source:@"Brook" error:&error];
        password.stringValue = @"";
        self->_status.stringValue = error ? error.localizedDescription : @"Login saved.";
    }];
}

- (void)beginImport {
    if (_importController || self.view.window.attachedSheet || !PasswordStore.shared.isAvailable) return;
    _importController = [PasswordImportController new];
    __weak PasswordsPane *weakSelf = self;
    [_importController beginForWindow:self.view.window completion:^{
        PasswordsPane *pane = weakSelf;
        if (!pane) return;
        pane->_importController = nil;
        [pane refresh];
    }];
}
@end
