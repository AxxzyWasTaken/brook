#import <WebKit/WebKit.h>

@interface PasswordAutofill : NSObject <WKScriptMessageHandler, NSPopoverDelegate>
@property (class, readonly) PasswordAutofill *shared;
- (void)installInto:(WKUserContentController *)controller;
- (void)navigationStartedForWebView:(WKWebView *)webView;
- (void)pageChangedForWebView:(WKWebView *)webView;
- (void)dismissForWebView:(WKWebView *)webView;
@end
