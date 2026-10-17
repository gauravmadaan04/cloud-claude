#!/usr/bin/env python3
"""One command for every reel, whatever its format.

  python make.py projects/<name> <stage> [<stage> ...] [--only id id] [--stills 1.0 3.5 ...] [--force] [--deep]
  python make.py --list                       # projects, formats and their stages

The project's format comes from `format:` in its project.yaml (default: paperdoll).

Shared stages (any format):
  images     generate stills listed in `images:` with GPT Image 2 via Kie   (formats may override)
  debindi    remove a bindi from every image in img/ (originals kept in out/img_original)
  voice      record the narration (+ 3 ending takes if there's an ending)   (Gemini TTS via Kie)
  timing     tighten pauses, word timings -> voice/vo_full.wav, vo_words.json ... (free; rerun after edits)
  mux        final MP4 -> out/<name>.mp4
  qa         loudness, face-guard log, contact sheet (--deep: transcript check)
Format stages: see formats/<format>/__init__.py (stills, render, mix, ... ).
Macros:  new = the format's first-time stages,  build = render mix mux qa (rebuild from existing assets: free)
"""
import argparse, importlib, os, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
from studio import imaging, mix as M, qa, voice  # noqa: E402
from studio.common import load_cfg  # noqa: E402

SHARED = {
    "images": lambda d, a: imaging.generate(d, a.only, a.force),
    "debindi": lambda d, a: imaging.debindi(d),
    "voice": lambda d, a: voice.record(d),
    "timing": lambda d, a: voice.build(d),
    "mux": lambda d, a: print("  final:", M.mux_project(d)),
    "qa": lambda d, a: qa.check(d, deep=a.deep),
}


def load_format(name):
    return importlib.import_module(f"formats.{name}")


def list_all():
    fdir, pdir = os.path.join(ROOT, "formats"), os.path.join(ROOT, "projects")
    print("formats:")
    for f in sorted(os.listdir(fdir)):
        if os.path.exists(os.path.join(fdir, f, "__init__.py")):
            m = load_format(f)
            print(f"  {f:10s} new = {' '.join(m.NEW)}  |  build = {' '.join(m.BUILD)}")
    print("projects:")
    for p in sorted(os.listdir(pdir)):
        if os.path.exists(os.path.join(pdir, p, "project.yaml")):
            print(f"  projects/{p:28s} format: {load_cfg(os.path.join(pdir, p)).get('format', 'paperdoll')}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project", nargs="?")
    ap.add_argument("stages", nargs="*")
    ap.add_argument("--only", nargs="*", help="limit image stages to these ids")
    ap.add_argument("--stills", nargs="*", type=float, help="times (s) for the stills stage")
    ap.add_argument("--force", action="store_true", help="redo work that already exists (images, masks, hems)")
    ap.add_argument("--deep", action="store_true", help="qa: also transcribe the final audio")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    if a.list or not a.project: return list_all()
    d = a.project.rstrip("/")
    fmt = load_format(load_cfg(d).get("format", "paperdoll"))
    table = {**SHARED, **fmt.STAGES}
    macros = {"new": fmt.NEW, "build": fmt.BUILD}
    stages = [s for st in a.stages for s in macros.get(st, [st])]
    for st in stages:
        if st not in table: sys.exit(f"unknown stage {st!r}; choose from {sorted(table) + list(macros)}")
    for st in stages:
        print(f"== {st}", flush=True)
        table[st](d, a)


if __name__ == "__main__":
    main()
