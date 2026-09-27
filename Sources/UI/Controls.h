#import <AppKit/AppKit.h>

/// Pasteboard type "app.brook.tab": a dragged tab's UUID string.
FOUNDATION_EXPORT NSPasteboardType const BrookTabPasteboardType;

/// A lightweight clickable view with hover and press states, drawn with a single layer.
/// Subclasses may override -updateLayer and -hoverChanged.
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
/// Runs onClick, then sends the control's action (if any) to its target.
- (void)fire;
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
@end
