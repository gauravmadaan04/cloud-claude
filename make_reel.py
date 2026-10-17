#!/usr/bin/env python3
"""Make a paper-doll "Types of ..." reel.

  python make_reel.py reels/<name> <stage> [<stage> ...] [--only id id] [--stills 1.0 3.5 ...]

Stages (run in this order for a brand-new reel; each one only needs the previous ones' files):
  images     generate the base look, then every other look from it          (Kie GPT Image 2, ~6 credits each)
  debindi    remove a bindi from every look (keeps originals in out/img_original)
  cutouts    paper cut-out of each item + background removal                 (~6 credits each)
  hems       estimate each item's hemline into reel.yaml (check white/black/navy items by hand)
  voice      record narration + 3 ending takes, keep the clearest            (~1.5 credits)
  timing     build vo_full.wav + word timings from the recordings (free; rerun after editing pauses)
  stills     render preview frames to out/ (use --stills t1 t2 ...)
  render     render the video (face guard on every frame)
  mix        sound design + music + voice -> out/mix.wav
  mux        final MP4 in out/<name>.mp4
  build      = render mix mux                      (re-render an existing reel: free)
  new        = images debindi cutouts hems voice timing stills    (then check stills, then `build`)
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from reelgen import audio, generate, render, voice  # noqa: E402

ORDER = ["images", "debindi", "cutouts", "hems", "voice", "timing", "stills", "render", "mix", "mux"]
MACROS = {"build": ["render", "mix", "mux"],
          "new": ["images", "debindi", "cutouts", "hems", "voice", "timing", "stills"]}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reel_dir")
    ap.add_argument("stages", nargs="+")
    ap.add_argument("--only", nargs="*", help="limit image/cut-out stages to these item ids")
    ap.add_argument("--stills", nargs="*", type=float, default=[1.0, 3.0, 8.0, 20.0, 35.0, 42.0, 47.0])
    a = ap.parse_args()
    stages = [s for st in a.stages for s in MACROS.get(st, [st])]
    for st in stages:
        if st not in ORDER: sys.exit(f"unknown stage {st!r}; choose from {ORDER + list(MACROS)}")
    d = a.reel_dir.rstrip("/")
    for st in stages:
        print(f"== {st}", flush=True)
        if st == "images": generate.images(d, a.only)
        elif st == "debindi": generate.debindi(d)
        elif st == "cutouts": generate.cutouts(d, a.only)
        elif st == "hems": generate.measure_hems(d)
        elif st == "voice": voice.record(d)
        elif st == "timing": voice.build(d)
        elif st == "stills": print("  " + "\n  ".join(render.render_video(d, stills=a.stills)))
        elif st == "render": render.render_video(d)
        elif st == "mix": audio.mix(d)
        elif st == "mux": print("  final:", audio.mux(d))


if __name__ == "__main__":
    main()
