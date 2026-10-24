import XCTest
@testable import RibbonCore

// A 1440x900 laptop screen: 25pt menu bar, 8pt spacing all round.
let area = Rect(x: 8, y: 33, w: 1424, h: 859)
let gap = 8.0

func board(_ n: Int, capacity: Int = 3) -> Board {
    var b = Board()
    for i in 1...n { b.add(WindowID(i), capacity: capacity, stackWhenFull: true) }
    return b
}

final class BoardTests: XCTestCase {
    func testWindowsGetTilesUntilFullThenStackOnTheOneInUse() {
        var b = board(3)
        XCTAssertEqual(b.showing, [1, 2, 3])
        b.setActive(1)
        XCTAssertEqual(b.add(4, capacity: 3, stackWhenFull: true), .stacked)
        XCTAssertEqual(b.tiles.count, 3)
        XCTAssertEqual(b.tiles[0].windows, [1, 4])
        XCTAssertEqual(b.tiles[0].showing, 4, "the new window sits on top")
        XCTAssertEqual(b.active, 4)
        XCTAssertEqual(b.add(5, capacity: 3, stackWhenFull: false), .full)
        XCTAssertFalse(b.contains(5))
        XCTAssertEqual(b.add(4, capacity: 3, stackWhenFull: true), .alreadyThere)
    }

    func testClosingReflowsAndPromotesTheNextPrimary() {
        var b = board(3)
        b.remove(1)
        XCTAssertEqual(b.showing, [2, 3], "the others fill the space in order")
        b.remove(3)
        XCTAssertEqual(b.showing, [2])
        XCTAssertFalse(b.remove(99))
    }

    func testClosingTheTopOfAStackBringsBackTheLastShown() {
        var b = board(1, capacity: 1)
        b.add(2, capacity: 1, stackWhenFull: true)
        b.add(3, capacity: 1, stackWhenFull: true)
        XCTAssertEqual(b.tiles[0].windows, [1, 2, 3])
        b.show(1)
        b.show(3)
        b.remove(3)
        XCTAssertEqual(b.tiles[0].showing, 1, "most recently shown comes forward")
        XCTAssertEqual(b.active, 1)
    }

    func testCycleThroughAStack() {
        var b = board(1, capacity: 1)
        b.add(2, capacity: 1, stackWhenFull: true)
        b.add(3, capacity: 1, stackWhenFull: true)
        XCTAssertEqual(b.tiles[0].showing, 3)
        XCTAssertTrue(b.cycle(tile: 0, 1))
        XCTAssertEqual(b.tiles[0].showing, 1)
        b.cycle(tile: 0, -1)
        XCTAssertEqual(b.tiles[0].showing, 3)
        XCTAssertFalse(board(2).tiles[0].isStack)
        var single = board(2)
        XCTAssertFalse(single.cycle(tile: 0, 1))
    }

    func testSwapAndMakePrimary() {
        var b = board(3)
        XCTAssertTrue(b.swap(0, 2))
        XCTAssertEqual(b.showing, [3, 2, 1])
        XCTAssertTrue(b.makePrimary(1))
        XCTAssertEqual(b.showing, [2, 3, 1])
        XCTAssertFalse(b.swap(1, 1))
        XCTAssertFalse(b.swap(0, 9))
    }

    func testSwapMovesOnlyTheShowingWindows() {
        var b = board(2, capacity: 2)
        b.setActive(1)
        b.add(3, capacity: 2, stackWhenFull: true)   // stacks on tile 0: [1, 3], showing 3
        b.swap(0, 1)
        XCTAssertEqual(b.tiles[0].windows, [1, 2])
        XCTAssertEqual(b.tiles[0].showing, 2)
        XCTAssertEqual(b.tiles[1].windows, [3])
    }

    func testFewerTilesMergeIntoTheLastAndMoreTilesFreeWaitingWindows() {
        var b = board(4, capacity: 4)
        b.setActive(2)
        XCTAssertTrue(b.fit(capacity: 2))
        XCTAssertEqual(b.tiles.count, 2)
        XCTAssertEqual(b.tiles[1].windows, [2, 3, 4])
        XCTAssertEqual(b.tiles[1].showing, 2, "the window in use stays on top")
        XCTAssertTrue(b.fit(capacity: 4))
        XCTAssertEqual(b.tiles.count, 4)
        XCTAssertEqual(Set(b.windows), [1, 2, 3, 4])
        XCTAssertFalse(b.fit(capacity: 4))
    }

