import AppKit
import Foundation
import HavenCore
import ImageIO
import PDFKit
import Vision

/// Thread-safe store of text Haven has read from files.
final class TextStore: @unchecked Sendable {
    struct Entry: Codable {
        var m: Double   // modification time
        var s: Int64    // size
        var t: String   // text as read
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var folded: [String: String] = [:]

    func folded(for path: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return folded[path]
    }

    /// A copy of all folded text, for searches that check thousands of files on many threads at once.
    func foldedSnapshot() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return folded
    }

    func raw(for path: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return entries[path]?.t
    }

    func isFresh(_ item: FileItem) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[item.path] else { return false }
        return e.m == item.modified.timeIntervalSince1970 && e.s == item.size
    }

    func set(_ text: String, for item: FileItem) {
        let e = Entry(m: item.modified.timeIntervalSince1970, s: item.size, t: text)
        let f = FileItem.fold(text)
        lock.lock()
        entries[item.path] = e
        folded[item.path] = f
        lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    /// Text follows files Haven renamed or moved (and everything inside moved folders), so nothing is read twice.
    func move(_ pairs: [(from: String, to: String)]) {
        // Only folders need a look through everything stored (for the files inside them).
        let folders = pairs.filter { p in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: p.to, isDirectory: &isDir) && isDir.boolValue
        }
        lock.lock()
        defer { lock.unlock() }
        for (from, to) in pairs {
            if let e = entries.removeValue(forKey: from) { entries[to] = e }
            if let f = folded.removeValue(forKey: from) { folded[to] = f }
        }
        for (from, to) in folders {
            let prefix = from + "/"
            for key in entries.keys.filter({ $0.hasPrefix(prefix) }) {
                let moved = to + "/" + key.dropFirst(prefix.count)
                if let e = entries.removeValue(forKey: key) { entries[moved] = e }
                if let f = folded.removeValue(forKey: key) { folded[moved] = f }
            }
        }
    }

    func load(from url: URL) {
        guard let d = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([String: Entry].self, from: d) else { return }
        var f: [String: String] = [:]
        for (k, v) in e where !v.t.isEmpty { f[k] = FileItem.fold(v.t) }
        lock.lock()
        entries = e
        folded = f
        lock.unlock()
    }

    func save(to url: URL) {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url, options: .atomic) }
    }

    func clear() {
        lock.lock()
        entries = [:]
        folded = [:]
        lock.unlock()
    }
}

/// Reads text in images (Vision OCR, on-device), PDFs and documents in the background so search can find it.
@MainActor
@Observable
final class TextIndex {
    private(set) var processed = 0
    private(set) var total = 0
    private(set) var isWorking = false
    private(set) var version = 0

    @ObservationIgnored let store = TextStore()
    @ObservationIgnored private var queue: [FileItem] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Bumped by "Forget text": anything started before stops touching the state.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastVersionBump = Date.distantPast

    private var cacheURL: URL { LaunchOptions.current.supportDirectory.appendingPathComponent("text.json") }

    /// For search: folded text for a path (a snapshot, so searching never waits on the reader).
    nonisolated var lookup: SearchEngine.TextLookup {
        let snapshot = store.foldedSnapshot()
        return { snapshot[$0] }
    }

    var readCount: Int { store.count }

    /// Reads the saved text off the main thread.
    func load() async {
        let store = self.store
        let url = cacheURL
        await Task.detached(priority: .userInitiated) { store.load(from: url) }.value
        version += 1
    }

    func clearCache() {
        generation += 1
        worker?.cancel()
        worker = nil
        saveTask?.cancel()
        saveTask = nil
        queue = []
        store.clear()
        try? FileManager.default.removeItem(at: cacheURL)
        isWorking = false
        processed = 0
        total = 0
        version += 1
    }

    /// Which files to read, newest first, for the chosen scope.
    nonisolated static func candidates(_ items: [FileItem], scope: OCRScope, now: Date = Date()) -> [FileItem] {
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        return items.filter { item in
            // iWork files are often folders on disk (size 0); everything else needs some bytes to read.
            guard !item.isCloudOnly, item.size > 0 || DocumentText.iWorkExtensions.contains(item.ext) else { return false }
            switch item.kind {
            case .image:
                guard item.size < 60 * ByteSize.mb, item.ext != "svg", item.ext != "psd", item.ext != "icns" else { return false }
                switch scope {
                case .off: return false
                case .screenshots: return item.isScreenshot
                case .recent: return item.isScreenshot || item.activityDate > yearAgo
                case .all: return true
                }
            case .pdf:
                return item.size < 150 * ByteSize.mb
            case .text, .code:
                return item.size < 2 * ByteSize.mb
            case .document:
                return TextExtractor.documentExtensions.contains(item.ext) && item.size < 80 * ByteSize.mb
            case .spreadsheet:
                if ["csv", "tsv"].contains(item.ext) { return item.size < 5 * ByteSize.mb }
                return TextExtractor.spreadsheetExtensions.contains(item.ext) && item.size < 80 * ByteSize.mb
            case .presentation:
                return TextExtractor.presentationExtensions.contains(item.ext) && item.size < 400 * ByteSize.mb
            default:
                return false
            }
        }
        .sorted { a, b in
            // Screenshots first: they're the files people most often search the text of.
            if a.isScreenshot != b.isScreenshot { return a.isScreenshot }
            return a.activityDate > b.activityDate
        }
    }

