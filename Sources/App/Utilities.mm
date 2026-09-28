#import "Brook.h"

@implementation AppPaths

static NSURL *BrookMakeDir(NSURL *dir) {
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

+ (NSURL *)support {
    static NSURL *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
        dir = BrookMakeDir([base URLByAppendingPathComponent:@"Brook" isDirectory:YES]);
    });
    return dir;
}

+ (NSURL *)caches {
    static NSURL *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
        dir = BrookMakeDir([base URLByAppendingPathComponent:@"Brook" isDirectory:YES]);
    });
    return dir;
}

+ (NSURL *)sub:(NSString *)name in:(NSURL *)base {
    return BrookMakeDir([base URLByAppendingPathComponent:name isDirectory:YES]);
}

+ (NSURL *)sub:(NSString *)name {
    return [self sub:name in:self.support];
}

@end

// MARK: - Small helpers

BOOL BrookIsDark(NSAppearance *appearance) {
    return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]]
               isEqualToString:NSAppearanceNameDarkAqua];
}

BOOL BrookIncreaseContrast(NSAppearance *appearance) {
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast) return YES;
    NSString *match = [appearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
        NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]];
    return [match isEqualToString:NSAppearanceNameAccessibilityHighContrastAqua] ||
           [match isEqualToString:NSAppearanceNameAccessibilityHighContrastDarkAqua];
}

BOOL BrookReduceMotion(void) {
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

static dispatch_queue_t BrookWriteQueue() {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("app.brook.writes",
                                  dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    });
    return q;
}

void BrookWriteJSONInBackground(id object, NSJSONWritingOptions options, NSURL *url) {
    if (!object || !url) return;
    dispatch_async(BrookWriteQueue(), ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:object options:options error:nil];
        if (data) [data writeToURL:url options:NSDataWritingAtomic error:nil];
    });
}

void BrookFinishBackgroundWrites(void) {
    dispatch_sync(BrookWriteQueue(), ^{});
}

NSFont *BrookUIFont(CGFloat size, NSFontWeight weight) {
    NSFont *base = [NSFont systemFontOfSize:size weight:weight];
    NSFontDescriptorSystemDesign design = nil;
    switch (Settings.uiFont) {
        case UIFontStyleRounded: design = NSFontDescriptorSystemDesignRounded; break;
        case UIFontStyleSerif: design = NSFontDescriptorSystemDesignSerif; break;
        case UIFontStyleMono: design = NSFontDescriptorSystemDesignMonospaced; break;
        default: return base;
    }
    NSFontDescriptor *d = [base.fontDescriptor fontDescriptorWithDesign:design];
    return (d ? [NSFont fontWithDescriptor:d size:size] : nil) ?: base;
}

NSColor *BrookAccentColor(void) {
    switch (Settings.accentSource) {
        case AccentSourceSystem: return NSColor.controlAccentColor;
        case AccentSourceCustom: return [NSColor brook_colorWithHex:Settings.accentColorHex] ?: NSColor.controlAccentColor;
        default: return BrowserState.shared.currentSpace.color ?: NSColor.controlAccentColor;
    }
}

static const std::pair<unichar, NSEventModifierFlags> kShortcutMods[] = {
    {0x2303, NSEventModifierFlagControl}, {0x2325, NSEventModifierFlagOption},
    {0x21E7, NSEventModifierFlagShift}, {0x2318, NSEventModifierFlagCommand},
};

NSString *BrookShortcutString(NSString *key, NSEventModifierFlags mods) {
    if (key.length == 0) return @"";
    NSMutableString *s = [NSMutableString string];
    for (auto [symbol, flag] : kShortcutMods) if (mods & flag) [s appendFormat:@"%C", symbol];
    [s appendString:key.lowercaseString];
    return s;
}

BOOL BrookParseShortcut(NSString *shortcut, NSString **key, NSEventModifierFlags *mods) {
    *key = nil;
    *mods = 0;
    NSUInteger i = 0;
    for (; i < shortcut.length; i++) {
        unichar c = [shortcut characterAtIndex:i];
        NSEventModifierFlags flag = 0;
        for (auto [symbol, f] : kShortcutMods) if (c == symbol) flag = f;
        if (!flag || i == shortcut.length - 1) break;   // the last character is always the key
        *mods |= flag;
    }
    if (i >= shortcut.length) return NO;
    *key = [shortcut substringFromIndex:i];
    return YES;
}

