"""Generate brick chain assets via PixelLab API (pixen endpoint, 64x64)."""
import urllib.request, json, base64, os
from pathlib import Path


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
BASE = "https://api.pixellab.ai/v2/create-image-pixen"


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
    req = urllib.request.Request(BASE, data=data, headers=HEADERS, method="POST")
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


BRICK_KILN_DESC = (
    "A small brick kiln building seen from a slightly elevated angle (classic top-down RPG "
    "perspective, roughly 60-70 degrees above horizon). The kiln has a squat stone chimney "
    "with orange glow at the top, dark reddish-brown fired brick walls, a low arched "
    "furnace opening on the front face, and a short stack of unfired clay bricks leaning "
    "against the left side as the characteristic operational prop. Light source upper-left, "
    "shadows fall lower-right. Earthy muted palette. Roof/top surface shows warm brick "
    "texture. Object is fully centered with at least 3 px clearance on all sides. "
    "Background is fully transparent — no ground, no border, no fill. "
    "Color palette: chimney highlight #D4704A, chimney midtone #A84E30, chimney shadow #6E2E14, "
    "wall brick #B85C3A, wall mortar #8C6B56, furnace opening #2A1A0E, clay stack #C49A72."
)

BRICK_ICON_DESC = (
    "A single fired clay brick seen from a slightly elevated angle (classic top-down RPG "
    "perspective). The brick is rectangular with visible rough texture, showing the top face "
    "and a narrow front edge. Warm reddish-brown color with subtle mortar-line grooves. "
    "Light source upper-left, shadow lower-right. Earthy muted palette, 2-3 shading tones. "
    "Object fully centered with at least 3 px clearance on all sides. "
    "Background fully transparent. "
    "Color palette: top face highlight #D4704A, top face midtone #A84E30, shadow edge #6E2E14, "
    "mortar groove #7A5C48."
)

generate(BRICK_KILN_DESC, "assets/art/tiles/bld_tile_brick_kiln.png")
generate(BRICK_ICON_DESC, "assets/ui/icons/resources/brick.png")
