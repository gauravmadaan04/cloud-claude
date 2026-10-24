#!/usr/bin/env python3
"""End-to-end tests for Ribbon in a real macOS session (GitHub's macOS runners).

Starts a fixture app that opens plain windows and reports their real frames, starts Ribbon,
drives it through the `ribbon` CLI and the ribbon:// URL scheme, and checks where the windows
actually end up. Screenshots and a JSON report go to --out.
"""
import argparse
import json
import os
import signal
import subprocess
import sys
import time
import traceback

ap = argparse.ArgumentParser()
ap.add_argument("--app", required=True)
ap.add_argument("--fixture", required=True)
ap.add_argument("--out", required=True)
args = ap.parse_args()

APP = os.path.abspath(args.app)
BIN = os.path.join(APP, "Contents/MacOS/Ribbon")
CLI = os.path.join(APP, "Contents/Helpers/ribbon")
FIX = os.path.abspath(args.fixture)
OUT = os.path.abspath(args.out)
FDIR = "/tmp/ribbon-fixture"
TDIR = "/tmp/ribbon-fixture-tabs"
os.makedirs(OUT, exist_ok=True)

results, shots, TESTS = [], [], []
logf = open(os.path.join(OUT, "e2e.log"), "w")
seq = 0
procs = {}


def say(*parts):
    s = " ".join(str(p) for p in parts)
    print(s, flush=True)
    logf.write(s + "\n")
    logf.flush()


def cli(*a, check=True, timeout=15):
    r = subprocess.run([CLI, *a], capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"`ribbon {' '.join(a)}` failed ({r.returncode}): {r.stderr.strip()} {r.stdout.strip()}")
    return r.stdout


def state():
    return json.loads(cli("state"))


def main_display(st):
    return next((d for d in st["displays"] if d["main"]), st["displays"][0])


def screen(st=None):
    """The tiled screen on the main display."""
    st = st or state()
    d = main_display(st)
    for s in st["screens"]:
        if s["active"] and s["display"] == d["uuid"]:
            return s
    return None


def tiles(sc):
    return [[w["title"] for w in t["windows"]] for t in sc["tiles"]]


def showing(sc=None):
    sc = sc or screen()
    out = []
    for t in sc["tiles"]:
        w = next((w for w in t["windows"] if w["id"] == t["showing"]), None)
        out.append(w["title"] if w else None)
    return out


def all_titles(sc=None):
    sc = sc or screen()
    return [t for tile in tiles(sc) for t in tile]


def tile_of(sc, title):
    for i, t in enumerate(tiles(sc)):
        if title in t:
            return i
    return None


def win(sc, title):
    for t in sc["tiles"]:
        for w in t["windows"]:
            if w["title"] == title:
                return w
    return None


def ids(st=None):
    st = st or state()
    out = {}
    for s in st["screens"]:
        for t in s["tiles"]:
            for w in t["windows"]:
                out[w["title"]] = w["id"]
    for w in st["floating"]:
        out[w["title"]] = w["id"]
    return out


def focused_title(st=None):
    st = st or state()
    f = st["focused"]
    return next((t for t, i in ids(st).items() if i == f), None)


def fixture_frames(d=FDIR):
    try:
        with open(os.path.join(d, "frames.json")) as fh:
            return {w["title"]: w for w in json.load(fh)["windows"]}
    except Exception:
        return {}


def fix(action, arg, d=FDIR):
    global seq
    seq += 1
    os.makedirs(os.path.join(d, "cmd"), exist_ok=True)
    open(os.path.join(d, "cmd", f"{seq:04d}_{action}_{arg}"), "w").close()


def close(a, b, tol=3):
    return abs(a - b) <= tol


def wait(pred, timeout=8.0, interval=0.15, what=""):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        try:
            last = pred()
            if last:
                return last
        except Exception as e:  # keep polling through transient errors
            last = e
        time.sleep(interval)
    raise AssertionError(f"timed out waiting for {what or 'condition'} (last: {last!r})")


