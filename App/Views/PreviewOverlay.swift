import AVKit
import HavenCore
import Quartz
import SwiftUI
import VisionKit

/// Large in-window preview (double-click). ←/→ step through the list, Esc closes.
struct PreviewOverlay: View {
    @Bindable private var model = AppModel.shared
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager

    private var list: [FileItem] { model.previewContext.isEmpty ? model.visibleItems : model.previewContext }

    var body: some View {
        if let item = model.previewItem {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                VStack(spacing: 0) {
                    toolbar(item)
                    Divider()
                    content(item)
                        .id(item.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .underPageBackgroundColor))
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
                .padding(36)
            }
            .background {
                // Invisible buttons so Esc, Space and the arrows work wherever keyboard focus is.
                ZStack {
                    Button("Close Preview") { close() }.keyboardShortcut(.cancelAction)
                    Button("Previous") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                    Button("Next") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                }
                .buttonStyle(.plain)
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .accessibilityHidden(true)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .accessibilityIdentifier("preview.overlay")
        }
    }

    private func toolbar(_ item: FileItem) -> some View {
        HStack(spacing: 12) {
            ThumbnailView(item: item, side: 30, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Text("\(item.kind.displayName) · \(fileSubtitle(item))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let index = list.firstIndex(where: { $0.id == item.id }), list.count > 1 {
                Text("\(index + 1) of \(list.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.help("Previous (←)")
                Button { step(1) } label: { Image(systemName: "chevron.right") }.help("Next (→)")
            }
            Divider().frame(height: 18)
            if item.kind.hasReadableText {
                Button { model.copyText([item]) } label: { Label("Copy Text", systemImage: "text.quote") }
                    .help("Copy the text Haven read from this file (⇧⌘C)")
            }
            Button { NSWorkspace.shared.open(item.url) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
            Button { model.revealInFinder([item]) } label: { Label("Show in Finder", systemImage: "folder") }
            ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) {
                let next = neighbour(of: item)
                model.trash([item], reason: "Moved by you", undoManager: undoManager)
                model.previewItem = next
            } label: { Label("Move to Trash", systemImage: "trash") }
            Button { close() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close (Esc)")
                .accessibilityIdentifier("preview.close")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func content(_ item: FileItem) -> some View {
        switch item.kind {
        case .image where item.ext != "psd" && item.ext != "svg":
            LiveTextImage(url: item.url)
                .padding(20)
        case .video:
            VideoPreview(url: item.url)
        case .audio:
            AudioPreview(item: item, queue: list.filter { $0.kind == .audio })
        default:
            QuickLookPreview(url: item.url)
        }
    }

    private func neighbour(of item: FileItem) -> FileItem? {
        guard let i = list.firstIndex(where: { $0.id == item.id }) else { return nil }
        if i + 1 < list.count { return list[i + 1] }
        if i > 0 { return list[i - 1] }
        return nil
    }

    private func step(_ delta: Int) {
        guard let current = model.previewItem, let i = list.firstIndex(where: { $0.id == current.id }) else { return }
        let next = i + delta
        guard list.indices.contains(next) else { return }
        model.previewItem = list[next]
        model.selectedIDs = [list[next].id]
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) {
            model.previewItem = nil
            model.previewContext = []
        }
    }
}

/// An image with Live Text: select and copy text right in the picture.
struct LiveTextImage: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var task: Task<Void, Never>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.isEditable = false
        view.animates = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if ImageAnalyzer.isSupported {
            let overlay = ImageAnalysisOverlayView()
            overlay.autoresizingMask = [.width, .height]
            overlay.frame = view.bounds
            overlay.trackingImageView = view
            overlay.preferredInteractionTypes = .automatic
            view.addSubview(overlay)
        }
        load(into: view, context: context)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {}

    static func dismantleNSView(_ view: NSImageView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        for overlay in view.subviews.compactMap({ $0 as? ImageAnalysisOverlayView }) {
            overlay.analysis = nil
            overlay.trackingImageView = nil
            overlay.removeFromSuperview()
        }
        view.image = nil
    }

    private func load(into view: NSImageView, context: Context) {
        let url = self.url
        context.coordinator.task = Task { @MainActor in
            guard let image = NSImage(contentsOf: url) else { return }
            view.image = image
            guard ImageAnalyzer.isSupported,
                  let overlay = view.subviews.compactMap({ $0 as? ImageAnalysisOverlayView }).first else { return }
            let analyzer = ImageAnalyzer()
            let config = ImageAnalyzer.Configuration([.text, .machineReadableCode])
            if let analysis = try? await analyzer.analyze(image, orientation: .up, configuration: config), !Task.isCancelled {
                overlay.analysis = analysis
            }
        }
    }
}

struct VideoPreview: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVPlayer(url: url)
                player = p
                p.play()
            }
            .onDisappear { player?.pause() }
    }
}

struct AudioPreview: View {
    let item: FileItem
    let queue: [FileItem]
    @Environment(\.theme) private var theme
    private var player: MusicPlayer { .shared }

    var body: some View {
        VStack(spacing: 18) {
            Group {
                if player.current == item, let art = player.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 70))
                        .foregroundStyle(theme.tint(.music))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.fill(.music))
                }
            }
            .frame(width: 260, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(player.current == item ? player.title : item.baseName).font(.title2.weight(.semibold))
            if player.current == item, !player.artist.isEmpty { Text(player.artist).foregroundStyle(.secondary) }
            Button {
                if player.current == item { player.togglePlayPause() } else { player.play(item, queue: queue) }
            } label: {
                Image(systemName: player.current == item && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Apple's Quick Look view embedded in the window (PDFs, documents, anything).
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }
}
