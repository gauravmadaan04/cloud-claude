import AVKit
import HavenCore
import Quartz
import SwiftUI
import VisionKit

/// Large in-window preview (double-click), like a lightbox: pictures float on a dark backdrop, documents sit
/// on a page card. ←/→ or the side arrows step through the list, the filmstrip jumps, Esc closes.
struct PreviewOverlay: View {
    @Bindable private var model = AppModel.shared
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager

    private var list: [FileItem] { model.previewContext.isEmpty ? model.visibleItems : model.previewContext }

    var body: some View {
        if let item = model.previewItem {
            let index = list.firstIndex(where: { $0.id == item.id })
            ZStack {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Color.black.opacity(0.74))
                }
                .ignoresSafeArea()
                .onTapGesture { close() }

                VStack(spacing: 14) {
                    header(item, index: index)
                    stage(item)
                        .id(item.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, list.count > 1 ? 64 : 12)
                    if list.count > 1, let index {
                        filmstrip(current: item, index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 14)

                if list.count > 1, let index {
                    HStack {
                        SideArrow(symbol: "chevron.left", enabled: index > 0) { step(-1) }
                            .help("Previous (←)")
                        Spacer()
                        SideArrow(symbol: "chevron.right", enabled: index + 1 < list.count) { step(1) }
                            .help("Next (→)")
                    }
                    .padding(.horizontal, 22)
                }
            }
            .environment(\.colorScheme, .dark)
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
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .accessibilityIdentifier("preview.overlay")
        }
    }

    // MARK: Header

    private func header(_ item: FileItem, index: Int?) -> some View {
        HStack(spacing: 10) {
            ThumbnailView(item: item, side: 30, cornerRadius: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.kind.displayName) · \(fileSubtitle(item))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            if let index, list.count > 1 {
                Text("\(index + 1) of \(list.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.trailing, 4)
            }
            HStack(spacing: 2) {
                if item.kind.hasReadableText {
                    PreviewAction(symbol: "text.quote", help: "Copy the text Haven read from this file (⇧⌘C)") { model.copyText([item]) }
                }
                PreviewAction(symbol: "arrow.up.forward.app", help: "Open") { NSWorkspace.shared.open(item.url) }
                PreviewAction(symbol: "folder", help: "Show in Finder") { model.revealInFinder([item]) }
                ShareLink(item: item.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Share")
                PreviewAction(symbol: "trash", help: "Move to Trash") {
                    let next = neighbour(of: item)
                    model.trash([item], reason: "Moved by you", undoManager: undoManager)
                    model.previewItem = next
                }
            }
            Divider().frame(height: 18).padding(.horizontal, 4)
            PreviewAction(symbol: "xmark", help: "Close (Esc)", prominent: true) { close() }
                .accessibilityIdentifier("preview.close")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassBackground(Capsule(), fallback: .ultraThinMaterial)
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .frame(maxWidth: 860)
    }

    // MARK: Stage

    @ViewBuilder
    private func stage(_ item: FileItem) -> some View {
        switch item.kind {
        case .image where item.ext != "psd" && item.ext != "svg":
            LightboxImage(url: item.url, animated: item.ext == "gif")
        case .video:
            VideoPreview(url: item.url)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        case .audio:
            AudioPreview(item: item, queue: list.filter { $0.kind == .audio })
        default:
            QuickLookPreview(url: item.url)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                .frame(maxWidth: 1000)
        }
    }

    // MARK: Filmstrip

    private func filmstrip(current: FileItem, index: Int) -> some View {
        let lower = max(0, index - 40)
        let upper = min(list.count, index + 41)
        let window = Array(list[lower..<upper])
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(window) { other in
                        let isCurrent = other.id == current.id
                        ThumbnailView(item: other, side: isCurrent ? 60 : 48, height: 42, cornerRadius: 6)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isCurrent ? Color.white : Color.white.opacity(0.1), lineWidth: isCurrent ? 2 : 1))
                            .opacity(isCurrent ? 1 : 0.6)
                            .contentShape(Rectangle())
                            .onTapGesture { jump(to: other) }
                            .help(other.name)
                            .id(other.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .animation(.snappy(duration: 0.2), value: current.id)
            }
            .onAppear { proxy.scrollTo(current.id, anchor: .center) }
            .onChange(of: current.id) { _, id in
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(maxWidth: min(760, CGFloat(window.count) * 54 + 32), maxHeight: 54)
        .mask {
            // Thumbnails fade out at the ends instead of being cut off.
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
            }
        }
        .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous), fallback: .ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .accessibilityIdentifier("preview.filmstrip")
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
        jump(to: list[next])
    }

    private func jump(to item: FileItem) {
        model.previewItem = item
        model.selectedIDs = [item.id]
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) {
            model.previewItem = nil
            model.previewContext = []
        }
    }
}

/// A round icon button in the preview header.
private struct PreviewAction: View {
    let symbol: String
    let help: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: prominent ? .bold : .medium))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : (prominent ? 0.1 : 0))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The big round arrows either side of the preview.
