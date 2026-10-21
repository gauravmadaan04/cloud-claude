import AVFoundation
import CoreGraphics
import Foundation
import HavenCore

/// An option picked from a tool's submenu.
enum ToolChoice: Hashable {
    case none
    case imageFormat(ImageFormat)
    case resize(ResizeOption)
    case rotation(Rotation)
    case videoQuality(VideoQuality)
    case container(VideoContainer)
    case audioFormat(AudioFormat)
    case gif(GIFSize)
    case speed(PlaybackSpeed)
}

/// Where a signature goes.
struct SignaturePlacement {
    var page: Int
    var rect: CGRect
    var image: CGImage
}

enum TranscriptFormat: String, CaseIterable, Identifiable {
    case text, subtitles
    var id: String { rawValue }
    var title: String { self == .text ? "Text (.txt)" : "Subtitles (.srt)" }
}

/// What the option sheets add: passwords, pages, a time range, a signature, transcription settings.
struct ToolExtras {
    var password: String?
    var pages: [PageEdit]?
    var timeRange: CMTimeRange?
    var signature: SignaturePlacement?
    var model: String?
    var language: String?
    var toEnglish = false
    var transcriptFormats: Set<TranscriptFormat> = [.text]
}

/// A file a tool made, and the file it was made from.
struct Made: Sendable, Equatable {
    let from: String
    let to: String
}

struct JobOutcome: Sendable {
    var made: [Made] = []
    /// Overrides the usual "Made “x”" toast.
    var message: String?
    var failures = 0
}

extension ToolID {
    /// The submenu of choices, if the tool has one.
    func choices(for items: [FileItem]) -> [(title: String, choice: ToolChoice)] {
        switch self {
        case .convertImage:
            let writable = ImageTools.writableFormats
            return ImageFormat.targets(for: items).filter(writable.contains).map { ($0.title, .imageFormat($0)) }
        case .resizeImage: return ResizeOption.presets.map { ($0.title, .resize($0)) }
        case .rotateImage: return Rotation.allCases.map { ($0.title, .rotation($0)) }
        case .compressVideo: return VideoQuality.allCases.map { ($0.title, .videoQuality($0)) }
        case .convertVideo:
            let current = Set(items.map(\.ext))
            return VideoContainer.allCases.filter { !(current.count == 1 && current.contains($0.ext)) }.map { ($0.title, .container($0)) }
        case .convertAudio: return AudioFormat.targets(for: items).map { ($0.title, .audioFormat($0)) }
        case .videoToGIF: return GIFSize.allCases.map { ($0.title, .gif($0)) }
        case .changeSpeed: return PlaybackSpeed.allCases.map { ($0.title, .speed($0)) }
        default: return []
        }
    }

    /// Tools that ask for something first (a password, pages, a range, an order, a language…).
    var opensSheet: Bool {
        switch self {
        case .mergePDFs, .mergeVideos, .organizePDF, .extractPDFPages, .lockPDF, .unlockPDF, .signPDF, .trimVideo, .trimAudio,
             .transcribe, .translate, .summarize:
            return true
        default:
            return false
        }
    }
}

/// The work behind every tool, away from the main thread. Used by the job runner, and directly by the tests.
enum ToolWork {
    static func destination(_ name: String, in dir: String) -> URL {
        URL(fileURLWithPath: RulesPlanner.uniqueDestination(name: name, in: dir) { FileManager.default.fileExists(atPath: $0) })
    }

