"""Final checks before a reel goes out. `python make.py projects/<name> qa`

  * loudness / true peak of the final MP4 (target about -9 LUFS, peak below -1 dBFS)
  * face guard log: graphics must never have touched a face
  * contact sheet: one frame every ~2.5 s -> out/contact.jpg (look at it!)
  * with --deep: whisper transcript of the final audio vs the script (catches misread words / spoken tags)
"""
import difflib, json, os, re

from PIL import Image, ImageDraw

from .common import load_cfg, out_dir
from .mix import loudness
from .video import frame_at


def contact_sheet(video, path, dur, cols=6, every=2.5, thumb=(216, 384)):
    ts = [round(i * every + 0.5, 2) for i in range(int((dur - 0.5) / every) + 1)]
    rows = (len(ts) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * thumb[0], rows * (thumb[1] + 24)), (20, 20, 20)); d = ImageDraw.Draw(sheet)
    for i, t in enumerate(ts):
        x, y = (i % cols) * thumb[0], (i // cols) * (thumb[1] + 24)
        sheet.paste(frame_at(video, t).resize(thumb), (x, y)); d.text((x + 6, y + thumb[1] + 4), f"{t:.1f}s", fill=(230, 230, 230))
    sheet.save(path, quality=85)
    return path


def check(project_dir, deep=False):
    cfg = load_cfg(project_dir); out = out_dir(project_dir)
    name = os.path.basename(os.path.normpath(project_dir)); final = os.path.join(out, f"{name}.mp4")
    if not os.path.exists(final): print("  no final video yet (run build)"); return False
    ok = True
    ld = loudness(final)
    print(f"  loudness {ld['lufs']} LUFS, true peak {ld['peak']} dBFS")
    if ld["peak"] is not None and ld["peak"] > -1.0: print("  !! peak too hot: lower audio.limit"); ok = False
    if ld["lufs"] is not None and ld["lufs"] < -12: print("  !! quieter than our other reels (~-9 LUFS): raise audio.gain_db")
    fl = os.path.join(out, "face_log.json")
    if os.path.exists(fl):
        log = json.load(open(fl)); hits = [f["t"] for f in log if f["overlap_px"] > 0]
        print(f"  face guard: {len(log)} frames, graphics touched a face in {len(hits)} {hits[:8] if hits else ''}")
        if hits: print("  !! move the graphic at those times (the guard punched a hole in it)"); ok = False
    import subprocess
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", final],
                               capture_output=True, text=True).stdout)
    print(f"  duration {dur:.2f}s | contact sheet: {contact_sheet(final, os.path.join(out, 'contact.jpg'), dur)}")
    if deep:
        from .voice import transcribe
        heard, _ = transcribe(final, words=False)
        v = cfg.get("voice", {})
        script = " ".join(v.get("lines", [])) + " " + v.get("ending_text", "")
        n = lambda s: re.sub(r"[^a-z ]", "", s.lower()).split()
        sm = difflib.SequenceMatcher(a=n(script), b=n(heard), autojunk=False)
        print(f"  transcript match {sm.ratio():.2f}")
        for op, i1, i2, j1, j2 in sm.get_opcodes():
            if op != "equal": print(f"    script: {' '.join(n(script)[i1:i2])!r:40s} heard: {' '.join(n(heard)[j1:j2])!r}")
    print("  QA " + ("passed" if ok else "FAILED"))
    return ok
