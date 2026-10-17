"""Face guard: keep every graphic off every face, on every frame — and prove it.

Usage inside a renderer:
    guard = FaceGuard()
    ...
    boxes = guard.detect(picture_rgb)          # the picture WITHOUT graphics
    guard.apply(overlay_rgba, boxes, t)        # clears graphics from faces, logs any overlap
    ...
    guard.save(path); guard.summary()          # 'frames where graphics touched a face' must be 0 for a final render

The overlap count is measured BEFORE clearing: a non-zero count means a graphic was placed over a face and got
punched out (visible as a hole) — move that graphic and re-render instead of relying on the guard.
"""
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .common import DETECTOR, W, H


def _iou(a, b):
    iw = max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])); ih = max(0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))
    inter = iw * ih
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)


class FaceGuard:
    def __init__(self, min_score=0.7, sure_score=0.85):
        self.det = cv2.FaceDetectorYN.create(DETECTOR, "", (540, 960), min_score, 0.3, 50)
        self.sure, self.prev, self.log = sure_score, [], []

    def detect(self, img):
        """Expanded face boxes (hairline to below chin) in frame coords. Weak detections must persist 2 frames
        (filters one-frame false positives like coffee cups)."""
        small = np.array(img.convert("RGB").resize((540, 960), Image.BILINEAR))[:, :, ::-1].copy()
        _, det = self.det.detect(small)
        raw = [tuple(float(v) * 2 for v in d[:4]) + (float(d[-1]),) for d in (det if det is not None else [])]
        keep = [r for r in raw if r[4] >= self.sure or any(_iou(r, p) > 0.3 for p in self.prev)]
        self.prev = raw
        return [(x - 0.25 * w, y - 0.45 * h, x + 1.25 * w, y + 1.2 * h) for x, y, w, h, _ in keep]

    def apply(self, ov, boxes, t):
        a = np.array(ov.getchannel("A")); hit = 0
        if boxes:
            fm = Image.new("L", (W, H), 0); d = ImageDraw.Draw(fm)
            for x0, y0, x1, y1 in boxes:
                X0, Y0, X1, Y1 = int(max(0, x0)), int(max(0, y0)), int(min(W, x1)), int(min(H, y1))
                hit += int((a[Y0:Y1, X0:X1] > 12).sum()); d.ellipse((x0, y0, x1, y1), fill=255)
            ov.putalpha(Image.fromarray(np.minimum(a, 255 - np.array(fm.filter(ImageFilter.GaussianBlur(6))))))
        self.log.append(dict(t=round(t, 3), faces=len(boxes), overlap_px=hit))
        return hit

    def save(self, path): json.dump(self.log, open(path, "w"))

    def summary(self):
        hits = [f["t"] for f in self.log if f["overlap_px"] > 0]
        none = [f["t"] for f in self.log if f["faces"] == 0]
        print(f"  face guard: {len(self.log)} frames | graphics touched a face in {len(hits)} "
              f"{'(times: ' + str(hits[:10]) + ')' if hits else ''} | frames without a detected face: {len(none)}")
        return len(hits)
