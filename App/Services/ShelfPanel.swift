import AppKit
import HavenCore
import SwiftUI

/// A small window that floats above every app: drop files on it from anywhere, then drag them all out together.
@MainActor
final class ShelfController: NSObject, NSWindowDelegate {
    static let shared = ShelfController()
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? close() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        ShelfStore.shared.prune()
        if !panel.isVisible { position(panel) }
        panel.orderFrontRegardless()
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 400),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Shelf"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setAccessibilityIdentifier("shelf.panel")
        let host = NSHostingView(rootView: ShelfView().environment(\.theme, Theme(look: Prefs.shared.look)))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrameAutosaveName("HavenShelf")
        return panel
    }

    /// Near the right edge of the screen the pointer is on, unless it was put somewhere already.
    private func position(_ panel: NSPanel) {
        guard panel.frameAutosaveName.isEmpty || UserDefaults.standard.string(forKey: "NSWindow Frame HavenShelf") == nil else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 24, y: frame.midY - size.height / 2 + 60))
    }
}

struct ShelfView: View {
    @Environment(\.theme) private var theme
    @State private var items: [FileItem] = []
    @State private var targeted = false
    private var shelf: ShelfStore { .shared }

    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 90), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if shelf.urls.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(theme.accent)
                    Text("Drop files here")
                        .font(.headline)
                    Text("Gather files from Haven, Finder or anywhere, then drag them all into Mail, Slack or a folder at once.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("shelf.empty")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            ShelfTile(item: item)
                        }
                    }
                    .padding(12)
                }
                Divider()
                footer
            }
        }
        .frame(width: 290, height: 400)
        .background(VisualEffectBackground(material: .popover))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: targeted ? 3 : 0)
                .padding(2)
                .animation(.snappy(duration: 0.15), value: targeted)
        )
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls) > 0
        } isTargeted: { targeted = $0 }
        .task(id: shelf.urls) {
            let urls = shelf.urls
            let made = await Task.detached(priority: .userInitiated) {
                urls.compactMap { FileScanner.item(at: $0, rootID: "shelf") }
            }.value
            if !Task.isCancelled { items = made }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shelf")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full").foregroundStyle(theme.accent)
            Text("Shelf").font(.headline)
            if !shelf.urls.isEmpty {
                Text(HavenFormat.count(shelf.urls.count, "file"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shelf.count")
            }
            Spacer()
            Menu {
                Button("Copy All") { copyAll() }
                Button("Show All in Finder") { NSWorkspace.shared.activateFileViewerSelecting(shelf.urls) }
                Button("Add All to a New Collection") {
                    AppModel.shared.bringMainWindowForward()
                    AppModel.shared.newCollection(with: items)
                }
                Divider()
                Button("Clear Shelf", role: .destructive) { shelf.clear() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(shelf.urls.isEmpty)
            Button { ShelfController.shared.close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Close the shelf (⌥⌘S)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            DragAllHandle(urls: shelf.urls) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                    Text("Drag all \(shelf.urls.count)")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(theme.onAccent)
                .background(theme.accent, in: Capsule())
            }
            .help("Drag all the files on the shelf into another app or folder")
            .accessibilityIdentifier("shelf.dragAll")
            Spacer()
            Text(ByteSize.format(items.totalSize))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear") { shelf.clear() }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("shelf.clear")
        }
        .padding(12)
    }

    private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(shelf.urls.map { $0 as NSURL })
    }
}

struct ShelfTile: View {
    let item: FileItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailView(item: item, side: 64, cornerRadius: 8)
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        Button { ShelfStore.shared.remove(item.url) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                        .help("Take off the shelf")
                    }
                }
            Text(item.name)
                .font(.system(size: 10.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 76)
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Show in Haven") { AppModel.shared.showInHaven(item) }
            Divider()
            Button("Take Off the Shelf") { ShelfStore.shared.remove(item.url) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityIdentifier("shelf.item.\(item.name)")
    }
}

/// Wraps a label so that dragging it drags every file on the shelf.
struct DragAllHandle<Label: View>: View {
    let urls: [URL]
    @ViewBuilder var label: () -> Label

    var body: some View {
        label()
            .overlay(DragAllSource(urls: urls))
    }
}

private struct DragAllSource: NSViewRepresentable {
    let urls: [URL]

    final class SourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        private var down: NSEvent?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { down = event }

        override func mouseDragged(with event: NSEvent) {
            guard let down, !urls.isEmpty else { return }
            self.down = nil
            let origin = convert(down.locationInWindow, from: nil)
            let session = beginDraggingSession(with: FileDrag.items(for: urls, at: origin), event: down, source: self)
            session.draggingFormation = .pile
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy, .generic, .link]
        }
    }

    func makeNSView(context: Context) -> SourceView {
        let v = SourceView()
        v.urls = urls
        return v
    }

    func updateNSView(_ v: SourceView, context: Context) { v.urls = urls }
}
