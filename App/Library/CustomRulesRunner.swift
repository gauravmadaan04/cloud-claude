import Foundation
import HavenCore

/// Runs the rules you made: shortly after new files land in a watched folder, on the regular schedule,
/// and when you turn a rule on. Everything a rule does is in Activity and can be undone there.
@MainActor
final class CustomRulesRunner {
    static let shared = CustomRulesRunner()

    /// Files each rename rule has already renamed (their numbers on disk), so a file is renamed once per rule.
    private var handled: [String: [UInt64]] = [:]
    private var pending: Task<Void, Never>?
    private var isRunning = false
    private var runAgain = false

    private var handledURL: URL { LaunchOptions.current.supportDirectory.appendingPathComponent("rules-handled.json") }

    private init() {
        if let d = try? Data(contentsOf: handledURL), let h = try? JSONDecoder().decode([String: [UInt64]].self, from: d) {
            handled = h
        }
    }

    var enabledRules: [CustomRule] { Prefs.shared.customRules.filter(\.enabled) }

    /// What a rule would do right now (worked out in the background).
    func plan(_ rule: CustomRule) async -> [CustomRuleStep] {
        let items = LibraryStore.shared.items
        let lookup = LibraryStore.shared.text.lookup
        let store = LibraryStore.shared.text.store
        let done = Set(handled[rule.id.uuidString] ?? [])
        return await Task.detached(priority: .utility) { () -> [CustomRuleStep] in
            var steps = CustomRulePlanner.plan(rule, items: items, text: lookup)
            if case .rename(let template) = rule.action {
                steps = steps.filter { step in
                    if let id = FileOps.fileID(step.item.path), done.contains(id) { return false }
                    // A title comes from the file's text: wait until Haven has read it.
                    if template.usesText, step.item.kind.hasReadableText, !store.isFresh(step.item) { return false }
                    return true
                }
            }
            return steps
        }.value
    }

    /// New files arrived: rules watching their folders run a little later (so downloads can finish).
    func noteNewFiles(_ fresh: [FileItem]) {
        let rules = enabledRules
        guard !rules.isEmpty, !fresh.isEmpty, !LaunchOptions.current.isRunningUnitTests else { return }
        let watched = Set(rules.flatMap(\.folders))
        guard fresh.contains(where: { watched.contains($0.parentPath) }) else { return }
        schedule(after: 20)
    }

    /// Haven finished reading text: rename rules that use titles may have work now.
    func noteTextRead() {
        guard enabledRules.contains(where: { if case .rename(let t) = $0.action { return t.usesText } else { return false } }) else { return }
        schedule(after: 5)
    }

    private func schedule(after seconds: Double) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self.runAll()
        }
    }

    func runAll() async {
        guard !LaunchOptions.current.isRunningUnitTests else { return }
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        repeat {
            runAgain = false
            for rule in enabledRules { await run(rule) }
        } while runAgain
        isRunning = false
    }

    /// Runs one rule now. Returns how many files it acted on.
    @discardableResult
    func run(_ rule: CustomRule) async -> Int {
        let steps = await plan(rule)
        guard !steps.isEmpty else { return 0 }
        let reason = "Rule · \(rule.name)"
        switch rule.action {
        case .move:
            FileOps.shared.move(steps.compactMap { step in step.destination.map { (item: step.item, directory: $0) } }, reason: reason)
        case .trash:
            FileOps.shared.trash(steps.map(\.item), reason: reason, announce: true, undoable: false)
        case .addToCollection(let id):
            guard CollectionStore.shared.collection(id) != nil else { return 0 }
            CollectionStore.shared.add(steps.map(\.item.path), to: id)
        case .rename(let template):
            let changes = await RenameService.plan(steps.map(\.item), template: template)
            let entry = FileOps.shared.rename(changes, reason: reason, announce: false, undoable: false)
            // Remember every file this rule looked at, renamed or already well named.
            var ids = entry?.moves.compactMap(\.fileID) ?? []
            ids += changes.filter { !$0.isChange }.compactMap { FileOps.fileID($0.item.path) }
            remember(rule.id, ids)
            if let entry, !entry.moves.isEmpty {
                AppModel.shared.showToast(entry.moves.count == 1 ? "A rule renamed “\((entry.moves[0].from as NSString).lastPathComponent)”"
                                          : "A rule renamed \(entry.moves.count) files", symbol: "pencil", undoEntry: entry.id)
            }
        }
        return steps.count
    }

    private func remember(_ rule: UUID, _ ids: [UInt64]) {
        guard !ids.isEmpty else { return }
        var list = handled[rule.uuidString] ?? []
        list.append(contentsOf: ids)
        if list.count > 5000 { list.removeFirst(list.count - 5000) }
        handled[rule.uuidString] = list
        let snapshot = handled
        let url = handledURL
        Task.detached(priority: .utility) {
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url, options: .atomic) }
        }
    }

    func forget(_ rule: UUID) {
        handled[rule.uuidString] = nil
    }
}
