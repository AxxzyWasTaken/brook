#import <AppKit/AppKit.h>

/// Folders under ~/Library for Brook's own files. Created on first access.
@interface AppPaths : NSObject
@property (class, readonly) NSURL *support;   // ~/Library/Application Support/Brook
@property (class, readonly) NSURL *caches;    // ~/Library/Caches/Brook
/// A subfolder of `base`, created if missing.
+ (NSURL *)sub:(NSString *)name in:(NSURL *)base;
/// A subfolder of `support`, created if missing.
+ (NSURL *)sub:(NSString *)name;
@end

/// Turns command-bar input into URLs.
@interface URLParser : NSObject
/// The URL the input names, or nil when it looks like a search.
+ (NSURL *)urlFromInput:(NSString *)input;
/// A URL for the input, falling back to a search with the current engine.
+ (NSURL *)destinationForInput:(NSString *)input;
/// Short, human friendly form of a URL for the address pill ("" for nil).
+ (NSString *)display:(NSURL *)url;
@end

@interface NSColor (Brook)
/// "#RRGGBB" (the # is optional). nil if invalid.
+ (NSColor *)brook_colorWithHex:(NSString *)hex;
+ (NSColor *)brook_dynamicLight:(NSColor *)light dark:(NSColor *)dark;
/// "#RRGGBB" in sRGB.
@property (readonly) NSString *brook_hexString;
@end

@interface Palette : NSObject
/// Preset space colours, each @[name, hex].
@property (class, readonly) NSArray<NSArray<NSString *> *> *spaceColors;
@property (class, readonly) NSColor *rowSelected;
@property (class, readonly) NSColor *rowHover;
@property (class, readonly) NSColor *pill;
@property (class, readonly) NSColor *tile;
@property (class, readonly) NSColor *divider;
@end

@interface NSView (Brook)
/// Resolves a (dynamic) color to a CGColor using this view's appearance.
- (CGColorRef)brook_cg:(NSColor *)color;
/// Turns off autoresizing-mask translation and pins all four edges to `other`.
- (void)brook_pinEdgesTo:(NSView *)other;
- (void)brook_pinEdgesTo:(NSView *)other inset:(CGFloat)inset;
@end

@interface NSImage (Brook)
/// SF Symbol at a point size, medium weight.
+ (NSImage *)brook_symbol:(NSString *)name size:(CGFloat)size;
+ (NSImage *)brook_symbol:(NSString *)name size:(CGFloat)size weight:(NSFontWeight)weight;
@end

/// Coalesces rapid calls into one, on the main queue.
@interface Debouncer : NSObject
- (instancetype)initWithDelay:(NSTimeInterval)delay;
/// Cancels any pending block and schedules this one after the delay.
- (void)call:(dispatch_block_t)block;
/// Cancels any pending block and runs this one now.
- (void)flush:(dispatch_block_t)block;
@end

FOUNDATION_EXPORT BOOL BrookIsDark(NSAppearance *appearance);
/// Trims spaces and tabs.
FOUNDATION_EXPORT NSString *BrookTrim(NSString *s);
/// Trims whitespace and newlines.
FOUNDATION_EXPORT NSString *BrookTrimAll(NSString *s);
/// Percent-encoded host, nil if none or empty.
FOUNDATION_EXPORT NSString *BrookHost(NSURL *url);
/// Named relative date ("1 hour ago", "yesterday", "last week"). Rounds like Foundation's
/// Date.RelativeFormatStyle, which NSRelativeDateTimeFormatter does not.
FOUNDATION_EXPORT NSString *BrookRelativeNamed(NSDate *date, NSDate *reference);
