"""Generate the overworld settlement marker icons (NPC city + player settlement) via PixelLab API.

Reads the API key from PIXELLAB_API_KEY or ~/.pixellab_key — never hardcode it (the repo is public).
Existing output files are skipped so re-running only fills in missing icons (pass --force to regen).
"""
import sys
import urllib.request
import json
import base64
import os
from pathlib import Path


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

ASSETS = [
    {
        "description": (
            "Top-down RPG pixel art map marker, 64x64 pixels, transparent background. A small "
            "fortified medieval NPC town seen from a high top-down angle: a cluster of a few "
            "houses with steep red-brown tiled roofs, packed tightly together, ringed by a "
            "grey stone curtain wall with two small round corner towers topped by tiny blue "
            "flags. A simple gatehouse on the front wall. Cobblestone courtyard glimpsed "
            "between the roofs. Compact and clearly readable as a town even when shrunk small. "
            "Light source top-left, shadows fall bottom-right, crisp hard-edged pixel shading. "
            "No outline around the whole marker. Everything outside the town walls is fully "
            "transparent. Color palette: roof highlight #C2553C, roof midtone #9A3B2A, roof "
            "shadow #6B2618, stone wall highlight #B6B2A6, wall midtone #8A867A, wall shadow "
            "#56524A, flag #3A6EA5, courtyard cobble #7A7568."
        ),
        "out": "assets/ui/icons/overworld/city.png",
    },
    {
        "description": (
            "Top-down RPG pixel art map marker, 64x64 pixels, transparent background. A small "
            "player frontier settlement seen from a high top-down angle, clearly newer and more "
            "rustic than a walled town: a single log cabin with a brown wooden plank roof, a "
            "small canvas tent beside it, a round campfire with a tiny orange flame and a thin "
            "grey smoke wisp, a couple of stacked wooden crates, and a tall flagpole flying a "
            "bright teal banner to mark it as the player's home base. A patch of trodden dirt "
            "ground holds the buildings together. No surrounding wall. Compact and clearly "
            "readable as a small camp even when shrunk small. Light source top-left, shadows "
            "fall bottom-right, crisp hard-edged pixel shading. No outline around the whole "
            "marker. Everything outside the camp is fully transparent. Color palette: log wall "
            "highlight #B5894F, log midtone #8A6334, log shadow #5E411F, plank roof #6E4A28, "
            "tent canvas #D9CBA6, tent shadow #A99B78, campfire flame #F0962E, dirt #8A7B5E, "
            "banner #2FB6A8, flagpole #6B5436."
        ),
        "out": "assets/ui/icons/overworld/player_settlement.png",
    },
]


def _generate(description: str, out_path: str) -> None:
    payload = {
        "description": description,
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
        d = json.load(resp)

    img = d["image"]["base64"]
    if "," in img:
        img = img.split(",", 1)[1]
    png = base64.b64decode(img)

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(png)
    print(f"Saved {out_path} ({len(png)} bytes)")


if __name__ == "__main__":
    force = "--force" in sys.argv[1:]
    for asset in ASSETS:
        if not force and Path(asset["out"]).exists():
            print(f"Skipping (exists): {asset['out']}")
            continue
        print(f"Generating: {asset['out']} ...")
        _generate(asset["description"], asset["out"])
    print("Done.")
