"""Paper-doll image stages: base look -> item looks -> paper cut-outs -> hemline measurement.

All looks are edits of ONE base image so the model, pose and framing stay identical (seamless swaps).
"""
import os
import numpy as np
from PIL import Image, ImageFilter

from studio import kie
from studio.common import ROOT, load_cfg, save_cfg
from studio.imaging import img_job as _job


def _img_job(name, urls, prompt, aspect="9:16"):
    return _job(name, urls, prompt, aspect, "1K")


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
              f"and rerun: make.py {reel_dir} images --only {' '.join(failed)}")


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


def measure_hems(reel_dir, overwrite=False):
    """Estimate each item's hemline (fraction of image height) by matching the garment colour at the belly.
    Unreliable for white/black/navy items (they blend with background/jeans) — check and fix those by hand in project.yaml."""
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
