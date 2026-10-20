import Foundation

/// A rule you make yourself: "PDFs from Gmail with 'invoice' in them, in Downloads → move to Documents/Invoices".
/// Rules look only at files sitting directly in their folders, never inside your project folders.
public struct CustomRule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    /// Folders the rule watches (the files directly inside them).
    public var folders: [String]
    /// All of these must be true for a file.
    public var conditions: [RuleCondition]
    public var action: CustomRuleAction

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, folders: [String], conditions: [RuleCondition],
                action: CustomRuleAction) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.folders = folders
        self.conditions = conditions
        self.action = action
    }
}

public enum RuleCondition: Codable, Hashable, Sendable {
    /// Downloaded from a source (an id like "gmail"; "*" is any download).
    case source(String)
    case kind(FileKind)
    case nameContains(String)
    /// Text Haven read inside the file (screenshots, photos, PDFs, documents).
    case textContains(String)
    case extensionIs(String)
    /// Arrived (or was created) more than this many days ago.
    case olderThan(days: Int)
    /// Not opened for this many days (never opened counts from when it arrived).
    case notOpenedFor(days: Int)
    case biggerThan(megabytes: Int)
    case isScreenshot

    public enum Field: String, CaseIterable, Sendable, Identifiable {
        case source, kind, nameContains, textContains, extensionIs, olderThan, notOpenedFor, biggerThan, isScreenshot
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .source: return "Downloaded from"
            case .kind: return "Is a"
            case .nameContains: return "Name contains"
            case .textContains: return "Text inside contains"
            case .extensionIs: return "Extension is"
            case .olderThan: return "Arrived more than"
            case .notOpenedFor: return "Not opened for"
            case .biggerThan: return "Bigger than"
            case .isScreenshot: return "Is a screenshot"
            }
        }

        public var defaultCondition: RuleCondition {
            switch self {
            case .source: return .source("*")
            case .kind: return .kind(.pdf)
            case .nameContains: return .nameContains("")
            case .textContains: return .textContains("")
            case .extensionIs: return .extensionIs("")
            case .olderThan: return .olderThan(days: 30)
            case .notOpenedFor: return .notOpenedFor(days: 90)
            case .biggerThan: return .biggerThan(megabytes: 100)
            case .isScreenshot: return .isScreenshot
            }
        }
    }

    public var field: Field {
        switch self {
        case .source: return .source
        case .kind: return .kind
        case .nameContains: return .nameContains
        case .textContains: return .textContains
        case .extensionIs: return .extensionIs
        case .olderThan: return .olderThan
        case .notOpenedFor: return .notOpenedFor
        case .biggerThan: return .biggerThan
        case .isScreenshot: return .isScreenshot
        }
    }

    /// "comes from Gmail", "is a PDF", "has “invoice” in its text"…
    public var phrase: String {
        switch self {
        case .source(let id):
            if id == "*" { return "was downloaded" }
            return "comes from \(SourceClassifier.source(withID: id)?.name ?? id)"
        case .kind(let k):
            let word = k.displayName == k.displayName.uppercased() ? k.displayName : k.displayName.lowercased()
            return "is \(article(word)) \(word)"
        case .nameContains(let s): return "has “\(s)” in its name"
        case .textContains(let s): return "has “\(s)” in its text"
        case .extensionIs(let e): return "ends in .\(e.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
        case .olderThan(let d): return "arrived over \(HavenFormat.count(d, "day")) ago"
        case .notOpenedFor(let d): return "wasn't opened for \(HavenFormat.count(d, "day"))"
        case .biggerThan(let mb): return "is over \(mb) MB"
        case .isScreenshot: return "is a screenshot"
        }
    }

    /// A condition with nothing filled in yet (an empty word) matches nothing, so a half-made rule never acts.
    public var isComplete: Bool {
        switch self {
        case .nameContains(let s), .textContains(let s), .extensionIs(let s):
            return !s.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    private func article(_ word: String) -> String {
        guard let first = word.lowercased().first else { return "a" }
        return "aeio".contains(first) ? "an" : "a"
    }
}

public enum CustomRuleAction: Codable, Hashable, Sendable {
    /// Into a folder; with `byMonth`, into "2026-10 October" inside it.
    case move(to: String, byMonth: Bool)
    case rename(RenameTemplate)
    case addToCollection(UUID)
    case trash

    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case move, rename, addToCollection, trash
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .move: return "Move to a folder"
            case .rename: return "Rename"
            case .addToCollection: return "Add to a collection"
            case .trash: return "Move to the Trash"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .move: return .move
        case .rename: return .rename
        case .addToCollection: return .addToCollection
        case .trash: return .trash
        }
    }
}

/// What a rule would do to one file.
public struct CustomRuleStep: Identifiable, Hashable, Sendable {
    public let rule: UUID
    public let item: FileItem
    public let action: CustomRuleAction
    /// For moves: the folder the file goes into.
    public let destination: String?
    public var id: String { item.path }
}

public enum CustomRulePlanner {
    /// Extensions of files still being downloaded.
    static let partial: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload", "filepart"]

