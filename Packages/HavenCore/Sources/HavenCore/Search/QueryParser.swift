import Foundation

/// Turns plain English ("pdfs from last week", "screenshots over 5 MB", "photos from whatsapp")
/// into a `SearchQuery` plus chips that show how the words were read.
public enum QueryParser {

    public static func parse(_ text: String, customRoots: [String: String] = [:]) -> ParsedQuery {
        let tokens = tokenize(text)
        var p = Parser(tokens: tokens, customRoots: customRoots)
        p.run()
        return ParsedQuery(text: text, query: p.query, chips: p.chips(), tokens: tokens)
    }

    // MARK: Tokenizing

    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        let quoteChars: Set<Character> = ["\"", "“", "”"]
        for ch in text {
            if quoteChars.contains(ch) {
                if inQuote {
                    if !current.isEmpty { tokens.append("\"" + current + "\"") }
                    current = ""
                    inQuote = false
                } else {
                    if !current.isEmpty { tokens.append(current) }
                    current = ""
                    inQuote = true
                }
            } else if ch.isWhitespace && !inQuote {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(inQuote ? "\"" + current + "\"" : current) }
        return tokens
    }

    static func normalize(_ token: String) -> String {
        var t = FileItem.fold(token)
        let trimSet = CharacterSet(charactersIn: ",;!?()[]{}")
        t = t.trimmingCharacters(in: trimSet)
        while t.hasSuffix("."), t.count > 1 { t.removeLast() }
        if t.hasSuffix("'s") || t.hasSuffix("’s") { t.removeLast(2) }
        return t
    }

    // MARK: Vocabulary

    enum TypeMatch {
        case kinds(Set<FileKind>, String)
        case screenshots
        case screenRecordings
        case ext(Set<String>, String)
    }

    static let documentKinds: Set<FileKind> = [.pdf, .document, .spreadsheet, .presentation, .text]

    static let typeWords: [String: TypeMatch] = {
        var m: [String: TypeMatch] = [:]
        func put(_ words: [String], _ match: TypeMatch) { for w in words { m[w] = match } }
        put(["pdf", "pdfs"], .kinds([.pdf], "PDFs"))
        put(["image", "images", "photo", "photos", "picture", "pictures", "pic", "pics", "img", "imgs", "graphics"], .kinds([.image], "Images"))
        put(["screenshot", "screenshots", "screengrab", "screengrabs", "screencap", "screencaps", "ss"], .screenshots)
        put(["video", "videos", "movie", "movies", "clip", "clips", "film", "films", "footage"], .kinds([.video], "Videos"))
        put(["music", "song", "songs", "audio", "track", "tracks", "sound", "sounds", "podcast", "podcasts", "recording", "recordings"], .kinds([.audio], "Music & audio"))
        put(["doc", "docs", "document", "documents", "paperwork"], .kinds(documentKinds, "Documents"))
        put(["spreadsheet", "spreadsheets", "sheet", "sheets", "excel", "workbook", "workbooks"], .kinds([.spreadsheet], "Spreadsheets"))
        put(["presentation", "presentations", "slide", "slides", "slideshow", "deck", "decks", "powerpoint", "powerpoints", "keynote", "keynotes"], .kinds([.presentation], "Presentations"))
        put(["zip", "zips", "archive", "archives", "compressed", "zipped"], .kinds([.archive], "Archives"))
        put(["installer", "installers", "dmg", "dmgs", "pkg", "pkgs", "setup"], .kinds([.installer], "Installers"))
        put(["app", "apps", "application", "applications", "program", "programs"], .kinds([.app], "Apps"))
        put(["font", "fonts", "typeface", "typefaces"], .kinds([.font], "Fonts"))
        put(["txt"], .kinds([.text], "Text files"))
        put(["code", "script", "scripts"], .kinds([.code], "Code"))
        put(["folder", "folders", "directory", "directories"], .kinds([.folder], "Folders"))
        put(["ebook", "ebooks"], .ext(["epub", "mobi"], "eBooks"))
        return m
    }()

