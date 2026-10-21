import Foundation

/// What a file is, decided from its extension (and whether it is a folder or bundle).
public enum FileKind: String, Codable, CaseIterable, Sendable, Hashable {
    case folder, image, video, audio, pdf, document, spreadsheet, presentation, text, code
    case archive, installer, app, font, other

    public var displayName: String {
        switch self {
        case .folder: return "Folder"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .pdf: return "PDF"
        case .document: return "Document"
        case .spreadsheet: return "Spreadsheet"
        case .presentation: return "Presentation"
        case .text: return "Text"
        case .code: return "Code"
        case .archive: return "Archive"
        case .installer: return "Installer"
        case .app: return "App"
        case .font: return "Font"
        case .other: return "File"
        }
    }

    public var pluralName: String {
        switch self {
        case .folder: return "Folders"
        case .image: return "Images"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .pdf: return "PDFs"
        case .document: return "Documents"
        case .spreadsheet: return "Spreadsheets"
        case .presentation: return "Presentations"
        case .text: return "Text files"
        case .code: return "Code"
        case .archive: return "Archives"
        case .installer: return "Installers"
        case .app: return "Apps"
        case .font: return "Fonts"
        case .other: return "Other files"
        }
    }

    public var symbolName: String {
        switch self {
        case .folder: return "folder"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .presentation: return "rectangle.on.rectangle.angled"
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archive: return "doc.zipper"
        case .installer: return "shippingbox"
        case .app: return "app.dashed"
        case .font: return "textformat"
        case .other: return "doc"
        }
    }

    /// The library shelf the kind belongs to, if any.
    public var category: LibraryCategory? {
        switch self {
        case .image: return .images
        case .video: return .videos
        case .audio: return .music
        case .pdf, .document, .spreadsheet, .presentation, .text: return .documents
        case .archive, .installer: return .archives
        case .app: return .apps
        case .folder, .code, .font, .other: return nil
        }
    }

    /// Kinds whose text Haven can read (OCR, PDF text, office documents, plain text).
    public var hasReadableText: Bool {
        switch self {
        case .image, .pdf, .document, .spreadsheet, .presentation, .text, .code: return true
        default: return false
        }
    }

    /// Text search can match inside: what Haven reads, plus what was said in transcribed audio and video.
    public var hasSearchableText: Bool { hasReadableText || self == .audio || self == .video }
}

/// The six library folders shown on Home and in the sidebar.
public enum LibraryCategory: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case images, videos, music, documents, archives, apps

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .images: return "Images"
        case .videos: return "Videos"
        case .music: return "Music"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .apps: return "Apps"
        }
    }

    public var symbolName: String {
        switch self {
        case .images: return "photo.on.rectangle"
        case .videos: return "play.rectangle"
        case .music: return "music.note.list"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .apps: return "square.grid.2x2"
        }
    }

    public var kinds: Set<FileKind> {
        Set(FileKind.allCases.filter { $0.category == self })
    }
}

public enum KindClassifier {
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp", "svg", "raw", "cr2", "cr3",
        "nef", "arw", "dng", "orf", "rw2", "raf", "psd", "ico", "icns", "avif", "jxl", "jfif",
    ]
    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp", "mts", "m2ts", "hevc",
    ]
    public static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "wma", "alac", "caf", "mid", "midi",
        "m4b", "m4p", "amr",
    ]
    public static let documentExtensions: Set<String> = [
        "doc", "docx", "pages", "rtf", "rtfd", "odt", "epub", "wpd", "dot", "dotx", "mobi",
    ]
    public static let spreadsheetExtensions: Set<String> = ["xls", "xlsx", "numbers", "csv", "tsv", "ods", "xlsm"]
    public static let presentationExtensions: Set<String> = ["ppt", "pptx", "key", "odp", "pps", "ppsx"]
    public static let textExtensions: Set<String> = ["txt", "md", "markdown", "log", "text", "rst", "tex", "vtt", "srt"]
    public static let codeExtensions: Set<String> = [
        "swift", "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "java", "c", "h", "cpp", "hpp", "cc", "m", "mm", "rb",
        "go", "rs", "php", "html", "htm", "css", "scss", "sass", "less", "json", "yaml", "yml", "xml", "sh", "zsh",
        "bash", "kt", "kts", "sql", "ipynb", "toml", "ini", "cfg", "conf", "lua", "pl", "r", "dart", "vue", "svelte",
        "gradle", "plist", "env",
    ]
    public static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "cpgz", "lz", "lzma", "sit", "sitx",
    ]
    public static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "msi", "exe", "apk", "appimage", "deb", "rpm"]
    public static let fontExtensions: Set<String> = ["ttf", "otf", "woff", "woff2", "ttc", "dfont"]

    /// Bundles that should never show up as items (libraries of other apps).
    public static let ignoredPackageExtensions: Set<String> = [
        "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "aplibrary", "migratedphotolibrary",
        "imovielibrary", "fcpbundle", "logicx", "band", "xcodeproj", "xcworkspace", "playground", "lproj",
    ]

    public static func kind(forExtension rawExt: String, isDirectory: Bool = false, isPackage: Bool = false) -> FileKind {
        let ext = rawExt.lowercased()
        if isDirectory && !isPackage { return .folder }
        if ext == "app" { return .app }
        if ext == "pdf" { return .pdf }
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if documentExtensions.contains(ext) { return .document }
        if spreadsheetExtensions.contains(ext) { return .spreadsheet }
        if presentationExtensions.contains(ext) { return .presentation }
        if textExtensions.contains(ext) { return .text }
        if codeExtensions.contains(ext) { return .code }
        if archiveExtensions.contains(ext) { return .archive }
        if installerExtensions.contains(ext) { return .installer }
        if fontExtensions.contains(ext) { return .font }
        if isDirectory { return .folder }
        return .other
    }

    /// Kinds a single extension word in a search ("png", "mp3") maps to.
    public static func isKnownExtension(_ ext: String) -> Bool {
        kind(forExtension: ext) != .other
    }
}
