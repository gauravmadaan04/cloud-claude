"""Narrated image story: stills with camera moves + 2.5D parallax, beat-snapped cuts, split-flap boards,
word-by-word captions, kinetic finale words. Everything is described in project.yaml (see projects/_template_story).

Two passes:  plates (camera moves, graded by ffmpeg) -> out/base.mp4,  then graphics over it -> out/graphics.mp4.
Bespoke one-off elements (e.g. Roshni's boarding pass) live in the project's own custom.py:
    def setup(story): ...                      # pre-build images, add times
    def overlay(story, ov, t): ...             # draw on the overlay layer (face guard still applies)
    def sfx(story, track): ...                 # extra sound effects
"""
import importlib.util, json, os
from PIL import Image, ImageFilter

from studio import components as C
from studio.common import ROOT, W, H, FPS, cover, load_cfg, out_dir, vgrad, watermark
from studio.faceguard import FaceGuard
from studio.music import analyse
from studio.timeline import Timeline
from studio.video import close, encoder, filter_image, frame_at, frames

GRADE = ("eq=contrast=1.05:saturation=1.07:gamma=0.98,"
         "colorbalance=rs=0.02:gs=0.0:bs=-0.025:rh=0.025:bh=-0.03,unsharp=5:5:0.35")


def smooth(p): return p * p * (3 - 2 * p)


class Story:
    def __init__(self, project_dir):
        self.dir = project_dir
        self.cfg = cfg = load_cfg(project_dir)
        self.tl = tl = Timeline(project_dir, cfg)
        a = cfg.get("audio", {})
        self.music = analyse(os.path.join(ROOT, a["music"]))
        if "music_align" in a:      # e.g. {track: 51.965, at: {word: [7, walk]}}: that music moment lands on that word
            self.music_start = a["music_align"]["track"] - tl.expr(a["music_align"]["at"])
        else:
            self.music_start = a.get("music_start", 0.0)
        tl.use_music(self.music["beats"], self.music_start)
        tl.T["END"] = float(cfg["duration"]) if "duration" in cfg else round(
            (tl.ending["end"] if tl.ending else tl.words[-1]["e"]) + tl.vo_offset + 1.5, 2)
        self.T = tl.resolve(cfg.get("times"))
        self.dur = self.T["END"]
        self.custom = self._load_custom()

        # shots
        # each shot runs from its `from` until the next shot's `from` (or its own `to`); missing `from` = previous end
        self.shots, prev = [], 0.0
        sh = cfg["shots"]
        for i, s in enumerate(sh):
            t0 = tl.expr(s["from"]) if "from" in s else prev
            t1 = tl.expr(s["to"]) if "to" in s else (
                tl.expr(sh[i + 1]["from"]) if i + 1 < len(sh) and "from" in sh[i + 1] else
                (self.dur if i + 1 == len(sh) else t0 + float(s.get("dur", 3.0))))
            z, an = s.get("zoom", [1.0, 1.1]), s.get("anchor", [[0.5, 0.4], [0.5, 0.4]])
            self.shots.append(dict(img=s["img"], t0=t0, t1=t1, z0=z[0], z1=z[1], a0=tuple(an[0]), a1=tuple(an[1]),
                                   parallax=s.get("parallax", 0.0)))
            prev = t1
        self.cuts = [s["t0"] for s in self.shots[1:]]

        g = cfg.get("graphics", {})
        self.g = g
        self.drop = [tl.expr(g["drop"])] if g.get("drop") is not None else []
        self.boards = []
        for b in g.get("boards", []):
            st = b.get("status")
            self.boards.append(C.Board(tl.expr(b["from"]), tl.expr(b["to"]),
                                       [(tl.expr(t), txt) for t, txt in b["entries"]], header=b.get("header"),
                                       y=b.get("y", g.get("board_y", 1075)),
                                       status=(st[0], tl.expr(st[1]), tl.expr(st[2])) if st else None))
        cap = g.get("captions")
        self.captions = C.Captions(tl.words, size=cap.get("size", 70), y=cap.get("y", 1300),
                                   break_after=tuple(cap.get("break_after", ())),
                                   stop_at=tl.expr(cap["stop_at"]) if cap.get("stop_at") is not None else None) if cap else None
        kin = g.get("kinetic")
        self.kinetic = None
        if kin:
            self.kinetic = dict(words=[(tl.expr(t), txt, col) for t, txt, col in kin["words"]], y=kin.get("y", 1120),
                                step=kin.get("step", 150), size=kin.get("size", 150),
                                out_at=tl.expr(kin["out_at"]) if kin.get("out_at") is not None else None)
        self.scrim_h = g.get("bottom_scrim", 820)
        self.scrim = vgrad(self.scrim_h, 0, g.get("bottom_scrim_alpha", 175)) if self.scrim_h else None
        self.fade_out_at = tl.expr(g.get("fade_out_at", {"at": "END", "add": -0.45}))
        self._imgs = {}
        if self.custom and hasattr(self.custom, "setup"): self.custom.setup(self)

    def _load_custom(self):
        p = os.path.join(self.dir, "custom.py")
        if not os.path.exists(p): return None
        spec = importlib.util.spec_from_file_location(f"custom_{os.path.basename(self.dir)}", p)
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        return mod

    # ------------------------------------------------------------ plates
    def _load(self, name):
        if name not in self._imgs:
            img = Image.open(os.path.join(self.dir, "img", f"{name}.png")).convert("RGB")
            mp = os.path.join(self.dir, "masks", f"{name}.png")
            mask = Image.open(mp).convert("L").filter(ImageFilter.GaussianBlur(1.5)) if os.path.exists(mp) else None
            self._imgs[name] = (img, mask)
        return self._imgs[name]

    def plate(self, s, i, nf):
        img, mask = self._load(s["img"])
        p = smooth(i / max(nf - 1, 1))
        z = s["z0"] + (s["z1"] - s["z0"]) * p
        ax, ay = s["a0"][0] + (s["a1"][0] - s["a0"][0]) * p, s["a0"][1] + (s["a1"][1] - s["a0"][1]) * p
        bg = cover(img, z, ax, ay)
        k = s["parallax"]
        if k <= 0 or mask is None: return bg
        zf = z * (1 + k * p)                 # subject grows a little faster than the room -> depth
        return Image.composite(cover(img, zf, ax, ay), bg, cover(mask, zf, ax, ay, resample=Image.BILINEAR))

    def plate_frames(self):
        for s in self.shots:
            nf = round(s["t1"] * FPS) - round(s["t0"] * FPS)
            for i in range(nf): yield self.plate(s, i, nf)

    def plate_at(self, t):
        s = next((s for s in self.shots if s["t0"] <= t < s["t1"]), self.shots[-1])
        nf = round(s["t1"] * FPS) - round(s["t0"] * FPS)
        return self.plate(s, min(nf - 1, round(t * FPS) - round(s["t0"] * FPS)), nf)

    # ------------------------------------------------------------ graphics
    def frame(self, base, t, guard=None):
        base = C.punch(base, t, self.cuts, big=self.drop) if self.g.get("punch", True) else base
        c = base.convert("RGBA")
        ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        if self.scrim: ov.alpha_composite(self.scrim, (0, H - self.scrim_h))
        for b in self.boards: b.draw(ov, t)
        if self.captions: self.captions.draw(ov, t)
        if self.kinetic: C.kinetic(ov, t, **self.kinetic)
        if self.custom and hasattr(self.custom, "overlay"): self.custom.overlay(self, ov, t)
        if self.g.get("watermark"):
            wm = self.g["watermark"]; watermark(ov, wm["text"], wm.get("x", W / 2), wm.get("y", 1720), wm.get("alpha", 62))
        if guard: guard.apply(ov, guard.detect(base), t)
        c.alpha_composite(ov)
        if self.g.get("flash", True): C.flash(c, t, self.cuts, big=self.drop)
        C.fade_black(c, t, fade_in=self.g.get("fade_in", 0.3), out_at=self.fade_out_at)
        return c.convert("RGB")

    def events(self):
        ev = dict(dur=self.dur, music_start=self.music_start, cuts=self.cuts, drop=self.drop,
                  flips=sorted(t for b in self.boards for t in b.flips()), times=self.T)
        if self.custom and hasattr(self.custom, "events"): ev.update(self.custom.events(self))
        return ev


