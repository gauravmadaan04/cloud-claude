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

    func launch(onboarding: Bool) {
        app = XCUIApplication()
        app.launchArguments = [
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

    func page(_ title: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'page.title' AND label == %@", title)).firstMatch
    }

    func search(_ text: String) {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        field.typeText(text)
    }

    func clearSearch() {
        let clear = app.buttons["search.clear"]
        if clear.exists { clear.click() }
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
        el("onboarding.look.minimal").click()
        snap("04-onboarding-look-minimal")
        el("onboarding.look.playful").click()
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
        waitFor(el("page.title"), 10)
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
}
