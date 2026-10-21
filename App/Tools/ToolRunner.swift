import AppKit
import HavenCore
import SwiftUI
import UniformTypeIdentifiers

/// A tool running in the background, shown as a card with a progress bar and a Stop button.
@MainActor
@Observable
final class ToolJob: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var progress = 0.0
    @ObservationIgnored var task: Task<Void, Never>?

    init(title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    func cancel() { task?.cancel() }
}

/// Runs tools in the background. What they make is recorded in Activity, selected when it appears, and Undo
/// (⌘Z, the toast or Activity) moves it to the Trash.
@MainActor
@Observable
final class ToolRunner {
    static let shared = ToolRunner()
    private(set) var jobs: [ToolJob] = []

    static func jobTitle(_ tool: ToolID, _ items: [FileItem]) -> String {
        "\(tool.title) · " + (items.count == 1 ? items[0].name : "\(items.count) files")
    }

    @discardableResult
    func start(_ tool: ToolID, _ items: [FileItem], choice: ToolChoice = .none, extras: ToolExtras = ToolExtras()) -> ToolJob {
        run(Self.jobTitle(tool, items), symbol: tool.symbol, reason: tool.title) { progress in
            try await ToolWork.run(tool, items, choice: choice, extras: extras, progress: progress)
        }
    }

    /// Runs any work as a job (translations and summaries use this too).
    @discardableResult
    func run(_ title: String, symbol: String, reason: String, work: @escaping @Sendable (@escaping ProgressHandler) async throws -> JobOutcome) -> ToolJob {
        let job = ToolJob(title: title, symbol: symbol)
        jobs.append(job)
        let undo = AppModel.mainWindow?.undoManager
        job.task = Task { [weak self] in
            let report: ProgressHandler = { [weak job] p in
                Task { @MainActor in
                    guard let job else { return }
                    job.progress = max(job.progress, min(1, p))
                }
            }
            do {
                let outcome = try await work(report)
                self?.finish(reason, outcome, symbol: symbol, undo: undo)
            } catch is CancellationError {
                AppModel.shared.showToast("Stopped: \(reason)", symbol: "stop.circle")
            } catch {
                AppModel.shared.showToast(error.localizedDescription, symbol: "exclamationmark.triangle")
            }
            self?.jobs.removeAll { $0.id == job.id }
        }
        return job
    }

    /// Records what was made (so Undo can take it away) and says so.
    func finish(_ reason: String, _ outcome: JobOutcome, symbol: String, undo: UndoManager?) {
        guard !outcome.made.isEmpty else {
            AppModel.shared.showToast(outcome.message ?? "Nothing was made", symbol: "exclamationmark.triangle")
            return
        }
        let entry = FileOps.shared.recordCreated(outcome.made.map { (from: $0.from, to: $0.to) }, reason: reason, undoManager: undo)
        let message = outcome.message ?? (outcome.made.count == 1 ? "Made “\((outcome.made[0].to as NSString).lastPathComponent)”"
            : "Made \(outcome.made.count) files")
        AppModel.shared.showToast(message, symbol: symbol, undoEntry: entry?.id)
    }
}

/// A tool waiting for its sheet (password, pages, time range, order, language…).
struct ToolSheetRequest: Identifiable {
    let id = UUID()
    let tool: ToolID
    let items: [FileItem]
}

/// What happens when you pick a tool, from a right-click, the Tools menu or the File Tools page.
@MainActor
enum ToolActions {
    static func perform(_ tool: ToolID, _ items: [FileItem], choice: ToolChoice = .none) {
        let model = AppModel.shared
        guard tool.applies(to: items) else {
            model.showToast(tool.choosePrompt, symbol: tool.symbol)
            return
        }
        if tool == .unlockPDF, !PDFTools.isLocked(items[0].url) {
            model.showToast("“\(items[0].name)” doesn't have a password", symbol: "lock.open")
            return
        }
        if tool.opensSheet || (choice == .none && !tool.choices(for: items).isEmpty) {
            model.bringMainWindowForward()
            model.toolSheet = ToolSheetRequest(tool: tool, items: items)
            return
        }
        ToolRunner.shared.start(tool, items, choice: choice)
    }

