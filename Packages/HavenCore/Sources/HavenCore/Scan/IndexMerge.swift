import Foundation

/// Folds a few changed folders into the full index (newest activity first) without re-sorting or
/// re-hashing everything: one pass over the index, then a merge with the new entries.
public enum IndexMerge {
    /// - Parameters:
    ///   - base: the current index, newest activity first.
    ///   - listed: folders that were re-listed, with their direct children as they are now.
    ///   - gone: folders that no longer exist (they and everything under them are dropped).
    ///   - added: whole subtrees found inside new subfolders (descendants only; the subfolders are in `listed`).
    public static func apply(base: [FileItem], listed: [String: [FileItem]], gone: [String] = [], added: [FileItem] = []) -> [FileItem] {
        let listedDirs = Set(listed.keys.map { Substring($0) })
        // Cheap first check: a direct child's parent must have the length of one of the listed folders.
        let listedLengths = Set(listed.keys.map { $0 == "/" ? 1 : $0.utf8.count })
        @inline(__always) func listedParent(_ path: String) -> Bool {
            guard let len = parentLength(path), listedLengths.contains(len), let parent = parentSubstring(path) else { return false }
            return listedDirs.contains(parent)
        }
        var newChildren = Set<String>()
        for children in listed.values { for c in children { newChildren.insert(c.path) } }

        // Folders that disappeared from a listing take their contents with them.
        var gonePrefixes = gone.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var goneExact = Set(gone)
        if !listedDirs.isEmpty {
            for item in base where item.kind == .folder || item.kind == .app {
                if listedParent(item.path), !newChildren.contains(item.path) {
                    gonePrefixes.append(item.path + "/")
                    goneExact.insert(item.path)
                }
            }
        }
        let goneBytes = gonePrefixes.map { Array($0.utf8) }
        let addedPaths = Set(added.map(\.path))
        let exactLengths = Set(goneExact.map(\.utf8.count)).union(addedPaths.map(\.utf8.count))

        var kept: [FileItem] = []
        kept.reserveCapacity(base.count)
        for item in base {
            if !listedDirs.isEmpty, listedParent(item.path) { continue }
            if exactLengths.contains(item.path.utf8.count), goneExact.contains(item.path) || addedPaths.contains(item.path) { continue }
            if !goneBytes.isEmpty, goneBytes.contains(where: { hasPrefix(item.path, $0) }) { continue }
            kept.append(item)
        }

        var fresh: [FileItem] = []
        for (dir, children) in listed where !goneExact.contains(dir) && !goneBytes.contains(where: { hasPrefix(dir, $0) }) {
            fresh.append(contentsOf: children)
        }
        fresh.append(contentsOf: added)
        if fresh.isEmpty { return kept }
        return mergeNewestFirst(kept, FileSortOrder.dateNewest.sorted(fresh))
    }

    /// The index without these paths (and without anything inside those that are folders).
    public static func removing(_ paths: Set<String>, from base: [FileItem]) -> [FileItem] {
        guard !paths.isEmpty else { return base }
        var folders: [[UInt8]] = []
        let lengths = Set(paths.map(\.utf8.count))
        var kept = base.filter { item in
            guard lengths.contains(item.path.utf8.count), paths.contains(item.path) else { return true }
            if item.kind == .folder || item.kind == .app { folders.append(Array((item.path + "/").utf8)) }
            return false
        }
        if !folders.isEmpty {
            kept.removeAll { item in folders.contains { hasPrefix(item.path, $0) } }
        }
        return kept
    }

    /// Two newest-first lists into one (stable: `a` wins ties).
    static func mergeNewestFirst(_ a: [FileItem], _ b: [FileItem]) -> [FileItem] {
        var out: [FileItem] = []
        out.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if b[j].activityDate > a[i].activityDate {
                out.append(b[j]); j += 1
            } else {
                out.append(a[i]); i += 1
            }
        }
        if i < a.count { out.append(contentsOf: a[i...]) }
        if j < b.count { out.append(contentsOf: b[j...]) }
        return out
    }

    /// UTF-8 length of the parent folder's path ("/" counts as 1), without building it.
    @inline(__always)
    static func parentLength(_ path: String) -> Int? {
        let find: (UnsafeBufferPointer<UInt8>) -> Int? = { buf in
            var i = buf.count - 1
            while i >= 0 {
                if buf[i] == 47 { return i == 0 ? 1 : i }
                i -= 1
            }
            return nil
        }
        if let r = path.utf8.withContiguousStorageIfAvailable(find) { return r }
        return Array(path.utf8).withUnsafeBufferPointer(find)
    }

    @inline(__always)
    static func parentSubstring(_ path: String) -> Substring? {
        guard let slash = path.utf8.lastIndex(of: UInt8(ascii: "/")) else { return nil }
        if slash == path.utf8.startIndex { return Substring("/") }
        return path[..<slash]
    }

    @inline(__always)
    static func hasPrefix(_ s: String, _ prefix: [UInt8]) -> Bool {
        let check: (UnsafeBufferPointer<UInt8>) -> Bool = { buf in
            guard buf.count >= prefix.count else { return false }
            for k in 0..<prefix.count where buf[k] != prefix[k] { return false }
            return true
        }
        if let r = s.utf8.withContiguousStorageIfAvailable(check) { return r }
        return Array(s.utf8).withUnsafeBufferPointer(check)
    }
}
