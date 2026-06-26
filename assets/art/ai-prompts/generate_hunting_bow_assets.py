"""Generate hunting bow chain assets via PixelLab API."""
import urllib.request
import json
import base64
import os
from pathlib import Path

def _load_api_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key_file = Path.home() / ".pixellab_key"
        if key_file.exists():
            key = key_file.read_text().strip()
    if not key:
        raise RuntimeError("No PixelLab API key found. Set PIXELLAB_API_KEY env var or write key to ~/.pixellab_key")
    return key

API_KEY = _load_api_key()
HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json",
}

ASSETS = [
    {
        "description": (
            "Top-down RPG tile, slightly elevated view ~60-70 degrees above horizon, showing "
            "a small wooden workshop building. Saddle roof with wood-plank shingles, left "
            "side highlighted, right side in shadow. Narrow front wall strip with a small "
            "arched doorway (~3x4 px). Distinguishing detail: a wooden long-bow hung "
            "vertically on the left exterior wall (light tan curved stave, dark string), "
            "and scattered wood shavings on the ground in front of the door. Light source "
            "upper-left, shadows lower-right. Earthy muted palette. 2-3 shading levels per "
            "color. No outline around the whole object, only internal depth lines. Object "
            "exactly centered with 2-4 px clearance to all edges. Everything outside the "
            "building silhouette is fully transparent. "
            "Color palette: roof highlight #C8A85A, roof midtone #A07840, roof shadow #6B4E28, "
            "wall #D4B87A, door #5C3A1A, bow stave #C8A040, shavings #E8C878."
        ),
        "out_path": "assets/art/tiles/bld_tile_bowyers_workshop.png",
        "label": "Bowyer's Workshop tile",
    },
    {
        "description": (
            "Top-down RPG item icon, slightly elevated view ~60-70 degrees above horizon. "
            "A simple wooden hunting bow: curved light-tan stave with visible grain texture, "
            "taut dark bowstring. Bow oriented diagonally (lower-left to upper-right) so "
            "the full curve is readable. Light source upper-left, subtle shadow on the right "
            "side of the stave. Earthy muted palette. 2-3 shading levels. No outline around "
            "the whole object, only internal depth lines. Object exactly centered with 2-4 px "
            "clearance to all edges. Everything outside the bow silhouette is fully transparent. "
            "Color palette: stave highlight #D4AA55, stave midtone #A07830, stave shadow #6B4E18, "
            "string #4A3520."
        ),
        "out_path": "assets/ui/icons/resources/hunting_bow.png",
        "label": "Hunting Bow UI icon",
    },
]


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
    # Strip data URI prefix if present
    if "," in img_data:
        img_data = img_data.split(",", 1)[1]
    png = base64.b64decode(img_data)

    out = asset["out_path"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(png)
    print(f"Saved {asset['label']}: {out} ({len(png)} bytes)")


if __name__ == "__main__":
    for asset in ASSETS:
        generate(asset)
    print("Done. Restart Godot editor to trigger .import sidecar generation.")
