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
let previewVisible = Rect(x: 0, y: 30, w: 1440, h: 790)

/// A board with windows 1…n, the way Ribbon would tile them.
func demoBoard(_ n: Int, capacity: Int = 3, active: WindowID? = nil) -> Board {
    var b = Board()
    for i in 1...max(1, n) { b.add(WindowID(i), capacity: capacity, stackWhenFull: true, activate: false) }
    b.capacity = capacity
    b.active = active ?? b.tiles.first?.showing
    return b
}

/// What a preview shows on top of the plain layout.
struct PreviewStyle: Equatable {
    var kind: LayoutKind = .grid
    var spacing: Double = 8
    var highlight: Highlight = .activeBorder
    var color: Color = Brand.violet
    var radius: Double = 12
    /// No peek: how dark the other windows get (0 = off).
    var dim: Double = 0
    var cleanSpace = false
    var grip = true
    var showDock = true

    init(kind: LayoutKind = .grid, spacing: Double = 8, highlight: Highlight = .activeBorder, color: Color = Brand.violet,
         radius: Double = 12, dim: Double = 0, cleanSpace: Bool = false, grip: Bool = true, showDock: Bool = true) {
        self.kind = kind; self.spacing = spacing; self.highlight = highlight; self.color = color; self.radius = radius
        self.dim = dim; self.cleanSpace = cleanSpace; self.grip = grip; self.showDock = showDock
    }

    init(config c: Config) {
        self.init(kind: c.layout, spacing: c.spacing, highlight: c.highlight, color: Color(nsColor: NSColor(hex: c.highlightColor) ?? .systemPurple),
                  radius: c.cornerRadius, grip: c.quickActions)
    }
}

/// A miniature desktop tiled by the real layout engine.
struct BoardPreview: View {
    var board: Board
    var style = PreviewStyle()
    /// Windows drawn where they are instead of where the layout puts them (the messy "before").
    var loose: [WindowID: Rect] = [:]
    var cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            canvas(k: geo.size.width / CGFloat(previewScreen.w))
        }
        .aspectRatio(CGFloat(previewScreen.w / previewScreen.h), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 10)
    }

    private struct Item: Identifiable {
        let id: WindowID
        let frame: Rect
        let active: Bool
        let behind: Bool
    }

    private func items() -> [Item] {
        let spacing = style.spacing * 1.5
        let area = previewVisible.insetBy(spacing)
        let arr = TileLayout.arrangement(style.kind, area: area)
        var frames = TileLayout.frames(count: board.tiles.count, arr, area: area, gap: spacing, splits: board.splits,
                                       widths: board.tiles.map { $0.width ?? 0.5 })
        if arr == .scrolling, let i = board.activeTile {
            // Keep the window in use in view, as the real strip does.
            let scroll = TileLayout.reveal(i, frames, area: area, scroll: board.scroll)
            frames = frames.map { Rect(x: $0.x - scroll, y: $0.y, w: $0.w, h: $0.h) }
        }
        var back: [Item] = [], front: [Item] = [], top: [Item] = []
        for (i, t) in board.tiles.enumerated() where frames.indices.contains(i) {
            for (j, wid) in t.waiting.enumerated() {
                // Waiting windows peek out a little so the stack reads as a stack.
                let off = Double(t.waiting.count - j) * 14
                let f = loose[wid] ?? Rect(x: frames[i].x + off, y: frames[i].y - off * 0.6, w: frames[i].w, h: frames[i].h)
                back.append(Item(id: wid, frame: f, active: false, behind: true))
            }
            let wid = t.showing
            let zoomed = board.zoomed == wid || (style.cleanSpace && board.active == wid)
            let item = Item(id: wid, frame: loose[wid] ?? (zoomed ? area : frames[i]), active: board.active == wid, behind: false)
            if zoomed { top.append(item) } else { front.append(item) }
        }
        return back + front + top
    }

    private func canvas(k: CGFloat) -> some View {
        let all = items()
        let activeFrame = all.first { $0.active }?.frame
        return ZStack(alignment: .topLeading) {
            Wallpaper()
            if style.cleanSpace {
                Rectangle().fill(Color(red: 0.16, green: 0.17, blue: 0.2))
            }
            ForEach(all) { it in
                windowView(it, k: k)
            }
            if style.grip, loose.isEmpty, let f = activeFrame, !style.cleanSpace {
                Capsule().fill(style.color)
                    .frame(width: 60 * k, height: 7 * k)
                    .offset(x: CGFloat(f.midX) * k - 30 * k, y: CGFloat(f.minY) * k - 9 * k)
            }
            MenuBarStrip(scale: k)
            if style.showDock && !style.cleanSpace { DockStrip(scale: k) }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.84), value: board)
        .animation(.spring(response: 0.5, dampingFraction: 0.84), value: style)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: loose)
    }

    private func windowView(_ it: Item, k: CGFloat) -> some View {
        let radius: CGFloat = CGFloat(style.radius) * k * 1.4 + 2
        let showBorder = (style.highlight == .activeBorder && it.active) || (style.highlight == .allBorders && !it.behind)
        let borderColor: Color = it.active ? style.color : Color.white.opacity(0.55)
        let dimmed = style.dim > 0 && !it.active
        return DemoWindowView(app: demoApps[it.id] ?? .finder, focused: it.active, scale: k)
            .frame(width: CGFloat(it.frame.w) * k, height: CGFloat(it.frame.h) * k)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(dimmed ? style.dim : 0)))
            .blur(radius: dimmed ? 3 * k + 1 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: max(1.5, 4 * k))
                    .padding(-3 * k)
                    .opacity(showBorder ? 1 : 0)
            )
            .shadow(color: style.color.opacity(style.highlight == .glow && it.active ? 0.9 : 0), radius: 22 * k)
            .offset(x: CGFloat(it.frame.x) * k, y: CGFloat(it.frame.y) * k)
            .zIndex(it.behind ? 0 : (it.active ? 2 : 1))
    }
}

