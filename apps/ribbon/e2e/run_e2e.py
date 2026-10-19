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
CLI = os.path.join(APP, "Contents/MacOS/ribbon")
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


def active_strip(st=None):
    st = st or state()
    d = main_display(st)
    for s in st["strips"]:
        if s["active"] and s["display"] == d["uuid"]:
            return s
    return None


def titles(strip):
    return [[w["title"] for w in c["windows"]] for c in strip["columns"]]


def flat_titles(strip):
    return [t for c in titles(strip) for t in c]


def col_of(strip, title):
    for i, c in enumerate(strip["columns"]):
        if any(w["title"] == title for w in c["windows"]):
            return i
    return None


def focused_title(st=None):
    st = st or state()
    s = active_strip(st)
    f = s["focused"]
    c = s["columns"][f]
    return c["windows"][c["active"]]["title"]


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
    """Every window in the active strip sits where Ribbon wants it (or is parked off screen)."""
    st = st or state()
    s = active_strip(st)
    if not s:
        return False
    d = main_display(st)
    fx, fy, fw, fh = d["frame"]
    for c in s["columns"]:
        for w in c["windows"]:
            f, t = w["frame"], w["target"]
            if f is None or t is None:
                return False
            if w["visibility"] in ("visible", "partial"):
                if not all(close(f[i], t[i], 3) for i in range(4)):
                    return False
            elif w["visibility"].startswith("hidden"):
                on_screen = min(f[0] + f[2], fx + fw) - max(f[0], fx)
                if on_screen > 4 and f[1] < fy + fh - 4:
                    return False
    return True


def wait_settled(timeout=8):
    return wait(lambda: settled(), timeout=timeout, what="windows to settle")


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
    wait(lambda: cli("ping", check=False).strip() == "pong", timeout=15, what="Ribbon to answer")


def geometry(st):
    d = main_display(st)
    vx, vy, vw, vh = d["visible"]
    cfg_gap = 10
    return vx, vy, vw, vh, cfg_gap


def px_width(frac, vw, gap=10, outer=10):
    working = vw - 2 * outer
    return min(working, max(80, frac * (working + gap) - gap))


# ---------------------------------------------------------------------------------------------

@test("Ribbon starts with Accessibility access")
def _():
    st = state()
    say("displays:", json.dumps(st["displays"]))
    assert st["accessibility"], "AXIsProcessTrusted() is false"
    assert st["running"], "window manager isn't running"


@test("existing windows are tiled side by side")
def _():
    wait(lambda: active_strip() and len(active_strip()["columns"]) == 3, what="3 columns")
    wait_settled()
    st = state()
    s = active_strip(st)
    assert flat_titles(s) == ["Fixture 1", "Fixture 2", "Fixture 3"], titles(s)
    vx, vy, vw, vh, g = geometry(st)
    expected_w = round(px_width(0.5, vw))
    cols = [c["windows"][0] for c in s["columns"]]
    f0 = cols[0]["frame"]
    assert close(f0[0], vx + 10) and close(f0[1], vy + 10), f"first column at {f0}, area {vx, vy}"
    assert close(f0[2], expected_w, 2) and close(f0[3], vh - 20, 2), f"size {f0[2:]} != {expected_w}x{vh - 20}"
    f1 = cols[1]["frame"]
    assert close(f1[0], f0[0] + f0[2] + 10), f"second column x {f1[0]} should follow first ({f0[0] + f0[2] + 10})"
    # Cross-check with what the fixture app itself reports.
    ff = fixture_frames()
    for w in cols:
        if w["visibility"] == "visible":
            mine = ff[w["title"]]["frame"]
            assert all(close(mine[i], w["target"][i], 3) for i in range(4)), f"{w['title']}: app says {mine}, Ribbon wanted {w['target']}"
    shot("tiled-three-windows")


@test("fixed-size windows float instead of tiling")
def _():
    st = state()
    assert any(w["title"] == "Fixed" for w in st["floating"]), st["floating"]
    assert "Fixed" not in flat_titles(active_strip(st))