NSString *BrookShortcutDisplay(NSString *shortcut) {
    NSString *key = nil;
    NSEventModifierFlags mods = 0;
    if (!BrookParseShortcut(shortcut, &key, &mods)) return @"";
    NSMutableString *s = [NSMutableString string];
    for (auto [symbol, flag] : kShortcutMods) if (mods & flag) [s appendFormat:@"%C", symbol];
    unichar c = [key characterAtIndex:0];
    NSString *name = nil;
    switch (c) {
        case NSLeftArrowFunctionKey: name = @"←"; break;
        case NSRightArrowFunctionKey: name = @"→"; break;
        case NSUpArrowFunctionKey: name = @"↑"; break;
        case NSDownArrowFunctionKey: name = @"↓"; break;
        case '\t': name = @"⇥"; break;
        case '\r': name = @"↩"; break;
        case ' ': name = @"Space"; break;
        case NSBackspaceCharacter: case NSDeleteCharacter: name = @"⌫"; break;
        case 0x1b: name = @"⎋"; break;
        default: name = key.uppercaseString;
    }
    [s appendString:name];
    return s;
}

NSString *BrookTrim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

NSString *BrookTrimAll(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *BrookHost(NSURL *url) {
    if (!url) return nil;
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *h = c.percentEncodedHost;
    return h.length ? h : nil;
}

// MARK: - Relative dates (Date.RelativeFormatStyle rounding, named presentation)

namespace {

// Largest first, like ICURelativeDateFormatter.sortedAllowedComponents.
constexpr NSCalendarUnit kRelativeUnits[] = {
    NSCalendarUnitYear, NSCalendarUnitMonth, NSCalendarUnitWeekOfMonth, NSCalendarUnitDay,
    NSCalendarUnitHour, NSCalendarUnitMinute, NSCalendarUnitSecond,
};
constexpr NSCalendarUnit kAllRelativeUnits = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfMonth |
    NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;

struct UnitValue {
    NSCalendarUnit unit;
    NSInteger value;
};

NSInteger ValueFor(NSDateComponents *c, NSCalendarUnit unit) {
    NSInteger v = [c valueForComponent:unit];
    return v == NSDateComponentUndefined ? 0 : v;
}

std::optional<UnitValue> FirstNonZero(NSDateComponents *c) {
    for (NSCalendarUnit u : kRelativeUnits) {
        if (NSInteger v = ValueFor(c, u)) return UnitValue{u, v};
    }
    return std::nullopt;
}

/// Index in kRelativeUnits; smaller index = larger unit.
size_t Rank(NSCalendarUnit unit) {
    for (size_t i = 0; i < std::size(kRelativeUnits); i++) if (kRelativeUnits[i] == unit) return i;
    return std::size(kRelativeUnits);
}

std::optional<UnitValue> Rounded(NSDate *ref, NSDate *dest, NSCalendar *cal, NSCalendarUnit largestAllowed) {
    NSCalendarUnit set = NSCalendarUnitNanosecond;
    for (NSCalendarUnit u : kRelativeUnits) if (Rank(u) >= Rank(largestAllowed)) set |= u;
    NSDateComponents *c = [cal components:set fromDate:ref toDate:dest options:0];
    NSInteger ns = c.nanosecond;
    if (c.second != NSDateComponentUndefined && std::llabs(ns) >= 500'000'000) c.second += ns > 0 ? 1 : -1;

    auto nonZero = FirstNonZero(c);
    NSCalendarUnit largest = nonZero ? nonZero->unit : NSCalendarUnitSecond;

    NSCalendarUnit smaller = NSCalendarUnitNanosecond;
    NSInteger smallerValue = ns;
    if (Rank(largest) + 1 < std::size(kRelativeUnits)) {
        smaller = kRelativeUnits[Rank(largest) + 1];
        smallerValue = ValueFor(c, smaller);
    }
    UnitValue rounded{largest, ValueFor(c, largest)};
    NSRange range = [cal rangeOfUnit:smaller inUnit:largest forDate:dest];
    if (range.location != NSNotFound && std::llabs(smallerValue) * 2 >= (long long)range.length) {
        rounded.value += smallerValue > 0 ? 1 : -1;
    }
    NSDate *shifted = [cal dateByAddingUnit:largest value:-rounded.value toDate:dest options:0];
    if (!shifted) return std::nullopt;
    // Rounding may have carried into the next larger unit.
    auto recomputed = FirstNonZero([cal components:kAllRelativeUnits fromDate:shifted toDate:dest options:0]);
    if (recomputed && recomputed->unit != rounded.unit) return recomputed;
    return rounded;
}

std::optional<UnitValue> Aligned(NSCalendarUnit unit, NSDate *dest, NSDate *ref, NSCalendar *cal) {
    NSDate *start = nil;
    NSTimeInterval interval = 0;
    if (![cal rangeOfUnit:unit startDate:&start interval:&interval forDate:ref]) return std::nullopt;
    NSDate *end = [start dateByAddingTimeInterval:interval - 1];
    NSDate *from = [ref compare:dest] == NSOrderedAscending ? start : end;
    return FirstNonZero([cal components:kAllRelativeUnits fromDate:from toDate:dest options:0]);
}

NSRelativeDateTimeFormatterUnitsStyle const kUnitsStyle = NSRelativeDateTimeFormatterUnitsStyleFull;

}  // namespace

NSString *BrookRelativeNamed(NSDate *dest, NSDate *reference) {
    if (!dest) return @"";
    NSCalendar *cal = NSCalendar.autoupdatingCurrentCalendar;
    // Date is more precise than a second, the smallest supported unit: round to seconds.
    NSDate *ref = [dest dateByAddingTimeInterval:std::round([reference timeIntervalSinceDate:dest])];
    NSDateComponents *c = [cal components:kAllRelativeUnits fromDate:ref toDate:dest options:0];
    UnitValue largest = FirstNonZero(c).value_or(UnitValue{NSCalendarUnitSecond, 0});
    std::optional<UnitValue> result;
    if (largest.unit == NSCalendarUnitHour || largest.unit == NSCalendarUnitMinute || largest.unit == NSCalendarUnitSecond) {
        result = Rounded(ref, dest, cal, largest.unit);
    } else {
        result = Aligned(largest.unit, dest, ref, cal);
    }
    UnitValue r = result.value_or(largest);

    NSDateComponents *one = [NSDateComponents new];
    [one setValue:r.value forComponent:r.unit];
    NSRelativeDateTimeFormatter *fmt = [NSRelativeDateTimeFormatter new];
    fmt.dateTimeStyle = NSRelativeDateTimeFormatterStyleNamed;
    fmt.unitsStyle = kUnitsStyle;
    fmt.calendar = cal;
    return [fmt localizedStringFromDateComponents:one];
}

// MARK: - URL input

@implementation URLParser

static BOOL BrookMatches(NSString *s, NSString *pattern) {
    return [s rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

+ (NSURL *)urlFromInput:(NSString *)input {
    NSString *s = BrookTrimAll(input);
    if (s.length == 0 || [s containsString:@" "]) return nil;
    NSString *lower = s.lowercaseString;
    for (NSString *scheme in @[@"http://", @"https://", @"file://", @"about:", @"data:", @"webkit-extension://"]) {
        if ([lower hasPrefix:scheme]) return [NSURL URLWithString:s];
    }
    if ([lower hasPrefix:@"localhost"] ||
        BrookMatches(s, @"^\\d{1,3}(\\.\\d{1,3}){3}(:\\d+)?([/?#].*)?$")) {
        return [NSURL URLWithString:[@"http://" stringByAppendingString:s]];
    }
    if (BrookMatches(s, @"^[^\\s/:?#@]+\\.[a-zA-Z]{2,63}\\.?(:\\d+)?([/?#].*)?$")) {
        return [NSURL URLWithString:[@"https://" stringByAppendingString:s]];
    }
    return nil;
}

+ (NSURL *)destinationForInput:(NSString *)input {
    return [self urlFromInput:input] ?: [SearchEngines searchURLForInput:BrookTrimAll(input)];
}

+ (NSString *)display:(NSURL *)url {
    if (!url) return @"";
    NSString *host = url.host;
    if (host.length) return [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
    return url.absoluteString ?: @"";
}

@end

// MARK: - Colors

@implementation NSColor (Brook)

+ (NSColor *)brook_colorWithHex:(NSString *)hex {
    NSString *s = BrookTrim(hex);
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length != 6) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    unsigned int v = 0;
    if (![scanner scanHexInt:&v] || !scanner.isAtEnd) return nil;
    return [NSColor colorWithSRGBRed:((v >> 16) & 0xFF) / 255.0
                               green:((v >> 8) & 0xFF) / 255.0
                                blue:(v & 0xFF) / 255.0
                               alpha:1];
}

+ (NSColor *)brook_dynamicLight:(NSColor *)light dark:(NSColor *)dark {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        return BrookIsDark(appearance) ? dark : light;
    }];
}

- (NSString *)brook_hexString {
    NSColor *c = [self colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: self;
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)lround(c.redComponent * 255), (int)lround(c.greenComponent * 255), (int)lround(c.blueComponent * 255)];
}

