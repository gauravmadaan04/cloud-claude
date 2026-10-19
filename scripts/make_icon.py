"""Draws Haven's app icon and writes the asset catalog PNGs.

python3 scripts/make_icon.py
"""
import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "App", "Resources", "Assets.xcassets", "AppIcon.appiconset")
S = 4  # supersampling


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def hexrgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def squircle_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([inset, inset, size - inset, size - inset], radius=radius, fill=255)
    return m


def draw_icon(px=1024):
    size = px * S
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inset = int(size * 100 / 1024)
    body = size - 2 * inset
    radius = int(body * 0.225)

    # Background gradient: violet → coral, diagonal.
    grad = Image.new("RGBA", (size, size))
    top, mid, bottom = hexrgb(0x7B5CF5), hexrgb(0xB86BE0), hexrgb(0xFF8A80)
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        c = lerp(top, mid, t / 0.55) if t < 0.55 else lerp(mid, bottom, (t - 0.55) / 0.45)
        gd.line([(0, y), (size, y)], fill=c + (255,))
    # Soft light from the top-left (smooth radial falloff, computed small then scaled up).
    small = 256
    glow_small = Image.new("L", (small, small), 0)
    gp = glow_small.load()
    for yy in range(small):
        for xx in range(small):
            dist = math.hypot(xx - small * 0.22, yy - small * 0.12) / (small * 0.85)
            gp[xx, yy] = int(max(0.0, 1 - dist) ** 2 * 60)
    glow_mask = glow_small.resize((size, size), Image.BICUBIC)
    white = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    grad = Image.composite(white, grad, glow_mask)

    # Drop shadow under the squircle.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sm = squircle_mask(size, inset, radius)
    shadow.paste((0, 0, 0, 90), (0, int(size * 0.012)), sm)
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.018))
    img = Image.alpha_composite(img, shadow)
    img.paste(grad, (0, 0), sm)

    d = ImageDraw.Draw(img)
    cx = size / 2

    # A folder-shaped house: back tab, then body with a pitched roof.
    w = body * 0.60
    h = body * 0.46
    left, right = cx - w / 2, cx + w / 2
    base_y = inset + body * 0.80
    top_y = base_y - h
    r = body * 0.05


    # Roof + body polygon (white).
    roof_peak = top_y - body * 0.16
    pts = [
        (left, top_y + body * 0.02),
        (cx, roof_peak),
        (right, top_y + body * 0.02),
        (right, base_y),
        (left, base_y),
    ]
    house = Image.new("L", (size, size), 0)
    hd = ImageDraw.Draw(house)
    hd.polygon(pts, fill=255)
    # Round the corners by blurring + thresholding.
    house = house.filter(ImageFilter.GaussianBlur(r * 0.55)).point(lambda v: 255 if v > 128 else 0)
    house = house.filter(ImageFilter.GaussianBlur(S * 0.8))
    hshadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hshadow.paste((60, 20, 90, 80), (0, int(body * 0.02)), house)
    hshadow = hshadow.filter(ImageFilter.GaussianBlur(body * 0.025))
    img = Image.alpha_composite(img, hshadow)
    img.paste((255, 255, 255, 255), (0, 0), house)

    d = ImageDraw.Draw(img)
    # Door-shaped "window" showing a little photo: sky + sun + hill.
    dw, dh = w * 0.34, h * 0.52
    dx0, dy1 = cx - dw / 2, base_y - h * 0.16
    dy0 = dy1 - dh
    door = Image.new("L", (size, size), 0)
    ImageDraw.Draw(door).rounded_rectangle([dx0, dy0, dx0 + dw, dy1], radius=dw * 0.22, fill=255)
    pic = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pic)
    for y in range(int(dy0), int(dy1) + 1):
        t = (y - dy0) / max(1, dh)
        pd.line([(dx0, y), (dx0 + dw, y)], fill=lerp(hexrgb(0x8EC5FF), hexrgb(0xFFE3B3), t) + (255,))
    sr = dw * 0.16
    pd.ellipse([dx0 + dw * 0.58 - sr, dy0 + dh * 0.30 - sr, dx0 + dw * 0.58 + sr, dy0 + dh * 0.30 + sr], fill=hexrgb(0xFFC93D) + (255,))
    hill = [(dx0, dy1)]
    for i in range(41):
        x = dx0 + dw * i / 40
        y = dy0 + dh * (0.70 - 0.12 * math.sin(i / 40 * math.pi * 1.3 + 0.4))
        hill.append((x, y))
    hill.append((dx0 + dw, dy1))
    pd.polygon(hill, fill=hexrgb(0x4CD496) + (255,))
    img.paste(pic, (0, 0), door)

    # Magnifying glass badge, bottom right.
    gx, gy, gr = cx + w * 0.40, base_y - h * 0.02, body * 0.11
    badge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(badge)
    bd.ellipse([gx - gr * 1.25, gy - gr * 1.25, gx + gr * 1.25, gy + gr * 1.25], fill=(40, 20, 80, 70))
    badge = badge.filter(ImageFilter.GaussianBlur(body * 0.02))
    img = Image.alpha_composite(img, badge)
    d = ImageDraw.Draw(img)
    d.ellipse([gx - gr, gy - gr, gx + gr, gy + gr], fill=hexrgb(0x6B4EFF) + (255,))
    ring = gr * 0.46
    lw = int(gr * 0.17)
    d.ellipse([gx - ring - gr * 0.12, gy - ring - gr * 0.12, gx + ring - gr * 0.12, gy + ring - gr * 0.12], outline=(255, 255, 255, 255), width=lw)
    hx, hy = gx - gr * 0.12 + ring * 0.72, gy - gr * 0.12 + ring * 0.72
    d.line([(hx, hy), (hx + gr * 0.38, hy + gr * 0.38)], fill=(255, 255, 255, 255), width=int(lw * 1.25))

    return img.resize((px, px), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    master = draw_icon(1024)
    master.save(os.path.join(ROOT, "scripts", "icon-1024.png"))
    images = []
    for pts in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pts * scale
            name = f"icon_{pts}x{pts}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
            images.append({"idiom": "mac", "size": f"{pts}x{pts}", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
