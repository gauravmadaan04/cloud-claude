# Haven: instructions for Claude

Haven is a paid macOS app (sold outside the Mac App Store as a DMG) that finds any file by describing it in plain
English, fixes files with 27 right-click tools (images, PDFs including Fill & Sign, video, audio, on-device AI),
and cleans up safely. Everything runs on the Mac. Price: $49 (1 Mac), $79 (3 Macs), $99 (5 Macs), one time,
30-day money-back guarantee, no trial. This repository holds the app, its tests, the CI, and the sales website.

## Map

```
App/                  SwiftUI app (macOS 14+, universal). Not sandboxed; hardened runtime currently off.
  HavenApp.swift      entry point, app delegate, fixture setup for tests
  Model/              AppModel (navigation, selection, toasts, windows), Prefs (all settings, UserDefaults), LaunchOptions
  Library/            LibraryStore (index of the chosen folders), TextIndex (text from OCR/PDFs/transcripts), FSWatcher,
                      FileOps (Trash + Undo log), DuplicateService, RenameService, CustomRulesRunner, Collections, Shelf
  Services/           Thumbnails, Metadata, Quick Search panel, Shelf panel, Dialog Jump, HotKey, ShortcutRouter, MusicPlayer, ShareMaker
  Tools/              the 27 tools: ToolRunner (jobs, toasts, menus), ToolWork (what each tool does), ToolSheets (option sheets),
                      ImageTools, PDFTools, MediaTools, Transcriber (whisper.cpp), AISheets (transcribe/translate/summarize)
  Tools/FillSign/     Fill & Sign window: FillModel (items + drawing), FillEditor (state, undo, PDF view), FillSignView (UI,
                      window), Signatures (library + maker: type / draw / photo)
  Views/              all screens; Views/Screens/ has Home, Clean Up, Duplicates, Space, Tools, Activity…
  Debug/              sample-file generators for tests and demos (DEBUG builds only)
Packages/HavenCore/   pure Swift logic, runs and is tested on Linux too: file model, QueryParser, SearchEngine, sources
                      (DownloadSource), duplicates, clean-up, rules, rename planner, tool catalog and naming, FormFill
Packages/WhisperCpp/  whisper.cpp as the prebuilt xcframework its project publishes (pinned by checksum)
Tests/HavenTests/     integration tests hosted in the app (OCR, PDFs, every tool on real files, Fill & Sign engine…)
Tests/HavenUITests/   end-to-end UI tests on generated sample folders, with screenshots; test90_Film records the site's film
website/              the static sales site (see website/README.md); COPY.md is the copy deck
scripts/              build_dmg.sh, mac_check.sh (everything on a Mac), make_icon.py, website_pages.py (builds inner pages)
packaging/            DMG background and Read Me First.pdf (make_art.py redraws both)
.github/workflows/    haven.yml (full CI + DMG), haven-quick.yml (one test), haven-film.yml (film), spotlight-check.yml
project.yml           XcodeGen project (bundle id app.haven.Haven, version 1.0.0)
```

## Build and test

- Linux or Mac, core logic: `cd Packages/HavenCore && swift test` (147 tests). Do this after any change in HavenCore.
- Mac: `brew install xcodegen && xcodegen generate`, then `scripts/mac_check.sh` (or `--no-ui`), or open Haven.xcodeproj.
- No Mac? Push to `haven-mac`: `.github/workflows/haven.yml` runs core tests, the 300,000-file speed check, a Debug build,
  integration tests (59), UI tests (13, ~16 min), a universal Release build, a smoke test and the DMG. Artifacts:
  `Haven-dmg`, `screenshots` (look at them), `test-logs`. Website-only commits skip it.
- One test on a Mac quickly: push a branch named `haven-quick-*` with `.github/quick-run.txt` (`config:` and `tests:` lines).
- Try the app on sample files, never your own: `Haven.app/Contents/MacOS/Haven -HavenFixtureRoot /tmp/haven-demo
  -HavenMakeFixtures YES -HavenResetState YES -HavenSkipOnboarding YES` (Debug builds). Other flags: see
  App/Model/LaunchOptions.swift (`tools` and `film` sample sets, `-HavenWhisperModel`, `-HavenAppearance`, `-HavenLook`).
- Tests and demos must only ever touch generated sample folders (/private/tmp/haven-*), never real user files.

## Rules that matter

- **Never change or delete a user's file.** Tools write a new file next to the original (names come from
  `ToolNaming` in HavenCore: "Report (signed).pdf", "IMG_4021.jpg", "Clip (720p).mp4"). Anything Haven removes goes to
  the Trash through FileOps, with Undo. Rules are off until the user turns them on.
- **Privacy promise (it's on the website, word for word):** Haven goes online only to (1) download a Whisper model from
  Hugging Face the first time someone transcribes, (2) let macOS fetch a translation language from Apple,
  (3) activate a license (key + a random ID for the Mac, once per Mac), (4) check for updates (app and macOS version;
  can be turned off). No analytics, no crash reporting, no uploads, no account. Don't add any network call outside
  this list without changing the website, privacy policy and FAQ in the same change.
- **Claims must stay true.** The website quotes numbers and facts (speed 0.09 s on 300,000 files, test counts, the
  Spotlight comparison, competitor prices with a date). If you change behaviour they depend on, update the site
  (`website/index.html`, `website/COPY.md`, `scripts/website_pages.py`) in the same change. Sources are listed in
  website/README.md.
- **Words:** plain, short, friendly English in the UI and on the site; say what happens ("Moved 2 items to the Trash").
- UI tests find things by `accessibilityIdentifier`; give new controls one. Note PDFView doesn't expose its own
  identifier: click inside its window by position instead (see test13_FillAndSign).
- New logic goes in HavenCore with Linux tests where possible; app-level behaviour gets a test in Tests/HavenTests;
  a new screen or flow gets a step (and screenshot) in Tests/HavenUITests.

## Things learned the hard way

- PDFKit: draw editor-only chrome (selection frames) on an overlay view, not inside a PDFAnnotation: PDFView doesn't
  reliably repaint annotations when only their look changes.
- Fill & Sign saves by redrawing changed pages with `drawPDFPage` + each annotation's `draw(with:in:)` in page space,
  then the items, keeping the page's rotation and crop box; links are copied back. Pages with a redaction become a
  200 dpi picture so the text underneath is gone. Untouched pages are kept as they were.
- Whisper: the app downloads ggml-large-v3-turbo-q5_0 (574 MB) or ggml-small-q5_1 (190 MB) on first use and checks
  SHA-256; tests use ggml-base.en from /Users/Shared/haven-test-models (CI downloads it).
- On the CI Macs, `say` sometimes writes an almost empty recording, which breaks the transcription step of
  test12_FileTools (the app correctly says "too short to transcribe"). Fix: use a checked-in recording as the fixture.
- macOS Spotlight does read text in images (since Ventura) and Voice Memos/Notes can transcribe their own recordings;
  Spotlight's importers don't read speech in .m4a/.mov (checked with `mdimport -t` on macOS 26.6). Keep comparisons
  that precise.
- The CI Macs have a 1024×768 screen; UI tests and the film are recorded at that size.
- ShortcutRouter only handles keys for the main window; other windows (Fill & Sign, Quick Search) handle their own.

## Commits

Plain-English messages that say what changed for the user. Work on `haven-mac`; check the screenshots artifact
after UI changes. Don't commit build output (DerivedData, .build, DMGs).

## What's next

Licensing, update checks, Developer ID signing and notarization, and the website launch. The handoff notes that
came with this code (WHATS-LEFT.md and handoff/) describe each one; the website half is also in website/README.md.
