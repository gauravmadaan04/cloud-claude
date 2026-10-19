import XCTest
@testable import RibbonCore

final class LayoutTests: XCTestCase {
    // A 1440x900 display with a 25pt menu bar.
    let screen = Rect(x: 0, y: 0, w: 1440, h: 900)
    let area = Rect(x: 0, y: 25, w: 1440, h: 875)
    var params: LayoutParams { LayoutParams(screen: screen, area: area, innerGap: 10, outerGap: 10) }

    func strip(_ n: Int, width: Double = 0.5) -> Strip {
        var s = Strip()
        for i in 1...n { s.insert(WindowID(i), width: width, at: .end, focus: false) }
        s.focused = 0
        return s
    }

    func testTwoHalvesFillTheWorkingWidth() {
        let working = 1420.0
        let a = Layout.pixelWidth(0.5, working: working, gap: 10)
        XCTAssertEqual(a * 2 + 10, working, accuracy: 0.001)
        let t = Layout.pixelWidth(1.0 / 3, working: working, gap: 10)
        XCTAssertEqual(t * 3 + 20, working, accuracy: 0.001)
        XCTAssertEqual(Layout.fraction(forPixelWidth: a, working: working, gap: 10), 0.5, accuracy: 0.0001)
    }

    func testColumnsSitSideBySideAndOverflowParks() {
        var s = strip(3)
        s.scroll = Layout.scrollToReveal(s, params)
        let r = Layout.compute(s, params)
        XCTAssertEqual(r.placements.count, 3)
        let f1 = r.placement(for: 1)!.frame, f2 = r.placement(for: 2)!.frame, f3 = r.placement(for: 3)!.frame
        XCTAssertEqual(f1.x, 10)
        XCTAssertEqual(f1.y, 35)
        XCTAssertEqual(f1.h, 855)
        XCTAssertEqual(f2.x, f1.maxX + 10)
        XCTAssertEqual(f2.maxX, 1430)
        XCTAssertEqual(r.placement(for: 1)!.visibility, .visible)
        XCTAssertEqual(r.placement(for: 2)!.visibility, .visible)
        XCTAssertEqual(r.placement(for: 3)!.visibility, .hidden(.right))
        XCTAssertEqual(f3.x, f2.maxX + 10)
    }

    func testFocusRightScrollsJustEnough() {
        var s = strip(3)
        s.focusRight(); s.focusRight()
        s.scroll = Layout.scrollToReveal(s, params)
        let r = Layout.compute(s, params)
        let f3 = r.placement(for: 3)!
        XCTAssertEqual(f3.visibility, .visible)
        XCTAssertEqual(f3.frame.maxX, 1430)
        XCTAssertEqual(r.placement(for: 1)!.visibility, .hidden(.left))
    }

    func testAlwaysCenter() {
        var p = params
        p.centerMode = .always
        var s = strip(4, width: 1.0 / 3)
        s.focusColumn(2)
        s.scroll = Layout.scrollToReveal(s, p)
        let f = Layout.compute(s, p).placement(for: 3)!.frame
        XCTAssertEqual(f.midX, 720, accuracy: 1)
    }

    func testCenterOnOverflowKeepsBothWhenTheyFit() {
        var p = params
        p.centerMode = .onOverflow
        var s = strip(4, width: 0.5)
        s.focusColumn(1)
        s.scroll = Layout.scrollToReveal(s, p)
        s.focusColumn(2)
        s.scroll = Layout.scrollToReveal(s, p)
        let r = Layout.compute(s, p)
        XCTAssertEqual(r.placement(for: 2)!.visibility, .visible)
        XCTAssertEqual(r.placement(for: 3)!.visibility, .visible)
        // A full-width column can't share the screen, so it gets centred.
        s.columns[3].width = 1.0
        s.focusColumn(3)
        s.scroll = Layout.scrollToReveal(s, p)
        let f = Layout.compute(s, p).placement(for: 4)!.frame
        XCTAssertEqual(f.midX, 720, accuracy: 1)
    }

