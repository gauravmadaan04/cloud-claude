import Foundation

/// Haven's saved index in a compact binary form: repeated strings (folders, sources, tags…) are stored once,
/// so a 300,000-file library saves and loads in a fraction of the time JSON takes.
public enum IndexCodec {
    public static let magic: [UInt8] = Array("HVNI".utf8)
    public static let version: UInt16 = 1

    public struct Snapshot: Sendable {
        public var savedAt: Date
        public var rootPaths: [String]
        public var items: [FileItem]
    }

    public enum Failure: Error { case notAnIndex, unsupportedVersion, corrupt }

    // MARK: Encoding

    public static func encode(items: [FileItem], rootPaths: [String], savedAt: Date = Date()) -> Data {
        var table = StringTable()
        var foldedParents: [Int: String] = [:]
        var body = Writer()
        body.reserve(items.count * 64)
        for item in items {
            let parent = FileItem.parent(of: item.path)
            let rebuilt = join(parent, item.name)
            var flags: UInt64 = 0
            if item.isScreenshot { flags |= 1 << 0 }
            if item.isCloudOnly { flags |= 1 << 1 }
            if item.added != nil { flags |= 1 << 2 }
            if item.lastOpened != nil { flags |= 1 << 3 }
            if item.quarantineAgent != nil { flags |= 1 << 4 }
            if item.source != nil { flags |= 1 << 5 }
            let sameSearchName = item.searchName == item.name
            if sameSearchName { flags |= 1 << 6 }
            if !item.tags.isEmpty || !item.whereFroms.isEmpty { flags |= 1 << 7 }
            if rebuilt != item.path { flags |= 1 << 8 }
            let parentID = table.id(parent)
            let folded: String
            if let f = foldedParents[parentID] {
                folded = f
            } else {
                folded = FileItem.fold(FileItem.lastComponent(parent))
                foldedParents[parentID] = folded
            }
            let sameParentName = item.searchParent == folded
            if !sameParentName { flags |= 1 << 9 }

            body.varint(flags)
            body.varint(UInt64(parentID))
            body.string(item.name)
            if rebuilt != item.path { body.string(item.path) }
            if !sameSearchName { body.string(item.searchName) }
            if !sameParentName { body.string(item.searchParent) }
            body.varint(UInt64(table.id(item.ext)))
            body.varint(UInt64(table.id(item.kind.rawValue)))
            body.varint(UInt64(bitPattern: item.size))
            body.double(item.created.timeIntervalSinceReferenceDate)
            body.double(item.modified.timeIntervalSinceReferenceDate)
            if let a = item.added { body.double(a.timeIntervalSinceReferenceDate) }
            if let o = item.lastOpened { body.double(o.timeIntervalSinceReferenceDate) }
            body.varint(UInt64(table.id(item.rootID)))
            if flags & (1 << 7) != 0 {
                body.varint(UInt64(item.tags.count))
                for t in item.tags { body.varint(UInt64(table.id(t))) }
                body.varint(UInt64(item.whereFroms.count))
                for w in item.whereFroms { body.string(w) }
            }
            if let q = item.quarantineAgent { body.varint(UInt64(table.id(q))) }
            if let s = item.source {
                body.varint(UInt64(table.id(s.id)))
                body.varint(UInt64(table.id(s.name)))
                body.varint(UInt64(table.id(s.symbol)))
                body.varint(UInt64(table.id(s.tint.rawValue)))
                body.varint(s.host.map { UInt64(table.id($0)) + 1 } ?? 0)
            }
        }

        var out = Writer()
        out.reserve(body.bytes.count + table.strings.count * 24 + 64)
        out.bytes.append(contentsOf: magic)
        out.varint(UInt64(version))
        out.double(savedAt.timeIntervalSinceReferenceDate)
        out.varint(UInt64(rootPaths.count))
        for r in rootPaths { out.string(r) }
        out.varint(UInt64(table.strings.count))
        for s in table.strings { out.string(s) }
        out.varint(UInt64(items.count))
        out.bytes.append(contentsOf: body.bytes)
        return Data(out.bytes)
    }

    // MARK: Decoding

