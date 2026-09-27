#import <AppKit/AppKit.h>

/// The fields of the New/Edit Space sheet.
struct SpaceDraft {
    __strong NSString *name;
    __strong NSString *colorHex;
    __strong NSString *searchEngineID;   // nil = default engine
    bool separateProfile;
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
