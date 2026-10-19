#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

// Ribbon's visual language: the indigo → violet → rose gradient of the app icon, native materials
// (Liquid Glass on macOS 26), SF Symbols, real-looking keycaps and springy motion.

enum Brand {
    static let indigo = Color(red: 0.204, green: 0.259, blue: 0.627)
    static let violet = Color(red: 0.471, green: 0.290, blue: 0.780)
    static let rose = Color(red: 0.929, green: 0.408, blue: 0.565)
    static let accent = violet

    static let gradient = LinearGradient(colors: [indigo, violet, rose], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let softGradient = LinearGradient(colors: [indigo.opacity(0.9), violet.opacity(0.9)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
}

/// Badge colours in the style of System Settings.
enum BadgeColors {
    static let gray = [Color(white: 0.62), Color(white: 0.45)]
    static let blue = [Color(red: 0.25, green: 0.6, blue: 1.0), Color(red: 0.1, green: 0.42, blue: 0.95)]
    static let indigo = [Color(red: 0.42, green: 0.45, blue: 1.0), Color(red: 0.3, green: 0.3, blue: 0.86)]
    static let violet = [Color(red: 0.66, green: 0.45, blue: 1.0), Color(red: 0.47, green: 0.29, blue: 0.86)]
    static let pink = [Color(red: 1.0, green: 0.45, blue: 0.62), Color(red: 0.92, green: 0.25, blue: 0.47)]
    static let orange = [Color(red: 1.0, green: 0.68, blue: 0.25), Color(red: 0.98, green: 0.47, blue: 0.13)]
    static let green = [Color(red: 0.35, green: 0.85, blue: 0.45), Color(red: 0.18, green: 0.68, blue: 0.32)]
    static let teal = [Color(red: 0.3, green: 0.82, blue: 0.86), Color(red: 0.1, green: 0.6, blue: 0.72)]
    static let red = [Color(red: 1.0, green: 0.42, blue: 0.38), Color(red: 0.9, green: 0.22, blue: 0.2)]
    static let brand = [Brand.violet, Brand.indigo]
}

// MARK: - Glass

/// Liquid Glass on macOS 26, a material everywhere else.
struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var material: Material = .regularMaterial

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? Glass.regular, in: shape)
        } else {
            content
                .background(material, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

extension View {
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, material: Material = .regularMaterial) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, material: material))
    }

    /// A rounded content card.
    func card(padding: CGFloat = 16, radius: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

// MARK: - Icon badge

struct IconBadge: View {
    let symbol: String
    var colors: [Color] = BadgeColors.brand
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 0.5, y: 0.5)
            )
            .frame(width: size, height: size)
            .shadow(color: (colors.last ?? .black).opacity(0.28), radius: size * 0.08, y: size * 0.04)
    }
}

// MARK: - Keycaps

enum KeyCapSize {
    case small, regular, large, hero

    var font: CGFloat {
        switch self {
        case .small: return 11
        case .regular: return 13
        case .large: return 20
        case .hero: return 30
        }
    }
    var height: CGFloat {
        switch self {
        case .small: return 20
        case .regular: return 26
        case .large: return 40
        case .hero: return 62
        }
    }
    var radius: CGFloat { height * 0.24 }
    var depth: CGFloat { max(1.5, height * 0.07) }
}

/// One physical-looking key.
struct KeyCap: View {
    let label: String
    var size: KeyCapSize = .regular
    var pressed = false
    var highlighted = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let face = dark ? [Color(white: 0.33), Color(white: 0.27)] : [Color.white, Color(white: 0.94)]
        let base = dark ? Color(white: 0.12) : Color(white: 0.74)
        let border = dark ? Color(white: 0.42) : Color(white: 0.8)
        let depth = size.depth
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                .fill(highlighted ? Brand.indigo : base)
                .offset(y: depth)
            RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                .fill(LinearGradient(colors: highlighted ? [Brand.violet, Brand.violet.opacity(0.85)] : face,
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                        .strokeBorder(highlighted ? Color.white.opacity(0.3) : border, lineWidth: 0.75)
                )
                .overlay(
                    Text(label)
                        .font(.system(size: size.font, weight: .semibold, design: .rounded))
                        .foregroundStyle(highlighted ? Color.white : (dark ? Color.white.opacity(0.92) : Color(white: 0.2)))
                        .padding(.horizontal, size.height * 0.28)
                )
                .offset(y: pressed ? depth * 0.8 : 0)
        }
        .frame(minWidth: size.height, minHeight: size.height + depth)
        .fixedSize(horizontal: label.count > 1, vertical: false)
        .animation(Brand.snappy, value: pressed)
        .animation(Brand.snappy, value: highlighted)
    }
}