    func testMoveOntoAnotherStack() {
        var b = board(3)
        XCTAssertTrue(b.move(3, toStackOf: 0))
        XCTAssertEqual(b.tiles.count, 2)
        XCTAssertEqual(b.tiles[0].windows, [1, 3])
        XCTAssertEqual(b.tiles[0].showing, 3)
        XCTAssertTrue(b.move(2, toStackOf: 0))
        XCTAssertEqual(b.tiles.count, 1)
    }

    func testRestoreToARememberedPlace() {
        var b = board(3)
        b.remove(2)
        XCTAssertEqual(b.restore(2, at: 1, capacity: 3, stackWhenFull: true), .newTile)
        XCTAssertEqual(b.showing, [1, 2, 3])
    }

    func testReplaceKeepsThePlace() {
        var b = board(3)
        b.setActive(2)
        b.replace(2, with: 9)
        XCTAssertEqual(b.showing, [1, 9, 3])
        XCTAssertEqual(b.active, 9)
    }

    func testFocusModeEndsWhenItsWindowGoes() {
        var b = board(2)
        b.zoomed = 2
        b.remove(2)
        XCTAssertNil(b.zoomed)
    }
}

final class LayoutTests: XCTestCase {
    func frames(_ n: Int, _ a: Arrangement = .grid, splits: Splits = Splits(), mins: [Size] = []) -> [Rect] {
        TileLayout.frames(count: n, a, area: area, gap: gap, splits: splits, mins: mins)
    }

    func testGridShapes() {
        XCTAssertEqual(frames(1), [area])
        let two = frames(2)
        XCTAssertEqual(two[0], Rect(x: 8, y: 33, w: 708, h: 859))
        XCTAssertEqual(two[1], Rect(x: 724, y: 33, w: 708, h: 859))
        let three = frames(3)
        XCTAssertEqual(three[0].h, 859, "the primary keeps the whole left side")
        XCTAssertEqual(three[1], Rect(x: 724, y: 33, w: 708, h: 425.5))
        XCTAssertEqual(three[2], Rect(x: 724, y: 466.5, w: 708, h: 425.5))
        let four = frames(4)
        XCTAssertEqual(four[0].y, 33)
        XCTAssertEqual(four[3].x, 8, "the fourth window takes the bottom of the primary's column")
        XCTAssertEqual(four[3].y, 466.5)
        XCTAssertEqual(four[1].minX, four[2].minX)
        for f in four { XCTAssertEqual(f.w, 708) }
    }

    func testColumnsAndRows() {
        let cols = frames(3, .columns)
        XCTAssertEqual(cols.map(\.h), [859, 859, 859])
        XCTAssertEqual(cols[0].w, (1424 - 16) / 3, accuracy: 0.001)
        XCTAssertEqual(cols[2].maxX, area.maxX, accuracy: 0.001)
        let rows = frames(2, .rows)
        XCTAssertEqual(rows[0].w, 1424)
        XCTAssertEqual(rows[1].maxY, area.maxY, accuracy: 0.001)
    }

    func testArrangementAndCapacity() {
        XCTAssertEqual(TileLayout.arrangement(.grid, area: area), .grid)
        XCTAssertEqual(TileLayout.arrangement(.grid, area: Rect(x: 0, y: 0, w: 1080, h: 1900)), .rows)
        XCTAssertEqual(TileLayout.capacity(requested: 4, .columns, area: area), 3, "a laptop fits three columns")
        XCTAssertEqual(TileLayout.capacity(requested: 4, .columns, area: Rect(x: 0, y: 0, w: 2544, h: 1400)), 4)
        XCTAssertEqual(TileLayout.capacity(requested: 4, .rows, area: area), 3)
        XCTAssertEqual(TileLayout.capacity(requested: 0, .grid, area: area), 1)
    }

    func testMinimumSizesMoveTheSplit() {
        let f = frames(2, mins: [Size(w: 0, h: 0), Size(w: 900, h: 0)])
        XCTAssertEqual(f[1].w, 900)
        XCTAssertEqual(f[0].w, 1424 - 8 - 900)
        XCTAssertTrue(TileLayout.fits(f, mins: [Size(w: 0, h: 0), Size(w: 900, h: 0)]))
        let tooBig = [Size(w: 1000, h: 0), Size(w: 1000, h: 0)]
        XCTAssertFalse(TileLayout.fits(frames(2, mins: tooBig), mins: tooBig))
        let rows = frames(3, .columns, mins: [Size(w: 600, h: 0)])
        XCTAssertEqual(rows[0].w, 600)
        XCTAssertEqual(rows[1].w, rows[2].w, accuracy: 0.001)
    }

