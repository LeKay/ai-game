"""Generate the NPC-city faction emblem icons via PixelLab API.

Reads the API key from PIXELLAB_API_KEY or ~/.pixellab_key — never hardcode it (the repo is public).

Usage:
    python generate_faction_icons.py                 # generate every missing emblem
    python generate_faction_icons.py ironhold        # generate only the named faction(s)
    python generate_faction_icons.py --force         # regenerate all (overwrite)
"""
import urllib.request
import json
import base64
import os
import sys
from pathlib import Path


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

_STYLE = (
    "Pixel art heraldic faction emblem icon, 64x64 pixels, fully transparent background. A single "
    "centred crest on a smooth shield shape, bold and instantly readable at small size, thick "
    "clean edges, flat 2-3 colour shading with a subtle highlight. Game UI faction badge. No text. "
    "Everything outside the shield is fully transparent."
)

# slug -> (theme description, shield/accent palette)
FACTIONS = {
    "ironhold": (
        "A forge-and-mountain faction crest: two crossed blacksmith hammers over a stylised "
        "triangular mountain peak. Iron-grey shield (#6F7479 / #4A4E52) with a crimson banner "
        "stripe (#B23A36) behind the hammers and warm steel highlights (#C9CDD2)."
    ),
    "verdant": (
        "A deep-forest faction crest: a broad oak tree with a thick trunk and a rounded canopy. "
        "Forest-green shield (#2E6B33 / #1E4A24) with the tree in lighter green (#5DA85B) and a "
        "small gold acorn accent (#D9A52E)."
    ),
    "tidewatch": (
        "A coastal seafarer faction crest: an upright trident crossing a curling ocean wave. "
        "Deep-blue shield (#274C7A / #1A3457) with silver trident and wave crest (#C7D4E2) and a "
        "pale teal highlight (#4FA6B8)."
    ),
    "goldfield": (
        "A farming-plains faction crest: a bound sheaf of wheat in front of a rising sun. "
        "Warm-gold shield (#C9962F / #9A6F1E) with bright wheat (#F0CE66) and a soft cream sun "
        "halo (#F7E9C0)."
    ),
    "ravenmoor": (
        "A marsh-and-river faction crest: a perched raven with spread wings beneath a thin "
        "crescent moon. Dark-purple shield (#3E2C57 / #281A3B) with a bone-white raven (#E6E2D6) "
        "and a cold silver crescent (#B9C4D0)."
    ),
}

OUT_DIR = "assets/ui/icons/factions"


def _generate(description: str, out_path: str) -> None:
    payload = {
        "description": f"{_STYLE} {description}",
        "image_size": {"width": 64, "height": 64},
        "view": "side",
        "detail": "highly detailed",
        "outline": "single color black outline",
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
    args = sys.argv[1:]
    force = "--force" in args
    wanted = [a for a in args if not a.startswith("--")]
    for slug, desc in FACTIONS.items():
        if wanted and slug not in wanted:
            continue
        out = f"{OUT_DIR}/{slug}.png"
        if not force and Path(out).exists():
            print(f"Skipping (exists): {out}")
            continue
        print(f"Generating: {out} ...")
        _generate(desc, out)
    print("Done.")
