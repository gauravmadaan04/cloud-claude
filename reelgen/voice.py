"""Voiceover: Gemini TTS via Kie -> whisper word timings -> tightened pauses -> one vo_full.wav + timing JSONs.

Lessons baked in:
  * Never put <long pause> style tags in the ENDING text: the voice sometimes reads them aloud. Pauses are added in the edit.
  * The ending is recorded as 3 takes; the take that both whisper models transcribe closest to the script wins
    (one take said "Do you know..." instead of "To know...").
"""
import difflib, json, os, re, subprocess, wave
import numpy as np

from . import kie
from .common import load_cfg

VOICE, TEMPO = "Sulafat", 1.04
norm = lambda s: re.sub(r"[^a-z]", "", s.lower())
_models = {}


def _whisper(name):
    if name not in _models:
        from faster_whisper import WhisperModel
        _models[name] = WhisperModel(name, device="cpu", compute_type="int8")
    return _models[name]


def _pcm16k(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", "16000", "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def transcribe(path, model="medium.en", words=True):
    segs, _ = _whisper(model).transcribe(_pcm16k(path), word_timestamps=words, language="en", beam_size=5)
    segs = list(segs)
    text = " ".join(s.text.strip() for s in segs)
    ws = [dict(w=x.word.strip(), s=round(x.start, 3), e=round(x.end, 3)) for s in segs for x in (s.words or [])]
    return text, ws


def _tts_job(name, text, style):
    return {"name": name, "kind": "task", "ext": "wav", "body": {"model": "google/gemini-3-8-flash-tts", "input": {
        "speakers": [{"speaker_id": "Speaker 1", "voice_name": VOICE}],
        "dialogue_turns": [{"speaker_id": "Speaker 1", "style": style, "text": text}]}}}


def record(reel_dir):
    """Generate the main narration (one call) and 3 ending takes; keeps the best ending take."""
    cfg = load_cfg(reel_dir); v = cfg["voice"]
    raw = os.path.join(reel_dir, "voice", "raw"); os.makedirs(raw, exist_ok=True)
    jobs = [_tts_job("vo", " <short pause> ".join(v["lines"]), v["style"])]
    jobs += [_tts_job(f"end_t{i}", v["ending_text"], v["ending_style"]) for i in range(3)]
    kie.run_jobs(jobs, raw)
    best, best_score = None, -1
    want = norm(v["ending_text"])
    for i in range(3):
        p = os.path.join(raw, f"end_t{i}.wav")
        if not os.path.exists(p): continue
        scores = []
        for m in ("medium.en", "small.en"):
            text, _ = transcribe(p, m, words=False)
            scores.append(difflib.SequenceMatcher(a=want, b=norm(text)).ratio())
            print(f"  ending take {i} [{m}]: {text}")
        if min(scores) > best_score: best, best_score = p, min(scores)
    os.replace(best, os.path.join(raw, "end.wav"))
    print(f"  picked {os.path.basename(best)} (match {best_score:.2f})")


def _read(p):
    with wave.open(p) as f: return f.getframerate(), np.frombuffer(f.readframes(f.getnframes()), np.int16)


def _write(p, sr, y):
    with wave.open(p, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(y.astype(np.int16).tobytes())


def _silences(p, d=0.22):
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", p, "-af", f"silencedetect=noise=-38dB:d={d}", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    vals = [float(x) for x in re.findall(r"silence_(?:start|end): ([0-9.]+)", r)]
    return list(zip(vals[0::2], vals[1::2]))


def build(reel_dir):
    """Main narration: align whisper words to script lines, shrink pauses, speed x1.04; then append the ending."""
    cfg = load_cfg(reel_dir); v = cfg["voice"]
    vd = os.path.join(reel_dir, "voice"); raw = os.path.join(vd, "raw")
    lines = v["lines"]; json.dump(lines, open(os.path.join(vd, "vo_lines.json"), "w"), indent=1)
    _, w = transcribe(os.path.join(raw, "vo.wav"))
    sw = [(li, t) for li, l in enumerate(lines) for t in l.replace("...", "").split()]
    sm = difflib.SequenceMatcher(a=[norm(t) for _, t in sw], b=[norm(q["w"]) for q in w], autojunk=False)
    li_of = [None] * len(w)
    for _, i1, i2, j1, j2 in sm.get_opcodes():
        for k, j in enumerate(range(j1, j2)):
            li_of[j] = sw[min(i1 + k, i2 - 1) if i2 > i1 else max(i1 - 1, 0)][0]
    for j in range(len(w)):
        w[j]["line"] = li_of[j] if li_of[j] is not None else w[j - 1]["line"]
    sil = _silences(os.path.join(raw, "vo.wav"))
    for q in w:
        for s, e in sil:
            if s - 0.06 <= q["s"] < e and q["e"] > e: q["s"] = e
            elif s < q["e"] < e - 0.05 and q["s"] < s: q["e"] = s
    sr, x = _read(os.path.join(raw, "vo.wav"))
    cuts = []
    for s, e in sil:
        if s < 0.01: cuts.append((0, max(0, e - 0.03))); continue
        nxt = next((i for i, q in enumerate(w) if q["s"] >= e - 0.15), None)
        if nxt is None:
            if e - s > 0.3: cuts.append((s + 0.3, e))
            continue
        prev = w[nxt - 1]
        target = 0.42 if w[nxt]["line"] != prev["line"] else (0.26 if prev["w"][-1] in ".?!,–" else 0.16)
        if e - s > target:
            mid = (s + e) / 2; cuts.append((mid - (e - s - target) / 2, mid + (e - s - target) / 2))
    keep, t = [], 0
    for a, b in sorted(cuts): keep.append((t, a)); t = b
    keep.append((t, len(x) / sr))
    _write(os.path.join(raw, "vo_tight.wav"), sr, np.concatenate([x[int(a * sr):int(b * sr)] for a, b in keep]))
    remap = lambda t: (t - sum(min(b, t) - a for a, b in cuts if a < t)) / TEMPO
    for q in w: q["s"], q["e"] = round(remap(q["s"]), 3), round(remap(q["e"]), 3)
    json.dump(w, open(os.path.join(vd, "vo_words.json"), "w"))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(raw, "vo_tight.wav"), "-af", f"atempo={TEMPO}",
                    os.path.join(raw, "vo_main.wav")], check=True)

    # ending: trim, speed match, make the pause before the pivot sentence exactly 1.25 s
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(raw, "end.wav"), "-af",
                    "silenceremove=start_periods=1:start_threshold=-40dB,areverse,silenceremove=start_periods=1:"
                    f"start_threshold=-40dB,areverse,atempo={TEMPO}", "-ar", str(sr), "-ac", "1",
                    os.path.join(raw, "end_trim.wav")], check=True)
    _, ew = transcribe(os.path.join(raw, "end_trim.wav"))
    _, b = _read(os.path.join(raw, "end_trim.wav"))
    pivot = cfg["ending"]["pivot_word"]
    q_end = next(q["e"] for q in ew if q["w"].lower().startswith("you?"))
    p_start = next(q["s"] for q in ew if norm(q["w"]) == pivot)
    cut0, cut1 = q_end + 0.15, p_start - 1.10
    if cut1 > cut0:
        b = np.concatenate([b[:int(cut0 * sr)], b[int(cut1 * sr):]]); shift = -(cut1 - cut0)
    else:
        b = np.concatenate([b[:int(cut0 * sr)], np.zeros(int((cut0 - cut1) * sr), np.int16), b[int(cut0 * sr):]]); shift = cut0 - cut1
    for q in ew:
        if q["s"] >= p_start - 0.01: q["s"] += shift; q["e"] += shift
    _, a = _read(os.path.join(raw, "vo_main.wav"))
    y = np.concatenate([a, np.zeros(int(0.35 * sr), np.int16), b])
    _write(os.path.join(vd, "vo_full.wav"), sr, y)
    off = len(a) / sr + 0.35
    json.dump(dict(start=off, words=[dict(w=q["w"], s=round(q["s"] + off, 3), e=round(q["e"] + off, 3)) for q in ew],
                   end=len(y) / sr), open(os.path.join(vd, "end_line.json"), "w"))
    for li in range(len(lines)):
        ws = [q for q in w if q["line"] == li]
        print(f"  line {li:2d} {ws[0]['s']:6.2f}-{ws[-1]['e']:6.2f}  {' '.join(q['w'] for q in ws)}")
    print(f"  narration {len(a) / sr:.1f}s + ending -> {len(y) / sr:.1f}s total")
