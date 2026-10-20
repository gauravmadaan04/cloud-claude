import HavenCore
import SwiftUI

/// Where the space goes: folders you can click into, the biggest files, and totals by kind, source and last use.
/// Everything comes from the index (no disk scan), so it opens instantly.
struct SpaceView: View {
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager
    /// The folder being looked into (nil: all indexed folders).
    @State private var folder: String?
    @State private var biggest: [FileItem] = []
    @State private var pendingTrash: [FileItem] = []
    @State private var confirmTrash = false
    private var store: LibraryStore { .shared }
    private var model: AppModel { .shared }
    private var prefs: Prefs { .shared }

    var body: some View {
        let d = store.derived
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Space",
                           subtitle: "\(ByteSize.format(d.space.totalBytes)) in \(HavenFormat.count(d.space.fileCount, "file")) Haven indexes",
                           symbol: "chart.pie")
                TipBanner(id: "space.intro", symbol: "chart.bar.xaxis", title: "See where your space goes",
                          message: "Click a folder to look inside it. Sizes add up the files Haven indexes; it skips hidden files, the insides of apps and build folders like node_modules.")
                StorageBar(stats: d.stats)
                HStack(alignment: .top, spacing: 18) {
                    foldersCard(d.folderSizes)
                        .frame(maxWidth: .infinity, alignment: .top)
                    biggestCard
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                HStack(alignment: .top, spacing: 18) {
                    slicesCard("By Kind", Array(d.space.byKind.prefix(8)), total: d.space.totalBytes) { slice in
                        guard let kind = FileKind(rawValue: slice.id), let c = kind.category else { return }
                        model.navigate(to: .category(c))
                        model.pageSortOverride = .sizeLargest
                    }
                    slicesCard("Downloaded From", Array(d.space.bySource.prefix(8)), total: d.space.totalBytes) { slice in
                        model.navigate(to: .source(slice.id))
                    }
                    slicesCard("By Last Use", d.space.byAge, total: d.space.totalBytes, action: nil)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .background(theme.canvas)
        .onAppear { model.setVisible([]) }
        .task(id: "\(folder ?? "")|\(store.version)") {
            let items = store.items
            let under = folder
            let top = await Task.detached(priority: .userInitiated) {
                SpaceReport.biggestFiles(items, under: under, limit: 14)
            }.value
            if !Task.isCancelled { biggest = top }
        }
        .confirmationDialog(trashTitle, isPresented: $confirmTrash) {
            Button("Move to Trash · \(ByteSize.format(pendingSize))", role: .destructive) {
                model.trash(pendingTrash, reason: "Space", undoManager: undoManager)
                pendingTrash = []
            }
            .accessibilityIdentifier("space.confirmTrash")
            Button("Cancel", role: .cancel) { pendingTrash = [] }
        } message: {
            Text("You can put it back with Undo or from the Trash.")
        }
        .accessibilityIdentifier("space")
    }

    private var trashTitle: String {
        pendingTrash.count == 1 ? "Move “\(pendingTrash[0].name)” to the Trash?" : "Move \(pendingTrash.count) items to the Trash?"
    }

    private var pendingSize: Int64 {
        pendingTrash.reduce(Int64(0)) { sum, item in
            sum + (item.kind == .folder ? (store.derived.folderSizes[item.path]?.bytes ?? 0) : item.size)
        }
    }

    // MARK: Folders

    struct FolderRow: Identifiable {
        let path: String
        let entry: FolderSizes.Entry
        var id: String { path }
    }

    private func foldersCard(_ sizes: FolderSizes) -> some View {
        let rows: [FolderRow]
        if let folder {
            rows = sizes.subfolders(of: folder).prefix(40).map { FolderRow(path: $0.path, entry: $0.entry) }
        } else {
            rows = prefs.enabledRoots.compactMap { root in
                sizes[root.path].map { FolderRow(path: root.path, entry: $0) }
            }
            .sorted { $0.entry.bytes > $1.entry.bytes }
        }
        let direct = folder.flatMap { sizes.direct[$0] }
        let largest = max(1, max(rows.first?.entry.bytes ?? 0, direct?.bytes ?? 0))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Folders").font(.system(size: 17, weight: .semibold, design: theme.headingDesign))
                Spacer()
                if let folder {
                    Button {
                        model.navigate(to: .folder(folder))
                    } label: {
                        Label("Open in Haven", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
            breadcrumbs
            if rows.isEmpty && direct == nil {
                Text("Nothing in here yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            }
            ForEach(rows) { row in
                SpaceRow(symbol: "folder.fill", title: FileManager.default.displayName(atPath: row.path),
                         detail: HavenFormat.count(row.entry.files, "file"), bytes: row.entry.bytes, fraction: Double(row.entry.bytes) / Double(largest),
                         tint: theme.accent, chevron: true) {
                    folder = row.path
                }
                .contextMenu {
                    Button("Open in Haven") { model.navigate(to: .folder(row.path)) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.path)]) }
                    if store.root(for: row.path)?.path != row.path {
                        Divider()
                        Button("Move to Trash…", role: .destructive) {
                            pendingTrash = [FileItem(path: row.path, created: Date(), modified: Date(), isDirectory: true)]
                            confirmTrash = true
                        }
                    }
                }
                .accessibilityIdentifier("space.folder.\((row.path as NSString).lastPathComponent)")
            }
            if let direct, direct.files > 0 {
                SpaceRow(symbol: "doc.on.doc", title: "Files right in this folder", detail: HavenFormat.count(direct.files, "file"),
                         bytes: direct.bytes, fraction: Double(direct.bytes) / Double(largest), tint: .secondary, chevron: false, action: nil)
            }
        }
        .cardStyle(theme, padding: 16)
    }

    private var breadcrumbs: some View {
        let trail = crumbs
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("All Folders") { folder = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(folder == nil ? Color.primary : theme.accent)
                    .accessibilityIdentifier("space.crumb.all")
                ForEach(trail, id: \.self) { path in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Button(FileManager.default.displayName(atPath: path)) { folder = path }
                        .buttonStyle(.plain)
                        .foregroundStyle(path == folder ? Color.primary : theme.accent)
                }
            }
            .font(.callout)
        }
    }

    /// The folders from the indexed folder down to the one being looked at.
    private var crumbs: [String] {
        guard let folder, let root = store.root(for: folder) else { return [] }
        var out: [String] = []
        var p = folder
        while true {
            out.insert(p, at: 0)
            if p == root.path || p.count <= 1 { break }
            p = FileItem.parent(of: p)
        }
        return out
    }

    // MARK: Biggest files

    private var biggestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(folder == nil ? "Biggest Files" : "Biggest Files Here")
                    .font(.system(size: 17, weight: .semibold, design: theme.headingDesign))
                Spacer()
                if !biggest.isEmpty {
                    Text(ByteSize.format(biggest.totalSize)).font(.callout).foregroundStyle(.secondary)
                }
            }
            if biggest.isEmpty {
                Text("No files here.").foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(biggest) { item in
                BigFileRow(item: item) {
                    model.preview(item, in: biggest)
                } trash: {
                    pendingTrash = [item]
                    confirmTrash = true
                }
            }
        }
        .cardStyle(theme, padding: 16)
        .accessibilityIdentifier("space.biggest")
    }

    // MARK: Slices

    private func slicesCard(_ title: String, _ slices: [SpaceReport.Slice], total: Int64, action: ((SpaceReport.Slice) -> Void)?) -> some View {
        let largest = max(1, slices.map(\.bytes).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .semibold, design: theme.headingDesign))
            if slices.allSatisfy({ $0.bytes == 0 }) {
                Text("Nothing yet.").foregroundStyle(.secondary)
            }
            ForEach(slices) { slice in
                SpaceRow(symbol: slice.symbol, title: slice.title, detail: HavenFormat.count(slice.files, "file"), bytes: slice.bytes,
                         fraction: Double(slice.bytes) / Double(largest), tint: tint(slice), chevron: action != nil,
                         action: action.map { act in { act(slice) } })
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardStyle(theme, padding: 16)
    }

    private func tint(_ slice: SpaceReport.Slice) -> Color {
        if let kind = FileKind(rawValue: slice.id) { return theme.tint(for: kind) }
        if let source = SourceClassifier.source(withID: slice.id) { return theme.sourceColor(source.tint) }
        return theme.accent
    }
}

