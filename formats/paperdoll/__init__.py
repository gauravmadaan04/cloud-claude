"""Format: paper-doll "Types of ..." reel (skirts, suits, kurtis, saree drapes, necklines).

Hook (all items scroll past her) -> one item per narration line (cut-out flies on, old one flies off)
-> confusion (items swirl, question marks) -> prime line, ends clean for a CTA stitch.

Stages:  images -> debindi -> cutouts -> hems -> voice -> timing -> stills -> render -> mix -> mux -> qa
"""
import json, os

from studio import sfx as S
from studio.common import out_dir
from studio.mix import mix_from_cfg
from . import render as R, stages as P

NEW = ["images", "debindi", "cutouts", "hems", "voice", "timing", "stills"]
BUILD = ["render", "mix", "mux", "qa"]
DEFAULT_STILLS = [1.0, 3.0, 8.0, 20.0, 35.0, 42.0, 47.0]


def build_sfx(ev, path):
    """Paper swishes into every swap, ticks as items pass in the hook, pop at the hook end, chaos ticks, a fall."""
    tr = S.Track(ev["dur"])
    tr.put(0.0, S.swish(ev["hook_end"] + 0.2), 0.11)
    for t in ev["hook_ticks"]: tr.put(t, S.tick(), 0.16)
    tr.put(ev["hook_end"], S.pop(620), 0.12)
    for s in ev["swaps"][1:]: tr.put(s - 0.45, S.swish(), 0.13); tr.put(s, S.tick(), 0.18)
    tr.put(ev["conf_t"], S.swish(0.8), 0.12)
    for t in ev["chaos"]: tr.put(t, S.tick(), 0.09)
    tr.put(ev["not_t"] - 0.05, S.fall(), 0.16)
    tr.save(path)
    return path


def mix(d, a):
    out = out_dir(d)
    ev = json.load(open(os.path.join(out, "events.json")))         # written by `render`
    mix_from_cfg(d, ev["dur"], sfx_wav=build_sfx(ev, os.path.join(out, "sfx.wav")),
                 dips=[(ev["not_t"], 0.5)])                         # music dips for the prime line


STAGES = {
    "images": lambda d, a: P.images(d, a.only),
    "cutouts": lambda d, a: P.cutouts(d, a.only),
    "hems": lambda d, a: P.measure_hems(d, overwrite=a.force),
    "stills": lambda d, a: print("  " + "\n  ".join(R.render_video(d, stills=a.stills or DEFAULT_STILLS))),
    "render": lambda d, a: R.render_video(d),
    "mix": mix,
}
