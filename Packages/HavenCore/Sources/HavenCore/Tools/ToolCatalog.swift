import Foundation

/// The groups on the Tools page and in the Tools menus.
public enum ToolGroup: String, CaseIterable, Sendable, Identifiable {
    case images, pdf, video, audio, ai

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .images: return "Images"
        case .pdf: return "PDF"
        case .video: return "Video"
        case .audio: return "Audio"
        case .ai: return "On-Device AI"
        }
    }

    public var symbol: String {
        switch self {
        case .images: return "photo.on.rectangle"
        case .pdf: return "doc.richtext"
        case .video: return "film"
        case .audio: return "waveform"
        case .ai: return "sparkles"
        }
    }

    public var tools: [ToolID] { ToolID.allCases.filter { $0.group == self } }
}

/// Every tool Haven has. Each one makes new files next to the originals (which never change), and Undo takes them away.
public enum ToolID: String, CaseIterable, Sendable, Identifiable, Codable {
    // Images
    case convertImage, resizeImage, rotateImage, removeImageDetails, removeBackground
    // PDF
    case mergePDFs, splitPDF, organizePDF, extractPDFPages, imagesToPDF, pdfToImages, lockPDF, unlockPDF, signPDF
    // Video
    case compressVideo, convertVideo, trimVideo, videoToGIF, extractAudio, muteVideo, mergeVideos, changeSpeed
    // Audio
    case convertAudio, trimAudio
    // On-device AI
    case transcribe, translate, summarize

    public var id: String { rawValue }

    public var group: ToolGroup {
        switch self {
        case .convertImage, .resizeImage, .rotateImage, .removeImageDetails, .removeBackground: return .images
        case .mergePDFs, .splitPDF, .organizePDF, .extractPDFPages, .imagesToPDF, .pdfToImages, .lockPDF, .unlockPDF, .signPDF: return .pdf
        case .compressVideo, .convertVideo, .trimVideo, .videoToGIF, .extractAudio, .muteVideo, .mergeVideos, .changeSpeed: return .video
        case .convertAudio, .trimAudio: return .audio
        case .transcribe, .translate, .summarize: return .ai
        }
    }

    public var title: String {
        switch self {
        case .convertImage: return "Convert Images"
        case .resizeImage: return "Resize Images"
        case .rotateImage: return "Rotate Images"
        case .removeImageDetails: return "Remove Private Details"
        case .removeBackground: return "Remove Background"
        case .mergePDFs: return "Merge PDFs"
        case .splitPDF: return "Split PDF"
        case .organizePDF: return "Organize Pages"
        case .extractPDFPages: return "Extract Pages"
        case .imagesToPDF: return "Images to PDF"
        case .pdfToImages: return "PDF to Images"
        case .lockPDF: return "Add Password"
        case .unlockPDF: return "Remove Password"
        case .signPDF: return "Sign PDF"
        case .compressVideo: return "Compress Video"
        case .convertVideo: return "Convert Video"
        case .trimVideo: return "Trim Video"
        case .videoToGIF: return "Make a GIF"
        case .extractAudio: return "Extract Audio"
        case .muteVideo: return "Mute Video"
        case .mergeVideos: return "Merge Videos"
        case .changeSpeed: return "Change Speed"
        case .convertAudio: return "Convert Audio"
        case .trimAudio: return "Trim Audio"
        case .transcribe: return "Transcribe"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        }
    }

    public var subtitle: String {
        switch self {
        case .convertImage: return "JPEG, PNG, HEIC, TIFF or WebP"
        case .resizeImage: return "Smaller, keeping the shape"
        case .rotateImage: return "A quarter turn, in bulk"
        case .removeImageDetails: return "Location, camera and dates out, before you share"
        case .removeBackground: return "Cut out the subject, one click"
        case .mergePDFs: return "Several PDFs into one"
        case .splitPDF: return "One file per page"
        case .organizePDF: return "Reorder, rotate or delete pages"
        case .extractPDFPages: return "Pick pages for a new PDF"
        case .imagesToPDF: return "Photos and scans into one document"
        case .pdfToImages: return "Every page as a picture"
        case .lockPDF: return "Only people with the password can open it"
        case .unlockPDF: return "A copy that opens without the password"
        case .signPDF: return "Draw your signature once, place it anywhere"
        case .compressVideo: return "Much smaller, still looks good"
        case .convertVideo: return "MP4 or MOV"
        case .trimVideo: return "Keep just the part you want"
        case .videoToGIF: return "A looping GIF to share"
        case .extractAudio: return "The soundtrack as M4A"
        case .muteVideo: return "Take the sound out"
        case .mergeVideos: return "Clips joined in order"
        case .changeSpeed: return "Slower or faster, same pitch"
        case .convertAudio: return "M4A, WAV, AIFF or FLAC"
        case .trimAudio: return "Cut to the part you need"
        case .transcribe: return "What's said, as text or subtitles (Whisper)"
        case .translate: return "Documents and subtitles, on your Mac"
        case .summarize: return "The gist of a long document"
        }
    }

