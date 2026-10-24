#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// Tab View: hold ⌥ and press ⇥ to see every window where it sits, screen by screen, and switch to one.
final class TabViewController {
    private var panel: KeyPanel?
    let model = TabViewModel()
    private var poll: Timer?

    var isOpen: Bool { panel?.isVisible == true }

    /// ⌥⇥ opens it; pressed again while open, it moves the selection.
    func trigger(forward: Bool) {
        if isOpen {
            model.step(forward ? 1 : -1)
            return
        }
        // Opened from the keyboard it switches when ⌥ comes up; otherwise it stays until you pick.
        open(forward: forward, sticky: !NSEvent.modifierFlags.contains(.option))
    }

    func open(forward: Bool, sticky: Bool) {
        close()
        model.load(forward: forward)
        guard !model.screens.isEmpty else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        model.maxWidth = vf.width - 120
        let host = NSHostingView(rootView: TabSwitcherView(model: model) { [weak self] wid in self?.commit(wid) })
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = host
        p.onEscape = { [weak self] in self?.close() }
        p.onKey = { [weak self] code, flags in self?.key(code, flags) ?? false }
        p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2))
        p.orderFrontRegardless()
        if sticky { p.makeKey() }
        panel = p
        let opt: Modifiers = [.option]
        HotkeyCenter.shared.registerTransient([
            (KeyCombo(keyCode: KeyCode.leftArrow, modifiers: opt), { [weak self] in self?.model.move(.left) }),
            (KeyCombo(keyCode: KeyCode.rightArrow, modifiers: opt), { [weak self] in self?.model.move(.right) }),
            (KeyCombo(keyCode: KeyCode.upArrow, modifiers: opt), { [weak self] in self?.model.move(.up) }),
            (KeyCombo(keyCode: KeyCode.downArrow, modifiers: opt), { [weak self] in self?.model.move(.down) }),
            (KeyCombo(keyCode: KeyCode.escape, modifiers: opt), { [weak self] in self?.close() }),
            (KeyCombo(keyCode: KeyCode.returnKey, modifiers: opt), { [weak self] in self?.commit(nil) }),
        ])
        if !sticky {
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                if !NSEvent.modifierFlags.contains(.option) { self?.commit(nil) }
            }
            RunLoop.main.add(t, forMode: .common)
            poll = t
        }
    }

    /// Keys while it's open in sticky mode.
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        switch code {
        case 123: model.move(.left)
        case 124: model.move(.right)
        case 125: model.move(.down)
        case 126: model.move(.up)
        case 48: model.step(flags.contains(.shift) ? -1 : 1)
        case 36, 76: commit(nil)
        default: return false
        }
        return true
    }

    func commit(_ wid: WindowID?) {
        let target = wid ?? model.selected
        close()
        if let target { WindowManager.shared.focus(window: target) }
    }

    func close() {
        poll?.invalidate()
        poll = nil
        HotkeyCenter.shared.clearTransient()
        panel?.orderOut(nil)
        panel = nil
    }
}

final class TabViewModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: WindowID
        let app: String
        let title: String
        let pid: pid_t
        let frame: Rect
        let behind: Bool
    }

    struct Screen: Identifiable {
        let id: String
        let name: String
        let frame: Rect
        let items: [Item]
        let minimized: [Item]
    }

    @Published var screens: [Screen] = []
    @Published var selected: WindowID?
    var maxWidth: CGFloat = 1300
    private var order: [WindowID] = []

    var allItems: [Item] { screens.flatMap { $0.items + $0.minimized } }

    func load(forward: Bool) {
        let wm = WindowManager.shared
        let onScreen = WindowServer.all(onScreenOnly: true)
        let sorted = wm.displays.sorted { ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y) }
        var waiting = Set<WindowID>()
        for b in wm.boards.values { for t in b.tiles { waiting.formUnion(t.waiting) } }
        screens = sorted.map { (d: Display) -> Screen in
            var items: [Item] = [], minimized: [Item] = []
            for w in wm.windows.values.sorted(by: { $0.seq < $1.seq }) {
                if w.element.isMinimized {
                    guard let f = w.lastFrame, wm.display(for: f)?.uuid == d.uuid else { continue }
                    minimized.append(Item(id: w.id, app: w.appName, title: w.title, pid: w.pid, frame: f, behind: false))
                } else if onScreen[w.id] != nil, let f = wm.targetFrame(for: w.id) ?? w.element.frame, wm.display(for: f)?.uuid == d.uuid {
                    items.append(Item(id: w.id, app: w.appName, title: w.title, pid: w.pid, frame: f, behind: waiting.contains(w.id)))
                }
            }
            return Screen(id: d.uuid, name: d.name, frame: d.frame, items: items, minimized: minimized)
        }
        .filter { !$0.items.isEmpty || !$0.minimized.isEmpty || sorted.count == 1 }
        let present = Set(allItems.map(\.id))
        order = wm.recentWindows.filter { present.contains($0) }
        for it in allItems where !order.contains(it.id) { order.append(it.id) }
        if order.isEmpty { selected = nil; return }
        // It starts on the window used before this one, so a quick ⌥⇥ switches back.
        selected = forward ? (order.count > 1 ? order[1] : order[0]) : order[order.count - 1]
    }

    func step(_ s: Int) {
        guard !order.isEmpty else { return }
        let i = selected.flatMap { order.firstIndex(of: $0) } ?? 0
        selected = order[((i + s) % order.count + order.count) % order.count]
    }

    /// The nearest window in a direction, on any screen.
    func move(_ dir: Direction) {
        let items = screens.flatMap(\.items)
        guard let cur = items.first(where: { $0.id == selected }) ?? items.first else { return }
        let c = cur.frame.center
        let candidates = items.filter { it in
            let p = it.frame.center
            switch dir {
            case .left: return p.x < c.x - 1
            case .right: return p.x > c.x + 1
            case .up: return p.y < c.y - 1
            case .down: return p.y > c.y + 1
            }
        }
        func cost(_ it: Item) -> Double {
            let p = it.frame.center
            let along = dir == .left || dir == .right ? abs(p.x - c.x) : abs(p.y - c.y)
            let across = dir == .left || dir == .right ? abs(p.y - c.y) : abs(p.x - c.x)
            return along + across * 2
        }
        if let best = candidates.min(by: { cost($0) < cost($1) }) { selected = best.id }
    }
}

