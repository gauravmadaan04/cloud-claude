import HavenCore
import SwiftUI

/// Big title at the top of a page.
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: Color? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol {
                Image(systemName: theme.symbol(symbol))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint ?? theme.accent)
                    .frame(width: 40, height: 40)
                    .background((tint ?? theme.accent).opacity(theme.isPlayful ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: theme.headingDesign))
                    .accessibilityIdentifier("page.title")
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

/// Loads a list from the index in the background and shows it in the file browser.
struct LibraryListView: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: Color? = nil
    let source: CollectionSource
    let sourceKey: String
    /// Search results keep their relevance order unless the user picks a sort.
    var usesRelevance = false
    var emptySymbol = "tray"
    var emptyTitle = "Nothing here yet"
    var emptyMessage = "Files will show up here as soon as Haven finds them."
    var accessory: AnyView? = nil

    @State private var items: [FileItem] = []
    @State private var isLoading = true
    @State private var loadedKey = ""

    private var store: LibraryStore { .shared }
    private var prefs: Prefs { .shared }
    private var model: AppModel { .shared }

    private var sort: FileSortOrder? {
        usesRelevance ? model.searchSortOverride : prefs.sortOrder
    }

    private var key: String {
        let textVersion = usesRelevance ? store.text.version : 0
        return "\(sourceKey)|\(store.version)|\(textVersion)|\(sort?.rawValue ?? "relevance")"
    }

    var body: some View {
        FileCollectionView(
            items: items,
            listID: loadedKey,
            isLoading: isLoading || !store.hasLoaded,
            emptySymbol: emptySymbol,
            emptyTitle: emptyTitle,
            emptyMessage: emptyMessage
        ) {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
                if let accessory { accessory }
            }
        }
        .task(id: key) {
            let result = await store.load(source, sort: sort)
            if Task.isCancelled { return }
            items = result
            loadedKey = key
            isLoading = false
        }
    }
}

/// "Haven read this as: [PDFs] [Last week]" with removable chips.
struct QueryChipsBar: View {
    let parsed: ParsedQuery
    var showsSave = true
    @Environment(\.theme) private var theme
    @Bindable private var model = AppModel.shared

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if parsed.chips.isEmpty {
                Text("Type what you're looking for, like “pdfs from last week”.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Haven read this as")
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(parsed.chips) { chip in
                            ChipView(chip: chip) {
                                model.searchText = parsed.text(removing: chip)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if showsSave && !parsed.chips.isEmpty {
                Button {
                    model.saveCurrentSearch()
                } label: {
                    Label("Save Search", systemImage: "bookmark")
                }
                .buttonStyle(.bordered)
                .help("Keep this search in the sidebar; it updates by itself")
                .accessibilityIdentifier("search.save")
            }
        }
        .font(.callout)
    }
}

struct ChipView: View {
    let chip: QueryChip
    var onRemove: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: chip.symbol).font(.system(size: 11, weight: .semibold))
            Text(chip.label).fontWeight(.medium)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove “\(chip.label)” from the search")
                .accessibilityIdentifier("chip.remove.\(chip.kind.rawValue)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(theme.isPlayful ? 0.16 : 0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25)))
        .foregroundStyle(theme.isPlayful ? color : .primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chip.\(chip.kind.rawValue)")
        .accessibilityLabel(chip.label)
    }

    private var color: Color {
        guard theme.isPlayful else { return .primary }
        switch chip.kind {
        case .type: return Color(hex: 0x2B78E4)
        case .date: return Color(hex: 0x7352F0)
        case .size: return Color(hex: 0xC98A00)
        case .source, .downloaded: return Color(hex: 0x189E63)
        case .location: return Color(hex: 0xE5651F)
        case .tag: return Color(hex: 0xE84A75)
        case .text: return Color.primary
        case .sort: return Color(hex: 0x7D8590)
        }
    }
}

struct SearchResultsView: View {
    let parsed: ParsedQuery
    private var model: AppModel { .shared }

