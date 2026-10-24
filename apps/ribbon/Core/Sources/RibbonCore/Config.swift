import Foundation

/// What a full screen does with one more window.
public enum WhenFull: String, Codable, CaseIterable {
    case stack, float
    public var title: String { self == .stack ? "Stack it on the window in use" : "Float it in the middle" }
}

/// What ⌃⌥ + arrow does when it carries a window onto a screen that is already full.
public enum IntoFull: String, Codable, CaseIterable {
    case swap, stack
    public var title: String { self == .swap ? "Swap with a window there" : "Stack on top" }
}

/// How the window in use stands out.
public enum Highlight: String, Codable, CaseIterable {
    case none, activeBorder, allBorders, glow
    public var title: String {
        switch self {
        case .none: return "None"
        case .activeBorder: return "Border"
        case .allBorders: return "All borders"
        case .glow: return "Glow"
        }
    }
}

/// The plain background behind Clean Space.
public enum Backdrop: String, Codable, CaseIterable {
    case slate, fog, sand, aurora
    public var title: String { rawValue.capitalized }
}

public enum AppBehavior: String, Codable, CaseIterable {
    case tile, float, ignore
    public var title: String {
        switch self {
        case .tile: return "Tile"
        case .float: return "Don't tile"
        case .ignore: return "Ignore completely"
        }
    }
}

public struct AppRule: Codable, Equatable, Identifiable, Hashable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var behavior: AppBehavior

    public init(bundleID: String, name: String, behavior: AppBehavior) {
        self.bundleID = bundleID; self.name = name; self.behavior = behavior
    }
}

/// Every user setting. Changes apply instantly; there is no Save button.
public struct Config: Codable, Equatable {
    public var tilingEnabled = true
    /// Grid or columns, for every screen that hasn't picked its own.
    public var layout: LayoutKind = .grid
    /// Windows per screen, for every screen that hasn't picked its own.
    public var windowsPerScreen = 3
    /// Space between windows and around the edge of the screen.
    public var spacing: Double = 8
    public var whenFull: WhenFull = .stack
    public var intoFull: IntoFull = .swap
    public var highlight: Highlight = .activeBorder
    public var highlightColor = "#7C5CFF"
    public var borderWidth: Double = 3
    public var cornerRadius: Double = 12
    /// The little grip above windows with quick actions.
    public var quickActions = true
    /// Activate a window when the pointer rests on it.
    public var hoverFocus = false
    public var shortcutsEnabled = true
    public var noPeekDim: Double = 0.5
    public var noPeekBlur = true
    public var backdrop: Backdrop = .slate
    /// Scrolling layout: width of a new column, as a share of the screen.
    public var scrollingWidth: Double = 0.5
    /// Scrolling layout: swipe with three (or four) fingers to scroll.
    public var swipeEnabled = true
    public var swipeFingers = 3
    public var swipeNatural = true
    public var swipeSensitivity: Double = 1.0
    /// Scrolling layout: hold ⌃⌥ and use the scroll wheel.
    public var scrollWheelWithModifiers = true
    public var animate = true
    /// Spring settle time in seconds.
    public var animationResponse: Double = 0.24
    public var floatFixedSizeWindows = true
    public var pauseForStageManager = true
    public var restoreSession = true
    public var haptics = true
    public var appRules: [AppRule] = Config.defaultRules
    /// Shortcut overrides keyed by command name. Missing commands use the defaults.
    public var bindings: [String: [KeyCombo]] = [:]
    public var hasCompletedOnboarding = false

    public init() {}

    /// Small tools and fixed-shape windows that look wrong stretched into a tile.
    public static let defaultRules: [AppRule] = [
        AppRule(bundleID: "com.apple.systempreferences", name: "System Settings", behavior: .float),
        AppRule(bundleID: "com.apple.calculator", name: "Calculator", behavior: .float),
        AppRule(bundleID: "com.apple.Stickies", name: "Stickies", behavior: .float),
        AppRule(bundleID: "com.apple.archiveutility", name: "Archive Utility", behavior: .float),
        AppRule(bundleID: "com.apple.ScreenContinuity", name: "iPhone Mirroring", behavior: .float),
        AppRule(bundleID: "com.apple.PhotoBooth", name: "Photo Booth", behavior: .float),
        AppRule(bundleID: "com.apple.DigitalColorMeter", name: "Digital Color Meter", behavior: .float),
        AppRule(bundleID: "com.apple.FaceTime", name: "FaceTime", behavior: .float),
    ]

