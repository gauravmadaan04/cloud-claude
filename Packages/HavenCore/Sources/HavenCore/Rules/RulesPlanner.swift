import Foundation

/// Optional automatic tidy-ups. All are off until the user turns them on.
public enum AutoRule: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case trashOldInstallers, fileScreenshots, archiveOldDownloads

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trashOldInstallers: return "Move old installers to the Trash"
        case .fileScreenshots: return "File screenshots into monthly folders"
        case .archiveOldDownloads: return "Archive old downloads by month"
        }
    }

    public func detail(_ s: RuleSettings) -> String {
        switch self {
        case .trashOldInstallers:
            return "Downloaded .dmg, .pkg and other installers left in Downloads for \(s.installerDays) days go to the Trash (you can put them back). Disk images you made are never touched."
        case .fileScreenshots:
            return "Screenshots older than a day move from your Desktop into \(tildePath(s.screenshotFolder))/<year-month>."
        case .archiveOldDownloads:
            return "Files that sat in Downloads for \(s.archiveDays) days move into Downloads/Archive/<year-month>."
        }
    }

    public var symbolName: String {
        switch self {
        case .trashOldInstallers: return "shippingbox"
        case .fileScreenshots: return "camera.viewfinder"
        case .archiveOldDownloads: return "archivebox"
        }
    }
}

/// "/Users/me/Pictures" → "~/Pictures".
public func tildePath(_ path: String, home: String = NSHomeDirectory()) -> String {
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}

public struct RuleSettings: Codable, Hashable, Sendable {
    public var installerDays = 30
    public var screenshotFolder: String
    public var screenshotMinAgeHours = 24
    public var archiveDays = 60

    public init(home: String = NSHomeDirectory()) {
        screenshotFolder = (home as NSString).appendingPathComponent("Pictures/Screenshots")
    }
}

public enum RuleOperation: Hashable, Codable, Sendable {
    case trash
    case move(toDirectory: String)
}

public struct RuleAction: Hashable, Sendable, Identifiable {
    public let rule: AutoRule
    public let item: FileItem
    public let operation: RuleOperation
    public var id: String { item.path }
}

public enum RulesPlanner {

    /// Folder name for a month, e.g. "2026-10 October".
    public static func monthFolderName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        let y = c.year ?? 1970, m = c.month ?? 1
        let name = DateSpec.monthNames[max(0, min(11, m - 1))].capitalized
        return String(format: "%04d-%02d", y, m) + " " + name
    }

    /// - Parameters:
    ///   - screenshotSources: folders screenshots land in (Desktop, or the user's custom screenshot folder).
    ///   - downloadsFolder: path of ~/Downloads.
    public static func plan(
        _ rule: AutoRule,
        items: [FileItem],
        settings: RuleSettings,
        screenshotSources: Set<String>,
        downloadsFolder: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RuleAction] {
        switch rule {
        case .trashOldInstallers:
            // Runs by itself, so it only touches installers that were downloaded (macOS marked them on arrival)
            // and still sit loose in Downloads. Disk images you made, and .iso files, are never touched.
            let cutoff = now.addingTimeInterval(-Double(settings.installerDays) * 86_400)
            return items.filter {
                $0.kind == .installer && !$0.isCloudOnly && $0.arrivalDate < cutoff && $0.ext != "iso"
                    && $0.parentPath == downloadsFolder
                    && ($0.quarantineAgent != nil || !$0.whereFroms.isEmpty)
            }
            .map { RuleAction(rule: rule, item: $0, operation: .trash) }
        case .fileScreenshots:
            let cutoff = now.addingTimeInterval(-Double(settings.screenshotMinAgeHours) * 3_600)
            return items.filter { $0.isScreenshot && !$0.isCloudOnly && screenshotSources.contains($0.parentPath) && $0.created < cutoff }
                .map {
                    let dir = (settings.screenshotFolder as NSString).appendingPathComponent(monthFolderName(for: $0.created, calendar: calendar))
                    return RuleAction(rule: rule, item: $0, operation: .move(toDirectory: dir))
                }
        case .archiveOldDownloads:
            let cutoff = now.addingTimeInterval(-Double(settings.archiveDays) * 86_400)
            let archiveRoot = (downloadsFolder as NSString).appendingPathComponent("Archive")
            return items.filter {
                $0.parentPath == downloadsFolder && $0.kind != .folder && !$0.isCloudOnly && $0.arrivalDate < cutoff
            }
            .map {
                let dir = (archiveRoot as NSString).appendingPathComponent(monthFolderName(for: $0.arrivalDate, calendar: calendar))
                return RuleAction(rule: rule, item: $0, operation: .move(toDirectory: dir))
            }
        }
    }

    /// "photo.png" → "photo 2.png" → "photo 3.png" … until `exists` says the name is free.
    public static func uniqueDestination(name: String, in directory: String, exists: (String) -> Bool) -> String {
        let first = (directory as NSString).appendingPathComponent(name)
        if !exists(first) { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let path = (directory as NSString).appendingPathComponent(candidate)
            if !exists(path) { return path }
            n += 1
        }
    }
}
