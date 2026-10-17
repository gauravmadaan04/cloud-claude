"""Paper-doll "Types of ..." reel renderer.

Layout of a project directory (see projects/<name>/project.yaml, `format: paperdoll`):
  img/<id>.png      model wearing each item (first item = base look); all images share framing
  pieces/<id>.png   paper cut-out of each item (RGBA, white paper border)
  voice/            vo_full.wav, vo_words.json, vo_lines.json, end_line.json   (built by studio.voice)

Story: hook (all items scroll past her) -> one item per line (cut-out flies on, old one flies off)
-> confusion (items swirl, outfit flickers, question marks) -> prime line, ends clean for a CTA stitch.
Every graphic is drawn on an overlay; a face detector clears the overlay from any face on every frame.
"""
import json, math, os, subprocess, sys
import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from studio.common import ASSETS, load_cfg

W, H, FPS = 1080, 1920, 30
INK, GREY, ACCENT = (34, 30, 28), (130, 122, 114), (176, 74, 92)
FD = os.path.join(ASSETS, "fonts") + "/"
DETECTOR = os.path.join(ASSETS, "detector", "yunet.onnx")


def font(name, size): return ImageFont.truetype(FD + name, size)
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def prog(t, s, d): return clamp((t - s) / d) if d > 0 else float(t >= s)
def ease_io(p): return 4 * p ** 3 if p < .5 else 1 - (-2 * p + 2) ** 3 / 2
def ease_out(p): return 1 - (1 - p) ** 3
def ease_back(p, s=1.6): return 1 + (s + 1) * (p - 1) ** 3 + s * (p - 1) ** 2
def lerp(a, b, p): return a + (b - a) * p


F_NAME = font("Playfair_Display_wght_500.ttf", 74)
F_DESC = font("Cormorant_Garamond_ital_wght_1_500.ttf", 50)
F_SUB = font("Montserrat_wght_500.ttf", 28)
F_NUM = font("Montserrat_wght_600.ttf", 26)
F_END = font("Playfair_Display_wght_700.ttf", 70)
F_END_I = font("Cormorant_Garamond_ital_wght_1_500.ttf", 58)
F_END_Q = font("Cormorant_Garamond_ital_wght_1_500.ttf", 84)
F_WM = font("Montserrat_wght_600.ttf", 46)
F_Q = font("Playfair_Display_wght_700.ttf", 120)
F_ASK = font("Playfair_Display_wght_700.ttf", 68)

ORBIT_C, ORBIT_R = (540, 1320), (470, 290)
QMARKS = [(185, 640, -12), (895, 610, 10), (130, 900, 8), (955, 870, -9), (300, 470, -6), (790, 455, 7)]
FACE_SHAPES = [("OVAL", 150, 900), ("ROUND", 150, 1150), ("SQUARE", 150, 1400), ("HEART", 930, 1000), ("LONG", 930, 1270)]
MODEL_S = 0.86
MODEL_X0, MODEL_Y0 = int(540 - 470 * MODEL_S), int(1880 - 1629 * MODEL_S)


def paper():
    rng = np.random.default_rng(1)
    base = np.full((H, W, 3), (250, 247, 241), np.float32)
    n = cv2.GaussianBlur(rng.normal(0, 1, (H, W)).astype(np.float32), (0, 0), 1.2) * 3.0
    fib = cv2.GaussianBlur(rng.normal(0, 1, (H, W)).astype(np.float32), (0, 0), 9) * 4.0
    yy, xx = np.mgrid[0:H, 0:W]
    vig = 1 - 0.06 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    return Image.fromarray(np.clip((base + (n + fib)[..., None]) * vig[..., None], 0, 255).astype(np.uint8))


def put_center(canvas, im, cx, cy):
    canvas.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def text_center(d, y, txt, fnt, fill, spacing=0):
    if spacing:
        widths = [fnt.getlength(c) for c in txt]; x = (W - sum(widths) - spacing * (len(txt) - 1)) / 2
        for c, w in zip(txt, widths):
            d.text((x, y), c, font=fnt, fill=fill); x += w + spacing
    else:
        d.text((W / 2, y), txt, font=fnt, fill=fill, anchor="ma")