private struct SideArrow: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .glassBackground(Circle(), fallback: .ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                .scaleEffect(hovering && enabled ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}

/// A picture at its own proportions with soft corners and a deep shadow, never blown up past its pixels.
struct LightboxImage: View {
    let url: URL
    var animated = false
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                let fitted = fit(image.size, in: geo.size)
                LiveTextImage(image: image)
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.opacity)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.easeOut(duration: 0.18), value: image == nil)
        .task(id: url) {
            let url = self.url
            if animated {
                image = NSImage(contentsOf: url)
                return
            }
            let loaded = await Task.detached(priority: .userInitiated) { Thumbnails.imageThumbnail(url, maxPixel: 3600) }.value
            if !Task.isCancelled { image = loaded ?? NSImage(contentsOf: url) }
        }
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height, 1)
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }
}

/// An image with Live Text: select and copy text right in the picture.
struct LiveTextImage: NSViewRepresentable {
    let image: NSImage

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
        view.image = image
        if ImageAnalyzer.isSupported {
            let overlay = ImageAnalysisOverlayView()
            overlay.autoresizingMask = [.width, .height]
            overlay.frame = view.bounds
            overlay.trackingImageView = view
            overlay.preferredInteractionTypes = .automatic
            view.addSubview(overlay)
            let image = self.image
            context.coordinator.task = Task { @MainActor in
                let analyzer = ImageAnalyzer()
                let config = ImageAnalyzer.Configuration([.text, .machineReadableCode])
                if let analysis = try? await analyzer.analyze(image, orientation: .up, configuration: config), !Task.isCancelled {
                    overlay.analysis = analysis
                }
            }
        }
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
}

/// Plays a video in the large preview, or says plainly when it can't be played.
struct VideoPreview: View {
    let url: URL
    @State private var failedURL: URL?

    var body: some View {
        if failedURL == url {
            VStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Haven can't play this video")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("It may be damaged or in a format macOS doesn't support.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.65))
                Button("Open in Another App") { NSWorkspace.shared.open(url) }
                    .controlSize(.large)
                    .padding(.top, 4)
            }
            .padding(36)
            .frame(maxWidth: 420)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("preview.video.failed")
        } else {
            PlayerView(url: url) { failedURL = url }
                .accessibilityIdentifier("preview.video")
        }
    }
}

/// AppKit's own player (the one QuickTime Player uses). SwiftUI's VideoPlayer is avoided on purpose: on
/// current macOS it can crash the app the moment it first appears.
private struct PlayerView: NSViewRepresentable {
    let url: URL
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = QuietPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        context.coordinator.onFailure = onFailure
        context.coordinator.play(url, in: view)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.onFailure = onFailure
        if context.coordinator.url != url { context.coordinator.play(url, in: view) }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop(view)
    }

    @MainActor
    final class Coordinator {
        var url: URL?
        var onFailure: () -> Void = {}
        private var statusObservation: NSKeyValueObservation?

        func play(_ url: URL, in view: AVPlayerView) {
            stop(view)
            self.url = url
            let item = AVPlayerItem(url: url)
            statusObservation = Self.whenFailed(item) { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.url == url else { return }
                        self.onFailure()
                    }
                }
            }
            let player = AVPlayer(playerItem: item)
            view.player = player
            // One thing plays at a time.
            if MusicPlayer.shared.isPlaying { MusicPlayer.shared.pause() }
            player.play()
        }

        /// AVFoundation reports from any thread, so this callback belongs to none.
        nonisolated static func whenFailed(_ item: AVPlayerItem, _ failed: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
            item.observe(\.status, options: [.initial, .new]) { item, _ in
                if item.status == .failed { failed() }
            }
        }

        func stop(_ view: AVPlayerView) {
            statusObservation?.invalidate()
            statusObservation = nil
            view.player?.pause()
            view.player = nil
        }
    }
}

/// Leaves the keyboard to the preview (← → step through files, Space and Esc close); the controls still work
/// with the mouse.
private final class QuietPlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { false }
}

struct AudioPreview: View {
    let item: FileItem
    let queue: [FileItem]
    @Environment(\.theme) private var theme
    private var player: MusicPlayer { .shared }

    private var isCurrent: Bool { player.current == item }

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if isCurrent, let art = player.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(hex: 0x2BB673), Color(hex: 0x1F6F8B)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        WaveformArt(seed: item.name, color: .white.opacity(0.85))
                            .frame(width: 170, height: 80)
                    }
                }
            }
            .frame(width: 270, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
            .padding(.bottom, 8)
            Text(isCurrent && !player.title.isEmpty ? player.title : item.baseName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if isCurrent, !player.artist.isEmpty {
                Text(player.artist).foregroundStyle(.secondary)
            }
            if isCurrent, player.duration > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: min(1, player.position / player.duration))
                        .progressViewStyle(.linear)
                        .tint(.white)
                    HStack {
                        Text(Self.time(player.position))
                        Spacer()
                        Text("-" + Self.time(max(0, player.duration - player.position)))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(width: 270)
            }
            Button {
                if isCurrent { player.togglePlayPause() } else { player.play(item, queue: queue) }
            } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func time(_ t: Double) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Apple's Quick Look view embedded in the window (PDFs, documents, anything).
struct QuickLookPreview: View {
    let url: URL

    var body: some View {
        // A new Quick Look view per file: changing the item of a live view during layout makes Quick Look abort.
        QuickLookHost(url: url).id(url)
    }
}

private struct QuickLookHost: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 240), style: .normal)!
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {}

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
