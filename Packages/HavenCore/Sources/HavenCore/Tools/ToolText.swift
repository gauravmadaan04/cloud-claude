import Foundation

/// Names for what the tools make (before Haven makes them unique in their folder).
public enum ToolNaming {
    static func base(_ item: FileItem) -> String { RenamePlanner.split(item).base }
    static func originalExt(_ item: FileItem) -> String { RenamePlanner.split(item).ext }

    /// "photo.png" (or "photo (converted).png" if it already was a PNG).
    public static func converted(_ item: FileItem, ext: String) -> String {
        let same = item.ext == ext.lowercased() || (ImageFormat.of(item.ext) != nil && ImageFormat.of(item.ext) == ImageFormat.of(ext))
        return base(item) + (same ? " (converted)" : "") + "." + ext
    }

    /// "photo (rotated).jpg", or with a new extension: "photo (cut out).png".
    public static func tagged(_ item: FileItem, _ tag: String, ext: String? = nil) -> String {
        let e = ext ?? originalExt(item)
        return base(item) + " (\(tag))" + (e.isEmpty ? "" : "." + e)
    }

    /// "Report (merged).pdf": named after the first file.
    public static func merged(_ items: [FileItem], ext: String) -> String {
        guard let first = items.first else { return "Merged.\(ext)" }
        return base(first) + " (merged).\(ext)"
    }

    /// The folder for many outputs: "Report (pages)".
    public static func folder(_ item: FileItem, _ tag: String) -> String { base(item) + " (\(tag))" }

    /// "Report - page 03.pdf" (numbers padded so they sort in order).
    public static func page(_ base: String, _ index: Int, of total: Int, ext: String) -> String {
        let digits = max(2, String(total).count)
        let n = String(index + 1)
        return "\(base) - page \(String(repeating: "0", count: max(0, digits - n.count)))\(n).\(ext)"
    }

    /// "Scan.pdf" for one image, "Scan (3 pages).pdf" for several.
    public static func pdfFromImages(_ items: [FileItem]) -> String {
        guard let first = items.first else { return "Images.pdf" }
        return items.count == 1 ? base(first) + ".pdf" : base(first) + " (\(items.count) pages).pdf"
    }

    public static func base(of item: FileItem) -> String { base(item) }
}

/// Page lists typed by people: "1-3, 5, 8-".
public enum PageRange {
    /// Zero-based pages in the order typed (no repeats), or nil if something doesn't make sense.
    public static func parse(_ text: String, pageCount: Int) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard pageCount > 0, !trimmed.isEmpty else { return nil }
        var out: [Int] = []
        var seen = Set<Int>()
        for rawPart in trimmed.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let part = rawPart.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: " ", with: "")
            guard !part.isEmpty else { continue }
            var low: Int, high: Int
            if let dash = part.firstIndex(of: "-") {
                let a = String(part[..<dash]), b = String(part[part.index(after: dash)...])
                guard let l = a.isEmpty ? 1 : Int(a) else { return nil }
                guard let h = b.isEmpty ? pageCount : Int(b) else { return nil }
                low = l
                high = h
            } else {
                guard let n = Int(part) else { return nil }
                low = n
                high = n
            }
            guard low >= 1, high >= 1, low <= pageCount, high <= pageCount else { return nil }
            let step = low <= high ? 1 : -1
            for p in stride(from: low, through: high, by: step) where seen.insert(p - 1).inserted {
                out.append(p - 1)
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Zero-based pages for people: [0, 1, 2, 4] → "1–3, 5".
    public static func describe(_ pages: [Int]) -> String {
        var parts: [String] = []
        var i = 0
        while i < pages.count {
            var j = i
            while j + 1 < pages.count, pages[j + 1] == pages[j] + 1 { j += 1 }
            parts.append(i == j ? "\(pages[i] + 1)" : "\(pages[i] + 1)–\(pages[j] + 1)")
            i = j + 1
        }
        return parts.joined(separator: ", ")
    }

    /// "page 3" or "pages 1–3, 5", for file names (with a plain hyphen).
    public static func tag(_ pages: [Int]) -> String {
        (pages.count == 1 ? "page " : "pages ") + describe(pages).replacingOccurrences(of: "–", with: "-")
    }
}

