"""Reusable motion-graphics pieces. Each returns an RGBA layer (or edits a frame) for time t; formats compose them.

    Board          split-flap departure board that flips between texts at given times
    chip(...)      rounded pill label, optional symbol (✈ ● ✓ ★)
    Captions       word-by-word karaoke captions driven by narration word timings
    kinetic(...)   big words that slam in one by one (finales, punchlines)
    punch(...)     zoom punch on cuts;  flash(...) white flash;  fade_black(...)

All graphics go on an overlay layer that the FaceGuard clears from faces, never straight onto the picture.
"""
import math, random
from PIL import Image, ImageDraw, ImageFilter

from .common import W, H, FPS, ease_back, ease_out, fade, inter, prog, symbol_font

AMBER, INK, CREAM, RUST = (255, 196, 61), (17, 17, 19), (247, 241, 230), (150, 52, 32)
GREY, GREEN, WHITE = (120, 112, 104), (70, 220, 120), (255, 255, 255)
COLORS = dict(amber=AMBER, ink=INK, cream=CREAM, rust=RUST, grey=GREY, green=GREEN, white=WHITE)


def color(c, default=WHITE):
    if c is None: return default
    return COLORS[c] if isinstance(c, str) else tuple(c)


# ---------------------------------------------------------------- chip
def chip(text, fnt, fg, bg, pad=(22, 12), sym=None):
    w = int(fnt.getlength(text)) + pad[0] * 2 + (44 if sym else 0); h = fnt.size + pad[1] * 2
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=bg)
    x = pad[0]
    if sym:
        d.text((x, h / 2), sym, font=symbol_font(int(fnt.size * 1.05)), fill=fg, anchor="lm"); x += 44
    d.text((x, h / 2), text, font=fnt, fill=fg, anchor="lm")
    return im


# ---------------------------------------------------------------- split-flap board
GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
_tiles = {}


