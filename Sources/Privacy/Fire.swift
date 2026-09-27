import AppKit
import WebKit

@MainActor
enum Fire {
    /// Asks, then closes regular tabs, resets pinned tabs, and wipes cookies, cache, storage and history.
    static func confirmAndBurn(in window: NSWindow?, overlayHost: NSView?) {
        let alert = NSAlert()
        alert.messageText = "Burn all tabs and browsing data?"
        alert.informativeText = "Closes every open tab and clears cookies, site data, cache and history. Pinned tabs and favorites stay, but are signed out."
        alert.addButton(withTitle: "Burn")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        let run: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            burn(overlayHost: overlayHost)
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: run) } else { run(alert.runModal()) }
    }

    static func burn(overlayHost: NSView?) {
        if let host = overlayHost { FireAnimationView.play(in: host) }
        BrowserState.shared.burnTabs()
        // Every profile: the main one plus each space's separate one.
        let stores = [WKWebsiteDataStore.default()] +
            BrowserState.shared.spaces.compactMap(\.profileID).map { WebViewFactory.dataStore(for: $0) }
        Task {
            for store in stores {
                await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            }
        }
        URLCache.shared.removeAllCachedResponses()
    }
}

/// A short warm flash that sweeps up the window.
final class FireAnimationView: NSView {
    static func play(in host: NSView) {
        let v = FireAnimationView(frame: host.bounds)
        v.autoresizingMask = [.width, .height]
        host.addSubview(v, positioned: .above, relativeTo: nil)
        v.run()
    }

    private let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        gradient.colors = [
            NSColor(srgbRed: 1, green: 0.32, blue: 0.1, alpha: 0.85).cgColor,
            NSColor(srgbRed: 1, green: 0.62, blue: 0.1, alpha: 0.55).cgColor,
            NSColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 0).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.frame = bounds
        layer?.addSublayer(gradient)
        layer?.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func run() {
        guard let layer else { return }
        gradient.frame = bounds
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = -bounds.height
        rise.toValue = bounds.height * 0.25
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.2, 0.55, 1]
        let group = CAAnimationGroup()
        group.animations = [fade]
        group.duration = 0.9
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rise.duration = 0.9
        rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        gradient.add(rise, forKey: "rise")
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        }
        layer.add(group, forKey: "fade")
        CATransaction.commit()
    }
}
