# Ribbon: windows that arrange themselves

A native macOS window manager that tiles automatically. Open a window and it takes its place; close one
and the others fill the space. Arrange everything with clicks from the menu bar panel (a live map of the
screen, a gallery of layouts, labelled buttons); every action also has an optional shortcut.
Menu bar app, SwiftUI settings, a two-minute tour, universal binary (Apple silicon + Intel), macOS 13+.

## Features
- Menu bar panel: click a layout picture (full, halves, 1 + 2, quarters, 3 or 4 columns, scrolling), click a
  window in the live map to switch to it, drag one onto another to swap, buttons for main / focus / float /
  swap / bigger / smaller / widths, every mode as a switch. ⌃⌥Space opens it; single keys work inside.
  VoiceOver labels and actions throughout.
- Scrolling layout (the PaperWM idea): columns on a strip that runs past the screen edges, three- or
  four-finger swipes, ⌃⌥ + scroll wheel, width presets (⅓ ½ ⅔ full).
- Automatic tiling per screen (each display and each Space): grid (main window left, the rest share the
  right; four makes a 2×2) or equal columns; tall screens stack rows. 1–4 windows per screen
  (⌃⌥⌘1–4), chosen per screen from the menu bar panel.
- Full screens stack the new window on the one in use (or float it, if you prefer); ⌃⌥` and the grip
  switch within a stack. Closing a window lets the others reflow.
- Swap with ⌃⌥ + arrows (crossing to the next display at an edge), ⌃⌥↩ makes the window the main one,
  ⌘-drag a title bar onto another window to swap, ⌥⌘-drag to stack, drag the edge between windows to
  resize (neighbours make room), ⌃⌥= / ⌃⌥- / ⌃⌥0 to grow, shrink and reset.
- Focus mode (⌃⌥Z), float (⌃⌥F), No peek (⌃⌥D: dim and blur the others), Clean Space (⌃⌥P: one window
  on a plain background), a ⌥⇥ window switcher that shows windows where they sit, quick actions on a
  grip above the window in use, hover focus.
- Highlights: border, all borders or glow, any colour. Learns each app's minimum size and floats a
  window that can't fit. Dialogs, sheets, panels and fixed-size windows are never tiled; per-app off
  switch from the menu bar. Pauses for Stage Manager. Layouts survive restarts.
- Automation: `ribbon://` URL scheme, a `ribbon` CLI (JSON state, config), Raycast script export.

## Layout of the code
```
Core/                  pure Swift (also builds on Linux): screens, tiles and stacks, layout geometry,
                       splits and minimum sizes, springs, config, shortcuts, session restore, IPC types
Sources/RibbonApp      the app: AX window control, Spaces, hotkeys, drag handling, overlays, SwiftUI UI
Sources/RibbonCLI      the `ribbon` command-line tool (talks to the app over a CFMessagePort)
Sources/RibbonFixture  a window-making app used only by the end-to-end tests
Core/Tests             unit tests (cd Core && swift test)
e2e/run_e2e.py         end-to-end tests against a real macOS session
scripts/               build_app.sh (universal .app, ad-hoc signed), make_dmg.sh (DMG + zip),
                       icon and DMG background generators
```

## Build
On a Mac with Xcode 15 or later: `scripts/build_app.sh && scripts/make_dmg.sh` → `dist/Ribbon-2.0.0.dmg`.
CI (`.github/workflows/ribbon.yml`) does the same on GitHub's macOS runners, runs the unit and
end-to-end tests, and publishes the DMG, screenshots and test report to the `ribbon-dist` branch.

The build is signed ad-hoc, not notarised, so the first launch needs System Settings → Privacy &
Security → Open Anyway (see `Resources/Read Me First.html`, which ships in the DMG).
