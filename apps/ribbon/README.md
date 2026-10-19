# Ribbon: a scrolling window manager for macOS

Every window is a column on one horizontal strip that runs past the screen edges, so opening a window
never squeezes the others (the PaperWM / niri idea, made native for macOS). Menu bar app, SwiftUI
settings, guided onboarding, universal binary (Apple silicon + Intel), macOS 13 or later.

## Features
- Columns on a strip with spring animation; each display and each Space keeps its own strip.
- Focus / move / jump (⌃⌥ + H J K L or arrows, ⌃⌥1–9, ⌃⌥⇥ back), send to the next display (⌃⌥N).
- Preset widths (⌃⌥R), wider/narrower, full width, centre, three centring modes.
- Stacks (⌃⌥[ ⌃⌥]), pop out, taller/shorter/equalise, tabbed columns with a clickable tab bar (⌃⌥⇧T).
- Pin a column to the left or right edge (⌃⌥P / ⌃⌥⇧P), float any window (⌃⌥T).
- Trackpad swipes (3 or 4 fingers) that follow your fingers and settle on the nearest column;
  ⌃⌥ + scroll wheel for mice.
- Strip map: hold ⌃⌥ to see it; click a tile to jump, drag tiles to reorder. Shortcut cheat sheet (⌃⌥/).
- Drag windows by the title bar to reorder or move them to another display; resize by dragging edges.
- Session restore across restarts, native macOS tabs share a column, dialogs and fixed-size windows
  float, apps that refuse to shrink are respected, no focus stealing, sleep/display-change recovery.
- Focus border, dimming, focus-follows-mouse (all off by default), per-app rules, excluded displays,
  rebindable shortcuts that work on any keyboard layout.
- Mac Setup checks (other window managers, Stage Manager, macOS edge tiling, trackpad gesture clashes,
  Spaces settings) with one-click fixes.
- Automation: `ribbon://` URL scheme, a `ribbon` CLI (JSON state, config, doctor), Raycast script export.

## Layout of the code
```
Sources/RibbonCore     pure Swift (also builds on Linux): strip model, layout, scrolling, springs,
                       config, shortcuts, swipe recogniser, session restore, IPC types
Sources/RibbonApp      the app: AX window control, Spaces, hotkeys, trackpad, overlays, SwiftUI UI
Sources/RibbonCLI      the `ribbon` command-line tool (talks to the app over a CFMessagePort)
Sources/RibbonFixture  a window-making app used only by the end-to-end tests
Tests/RibbonCoreTests  unit tests (swift test)
e2e/run_e2e.py         end-to-end tests against a real macOS session
scripts/               build_app.sh (universal .app, ad-hoc signed), make_dmg.sh (DMG + zip),
                       icon and DMG background generators
```

## Build
On a Mac with Xcode 15 or later: `scripts/build_app.sh && scripts/make_dmg.sh` → `dist/Ribbon-1.0.0.dmg`.
CI (`.github/workflows/ribbon.yml`) does the same on GitHub's macOS runners, runs the unit and
end-to-end tests, and publishes the DMG, screenshots and test report to the `ribbon-dist` branch.

The build is signed ad-hoc, not notarised, so the first launch needs System Settings → Privacy &
Security → Open Anyway (see `Resources/Read Me First.html`, which ships in the DMG).
