#if os(macOS)
import AppKit
import RibbonCore

/// Activate windows on hover: the tiled window under a resting pointer becomes the one in use.
final class HoverFocus {
    static let shared = HoverFocus()
    private var monitor: Any?
    private var work: DispatchWorkItem?
    private var last: WindowID?

    func apply(_ c: Config) {
        if c.hoverFocus && c.tilingEnabled { install() } else { remove() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.moved() }
    }

    private func remove() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        work?.cancel()
    }

    private func moved() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let wm = WindowManager.shared
        let target = wm.tiledWindow(at: Displays.mouseLocation)
        guard target != last else { return }
        last = target
        work?.cancel()
        guard let target, target != wm.focusedWindowID else { return }
        let w = DispatchWorkItem { [weak self] in
            // Only if the pointer is still resting on it and nothing covers it there.
            guard self?.last == target, NSEvent.pressedMouseButtons == 0,
                  WindowServer.topWindow(at: Displays.mouseLocation) == target else { return }
            wm.focusOS(target)
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }
}

/// Mouse drags posted by Ribbon itself, for the end-to-end tests of ⌘-drag swapping and edge resizing.
enum SyntheticDrag {
    static func run(from a: CGPoint, to b: CGPoint, flags: CGEventFlags) {
        let wm = WindowManager.shared
        let src = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, _ p: CGPoint) {
            let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, a)
        let steps = 24
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            wm.simulatedDrag = true
            post(.leftMouseDown, a)
            for i in 1...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(i) * 0.03) {
                    let t = CGFloat(i) / CGFloat(steps)
                    post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(steps) * 0.03 + 0.25) {
                post(.leftMouseUp, b)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    wm.simulatedDrag = false
                    if wm.drag != nil { wm.finishDrag(flags: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))) }
                }
            }
        }
    }
}
#endif
