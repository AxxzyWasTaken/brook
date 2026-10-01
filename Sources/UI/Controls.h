#import <AppKit/AppKit.h>

/// Pasteboard type "app.brook.tab": a dragged tab's UUID string.
FOUNDATION_EXPORT NSPasteboardType const BrookTabPasteboardType;

/// A lightweight clickable view with hover and press states, drawn with a single layer.
/// Subclasses may override -updateLayer and -hoverChanged.
/// With an onClick or action it's an accessibility button (labelled from its tooltip, minus the
/// shortcut) and, with Full Keyboard Access on, a key view that Space and Return press. Subclasses
/// override the accessibility getters for another role, label or value.
@interface HoverControl : NSControl
@property (copy) void (^onClick)(void);
@property (nonatomic) CGFloat cornerRadius;          // default 8; redraws
@property (strong) NSColor *hoverColor;              // default Palette.rowHover
@property (nonatomic, strong) NSColor *baseColor;    // default clear; redraws
@property (nonatomic) BOOL isHighlightedState;       // redraws
@property (strong) NSColor *highlightColor;          // default Palette.rowSelected
@property (nonatomic, readonly) BOOL isHovering;
@property (nonatomic) BOOL isPressed;                // redraws
/// Called whenever isHovering changes. Default does nothing.
- (void)hoverChanged;
- (void)resetInteractionState;
/// Runs onClick, then sends the control's action (if any) to its target.
- (void)fire;
/// Pressing it does something (default: has an onClick or action). Only these are accessibility
/// elements and key views.
@property (readonly) BOOL isActionable;
@end

/// An SF Symbol button, Arc-style: no border, soft hover background.
@interface IconButton : HoverControl
@property (readonly) NSImageView *imageView;
/// Resting tint; hovering always brightens to the label colour. Default secondaryLabelColor.
@property (nonatomic, strong) NSColor *tint;
/// The short initializer uses size 14, dimension 28.
- (instancetype)initWithSymbol:(NSString *)symbol size:(CGFloat)size tooltip:(NSString *)tooltip
                     dimension:(CGFloat)dimension onClick:(void (^)(void))onClick;
/// size 14, dimension 28.
- (instancetype)initWithSymbol:(NSString *)symbol tooltip:(NSString *)tooltip onClick:(void (^)(void))onClick;
/// size 14.
- (void)setSymbol:(NSString *)name;
- (void)setSymbol:(NSString *)name size:(CGFloat)size;
@end

/// Small rounded label that floats over the page for a moment.
@interface ToastView : NSView
- (void)showText:(NSString *)text;
/// Shown until set to nil (a mode's instructions, e.g. while picking things to hide); a showText passes over it.
@property (nonatomic, copy) NSString *hint;
@end
