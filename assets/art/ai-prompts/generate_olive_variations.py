"""Generate slight variations of the single hand-kept olive overlay tile via PixelLab img2img.

The user trimmed assets/art/tiles/olive/ down to one approved sprite (env_tile_olive.png).
terrain_renderer.gd expects up to 16 variants (env_tile_olive_01.png .. _16.png) and picks one
deterministically per tile, so a single sprite makes every olive tile identical. This script
feeds the approved sprite back in as the init_image to /create-image-pixflux and varies only the
seed, so each output stays visually close to the reference but differs slightly.

init_image_strength (1..999) controls how much the init image constrains the result. Its
direction is verified empirically (see --test) before committing to a value — higher is intended
to keep variants closer to the reference.

Usage:
  python generate_olive_variations.py --test          # 2 probe images at low/high strength
  python generate_olive_variations.py                 # fill env_tile_olive_02.png .. _16.png
  python generate_olive_variations.py --strength 700  # override strength

Run from the project root. Restart the Godot editor afterwards to generate .import sidecars.
"""
import argparse
import base64
import json
import os
import urllib.request
from pathlib import Path

API = "https://api.pixellab.ai/v2"
OLIVE_DIR = Path("assets/art/tiles/olive")
REF = OLIVE_DIR / "env_tile_olive_01.png"  # the one hand-kept sprite (renamed from env_tile_olive.png)
VARIANTS = 16          # total slots terrain_renderer.gd can use
DEFAULT_STRENGTH = 600  # keep close to the reference; tune via --test
BASE_SEED = 7100

DESCRIPTION = (
    "Pixel-art top-down game terrain feature: a single small bushy olive tree seen from a high "
    "top-down angle, its rounded silver-green canopy dotted with tiny green and black olives, a "
    "short brown trunk just visible beneath, filling most of the tile. Crisp pixel-art with 2 to "
    "3 shading levels per color, light from the upper-left. The ENTIRE background is fully "
    "transparent: no ground fill, no grass, no tile, no cast shadow; only the tree itself."
)


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    if not key:
        raise RuntimeError("No PixelLab API key. Set PIXELLAB_API_KEY or write to ~/.pixellab_key")
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}


def _ref_b64() -> str:
    return base64.b64encode(REF.read_bytes()).decode("ascii")


def generate_one(seed: int, strength: int, init_b64: str) -> bytes:
    payload = {
        "description": DESCRIPTION,
        "image_size": {"width": 64, "height": 64},
        "view": "high top-down",
        "no_background": True,
        "init_image": {"type": "base64", "base64": init_b64, "format": "png"},
        "init_image_strength": strength,
        "seed": seed,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API + "/create-image-pixflux", data=data, headers=HEADERS, method="POST")
    with urllib.request.urlopen(req) as resp:
        result = json.load(resp)
    img_data = result["image"]["base64"]
    if "," in img_data:
        img_data = img_data.split(",", 1)[1]
    return base64.b64decode(img_data)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", action="store_true", help="generate 2 probe images at strength 300 and 800")
    ap.add_argument("--strength", type=int, default=DEFAULT_STRENGTH)
    args = ap.parse_args()

    if not REF.exists():
        raise SystemExit(f"Reference image missing: {REF}")
    init_b64 = _ref_b64()

    if args.test:
        for strength in (300, 800):
            png = generate_one(BASE_SEED + strength, strength, init_b64)
            out = OLIVE_DIR / f"_probe_strength_{strength}.png"
            out.write_bytes(png)
            print(f"  OK {out.name} (strength={strength}, {len(png)} bytes)")
        print("Inspect the two probe images, then run without --test.")
        return

    print(f"Generating olive variants 02..{VARIANTS:02d} at strength {args.strength}...")
    for i in range(2, VARIANTS + 1):
        png = generate_one(BASE_SEED + i, args.strength, init_b64)
        out = OLIVE_DIR / f"env_tile_olive_{i:02d}.png"
        out.write_bytes(png)
        print(f"  OK {out.name} ({len(png)} bytes)")
    print("Done. Restart the Godot editor to trigger .import sidecar generation.")


if __name__ == "__main__":
    main()