    public static func decode(_ data: Data) throws -> Snapshot {
        try data.withUnsafeBytes { raw -> Snapshot in
            var r = Reader(raw.bindMemory(to: UInt8.self))
            guard raw.count >= 4, Array(raw.prefix(4)) == magic else { throw Failure.notAnIndex }
            r.pos = 4
            guard try r.varint() == UInt64(version) else { throw Failure.unsupportedVersion }
            let savedAt = Date(timeIntervalSinceReferenceDate: try r.double())
            let rootCount = try r.count()
            var roots: [String] = []
            for _ in 0..<rootCount { roots.append(try r.string()) }
            let tableCount = try r.count()
            var strings: [String] = []
            strings.reserveCapacity(tableCount)
            for _ in 0..<tableCount { strings.append(try r.string()) }
            func s(_ i: UInt64) throws -> String {
                guard i < UInt64(strings.count) else { throw Failure.corrupt }
                return strings[Int(i)]
            }
            var parentNames = [String?](repeating: nil, count: strings.count)
            let kindsByName = Dictionary(uniqueKeysWithValues: FileKind.allCases.map { ($0.rawValue, $0) })
            var tintCache: [Int: SourceTint] = [:]
            var sourceCache: [SourceKey: DownloadSource] = [:]

            let count = try r.count()
            var items: [FileItem] = []
            items.reserveCapacity(count)
            for _ in 0..<count {
                let flags = try r.varint()
                let parentID = try r.varint()
                let parent = try s(parentID)
                let name = try r.string()
                let path = flags & (1 << 8) != 0 ? try r.string() : join(parent, name)
                let searchName = flags & (1 << 6) != 0 ? name : try r.string()
                let searchParent: String
                if flags & (1 << 9) != 0 {
                    searchParent = try r.string()
                } else if let cached = parentNames[Int(parentID)] {
                    searchParent = cached
                } else {
                    let folded = FileItem.fold(FileItem.lastComponent(parent))
                    parentNames[Int(parentID)] = folded
                    searchParent = folded
                }
                let ext = try s(try r.varint())
                guard let kind = kindsByName[try s(try r.varint())] else { throw Failure.corrupt }
                let size = Int64(bitPattern: try r.varint())
                let created = Date(timeIntervalSinceReferenceDate: try r.double())
                let modified = Date(timeIntervalSinceReferenceDate: try r.double())
                let added = flags & (1 << 2) != 0 ? Date(timeIntervalSinceReferenceDate: try r.double()) : nil
                let opened = flags & (1 << 3) != 0 ? Date(timeIntervalSinceReferenceDate: try r.double()) : nil
                let rootID = try s(try r.varint())
                var tags: [String] = []
                var froms: [String] = []
                if flags & (1 << 7) != 0 {
                    let tc = try r.count()
                    for _ in 0..<tc { tags.append(try s(try r.varint())) }
                    let fc = try r.count()
                    for _ in 0..<fc { froms.append(try r.string()) }
                }
                let quarantine = flags & (1 << 4) != 0 ? try s(try r.varint()) : nil
                var source: DownloadSource?
                if flags & (1 << 5) != 0 {
                    let key = SourceKey(id: try r.index(), name: try r.index(), symbol: try r.index(),
                                        tint: try r.index(), host: try r.index())
                    if let cached = sourceCache[key] {
                        source = cached
                    } else {
                        let tint: SourceTint
                        if let t = tintCache[key.tint] {
                            tint = t
                        } else {
                            guard let t = SourceTint(rawValue: try s(UInt64(key.tint))) else { throw Failure.corrupt }
                            tintCache[key.tint] = t
                            tint = t
                        }
                        let made = DownloadSource(id: try s(UInt64(key.id)), name: try s(UInt64(key.name)),
                                                  symbol: try s(UInt64(key.symbol)), tint: tint,
                                                  host: key.host == 0 ? nil : try s(UInt64(key.host - 1)))
                        sourceCache[key] = made
                        source = made
                    }
                }
                items.append(FileItem(
                    stored: path, name: name, ext: ext, kind: kind, size: size, created: created, modified: modified,
                    added: added, lastOpened: opened, rootID: rootID, tags: tags, whereFroms: froms,
                    quarantineAgent: quarantine, isScreenshot: flags & 1 != 0, isCloudOnly: flags & 2 != 0,
                    source: source, searchName: searchName, searchParent: searchParent
                ))
            }
            return Snapshot(savedAt: savedAt, rootPaths: roots, items: items)
        }
    }

    static func join(_ parent: String, _ name: String) -> String {
        if parent.isEmpty { return name }
        if parent == "/" { return "/" + name }
        return parent + "/" + name
    }

    struct SourceKey: Hashable {
        let id, name, symbol, tint, host: Int
    }

    struct StringTable {
        var strings: [String] = []
        var ids: [String: Int] = [:]

        mutating func id(_ s: String) -> Int {
            if let i = ids[s] { return i }
            let i = strings.count
            strings.append(s)
            ids[s] = i
            return i
        }
    }

    struct Writer {
        var bytes: [UInt8] = []

        mutating func reserve(_ n: Int) { bytes.reserveCapacity(n) }

        mutating func varint(_ value: UInt64) {
            var v = value
            while v >= 0x80 {
                bytes.append(UInt8(v & 0x7F) | 0x80)
                v >>= 7
            }
            bytes.append(UInt8(v))
        }

        mutating func double(_ d: Double) {
            var bits = d.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
        }

        mutating func string(_ s: String) {
            varint(UInt64(s.utf8.count))
            bytes.append(contentsOf: s.utf8)
        }
    }

    struct Reader {
        let buf: UnsafeBufferPointer<UInt8>
        var pos = 0

        init(_ buf: UnsafeBufferPointer<UInt8>) { self.buf = buf }

        mutating func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard pos < buf.count, shift < 64 else { throw Failure.corrupt }
                let b = buf[pos]
                pos += 1
                result |= UInt64(b & 0x7F) << shift
                if b < 0x80 { return result }
                shift += 7
            }
        }

        /// A table position; a damaged file can't make it overflow.
        mutating func index() throws -> Int {
            guard let i = Int(exactly: try varint()) else { throw Failure.corrupt }
            return i
        }

        mutating func count() throws -> Int {
            let n = try varint()
            guard n <= UInt64(buf.count) else { throw Failure.corrupt }
            return Int(n)
        }

        mutating func double() throws -> Double {
            guard pos + 8 <= buf.count else { throw Failure.corrupt }
            var bits: UInt64 = 0
            for i in 0..<8 { bits |= UInt64(buf[pos + i]) << (8 * UInt64(i)) }
            pos += 8
            return Double(bitPattern: bits)
        }

        mutating func string() throws -> String {
            let n = try count()
            guard pos + n <= buf.count else { throw Failure.corrupt }
            let s = String(decoding: UnsafeBufferPointer(rebasing: buf[pos..<(pos + n)]), as: UTF8.self)
            pos += n
            return s
        }
    }
}