    func testSplitSharesWhatIsLeft() {
        XCTAssertEqual(TileLayout.split(100, gap: 0, shares: [1, 1], mins: [70, 0]), [70, 30])
        XCTAssertEqual(TileLayout.split(100, gap: 10, shares: [1, 1], mins: []), [45, 45])
    }

    func testNeighbours() {
        let f = frames(4)
        XCTAssertEqual(TileLayout.neighbor(of: 0, .right, in: f), 1)
        XCTAssertEqual(TileLayout.neighbor(of: 0, .down, in: f), 3)
        XCTAssertEqual(TileLayout.neighbor(of: 2, .left, in: f), 3)
        XCTAssertEqual(TileLayout.neighbor(of: 2, .up, in: f), 1)
        XCTAssertNil(TileLayout.neighbor(of: 0, .left, in: f))
        let three = frames(3)
        XCTAssertEqual(TileLayout.neighbor(of: 0, .right, in: three), 1, "the top one when two line up")
        XCTAssertEqual(TileLayout.neighbor(of: 2, .left, in: three), 0)
    }

    func testGrowAndShrink() {
        let grown = TileLayout.resized(Splits(), tile: 0, by: 0.05, count: 2, .grid)
        XCTAssertEqual(grown?.x ?? 0, 0.55, accuracy: 0.0001)
        let shrunkRight = TileLayout.resized(Splits(), tile: 1, by: -0.05, count: 2, .grid)
        XCTAssertEqual(shrunkRight?.x ?? 0, 0.55, accuracy: 0.0001)
        let bottom = TileLayout.resized(Splits(), tile: 2, by: 0.1, count: 3, .grid)
        XCTAssertEqual(bottom?.rightY ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertNil(TileLayout.resized(Splits(), tile: 0, by: 0.1, count: 1, .grid), "one window can't grow")
        var maxed = Splits()
        maxed.x = 1 - TileLayout.minShare
        XCTAssertNil(TileLayout.resized(maxed, tile: 0, by: 0.05, count: 2, .grid))
        let col = TileLayout.resized(Splits(), tile: 1, by: 0.1, count: 3, .columns)!
        let w = col.weights(3)
        XCTAssertGreaterThan(w[1], w[0])
        XCTAssertEqual(w[0], w[2], accuracy: 0.0001)
        XCTAssertEqual(w.reduce(0, +), 3, accuracy: 0.0001)
    }

    func testDraggingAnEdgeSetsTheSplit() {
        let f = frames(2)
        var dragged = f[0]
        dragged.w += 100
        let s = TileLayout.splits(afterResizing: 0, from: f[0], to: dragged, count: 2, .grid, area: area, gap: gap, splits: Splits())
        let after = TileLayout.frames(count: 2, .grid, area: area, gap: gap, splits: s)
        XCTAssertEqual(after[0].maxX, dragged.maxX, accuracy: 0.5)
        XCTAssertEqual(after[1].minX, dragged.maxX + gap, accuracy: 0.5)

        // Dragging the left edge of the right window moves the same split.
        var right = f[1]
        right.x -= 50; right.w += 50
        let s2 = TileLayout.splits(afterResizing: 1, from: f[1], to: right, count: 2, .grid, area: area, gap: gap, splits: Splits())
        XCTAssertEqual(TileLayout.frames(count: 2, .grid, area: area, gap: gap, splits: s2)[1].minX, right.minX, accuracy: 0.5)

        // Screen edges don't move anything.
        var outer = f[0]
        outer.x += 30; outer.w -= 30
        XCTAssertEqual(TileLayout.splits(afterResizing: 0, from: f[0], to: outer, count: 2, .grid, area: area, gap: gap, splits: Splits()), Splits())

        let c = frames(3, .columns)
        var mid = c[1]
        mid.w += 120
        let s3 = TileLayout.splits(afterResizing: 1, from: c[1], to: mid, count: 3, .columns, area: area, gap: gap, splits: Splits())
        let after3 = TileLayout.frames(count: 3, .columns, area: area, gap: gap, splits: s3)
        XCTAssertEqual(after3[1].maxX, mid.maxX, accuracy: 0.5)
        XCTAssertEqual(after3[0].w, c[0].w, accuracy: 0.5, "only the neighbour gives up space")
    }
}

final class ScrollingTests: XCTestCase {
    func frames(_ widths: [Double], scroll: Double = 0) -> [Rect] {
        TileLayout.frames(count: widths.count, .scrolling, area: area, gap: gap, splits: Splits(), widths: widths, scroll: scroll)
    }