    static let multiWordTypes: [([String], TypeMatch)] = [
        (["screen", "recordings"], .screenRecordings),
        (["screen", "recording"], .screenRecordings),
        (["screen", "shots"], .screenshots),
        (["screen", "shot"], .screenshots),
        (["text", "files"], .kinds([.text], "Text files")),
        (["text", "file"], .kinds([.text], "Text files")),
        (["source", "code"], .kinds([.code], "Code")),
        (["voice", "memos"], .kinds([.audio], "Music & audio")),
        (["voice", "notes"], .kinds([.audio], "Music & audio")),
        (["word", "documents"], .ext(["doc", "docx"], "Word documents")),
        (["word", "docs"], .ext(["doc", "docx"], "Word documents")),
        (["disk", "images"], .kinds([.installer], "Installers")),
    ]

    /// Extensions that may be typed bare ("png", "mp4s") to filter by file type.
    static let bareExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp", "svg", "raw", "dng", "psd", "bmp", "avif",
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "mp3", "m4a", "wav", "flac", "aac", "aiff", "ogg",
        "docx", "xlsx", "xls", "csv", "pptx", "ppt", "rtf", "epub", "json", "html", "rar", "7z", "iso", "tar", "gz", "md",
    ]

    static let extensionSynonyms: [String: Set<String>] = [
        "jpg": ["jpg", "jpeg"], "jpeg": ["jpg", "jpeg"], "tif": ["tif", "tiff"], "tiff": ["tif", "tiff"],
        "htm": ["htm", "html"], "html": ["htm", "html"], "aif": ["aif", "aiff"], "aiff": ["aif", "aiff"],
        "heic": ["heic", "heif"], "heif": ["heic", "heif"], "mpg": ["mpg", "mpeg"], "mpeg": ["mpg", "mpeg"],
        "md": ["md", "markdown"], "gz": ["gz", "tgz"],
    ]

    static func expandExtension(_ e: String) -> Set<String> { extensionSynonyms[e] ?? [e] }

    static let stopwords: Set<String> = [
        "the", "a", "an", "my", "all", "any", "some", "files", "file", "items", "item", "stuff", "things", "thing",
        "show", "me", "find", "get", "search", "for", "that", "which", "were", "was", "are", "is", "i", "with", "and",
        "or", "of", "please", "everything", "list", "named", "called", "about", "containing", "contain", "contains",
        "mentioning", "where", "what", "whats", "have", "has", "had", "to", "&", "+", "-", "–", "your", "our", "those", "these",
        "type", "kind", "kinds", "types", "saying", "says", "say", "text",
        // How people describe a file from memory: "the contract Sam sent", "where someone said budget".
        "sent", "someone", "somebody", "said", "mentioned", "mentions", "talked", "spoke", "he", "she", "they", "we", "it",
        "think", "maybe", "probably", "guess", "remember",
    ]

    /// Prepositions that never stand alone as search words.
    static let prepositions: Set<String> = ["from", "in", "on", "at", "via", "inside", "under", "during", "within", "since", "through", "by"]

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30,
        "few": 3, "several": 5, "couple": 2,
    ]

    static let timeUnits: [String: TimeUnit] = [
        "day": .day, "days": .day, "d": .day,
        "week": .week, "weeks": .week, "wk": .week, "wks": .week, "w": .week,
        "month": .month, "months": .month, "mo": .month, "mos": .month, "mth": .month, "mths": .month,
        "year": .year, "years": .year, "yr": .year, "yrs": .year, "y": .year,
    ]

    static let monthWords: [String: Int] = {
        var m: [String: Int] = [:]
        for (i, name) in DateSpec.monthNames.enumerated() {
            m[name] = i + 1
            m[String(name.prefix(3))] = i + 1
        }
        m["sept"] = 9
        return m
    }()

    static let weekdayWords: [String: Int] = {
        var m: [String: Int] = [:]
        for (i, name) in DateSpec.weekdayNames.enumerated() {
            m[name] = i + 1
            m[String(name.prefix(3))] = i + 1
        }
        m["tues"] = 3
        m["thurs"] = 5
        return m
    }()

    static let sizeUnits: [String: Int64] = [
        "b": 1, "byte": 1, "bytes": 1,
        "k": ByteSize.kb, "kb": ByteSize.kb, "kbs": ByteSize.kb, "kilobyte": ByteSize.kb, "kilobytes": ByteSize.kb,
        "m": ByteSize.mb, "mb": ByteSize.mb, "mbs": ByteSize.mb, "meg": ByteSize.mb, "megs": ByteSize.mb, "megabyte": ByteSize.mb, "megabytes": ByteSize.mb,
        "g": ByteSize.gb, "gb": ByteSize.gb, "gbs": ByteSize.gb, "gig": ByteSize.gb, "gigs": ByteSize.gb, "gigabyte": ByteSize.gb, "gigabytes": ByteSize.gb,
        "t": ByteSize.tb, "tb": ByteSize.tb, "terabyte": ByteSize.tb, "terabytes": ByteSize.tb,
    ]

    public static let standardRoots: [String: (id: String, name: String, bare: Bool)] = [
        "downloads": ("downloads", "Downloads", true),
        "download": ("downloads", "Downloads", false),
        "desktop": ("desktop", "Desktop", true),
        "documents": ("documents", "Documents", false),
        "docs": ("documents", "Documents", false),
        "pictures": ("pictures", "Pictures", false),
        "movies": ("movies", "Movies", false),
        "music": ("music", "Music", false),
        "applications": ("applications", "Applications", false),
        "apps": ("applications", "Applications", false),
    ]

    // MARK: Parser

    struct Parser {
        let raw: [String]
        let tok: [String]
        let customRoots: [String: String]
        var i = 0
        var query = SearchQuery()

        var typeLabels: [String] = []
        var typeIdx: [Int] = []
        var dateIdx: [Int] = []
        var dateFieldIdx: [Int] = []
        var sizeIdx: [Int] = []
        var sources: [(DownloadSource, [Int])] = []
        var roots: [(String, String, [Int])] = []
        var tagChips: [(String, [Int])] = []
        var termChips: [(String, [Int])] = []
        var sortIdx: [Int] = []

        init(tokens: [String], customRoots: [String: String]) {
            raw = tokens
            tok = tokens.map(QueryParser.normalize)
            self.customRoots = customRoots
        }

        func t(_ j: Int) -> String { j < tok.count && j >= 0 ? tok[j] : "" }

        mutating func run() {
            while i < tok.count {
                let w = tok[i]
                if w.isEmpty { i += 1; continue }
                if raw[i].hasPrefix("\"") {
                    let phrase = FileItem.fold(raw[i].trimmingCharacters(in: CharacterSet(charactersIn: "\"“”")))
                        .trimmingCharacters(in: .whitespaces)
                    if !phrase.isEmpty {
                        query.terms.append(phrase)
                        termChips.append((phrase, [i]))
                    }
                    i += 1
                    continue
                }
                if matchTag() || matchExtension() || matchSort() || matchDateField() || matchDate() || matchSize()
                    || matchSource() || matchLocation() || matchType() {
                    continue
                }
                // "the one with the wifi password"
                if w == "one", ["the", "that", "this"].contains(t(i - 1)) {
                    i += 1
                    continue
                }
                if QueryParser.stopwords.contains(w) || QueryParser.prepositions.contains(w) {
                    i += 1
                    continue
                }
                query.terms.append(w)
                termChips.append((w, [i]))
                i += 1
            }
            if query.date == nil, query.dateField == .added, !dateFieldIdx.isEmpty {
                if sources.isEmpty {
                    query.downloadedOnly = true
                } else {
                    // "downloaded from gmail": the verb belongs to the source chip.
                    sources[0].1 = dateFieldIdx + sources[0].1
                }
            }
            if query.date == nil { query.dateField = .activity }
        }

        // MARK: tags & extensions

        mutating func matchTag() -> Bool {
            let w = tok[i]
            var tag: String?
            var len = 1
            if w.hasPrefix("#"), w.count > 1 {
                tag = String(w.dropFirst())
            } else if w.hasPrefix("tag:"), w.count > 4 {
                tag = String(w.dropFirst(4))
            } else if (w == "tagged" || w == "tag"), i + 1 < tok.count, !t(i + 1).isEmpty {
                var j = i + 1
                if t(j) == "as" || t(j) == "with" { j += 1 }
                if j < tok.count, !t(j).isEmpty {
                    tag = t(j)
                    len = j - i + 1
                }
            }
            guard let found = tag, !found.isEmpty else { return false }
            query.tags.insert(found)
            tagChips.append((found, Array(i..<(i + len))))
            i += len
            return true
        }

        mutating func matchExtension() -> Bool {
            let w = tok[i]
            var ext: String?
            if w.hasPrefix("*."), w.count > 2 { ext = String(w.dropFirst(2)) }
            else if w.hasPrefix("ext:"), w.count > 4 { ext = String(w.dropFirst(4)) }
            else if w.hasPrefix("."), w.count > 1, w.count <= 8, w.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber }) { ext = String(w.dropFirst()) }
            else {
                var bare = w
                if bare.hasSuffix("s"), QueryParser.bareExtensions.contains(String(bare.dropLast())) { bare.removeLast() }
                if QueryParser.bareExtensions.contains(bare) { ext = bare }
            }
            guard let e = ext?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), !e.isEmpty else { return false }
            query.extensions.formUnion(QueryParser.expandExtension(e))
            appendTypeLabel("." + e.uppercased())
            typeIdx.append(i)
            i += 1
            return true
        }

        mutating func appendTypeLabel(_ label: String) {
            if !typeLabels.contains(label) { typeLabels.append(label) }
        }

        // MARK: sort

        mutating func matchSort() -> Bool {
            let w = tok[i]
            var hint: SortHint?
            var len = 1
            switch w {
            case "largest", "biggest", "heaviest": hint = .largest
            case "smallest", "lightest", "tiniest": hint = .smallest
            case "newest", "latest", "freshest": hint = .newest
            case "oldest", "earliest": hint = .oldest
            case "most" where t(i + 1) == "recent":
                hint = .newest
                len = 2
            default: break
            }
            guard let h = hint else { return false }
            query.sort = h
            sortIdx.append(contentsOf: i..<(i + len))
            i += len
            return true
        }

        // MARK: date

        mutating func matchDateField() -> Bool {
            let w = tok[i]
            let field: DateField?
            switch w {
            case "downloaded", "download", "saved", "received", "got": field = .added
            case "created", "made", "taken", "shot": field = .created
            case "modified", "edited", "changed", "updated": field = .modified
            case "opened", "used", "viewed", "accessed": field = .opened
            default: field = nil
            }
            guard let f = field else { return false }
            // "download" only counts as a verb when a date or source follows; "download folder" is a location.
            if w == "download", t(i + 1) == "folder" { return false }
            query.dateField = f
            dateFieldIdx.append(i)
            i += 1
            return true
        }

        func number(at j: Int) -> (Int, Int)? {
            let w = t(j)
            if let n = Int(w), n >= 0, n < 10_000 { return (n, 1) }
            if w == "couple", t(j + 1) == "of" { return (2, 2) }
            if let n = QueryParser.numberWords[w] { return (n, 1) }
            return nil
        }

        /// "3 days", "a week", "3days".
        func amount(at j: Int) -> (Int, TimeUnit, Int)? {
            if let (n, len) = number(at: j), let unit = QueryParser.timeUnits[t(j + len)] {
                return (n, unit, len + 1)
            }
            if t(j) == "fortnight" { return (2, .week, 1) }
            // glued: "3days", "2wks"
            let w = t(j)
            let digits = w.prefix(while: { $0.isNumber })
            if !digits.isEmpty, let n = Int(digits), let unit = QueryParser.timeUnits[String(w.dropFirst(digits.count))] {
                return (n, unit, 1)
            }
            return nil
        }

        func year(at j: Int) -> Int? {
            guard let y = Int(t(j)), y >= 1970, y <= 2100, t(j).count == 4 else { return nil }
            return y
        }

        /// Parses a date expression without a leading "since/before/after".
        /// `prefixed` is true when a preposition ("in", "from"…) came first, which unlocks bare years and months.
        func coreDate(at j: Int, prefixed: Bool, within: Bool) -> (DateSpec, Int)? {
            var j = j
            var skipped = 0
            if t(j) == "the" { j += 1; skipped = 1 }
            let w = t(j)
            switch w {
            case "today", "tonight": return (.today, skipped + 1)
            case "yesterday": return (.yesterday, skipped + 1)
            case "recent", "recently", "lately": return (.within(30, .day), skipped + 1)
            default: break
            }
            if w == "this" || w == "current" {
                switch t(j + 1) {
                case "week": return (.thisWeek, skipped + 2)
                case "month": return (.thisMonth, skipped + 2)
                case "year": return (.thisYear, skipped + 2)
                default: break
                }
                if let wd = QueryParser.weekdayWords[t(j + 1)] { return (.weekday(wd), skipped + 2) }
            }
            if w == "last" || w == "past" || w == "previous" || w == "prior" {
                if let (n, unit, len) = amount(at: j + 1) {
                    return (.within(n, unit), skipped + 1 + len)
                }
                switch t(j + 1) {
                case "week": return (w == "past" ? .within(1, .week) : .lastWeek, skipped + 2)
                case "month": return (w == "past" ? .within(1, .month) : .lastMonth, skipped + 2)
                case "year": return (w == "past" ? .within(1, .year) : .lastYear, skipped + 2)
                default: break
                }
                if let wd = QueryParser.weekdayWords[t(j + 1)] { return (.weekday(wd), skipped + 2) }
            }
            if w == "older" || w == "newer", t(j + 1) == "than", let (n, unit, len) = amount(at: j + 2) {
                return (w == "older" ? .olderThan(n, unit) : .within(n, unit), skipped + 2 + len)
            }
            if (w == "more" || w == "less") && t(j + 1) == "than", let (n, unit, len) = amount(at: j + 2), t(j + 2 + len) == "old" {
                return (w == "more" ? .olderThan(n, unit) : .within(n, unit), skipped + 3 + len)
            }
            if w == "over", let (n, unit, len) = amount(at: j + 1), t(j + 1 + len) == "old" {
                return (.olderThan(n, unit), skipped + 2 + len)
            }
            if (w == "old" || w == "older" || w == "stale") && t(j + 1) != "than" {
                return (.olderThan(6, .month), skipped + 1)
            }
            if let (n, unit, len) = amount(at: j) {
                if t(j + len) == "ago" { return (.ago(n, unit), skipped + len + 1) }
                if t(j + len) == "old" || t(j + len) == "older" { return (.olderThan(n, unit), skipped + len + 1) }
                if within { return (.within(n, unit), skipped + len) }
            }
            if let m = QueryParser.monthWords[w], w != "may" || prefixed || year(at: j + 1) != nil {
                // "mar" / "jan" as bare words are only months when followed by a year or after a preposition.
                let isAbbrev = w.count <= 4 && w != "june" && w != "july"
                if isAbbrev && !prefixed && year(at: j + 1) == nil && w != "sept" { return nil }
                if let y = year(at: j + 1) { return (.month(m, year: y), skipped + 2) }
                return (.month(m, year: nil), skipped + 1)
            }
            if prefixed, let y = year(at: j) { return (.year(y), skipped + 1) }
            if let wd = QueryParser.weekdayWords[w], w.count > 3 || prefixed {
                return (.weekday(wd), skipped + 1)
            }
            return nil
        }

        mutating func matchDate() -> Bool {
            let w = tok[i]
            var j = i
            var wrap: ((DateSpec) -> DateSpec)?
            var prefixed = false
            var within = false
            switch w {
            case "since", "after":
                wrap = w == "since" ? { .since($0) } : { .after($0) }
                j += 1
                prefixed = true
            case "before", "until", "till", "prior":
                if w == "prior", t(i + 1) != "to" { return false }
                wrap = { .before($0) }
                j += w == "prior" ? 2 : 1
                prefixed = true
            case "from", "in", "on", "during", "at", "within", "for":
                j += 1
                prefixed = true
                within = w == "within" || w == "for"
                if w == "in" && (t(j) == "the" && (t(j + 1) == "last" || t(j + 1) == "past")) { within = true }
            default:
                break
            }
            guard let (spec, len) = coreDate(at: j, prefixed: prefixed, within: within) else { return false }
            let final = wrap.map { $0(spec) } ?? spec
            query.date = final
            let end = j + len
            dateIdx.append(contentsOf: i..<end)
            i = end
            return true
        }

        // MARK: size

        func sizeValue(at j: Int, unitRequired: Bool) -> (Int64, Int)? {
            let w = t(j)
            // glued: "5mb", "1.5gb"
            let numPart = w.prefix(while: { $0.isNumber || $0 == "." })
            if !numPart.isEmpty, let v = Double(numPart) {
                let rest = String(w.dropFirst(numPart.count))
                if rest.isEmpty {
                    if let mult = QueryParser.sizeUnits[t(j + 1)] { return (Int64(v * Double(mult)), 2) }
                    return unitRequired ? nil : (Int64(v * Double(ByteSize.mb)), 1)
                }
                if let mult = QueryParser.sizeUnits[rest] { return (Int64(v * Double(mult)), 1) }
                return nil
            }
            if let n = QueryParser.numberWords[w], let mult = QueryParser.sizeUnits[t(j + 1)], w != "a" {
                return (Int64(n) * mult, 2)
            }
            return nil
        }

        mutating func matchSize() -> Bool {
            let w = tok[i]
            var j = i
            enum Cmp { case min, max }
            var cmp: Cmp?
            switch w {
            case "over", "above", ">", ">=", "≥", "min", "minimum":
                cmp = .min; j += 1
            case "under", "below", "<", "<=", "≤", "max", "maximum":
                cmp = .max; j += 1
            case "more", "bigger", "larger", "greater", "heavier":
                if t(i + 1) == "than" { cmp = .min; j += 2 }
            case "less", "smaller", "lighter", "fewer":
                if t(i + 1) == "than" { cmp = .max; j += 2 }
            case "at":
                if t(i + 1) == "least" { cmp = .min; j += 2 } else if t(i + 1) == "most" { cmp = .max; j += 2 }
            case "up":
                if t(i + 1) == "to" { cmp = .max; j += 2 }
            case "between":
                if let (a, la) = sizeValue(at: i + 1, unitRequired: false), t(i + 1 + la) == "and",
                   let (b, lb) = sizeValue(at: i + 2 + la, unitRequired: false) {
                    var lo = a, hi = b
                    // "between 5 and 10 mb": the first number borrows the second's unit.
                    if la == 1, Int64(t(i + 1)) != nil, lb == 2, let mult = QueryParser.sizeUnits[t(i + 3 + la)] {
                        lo = Int64((Double(t(i + 1)) ?? 0) * Double(mult))
                    }
                    if lo > hi { swap(&lo, &hi) }
                    query.minSize = lo
                    query.maxSize = hi
                    let end = i + 2 + la + lb
                    sizeIdx.append(contentsOf: i..<end)
                    i = end
                    return true
                }
                return false
            case "big", "large":
                query.minSize = 100 * ByteSize.mb
                sizeIdx.append(i)
                i += 1
                return true
            case "huge", "massive", "giant", "enormous":
                query.minSize = ByteSize.gb
                sizeIdx.append(i)
                i += 1
                return true
            case "small", "tiny", "little":
                query.maxSize = ByteSize.mb
                sizeIdx.append(i)
                i += 1
                return true
            default:
                break
            }
            if let c = cmp {
                guard let (v, len) = sizeValue(at: j, unitRequired: false) else { return false }
                if c == .min { query.minSize = v } else { query.maxSize = v }
                let end = j + len
                sizeIdx.append(contentsOf: i..<end)
                i = end
                return true
            }
            // Bare "5mb" / "2 gb": treat as "over".
            if let (v, len) = sizeValue(at: i, unitRequired: true) {
                query.minSize = v
                sizeIdx.append(contentsOf: i..<(i + len))
                i += len
                return true
            }
            return false
        }

        // MARK: source

        mutating func matchSource() -> Bool {
            let w = tok[i]
            if matchEmail() { return true }
            var j = i
            var prefixed = false
            if ["from", "via", "on", "through", "by", "using"].contains(w) {
                j += 1
                prefixed = true
            } else if (w == "sent" || w == "shared") && ["on", "via", "from", "through", "over", "by"].contains(t(i + 1)) {
                j += 2
                prefixed = true
            }
            if t(j) == "the" { j += 1 }
            // Two-word names first ("google drive").
            let pair = t(j) + " " + t(j + 1)
            if let s = SourceClassifier.source(forKeyword: pair), prefixed || SourceClassifier.multiWordKeywords.contains(pair) {
                add(source: s, end: j + 2)
                return true
            }
            let word = t(j)
            if let s = SourceClassifier.source(forKeyword: word), prefixed || SourceClassifier.bareKeywords.contains(word) {
                add(source: s, end: j + 1)
                return true
            }
            if prefixed, word.contains("."), !word.hasPrefix("."), word.split(separator: ".").count >= 2,
               word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
               let last = word.split(separator: ".").last, last.allSatisfy({ $0.isLetter }), last.count >= 2 {
                add(source: SourceClassifier.website(word), end: j + 1)
                return true
            }
            return false
        }

        /// "the invoice Sam emailed", "an email attachment", "from my inbox": anything that came from an inbox.
        mutating func matchEmail() -> Bool {
            let w = tok[i]
            if SourceClassifier.emailedWords.contains(w) {
                addEmail(end: i + 1)
                return true
            }
            if SourceClassifier.emailWords.contains(w), SourceClassifier.emailedWords.contains(t(i + 1)) {
                addEmail(end: i + 2)
                return true
            }
            guard ["from", "via", "by", "through", "in", "on"].contains(w) else { return false }
            var j = i + 1
            if ["my", "the", "an", "a"].contains(t(j)) { j += 1 }
            guard SourceClassifier.emailWords.contains(t(j)) || SourceClassifier.emailedWords.contains(t(j)) else { return false }
            addEmail(end: SourceClassifier.emailedWords.contains(t(j + 1)) ? j + 2 : j + 1)
            return true
        }

        mutating func addEmail(end: Int) {
            query.sourceIDs.formUnion(SourceClassifier.emailSourceIDs)
            sources.append((DownloadSource(id: "email", name: "email", symbol: "envelope", tint: .blue), Array(i..<end)))
            i = end
        }

        mutating func add(source: DownloadSource, end: Int) {
            query.sourceIDs.insert(source.id)
            sources.append((source, Array(i..<end)))
            i = end
        }

        // MARK: location

        mutating func matchLocation() -> Bool {
            let w = tok[i]
            var j = i
            var prefixed = false
            if ["in", "on", "at", "inside", "from", "under", "within"].contains(w) {
                j += 1
                prefixed = true
            }
            if t(j) == "my" || t(j) == "the" { j += 1 }
            let word = t(j)
            var len = 1
            if t(j + 1) == "folder" || t(j + 1) == "dir" || t(j + 1) == "directory" { len = 2 }
            if let custom = customRoots[word], prefixed || len == 2 {
                addRoot(id: custom, name: raw[j].capitalized, end: j + len)
                return true
            }
            guard let root = QueryParser.standardRoots[word] else { return false }
            if !(prefixed || len == 2 || root.bare) { return false }
            addRoot(id: root.id, name: root.name, end: j + len)
            return true
        }

        mutating func addRoot(id: String, name: String, end: Int) {
            query.rootIDs.insert(id)
            if !roots.contains(where: { $0.0 == id }) { roots.append((id, name, Array(i..<end))) }
            i = end
        }

        // MARK: type

        mutating func matchType() -> Bool {
            for (words, match) in QueryParser.multiWordTypes {
                if words.enumerated().allSatisfy({ t(i + $0.offset) == $0.element }) {
                    apply(match)
                    typeIdx.append(contentsOf: i..<(i + words.count))
                    i += words.count
                    return true
                }
            }
            guard let match = QueryParser.typeWords[tok[i]] else { return false }
            apply(match)
            typeIdx.append(i)
            i += 1
            return true
        }

        mutating func apply(_ match: TypeMatch) {
            switch match {
            case .kinds(let kinds, let label):
                query.kinds.formUnion(kinds)
                appendTypeLabel(label)
            case .screenshots:
                query.screenshots = true
                appendTypeLabel("Screenshots")
            case .screenRecordings:
                query.screenRecordings = true
                appendTypeLabel("Screen recordings")
            case .ext(let exts, let label):
                query.extensions.formUnion(exts)
                appendTypeLabel(label)
            }
        }

        // MARK: chips

        func chips() -> [QueryChip] {
            var out: [QueryChip] = []
            if !typeLabels.isEmpty {
                let symbol: String
                if (query.screenshots || query.screenRecordings) && query.kinds.isEmpty { symbol = "camera.viewfinder" }
                else if query.kinds.count == 1, let k = query.kinds.first { symbol = k.symbolName }
                else { symbol = "square.grid.2x2" }
                out.append(QueryChip(kind: .type, label: typeLabels.joined(separator: " + "), symbol: symbol, tokenIndexes: typeIdx))
            }
            for (s, idx) in sources {
                out.append(QueryChip(kind: .source, label: "From \(s.name)", symbol: s.symbol, tokenIndexes: idx))
            }
            if let d = query.date {
                var label = d.label
                if let verb = query.dateField.verb { label = "\(verb) \(label.lowercasedFirst)" }
                out.append(QueryChip(kind: .date, label: label, symbol: "calendar", tokenIndexes: dateFieldIdx + dateIdx))
            } else if query.downloadedOnly {
                out.append(QueryChip(kind: .downloaded, label: "Downloaded", symbol: "arrow.down.circle", tokenIndexes: dateFieldIdx))
            }
            if query.minSize != nil || query.maxSize != nil {
                let label: String
                switch (query.minSize, query.maxSize) {
                case let (lo?, hi?): label = "\(ByteSize.format(lo)) – \(ByteSize.format(hi))"
                case let (lo?, nil): label = "Over \(ByteSize.format(lo))"
                case let (nil, hi?): label = "Under \(ByteSize.format(hi))"
                default: label = ""
                }
                out.append(QueryChip(kind: .size, label: label, symbol: "scalemass", tokenIndexes: sizeIdx))
            }
            for (_, name, idx) in roots {
                out.append(QueryChip(kind: .location, label: "In \(name)", symbol: "folder", tokenIndexes: idx))
            }
            for (tag, idx) in tagChips {
                out.append(QueryChip(kind: .tag, label: "#\(tag)", symbol: "tag", tokenIndexes: idx))
            }
            for (term, idx) in termChips {
                out.append(QueryChip(kind: .text, label: "“\(term)”", symbol: "text.magnifyingglass", tokenIndexes: idx))
            }
            if let s = query.sort {
                out.append(QueryChip(kind: .sort, label: s.label, symbol: "arrow.up.arrow.down", tokenIndexes: sortIdx))
            }
            return out
        }
    }
}
