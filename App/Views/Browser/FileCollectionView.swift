import AppKit
import HavenCore
import SwiftUI

/// Grid or list of files with Finder-style selection, keyboard navigation, Quick Look and drag-out.
/// Built for very long lists: hover and selection live in the cards, so pointing at or selecting a file
/// redraws only the cards on screen, never the whole list.
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
    @FocusState private var focused: Bool
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
                .onMoveCommand { dir in
                    if model.isPreviewing {
                        if dir == .left { model.stepPreview(-1) } else if dir == .right { model.stepPreview(1) }
                        return
                    }
                    // Usually the shortcut router gets arrows first; this covers anything it lets through.
                    switch dir {
                    case .left: model.moveSelection(.left, extend: false)
                    case .right: model.moveSelection(.right, extend: false)
                    case .up: model.moveSelection(.up, extend: false)
                    case .down: model.moveSelection(.down, extend: false)
                    @unknown default: break
                    }
                }
                .onKeyPress(.space) {
                    if model.isPreviewing { model.closePreview() } else { model.toggleQuickLook() }
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
                .onExitCommand {
                    if model.isPreviewing { model.closePreview() } else { model.selectedIDs = [] }
                }
                .onChange(of: geo.size.width, initial: true) { _, w in
                    columns = Self.columnCount(width: w, card: prefs.cardSize)
                    model.gridColumns = columns
                }
                .onChange(of: prefs.cardSize) { _, size in
                    columns = Self.columnCount(width: geo.size.width, card: size)
                    model.gridColumns = columns
                }
                .onChange(of: model.revealRequest) { _, _ in
                    guard let target = model.scrollTarget else { return }
                    focused = true
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(target.id, anchor: target.centered ? .center : nil)
                    }
                }
            }
        }
        .background(theme.canvas)
        .onAppear {
            model.fileListsOnScreen += 1
            // Like Finder: the files take the keyboard when a page opens (not while you type a search).
            if !model.isSearching && !model.searchFieldFocused { focused = true }
        }
        .onDisappear { model.fileListsOnScreen -= 1 }
        .onChange(of: listID, initial: true) { _, _ in
            model.setVisible(shown)
            refreshSources()
            model.gridColumns = columns
        }
        .onChange(of: model.sourceFilter) { _, _ in model.setVisible(shown) }
        .onChange(of: model.focusResultsRequest) { _, _ in
            focused = true
            if model.selectedIDs.isEmpty, let first = shown.first {
                model.selectedIDs = [first.id]
                model.selectionAnchor = first.id
                model.selectionLead = first.id
            }
        }
    }

    static func columnCount(width: CGFloat, card: Double) -> Int {
        max(1, Int((width - 44 + 16) / (CGFloat(card) + 16)))
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
                ListSummary(list: list, listID: listID)
                Spacer()
                Menu {
                    let selected = model.selectedItems
                    let targets = selected.isEmpty ? list : selected
                    Section(selected.isEmpty ? "All \(list.count) files" : "\(selected.count) selected") {
                        ForEach(ListExport.Format.allCases) { format in
                            Button(format.title) {
                                if format == .csv { model.exportCSV(targets) } else { model.copyList(format, targets) }
                            }
                        }
                    }
                } label: {
                    Label("Copy List", systemImage: "list.bullet.rectangle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .help("Copy these files' names, paths or a table for a spreadsheet")
                .accessibilityIdentifier("filter.copyList")
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

    // MARK: Grid

    private func grid(_ list: [FileItem], width: CGFloat) -> some View {
        let cols = max(1, columns)
        let spacing: CGFloat = 16
        let side = max(80, floor((width - 44 - spacing * CGFloat(cols - 1)) / CGFloat(cols)) - 0.5)
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: spacing, alignment: .top), count: cols),
                         alignment: .leading, spacing: 20) {
            ForEach(list) { item in
                FileCard(item: item, side: side, interaction: interaction(for: item, in: list))
            }
        }
        .accessibilityIdentifier("file.grid")
    }

    // MARK: List

    private func listView(_ list: [FileItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                // Rows know their position for striping without copying the list.
                ForEach(list.indices.lazy.map { IndexedFile(index: $0, item: list[$0]) }, id: \.item.id) { row in
                    FileRow(item: row.item, isStriped: row.index % 2 == 1, interaction: interaction(for: row.item, in: list))
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
            dragURLs: {
                if model.selectedIDs.contains(item.id) { return model.selectedItems.map(\.url) }
                return [item.url]
            },
            menu: {
                let targets = model.selectedIDs.contains(item.id) ? model.selectedItems : [item]
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
            model.selectionAnchor = item.id
            model.selectionLead = item.id
        } else if mods.contains(.shift), let anchor = model.selectionAnchor,
                  let a = list.firstIndex(where: { $0.id == anchor }), let b = list.firstIndex(where: { $0.id == item.id }) {
            let range = a <= b ? a...b : b...a
            model.selectedIDs = Set(list[range].map(\.id))
            model.selectionLead = item.id
        } else {
            if !model.selectedIDs.contains(item.id) { model.selectedIDs = [item.id] }
            model.selectionAnchor = item.id
            model.selectionLead = item.id
        }
        if model.quickLookURL != nil { model.quickLookURL = item.url }
    }
}

/// A file with its position in the list (for striped rows).
struct IndexedFile {
    let index: Int
    let item: FileItem
}

/// "1,204 items · 3.2 GB · 3 selected (12 MB)": redraws on its own when the selection changes.
private struct ListSummary: View {
    let list: [FileItem]
    let listID: String
    @State private var totalBytes: Int64 = 0
    private var model: AppModel { .shared }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityIdentifier("results.count")
            .onChange(of: listID, initial: true) { _, _ in totalBytes = list.totalSize }
            .onChange(of: list.count) { _, _ in totalBytes = list.totalSize }
    }

    private var text: String {
        var s = HavenFormat.count(list.count, "item")
        if totalBytes > 0 { s += " · \(ByteSize.format(totalBytes))" }
        if !model.selectedIDs.isEmpty {
            let sel = model.selectedItems
            if !sel.isEmpty { s += " · \(sel.count) selected (\(ByteSize.format(sel.totalSize)))" }
        }
        return s
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

/// One card in the grid: big thumbnail, name, size and date. Lifts under the pointer; selection draws
/// a ring and a check like Photos, and highlights the name like Finder.
struct FileCard: View {
    let item: FileItem
    let side: CGFloat
    let interaction: ItemInteraction

    @Environment(\.theme) private var theme
    @State private var isHovered = false
    private var isSelected: Bool { AppModel.shared.selectedIDs.contains(item.id) }

    var body: some View {
        let isSelected = self.isSelected
        let thumbW = side - 12
        let radius: CGFloat = theme.isPlayful ? 12 : 8
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(item: item, side: thumbW, height: thumbW * 0.78, cornerRadius: radius)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                    .overlay(alignment: .bottomLeading) {
                        if let s = item.source {
                            SourceBadge(source: s, size: 20)
                                .padding(7)
                                .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        }
                    }
                    .shadow(color: .black.opacity(isHovered ? 0.2 : (theme.isPlayful ? 0.07 : 0.04)),
                            radius: isHovered ? 11 : 3, y: isHovered ? 6 : 1)
                    .scaleEffect(isHovered && !isSelected ? 1.02 : 1)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                                .strokeBorder(theme.accent, lineWidth: 2.5)
                                .padding(-4.5)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(theme.onAccent, theme.accent)
                                .overlay(Circle().strokeBorder(theme.onAccent, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                .padding(7)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: isHovered)
                    .animation(.snappy(duration: 0.2), value: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isSelected ? theme.onAccent : Color.primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(.horizontal, -5)
                    Text(fileSubtitle(item))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 3)
            }
            .padding(6)
            interaction.reportingHover { isHovered = $0 }
            if isHovered, item.kind == .image || item.kind == .pdf {
                Button {
                    AppModel.shared.copyText([item])
                } label: {
                    Label("Copy Text", systemImage: "text.quote")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .glassBackground(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy the text in this \(item.kind == .pdf ? "PDF" : "image")")
                .padding(13)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
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

/// One row in list view; selection is a solid accent bar like Finder.
struct FileRow: View {
    let item: FileItem
    let isStriped: Bool
    let interaction: ItemInteraction

    @Environment(\.theme) private var theme
    private var isSelected: Bool { AppModel.shared.selectedIDs.contains(item.id) }

    private var secondary: AnyShapeStyle {
        isSelected ? AnyShapeStyle(theme.onAccent.opacity(0.78)) : AnyShapeStyle(.secondary)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                ThumbnailView(item: item, side: 26, cornerRadius: 5)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? AnyShapeStyle(theme.onAccent) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let s = item.source {
                    SourceBadge(source: s, size: 16)
                }
                Text(item.kind.displayName)
                    .foregroundStyle(secondary)
                    .frame(width: 100, alignment: .leading)
                Text(item.kind == .folder ? folderSizeText(item) : ByteSize.format(item.size))
                    .foregroundStyle(secondary)
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
                Text(HavenFormat.friendlyDate(item.activityDate))
                    .foregroundStyle(secondary)
                    .frame(width: 150, alignment: .leading)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(theme.isPlayful ? 0.92 : 0.85) : (isStriped ? Color.primary.opacity(0.03) : .clear))
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

    /// nil while search results are in best-match order: no column is marked.
    private var current: FileSortOrder? { model.activeSort }

    @ViewBuilder
    private func header(_ title: String, asc: FileSortOrder, desc: FileSortOrder) -> some View {
        if sortable {
            Button {
                let next: FileSortOrder = current == desc ? asc : desc
                model.pickSort(next)
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
