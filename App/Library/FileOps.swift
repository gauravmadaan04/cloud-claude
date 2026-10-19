import AppKit
import Foundation
import HavenCore

/// Every move Haven makes: files only ever go to the Trash or into folders, and everything can be put back.
@MainActor
@Observable
final class FileOps {
    static let shared = FileOps()

    private(set) var activity: [ActivityEntry] = []

    private var logURL: URL { LaunchOptions.current.supportDirectory.appendingPathComponent("activity.json") }

    private init() {
        if let d = try? Data(contentsOf: logURL), let a = try? JSONDecoder().decode([ActivityEntry].self, from: d) {
            activity = a
        }
    }

    private func saveLog() {
        let snapshot = Array(activity.prefix(500))
        if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: logURL, options: .atomic) }
    }

    // MARK: Trash

    @discardableResult
    func trash(_ items: [FileItem], reason: String, undoManager: UndoManager? = nil, announce: Bool = true) -> ActivityEntry? {
        var moves: [ActivityEntry.Move] = []
        var failed: [FileItem] = []
        for item in items {
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resulting)
                moves.append(.init(from: item.path, to: (resulting as URL?)?.path ?? "", size: item.size))
            } catch {
                failed.append(item)
            }
        }
        LibraryStore.shared.forget(paths: moves.map(\.from))
        guard !moves.isEmpty else {
            if let first = failed.first {
                AppModel.shared.showToast("Couldn't move “\(first.name)” to the Trash", symbol: "exclamationmark.triangle")
            }
            return nil
        }
        let entry = ActivityEntry(action: .trashed, reason: reason, moves: moves)
        activity.insert(entry, at: 0)
        saveLog()
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { ops in
                MainActor.assumeIsolated { ops.undo(entry.id) }
            }
            undoManager.setActionName("Move to Trash")
        }
        if announce {
            var message = moves.count == 1 ? "Moved “\((moves[0].from as NSString).lastPathComponent)” to the Trash"
                : "Moved \(moves.count) items to the Trash · \(ByteSize.format(entry.totalBytes))"
            if !failed.isEmpty { message += " (\(failed.count) couldn't be moved)" }
            AppModel.shared.showToast(message, symbol: "trash", undoEntry: entry.id)
        }
        return entry
    }

    // MARK: Move (rules)

    @discardableResult
    func move(_ plan: [(item: FileItem, directory: String)], reason: String) -> ActivityEntry? {
        let fm = FileManager.default
        var moves: [ActivityEntry.Move] = []
        for (item, dir) in plan {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let dest = RulesPlanner.uniqueDestination(name: item.name, in: dir) { fm.fileExists(atPath: $0) }
                try fm.moveItem(atPath: item.path, toPath: dest)
                moves.append(.init(from: item.path, to: dest, size: item.size))
            } catch {
                continue
            }
        }
        guard !moves.isEmpty else { return nil }
        LibraryStore.shared.forget(paths: moves.map(\.from))
        let entry = ActivityEntry(action: .moved, reason: reason, moves: moves)
        activity.insert(entry, at: 0)
        saveLog()
        let dirs = Set(moves.map { ($0.to as NSString).deletingLastPathComponent })
        Task { await LibraryStore.shared.refresh(directories: Array(dirs)) }
        return entry
    }

    // MARK: Undo

    func canUndo(_ entry: ActivityEntry) -> Bool {
        !entry.undone && entry.action != .restored && entry.moves.contains { FileManager.default.fileExists(atPath: $0.to) }
    }

    func undo(_ id: UUID) {
        guard let index = activity.firstIndex(where: { $0.id == id }) else { return }
        let entry = activity[index]
        guard !entry.undone else { return }
        let fm = FileManager.default
        var restored: [ActivityEntry.Move] = []
        for move in entry.moves where fm.fileExists(atPath: move.to) {
            let originalDir = (move.from as NSString).deletingLastPathComponent
            let name = (move.from as NSString).lastPathComponent
            do {
                try fm.createDirectory(atPath: originalDir, withIntermediateDirectories: true)
                let dest = RulesPlanner.uniqueDestination(name: name, in: originalDir) { fm.fileExists(atPath: $0) }
                try fm.moveItem(atPath: move.to, toPath: dest)
                restored.append(.init(from: move.to, to: dest, size: move.size))
            } catch {
                continue
            }
        }
        activity[index].undone = true
        if !restored.isEmpty {
            activity.insert(ActivityEntry(action: .restored, reason: "Undo · \(entry.reason)", moves: restored), at: 0)
            let dirs = Set(restored.map { ($0.to as NSString).deletingLastPathComponent })
            Task { await LibraryStore.shared.refresh(directories: Array(dirs)) }
            AppModel.shared.showToast(restored.count == 1 ? "Put back “\((restored[0].to as NSString).lastPathComponent)”" : "Put back \(restored.count) items",
                                      symbol: "arrow.uturn.backward")
        } else {
            AppModel.shared.showToast("Nothing to put back: the items are no longer in the Trash", symbol: "exclamationmark.triangle")
        }
        saveLog()
    }

    func clearHistory() {
        activity.removeAll()
        saveLog()
    }
}

/// Runs the optional automatic rules on launch and every few hours.
@MainActor
final class RulesRunner {
    static let shared = RulesRunner()
    private var timer: Timer?

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { RulesRunner.shared.runIfDue(force: true) }
        }
    }

    var screenshotSources: Set<String> {
        var set: Set<String> = []
        let opts = LaunchOptions.current
        set.insert((opts.homeForRoots as NSString).appendingPathComponent("Desktop"))
        if !opts.isFixtureMode,
           let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            set.insert((custom as NSString).expandingTildeInPath)
        }
        return set
    }

    var downloadsFolder: String {
        (LaunchOptions.current.homeForRoots as NSString).appendingPathComponent("Downloads")
    }

    func plan(_ rule: AutoRule) -> [RuleAction] {
        RulesPlanner.plan(rule, items: LibraryStore.shared.items, settings: Prefs.shared.ruleSettings,
                          screenshotSources: screenshotSources, downloadsFolder: downloadsFolder)
    }

    func runIfDue(force: Bool = false) {
        let prefs = Prefs.shared
        guard !prefs.enabledRules.isEmpty, !LaunchOptions.current.isRunningUnitTests else { return }
        if !force, let last = prefs.lastRulesRun, Date().timeIntervalSince(last) < 3 * 3600 { return }
        for rule in AutoRule.allCases where prefs.enabledRules.contains(rule) {
            run(rule)
        }
        prefs.lastRulesRun = Date()
    }

    @discardableResult
    func run(_ rule: AutoRule) -> Int {
        let actions = plan(rule)
        guard !actions.isEmpty else { return 0 }
        let trash = actions.filter { $0.operation == .trash }.map(\.item)
        var moves: [(item: FileItem, directory: String)] = []
        for a in actions {
            if case .move(let dir) = a.operation { moves.append((a.item, dir)) }
        }
        let reason = "Rule · \(rule.title)"
        if !trash.isEmpty { FileOps.shared.trash(trash, reason: reason, announce: false) }
        if !moves.isEmpty { FileOps.shared.move(moves, reason: reason) }
        return actions.count
    }
}
