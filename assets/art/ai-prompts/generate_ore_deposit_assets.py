"""Generate overlay + UI icons for the six ore/gem deposits via PixelLab pixen API.

Mirrors generate_clay_leather_assets.py. Produces, per ore, two centered transparent icons:
  - assets/art/tiles/env_tile_resource_<ore>.png   (world/carry overlay -> world_icon_path)
  - assets/ui/icons/resources/<ore>.png            (inventory/HUD icon  -> icon_path)

The 16-variant ground pit tilesets (env_tile_<ore>_NN.png) are generated separately by
generate_ore_ground_tiles.py (async /v2/create-tiles-pro). Until both exist the game
falls back to per-ore solid colors (_TERRAIN_FALLBACK_COLORS) and the resource fallback_color.
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

# Per-ore: the distinguishing description fragment + color palette line. The shared boilerplate
# (irregular natural shape, perspective, transparency, lighting) is added by _build_description().
# v2 (2026-06-22): rewritten to stop the model rendering cube/brick ore blocks and tile
# backgrounds — stress raw nugget shape, anti-cube, hard transparent background.
ORES = [
    {
        "id": "iron",
        "subject": (
            "a small loose cluster of several raw iron-ore nuggets lying freely together in a "
            "little pile — irregular rounded craggy metallic lumps of varying size, each a dull "
            "grey-brown rock studded with rusty-orange and dark steel metallic specks and small "
            "glints. They rest loosely against one another like a handful of raw ore nuggets, NOT "
            "fused into one block"
        ),
        "palette": "rock #6E5A50, highlight #8A766A, shadow #46382F, iron ore #9C6A4A, glint #C89A7A",
    },
    {
        "id": "copper",
        "subject": (
            "a single rough lump of raw copper ore — a craggy natural mineral nugget. Bright "
            "orange-bronze copper metallic specks, glinting facets and a few greenish patina "
            "flecks are embedded in dull grey-brown host rock, so it clearly reads as raw copper ore"
        ),
        "palette": "rock #7C6048, highlight #A88A6A, shadow #4E3A28, copper #C07838, patina #5FA07A",
    },
    {
        "id": "tin",
        "subject": (
            "a single rough lump of raw tin ore — a craggy natural mineral nugget. Dull "
            "pewter-grey tin metallic specks with a faint cool sheen and small glinting facets are "
            "embedded in grey host rock, so it clearly reads as raw tin ore"
        ),
        "palette": "rock #74767A, highlight #9A9CA0, shadow #4A4C50, tin #B6B8BE, glint #D6D8DC",
    },
    {
        "id": "silver",
        "subject": (
            "a single rough lump of raw silver ore — a craggy natural mineral nugget. Bright "
            "pale-silver metallic specks, veins and glinting facets stand out sharply against the "
            "dark host rock, so it clearly reads as raw silver ore"
        ),
        "palette": "rock #54565C, highlight #C8CBD2, shadow #34363A, silver #E6E8EE, glint #FFFFFF",
    },
    {
        "id": "gold",
        "subject": (
            "a small loose cluster of several raw gold nuggets lying freely together in a little "
            "pile — irregular rounded blobby lumps of solid native gold of varying size, with a "
            "rich warm-gold metallic surface and bright glints on their upper edges, a few showing "
            "tiny patches of dark rock. They rest loosely against one another like a handful of "
            "gold nuggets, NOT fused into one block"
        ),
        "palette": "gold midtone #D4A82E, highlight #F4DC72, shadow #8A6A1A, deep #6E5A1E, glint #FFF0A0",
    },
    {
        "id": "gemstones",
        "subject": (
            "a small loose cluster of three or four cut gemstones lying freely together in a little "
            "pile — sharp faceted teal and violet crystals of varying size, each with flat angular "
            "facets and tiny bright glints on their upper edges. They rest loosely against one "
            "another, NOT mounted in any ring, socket, setting, frame or plate"
        ),
        "palette": "gem teal #3E8A8E, teal highlight #5FBFC2, gem violet #9A6AD0, shadow #27585A, glint #DFFAFB",
    },
]

# Strong anti-cube + hard-transparency boilerplate. No use of the word "tile" (it tended to induce
# a tiled ground); the shape is explicitly irregular/organic and forbidden from being a cube/block.
_BOILERPLATE = (
    "The silhouette is irregular, craggy and organic with an uneven bumpy surface and rounded "
    "natural edges — it is absolutely NOT a cube, NOT a square block, NOT a brick, NOT a box, with "
    "no flat straight sides and no regular geometry. It is perfectly centered in the square image "
    "frame with equal empty space on all four sides and does not touch any edge. Viewed from a "
    "slightly elevated angle, about 60 to 70 degrees above the horizon, like a classic top-down "
    "RPG inventory item, so it has clear visible height and mass. Light comes from the upper-left: "
    "the top and upper-left are the lightest, the lower-right is in shadow and darkest. 2 to 3 "
    "shading levels per color, crisp pixel-art shapes, no outline around the whole object, only "
    "internal depth lines. The ENTIRE background is fully transparent — there is no ground, no "
    "floor, no stone tiles, no cobblestone, no platform, no base plate, no table, and no cast "
    "shadow on any surface; only the object itself is visible, floating on pure transparency. "
    "Color palette: "
)


def _build_description(ore: dict) -> str:
    return (
        "A single isolated pixel-art RPG item icon of " + ore["subject"] + ". " + _BOILERPLATE
        + ore["palette"] + "."
    )


def _assets(only: set[str] | None = None) -> list[dict]:
    out: list[dict] = []
    for ore in ORES:
        if only and ore["id"] not in only:
            continue
        desc = _build_description(ore)
        out.append({"label": f"{ore['id']} world overlay",
                    "out": f"assets/art/tiles/env_tile_resource_{ore['id']}.png", "description": desc})
        out.append({"label": f"{ore['id']} UI icon",
                    "out": f"assets/ui/icons/resources/{ore['id']}.png", "description": desc})
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
    only = set(sys.argv[1:]) or None  # pass ore ids to regenerate a subset, e.g. `... iron gold`
    assets = _assets(only)
    print(f"Generating {len(assets)} ore/gem icons{' for ' + ', '.join(sorted(only)) if only else ''}...")
    for asset in assets:
        generate(asset)
    print("Done. Generate the 16-variant pit tilesets via generate_ore_ground_tiles.py,")
    print("then restart the Godot editor to trigger .import sidecar generation.")
