import AppKit
import WebKit

private struct ExtensionRecord: Codable {
    var id: String
    var folder: String
    var name: String
    var chromeWebStoreID: String?
}

enum ExtensionInstallError: LocalizedError {
    case invalidInput
    case badPackage
    case downloadFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "That doesn’t look like a Chrome Web Store link or extension ID."
        case .badPackage: return "The extension package couldn’t be read."
        case .downloadFailed(let why): return "Couldn’t download the extension: \(why)"
        case .cancelled: return "Cancelled."
        }
    }
}

/// Runs Chrome/Safari-style web extensions using WebKit's WKWebExtension API
/// (the same approach DuckDuckGo's browser uses).
@MainActor
final class ExtensionManager: NSObject, WKWebExtensionControllerDelegate {
    static let shared = ExtensionManager()
    static let didChange = Notification.Name("DriftExtensionsDidChange")

    let controller: WKWebExtensionController
    weak var window: BrowserWindowController?

    private var records: [ExtensionRecord] = []
    private let recordsURL = AppPaths.support.appendingPathComponent("extensions.json")
    private let folder = AppPaths.sub("Extensions")

    override init() {
        let config = WKWebExtensionController.Configuration.default()
        config.webViewConfiguration.applicationNameForUserAgent = WebViewFactory.userAgentSuffix
        controller = WKWebExtensionController(configuration: config)
        super.init()
        controller.delegate = self
    }

    var contexts: [WKWebExtensionContext] {
        records.compactMap { r in controller.extensionContexts.first { $0.uniqueIdentifier == r.id } }
    }

    func context(for id: String) -> WKWebExtensionContext? {
        controller.extensionContexts.first { $0.uniqueIdentifier == id }
    }

    // MARK: Loading

    func loadAll() async {
        if let data = try? Data(contentsOf: recordsURL),
           let list = try? JSONDecoder().decode([ExtensionRecord].self, from: data) {
            records = list
        }
        for r in records {
            do {
                let ext = try await WKWebExtension(resourceBaseURL: folder.appendingPathComponent(r.folder, isDirectory: true))
                try controller.load(makeContext(ext, id: r.id))
            } catch {
                NSLog("Drift: failed to load extension \(r.name): \(error)")
            }
            await Task.yield()
        }
        notify()
    }

