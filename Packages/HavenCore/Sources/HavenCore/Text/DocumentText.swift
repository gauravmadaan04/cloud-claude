import Foundation

/// Text inside office documents and e-books, read straight from their ZIP and XML (no Office or Pages needed):
/// Word (.docx), Excel (.xlsx), PowerPoint (.pptx), OpenDocument (.odt .ods .odp) and EPUB.
public enum DocumentText {
    /// Extensions this reader handles.
    public static let zippedExtensions: Set<String> = ["docx", "dotx", "xlsx", "xlsm", "pptx", "ppsx", "odt", "ods", "odp", "epub"]
    /// iWork files carry a picture of their first page, which Haven reads with OCR.
    public static let iWorkExtensions: Set<String> = ["pages", "numbers", "key"]
    public static let iWorkPreviewNames = ["preview.jpg", "QuickLook/Thumbnail.jpg", "preview-web.jpg", "QuickLook/Preview.jpg"]

    public static func extract(url: URL, limit: Int = 60_000) -> String? {
        guard let zip = try? ZipArchive(url: url) else { return nil }
        return extract(zip: zip, ext: url.pathExtension.lowercased(), limit: limit)
    }

    public static func extract(zip: ZipArchive, ext: String, limit: Int = 60_000) -> String? {
        var parts: [String] = []
        var total = 0
        func add(_ name: String, html: Bool = false) {
            guard total < limit, let bytes = zip.read(named: name, limit: 8 << 20) else { return }
            let text = xmlText(bytes, html: html, limit: limit - total)
            guard !text.isEmpty else { return }
            parts.append(text)
            total += text.count
        }
        switch ext {
        case "docx", "dotx":
            add("word/document.xml")
        case "xlsx", "xlsm":
            // Sheet names, then every piece of text the workbook holds.
            if let wb = zip.read(named: "xl/workbook.xml", limit: 2 << 20) {
                let names = attributeValues(wb, element: "sheet", attribute: "name")
                if !names.isEmpty { parts.append(names.joined(separator: "\n")) }
            }
            add("xl/sharedStrings.xml")
        case "pptx", "ppsx":
            let slides = zip.entries.map(\.name).filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            for name in slides.sorted(by: { number(in: $0) < number(in: $1) }) { add(name) }
        case "odt", "ods", "odp":
            add("content.xml")
        case "epub":
            let pages = zip.entries.map(\.name).filter {
                let l = $0.lowercased()
                return (l.hasSuffix(".xhtml") || l.hasSuffix(".html") || l.hasSuffix(".htm")) && !l.contains("nav.") && !l.contains("toc.")
            }
            for name in pages.sorted(by: { NaturalOrder.compare(NaturalOrder.key($0.lowercased()), NaturalOrder.key($1.lowercased())) < 0 }) {
                add(name, html: true)
            }
        default:
            return nil
        }
        let joined = parts.joined(separator: "\n")
        return joined.isEmpty ? nil : String(joined.prefix(limit))
    }