    public var symbol: String {
        switch self {
        case .convertImage: return "arrow.triangle.2.circlepath"
        case .resizeImage: return "arrow.down.right.and.arrow.up.left"
        case .rotateImage: return "rotate.right"
        case .removeImageDetails: return "location.slash"
        case .removeBackground: return "person.crop.rectangle"
        case .mergePDFs: return "doc.on.doc"
        case .splitPDF: return "rectangle.split.3x1"
        case .organizePDF: return "square.grid.3x3"
        case .extractPDFPages: return "doc.badge.plus"
        case .imagesToPDF: return "photo.on.rectangle.angled"
        case .pdfToImages: return "photo.stack"
        case .lockPDF: return "lock"
        case .unlockPDF: return "lock.open"
        case .signPDF: return "signature"
        case .compressVideo: return "film.stack"
        case .convertVideo: return "arrow.triangle.2.circlepath"
        case .trimVideo: return "timeline.selection"
        case .videoToGIF: return "sparkles.rectangle.stack"
        case .extractAudio: return "waveform"
        case .muteVideo: return "speaker.slash"
        case .mergeVideos: return "film.stack"
        case .changeSpeed: return "gauge.with.dots.needle.67percent"
        case .convertAudio: return "arrow.triangle.2.circlepath"
        case .trimAudio: return "scissors"
        case .transcribe: return "captions.bubble"
        case .translate: return "character.bubble"
        case .summarize: return "text.redaction"
        }
    }

    /// The kinds of files the tool takes.
    public var inputs: ToolInput {
        switch group {
        case .images: return .images
        case .pdf: return self == .imagesToPDF ? .images : .pdfs
        case .video: return .videos
        case .audio: return .audio
        case .ai: return self == .transcribe ? .media : .text
        }
    }

    /// How many files it takes: (at least, at most).
    public var count: (min: Int, max: Int?) {
        switch self {
        case .mergePDFs, .mergeVideos: return (2, nil)
        case .organizePDF, .extractPDFPages, .unlockPDF, .signPDF, .trimVideo, .trimAudio, .translate, .summarize: return (1, 1)
        default: return (1, nil)
        }
    }

    public func applies(to items: [FileItem]) -> Bool {
        let (low, high) = count
        guard items.count >= low, high.map({ items.count <= $0 }) ?? true else { return false }
        return items.allSatisfy(inputs.accepts)
    }

    /// What to pick, for the Tools page ("Choose two or more PDFs").
    public var choosePrompt: String {
        let (low, high) = count
        let what = inputs.noun
        if low >= 2 { return "Choose two or more \(what.plural)" }
        if high == 1 { return "Choose \(what.one)" }
        return "Choose one or more \(what.plural)"
    }

    /// Tools that run in the background with a progress bar (everything else is near instant).
    public var isLong: Bool {
        switch group {
        case .video, .audio, .ai: return true
        default: return self == .removeBackground || self == .pdfToImages
        }
    }

    /// The tools that fit these files, in catalog order.
    public static func available(for items: [FileItem]) -> [ToolID] {
        allCases.filter { $0.applies(to: items) }
    }
}

/// The files a tool reads.
public enum ToolInput: Sendable {
    case images, pdfs, videos, audio, media, text

    /// Image formats ImageIO reads.
    public static let imageExtensions: Set<String> = ["heic", "heif", "png", "tiff", "tif", "webp", "bmp", "gif", "jpg", "jpeg", "jfif", "avif"]
    /// Containers AVFoundation opens (MKV, AVI and WebM need other software).
    public static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "3gp", "3g2"]
    public static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "aifc", "caf", "aac", "flac", "m4b", "m4r", "amr"]
    public static let textKinds: Set<FileKind> = [.text, .document, .pdf, .presentation]

    public func accepts(_ item: FileItem) -> Bool {
        let ext = item.ext
        switch self {
        case .images: return item.kind == .image && Self.imageExtensions.contains(ext)
        case .pdfs: return item.kind == .pdf
        case .videos: return item.kind == .video && Self.videoExtensions.contains(ext)
        case .audio: return item.kind == .audio && Self.audioExtensions.contains(ext)
        case .media: return ToolInput.videos.accepts(item) || ToolInput.audio.accepts(item)
        case .text: return Self.textKinds.contains(item.kind)
        }
    }

    public var noun: (one: String, plural: String) {
        switch self {
        case .images: return ("an image", "images")
        case .pdfs: return ("a PDF", "PDFs")
        case .videos: return ("a video", "videos")
        case .audio: return ("an audio file", "audio files")
        case .media: return ("a video or audio file", "videos or audio files")
        case .text: return ("a document", "documents")
        }
    }

    /// File types for the "Choose files" panel.
    public var extensions: [String] {
        switch self {
        case .images: return Self.imageExtensions.sorted()
        case .pdfs: return ["pdf"]
        case .videos: return Self.videoExtensions.sorted()
        case .audio: return Self.audioExtensions.sorted()
        case .media: return (Self.videoExtensions.union(Self.audioExtensions)).sorted()
        case .text: return ["txt", "md", "markdown", "srt", "vtt", "rtf", "pdf", "docx", "doc", "pages", "odt", "html", "htm", "pptx", "key"]
        }
    }
}

