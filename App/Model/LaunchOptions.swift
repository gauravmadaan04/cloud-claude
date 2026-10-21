import Foundation

/// Command-line switches used by the UI tests and for trying Haven on sample files.
///
///   -HavenFixtureRoot <path>   index <path>/Desktop, <path>/Documents… instead of the real home folders
///   -HavenMakeFixtures YES      fill the fixture root with sample files first (debug builds)
///   -HavenResetState YES        forget settings and caches (fresh onboarding)
///   -HavenSkipOnboarding YES    go straight to the app
///   -HavenAppearance dark       start in light/dark/system appearance (not saved)
///   -HavenLook minimal          start in the playful/minimal look (not saved)
///   -HavenMakeFixtures tools    sample files for the tools (photos, PDFs, a video, a voice memo) instead
///   -HavenWhisperModel <path>   transcribe with this model file (the tests use a small one)
struct LaunchOptions {
    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    let fixtureRoot: String?
    let makeFixtures: Bool
    let resetState: Bool
    let skipOnboarding: Bool
    let appearance: String?
    let look: String?
    /// "tools" for the tools' sample files.
    let fixtureSet: String?
    let whisperModel: String?

    init(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        func flag(_ name: String) -> Bool {
            guard let v = value(name)?.lowercased() else { return false }
            return v == "yes" || v == "1" || v == "true"
        }
        fixtureRoot = value("-HavenFixtureRoot").map { ($0 as NSString).expandingTildeInPath }
        fixtureSet = value("-HavenMakeFixtures")?.lowercased()
        makeFixtures = flag("-HavenMakeFixtures") || fixtureSet == "tools"
        whisperModel = value("-HavenWhisperModel").map { ($0 as NSString).expandingTildeInPath }
        resetState = flag("-HavenResetState")
        skipOnboarding = flag("-HavenSkipOnboarding")
        appearance = value("-HavenAppearance")?.lowercased()
        look = value("-HavenLook")?.lowercased()
    }

    var isFixtureMode: Bool { fixtureRoot != nil }

    /// Hosted unit tests load the app too; it should stay idle for them.
    var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var homeForRoots: String { fixtureRoot ?? NSHomeDirectory() }

    var applicationsFolder: String {
        if let root = fixtureRoot { return (root as NSString).appendingPathComponent("Applications") }
        return "/Applications"
    }

    /// Fixture runs keep their settings apart from the real ones.
    var defaults: UserDefaults {
        if isFixtureMode, let d = UserDefaults(suiteName: "app.haven.Haven.fixture") { return d }
        // Unit tests never touch your real settings.
        if isRunningUnitTests, let d = UserDefaults(suiteName: "app.haven.Haven.tests") { return d }
        return .standard
    }

    /// ~/Library/Application Support/Haven (or a fixture-specific folder).
    var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        // Sample-folder runs and unit tests keep their caches apart from your real index and activity log.
        let name = isFixtureMode ? "Haven-Fixture" : (isRunningUnitTests ? "Haven-Tests" : "Haven")
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Wipes saved state when asked to (UI tests start every run fresh).
    func applyReset() {
        guard resetState else { return }
        if isFixtureMode {
            UserDefaults.standard.removePersistentDomain(forName: "app.haven.Haven.fixture")
            defaults.dictionaryRepresentation().keys.forEach { defaults.removeObject(forKey: $0) }
        } else if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        try? FileManager.default.removeItem(at: supportDirectory)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }
}