@test("focus moves along the strip and off-screen windows are parked")
def _():
    cli("focus-first")
    wait(lambda: active_strip()["focused"] == 0, what="focus on first column")
    cli("focus-right")
    cli("focus-right")
    wait(lambda: active_strip()["focused"] == 2, what="focus on third column")
    wait_settled()
    st = state()
    s = active_strip(st)
    assert s["columns"][2]["visibility"] == "visible", s["columns"][2]["visibility"]
    assert s["columns"][0]["visibility"] == "hidden-left", s["columns"][0]["visibility"]
    d = main_display(st)
    parked = s["columns"][0]["windows"][0]["frame"]
    assert parked[0] + parked[2] <= d["frame"][0] + 2, f"parked window still on screen: {parked}"
    assert fixture_frames()["Fixture 3"]["key"], "fixture didn't receive focus"
    shot("scrolled-to-third")


@test("moving a window reorders the strip")
def _():
    t = focused_title()
    before = flat_titles(active_strip())
    cli("move-left")
    wait(lambda: flat_titles(active_strip()).index(t) == before.index(t) - 1, what="window to move left")
    wait_settled()
    cli("move-right")
    wait(lambda: flat_titles(active_strip()) == before, what="order back")


@test("width presets cycle and full width toggles")
def _():
    cli("focus-first")
    wait(lambda: active_strip()["focused"] == 0)
    cli("cycle-width")
    wait(lambda: close(active_strip()["columns"][0]["width"], 2 / 3, 0.01), what="2/3 width")
    wait_settled()
    st = state()
    vw = main_display(st)["visible"][2]
    f = active_strip(st)["columns"][0]["windows"][0]["frame"]
    assert close(f[2], px_width(2 / 3, vw), 2), f"width {f[2]} != {px_width(2 / 3, vw)}"
    cli("full-width")
    wait(lambda: active_strip()["columns"][0]["width"] == 1.0, what="full width")
    wait_settled()
    f = active_strip()["columns"][0]["windows"][0]["frame"]
    assert close(f[2], vw - 20, 2), f"full width {f[2]} != {vw - 20}"
    shot("full-width")
    cli("full-width")
    wait(lambda: close(active_strip()["columns"][0]["width"], 2 / 3, 0.01), what="back from full width")
    for _ in range(3):  # 2/3 -> 3/4 -> 1/4 -> 1/3
        cli("cycle-width")
    cli("cycle-width")
    wait(lambda: close(active_strip()["columns"][0]["width"], 0.5, 0.01), what="back to half width")
    wait_settled()


@test("stacking, tabs and popping out")
def _():
    cli("focus-2")
    wait(lambda: active_strip()["focused"] == 1)
    cli("stack-left")
    wait(lambda: titles(active_strip())[0] == ["Fixture 1", "Fixture 2"], what="stacked column")
    wait_settled()
    st = state()
    vy, vh = main_display(st)["visible"][1], main_display(st)["visible"][3]
    a, b = [w["frame"] for w in active_strip(st)["columns"][0]["windows"]]
    assert close(a[1], vy + 10) and close(b[1], a[1] + a[3] + 10), f"stack positions {a} {b}"
    assert close(b[1] + b[3], vy + vh - 10), f"stack bottom {b}"
    shot("stacked")
    cli("taller")
    wait(lambda: active_strip()["columns"][0]["windows"][1]["target"][3] > b[3] + 20, what="taller")
    cli("equalize-heights")
    cli("toggle-tabbed")
    wait(lambda: active_strip()["columns"][0]["mode"] == "tabbed", what="tabbed")
    wait_settled()
    vis = [w["visibility"] for w in active_strip()["columns"][0]["windows"]]
    assert sorted(vis) == ["hidden-left", "visible"] or sorted(vis) == ["hidden-right", "visible"], vis
    time.sleep(0.4)
    shot("tabbed-column")
    cli("focus-up")
    wait(lambda: focused_title() == "Fixture 1", what="previous tab")
    cli("toggle-tabbed")
    cli("focus-down")
    wait(lambda: focused_title() == "Fixture 2")
    cli("pop-right")
    wait(lambda: titles(active_strip()) == [["Fixture 1"], ["Fixture 2"], ["Fixture 3"]], what="popped out")
    wait_settled()


@test("pinning a window to the left edge")
def _():
    cli("focus-last")
    wait(lambda: active_strip()["focused"] == 2)
    cli("pin-left")
    wait(lambda: active_strip()["columns"][0]["pin"] == "left" and titles(active_strip())[0] == ["Fixture 3"], what="pinned")
    wait_settled()
    st = state()
    f = active_strip(st)["columns"][0]["windows"][0]["frame"]
    assert close(f[0], main_display(st)["visible"][0] + 10), f
    shot("pinned-left")
    cli("pin-left")
    wait(lambda: all(c["pin"] is None for c in active_strip()["columns"]), what="unpinned")
    cli("move-last")
    wait(lambda: flat_titles(active_strip()) == ["Fixture 1", "Fixture 2", "Fixture 3"], what="original order")
    wait_settled()


