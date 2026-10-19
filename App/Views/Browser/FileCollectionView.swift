import AppKit
import HavenCore
import SwiftUI

/// Grid or list of files with Finder-style selection, keyboard navigation, Quick Look and drag-out.
struct FileCollectionView<Header: View>: View {
    let items: [FileItem]
    /// Changes whenever `items` changes (lets the view refresh selection and Quick Look lists cheaply).
    let listID: String
    var isLoading = false
    var emptySymbol = "tray"
    var emptyTitle = "Nothing here yet"
    var emptyMessage = "Files will show up here as soon as Haven finds them."
    var showsFromFilter = true
    var sortable = true
    @ViewBuilder var header: () -> Header

    @Bindable private var model = AppModel.shared
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focused: Bool
    @State private var anchorID: String?
    @State private var hoveredID: String?
    @State private var columns = 4
    @State private var presentSources: [SourceCount] = []

    private var prefs: Prefs { .shared }

    private var shown: [FileItem] {
        guard let f = model.sourceFilter else { return items }
        return items.filter { $0.source?.id == f }
    }

    var body: some View {
        let list = shown
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header()
                        filterBar(list)
                        if list.isEmpty {
                            if isLoading {
                                ProgressView().frame(maxWidth: .infinity).padding(60)
                            } else {
                                EmptyStateView(symbol: emptySymbol, title: emptyTitle, message: emptyMessage)
                                    .frame(minHeight: 320)
                            }
                        } else if prefs.viewMode == .grid {
                            grid(list, width: geo.size.width)
                        } else {
                            listView(list)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedIDs = []
                                focused = true
                            }
                    )
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onMoveCommand { dir in move(dir, in: list, proxy: proxy) }
                .onKeyPress(.space) {
                    model.toggleQuickLook()
                    return .handled
                }
                .onKeyPress(.return) {
                    let sel = model.selectedItems
                    if sel.count == 1, let one = sel.first { model.activate(one) } else { model.open(sel) }
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "=+-")) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    if press.characters == "-" { model.smaller() } else { model.bigger() }
                    return .handled
                }
                .onCopyCommand {
                    model.selectedItems.map { NSItemProvider(object: $0.url as NSURL) }
                }
                .onExitCommand { model.selectedIDs = [] }
                .onChange(of: geo.size.width, initial: true) { _, w in
                    columns = Self.columnCount(width: w, card: prefs.cardSize)
                }
                .onChange(of: prefs.cardSize) { _, size in
                    columns = Self.columnCount(width: geo.size.width, card: size)
                }
            }
        }
        .background(theme.canvas)
        .onChange(of: listID, initial: true) { _, _ in
            model.setVisible(shown)
            refreshSources()
            if let reveal = model.selectedIDs.first, model.pendingReveal == nil {
                anchorID = reveal
            }
        }
        .onChange(of: model.sourceFilter) { _, _ in model.setVisible(shown) }
        .onAppear { focused = true }
    }

    static func columnCount(width: CGFloat, card: Double) -> Int {
        max(1, Int((width - 44 + 14) / (CGFloat(card) + 14)))
    }

    // MARK: Filter bar

    private func refreshSources() {
        guard showsFromFilter else { presentSources = []; return }
        var counts: [String: SourceCount] = [:]
        for item in items.prefix(20_000) {
            if let s = item.source { counts[s.id, default: SourceCount(source: s, count: 0)].count += 1 }
        }
        presentSources = counts.values.sorted { $0.count > $1.count }
        if let f = model.sourceFilter, counts[f] == nil { model.sourceFilter = nil }
    }

    @ViewBuilder
    private func filterBar(_ list: [FileItem]) -> some View {
        if !list.isEmpty || model.sourceFilter != nil {
            HStack(spacing: 10) {
                Text(summary(list))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("results.count")
                Spacer()
                if !presentSources.isEmpty {
                    Menu {
                        Button("Anywhere") { model.sourceFilter = nil }
                        Divider()
                        ForEach(presentSources) { pair in
                            Button("\(pair.source.name) (\(pair.count))") { model.sourceFilter = pair.source.id }
                        }
                    } label: {
                        Label(model.sourceFilter.flatMap { id in presentSources.first { $0.id == id }?.source.name }.map { "From \($0)" } ?? "From: Anywhere",
                              systemImage: "arrow.down.circle")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .accessibilityIdentifier("filter.from")
                }
            }
        }
    }

    private func summary(_ list: [FileItem]) -> String {
        let files = list.count
        let bytes = list.totalSize
        var s = HavenFormat.count(files, "item")
        if bytes > 0 { s += " · \(ByteSize.format(bytes))" }
        if !model.selectedIDs.isEmpty {
            let sel = list.filter { model.selectedIDs.contains($0.id) }
            if !sel.isEmpty { s += " · \(sel.count) selected (\(ByteSize.format(sel.totalSize)))" }
        }
        return s
    }

    // MARK: Grid

    private func grid(_ list: [FileItem], width: CGFloat) -> some View {
        let cols = max(1, columns)
        let spacing: CGFloat = 14
        let side = max(80, floor((width - 44 - spacing * CGFloat(cols - 1)) / CGFloat(cols)) - 0.5)
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: spacing, alignment: .top), count: cols),
                         alignment: .leading, spacing: 16) {
            ForEach(list) { item in
                FileCard(
                    item: item,
                    side: side,
                    isSelected: model.selectedIDs.contains(item.id),
                    isHovered: hoveredID == item.id,
                    interaction: interaction(for: item, in: list)
                )
                .id(item.id)
            }
        }
        .accessibilityIdentifier("file.grid")
    }

    // MARK: List

    private func listView(_ list: [FileItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                    FileRow(
                        item: item,
                        isSelected: model.selectedIDs.contains(item.id),
                        isStriped: index % 2 == 1,
                        interaction: interaction(for: item, in: list)
                    )
                    .id(item.id)
                }
            } header: {
                ListHeader(sortable: sortable)
            }
        }
        .accessibilityIdentifier("file.list")
    }

    // MARK: Interaction

    private func interaction(for item: FileItem, in list: [FileItem]) -> ItemInteraction {
        ItemInteraction(
            onMouseDown: { mods, clicks in mouseDown(item, mods: mods, clicks: clicks, list: list) },
            onMouseUp: { mods, dragged in
                if !dragged, !mods.contains(.command), !mods.contains(.shift), model.selectedIDs.count > 1,
                   model.selectedIDs.contains(item.id) {
                    model.selectedIDs = [item.id]
                }
            },
            onHover: { inside in
                if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
            },
            dragURLs: {
                if model.selectedIDs.contains(item.id) {
                    return list.filter { model.selectedIDs.contains($0.id) }.map(\.url)
                }
                return [item.url]
            },
            menu: {
                let targets = model.selectedIDs.contains(item.id) ? list.filter { model.selectedIDs.contains($0.id) } : [item]
                return ItemMenu.make(for: targets)
            },
            accessibilityLabel: item.name
        )
    }

    private func mouseDown(_ item: FileItem, mods: NSEvent.ModifierFlags, clicks: Int, list: [FileItem]) {
        focused = true
        if clicks >= 2 {
            model.selectedIDs = [item.id]
            model.activate(item)
            return
        }
        if mods.contains(.command) {
            if model.selectedIDs.contains(item.id) { model.selectedIDs.remove(item.id) } else { model.selectedIDs.insert(item.id) }
            anchorID = item.id
        } else if mods.contains(.shift), let anchor = anchorID,
                  let a = list.firstIndex(where: { $0.id == anchor }), let b = list.firstIndex(where: { $0.id == item.id }) {
            let range = a <= b ? a...b : b...a
            model.selectedIDs = Set(list[range].map(\.id))
        } else {
            if !model.selectedIDs.contains(item.id) { model.selectedIDs = [item.id] }
            anchorID = item.id
        }
        if model.quickLookURL != nil { model.quickLookURL = item.url }
    }

    private func move(_ dir: MoveCommandDirection, in list: [FileItem], proxy: ScrollViewProxy) {
        guard !list.isEmpty else { return }
        let isGrid = prefs.viewMode == .grid
        let step: Int
        switch dir {
        case .left: step = isGrid ? -1 : 0
        case .right: step = isGrid ? 1 : 0
        case .up: step = isGrid ? -columns : -1
        case .down: step = isGrid ? columns : 1
        @unknown default: step = 0
        }
        guard step != 0 else { return }
        let current = anchorID.flatMap { id in list.firstIndex { $0.id == id } }
            ?? list.firstIndex { model.selectedIDs.contains($0.id) }
        let next = current.map { max(0, min(list.count - 1, $0 + step)) } ?? 0
        let target = list[next]
        model.selectedIDs = [target.id]
        anchorID = target.id
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(target.id) }
        if model.quickLookURL != nil { model.quickLookURL = target.url }
    }
}

