import Foundation
import SwiftUI
import HavenCore
import Carbon.HIToolbox

enum Look: String, CaseIterable, Identifiable, Codable {
    case playful, minimal
    var id: String { rawValue }
    var title: String { self == .playful ? "Playful" : "Minimal" }
    var symbol: String { self == .playful ? "paintpalette" : "circle.lefthalf.filled" }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
}

enum DoubleClickAction: String, CaseIterable, Identifiable {
    case preview, open
    var id: String { rawValue }
    var title: String { self == .preview ? "Show a large preview" : "Open the file" }
}

enum OCRScope: String, CaseIterable, Identifiable {
    case off, screenshots, recent, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .screenshots: return "Screenshots only"
        case .recent: return "Screenshots and photos from the last year"
        case .all: return "All images"
        }
    }
}

/// A global keyboard shortcut in Carbon terms (what RegisterEventHotKey wants).
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey), display: "⇧⌘Space")
}

/// Everything the user can change, saved in UserDefaults as it changes.
@MainActor
@Observable
final class Prefs {
    static let shared = Prefs(defaults: LaunchOptions.current.defaults)

    @ObservationIgnored let defaults: UserDefaults

    var look: Look { didSet { defaults.set(look.rawValue, forKey: "look") } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var viewMode: ViewMode { didSet { defaults.set(viewMode.rawValue, forKey: "viewMode") } }
    var sortOrder: SortOrder { didSet { defaults.set(sortOrder.rawValue, forKey: "sortOrder") } }
    var cardSize: Double { didSet { defaults.set(cardSize, forKey: "cardSize") } }
    var doubleClick: DoubleClickAction { didSet { defaults.set(doubleClick.rawValue, forKey: "doubleClick") } }
    var showMenuBarExtra: Bool { didSet { defaults.set(showMenuBarExtra, forKey: "showMenuBarExtra") } }
    var quickSearchEnabled: Bool { didSet { defaults.set(quickSearchEnabled, forKey: "quickSearchEnabled") } }
    var hotKey: HotKeyCombo { didSet { saveJSON(hotKey, "hotKey") } }
    var ocrScope: OCRScope { didSet { defaults.set(ocrScope.rawValue, forKey: "ocrScope") } }
    var findSimilarPhotos: Bool { didSet { defaults.set(findSimilarPhotos, forKey: "findSimilarPhotos") } }
    var cleanup: CleanupSettings { didSet { saveJSON(cleanup, "cleanup") } }
    var enabledRules: Set<AutoRule> { didSet { defaults.set(enabledRules.map(\.rawValue), forKey: "enabledRules") } }
    var ruleSettings: RuleSettings { didSet { saveJSON(ruleSettings, "ruleSettings") } }
    var customRoots: [String] { didSet { defaults.set(customRoots, forKey: "customRoots") } }
    var disabledRoots: Set<String> { didSet { defaults.set(Array(disabledRoots), forKey: "disabledRoots") } }
    var pinnedFolders: [String] { didSet { defaults.set(pinnedFolders, forKey: "pinnedFolders") } }
    var savedSearches: [SavedSearch] { didSet { saveJSON(savedSearches, "savedSearches") } }
    var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    var dismissedTips: Set<String> { didSet { defaults.set(Array(dismissedTips), forKey: "dismissedTips") } }
    var lastRulesRun: Date? { didSet { defaults.set(lastRulesRun, forKey: "lastRulesRun") } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        func string(_ k: String) -> String? { defaults.string(forKey: k) }
        func bool(_ k: String, _ fallback: Bool) -> Bool { defaults.object(forKey: k) == nil ? fallback : defaults.bool(forKey: k) }
        func json<T: Decodable>(_ k: String, _ fallback: T) -> T {
            guard let d = defaults.data(forKey: k), let v = try? JSONDecoder().decode(T.self, from: d) else { return fallback }
            return v
        }
        look = string("look").flatMap(Look.init(rawValue:)) ?? .playful
        appearance = string("appearance").flatMap(AppearanceMode.init(rawValue:)) ?? .system
        viewMode = string("viewMode").flatMap(ViewMode.init(rawValue:)) ?? .grid
        sortOrder = string("sortOrder").flatMap(SortOrder.init(rawValue:)) ?? .dateNewest
        let size = defaults.double(forKey: "cardSize")
        cardSize = size == 0 ? 168 : min(320, max(110, size))
        doubleClick = string("doubleClick").flatMap(DoubleClickAction.init(rawValue:)) ?? .preview
        showMenuBarExtra = bool("showMenuBarExtra", true)
        quickSearchEnabled = bool("quickSearchEnabled", true)
        hotKey = json("hotKey", HotKeyCombo.default)
        ocrScope = string("ocrScope").flatMap(OCRScope.init(rawValue:)) ?? .recent
        findSimilarPhotos = bool("findSimilarPhotos", true)
        cleanup = json("cleanup", CleanupSettings())
        enabledRules = Set((defaults.stringArray(forKey: "enabledRules") ?? []).compactMap(AutoRule.init(rawValue:)))
        ruleSettings = json("ruleSettings", RuleSettings(home: LaunchOptions.current.homeForRoots))
        customRoots = defaults.stringArray(forKey: "customRoots") ?? []
        disabledRoots = Set(defaults.stringArray(forKey: "disabledRoots") ?? [])
        pinnedFolders = defaults.stringArray(forKey: "pinnedFolders") ?? []
        savedSearches = json("savedSearches", [SavedSearch]())
        onboardingDone = bool("onboardingDone", false)
        dismissedTips = Set(defaults.stringArray(forKey: "dismissedTips") ?? [])
        lastRulesRun = defaults.object(forKey: "lastRulesRun") as? Date
    }

    private func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        if let d = try? JSONEncoder().encode(value) { defaults.set(d, forKey: key) }
    }

    /// All roots Haven indexes: the standard folders (or the test fixture's) plus any added by the user.
    var roots: [IndexRoot] {
        let opts = LaunchOptions.current
        var list = IndexRoot.standard(home: opts.homeForRoots, applications: opts.applicationsFolder)
        list += customRoots.map(IndexRoot.custom(path:))
        return list.map { root in
            var r = root
            r.enabled = !disabledRoots.contains(root.id)
            return r
        }
    }

    var enabledRoots: [IndexRoot] { roots.filter(\.enabled) }

    func isTipDismissed(_ id: String) -> Bool { dismissedTips.contains(id) }
    func dismissTip(_ id: String) { dismissedTips.insert(id) }
}
