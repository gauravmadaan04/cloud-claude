import Foundation

public enum NewWindowPlacement: String, Codable, CaseIterable {
    case afterFocused, end
    public var title: String { self == .afterFocused ? "Next to the focused window" : "At the end of the strip" }
}

public enum IndicatorPosition: String, Codable, CaseIterable {
    case bottom, top
    public var title: String { self == .bottom ? "Bottom" : "Top" }
}

public enum AppBehavior: String, Codable, CaseIterable {
    case tile, float, ignore
    public var title: String {
        switch self {
        case .tile: return "Tile"
        case .float: return "Float"
        case .ignore: return "Ignore completely"
        }
    }
}

public struct AppRule: Codable, Equatable, Identifiable, Hashable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var behavior: AppBehavior
    /// Opening width for this app's windows (fraction), nil = the general default.
    public var width: Double?

    public init(bundleID: String, name: String, behavior: AppBehavior, width: Double? = nil) {
        self.bundleID = bundleID; self.name = name; self.behavior = behavior; self.width = width
    }
}

/// Every user setting. Changes apply instantly; there is no Save button.
public struct Config: Codable, Equatable {
    public var tilingEnabled = true
    public var innerGap: Double = 10
    public var outerGap: Double = 10
    public var widthPresets: [Double] = [0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75]
    /// Opening width of new windows (fraction of the working width).
    public var defaultWidth: Double = 0.5
    /// Keep the width a window opens with instead of `defaultWidth`.
    public var useOwnWidth = false
    public var newWindowPlacement: NewWindowPlacement = .afterFocused
    public var centerMode: CenterMode = .never
    public var sparse: SparseAlignment = .left
    public var keepOriginalHeight = false
    public var animate = true
    /// Spring settle time in seconds.
    public var animationResponse: Double = 0.26
    public var focusBorder = false
    public var borderColor = "#4F8CFF"
    public var borderWidth: Double = 4
    public var borderRadius: Double = 12
    public var dimUnfocused = false
    public var dimAmount: Double = 0.25
    public var focusFollowsMouse = false
    public var showIndicatorOnScroll = true
    public var showIndicatorOnHold = true
    public var indicatorPosition: IndicatorPosition = .bottom
    public var swipeEnabled = true
    public var swipeFingers = 3
    public var swipeNatural = true
    public var swipeSensitivity: Double = 1.0
    public var scrollWheelWithModifiers = true
    public var floatFixedSizeWindows = true
    public var restoreSession = true
    public var tabBarHeight: Double = 28
    public var excludedDisplays: [String] = []
    public var appRules: [AppRule] = Config.defaultRules
    /// Shortcut overrides keyed by command name. Missing commands use the defaults.
    public var bindings: [String: [KeyCombo]] = [:]
    public var hasCompletedOnboarding = false

    public init() {}

    public static let defaultRules: [AppRule] = [
        AppRule(bundleID: "com.apple.systempreferences", name: "System Settings", behavior: .float),
        AppRule(bundleID: "com.apple.calculator", name: "Calculator", behavior: .float),
        AppRule(bundleID: "com.apple.archiveutility", name: "Archive Utility", behavior: .float),
        AppRule(bundleID: "com.apple.ScreenContinuity", name: "iPhone Mirroring", behavior: .float),
    ]

    public func rule(for bundleID: String?) -> AppRule? {
        guard let b = bundleID?.lowercased() else { return nil }
        return appRules.first { $0.bundleID.lowercased() == b }
    }

    public func combos(for c: Command) -> [KeyCombo] {
        bindings[c.rawValue] ?? Command.defaultBindings[c] ?? []
    }

    /// All active shortcuts. Later commands lose a clash, so each key does one thing.
    public func effectiveBindings() -> [KeyCombo: Command] {
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
