"""Generate the wooden footbridge tile for the river ford / land-bridge feature.

One horizontal deck is generated via the PixelLab pixen endpoint (real PNG, transparent
background); the vertical variant is derived by a 90-degree rotation so both stay identical
in style. See water-bridge-prompts.md for the prompt rationale.

Key is read from ~/.pixellab_key (never hardcoded). Run: python3 <this file>
"""
import urllib.request
import json
import base64
import os
import io
from pathlib import Path

from PIL import Image


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    if not key:
        raise RuntimeError("No PixelLab API key. Set PIXELLAB_API_KEY or write ~/.pixellab_key")
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

TILES_DIR = Path(__file__).resolve().parents[2] / "art" / "tiles"

HORIZONTAL_DESCRIPTION = (
    "Top-down RPG object on a fully transparent background. A simple horizontal wooden "
    "plank footbridge deck running straight from the left edge to the right edge of the "
    "frame. Two parallel wooden stringer beams run left-to-right, with short transverse "
    "planks laid across them forming the walkway, and low wooden side railings along the "
    "top and bottom long edges. The bridge deck is the ONLY thing in the image. Weathered "
    "brown timber, light source upper-left, soft shadows lower-right. Earthy muted palette, "
    "2-3 shading levels per colour, no outline around the whole object, only internal plank "
    "and depth lines. NO water, NO river, NO ground, NO background scenery whatsoever - the "
    "entire area around, above and below the deck is 100% transparent (alpha zero). "
    "Color palette: plank highlight #B08A52, plank midtone #8A6638, plank shadow #5C4322, "
    "railing #9A7240, beam shadow #4E3818."
)


def generate_horizontal() -> Image.Image:
    payload = {
        "description": HORIZONTAL_DESCRIPTION,
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
    return Image.open(io.BytesIO(png)).convert("RGBA")


def main() -> None:
    TILES_DIR.mkdir(parents=True, exist_ok=True)
    horizontal = generate_horizontal()
    h_path = TILES_DIR / "env_tile_bridge_h_01.png"
    horizontal.save(h_path)
    print(f"  OK horizontal: {h_path}")

    # Vertical = horizontal rotated 90 degrees (expand=True keeps it square at 64x64).
    vertical = horizontal.rotate(90, expand=True)
    v_path = TILES_DIR / "env_tile_bridge_v_01.png"
    vertical.save(v_path)
    print(f"  OK vertical (rotated): {v_path}")


if __name__ == "__main__":
    main()
