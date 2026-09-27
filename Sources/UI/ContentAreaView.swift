import AppKit
import WebKit

/// The rounded "card" that hosts the current page.
@MainActor
final class ContentAreaView: NSView {
    private let clip = NSView()
    private let progress = CALayer()
    private let empty = EmptyStateView()
    private let errorView = ErrorView()
    let findBar = FindBar()
    let toast = ToastView()
    private(set) weak var webView: WKWebView?
    private weak var tab: BrowserTab?
    var accentColor: NSColor = .controlAccentColor { didSet { progress.backgroundColor = accentColor.cgColor; empty.accent = accentColor } }
    var cornerRadius: CGFloat = 12 {
        didSet {
            clip.layer?.cornerRadius = cornerRadius
            // Edge-to-edge (no rounding) drops the card border and shadow too.
            clip.layer?.borderWidth = cornerRadius == 0 ? 0 : 0.5
            layer?.shadowOpacity = cornerRadius == 0 ? 0 : shadowStrength
            needsLayout = true
        }
    }
    private var shadowStrength: Float = 0.14

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        clip.wantsLayer = true
        clip.layer?.cornerRadius = 12
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.layer?.borderWidth = 0.5
        addSubview(clip)
        clip.pinEdges(to: self)

        empty.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(empty)
        empty.pinEdges(to: clip)

        errorView.isHidden = true
        clip.addSubview(errorView)
        errorView.pinEdges(to: clip)

        progress.backgroundColor = accentColor.cgColor
        progress.opacity = 0
        progress.anchorPoint = .zero
        clip.layer?.addSublayer(progress)

        findBar.isHidden = true
        findBar.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(findBar)
        toast.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(toast)
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: clip.topAnchor, constant: 10),
            findBar.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -12),
            toast.centerXAnchor.constraint(equalTo: clip.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: clip.bottomAnchor, constant: -18)
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let r = min(cornerRadius, bounds.width / 2, bounds.height / 2)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        updateProgressFrame(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        clip.layer?.backgroundColor = cg(.textBackgroundColor)
        clip.layer?.borderColor = cg(NSColor.dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.1)))
        shadowStrength = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.35 : 0.14
        layer?.shadowOpacity = cornerRadius == 0 ? 0 : shadowStrength
    }

    // MARK: Showing tabs

    func show(_ tab: BrowserTab?, spaceName: String) {
        self.tab = tab
        if let wv = webView, wv !== tab?.webView { wv.removeFromSuperview() }
        empty.spaceName = spaceName
        guard let tab else {
            webView = nil
            empty.isHidden = false
            errorView.isHidden = true
            progress.opacity = 0
            findBar.isHidden = true
            return
        }
        empty.isHidden = true
        let wv = tab.materialize()
        if wv.superview !== clip {
            wv.frame = clip.bounds
            wv.autoresizingMask = [.width, .height]
            clip.addSubview(wv, positioned: .below, relativeTo: errorView)
        }
        webView = wv
        updateError()
        updateProgress()
        if !findBar.isHidden { findBar.webView = wv; findBar.search(forward: true) }
    }

    func tabChanged(_ tab: BrowserTab, change: TabChange) {
        guard tab === self.tab else { return }
        if change.contains(.progress) || change.contains(.loading) { updateProgress() }
        if change.contains(.error) { updateError() }
        if change.contains(.loaded) && tab.webView !== webView { show(tab, spaceName: empty.spaceName) }
    }

    private func updateError() {
        guard let tab, let message = tab.loadError else { errorView.isHidden = true; return }
        errorView.configure(message: message, url: tab.url) { [weak tab] in tab?.reload() }
        errorView.isHidden = false
    }

    private var lastProgress: Double = 0

    private func updateProgress() {
        guard let tab else { return }
        let p = tab.isLoading ? max(0.08, tab.progress) : 1
        if tab.isLoading {
            progress.opacity = 1
            if p < lastProgress { lastProgress = 0 }
            lastProgress = p
            updateProgressFrame(animated: true)
        } else if lastProgress > 0 {
            lastProgress = 1
            updateProgressFrame(animated: true)
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            progress.opacity = 0
            CATransaction.commit()
            lastProgress = 0
        }
    }

    private func updateProgressFrame(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.2)
        let h: CGFloat = 2.5
        progress.frame = CGRect(x: 0, y: clip.bounds.height - h, width: clip.bounds.width * CGFloat(lastProgress), height: h)
        CATransaction.commit()
    }

    // MARK: Find

    func showFind() {
        findBar.webView = webView
        findBar.isHidden = false
        findBar.focus()
    }
}

// MARK: - Empty state

final class EmptyStateView: NSView {
    private let title = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "Press ⌘T to search or open a site")
    var accent: NSColor = .controlAccentColor { didSet { needsLayout = true } }
    var spaceName: String = "" { didSet { title.stringValue = spaceName } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .labelColor
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        (window?.windowController as? BrowserWindowController)?.showCommandBar(editing: false)
    }
}

// MARK: - Load error

final class ErrorView: NSView {
    private let title = NSTextField(labelWithString: "This page couldn’t load")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let retry = NSButton(title: "Try Again", target: nil, action: nil)
    private var onRetry: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.preferredMaxLayoutWidth = 420
        retry.bezelStyle = .glass
        retry.controlSize = .large
        retry.target = self
        retry.action = #selector(retryTapped)
        let icon = NSImageView(image: NSImage.symbol("wifi.exclamationmark", size: 34, weight: .regular) ?? NSImage())
        icon.contentTintColor = .tertiaryLabelColor
        let stack = NSStackView(views: [icon, title, detail, retry])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(18, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 440)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.backgroundColor = cg(.textBackgroundColor)
    }

    func configure(message: String, url: URL?, onRetry: @escaping () -> Void) {
        detail.stringValue = [URLParser.display(url), message].filter { !$0.isEmpty }.joined(separator: "\n")
        self.onRetry = onRetry
    }

    @objc private func retryTapped() { onRetry?() }
}

// MARK: - Find in page

final class FindBar: NSView, NSSearchFieldDelegate {
    weak var webView: WKWebView?
    private let glass = NSGlassEffectView()
    private let field = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private lazy var prev = IconButton(symbol: "chevron.up", size: 11, tooltip: "Previous (⇧⌘G)", dimension: 24) { [weak self] in self?.search(forward: false) }
    private lazy var next = IconButton(symbol: "chevron.down", size: 11, tooltip: "Next (⌘G)", dimension: 24) { [weak self] in self?.search(forward: true) }
    private lazy var done = IconButton(symbol: "xmark", size: 11, tooltip: "Done (esc)", dimension: 24) { [weak self] in self?.close() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glass.cornerRadius = 18
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        glass.pinEdges(to: self)

        field.placeholderString = "Find on page"
        field.delegate = self
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.target = self
        field.action = #selector(fieldChanged)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .systemRed
        let stack = NSStackView(views: [field, status, prev, next, done])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 6)
        field.widthAnchor.constraint(equalToConstant: 200).isActive = true
        glass.contentView = stack
        stack.pinEdges(to: self)
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func close() {
        isHidden = true
        status.stringValue = ""
        if let webView { window?.makeFirstResponder(webView) }
    }

    @objc private func fieldChanged() { search(forward: true) }

    func search(forward: Bool) {
        guard let webView, !field.stringValue.isEmpty else { status.stringValue = ""; return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.wraps = true
        config.caseSensitive = false
        webView.find(field.stringValue, configuration: config) { [weak self] result in
            self?.status.stringValue = result.matchFound ? "" : "Not found"
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            search(forward: !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)); return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(); return true
        default:
            return false
        }
    }
}
