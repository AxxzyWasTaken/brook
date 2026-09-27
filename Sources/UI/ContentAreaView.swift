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
        // Web views are added as subviews later; their layers would otherwise cover the bar.
        progress.zPosition = 100
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
        if !findBar.isHidden { findBar.webView = wv; findBar.invalidateCount(); findBar.search(forward: true) }
    }

    func tabChanged(_ tab: BrowserTab, change: TabChange) {
        guard tab === self.tab else { return }
        if change.contains(.progress) || change.contains(.loading) { updateProgress() }
        if change.contains(.error) { updateError() }
        if change.contains(.url) { findBar.invalidateCount() }
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

    /// Safari-style "3 of 12". WebKit's find API reports only found/not found, so the total is
    /// counted once per query in an isolated JS world and the index is tracked here.
    private var total = 0
    private var index = 0
    private var countedQuery = ""
    private var countWork: DispatchWorkItem?

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
        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        status.textColor = .secondaryLabelColor
        status.alignment = .right
        status.setContentHuggingPriority(.required, for: .horizontal)
        let stack = NSStackView(views: [field, status, prev, next, done])
        stack.spacing = 4
        stack.setCustomSpacing(8, after: status)
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
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()", in: nil, in: .defaultClient)
        if let webView { window?.makeFirstResponder(webView) }
    }

    /// The page changed underneath (navigation or tab switch): recount on the next search.
    func invalidateCount() { countedQuery = "" }

    @objc private func fieldChanged() { search(forward: true) }

    func search(forward: Bool) {
        let query = field.stringValue
        guard let webView, !query.isEmpty else { total = 0; index = 0; showStatus(); return }
        let fresh = query != countedQuery
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.wraps = true
        config.caseSensitive = false
        webView.find(query, configuration: config) { [weak self] result in
            guard let self, self.field.stringValue == query else { return }
            if !result.matchFound {
                self.total = 0; self.index = 0; self.countedQuery = query
                self.showStatus()
                return
            }
            if fresh {
                self.index = 1
                self.scheduleCount(query)
            } else if self.total > 0 {
                self.index = forward ? self.index % self.total + 1 : (self.index + self.total - 2) % self.total + 1
            }
            self.showStatus()
        }
    }

    /// Counting walks the page text, so wait for typing to pause.
    private func scheduleCount(_ query: String) {
        countWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let webView = self.webView, self.field.stringValue == query else { return }
                let js = """
                const q = needle.toLocaleLowerCase(), t = (document.body ? document.body.innerText : '').toLocaleLowerCase();
                let n = 0, i = 0;
                while (n < 10000 && (i = t.indexOf(q, i)) !== -1) { n++; i += q.length; }
                return n;
                """
                webView.callAsyncJavaScript(js, arguments: ["needle": query], in: nil, in: .defaultClient) { [weak self] result in
                    guard let self, self.field.stringValue == query else { return }
                    let n = (try? result.get()) as? Int ?? 0
                    self.countedQuery = query
                    // innerText can miss text WebKit still finds (e.g. in form fields); never show "2 of 1".
                    self.total = max(n, self.index)
                    self.showStatus()
                }
            }
        }
        countWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func showStatus() {
        if field.stringValue.isEmpty {
            status.stringValue = ""
        } else if total == 0 && countedQuery == field.stringValue {
            status.stringValue = "No matches"
        } else if total == 0 {
            status.stringValue = ""
        } else {
            status.stringValue = "\(index) of \(total)"
        }
        status.textColor = status.stringValue == "No matches" ? .systemRed : .secondaryLabelColor
        prev.isEnabled = total != 0 || countedQuery != field.stringValue
        next.isEnabled = prev.isEnabled
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