/// A preview that plays a little script of changes on a loop.
struct ScriptedBoard: View {
    let start: Board
    let script: [(inout Board) -> Void]
    var every: Double = 1.4
    var style = PreviewStyle()
    @State private var board: Board?
    @State private var tick = 0

    var body: some View {
        BoardPreview(board: board ?? start, style: style)
            .onReceive(Timer.publish(every: every, on: .main, in: .common).autoconnect()) { _ in
                var b = board ?? start
                let phase = tick % (script.count + 1)
                if phase == script.count { b = start } else { script[phase](&b) }
                tick += 1
                board = b
            }
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
            Image(systemName: "square.grid.2x2").font(.system(size: 15 * scale, weight: .semibold))
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

    private func content(dark: Bool) -> some View {
        GeometryReader { (geo: GeometryProxy) in
            DemoContent(app: app, dark: dark, s: scale, size: geo.size)
        }
    }
}

/// Placeholder content that fills a demo window at any size, so previews look like real, busy windows.
private struct DemoContent: View {
    let app: DemoApp
    let dark: Bool
    let s: CGFloat
    let size: CGSize

    private var ink: Color { Color.primary.opacity(0.12) }
    private var faint: Color { Color.primary.opacity(0.07) }

    var body: some View {
        Group {
            switch app {
            case .terminal: terminal
            case .music: music
            case .calendar: calendar
            case .safari: safari
            case .messages: messages
            case .finder: finder
            default: list
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private func bar(_ color: Color, _ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(3 * s, height / 2)).fill(color).frame(width: max(0, width), height: height)
    }

    private func count(_ length: CGFloat, step: CGFloat) -> Int { max(0, Int(length / max(1, step))) }

    private var terminal: some View {
        let widths: [CGFloat] = [0.55, 0.38, 0.72, 0.3, 0.64, 0.46, 0.22, 0.6, 0.34, 0.5]
        let n: Int = max(1, count(size.height + 9 * s, step: 17 * s))
        return VStack(alignment: .leading, spacing: 9 * s) {
            ForEach(0..<n, id: \.self) { (i: Int) in
                HStack(spacing: 6 * s) {
                    if i % 4 == 0 { bar(Color.green.opacity(0.85), 14 * s, 8 * s) }
                    if i == n - 1 {
                        bar(Color.white.opacity(0.75), 8 * s, 12 * s)
                    } else {
                        bar(Color.white.opacity(i % 4 == 0 ? 0.6 : 0.3), size.width * widths[i % widths.count], 8 * s)
                    }
                }
            }
        }
    }

    private var music: some View {
        let gap: CGFloat = 10 * s
        let tile: CGFloat = max(0, min((size.width - 2 * gap) / 3, size.height * 0.42))
        let rowH: CGFloat = 26 * s
        let rows: Int = count(size.height - tile - gap + 6 * s, step: rowH + 6 * s)
        let tints: [Color] = [Brand.rose, Brand.violet, DemoApp.music.color]
        let titles: [CGFloat] = [0.42, 0.3, 0.36, 0.26]
        return VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { (i: Int) in
                    RoundedRectangle(cornerRadius: 8 * s)
                        .fill(LinearGradient(colors: [tints[i], Brand.indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: tile, height: tile)
                }
            }
            VStack(spacing: 6 * s) {
                ForEach(0..<rows, id: \.self) { (i: Int) in
                    HStack(spacing: 8 * s) {
                        RoundedRectangle(cornerRadius: 4 * s).fill(tints[i % 3].opacity(0.55)).frame(width: rowH, height: rowH)
                        VStack(alignment: .leading, spacing: 5 * s) {
                            bar(ink, size.width * titles[i % titles.count], 7 * s)
                            bar(faint, size.width * 0.2, 6 * s)
                        }
                        Spacer(minLength: 0)
                        bar(faint, 24 * s, 6 * s)
                    }
                    .frame(height: rowH)
                }
            }
        }
    }

    private var calendar: some View {
        let gap: CGFloat = 6 * s
        let header: CGFloat = 12 * s + 8 * s + 2 * gap
        let cell: CGFloat = max(4 * s, (size.height - header - 4 * gap) / 5)
        return VStack(alignment: .leading, spacing: gap) {
            bar(DemoApp.calendar.color.opacity(0.7), min(size.width * 0.4, 150 * s), 12 * s)
            HStack(spacing: gap) {
                ForEach(0..<7, id: \.self) { (_: Int) in bar(faint, 18 * s, 8 * s).frame(maxWidth: .infinity) }
            }
            ForEach(0..<5, id: \.self) { (row: Int) in
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { (col: Int) in
                        calendarCell(index: row * 7 + col, height: cell)
                    }
                }
            }
        }
    }

    private func calendarCell(index: Int, height: CGFloat) -> some View {
        let busy: Bool = index % 9 == 3 || index % 11 == 6
        return RoundedRectangle(cornerRadius: 4 * s).fill(faint)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if busy && height > 22 * s {
                    RoundedRectangle(cornerRadius: 3 * s)
                        .fill((index % 2 == 0 ? DemoApp.calendar.color : Brand.violet).opacity(0.7))
                        .frame(height: min(10 * s, height * 0.3))
                        .padding(4 * s)
                }
            }
    }

