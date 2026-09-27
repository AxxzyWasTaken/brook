import AppKit

/// Popover shown from the lock icon in the address pill: this site's settings, one click away.
@MainActor
final class SiteInfoViewController: NSViewController {
    private let host: String
    private let secure: Bool

    init(host: String, secure: Bool) {
        self.host = SiteSettings.key(for: host)
        self.secure = secure
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let o = SiteSettings.override(for: host)

        let title = NSTextField(labelWithString: host)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let status = NSTextField(labelWithString: secure ? "Connection is secure" : "Connection is not secure")
        status.font = .systemFont(ofSize: 11)
        status.textColor = secure ? .secondaryLabelColor : .systemOrange
        let icon = NSImageView(image: NSImage.symbol(secure ? "lock.fill" : "exclamationmark.triangle.fill", size: 13) ?? NSImage())
        icon.contentTintColor = secure ? .secondaryLabelColor : .systemOrange
        let header = NSStackView(views: [icon, NSStackView(views: [title, status]).vertical()])
        header.alignment = .centerY
        header.spacing = 8

        let form = SettingsForm()
        form.grid.rowSpacing = 8
        let zooms: [Double?] = [nil, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 2]
        form.row("Zoom", popup(zooms.map { $0.map { "\(Int($0 * 100))%" } ?? "Default (\(Int(Settings.defaultZoom * 100))%)" },
                               selected: zooms.firstIndex { $0 != nil && o.zoom != nil && abs($0! - o.zoom!) < 0.01 } ?? 0) { [host] i in
            SiteSettings.update(host) { $0.zoom = zooms[i] }
        })
        let tri: [Bool?] = [nil, true, false]
        form.row("JavaScript", popup(["Default (\(Settings.javascriptEnabled ? "Allow" : "Block"))", "Allow", "Block"],
                                     selected: tri.firstIndex { $0 == o.javascript } ?? 0) { [host] i in
            SiteSettings.update(host) { $0.javascript = tri[i] }
        })
        let autoplay: [String?] = [nil] + AutoplayPolicy.allCases.map(\.rawValue)
        form.row("Autoplay", popup(["Default (\(Settings.autoplay.shortTitle))"] + AutoplayPolicy.allCases.map(\.shortTitle),
                                   selected: autoplay.firstIndex { $0 == o.autoplay } ?? 0) { [host] i in
            SiteSettings.update(host) { $0.autoplay = autoplay[i] }
        })
        form.row("Cookie popups", popup(["Default (\(Settings.blockCookiePopups ? "Decline" : "Leave"))", "Decline", "Leave"],
                                        selected: tri.firstIndex { $0 == o.cookiePopups } ?? 0) { [host] i in
            SiteSettings.update(host) { $0.cookiePopups = tri[i] }
        })
        form.finish()
        form.grid.column(at: 0).width = 96
        // One width for every popup so the right edge lines up.
        for case let p as NSPopUpButton in form.grid.subviews {
            p.widthAnchor.constraint(equalToConstant: 180).isActive = true
        }

        let boosts = Boosts.boosts(for: host).filter { $0.site != "*" }
        let boostTitle = boosts.isEmpty ? "Boost This Site…" : "Edit Boost (\(boosts.count))…"
        let boost = Controls.button(boostTitle) { [weak self] in
            guard let self else { return }
            if boosts.isEmpty { Boosts.save(Boost(name: self.host, site: self.host, css: "/* CSS for \(self.host) */\n")) }
            self.dismiss(nil)
            SettingsWindowController.shared.show(pane: "Boosts")
        }
        let reload = Controls.button("Reload") { [weak self] in
            self?.dismiss(nil)
            BrowserState.shared.selectedTab?.reload()
        }
        reload.keyEquivalent = "\r"
        let buttons = NSStackView(views: [boost, NSView(), reload])
        buttons.distribution = .fill

        let note = NSTextField(labelWithString: "JavaScript and Autoplay changes apply on reload.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [header, form.grid, note, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        stack.widthAnchor.constraint(equalToConstant: 330).isActive = true
        view = stack
    }

    private func popup(_ titles: [String], selected: Int, onChange: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.addItems(withTitles: titles)
        p.selectItem(at: selected)
        p.onAction { c in onChange((c as! NSPopUpButton).indexOfSelectedItem) }
        return p
    }
}

extension NSStackView {
    func vertical() -> NSStackView {
        orientation = .vertical
        alignment = .leading
        spacing = 1
        return self
    }
}
