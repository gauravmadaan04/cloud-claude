"""Image stages: base look -> item looks -> paper cut-outs -> bindi removal -> hemline measurement.

All looks are edits of ONE base image so the model, pose and framing stay identical (seamless swaps).
"""
import json, os, shutil
import cv2
import numpy as np
from PIL import Image, ImageFilter

from . import kie
from .common import ASSETS, ROOT, load_cfg, save_cfg

DETECTOR = os.path.join(ASSETS, "detector", "yunet.onnx")


def _img_job(name, urls, prompt, aspect="9:16"):
    return {"name": name, "kind": "task", "ext": "png", "body": {"model": "gpt-image-2-image-to-image", "input": {
        "input_urls": urls, "prompt": prompt, "aspect_ratio": aspect, "resolution": "1K"}}}


def images(reel_dir, only=None):
    """Generate the base look (from the model reference) and then every other look from the base."""
    cfg = load_cfg(reel_dir); g = cfg["generation"]; items = cfg["items"]
    img = os.path.join(reel_dir, "img"); os.makedirs(img, exist_ok=True)
    base_id = items[0]["id"]
    if not os.path.exists(os.path.join(img, f"{base_id}.png")) and (only is None or base_id in only):
        ref = kie.upload(os.path.join(ROOT, g["model_image"]))
        kie.run_jobs([_img_job(base_id, [ref], g["base_keep"] + items[0]["prompt"] + g["end"])], img)
    base_url = kie.upload(os.path.join(img, f"{base_id}.png"))
    todo = [it for it in items[1:] if (only is None or it["id"] in only)]
    res = kie.run_jobs([_img_job(it["id"], [base_url], g["keep"] + it["prompt"] + g["end"]) for it in todo], img)
    failed = [n for n, p in res.items() if p is None]
    if failed:
        print(f"  !! failed (often an over-cautious content filter): {failed} — reword those prompts more modestly "
              f"and rerun: make_reel.py {reel_dir} images --only {' '.join(failed)}")


def cutouts(reel_dir, only=None):
    """Paper-doll cut-out of each item, drawn from the matching look, then background-removed with a paper border."""
    cfg = load_cfg(reel_dir); g = cfg["generation"]
    ids = [it["id"] for it in cfg["items"] if only is None or it["id"] in only]
    raw = os.path.join(reel_dir, "out", "cut_raw"); os.makedirs(raw, exist_ok=True)
    urls = {n: kie.upload(os.path.join(reel_dir, "img", f"{n}.png")) for n in ids}
    kie.run_jobs([_img_job(n, [urls[n]], g["cutout_prompt"], g.get("cutout_aspect", "3:4")) for n in ids], raw)
    pieces(reel_dir, ids)


def pieces(reel_dir, ids):
    from rembg import new_session, remove
    s = new_session("isnet-general-use")
    os.makedirs(os.path.join(reel_dir, "pieces"), exist_ok=True)
    for n in ids:
        im = Image.open(os.path.join(reel_dir, "out", "cut_raw", f"{n}.png")).convert("RGB")
        m = remove(im, session=s, only_mask=True).convert("L").point(lambda v: 255 if v > 110 else int(v * 2.3))
        rgba = im.copy(); rgba.putalpha(m); rgba = rgba.crop(m.point(lambda v: 255 if v > 40 else 0).getbbox())
        pad = 24; big = Image.new("RGBA", (rgba.width + 2 * pad, rgba.height + 2 * pad), (0, 0, 0, 0)); big.alpha_composite(rgba, (pad, pad))
        border = big.getchannel("A").filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(1.2))
        paper = Image.new("RGBA", big.size, (252, 250, 246, 0)); paper.putalpha(border); paper.alpha_composite(big)
        paper.save(os.path.join(reel_dir, "pieces", f"{n}.png"))
    print(f"  {len(ids)} paper pieces ready")


def remove_bindi_image(bgr):
    """Find a bindi on the forehead centre line (from the eye landmarks) and inpaint it. Returns (image, message)."""
    h, w = bgr.shape[:2]
    det = cv2.FaceDetectorYN.create(DETECTOR, "", (w, h), 0.6, 0.3, 5)
    _, faces = det.detect(bgr)
    if faces is None: return bgr, "no face"
    f = faces[0]; re_, le = np.array(f[4:6]), np.array(f[6:8])
    mid, dist = (re_ + le) / 2, np.linalg.norm(le - re_)
    x0, x1 = int(mid[0] - 0.16 * dist), int(mid[0] + 0.16 * dist)
    y0, y1 = int(mid[1] - 0.80 * dist), int(mid[1] - 0.18 * dist)
    roi = bgr[y0:y1, x0:x1].astype(float)
    skin = np.median(roi.reshape(-1, 3), axis=0)
    b, g, r = roi[..., 0], roi[..., 1], roi[..., 2]
    cand = (((roi.mean(2) < skin.mean() - 55) | ((r > 100) & (r - g > 50) & (r - b > 40) & (np.abs(roi - skin).sum(2) > 70))) * 255).astype(np.uint8)
    n, lab, stats, cent = cv2.connectedComponentsWithStats(cand, 8)
    best, score = None, 1e9
    for i in range(1, n):
        _, _, bw, bh, area = stats[i]
        if not (12 <= area <= 900) or not (0.5 <= bw / max(bh, 1) <= 2.0) or area / float(bw * bh) < 0.45: continue
        sc = abs(cent[i][0] - (x1 - x0) / 2)
        if sc < score: best, score = i, sc
    if best is None: return bgr, "no bindi"
    mask = np.zeros((h, w), np.uint8); mask[y0:y1, x0:x1][lab == best] = 255
    mask = cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
    return cv2.inpaint(bgr, mask, 5, cv2.INPAINT_TELEA), f"removed bindi ({int(stats[best, cv2.CC_STAT_AREA])} px)"


def debindi(reel_dir):
    img = os.path.join(reel_dir, "img"); bak = os.path.join(reel_dir, "out", "img_original"); os.makedirs(bak, exist_ok=True)
    for f in sorted(os.listdir(img)):
        src = os.path.join(bak, f)
        if not os.path.exists(src): shutil.copy2(os.path.join(img, f), src)
        out, msg = remove_bindi_image(cv2.imread(src))
        cv2.imwrite(os.path.join(img, f), out); print(f"  {f}: {msg}")


def measure_hems(reel_dir, overwrite=False):
    """Estimate each item's hemline (fraction of image height) by matching the garment colour at the belly.
    Unreliable for white/black/navy items (they blend with background/jeans) — check and fix those by hand in reel.yaml."""
    cfg = load_cfg(reel_dir)
    for it in cfg["items"]:
        if it.get("hem") and not overwrite: continue
        im = np.array(Image.open(os.path.join(reel_dir, "img", f"{it['id']}.png")).convert("RGB").resize((940, 1672))).astype(float)
        ref = np.median(im[640:760, 400:540].reshape(-1, 3), axis=0)
        dist = np.sqrt(((im - ref) ** 2).sum(2))
        rows = [y for y in range(600, 1560) if (dist[y, 230:720] < 38).sum() > 12]
        it["hem"] = round(max(rows) / 1672, 3) if rows else 0.75
        print(f"  {it['id']}: hem {it['hem']}")
    save_cfg(reel_dir, cfg)