@test("float and re-tile a window")
def _():
    cli("focus-2")
    wait(lambda: focused_title() == "Fixture 2")
    cli("toggle-float")
    wait(lambda: any(w["title"] == "Fixture 2" for w in state()["floating"]), what="floating")
    assert "Fixture 2" not in flat_titles(active_strip())
    time.sleep(0.5)
    shot("floating")
    cli("toggle-float")
    wait(lambda: "Fixture 2" in flat_titles(active_strip()), what="tiled again")
    wait_settled()


@test("new windows open next to the focused one")
def _():
    cli("focus-first")
    wait(lambda: active_strip()["focused"] == 0)
    fix("focus", "Fixture 1")
    time.sleep(0.5)
    fix("open", "Fixture 9")
    wait(lambda: "Fixture 9" in flat_titles(active_strip()), what="new window tiled")
    s = active_strip()
    assert col_of(s, "Fixture 9") == 1, titles(s)
    wait(lambda: focused_title() == "Fixture 9", what="new window focused")
    wait_settled()
    shot("new-window")


@test("closing a window closes the gap")
def _():
    fix("close", "Fixture 9")
    wait(lambda: "Fixture 9" not in flat_titles(active_strip()), what="window removed")
    wait_settled()
    st = state()
    s = active_strip(st)
    vis = [c["windows"][0]["frame"] for c in s["columns"] if c["visibility"] == "visible"]
    for a, b in zip(vis, vis[1:]):
        assert close(b[0], a[0] + a[2] + 10), f"gap between {a} and {b}"


@test("minimise and restore keeps the place")
def _():
    before = flat_titles(active_strip())
    fix("minimize", "Fixture 2")
    wait(lambda: "Fixture 2" not in flat_titles(active_strip()), what="minimised window leaves the strip")
    fix("unminimize", "Fixture 2")
    wait(lambda: flat_titles(active_strip()) == before, timeout=10, what="window back in the same place")
    wait_settled()