    /// The first-page picture inside an iWork file (a ZIP, or a folder package).
    public static func iWorkPreview(url: URL) -> Data? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            for name in iWorkPreviewNames {
                if let d = try? Data(contentsOf: url.appendingPathComponent(name)) { return d }
            }
            return nil
        }
        guard let zip = try? ZipArchive(url: url) else { return nil }
        for name in iWorkPreviewNames {
            if let bytes = zip.read(named: name, limit: 20 << 20) { return Data(bytes) }
        }
        return nil
    }

    static func number(in name: String) -> Int {
        Int(name.filter(\.isNumber)) ?? 0
    }

    // MARK: XML

    /// Elements that end a line of text.
    static let lineBreaks: Set<String> = [
        "w:p", "a:p", "text:p", "text:h", "si", "p", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6",
        "br", "w:br", "a:br", "text:line-break", "w:cr", "title", "dt", "dd", "blockquote", "section",
    ]
    /// Elements that stand for a gap between words.
    static let gaps: Set<String> = ["w:tab", "text:tab", "text:s", "td", "th", "a:tab"]

    /// The text of an XML or HTML document: tags dropped, entities decoded, paragraphs on their own lines.
    public static func xmlText(_ bytes: [UInt8], html: Bool = false, limit: Int = 60_000) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(min(bytes.count, limit * 2))
        let n = bytes.count
        var i = 0
        func newline() {
            if let last = out.last, last != 10 { out.append(10) }
        }
        func space() {
            if let last = out.last, last != 32, last != 10 { out.append(32) }
        }
        /// Index just past the next `marker` (ASCII letters match in either case).
        func skip(past marker: [UInt8], from start: Int) -> Int {
            @inline(__always) func lower(_ c: UInt8) -> UInt8 { c >= 65 && c <= 90 ? c + 32 : c }
            var j = start
            outer: while j + marker.count <= n {
                for k in 0..<marker.count where lower(bytes[j + k]) != lower(marker[k]) {
                    j += 1
                    continue outer
                }
                return j + marker.count
            }
            return n
        }
        while i < n && out.count < limit * 2 {
            let b = bytes[i]
            if b == 60 { // <
                if i + 3 < n && bytes[i + 1] == 33 && bytes[i + 2] == 45 && bytes[i + 3] == 45 { // <!--
                    i = skip(past: Array("-->".utf8), from: i + 4)
                    continue
                }
                if i + 8 < n && Array(bytes[(i + 1)..<(i + 9)]) == Array("![CDATA[".utf8) {
                    let end = skip(past: Array("]]>".utf8), from: i + 9)
                    let stopAt = max(i + 9, end - 3)
                    out.append(contentsOf: bytes[(i + 9)..<stopAt])
                    i = end
                    continue
                }
                var j = i + 1
                let closing = j < n && bytes[j] == 47
                if closing { j += 1 }
                let nameStart = j
                while j < n && bytes[j] != 62 && bytes[j] != 32 && bytes[j] != 47 && bytes[j] != 10 && bytes[j] != 9 && bytes[j] != 13 { j += 1 }
                let name = String(decoding: bytes[nameStart..<j], as: UTF8.self).lowercased()
                // Find the end of the tag (quotes may hold ">").
                var quote: UInt8 = 0
                while j < n {
                    let c = bytes[j]
                    if quote != 0 {
                        if c == quote { quote = 0 }
                    } else if c == 34 || c == 39 {
                        quote = c
                    } else if c == 62 {
                        break
                    }
                    j += 1
                }
                let selfClosing = j > 0 && j - 1 < n && bytes[j - 1] == 47
                i = j + 1
                if html && !closing && (name == "script" || name == "style") {
                    i = skip(past: Array("</\(name)".utf8), from: i)
                    i = skip(past: [62], from: i)
                    continue
                }
                if lineBreaks.contains(name) && (closing || selfClosing || name == "br") {
                    newline()
                } else if gaps.contains(name) {
                    space()
                }
                continue
            }
            if b == 38 { // &
                var j = i + 1
                while j < n && j - i < 12 && bytes[j] != 59 && bytes[j] != 60 { j += 1 }
                if j < n && bytes[j] == 59 {
                    let entity = String(decoding: bytes[(i + 1)..<j], as: UTF8.self)
                    if let scalar = decodeEntity(entity) {
                        out.append(contentsOf: Array(String(Character(scalar)).utf8))
                        i = j + 1
                        continue
                    }
                }
                out.append(b)
                i += 1
                continue
            }
            if b == 13 || b == 9 || b == 10 {
                space()
            } else {
                out.append(b)
            }
            i += 1
        }
        let text = String(decoding: out, as: UTF8.self)
        // Tidy up: no runs of spaces, no blank lines.
        let lines = text.split(separator: "\n").map { line -> String in
            line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }.filter { !$0.isEmpty }
        return String(lines.joined(separator: "\n").prefix(limit))
    }

    static let named: [String: Unicode.Scalar] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
        "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "copy": "©", "reg": "®", "euro": "€",
        "pound": "£", "rupee": "₹", "middot": "·", "bull": "•", "eacute": "é", "egrave": "è", "aacute": "á", "uuml": "ü",
        "ouml": "ö", "auml": "ä", "szlig": "ß", "ccedil": "ç", "ntilde": "ñ",
    ]

    static func decodeEntity(_ e: String) -> Unicode.Scalar? {
        if e.hasPrefix("#x") || e.hasPrefix("#X") { return UInt32(e.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init) }
        if e.hasPrefix("#") { return UInt32(e.dropFirst()).flatMap(Unicode.Scalar.init) }
        return named[e.lowercased()]
    }

    /// Values of one attribute on every element with that name: `<sheet name="Budget" …>` → "Budget".
    static func attributeValues(_ bytes: [UInt8], element: String, attribute: String) -> [String] {
        let text = String(decoding: bytes, as: UTF8.self)
        var out: [String] = []
        var rest = Substring(text)
        let open = "<" + element + " "
        let key = attribute + "=\""
        while let r = rest.range(of: open) {
            rest = rest[r.upperBound...]
            guard let end = rest.firstIndex(of: ">") else { break }
            let tag = rest[..<end]
            if let k = tag.range(of: key), let close = tag[k.upperBound...].firstIndex(of: "\"") {
                let raw = String(tag[k.upperBound..<close])
                out.append(xmlText(Array(raw.utf8)))
            }
            rest = rest[end...]
        }
        return out
    }
}
