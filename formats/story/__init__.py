"""Format: narrated image story (e.g. projects/roshni-airport-story).

Stages:  images -> debindi (optional) -> masks -> voice -> timing -> stills -> render -> mix -> mux -> qa
"""
import os

from studio import sfx as S
from studio.common import out_dir
from studio.mix import mix_from_cfg
from . import render as R

NEW = ["images", "masks", "voice", "timing", "stills"]
BUILD = ["render", "mix", "mux", "qa"]
DEFAULT_STILLS = [1.0, 5.0, 12.0, 20.0, 30.0, 40.0, 45.0]


def masks(d, a):
    """Subject masks for the 2.5D parallax (only for shots with parallax > 0)."""
    from rembg import new_session, remove
    from studio.common import load_cfg
    from PIL import Image
    cfg = load_cfg(d); os.makedirs(os.path.join(d, "masks"), exist_ok=True)
    names = sorted({s["img"] for s in cfg["shots"] if s.get("parallax", 0) > 0})
    sess = None
    for n in names:
        p = os.path.join(d, "masks", f"{n}.png")
        if os.path.exists(p) and not a.force: continue
        sess = sess or new_session("isnet-general-use")
        remove(Image.open(os.path.join(d, "img", f"{n}.png")).convert("RGB"), session=sess, only_mask=True).save(p)
        print(f"  mask {n}")


def build_sfx(st):
    """Default story sound design: whoosh into every cut, clatter on board flips, riser + impact on the drop,
    plus every `sfx:` entry in project.yaml, plus custom.sfx()."""
    tr = S.Track(st.dur)
    for c in st.cuts: tr.put(c - 0.34, S.whoosh(0.42), 0.10)
    for b in st.boards:
        for t in b.flips(): tr.put(t + 0.05, S.clatter(), 0.16)
    for d in st.drop: tr.put(d - 2.0, S.riser(2.0), 0.20); tr.put(d, S.impact(), 0.55)
    for e in st.cfg.get("sfx", []):
        tr.put(st.tl.expr(e["at"]), getattr(S, e["sound"])(**e.get("args", {})), e.get("gain", 0.15))
    if st.custom and hasattr(st.custom, "sfx"): st.custom.sfx(st, tr)
    p = os.path.join(out_dir(st.dir), "sfx.wav"); tr.save(p)
    return p


def mix(d, a):
    st = R.Story(d)
    mix_from_cfg(d, st.dur, sfx_wav=build_sfx(st), music_start=st.music_start)


STAGES = {
    "masks": masks,
    "stills": lambda d, a: print("  " + "\n  ".join(R.render_video(d, stills=a.stills or DEFAULT_STILLS))),
    "plates": lambda d, a: R.render_plates(d),
    "render": lambda d, a: R.render_video(d),
    "mix": mix,
}
