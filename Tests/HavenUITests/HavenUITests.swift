import AppKit
import AVFoundation
import XCTest

/// Drives the real app like a person would, on a sample home folder, and keeps screenshots of every screen.
final class HavenUITests: XCTestCase {
    static let fixtureRoot = "/private/tmp/haven-uitest-fixture"
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func launch(onboarding: Bool, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = extra + [
            "-HavenFixtureRoot", Self.fixtureRoot,
            "-HavenMakeFixtures", "YES",
            "-HavenResetState", "YES",
            "-HavenSkipOnboarding", onboarding ? "NO" : "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        app.activate()
    }

    // MARK: Helpers

    func snap(_ name: String) {
        let window = app.windows.firstMatch
        let shot = window.exists ? window.screenshot() : XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Also drop a copy on disk for CI artifacts (best effort).
        let dir = URL(fileURLWithPath: "/private/tmp/haven-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }

    func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func file(_ name: String) -> XCUIElement { el("file." + name) }

    @discardableResult
    func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 20, _ message: String = "") -> Bool {
        let ok = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(ok, message.isEmpty ? "Missing \(element)" : message)
        return ok
    }

    /// Waits for Home's library tiles; takes a screenshot to explain a failure.
    func requireHome(_ label: String) {
        if !el("home.tile.images").waitForExistence(timeout: 60) {
            snap("debug-\(label)-no-home")
            XCTFail("Home did not appear (\(label))")
        }
    }

    /// The big title of the current page (macOS puts a text's string in `value`).
    func page(_ title: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'page.title' AND (value == %@ OR label == %@)", title, title)).firstMatch
    }

    func search(_ text: String) {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        if !((field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false) {
            // Explain a lost focus: which view took it (the app logs this in test runs).
            sleep(1)
            snap("debug-search-focus")
            print("FOCUS LOG for “\(text)”:\n\(focusLog())")
        }
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        field.typeText(text)
    }

    func clearSearch() {
        let clear = app.buttons["search.clear"]
        if clear.exists { clear.click() }
    }

    func focusLog() -> String {
        (try? String(contentsOfFile: "/private/tmp/haven-focus.log", encoding: .utf8)) ?? "(no focus log)"
    }

    // MARK: Tests

    func test01_OnboardingTour() throws {
        launch(onboarding: true)
        waitFor(app.staticTexts["Welcome to Haven"], 40, "Onboarding should open on first launch")
        snap("01-onboarding-welcome")
        let next = app.buttons["onboarding.continue"]
        next.click()
        waitFor(app.staticTexts["Everything stays on your Mac"])
        snap("02-onboarding-privacy")
        next.click()
        waitFor(app.staticTexts["Choose what Haven looks at"])
        snap("03-onboarding-folders")
        next.click()
        waitFor(app.staticTexts["Pick a look"])
        app.typeKey("t", modifierFlags: [.command, .control])
        sleep(1)
        snap("04-onboarding-look-minimal")
        app.typeKey("t", modifierFlags: [.command, .control])
        next.click()
        waitFor(app.staticTexts["Search the way you talk"])
        app.buttons["screenshots over 5 MB"].click()
        waitFor(el("chip.type"), 5)
        snap("05-onboarding-search")
        next.click()
        waitFor(app.staticTexts["Quick Search, from any app"])
        snap("06-onboarding-quicksearch")
        next.click()
        waitFor(app.staticTexts["Your latest downloads, one click away"])
        snap("07-onboarding-menubar")
        next.click()
        waitFor(app.staticTexts["A few things to try"])
        snap("08-onboarding-tour")
        next.click()
        waitFor(app.staticTexts["You're all set"])
        sleep(3)
        snap("09-onboarding-ready")
        app.buttons["onboarding.finish"].click()
        waitFor(app.staticTexts["home.greeting"], 30, "Home should appear after onboarding")
        waitFor(el("home.tile.images"), 60)
        sleep(2)
        snap("10-home-after-onboarding")
    }

    func test02_HomeSearchAndBrowse() throws {
        launch(onboarding: false)
        waitFor(app.staticTexts["home.greeting"], 40)
        requireHome("search")
        sleep(4) // let thumbnails and duplicate checks settle
        snap("11-home-playful")

        // Plain-English search with visible chips.
        search("pdfs from last week")
        waitFor(el("chip.type"), 10, "PDFs chip")
        waitFor(el("chip.date"), 10, "Last week chip")
        waitFor(file("Q3-report.pdf"), 20, "The PDF from last week should be found")
        XCTAssertFalse(file("Tax Return 2025.pdf").exists, "Older PDFs should not match")
        snap("12-search-pdfs-last-week")

        // Remove the date chip: the search text updates and older PDFs appear.
        el("chip.remove.date").click()
        waitFor(file("Tax Return 2025.pdf"), 10)
        snap("13-search-chip-removed")

        // Save the search to the sidebar.
        search("screenshots")
        waitFor(app.buttons["search.save"], 10)
        app.buttons["search.save"].click()
        waitFor(page("Screenshots"), 10, "Saved search should open from the sidebar")
        snap("14-saved-search")

        // Text inside screenshots (OCR) becomes searchable.
        search("boarding gate")
        let boarding = file("Screenshot 2026-10-12 at 09.41.22.png")
        XCTAssertTrue(boarding.waitForExistence(timeout: 90), "OCR text should be searchable")
        snap("15-search-text-in-images")

        // Downloaded From
        search("from gmail")
        waitFor(file("invoice-4821.png"), 10)
        snap("16-search-from-gmail")
        clearSearch()

        // ⌘F focuses the search field; while it's empty, recent searches and ideas drop down.
        app.typeKey("f", modifierFlags: .command)
        waitFor(el("search.suggestions"), 5, "Suggestions should drop down under the search field")
        XCTAssertTrue((app.textFields["search.field"].value(forKey: "hasKeyboardFocus") as? Bool) ?? false, "⌘F should focus the search field")
        sleep(1)
        snap("16b-search-suggestions")
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        app.typeKey("j", modifierFlags: [.command, .shift])
        waitFor(el("source.card.gmail"), 15, "Downloaded From groups")
        sleep(2)
        snap("17-downloaded-from")
        el("source.card.gmail").click()
        waitFor(file("Q3-report.pdf"), 10)
        snap("18-source-gmail")

        // Category, list view, inspector, preview.
        el("sidebar.category.images").click()
        waitFor(page("Images"), 10, "Sidebar should open Images")
        waitFor(file("Goa Beach.jpg"), 15)
        sleep(2)
        snap("19-images-grid")
        file("Goa Beach.jpg").click()
        app.typeKey("i", modifierFlags: .command)
        waitFor(el("inspector"), 10)
        sleep(2)
        snap("20-inspector")
        app.typeKey("i", modifierFlags: .command)
        app.typeKey("2", modifierFlags: .command)
        waitFor(el("file.list"), 10)
        sleep(1)
        snap("21-images-list")
        app.typeKey("1", modifierFlags: .command)
        file("IMG_2041.jpg").doubleClick()
        waitFor(el("preview.overlay"), 10)
        sleep(2)
        snap("22-large-preview")
        app.typeKey(.escape, modifierFlags: [])
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: el("preview.overlay"))
        waitForExpectations(timeout: 5)

        // Music plays in the toolbar.
        el("sidebar.category.music").click()
        waitFor(file("Morning Tune.wav"), 10)
        file("Morning Tune.wav").doubleClick()
        waitFor(el("player.toggle"), 10, "Mini player should appear")
        snap("23-music-player")
        el("player.toggle").click()

        // Folder browsing.
        app.typeKey("l", modifierFlags: [.command, .option])
        waitFor(file("Zoom-6.2.pkg"), 15)
        snap("24-folder-downloads")
    }

    func test03_DuplicatesCleanUpAndUndo() throws {
        launch(onboarding: false)
        requireHome("cleanup")

        app.typeKey("d", modifierFlags: [.command, .shift])
        waitFor(el("dupes.freeup"), 90, "Duplicates should be found")
        sleep(2)
        snap("30-duplicates")

        app.typeKey("k", modifierFlags: [.command, .shift])
        waitFor(el("cleanup.card.oldInstallers"), 15)
        sleep(1)
        snap("31-cleanup")
        el("cleanup.card.oldInstallers").click()
        waitFor(el("cleanup.trashAll"), 10)
        waitFor(app.staticTexts["Zoom-6.2.pkg"], 10)
        snap("32-cleanup-review-installers")

        el("cleanup.trashAll").click()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Move All to Trash'")).firstMatch
        waitFor(confirm, 10, "Confirmation should ask first")
        snap("33-cleanup-confirm")
        confirm.click()
        waitFor(el("toast.undo"), 10, "Undo should be offered")
        snap("34-cleanup-trashed-toast")
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.fixtureRoot + "/Downloads/Zoom-6.2.pkg"))
        el("toast.undo").click()
        sleep(2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: Self.fixtureRoot + "/Downloads/Zoom-6.2.pkg"), "Undo should restore the file")

