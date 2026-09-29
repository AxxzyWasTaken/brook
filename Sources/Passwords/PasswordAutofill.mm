#import "Brook.h"

static WKContentWorld *PasswordWorld(void) { return [WKContentWorld worldWithName:@"BrookPasswords"]; }

typedef NS_ENUM(NSInteger, PasswordRequestPhase) {
    PasswordRequestSuggesting, PasswordRequestAuthenticating, PasswordRequestFilling,
    PasswordRequestComparing, PasswordRequestSaving
};

@interface PasswordRequest : NSObject
@property (weak, readonly) WKWebView *webView;
@property (copy, readonly) NSString *origin;
@property (copy, readonly) NSString *token;
@property PasswordRequestPhase phase;
@property (strong) NSPopover *popover;
- (instancetype)initWithWebView:(WKWebView *)webView origin:(NSString *)origin token:(NSString *)token phase:(PasswordRequestPhase)phase;
- (BOOL)survivesNavigation;
- (void)closePopover;
@end

@implementation PasswordRequest
- (instancetype)initWithWebView:(WKWebView *)webView origin:(NSString *)origin token:(NSString *)token phase:(PasswordRequestPhase)phase {
    if ((self = [super init])) {
        _webView = webView;
        _origin = [origin copy];
        _token = [token copy];
        _phase = phase;
    }
    return self;
}
- (BOOL)survivesNavigation { return _phase == PasswordRequestComparing || _phase == PasswordRequestSaving; }
- (void)closePopover {
    NSPopover *popover = _popover;
    _popover = nil;
    [popover close];
}
@end

@implementation PasswordAutofill {
    PasswordRequest *_request;
}

+ (PasswordAutofill *)shared {
    static PasswordAutofill *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [PasswordAutofill new]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationResigned)
        name:NSApplicationDidResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(close)
        name:BrookSettingsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(storeChanged)
        name:PasswordStoreDidChangeNotification object:nil];
    return self;
}

- (void)installInto:(WKUserContentController *)controller {
    NSString *path = [NSBundle.mainBundle pathForResource:@"password-autofill" ofType:@"js"];
    NSString *script = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!script) return;
    [controller addScriptMessageHandler:self contentWorld:PasswordWorld() name:@"brookPasswords"];
    [controller addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
        forMainFrameOnly:YES inContentWorld:PasswordWorld()]];
}

- (void)applicationResigned { if (_request.phase != PasswordRequestAuthenticating) [self close]; }
- (void)storeChanged { if (!PasswordStore.shared.isUnlocked) [self close]; }
- (void)finishRequest:(PasswordRequest *)request {
    if (_request != request) return;
    _request = nil;
    [request closePopover];
}
- (void)close { [self finishRequest:_request]; }
- (void)popoverDidClose:(NSNotification *)note {
    if (note.object == _request.popover) [self close];
}
- (void)navigationStartedForWebView:(WKWebView *)webView {
    if (_request.webView == webView && !_request.survivesNavigation) [self close];
}
- (void)pageChangedForWebView:(WKWebView *)webView {
    if (_request.webView == webView && ![_request.origin isEqualToString:[PasswordStore originForURLString:webView.URL.absoluteString]]) [self close];
}
- (void)dismissForWebView:(WKWebView *)webView { if (_request.webView == webView) [self close]; }

