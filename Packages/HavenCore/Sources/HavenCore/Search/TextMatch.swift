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

    /// True when `s` begins with these bytes.
    public static func starts(with prefix: [UInt8], _ s: String) -> Bool {
        var i = prefix.startIndex
        for b in s.utf8 {
            if i == prefix.endIndex { return true }
            if b != prefix[i] { return false }
            i += 1
        }
        return i == prefix.endIndex
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
        appendKey(folded, to: &out)
        return out
    }

    /// Writes the key for `folded` onto the end of `out` (no temporary arrays).
    public static func appendKey(_ folded: String, to out: inout [UInt8]) {
        var s = folded
        s.withUTF8 { u in
            var i = 0
            while i < u.count {
                let b = u[i]
                guard b >= 48 && b <= 57 else {
                    out.append(b)
                    i += 1
                    continue
                }
                var end = i
                while end < u.count && u[end] >= 48 && u[end] <= 57 { end += 1 }
                var start = i
                while start < end - 1 && u[start] == 48 { start += 1 }
                let length = min(end - start, 255)
                out.append(48)
                out.append(UInt8(length))
                out.append(contentsOf: UnsafeBufferPointer(rebasing: u[start..<(start + length)]))
                i = end
            }
        }
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

/// Natural-order keys for many names in one buffer, built on every core: comparing two is a single memcmp
/// with no reference counting, which keeps sorting 300,000 names by name quick.
public struct NaturalKeys: Sendable {
    let bytes: [UInt8]
    /// Key `i` is bytes[offsets[i]..<offsets[i + 1]].
    let offsets: [Int]

    public var count: Int { offsets.count - 1 }

    public init(_ folded: [String]) {
        let n = folded.count
        let parts = n >= 20_000 ? min(max(1, ProcessInfo.processInfo.activeProcessorCount), 16) : 1
        let size = (n + parts - 1) / parts
        var chunks = [(bytes: [UInt8], ends: [Int])](repeating: ([], []), count: parts)
        chunks.withUnsafeMutableBufferPointer { out in
            DispatchQueue.concurrentPerform(iterations: parts) { p in
                let lo = p * size, hi = min(n, lo + size)
                guard lo < hi else { return }
                var bytes: [UInt8] = []
                bytes.reserveCapacity((hi - lo) * 24)
                var ends: [Int] = []
                ends.reserveCapacity(hi - lo)
                for i in lo..<hi {
                    NaturalOrder.appendKey(folded[i], to: &bytes)
                    ends.append(bytes.count)
                }
                out[p] = (bytes, ends)
            }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chunks.reduce(0) { $0 + $1.bytes.count })
        var offsets: [Int] = [0]
        offsets.reserveCapacity(n + 1)
        for c in chunks {
            let base = bytes.count
            bytes.append(contentsOf: c.bytes)
            for e in c.ends { offsets.append(base + e) }
        }
        self.bytes = bytes
        self.offsets = offsets
    }

    /// Runs `body` with a comparator (<0, 0, >0) over key indices that touches only raw memory.
    public func withComparator<R>(_ body: ((Int, Int) -> Int) throws -> R) rethrows -> R {
        try bytes.withUnsafeBufferPointer { b in
            try offsets.withUnsafeBufferPointer { o in
                let base = b.baseAddress
                return try body { i, j in
                    let ai = o[i], an = o[i + 1] - ai
                    let bj = o[j], bn = o[j + 1] - bj
                    let n = min(an, bn)
                    if n > 0, let base {
                        let c = memcmp(base + ai, base + bj, n)
                        if c != 0 { return Int(c) }
                    }
                    return an - bn
                }
            }
        }
    }
}