    func testColumnsRunPastTheScreen() {
        let f = frames([0.5, 0.5, 0.5])
        XCTAssertEqual(f[0].x, area.x)
        XCTAssertEqual(f[0].w + f[1].w + gap, area.w, accuracy: 0.001, "two halves fill the screen exactly")
        XCTAssertEqual(f[2].minX, f[1].maxX + gap, accuracy: 0.001)
        XCTAssertGreaterThan(f[2].maxX, area.maxX)
        XCTAssertEqual(TileLayout.visibility(f[0], area: area), .visible)
        XCTAssertEqual(TileLayout.visibility(f[2], area: area), .hidden(.right))
        XCTAssertEqual(TileLayout.arrangement(.scrolling, area: Rect(x: 0, y: 0, w: 1080, h: 1900)), .scrolling)
        XCTAssertEqual(TileLayout.capacity(requested: 3, .scrolling, area: area), 3)
        XCTAssertEqual(TileLayout.maxTiles(.scrolling, area: area), 99)
    }

    func testRevealScrollsJustEnough() {
        let f = frames([0.5, 0.5, 0.5, 0.5])
        let s = TileLayout.reveal(2, f, area: area, scroll: 0)
        XCTAssertEqual(f[2].maxX - s, area.maxX, accuracy: 0.001, "the third column's right edge meets the screen edge")
        XCTAssertEqual(TileLayout.reveal(1, f, area: area, scroll: s), s, "already visible: no movement")
        XCTAssertEqual(TileLayout.reveal(0, f, area: area, scroll: s), 0)
        let (lo, hi) = TileLayout.scrollLimits(f, area: area)
        XCTAssertEqual(lo, 0)
        XCTAssertEqual(hi, f[3].maxX - area.maxX, accuracy: 0.001)
        let scrolled = frames([0.5, 0.5, 0.5, 0.5], scroll: s)
        XCTAssertEqual(TileLayout.visibility(scrolled[0], area: area), .hidden(.left))
        XCTAssertEqual(TileLayout.settleIndex(f, area: area, scroll: s), 1)
    }