def render_plates(project_dir, story=None):
    st = story or Story(project_dir)
    enc = encoder(os.path.join(out_dir(project_dir), "base.mp4"), vf=st.cfg.get("grade", GRADE))
    n = 0
    for f in st.plate_frames(): enc.stdin.write(f.tobytes()); n += 1
    close(enc)
    print(f"  plates: {n} frames ({len(st.shots)} shots)")


def render_video(project_dir, stills=None):
    st = Story(project_dir); out = out_dir(project_dir)
    json.dump(st.events(), open(os.path.join(out, "events.json"), "w"), indent=1)
    base = os.path.join(out, "base.mp4")
    if stills is not None:
        paths = []
        for t in stills:
            src = frame_at(base, t) if os.path.exists(base) else filter_image(st.plate_at(t), st.cfg.get("grade", GRADE))
            p = os.path.join(out, f"still_{t:05.2f}.jpg"); st.frame(src, t, FaceGuard()).save(p, quality=88); paths.append(p)
        return paths
    render_plates(project_dir, st)
    guard = FaceGuard()
    enc = encoder(os.path.join(out, "graphics.mp4"))
    n = round(st.dur * FPS)
    for i, f in enumerate(frames(base)):
        if i >= n: break
        enc.stdin.write(st.frame(f, i / FPS, guard).tobytes())
        if i % 300 == 0: print(f"  {i}/{n}", flush=True)
    close(enc)
    guard.save(os.path.join(out, "face_log.json")); guard.summary()
    return st