    func testSparseStripCanBeCentred() {
        var p = params
        p.sparse = .center
        var s = strip(1)
        s.scroll = Layout.scrollToReveal(s, p)
        let f = Layout.compute(s, p).placement(for: 1)!.frame
        XCTAssertEqual(f.midX, 720, accuracy: 1)
    }

    func testStackHeightsAndTabs() {
        var s = strip(2)
        s.focusColumn(1)
        XCTAssertTrue(s.consume(into: .left))
        XCTAssertEqual(s.columns.count, 1)
        XCTAssertEqual(s.columns[0].windows, [1, 2])
        XCTAssertEqual(s.focusedWindow, 2)
        var r = Layout.compute(s, params)
        let a = r.placement(for: 1)!.frame, b = r.placement(for: 2)!.frame
        XCTAssertEqual(a.y, 35)
        XCTAssertEqual(b.y, a.maxY + 10)
        XCTAssertEqual(b.maxY, 890)
        XCTAssertTrue(s.adjustHeight(by: 0.1))
        XCTAssertEqual(s.columns[0].weights[1], 0.6, accuracy: 0.0001)
        XCTAssertTrue(s.toggleTabbed())
        r = Layout.compute(s, params)
        XCTAssertEqual(r.tabBars.count, 1)
        XCTAssertEqual(r.placement(for: 2)!.visibility, .visible)
        if case .hidden = r.placement(for: 1)!.visibility {} else { XCTFail("inactive tab should be hidden") }
        XCTAssertEqual(r.placement(for: 2)!.frame.y, 35 + 28)
        XCTAssertTrue(s.focusVertical(1)) // wraps to the first tab
        XCTAssertEqual(s.focusedWindow, 1)
        XCTAssertTrue(s.expel(to: .right))
        XCTAssertEqual(s.columns.map(\.windows), [[2], [1]])
        XCTAssertEqual(s.focused, 1)
    }

    func testPinnedColumnsHugTheEdges() {
        var s = strip(4, width: 1.0 / 3)
        s.focusColumn(2)
        XCTAssertTrue(s.togglePin(.left))
        XCTAssertEqual(s.columns.first?.windows, [3])
        XCTAssertEqual(s.columns.first?.pin, .left)
        s.scroll = Layout.scrollToReveal(s, params)
        let r = Layout.compute(s, params)
        XCTAssertEqual(r.placement(for: 3)!.frame.x, 10)
        XCTAssertEqual(r.viewport.x, 10 + Layout.pixelWidth(1.0 / 3, working: 1420, gap: 10).rounded() + 10, accuracy: 1)
        // Unpin puts it back at the start of the scrolling columns.
        s.focusColumn(0)
        XCTAssertTrue(s.togglePin(.left))
        XCTAssertNil(s.columns[0].pin)
        s.focusColumn(3)
        XCTAssertTrue(s.togglePin(.right))
        XCTAssertEqual(s.columns.last?.pin, .right)
        let r2 = Layout.compute(s, params)
        XCTAssertEqual(r2.placement(for: s.columns.last!.windows[0])!.frame.maxX, 1430, accuracy: 1)
    }

    func testMinWidthFromStubbornApps() {
        let s = strip(1, width: 0.25)
        let r = Layout.compute(s, params, constraints: [1: WindowConstraints(minWidth: 600)])
        XCTAssertEqual(r.placement(for: 1)!.frame.w, 600)
    }

    func testKeepOriginalHeight() {
        var p = params
        p.keepOriginalHeight = true
        let s = strip(1)
        let r = Layout.compute(s, p, constraints: [1: WindowConstraints(originalHeight: 500)])
        XCTAssertEqual(r.placement(for: 1)!.frame.h, 500)
        XCTAssertEqual(r.placement(for: 1)!.frame.y, 35)
    }