    /// Queues files to read. Picking them out of a big index happens in the background.
    func enqueue(_ items: [FileItem], scope: OCRScope) {
        let store = self.store
        let gen = generation
        Task {
            let fresh = await Task.detached(priority: .utility) {
                TextIndex.candidates(items, scope: scope).filter { !store.isFresh($0) }
            }.value
            guard gen == self.generation, !fresh.isEmpty else { return }
            let existing = Set(self.queue.map(\.path))
            self.queue.append(contentsOf: fresh.filter { !existing.contains($0.path) })
            self.total = self.processed + self.queue.count
            self.startWorker()
        }
    }

    private func startWorker() {
        guard worker == nil, !queue.isEmpty else { return }
        isWorking = true
        let gen = generation
        worker = Task { [weak self] in
            while let self, !Task.isCancelled, gen == self.generation {
                guard !self.queue.isEmpty else { break }
                let batch = Array(self.queue.prefix(4))
                self.queue.removeFirst(batch.count)
                let store = self.store
                let job = Task.detached(priority: .utility) {
                    for item in batch {
                        if Task.isCancelled { return }
                        let text = TextExtractor.extract(item) ?? ""
                        store.set(text, for: item)
                    }
                }
                await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
                guard gen == self.generation else { return }
                self.processed += batch.count
                self.bumpVersion(force: false)
                self.scheduleSave()
            }
            guard let self, gen == self.generation else { return }
            self.bumpVersion(force: true)
            self.isWorking = false
            self.worker = nil
            self.scheduleSave()
            CustomRulesRunner.shared.noteTextRead()
            if !self.queue.isEmpty { self.startWorker() }
        }
    }

    /// Search results re-run when `version` changes; while reading, that happens every few seconds, not per batch.
    private func bumpVersion(force: Bool) {
        let now = Date()
        if force || now.timeIntervalSince(lastVersionBump) > 3 {
            version += 1
            lastVersionBump = now
        }
    }

    /// Saves at most every few seconds while reading, so quitting midway keeps what was read.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        let store = self.store
        let url = cacheURL
        let gen = generation
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .background) { store.save(to: url) }.value
            if let self, gen == self.generation { self.saveTask = nil }
        }
    }

    /// Text Haven got another way (a transcript of a video or voice memo) is searchable straight away.
    func remember(_ text: String, for item: FileItem) {
        store.set(text, for: item)
        bumpVersion(force: true)
        scheduleSave()
    }

    /// Text for Copy Text: cached, or read right now.
    func text(for item: FileItem) async -> String? {
        if store.isFresh(item), let t = store.raw(for: item.path) { return t }
        let store = self.store
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            let t = TextExtractor.extract(item)
            if let t { store.set(t, for: item) }
            return t
        }.value
        version += 1
        return result
    }
}

/// The actual reading: Vision OCR for images, PDFKit for PDFs, the ZIP/XML reader for office files and
/// e-books, AppKit for Word 97 and RTF, and OCR of the first-page picture inside Pages, Numbers and Keynote files.
enum TextExtractor {
    static let documentExtensions: Set<String> = ["docx", "dotx", "doc", "rtf", "rtfd", "odt", "epub", "pages"]
    static let spreadsheetExtensions: Set<String> = ["xlsx", "xlsm", "ods", "numbers"]
    static let presentationExtensions: Set<String> = ["pptx", "ppsx", "odp", "key"]

    static func extract(_ item: FileItem) -> String? {
        if DocumentText.zippedExtensions.contains(item.ext) { return DocumentText.extract(url: item.url) }
        if DocumentText.iWorkExtensions.contains(item.ext) { return iWorkText(item.url) }
        switch item.kind {
        case .image: return recognizeText(in: item.url)
        case .pdf: return pdfText(item.url)
        case .code where item.ext == "html" || item.ext == "htm":
            return plainText(item.url).map { DocumentText.xmlText(Array($0.utf8), html: true) }
        case .text, .code, .spreadsheet: return plainText(item.url)
        case .document: return documentText(item.url)
        default: return nil
        }
    }

    /// Pages, Numbers and Keynote keep a picture of the first page; reading it finds the title and opening text.
    static func iWorkText(_ url: URL) -> String? {
        guard let data = DocumentText.iWorkPreview(url: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return recognizeText(in: cg)
    }

    static func recognizeText(in url: URL, maxPixels: Int = 2600) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        return recognizeText(in: cg)
    }

    static func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    static func pdfText(_ url: URL, maxPages: Int = 40) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var parts: [String] = []
        let pages = min(doc.pageCount, maxPages)
        for i in 0..<pages {
            if let s = doc.page(at: i)?.string, !s.isEmpty { parts.append(s) }
        }
        let text = parts.joined(separator: "\n")
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return String(text.prefix(60_000)) }
        // Scanned PDF: OCR the first pages.
        var ocr: [String] = []
        for i in 0..<min(doc.pageCount, 3) {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 1800 / max(bounds.width, bounds.height, 1)
            let thumb = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            if let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil), let t = recognizeText(in: cg) { ocr.append(t) }
        }
        return ocr.joined(separator: "\n")
    }

    static func plainText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256 * 1024) else { return nil }
        if data.prefix(4096).contains(0) { return nil } // binary
        return String(decoding: data, as: UTF8.self)
    }

    static func documentText(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch ext {
        case "docx": options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": options[.documentType] = NSAttributedString.DocumentType.docFormat
        case "rtf": options[.documentType] = NSAttributedString.DocumentType.rtf
        case "rtfd": options[.documentType] = NSAttributedString.DocumentType.rtfd
        case "odt": options[.documentType] = NSAttributedString.DocumentType.openDocument
        default: return nil
        }
        guard let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil) else { return nil }
        return String(attributed.string.prefix(60_000))
    }
}
