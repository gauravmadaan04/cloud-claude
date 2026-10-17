"""Music analysis: tempo + kick-aligned beat grid, energy map (to find drops/breaks), and cut snapping.

Typical use:
    info = analyse("assets/music/house_117bpm.mp3")        # cached next to the file as <name>.beats.json
    start = align(info["drops"][1], at_time=31.74)           # music offset so drop 2 lands at video t=31.74
    cut = snap(t, info["beats"], start)                      # nearest beat in VIDEO time

`drops` are CANDIDATES and can be one beat early (risers/fills start the jump early): listen, then pin the exact
track time in project.yaml (house_117bpm: 19.975 and 51.965 are verified).
"""
import json, os, subprocess
import numpy as np


def _pcm(path, sr=22050):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32), sr


def analyse(path, force=False):
    cache = os.path.splitext(path)[0] + ".beats.json"
    if os.path.exists(cache) and not force:
        return json.load(open(cache))
    x, sr = _pcm(path); hop = 128
    frames = np.lib.stride_tricks.sliding_window_view(x, 2048)[::hop]
    S = np.abs(np.fft.rfft(frames * np.hanning(2048), axis=1)); f = np.fft.rfftfreq(2048, 1 / sr)
    low = np.log1p(S[:, (f > 35) & (f < 130)].sum(1)); fps = sr / hop
    on = np.maximum(0, np.diff(low, prepend=low[0]))          # kick onsets
    # tempo + phase that best fit the kick onsets over the WHOLE track (a busy section alone can lock onto an
    # off-beat bassline, half a beat out), coarse then fine
    def fit(bpms, nph, around=None):
        best = (-1, 120.0, 0.0)
        for bpm in bpms:
            per = 60 / bpm * fps; idx = np.arange(0, len(on) - 2 * per, per)
            phs = np.linspace(0, per, nph, endpoint=False) if around is None else around + np.linspace(-2, 2, nph)
            for ph in phs:
                sc = on[(idx + ph % per).astype(int)].mean()
                if sc > best[0]: best = (sc, bpm, ph % per)
        return best
    _, bpm, ph = fit(np.arange(90, 150, 0.02), 48)
    _, bpm, ph = fit(np.arange(bpm - 0.06, bpm + 0.06, 0.005), 41, around=ph)
    per = 60 / bpm; t0 = ph / fps + 1024 / sr / 2               # small window-centre correction
    beats = [round(float(b), 3) for b in t0 + per * np.arange(0, int((len(x) / sr - t0) / per))]
    # drops = biggest loudness jumps (2 s after vs 2 s before, 0.25 s steps), on the first beat after the jump
    hd = sr // 4; n = len(x) // hd
    e = 20 * np.log10(np.sqrt((x[: n * hd].reshape(n, hd) ** 2).mean(1)) + 1e-6)
    jump = np.array([e[i:i + 8].mean() - e[i - 8:i].mean() if i >= 8 else 0 for i in range(n - 8)])
    drops = []
    for c in np.argsort(jump)[::-1][:60]:
        b = next((v for v in beats if v >= c / 4 - 0.05), beats[-1])     # first beat of the louder part
        if jump[c] > 3 and all(abs(b - d) > 8 for d in drops): drops.append(b)
    rms = np.sqrt((x[: len(x) // sr * sr].reshape(-1, sr) ** 2).mean(1))
    info = dict(bpm=round(float(bpm), 3), beats=beats, drops=sorted(drops)[:8],
                energy=[round(float(v), 3) for v in rms],
                map="".join("#" if v > np.percentile(rms, 66) else ("+" if v > np.percentile(rms, 33) else ".") for v in rms))
    json.dump(info, open(cache, "w"))
    return info


def align(music_time, at_time):
    """Music start offset so that `music_time` in the track plays at `at_time` in the video."""
    return music_time - at_time


def snap(t, beats, music_start, window=None):
    """Nearest beat to video time t (beats are in track time; music_start = track time at video t=0)."""
    cands = [b - music_start for b in beats]
    if window: cands = [c for c in cands if abs(c - t) <= window] or [t]
    return min(cands, key=lambda b: abs(b - t))
