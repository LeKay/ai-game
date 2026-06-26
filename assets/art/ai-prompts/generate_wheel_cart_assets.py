"""Generate wheel & cart chain assets via PixelLab API (create-image-pixen, 64x64)."""
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
            "Pixel art building tile for a top-down RPG game. A wheel maker workshop seen from a slightly "
            "elevated angle (~60-70 degrees above horizon), showing the top face and a narrow front strip. "
            "The building has a warm brown saddle roof with highlight on the left slope and shadow on the right. "
            "A narrow front wall below the roof has a small wooden door (~3x4 px). Leaning against the right "
            "side of the building are two or three large spoked wooden wheels — each wheel is roughly 6 px in "
            "diameter, rendered with a circular rim, four or five thin spoke lines radiating from a small dark "
            "hub at centre, with highlight on the upper-left arc and shadow on the lower-right arc. The walls "
            "are warm tan-brown timber planks with subtle vertical plank lines. Light source upper-left, earthy "
            "muted palette, 2-3 shading tones per colour, no outline around the full object, only internal "
            "depth lines. Everything outside the building silhouette is fully transparent. "
            "Color palette: roof highlight #8B5A2B, roof midtone #6B3F1E, roof shadow #4A2B10, "
            "wall plank #C8A06A, door #5C3A1E, wheel rim #A07840, wheel spoke #8B6030, wheel hub #4A3018."
        ),
        "out": "assets/art/buildings/bld_tile_wheel_maker.png",
    },
    {
        "description": (
            "Pixel art building tile for a top-down RPG game. A cart workshop seen from a slightly elevated "
            "angle (~60-70 degrees above horizon), showing the top face and a narrow front strip. The building "
            "has a dark tan saddle roof with highlight on the left slope and shadow on the right. A narrow front "
            "wall below the roof has a small wooden door (~3x4 px). In front of the entrance sits a small "
            "finished wooden cart — the cart body is a flat rectangular plank frame about 8 px wide and 5 px "
            "tall, with two spoked wheels (each ~5 px diameter) visible on either side, rendered with rim arc, "
            "spokes, and a small hub. The cart casts a tiny shadow to the lower-right. The walls are warm tan "
            "timber planks with subtle plank lines. Light source upper-left, earthy muted palette, 2-3 shading "
            "tones per colour, no outline around the full object, only internal depth lines. Everything outside "
            "the building silhouette is fully transparent. "
            "Color palette: roof highlight #7A4A22, roof midtone #5A3215, roof shadow #3A200B, "
            "wall plank #C8A06A, door #5C3A1E, cart body #B89050, cart shadow #6B4E28, "
            "wheel #A07840, wheel hub #4A3018."
        ),
        "out": "assets/art/buildings/bld_tile_cart_workshop.png",
    },
    {
        "description": (
            "Pixel art resource icon for a top-down RPG game. A single large wooden wheel with spokes, seen "
            "from a slightly elevated angle (~60-70 degrees above horizon). The wheel has a thick circular "
            "wooden rim rendered with highlight on the upper-left arc and shadow on the lower-right arc. Five "
            "or six straight spoke lines radiate from a small dark circular hub at the centre to the inner edge "
            "of the rim. The rim is wider at the top (facing the light source) and narrower in shadow at the "
            "bottom-right. The wheel is exactly centred in the 64x64 tile with equal margins on all sides, "
            "fully visible, no part clipped, at least 6 px gap to every edge. Light source upper-left, earthy "
            "muted palette, no outline around the full object, only internal depth lines. Everything outside "
            "the wheel silhouette is fully transparent. "
            "Color palette: rim highlight #C8A06A, rim midtone #A07840, rim shadow #6B4E28, "
            "spoke #8B6030, hub #4A3018, hub highlight #6B4E28."
        ),
        "out": "assets/ui/icons/resources/wheel.png",
    },
    {
        "description": (
            "Pixel art resource icon for a top-down RPG game. A small wooden cart seen from a slightly "
            "elevated angle (~60-70 degrees above horizon), showing the top face of the flat cart bed and a "
            "narrow front strip. The cart body is a simple rectangular flat-bed frame made of planks — roughly "
            "20 px wide and 14 px tall in the tile. Two large spoked wooden wheels (each ~10 px diameter) are "
            "attached on either side of the cart body, visible as circular rims with four or five spokes "
            "radiating from a small hub. The cart bed planks have subtle horizontal grain lines and a light "
            "shadow at the lower-right edge. The cart is exactly centred in the 64x64 tile with equal margins, "
            "fully visible, no part clipped, at least 4 px gap to every edge. Light source upper-left, earthy "
            "muted palette, no outline around the full object, only internal depth lines. Everything outside "
            "the cart silhouette is fully transparent. "
            "Color palette: cart bed highlight #C8A06A, cart bed midtone #A07840, cart bed shadow #6B4E28, "
            "wheel rim #8B6030, wheel hub #4A3018, plank grain #B89050."
        ),
        "out": "assets/ui/icons/resources/cart.png",
    },
]


def check_balance() -> None:
    req = urllib.request.Request(
        "https://api.pixellab.ai/v2/balance",
        headers={"Authorization": f"Bearer {KEY}"},
    )
    with urllib.request.urlopen(req) as resp:
        data = json.load(resp)
    print(f"Balance: {data}")


def generate(asset: dict, repo_root: Path) -> None:
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

    img_b64 = result["image"]["base64"]
    if "," in img_b64:
        img_b64 = img_b64.split(",", 1)[1]
    png_bytes = base64.b64decode(img_b64)

    out_path = repo_root / asset["out"]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(png_bytes)
    print(f"Saved {asset['out']} ({len(png_bytes)} bytes)")


if __name__ == "__main__":
    repo_root = Path(__file__).parent.parent.parent.parent
    check_balance()
    for asset in ASSETS:
        generate(asset, repo_root)
    print("Done — 4 assets generated.")
