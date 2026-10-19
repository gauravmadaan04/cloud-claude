import AppKit
import HavenCore
import SwiftUI

// MARK: - Glass

extension View {
    /// Liquid Glass on macOS 26, a material on earlier systems.
    @ViewBuilder
    func glassBackground<S: Shape>(_ shape: S, fallback: Material = .regularMaterial) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    /// Lifts a card a little under the pointer.
    func hoverLift(_ active: Bool, radius: CGFloat = 12) -> some View {
        self
            .scaleEffect(active ? 1.018 : 1)
            .shadow(color: .black.opacity(active ? 0.16 : 0.05), radius: active ? 12 : 3, y: active ? 6 : 1)
            .animation(.snappy(duration: 0.2), value: active)
    }
}

// MARK: - Thumbnails

/// A file's thumbnail: photos fill the frame, documents sit on a soft sheet, everything else gets a
/// designed tile for its type instead of a generic icon.
struct ThumbnailView: View {
    let item: FileItem
    let side: CGFloat
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 10
    var showsFrame = true

    @Environment(\.displayScale) private var scale
    @Environment(\.theme) private var theme
    @State private var thumb: Thumbnail?

    private var h: CGFloat { height ?? side }
    private var showsRealIcon: Bool { item.kind == .app || item.kind == .folder }

