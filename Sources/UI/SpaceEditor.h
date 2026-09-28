#import <AppKit/AppKit.h>

/// The fields of the New/Edit Space sheet.
struct SpaceDraft {
    __strong NSString *name;
    __strong NSString *colorHex;
    __strong NSString *searchEngineID;   // nil = default engine
    bool separateProfile;
    /// Overrides of the global settings; -1 = use the global one.
    NSInteger theme = -1;           // ThemeMode
    NSInteger tabLayout = -1;       // TabLayout
    NSInteger pinnedClose = -1;     // PinnedCloseBehavior
    NSInteger archiveHours = -1;    // 0 = never
};

/// Accessory view for the New/Edit Space sheet. (SwatchButton / RainbowSwatch stay private to SpaceEditor.mm.)
@interface SpaceEditorView : NSView
- (instancetype)initWithDraft:(SpaceDraft)draft NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@property (readonly) NSTextField *nameField;
/// The edited values (name trimmed).
@property (nonatomic, readonly) SpaceDraft draft;
@end
