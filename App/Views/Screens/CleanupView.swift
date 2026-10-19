import HavenCore
import SwiftUI

struct CleanupView: View {
    @Environment(\.theme) private var theme
    private var store: LibraryStore { .shared }
    private var model: AppModel { .shared }
    private var prefs: Prefs { .shared }

    var body: some View {
        let cards = store.derived.cleanupCards
        let total = cards.reduce(Int64(0)) { $0 + $1.totalBytes } + store.duplicates.reclaimableBytes
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Clean Up", subtitle: total > 0 ? "Up to \(ByteSize.format(total)) you could free" : "Nothing to clean up right now",
                           symbol: "sparkles")
                TipBanner(id: "cleanup.intro", symbol: "trash.slash",
                          title: "Nothing is ever deleted outright",
                          message: "Every card opens a review page first. Files you choose go to the Trash, and you can put them back with Undo or from the Activity page.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 16)], spacing: 16) {
                    Button { model.navigate(to: .duplicates) } label: {
                        BigCleanupCard(kind: .duplicates,
                                       count: store.duplicates.groups.reduce(0) { $0 + $1.items.count - 1 },
                                       bytes: store.duplicates.reclaimableBytes,
                                       status: store.duplicates.isRunning ? "Checking…" : (store.duplicates.lastRun == nil ? "Not checked yet" : nil))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("cleanup.card.duplicates")
                    ForEach(CleanupKind.allCases.filter { $0 != .duplicates }) { kind in
                        let card = cards.first { $0.kind == kind }
                        Button { model.navigate(to: .cleanupCard(kind)) } label: {
                            BigCleanupCard(kind: kind, count: card?.items.count ?? 0, bytes: card?.totalBytes ?? 0, status: nil)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("cleanup.card.\(kind.rawValue)")
                    }
                }
                rulesSection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .background(theme.canvas)
        .onAppear { model.setVisible([]) }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Automatic Rules", subtitle: "Off unless you turn them on")
            ForEach(AutoRule.allCases) { rule in
                RuleRow(rule: rule)
            }
        }
    }
}

struct RuleRow: View {
    let rule: AutoRule
    @Environment(\.theme) private var theme
    @State private var preview = 0
    private var prefs: Prefs { .shared }

    var body: some View {
        let isOn = Binding(
            get: { prefs.enabledRules.contains(rule) },
            set: { on in
                if on { prefs.enabledRules.insert(rule) } else { prefs.enabledRules.remove(rule) }
                if on { RulesRunner.shared.runIfDue(force: true) }
            }
        )
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: rule.symbolName)
                .font(.title3)
                .foregroundStyle(theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.title).font(.headline)
                Text(rule.detail(prefs.ruleSettings)).font(.callout).foregroundStyle(.secondary)
                Text(preview == 0 ? "Nothing to do right now." : "Right now this would tidy \(HavenFormat.count(preview, "file")).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityIdentifier("rule.\(rule.rawValue)")
        }
        .cardStyle(theme, padding: 14)
        .task(id: LibraryStore.shared.version) { preview = RulesRunner.shared.plan(rule).count }
    }
}

struct BigCleanupCard: View {
    let kind: CleanupKind
    let count: Int
    let bytes: Int64
    let status: String?
    @Environment(\.theme) private var theme
    private var prefs: Prefs { .shared }

