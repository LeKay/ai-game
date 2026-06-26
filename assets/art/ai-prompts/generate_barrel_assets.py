"""Generate barrel chain assets via PixelLab API (pixen endpoint, 64x64)."""
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
            "Pixel art building tile for a top-down RPG game. A cooperage workshop seen from a "
            "slightly elevated angle (~60-70 degrees above horizon), showing the top face and a "
            "narrow front strip. The building has a dark-brown saddle roof with highlight on the "
            "left slope and shadow on the right. A narrow front wall below the roof has a small "
            "wooden door (~3x4 px). To the right of the entrance, two or three small wooden "
            "barrels are stacked — each barrel is roughly 4 px wide, rendered with curved stave "
            "highlights and iron-hoop bands. One barrel lies on its side at ground level. The "
            "walls are warm tan-brown planks with subtle vertical plank lines. Light source "
            "upper-left, earthy muted palette, 2-3 shading tones per colour, no outline around "
            "the full object, only internal depth lines. Everything outside the building "
            "silhouette is fully transparent. "
            "Color palette: roof highlight #8B5A2B, roof midtone #6B3F1E, roof shadow #4A2B10, "
            "wall plank #C8A06A, door #5C3A1E, barrel stave #A07840, barrel hoop #4A4A4A."
        ),
        "out_path": "assets/art/buildings/bld_tile_cooperage.png",
    },
    {
        "description": (
            "Pixel art resource icon for a top-down RPG game. A single wooden barrel seen from "
            "a slightly elevated angle (~60-70 degrees), showing the top face and a narrow front "
            "strip. The barrel is rendered with curved vertical stave planks highlighted on the "
            "upper-left and shadowed on the lower-right. Two iron hoop bands wrap around the "
            "barrel — one near the top and one near the bottom — rendered as thin dark-grey "
            "arcs. The barrel top is a slightly lighter wood circle with subtle grain lines. "
            "The barrel is exactly centred in the 64x64 tile with equal margins on all sides, "
            "fully visible, no part clipped, at least 4 px gap to every edge. Light source "
            "upper-left, earthy muted palette, no outline around the full object, only internal "
            "depth lines. Everything outside the barrel silhouette is fully transparent. "
            "Color palette: stave highlight #C8A06A, stave midtone #A07840, stave shadow "
            "#6B4E28, hoop #4A4A4A, hoop highlight #6E6E6E, barrel top #B89050."
        ),
        "out_path": "assets/ui/icons/resources/barrel.png",
    },
]

REPO_ROOT = Path(__file__).parent.parent.parent


def generate(description: str, out_path: str) -> None:
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

    full_path = REPO_ROOT / out_path
    full_path.parent.mkdir(parents=True, exist_ok=True)
    full_path.write_bytes(png)
    print(f"Saved {out_path} ({len(png)} bytes)")


if __name__ == "__main__":
    for asset in ASSETS:
        print(f"Generating: {asset['out_path']} ...")
        generate(asset["description"], asset["out_path"])
    print("Done.")
