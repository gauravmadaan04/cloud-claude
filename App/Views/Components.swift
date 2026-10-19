import AppKit
import HavenCore
import SwiftUI

/// A file's thumbnail: photos fill the frame, documents and icons sit inside it.
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
    private var fills: Bool {
        guard let t = thumb, !t.isIcon else { return false }
        return item.kind == .image || item.kind == .video
    }

    var body: some View {
        ZStack {
            if showsFrame {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.fill(for: item.kind).opacity(thumb == nil || thumb!.isIcon ? 1 : 0.6))
            }
            if let thumb {
                if fills {
                    Image(nsImage: thumb.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: h)
                        .clipped()
                } else if thumb.isIcon {
                    Image(nsImage: thumb.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(side, h) * 0.66, height: min(side, h) * 0.66)
                } else {
                    Image(nsImage: thumb.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(min(side, h) * 0.08)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                }
            } else {
                Image(systemName: theme.symbol(item.kind.symbolName))
                    .font(.system(size: min(side, h) * 0.3, weight: .regular))
                    .foregroundStyle(theme.tint(for: item.kind).opacity(0.7))
            }
            if item.kind == .video, thumb != nil, !(thumb!.isIcon) {
                Image(systemName: "play.fill")
                    .font(.system(size: max(10, min(side, h) * 0.12)))
                    .foregroundStyle(.white)
                    .padding(min(side, h) * 0.07)
                    .background(.black.opacity(0.35), in: Circle())
            }
        }
        .frame(width: side, height: h)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

/// A coloured circle naming where a download came from.
struct SourceBadge: View {
    let source: DownloadSource
    var size: CGFloat = 22
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(theme.sourceColor(source.tint))
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
                .font(.system(.title3, design: theme.headingDesign).weight(.semibold))
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

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.isPlayful ? theme.accent.opacity(0.7) : .secondary)
            Text(title)
                .font(.system(.title3, design: theme.headingDesign).weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .padding(.top, 4)
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
    private var prefs: Prefs { .shared }

    var body: some View {
        if !prefs.isTipDismissed(id) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    withAnimation { prefs.dismissTip(id) }
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Got it")
                .accessibilityIdentifier("tip.dismiss.\(id)")
            }
            .padding(14)
            .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.accent.opacity(0.18)))
        }
    }
}

struct ToastView: View {
    let toast: Toast
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .foregroundStyle(theme.isPlayful ? theme.accent : .primary)
            Text(toast.message)
                .lineLimit(2)
            if let id = toast.undoEntry {
                Button("Undo") {
                    FileOps.shared.undo(id)
                    AppModel.shared.toast = nil
                }
                .buttonStyle(.borderless)
                .fontWeight(.semibold)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityIdentifier("toast.undo")
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

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

/// Accessibility-friendly progress capsule used for scans.
struct ProgressPill: View {
    let text: String
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let progress {
                ProgressView(value: progress).progressViewStyle(.circular).controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }
}
