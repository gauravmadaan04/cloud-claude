import HavenCore
import SwiftUI

struct HomeView: View {
    @Environment(\.theme) private var theme
    private var store: LibraryStore { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        let d = store.derived
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(theme.isPlayful ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary))
                Text(greeting)
                    .font(.system(size: 32, weight: .bold, design: theme.headingDesign))
                    .accessibilityIdentifier("home.greeting")
                Text(store.hasLoaded
                     ? "\(HavenFormat.count(d.fileCount, "file")) across \(HavenFormat.count(Prefs.shared.enabledRoots.count, "folder")), all on this Mac"
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 176, maximum: 280), spacing: 18)], spacing: 18) {
                ForEach(LibraryCategory.allCases) { c in
                    Button {
                        model.navigate(to: .category(c))
                    } label: {
                        CategoryTile(category: c, stat: d.stats[c] ?? CategoryStat(), previews: previews(c, d))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("home.tile.\(c.rawValue)")
                }
            }
        }
    }

    /// The newest few files of a kind, peeking out of its folder. Photos beat screenshots.
    private func previews(_ c: LibraryCategory, _ d: LibraryDerived) -> [FileItem] {
        let all = (d.byCategory[c] ?? []).lazy.filter { $0.kind != .folder && !$0.isCloudOnly }
        let photos = Array(all.filter { !$0.isScreenshot }.prefix(3))
        if photos.count >= 3 { return photos }
        return photos + Array(all.filter(\.isScreenshot).prefix(3 - photos.count))
    }

    // MARK: Clean Up

    private func cleanupRow(_ d: LibraryDerived) -> some View {
        let dupBytes = store.duplicates.reclaimableBytes
        let total = d.cleanupCards.reduce(Int64(0)) { $0 + $1.totalBytes } + dupBytes
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Clean Up", subtitle: total > 0 ? "Up to \(ByteSize.format(total)) to free" : "All tidy") {
                SeeAllButton { model.navigate(to: .cleanup) }
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
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, -4)
        }
    }

    // MARK: Downloaded From

    @ViewBuilder
    private func sourcesRow(_ d: LibraryDerived) -> some View {
        if !d.sources.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Downloaded From") {
                    SeeAllButton { model.navigate(to: .sources) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(d.sources.prefix(14)) { s in
                            Button { model.navigate(to: .source(s.source.id)) } label: {
                                SourceChip(summary: s)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("home.source.\(s.source.id)")
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, -4)
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

/// A library folder on Home: the newest files peek out of a pocket and fan out under the pointer.
/// Pastel in Playful, greys in Minimal.
struct CategoryTile: View {
    let category: LibraryCategory
    let stat: CategoryStat
    var previews: [FileItem] = []
    @Environment(\.theme) private var theme
    @State private var hovering = false

    private let height: CGFloat = 156
    private let pocketHeight: CGFloat = 98

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                FolderShape()
                    .fill(backColor)
                    .overlay(FolderShape().stroke(strokeColor, lineWidth: 1))
                peeks(width: geo.size.width)
                pocket
                    .frame(height: pocketHeight)
            }
        }
        .frame(height: height)
        .shadow(color: .black.opacity(hovering ? 0.14 : (theme.isPlayful ? 0.05 : 0.03)), radius: hovering ? 14 : 4, y: hovering ? 7 : 1)
        .offset(y: hovering ? -2 : 0)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: hovering)
    }

    private var backColor: Color {
        theme.isPlayful ? theme.tint(category).opacity(0.3) : Color.primary.opacity(0.1)
    }

    private var strokeColor: Color {
        theme.isPlayful ? theme.tint(category).opacity(0.2) : Color.primary.opacity(0.1)
    }

    /// Up to three thumbnails like prints tucked into the folder: newest in the middle.
    private func peeks(width w: CGFloat) -> some View {
        let tw = min(92, w * 0.38)
        let th = tw * 0.76
        let shown = Array(previews.prefix(3))
        let slots: [CGFloat] = shown.count == 1 ? [0] : shown.count == 2 ? [0.55, -0.55] : [0, -1, 1]
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                let slot = slots[i]
                ThumbnailView(item: item, side: tw, height: th, cornerRadius: 7)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.cardBackground, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                    .rotationEffect(.degrees(Double(slot) * (hovering ? 11 : 6)), anchor: .bottom)
                    .offset(x: slot * w * (hovering ? 0.2 : 0.15), y: (hovering ? -12 : 0) + abs(slot) * 4)
                    .zIndex(slot == 0 ? 2 : 1)
            }
        }
        .frame(width: w, height: height, alignment: .top)
        .offset(y: 22)
        .accessibilityHidden(true)
    }

    private var pocket: some View {
        let shape = RoundedRectangle(cornerRadius: theme.isPlayful ? 16 : 11, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: theme.symbol(category.symbolName))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.isPlayful ? Color.white : Color.primary.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(theme.isPlayful ? AnyShapeStyle(theme.tint(category).gradient) : AnyShapeStyle(Color.primary.opacity(0.08)),
                                in: Circle())
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.isPlayful ? theme.tint(category) : Color.secondary)
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering ? 0 : -4, y: hovering ? 0 : 4)
            }
            Spacer(minLength: 0)
            Text(category.title)
                .font(.system(size: 15.5, weight: .semibold, design: theme.headingDesign))
                .foregroundStyle(.primary)
            Text("\(HavenFormat.count(stat.count, "item")) · \(ByteSize.format(stat.bytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(theme.cardBackground)
                shape.fill(LinearGradient(colors: [theme.fill(category), theme.fill(category).opacity(theme.isPlayful ? 0.8 : 1)],
                                          startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay(shape.strokeBorder(strokeColor))
        .shadow(color: .black.opacity(0.08), radius: 3, y: -1)
    }
}

/// A "Downloaded From" chip on Home.
struct SourceChip: View {
    let summary: SourceSummary
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            SourceBadge(source: summary.source, size: 26)
            Text(summary.source.name).fontWeight(.medium)
            Text("\(summary.count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(theme.cardBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(hovering ? theme.accent.opacity(0.35) : theme.cardStroke))
        .shadow(color: .black.opacity(hovering ? 0.1 : 0.03), radius: hovering ? 6 : 2, y: hovering ? 3 : 1)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
    }
}

struct CleanupMiniCard: View {
    let kind: CleanupKind
    let count: Int
    let bytes: Int64
    var progressText: String? = nil
    @Environment(\.theme) private var theme
    @State private var hovering = false

    private var color: Color { cleanupColor(kind, theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(theme.isPlayful ? 0.14 : 0.07), in: Circle())
                Spacer()
                if progressText == nil && count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            Spacer(minLength: 10)
            Text(kind.title)
                .font(.system(size: 13, weight: .semibold, design: theme.headingDesign))
                .lineLimit(1)
            if let progressText {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            } else {
                Text(ByteSize.format(bytes))
                    .font(.system(size: 22, weight: .bold, design: theme.headingDesign))
                    .monospacedDigit()
                    .padding(.top, 1)
                Text(HavenFormat.count(count, "item"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 152, height: 112, alignment: .topLeading)
        .cardStyle(theme, padding: 14)
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
            .strokeBorder(hovering ? color.opacity(0.35) : .clear, lineWidth: 1))
        .hoverLift(hovering)
        .onHover { hovering = $0 }
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

/// How space splits across the library: a segmented bar, largest first, with a legend.
struct StorageBar: View {
    let stats: [LibraryCategory: CategoryStat]
    @Environment(\.theme) private var theme
    @State private var hovered: LibraryCategory?

    var body: some View {
        let parts = LibraryCategory.allCases
            .map { StoragePart(category: $0, bytes: stats[$0]?.bytes ?? 0) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
        let total = max(1, parts.reduce(Int64(0)) { $0 + $1.bytes })
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ByteSize.format(total))
                    .font(.system(size: 24, weight: .bold, design: theme.headingDesign))
                    .monospacedDigit()
                Text("in your library")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let top = parts.first {
                    Text("Most space: \(top.category.title)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                let gap: CGFloat = 3
                let room = geo.size.width - gap * CGFloat(max(0, parts.count - 1))
                HStack(spacing: gap) {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barColor(part.category).gradient)
                            .frame(width: max(4, room * CGFloat(Double(part.bytes) / Double(total))))
                            .opacity(hovered == nil || hovered == part.category ? 1 : 0.3)
                            .onHover { inside in hovered = inside ? part.category : (hovered == part.category ? nil : hovered) }
                            .help("\(part.category.title): \(ByteSize.format(part.bytes))")
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipShape(Capsule())
            }
            .frame(height: 12)
            FlowLayout(spacing: 8, centered: false) {
                ForEach(parts) { part in
                    HStack(spacing: 6) {
                        Circle().fill(barColor(part.category)).frame(width: 8, height: 8)
                        Text(part.category.title)
                        Text(ByteSize.format(part.bytes)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(hovered == part.category ? 0.09 : 0.045), in: Capsule())
                    .onHover { inside in hovered = inside ? part.category : (hovered == part.category ? nil : hovered) }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .cardStyle(theme, padding: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage by kind")
    }

    private func barColor(_ c: LibraryCategory) -> Color {
        if theme.isPlayful { return theme.tint(c) }
        let shades: [LibraryCategory: Double] = [.images: 0.85, .videos: 0.68, .music: 0.52, .documents: 0.38, .archives: 0.26, .apps: 0.16]
        return Color.primary.opacity(shades[c] ?? 0.3)
    }
}

struct StoragePart: Identifiable {
    let category: LibraryCategory
    let bytes: Int64
    var id: LibraryCategory { category }
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
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: title) {
                    SeeAllButton { model.navigate(to: destination) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(items) { item in
                            ShelfItem(item: item, context: items)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, -4)
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
        let radius: CGFloat = theme.isPlayful ? 12 : 8
        VStack(alignment: .leading, spacing: 7) {
            ThumbnailView(item: item, side: 172, height: 128, cornerRadius: radius)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                .overlay(alignment: .bottomLeading) {
                    if let s = item.source { SourceBadge(source: s, size: 20).padding(7).shadow(color: .black.opacity(0.2), radius: 2, y: 1) }
                }
                .hoverLift(hovering)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(fileSubtitle(item)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 172)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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
