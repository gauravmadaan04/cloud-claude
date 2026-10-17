"""Sound design + final mix: paper swishes/clicks synced to the render's events, music ducked under the voice, loud master."""
import json, os, subprocess, wave
import numpy as np

from .common import ROOT, load_cfg

SR = 48000


def _lowpass_sweep(x, f0, f1):
    fc = f0 * (f1 / f0) ** np.linspace(0, 1, len(x)); a = np.exp(-2 * np.pi * fc / SR)
    y = np.zeros_like(x); s = 0.0
    for i in range(len(x)):
        s = (1 - a[i]) * x[i] + a[i] * s; y[i] = s
    return y


def build_sfx(ev, path):
    rng = np.random.default_rng(5)
    dur = ev["dur"]; out = np.zeros(int(SR * (dur + 1)))

    def put(t, sig, gain):
        i = int(t * SR); j = min(len(out), i + len(sig)); out[i:j] += sig[: j - i] * gain

    def swish(d=0.42):
        n = int(SR * d); y = np.diff(_lowpass_sweep(rng.standard_normal(n), 1500, 9000), prepend=0)
        return y / (np.abs(y).max() + 1e-9) * np.sin(np.linspace(0, np.pi, n)) ** 2

    def tick():
        n = int(SR * 0.05); t = np.arange(n) / SR
        return (np.sin(2 * np.pi * 2400 * t) * 0.5 + rng.standard_normal(n) * 0.5) * np.exp(-t / 0.008)

    def pop(freq):
        n = int(SR * 0.18); t = np.arange(n) / SR
        return np.sin(2 * np.pi * np.cumsum(freq * (1 + 0.6 * np.exp(-t / 0.01))) / SR) * np.exp(-t / 0.05)

    def fall(d=1.1):
        n = int(SR * d); y = _lowpass_sweep(rng.standard_normal(n), 6000, 400)
        return y / (np.abs(y).max() + 1e-9) * np.sin(np.linspace(0, np.pi, n)) ** 1.5

    put(0.0, swish(ev["hook_end"] + 0.2), 0.11)
    for t in ev["hook_ticks"]: put(t, tick(), 0.16)
    put(ev["hook_end"], pop(620), 0.12)
    for s in ev["swaps"][1:]: put(s - 0.45, swish(), 0.13); put(s, tick(), 0.18)
    put(ev["conf_t"], swish(0.8), 0.12)
    for t in ev["chaos"]: put(t, tick(), 0.09)
    put(ev["not_t"] - 0.05, fall(), 0.16)
    out = out[: int(SR * dur)]
    with wave.open(path, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes((np.clip(out, -1, 1) * 32767).astype(np.int16).tobytes())


def mix(reel_dir):
    cfg = load_cfg(reel_dir); a = cfg["audio"]
    out = os.path.join(reel_dir, "out")
    ev = json.load(open(os.path.join(out, "events.json")))
    build_sfx(ev, os.path.join(out, "sfx.wav"))
    dur = ev["dur"]
    fc = (
        f"[1:a]aformat=channel_layouts=mono,highpass=f=85,equalizer=f=3200:t=q:w=1.2:g=2.5,"
        f"acompressor=threshold=-20dB:ratio=3:attack=5:release=120:makeup=2,adelay={int(ev['vo_offset'] * 1000)},apad,"
        f"atrim=0:{dur},asplit=2[vo][sc];"
        f"[0:a]aformat=channel_layouts=stereo,volume=0.55,"
        f"volume='1-0.5*min(max((t-{ev['not_t']})/0.6\\,0)\\,1)':eval=frame,"      # music dips for the prime line
        f"afade=t=in:d=0.05,afade=t=out:st={dur - 0.3}:d=0.3[mus];"
        f"[sc]aformat=channel_layouts=stereo[sc2];"
        f"[mus][sc2]sidechaincompress=threshold=0.035:ratio=6:attack=12:release=350:makeup=1[duck];"
        f"[2:a]aformat=channel_layouts=stereo[fx];[vo]aformat=channel_layouts=stereo[vo2];"
        f"[duck][vo2][fx]amix=inputs=3:normalize=0:weights=1 1.45 1,"
        f"loudnorm=I=-14:TP=-1.5:LRA=9,volume={a.get('gain_db', 7.0)}dB,"
        f"alimiter=limit={a.get('limit', 0.72)}:attack=2:release=60:level=disabled,aresample=48000[a]"
    )
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", str(a["music_start"]), "-t", str(dur),
                    "-i", os.path.join(ROOT, a["music"]), "-i", os.path.join(reel_dir, "voice", "vo_full.wav"),
                    "-i", os.path.join(out, "sfx.wav"), "-filter_complex", fc, "-map", "[a]",
                    "-c:a", "pcm_s16le", os.path.join(out, "mix.wav")], check=True)


def mux(reel_dir, name=None):
    out = os.path.join(reel_dir, "out")
    final = os.path.join(out, name or f"{os.path.basename(os.path.normpath(reel_dir))}.mp4")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", os.path.join(out, "graphics.mp4"), "-i", os.path.join(out, "mix.wav"),
                    "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-profile:v", "high",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-movflags", "+faststart",
                    "-shortest", final], check=True)
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", final, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    lines = [l.strip() for l in r.splitlines() if l.strip().startswith(("I:", "Peak:"))][-2:]
    print("  " + " | ".join(lines))
    return final