    var body: some View {
        let lead = parsed.chips.first { $0.kind != .sort && $0.kind != .text }
        LibraryListView(
            title: parsed.headline,
            subtitle: parsed.headline == parsed.text ? "Search results" : "Results for “\(parsed.text)”",
            symbol: lead?.symbol ?? "magnifyingglass",
            source: .query(parsed.query),
            sourceKey: "q:" + parsed.text,
            usesRelevance: true,
            emptySymbol: "magnifyingglass",
            emptyTitle: "No matches",
            emptyMessage: "Try fewer words, or remove a chip above. Haven searches names, tags, folders and the text inside images and PDFs.",
            accessory: AnyView(QueryChipsBar(parsed: parsed))
        )
    }
}

struct SavedSearchView: View {
    let saved: SavedSearch
    @Bindable private var model = AppModel.shared

    var body: some View {
        let parsed = QueryParser.parse(saved.text, customRoots: model.customRootWords)
        LibraryListView(
            title: saved.name,
            subtitle: "Saved search · updates by itself",
            symbol: saved.symbol,
            source: .query(parsed.query),
            sourceKey: "saved:\(saved.id):\(saved.text)",
            usesRelevance: true,
            emptySymbol: "magnifyingglass",
            emptyTitle: "Nothing matches right now",
            emptyMessage: "This saved search will fill up as matching files arrive.",
            accessory: AnyView(HStack {
                QueryChipsBar(parsed: parsed, showsSave: false).allowsHitTesting(false)
                Button("Edit Search") { model.searchText = saved.text }
                    .buttonStyle(.bordered)
            })
        )
    }
}

/// Picks the page for the current sidebar selection (or search results).
struct DetailView: View {
    @Bindable private var model = AppModel.shared
    @Environment(\.theme) private var theme

    var body: some View {
        if LaunchOptions.current.debug("plaindetail") {
            Group {
                if let parsed = model.parsed {
                    SearchResultsView(parsed: parsed)
                } else {
                    page(model.selection ?? .home)
                        .id(model.selection)
                }
            }
        } else {
            ZStack {
                if let parsed = model.parsed {
                    SearchResultsView(parsed: parsed)
                        .transition(.opacity)
                } else {
                    page(model.selection ?? .home)
                        .id(model.selection)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: model.selection)
            .animation(.easeInOut(duration: 0.16), value: model.parsed == nil)
        }
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .home:
            HomeView()
        case .recents:
            LibraryListView(title: "Recents", subtitle: "Everything that arrived or changed lately", symbol: "clock",
                            source: .recents, sourceKey: "recents")
        case .category(let c):
            LibraryListView(title: c.title, symbol: c.symbolName, tint: theme.tint(c), source: .category(c), sourceKey: "cat:\(c.rawValue)",
                            emptySymbol: c.symbolName, emptyTitle: "No \(c.title.lowercased()) yet")
        case .largeFiles:
            LibraryListView(title: "Large Files", subtitle: "Files over 100 MB, biggest first", symbol: "externaldrive.badge.exclamationmark",
                            source: .largeFiles, sourceKey: "large", emptySymbol: "externaldrive",
                            emptyTitle: "No large files", emptyMessage: "Nothing over 100 MB in your folders.")
        case .screenshots:
            LibraryListView(title: "Screenshots", subtitle: "Every screenshot, newest first. Haven reads the text in them.",
                            symbol: "camera.viewfinder", source: .screenshots, sourceKey: "screenshots", emptySymbol: "camera.viewfinder",
                            emptyTitle: "No screenshots", emptyMessage: "Press ⇧⌘4 to take one.")
        case .saved(let id):
            if let saved = Prefs.shared.savedSearches.first(where: { $0.id == id }) {
                SavedSearchView(saved: saved)
            } else {
                EmptyStateView(symbol: "magnifyingglass", title: "Search not found", message: "This saved search was deleted.")
            }
        case .sources:
            SourcesView()
        case .source(let id):
            let s = SourceClassifier.source(withID: id)
            LibraryListView(title: s.map { "From \($0.name)" } ?? "Downloads", subtitle: s?.host, symbol: "arrow.down.circle",
                            source: .source(id), sourceKey: "src:\(id)")
        case .duplicates:
            DuplicatesView()
        case .cleanup:
            CleanupView()
        case .cleanupCard(let k):
            if k == .duplicates { DuplicatesView() } else { CleanupReviewView(kind: k) }
        case .activity:
            ActivityView()
        case .folder(let path):
            FolderView(path: path)
        }
    }
}