    /// Runs `body` for each file, one after another, with overall progress. Files that fail are counted, not fatal.
    private static func each(_ items: [FileItem], progress: ProgressHandler?,
                             _ body: (FileItem, ProgressHandler?) async throws -> [URL]) async throws -> JobOutcome {
        var outcome = JobOutcome()
        var firstError: Error?
        for (i, item) in items.enumerated() {
            try Task.checkCancellation()
            let share = 1 / Double(items.count)
            let itemProgress: ProgressHandler = { p in progress?((Double(i) + min(1, max(0, p))) * share) }
            do {
                for url in try await body(item, itemProgress) { outcome.made.append(Made(from: item.path, to: url.path)) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                outcome.failures += 1
                if firstError == nil { firstError = error }
            }
            progress?(Double(i + 1) * share)
        }
        if outcome.made.isEmpty, let firstError { throw firstError }
        if outcome.failures > 0, let firstError {
            outcome.message = "Made \(outcome.made.count), \(outcome.failures) didn't work: \(firstError.localizedDescription)"
        }
        return outcome
    }

    private static func single(_ items: [FileItem], _ to: URL) -> JobOutcome {
        JobOutcome(made: [Made(from: items.count == 1 ? items[0].path : items[0].parentPath, to: to.path)])
    }

    /// The extension edits keep: the original's when this Mac can write it, otherwise JPEG.
    private static func editExt(_ item: FileItem) -> String {
        if let f = ImageFormat.of(item.ext), ImageTools.writableFormats.contains(f) { return RenamePlanner.split(item).ext }
        return "jpg"
    }

    static func run(_ tool: ToolID, _ items: [FileItem], choice: ToolChoice = .none, extras: ToolExtras = ToolExtras(),
                    progress: ProgressHandler? = nil) async throws -> JobOutcome {
        guard !items.isEmpty else { throw ToolError.failed("Nothing to work on") }
        switch tool {
        // MARK: Images
        case .convertImage:
            guard case .imageFormat(let format) = choice else { throw ToolError.failed("Pick a format") }
            return try await each(items, progress: progress) { item, _ in
                let dest = destination(ToolNaming.converted(item, ext: format.ext), in: item.parentPath)
                try ImageTools.convert(item.url, to: format, dest: dest)
                return [dest]
            }
        case .resizeImage:
            guard case .resize(let option) = choice else { throw ToolError.failed("Pick a size") }
            return try await each(items, progress: progress) { item, _ in
                let dest = destination(ToolNaming.tagged(item, option.tag, ext: editExt(item)), in: item.parentPath)
                try ImageTools.resize(item.url, option, dest: dest)
                return [dest]
            }
        case .rotateImage:
            guard case .rotation(let rotation) = choice else { throw ToolError.failed("Pick a direction") }
            return try await each(items, progress: progress) { item, _ in
                let dest = destination(ToolNaming.tagged(item, "rotated", ext: editExt(item)), in: item.parentPath)
                try ImageTools.rotate(item.url, rotation, dest: dest)
                return [dest]
            }
        case .removeImageDetails:
            var outcome = try await each(items, progress: progress) { item, _ in
                let ext = ImageFormat.of(item.ext) == nil ? "png" : RenamePlanner.split(item).ext
                let dest = destination(ToolNaming.tagged(item, "clean", ext: ext), in: item.parentPath)
                try ImageTools.removeDetails(item.url, dest: dest)
                return [dest]
            }
            if outcome.message == nil {
                outcome.message = outcome.made.count == 1 ? "Made “\((outcome.made[0].to as NSString).lastPathComponent)”: no location, camera or dates"
                    : "Made \(outcome.made.count) copies without location, camera or dates"
            }
            return outcome
        case .removeBackground:
            return try await each(items, progress: progress) { item, _ in
                let dest = destination(ToolNaming.tagged(item, "cut out", ext: "png"), in: item.parentPath)
                try ImageTools.removeBackground(item.url, dest: dest)
                return [dest]
            }

        // MARK: PDF
        case .mergePDFs:
            let dest = destination(ToolNaming.merged(items, ext: "pdf"), in: items[0].parentPath)
            let pages = try PDFTools.merge(items.map(\.url), dest: dest)
            var outcome = single(items, dest)
            outcome.message = "Made “\(dest.lastPathComponent)” · \(HavenFormat.count(pages, "page"))"
            return outcome
        case .splitPDF:
            return try await each(items, progress: progress) { item, _ in
                let folder = destination(ToolNaming.folder(item, "pages"), in: item.parentPath)
                _ = try PDFTools.split(item.url, into: folder, base: ToolNaming.base(of: item))
                return [folder]
            }
        case .organizePDF, .extractPDFPages:
            guard let pages = extras.pages, !pages.isEmpty else { throw ToolError.failed("Pick at least one page") }
            let item = items[0]
            let tag = tool == .organizePDF ? "edited" : PageRange.tag(pages.map(\.source))
            let dest = destination(ToolNaming.tagged(item, tag, ext: "pdf"), in: item.parentPath)
            try PDFTools.rebuild(item.url, pages: pages, dest: dest)
            return single(items, dest)
        case .imagesToPDF:
            let dest = destination(ToolNaming.pdfFromImages(items), in: items[0].parentPath)
            let pages = try PDFTools.imagesToPDF(items.map(\.url), dest: dest)
            var outcome = single(items, dest)
            outcome.message = "Made “\(dest.lastPathComponent)” · \(HavenFormat.count(pages, "page"))"
            return outcome
        case .pdfToImages:
            return try await each(items, progress: progress) { item, p in
                let folder = destination(ToolNaming.folder(item, "images"), in: item.parentPath)
                _ = try PDFTools.toImages(item.url, into: folder, base: ToolNaming.base(of: item), progress: p)
                return [folder]
            }
        case .lockPDF:
            guard let password = extras.password, !password.isEmpty else { throw ToolError.failed("Type a password") }
            return try await each(items, progress: progress) { item, _ in
                let dest = destination(ToolNaming.tagged(item, "locked", ext: "pdf"), in: item.parentPath)
                try PDFTools.lock(item.url, password: password, dest: dest)
                return [dest]
            }
        case .unlockPDF:
            let item = items[0]
            let dest = destination(ToolNaming.tagged(item, "unlocked", ext: "pdf"), in: item.parentPath)
            try PDFTools.unlock(item.url, password: extras.password ?? "", dest: dest)
            return single(items, dest)
        case .signPDF:
            guard let placement = extras.signature else { throw ToolError.failed("Place your signature first") }
            let item = items[0]
            let dest = destination(ToolNaming.tagged(item, "signed", ext: "pdf"), in: item.parentPath)
            try PDFTools.sign(item.url, page: placement.page, rect: placement.rect, signature: placement.image, dest: dest)
            return single(items, dest)

        // MARK: Video
        case .compressVideo:
            guard case .videoQuality(let quality) = choice else { throw ToolError.failed("Pick a size") }
            var before: Int64 = 0, after: Int64 = 0
            var outcome = try await each(items, progress: progress) { item, p in
                let dest = destination(ToolNaming.tagged(item, quality.tag, ext: "mp4"), in: item.parentPath)
                try await MediaTools.compress(item.url, quality, dest: dest, progress: p)
                before += MediaTools.size(item.url)
                after += MediaTools.size(dest)
                return [dest]
            }
            if outcome.message == nil, before > 0 {
                let what = outcome.made.count == 1 ? "“\((outcome.made[0].to as NSString).lastPathComponent)”" : "\(outcome.made.count) videos"
                outcome.message = "Made \(what) · \(ByteSize.format(before)) → \(ByteSize.format(after))"
            }
            return outcome
        case .convertVideo:
            guard case .container(let container) = choice else { throw ToolError.failed("Pick a format") }
            return try await each(items, progress: progress) { item, p in
                let dest = destination(ToolNaming.converted(item, ext: container.ext), in: item.parentPath)
                try await MediaTools.convert(item.url, to: container, dest: dest, progress: p)
                return [dest]
            }
        case .trimVideo, .trimAudio:
            guard let range = extras.timeRange else { throw ToolError.failed("Pick the part to keep") }
            let item = items[0]
            let ext = tool == .trimAudio ? "m4a" : RenamePlanner.split(item).ext
            let dest = destination(ToolNaming.tagged(item, "trimmed", ext: ext), in: item.parentPath)
            try await MediaTools.trim(item.url, range: range, dest: dest, progress: progress)
            return single(items, dest)
        case .videoToGIF:
            guard case .gif(let size) = choice else { throw ToolError.failed("Pick a size") }
            return try await each(items, progress: progress) { item, p in
                let dest = destination(ToolNaming.converted(item, ext: "gif"), in: item.parentPath)
                try await MediaTools.gif(item.url, size, dest: dest, progress: p)
                return [dest]
            }
        case .extractAudio:
            return try await each(items, progress: progress) { item, p in
                let dest = destination(ToolNaming.converted(item, ext: "m4a"), in: item.parentPath)
                try await MediaTools.extractAudio(item.url, dest: dest, progress: p)
                return [dest]
            }
        case .muteVideo:
            return try await each(items, progress: progress) { item, p in
                let dest = destination(ToolNaming.tagged(item, "muted"), in: item.parentPath)
                try await MediaTools.mute(item.url, dest: dest, progress: p)
                return [dest]
            }
        case .mergeVideos:
            let ext = items[0].ext == "mp4" ? "mp4" : "mov"
            let dest = destination(ToolNaming.merged(items, ext: ext), in: items[0].parentPath)
            try await MediaTools.merge(items.map(\.url), dest: dest, progress: progress)
            return single(items, dest)
        case .changeSpeed:
            guard case .speed(let speed) = choice else { throw ToolError.failed("Pick a speed") }
            return try await each(items, progress: progress) { item, p in
                let ext = item.kind == .audio ? "m4a" : RenamePlanner.split(item).ext
                let dest = destination(ToolNaming.tagged(item, speed.tag, ext: ext), in: item.parentPath)
                try await MediaTools.changeSpeed(item.url, speed, dest: dest, progress: p)
                return [dest]
            }

        // MARK: Audio
        case .convertAudio:
            guard case .audioFormat(let format) = choice else { throw ToolError.failed("Pick a format") }
            return try await each(items, progress: progress) { item, p in
                let dest = destination(ToolNaming.converted(item, ext: format.ext), in: item.parentPath)
                try await MediaTools.convertAudio(item.url, to: format, dest: dest, progress: p)
                return [dest]
            }

        // MARK: AI
        case .transcribe:
            guard let model = extras.model else { throw ToolError.needsModel }
            let formats = extras.transcriptFormats.isEmpty ? [.text] : extras.transcriptFormats
            return try await each(items, progress: progress) { item, p in
                let transcript = try await Transcriber.transcribe(item.url, model: model, language: extras.language, toEnglish: extras.toEnglish, progress: p)
                guard !transcript.cues.isEmpty else { throw ToolError.failed("No speech found in “\(item.name)”") }
                var made: [URL] = []
                if formats.contains(.text) {
                    let dest = destination(ToolNaming.converted(item, ext: "txt"), in: item.parentPath)
                    try transcript.text.write(to: dest, atomically: true, encoding: .utf8)
                    made.append(dest)
                }
                if formats.contains(.subtitles) {
                    let dest = destination(ToolNaming.converted(item, ext: "srt"), in: item.parentPath)
                    try Subtitles.srt(transcript.cues).write(to: dest, atomically: true, encoding: .utf8)
                    made.append(dest)
                }
                // What was said becomes searchable, like the text in screenshots.
                let text = transcript.text
                await MainActor.run { LibraryStore.shared.text.remember(text, for: item) }
                return made
            }
        case .translate, .summarize:
            throw ToolError.unsupported("Open \(tool.title) from its window")
        }
    }
}
