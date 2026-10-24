#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// The grip above the window in use (and above any stack). Rest the pointer on it for quick actions;
/// click a segment to show that window of the stack.
final class GripController {
    private var grips: [ScreenKeyTile: Grip] = [:]

    struct ScreenKeyTile: Hashable {
        let key: ScreenKey
        let tile: Int
    }

    private final class Grip {
        let panel: NSPanel
        let model = GripModel()
        let host: NSHostingView<GripView>
        var anchor: Rect = .zero

        init() {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary, .transient]
            panel.animationBehavior = .none
            host = NSHostingView(rootView: GripView(model: model))
            panel.contentView = host
        }
    }

    func refresh() {
        let wm = WindowManager.shared
        let c = SettingsStore.shared.config
        var keep = Set<ScreenKeyTile>()
        if c.quickActions, wm.isRunning, wm.drag == nil {
            for (key, b) in wm.boards where wm.isActive(key) && !wm.cleanSpace.contains(key.display) {
                guard let frames = wm.tileFrames[key], let d = wm.display(uuid: key.display) else { continue }
                for (i, t) in b.tiles.enumerated() where frames.indices.contains(i) {
                    let inUse = t.showing == wm.focusedWindowID
                    guard inUse || t.isStack else { continue }
                    if let z = b.zoomed, z != t.showing { continue }
                    let id = ScreenKeyTile(key: key, tile: i)
                    keep.insert(id)
                    let g = grips[id] ?? Grip()
                    grips[id] = g
                    let frame = b.zoomed == t.showing ? wm.area(for: d) : frames[i]
                    update(g, windows: t.windows, showing: t.showing, inUse: inUse, frame: frame, gap: c.spacing)
                }
            }
        }
        for (id, g) in grips where !keep.contains(id) {
            g.panel.orderOut(nil)
            grips[id] = nil
        }
    }

    private func update(_ g: Grip, windows: [WindowID], showing: WindowID, inUse: Bool, frame: Rect, gap: Double) {
        let wm = WindowManager.shared
        let m = g.model
        m.chips = windows.compactMap { wid in
            wm.windows[wid].map { GripModel.Chip(id: wid, app: $0.appName, title: $0.title, pid: $0.pid) }
        }
        m.showing = showing
        m.inUse = inUse
        m.multipleDisplays = wm.displays.count > 1
        m.color = Color(nsColor: NSColor(hex: SettingsStore.shared.config.highlightColor) ?? .systemPurple)
        m.onExpand = { [weak self, weak g] expanded in
            // After SwiftUI has laid out the new content.
            DispatchQueue.main.async {
                guard let self, let g else { return }
                self.place(g, expanded: expanded)
            }
        }
        g.anchor = frame
        place(g, expanded: m.expanded)
        if !g.panel.isVisible { g.panel.orderFrontRegardless() }
    }

    /// Collapsed, the grip sits in the gap above the window; expanded, the bar overlaps the title bar.
    private func place(_ g: Grip, expanded: Bool) {
        let size = g.host.fittingSize
        let f = g.anchor
        let topGap = 8.0
        let y = expanded ? f.minY - topGap : f.minY - topGap / 2 - Double(size.height) / 2
        let r = Rect(x: f.midX - Double(size.width) / 2, y: y, w: Double(size.width), h: Double(size.height))
        g.panel.setFrame(Displays.toNS(r), display: true)
    }
}

final class GripModel: ObservableObject {
    struct Chip: Identifiable, Equatable {
        let id: WindowID
        let app: String
        let title: String
        let pid: pid_t
    }

    @Published var chips: [Chip] = []
    @Published var showing: WindowID = 0
    @Published var inUse = false
    @Published var expanded = false
    @Published var multipleDisplays = false
    @Published var color: Color = Brand.violet
    var onExpand: ((Bool) -> Void)?
}

struct GripView: View {
    @ObservedObject var model: GripModel
    @State private var hoverWork: DispatchWorkItem?

    var body: some View {
        Group {
            if model.expanded { bar } else { grip }
        }
        .onHover { inside in hover(inside) }
        .fixedSize()
    }

    /// Segments, one per window in the tile; the one showing is filled.
    private var grip: some View {
        HStack(spacing: 3) {
            ForEach(model.chips) { chip in
                Capsule()
                    .fill(chip.id == model.showing ? (model.inUse ? model.color : Color.white.opacity(0.85)) : Color.white.opacity(0.35))
                    .frame(width: model.chips.count > 1 ? 16 : 44, height: 5)
                    .contentShape(Rectangle().inset(by: -4))
                    .onTapGesture { WindowManager.shared.focus(window: chip.id) }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .padding(2)
    }

    private var bar: some View {
        HStack(spacing: 4) {
            ForEach(model.chips) { chip in
                Button { WindowManager.shared.focus(window: chip.id) } label: {
                    appIcon(chip.pid).frame(width: 20, height: 20)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(chip.id == model.showing ? model.color.opacity(0.35) : Color.clear))
                }
                .buttonStyle(.plain)
                .help(chip.title.isEmpty ? chip.app : "\(chip.app): \(chip.title)")
            }
            Divider().frame(height: 18).padding(.horizontal, 2)
            action("crown.fill", "Make this the main window") { act(.makePrimary) }
            action("scope", "Focus: fill the screen") { act(.focusMode) }
            action("macwindow.on.rectangle", "Float") { act(.toggleFloat) }
            if model.multipleDisplays { action("display.2", "Send to the next display") { act(.nextDisplay) } }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .glassSurface(Capsule())
        .padding(4)
    }

    private func action(_ symbol: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func act(_ c: Command) {
        // Quick actions apply to the window showing in this tile.
        WindowManager.shared.focus(window: model.showing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { WindowManager.shared.perform(c) }
    }

    private func appIcon(_ pid: pid_t) -> some View {
        Group {
            if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.fill").resizable()
            }
        }
    }

    private func hover(_ inside: Bool) {
        hoverWork?.cancel()
        let w = DispatchWorkItem {
            guard model.expanded != inside else { return }
            withAnimation(Brand.snappy) { model.expanded = inside }
            model.onExpand?(inside)
        }
        hoverWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.25 : 0.4), execute: w)
    }
}
#endif