- (BOOL)canUseWebView:(WKWebView *)view origin:(NSString *)origin {
    if (view.window.attachedSheet || !view.window.isVisible || !view.window.isKeyWindow || ![origin isEqualToString:[PasswordStore originForURLString:view.URL.absoluteString]]) return NO;
    if ([view isKindOfClass:BrookWebView.class]) {
        BrowserTab *tab = ((BrookWebView *)view).tab;
        if (tab.state && tab.state.selectedTab != tab) return NO;
    }
    return YES;
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.isMainFrame || ![message.body isKindOfClass:NSDictionary.class]) return;
    WKSecurityOrigin *security = message.frameInfo.securityOrigin;
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = security.protocol;
    components.host = security.host;
    if (security.port) components.port = @(security.port);
    NSString *origin = [PasswordStore originForURLString:components.string];
    if (!origin || ![self canUseWebView:message.webView origin:origin]) return;
    NSDictionary *body = message.body;
    NSString *type = [body[@"type"] isKindOfClass:NSString.class] ? body[@"type"] : nil;
    if ([type isEqualToString:@"dismiss"]) { if (!_request.survivesNavigation) [self dismissForWebView:message.webView]; return; }
    if ([type isEqualToString:@"focus"] && Settings.autofillPasswords) {
        NSString *token = [body[@"token"] isKindOfClass:NSString.class] ? body[@"token"] : nil;
        if (token.length == 0 || token.length > 200) return;
        NSArray<SavedLogin *> *logins = [PasswordStore.shared loginsForPageURL:message.webView.URL];
        if (logins.count == 0) return;
        for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
            if (![body[key] isKindOfClass:NSNumber.class] || !std::isfinite([body[key] doubleValue])) return;
        }
        NSRect bounds = message.webView.bounds;
        CGFloat zoom = message.webView.pageZoom;
        NSRect rect = NSMakeRect([body[@"x"] doubleValue] * zoom, [body[@"y"] doubleValue] * zoom,
            [body[@"width"] doubleValue] * zoom, [body[@"height"] doubleValue] * zoom);
        if (!message.webView.isFlipped) rect.origin.y = NSHeight(bounds) - NSMaxY(rect);
        rect = NSIntersectionRect(rect, bounds);
        if (NSWidth(rect) < 8 || NSHeight(rect) < 8) return;
        [self close];
        PasswordRequest *request = [[PasswordRequest alloc] initWithWebView:message.webView origin:origin token:token phase:PasswordRequestSuggesting];
        _request = request;
        __weak PasswordAutofill *weakSelf = self;
        NSMutableArray<NSView *> *views = [NSMutableArray array];
        NSTextField *label = [NSTextField labelWithString:[NSString stringWithFormat:@"Passwords for %@", security.host]];
        label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        [views addObject:label];
        for (SavedLogin *login in logins) {
            NSButton *button = [Controls button:login.username.length ? login.username : @"Use saved password" action:^{ [weakSelf fillLogin:login request:request]; }];
            button.alignment = NSTextAlignmentLeft;
            button.accessibilityLabel = [NSString stringWithFormat:@"Fill password for %@ on %@", login.username.length ? login.username : @"saved login", login.host];
            [views addObject:button];
        }
        [views addObject:[Controls button:@"Manage Passwords…" action:^{
            PasswordAutofill *self = weakSelf;
            if (!self || self->_request != request) return;
            [self finishRequest:request];
            [SettingsWindowController.shared showPane:@"Passwords"];
        }]];
        [self showViews:views relativeToRect:rect request:request];
    } else if ([type isEqualToString:@"submit"] && Settings.offerToSavePasswords) {
        NSString *username = [body[@"username"] isKindOfClass:NSString.class] ? body[@"username"] : nil;
        NSString *password = [body[@"password"] isKindOfClass:NSString.class] ? body[@"password"] : nil;
        if (!username || username.length > 4096 || password.length == 0 || password.length > 16384 ||
            [PasswordStore.shared neverSavesHost:security.host] || !PasswordStore.shared.isAvailable) return;
        [self offerSaveForWebView:message.webView origin:origin username:username password:password];
    }
}

- (void)showViews:(NSArray<NSView *> *)views relativeToRect:(NSRect)rect request:(PasswordRequest *)request {
    if (_request != request) return;
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = stack;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    NSSize size = stack.fittingSize;
    size.width = std::clamp<CGFloat>(size.width, 240, 380);
    stack.frame = NSMakeRect(0, 0, size.width, size.height);
    NSViewController *content = [NSViewController new];
    content.view = scroll;
    request.popover = [NSPopover new];
    request.popover.delegate = self;
    request.popover.behavior = NSPopoverBehaviorSemitransient;
    request.popover.contentViewController = content;
    request.popover.contentSize = NSMakeSize(size.width, std::min<CGFloat>(size.height, 320));
    [request.popover showRelativeToRect:rect ofView:request.webView preferredEdge:NSRectEdgeMaxY];
}