    func testWidthConversions() {
        let px = TileLayout.pixelWidth(1.0 / 3, working: 1424, gap: 8)
        XCTAssertEqual(TileLayout.fraction(forPixelWidth: px, working: 1424, gap: 8), 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(TileLayout.pixelWidth(1, working: 1424, gap: 8), 1424)
    }

    func testNewColumnsOpenNextToTheOneInUse() {
        var b = Board()
        for i in 1...3 { b.add(WindowID(i), capacity: 99, stackWhenFull: false) }
        b.setActive(1)
        b.add(9, capacity: 99, stackWhenFull: false, after: b.activeTile)
        XCTAssertEqual(b.showing, [1, 9, 2, 3])
        XCTAssertEqual(SwipeMath.rubberBand(-100, min: 0, max: 500), -pow(100, 0.75), accuracy: 0.001)
    }

    func testSwipeRecognizer() {
        var r = SwipeRecognizer(fingers: 3)
        XCTAssertNil(r.feed(count: 3, x: 0.5, y: 0.5, time: 0))
        XCTAssertEqual(r.feed(count: 3, x: 0.56, y: 0.5, time: 0.01), .began(dx: 0.06000000000000005))
        if case .changed? = r.feed(count: 3, x: 0.6, y: 0.5, time: 0.02) {} else { XCTFail("expected a change") }
        if case .ended? = r.feed(count: 0, x: 0, y: 0, time: 0.03) {} else { XCTFail("expected the end") }
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
        XCTAssertEqual(Config().effectiveBindings()[KeyCombo(keyCode: KeyCode.rightArrow, modifiers: [.control, .option])], .swapRight)
        XCTAssertEqual(Config().effectiveBindings()[KeyCombo(keyCode: KeyCode.n4, modifiers: [.control, .option, .command])], .tile4)
        var off = Config()
        off.shortcutsEnabled = false
        XCTAssertTrue(off.effectiveBindings().isEmpty)
    }

    func testTolerantDecoding() {
        let json = #"{"spacing": 4, "windowsPerScreen": "three", "unknown": 1, "layout": "columns"}"#
        let c = Config.decode(Data(json.utf8))
        XCTAssertEqual(c.spacing, 4)
        XCTAssertEqual(c.windowsPerScreen, 3, "bad value falls back to the default")
        XCTAssertEqual(c.layout, .columns)
        XCTAssertEqual(Config.decode(Data("garbage".utf8)), Config())
    }

    func testRoundTripAndSet() throws {
        var c = Config()
        c.bindings["swap-left"] = [KeyCombo(keyCode: KeyCode.a, modifiers: [.command, .shift])]
        XCTAssertEqual(Config.decode(c.encoded()), c)
        try c.set("spacing", to: "0")
        XCTAssertEqual(c.spacing, 0)
        try c.set("hoverFocus", to: "true")
        XCTAssertTrue(c.hoverFocus)
        try c.set("highlight", to: "glow")
        XCTAssertEqual(c.highlight, .glow)
        try c.set("highlightColor", to: "#FF0000")
        XCTAssertEqual(c.highlightColor, "#FF0000")
        XCTAssertThrowsError(try c.set("nope", to: "1"))
        XCTAssertThrowsError(try c.set("highlight", to: "sparkles"))
        XCTAssertEqual(c.value(of: "spacing"), "0")
    }

    func testCommandParsing() {
        XCTAssertEqual(Command.parse("swap-left"), .swapLeft)
        XCTAssertEqual(Command.parse("swapLeft"), .swapLeft)
        XCTAssertEqual(Command.parse("FOCUS_MODE"), .focusMode)
        XCTAssertNil(Command.parse("explode"))
        XCTAssertEqual(Command.tile3.tileCount, 3)
        XCTAssertEqual(Command.swapUp.direction, .up)
        XCTAssertEqual(KeyCombo(keyCode: KeyCode.z, modifiers: [.control, .option]).description, "⌃⌥Z")
    }

    func testAppRules() {
        var c = Config()
        XCTAssertFalse(c.tiles("com.apple.SystemPreferences"))
        XCTAssertTrue(c.tiles("com.apple.Safari"))
        c.setTiles(false, bundleID: "com.apple.Safari", name: "Safari")
        XCTAssertFalse(c.tiles("com.apple.safari"))
        c.setTiles(true, bundleID: "com.apple.Safari", name: "Safari")
        XCTAssertTrue(c.tiles("com.apple.Safari"))
    }
}

final class SessionTests: XCTestCase {
    func testRestoreByIdThenByTitle() {
        var b = board(3)
        b.setActive(1)
        b.add(4, capacity: 3, stackWhenFull: true)
        b.capacity = 3
        b.layout = .columns
        b.splits.x = 0.6
        let refs: [WindowID: SavedWindow] = [
            1: SavedWindow(id: 1, bundleID: "a", title: "One"), 2: SavedWindow(id: 2, bundleID: "b", title: "Two"),
            3: SavedWindow(id: 3, bundleID: "c", title: "Three"), 4: SavedWindow(id: 4, bundleID: "d", title: "Four"),
        ]
        let snap = BoardSnapshot(displayUUID: "D", spaceID: 7, spaceIndex: 0, board: b) { refs[$0] }
        let session = SessionSnapshot(boards: [snap])
        let decoded = try! JSONDecoder().decode(SessionSnapshot.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded, session)
        XCTAssertNotNil(SessionRestore.snapshot(in: session, displayUUID: "D", spaceID: 99, spaceIndex: 0), "falls back to the Space position")

        // After a restart window 2 has a new number but the same app and title; window 3 is gone.
        let live = [SavedWindow(id: 1, bundleID: "a", title: "One"), SavedWindow(id: 20, bundleID: "b", title: "Two"),
                    SavedWindow(id: 4, bundleID: "d", title: "Four")]
        var used = Set<WindowID>()
        let back = SessionRestore.restore(snap, live: live, used: &used)
        XCTAssertEqual(back.tiles.map(\.windows), [[1, 4], [20]])
        XCTAssertEqual(back.tiles[0].showing, 4)
        XCTAssertEqual(back.layout, .columns)
        XCTAssertEqual(back.splits.x, 0.6)
        XCTAssertEqual(used, [1, 4, 20])
    }
}

final class IPCTests: XCTestCase {
    func testURLParsing() {
        XCTAssertEqual(IPC.request(from: URL(string: "ribbon://swap-left")!), IPC.Request(cmd: "swap-left"))
        XCTAssertEqual(IPC.request(from: URL(string: "ribbon://command/focus-mode")!), IPC.Request(cmd: "focus-mode"))
        XCTAssertEqual(IPC.request(from: URL(string: "ribbon://run?cmd=tile-2")!), IPC.Request(cmd: "tile-2"))
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
