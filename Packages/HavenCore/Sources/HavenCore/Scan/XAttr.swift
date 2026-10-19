import Foundation
#if canImport(Darwin)
import Darwin

/// Reads and writes the extended attributes macOS stores on files.
public enum XAttr {
    public static let whereFromsName = "com.apple.metadata:kMDItemWhereFroms"
    public static let quarantineName = "com.apple.quarantine"
    public static let lastUsedName = "com.apple.lastuseddate#PS"
    public static let screenCaptureName = "com.apple.metadata:kMDItemIsScreenCapture"
    /// Test-only arrival date (unix seconds as text), honoured when scanning with `honorTestDates`.
    public static let testAddedName = "app.haven.test.added"

    public static func data(_ path: String, _ name: String) -> Data? {
        let len = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard len > 0 else { return nil }
        var data = Data(count: len)
        let read = data.withUnsafeMutableBytes { buf in
            getxattr(path, name, buf.baseAddress, len, 0, XATTR_NOFOLLOW)
        }
        guard read > 0 else { return nil }
        return data.prefix(read)
    }

    @discardableResult
    public static func set(_ path: String, _ name: String, _ data: Data) -> Bool {
        data.withUnsafeBytes { buf in
            setxattr(path, name, buf.baseAddress, data.count, 0, XATTR_NOFOLLOW) == 0
        }
    }

    public static func whereFroms(_ path: String) -> [String] {
        guard let d = data(path, whereFromsName),
              let plist = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) else { return [] }
        if let arr = plist as? [String] { return arr.filter { !$0.isEmpty } }
        if let s = plist as? String { return [s] }
        return []
    }

    public static func quarantineAgent(_ path: String) -> String? {
        guard let d = data(path, quarantineName), let s = String(data: d, encoding: .utf8) else { return nil }
        return quarantineAgentName(s)
    }

    public static func lastUsedDate(_ path: String) -> Date? {
        guard let d = data(path, lastUsedName), d.count >= 8 else { return nil }
        let seconds: Int64 = d.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
        var nanos: Int64 = 0
        if d.count >= 16 {
            nanos = d.dropFirst(8).prefix(8).withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
        }
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1e9)
    }

    public static func isScreenCapture(_ path: String) -> Bool {
        guard let d = data(path, screenCaptureName),
              let plist = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) else { return false }
        if let b = plist as? Bool { return b }
        if let n = plist as? NSNumber { return n.boolValue }
        return false
    }

    /// Finder tags ("Work", "Red"…), stored as "Name\n<colour>" strings.
    public static func tags(_ path: String) -> [String] {
        guard let d = data(path, "com.apple.metadata:_kMDItemUserTags"),
              let list = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String] else { return [] }
        return list.compactMap { $0.split(separator: "\n").first.map(String.init) }.filter { !$0.isEmpty }
    }

    public static func testAddedDate(_ path: String) -> Date? {
        guard let d = data(path, testAddedName), let s = String(data: d, encoding: .utf8), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    // MARK: Writers (used by fixtures and tests)

    @discardableResult
    public static func setWhereFroms(_ urls: [String], path: String) -> Bool {
        guard let d = try? PropertyListSerialization.data(fromPropertyList: urls, format: .binary, options: 0) else { return false }
        return set(path, whereFromsName, d)
    }

    @discardableResult
    public static func setQuarantine(agent: String, path: String) -> Bool {
        let value = String(format: "0083;%08x;%@;", Int(Date().timeIntervalSince1970), agent)
        return set(path, quarantineName, Data(value.utf8))
    }

    @discardableResult
    public static func setLastUsedDate(_ date: Date, path: String) -> Bool {
        var seconds = Int64(date.timeIntervalSince1970)
        var nanos: Int64 = 0
        var d = Data(bytes: &seconds, count: 8)
        d.append(Data(bytes: &nanos, count: 8))
        return set(path, lastUsedName, d)
    }

    @discardableResult
    public static func setScreenCapture(path: String) -> Bool {
        guard let d = try? PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0) else { return false }
        return set(path, screenCaptureName, d)
    }

    @discardableResult
    public static func setTestAddedDate(_ date: Date, path: String) -> Bool {
        set(path, testAddedName, Data(String(date.timeIntervalSince1970).utf8))
    }
}
#endif
