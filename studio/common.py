"""Shared basics for every format: paths, config, easing, fonts, small drawing helpers."""
import json, os
import yaml
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
FONTS = os.path.join(ASSETS, "fonts")
DETECTOR = os.path.join(ASSETS, "detector", "yunet.onnx")
W, H, FPS = 1080, 1920, 30                  # 9:16 reels


def load_cfg(project_dir):
    with open(os.path.join(project_dir, "project.yaml")) as f:
        return yaml.safe_load(f)


class _Dumper(yaml.SafeDumper):
    """Short lists/maps on one line ([7, walk], {word: [2, she], add: -0.1}) so project.yaml stays readable."""


def _short(data): return len(json.dumps(data, ensure_ascii=False)) <= 100 and not any(
    isinstance(v, str) and len(v) > 60 for v in (data.values() if isinstance(data, dict) else data))


_Dumper.add_representer(list, lambda d, v: d.represent_sequence("tag:yaml.org,2002:seq", v, flow_style=_short(v)))
_Dumper.add_representer(dict, lambda d, v: d.represent_mapping("tag:yaml.org,2002:map", v.items(),
                                                               flow_style=_short(v) and len(v) <= 4))


def save_cfg(project_dir, cfg, header=None):
    """Rewrites project.yaml. Comments inside are lost; the leading comment block is kept (or replaced by `header`)."""
    path = os.path.join(project_dir, "project.yaml")
    if header is None and os.path.exists(path):
        lines = open(path).read().splitlines()
        header = "\n".join(l for l in lines[:next((i for i, l in enumerate(lines) if not l.startswith("#")), len(lines))])
    with open(path, "w") as f:
        if header: f.write(header.rstrip() + "\n")
        yaml.dump(cfg, f, Dumper=_Dumper, sort_keys=False, allow_unicode=True, width=120)


def out_dir(project_dir):
    d = os.path.join(project_dir, "out"); os.makedirs(d, exist_ok=True); return d


# ---------------------------------------------------------------- easing
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def prog(t, s, d): return clamp((t - s) / d) if d > 0 else float(t >= s)
def ease_io(p): return 4 * p ** 3 if p < .5 else 1 - (-2 * p + 2) ** 3 / 2
def ease_out(p): return 1 - (1 - p) ** 3
def ease_back(p, s=1.6): return 1 + (s + 1) * (p - 1) ** 3 + s * (p - 1) ** 2
def lerp(a, b, p): return a + (b - a) * p


# ---------------------------------------------------------------- fonts
# bundled: Playfair Display (500/700), Cormorant Garamond italic, Montserrat (500/600). System: Inter Display, DejaVu.
_font_cache = {}


def font(name, size):
    """font("Playfair_Display_wght_700.ttf", 80) for bundled fonts, or an absolute path for system fonts."""
    key = (name, size)
    if key not in _font_cache:
        path = name if os.path.isabs(name) else os.path.join(FONTS, name)
        _font_cache[key] = ImageFont.truetype(path, size)
    return _font_cache[key]


def inter(weight, size):  # Inter Display (system font in Claude Code cloud VMs): Bold, Black, SemiBold, Medium ...
    return font(f"/usr/share/fonts/opentype/inter/InterDisplay-{weight}.otf", size)


def symbol_font(size):     # has ✈ ● ✓ etc.
    return font("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", size)


# ---------------------------------------------------------------- drawing helpers
def put_center(canvas, im, cx, cy):
    canvas.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def text_center(d, y, txt, fnt, fill, spacing=0, w=W):
    if spacing:
        widths = [fnt.getlength(c) for c in txt]; x = (w - sum(widths) - spacing * (len(txt) - 1)) / 2
        for c, cw in zip(txt, widths):
            d.text((x, y), c, font=fnt, fill=fill); x += cw + spacing
    else:
        d.text((w / 2, y), txt, font=fnt, fill=fill, anchor="ma")


def fade(im, a):
    if a >= 1: return im
    im = im.copy(); im.putalpha(im.getchannel("A").point(lambda v: int(v * max(0.0, a)))); return im


def vgrad(h, a0, a1, w=W, color=(0, 0, 0)):
    """Vertical alpha gradient (a0 at top -> a1 at bottom) as an RGBA strip."""
    g = Image.linear_gradient("L").resize((w, h))
    if a0 > a1: g = g.transpose(Image.FLIP_TOP_BOTTOM); a0, a1 = a1, a0
    return Image.merge("RGBA", (*Image.new("RGB", (w, h), color).split(), g.point(lambda v: int(a0 + (a1 - a0) * v / 255))))


def cover(img, z, ax, ay, size=(W, H), resample=Image.BICUBIC):
    """Crop-to-fill `size`, zoomed by z; image point (ax, ay) keeps its relative screen position (Ken Burns)."""
    iw, ih = img.size
    s = max(size[0] / iw, size[1] / ih) * z
    bw, bh = size[0] / s, size[1] / s
    x0 = min(max(ax * iw - bw * ax, 0), iw - bw); y0 = min(max(ay * ih - bh * ay, 0), ih - bh)
    return img.resize(size, resample, box=(x0, y0, x0 + bw, y0 + bh))


def watermark(ov, text, x, y, alpha=62, rotate=-8, color=(34, 30, 28)):
    wm = Image.new("RGBA", (460, 80), (0, 0, 0, 0))
    ImageDraw.Draw(wm).text((230, 40), text, font=font("Montserrat_wght_600.ttf", 46), fill=color + (alpha,), anchor="mm")
    wm = wm.rotate(rotate, expand=True, resample=Image.BICUBIC)
    ov.alpha_composite(wm, (int(x - wm.width / 2), int(y - wm.height / 2)))