def settled(st=None):
    """Every tiled window on the main screen sits where Ribbon wants it."""
    sc = screen(st)
    if not sc:
        return False
    for t in sc["tiles"]:
        for w in t["windows"]:
            f, g = w["frame"], w["target"]
            if f is None or g is None:
                return False
            # Scrolled out of view: parked at the edge, where macOS may nudge it; the size must match.
            n = 2 if w.get("parked") else 4
            if not all(close(f[i + (4 - n)], g[i + (4 - n)], 3) for i in range(n)):
                return False
    return True


def wait_settled(timeout=8):
    return wait(lambda: settled(), timeout=timeout, what="windows to settle")


def focus(title):
    fix("focus", title)
    wait(lambda: focused_title() == title, what=f"{title} in use")


def home():
    """Back to the starting arrangement: three fixtures in a grid, in order."""
    wait(lambda: showing() == ["Fixture 1", "Fixture 2", "Fixture 3"] and len(screen()["tiles"]) == 3, what="starting arrangement")
    wait_settled()


def shot(name):
    base = os.path.join(OUT, f"{len(shots) + 1:02d}-{name}")
    subprocess.run(["screencapture", "-x", base + ".png"], capture_output=True)
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "72", "-Z", "1600", base + ".png", "--out", base + ".jpg"],
                   capture_output=True)
    if os.path.exists(base + ".jpg"):
        os.remove(base + ".png")
        shots.append(os.path.basename(base + ".jpg"))


def test(name):
    def deco(fn):
        def run():
            t0 = time.time()
            try:
                fn()
                results.append({"name": name, "ok": True, "secs": round(time.time() - t0, 2)})
                say("PASS", name)
            except Exception as e:
                results.append({"name": name, "ok": False, "error": f"{type(e).__name__}: {e}", "secs": round(time.time() - t0, 2)})
                say("FAIL", name, "-", e)
                say(traceback.format_exc())
                try:
                    shot("FAIL-" + name.replace(" ", "-")[:40])
                    with open(os.path.join(OUT, f"state-at-failure-{len(results)}.json"), "w") as fh:
                        fh.write(cli("state", check=False))
                except Exception:
                    pass
        TESTS.append(run)
        return run
    return deco


def start_ribbon():
    env = dict(os.environ, RIBBON_DEBUG="1")
    out = open(os.path.join(OUT, "ribbon-stderr.log"), "a")
    procs["ribbon"] = subprocess.Popen([BIN, "--skip-onboarding", "--e2e"], stdout=out, stderr=out, env=env)
    wait(lambda: cli("ping", check=False, timeout=4).strip() == "pong", timeout=20, what="Ribbon to answer")


def area(st=None):
    return main_display(st or state())["area"]


GAP = 8


@test("Ribbon starts with Accessibility access")
def _():
    st = state()
    say("displays:", json.dumps(st["displays"]))
    assert st["accessibility"], "AXIsProcessTrusted() is false"
    assert st["running"], "window manager isn't running"


@test("open windows tile into a grid")
def _():
    wait(lambda: screen() and len(screen()["tiles"]) == 3, what="3 tiles")
    wait_settled()
    st = state()
    sc = screen(st)
    assert showing(sc) == ["Fixture 1", "Fixture 2", "Fixture 3"], tiles(sc)
    assert sc["layout"] == "grid" and sc["capacity"] == 3, (sc["layout"], sc["capacity"])
    ax, ay, aw, ah = area(st)
    half_w = (aw - GAP) / 2
    half_h = (ah - GAP) / 2
    f1, f2, f3 = (win(sc, t)["frame"] for t in ("Fixture 1", "Fixture 2", "Fixture 3"))
    assert close(f1[0], ax) and close(f1[1], ay) and close(f1[2], half_w) and close(f1[3], ah), f"primary {f1}, area {ax, ay, aw, ah}"
    assert close(f2[0], ax + half_w + GAP) and close(f2[1], ay) and close(f2[3], half_h), f"top right {f2}"
    assert close(f3[0], f2[0]) and close(f3[1], ay + half_h + GAP) and close(f3[3], half_h), f"bottom right {f3}"
    # Cross-check with what the fixture app itself reports.
    ff = fixture_frames()
    for t in ("Fixture 1", "Fixture 2", "Fixture 3"):
        mine, target = ff[t]["frame"], win(sc, t)["target"]
        assert all(close(mine[i], target[i], 3) for i in range(4)), f"{t}: app says {mine}, Ribbon wanted {target}"
    shot("grid-three-windows")