    public func rule(for bundleID: String?) -> AppRule? {
        guard let b = bundleID?.lowercased() else { return nil }
        return appRules.first { $0.bundleID.lowercased() == b }
    }

    /// True unless the app has been set not to tile.
    public func tiles(_ bundleID: String?) -> Bool { (rule(for: bundleID)?.behavior ?? .tile) == .tile }

    public mutating func setTiles(_ on: Bool, bundleID: String, name: String) {
        appRules.removeAll { $0.bundleID.lowercased() == bundleID.lowercased() }
        if !on { appRules.append(AppRule(bundleID: bundleID, name: name, behavior: .float)) }
    }

    public func combos(for c: Command) -> [KeyCombo] {
        bindings[c.rawValue] ?? Command.defaultBindings[c] ?? []
    }

    /// All active shortcuts. Later commands lose a clash, so each key does one thing.
    public func effectiveBindings() -> [KeyCombo: Command] {
        guard shortcutsEnabled else { return [:] }
        var out: [KeyCombo: Command] = [:]
        for c in Command.allCases {
            for k in combos(for: c) where out[k] == nil { out[k] = c }
        }
        return out
    }

    public func conflicts() -> [KeyCombo: [Command]] {
        var seen: [KeyCombo: [Command]] = [:]
        for c in Command.allCases { for k in combos(for: c) { seen[k, default: []].append(c) } }
        return seen.filter { $0.value.count > 1 }
    }

    // MARK: Tolerant decoding: unknown or broken keys fall back to defaults.

    public static func decode(_ data: Data) -> Config {
        guard let stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(Config()),
              let defaults = (try? JSONSerialization.jsonObject(with: defaultsData)) as? [String: Any]
        else { return Config() }
        func attempt(_ dict: [String: Any]) -> Config? {
            guard let d = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(Config.self, from: d)
        }
        var merged = defaults
        for (k, v) in stored where defaults[k] != nil { merged[k] = v }
        if let c = attempt(merged) { return c }
        var good = defaults
        for (k, v) in stored where defaults[k] != nil {
            var trial = good
            trial[k] = v
            if attempt(trial) != nil { good = trial }
        }
        return attempt(good) ?? Config()
    }

    public func encoded() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? enc.encode(self)) ?? Data()
    }

    /// Sets one setting from text, for `ribbon config set <key> <value>`.
    public mutating func set(_ key: String, to value: String) throws {
        guard let data = try? JSONEncoder().encode(self),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let current = dict[key] else { throw ConfigError.unknownKey(key) }
        let parsed: Any
        if current is String {
            parsed = value
        } else if value == "true" || value == "false" || value == "on" || value == "off" {
            parsed = value == "true" || value == "on"
        } else if let d = Double(value) {
            parsed = d
        } else if let json = try? JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed]) {
            parsed = json
        } else {
            parsed = value
        }
        dict[key] = parsed
        guard let d2 = try? JSONSerialization.data(withJSONObject: dict),
              let c = try? JSONDecoder().decode(Config.self, from: d2) else { throw ConfigError.badValue(key, value) }
        self = c
    }

    public func value(of key: String) -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let v = dict[key] else { return nil }
        if let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .sortedKeys]) {
            return String(decoding: d, as: UTF8.self)
        }
        return "\(v)"
    }
}

public enum ConfigError: Error, CustomStringConvertible {
    case unknownKey(String), badValue(String, String)
    public var description: String {
        switch self {
        case .unknownKey(let k): return "Unknown setting '\(k)'"
        case .badValue(let k, let v): return "Can't set '\(k)' to '\(v)'"
        }
    }
}
