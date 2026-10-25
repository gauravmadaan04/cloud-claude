#if os(macOS)
import AppKit
import Combine
import ServiceManagement
import RibbonCore

/// Lightweight logging: memory ring buffer (for "Copy diagnostics") plus a file in ~/Library/Logs.
enum Log {
    private static var lines: [String] = []
    private static let lock = NSLock()
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Ribbon")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ribbon.log")
    }()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    static var verbose = ProcessInfo.processInfo.environment["RIBBON_DEBUG"] != nil

    static func info(_ s: @autoclosure () -> String) { write("I", s()) }
    static func debug(_ s: @autoclosure () -> String) { if verbose { write("D", s()) } }
    static func error(_ s: @autoclosure () -> String) { write("E", s()) }

    private static func write(_ level: String, _ s: String) {
        let line = "\(formatter.string(from: Date())) \(level) \(s)"
        lock.lock()
        lines.append(line)
        if lines.count > 2000 { lines.removeFirst(500) }
        lock.unlock()
        if verbose { FileHandle.standardError.write(Data((line + "\n").utf8)) }
        if let h = try? FileHandle(forWritingTo: fileURL) {
            h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
        } else {
            try? Data((line + "\n").utf8).write(to: fileURL)
        }
    }

    static func recent() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.suffix(400).joined(separator: "\n")
    }

    static func trimFile() {
        if let a = try? FileManager.default.attributesOfItem(atPath: fileURL.path), let size = a[.size] as? Int, size > 2_000_000 {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

/// The user's settings, saved to UserDefaults on every change.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let key = "config.v2"

    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            UserDefaults.standard.set(config.encoded(), forKey: key)
            for l in listeners { l(oldValue, config) }
        }
    }

    private var listeners: [(Config, Config) -> Void] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: key) { config = Config.decode(d) } else { config = Config() }
    }

    func onChange(_ f: @escaping (_ old: Config, _ new: Config) -> Void) { listeners.append(f) }

    func resetToDefaults() {
        var c = Config()
        c.hasCompletedOnboarding = config.hasCompletedOnboarding
        config = c
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            Log.error("Login item: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}

/// Saves where every window sits so layouts come back after a restart.
enum SessionStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ribbon")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    static func load() -> SessionSnapshot? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(SessionSnapshot.self, from: d)
    }

    static func save(_ s: SessionSnapshot) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(s) { try? d.write(to: url, options: .atomic) }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((v >> 24) & 0xFF) / 255; g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8) & 0xFF) / 255; a = CGFloat(v & 0xFF) / 255
        } else {
            r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255; a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#4F8CFF" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? IPC.version
    }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev" }
    static var isE2E: Bool { CommandLine.arguments.contains("--e2e") }

    /// Quits and opens Ribbon again (macOS sometimes only notices a new Accessibility switch on relaunch).
    static func relaunch() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open '\(path)'"]
        try? p.run()
        NSApp.terminate(nil)
    }
}
#endif