struct TabSwitcherView: View {
    @ObservedObject var model: TabViewModel
    let pick: (WindowID) -> Void

    private let screenHeight: CGFloat = 230

    var body: some View {
        let natural = model.screens.reduce(CGFloat(0)) { $0 + screenHeight * CGFloat($1.frame.w / max(1, $1.frame.h)) + 20 }
        let k = min(1, model.maxWidth / max(1, natural))
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle").foregroundStyle(Brand.violet)
                Text("Windows").font(.system(size: 13, weight: .bold))
                Spacer()
                if let it = model.allItems.first(where: { $0.id == model.selected }) {
                    Text(it.title.isEmpty ? it.app : "\(it.app) — \(it.title)").font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            HStack(alignment: .top, spacing: 20 * k) {
                ForEach(model.screens) { s in screenView(s, height: screenHeight * k) }
            }
            Text("Release ⌥ to switch  ·  ⇥ next  ·  arrows move  ·  esc cancels")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(18)
        .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(20)
        .fixedSize()
    }

    private func screenView(_ s: TabViewModel.Screen, height: CGFloat) -> some View {
        let width = height * CGFloat(s.frame.w / max(1, s.frame.h))
        let k = height / CGFloat(max(1, s.frame.h))
        return VStack(alignment: .leading, spacing: 8) {
            Text(s.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.25))
                ForEach(s.items.sorted { ($0.behind ? 0 : 1) < ($1.behind ? 0 : 1) }) { it in
                    tile(it, selected: it.id == model.selected)
                        .frame(width: max(30, CGFloat(it.frame.w) * k - 4), height: max(24, CGFloat(it.frame.h) * k - 4))
                        .offset(x: CGFloat(it.frame.x - s.frame.x) * k + 2 + (it.behind ? 6 : 0),
                                y: CGFloat(it.frame.y - s.frame.y) * k + 2 - (it.behind ? 6 : 0))
                        .zIndex(it.id == model.selected ? 3 : (it.behind ? 0 : 1))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !s.minimized.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "dock.arrow.down.rectangle").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(s.minimized) { it in
                        chip(it, selected: it.id == model.selected)
                    }
                }
            }
        }
    }

    private func tile(_ it: TabViewModel.Item, selected: Bool) -> some View {
        VStack(spacing: 4) {
            icon(it.pid).frame(width: 34, height: 34)
            Text(it.app).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            if !it.title.isEmpty {
                Text(it.title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(it.behind ? 0.55 : 0.92)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(selected ? Brand.violet : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1))
        .scaleEffect(selected ? 1.03 : 1)
        .animation(Brand.snappy, value: selected)
        .contentShape(Rectangle())
        .onTapGesture { pick(it.id) }
    }

    private func chip(_ it: TabViewModel.Item, selected: Bool) -> some View {
        HStack(spacing: 5) {
            icon(it.pid).frame(width: 16, height: 16)
            Text(it.app).font(.system(size: 11)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(selected ? Brand.violet.opacity(0.35) : Color.primary.opacity(0.08)))
        .onTapGesture { pick(it.id) }
    }

    private func icon(_ pid: pid_t) -> some View {
        Group {
            if let img = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: img).resizable()
            } else {
                Image(systemName: "macwindow").resizable().foregroundStyle(.secondary)
            }
        }
    }
}
#endif
