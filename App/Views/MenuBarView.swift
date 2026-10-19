import HavenCore
import SwiftUI

/// The menu bar window: the ten newest downloads, ready to drag into any app.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    private var store: LibraryStore { .shared }
    private var prefs: Prefs { .shared }

    var body: some View {
        let theme = Theme(look: prefs.look)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Latest Downloads").font(.headline)
                Spacer()
                Text("Drag into any app").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            let latest = Array(store.derived.latestDownloads.prefix(10))
            if latest.isEmpty {
                Text(store.hasLoaded ? "Nothing in Downloads yet." : "Haven is still looking…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                VStack(spacing: 2) {
                    ForEach(latest) { item in
                        MenuBarRow(item: item)
                    }
                }
                .padding(.horizontal, 6)
            }
            Divider().padding(.top, 8)
            VStack(spacing: 0) {
                menuButton("Quick Search", symbol: "magnifyingglass", keys: prefs.hotKey.display) {
                    QuickSearchController.shared.show()
                }
                menuButton("Open Haven", symbol: "house", keys: nil) {
                    AppModel.shared.openWindowAction = openWindow
                    AppModel.shared.bringMainWindowForward()
                }
                menuButton("Settings…", symbol: "gearshape", keys: "⌘,") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Divider().padding(.vertical, 4)
                menuButton("Quit Haven", symbol: "power", keys: "⌘Q") { NSApp.terminate(nil) }
            }
            .padding(6)
        }
        .frame(width: 340)
        .environment(\.theme, theme)
        .onAppear {
            AppModel.shared.openWindowAction = openWindow
        }
    }

    private func menuButton(_ title: String, symbol: String, keys: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                if let keys { Text(keys).foregroundStyle(.secondary).font(.caption) }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration)
    }

    struct MenuRowBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering || configuration.isPressed ? Color.primary.opacity(0.09) : .clear))
                .onHover { hovering = $0 }
        }
    }
}

struct MenuBarRow: View {
    let item: FileItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(item: item, side: 36, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    if let s = item.source { Text(s.name) ; Text("·") }
                    Text(HavenFormat.ago(item.arrivalDate))
                    Text("·")
                    Text(ByteSize.format(item.size))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .help("Click to open, or drag into another app")
    }
}