    func testInsertionIndexForDrops() {
        let s = strip(3, width: 1.0 / 3)
        let r = Layout.compute(s, params)
        XCTAssertEqual(Layout.insertionIndex(atScreenX: 5, in: r, excluding: 2), 0)
        XCTAssertEqual(Layout.insertionIndex(atScreenX: r.columnRects[0].maxX - 5, in: r, excluding: 2), 1)
        XCTAssertEqual(Layout.column(atScreenX: r.columnRects[1].midX, in: r), 1)
    }
}

final class StripTests: XCTestCase {
    func testInsertAfterFocusedAndRemoveFocusesNeighbour() {
        var s = Strip()
        s.insert(1, width: 0.5, focus: true)
        s.insert(2, width: 0.5, focus: true)
        s.insert(3, width: 0.5, focus: true)
        XCTAssertEqual(s.allWindows, [1, 2, 3])
        s.focusColumn(0)
        s.insert(4, width: 0.5, focus: false)
        XCTAssertEqual(s.allWindows, [1, 4, 2, 3])
        XCTAssertEqual(s.focusedWindow, 1)
        s.focusColumn(2)
        s.remove(2)
        XCTAssertEqual(s.allWindows, [1, 4, 3])
        XCTAssertEqual(s.focusedWindow, 1, "falls back to the previously focused window")
        s.remove(1); s.remove(4); s.remove(3)
        XCTAssertNil(s.focused)
        XCTAssertTrue(s.isEmpty)
    }

    func testMoveColumns() {
        var s = Strip()
        for i in 1...4 { s.insert(WindowID(i), width: 0.5, at: .end, focus: false) }
        s.focusColumn(1)
        XCTAssertTrue(s.moveColumn(1))
        XCTAssertEqual(s.allWindows, [1, 3, 2, 4])
        XCTAssertEqual(s.focusedWindow, 2)
        XCTAssertTrue(s.moveColumnToEdge(last: false))
        XCTAssertEqual(s.allWindows, [2, 1, 3, 4])
        XCTAssertFalse(s.moveColumn(-1))
        XCTAssertTrue(s.moveColumn(from: 0, to: 4))
        XCTAssertEqual(s.allWindows, [1, 3, 4, 2])
        XCTAssertEqual(s.focusedWindow, 2)
        XCTAssertTrue(s.moveColumn(from: 3, to: 1))
        XCTAssertEqual(s.allWindows, [1, 2, 3, 4])
    }

    func testWidths() {
        var s = Strip()
        s.insert(1, width: 0.5, focus: true)
        let presets = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75]
        s.cycleWidth(presets: presets)
        XCTAssertEqual(s.columns[0].width, 2.0 / 3, accuracy: 0.0001)
        s.cycleWidth(presets: presets); s.cycleWidth(presets: presets)
        XCTAssertEqual(s.columns[0].width, 0.25, accuracy: 0.0001)
        s.cycleWidth(presets: presets, forward: false)
        XCTAssertEqual(s.columns[0].width, 0.75, accuracy: 0.0001)
        s.toggleFullWidth()
        XCTAssertEqual(s.columns[0].width, 1.0)
        s.toggleFullWidth()
        XCTAssertEqual(s.columns[0].width, 0.75, accuracy: 0.0001)
        s.adjustWidth(by: 0.1)
        XCTAssertEqual(s.columns[0].width, 0.85, accuracy: 0.0001)
        s.adjustWidth(by: 0.5)
        XCTAssertEqual(s.columns[0].width, 1.0)
    }

    func testFocusBackAndVertical() {
        var s = Strip()
        for i in 1...3 { s.insert(WindowID(i), width: 0.5, at: .end, focus: false) }
        s.focusColumn(0)
        s.focusColumn(2)
        XCTAssertEqual(s.previousFocusedWindow, 1)
        XCTAssertFalse(s.focusVertical(1))
        s.focusColumn(1)
        s.consume(into: .right)
        XCTAssertEqual(s.columns.count, 2)
        XCTAssertEqual(s.columns[1].windows, [3, 2])
        XCTAssertTrue(s.moveWindowVertical(-1))
        XCTAssertEqual(s.columns[1].windows, [2, 3])
        XCTAssertTrue(s.focusVertical(1))
        XCTAssertEqual(s.focusedWindow, 3)
    }

    func testReplaceAndPrune() {
        var s = Strip()
        for i in 1...3 { s.insert(WindowID(i), width: 0.5, at: .end, focus: false) }
        XCTAssertTrue(s.replace(2, with: 20))
        XCTAssertEqual(s.allWindows, [1, 20, 3])
        XCTAssertEqual(s.prune(keeping: [1, 3]), [20])
        XCTAssertEqual(s.allWindows, [1, 3])
    }

    func testCodableRoundTrip() throws {
        var s = Strip()
        for i in 1...3 { s.insert(WindowID(i), width: 0.5, at: .end, focus: false) }
        s.focusColumn(1)
        s.togglePin(.right)
        let d = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Strip.self, from: d)
        XCTAssertEqual(back, s)
    }
}

