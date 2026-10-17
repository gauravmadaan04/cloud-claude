"""Image stages shared by all formats: generate stills with GPT Image 2 (via Kie), remove bindis.

`images:` block in project.yaml (any format that doesn't bring its own image stage):
    images:
      refs: [refs/face.jpg, refs/full.jpg]   # optional reference photos (character consistency); none = text-to-image
      resolution: 1K                        # 1K (~6 credits) or 2K (~10)
      aspect: "9:16"
      prefix: "Use the woman in the reference photos ... "   # shared character/look description
      suffix: ". Photorealistic ... No text, no logos, no watermark."
      shots:
        s1_hero: She walks towards the camera ...            # -> img/s1_hero.png
"""
import os, shutil
import cv2
import numpy as np

from . import kie
from .common import DETECTOR, load_cfg


def img_job(name, urls, prompt, aspect="9:16", resolution="1K"):
    model = "gpt-image-2-image-to-image" if urls else "gpt-image-2-text-to-image"
    inp = {"prompt": prompt, "aspect_ratio": aspect, "resolution": resolution}
    if urls: inp["input_urls"] = urls
    return {"name": name, "kind": "task", "ext": "png", "body": {"model": model, "input": inp}}


def generate(project_dir, only=None, force=False):
    """Generate every image listed in `images.shots` that doesn't exist yet (or those in `only`)."""
    g = load_cfg(project_dir)["images"]
    img = os.path.join(project_dir, "img"); os.makedirs(img, exist_ok=True)
    todo = {k: v for k, v in g["shots"].items()
            if (only and k in only) or (not only and (force or not os.path.exists(os.path.join(img, f"{k}.png"))))}
    if not todo: print("  all images exist (use --only id ... to regenerate some)"); return
    refs = [kie.upload(r if os.path.isabs(r) else os.path.join(project_dir, r)) for r in g.get("refs", [])]
    res = kie.run_jobs([img_job(k, refs, g.get("prefix", "") + v + g.get("suffix", ""), g.get("aspect", "9:16"),
                                g.get("resolution", "1K")) for k, v in todo.items()], img)
    failed = [n for n, p in res.items() if p is None]
    if failed:
        print(f"  !! failed (often an over-cautious content filter): {failed} -- reword those prompts more modestly "
              f"and rerun with --only {' '.join(failed)}")


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
