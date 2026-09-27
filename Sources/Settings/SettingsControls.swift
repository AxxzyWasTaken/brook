import AppKit

// MARK: - Form building blocks

/// A two-column settings form (label on the right-aligned left column, control on the right),
/// laid out like System Settings / Safari's preference panes.
@MainActor
final class SettingsForm {
    let grid = NSGridView()
    private(set) var rowCount = 0

    init() {
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
    }

    @discardableResult
    func row(_ title: String, _ views: NSView...) -> NSGridRow {
        let label = NSTextField(labelWithString: title.isEmpty ? "" : title + ":")
        label.alignment = .right
        let right: NSView
        if views.count == 1 {
            right = views[0]
        } else {
            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            right = stack
        }
        let r = grid.addRow(with: [label, right])
        r.rowAlignment = .firstBaseline
        rowCount += 1
        return r
    }

    func note(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 360
        let r = grid.addRow(with: [NSGridCell.emptyContentView, label])
        r.topPadding = -4
    }

    func separator() {
        let r = grid.addRow(with: [NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        r.topPadding = 8
    }

    func finish() {
        guard grid.numberOfColumns == 2 else { return }
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
    }

    /// Wraps the form in a padded container view.
    func view(width: CGFloat = 620) -> NSView {
        finish()
        let v = NSView()
        v.addSubview(grid)
        // Centred (nudged left, like Safari's panes), but never closer than 24pt to an edge:
        // wide panes grow the window instead of clipping.
        let center = grid.centerXAnchor.constraint(equalTo: v.centerXAnchor, constant: -30)
        center.priority = .defaultHigh
        let minWidth = v.widthAnchor.constraint(equalToConstant: width)
        minWidth.priority = .defaultLow
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: v.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: v.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -24),
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: width),
            center, minWidth
        ])
        return v
    }
}

@MainActor
enum Controls {
    static func popup<E: Equatable>(_ values: [E], title: (E) -> String, selected: E,
                                                  onChange: @escaping (E) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        for v in values { p.addItem(withTitle: title(v)) }
        p.selectItem(at: values.firstIndex(of: selected) ?? 0)
        p.onAction { c in
            let i = (c as! NSPopUpButton).indexOfSelectedItem
            if values.indices.contains(i) { onChange(values[i]) }
        }
        return p
    }

    static func check(_ title: String, _ on: Bool, onChange: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = on ? .on : .off
        b.onAction { c in onChange((c as! NSButton).state == .on) }
        return b
    }

    /// Slider with a live value label.
    static func slider(min: Double, max: Double, value: Double, width: CGFloat = 220, ticks: Int = 0,
                       format: @escaping (Double) -> String, onChange: @escaping (Double) -> Void) -> NSView {
        let s = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        s.isContinuous = true
        if ticks > 1 {
            s.numberOfTickMarks = ticks
            s.allowsTickMarkValuesOnly = true
        }
        s.widthAnchor.constraint(equalToConstant: width).isActive = true
        let label = NSTextField(labelWithString: format(value))
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        s.onAction { c in
            let v = (c as! NSSlider).doubleValue
            label.stringValue = format(v)
            onChange(v)
        }
        let row = NSStackView(views: [s, label])
        row.spacing = 8
        return row
    }

    static func segmented<E: Equatable>(_ values: [E], title: (E) -> String, selected: E,
                                        onChange: @escaping (E) -> Void) -> NSSegmentedControl {
        let seg = NSSegmentedControl(labels: values.map(title), trackingMode: .selectOne, target: nil, action: nil)
        seg.selectedSegment = values.firstIndex(of: selected) ?? 0
        seg.onAction { c in
            let i = (c as! NSSegmentedControl).selectedSegment
            if values.indices.contains(i) { onChange(values[i]) }
        }
        return seg
    }

    static func button(_ title: String, action: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .push
        b.onAction { _ in action() }
        return b
    }

    /// Text field that commits when editing ends (return or focus change).
    static func field(_ value: String, placeholder: String, width: CGFloat = 260,
                      onCommit: @escaping (String) -> Void) -> NSTextField {
        let f = NSTextField(string: value)
        f.placeholderString = placeholder
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        f.onAction { c in onCommit((c as! NSTextField).stringValue.trimmingCharacters(in: .whitespaces)) }
        (f.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        return f
    }
}

/// Plain table with a scroll view and +/- buttons underneath, used by the list-style panes.
@MainActor
final class EditableList: NSObject {
    let table = NSTableView()
    let scroll = NSScrollView()
    let segment = NSSegmentedControl()
    let container = NSStackView()
    /// Shown over the table when it has no rows.
    let emptyLabel = NSTextField(labelWithString: "")
    var onAdd: (() -> Void)?
    var onRemove: ((Int) -> Void)?
    var extra: [NSView] = [] {
        didSet {
            buttonRow.arrangedSubviews.dropFirst().forEach { $0.removeFromSuperview() }
            extra.forEach { buttonRow.addArrangedSubview($0) }
        }
    }
    private let buttonRow = NSStackView()

    init(columns: [(id: String, title: String, width: CGFloat)], height: CGFloat = 220) {
        super.init()
        for c in columns {
            let col = NSTableColumn(identifier: .init(c.id))
            col.title = c.title
            col.width = c.width
            table.addTableColumn(col)
        }
        table.style = .fullWidth
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        // Overlay the empty message on the scroll view (above its clip view, so it's visible).
        scroll.addSubview(emptyLabel, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: 10)
        ])

        segment.segmentCount = 2
        segment.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: "Add"), forSegment: 0)
        segment.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove"), forSegment: 1)
        segment.trackingMode = .momentary
        segment.segmentStyle = .smallSquare
        segment.onAction { [weak self] c in
            guard let self else { return }
            if (c as! NSSegmentedControl).selectedSegment == 0 { self.onAdd?() }
            else if self.table.selectedRow >= 0 { self.onRemove?(self.table.selectedRow) }
        }
        buttonRow.addArrangedSubview(segment)
        buttonRow.spacing = 8

        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        container.addArrangedSubview(scroll)
        container.addArrangedSubview(buttonRow)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
    }

    /// Reloads the table and shows the empty message when there's nothing in it.
    func reload() {
        table.reloadData()
        emptyLabel.isHidden = table.numberOfRows > 0
    }
}

/// View controller whose content is rebuilt from scratch, used for panes whose rows depend on data.
class RebuildingPane: NSViewController {
    private var observer: NSObjectProtocol?
    /// Settings keys that should rebuild this pane when changed elsewhere ("*" for import/reset).
    var rebuildKeys: Set<String> = ["*"]

    override func loadView() {
        view = NSView()
        rebuild()
        observer = NotificationCenter.default.addObserver(forName: .brookSettingsDidChange, object: nil, queue: .main) { [weak self] note in
            let key = note.userInfo?["key"] as? String ?? "*"
            MainActor.assumeIsolated {
                guard let self, self.rebuildKeys.contains(key) else { return }
                self.rebuild()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func makeContent() -> NSView { NSView() }

    func rebuild() {
        view.subviews.forEach { $0.removeFromSuperview() }
        let content = makeContent()
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        content.pinEdges(to: view)
        preferredContentSize = content.fittingSize
    }
}
