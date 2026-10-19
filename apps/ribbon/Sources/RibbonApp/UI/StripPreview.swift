#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// Make-believe apps for previews and the tour.
enum DemoApp: CaseIterable {
    case mail, notes, safari, terminal, music, calendar, messages, finder

    var title: String {
        switch self {
        case .mail: return "Mail"
        case .notes: return "Notes"
        case .safari: return "Safari"
        case .terminal: return "Terminal"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .messages: return "Messages"
        case .finder: return "Finder"
        }
    }
    var symbol: String {
        switch self {
        case .mail: return "envelope.fill"
        case .notes: return "note.text"
        case .safari: return "safari.fill"
        case .terminal: return "terminal.fill"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .messages: return "message.fill"
        case .finder: return "folder.fill"
        }
    }
    var color: Color {
        switch self {
        case .mail: return Color(red: 0.2, green: 0.55, blue: 1.0)
        case .notes: return Color(red: 0.98, green: 0.78, blue: 0.2)
        case .safari: return Color(red: 0.16, green: 0.62, blue: 0.95)
        case .terminal: return Color(red: 0.2, green: 0.22, blue: 0.26)
        case .music: return Color(red: 0.98, green: 0.24, blue: 0.38)
        case .calendar: return Color(red: 0.95, green: 0.3, blue: 0.27)
        case .messages: return Color(red: 0.2, green: 0.8, blue: 0.35)
        case .finder: return Color(red: 0.25, green: 0.6, blue: 0.98)
        }
    }
}

let demoApps: [WindowID: DemoApp] = [1: .mail, 2: .notes, 3: .safari, 4: .terminal, 5: .music, 6: .calendar, 7: .messages, 8: .finder]

/// The virtual Mac screen previews are laid out on (points).
let previewScreen = Rect(x: 0, y: 0, w: 1440, h: 900)
let previewArea = Rect(x: 0, y: 30, w: 1440, h: 790)

func previewParams(_ c: Config? = nil) -> LayoutParams {
    let c = c ?? Config()
    return LayoutParams(screen: previewScreen, area: previewArea, innerGap: max(c.innerGap, 0) * 1.4, outerGap: max(c.outerGap, 0) * 1.4,
                        centerMode: c.centerMode, sparse: c.sparse, tabBarHeight: 40, keepOriginalHeight: false)
}

func demoStrip(count: Int = 5, focus: Int = 1, params: LayoutParams = previewParams()) -> Strip {
    var s = Strip()
    let widths = [0.5, 0.5, 2.0 / 3, 1.0 / 3, 0.5, 0.5, 0.5, 0.5]
    for i in 1...count { s.insert(WindowID(i), width: widths[(i - 1) % widths.count], at: .end, focus: false) }
    s.focusColumn(min(focus, count - 1))
    s.scroll = Layout.scrollToReveal(s, params)
    return s
}

/// A miniature desktop showing a strip, drawn with the real layout engine.
struct StripPreview: View {
    var strip: Strip
    var params: LayoutParams = previewParams()
    var border: (color: Color, width: Double, radius: Double)? = nil
    var dim: Double = 0
    var showDock = true
    var cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            canvas(scale: geo.size.width / CGFloat(previewScreen.w))
        }
        .aspectRatio(CGFloat(previewScreen.w / previewScreen.h), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 10)
    }

    private func canvas(scale k: CGFloat) -> some View {
        let r = Layout.compute(strip, params)
        return ZStack(alignment: .topLeading) {
            Wallpaper()
            ForEach(r.placements, id: \.window) { pl in
                windowView(pl, r: r, k: k)
            }
            ForEach(r.tabBars, id: \.column) { tb in
                tabBar(tb, r: r, k: k)
            }
            MenuBarStrip(scale: k)
            if showDock { DockStrip(scale: k) }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: strip)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: params)
    }

    @ViewBuilder
    private func windowView(_ pl: Placement, r: LayoutResult, k: CGFloat) -> some View {
        let col = strip.columns[pl.column]
        let hiddenTab = col.mode == .tabbed && pl.row != col.active
        if !hiddenTab {
            let focused = strip.focusedWindow == pl.window
            DemoWindowView(app: demoApps[pl.window] ?? .finder, focused: focused, scale: k,
                           ring: focused && border == nil ? Brand.violet : nil)
                .frame(width: CGFloat(pl.frame.w) * k, height: CGFloat(pl.frame.h) * k)
                .overlay(
                    RoundedRectangle(cornerRadius: 11 * k + 2, style: .continuous)
                        .fill(Color.black.opacity(focused ? 0 : dim))
                )
                .overlay(borderOverlay(focused: focused, k: k))
                .offset(x: CGFloat(pl.frame.x) * k, y: CGFloat(pl.frame.y) * k)
        }
    }

    @ViewBuilder
    private func borderOverlay(focused: Bool, k: CGFloat) -> some View {
        if focused, let b = border {
            RoundedRectangle(cornerRadius: CGFloat(b.radius) * k + 2, style: .continuous)
                .strokeBorder(b.color, lineWidth: max(1.5, CGFloat(b.width) * k * 1.6))
                .padding(-CGFloat(b.width) * k)
        }
    }

    private func tabBar(_ tb: RibbonCore.TabBarPlacement, r: LayoutResult, k: CGFloat) -> some View {
        let x: CGFloat = CGFloat(r.columnRects[tb.column].x) * k
        let y: CGFloat = CGFloat(tb.frame.y) * k
        let w: CGFloat = CGFloat(tb.frame.w) * k
        let h: CGFloat = CGFloat(tb.frame.h - 5) * k
        return PreviewTabBar(windows: tb.windows, active: tb.active, k: k)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
}