final class MotionTests: XCTestCase {
    func testSpringSettles() {
        var sp = Spring(value: 0, target: 1000, response: 0.25)
        var t = 0.0
        while !sp.isSettled && t < 2 { sp.step(1.0 / 60); t += 1.0 / 60 }
        XCTAssertEqual(sp.value, 1000)
        XCTAssertLessThan(t, 0.6)
    }

    func testSpringNeverOvershootsMuch() {
        var sp = Spring(value: 0, target: 100, response: 0.3)
        var peak = 0.0
        for _ in 0..<120 { sp.step(1.0 / 120); peak = max(peak, sp.value) }
        XCTAssertLessThanOrEqual(peak, 100.5)
    }

    func testParkingAvoidsNeighbourDisplay() {
        let main = Rect(x: 0, y: 0, w: 1440, h: 900)
        let right = Rect(x: 1440, y: 0, w: 1920, h: 1080)
        let size = Size(w: 700, h: 800)
        let alone = Parking.frame(size: size, side: .right, screen: main, others: [], y: 35)
        XCTAssertEqual(alone.x, 1439)
        XCTAssertEqual(alone.y, 35)
        let withNeighbour = Parking.frame(size: size, side: .right, screen: main, others: [right], y: 35)
        XCTAssertEqual(withNeighbour.intersectionArea(right), 0)
        XCTAssertGreaterThan(withNeighbour.intersectionArea(main), 0)
        let left = Parking.frame(size: size, side: .left, screen: main, others: [], y: 35)
        XCTAssertEqual(left.maxX, 1)
    }

    func testFrameAnimationAppliesSizeImmediately() {
        var a = FrameAnimation(from: Rect(x: 0, y: 0, w: 100, h: 100), to: Rect(x: 500, y: 0, w: 300, h: 100), response: 0.2)
        XCTAssertEqual(a.frame.w, 300)
        a.step(0.05)
        XCTAssertGreaterThan(a.frame.x, 0)
        XCTAssertLessThan(a.frame.x, 500)
        for _ in 0..<60 { a.step(1.0 / 60) }
        XCTAssertTrue(a.isSettled)
        XCTAssertEqual(a.frame.x, 500)
    }
}

final class ConfigTests: XCTestCase {
    func testDefaultBindingsHaveNoClashes() {
        XCTAssertTrue(Config().conflicts().isEmpty, "\(Config().conflicts())")
        XCTAssertEqual(Config().effectiveBindings()[KeyCombo(keyCode: KeyCode.rightArrow, modifiers: [.control, .option])], .focusRight)
    }

