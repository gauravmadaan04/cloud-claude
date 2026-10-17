import os
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")


def load_cfg(reel_dir):
    with open(os.path.join(reel_dir, "reel.yaml")) as f:
        return yaml.safe_load(f)


def save_cfg(reel_dir, cfg):
    with open(os.path.join(reel_dir, "reel.yaml"), "w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False, allow_unicode=True, width=120)
