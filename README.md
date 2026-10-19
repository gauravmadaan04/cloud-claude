# Haven

A friendlier home for your files on macOS: big thumbnails, plain-English search, text inside images,
downloads grouped by where they came from, duplicates, and gentle clean-up. It runs alongside Finder,
and nothing leaves your Mac.

Haven is a personal build modelled on [Homy](https://tryhomy.app/), with some extras on top.

## What it does

| Area | What you get |
|---|---|
| Home | Library folders (Images, Videos, Music, Documents, Archives, Apps) with counts and sizes, a storage bar, Clean Up cards with "up to X GB to free", Downloaded From chips, shelves of recent photos, screenshots, videos, documents and music |
| Search (⌘F) | Plain English: "pdfs from last week", "screenshots over 5 MB", "photos from whatsapp", "big videos older than a year", "#work", "in downloads". Shows how it read the query as removable chips. Matches names, tags, folders and text inside files |
| Text in images (⇧⌘C) | Vision OCR on screenshots and recent photos, PDF text and documents, all on-device. Copy Text button on hover, Live Text selection in the big preview |
| Downloaded From (⇧⌘J) | Gmail, Google Drive, ChatGPT, Claude, Canva, Figma, X, Slack, WhatsApp, Telegram, GitHub, Dropbox, AirDrop, Mail, browser extensions, or any website. A "From" filter on every list |
| Duplicates (⇧⌘D) | SHA-256 for identical files, Vision feature prints for look-alike photos (bursts, edits, HEIC/JPEG pairs). Suggests what to keep; iCloud-only files are skipped |
| Clean Up (⇧⌘K) | Old installers, forgotten downloads, old screenshots, big old videos, unused apps, and zips that were already unzipped. Review first, Trash only, Undo always |
| Quick Search (⇧⌘Space) | Spotlight-style panel from any app: ↩ open, ⌘↩ show in Haven, ⌥↩ show in Finder, ⌘C copy. The shortcut can be changed |
| Menu bar | The ten newest downloads with thumbnails, ready to drag into other apps |
| Looks | Playful (pastel) and Minimal (black, white and grey), ⌃⌘T. Light, dark or system |
| Saved searches | Save any search to the sidebar; relative dates stay current |
| Rules (off by default) | Trash old installers, file screenshots into monthly folders, archive old downloads |
| Shortcuts & Siri | Find Files, Get Latest Download, Search in Haven |
| Also | Grid/list (⌘1/⌘2), card size (⌘+/⌘−), Quick Look (Space), large preview with ←/→, inspector (⌘I) with camera, duration and source, music player with media keys, multi-file drag out, right-click menu with Open With and Share, folder browsing with pinned folders, Activity page with Undo, launch at login, onboarding tour |

## Install

Download `Haven-1.0.0.dmg`, open it, drag Haven to Applications. The first time you open it, macOS
asks you to confirm because the app is ad-hoc signed rather than notarized:

- macOS 15 or later: System Settings › Privacy & Security › **Open Anyway**.
- macOS 14: right-click Haven › Open › Open.
- Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Haven.app`

The DMG also contains **Read Me First.pdf** with these steps and a short guide.

Requires macOS 14 Sonoma or later; universal binary (Apple silicon and Intel).

## Project layout

```
Packages/HavenCore   pure logic: file model, query parser, search, sources, duplicates, clean-up, rules (+ tests, run on Linux too)
App/                 the SwiftUI app: library index, OCR, thumbnails, views, Quick Search, menu bar, onboarding, settings, intents
Tests/HavenTests     integration tests run inside the app (OCR, PDFs, xattrs, Vision, Trash/Undo, full sample-folder checks)
Tests/HavenUITests   end-to-end UI tests that click through the app on a generated sample home folder and save screenshots
packaging/           DMG background, dmgbuild settings, Read Me First.pdf (make_art.py redraws them)
scripts/             make_icon.py (app icon), build_dmg.sh
project.yml          XcodeGen project
```

## Build

On a Mac with Xcode 16 or later:

```bash
brew install xcodegen
xcodegen generate
open Haven.xcodeproj            # or:
xcodebuild -scheme Haven -configuration Release build
scripts/build_dmg.sh build/.../Haven.app Haven.dmg
```

`.github/workflows/haven.yml` does all of this on GitHub's macOS runners: core tests, a Debug build, integration
tests, UI tests with screenshots, a universal Release build, a smoke test, and the DMG.

Try the app on sample files without touching your own:

```bash
Haven.app/Contents/MacOS/Haven -HavenFixtureRoot /tmp/haven-demo -HavenMakeFixtures YES -HavenResetState YES
```

(`-HavenMakeFixtures` is available in Debug builds.)