        el("sidebar.activity").click()
        waitFor(page("Activity"), 10, "Sidebar should open Activity")
        sleep(1)
        snap("35-activity")

        // Minimal look.
        app.typeKey("t", modifierFlags: [.command, .control])
        el("sidebar.home").click()
        waitFor(el("home.tile.images"), 10, "Sidebar should open Home")
        sleep(2)
        snap("36-home-minimal")
        app.typeKey("t", modifierFlags: [.command, .control])

        // Keyboard shortcuts sheet.
        app.typeKey("/", modifierFlags: .command)
        waitFor(el("shortcuts.sheet"), 10)
        snap("37-shortcuts")
        app.typeKey(.return, modifierFlags: [])
    }

    func test04_QuickSearchAndSettings() throws {
        launch(onboarding: false)
        requireHome("quicksearch")

        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Quick Search…"].click()
        let field = el("quicksearch.field")
        waitFor(field, 10, "Quick Search panel should open")
        sleep(1)
        snap("40-quicksearch-recent")
        field.typeText("invoice")
        waitFor(el("quicksearch.row.invoice-4821.png"), 10, "Quick Search should find the invoice by name")
        sleep(1)
        let screen = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: screen)
        a.name = "41-quicksearch-results"
        a.lifetime = .keepAlways
        add(a)
        try? screen.pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/haven-shots/41-quicksearch-results.png"))
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.matching(NSPredicate(format: "title CONTAINS[c] 'General' OR title CONTAINS[c] 'Settings'")).firstMatch
        if settings.waitForExistence(timeout: 10) {
            sleep(1)
            let s = XCTAttachment(screenshot: settings.screenshot())
            s.name = "42-settings"
            s.lifetime = .keepAlways
            add(s)
            try? settings.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/haven-shots/42-settings.png"))
        }
    }

    func test05_GlobalHotKeyAndMenuBar() throws {
        launch(onboarding: false)
        requireHome("hotkey")

        // The system-wide shortcut opens Quick Search.
        app.typeKey(.space, modifierFlags: [.command, .shift])
        let field = el("quicksearch.field")
        waitFor(field, 10, "⇧⌘Space should open Quick Search")
        field.typeText("boarding")
        sleep(2)
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = "43-hotkey-quicksearch"
        a.lifetime = .keepAlways
        add(a)
        app.typeKey(.escape, modifierFlags: [])

        // The menu bar window lists the latest downloads.
        let status = app.statusItems.firstMatch
        if status.waitForExistence(timeout: 5) {
            status.click()
            if app.staticTexts["Latest Downloads"].waitForExistence(timeout: 5) {
                sleep(1)
                let menuShot = XCUIScreen.main.screenshot()
                let m = XCTAttachment(screenshot: menuShot)
                m.name = "44-menu-bar"
                m.lifetime = .keepAlways
                add(m)
                XCTAssertTrue(app.staticTexts["invoice-4821.png"].exists || app.staticTexts["Q3-report.pdf"].exists,
                              "Menu bar should list recent downloads")
            }
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    func test06_DarkMode() throws {
        launch(onboarding: false, extra: ["-HavenAppearance", "dark"])
        requireHome("dark")
        sleep(4)
        snap("50-dark-home")

        el("sidebar.category.images").click()
        waitFor(file("Goa Beach.jpg"), 15)
        file("Goa Beach.jpg").click()
        sleep(2)
        snap("51-dark-images-grid")
        app.typeKey("i", modifierFlags: .command)
        waitFor(el("inspector"), 10)
        sleep(2)
        snap("52-dark-inspector")
        app.typeKey("i", modifierFlags: .command)

        search("pdfs from last week")
        waitFor(file("Q3-report.pdf"), 20)
        sleep(1)
        snap("53-dark-search")
        clearSearch()

        app.typeKey("d", modifierFlags: [.command, .shift])
        waitFor(el("dupes.freeup"), 90, "Duplicates should be found")
        sleep(2)
        snap("54-dark-duplicates")

        app.typeKey("k", modifierFlags: [.command, .shift])
        waitFor(el("cleanup.card.oldInstallers"), 15)
        sleep(1)
        snap("55-dark-cleanup")

        el("sidebar.category.images").click()
        waitFor(file("IMG_2041.jpg"), 15)
        file("IMG_2041.jpg").doubleClick()
        waitFor(el("preview.overlay"), 10)
        sleep(2)
        snap("56-dark-preview")
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        app.typeKey("t", modifierFlags: [.command, .control])
        app.typeKey("h", modifierFlags: [.command, .shift]) // Go › Home
        waitFor(el("home.tile.images"), 10)
        sleep(2)
        snap("57-dark-home-minimal")
        app.typeKey("t", modifierFlags: [.command, .control])
    }

    /// Finder's everyday keys work in the file browser (and leave text fields alone).
    func test07_StandardShortcuts() throws {
        launch(onboarding: false)
        requireHome("shortcuts")

        // ⌘A selects every file on the page.
        el("sidebar.category.images").click()
        waitFor(file("Goa Beach.jpg"), 15)
        file("Goa Beach.jpg").click()
        app.typeKey("a", modifierFlags: .command)
        let summary = el("results.count")
        expectation(for: NSPredicate(format: "value CONTAINS ' selected'"), evaluatedWith: summary)
        waitForExpectations(timeout: 5)
        let text = summary.value as? String ?? ""
        let total = String(text.prefix { $0.isNumber || $0 == "," })
        XCTAssertTrue(text.contains(" \(total) selected"), "⌘A should select all \(total) files: \(text)")
        snap("60-select-all")

        // A click inside the selection leaves just that file; ⇧← / ⇧→ grow and shrink from it.
        // (Goa Beach.jpg is the oldest image, so it sits at the end of the grid.)
        file("Goa Beach.jpg").click()
        expectation(for: NSPredicate(format: "value CONTAINS ' 1 selected'"), evaluatedWith: summary)
        waitForExpectations(timeout: 5)
        app.typeKey(.leftArrow, modifierFlags: .shift)
        app.typeKey(.leftArrow, modifierFlags: .shift)
        expectation(for: NSPredicate(format: "value CONTAINS ' 3 selected'"), evaluatedWith: summary)
        waitForExpectations(timeout: 5)
        app.typeKey(.rightArrow, modifierFlags: .shift)
        expectation(for: NSPredicate(format: "value CONTAINS ' 2 selected'"), evaluatedWith: summary)
        waitForExpectations(timeout: 5)

        // ⌘C puts the file itself on the clipboard.
        file("Goa Beach.jpg").click()
        NSPasteboard.general.clearContents()
        app.typeKey("c", modifierFlags: .command)
        sleep(1)
        let copied = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        XCTAssertEqual(copied.map(\.lastPathComponent), ["Goa Beach.jpg"], "⌘C should copy the selected file")

        // ⌘V in a folder pastes a copy, never replacing anything.
        let downloads = Self.fixtureRoot + "/Downloads"
        func beachCopies() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: downloads)) ?? []).filter { $0.hasPrefix("Goa Beach") }.sorted()
        }
        let before = beachCopies()
        app.typeKey("l", modifierFlags: [.command, .option])
        waitFor(file("Zoom-6.2.pkg"), 15)
        app.typeKey("v", modifierFlags: .command)
        waitFor(file("Goa Beach.jpg"), 15, "The pasted copy should show up in Downloads")
        app.typeKey("v", modifierFlags: .command)
        sleep(2)
        let after = beachCopies()
        XCTAssertEqual(after.count, before.count + 2, "Two pastes, two new copies: \(after)")
        XCTAssertTrue(Set(before).isSubset(of: Set(after)), "Nothing that was there is replaced")
        snap("61-pasted")

        // Typing a name jumps to it.
        app.typeKey("z", modifierFlags: [])
        app.typeKey("o", modifierFlags: [])
        let zoom = NSPredicate(format: "value CONTAINS ' 1 selected'")
        expectation(for: zoom, evaluatedWith: summary)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(file("Zoom-6.2.pkg").isSelected, "Typing “zo” should select Zoom-6.2.pkg")

        // ⌘↓ opens a folder in Haven, ⌘↑ goes back up to the folder around it.
        app.typeKey("h", modifierFlags: [])
        app.typeKey("o", modifierFlags: [])
        app.typeKey("l", modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: .command)
        waitFor(file("beach-day.jpg"), 10, "⌘↓ should open the holiday-photos folder")
        app.typeKey(.upArrow, modifierFlags: .command)
        waitFor(file("Zoom-6.2.pkg"), 10, "⌘↑ should go back to Downloads")

        // In the search field the same keys edit text instead.
        search("invoice")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(app.textFields["search.field"].value as? String ?? "", "", "⌘A in the search field selects its text")
    }

    // MARK: Videos

    /// Double-clicking a video opens it in the big preview and plays it; a damaged one shows a message.
    /// Uses its own folder of real and broken videos, so it also runs against a Release build.
    func test08_Videos() throws {
        let root = "/private/tmp/haven-video-fixture"
        let fm = FileManager.default
        try? fm.removeItem(atPath: root)
        let movies = root + "/Movies"
        for sub in ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Applications"] {
            try fm.createDirectory(atPath: root + "/" + sub, withIntermediateDirectories: true)
        }
        try Self.makeVideo(at: URL(fileURLWithPath: movies + "/Beach Walk.mov"), seconds: 3)
        try Self.makeVideo(at: URL(fileURLWithPath: movies + "/Sunset.mp4"), seconds: 2, type: .mp4)
        try Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: URL(fileURLWithPath: movies + "/Broken clip.mov"))

        app = XCUIApplication()
        app.launchArguments = [
            "-HavenFixtureRoot", root,
            "-HavenResetState", "YES",
            "-HavenSkipOnboarding", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        app.activate()

        func stillRunning(_ step: String) {
            XCTAssertEqual(app.state, .runningForeground, "Haven quit after: \(step)")
        }

        waitFor(el("sidebar.category.videos"), 60)
        el("sidebar.category.videos").click()
        waitFor(file("Beach Walk.mov"), 30, "The videos should be listed")
        sleep(2) // thumbnails
        snap("70-videos-grid")
        stillRunning("showing the videos")

        file("Beach Walk.mov").doubleClick()
        waitFor(el("preview.overlay"), 10, "Double-clicking a video opens the preview")
        sleep(3)
        stillRunning("double-clicking a video")
        snap("71-video-playing")

        // Next video, then the damaged one, with the arrow keys.
        app.typeKey(.rightArrow, modifierFlags: [])
        sleep(2)
        stillRunning("moving to the next video")
        app.typeKey(.rightArrow, modifierFlags: [])
        sleep(2)
        stillRunning("moving to a damaged video")
        snap("72-video-broken")
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)
        stillRunning("closing the preview")

        // Straight to the damaged one, and Quick Look on a video.
        file("Broken clip.mov").doubleClick()
        sleep(2)
        stillRunning("double-clicking a damaged video")
        app.typeKey(.escape, modifierFlags: [])
        file("Sunset.mp4").click()
        app.typeKey(" ", modifierFlags: [])
        sleep(2)
        stillRunning("Quick Look on a video")
        app.typeKey(" ", modifierFlags: [])
        sleep(1)

        // The inspector reads the video's length and size.
        file("Beach Walk.mov").click()
        app.typeKey("i", modifierFlags: .command)
        waitFor(el("inspector"), 10)
        sleep(2)
        stillRunning("showing a video in the inspector")
        snap("73-video-inspector")
        app.typeKey("i", modifierFlags: .command)
    }

    /// A short real video (moving colour bands), written with AVFoundation.
    static func makeVideo(at url: URL, seconds: Int, type: AVFileType = .mov) throws {
        try? FileManager.default.removeItem(at: url)
        let w = 320, h = 240
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 15
        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<h {
                    let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<w {
                        row[x * 4] = 255
                        row[x * 4 + 1] = UInt8(truncatingIfNeeded: x + frame * 6)
                        row[x * 4 + 2] = UInt8(truncatingIfNeeded: y * 2)
                        row[x * 4 + 3] = 180
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
