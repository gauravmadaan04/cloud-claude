import AVFoundation
import CryptoKit
import Foundation
import HavenCore
import whisper

/// Whisper models Haven downloads on first use, from the whisper.cpp project (MIT licensed, like Whisper itself).
enum WhisperModel: String, CaseIterable, Identifiable {
    case best, fast

    var id: String { rawValue }
    var fileName: String { self == .best ? "ggml-large-v3-turbo-q5_0.bin" : "ggml-small-q5_1.bin" }
    var bytes: Int64 { self == .best ? 574_041_195 : 190_085_487 }
    var sha256: String {
        self == .best ? "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
            : "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
    }
    var title: String { self == .best ? "Best Quality" : "Faster" }
    var detail: String {
        self == .best ? "Whisper large-v3 turbo · \(ByteSize.format(bytes)) · best with accents and mixed languages"
            : "Whisper small · \(ByteSize.format(bytes)) · quicker, good for clear speech"
    }
    var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")! }

    /// Apple silicon runs the big model quickly; Intel Macs are better off with the small one.
    static var recommended: WhisperModel {
        var size = 0
        sysctlbyname("hw.optional.arm64", nil, &size, nil, 0)
        return size > 0 ? .best : .fast
    }
}

/// The downloaded models, kept in Haven's support folder.
@MainActor
@Observable
final class WhisperModels {
    static let shared = WhisperModels()

    private(set) var downloading: WhisperModel?
    private(set) var progress = 0.0
    private(set) var installed: Set<WhisperModel> = []
    @ObservationIgnored private var task: Task<Void, Never>?

    /// A model file given on the command line (tests use a tiny one).
    @ObservationIgnored var overridePath: String? = LaunchOptions.current.whisperModel

    private init() { refresh() }

    nonisolated static var folder: URL {
        let dir = LaunchOptions.current.supportDirectory.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func path(_ model: WhisperModel) -> URL { folder.appendingPathComponent(model.fileName) }

    func refresh() {
        installed = Set(WhisperModel.allCases.filter { model in
            let size = (try? FileManager.default.attributesOfItem(atPath: Self.path(model).path))?[.size] as? NSNumber
            return size?.int64Value == model.bytes
        })
    }

    /// The model to transcribe with: the best one that's here.
    var current: String? {
        if let overridePath, FileManager.default.fileExists(atPath: overridePath) { return overridePath }
        if installed.contains(.best) { return Self.path(.best).path }
        if installed.contains(.fast) { return Self.path(.fast).path }
        return nil
    }

    var isReady: Bool { current != nil }

    func download(_ model: WhisperModel) {
        guard downloading == nil else { return }
        downloading = model
        progress = 0
        task = Task {
            do {
                try await Self.fetch(model) { p in Task { @MainActor in WhisperModels.shared.progress = p } }
                refresh()
                AppModel.shared.showToast("The transcription model is ready", symbol: "captions.bubble")
            } catch is CancellationError {
                // Stopped by you.
            } catch {
                AppModel.shared.showToast("Couldn't download the model: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
            downloading = nil
        }
    }

    func cancelDownload() { task?.cancel() }

    func remove(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: Self.path(model))
        refresh()
    }

    /// Downloads, checks the file is exactly the published one, then moves it into place.
    nonisolated static func fetch(_ model: WhisperModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        let downloader = ModelDownloader(progress: progress)
        let temp = try await downloader.download(model.url)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard try sha256(of: temp) == model.sha256 else { throw ToolError.failed("The download was damaged; try again") }
        let dest = path(model)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// A download with progress and cancellation.
private final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var kept: URL?
    private var session: URLSession?

    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func download(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file is deleted when this returns, so it's moved somewhere of ours first.
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("haven-model-\(UUID().uuidString).bin")
        if (try? FileManager.default.moveItem(at: location, to: dest)) != nil { kept = dest }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let error {
            continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else if let status = (task.response as? HTTPURLResponse)?.statusCode, status >= 400 {
            continuation?.resume(throwing: ToolError.failed("The server answered \(status)"))
        } else if let kept {
            continuation?.resume(returning: kept)
        } else {
            continuation?.resume(throwing: ToolError.failed("The download didn't finish"))
        }
        continuation = nil
    }
}

/// What was said, with timings.
struct Transcript {
    var cues: [Cue]
    /// Language code Whisper heard ("en", "hi"…).
    var language: String
    var text: String { Subtitles.plainText(cues) }
}

/// Speech to text with whisper.cpp, entirely on this Mac.
enum Transcriber {
    /// Tests run on the CPU: it gives the same result on every machine.
    nonisolated(unsafe) static var useGPU = !LaunchOptions.current.isRunningUnitTests

    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("hi", "Hindi"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("nl", "Dutch"), ("ja", "Japanese"), ("zh", "Chinese"), ("ko", "Korean"), ("ar", "Arabic"),
        ("ru", "Russian"), ("tr", "Turkish"), ("bn", "Bengali"), ("ta", "Tamil"), ("te", "Telugu"), ("mr", "Marathi"),
        ("gu", "Gujarati"), ("kn", "Kannada"), ("ml", "Malayalam"), ("pa", "Punjabi"), ("ur", "Urdu"),
    ]

    /// Sound as 16 kHz mono samples (what Whisper listens to), mixed from every audio track.
    static func decode(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw ToolError.failed("“\(url.lastPathComponent)” has no sound") }
        return try await Task.detached(priority: .userInitiated) { () -> [Float] in
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else { throw ToolError.unreadable(url.lastPathComponent) }
            var samples: [Float] = []
            while let buffer = output.copyNextSampleBuffer() {
                if Task.isCancelled {
                    reader.cancelReading()
                    throw CancellationError()
                }
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
                guard count > 0 else { continue }
                let start = samples.count
                samples.append(contentsOf: repeatElement(0, count: count))
                samples.withUnsafeMutableBytes { raw in
                    _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                                   destination: raw.baseAddress! + start * MemoryLayout<Float>.size)
                }
            }
            if reader.status == .failed { throw ToolError.unreadable(url.lastPathComponent) }
            return samples
        }.value
    }

    private final class Run: @unchecked Sendable {
        var cancelled = false
        let progress: ProgressHandler?
        init(progress: ProgressHandler?) { self.progress = progress }
    }

    /// - Parameters:
    ///   - language: a code like "en", or nil to let Whisper tell.
    ///   - toEnglish: Whisper's own translation of the speech into English.
    static func transcribe(_ url: URL, model: String, language: String? = nil, toEnglish: Bool = false,
                           progress: ProgressHandler? = nil) async throws -> Transcript {
        let samples = try await decode(url)
        progress?(0.05)
        guard samples.count > 1_600 else { throw ToolError.failed("“\(url.lastPathComponent)” is too short to transcribe") }
        let run = Run(progress: { p in progress?(0.05 + p * 0.95) })
        let gpu = useGPU
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try whisperRun(samples, model: model, language: language, toEnglish: toEnglish, gpu: gpu, run: run)
            }.value
        } onCancel: {
            run.cancelled = true
        }
    }

