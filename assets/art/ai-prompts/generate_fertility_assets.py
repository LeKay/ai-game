"""Generate world-overlay + UI icons for the nine second-wave fertilities via PixelLab pixen.

Mirrors generate_ore_deposit_assets.py. Produces, per resource, two centered transparent icons:
  - assets/art/tiles/env_tile_resource_<id>.png   (world/carry badge -> world_icon_path)
  - assets/ui/icons/resources/<id>.png            (inventory/HUD icon -> icon_path)

The opaque field/beach GROUND tilesets (env_tile_<id>_NN.png for flax/hops/grapes/sand) are
generated separately by generate_fertility_ground_tiles.py. The transparent terrain overlay
tilesets for olive/bees/marble/amber/pearl are produced like the tree/stone overlays. Until all
art exists the game falls back to the per-type solid colors (_TERRAIN_FALLBACK_COLORS) and each
resource's fallback_color in data/resources.json.
"""
import urllib.request
import json
import base64
import os
from pathlib import Path


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    if not key:
        raise RuntimeError("No PixelLab API key. Set PIXELLAB_API_KEY or write to ~/.pixellab_key")
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

# Per-resource distinguishing subject + palette. Shared transparency/centering/lighting
# boilerplate is appended by _build_description().
RESOURCES = [
    {"id": "flax",
     "subject": "a small neat bundle of harvested flax stalks tied together — slender green stems "
                "topped with a few tiny pale blue flowers and seed pods",
     "palette": "stalk green #5E7E3A, leaf highlight #7E9E50, flax bloom #8FB2D8, tie #9A7A4A"},
    {"id": "hops",
     "subject": "a small loose cluster of several pale green papery hop cones with a couple of "
                "green leaves, lying freely together",
     "palette": "cone #C6D88A, cone shadow #8FA85A, leaf #6E9A3C, highlight #DCE8B0"},
    {"id": "grapes",
     "subject": "a single plump bunch of deep purple grapes with a small green leaf and curl of "
                "vine at the top",
     "palette": "grape purple #6B2A6B, grape highlight #9A5AA0, deep shadow #3E1840, leaf #4E7A38"},
    {"id": "olives",
     "subject": "a small loose cluster of several ripe green and black olives with a sprig of "
                "narrow silver-green olive leaves",
     "palette": "olive green #6E7E3A, olive black #2E2A22, leaf silver-green #9AAE7A, glint #C8D2A0"},
    {"id": "honey",
     "subject": "a small open clay pot of golden honey with a wooden honey dipper resting across "
                "it and a thick glossy drip down the side",
     "palette": "honey gold #E0A828, honey highlight #F6D870, pot clay #9A6A42, drip #D89A20"},
    {"id": "sand",
     "subject": "a small loose heap of fine pale golden sand with a couple of tiny shell flecks, "
                "the grains forming a soft rounded mound",
     "palette": "sand base #E6D8A8, sand highlight #F2E8C2, sand shadow #C8B884, shell #F0E6D0"},
    {"id": "marble",
     "subject": "a small loose stack of two or three rough-cut white marble blocks with subtle "
                "grey veining and chipped natural edges, NOT a single fused cube",
     "palette": "marble white #E8E8EC, marble shadow #B8BAC2, vein grey #8A8C94, highlight #FAFAFE"},
    {"id": "amber",
     "subject": "a small loose cluster of two or three translucent warm-orange amber nuggets with "
                "smooth rounded organic shapes and bright inner glints, one with a tiny dark fleck",
     "palette": "amber orange #D6841E, amber highlight #F4B454, deep amber #9A5610, glint #FCE0A0"},
    {"id": "pearl",
     "subject": "a few small lustrous round off-white pearls resting in a half-open grey oyster "
                "shell, the pearls catching soft iridescent highlights",
     "palette": "pearl white #F2EEE6, pearl sheen #FFFFFF, pearl shadow #C8C2B8, shell grey #8A8E92"},
]

_BOILERPLATE = (
    "It is perfectly centered in the square image frame with equal empty space on all four sides "
    "and does not touch any edge. Viewed from a slightly elevated angle, about 60 to 70 degrees "
    "above the horizon, like a classic top-down RPG inventory item, so it has clear visible height "
    "and mass. Light comes from the upper-left: the top and upper-left are the lightest, the "
    "lower-right is in shadow and darkest. 2 to 3 shading levels per color, crisp pixel-art shapes, "
    "no outline around the whole object, only internal depth lines. The ENTIRE background is fully "
    "transparent — there is no ground, no floor, no tiles, no platform, no base plate, no table and "
    "no cast shadow on any surface; only the object itself is visible, floating on pure "
    "transparency. Color palette: "
)


def _build_description(res: dict) -> str:
    return (
        "A single isolated pixel-art RPG item icon of " + res["subject"] + ". " + _BOILERPLATE
        + res["palette"] + "."
    )


def _assets(only: set[str] | None = None) -> list[dict]:
    out: list[dict] = []
    for res in RESOURCES:
        if only and res["id"] not in only:
            continue
        desc = _build_description(res)
        out.append({"label": f"{res['id']} world overlay",
                    "out": f"assets/art/tiles/env_tile_resource_{res['id']}.png", "description": desc})
        out.append({"label": f"{res['id']} UI icon",
                    "out": f"assets/ui/icons/resources/{res['id']}.png", "description": desc})
    return out


def generate(asset: dict) -> None:
    payload = {
        "description": asset["description"],
        "image_size": {"width": 64, "height": 64},
        "view": "high top-down",
        "detail": "highly detailed",
        "outline": "lineless",
        "no_background": True,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        "https://api.pixellab.ai/v2/create-image-pixen",
        data=data,
        headers=HEADERS,
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        result = json.load(resp)

    img_data = result["image"]["base64"]
    if "," in img_data:
        img_data = img_data.split(",", 1)[1]
    png = base64.b64decode(img_data)

    out = asset["out"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(png)
    print(f"  OK {asset['label']}: {out} ({len(png)} bytes)")


if __name__ == "__main__":
    import sys
    only = set(sys.argv[1:]) or None  # pass resource ids to regenerate a subset, e.g. `... amber pearl`
    assets = _assets(only)
    print(f"Generating {len(assets)} fertility icons{' for ' + ', '.join(sorted(only)) if only else ''}...")
    for asset in assets:
        generate(asset)
    print("Done. Generate the opaque ground tiles via generate_fertility_ground_tiles.py,")
    print("then restart the Godot editor to trigger .import sidecar generation.")