@test("fixed-size windows float instead of tiling")
def _():
    st = state()
    assert any(w["title"] == "Fixed" for w in st["floating"]), st["floating"]
    assert "Fixed" not in all_titles(screen(st))


@test("⌃⌥ + arrow swaps with the neighbour")
def _():
    focus("Fixture 1")
    cli("swap-right")
    wait(lambda: showing() == ["Fixture 2", "Fixture 1", "Fixture 3"], what="swapped right")
    cli("swap-down")
    wait(lambda: showing() == ["Fixture 2", "Fixture 3", "Fixture 1"], what="swapped down")
    wait_settled()
    shot("swapped")
    cli("swap-left")
    wait(lambda: showing() == ["Fixture 1", "Fixture 3", "Fixture 2"], what="swapped left")
    focus("Fixture 2")
    cli("swap-up")
    home()


@test("make the window in use the main one")
def _():
    focus("Fixture 3")
    cli("make-primary")
    wait(lambda: showing()[0] == "Fixture 3", what="Fixture 3 primary")
    wait_settled()
    f = win(screen(), "Fixture 3")["frame"]
    assert close(f[3], area()[3]), f"the main window takes the whole left side: {f}"
    focus("Fixture 1")
    cli("make-primary")
    home()


@test("a full screen stacks a new window on the one in use")
def _():
    focus("Fixture 2")
    fix("open", "Fixture 9")
    wait(lambda: "Fixture 9" in all_titles(), what="new window tiled")
    sc = screen()
    assert len(sc["tiles"]) == 3, tiles(sc)
    assert tile_of(sc, "Fixture 9") == tile_of(sc, "Fixture 2") == 1, tiles(sc)
    assert showing(sc)[1] == "Fixture 9", showing(sc)
    wait_settled()
    shot("stacked")
    cli("stack-next")
    wait(lambda: showing()[1] == "Fixture 2", what="the other window in the stack shows")
    fix("close", "Fixture 9")
    wait(lambda: "Fixture 9" not in all_titles(), what="stacked window closed")
    home()


@test("windows per screen: 4, 2 and back to 3")
def _():
    cli("tile-4")
    wait(lambda: screen()["capacity"] == 4)
    fix("open", "Fixture 8")
    wait(lambda: len(screen()["tiles"]) == 4, what="four tiles")
    wait_settled()
    st = state()
    sc = screen(st)
    ax, ay, aw, ah = area(st)
    f1, f4 = win(sc, "Fixture 1")["frame"], win(sc, "Fixture 8")["frame"]
    assert close(f4[0], ax) and close(f4[1], f1[1] + f1[3] + GAP), f"fourth window under the primary: {f1} {f4}"
    shot("grid-four")
    fix("close", "Fixture 8")
    wait(lambda: len(screen()["tiles"]) == 3, what="reflow to three")
    wait_settled()
    assert close(win(screen(), "Fixture 1")["frame"][3], area()[3]), "the primary has the whole left side again"
    cli("tile-2")
    wait(lambda: len(screen()["tiles"]) == 2, what="two tiles")
    sc = screen()
    assert len(sc["tiles"][1]["windows"]) == 2, f"the extra window joins the last tile's stack: {tiles(sc)}"
    wait_settled()
    shot("two-per-screen")
    cli("tile-3")
    wait(lambda: len(screen()["tiles"]) == 3 and all(len(t) == 1 for t in tiles(screen())), what="three tiles again")
    home()