def _tile(ch, tw, th, squash=1.0, dim=False, fg=AMBER):
    key = (ch, tw, th, round(squash, 2), dim, fg)
    if key in _tiles: return _tiles[key]
    im = Image.new("RGBA", (tw, th), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, tw - 1, th - 1), radius=max(6, tw // 9), fill=(22, 22, 25, 240))
    d.rounded_rectangle((2, 2, tw - 3, th // 2), radius=max(5, tw // 10), fill=(32, 32, 36, 255))
    if ch.strip():
        g = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        ImageDraw.Draw(g).text((tw / 2, th / 2 + th * 0.02), ch, font=inter("Bold", int(th * 0.72)),
                               fill=fg + (150 if dim else 255,), anchor="mm")
        if squash < 1:
            sh = max(1, int(th * squash)); g = g.resize((tw, sh), Image.BILINEAR)
            gg = Image.new("RGBA", (tw, th), (0, 0, 0, 0)); gg.alpha_composite(g, (0, (th - sh) // 2)); g = gg
        im.alpha_composite(g)
    ImageDraw.Draw(im).line((3, th // 2, tw - 4, th // 2), fill=(0, 0, 0, 255), width=3)
    _tiles[key] = im
    return im


class Board:
    """One-row split-flap board.  entries = [(t, "TEXT"), ...]: at each t it flips from the previous text.
    header = small chip above it.  status = optional (text, t0, t1) blinking chip below it."""

    def __init__(self, t0, t1, entries, header=None, y=1075, status=None, max_w=980, gap=7, seed=None):
        self.t0, self.t1, self.entries, self.header, self.y, self.status = t0, t1, sorted(entries), header, y, status
        self.ncols = max(len(x[1]) for x in entries)
        self.tw = min(84, int((max_w - gap * (self.ncols - 1)) / self.ncols)); self.th = int(self.tw * 1.42)
        self.gap, self.seed = gap, int(t0 * 100) if seed is None else seed
        self.f_head, self.f_status = inter("Bold", 30), inter("Bold", 30)

    def flips(self): return [t for t, _ in self.entries]

    def active(self, t): return self.t0 <= t < self.t1 and t >= self.entries[0][0] - 0.05

    def _row(self, t):
        cur = [e for e in self.entries if e[0] <= t]
        if not cur: return None
        t0, text = cur[-1]
        prev = cur[-2][1] if len(cur) > 1 else " " * self.ncols
        text, prev = text.center(self.ncols), prev.center(self.ncols)
        rnd = random.Random(self.seed)
        settle = [t0 + 0.08 + i * 0.045 + rnd.random() * 0.22 for i in range(self.ncols)]
        img = Image.new("RGBA", (self.ncols * self.tw + (self.ncols - 1) * self.gap, self.th), (0, 0, 0, 0))
        frame = int(t * FPS)
        for i in range(self.ncols):
            if t >= settle[i] or (text[i] == " " and prev[i] == " "):
                ch, sq = text[i], 1.0
                dt = t - settle[i]
                if 0 <= dt < 0.08: sq = 0.75 + dt / 0.08 * 0.25
            else:
                ch = GLYPHS[(frame * 7 + i * 13 + self.seed) % len(GLYPHS)]; sq = 0.55 + 0.45 * ((frame % 2) == 0)
            img.alpha_composite(_tile(ch, self.tw, self.th, sq, dim=t < settle[i]), (i * (self.tw + self.gap), 0))
        return img

    def draw(self, ov, t):
        if not self.active(t): return
        if self.header:
            hp = ease_out(prog(t, self.entries[0][0], 0.3))
            hd = chip(self.header, self.f_head, INK, AMBER + (255,), sym="✈")
            ov.alpha_composite(fade(hd, hp), ((W - hd.width) // 2, int(self.y - 78 - (1 - hp) * 20)))
        b = self._row(t)
        if b: ov.alpha_composite(b, ((W - b.width) // 2, self.y))
        if self.status and self.status[1] <= t < self.status[2]:
            blink = 0.55 + 0.45 * (math.sin(t * 2 * math.pi * 1.6) > 0)
            st = chip(self.status[0], self.f_status, WHITE, (20, 120, 60, 235), sym="●")
            pa = ease_back(prog(t, self.status[1], 0.3))
            ov.alpha_composite(fade(st, min(1, pa) * blink), ((W - st.width) // 2, self.y + self.th + 14))


# ---------------------------------------------------------------- captions
class Captions:
    """Word-by-word captions. words = narration words (video time) with 'line'; a chunk ends at . ? ! , or after
    any word listed in `break_after`.  Words at/after `stop_at` are skipped (e.g. when big kinetic type takes over)."""

    def __init__(self, words, size=70, y=1300, max_w=920, break_after=(), stop_at=None, lines=None,
                 hi=AMBER, fg=WHITE, backing=120):
        self.f = inter("Bold", size); self.y, self.max_w, self.lh = y, max_w, int(size * 1.31)
        self.hi, self.fg, self.backing = hi, fg, backing
        out, cur, last_line = [], [], None
        for w in words:
            if lines is not None and w["line"] not in lines: continue
            if stop_at is not None and w["s"] >= stop_at: continue
            if cur and w["line"] != last_line: out.append(cur); cur = []
            cur.append(w); last_line = w["line"]
            if w["w"][-1] in ".?!," or w["w"].strip(".,!?").lower() in break_after: out.append(cur); cur = []
        if cur: out.append(cur)
        self.chunks = []
        for i, c in enumerate(out):
            nxt = out[i + 1][0]["s"] if i + 1 < len(out) else 1e9
            self.chunks.append((c[0]["s"] - 0.08, min(c[-1]["e"] + 0.55, nxt - 0.05), c))

    def _wrap(self, words):
        rows, cur = [], []
        for w in words:
            if cur and self.f.getlength(" ".join(x["w"] for x in cur + [w])) > self.max_w: rows.append(cur); cur = [w]
            else: cur.append(w)
        return rows + [cur]

    def layer(self, t):
        act = [c for c in self.chunks if c[0] <= t < c[1]]
        if not act: return None
        s, e, words = act[0]
        a = ease_out(prog(t, s, 0.12)) * (1 - prog(t, e - 0.12, 0.12))
        rows = self._wrap(words); lh = self.lh
        size = (W, lh * len(rows) + 40)
        txt, shadow = Image.new("RGBA", size, (0, 0, 0, 0)), Image.new("RGBA", size, (0, 0, 0, 0))
        dt, ds = ImageDraw.Draw(txt), ImageDraw.Draw(shadow)
        space = self.f.getlength(" ")
        for r, row in enumerate(rows):
            widths = [self.f.getlength(w["w"]) for w in row]; rw = sum(widths) + space * (len(row) - 1)
            x, y = (W - rw) / 2, 20 + r * lh
            if self.backing: ds.rounded_rectangle((x - 22, y - 6, x + rw + 22, y + lh - 8), radius=22, fill=(0, 0, 0, self.backing))
            for w, wd in zip(row, widths):
                spoken, current = t >= w["s"], w["s"] <= t < w["e"] + 0.08
                dy = (1 - ease_back(prog(t, w["s"], 0.16))) * 10 if spoken else 0
                ds.text((x + 3, y + 5 + dy), w["w"], font=self.f, fill=(0, 0, 0, 200))
                dt.text((x, y + dy), w["w"], font=self.f, fill=(self.hi if current else self.fg) + (255 if spoken else 120,))
                x += wd + space
        out = shadow.filter(ImageFilter.GaussianBlur(6)); out.alpha_composite(txt)
        return fade(out, a)

    def draw(self, ov, t):
        lay = self.layer(t)
        if lay: ov.alpha_composite(lay, (0, self.y))


# ---------------------------------------------------------------- kinetic type
def kinetic(ov, t, words, y=1120, step=150, size=150, out_at=None, weight="Black"):
    """words = [(t, "TEXT", color), ...]: each slams in (scale 1.45 -> 1) and stacks downwards; all lift away at out_at."""
    f = inter(weight, size); hgt = int(size * 1.27)
    out = ease_out(prog(t, out_at - 0.25, 0.45)) if out_at else 0
    for i, (ts, txt, col) in enumerate(words):
        p = prog(t, ts, 0.22)
        if p <= 0: continue
        sc = 1.45 - 0.45 * ease_out(p)
        lay = Image.new("RGBA", (W, hgt), (0, 0, 0, 0))
        ImageDraw.Draw(lay).text((W / 2 + 4, hgt * 0.53), txt, font=f, fill=(0, 0, 0, 170), anchor="mm")
        lay = lay.filter(ImageFilter.GaussianBlur(8))
        ImageDraw.Draw(lay).text((W / 2, hgt * 0.5), txt, font=f, fill=color(col), anchor="mm")
        if sc != 1:
            lw, lh = int(W * sc), int(hgt * sc)
            lay = lay.resize((lw, lh), Image.BICUBIC).crop(((lw - W) // 2, (lh - hgt) // 2, (lw - W) // 2 + W, (lh - hgt) // 2 + hgt))
        ov.alpha_composite(fade(lay, min(1, p * 3) * (1 - out)), (0, int(y + i * step - out * 120)))


# ---------------------------------------------------------------- frame-level transitions
def punch(frame, t, cuts, amount=0.035, big=(), big_amount=0.07):
    """Quick zoom-in that settles after each cut (bigger on `big` moments like a drop). Apply to the picture."""
    z = 0.0
    for c in cuts:
        if c <= t < c + 0.2: z = amount * (1 - ease_out(prog(t, c, 0.2)))
    for c in big:
        if c <= t < c + 0.35: z = big_amount * (1 - ease_out(prog(t, c, 0.35)))
    if not z: return frame
    zz = 1 + z; bw, bh = W / zz, H / zz
    return frame.resize((W, H), Image.BICUBIC, box=((W - bw) / 2, (H - bh) / 2, (W + bw) / 2, (H + bh) / 2))


def flash(canvas, t, cuts, amount=0.12, big=(), big_amount=0.6, tint=(255, 246, 230)):
    fl = 0
    for c in cuts:
        if c <= t < c + 0.1: fl = max(fl, amount * (1 - prog(t, c, 0.1)))
    for c in big:
        if c <= t < c + 0.3: fl = max(fl, big_amount * (1 - prog(t, c, 0.3)))
    if fl: canvas.alpha_composite(Image.new("RGBA", (W, H), tint + (int(255 * fl),)))


def fade_black(canvas, t, fade_in=0.3, out_at=None, out_dur=0.45):
    blk = 1 - prog(t, 0, fade_in) if fade_in else 0
    if out_at is not None: blk = max(blk, prog(t, out_at, out_dur))
    if blk > 0: canvas.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(255 * blk))))
