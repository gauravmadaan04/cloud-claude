import HavenCore
import SwiftUI

struct HomeView: View {
    @Environment(\.theme) private var theme
    private var store: LibraryStore { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        let d = store.derived
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header(d)
                if !store.hasLoaded {
                    firstScan
                } else {
                    TipBanner(id: "home.welcome", symbol: "hand.wave",
                              title: "Your files, at a glance",
                              message: "Click a folder to browse it, try a search like “screenshots from last week” (⌘F), or press ⇧⌘Space in any app for Quick Search.")
                    StorageBar(stats: d.stats)
                    libraryGrid(d)
                    cleanupRow(d)
                    sourcesRow(d)
                    shelves(d)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.canvas)
        .accessibilityIdentifier("home")
        .onAppear { model.setVisible([]) }
    }

    // MARK: Header

    private func header(_ d: LibraryDerived) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 30, weight: .bold, design: theme.headingDesign))
                    .accessibilityIdentifier("home.greeting")
                Text(store.hasLoaded
                     ? "\(HavenFormat.count(d.fileCount, "file")) · \(ByteSize.format(d.totalBytes)) across \(HavenFormat.count(Prefs.shared.enabledRoots.count, "folder"))"
                     : "Getting to know your files…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isScanning && store.hasLoaded {
                ProgressPill(text: "Updating · \(HavenFormat.count(store.scanCount, "file"))")
            } else if store.text.isWorking {
                ProgressPill(text: "Reading text \(store.text.processed)/\(store.text.total)",
                             progress: store.text.total > 0 ? Double(store.text.processed) / Double(store.text.total) : nil)
                    .help("Haven reads the text in screenshots, photos and PDFs on this Mac so you can search it.")
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private var firstScan: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Looking through your folders…")
                .font(.system(.title3, design: theme.headingDesign).weight(.semibold))
            Text("\(HavenFormat.count(store.scanCount, "file")) found so far. Everything stays on this Mac.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: Library

    private func libraryGrid(_ d: LibraryDerived) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Library")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 16)], spacing: 16) {
                ForEach(LibraryCategory.allCases) { c in
                    Button {
                        model.navigate(to: .category(c))
                    } label: {
                        CategoryTile(category: c, stat: d.stats[c] ?? CategoryStat())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("home.tile.\(c.rawValue)")
                }
            }
        }
    }

    // MARK: Clean Up

    private func cleanupRow(_ d: LibraryDerived) -> some View {
        let dupBytes = store.duplicates.reclaimableBytes
        let total = d.cleanupCards.reduce(Int64(0)) { $0 + $1.totalBytes } + dupBytes
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Clean Up", subtitle: total > 0 ? "Up to \(ByteSize.format(total)) to free" : "All tidy") {
                Button("See All") { model.navigate(to: .cleanup) }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("home.cleanup.all")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    DuplicatesMiniCard()
                    ForEach(d.cleanupCards) { card in
                        Button { model.navigate(to: .cleanupCard(card.kind)) } label: {
                            CleanupMiniCard(kind: card.kind, count: card.items.count, bytes: card.totalBytes)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("home.cleanup.\(card.kind.rawValue)")
                    }
                    if d.cleanupCards.isEmpty && dupBytes == 0 && !store.duplicates.isRunning {
                        Label("Nothing to clean up right now", systemImage: "checkmark.seal")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Downloaded From

    @ViewBuilder
    private func sourcesRow(_ d: LibraryDerived) -> some View {
        if !d.sources.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Downloaded From") {
                    Button("See All") { model.navigate(to: .sources) }
                        .buttonStyle(.link)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(d.sources.prefix(14)) { s in
                            Button { model.navigate(to: .source(s.source.id)) } label: {
                                HStack(spacing: 8) {
                                    SourceBadge(source: s.source, size: 24)
                                    Text(s.source.name).fontWeight(.medium)
                                    Text("\(s.count)")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.07), in: Capsule())
                                }
                                .padding(.leading, 6)
                                .padding(.trailing, 12)
                                .padding(.vertical, 6)
                                .background(theme.cardBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(theme.cardStroke))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("home.source.\(s.source.id)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Shelves

    @ViewBuilder
    private func shelves(_ d: LibraryDerived) -> some View {
        let photos = Array((d.byCategory[.images] ?? []).filter { !$0.isScreenshot }.prefix(14))
        let shots = Array(d.screenshots.prefix(14))
        let videos = Array((d.byCategory[.videos] ?? []).prefix(14))
        let docs = Array((d.byCategory[.documents] ?? []).prefix(14))
        let music = Array((d.byCategory[.music] ?? []).prefix(14))
        Shelf(title: "Recent Photos", items: photos, destination: .category(.images))
        Shelf(title: "Screenshots", items: shots, destination: .screenshots)
        Shelf(title: "Videos", items: videos, destination: .category(.videos))
        Shelf(title: "Documents", items: docs, destination: .category(.documents))
        Shelf(title: "Music", items: music, destination: .category(.music))
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A library folder on Home: pastel folder in Playful, grey in Minimal.
struct CategoryTile: View {
    let category: LibraryCategory
    let stat: CategoryStat
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FolderShape()
                .fill(theme.fill(category))
                .overlay(FolderShape().stroke(theme.isPlayful ? theme.tint(category).opacity(0.18) : Color.primary.opacity(0.12), lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: theme.symbol(category.symbolName))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(theme.tint(category))
                Spacer(minLength: 4)
                Text(category.title)
                    .font(.system(.headline, design: theme.headingDesign))
                    .foregroundStyle(.primary)
                Text("\(HavenFormat.count(stat.count, "item")) · \(ByteSize.format(stat.bytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 14)
        }
        .frame(height: 128)
        .shadow(color: .black.opacity(hovering && theme.isPlayful ? 0.10 : 0.03), radius: hovering ? 10 : 4, y: hovering ? 4 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct CleanupMiniCard: View {
    let kind: CleanupKind
    let count: Int
    let bytes: Int64
    var progressText: String? = nil
    @Environment(\.theme) private var theme

    private var color: Color { cleanupColor(kind, theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(theme.isPlayful ? 0.14 : 0.07), in: Circle())
            Text(kind.title)
                .font(.system(.subheadline, design: theme.headingDesign).weight(.semibold))
            if let progressText {
                Text(progressText).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(ByteSize.format(bytes))
                    .font(.system(size: 20, weight: .bold, design: theme.headingDesign))
                Text(HavenFormat.count(count, "item"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, alignment: .leading)
        .cardStyle(theme, padding: 14)
    }
}

func cleanupColor(_ kind: CleanupKind, theme: Theme) -> Color {
    guard theme.isPlayful else { return .primary }
    switch kind {
    case .duplicates: return Color(hex: 0x7352F0)
    case .oldInstallers: return Color(hex: 0xE5651F)
    case .forgottenDownloads: return Color(hex: 0x2B78E4)
    case .oldScreenshots: return Color(hex: 0xE84A75)
    case .bigOldVideos: return Color(hex: 0x189E63)
    case .unusedApps: return Color(hex: 0xC98A00)
    case .unzippedArchives: return Color(hex: 0x7D8590)
    }
}

struct DuplicatesMiniCard: View {
    private var dupes: DuplicateService { LibraryStore.shared.duplicates }
    private var model: AppModel { .shared }

    var body: some View {
        Button { model.navigate(to: .duplicates) } label: {
            switch dupes.phase {
            case .hashing, .comparingPhotos:
                CleanupMiniCard(kind: .duplicates, count: 0, bytes: 0, progressText: "Checking…")
            default:
                if dupes.groups.isEmpty {
                    CleanupMiniCard(kind: .duplicates, count: 0, bytes: 0, progressText: dupes.lastRun == nil ? "Not checked yet" : "None found")
                } else {
                    CleanupMiniCard(kind: .duplicates, count: dupes.groups.reduce(0) { $0 + $1.items.count - 1 }, bytes: dupes.reclaimableBytes)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("home.cleanup.duplicates")
    }
}

/// Coloured bar showing how space splits across the library.
struct StorageBar: View {
    let stats: [LibraryCategory: CategoryStat]
    @Environment(\.theme) private var theme

    var body: some View {
        let total = max(1, stats.values.reduce(Int64(0)) { $0 + $1.bytes })
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(LibraryCategory.allCases) { c in
                        let bytes = stats[c]?.bytes ?? 0
                        if bytes > 0 {
                            Rectangle()
                                .fill(barColor(c))
                                .frame(width: max(3, geo.size.width * CGFloat(Double(bytes) / Double(total))))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack(spacing: 16) {
                ForEach(LibraryCategory.allCases) { c in
                    HStack(spacing: 5) {
                        Circle().fill(barColor(c)).frame(width: 8, height: 8)
                        Text(c.title).foregroundStyle(.secondary)
                        Text(ByteSize.format(stats[c]?.bytes ?? 0)).fontWeight(.medium)
                    }
                    .font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage by kind")
    }

    private func barColor(_ c: LibraryCategory) -> Color {
        if theme.isPlayful { return theme.tint(c) }
        let shades: [LibraryCategory: Double] = [.images: 0.85, .videos: 0.68, .music: 0.52, .documents: 0.38, .archives: 0.26, .apps: 0.16]
        return Color.primary.opacity(shades[c] ?? 0.3)
    }
}

/// A horizontal row of recent files on Home.
struct Shelf: View {
    let title: String
    let items: [FileItem]
    let destination: SidebarItem
    @Environment(\.theme) private var theme
    private var model: AppModel { .shared }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title) {
                    Button("See All") { model.navigate(to: destination) }.buttonStyle(.link)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { item in
                            ShelfItem(item: item, context: items)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct ShelfItem: View {
    let item: FileItem
    let context: [FileItem]
    @Environment(\.theme) private var theme
    @State private var hovering = false
    private var model: AppModel { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(item: item, side: 150, height: 112, cornerRadius: theme.isPlayful ? 12 : 8)
                .overlay(alignment: .bottomLeading) {
                    if let s = item.source { SourceBadge(source: s, size: 18).padding(6) }
                }
                .scaleEffect(hovering ? 1.02 : 1)
            Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text(HavenFormat.friendlyDate(item.activityDate)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 150)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onTapGesture { item.kind == .audio ? MusicPlayer.shared.play(item, queue: context) : model.preview(item, in: context) }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { model.revealInFinder([item]) }
            Button("Show in Enclosing Folder") { model.showInHaven(item) }
            Divider()
            Button("Copy") { model.copyFiles([item]) }
            if item.kind.hasReadableText { Button("Copy Text") { model.copyText([item]) } }
            Divider()
            Button("Move to Trash", role: .destructive) { model.trash([item], reason: "Moved by you") }
        }
        .help(item.name)
        .accessibilityIdentifier("shelf.\(item.name)")
    }
}
