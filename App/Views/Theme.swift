import AppKit
import HavenCore
import SwiftUI

extension Color {
    /// A colour that adapts to light and dark mode.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }

    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The two looks: Playful (pastel colour) and Minimal (black, white and grey).
struct Theme {
    let look: Look

    var isPlayful: Bool { look == .playful }

    private struct Palette {
        let fillLight: UInt32, fillDark: UInt32, tintLight: UInt32, tintDark: UInt32
    }

    private static let palettes: [LibraryCategory: Palette] = [
        .images: Palette(fillLight: 0xFFE3EC, fillDark: 0x4A2433, tintLight: 0xE84A75, tintDark: 0xFF7A9C),
        .videos: Palette(fillLight: 0xECE4FF, fillDark: 0x33294D, tintLight: 0x7352F0, tintDark: 0xA38BFF),
        .music: Palette(fillLight: 0xD9F5E7, fillDark: 0x1F3D30, tintLight: 0x189E63, tintDark: 0x4CD496),
        .documents: Palette(fillLight: 0xE1F0FF, fillDark: 0x1F3247, tintLight: 0x2B78E4, tintDark: 0x64A6FF),
        .archives: Palette(fillLight: 0xFFF1C7, fillDark: 0x45391A, tintLight: 0xC98A00, tintDark: 0xFFC93D),
        .apps: Palette(fillLight: 0xFFE6D6, fillDark: 0x4A2E1F, tintLight: 0xE5651F, tintDark: 0xFF9A61),
    ]

    func tint(_ c: LibraryCategory) -> Color {
        guard isPlayful, let p = Self.palettes[c] else { return Color.primary.opacity(0.78) }
        return Color(light: NSColor(hex: p.tintLight), dark: NSColor(hex: p.tintDark))
    }

    func fill(_ c: LibraryCategory) -> Color {
        guard isPlayful, let p = Self.palettes[c] else { return Color.primary.opacity(0.055) }
        return Color(light: NSColor(hex: p.fillLight), dark: NSColor(hex: p.fillDark))
    }

    func tint(for kind: FileKind) -> Color {
        if let c = kind.category { return tint(c) }
        return isPlayful ? Color(light: NSColor(hex: 0x8A8F98), dark: NSColor(hex: 0xA9AEB8)) : Color.primary.opacity(0.7)
    }

    func fill(for kind: FileKind) -> Color {
        if let c = kind.category { return fill(c) }
        return Color.primary.opacity(0.06)
    }

    /// Accent used for selection and primary buttons.
    var accent: Color {
        isPlayful ? Color(light: NSColor(hex: 0x6B4EFF), dark: NSColor(hex: 0x9C86FF)) : Color.primary
    }

    /// Text colour on top of `accent`.
    var onAccent: Color {
        isPlayful ? .white : Color(light: .white, dark: .black)
    }

    var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }

    var cardStroke: Color { Color.primary.opacity(isPlayful ? 0.06 : 0.12) }

    var canvas: Color {
        isPlayful ? Color(light: NSColor(hex: 0xFAF8F5), dark: NSColor(hex: 0x1C1B1F)) : Color(nsColor: .windowBackgroundColor)
    }

    var cornerRadius: CGFloat { isPlayful ? 16 : 10 }

    var headingDesign: Font.Design { isPlayful ? .rounded : .default }

    /// Playful uses filled symbols, Minimal outlines.
    func symbol(_ name: String) -> String {
        guard isPlayful else { return name }
        let fillable: Set<String> = [
            "house", "clock", "photo", "doc.text", "archivebox", "folder", "camera.viewfinder", "trash", "magnifyingglass",
            "music.note.list", "play.rectangle", "square.grid.2x2", "arrow.down.circle", "square.on.square", "doc",
            "photo.on.rectangle", "shippingbox", "film", "bookmark", "tag", "pin", "star", "heart", "envelope",
            "externaldrive", "doc.richtext", "app.badge.clock", "film.stack", "doc.zipper",
        ]
        if fillable.contains(name) {
            switch name {
            case "magnifyingglass", "camera.viewfinder", "square.on.square", "doc.zipper", "app.badge.clock": return name
            case "photo.on.rectangle": return "photo.fill.on.rectangle.fill"
            case "square.grid.2x2": return "square.grid.2x2.fill"
            case "music.note.list": return "music.note.list"
            case "film.stack": return "film.stack.fill"
            default: return name + ".fill"
            }
        }
        return name
    }

    func sourceColor(_ tint: SourceTint) -> Color {
        guard isPlayful else { return Color.primary.opacity(0.7) }
        switch tint {
        case .red: return Color(hex: 0xEA4335)
        case .orange: return Color(hex: 0xF08A24)
        case .yellow: return Color(hex: 0xF4B400)
        case .green: return Color(hex: 0x25A35A)
        case .mint: return Color(hex: 0x2BB6A3)
        case .teal: return Color(hex: 0x10A37F)
        case .blue: return Color(hex: 0x2F7CF6)
        case .indigo: return Color(hex: 0x5865F2)
        case .purple: return Color(hex: 0x8E44D9)
        case .pink: return Color(hex: 0xE1306C)
        case .gray: return Color(hex: 0x7D8590)
        case .black: return Color(light: NSColor(hex: 0x24292F), dark: NSColor(hex: 0xD0D7DE))
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(look: .playful)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func cardStyle(_ theme: Theme, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous).strokeBorder(theme.cardStroke))
            .shadow(color: .black.opacity(theme.isPlayful ? 0.05 : 0), radius: 8, y: 2)
    }
}