    /// From the File Tools page: pick the files first.
    static func choose(_ tool: ToolID) {
        let panel = NSOpenPanel()
        panel.message = tool.choosePrompt
        panel.prompt = tool.title
        panel.allowsMultipleSelection = tool.count.max != 1
        panel.canChooseDirectories = false
        panel.allowedContentTypes = tool.inputs.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = URL(fileURLWithPath: LaunchOptions.current.homeForRoots)
        guard panel.runModal() == .OK else { return }
        perform(tool, items(panel.urls))
    }

    /// Files dropped on a tool card.
    @discardableResult
    static func dropped(_ urls: [URL], on tool: ToolID) -> Bool {
        let files = items(urls)
        guard tool.applies(to: files) else {
            AppModel.shared.showToast(tool.choosePrompt, symbol: tool.symbol)
            return false
        }
        perform(tool, files)
        return true
    }

    static func items(_ urls: [URL]) -> [FileItem] {
        urls.compactMap { FileScanner.item(at: $0, rootID: "tools") }
    }

    /// The Tools submenu of the right-click menu: only what fits these files, grouped.
    static func menuItem(for items: [FileItem]) -> NSMenuItem? {
        let tools = ToolID.available(for: items)
        guard !tools.isEmpty else { return nil }
        let root = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        let menu = NSMenu()
        var group: ToolGroup?
        for tool in tools {
            if let group, group != tool.group { menu.addItem(.separator()) }
            group = tool.group
            let choices = tool.choices(for: items)
            if choices.isEmpty {
                menu.addItem(ClosureMenuItem(tool.title + (tool.opensSheet ? "…" : ""), symbol: tool.symbol) { perform(tool, items) })
            } else {
                let item = NSMenuItem(title: tool.title, action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
                let sub = NSMenu()
                for c in choices {
                    sub.addItem(ClosureMenuItem(c.title) { perform(tool, items, choice: c.choice) })
                }
                item.submenu = sub
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("All File Tools", symbol: "square.grid.2x2") { AppModel.shared.navigate(to: .tools) })
        root.submenu = menu
        return root
    }
}

/// Running tools, bottom right of the main window.
struct JobsView: View {
    private var runner: ToolRunner { .shared }
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(runner.jobs) { job in
                JobCard(job: job)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: runner.jobs.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jobs")
    }
}

struct JobCard: View {
    let job: ToolJob
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.symbol)
                .foregroundStyle(theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(job.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
            }
            .frame(width: 220)
            Button { job.cancel() } label: {
                Image(systemName: "stop.circle.fill").font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Stop")
            .accessibilityIdentifier("job.stop")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassBackground(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("job")
    }
}

/// The Tools menu in the menu bar: every tool, enabled when it fits the selected files.
struct ToolsMenuContent: View {
    private var model: AppModel { .shared }

    var body: some View {
        let items = model.selectedItems
        ForEach(ToolGroup.allCases) { group in
            Menu(group.title) {
                ForEach(group.tools) { tool in
                    let choices = tool.choices(for: items)
                    if choices.isEmpty {
                        Button(tool.title + (tool.opensSheet ? "…" : "")) { ToolActions.perform(tool, items) }
                            .disabled(!tool.applies(to: items))
                    } else {
                        Menu(tool.title) {
                            ForEach(choices.indices, id: \.self) { i in
                                Button(choices[i].title) { ToolActions.perform(tool, items, choice: choices[i].choice) }
                            }
                        }
                        .disabled(!tool.applies(to: items))
                    }
                }
            }
        }
        Divider()
        Button("Show File Tools") {
            model.bringMainWindowForward()
            model.navigate(to: .tools)
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
