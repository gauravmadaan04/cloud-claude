import Foundation

/// Byte-level substring search over folded (lowercased, accent-free) UTF-8 text. Much faster than
/// `String.range(of:)` in the per-file loops of search.
public enum TextMatch {
    /// Byte offset of `needle` in `hay`, or nil.
    @inline(__always)
    public static func find(_ needle: [UInt8], in hay: String) -> Int? {
        if let hit = hay.utf8.withContiguousStorageIfAvailable({ find(needle, in: $0) }) { return hit }
        return Array(hay.utf8).withUnsafeBufferPointer { find(needle, in: $0) }
    }

    public static func contains(_ needle: [UInt8], in hay: String) -> Bool {
        find(needle, in: hay) != nil
    }

    static func find(_ needle: [UInt8], in hay: UnsafeBufferPointer<UInt8>) -> Int? {
        let n = needle.count
        let h = hay.count
        if n == 0 { return 0 }
        if n > h { return nil }
        return needle.withUnsafeBufferPointer { nb -> Int? in
            let first = nb[0]
            let last = h - n
            var i = 0
            while i <= last {
                if hay[i] == first {
                    var j = 1
                    while j < n && hay[i + j] == nb[j] { j += 1 }
                    if j == n { return i }
                }
                i += 1
            }
            return nil
        }
    }

    /// How well a word matches a folded name: 30 at the start, 20 at a word start, 12 inside a word, 0 if absent.
    public static func score(_ term: [UInt8], in name: String) -> Int {
        let compute: (UnsafeBufferPointer<UInt8>) -> Int = { buf in
            guard let at = find(term, in: buf) else { return 0 }
            if at == 0 { return 30 }
            let before = buf[at - 1]
            let alnum = (before >= 48 && before <= 57) || (before >= 97 && before <= 122) || (before >= 65 && before <= 90)
            // A byte of a multi-byte character counts as a letter.
            if before >= 0x80 || alnum { return 12 }
            return 20
        }
        if let s = name.utf8.withContiguousStorageIfAvailable(compute) { return s }
        return Array(name.utf8).withUnsafeBufferPointer(compute)
    }
}

/// Natural ("file2" before "file10"), case- and accent-insensitive ordering of names, as sortable byte keys.
public enum NaturalOrder {
    /// A key whose byte order is the natural order of the folded name. Digit runs become
    /// "0", their length, then the digits without leading zeros, so 9 < 10 < 100.
    public static func key(_ folded: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(folded.utf8.count + 4)
        var digits: [UInt8] = []
        func flush() {
            guard !digits.isEmpty else { return }
            var start = 0
            while start < digits.count - 1 && digits[start] == 48 { start += 1 }
            let run = digits[start...]
            out.append(48)
            out.append(UInt8(min(run.count, 255)))
            out.append(contentsOf: run.prefix(255))
            digits.removeAll(keepingCapacity: true)
        }
        for b in folded.utf8 {
            if b >= 48 && b <= 57 {
                digits.append(b)
            } else {
                flush()
                out.append(b)
            }
        }
        flush()
        return out
    }

    @inline(__always)
    public static func compare(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let n = min(a.count, b.count)
        if n == 0 { return a.count - b.count }
        let c = a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in memcmp(pa.baseAddress!, pb.baseAddress!, n) }
        }
        return c == 0 ? a.count - b.count : Int(c)
    }
}
