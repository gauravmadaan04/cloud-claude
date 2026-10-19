#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// The strip map: a small picture of every column, the part on screen, and which one is focused.
/// Hold ⌃⌥ to keep it up; click a tile to jump to it, drag a tile to reorder.
final class IndicatorModel: ObservableObject {
    struct Tile: Identifiable, Equatable {
        let id: UUID
        let index: Int
        let width: Double
        let windows: Int
        let icon: NSImage?
        let title: String
        let focused: Bool
        let pinned: Bool
        let tabbed: Bool
    }
    @Published var tiles: [Tile] = []
    /// Viewport position within the tiles, as fractions of the total width.
    @Published var viewport: (start: Double, length: Double) = (0, 1)
    @Published var interactive = false
    var key: StripKey?
}

final class StripIndicatorController {
    private let model = IndicatorModel()
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 76),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentViewController = NSHostingController(rootView: StripIndicatorView(model: model))
        return p
    }()
    private var hideWork: DispatchWorkItem?
    private var sticky = false

    func show(for key: StripKey?, sticky: Bool, duration: Double = 1.2, interactive: Bool = true) {
        guard WindowManager.shared.isRunning, let key else { return }
        model.key = key
        if sticky { self.sticky = true }
        model.interactive = interactive || self.sticky
        guard rebuild() else { return }
        panel.ignoresMouseEvents = !model.interactive
        panel.orderFrontRegardless()
        hideWork?.cancel()
        if !self.sticky {
            let w = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
        }
    }

    func endSticky() {
        sticky = false
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    func hide() { panel.orderOut(nil) }

    func refresh() {
        guard panel.isVisible else { return }
        if !rebuild() { hide() }
    }

    /// Rebuilds the model from the window manager. Returns false if there's nothing to show.
    @discardableResult
    private func rebuild() -> Bool {
        let wm = WindowManager.shared
        guard let key = model.key, let s = wm.strips[key], !s.isEmpty, let r = wm.layouts[key],
              let d = wm.display(uuid: key.display) else { return false }
        var tiles: [IndicatorModel.Tile] = []
        for (i, c) in s.columns.enumerated() {
            let wid = c.activeWindow ?? 0
            let w = wm.windows[wid]
            tiles.append(.init(id: c.id, index: i, width: r.columnRects.indices.contains(i) ? r.columnRects[i].w : 400,
                               windows: c.windows.count, icon: w.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon },
                               title: w?.title.isEmpty == false ? w!.title : (w?.appName ?? ""), focused: s.focused == i,
                               pinned: c.pin != nil, tabbed: c.mode == .tabbed))
        }
        model.tiles = tiles
        // Viewport: the scrolling part of the strip that is on screen.
        let gap = SettingsStore.shared.config.innerGap
        let total = tiles.reduce(0) { $0 + $1.width + gap }
        if total > 0, let first = r.columnRects.first {
            let stripLeft = r.columnRects.map(\.minX).min() ?? first.minX
            let start = (d.frame.minX - stripLeft) / total
            model.viewport = (max(0, start), min(1, d.frame.w / total))
        }
        // Size and place the panel.
        let maxW = d.visible.w * 0.7
        let scale = min(0.09, maxW / max(1, total))
        let width = min(maxW, max(160, total * scale)) + 24
        let height = 76.0
        let pos = SettingsStore.shared.config.indicatorPosition
        let y = pos == .bottom ? d.visible.maxY - height - 18 : d.visible.y + 14
        let frame = Rect(x: d.visible.midX - width / 2, y: y, w: width, h: height)
        panel.setFrame(Displays.toNS(frame), display: true)
        return true
    }
}

/// Pixel geometry for the strip map, worked out outside the view builder.
struct IndicatorGeometry {
    let inner: CGFloat
    let scale: CGFloat
    let tileHeight: CGFloat
    let viewportX: CGFloat
    let viewportW: CGFloat
    let viewportH: CGFloat

    init(size: CGSize, model: IndicatorModel, gap: CGFloat) {
        inner = size.width - 24
        var total: Double = 0
        for t in model.tiles { total += t.width }
        let gaps: CGFloat = gap * CGFloat(max(0, model.tiles.count - 1))
        let usable: CGFloat = max(1, inner - gaps)
        scale = usable / CGFloat(max(1, total))
        tileHeight = size.height - 26
        viewportX = 12 + CGFloat(model.viewport.start) * inner
        viewportW = max(20, CGFloat(model.viewport.length) * inner)
        viewportH = size.height - 14
    }

    func width(_ t: IndicatorModel.Tile) -> CGFloat { max(18, CGFloat(t.width) * scale) }
}

struct StripIndicatorView: View {
    @ObservedObject var model: IndicatorModel
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0
    private let gap: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            content(IndicatorGeometry(size: geo.size, model: model, gap: gap))
        }
    }

    private func content(_ g: IndicatorGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1))
            // The part of the strip on screen.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: g.viewportW, height: g.viewportH)
                .offset(x: g.viewportX, y: 7)
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: model.viewport.start)
            HStack(spacing: gap) {
                ForEach(model.tiles) { tile in
                    tileCell(tile, g)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
        }
    }

    private func tileCell(_ tile: IndicatorModel.Tile, _ g: IndicatorGeometry) -> some View {
        let offset: CGFloat = dragging == tile.id ? dragOffset : 0
        return tileView(tile)
            .frame(width: g.width(tile), height: g.tileHeight)
            .offset(x: offset)
            .zIndex(dragging == tile.id ? 1 : 0)
            .gesture(dragGesture(tile, g), including: model.interactive ? GestureMask.all : GestureMask.none)
            .onTapGesture {
                guard model.interactive, let key = model.key else { return }
                WindowManager.shared.focusColumn(in: key, index: tile.index)
            }
            .help(tile.title)
    }

    @ViewBuilder
    private func tileView(_ t: IndicatorModel.Tile) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(t.focused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.13))
            if let icon = t.icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 26, height: 26)
                    .shadow(radius: 1)
            }
            VStack {
                HStack(spacing: 2) {
                    if t.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    if t.tabbed { Image(systemName: "rectangle.stack").font(.system(size: 8)) }
                    Spacer()
                    if t.windows > 1 { Text("\(t.windows)").font(.system(size: 9, weight: .bold)) }
                }
                Spacer()
            }
            .padding(4)
            .foregroundColor(t.focused ? Color.white : Color.secondary)
        }
    }

    private func dragGesture(_ tile: IndicatorModel.Tile, _ g: IndicatorGeometry) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { (v: DragGesture.Value) in
                dragging = tile.id
                dragOffset = v.translation.width
            }
            .onEnded { (v: DragGesture.Value) in
                defer { dragging = nil; dragOffset = 0 }
                guard let key = model.key else { return }
                // Find the insertion point from the dragged tile's new centre.
                var x: CGFloat = 0
                var centers: [CGFloat] = []
                for t in model.tiles {
                    let w = g.width(t)
                    centers.append(x + w / 2)
                    x += w + gap
                }
                guard centers.indices.contains(tile.index) else { return }
                let c = centers[tile.index] + v.translation.width
                var to = 0
                for (i, cx) in centers.enumerated() where i != tile.index && c > cx { to = i + 1 }
                WindowManager.shared.moveColumn(in: key, from: tile.index, to: to)
            }
    }
}
#endif