- (void)fillLogin:(SavedLogin *)login request:(PasswordRequest *)request {
    if (_request != request || request.phase != PasswordRequestSuggesting) return;
    request.phase = PasswordRequestAuthenticating;
    [request closePopover];
    [PasswordStore.shared openPassword:login reason:@"fill this saved password" completion:^(NSString *password) {
        if (self->_request != request) return;
        if (!password || !Settings.autofillPasswords ||
            ![self canUseWebView:request.webView origin:request.origin] || ![login.origin isEqualToString:request.origin]) {
            [self finishRequest:request];
            return;
        }
        request.phase = PasswordRequestFilling;
        [request.webView callAsyncJavaScript:@"return globalThis.brookPasswordFill(token, username, password);"
            arguments:@{@"token": request.token, @"username": login.username, @"password": password}
            inFrame:nil inContentWorld:PasswordWorld() completionHandler:^(id result, NSError *error) {
                if (self->_request != request) return;
                if (!error && [result isEqual:@YES]) [PasswordStore.shared markUsed:login];
                [self finishRequest:request];
            }];
    }];
}

- (void)offerSaveForWebView:(WKWebView *)view origin:(NSString *)origin username:(NSString *)username password:(NSString *)password {
    [self close];
    PasswordRequest *request = [[PasswordRequest alloc] initWithWebView:view origin:origin token:nil phase:PasswordRequestComparing];
    _request = request;
    SavedLogin *existing = [PasswordStore.shared loginForOrigin:origin username:BrookTrimAll(username)];
    void (^show)(NSString *) = ^(NSString *current) {
        if (self->_request != request) return;
        if ([current isEqualToString:password] || !Settings.offerToSavePasswords || ![self canUseWebView:view origin:origin]) {
            [self finishRequest:request];
            return;
        }
        request.phase = PasswordRequestSaving;
        NSTextField *title = [NSTextField labelWithString:existing ? @"Update saved password?" : @"Save password?"];
        title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        NSTextField *site = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:@"%@\n%@", origin, username.length ? username : @"No username"]];
        [site.widthAnchor constraintLessThanOrEqualToConstant:340].active = YES;
        __weak PasswordAutofill *weakSelf = self;
        NSButton *save = [Controls button:existing ? @"Update Password" : @"Save Password" action:^{
            PasswordAutofill *self = weakSelf;
            if (!self || self->_request != request) return;
            if (!Settings.offerToSavePasswords || ![self canUseWebView:view origin:origin]) { [self finishRequest:request]; return; }
            NSError *error = nil;
            [PasswordStore.shared saveOrigin:origin username:username password:password source:@"Brook" error:&error];
            [self finishRequest:request];
            if (error) {
                NSAlert *alert = [NSAlert alertWithError:error];
                [alert beginSheetModalForWindow:view.window completionHandler:nil];
            }
        }];
        NSButton *later = [Controls button:@"Not Now" action:^{ [weakSelf finishRequest:request]; }];
        NSButton *never = [Controls button:@"Never for This Website" action:^{
            PasswordAutofill *self = weakSelf;
            if (!self || self->_request != request) return;
            [PasswordStore.shared setNeverSaves:YES host:BrookHost([NSURL URLWithString:origin])];
            [self finishRequest:request];
        }];
        [self showViews:@[title, site, save, later, never]
            relativeToRect:NSMakeRect(NSMidX(view.bounds), view.isFlipped ? 0 : NSHeight(view.bounds) - 1, 1, 1) request:request];
    };
    if (existing && PasswordStore.shared.isUnlocked) {
        [PasswordStore.shared openPassword:existing reason:@"compare the saved password" completion:show];
    } else show(nil);
}
@end