@test("columns layout")
def _():
    cli("toggle-layout")
    wait(lambda: screen()["arrangement"] == "columns", what="columns (next layout)")
    wait_settled()
    st = state()
    sc = screen(st)
    ax, ay, aw, ah = area(st)
    w = (aw - 2 * GAP) / 3
    frames = [win(sc, t)["frame"] for t in showing(sc)]
    for f in frames:
        assert close(f[3], ah) and close(f[2], w), f"column {f}, expected {w}x{ah}"
    shot("columns")
    cli("arrange", "grid", "3")
    wait(lambda: screen()["arrangement"] == "grid", what="grid again")
    home()


@test("one click picks a layout (the menu bar gallery)")
def _():
    cli("arrange", "grid", "2")
    wait(lambda: len(screen()["tiles"]) == 2 and screen()["capacity"] == 2, what="halves")
    wait_settled()
    cli("arrange", "columns", "3")
    wait(lambda: screen()["arrangement"] == "columns" and len(screen()["tiles"]) == 3, what="three columns")
    wait_settled()
    cli("arrange", "grid", "3")
    home()


@test("scrolling layout: columns run past the screen")
def _():
    focus("Fixture 1")
    cli("arrange", "scrolling")
    wait(lambda: screen()["arrangement"] == "scrolling", what="scrolling layout")
    wait_settled()
    st = state()
    sc = screen(st)
    a = area(st)
    f1 = win(sc, "Fixture 1")["frame"]
    assert close(f1[0], a[0]) and close(f1[2], (a[2] - GAP) / 2), f"first column {f1}, area {a}"
    assert win(sc, "Fixture 3")["parked"], "the third column waits at the screen edge"
    shot("scrolling")
    focus("Fixture 3")
    wait(lambda: not win(screen(), "Fixture 3")["parked"] and win(screen(), "Fixture 1")["parked"], what="the strip scrolls to Fixture 3")
    wait_settled()
    f3 = win(screen(), "Fixture 3")["frame"]
    assert close(f3[0] + f3[2], a[0] + a[2]), f"Fixture 3 meets the right edge: {f3}"
    shot("scrolled")
    cli("cycle-width")
    wait(lambda: close(screen()["tiles"][2]["width"] or 0, 2 / 3, 0.01), what="a wider column")
    focus("Fixture 1")
    fix("open", "Fixture 7")
    wait(lambda: "Fixture 7" in all_titles(), what="new column")
    assert showing()[1] == "Fixture 7", f"opens next to the window in use: {showing()}"
    fix("close", "Fixture 7")
    wait(lambda: "Fixture 7" not in all_titles(), what="column closed")
    cli("reset-sizes")
    cli("arrange", "grid", "3")
    home()
    assert not any(w["parked"] for t in screen()["tiles"] for w in t["windows"]), "nothing left parked"


@test("⌃⌥Space opens the menu bar panel")
def _():
    focus("Fixture 1")
    cli("open-menu")
    time.sleep(1.0)
    shot("menu-from-keyboard")
    cli("open-menu")
    time.sleep(0.4)


@test("make bigger, smaller and reset sizes")
def _():
    focus("Fixture 1")
    w0 = win(screen(), "Fixture 1")["frame"][2]
    cli("grow")
    wait(lambda: close(screen()["splits"]["x"], 0.55, 0.001), what="split at 55%")
    wait_settled()
    assert win(screen(), "Fixture 1")["frame"][2] > w0 + 30, "primary got wider"
    cli("shrink")
    cli("shrink")
    wait(lambda: close(screen()["splits"]["x"], 0.45, 0.001), what="split at 45%")
    cli("reset-sizes")
    wait(lambda: close(screen()["splits"]["x"], 0.5, 0.001), what="split reset")
    home()


