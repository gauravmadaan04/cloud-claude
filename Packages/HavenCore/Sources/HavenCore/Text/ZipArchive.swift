import Foundation

/// Reads files out of a ZIP archive (Word, Excel, PowerPoint, OpenDocument, EPUB and iWork files are ZIPs).
/// Read-only, and careful with damaged or hostile files: every offset is checked and output is capped.
public struct ZipArchive {
    public struct Entry: Sendable {
        public let name: String
        let method: UInt16
        let compressedSize: Int
        public let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    public enum Failure: Error { case notAZip, corrupt, unsupportedMethod }

    public let data: Data
    public let entries: [Entry]

    public init(data: Data) throws {
        self.data = data
        self.entries = try data.withUnsafeBytes { raw in
            try ZipArchive.readDirectory(raw.bindMemory(to: UInt8.self))
        }
    }

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public func entry(named name: String) -> Entry? { entries.first { $0.name == name } }

    /// The entry's bytes, decompressed (at most `limit` bytes).
    public func read(_ entry: Entry, limit: Int = 16 << 20) throws -> [UInt8] {
        try data.withUnsafeBytes { raw -> [UInt8] in
            let buf = raw.bindMemory(to: UInt8.self)
            let at = entry.localHeaderOffset
            guard at >= 0, at + 30 <= buf.count, ZipArchive.u32(buf, at) == 0x0403_4B50 else { throw Failure.corrupt }
            let start = at + 30 + Int(ZipArchive.u16(buf, at + 26)) + Int(ZipArchive.u16(buf, at + 28))
            guard start >= 0, entry.compressedSize >= 0, start + entry.compressedSize <= buf.count else { throw Failure.corrupt }
            let body = UnsafeBufferPointer(rebasing: buf[start..<(start + entry.compressedSize)])
            switch entry.method {
            case 0: return Array(body.prefix(limit))
            case 8: return try Inflate.inflate(body, expectedSize: entry.uncompressedSize, limit: limit)
            default: throw Failure.unsupportedMethod
            }
        }
    }

    public func read(named name: String, limit: Int = 16 << 20) -> [UInt8]? {
        guard let e = entry(named: name) else { return nil }
        return try? read(e, limit: limit)
    }

    // MARK: Directory

    static func u16(_ b: UnsafeBufferPointer<UInt8>, _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    static func u32(_ b: UnsafeBufferPointer<UInt8>, _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
    static func u64(_ b: UnsafeBufferPointer<UInt8>, _ i: Int) -> UInt64 { UInt64(u32(b, i)) | UInt64(u32(b, i + 4)) << 32 }

    static func readDirectory(_ b: UnsafeBufferPointer<UInt8>) throws -> [Entry] {
        guard b.count >= 22 else { throw Failure.notAZip }
        // The end record sits in the last 64 KB (after an optional comment).
        var eocd = -1
        var i = b.count - 22
        let stop = max(0, b.count - 22 - 65_535)
        while i >= stop {
            if b[i] == 0x50 && u32(b, i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.notAZip }
        var count = Int(u16(b, eocd + 10))
        var dirOffset = Int(u32(b, eocd + 16))
        // ZIP64: the real numbers are in another record.
        if dirOffset == 0xFFFF_FFFF || count == 0xFFFF, eocd >= 20, u32(b, eocd - 20) == 0x0706_4B50 {
            let rec = Int(clamping: u64(b, eocd - 12))
            guard rec >= 0, rec + 56 <= b.count, u32(b, rec) == 0x0606_4B50 else { throw Failure.corrupt }
            count = Int(clamping: u64(b, rec + 32))
            dirOffset = Int(clamping: u64(b, rec + 48))
        }
        guard dirOffset >= 0, dirOffset < b.count, count < 1_000_000 else { throw Failure.corrupt }
        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var p = dirOffset
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(b, p) == 0x0201_4B50 else { throw Failure.corrupt }
            let method = u16(b, p + 10)
            var compressed = Int(u32(b, p + 20))
            var uncompressed = Int(u32(b, p + 24))
            let nameLength = Int(u16(b, p + 28))
            let extraLength = Int(u16(b, p + 30))
            let commentLength = Int(u16(b, p + 32))
            var local = Int(u32(b, p + 42))
            let nameStart = p + 46
            guard nameStart + nameLength + extraLength <= b.count else { throw Failure.corrupt }
            let name = String(decoding: UnsafeBufferPointer(rebasing: b[nameStart..<(nameStart + nameLength)]), as: UTF8.self)
            // ZIP64 sizes and offsets live in an extra field.
            var e = nameStart + nameLength
            let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = u16(b, e)
                let size = Int(u16(b, e + 2))
                var v = e + 4
                if id == 0x0001 {
                    if uncompressed == 0xFFFF_FFFF, v + 8 <= extraEnd { uncompressed = Int(clamping: u64(b, v)); v += 8 }
                    if compressed == 0xFFFF_FFFF, v + 8 <= extraEnd { compressed = Int(clamping: u64(b, v)); v += 8 }
                    if local == 0xFFFF_FFFF, v + 8 <= extraEnd { local = Int(clamping: u64(b, v)) }
                }
                e += 4 + size
            }
            entries.append(Entry(name: name, method: method, compressedSize: compressed, uncompressedSize: uncompressed,
                                 localHeaderOffset: local))
            p = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }
}