/// A shortcut drawn as separate keycaps: ⌃ ⌥ →.
struct ShortcutKeys: View {
    let combo: KeyCombo
    var size: KeyCapSize = .regular
    var pressed = false
    var highlighted = false

    var body: some View {
        HStack(spacing: size.height * 0.14) {
            ForEach(ShortcutKeys.parts(combo), id: \.self) { p in
                KeyCap(label: p, size: size, pressed: pressed, highlighted: highlighted)
            }
        }
    }

    static func parts(_ c: KeyCombo) -> [String] {
        var out: [String] = []
        if c.modifiers.contains(.control) { out.append("⌃") }
        if c.modifiers.contains(.option) { out.append("⌥") }
        if c.modifiers.contains(.shift) { out.append("⇧") }
        if c.modifiers.contains(.command) { out.append("⌘") }
        out.append(KeyboardLayout.name(for: c.keyCode) ?? KeyCode.label(for: c.keyCode))
        return out
    }
}

/// The first shortcut of a command, or a dash.
struct CommandKeys: View {
    let command: Command
    var size: KeyCapSize = .regular
    var pressed = false
    var highlighted = false
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        if let c = store.config.combos(for: command).first {
            ShortcutKeys(combo: c, size: size, pressed: pressed, highlighted: highlighted)
        } else {
            Text("Not set").font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Buttons

struct BrandButtonStyle: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        BrandButton(configuration: configuration, large: large)
    }

    private struct BrandButton: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: large ? 15 : 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, large ? 22 : 16)
                .padding(.vertical, large ? 10 : 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Brand.gradient)
                        .brightness(hover ? 0.06 : 0)
                        .opacity(enabled ? 1 : 0.4)
                )
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
                .shadow(color: Brand.violet.opacity(hover ? 0.45 : 0.3), radius: hover ? 10 : 6, y: 3)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Brand.snappy, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 }
        }
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration)
    }

    private struct QuietButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(hover ? 0.1 : 0.06)))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Brand.snappy, value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}

// MARK: - Status pill

struct StatusPill: View {
    enum Kind { case good, waiting, warn, info }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .waiting: ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
            default: Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
        .foregroundStyle(kind == .waiting ? Color.secondary : color)
    }

    private var color: Color {
        switch kind {
        case .good: return .green
        case .waiting: return .secondary
        case .warn: return .orange
        case .info: return .blue
        }
    }
}

// MARK: - Pane header (System Settings style)

struct PaneHeader: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconBadge(symbol: symbol, colors: colors, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Animated backdrop

/// Slowly drifting colour blobs behind the welcome tour.
struct AuroraBackdrop: View {
    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let blobs: [(Color, Double, Double, Double)] = [
                    (Brand.indigo, 0.21, 0.0, 0.55), (Brand.violet, 0.17, 2.1, 0.5), (Brand.rose, 0.13, 4.2, 0.42),
                ]
                for (color, speed, phase, scale) in blobs {
                    let x = size.width * (0.5 + 0.38 * cos(t * speed + phase))
                    let y = size.height * (0.5 + 0.34 * sin(t * speed * 1.3 + phase))
                    let r = min(size.width, size.height) * scale
                    g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                           with: .color(color.opacity(0.35 * intensity)))
                }
            }
            .blur(radius: 70)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Checkmark burst

struct SuccessMark: View {
    var size: CGFloat = 64
    @State private var appear = false

    var body: some View {
        ZStack {
            Circle().fill(Color.green.opacity(0.15)).frame(width: size * 1.6, height: size * 1.6)
                .scaleEffect(appear ? 1 : 0.4).opacity(appear ? 1 : 0)
            Circle().fill(LinearGradient(colors: [Color(red: 0.35, green: 0.85, blue: 0.45), Color(red: 0.16, green: 0.66, blue: 0.3)],
                                         startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .shadow(color: Color.green.opacity(0.4), radius: 12, y: 4)
            Image(systemName: "checkmark").font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(Color.white)
                .scaleEffect(appear ? 1 : 0.2)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true } }
    }
}
#endif
