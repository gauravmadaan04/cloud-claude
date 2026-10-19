import Foundation

public enum CleanupKind: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case duplicates, oldInstallers, forgottenDownloads, oldScreenshots, bigOldVideos, unusedApps, unzippedArchives

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .duplicates: return "Duplicates"
        case .oldInstallers: return "Old Installers"
        case .forgottenDownloads: return "Forgotten Downloads"
        case .oldScreenshots: return "Old Screenshots"
        case .bigOldVideos: return "Big Old Videos"
        case .unusedApps: return "Unused Apps"
        case .unzippedArchives: return "Already Unzipped"
        }
    }

    public var symbolName: String {
        switch self {
        case .duplicates: return "square.on.square"
        case .oldInstallers: return "shippingbox"
        case .forgottenDownloads: return "arrow.down.circle"
        case .oldScreenshots: return "camera.viewfinder"
        case .bigOldVideos: return "film.stack"
        case .unusedApps: return "app.badge.clock"
        case .unzippedArchives: return "doc.zipper"
        }
    }

    public func explanation(_ s: CleanupSettings) -> String {
        switch self {
        case .duplicates: return "Identical files and look-alike photos. Haven keeps the best copy."
        case .oldInstallers: return "Disk images and installers older than \(s.installerAgeDays) days. The apps they installed stay."
        case .forgottenDownloads: return "Downloads you haven't opened in \(s.forgottenDays) days."
        case .oldScreenshots: return "Screenshots older than \(s.screenshotAgeDays) days."
        case .bigOldVideos: return "Videos over \(ByteSize.format(s.bigVideoBytes)) not opened in \(s.bigVideoAgeDays) days."
        case .unusedApps: return "Apps you haven't opened in \(s.unusedAppDays) days."
        case .unzippedArchives: return "Zip files sitting next to the folder they were unzipped into."
        }
    }
}

public struct CleanupSettings: Codable, Hashable, Sendable {
    public var installerAgeDays = 14
    public var forgottenDays = 90
    public var screenshotAgeDays = 30
    public var bigVideoBytes: Int64 = 200 * ByteSize.mb
    public var bigVideoAgeDays = 180
    public var unusedAppDays = 90

    public init() {}
}

public struct CleanupCard: Identifiable, Hashable, Sendable {
    public let kind: CleanupKind
    public let items: [FileItem]
    public var id: String { kind.rawValue }
    public var totalBytes: Int64 { items.totalSize }

    public init(kind: CleanupKind, items: [FileItem]) {
        self.kind = kind
        self.items = items
    }
}

public enum CleanupEngine {

    static let protectedAppNames: Set<String> = ["haven.app", "safari.app", "finder.app", "system settings.app", "app store.app"]

    public static func items(
        for kind: CleanupKind,
        in items: [FileItem],
        settings s: CleanupSettings = CleanupSettings(),
        now: Date = Date()
    ) -> [FileItem] {
        func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }
        switch kind {
        case .duplicates:
            return []
        case .oldInstallers:
            let cutoff = daysAgo(s.installerAgeDays)
            return items.filter { $0.kind == .installer && !$0.isCloudOnly && $0.arrivalDate < cutoff }
                .sorted { $0.size > $1.size }
        case .forgottenDownloads:
            let cutoff = daysAgo(s.forgottenDays)
            // Top-level files in Downloads only; things filed into subfolders were looked after.
            return items.filter {
                $0.rootID == "downloads" && isTopLevelDownload($0) && $0.kind != .installer && $0.kind != .folder
                    && !$0.isCloudOnly && $0.lastUsedDate < cutoff
            }
            .sorted { $0.lastUsedDate < $1.lastUsedDate }
        case .oldScreenshots:
            let cutoff = daysAgo(s.screenshotAgeDays)
            return items.filter { $0.isScreenshot && !$0.isCloudOnly && $0.created < cutoff }
                .sorted { $0.created < $1.created }
        case .bigOldVideos:
            let cutoff = daysAgo(s.bigVideoAgeDays)
            return items.filter { $0.kind == .video && !$0.isCloudOnly && $0.size >= s.bigVideoBytes && $0.lastUsedDate < cutoff && $0.modified < cutoff }
                .sorted { $0.size > $1.size }
        case .unusedApps:
            let cutoff = daysAgo(s.unusedAppDays)
            return items.filter {
                $0.kind == .app && $0.rootID == "applications" && !protectedAppNames.contains($0.name.lowercased())
                    && $0.lastUsedDate < cutoff
            }
            .sorted { ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast) }
        case .unzippedArchives:
            var folders = Set<String>()
            for item in items where item.kind == .folder { folders.insert(item.path) }
            return items.filter { item in
                guard item.kind == .archive, item.ext == "zip" || item.ext == "tar" || item.ext == "tgz" || item.ext == "gz" || item.ext == "rar" || item.ext == "7z" else { return false }
                var stem = item.parentPath + "/" + item.baseName
                if stem.hasSuffix(".tar") { stem = String(stem.dropLast(4)) }
                return folders.contains(stem)
            }
            .sorted { $0.size > $1.size }
        }
    }

    static func isTopLevelDownload(_ item: FileItem) -> Bool {
        item.parentPath.hasSuffix("/Downloads")
    }

    /// All non-empty cards except duplicates (those come from `DuplicateFinder`).
    public static func cards(in items: [FileItem], settings: CleanupSettings = CleanupSettings(), now: Date = Date()) -> [CleanupCard] {
        CleanupKind.allCases.filter { $0 != .duplicates }.compactMap { kind in
            let found = self.items(for: kind, in: items, settings: settings, now: now)
            return found.isEmpty ? nil : CleanupCard(kind: kind, items: found)
        }
    }
}