// MARK: Options

public enum ImageFormat: String, CaseIterable, Sendable, Identifiable {
    case jpeg, png, heic, tiff, webp

    public var id: String { rawValue }
    public var title: String { self == .jpeg ? "JPEG" : rawValue.uppercased() }
    public var ext: String { self == .jpeg ? "jpg" : (self == .tiff ? "tiff" : rawValue) }
    public var typeIdentifier: String {
        switch self {
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .heic: return "public.heic"
        case .tiff: return "public.tiff"
        case .webp: return "org.webmproject.webp"
        }
    }

    /// The format a file already has, if it's one of these.
    public static func of(_ ext: String) -> ImageFormat? {
        switch ext.lowercased() {
        case "jpg", "jpeg", "jfif": return .jpeg
        case "png": return .png
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        case "webp": return .webp
        default: return nil
        }
    }

    /// Formats worth offering for these images (not the one they all have already).
    public static func targets(for items: [FileItem]) -> [ImageFormat] {
        let current = Set(items.map { of($0.ext) })
        return allCases.filter { !(current.count == 1 && current.contains($0)) }
    }
}

public enum ResizeOption: Hashable, Sendable, Identifiable {
    case percent(Int)
    case longestSide(Int)

    public static let presets: [ResizeOption] = [.percent(50), .percent(25), .longestSide(3840), .longestSide(2048), .longestSide(1600), .longestSide(1024), .longestSide(800)]

    public var id: String { tag }

    public var title: String {
        switch self {
        case .percent(let p): return "\(p)%"
        case .longestSide(let s): return "Fit in \(s) px"
        }
    }

    /// The part of the new name: "photo (50%).jpg", "photo (2048px).jpg".
    public var tag: String {
        switch self {
        case .percent(let p): return "\(p)%"
        case .longestSide(let s): return "\(s)px"
        }
    }

    /// The new pixel size, never larger than the original.
    public func size(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (width, height) }
        let scale: Double
        switch self {
        case .percent(let p): scale = Double(min(100, max(1, p))) / 100
        case .longestSide(let s): scale = min(1, Double(s) / Double(max(width, height)))
        }
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }
}

public enum Rotation: Int, CaseIterable, Sendable, Identifiable {
    case left = 270, right = 90, upsideDown = 180

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .left: return "Rotate Left"
        case .right: return "Rotate Right"
        case .upsideDown: return "Turn Upside Down"
        }
    }
    /// Degrees clockwise.
    public var degrees: Int { rawValue }
    /// Whether width and height swap.
    public var swapsSides: Bool { self != .upsideDown }
}

public enum VideoQuality: String, CaseIterable, Sendable, Identifiable {
    case high, medium, small

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .high: return "High Quality (1080p)"
        case .medium: return "Smaller (720p)"
        case .small: return "Smallest (540p)"
        }
    }
    public var tag: String {
        switch self {
        case .high: return "1080p"
        case .medium: return "720p"
        case .small: return "540p"
        }
    }
    /// The long side of the picture.
    public var longestSide: Int {
        switch self {
        case .high: return 1920
        case .medium: return 1280
        case .small: return 960
        }
    }

    /// Picture size after compressing: never enlarged, even numbers (video encoders need them).
    public func size(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (width, height) }
        let scale = min(1, Double(longestSide) / Double(max(width, height)))
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }
}

public enum VideoContainer: String, CaseIterable, Sendable, Identifiable {
    case mp4, mov
    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
    public var ext: String { rawValue }
}

public enum AudioFormat: String, CaseIterable, Sendable, Identifiable {
    case m4a, wav, aiff, flac
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .m4a: return "M4A (AAC)"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .flac: return "FLAC"
        }
    }
    public var ext: String { rawValue }

    public static func targets(for items: [FileItem]) -> [AudioFormat] {
        let current = Set(items.map { $0.ext == "aif" ? "aiff" : $0.ext })
        return allCases.filter { !(current.count == 1 && current.contains($0.ext)) }
    }
}

public enum GIFSize: Int, CaseIterable, Sendable, Identifiable {
    case small = 320, medium = 480, large = 640
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .small: return "Small (320 px)"
        case .medium: return "Medium (480 px)"
        case .large: return "Large (640 px)"
        }
    }
}

public enum PlaybackSpeed: Double, CaseIterable, Sendable, Identifiable {
    case half = 0.5, faster = 1.5, double = 2, quadruple = 4
    public var id: Double { rawValue }
    public var title: String { "\(tag) speed" }
    /// "0.5×", "2×"
    public var tag: String {
        let v = rawValue
        return (v == v.rounded() ? String(Int(v)) : String(v)) + "×"
    }
    public func newDuration(_ seconds: Double) -> Double { seconds / rawValue }
}