@test("native tabs share one column")
def _():
    n = len(active_strip()["columns"])
    env = dict(os.environ)
    procs["tabs"] = subprocess.Popen([FIX, "--windows", "0", "--tabs", "--dir", TDIR], env=env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait(lambda: len(active_strip()["columns"]) == n + 1, timeout=10, what="one column for the tab group")
    time.sleep(1.5)
    s = active_strip()
    tabs = [t for t in flat_titles(s) if t.startswith("Tab")]
    assert len(tabs) == 1, titles(s)
    shot("native-tabs")
    fix("quit", "x", d=TDIR)
    wait(lambda: len(active_strip()["columns"]) == n, timeout=10, what="tab group gone")
    wait_settled()


@test("apps that refuse to shrink keep their width without overlap")
def _():
    st = state()
    vw = main_display(st)["visible"][2]
    minw = int(min(900, vw * 0.6))
    fix("minwidth", f"Fixture 1={minw}")
    cli("focus-first")
    wait(lambda: active_strip()["focused"] == 0)
    for _ in range(3):  # 1/2 -> 2/3 -> 3/4 -> 1/4
        cli("cycle-width")
    wait(lambda: close(active_strip()["columns"][0]["width"], 0.25, 0.01), what="quarter width requested")
    wait(lambda: active_strip()["columns"][0]["windows"][0]["target"][2] >= minw - 2, timeout=8, what="layout learns min width")
    wait_settled()
    s = active_strip()
    a = s["columns"][0]["windows"][0]["frame"]
    b = s["columns"][1]["windows"][0]["frame"]
    assert a[2] >= minw - 2, a
    assert b[0] >= a[0] + a[2] + 9, f"overlap: {a} then {b}"
    fix("minwidth", "Fixture 1=200")
    cli("cycle-width")
    wait(lambda: close(active_strip()["columns"][0]["width"], 1 / 3, 0.01))
    cli("cycle-width")
    wait(lambda: close(active_strip()["columns"][0]["width"], 0.5, 0.01))
    wait_settled()


@test("ribbon:// URLs run commands")
def _():
    subprocess.run(["open", "-g", "ribbon://focus-last"], check=True)
    wait(lambda: active_strip()["focused"] == len(active_strip()["columns"]) - 1, what="URL focus-last")
    subprocess.run(["open", "-g", "ribbon://command/focus-first"], check=True)
    wait(lambda: active_strip()["focused"] == 0, what="URL focus-first")


@test("settings apply instantly (gaps)")
def _():
    cli("config", "set", "innerGap", "0")
    cli("config", "set", "outerGap", "0")

    def touching():
        st = state()
        s = active_strip(st)
        vis = [c["windows"][0]["frame"] for c in s["columns"] if c["visibility"] == "visible"]
        vx = main_display(st)["visible"][0]
        return len(vis) >= 2 and close(vis[0][0], vx, 1) and all(close(b[0], a[0] + a[2], 1) for a, b in zip(vis, vis[1:]))
    wait(touching, what="edge-to-edge windows")
    shot("no-gaps")
    cli("config", "set", "innerGap", "10")
    cli("config", "set", "outerGap", "10")
    wait_settled()


@test("Mac Setup checks run")
def _():
    out = cli("doctor")
    say(out)
    assert "Accessibility" in out


@test("strip map, cheat sheet and settings render")
def _():
    cli("show-strip")
    time.sleep(0.6)
    shot("strip-map")
    cli("show-shortcuts")
    time.sleep(0.8)
    shot("cheat-sheet")
    cli("show-shortcuts")
    for pane in ["general", "layout", "appearance", "shortcuts", "trackpad", "setup", "automation"]:
        cli("show-settings", pane)
        time.sleep(0.9)
        shot(f"settings-{pane}")
    cli("close-windows")
    time.sleep(0.3)


@test("welcome tour renders every step")
def _():
    for step in range(7):
        cli("show-onboarding", str(step))
        time.sleep(1.2)
        shot(f"onboarding-step-{step}")
    cli("close-windows")


@test("focus border and dimming")
def _():
    cli("config", "set", "focusBorder", "true")
    cli("config", "set", "dimUnfocused", "true")
    cli("focus-2")
    time.sleep(1.0)
    shot("border-and-dim")
    cli("config", "set", "focusBorder", "false")
    cli("config", "set", "dimUnfocused", "false")


@test("pausing puts every window back on screen")
def _():
    cli("focus-last")
    wait_settled()
    cli("pause")
    wait(lambda: not state()["running"], what="paused")
    st = state()
    d = main_display(st)
    fx, fy, fw, fh = d["frame"]

    def all_on_screen():
        ff = fixture_frames()
        for t in ("Fixture 1", "Fixture 2", "Fixture 3"):
            x, y, w, h = ff[t]["frame"]
            if min(x + w, fx + fw) - max(x, fx) < w * 0.5:
                return False
        return True
    wait(all_on_screen, what="windows visible after pause")
    shot("paused")
    cli("resume")
    wait(lambda: state()["running"] and active_strip() and len(active_strip()["columns"]) == 3, what="resumed")
    wait_settled()


@test("layout survives quitting and reopening Ribbon")
def _():
    cli("focus-2")
    cli("cycle-width")
    cli("move-right")
    wait(lambda: flat_titles(active_strip()) == ["Fixture 1", "Fixture 3", "Fixture 2"], what="custom layout")
    wait_settled()
    before = [(c["windows"][0]["title"], round(c["width"], 3)) for c in active_strip()["columns"]]
    time.sleep(1.5)  # let the debounced save land
    cli("quit")
    procs["ribbon"].wait(timeout=10)
    start_ribbon()
    wait(lambda: active_strip() and len(active_strip()["columns"]) == 3, timeout=10, what="strip after restart")
    after = [(c["windows"][0]["title"], round(c["width"], 3)) for c in active_strip()["columns"]]
    assert after == before, f"{before} -> {after}"
    wait_settled()
    shot("after-restart")


@test("a real app (Finder) is tiled")
def _():
    subprocess.run(["open", "/Applications"], check=True)
    wait(lambda: any(w["app"] == "Finder" for c in active_strip()["columns"] for w in c["windows"]), timeout=10, what="Finder window")
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
    start_ribbon()
    time.sleep(1.0)
    for t in TESTS:
        t()
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