@test("focus mode fills the screen and comes back")
def _():
    focus("Fixture 2")
    cli("focus-mode")
    wait(lambda: screen()["zoomed"] == ids()["Fixture 2"], what="Fixture 2 zoomed")
    wait_settled()
    f = win(screen(), "Fixture 2")["frame"]
    a = area()
    assert all(close(f[i], a[i]) for i in range(4)), f"zoomed {f} vs area {a}"
    shot("focus-mode")
    cli("focus-mode")
    wait(lambda: screen()["zoomed"] is None, what="back to the layout")
    home()


@test("float and tile a window again")
def _():
    focus("Fixture 2")
    cli("toggle-float")
    wait(lambda: any(w["title"] == "Fixture 2" for w in state()["floating"]), what="floating")
    wait(lambda: showing() == ["Fixture 1", "Fixture 3"], what="the others fill the space")
    wait_settled()
    shot("floating")
    cli("toggle-float")
    home()


@test("minimise and restore keeps the place")
def _():
    fix("minimize", "Fixture 2")
    wait(lambda: showing() == ["Fixture 1", "Fixture 3"], what="minimised window leaves")
    fix("unminimize", "Fixture 2")
    home()


@test("native tabs share one tile")
def _():
    cli("tile-4")
    wait(lambda: screen()["capacity"] == 4)
    procs["tabs"] = subprocess.Popen([FIX, "--windows", "0", "--tabs", "--dir", TDIR],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait(lambda: len(screen()["tiles"]) == 4, timeout=10, what="one tile for the tab group")
    time.sleep(1.5)
    tabs = [t for t in all_titles() if t.startswith("Tab")]
    assert len(tabs) == 1, tiles(screen())
    shot("native-tabs")
    fix("quit", "x", d=TDIR)
    wait(lambda: len(screen()["tiles"]) == 3, timeout=10, what="tab group gone")
    cli("tile-3")
    home()


@test("apps that refuse to shrink get room without overlap")
def _():
    a = area()
    minw = int(a[2] * 0.68)
    fix("minwidth", f"Fixture 2={minw}")
    focus("Fixture 2")
    cli("retile")
    wait(lambda: win(screen(), "Fixture 2")["target"][2] >= minw - 2, timeout=10, what="layout learns the minimum width")
    wait_settled()
    sc = screen()
    f1, f2 = win(sc, "Fixture 1")["frame"], win(sc, "Fixture 2")["frame"]
    assert f2[2] >= minw - 2, f2
    assert f2[0] >= f1[0] + f1[2] + GAP - 1, f"overlap: {f1} then {f2}"
    shot("min-width")
    fix("minwidth", "Fixture 2=200")
    time.sleep(0.8)
    cli("reset-sizes")
    wait(lambda: win(screen(), "Fixture 2")["target"][2] < minw - 50, what="minimum forgotten")
    home()


@test("⌘-drag swaps two windows")
def _():
    sc = screen()
    f1, f3 = win(sc, "Fixture 1")["frame"], win(sc, "Fixture 3")["frame"]
    start = (f1[0] + f1[2] * 0.5, f1[1] + 12)
    end = (f3[0] + f3[2] * 0.5, f3[1] + f3[3] * 0.5)
    cli("debug-drag", str(start[0]), str(start[1]), str(end[0]), str(end[1]), "cmd")
    wait(lambda: showing() == ["Fixture 3", "Fixture 2", "Fixture 1"], timeout=10, what="dragged window swapped")
    wait_settled()
    shot("drag-swapped")
    focus("Fixture 1")
    cli("make-primary")
    home()


@test("dragging the edge between windows resizes both")
def _():
    sc = screen()
    f1 = win(sc, "Fixture 1")["frame"]
    edge = (f1[0] + f1[2] - 1, f1[1] + f1[3] * 0.5)
    cli("debug-drag", str(edge[0]), str(edge[1]), str(edge[0] + 120), str(edge[1]), "none")
    wait(lambda: screen()["splits"]["x"] > 0.56, timeout=10, what="split moved by the drag")
    wait(lambda: not screen()["dragging"], timeout=10, what="drag finished")
    wait_settled()
    sc = screen()
    f1, f2 = win(sc, "Fixture 1")["frame"], win(sc, "Fixture 2")["frame"]
    assert close(f2[0], f1[0] + f1[2] + GAP), f"the neighbour made room: {f1} {f2}"
    shot("edge-resized")
    cli("reset-sizes")
    home()


@test("ribbon:// URLs run commands")
def _():
    subprocess.run(["open", "-g", "ribbon://tile-2"], check=True)
    wait(lambda: screen()["capacity"] == 2, what="URL tile-2")
    subprocess.run(["open", "-g", "ribbon://command/tile-3"], check=True)
    wait(lambda: screen()["capacity"] == 3, what="URL tile-3")
    home()


@test("settings apply instantly (spacing)")
def _():
    cli("config", "set", "spacing", "0")

    def touching():
        st = state()
        sc = screen(st)
        f1, f2 = win(sc, "Fixture 1")["frame"], win(sc, "Fixture 2")["frame"]
        vx = main_display(st)["visible"][0]
        return close(f1[0], vx, 1) and close(f2[0], f1[0] + f1[2], 1)
    try:
        wait(touching, what="edge-to-edge windows")
        shot("no-spacing")
    finally:
        cli("config", "set", "spacing", "8")
    home()


@test("highlight styles: border, all borders, glow")
def _():
    focus("Fixture 1")
    for style in ("activeBorder", "allBorders", "glow"):
        cli("config", "set", "highlight", style)
        time.sleep(0.8)
        shot(f"highlight-{style}")
    cli("config", "set", "highlight", "activeBorder")


@test("No peek dims the other windows")
def _():
    focus("Fixture 2")
    cli("no-peek")
    wait(lambda: state()["noPeek"], what="no peek on")
    time.sleep(1.0)
    shot("no-peek")
    cli("no-peek")
    wait(lambda: not state()["noPeek"], what="no peek off")


@test("Clean Space shows one window on a plain background")
def _():
    focus("Fixture 2")
    cli("clean-space")
    wait(lambda: state()["cleanSpace"] and screen()["zoomed"] == ids()["Fixture 2"], what="clean space on")
    wait_settled()
    time.sleep(0.6)
    shot("clean-space")
    cli("clean-space")
    wait(lambda: not state()["cleanSpace"] and screen()["zoomed"] is None, what="clean space off")
    home()


@test("window switcher shows every window and switches")
def _():
    focus("Fixture 1")
    cli("tab-view-open")
    info = wait(lambda: (lambda j: j if j["open"] else None)(json.loads(cli("tab-view-state"))), what="switcher open")
    assert info["count"] >= 4, info
    time.sleep(0.6)
    shot("window-switcher")
    cli("tab-view-next")
    target = json.loads(cli("tab-view-state"))["selected"]
    cli("tab-view-commit")
    wait(lambda: state()["focused"] == target, what="switched to the selected window")
    focus("Fixture 1")


@test("quick actions grip, menu bar panel, cheat sheet and settings render")
def _():
    focus("Fixture 1")
    time.sleep(0.8)
    shot("grip")
    cli("show-menu")
    time.sleep(1.0)
    shot("menu-panel")
    cli("hide-menu")
    time.sleep(0.4)
    cli("show-shortcuts")
    time.sleep(0.8)
    shot("cheat-sheet")
    cli("show-shortcuts")
    for pane in ["general", "layout", "highlight", "shortcuts", "apps", "advanced", "about"]:
        cli("show-settings", pane)
        time.sleep(1.2)
        shot(f"settings-{pane}")
        assert cli("ping", check=False, timeout=4).strip() == "pong", f"Ribbon stopped responding on the {pane} pane"
    cli("close-windows")
    time.sleep(0.3)


@test("welcome tour renders every step")
def _():
    for step in range(7):
        cli("show-onboarding", str(step))
        time.sleep(1.8)
        shot(f"tour-step-{step}")
    cli("close-windows")


@test("pausing leaves every window where it is")
def _():
    home()
    before = {t: fixture_frames()[t]["frame"] for t in ("Fixture 1", "Fixture 2", "Fixture 3")}
    cli("pause")
    wait(lambda: not state()["running"], what="paused")
    time.sleep(1.0)
    after = {t: fixture_frames()[t]["frame"] for t in before}
    for t in before:
        assert all(close(before[t][i], after[t][i], 2) for i in range(4)), f"{t} moved: {before[t]} -> {after[t]}"
    cli("resume")
    wait(lambda: state()["running"] and screen() and len(screen()["tiles"]) == 3, what="resumed")
    home()


@test("layout survives quitting and reopening Ribbon")
def _():
    focus("Fixture 3")
    cli("make-primary")
    cli("toggle-layout")
    wait(lambda: showing() == ["Fixture 3", "Fixture 2", "Fixture 1"] and screen()["layout"] == "columns", what="custom layout")
    wait_settled()
    time.sleep(1.5)  # let the debounced save land
    cli("quit")
    procs["ribbon"].wait(timeout=10)
    start_ribbon()
    wait(lambda: screen() and len(screen()["tiles"]) == 3, timeout=10, what="screen after restart")
    sc = screen()
    assert showing(sc) == ["Fixture 3", "Fixture 2", "Fixture 1"], showing(sc)
    assert sc["layout"] == "columns", sc["layout"]
    wait_settled()
    shot("after-restart")
    cli("arrange", "grid", "3")
    focus("Fixture 1")
    cli("make-primary")
    home()


@test("a real app (Finder) is tiled")
def _():
    cli("tile-4")
    subprocess.run(["open", "/Applications"], check=True)
    wait(lambda: any(w["app"] == "Finder" for t in screen()["tiles"] for w in t["windows"]), timeout=10, what="Finder window")
    wait_settled(timeout=10)
    shot("finder")


def main():
    say("Ribbon e2e on", subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip())
    subprocess.run(["defaults", "delete", "in.thegent.ribbon"], capture_output=True)
    subprocess.run(["rm", "-rf", os.path.expanduser("~/Library/Application Support/Ribbon"), FDIR, TDIR])
    os.makedirs(os.path.join(FDIR, "cmd"), exist_ok=True)
    procs["fixture"] = subprocess.Popen([FIX, "--windows", "3", "--fixed", "--dir", FDIR],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait(lambda: len(fixture_frames()) == 4, timeout=15, what="fixture windows")
    time.sleep(0.5)
    with open(os.path.join(FDIR, "frames.json")) as fh:
        say("fixture:", fh.read())
    shot("before-ribbon")
    try:
        start_ribbon()
        time.sleep(1.0)
        for t in TESTS:
            t()
    except Exception as e:
        results.append({"name": "start Ribbon", "ok": False, "error": f"{type(e).__name__}: {e}", "secs": 0})
        say(traceback.format_exc())
    passed = sum(r["ok"] for r in results)
    report = {"passed": passed, "failed": len(results) - passed, "results": results, "screenshots": shots}
    with open(os.path.join(OUT, "report.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    lines = [f"# Ribbon end-to-end tests: {passed}/{len(results)} passed", ""]
    lines += [f"- {'✅' if r['ok'] else '❌'} {r['name']} ({r['secs']}s)" + ("" if r["ok"] else f" — {r['error']}") for r in results]
    with open(os.path.join(OUT, "REPORT.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    say("\n".join(lines))
    for p in procs.values():
        try:
            p.send_signal(signal.SIGTERM)
        except Exception:
            pass
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