    private var safari: some View {
        let gap: CGFloat = 10 * s
        let hero: CGFloat = max(0, size.height * 0.32)
        let card: CGFloat = max(0, size.height * 0.16)
        let cardTints: [Color] = [Brand.rose, Brand.indigo, DemoApp.safari.color]
        let lines: Int = count(size.height - 22 * s - hero - card - 3 * gap + 9 * s, step: 19 * s)
        let widths: [CGFloat] = [0.9, 0.72, 0.84, 0.64, 0.5, 0.78]
        return VStack(alignment: .leading, spacing: gap) {
            Capsule().fill(faint).frame(height: 22 * s)
            RoundedRectangle(cornerRadius: 8 * s)
                .fill(LinearGradient(colors: [DemoApp.safari.color.opacity(0.5), Brand.violet.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                .frame(height: hero)
            HStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { (i: Int) in
                    RoundedRectangle(cornerRadius: 6 * s).fill(cardTints[i].opacity(0.18)).frame(height: card)
                }
            }
            VStack(alignment: .leading, spacing: 10 * s) {
                ForEach(0..<lines, id: \.self) { (i: Int) in bar(ink, size.width * widths[i % widths.count], 9 * s) }
            }
        }
    }

    private var messages: some View {
        let rowH: CGFloat = 30 * s
        let n: Int = count(size.height + 10 * s, step: rowH + 10 * s)
        let widths: [CGFloat] = [0.55, 0.4, 0.62, 0.34, 0.48, 0.58]
        return VStack(spacing: 10 * s) {
            ForEach(0..<n, id: \.self) { (i: Int) in
                let mine: Bool = i % 3 == 1 || i % 5 == 4
                HStack(spacing: 0) {
                    if mine { Spacer(minLength: 0) }
                    Capsule()
                        .fill(mine ? AnyShapeStyle(DemoApp.messages.color.opacity(0.8)) : AnyShapeStyle(faint))
                        .frame(width: size.width * widths[i % widths.count], height: rowH)
                    if !mine { Spacer(minLength: 0) }
                }
            }
        }
    }

    private var finder: some View {
        let side: CGFloat = min(130 * s, size.width * 0.3)
        let mainW: CGFloat = max(0, size.width - side - 12 * s)
        let cellW: CGFloat = 74 * s
        let cols: Int = max(1, count(mainW, step: cellW))
        let rows: Int = max(1, count(size.height, step: 78 * s))
        return HStack(alignment: .top, spacing: 12 * s) {
            sidebar(width: side)
            VStack(alignment: .leading, spacing: 12 * s) {
                ForEach(0..<rows, id: \.self) { (r: Int) in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { (c: Int) in
                            VStack(spacing: 6 * s) {
                                Image(systemName: (r * cols + c) % 4 == 2 ? "doc.fill" : "folder.fill")
                                    .font(.system(size: 30 * s))
                                    .foregroundStyle((r * cols + c) % 4 == 2 ? Color.primary.opacity(0.3) : DemoApp.finder.color.opacity(0.85))
                                bar(ink, 40 * s, 6 * s)
                            }
                            .frame(width: cellW, height: 66 * s)
                        }
                    }
                }
            }
        }
    }

    private func sidebar(width: CGFloat) -> some View {
        let n: Int = count(size.height + 10 * s, step: 24 * s)
        let widths: [CGFloat] = [0.7, 0.5, 0.62, 0.45]
        return VStack(alignment: .leading, spacing: 10 * s) {
            ForEach(0..<n, id: \.self) { (i: Int) in
                HStack(spacing: 6 * s) {
                    Circle().fill(i == 0 ? app.color : Color.primary.opacity(0.12)).frame(width: 14 * s, height: 14 * s)
                    bar(ink, width * widths[i % widths.count], 8 * s)
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var list: some View {
        let side: CGFloat = min(150 * s, size.width * 0.36)
        let mainW: CGFloat = max(0, size.width - side - 12 * s)
        let lines: Int = count(size.height - 12 * s, step: 19 * s)
        let widths: [CGFloat] = [0.95, 0.82, 0.9, 0.7, 0.88, 0.6, 0.0, 0.92, 0.78, 0.85, 0.5]
        return HStack(alignment: .top, spacing: 12 * s) {
            sidebar(width: side)
            VStack(alignment: .leading, spacing: 10 * s) {
                bar(app.color.opacity(0.6), mainW * 0.55, 12 * s)
                ForEach(0..<lines, id: \.self) { (i: Int) in bar(ink, mainW * widths[i % widths.count], 9 * s) }
            }
        }
    }
}
#endif