@end

@implementation Palette

+ (NSArray<NSArray<NSString *> *> *)spaceColors {
    static NSArray *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @[@[@"Violet", @"#7B61FF"], @[@"Blue", @"#2F80ED"], @[@"Teal", @"#1AAE9F"], @[@"Green", @"#34C759"],
                   @[@"Orange", @"#FF8A34"], @[@"Red", @"#FF4D5E"], @[@"Pink", @"#FF5DA2"], @[@"Graphite", @"#8E8E93"]];
    });
    return colors;
}

NSColor *BrookFill(CGFloat lightWhite, CGFloat lightAlpha, CGFloat darkWhite, CGFloat darkAlpha) {
    // Increase Contrast roughly doubles a translucent fill or hairline, capped at half opacity.
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL dark = BrookIsDark(appearance);
        CGFloat a = dark ? darkAlpha : lightAlpha;
        if (a < 0.5 && BrookIncreaseContrast(appearance)) a = std::min<CGFloat>(0.5, a * 2.2);
        return [NSColor colorWithWhite:dark ? darkWhite : lightWhite alpha:a];
    }];
}

#define BROOK_DYNAMIC(NAME, LW, LA, DW, DA)                                                          \
    +(NSColor *)NAME {                                                                               \
        static NSColor *c;                                                                           \
        static dispatch_once_t once;                                                                 \
        dispatch_once(&once, ^{ c = BrookFill(LW, LA, DW, DA); });                                   \
        return c;                                                                                    \
    }

