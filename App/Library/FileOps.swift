import AppKit
import Foundation
import HavenCore

/// Every move Haven makes: files only ever go to the Trash or into folders, and everything can be put back.
@MainActor
@Observable
final class FileOps {
    static let shared = FileOps()

    private(set) var activity: [ActivityEntry] = []
    /// Each trash registers its own undo target, so Undo from the toast or Activity can take back the
    /// matching ⌘Z step instead of leaving a dead one behind.
    @ObservationIgnored private var undoTargets: [UUID: (target: UndoTarget, manager: UndoManager)] = [:]
    /// Pastes run one after another, so two quick ⌘Vs pick different free names.
    @ObservationIgnored private var pasteTail: Task<Void, Never>?

    private final class UndoTarget {}

    private var logURL: URL { LaunchOptions.current.supportDirectory.appendingPathComponent("activity.json") }

    /// The number a file has on its disk (stays the same when it's moved on that disk).
    nonisolated static func fileID(_ path: String) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    /// Selected items inside other selected folders go along with their folder.
    static func outermost(_ items: [FileItem]) -> [FileItem] {
        let folders = Set(items.filter { $0.kind == .folder || $0.kind == .app }.map(\.path))
        guard !folders.isEmpty else { return items }
        // Walk up each file's folders (a handful of steps) instead of comparing against every selected folder.
        return items.filter { item in
            var parent = FileItem.parent(of: item.path)
            while parent.count > 1 {
                if folders.contains(parent) { return false }
                parent = FileItem.parent(of: parent)
            }
            return true
        }
    }

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
    func trash(_ items: [FileItem], reason: String, undoManager: UndoManager? = nil, announce: Bool = true,
               undoable: Bool = true) -> ActivityEntry? {
        var moves: [ActivityEntry.Move] = []
        var failed: [FileItem] = []
        for item in FileOps.outermost(items) {
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resulting)
                let to = (resulting as URL?)?.path ?? ""
                moves.append(.init(from: item.path, to: to, size: item.size, fileID: to.isEmpty ? nil : FileOps.fileID(to)))
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
        // ⌘Z undoes anything you trashed yourself (rules run on their own and are undone from Activity).
        if undoable, let manager = undoManager ?? AppModel.mainWindow?.undoManager {
            let target = UndoTarget()
            undoTargets[entry.id] = (target, manager)
            manager.registerUndo(withTarget: target) { _ in
                MainActor.assumeIsolated { FileOps.shared.undo(entry.id, viaUndoManager: true) }
            }
            manager.setActionName("Move to Trash")
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

    /// The moved file is still where Haven put it, and it's the same file (not a later one with the same name).
    static func isStillThere(_ move: ActivityEntry.Move) -> Bool {
        guard !move.to.isEmpty, FileManager.default.fileExists(atPath: move.to) else { return false }
        guard let expected = move.fileID else { return true }
        return fileID(move.to) == expected
    }

    func canUndo(_ entry: ActivityEntry) -> Bool {
        !entry.undone && entry.action != .restored && entry.moves.contains(where: FileOps.isStillThere)
    }

    func undo(_ id: UUID, viaUndoManager: Bool = false) {
        guard let index = activity.firstIndex(where: { $0.id == id }) else { return }
        if let registered = undoTargets.removeValue(forKey: id), !viaUndoManager {
            registered.manager.removeAllActions(withTarget: registered.target)
        }
        let entry = activity[index]
        guard !entry.undone else { return }
        let fm = FileManager.default
        var restored: [ActivityEntry.Move] = []
        // Last moved first, so folders come back before anything that was inside them.
        for move in entry.moves.reversed() where FileOps.isStillThere(move) {
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

    // MARK: Paste (⌘V in a folder)

    /// Copies files into a folder, never replacing anything: a name that's taken gets " 2", " 3"…
    func copy(_ sources: [URL], into dir: String) {
        let items = sources.filter { src in
            // A folder can't be copied into itself.
            let p = src.standardizedFileURL.path
            return dir != p && !dir.hasPrefix(p + "/")
        }
        guard !items.isEmpty else { return }
        let previous = pasteTail
        pasteTail = Task {
            await previous?.value
            let created = await Task.detached(priority: .userInitiated) { () -> [String] in
                let fm = FileManager()
                var out: [String] = []
                for src in items {
                    let dest = RulesPlanner.uniqueDestination(name: src.lastPathComponent, in: dir) { fm.fileExists(atPath: $0) }
                    do {
                        try fm.copyItem(atPath: src.path, toPath: dest)
                        out.append(dest)
                    } catch {
                        continue
                    }
                }
                return out
            }.value
            guard let first = created.first else {
                AppModel.shared.showToast("Couldn't paste here", symbol: "exclamationmark.triangle")
                return
            }
            await LibraryStore.shared.refresh(directories: [dir])
            AppModel.shared.pendingReveal = first
            AppModel.shared.showToast(created.count == 1 ? "Pasted “\((first as NSString).lastPathComponent)”" : "Pasted \(created.count) items",
                                      symbol: "doc.on.clipboard")
        }
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
        // Say so when a rule trashes something, with Undo right there.
        if !trash.isEmpty { FileOps.shared.trash(trash, reason: reason, announce: true, undoable: false) }
        if !moves.isEmpty { FileOps.shared.move(moves, reason: reason) }
        return actions.count
    }
}