    func testTolerantDecoding() {
        let json = #"{"innerGap": 4, "swipeFingers": "three", "unknown": 1, "centerMode": "always"}"#
        let c = Config.decode(Data(json.utf8))
        XCTAssertEqual(c.innerGap, 4)
        XCTAssertEqual(c.swipeFingers, 3, "bad value falls back to the default")
        XCTAssertEqual(c.centerMode, .always)
        XCTAssertEqual(Config.decode(Data("garbage".utf8)), Config())
    }

    func testRoundTripAndSet() throws {
        var c = Config()
        c.bindings["focus-left"] = [KeyCombo(keyCode: KeyCode.a, modifiers: [.command, .shift])]
        let back = Config.decode(c.encoded())
        XCTAssertEqual(back, c)
        try c.set("innerGap", to: "0")
        XCTAssertEqual(c.innerGap, 0)
        try c.set("focusBorder", to: "true")
        XCTAssertTrue(c.focusBorder)
        try c.set("centerMode", to: "onOverflow")
        XCTAssertEqual(c.centerMode, .onOverflow)
        try c.set("borderColor", to: "#FF0000")
        XCTAssertEqual(c.borderColor, "#FF0000")
        XCTAssertThrowsError(try c.set("nope", to: "1"))
        XCTAssertThrowsError(try c.set("centerMode", to: "sideways"))
        XCTAssertEqual(c.value(of: "innerGap"), "0")
    }

    func testCommandParsing() {
        XCTAssertEqual(Command.parse("focus-left"), .focusLeft)
        XCTAssertEqual(Command.parse("focusLeft"), .focusLeft)
        XCTAssertEqual(Command.parse("FOCUS_LEFT"), .focusLeft)
        XCTAssertNil(Command.parse("explode"))
        XCTAssertEqual(KeyCombo(keyCode: KeyCode.r, modifiers: [.control, .option]).description, "⌃⌥R")
    }

    func testAppRules() {
        let c = Config()
        XCTAssertEqual(c.rule(for: "com.apple.SystemPreferences")?.behavior, .float)
        XCTAssertNil(c.rule(for: "com.apple.Safari"))
    }
}

final class SessionTests: XCTestCase {
    func testRestoreByIdThenByTitle() {
        var s = Strip()
        s.insert(10, width: 0.5, at: .end, focus: false)
        s.insert(11, width: 0.75, at: .end, focus: false)
        s.insert(12, width: 0.5, at: .end, focus: false)
        s.focusColumn(1)
        s.consume(into: .right)  // [10] [12, 11]
        let refs: [WindowID: SavedWindow] = [
            10: SavedWindow(id: 10, bundleID: "a", title: "Doc A"),
            11: SavedWindow(id: 11, bundleID: "b", title: "Doc B"),
            12: SavedWindow(id: 12, bundleID: "c", title: "Doc C"),
        ]
        let snap = StripSnapshot(displayUUID: "D", spaceID: 5, spaceIndex: 0, strip: s) { refs[$0] }
        // After a restart window 11 has a new number but the same app and title; 12 is gone.
        let live = [SavedWindow(id: 10, bundleID: "a", title: "Doc A"), SavedWindow(id: 99, bundleID: "b", title: "Doc B"),
                    SavedWindow(id: 50, bundleID: "z", title: "New")]
        var used = Set<WindowID>()
        let r = SessionRestore.restore(snap, live: live, used: &used)
        XCTAssertEqual(r.columns.map(\.windows), [[10], [99]])
        XCTAssertEqual(r.columns[1].width, 0.5, accuracy: 0.001)
        XCTAssertEqual(used, [10, 99])
        let session = SessionSnapshot(strips: [snap], floating: [])
        XCTAssertNotNil(SessionRestore.snapshot(in: session, displayUUID: "D", spaceID: 777, spaceIndex: 0))
        XCTAssertNil(SessionRestore.snapshot(in: session, displayUUID: "E", spaceID: 5, spaceIndex: 0))
    }
}

