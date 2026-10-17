"""ffmpeg pipes for frame-by-frame rendering."""
import subprocess
from PIL import Image

from .common import W, H, FPS


def encoder(path, vf=None, crf=12, preset="medium"):
    """Popen that takes raw RGB frames on stdin:  enc.stdin.write(img.tobytes()) ... close(enc)."""
    return subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                             "-r", str(FPS), "-i", "-", *(["-vf", vf] if vf else []), "-c:v", "libx264",
                             "-preset", preset, "-crf", str(crf), "-pix_fmt", "yuv420p", path], stdin=subprocess.PIPE)


def close(enc):
    enc.stdin.close(); enc.wait()
    if enc.returncode: raise RuntimeError("ffmpeg encoder failed")


def frames(path):
    """Yield every frame of a video as a PIL RGB image."""
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                           stdout=subprocess.PIPE)
    while True:
        buf = dec.stdout.read(W * H * 3)
        if len(buf) < W * H * 3: break
        yield Image.frombytes("RGB", (W, H), buf)
    dec.wait()


def frame_at(path, t):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", path, "-frames:v", "1",
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    return Image.frombytes("RGB", (W, H), raw)


def filter_image(img, vf):
    """Run one image through an ffmpeg filter chain (e.g. a colour grade) and get it back."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-i", "-",
                          "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         input=img.convert("RGB").tobytes(), capture_output=True, check=True).stdout
    return Image.frombytes("RGB", (W, H), raw)
