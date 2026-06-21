"""Generate Salt Works building tile and salt UI icon via PixelLab API."""
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
            "Top-down RPG pixel art building tile, 64x64 pixels, no background, transparent "
            "background outside the structure. Classic top-down RPG perspective, camera elevated "
            "~60-70 degrees above horizon, showing rooftop and a thin front wall strip. "
            "A coastal salt works: two shallow rectangular evaporation pans made of low stone "
            "walls, filled with pale crystalline water showing salt deposits forming at the "
            "edges. A tiny stone storage hut sits top-left with a flat sandy-beige roof. "
            "A wooden rake leans against the hut front wall. Stone pan walls with eroded "
            "texture. Pan water surface with white salt crystal speckles. "
            "Light source top-left, shadows fall bottom-right. No outline around the entire "
            "tile. Everything outside the structure footprint is fully transparent. "
            "Color palette: hut roof highlight #D4C890, roof midtone #B8A868, roof shadow "
            "#8C7840, hut wall #9A8870, stone pan highlight #8C7A6A, pan shadow #50423A, "
            "brine water #A8D4E8, salt crystals #F0F0EC."
        ),
        "out": "assets/art/tiles/bld_tile_salt_works.png",
    },
    {
        "description": (
            "Top-down RPG pixel art resource icon, 64x64 pixels, transparent background. "
            "Classic top-down RPG perspective ~60-70 degrees. A small heap of coarse salt "
            "crystals, angular white and pale-grey grains piled in a loose mound. Largest "
            "crystals at top catching the light. A few scattered individual crystals on "
            "the transparent ground around the mound. Light source top-left, crisp "
            "hard-edged pixel shading. No outline around the entire object. Everything "
            "outside the salt pile is fully transparent. "
            "Color palette: crystal highlight #F4F2EC, midtone #D8D4C8, shadow #B0AAA0, "
            "accent mineral blue-grey #9AAAB8."
        ),
        "out": "assets/ui/icons/resources/salt.png",
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
    for asset in ASSETS:
        print(f"Generating: {asset['out']} ...")
        _generate(asset["description"], asset["out"])
    print("Done.")