/// One line with a bar: "Downloads ▇▇▇▇▇▇▇▇ 12.4 GB".
struct SpaceRow: View {
    let symbol: String
    let title: String
    let detail: String
    let bytes: Int64
    let fraction: Double
    let tint: Color
    let chevron: Bool
    let action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let content = HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(ByteSize.format(bytes)).monospacedDigit().fontWeight(.medium)
                }
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(tint.gradient)
                                .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
                        }
                    }
                    .frame(height: 6)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
            }
            if chevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hovering && action != nil ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        if let action {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

/// A big file with quick actions: preview, show in Haven, trash.
struct BigFileRow: View {
    let item: FileItem
    let open: () -> Void
    let trash: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(item: item, side: 30, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(tildePath(item.parentPath)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            if hovering {
                Button { AppModel.shared.showInHaven(item) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless)
                    .help("Show in Haven")
                Button(action: trash) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Move to Trash")
                    .accessibilityIdentifier("space.trash")
            }
            Text(ByteSize.format(item.size)).monospacedDigit().fontWeight(.medium)
        }
        .font(.callout)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .contextMenu {
            Button("Preview") { open() }
            Button("Show in Haven") { AppModel.shared.showInHaven(item) }
            Button("Show in Finder") { AppModel.shared.revealInFinder([item]) }
            Divider()
            Button("Move to Trash…", role: .destructive, action: trash)
        }
        .accessibilityIdentifier("space.file.\(item.name)")
    }
}