    var body: some View {
        let color = cleanupColor(kind, theme: theme)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(theme.isPlayful ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                } else if count == 0 {
                    Label("All clear", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(ByteSize.format(bytes))
                        .font(.system(size: 22, weight: .bold, design: theme.headingDesign))
                }
            }
            Text(kind.title)
                .font(.system(.title3, design: theme.headingDesign).weight(.semibold))
            Text(kind.explanation(prefs.cleanup))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(count == 0 ? "Nothing found" : HavenFormat.count(count, "item"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Review")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.accent)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .cardStyle(theme, padding: 18)
        .interactiveCard(tint: color)
    }
}

/// Review page for one Clean Up card: everything is ticked; untick what to keep. Files that join the card
/// while you look start unticked, and the confirmation trashes exactly the files it counted.
struct CleanupReviewView: View {
    let kind: CleanupKind
    @State private var ticked: Set<String> = []
    /// Files already shown on this page (later arrivals aren't ticked for you).
    @State private var seen: Set<String> = []
    /// The exact files a confirmation is about.
    @State private var pending: [FileItem] = []
    @State private var confirmAll = false
    @State private var confirmSelected = false
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager
    private var store: LibraryStore { .shared }
    private var model: AppModel { .shared }
    private var prefs: Prefs { .shared }

    private var items: [FileItem] {
        store.derived.cleanupCards.first { $0.kind == kind }?.items ?? []
    }

    var body: some View {
        let all = items
        let selected = all.filter { ticked.contains($0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: kind.title, subtitle: kind.explanation(prefs.cleanup), symbol: kind.symbolName)
                if all.isEmpty {
                    EmptyStateView(symbol: "checkmark.seal", title: "All clear", message: "Nothing here needs your attention.")
                        .frame(minHeight: 280)
                } else {
                    actionBar(all: all, selected: selected)
                    LazyVStack(spacing: 6) {
                        ForEach(all) { item in
                            reviewRow(item, all: all)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .background(theme.canvas)
        .onAppear {
            model.setVisible(all)
            noteShown(all.map(\.id))
        }
        .onChange(of: all.map(\.id)) { _, ids in noteShown(ids) }
        .confirmationDialog("Move \(HavenFormat.count(pending.count, "item")) to the Trash?", isPresented: $confirmAll) {
            Button("Move All to Trash · \(ByteSize.format(pending.totalSize))", role: .destructive) {
                model.trash(pending, reason: "Clean Up · \(kind.title)", undoManager: undoManager)
                pending = []
            }
            Button("Cancel", role: .cancel) { pending = [] }
        } message: {
            Text("You can put them back with Undo or from the Trash.")
        }
        .confirmationDialog("Move \(HavenFormat.count(pending.count, "item")) to the Trash?", isPresented: $confirmSelected) {
            Button("Move to Trash · \(ByteSize.format(pending.totalSize))", role: .destructive) {
                model.trash(pending, reason: "Clean Up · \(kind.title)", undoManager: undoManager)
                ticked.subtract(pending.map(\.id))
                pending = []
            }
            .accessibilityIdentifier("cleanup.confirm")
            Button("Cancel", role: .cancel) { pending = [] }
        } message: {
            Text("You can put them back with Undo or from the Trash.")
        }
    }

    /// The first files shown start ticked; files that turn up later start unticked.
    private func noteShown(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        if seen.isEmpty { ticked = Set(ids) }
        seen.formUnion(ids)
    }

    private func actionBar(all: [FileItem], selected: [FileItem]) -> some View {
        HStack(spacing: 12) {
            Text("\(selected.count) of \(all.count) selected · \(ByteSize.format(selected.totalSize))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cleanup.selection")
            Button(selected.count == all.count ? "Select None" : "Select All") {
                ticked = selected.count == all.count ? [] : Set(all.map(\.id))
            }
            .buttonStyle(.link)
            Spacer()
            Button("Trash Selected") {
                pending = selected
                confirmSelected = true
            }
                .buttonStyle(.bordered)
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("cleanup.trashSelected")
            Button {
                pending = all
                confirmAll = true
            } label: {
                Label("Trash All", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.isPlayful ? Color(hex: 0xE5484D) : .primary)
            .accessibilityIdentifier("cleanup.trashAll")
        }
        .cardStyle(theme, padding: 12)
    }

    private func reviewRow(_ item: FileItem, all: [FileItem]) -> some View {
        let isTicked = ticked.contains(item.id)
        return HStack(spacing: 12) {
            Button {
                if isTicked { ticked.remove(item.id) } else { ticked.insert(item.id) }
            } label: {
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isTicked ? theme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cleanup.tick")
            ThumbnailView(item: item, side: 46, cornerRadius: 7)
                .onTapGesture { model.preview(item, in: all) }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                Text(tildePath(item.parentPath)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteSize.format(item.size)).monospacedDigit()
                Text(detail(item)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            Button("Quick Look") { model.preview(item, in: all) }
            Button("Show in Finder") { model.revealInFinder([item]) }
            Button("Open") { NSWorkspace.shared.open(item.url) }
        }
    }

    private func detail(_ item: FileItem) -> String {
        switch kind {
        case .unusedApps, .forgottenDownloads, .bigOldVideos:
            if let opened = item.lastOpened { return "Last opened \(HavenFormat.ago(opened))" }
            return "Never opened · added \(HavenFormat.ago(item.arrivalDate))"
        case .oldScreenshots:
            return "Taken \(HavenFormat.ago(item.created))"
        default:
            return "Added \(HavenFormat.ago(item.arrivalDate))"
        }
    }
}
