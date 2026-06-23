"""Regenerate the bees (wildflower + honeybee) overlay tiles as flat top-down TRANSPARENT sprites.

The previous bees tiles were generated as isometric dioramas: a 3D grass+earth cube with flowers
on top. terrain_renderer.gd composites BEES as a transparent overlay over a flat top-down GRASS
base tile, so a diorama (wrong perspective + its own opaque ground) cannot sit on the grass.

This script uses /create-image-pixen (text-to-image, no_background) — NOT img2img from the old
diorama, which would carry the isometric ground over. Every variant is a flat overhead patch of
wildflowers with a couple of bees on a fully transparent background, so the grass tile below shows
through. Output: assets/art/tiles/bees/env_tile_bees_NN.png (NN = 01..16), the slots
terrain_renderer.gd expects.

Usage:
  python generate_bees_variations.py --test   # 2 probe images to eyeball perspective/transparency
  python generate_bees_variations.py          # generate env_tile_bees_01.png .. _16.png

Run from the project root. Restart the Godot editor afterwards to generate .import sidecars.
"""
import argparse
import base64
import json
import os
import urllib.request
from pathlib import Path

API = "https://api.pixellab.ai/v2"
BEES_DIR = Path("assets/art/tiles/bees")
VARIANTS = 16
BASE_SEED = 8300

# Framed as LOOSE INDIVIDUAL SPRITES, not a "tile/terrain/patch" — the latter wording makes pixen
# render an isometric grass+earth diorama (the exact bug we are fixing). Describing separate
# floating objects on transparency defeats that bias and yields a clean grass-compatible overlay.
DESCRIPTION = (
    "Pixel-art overhead view of a few SEPARATE wildflower blossoms and two small honeybees, like "
    "individual loose game item sprites scattered apart with empty gaps between them. Each is its "
    "own little object: a short green stem topped with a tiny yellow, white or pink flower, plus a "
    "couple of bees. Crisp pixel-art, light from upper-left. Fully transparent background: every "
    "pixel that is not a flower or a bee is transparent. There is NO tile, NO ground, NO soil, NO "
    "grass fill, NO cube, NO block, NO diorama, NO platform, NO base plate, NO cast shadow. Just "
    "floating flowers and bees on pure transparency."
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


def generate_one(seed: int) -> bytes:
    payload = {
        "description": DESCRIPTION,
        "image_size": {"width": 64, "height": 64},
        "view": "high top-down",
        "detail": "highly detailed",
        "outline": "lineless",
        "no_background": True,
        "seed": seed,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API + "/create-image-pixen", data=data, headers=HEADERS, method="POST")
    with urllib.request.urlopen(req) as resp:
        result = json.load(resp)
    img_data = result["image"]["base64"]
    if "," in img_data:
        img_data = img_data.split(",", 1)[1]
    return base64.b64decode(img_data)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", action="store_true", help="generate 2 probe images only")
    args = ap.parse_args()
    BEES_DIR.mkdir(parents=True, exist_ok=True)

    if args.test:
        for i in (1, 2):
            png = generate_one(BASE_SEED + i)
            out = BEES_DIR / f"_probe_bees_{i}.png"
            out.write_bytes(png)
            print(f"  OK {out.name} ({len(png)} bytes)")
        print("Inspect the probe images (flat top-down, transparent, no ground), then run without --test.")
        return

    print(f"Generating {VARIANTS} flat transparent bees overlays...")
    for i in range(1, VARIANTS + 1):
        png = generate_one(BASE_SEED + i)
        out = BEES_DIR / f"env_tile_bees_{i:02d}.png"
        out.write_bytes(png)
        print(f"  OK {out.name} ({len(png)} bytes)")
    print("Done. Restart the Godot editor to trigger .import sidecar generation.")


if __name__ == "__main__":
    main()
