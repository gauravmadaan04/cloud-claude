"""One-off graphics for this story: the boarding-pass end card, BOARDED stamp and tagline.
Times come from project.yaml (`PASS_IN`, `STAMP_AT`, `TAG_AT`); the sounds for them are in its `sfx:` list."""
import random
from PIL import Image, ImageDraw, ImageFilter

from studio.common import H, W, ease_back, ease_out, fade, inter, prog, symbol_font, vgrad
from studio.components import AMBER, CREAM, GREY, INK, RUST

PASS_Y = 640


def _barcode(d, x0, y0, x1, y1, seed=7):
    r = random.Random(seed); x = x0
    while x < x1:
        w = r.choice((2, 3, 4, 6)); d.rectangle((x, y0, min(x + w, x1), y1), fill=INK); x += w + r.choice((2, 3, 4))


def boarding_pass():
    cw, ch, stub = 940, 640, 220
    im = Image.new("RGBA", (cw + 60, ch + 60), (0, 0, 0, 0))
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((30, 40, 30 + cw, 40 + ch), radius=34, fill=(0, 0, 0, 150))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)))
    card = Image.new("RGBA", (cw, ch), (0, 0, 0, 0)); d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 0, cw - 1, ch - 1), radius=34, fill=CREAM)
    d.rounded_rectangle((0, 0, cw - 1, 120), radius=34, fill=RUST); d.rectangle((0, 80, cw - 1, 120), fill=RUST)
    d.text((40, 60), "✈", font=symbol_font(48), fill=CREAM, anchor="lm")
    d.text((104, 60), "BOARDING PASS", font=inter("Black", 44), fill=CREAM, anchor="lm")
    d.text((cw - 40, 60), "FIRST CLASS", font=inter("Bold", 28), fill=AMBER, anchor="rm")
    lab, val = inter("SemiBold", 24), inter("Black", 40)
    L = 44
    d.text((L, 150), "PASSENGER", font=lab, fill=GREY)
    d.text((L, 178), "ROSHNI", font=inter("Black", 92), fill=INK)
    d.text((L, 312), "FROM", font=lab, fill=GREY); d.text((L, 340), "YESTERDAY", font=val, fill=INK)
    d.text((L + 330, 352), "✈", font=symbol_font(44), fill=RUST)
    d.text((L + 410, 312), "TO", font=lab, fill=GREY); d.text((L + 410, 340), "TOMORROW", font=val, fill=INK)
    d.line((L, 418, cw - stub - 30, 418), fill=(215, 205, 190), width=2)
    for i, (k, v) in enumerate((("GATE", "OPEN"), ("SEAT", "WINDOW"), ("BAGS", "LIGHT"))):
        x = L + i * 225
        d.text((x, 444), k, font=lab, fill=GREY); d.text((x, 472), v, font=inter("Black", 38), fill=INK)
    d.text((L, 556), "STATUS", font=lab, fill=GREY)
    d.text((L + 120, 552), "● ON TIME", font=inter("Bold", 30), fill=(40, 150, 80))
    px = cw - stub
    for y in range(140, ch - 20, 22): d.rectangle((px - 1, y, px + 1, y + 11), fill=(190, 178, 160))
    d.ellipse((px - 20, -20, px + 20, 20), fill=(0, 0, 0, 0)); d.ellipse((px - 20, ch - 20, px + 20, ch + 20), fill=(0, 0, 0, 0))
    d.text((px + stub / 2, 160), "FLIGHT", font=lab, fill=GREY, anchor="mm")
    d.text((px + stub / 2, 200), "RS 101", font=inter("Black", 40), fill=INK, anchor="mm")
    _barcode(d, px + 40, 250, cw - 40, 560)
    im.alpha_composite(card, (30, 30))
    return im


def stamp():
    s = Image.new("RGBA", (520, 200), (0, 0, 0, 0)); d = ImageDraw.Draw(s)
    d.rounded_rectangle((8, 8, 512, 192), radius=26, outline=RUST + (235,), width=10)
    d.text((260, 100), "BOARDED", font=inter("Black", 104), fill=RUST + (235,), anchor="mm")
    return s.rotate(-11, expand=True, resample=Image.BICUBIC)


def setup(story):
    story.pass_img, story.stamp_img, story.end_scrim = boarding_pass(), stamp(), vgrad(1300, 0, 190)


def overlay(story, ov, t):
    T = story.T
    if t < T["PASS_IN"]: return
    # darkening only from the card down, never over her face
    ov.alpha_composite(fade(story.end_scrim, ease_out(prog(t, T["PASS_IN"], 0.5))), (0, H - story.end_scrim.height))
    p = ease_back(prog(t, T["PASS_IN"], 0.7), 1.2)
    ov.alpha_composite(story.pass_img, ((W - story.pass_img.width) // 2, int(H + 40 - (H + 40 - PASS_Y) * p)))
    if t >= T["STAMP_AT"]:
        sp = prog(t, T["STAMP_AT"], 0.18); sc = (1.8 - 0.8 * ease_out(sp)) * 0.78
        si = story.stamp_img.resize((int(story.stamp_img.width * sc), int(story.stamp_img.height * sc)), Image.BICUBIC)
        ov.alpha_composite(fade(si, min(1, sp * 2)), (int(640 - si.width / 2), int(PASS_Y + 612 - si.height / 2)))
    if t >= T["TAG_AT"]:
        tp = ease_out(prog(t, T["TAG_AT"], 0.5))
        tg = Image.new("RGBA", (W, 120), (0, 0, 0, 0))
        ImageDraw.Draw(tg).text((W / 2, 60), "Walk like the runway is yours.", font=inter("SemiBold", 50), fill=CREAM, anchor="mm")
        ov.alpha_composite(fade(tg, tp), (0, int(PASS_Y + 780 + (1 - tp) * 30)))