    private static func whisperRun(_ samples: [Float], model: String, language: String?, toEnglish: Bool, gpu: Bool, run: Run) throws -> Transcript {
        whisper_log_set({ _, _, _ in }, nil)
        var cparams = whisper_context_default_params()
        cparams.use_gpu = gpu
        guard let ctx = whisper_init_from_file_with_params(model, cparams) else {
            throw ToolError.failed("Couldn't load the transcription model")
        }
        defer { whisper_free(ctx) }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1)))
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = toEnglish
        let lang = strdup(language ?? "auto")
        defer { free(lang) }
        params.language = UnsafePointer(lang)
        let user = Unmanaged.passUnretained(run).toOpaque()
        params.progress_callback = { _, _, percent, user in
            guard let user else { return }
            Unmanaged<Run>.fromOpaque(user).takeUnretainedValue().progress?(Double(percent) / 100)
        }
        params.progress_callback_user_data = user
        params.abort_callback = { user in
            guard let user else { return false }
            return Unmanaged<Run>.fromOpaque(user).takeUnretainedValue().cancelled
        }
        params.abort_callback_user_data = user
        let rc = samples.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
        if run.cancelled { throw CancellationError() }
        guard rc == 0 else { throw ToolError.failed("Transcription stopped (error \(rc))") }
        var cues: [Cue] = []
        let n = whisper_full_n_segments(ctx)
        for i in 0..<n {
            guard let raw = whisper_full_get_segment_text(ctx, i) else { continue }
            let text = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !Self.isNoise(text) else { continue }
            let t0 = Double(whisper_full_get_segment_t0(ctx, i)) / 100
            let t1 = Double(whisper_full_get_segment_t1(ctx, i)) / 100
            cues.append(Cue(start: t0, end: t1, text: text))
        }
        let code = whisper_lang_str(whisper_full_lang_id(ctx)).map { String(cString: $0) } ?? (language ?? "")
        return Transcript(cues: cues, language: code)
    }

    /// Whisper's notes about sound rather than speech ("[Music]", "(applause)").
    static func isNoise(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let first = t.first, let last = t.last else { return true }
        return (first == "[" && last == "]") || (first == "(" && last == ")") || t == "♪"
    }
}
