import Foundation

/// How a batch of files gets new names. The pattern mixes plain text with tokens:
///
///     {name}    the current name, without its extension
///     {title}   a title read from the file's text ("Invoice 4821"), or the current name when there's no text
///     {date}    2026-10-12 (which date: `dateField`)      {time}  14.05
///     {n}       a counter (1, 2, 3…); {n:3} pads it to 001, 002…
///     {source}  where it was downloaded from ("Gmail")    {folder}  the enclosing folder    {kind}  "PDF"
///
/// The extension always stays as it is.
public struct RenameTemplate: Codable, Hashable, Sendable {
    public enum DateField: String, Codable, CaseIterable, Sendable, Identifiable {
        case created, modified, added, taken
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .created: return "Date created"
            case .modified: return "Date modified"
            case .added: return "Date added"
            case .taken: return "Date taken (photos)"
            }
        }
    }

    public enum CaseStyle: String, Codable, CaseIterable, Sendable, Identifiable {
        case keep, lower, upper, title
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .keep: return "Keep as typed"
            case .lower: return "lowercase"
            case .upper: return "UPPERCASE"
            case .title: return "Title Case"
            }
        }
    }

    public var pattern: String
    public var dateField: DateField
    public var counterStart: Int
    /// Plain text to find in the new name (not case-sensitive) and what to put instead.
    public var find: String
    public var replace: String
    public var caseStyle: CaseStyle

    public init(pattern: String = "{name}", dateField: DateField = .created, counterStart: Int = 1,
                find: String = "", replace: String = "", caseStyle: CaseStyle = .keep) {
        self.pattern = pattern
        self.dateField = dateField
        self.counterStart = counterStart
        self.find = find
        self.replace = replace
        self.caseStyle = caseStyle
    }

    /// "2026-10-12 Invoice 4821.pdf": the date first so names sort by time.
    public static let smart = RenameTemplate(pattern: "{date} {title}")
    public static let addDate = RenameTemplate(pattern: "{date} {name}")
    public static let numbered = RenameTemplate(pattern: "{name} {n}")
    public static let findReplace = RenameTemplate(pattern: "{name}")

    public var usesText: Bool { pattern.contains("{title}") }
    public var usesTakenDate: Bool { dateField == .taken && (pattern.contains("{date}") || pattern.contains("{time}")) }
}

/// One file's new name.
public struct RenameChange: Hashable, Sendable, Identifiable {
    public let item: FileItem
    public let newName: String
    /// A number was added to keep the name unique in its folder.
    public let adjusted: Bool

    public var id: String { item.path }
    public var newPath: String { (item.parentPath as NSString).appendingPathComponent(newName) }
    public var isChange: Bool { newName != item.name }
}

/// What the planner may need to know beyond the file record itself.
public struct RenameContext: Sendable {
    public var text: @Sendable (FileItem) -> String?
    public var takenDate: @Sendable (FileItem) -> Date?
    public var timeZone: TimeZone

    public init(text: @escaping @Sendable (FileItem) -> String? = { _ in nil },
                takenDate: @escaping @Sendable (FileItem) -> Date? = { _ in nil },
                timeZone: TimeZone = .current) {
        self.text = text
        self.takenDate = takenDate
        self.timeZone = timeZone
    }
}

public enum RenamePlanner {
    static let separators: Set<Character> = [" ", "-", "–", "—", "_", "·", ","]

    /// New names for `items` (in the order given, which is the order the counter runs in).
    /// - Parameter existing: names already in a folder (as they are on disk), to never take one of them.
    public static func plan(_ items: [FileItem], template: RenameTemplate, context: RenameContext = RenameContext(),
                            existing: (String) -> [String]) -> [RenameChange] {
        let dayFormat = formatter("yyyy-MM-dd", context.timeZone)
        let timeFormat = formatter("HH.mm", context.timeZone)
        var desired: [String] = []
        desired.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            let (base, ext) = split(item)
            var newBase = render(template, item: item, base: base, index: index, context: context, day: dayFormat, time: timeFormat)
            newBase = apply(find: template.find, replace: template.replace, to: newBase)
            newBase = applyCase(template.caseStyle, newBase)
            newBase = sanitize(newBase, ext: ext)
            if newBase.isEmpty { newBase = base }
            desired.append(join(newBase, ext))
        }