/// A line of subtitles.
public struct Cue: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Subtitles in and out: SRT files (also reads WebVTT) and plain transcripts.
public enum Subtitles {
    /// 3725.5 → "01:02:05,500"
    public static func timestamp(_ seconds: Double, separator: Character = ",") -> String {
        let total = max(0, Int((seconds * 1000).rounded()))
        let ms = total % 1000, s = total / 1000 % 60, m = total / 60_000 % 60, h = total / 3_600_000
        func pad(_ v: Int, _ n: Int) -> String { String(repeating: "0", count: max(0, n - String(v).count)) + String(v) }
        return "\(pad(h, 2)):\(pad(m, 2)):\(pad(s, 2))\(separator)\(pad(ms, 3))"
    }

    public static func srt(_ cues: [Cue]) -> String {
        var blocks: [String] = []
        for cue in cues {
            // A blank line would end the cue early, so lines inside one stay together.
            var text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            while text.contains("\n\n") { text = text.replacingOccurrences(of: "\n\n", with: "\n") }
            guard !text.isEmpty else { continue }
            blocks.append("\(blocks.count + 1)\n\(timestamp(cue.start)) --> \(timestamp(max(cue.end, cue.start)))\n\(text)\n")
        }
        return blocks.joined(separator: "\n")
    }

    /// "01:02:05,500", "02:05.500" (WebVTT without hours) → seconds.
    public static func seconds(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = t.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var total = 0.0
        for p in parts {
            guard let v = Double(p) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    public static func parse(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let sides = lines[timing].components(separatedBy: "-->")
            guard sides.count == 2, let start = seconds(sides[0]),
                  let end = seconds(sides[1].split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? "") else { continue }
            let body = lines[(timing + 1)...].joined(separator: "\n")
            cues.append(Cue(start: start, end: end, text: body))
        }
        return cues
    }

    /// Cues as reading text: a new paragraph wherever the speaker paused for a couple of seconds.
    public static func plainText(_ cues: [Cue], pause: Double = 2) -> String {
        var paragraphs: [String] = []
        var current = ""
        var lastEnd: Double?
        for cue in cues {
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            guard !text.isEmpty else { continue }
            if let last = lastEnd, cue.start - last >= pause, !current.isEmpty {
                paragraphs.append(current)
                current = ""
            }
            current += current.isEmpty ? text : " " + text
            lastEnd = cue.end
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }
}

/// Long text in pieces small enough for an on-device model, cut at paragraph or sentence ends.
public enum TextChunks {
    public static func split(_ text: String, maxCharacters: Int) -> [String] {
        let limit = max(50, maxCharacters)
        var chunks: [String] = []
        var current = ""
        func flush() {
            let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { chunks.append(t) }
            current = ""
        }
        func add(_ piece: String, separator: String) {
            if current.count + separator.count + piece.count <= limit {
                current += current.isEmpty ? piece : separator + piece
                return
            }
            flush()
            if piece.count <= limit {
                current = piece
                return
            }
            // A very long paragraph: by sentences, then hard cuts.
            for sentence in sentences(piece) {
                if current.count + 1 + sentence.count <= limit {
                    current += current.isEmpty ? sentence : " " + sentence
                } else {
                    flush()
                    var rest = Substring(sentence)
                    while rest.count > limit {
                        chunks.append(String(rest.prefix(limit)))
                        rest = rest.dropFirst(limit)
                    }
                    current = String(rest)
                }
            }
        }
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for p in paragraphs { add(p, separator: "\n\n") }
        flush()
        return chunks
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            let atEnd = i + 1 == chars.count
            if ".!?。".contains(c), atEnd || chars[i + 1] == " " || chars[i + 1] == "\n" {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out
    }
}

/// Which frames a GIF takes from a video.
public enum GIFPlan {
    /// Frame times (seconds) at `fps`, lowering the rate for long clips so a GIF stays a sensible size.
    public static func frameTimes(duration: Double, fps: Double = 12, maxFrames: Int = 240) -> [Double] {
        guard duration > 0, fps > 0 else { return [] }
        let rate = min(fps, Double(maxFrames) / duration)
        let count = max(1, Int((duration * rate).rounded(.down)))
        let step = duration / Double(count)
        return (0..<count).map { Double($0) * step }
    }

    /// How long each frame shows, in seconds (GIF delays are in hundredths).
    public static func delay(duration: Double, frames: Int) -> Double {
        guard frames > 0 else { return 0.1 }
        return max(0.02, (duration / Double(frames) * 100).rounded() / 100)
    }
}
