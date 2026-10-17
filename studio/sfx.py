"""Synthesised sound-effects library (no samples needed) + a Track to place them on a timeline.

    tr = Track(duration)
    tr.put(1.2, swish(), 0.13); tr.put(3.0, impact(), 0.5)
    tr.save("out/sfx.wav")
"""
import wave
import numpy as np

SR = 48000
_rng = np.random.default_rng(5)


class Track:
    def __init__(self, dur):
        self.dur, self.buf = dur, np.zeros(int(SR * (dur + 2)))

    def put(self, t, sig, gain=1.0):
        i = max(0, int(t * SR)); j = min(len(self.buf), i + len(sig)); self.buf[i:j] += sig[: j - i] * gain

    def save(self, path):
        out = self.buf[: int(SR * self.dur)]
        out = out / max(1.0, np.abs(out).max() / 0.9)
        with wave.open(path, "wb") as f:
            f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
            f.writeframes((out * 32767).astype(np.int16).tobytes())


def _env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-t / decay)


def lowpass_sweep(x, f0, f1):
    fc = f0 * (f1 / f0) ** np.linspace(0, 1, len(x)); a = np.exp(-2 * np.pi * fc / SR)
    y = np.zeros_like(x); s = 0.0
    for i in range(len(x)):
        s = (1 - a[i]) * x[i] + a[i] * s; y[i] = s
    return y


def swish(dur=0.42):
    """Paper sliding / quick transition."""
    n = int(SR * dur); y = np.diff(lowpass_sweep(_rng.standard_normal(n), 1500, 9000), prepend=0)
    return y / (np.abs(y).max() + 1e-9) * np.sin(np.linspace(0, np.pi, n)) ** 2


def whoosh(dur=0.42, f0=300, f1=4000):
    """Softer, airier transition whoosh."""
    n = int(SR * dur); y = lowpass_sweep(_rng.standard_normal(n), f0, f1)
    return y / (np.abs(y).max() + 1e-9) * np.sin(np.linspace(0, np.pi, n)) ** 1.6


def tick():
    n = int(SR * 0.05); t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 2400 * t) * 0.5 + _rng.standard_normal(n) * 0.5) * np.exp(-t / 0.008)


def pop(freq=620):
    n = int(SR * 0.18); t = np.arange(n) / SR
    return np.sin(2 * np.pi * np.cumsum(freq * (1 + 0.6 * np.exp(-t / 0.01))) / SR) * np.exp(-t / 0.05)


def fall(dur=1.1):
    """Descending swish: things dropping away."""
    n = int(SR * dur); y = lowpass_sweep(_rng.standard_normal(n), 6000, 400)
    return y / (np.abs(y).max() + 1e-9) * np.sin(np.linspace(0, np.pi, n)) ** 1.5


def riser(dur=2.0):
    """Build-up into a drop (place it ending at the drop)."""
    n = int(SR * dur); t = np.arange(n) / SR
    noise = lowpass_sweep(_rng.standard_normal(n), 200, 7000); noise /= np.abs(noise).max()
    tone = np.sin(2 * np.pi * np.cumsum(180 * (1200 / 180) ** (t / dur)) / SR) * 0.35
    return (noise * 0.8 + tone) * (t / dur) ** 2.2


def impact():
    """Low boom for a drop / big reveal."""
    n = int(SR * 1.4); t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * np.cumsum(45 + 75 * np.exp(-t / 0.08)) / SR) * np.exp(-t / 0.55)
    return np.tanh((boom + _rng.standard_normal(n) * np.exp(-t / 0.025) * 0.5) * 1.6)


def thud():
    """Stamp / object landing."""
    n = int(SR * 0.5); t = np.arange(n) / SR
    return np.sin(2 * np.pi * np.cumsum(70 + 90 * np.exp(-t / 0.03)) / SR) * np.exp(-t / 0.12) + _rng.standard_normal(n) * np.exp(-t / 0.01) * 0.4


def bell(freq=880, dur=1.8):
    """Airport / announcement chime tone (use two: 880 then 698 Hz for 'ding-dong')."""
    n = int(SR * dur); t = np.arange(n) / SR
    sig = sum(a * np.sin(2 * np.pi * freq * m * t) * np.exp(-t / (1.3 / m ** 0.7)) for m, a in ((1, 1.0), (2.0, 0.35), (3.01, 0.18), (4.2, 0.08)))
    return sig * np.minimum(1, t / 0.004)


def clatter(dur=0.75):
    """Split-flap board flipping."""
    n = int(SR * dur); sig = np.zeros(n); t = 0.0
    while t < dur:
        k = int(t * SR); cl = int(SR * 0.004)
        burst = np.diff(_rng.standard_normal(cl) * _env(cl, 0.0003, 0.0012), prepend=0)
        sig[k:k + cl] += burst[: n - k] * (0.6 + 0.4 * _rng.random()) * (1 - t / dur * 0.6)
        t += _rng.uniform(0.012, 0.035)
    return sig


def flyover(dur=3.2):
    """Distant jet / passing vehicle."""
    n = int(SR * dur); t = np.arange(n) / SR
    y = lowpass_sweep(_rng.standard_normal(n), 900, 250); y /= np.abs(y).max() + 1e-9
    hum = np.sin(2 * np.pi * np.cumsum(140 - 50 * t / dur) / SR) * 0.25
    return (y + hum) * np.sin(np.pi * t / dur) ** 1.5