BROOK_DYNAMIC(rowSelected, 1, 0.78, 1, 0.16)
BROOK_DYNAMIC(rowHover, 0, 0.05, 1, 0.07)
BROOK_DYNAMIC(pill, 0, 0.055, 1, 0.08)
BROOK_DYNAMIC(well, 0, 0.055, 0, 0.22)
BROOK_DYNAMIC(wellHover, 0, 0.09, 0, 0.3)
BROOK_DYNAMIC(tile, 1, 0.45, 1, 0.07)
BROOK_DYNAMIC(divider, 0, 0.1, 1, 0.1)

#undef BROOK_DYNAMIC

@end

// MARK: - Views and images

@implementation NSView (Brook)

- (CGColorRef)brook_cg:(NSColor *)color {
    __block CGColorRef result = CGColorRetain(color.CGColor);
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        CGColorRelease(result);
        result = CGColorRetain(color.CGColor);
    }];
    return (CGColorRef)CFAutorelease(result);
}

- (void)brook_pinEdgesTo:(NSView *)other {
    [self brook_pinEdgesTo:other inset:0];
}

- (void)brook_pinEdgesTo:(NSView *)other inset:(CGFloat)inset {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.leadingAnchor constraintEqualToAnchor:other.leadingAnchor constant:inset],
        [self.trailingAnchor constraintEqualToAnchor:other.trailingAnchor constant:-inset],
        [self.topAnchor constraintEqualToAnchor:other.topAnchor constant:inset],
        [self.bottomAnchor constraintEqualToAnchor:other.bottomAnchor constant:-inset],
    ]];
}

@end

@implementation NSImage (Brook)

+ (NSImage *)brook_symbol:(NSString *)name size:(CGFloat)size {
    return [self brook_symbol:name size:size weight:NSFontWeightMedium];
}

+ (NSImage *)brook_symbol:(NSString *)name size:(CGFloat)size weight:(NSFontWeight)weight {
    NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    return [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:cfg];
}

@end

// MARK: - Debouncer

@implementation Debouncer {
    NSTimeInterval _delay;
    dispatch_block_t _work;
}

- (instancetype)initWithDelay:(NSTimeInterval)delay {
    if ((self = [super init])) _delay = delay;
    return self;
}

- (void)call:(dispatch_block_t)block {
    if (_work) dispatch_block_cancel(_work);
    dispatch_block_t item = dispatch_block_create((dispatch_block_flags_t)0, block);
    _work = item;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_delay * NSEC_PER_SEC)), dispatch_get_main_queue(), item);
}

- (void)flush:(dispatch_block_t)block {
    if (_work) dispatch_block_cancel(_work);
    _work = nil;
    block();
}

@end