    var body: some View {
        ZStack {
            if let thumb, !thumb.isIcon {
                if item.kind == .image || item.kind == .video {
                    Image(nsImage: thumb.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: h)
                        .clipped()
                        .transition(.opacity)
                } else {
                    // A page (PDF, document, text): show it like a sheet of paper.
                    ZStack {
                        LinearGradient(colors: [theme.fill(for: item.kind), theme.fill(for: item.kind).opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                        Image(nsImage: thumb.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                            .padding(.horizontal, side * 0.14)
                            .padding(.top, h * 0.1)
                            .padding(.bottom, h * 0.06)
                    }
                    .transition(.opacity)
                }
            } else if let thumb, showsRealIcon {
                ZStack {
                    if showsFrame { theme.fill(for: item.kind).opacity(0.55) }
                    Image(nsImage: thumb.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(side, h) * 0.68, height: min(side, h) * 0.68)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                }
            } else {
                FileTypeTile(item: item, compact: min(side, h) < 60)
            }
            if item.kind == .video, let thumb, !thumb.isIcon {
                Image(systemName: "play.fill")
                    .font(.system(size: max(9, min(side, h) * 0.11), weight: .bold))
                    .foregroundStyle(.white)
                    .padding(min(side, h) * 0.075)
                    .background(.black.opacity(0.32), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            }
        }
        .frame(width: side, height: h)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: thumb == nil)
        .task(id: "\(item.path)|\(item.modified.timeIntervalSince1970)|\(Thumbnails.bucket(max(side, h)))") {
            if let hit = Thumbnails.shared.cached(item, side: max(side, h)) {
                thumb = hit
                return
            }
            let t = await Thumbnails.shared.thumbnail(for: item, side: max(side, h), scale: scale)
            if !Task.isCancelled { thumb = t }
        }
    }
}

/// A designed tile for files without a picture: soft colour of the kind, a symbol, and the extension.
struct FileTypeTile: View {
    let item: FileItem
    var compact = false
    @Environment(\.theme) private var theme

    private var symbol: String {
        switch item.kind {
        case .audio: return "waveform"
        case .pdf: return "doc.richtext.fill"
        case .document: return "doc.text.fill"
        case .spreadsheet: return "tablecells.fill"
        case .presentation: return "play.rectangle.on.rectangle.fill"
        case .text: return "doc.plaintext.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archive: return "doc.zipper"
        case .installer: return "shippingbox.fill"
        case .app: return "app.dashed"
        case .font: return "textformat"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .folder: return "folder.fill"
        case .other: return "doc.fill"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let tint = theme.tint(for: item.kind)
            ZStack {
                theme.fill(for: item.kind)
                LinearGradient(colors: [.white.opacity(theme.isPlayful ? 0.35 : 0.0), tint.opacity(theme.isPlayful ? 0.16 : 0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if item.kind == .audio && !compact {
                    WaveformArt(seed: item.name, color: tint.opacity(0.75))
                        .frame(width: geo.size.width * 0.66, height: s * 0.36)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: s * (compact ? 0.42 : 0.3), weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                }
                if !compact && !item.ext.isEmpty && item.kind != .folder {
                    VStack {
                        Spacer()
                        HStack {
                            Text(item.ext.uppercased())
                                .font(.system(size: max(8, s * 0.075), weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                                .padding(.horizontal, s * 0.05)
                                .padding(.vertical, s * 0.018)
                                .background(.white.opacity(0.85), in: Capsule())
                            Spacer()
                        }
                    }
                    .padding(s * 0.07)
                }
            }
        }
    }
}

/// Decorative waveform bars, stable for a given name.
struct WaveformArt: View {
    let seed: String
    let color: Color

    private var heights: [CGFloat] {
        var x: UInt32 = seed.unicodeScalars.reduce(2_166_136_261) { ($0 ^ $1.value) &* 16_777_619 }
        return (0..<22).map { i in
            x ^= x << 13; x ^= x >> 17; x ^= x << 5
            let wave = 0.55 + 0.45 * sin(Double(i) / 3.2)
            return CGFloat(0.25 + 0.75 * wave * (0.55 + Double(x % 100) / 220))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let bars = heights
            let w = geo.size.width / CGFloat(bars.count * 2 - 1)
            HStack(alignment: .center, spacing: w) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, h in
                    Capsule().fill(color).frame(width: w, height: max(w, geo.size.height * h))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Badges & headers

/// A coloured circle naming where a download came from.
struct SourceBadge: View {
    let source: DownloadSource
    var size: CGFloat = 22
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(theme.sourceColor(source.tint).gradient)
            if source.isWebsite {
                Text(source.monogram)
                    .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: source.symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: max(1, size * 0.06)))
        .help("Downloaded from \(source.name)")
    }
}

struct SectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: theme.headingDesign))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = { EmptyView() }
    }
}

/// "See All ›" link used on Home sections.
struct SeeAllButton: View {
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("See All")
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(theme.accent.opacity(hovering ? 1 : 0.85))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - States

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [theme.accent.opacity(0.18), theme.accent.opacity(0.05)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(theme.accent.opacity(0.15), lineWidth: 1)
                    .frame(width: 96, height: 96)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.isPlayful ? theme.accent : Color.secondary)
            }
            .padding(.bottom, 4)
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: theme.headingDesign))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(theme.accent)
                    .padding(.top, 6)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small dismissible explanation shown the first time a screen is visited.
struct TipBanner: View {
    let id: String
    let symbol: String
    let title: String
    let message: String
    @Environment(\.theme) private var theme
    @State private var hoveringClose = false
    private var prefs: Prefs { .shared }

    var body: some View {
        if !prefs.isTipDismissed(id) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent)
                    .frame(width: 38, height: 38)
                    .background(theme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy) { prefs.dismissTip(id) }
                } label: {
                    Text("Got it")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(hoveringClose ? 0.1 : 0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hoveringClose = $0 }
                .accessibilityIdentifier("tip.dismiss.\(id)")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.cardStroke))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

struct ToastView: View {
    let toast: Toast
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.isPlayful ? theme.accent : .primary)
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.message)
                .lineLimit(2)
            if let id = toast.undoEntry {
                Divider().frame(height: 16)
                Button {
                    FileOps.shared.undo(id)
                    AppModel.shared.toast = nil
                } label: {
                    Text("Undo").fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityIdentifier("toast.undo")
            }
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassBackground(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

// MARK: - Shapes & bits

/// A folder silhouette with a tab, used for the library tiles.
struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = min(rect.width, rect.height) * 0.09
        let tabW = rect.width * 0.38
        let tabH = rect.height * 0.12
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tabW - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tabW + r * 0.6, y: rect.minY + tabH * 0.6),
                       control: CGPoint(x: rect.minX + tabW, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tabW + r * 1.8, y: rect.minY + tabH),
                       control: CGPoint(x: rect.minX + tabW + r * 1.2, y: rect.minY + tabH))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY + tabH))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tabH + r), control: CGPoint(x: rect.maxX, y: rect.minY + tabH))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Keyboard key caps like ⌘ F.
struct KeyCaps: View {
    let keys: String
    var body: some View {
        Text(keys)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// "12 MB · Yesterday" under a file name.
func fileSubtitle(_ item: FileItem) -> String {
    var parts: [String] = []
    if item.kind != .folder && item.size > 0 { parts.append(ByteSize.format(item.size)) }
    parts.append(HavenFormat.friendlyDate(item.activityDate))
    return parts.joined(separator: " · ")
}

/// Small status capsule used for scans.
struct ProgressPill: View {
    let text: String
    var progress: Double? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            if let progress {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(0.03, progress))
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: progress)
                }
                .frame(width: 13, height: 13)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
    }
}