        // Names taken in each folder: what's on disk, minus the files being renamed (they move out of the way).
        var taken: [String: Set<String>] = [:]
        var leaving: [String: Set<String>] = [:]
        for item in items { leaving[item.parentPath, default: []].insert(key(item.name)) }
        for (dir, names) in leaving {
            taken[dir] = Set(existing(dir).map(key)).subtracting(names)
        }

        var result = [RenameChange?](repeating: nil, count: items.count)
        // Files that keep their name claim it first, so nobody else is given it.
        for pass in 0..<2 {
            for (i, item) in items.enumerated() {
                let keeps = desired[i] == item.name
                guard (pass == 0) == keeps else { continue }
                let dir = item.parentPath
                var name = desired[i]
                var adjusted = false
                if taken[dir, default: []].contains(key(name)) {
                    name = free(name, isFolder: item.kind == .folder) { taken[dir, default: []].contains(key($0)) }
                    adjusted = true
                }
                taken[dir, default: []].insert(key(name))
                result[i] = RenameChange(item: item, newName: name, adjusted: adjusted)
            }
        }
        return result.compactMap { $0 }
    }

    /// Names compare without case (the Mac's disks don't tell "Photo" and "photo" apart).
    static func key(_ name: String) -> String { name.lowercased() }

    /// The name split into base and extension, keeping the extension's own spelling. Folders have no extension.
    public static func split(_ item: FileItem) -> (base: String, ext: String) {
        guard item.kind != .folder, !item.ext.isEmpty else { return (item.name, "") }
        let ext = (item.name as NSString).pathExtension
        let base = String(item.name.dropLast(ext.count + 1))
        return base.isEmpty ? (item.name, "") : (base, ext)
    }

    static func join(_ base: String, _ ext: String) -> String { ext.isEmpty ? base : base + "." + ext }

    static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    static func date(_ item: FileItem, _ field: RenameTemplate.DateField, _ context: RenameContext) -> Date {
        switch field {
        case .created: return item.created
        case .modified: return item.modified
        case .added: return item.added ?? item.created
        case .taken: return context.takenDate(item) ?? item.created
        }
    }

    enum Part {
        case literal(String)
        case value(String)
    }

    /// Fills in the pattern; tokens that come out empty take their separator with them.
    static func render(_ t: RenameTemplate, item: FileItem, base: String, index: Int, context: RenameContext,
                       day: DateFormatter, time: DateFormatter) -> String {
        var parts: [Part] = []
        var literal = ""
        var rest = Substring(t.pattern)
        while let open = rest.firstIndex(of: "{") {
            literal += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { break }
            let token = rest[rest.index(after: open)..<close].lowercased()
            if let value = resolve(token, t: t, item: item, base: base, index: index, context: context, day: day, time: time) {
                if !literal.isEmpty { parts.append(.literal(literal)) }
                literal = ""
                parts.append(.value(value))
            } else {
                // Not a token: keep the braces as typed.
                literal += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        literal += rest
        if !literal.isEmpty { parts.append(.literal(literal)) }

        var out: [Part] = []
        for p in parts {
            if case .value(let v) = p, v.isEmpty { continue }
            if case .literal(let l) = p, let last = out.last, case .literal(let prev) = last {
                // Two pieces of text met where a token went missing: keep one separator, not both.
                if isSeparator(prev) && isSeparator(l) {
                    out[out.count - 1] = .literal(prev.count >= l.count ? prev : l)
                } else {
                    out[out.count - 1] = .literal(prev + l)
                }
                continue
            }
            out.append(p)
        }
        if case .literal(let l)? = out.first, isSeparator(l), out.count > 1 { out.removeFirst() }
        if case .literal(let l)? = out.last, isSeparator(l), out.count > 1 { out.removeLast() }
        return out.map { p -> String in
            switch p {
            case .literal(let s), .value(let s): return s
            }
        }.joined()
    }

    static func isSeparator(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { separators.contains($0) } }

    static func resolve(_ token: String, t: RenameTemplate, item: FileItem, base: String, index: Int, context: RenameContext,
                        day: DateFormatter, time: DateFormatter) -> String? {
        switch token {
        case "name": return base
        case "title":
            if item.kind.hasReadableText, let text = context.text(item), let title = SmartTitle.title(from: text) { return title }
            return base
        case "date": return day.string(from: date(item, t.dateField, context))
        case "time": return time.string(from: date(item, t.dateField, context))
        case "source": return item.source?.name ?? ""
        case "folder": return item.parentName
        case "kind": return item.kind.displayName
        default:
            guard token == "n" || token.hasPrefix("n:") else { return nil }
            let pad = token.hasPrefix("n:") ? max(1, min(9, Int(token.dropFirst(2)) ?? 1)) : 1
            let n = t.counterStart + index
            let digits = String(abs(n))
            let padded = digits.count >= pad ? digits : String(repeating: "0", count: pad - digits.count) + digits
            return n < 0 ? "-" + padded : padded
        }
    }

    static func apply(find: String, replace: String, to s: String) -> String {
        guard !find.isEmpty else { return s }
        return s.replacingOccurrences(of: find, with: replace, options: [.caseInsensitive, .literal])
    }

    static func applyCase(_ style: RenameTemplate.CaseStyle, _ s: String) -> String {
        switch style {
        case .keep: return s
        case .lower: return s.lowercased()
        case .upper: return s.uppercased()
        case .title:
            return s.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst().lowercased()
            }.joined(separator: " ")
        }
    }

    /// A name macOS accepts and Finder shows cleanly: no slashes or colons, no leading dot, not too long.
    static func sanitize(_ raw: String, ext: String) -> String {
        var s = String(raw.map { c -> Character in
            if c == "/" || c == ":" { return "-" }
            if c.isNewline || c == "\t" { return " " }
            return c
        })
        s = s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        // Typed the extension too ("report.pdf"): don't end up with "report.pdf.pdf".
        if !ext.isEmpty, s.lowercased().hasSuffix("." + ext.lowercased()), s.count > ext.count + 1 {
            s = String(s.dropLast(ext.count + 1))
        }
        // File names can be 255 bytes long; leave room for the extension and a " 99".
        let budget = 250 - ext.utf8.count - 4
        if s.utf8.count > budget {
            var cut = ""
            for ch in s {
                if cut.utf8.count + String(ch).utf8.count > budget { break }
                cut.append(ch)
            }
            s = cut.trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// "photo.png" → "photo 2.png" → "photo 3.png"… until `isTaken` says no.
    static func free(_ name: String, isFolder: Bool, isTaken: (String) -> Bool) -> String {
        let ext = isFolder ? "" : (name as NSString).pathExtension
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var n = 2
        while true {
            let candidate = join("\(base) \(n)", ext)
            if !isTaken(candidate) { return candidate }
            n += 1
        }
    }

    /// Renames that can't run one by one (a new name is another file's current name) go through
    /// temporary names first. Returns true when that's needed.
    public static func needsTwoSteps(_ changes: [RenameChange]) -> Bool {
        let current = Set(changes.map { key($0.item.path) })
        return changes.contains { $0.isChange && current.contains(key($0.newPath)) }
    }
}

/// Picks a short, readable title from the text Haven read in a file (OCR or PDF/document text).
public enum SmartTitle {
    static let noise = ["page ", "http", "www.", "@", "copyright", "©", "all rights reserved", "confidential"]

    public static func title(from text: String, maxWords: Int = 6, maxLength: Int = 50) -> String? {
        var looked = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            looked += 1
            if looked > 15 { break }
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if noise.contains(where: { lower.hasPrefix($0) || lower.contains("://") }) { continue }
            let letters = line.filter(\.isLetter).count
            guard letters >= 3, Double(letters) / Double(max(1, line.count)) >= 0.4 else { continue }
            if let cleaned = clean(line, maxWords: maxWords, maxLength: maxLength), cleaned.filter(\.isLetter).count >= 3 {
                return cleaned
            }
        }
        return nil
    }

    static func clean(_ line: String, maxWords: Int, maxLength: Int) -> String? {
        let allowedPunctuation: Set<Character> = ["&", "-", "'", "#", "+", ".", ",", "(", ")", "%"]
        let mapped = String(line.map { c -> Character in
            if c.isLetter || c.isNumber || c == " " || allowedPunctuation.contains(c) { return c }
            return " "
        })
        var words = mapped.split(separator: " ").map(String.init)
        // Strip punctuation hanging off the ends of words ("Total:" → "Total", "(draft)" stays).
        words = words.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,-'")) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let shouting = line.contains(where: \.isLetter) && !line.contains(where: \.isLowercase)
        if shouting {
            words = words.map { w in
                w.contains(where: \.isNumber) ? w : w.prefix(1).uppercased() + w.dropFirst().lowercased()
            }
        }
        var out = ""
        for w in words.prefix(maxWords) {
            let next = out.isEmpty ? w : out + " " + w
            if next.count > maxLength { break }
            out = next
        }
        if out.isEmpty { out = String(words[0].prefix(maxLength)) }
        return out
    }
}