/// The tab bar of a tabbed column in previews.
private struct PreviewTabBar: View {
    let windows: [WindowID]
    let active: Int
    let k: CGFloat

    var body: some View {
        let gap: CGFloat = 3 * k + 1
        let pad: CGFloat = 3 * k
        let radius: CGFloat = 9 * k + 1
        HStack(spacing: gap) {
            ForEach(Array(windows.enumerated()), id: \.offset) { (pair: (offset: Int, element: WindowID)) in
                PreviewTab(app: demoApps[pair.element] ?? DemoApp.finder, active: pair.offset == active, k: k)
            }
        }
        .padding(pad)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(0.35)))
    }
}

private struct PreviewTab: View {
    let app: DemoApp
    let active: Bool
    let k: CGFloat

    var body: some View {
        let iconSize: CGFloat = max(6, 15 * k)
        let textSize: CGFloat = max(6, 16 * k)
        let radius: CGFloat = 7 * k + 1
        let fill: Color = active ? Brand.violet : Color.white.opacity(0.22)
        HStack(spacing: 4 * k) {
            Image(systemName: app.symbol).font(.system(size: iconSize))
            Text(app.title).font(.system(size: textSize, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
        .foregroundStyle(Color.white)
    }
}

struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.11, blue: 0.27), Color(red: 0.24, green: 0.16, blue: 0.42),
                                    Color(red: 0.55, green: 0.27, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                Ellipse().fill(Brand.violet.opacity(0.55)).frame(width: g.size.width * 0.9, height: g.size.height * 0.7)
                    .offset(x: -g.size.width * 0.2, y: g.size.height * 0.45).blur(radius: g.size.width * 0.06)
                Ellipse().fill(Brand.rose.opacity(0.45)).frame(width: g.size.width * 0.7, height: g.size.height * 0.6)
                    .offset(x: g.size.width * 0.5, y: g.size.height * 0.05).blur(radius: g.size.width * 0.07)
            }
        }
    }
}

struct MenuBarStrip: View {
    let scale: CGFloat
    var body: some View {
        HStack(spacing: 14 * scale) {
            Image(systemName: "apple.logo").font(.system(size: 17 * scale))
            Text("Ribbon").font(.system(size: 15 * scale, weight: .bold))
            Text("File   Edit   View   Window").font(.system(size: 15 * scale))
            Spacer()
            Image(systemName: "rectangle.split.3x1").font(.system(size: 16 * scale, weight: .semibold))
                .padding(.horizontal, 6 * scale).padding(.vertical, 2 * scale)
                .background(RoundedRectangle(cornerRadius: 4 * scale).fill(Color.white.opacity(0.25)))
            Image(systemName: "wifi").font(.system(size: 15 * scale))
            Text("9:41").font(.system(size: 15 * scale, weight: .medium))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16 * scale)
        .frame(height: 30 * scale)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.18))
    }
}