final class GestureTests: XCTestCase {
    func testThreeFingerSwipe() {
        var g = SwipeRecognizer(fingers: 3)
        var t = 0.0
        XCTAssertNil(g.feed(count: 1, x: 0.5, y: 0.5, time: t))
        XCTAssertNil(g.feed(count: 3, x: 0.5, y: 0.5, time: t))
        t += 0.01
        XCTAssertNil(g.feed(count: 3, x: 0.51, y: 0.5, time: t))
        t += 0.01
        guard case .began = g.feed(count: 3, x: 0.54, y: 0.5, time: t) else { return XCTFail("should begin") }
        t += 0.01
        XCTAssertEqual(g.feed(count: 3, x: 0.56, y: 0.5, time: t), .changed(dx: 0.56 - 0.54))
        t += 0.01
        guard case .ended(let v) = g.feed(count: 2, x: 0.5, y: 0.5, time: t) else { return XCTFail("should end") }
        XCTAssertGreaterThan(v, 0)
        XCTAssertFalse(g.isSwiping)
    }

    func testVerticalAndWrongFingerCountIgnored() {
        var g = SwipeRecognizer(fingers: 3)
        _ = g.feed(count: 3, x: 0.5, y: 0.5, time: 0)
        XCTAssertNil(g.feed(count: 3, x: 0.5, y: 0.6, time: 0.01))
        XCTAssertNil(g.feed(count: 3, x: 0.6, y: 0.6, time: 0.02), "vertical gestures are rejected")
        _ = g.feed(count: 0, x: 0, y: 0, time: 0.03)
        _ = g.feed(count: 4, x: 0.5, y: 0.5, time: 0.04)
        XCTAssertNil(g.feed(count: 4, x: 0.7, y: 0.5, time: 0.05))
    }

    func testSettleColumn() {
        let p = LayoutParams(screen: Rect(x: 0, y: 0, w: 1440, h: 900), area: Rect(x: 0, y: 25, w: 1440, h: 875))
        var s = Strip()
        for i in 1...5 { s.insert(WindowID(i), width: 0.5, at: .end, focus: false) }
        XCTAssertEqual(SwipeMath.settleColumn(s, p, projectedScroll: 0), 0)
        XCTAssertEqual(SwipeMath.settleColumn(s, p, projectedScroll: 1420), 2)
        XCTAssertLessThan(SwipeMath.points(forPadDelta: 0.1, viewportWidth: 1000, sensitivity: 1, natural: true), 0)
        XCTAssertEqual(SwipeMath.rubberBand(50, min: 0, max: 100), 50)
        XCTAssertLessThan(SwipeMath.rubberBand(200, min: 0, max: 100), 200)
    }
}

final class IPCTests: XCTestCase {
    func testURLParsing() {
        XCTAssertEqual(IPC.request(from: URL(string: "ribbon://focus-left")!), IPC.Request(cmd: "focus-left"))
        XCTAssertEqual(IPC.request(from: URL(string: "ribbon://command/cycle-width")!), IPC.Request(cmd: "cycle-width"))
        XCTAssertEqual(IPC.request(from: URL(string: "ribbon://run?cmd=focus-3")!), IPC.Request(cmd: "focus-3"))
        XCTAssertEqual(IPC.request(from: URL(string: "ribbon://focus-window/1234")!), IPC.Request(cmd: "focus-window", args: ["1234"]))
        XCTAssertNil(IPC.request(from: URL(string: "https://example.com")!))
    }

    func testRaycastScripts() {
        let s = RaycastScripts.scripts()
        XCTAssertEqual(s.count, Command.allCases.count)
        XCTAssertTrue(s[0].contents.contains("@raycast.schemaVersion 1"))
        XCTAssertTrue(s[0].contents.contains("open -g \"ribbon://"))
    }
}
