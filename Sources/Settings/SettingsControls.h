#import <AppKit/AppKit.h>
#include <vector>

// MARK: - Form building blocks

/// A two-column settings form (label on the right-aligned left column, control on the right),
/// laid out like System Settings / Safari's preference panes.
@interface SettingsForm : NSObject
@property (readonly) NSGridView *grid;
@property (readonly) NSInteger rowCount;
/// One view goes straight in; several are stacked vertically.
/// title "" leaves the label empty (otherwise a ":" is appended).
- (NSGridRow *)row:(NSString *)title views:(NSArray<NSView *> *)views;
- (NSGridRow *)row:(NSString *)title view:(NSView *)view;
/// Small grey explanatory text under the previous row.
- (void)note:(NSString *)text;
- (void)separator;
/// Sets column placement (idempotent). -view calls it.
- (void)finish;
/// Wraps the form in a padded container view. Default width 620.
- (NSView *)view;
- (NSView *)viewWithWidth:(CGFloat)width;
@end

/// Factory for the standard settings controls. Popups and segmented controls
/// are index-based: pass titles in value order and map the index back (Settings enums run 0..<count).
@interface Controls : NSObject
+ (NSPopUpButton *)popupWithTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)selected
                          onChange:(void (^)(NSInteger index))onChange;
+ (NSButton *)check:(NSString *)title on:(BOOL)on onChange:(void (^)(BOOL on))onChange;
/// Slider with a live value label. Typical: width 220, ticks 0.
+ (NSView *)sliderWithMin:(double)min max:(double)max value:(double)value width:(CGFloat)width ticks:(NSInteger)ticks
                   format:(NSString * (^)(double value))format onChange:(void (^)(double value))onChange;
+ (NSSegmentedControl *)segmentedWithTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)selected
                                   onChange:(void (^)(NSInteger index))onChange;
+ (NSButton *)button:(NSString *)title action:(void (^)(void))action;
/// Text field that commits (trimmed) when editing ends (return or focus change). Typical width 260.
+ (NSTextField *)field:(NSString *)value placeholder:(NSString *)placeholder width:(CGFloat)width
              onCommit:(void (^)(NSString *value))onCommit;
@end

/// One EditableList column: identifier, title, width.
struct EditableListColumn {
    __strong NSString *identifier;
    __strong NSString *title;
    CGFloat width;
};

/// Plain table with a scroll view and +/- buttons underneath, used by the list-style panes.
/// Set table.dataSource / table.delegate yourself.
@interface EditableList : NSObject
/// Typical height 220.
- (instancetype)initWithColumns:(const std::vector<EditableListColumn> &)columns height:(CGFloat)height NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (readonly) NSTableView *table;
@property (readonly) NSScrollView *scroll;
@property (readonly) NSSegmentedControl *segment;
/// Put this in the form.
@property (readonly) NSStackView *container;
/// Shown over the table when it has no rows.
@property (readonly) NSTextField *emptyLabel;
@property (copy) void (^onAdd)(void);
/// Called with the selected row when "-" is clicked (only if a row is selected).
@property (copy) void (^onRemove)(NSInteger row);
/// Extra controls after the +/- buttons; setting replaces the previous ones.
@property (nonatomic, copy) NSArray<NSView *> *extra;
/// Reloads the table and shows the empty message when there's nothing in it.
- (void)reload;
@end

/// View controller whose content is rebuilt from scratch, used for panes whose rows depend on data.
/// Subclasses override -makeContent.
@interface RebuildingPane : NSViewController
/// Settings keys that should rebuild this pane when changed elsewhere ("*" for import/reset). Default {"*"}.
@property (copy) NSSet<NSString *> *rebuildKeys;
/// Override point. Default returns an empty NSView.
- (NSView *)makeContent;
- (void)rebuild;
@end
