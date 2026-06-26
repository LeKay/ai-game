"""Generate rope chain assets via PixelLab API (pixen endpoint, 64x64)."""
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
BASE_URL = "https://api.pixellab.ai/v2/create-image-pixen"

ASSETS = [
    {
        "out": Path("assets/art/buildings/bld_tile_rope_maker.png"),
        "description": (
            "A small rustic wooden rope-making workshop perfectly centered in the tile "
            "with equal empty space on all four sides, viewed from a slightly elevated "
            "angle — about 60 to 70 degrees above the horizon, like a classic top-down "
            "RPG perspective. The entire building is fully visible — no part touches or "
            "crosses any edge of the tile. Because of the slight angle, you can see both "
            "the sloped roof from above and a narrow strip of the front wall, giving the "
            "building clear visible height and mass. "
            "The roof is a shallow pitched gable roof running left to right. The left "
            "slope catches the overhead light from the upper-left and is the lightest "
            "warm tan-brown. The right slope is in shadow and is the darkest brown. A "
            "narrow front wall strip is visible below the roof edge: plank-wall texture "
            "in mid warm brown, and a small dark rectangular door opening (3x4 pixels) "
            "centered on the front face. "
            "To the right side of the building, a large coiled bundle of twisted rope "
            "sits on the ground — thick golden-brown coils stacked in a neat flat pile, "
            "showing the finished output. At the front-left, two short vertical wooden "
            "posts with thin rope strands strung between them form a simple "
            "rope-twisting rack, hinting at the craft inside. "
            "The building footprint is roughly 18 to 20 pixels wide and 14 to 16 pixels "
            "tall on the tile. The walls are made of horizontal wooden planks in warm "
            "mid brown. Everything outside the building is fully transparent. "
            "Color palette: roof highlight #A09060, roof midtone #706840, roof shadow "
            "#4A4428, wall #8A7050, door #302010, rope coil highlight #C8A840, rope "
            "coil shadow #8A7228, post #7A6040."
        ),
    },
    {
        "out": Path("assets/ui/icons/resources/rope.png"),
        "description": (
            "A neatly coiled length of twisted brown rope perfectly centered on a fully "
            "transparent background, viewed from a slightly elevated angle — about 60 to "
            "70 degrees above the horizon, like a classic top-down RPG perspective. The "
            "rope is wound into a compact circular coil showing 3 to 4 overlapping loops "
            "of thick twisted fiber cord. "
            "The rope surface clearly shows the characteristic twisted two-strand texture "
            "in warm golden-brown. The upper-left portion of the coil catches overhead "
            "light and shows the brightest warm gold-brown highlight. The lower-right "
            "portion is in shadow, darker brown. The rope coil sits entirely within the "
            "tile, centered with equal empty space on all sides and at least 6 pixels of "
            "transparent margin on every edge. "
            "No ground, no shadow cast onto a surface, no background fill — only the rope "
            "coil itself on a fully transparent background. "
            "Color palette: rope highlight #D4A840, rope midtone #A07828, rope shadow "
            "#6A5018, twist dark line #3A2808."
        ),
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
    req = urllib.request.Request(BASE_URL, data=data, headers=HEADERS, method="POST")
    with urllib.request.urlopen(req) as resp:
        d = json.load(resp)

    img = d["image"]["base64"]
    if "," in img:
        img = img.split(",", 1)[1]
    png = base64.b64decode(img)
    out: Path = asset["out"]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)
    print(f"Saved {out}  ({len(png):,} bytes)")


if __name__ == "__main__":
    for asset in ASSETS:
        print(f"Generating {asset['out']} ...")
        generate(asset)
    print("Done.")
