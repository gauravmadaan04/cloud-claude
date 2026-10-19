import HavenCore
import SwiftUI

struct DuplicatesView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", identical = "Identical files", similar = "Look-alike photos"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    /// User overrides: path → keep (true) or trash (false).
    @State private var decisions: [String: Bool] = [:]
    @State private var confirming = false
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager

    private var dupes: DuplicateService { LibraryStore.shared.duplicates }
    private var store: LibraryStore { .shared }
    private var model: AppModel { .shared }

    private var groups: [DuplicateGroup] {
        switch filter {
        case .all: return dupes.groups
        case .identical: return dupes.identicalGroups
        case .similar: return dupes.similarGroups
        }
    }

    func keeps(_ item: FileItem, in group: DuplicateGroup) -> Bool {
        decisions[item.path] ?? (item.path == group.suggestedKeep)
    }

    private var toTrash: [FileItem] {
        groups.flatMap { g in g.items.filter { !keeps($0, in: g) } }
    }

    var body: some View {
        let trashList = toTrash
        let bytes = trashList.totalSize
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Duplicates", subtitle: subtitle, symbol: "square.on.square")
                TipBanner(id: "dupes.intro", symbol: "checkmark.shield",
                          title: "Haven keeps the best copy",
                          message: "Identical files match byte for byte (SHA-256). Look-alike photos are bursts, edits and HEIC/JPEG pairs, compared on this Mac with Apple's Vision. Click Keep or Trash to change Haven's pick. Files stored only in iCloud are skipped so nothing downloads.")
                statusRow
                if !dupes.groups.isEmpty {
                    freeUpBanner(count: trashList.count, bytes: bytes)
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)
                    ForEach(groups) { group in
                        DuplicateGroupCard(group: group, keeps: { keeps($0, in: group) }, toggle: { toggle($0, in: group) })
                    }
                } else if !dupes.isRunning {
                    EmptyStateView(symbol: "checkmark.seal", title: dupes.lastRun == nil ? "Not checked yet" : "No duplicates",
                                   message: dupes.lastRun == nil ? "Haven compares files on this Mac to find copies." : "Haven didn't find any copies. Nice and tidy.",
                                   actionTitle: dupes.lastRun == nil ? "Find Duplicates" : nil,
                                   action: dupes.lastRun == nil ? { rescan() } : nil)
                        .frame(minHeight: 300)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .background(theme.canvas)
        .onAppear {
            model.setVisible([])
            if dupes.lastRun == nil && !dupes.isRunning && store.hasLoaded { rescan() }
        }
        .confirmationDialog("Move \(HavenFormat.count(trashList.count, "file")) to the Trash?", isPresented: $confirming) {
            Button("Move to Trash · \(ByteSize.format(bytes))", role: .destructive) {
                model.trash(trashList, reason: "Duplicates", undoManager: undoManager)
                decisions = [:]
            }
            .accessibilityIdentifier("dupes.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One copy of each file stays where it is. You can put the others back with Undo or from the Trash.")
        }
    }

    private var subtitle: String {
        if dupes.groups.isEmpty { return "Identical files and look-alike photos" }
        return "\(HavenFormat.count(dupes.groups.count, "set")) · up to \(ByteSize.format(dupes.reclaimableBytes)) to free"
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 12) {
            switch dupes.phase {
            case .hashing(let p):
                ProgressPill(text: "Comparing files… \(Int(p * 100))%", progress: p)
                Button("Stop") { dupes.cancel() }.buttonStyle(.borderless)
            case .comparingPhotos(let p):
                ProgressPill(text: "Looking for look-alike photos… \(Int(p * 100))%", progress: p)
                Button("Stop") { dupes.cancel() }.buttonStyle(.borderless)
            default:
                if let last = dupes.lastRun {
                    Text("Checked \(HavenFormat.ago(last))").font(.callout).foregroundStyle(.secondary)
                }
                Button {
                    rescan()
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("dupes.rescan")
            }
            Spacer()
        }
    }

    private func freeUpBanner(count: Int, bytes: Int64) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Free up \(ByteSize.format(bytes))")
                    .font(.system(.title3, design: theme.headingDesign).weight(.bold))
                    .accessibilityIdentifier("dupes.freeup")
                Text("\(HavenFormat.count(count, "copy", "copies")) marked Trash. Everything else stays.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                confirming = true
            } label: {
                Label("Move \(count) to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.isPlayful ? Color(hex: 0xE5484D) : .primary)
            .disabled(count == 0)
            .accessibilityIdentifier("dupes.trash")
        }
        .cardStyle(theme, padding: 16)
    }

    private func toggle(_ item: FileItem, in group: DuplicateGroup) {
        let newValue = !keeps(item, in: group)
        if !newValue {
            // Never trash every copy.
            let others = group.items.filter { $0.path != item.path }
            if !others.contains(where: { keeps($0, in: group) }) {
                model.showToast("Keep at least one copy", symbol: "hand.raised")
                return
            }
        }
        decisions[item.path] = newValue
    }

    private func rescan() {
        dupes.scan(items: store.items, similar: Prefs.shared.findSimilarPhotos)
    }
}

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let keeps: (FileItem) -> Bool
    let toggle: (FileItem) -> Void
    @Environment(\.theme) private var theme
    private var model: AppModel { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: group.kind == .identical ? "equal.square" : "photo.stack")
                    .foregroundStyle(theme.accent)
                Text(group.kind == .identical ? "\(group.items.count) identical copies" : "\(group.items.count) look-alike photos")
                    .font(.headline)
                if group.kind == .identical, let first = group.items.first {
                    Text("· \(ByteSize.format(first.size)) each").foregroundStyle(.secondary)
                }
                Spacer()
                Text("Frees \(ByteSize.format(group.items.filter { !keeps($0) }.totalSize))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(group.items) { item in
                        tile(item)
                    }
                }
            }
        }
        .cardStyle(theme, padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dupes.group")
    }

    private func tile(_ item: FileItem) -> some View {
        let keep = keeps(item)
        return VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(item: item, side: 150, height: 110, cornerRadius: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(keep ? Color.green.opacity(0.8) : Color.red.opacity(0.55), lineWidth: 2)
                )
                .opacity(keep ? 1 : 0.6)
                .onTapGesture { model.preview(item, in: group.items) }
                .contextMenu {
                    Button("Show in Finder") { model.revealInFinder([item]) }
                    Button("Open") { NSWorkspace.shared.open(item.url) }
                }
            Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text("\(item.parentName) · \(ByteSize.format(item.size))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(HavenFormat.friendlyDate(item.created)).font(.caption2).foregroundStyle(.secondary)
            Button {
                toggle(item)
            } label: {
                Label(keep ? "Keep" : "Trash", systemImage: keep ? "checkmark.circle.fill" : "trash.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(keep ? Color.green : Color.red)
                    .background((keep ? Color.green : Color.red).opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(keep ? "Haven will keep this copy. Click to trash it instead." : "This copy goes to the Trash. Click to keep it.")
            .accessibilityIdentifier(keep ? "dupes.keep" : "dupes.trashmark")
        }
        .frame(width: 150)
    }
}