struct DockStrip: View {
    let scale: CGFloat
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10 * scale) {
                ForEach(Array(DemoApp.allCases.enumerated()), id: \.offset) { _, app in
                    RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                        .fill(LinearGradient(colors: [app.color.opacity(0.95), app.color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .overlay(Image(systemName: app.symbol).font(.system(size: 24 * scale, weight: .semibold)).foregroundStyle(Color.white))
                        .frame(width: 52 * scale, height: 52 * scale)
                }
            }
            .padding(9 * scale)
            .background(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous).fill(Color.white.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .padding(.bottom, 6 * scale)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A convincing little app window.
struct DemoWindowView: View {
    let app: DemoApp
    let focused: Bool
    let scale: CGFloat
    var ring: Color? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let radius = 11 * scale + 2
        let dark = app == .terminal
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(dark ? Color(red: 0.12, green: 0.13, blue: 0.16) : Color(white: scheme == .dark ? 0.16 : 0.98))
            VStack(spacing: 0) {
                titleBar(dark: dark)
                content(dark: dark).padding(12 * scale).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(ring ?? Color.black.opacity(0.18), lineWidth: ring == nil ? 0.75 : max(1.5, 3 * scale))
        )
        .shadow(color: Color.black.opacity(focused ? 0.45 : 0.25), radius: focused ? 14 * scale + 2 : 6 * scale + 1, y: 4 * scale)
    }

    private func titleBar(dark: Bool) -> some View {
        HStack(spacing: 7 * scale) {
            ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)],
                    id: \.self) { c in
                Circle().fill(focused ? c : Color.gray.opacity(0.45)).frame(width: 11 * scale, height: 11 * scale)
            }
            Spacer().frame(width: 8 * scale)
            Image(systemName: app.symbol).font(.system(size: 13 * scale, weight: .semibold)).foregroundStyle(app.color)
            Text(app.title).font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(dark ? Color.white.opacity(0.85) : Color.primary.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 12 * scale)
        .frame(height: 34 * scale)
        .background(dark ? Color.white.opacity(0.05) : app.color.opacity(0.08))
    }

    @ViewBuilder
    private func content(dark: Bool) -> some View {
        let line = dark ? Color.green.opacity(0.75) : Color.primary.opacity(0.12)
        let s = scale
        switch app {
        case .terminal:
            VStack(alignment: .leading, spacing: 9 * s) {
                ForEach(0..<9, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2 * s).fill(i % 3 == 0 ? Color.green.opacity(0.85) : Color.white.opacity(0.35))
                        .frame(width: CGFloat([220, 160, 300, 120, 260, 180, 90, 240, 140][i]) * s, height: 8 * s)
                }
            }
        case .music:
            VStack(alignment: .leading, spacing: 10 * s) {
                HStack(spacing: 10 * s) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 8 * s).fill(LinearGradient(colors: [[Brand.rose, Brand.violet, DemoApp.music.color][i], Brand.indigo],
                                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 110 * s, height: 110 * s)
                    }
                }
                ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 3 * s).fill(line).frame(height: 9 * s) }
            }
        case .calendar:
            VStack(spacing: 6 * s) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 6 * s) {
                        ForEach(0..<7, id: \.self) { col in
                            RoundedRectangle(cornerRadius: 4 * s)
                                .fill((row * 7 + col) % 9 == 3 ? DemoApp.calendar.color.opacity(0.75) : Color.primary.opacity(0.07))
                                .frame(height: 38 * s)
                        }
                    }
                }
            }
        case .safari:
            VStack(alignment: .leading, spacing: 10 * s) {
                Capsule().fill(Color.primary.opacity(0.08)).frame(height: 22 * s)
                RoundedRectangle(cornerRadius: 8 * s).fill(LinearGradient(colors: [DemoApp.safari.color.opacity(0.5), Brand.violet.opacity(0.4)],
                                                                         startPoint: .leading, endPoint: .trailing)).frame(height: 120 * s)
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3 * s).fill(line).frame(width: CGFloat([380, 300, 340, 260, 200][i]) * s, height: 9 * s)
                }
            }
        default:
            HStack(alignment: .top, spacing: 12 * s) {
                VStack(alignment: .leading, spacing: 10 * s) {
                    ForEach(0..<6, id: \.self) { i in
                        HStack(spacing: 6 * s) {
                            Circle().fill(i == 0 ? app.color : Color.primary.opacity(0.12)).frame(width: 14 * s, height: 14 * s)
                            RoundedRectangle(cornerRadius: 3 * s).fill(line).frame(height: 9 * s)
                        }
                    }
                }
                .frame(width: 150 * s)
                VStack(alignment: .leading, spacing: 10 * s) {
                    RoundedRectangle(cornerRadius: 3 * s).fill(app.color.opacity(0.6)).frame(width: 180 * s, height: 12 * s)
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3 * s).fill(line).frame(width: CGFloat([320, 280, 300, 240, 310, 180][i]) * s, height: 9 * s)
                    }
                }
            }
        }
    }
}
#endif