def face_shape_icon(kind, scale=1.0):
    im = Image.new("RGBA", (200, 230), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((8, 8, 192, 222), radius=22, fill=(252, 250, 246, 235), outline=(214, 204, 190, 255), width=2)
    c, w5 = (100, 92), 5
    if kind == "OVAL": d.ellipse((c[0] - 46, c[1] - 62, c[0] + 46, c[1] + 62), outline=INK, width=w5)
    elif kind == "ROUND": d.ellipse((c[0] - 58, c[1] - 58, c[0] + 58, c[1] + 58), outline=INK, width=w5)
    elif kind == "SQUARE": d.rounded_rectangle((c[0] - 54, c[1] - 58, c[0] + 54, c[1] + 58), radius=16, outline=INK, width=w5)
    elif kind == "LONG": d.rounded_rectangle((c[0] - 40, c[1] - 66, c[0] + 40, c[1] + 66), radius=36, outline=INK, width=w5)
    elif kind == "HEART":
        pts = [(c[0] + 58 * math.cos(a), c[1] - 14 + 52 * math.sin(a)) for a in [math.pi + i * math.pi / 12 for i in range(13)]]
        pts += [(c[0] + 52, c[1] + 6), (c[0] + 16, c[1] + 54), (c[0], c[1] + 64), (c[0] - 16, c[1] + 54), (c[0] - 52, c[1] + 6)]
        d.line(pts + [pts[0]], fill=INK, width=w5, joint="curve")
    d.text((100, 172), kind, font=F_NUM, fill=ACCENT, anchor="ma")
    return im.resize((max(1, int(200 * scale)), max(1, int(230 * scale))), Image.BICUBIC) if scale != 1 else im


class Reel:
    def __init__(self, reel_dir):
        self.dir = reel_dir
        self.cfg = cfg = load_cfg(reel_dir)
        lay, end = cfg["layout"], cfg["ending"]
        self.ids = [it["id"] for it in cfg["items"]]
        self.labels = [it["label"] for it in cfg["items"]]
        self.hem = {it["id"]: it["hem"] for it in cfg["items"]}
        self.top = lay["outfit_top"]
        self.side_h, self.side_y = lay["side_h"], lay["side_y"]
        self.left, self.right = (150, self.side_y, -6), (930, self.side_y, 6)
        self.hook_spacing, self.hook_h, self.hook_shift = lay["hook_spacing"], lay["hook_h"], lay["hook_shift"]
        self.orbit_h = lay["orbit_h"]
        self.vo_offset = cfg.get("vo_offset", 0.5)
        ts = 82
        while font("Playfair_Display_wght_700.ttf", ts).getlength(cfg["title"]) + 3 * len(cfg["title"]) > 980: ts -= 2
        self.f_title = font("Playfair_Display_wght_700.ttf", ts)

        v = lambda f: os.path.join(reel_dir, "voice", f)
        off = self.vo_offset
        self.words = [dict(q, s=q["s"] + off, e=q["e"] + off) for q in json.load(open(v("vo_words.json")))]
        self.lines = json.load(open(v("vo_lines.json")))
        el = json.load(open(v("end_line.json")))
        self.end_words = [dict(q, s=q["s"] + off, e=q["e"] + off) for q in el["words"]]
        self.swap = [self.line_words(k + 1)[0]["s"] - 0.1 for k in range(len(self.ids))]
        self.conf_t = self.end_words[0]["s"] - 0.15
        self.q_t = self.end_word("which")["s"] - 0.05
        self.not_t = self.end_word(end["pivot_word"])["s"] - 0.1
        self.to_t = self.end_word("to")["s"] - 0.05
        self.hook_end = self.swap[0] - 0.05
        self.hook_order = self.ids[1:] + [self.ids[0]]
        self.dur = round(el["end"] + off + 0.8, 2)
        self.prime_rows = end["prime_rows"]
        self.icons = end.get("icons")
        self.desc = self._descriptions()

        self.paper = paper()
        self.models = self._load_models()
        self.pieces = {n: Image.open(os.path.join(reel_dir, "pieces", f"{n}.png")).convert("RGBA") for n in self.ids}
        self._pc = {}
        self.det = cv2.FaceDetectorYN.create(DETECTOR, "", (540, 960), 0.85, 0.3, 50)
        self.face_log = []

    # ---------------------------------------------------------------- timing helpers
    def line_words(self, li): return [w for w in self.words if w["line"] == li]

    def end_word(self, w, nth=0):
        return [q for q in self.end_words if q["w"].lower().strip(".,?!") == w][nth]

    def _descriptions(self):
        """Description text per item (from the script) timed across the words spoken after the item's name."""
        fin = self.cfg.get("finale", {})
        out = []
        for k in range(len(self.ids)):
            li = k + 1
            ws = self.line_words(li)
            if k == len(self.ids) - 1 and fin:
                desc = fin["desc"]
                skip = [s.lower() for s in fin.get("name_words", [])]
                spoken = [w for w in ws[1:] if w["w"].lower().strip(",.!?") not in skip]
            else:
                desc = self.lines[li].replace("...", "").split(".", 1)[1]
                spoken = [w for w in ws if w["s"] >= ws[0]["e"] - 0.01][1:] or ws
            dw = desc.split()
            out.append([(dw[i], spoken[min(len(spoken) - 1, int(i * len(spoken) / len(dw)))]["s"]) for i in range(len(dw))])
        return out

    def _load_models(self):
        """Load every look, shifted so her face sits exactly where it is in the base look (seamless swaps)."""
        det = cv2.FaceDetectorYN.create(DETECTOR, "", (940, 1672), 0.7, 0.3, 5)
        def face_c(im):
            _, d = det.detect(np.array(im)[:, :, ::-1].copy())
            return (float(d[0][0] + d[0][2] / 2), float(d[0][1] + d[0][3] / 2)) if d is not None else None
        raw = {n: Image.open(os.path.join(self.dir, "img", f"{n}.png")).convert("RGB").resize((940, 1672), Image.LANCZOS)
               for n in self.ids}
        target = face_c(raw[self.ids[0]]) or (474.0, 226.5)
        out = {}
        for n, im in raw.items():
            c = face_c(im) or target
            canvas = Image.new("RGB", im.size, (255, 255, 255))
            canvas.paste(im, (int(round(target[0] - c[0])), int(round(target[1] - c[1]))))
            out[n] = canvas.resize((int(940 * MODEL_S), int(1672 * MODEL_S)), Image.LANCZOS)
        return out

    def body_target(self, n):
        top = MODEL_Y0 + self.top * 1672 * MODEL_S
        hgt = (self.hem[n] - self.top) * 1672 * MODEL_S
        return 540, top + hgt / 2, hgt

    def piece(self, n, height, rot, alpha=1.0):
        key = (n, int(height), round(rot, 1))
        if key not in self._pc:
            p = self.pieces[n]; s = height / p.height
            im = p.resize((max(1, int(p.width * s)), max(1, int(height))), Image.BICUBIC).rotate(rot, expand=True, resample=Image.BICUBIC)
            sh = Image.new("RGBA", (im.width + 40, im.height + 40), (0, 0, 0, 0))
            sh.paste(Image.new("RGBA", im.size, (60, 40, 30, 255)), (26, 30), im.getchannel("A").point(lambda v: int(v * 0.28)))
            sh = sh.filter(ImageFilter.GaussianBlur(9)); sh.alpha_composite(im, (20, 20))
            if len(self._pc) > 400: self._pc.clear()
            self._pc[key] = sh
        im = self._pc[key]
        if alpha < 1:
            im = im.copy(); im.putalpha(im.getchannel("A").point(lambda v: int(v * alpha)))
        return im

    def faces(self, img):
        small = np.array(img.resize((540, 960), Image.BILINEAR))[:, :, ::-1].copy()
        _, det = self.det.detect(small)
        boxes = []
        for d in (det if det is not None else []):
            x, y, w, h = (float(v) * 2 for v in d[:4])
            boxes.append((x - 0.25 * w, y - 0.45 * h, x + 1.25 * w, y + 1.2 * h))
        return boxes

    def current_index(self, t):
        k = 0
        for i, s in enumerate(self.swap[1:], 1):
            if t >= s: k = i
        return k

    def hook_u(self, t):
        n = len(self.ids)
        p = prog(t, 0.05, self.hook_end - 0.05)
        return -1.3 + (n + 0.3) * (1 - (1 - p) ** 2)

    def chaos_name(self, t):
        return self.ids[(int((t - self.conf_t) * 7.5) * 7 + 3) % len(self.ids)]

    def figure_at(self, t):
        if t < self.hook_end:
            i = int(math.floor(self.hook_u(t) + 0.5))
            return self.models[self.hook_order[i]] if i >= 0 else self.models[self.ids[0]]
        if self.conf_t + 0.2 <= t < self.not_t:
            return self.models[self.chaos_name(t)]
        if t >= self.not_t:
            return Image.blend(self.models[self.chaos_name(self.not_t - 0.01)], self.models[self.ids[0]], prog(t, self.not_t, 0.25))
        k = self.current_index(t)
        fig = self.models[self.ids[k]]
        if k >= 1 and t < self.swap[k] + 0.15:
            fig = Image.blend(self.models[self.ids[k - 1]], fig, prog(t, self.swap[k], 0.15))
        return fig

    def words_row(self, d, ws, texts, fnt, col, y, t, alpha=1.0):
        x = (W - fnt.getlength(" ".join(texts))) / 2
        for q, tx in zip(ws, texts):
            p = ease_out(prog(t, q["s"] - 0.06, 0.3))
            if p > 0 and alpha > 0:
                d.text((x, y + (1 - p) * 14), tx, font=fnt, fill=col + (int(255 * p * alpha),))
            x += fnt.getlength(tx + " ")
        return x

    # ---------------------------------------------------------------- one frame
    def render(self, t):
        cfg, n_items = self.cfg, len(self.ids)
        canvas = self.paper.copy()
        intro = ease_out(prog(t, 0.0, 0.3))
        layer = Image.new("RGB", (W, H), (255, 255, 255))
        shake = (math.sin(t * 61) * 5, math.cos(t * 47) * 3) if self.conf_t + 0.2 <= t < self.not_t else (0, 0)
        layer.paste(self.figure_at(t), (int(MODEL_X0 + shake[0]), int(MODEL_Y0 + (1 - intro) * 60 + shake[1])))
        if intro < 1:
            layer = Image.blend(Image.new("RGB", (W, H), (255, 255, 255)), layer, intro)
        canvas = ImageChops.multiply(canvas, layer)          # drawn onto the paper
        face_boxes = self.faces(canvas)
        canvas = canvas.convert("RGBA")
        ov = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
        k = self.current_index(t)

        # titles
        tp = ease_out(prog(t, 0.0, 0.4)) * (1 - ease_io(prog(t, self.conf_t, 0.35)))
        if tp > 0:
            tt = Image.new("RGBA", (W, 120), (0, 0, 0, 0))
            text_center(ImageDraw.Draw(tt), 6, cfg["title"], self.f_title, INK + (int(255 * tp),), spacing=3)
            ov.alpha_composite(tt, (0, int(96 + (1 - ease_out(prog(t, 0.0, 0.4))) * 25)))
            text_center(d, 214, cfg["subtitle"], F_SUB, GREY + (int(255 * tp),), spacing=5)

        # item name + counter + description, above her head
        if self.swap[0] <= t < self.conf_t + 0.2:
            out_a = 1 - prog(t, self.conf_t, 0.2)
            for kk in (k - 1, k):
                if kk < 0: continue
                if kk == k: p = ease_out(prog(t, self.swap[kk], 0.35)); y = 300 + (1 - p) * 40; a = p
                else: p = ease_io(prog(t, self.swap[k], 0.3)); y = 300 - p * 40; a = 1 - p
                if a <= 0.01: continue
                nl = Image.new("RGBA", (W, 110), (0, 0, 0, 0))
                text_center(ImageDraw.Draw(nl), 0, self.labels[kk], F_NAME, ACCENT + (int(255 * a * out_a),), spacing=6)
                ov.alpha_composite(nl, (0, int(y)))
            text_center(d, 268, f"{k + 1:02d} / {n_items}", F_NUM, GREY + (int(200 * ease_out(prog(t, self.swap[k], 0.4)) * out_a),), spacing=2)
            rows, cur = [], []
            for w, ts in self.desc[k]:
                if cur and F_DESC.getlength(" ".join(x for x, _ in cur + [(w, ts)])) > 900: rows.append(cur); cur = []
                cur.append((w, ts))
            rows.append(cur)
            for r, row in enumerate(rows):
                x = (W - F_DESC.getlength(" ".join(x for x, _ in row))) / 2
                for w, ts in row:
                    p = ease_out(prog(t, ts - 0.05, 0.25))
                    if p > 0: d.text((x, 404 + r * 56 + (1 - p) * 10), w, font=F_DESC, fill=INK + (int(235 * p * out_a),))
                    x += F_DESC.getlength(w + " ")

        # hook: every cut-out scrolls past in front of her; her look changes as each one crosses
        bx_a, by_a, bh_a = self.body_target(self.ids[0])
        hook_h = bh_a * self.hook_h
        if t < self.hook_end + 0.3:
            u = self.hook_u(min(t, self.hook_end))
            for i, n in enumerate(self.hook_order):
                cx = 540 + (i - u) * self.hook_spacing
                if cx < -300 or cx > W + 300: continue
                h, cy, a, rot = hook_h, by_a + bh_a * self.hook_shift, 1.0, math.sin(t * 9 + i) * 3
                if n == self.ids[0] and t >= self.hook_end - 0.25:
                    q = ease_io(prog(t, self.hook_end - 0.25, 0.25))
                    h, rot, cy = lerp(hook_h, bh_a, q), lerp(rot, 0, q), lerp(cy, by_a, q); a = 1 - prog(t, self.hook_end, 0.2)
                if a > 0: put_center(ov, self.piece(n, h, rot, a), cx, cy)

        # carousel: next item waits right and flies on; previous flies off to the left
        if self.hook_end <= t < self.conf_t + 0.5:
            car_a = 1 - ease_io(prog(t, self.conf_t, 0.35))
            nk = k + 1
            if nk < n_items:
                enter = ease_out(prog(t, self.swap[k] + 0.12, 0.45)) if k >= 1 else ease_out(prog(t, self.hook_end, 0.5))
                x, y, r, h = self.right[0] + (1 - enter) * 420, self.right[1], self.right[2], self.side_h
                if t >= self.swap[nk] - 0.45:
                    fly = ease_io(prog(t, self.swap[nk] - 0.45, 0.45))
                    bx, by, bh = self.body_target(self.ids[nk])
                    x, y = lerp(x, bx, fly), lerp(y, by, fly) - math.sin(math.pi * fly) * 60
                    r, h = lerp(r, 0, fly), lerp(self.side_h, bh, fly)
                put_center(ov, self.piece(self.ids[nk], h, r, car_a), x, y)
            if k >= 1:
                off = ease_io(prog(t, self.swap[k], 0.45))
                bx, by, bh = self.body_target(self.ids[k - 1])
                x, y = lerp(bx, self.left[0], off), lerp(by, self.left[1], off) - math.sin(math.pi * off) * 60
                put_center(ov, self.piece(self.ids[k - 1], lerp(bh, self.side_h, off), lerp(0, self.left[2], off),
                                          car_a * prog(t, self.swap[k], 0.08)), x, y)
                if k >= 2:
                    gone = ease_io(prog(t, self.swap[k], 0.4))
                    if gone < 1:
                        put_center(ov, self.piece(self.ids[k - 2], self.side_h, self.left[2], car_a), self.left[0] - gone * 420, self.left[1])

        # confusion: items swirl below her face, outfit flickers, question marks pop
        if self.conf_t <= t < self.not_t + 1.4:
            spin = (t - self.conf_t) * (1.6 + 1.2 * prog(t, self.conf_t, self.not_t - self.conf_t)) * 2.2
            come = ease_out(prog(t, self.conf_t, 0.5))
            for i, n in enumerate(self.ids):
                th = 2 * math.pi * i / n_items + spin
                x = ORBIT_C[0] + math.cos(th) * ORBIT_R[0] * lerp(2.2, 1.0, come)
                y = ORBIT_C[1] + math.sin(th) * ORBIT_R[1] + (1 - come) * 650
                rot, a = math.sin(th * 2 + t * 5) * 14, 1.0
                if t >= self.not_t:
                    dt = max(0.0, t - self.not_t - i * 0.04)
                    y += 2600 * dt * dt; rot += dt * 220 * (1 if i % 2 else -1); a = 1 - prog(dt, 0.5, 0.4)
                if a > 0 and -300 < y < H + 300: put_center(ov, self.piece(n, self.orbit_h, rot, a), x, y)
            for j, (qx, qy, qr) in enumerate(QMARKS):
                p = prog(t, self.conf_t + 0.25 + j * 0.28, 0.3)
                a = 1 - prog(t, self.not_t, 0.3)
                if p <= 0 or a <= 0: continue
                qm = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
                ImageDraw.Draw(qm).text((100, 100), "?", font=F_Q, fill=ACCENT + (int(230 * a),), anchor="mm")
                sc = ease_back(p)
                qm = qm.resize((max(1, int(200 * sc)), max(1, int(200 * sc))), Image.BICUBIC).rotate(qr + math.sin(t * 6 + j) * 8, resample=Image.BICUBIC)
                put_center(ov, qm, qx, qy + math.sin(t * 4 + j) * 10)
            oa = 1 - ease_io(prog(t, self.not_t - 0.2, 0.3))
            self.words_row(d, [q for q in self.end_words if q["s"] < self.q_t][:3], ["So", "many", "options..."], F_END_I, ACCENT, 150, t, oa)
            qw = [q for q in self.end_words if self.q_t <= q["s"] < self.not_t]
            self.words_row(d, qw[:4], ["Which", "one", "is", "actually"], F_ASK, INK, 240, t, oa)
            self.words_row(d, qw[4:7], ["right", "for", "YOU?"], F_ASK, INK, 325, t, oa)

        # prime: she stands alone; the line sets up the CTA
        if t >= self.not_t:
            nw = [q for q in self.end_words if self.not_t <= q["s"] < self.to_t]
            i0 = 0
            for r, row in enumerate(self.prime_rows):
                self.words_row(d, nw[i0:i0 + len(row)], row, F_END, INK, 150 + r * 90, t); i0 += len(row)
            tw = [q for q in self.end_words if q["s"] >= self.to_t]
            x = self.words_row(d, tw[:5], ["To", "know", "what", "suits", "you"], F_END_Q, ACCENT, 355, t)
            dots_t = tw[-1]["e"] if tw else self.dur
            for j in range(3):
                a = ease_out(prog(t, dots_t + j * 0.18, 0.2))
                if a > 0: d.text((x - F_END_Q.getlength(" ") + 4 + j * 20, 355), ".", font=F_END_Q, fill=ACCENT + (int(255 * a),))
            if self.icons == "face_shapes":
                st = self.end_word(self.cfg["ending"].get("icons_word", "face"))["s"]
                for j, (kind, sx, sy) in enumerate(FACE_SHAPES):
                    p = prog(t, st + j * 0.22, 0.35)
                    if p > 0: put_center(ov, face_shape_icon(kind, 1.18 * ease_back(p)), sx, sy + math.sin(t * 3 + j) * 6)

        # watermark: low opacity, mid-frame, hops sides on every change
        side = k % 2 if t >= self.swap[0] else 0
        prev_side = ((k - 1) % 2) if k >= 1 else side
        mp = ease_io(prog(t, self.swap[k], 0.5)) if k >= 1 else 1
        wx = lerp((255, 825)[prev_side], (255, 825)[side], mp)
        wm = Image.new("RGBA", (460, 80), (0, 0, 0, 0))
        ImageDraw.Draw(wm).text((230, 40), cfg.get("watermark", "divasclub"), font=F_WM, fill=INK + (62,), anchor="mm")
        ov.alpha_composite(wm.rotate(-8, expand=True, resample=Image.BICUBIC), (int(wx - 230), 1520))

        # face guard: measure, then clear any graphic from every detected face
        a = np.array(ov.getchannel("A")); hit = 0
        if face_boxes:
            fm = Image.new("L", (W, H), 0); fd = ImageDraw.Draw(fm)
            for x0, y0, x1, y1 in face_boxes:
                X0, Y0, X1, Y1 = int(max(0, x0)), int(max(0, y0)), int(min(W, x1)), int(min(H, y1))
                hit += int((a[Y0:Y1, X0:X1] > 12).sum()); fd.ellipse((x0, y0, x1, y1), fill=255)
            ov.putalpha(Image.fromarray(np.minimum(a, 255 - np.array(fm.filter(ImageFilter.GaussianBlur(6))))))
        self.face_log.append(dict(t=round(t, 3), faces=len(face_boxes), overlap_px=hit))
        canvas.alpha_composite(ov)
        fade = 1 - prog(t, 0, 0.25)
        if fade > 0: canvas.alpha_composite(Image.new("RGBA", (W, H), (250, 247, 241, int(255 * fade))))
        return canvas.convert("RGB")

    def events(self):
        ticks, last = [], None
        for f in range(int(self.hook_end * FPS)):
            i = int(math.floor(self.hook_u(f / FPS) + 0.5))
            if i >= 0 and i != last: ticks.append(f / FPS)
            last = i
        return dict(swaps=self.swap, dur=self.dur, vo_offset=self.vo_offset, end_t=self.not_t, hook_ticks=ticks,
                    hook_end=self.hook_end, conf_t=self.conf_t, not_t=self.not_t,
                    chaos=[self.conf_t + 0.2 + i / 7.5 for i in range(int((self.not_t - self.conf_t - 0.2) * 7.5))])


def render_video(reel_dir, stills=None):
    out = os.path.join(reel_dir, "out"); os.makedirs(out, exist_ok=True)
    reel = Reel(reel_dir)
    if stills:
        paths = []
        for t in stills:
            p = os.path.join(out, f"still_{t:05.2f}.jpg"); reel.render(t).save(p, quality=85); paths.append(p)
        return paths
    json.dump(reel.events(), open(os.path.join(out, "events.json"), "w"))
    enc = subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                            "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "14",
                            "-pix_fmt", "yuv420p", os.path.join(out, "graphics.mp4")], stdin=subprocess.PIPE)
    n = round(reel.dur * FPS)
    for i in range(n):
        enc.stdin.write(reel.render(i / FPS).tobytes())
        if i % 300 == 0: print(f"  render {i}/{n}", flush=True)
    enc.stdin.close(); enc.wait()
    json.dump(reel.face_log, open(os.path.join(out, "face_log.json"), "w"))
    hits = sum(1 for f in reel.face_log if f["overlap_px"] > 0)
    print(f"  rendered {n} frames | frames where graphics touched a face (cleared by guard): {hits}")
    return hits
