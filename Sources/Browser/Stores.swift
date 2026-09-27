import AppKit
import WebKit

// MARK: - History

struct HistoryEntry: Codable {
    var url: String
    var title: String
    var visits: Int
    var last: Date
}

@MainActor
final class HistoryStore {
    static let shared = HistoryStore()

    private var entries: [String: HistoryEntry] = [:]
    private let fileURL = AppPaths.support.appendingPathComponent("history.json")
    private let saver = Debouncer(delay: 5)
    private let limit = 20_000

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            for e in list { entries[e.url] = e }
        }
    }

    func record(url: URL, title: String?) {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" else { return }
        let key = url.absoluteString
        var e = entries[key] ?? HistoryEntry(url: key, title: "", visits: 0, last: Date())
        e.visits += 1
        e.last = Date()
        if let title, !title.isEmpty { e.title = title }
        entries[key] = e
        scheduleSave()
    }

    func updateTitle(_ title: String, for url: URL) {
        let key = url.absoluteString
        guard var e = entries[key], e.title != title else { return }
        e.title = title
        entries[key] = e
        scheduleSave()
    }

    /// Simple frecency ranking: matches in the host or title, weighted by visits and recency.
    func search(_ query: String, limit: Int = 6) -> [HistoryEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let now = Date()
        var scored: [(HistoryEntry, Double)] = []
        for e in entries.values {
            let u = e.url.lowercased()
            let t = e.title.lowercased()
            let stripped = u.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "www.", with: "")
            var score: Double
            if stripped.hasPrefix(q) { score = 4 }
            else if t.hasPrefix(q) { score = 3 }
            else if u.contains(q) || t.contains(q) { score = 1 }
            else { continue }
            let ageDays = now.timeIntervalSince(e.last) / 86_400
            score *= log2(Double(e.visits) + 1) + 1
            score /= (1 + ageDays / 14)
            scored.append((e, score))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    func clear() {
        entries.removeAll()
        saver.flush { self.saveNow() }
    }

    private func scheduleSave() {
        saver.call { [weak self] in self?.saveNow() }
    }

    func saveNow() {
        var list = Array(entries.values)
        if list.count > limit {
            list.sort { $0.last > $1.last }
            list = Array(list.prefix(limit))
            entries = Dictionary(uniqueKeysWithValues: list.map { ($0.url, $0) })
        }
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Favicons

@MainActor
final class FaviconStore {
    static let shared = FaviconStore()

    private let memory = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private var misses: Set<String> = []
    private let dir = AppPaths.sub("Favicons", in: AppPaths.caches)

    private func file(for host: String) -> URL {
        dir.appendingPathComponent(host.replacingOccurrences(of: "/", with: "_") + ".img")
    }

    func cachedIcon(for host: String) -> NSImage? {
        if let img = memory.object(forKey: host as NSString) { return img }
        if let data = try? Data(contentsOf: file(for: host)), let img = NSImage(data: data) {
            memory.setObject(img, forKey: host as NSString)
            return img
        }
        return nil
    }

    func icon(for host: String) async -> NSImage? {
        if let img = cachedIcon(for: host) { return img }
        if misses.contains(host) { return nil }
        if let task = inflight[host] { return await task.value }
        let dest = file(for: host)
        let task = Task<NSImage?, Never> {
            guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
                  let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: result.0) else { return nil }
            try? result.0.write(to: dest, options: .atomic)
            return img
        }
        inflight[host] = task
        let img = await task.value
        inflight[host] = nil
        if let img { memory.setObject(img, forKey: host as NSString) } else { misses.insert(host) }
        return img
    }
}

// MARK: - Downloads

@MainActor
final class DownloadItem: NSObject {
    enum Status { case active, finished, failed }

    let download: WKDownload
    var filename: String = "Download"
    var destination: URL?
    var status: Status = .active
    var fraction: Double { download.progress.fractionCompleted }

    init(download: WKDownload) {
        self.download = download
    }
}

@MainActor
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    static let didChange = Notification.Name("BrookDownloadsDidChange")

    private(set) var items: [DownloadItem] = []

    var hasActive: Bool { items.contains { $0.status == .active } }

    func track(_ download: WKDownload) {
        download.delegate = self
        items.insert(DownloadItem(download: download), at: 0)
        notify()
    }

    func clearFinished() {
        items.removeAll { $0.status != .active }
        notify()
    }

    private func item(for d: WKDownload) -> DownloadItem? { items.first { $0.download === d } }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = suggestedFilename.isEmpty ? "Download" : suggestedFilename
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        if let item = item(for: download) {
            item.filename = candidate.lastPathComponent
            item.destination = candidate
        }
        notify()
        return candidate
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        item.status = .finished
        if let path = item.destination?.path {
            // Makes the Downloads stack in the Dock bounce, like Safari.
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: path)
        }
        notify()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        item(for: download)?.status = .failed
        notify()
    }
}