extension FileCollectionView where Header == EmptyView {
    init(items: [FileItem], listID: String, isLoading: Bool = false, emptySymbol: String = "tray",
         emptyTitle: String = "Nothing here yet", emptyMessage: String = "Files will show up here as soon as Haven finds them.",
         showsFromFilter: Bool = true, sortable: Bool = true) {
        self.items = items
        self.listID = listID
        self.isLoading = isLoading
        self.emptySymbol = emptySymbol
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.showsFromFilter = showsFromFilter
        self.sortable = sortable
        self.header = { EmptyView() }
    }
}

struct SourceCount: Identifiable {
    let source: DownloadSource
    var count: Int
    var id: String { source.id }
}

/// One card in the grid: big thumbnail, name, size and date.
struct FileCard: View {
    let item: FileItem
    let side: CGFloat
    let isSelected: Bool
    let isHovered: Bool
    let interaction: ItemInteraction

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 7) {
                ThumbnailView(item: item, side: side - 12, height: (side - 12) * 0.78, cornerRadius: theme.isPlayful ? 12 : 8)
                    .overlay(alignment: .bottomLeading) {
                        if let s = item.source {
                            SourceBadge(source: s, size: 20)
                                .padding(6)
                                .shadow(color: .black.opacity(0.2), radius: 2)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(fileSubtitle(item))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: theme.isPlayful ? 16 : 10, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(0.16) : (isHovered ? Color.primary.opacity(0.045) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.isPlayful ? 16 : 10, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent.opacity(0.7) : .clear, lineWidth: 1.5)
            )
            interaction
            if isHovered, item.kind == .image || item.kind == .pdf {
                Button {
                    AppModel.shared.copyText([item])
                } label: {
                    Label("Copy Text", systemImage: "text.quote")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Copy the text in this \(item.kind == .pdf ? "PDF" : "image")")
                .padding(12)
                .accessibilityIdentifier("card.copyText")
            }
        }
        .frame(width: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityIdentifier("file.\(item.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

/// One row in list view.
struct FileRow: View {
    let item: FileItem
    let isSelected: Bool
    let isStriped: Bool
    let interaction: ItemInteraction

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                ThumbnailView(item: item, side: 26, cornerRadius: 5)
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let s = item.source {
                    SourceBadge(source: s, size: 16)
                }
                Text(item.kind.displayName)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Text(item.kind == .folder ? "—" : ByteSize.format(item.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
                Text(HavenFormat.friendlyDate(item.activityDate))
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(0.18) : (isStriped ? Color.primary.opacity(0.025) : .clear))
            )
            interaction
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityIdentifier("file.\(item.name)")
    }
}

struct ListHeader: View {
    let sortable: Bool
    private var prefs: Prefs { .shared }
    @Bindable private var model = AppModel.shared

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 26, height: 1)
            header("Name", asc: .nameAZ, desc: .nameZA).frame(maxWidth: .infinity, alignment: .leading)
            header("Kind", asc: .kind, desc: .kind).frame(width: 100, alignment: .leading)
            header("Size", asc: .sizeSmallest, desc: .sizeLargest).frame(width: 80, alignment: .trailing)
            header("Date", asc: .dateOldest, desc: .dateNewest).frame(width: 150, alignment: .leading)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var current: FileSortOrder { model.isSearching ? (model.searchSortOverride ?? .dateNewest) : prefs.sortOrder }

    @ViewBuilder
    private func header(_ title: String, asc: FileSortOrder, desc: FileSortOrder) -> some View {
        if sortable {
            Button {
                let next: FileSortOrder = current == desc ? asc : desc
                if model.isSearching { model.searchSortOverride = next } else { prefs.sortOrder = next }
            } label: {
                HStack(spacing: 3) {
                    Text(title)
                    if current == asc || current == desc {
                        Image(systemName: current == asc && asc != desc ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Text(title)
        }
    }
}
