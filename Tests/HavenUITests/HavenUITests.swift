import AppKit
import AVFoundation
import XCTest

/// Drives the real app like a person would, on a sample home folder, and keeps screenshots of every screen.
final class HavenUITests: XCTestCase {
    static let fixtureRoot = "/private/tmp/haven-uitest-fixture"
    static let toolsRoot = "/private/tmp/haven-tools-fixture"
    static let testModel = "/Users/Shared/haven-test-models/ggml-base.en-q5_1.bin"
    var app: XCUIApplication!
    /// The sample folder the current test checks on disk.
    var root = HavenUITests.fixtureRoot

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

    /// The menu item you can see right now (a right-click menu's item, not the same item in the menu bar's closed menus).
    func menuItem(_ title: String, timeout: TimeInterval = 4) -> XCUIElement {
        let all = app.menuItems.matching(NSPredicate(format: "title == %@", title))
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for i in 0..<all.count where all.element(boundBy: i).isHittable { return all.element(boundBy: i) }
            usleep(150_000)
        } while Date() < end
        return all.firstMatch
    }

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
        // Home is scrolled out of the sidebar by now (Activity sits low in it): use Go › Home.
        app.typeKey("h", modifierFlags: [.command, .shift])
        waitFor(el("home.tile.images"), 10, "⇧⌘H should open Home")
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
        app.typeText("zo")
        let zoom = NSPredicate(format: "value CONTAINS ' 1 selected'")
        expectation(for: zoom, evaluatedWith: summary)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(file("Zoom-6.2.pkg").isSelected, "Typing “zo” should select Zoom-6.2.pkg")

        // ⌘↓ opens a folder in Haven, ⌘↑ goes back up to the folder around it.
        app.typeText("hol")
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

    // MARK: New features

    /// The whole screen (for floating panels like Quick Search and the Shelf).
    func snapScreen(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        try? FileManager.default.createDirectory(atPath: "/private/tmp/haven-shots", withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/haven-shots/\(name).png"))
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root + "/" + relative)
    }

    func waitOnDisk(_ relative: String, _ timeout: TimeInterval = 15, gone: Bool = false) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if exists(relative) != gone { return true }
            usleep(200_000)
        }
        return false
    }

    /// Text in screenshots is read in the background; searching for it waits until it's there.
    func waitForText(_ query: String, finds name: String) {
        search(query)
        XCTAssertTrue(file(name).waitForExistence(timeout: 90), "Text in \(name) should be read")
        clearSearch()
    }

    func value(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    func test09_RenameSpaceAndLists() throws {
        launch(onboarding: false)
        requireHome("rename")
        waitForText("boarding gate", finds: "Screenshot 2026-10-12 at 09.41.22.png")

        // One file: type a title read from the screenshot; the extension stays.
        el("sidebar.screenshots").click()
        let shot = file("Screenshot 2026-10-12 at 09.41.22.png")
        waitFor(shot, 15)
        shot.click()
        app.typeKey("r", modifierFlags: .command)
        waitFor(el("rename.sheet"), 10, "⌘R should open Rename")
        let pattern = el("rename.pattern")
        pattern.click()
        pattern.typeKey("a", modifierFlags: .command)
        pattern.typeText("{title}")
        let firstNew = el("rename.new.0")
        expectation(for: NSPredicate(format: "value CONTAINS 'Boarding Pass.png'"), evaluatedWith: firstNew)
        waitForExpectations(timeout: 10)
        snap("80-rename-one")
        app.buttons["rename.apply"].click()
        XCTAssertTrue(waitOnDisk("Desktop/Boarding Pass.png"), "The file should be renamed on disk")
        XCTAssertFalse(exists("Desktop/Screenshot 2026-10-12 at 09.41.22.png"))
        waitFor(file("Boarding Pass.png"), 15, "The renamed file shows up, still selected")
        snap("81-renamed")
        // ⌘Z puts the old name back.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitOnDisk("Desktop/Screenshot 2026-10-12 at 09.41.22.png"), "⌘Z should undo the rename")
        XCTAssertFalse(exists("Desktop/Boarding Pass.png"))

        // Many files: Smart Names, previewed, then cancelled.
        waitFor(file("Screenshot 2026-10-12 at 09.41.22.png"), 15)
        file("Screenshot 2026-10-12 at 09.41.22.png").click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("r", modifierFlags: .command)
        waitFor(el("rename.sheet"), 10)
        // All three screenshots, including the one whose name was just put back.
        expectation(for: NSPredicate(format: "value CONTAINS '3 files will be renamed'"), evaluatedWith: el("rename.summary"))
        waitForExpectations(timeout: 10)
        sleep(1)
        snap("82-rename-many")
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        // Space: where the room goes, folder by folder.
        app.menuBars.menuBarItems["Go"].click()
        menuItem("Space").click()
        waitFor(el("space"), 15, "The Space page should open")
        sleep(2)
        snap("83-space")
        el("space.folder.Downloads").click()
        waitFor(app.staticTexts["Files right in this folder"], 10, "Clicking a folder looks inside it")
        sleep(1)
        snap("84-space-downloads")

        // Copy the list of files on a page.
        el("sidebar.category.images").click()
        waitFor(file("Goa Beach.jpg"), 15)
        NSPasteboard.general.clearContents()
        el("filter.copyList").click()
        menuItem("Copy Names").click()
        sleep(1)
        let names = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(names.contains("Goa Beach.jpg"), "Copy Names should list the files: \(names)")

        // Quick Search starts with recent folders (for Open/Save dialogs).
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Quick Search…"].click()
        waitFor(el("quicksearch.field"), 10)
        sleep(1)
        snapScreen("85-quicksearch-folders")
        app.typeKey(.escape, modifierFlags: [])
    }

    func test10_CollectionsShelfAndShare() throws {
        launch(onboarding: false)
        requireHome("collections")

        // A new collection from a right-click.
        el("sidebar.category.images").click()
        let goa = file("Goa Beach.jpg")
        waitFor(goa, 15)
        goa.rightClick()
        menuItem("Add to Collection").hover()
        menuItem("New Collection with This File").click()
        waitFor(page("Collection"), 10, "The new collection should open")
        waitFor(file("Goa Beach.jpg"), 10, "with the file in it")
        sleep(1)
        snap("86-collection")

        // Make Shareable: a JPEG copy of a HEIC photo, next to it.
        el("sidebar.category.images").click()
        let heic = file("IMG_2041.heic")
        waitFor(heic, 15)
        heic.rightClick()
        menuItem("Make Shareable").hover()
        menuItem("Save as JPEG").click()
        XCTAssertTrue(waitOnDisk("Pictures/Trips/IMG_2041 2.jpg", 20), "A JPEG copy should be made (the name IMG_2041.jpg is taken)")
        XCTAssertTrue(exists("Pictures/Trips/IMG_2041.heic"), "The original stays")
        sleep(1)
        snap("87-made-jpeg")

        // The Shelf: drag a file onto it.
        app.typeKey("s", modifierFlags: [.command, .option])
        let shelf = el("shelf")
        waitFor(shelf, 10, "⌥⌘S should show the Shelf")
        sleep(1)
        snapScreen("88-shelf-empty")
        file("Goa Beach.jpg").press(forDuration: 0.8, thenDragTo: shelf)
        waitFor(el("shelf.item.Goa Beach.jpg"), 10, "The dropped file sits on the shelf")
        sleep(1)
        snapScreen("89-shelf")

        // Dragging a file off the shelf into another window: onto the collection in the sidebar.
        file("IMG_2041.heic").rightClick()
        menuItem("Add to Shelf").click()
        let onShelf = el("shelf.item.IMG_2041.heic")
        waitFor(onShelf, 10, "Add to Shelf puts the file on the shelf")
        let collectionRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar.collection.'")).firstMatch
        waitFor(collectionRow, 10)
        let shelfFrame = el("shelf").frame
        onShelf.press(forDuration: 0.6, thenDragTo: collectionRow)
        let added = app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Added 1 file' OR label CONTAINS 'Added 1 file'")).firstMatch
        waitFor(added, 10, "A file dragged off the shelf lands in the collection")
        XCTAssertEqual(el("shelf").frame, shelfFrame, "Dragging a file must not move the shelf window")
        snapScreen("89b-shelf-drag-out")

        // "Drag all": every file on the shelf goes along (only the JPEG copy is new to the collection).
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: added)
        waitForExpectations(timeout: 15)
        file("IMG_2041 2.jpg").rightClick()
        menuItem("Add to Shelf").click()
        waitFor(el("shelf.item.IMG_2041 2.jpg"), 10)
        el("shelf.dragAll").press(forDuration: 0.6, thenDragTo: collectionRow)
        waitFor(added, 10, "Drag all should drop every shelf file into the collection")
        XCTAssertEqual(el("shelf").frame, shelfFrame, "Drag all must not move the shelf window")
        app.typeKey("s", modifierFlags: [.command, .option])
    }

    func test11_YourOwnRules() throws {
        launch(onboarding: false)
        requireHome("rules")
        waitForText("pay by 30 oct", finds: "invoice-4821.png")

        app.typeKey("k", modifierFlags: [.command, .shift])
        let idea = el("rules.idea.File invoices from Gmail")
        waitFor(idea, 15, "Rule ideas should be on Clean Up")
        idea.click()
        waitFor(el("ruleEditor"), 10, "The rule editor should open")
        let preview = el("ruleEditor.preview")
        expectation(for: NSPredicate(format: "value CONTAINS 'matches 1 file'"), evaluatedWith: preview)
        waitForExpectations(timeout: 20)
        sleep(1)
        snap("90-rule-editor")
        app.buttons["ruleEditor.save"].click()

        let toggle = el("rule.toggle.File invoices from Gmail")
        waitFor(toggle, 10, "The saved rule shows on Clean Up")
        toggle.click()
        XCTAssertTrue(waitOnDisk("Documents/Invoices/invoice-4821.png", 30), "Turning the rule on files the invoice")
        XCTAssertFalse(exists("Downloads/invoice-4821.png"))
        sleep(1)
        snap("91-rules")

        el("sidebar.activity").click()
        waitFor(app.buttons["activity.undo"], 10)
        sleep(1)
        snap("92-activity")
        app.buttons["activity.undo"].firstMatch.click()
        XCTAssertTrue(waitOnDisk("Downloads/invoice-4821.png", 15), "Undo puts the invoice back")
    }

    // MARK: File Tools

    /// Right-click tools on real images, PDFs, video and a spoken voice memo, from their own sample folder.
    func test12_FileTools() throws {
        root = Self.toolsRoot
        app = XCUIApplication()
        app.launchArguments = [
            "-HavenFixtureRoot", Self.toolsRoot,
            "-HavenMakeFixtures", "tools",
            "-HavenResetState", "YES",
            "-HavenSkipOnboarding", "YES",
            "-HavenWhisperModel", Self.testModel,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        app.activate()
        waitFor(el("sidebar.category.images"), 60)

        // Every tool on one page.
        app.typeKey("t", modifierFlags: [.command, .shift])
        waitFor(el("tools"), 15, "⇧⌘T should open File Tools")
        waitFor(el("tool.transcribe"), 10)
        sleep(1)
        snap("93-file-tools")

        func tool(_ file: XCUIElement, _ title: String, _ choice: String? = nil) {
            file.rightClick()
            menuItem("Tools").hover()
            if let choice {
                menuItem(title).hover()
                menuItem(choice).click()
            } else {
                menuItem(title).click()
            }
        }

        // Images: a photo that says where it was taken, made safe to share; a HEIC made into a JPEG.
        el("sidebar.category.images").click()
        let goa = file("Goa Trip.jpg")
        waitFor(goa, 20)
        tool(goa, "Remove Private Details")
        XCTAssertTrue(waitOnDisk("Pictures/Goa Trip (clean).jpg", 20), "a clean copy is made")
        tool(file("Hills.heic"), "Convert Images", "JPEG")
        XCTAssertTrue(waitOnDisk("Pictures/Hills.jpg", 20))
        XCTAssertTrue(exists("Pictures/Hills.heic"), "the original stays")
        waitFor(file("Hills.jpg"), 15, "the new file shows up")
        sleep(1)
        snap("94-image-tools")

        // PDFs: merge two (in an order you can change), reorganize pages, add a password.
        el("sidebar.category.documents").click()
        let contract = file("Contract.pdf"), appendix = file("Appendix.pdf")
        waitFor(contract, 20)
        contract.click()
        XCUIElement.perform(withKeyModifiers: .command) { appendix.click() }
        tool(contract, "Merge PDFs…")
        waitFor(el("merge.list"), 10, "Merge asks for the order")
        sleep(1)
        snap("95-merge-order")
        el("merge.go").click()
        XCTAssertTrue(waitOnDisk("Documents/Contract (merged).pdf", 20) || exists("Documents/Appendix (merged).pdf"), "merged")

        tool(file("Contract.pdf"), "Organize Pages…")
        let firstPage = el("page.1")
        waitFor(firstPage, 10, "the pages are shown")
        firstPage.click()
        el("pages.rotateRight").click()
        sleep(1)
        snap("96-organize-pages")
        el("pages.save").click()
        XCTAssertTrue(waitOnDisk("Documents/Contract (edited).pdf", 20))

        tool(file("Contract.pdf"), "Add Password…")
        let pw = el("password.field")
        waitFor(pw, 10)
        pw.click()
        pw.typeText("mango42")
        el("password.again").click()
        el("password.again").typeText("mango42")
        el("password.go").click()
        XCTAssertTrue(waitOnDisk("Documents/Contract (locked).pdf", 20))

        // Video: compress (a job with progress), then a GIF.
        el("sidebar.category.videos").click()
        let beach = file("Beach Clip.mov")
        waitFor(beach, 20)
        tool(beach, "Compress Video", "Smallest (540p)")
        if el("job").waitForExistence(timeout: 5) { snapScreen("97-job-progress") }
        XCTAssertTrue(waitOnDisk("Movies/Beach Clip (540p).mp4", 60), "compressed")
        tool(file("Beach Clip.mov"), "Make a GIF", "Small (320 px)")
        XCTAssertTrue(waitOnDisk("Movies/Beach Clip.gif", 60))

        // A spoken voice memo: transcribed with Whisper, then found by what was said.
        el("sidebar.category.music").click()
        let memo = file("Voice Memo.m4a")
        waitFor(memo, 20)
        tool(memo, "Transcribe…")
        waitFor(el("transcribe.go"), 10, "the transcription window opens")
        el("transcribe.srt").click()
        sleep(1)
        snap("98-transcribe")
        el("transcribe.go").click()
        XCTAssertTrue(waitOnDisk("Music/Voice Memo.txt", 120), "a transcript is written")
        XCTAssertTrue(waitOnDisk("Music/Voice Memo.srt", 10), "and subtitles")
        sleep(2)
        el("sidebar.category.images").click()
        XCTAssertFalse(file("Voice Memo.m4a").waitForExistence(timeout: 2), "not on the Images page")
        search("quarterly budget")
        waitFor(file("Voice Memo.m4a"), 20, "searching for what was said finds the memo")
        XCTAssertEqual(app.textFields["search.field"].value as? String, "quarterly budget", "every key went into the search box")
        sleep(1)
        snap("99-search-what-was-said")
        clearSearch()

        // ⌘Z takes back what the last tool made.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitOnDisk("Music/Voice Memo.txt", 15, gone: true), "Undo moves the transcript to the Trash")

        // Summaries and translation open (what they can do depends on the Mac).
        el("sidebar.category.documents").click()
        let notes = file("Meeting Notes.txt")
        waitFor(notes, 20)
        tool(notes, "Summarize…")
        waitFor(el("toolSheet"), 10)
        sleep(2)
        snap("99b-summarize")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: Videos

    /// Double-clicking a video opens it in the big preview and plays it; a damaged one shows a message.
    /// Uses its own folder of real and broken videos, so it also runs against a Release build.
    func test08_Videos() throws {
        // The test runner is sandboxed: it can only write inside its own temporary folder (Haven can read it).
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("haven-video-fixture").path
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

        // Step to the other videos with the arrow keys (the keyboard stays with the preview).
        app.typeKey(.leftArrow, modifierFlags: [])
        sleep(2)
        stillRunning("moving to the next video")
        app.typeKey(.leftArrow, modifierFlags: [])
        sleep(2)
        stillRunning("moving to a damaged video")
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)
        stillRunning("closing the preview")

        // A damaged video says so instead of showing a black box.
        file("Broken clip.mov").doubleClick()
        let message = "Haven can't play this video"
        let cantPlay = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", message, message)).firstMatch
        waitFor(cantPlay, 10, "A damaged video should say it can't be played")
        stillRunning("double-clicking a damaged video")
        snap("72-video-broken")
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
