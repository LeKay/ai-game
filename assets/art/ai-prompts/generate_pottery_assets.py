"""Generate pottery chain assets via PixelLab API."""
import urllib.request, json, base64, os
from pathlib import Path

def _load_api_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    if not key:
        raise RuntimeError("No PixelLab API key. Set PIXELLAB_API_KEY or write to ~/.pixellab_key")
    return key

API_KEY = _load_api_key()
BASE_URL = "https://api.pixellab.ai/v2"

def check_balance():
    req = urllib.request.Request(
        f"{BASE_URL}/balance",
        headers={"Authorization": f"Bearer {API_KEY}"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)

def generate(description: str, out_path: str):
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
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        d = json.load(resp)
    png = base64.b64decode(d["image"]["base64"])
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(png)
    print(f"Saved {out_path} ({len(png)} bytes)")

ASSETS = [
    (
        "A small clay pit building seen from a classic top-down RPG perspective (~60-70 degrees above horizon), pixel art style, highly detailed, lineless (no black outline around the whole object). The structure has a low timber-framed shed roof with wooden support beams, seen at a slight angle showing the top and a narrow front strip. In front of the shed lies a mound of raw reddish-brown clay freshly dug from the earth. The pit entrance is visible as a dark earthy recess. Light comes from the upper-left; shadows fall to the lower-right. Roof boards are weathered grey-brown wood. Walls are rough timber planks. Everything outside the building silhouette is fully transparent. Color palette: roof highlight #A08060, roof midtone #7A6040, roof shadow #4E3C20, wall #8C6E48, clay mound highlight #C87840, clay mound midtone #A05820, clay mound shadow #6B3810.",
        "assets/art/tiles/bld_tile_clay_pit.png",
    ),
    (
        "A pottery kiln building seen from a classic top-down RPG perspective (~60-70 degrees above horizon), pixel art style, highly detailed, lineless (no black outline around the whole object). The kiln is a squat rounded dome structure made of fired clay bricks in warm terracotta tones, with a small smoke hole visible on the top surface. A narrow front strip shows a sealed brick arch entrance. Beside the kiln stands a finished clay pot as the operational requisite. Light comes from the upper-left; shadows fall to the lower-right. Brick highlights are warm orange-tan, shadows are deep brown. Everything outside the building silhouette is fully transparent. Color palette: brick highlight #C8784A, brick midtone #A05830, brick shadow #6B3818, dome top #8C4820, pot #D49060, pot shadow #9A6038.",
        "assets/art/tiles/bld_tile_pottery_kiln.png",
    ),
    (
        "A single clay pottery vessel (amphora-style pot) seen from a slightly elevated angle, pixel art style, highly detailed, lineless. The pot has a round belly, narrow neck, and two small handles. Warm terracotta color with light catch on the upper-left shoulder and deep shadow on the lower-right. Everything outside the pot silhouette is fully transparent. Object is centered with at least 4 pixels margin on all sides. Color palette: pot highlight #D4905A, pot midtone #B06830, pot shadow #7A4018, rim #C87848.",
        "assets/ui/icons/resources/pottery.png",
    ),
]

if __name__ == "__main__":
    bal = check_balance()
    print(f"Balance: {bal}")
    print(f"Will generate {len(ASSETS)} assets. Proceed? (y/n)")
    if input().strip().lower() != "y":
        print("Aborted.")
    else:
        for desc, path in ASSETS:
            generate(desc, path)
        print("Done. Open Godot editor to trigger .import sidecar generation.")
