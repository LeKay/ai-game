"""Generate charcoal chain assets via PixelLab API (commitble — no key in code)."""
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
BASE_URL = "https://api.pixellab.ai/v2"


def check_balance() -> dict:
    req = urllib.request.Request(
        f"{BASE_URL}/balance",
        headers={"Authorization": f"Bearer {KEY}"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


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
        f"{BASE_URL}/create-image-pixen",
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


KILN_PROMPT = (
    "Pixel art charcoal kiln building tile for a top-down RPG, viewed from a slightly "
    "elevated angle of about 60-70 degrees (classic top-down RPG perspective) — the top "
    "surface and a narrow front strip are both visible. The building is a low rounded "
    "earth-and-stone mound kiln (Kohlenmeiler), dome-shaped, packed dark earth with stone "
    "reinforcement around the base. The dome top has a small vent hole with faint dark "
    "smoke wisps rising from it. To the front-left of the mound, a small stack of 2-3 "
    "dark logs is visible as a characteristic operational detail. Light source comes from "
    "the upper-left: the dome top-left face is the lightest, center midtone, lower-right "
    "shadow. The base stone ring has a slightly lighter highlight on the upper-left stones. "
    "Everything outside the building silhouette is fully transparent. "
    "Color palette: dome highlight #8B7055, dome midtone #5C4530, dome shadow #362818, "
    "stone base #706050, log stack #4A3220, smoke vent #2A1E14."
)

CHARCOAL_ICON_PROMPT = (
    "Pixel art icon of three pieces of charcoal (coal chunks) for a top-down RPG resource "
    "icon, viewed from a slightly elevated angle. Three irregularly shaped dark charcoal "
    "chunks arranged in a loose cluster, slightly overlapping. The chunks have rough, jagged "
    "edges and a matte dark black-grey surface. A sparse bright highlight glint on the "
    "upper-left face of each chunk catches the light source from the upper-left direction. "
    "No outline around the entire group — only internal edge lines between chunk faces. "
    "Everything outside the charcoal chunks is fully transparent. Highly detailed pixel art. "
    "Color palette: chunk highlight #706868, chunk midtone #302828, chunk shadow #181010, "
    "internal edge #100C0C."
)

ASSETS = [
    (KILN_PROMPT,          "assets/art/tiles/bld_tile_charcoal_kiln.png"),
    (CHARCOAL_ICON_PROMPT, "assets/ui/icons/resources/charcoal.png"),
]

if __name__ == "__main__":
    bal = check_balance()
    print(f"Balance: {bal}")
    for prompt, path in ASSETS:
        generate(prompt, path)
    print("Done.")
