"""Generate the 16-variant TRANSPARENT terrain-overlay tilesets for the overlay fertilities.

Covers olive / bees / marble / amber / pearl — the fertilities whose terrain sprite is a
transparent object composited over a base tile (GRASS for olive/bees, COAST ocean for pearl,
sand for marble/amber) by terrain_renderer.gd. Because the base must show through, these MUST be
transparent — so they use the pixen recipe (no_background) rather than create-tiles-pro (opaque).

Each resource gets 16 variants via a per-variant seed:
  POST /v2/create-image-pixen  (one image per call, fully transparent background)
Saves assets/art/tiles/env_tile_<id>_NN.png (NN = 01..16), wired into terrain_renderer.gd.
Until they exist the game falls back to _TERRAIN_FALLBACK_COLORS.

The opaque field/beach ground tiles (flax/hops/grapes/sand) come from
generate_fertility_ground_tiles.py; the centered world/UI icons from generate_fertility_assets.py.
"""
import urllib.request
import json
import base64
import os
from pathlib import Path

API = "https://api.pixellab.ai/v2"
VARIANTS = 16
BASE_SEED = 4200  # per-variant seed = BASE_SEED + index; distinct per resource via offset


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    if not key:
        raise RuntimeError("No PixelLab API key. Set PIXELLAB_API_KEY or write to ~/.pixellab_key")
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

# Per-resource subject + palette. Framed to fill most of the tile (a terrain feature, not a tiny
# inventory item) and sit on the ground plane, viewed from a high top-down angle, with a fully
# transparent background so the base tile (grass / ocean / sand) shows around it.
OVERLAYS = [
    {"id": "olive", "seed_offset": 0,
     "subject": "a single small bushy olive tree seen from a high top-down angle, its rounded "
                "silver-green canopy dotted with tiny green and black olives, a short brown trunk "
                "just visible beneath, filling most of the tile",
     "palette": "canopy silver-green #6E7E3A, leaf highlight #9AAE7A, olive black #2E2A22, trunk #5A4632"},
    {"id": "bees", "seed_offset": 100,
     "subject": "a small patch of wildflowers seen from a high top-down angle — clusters of little "
                "yellow, white and pink blossoms on green stems with a couple of bees hovering "
                "over them, spread across most of the tile",
     "palette": "flower yellow #F2D03A, flower white #F4F0E2, flower pink #E08AA8, stem green #5E8A3A, bee #2E2A22"},
    {"id": "marble", "seed_offset": 200,
     "subject": "a rough natural outcrop of white marble rock seen from a high top-down angle — a "
                "cluster of chunky angular pale stone blocks with subtle grey veining and chipped "
                "edges jutting from the ground, filling most of the tile",
     "palette": "marble white #E8E8EC, marble shadow #B8BAC2, vein grey #8A8C94, highlight #FAFAFE"},
    {"id": "amber", "seed_offset": 300,
     "subject": "a scatter of translucent warm-orange amber nodules exposed in the ground seen "
                "from a high top-down angle — several smooth rounded glossy lumps of varying size "
                "catching bright inner glints, spread across the tile",
     "palette": "amber orange #D6841E, amber highlight #F4B454, deep amber #9A5610, glint #FCE0A0"},
    {"id": "pearl", "seed_offset": 400,
     "subject": "a single half-open grey oyster shell resting in shallow water seen from a high "
                "top-down angle, cradling two or three small lustrous off-white pearls that catch "
                "soft iridescent highlights, centered in the tile",
     "palette": "pearl white #F2EEE6, pearl sheen #FFFFFF, pearl shadow #C8C2B8, shell grey #8A8E92"},
]

_BOILERPLATE = (
    "Crisp pixel-art with 2 to 3 shading levels per color and no outline around the whole object, "
    "only internal depth lines. Light comes from the upper-left: top and upper-left lightest, "
    "lower-right darkest. The object keeps a small margin from the tile edges so it tiles cleanly. "
    "The ENTIRE background is fully transparent — there is no ground fill, no grass, no water, no "
    "tile, no platform, no base plate and no cast shadow on any surface; only the object itself is "
    "visible, floating on pure transparency. Color palette: "
)

TILES_DIR = Path("assets/art/tiles")


def _build_description(ov: dict) -> str:
    return "Pixel-art top-down game terrain feature: " + ov["subject"] + ". " + _BOILERPLATE + ov["palette"] + "."


def _generate_one(description: str, seed: int) -> bytes:
    payload = {
        "description": description,
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


def generate(ov: dict) -> None:
    TILES_DIR.mkdir(parents=True, exist_ok=True)
    desc = _build_description(ov)
    print(f"  {ov['id']}: generating {VARIANTS} transparent variants...")
    for i in range(1, VARIANTS + 1):
        seed = BASE_SEED + ov["seed_offset"] + i
        png = _generate_one(desc, seed)
        out = TILES_DIR / f"env_tile_{ov['id']}_{i:02d}.png"
        with open(out, "wb") as f:
            f.write(png)
        print(f"    OK {out.name} ({len(png)} bytes)")
    print(f"  {ov['id']}: done -> {TILES_DIR}/env_tile_{ov['id']}_NN.png")


if __name__ == "__main__":
    import sys
    only = set(sys.argv[1:]) or None  # pass ids to regenerate a subset, e.g. `... olive pearl`
    overlays = [o for o in OVERLAYS if not only or o["id"] in only]
    total = len(overlays) * VARIANTS
    print(f"Generating {total} transparent overlay tiles for {len(overlays)} fertilities...")
    for ov in overlays:
        generate(ov)
    print("Done. Restart the Godot editor to trigger .import sidecar generation for the new tiles.")
