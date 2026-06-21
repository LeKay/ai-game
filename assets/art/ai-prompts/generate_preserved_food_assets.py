"""Generate preserved food chain assets via PixelLab API."""
import urllib.request, json, base64, os
from pathlib import Path


def _load_key():
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

ASSETS = [
    {
        "description": (
            "A small preservation house perfectly centered in the tile with equal empty space on all "
            "four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the "
            "horizon. The building uses rough stone walls with visible mortar joints. A squat stone "
            "chimney rises slightly off-center on the roof, emitting a faint pixel smudge of smoke. "
            "The saddle roof is covered with dark clay tiles: highlight on the left side, shadow on "
            "the right. A narrow front wall strip shows a low wooden door with iron hinges. To the "
            "right of the door, two stacked clay pottery jars in earthy ochre tones sit on a small "
            "stone ledge — they are the key identifying feature of this building. To the left, a "
            "small wooden hanging rack displays two dark cured meat bundles tied with thin fiber "
            "cord. Light source upper-left. Everything outside the building silhouette is fully "
            "transparent. "
            "Color palette: roof highlight #8A7060, roof midtone #5C4A38, roof shadow #2E2018, "
            "wall block #8A8070, mortar #4A4040, door #2A1A10, jar body #B07840, jar highlight #D09860, "
            "cured meat dark #6A2820."
        ),
        "out": "assets/art/tiles/bld_tile_preservation_house.png",
    },
    {
        "description": (
            "A single sealed ceramic preservation jar perfectly centered in the tile with equal empty "
            "space on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees "
            "above the horizon. The jar is a short round-bellied pottery vessel in warm ochre-brown "
            "tones. A scrap of dark cloth is tied over the mouth with a thin cord, indicating a "
            "hermetic seal. Light from upper-left creates a highlight arc on the left shoulder of "
            "the vessel and a cast shadow on the lower-right. A faint ring of white crystalline salt "
            "residue marks the neck where it was sealed. The jar stands alone on a fully transparent "
            "background. Everything outside the jar silhouette is fully transparent. "
            "Color palette: jar highlight #D09860, jar midtone #A07040, jar shadow #5A3820, "
            "cloth #4A3828, salt ring #D8D0C0, cord #8A6040."
        ),
        "out": "assets/ui/icons/resources/preserved_food.png",
    },
]

BASE = Path(__file__).parent.parent.parent


def generate(asset):
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
        d = json.load(resp)
    img = d["image"]["base64"]
    if "," in img:
        img = img.split(",", 1)[1]
    png = base64.b64decode(img)
    out = BASE / asset["out"]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)
    print(f"Saved {out} ({len(png)} bytes)")


if __name__ == "__main__":
    for asset in ASSETS:
        print(f"Generating: {asset['out']}")
        generate(asset)
    print("Done.")