    public static func matches(_ item: FileItem, _ conditions: [RuleCondition], text: SearchEngine.TextLookup?,
                               now: Date) -> Bool {
        for c in conditions {
            guard c.isComplete else { return false }
            switch c {
            case .source(let id):
                guard let s = item.source else { return false }
                if id != "*" && s.id != id { return false }
            case .kind(let k):
                if item.kind != k { return false }
            case .nameContains(let s):
                if !TextMatch.contains(Array(FileItem.fold(s.trimmingCharacters(in: .whitespaces)).utf8), in: item.searchName) { return false }
            case .textContains(let s):
                guard item.kind.hasReadableText, let text, let content = text(item.path) else { return false }
                if !TextMatch.contains(Array(FileItem.fold(s.trimmingCharacters(in: .whitespaces)).utf8), in: content) { return false }
            case .extensionIs(let e):
                if item.ext != e.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) { return false }
            case .olderThan(let days):
                if now.timeIntervalSince(item.arrivalDate) < Double(days) * 86_400 { return false }
            case .notOpenedFor(let days):
                if now.timeIntervalSince(item.lastUsedDate) < Double(days) * 86_400 { return false }
            case .biggerThan(let mb):
                if item.size <= Int64(mb) * ByteSize.mb { return false }
            case .isScreenshot:
                if !item.isScreenshot { return false }
            }
        }
        return true
    }

    /// Everything the rule would do now. Files that changed in the last `settle` seconds are left for the
    /// next run (they may still be downloading).
    public static func plan(_ rule: CustomRule, items: [FileItem], text: SearchEngine.TextLookup? = nil, now: Date = Date(),
                            settle: TimeInterval = 15, calendar: Calendar = .current) -> [CustomRuleStep] {
        let folders = Set(rule.folders.map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 })
        guard !folders.isEmpty, !rule.conditions.isEmpty || rule.action != .trash else { return [] }
        let lengths = Set(folders.map(\.utf8.count))
        var steps: [CustomRuleStep] = []
        for item in items where item.kind != .folder && !item.isCloudOnly {
            guard let parentLength = IndexMerge.parentLength(item.path), lengths.contains(parentLength),
                  folders.contains(item.parentPath) else { continue }
            if partial.contains(item.ext) || now.timeIntervalSince(item.modified) < settle { continue }
            guard matches(item, rule.conditions, text: text, now: now) else { continue }
            switch rule.action {
            case .move(let to, let byMonth):
                let dir = byMonth ? (to as NSString).appendingPathComponent(RulesPlanner.monthFolderName(for: item.arrivalDate, calendar: calendar)) : to
                if dir == item.parentPath { continue }
                steps.append(CustomRuleStep(rule: rule.id, item: item, action: rule.action, destination: dir))
            default:
                steps.append(CustomRuleStep(rule: rule.id, item: item, action: rule.action, destination: nil))
            }
        }
        return steps
    }

    /// "Any file in Downloads that comes from Gmail and has “invoice” in its text: move to ~/Documents/Invoices."
    public static func describe(_ rule: CustomRule, collectionName: (UUID) -> String? = { _ in nil },
                                home: String = NSHomeDirectory()) -> String {
        let places = rule.folders.map { (($0 as NSString).lastPathComponent) }.joined(separator: " or ")
        var s = "Any file in \(places.isEmpty ? "no folder yet" : places)"
        let parts = rule.conditions.map(\.phrase)
        if !parts.isEmpty { s += " that " + joinedList(parts) }
        s += ": "
        switch rule.action {
        case .move(let to, let byMonth):
            s += "move to \(tildePath(to, home: home))" + (byMonth ? ", in a folder per month" : "")
        case .rename(let t):
            s += "rename to “\(t.pattern)”"
        case .addToCollection(let id):
            s += "add to “\(collectionName(id) ?? "a collection")”"
        case .trash:
            s += "move to the Trash"
        }
        return s + "."
    }

    static func joinedList(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        }
    }

    /// Ready-made rules to start from.
    public static func suggestions(home: String) -> [CustomRule] {
        func p(_ rel: String) -> String { (home as NSString).appendingPathComponent(rel) }
        return [
            CustomRule(name: "File invoices from Gmail", enabled: false, folders: [p("Downloads")],
                       conditions: [.source("gmail"), .textContains("invoice")],
                       action: .move(to: p("Documents/Invoices"), byMonth: false)),
            CustomRule(name: "Keep WhatsApp photos together", enabled: false, folders: [p("Downloads")],
                       conditions: [.source("whatsapp"), .kind(.image)],
                       action: .move(to: p("Pictures/WhatsApp"), byMonth: true)),
            CustomRule(name: "Name screenshots by what's in them", enabled: false, folders: [p("Desktop")],
                       conditions: [.isScreenshot],
                       action: .rename(.smart)),
            CustomRule(name: "Trash downloads untouched for 6 months", enabled: false, folders: [p("Downloads")],
                       conditions: [.olderThan(days: 180), .notOpenedFor(days: 180)],
                       action: .trash),
        ]
    }
}