    private func makeContext(_ ext: WKWebExtension, id: String) -> WKWebExtensionContext {
        let context = WKWebExtensionContext(for: ext)
        context.uniqueIdentifier = id
        for pattern in ext.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: nil)
        }
        for permission in ext.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission, expirationDate: nil)
        }
        context.isInspectable = true
        context.hasAccessToPrivateData = true
        return context
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: recordsURL, options: .atomic)
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: Installing

    /// Accepts a Chrome Web Store URL or a bare 32-letter extension ID.
    func installFromChromeWebStore(_ input: String) async throws {
        guard let id = Self.chromeID(in: input) else { throw ExtensionInstallError.invalidInput }
        if let existing = records.first(where: { $0.chromeWebStoreID == id }), context(for: existing.id) != nil {
            return
        }
        let url = URL(string: "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=138.0.0.0&acceptformat=crx2,crx3&x=id%3D\(id)%26uc")!
        let data: Data
        do {
            let result = try await URLSession.shared.data(from: url)
            guard (result.1 as? HTTPURLResponse)?.statusCode == 200, !result.0.isEmpty else {
                throw ExtensionInstallError.downloadFailed("the store didn’t return a package")
            }
            data = result.0
        } catch let e as ExtensionInstallError {
            throw e
        } catch {
            throw ExtensionInstallError.downloadFailed(error.localizedDescription)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).crx")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await install(from: tmp, chromeWebStoreID: id)
    }

    static func chromeID(in input: String) -> String? {
        guard let r = input.range(of: #"[a-p]{32}"#, options: .regularExpression) else { return nil }
        return String(input[r])
    }

    /// Installs from an unpacked folder, a .crx, or a .zip.
    func install(from source: URL, chromeWebStoreID: String? = nil) async throws {
        let id = UUID().uuidString
        let dest = folder.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        fm.fileExists(atPath: source.path, isDirectory: &isDir)
        if isDir.boolValue {
            try fm.copyItem(at: source, to: dest)
        } else {
            let zipURL: URL
            if source.pathExtension.lowercased() == "crx" {
                let raw = try Data(contentsOf: source)
                guard let zip = CRX.zipPayload(of: raw) else { throw ExtensionInstallError.badPackage }
                zipURL = fm.temporaryDirectory.appendingPathComponent("\(id).zip")
                try zip.write(to: zipURL)
            } else {
                zipURL = source
            }
            try await CRX.unzip(zipURL, to: dest)
            if zipURL != source { try? fm.removeItem(at: zipURL) }
        }

        // Some zips wrap everything in one top-level folder.
        var root = dest
        if !fm.fileExists(atPath: dest.appendingPathComponent("manifest.json").path),
           let items = try? fm.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil),
           items.count == 1, fm.fileExists(atPath: items[0].appendingPathComponent("manifest.json").path) {
            root = items[0]
        }
        try? fm.removeItem(at: root.appendingPathComponent("_metadata"))

        let ext: WKWebExtension
        do {
            ext = try await WKWebExtension(resourceBaseURL: root)
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }

        guard await confirmInstall(ext) else {
            try? fm.removeItem(at: dest)
            throw ExtensionInstallError.cancelled
        }

        try controller.load(makeContext(ext, id: id))
        let relative = root.path.replacingOccurrences(of: folder.path + "/", with: "")
        records.append(ExtensionRecord(id: id, folder: relative, name: ext.displayName ?? "Extension",
                                       chromeWebStoreID: chromeWebStoreID))
        saveRecords()
        notify()
    }

    private func confirmInstall(_ ext: WKWebExtension) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Add “\(ext.displayName ?? "this extension")”?"
        var lines: [String] = []
        let perms = ext.requestedPermissions.map { $0.rawValue }.sorted()
        if !perms.isEmpty { lines.append("Permissions: " + perms.joined(separator: ", ")) }
        let hosts = ext.allRequestedMatchPatterns.map { String(describing: $0) }
        if hosts.contains(where: { $0.contains("<all_urls>") || $0.hasPrefix("*://*/") }) {
            lines.append("It can read and change your data on all websites.")
        } else if !hosts.isEmpty {
            lines.append("Sites: " + hosts.prefix(6).joined(separator: ", ") + (hosts.count > 6 ? "…" : ""))
        }
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: "Add Extension")
        alert.addButton(withTitle: "Cancel")
        if let icon = ext.icon(for: NSSize(width: 64, height: 64)) { alert.icon = icon }
        if let w = window?.window {
            return await alert.beginSheetModal(for: w) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    func uninstall(_ context: WKWebExtensionContext) {
        try? controller.unload(context)
        if let i = records.firstIndex(where: { $0.id == context.uniqueIdentifier }) {
            let rec = records.remove(at: i)
            let top = rec.folder.split(separator: "/").first.map(String.init) ?? rec.folder
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(top))
        }
        saveRecords()
        notify()
    }

    // MARK: Tab & window events

    func windowDidOpen(_ w: BrowserWindowController) {
        window = w
        controller.didOpenWindow(w)
        controller.didFocusWindow(w)
    }

    func tabDidOpen(_ tab: BrowserTab) {
        controller.didOpenTab(tab)
    }

    func tabWillClose(_ tab: BrowserTab) {
        controller.didCloseTab(tab, windowIsClosing: false)
    }

    func tabDidActivate(_ tab: BrowserTab?, previous: BrowserTab?) {
        guard let tab, tab.isLoaded else { return }
        let prev: (any WKWebExtensionTab)? = (previous?.isLoaded ?? false) ? previous : nil
        controller.didActivateTab(tab, previousActiveTab: prev)
    }

    func tabDidChange(_ tab: BrowserTab, properties: WKWebExtension.TabChangedProperties) {
        guard tab.isLoaded else { return }
        controller.didChangeTabProperties(properties, for: tab)
    }

    // MARK: WKWebExtensionControllerDelegate

    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        guard let window else { return [] }
        return [window]
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        window
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        let tab = BrowserState.shared.openTab(url: configuration.url, select: true)
        tab.materialize()
        return tab
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        for url in configuration.tabURLs {
            BrowserState.shared.openTab(url: url, select: true)
        }
        return window
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        if let url = extensionContext.optionsPageURL {
            BrowserState.shared.openTab(url: url, select: true)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                presentActionPopup action: WKWebExtension.Action,
                                for extensionContext: WKWebExtensionContext) async throws {
        window?.presentExtensionPopup(action)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?,
                                for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        (permissions, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?,
                                for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        (urls, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?,
                                for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        (matchPatterns, nil)
    }
}

// MARK: - CRX packages

enum CRX {
    /// Chrome packages are a zip with a signed header in front. Returns just the zip.
    static func zipPayload(of data: Data) -> Data? {
        guard data.count > 16 else { return nil }
        let bytes = [UInt8](data.prefix(16))
        func u32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24 }
        if bytes[0] == 0x50 && bytes[1] == 0x4B { return data } // already a zip
        guard bytes[0] == 0x43, bytes[1] == 0x72, bytes[2] == 0x32, bytes[3] == 0x34 else { return nil } // "Cr24"
        let offset: Int
        switch u32(4) {
        case 3: offset = 12 + u32(8)
        case 2: offset = 16 + u32(8) + u32(12)
        default: return nil
        }
        guard offset < data.count else { return nil }
        return data.subdata(in: data.startIndex + offset ..< data.endIndex)
    }

    static func unzip(_ zip: URL, to dest: URL) async throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, dest.path]
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { p in
                if p.terminationStatus == 0 { cont.resume() } else { cont.resume(throwing: ExtensionInstallError.badPackage) }
            }
            do { try process.run() } catch { cont.resume(throwing: error) }
        }
    }
}

// MARK: - "Add to Drift" button on the Chrome Web Store

@MainActor
final class ChromeWebStoreBridge: NSObject, WKScriptMessageHandler {
    static let shared = ChromeWebStoreBridge()
    private let world = WKContentWorld.world(name: "DriftStore")

    func install(into ucc: WKUserContentController) {
        guard let url = Bundle.main.url(forResource: "chrome-web-store", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        ucc.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world))
        ucc.add(self, contentWorld: world, name: "driftInstallExtension")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView?.url?.host() == "chromewebstore.google.com",
              let id = message.body as? String else { return }
        Task {
            do {
                try await ExtensionManager.shared.installFromChromeWebStore(id)
                ExtensionManager.shared.window?.showToast("Extension added")
            } catch ExtensionInstallError.cancelled {
            } catch {
                ExtensionManager.shared.window?.showError(error)
            }
        }
    }
}
