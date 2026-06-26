"""Generate missing assets for clay→pottery and leather chains via PixelLab API."""
import urllib.request
import json
import base64
import os
from pathlib import Path


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    if not key:
        raise RuntimeError("No PixelLab API key. Set PIXELLAB_API_KEY or write to ~/.pixellab_key")
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

ASSETS = [
    # ── Clay Pit ──────────────────────────────────────────────────────────────
    {
        "label": "Clay Pit building tile",
        "out": "assets/art/tiles/bld_tile_clay_pit.png",
        "description": (
            "Top-down RPG tile, slightly elevated view ~60-70 degrees above horizon. "
            "A small open-pit clay extraction site: a shallow rectangular excavation "
            "with exposed dark reddish-brown clay walls visible inside the pit. A simple "
            "wooden A-frame hoist with a rope bucket stands at the pit edge. Scattered "
            "lumps of wet clay beside the pit. Light source upper-left, shadows lower-right. "
            "Earthy muted palette. 2-3 shading levels per color. No outline around the whole "
            "object, only internal depth lines. Object exactly centered with 2-4 px clearance "
            "to all edges. Everything outside the pit-site silhouette is fully transparent. "
            "Color palette: clay walls #8B5E3C, clay highlight #A87050, clay shadow #5C3820, "
            "wooden frame #C8A060, rope #B08040, excavated floor #6B4028."
        ),
    },
    # ── Pottery Kiln ──────────────────────────────────────────────────────────
    {
        "label": "Pottery Kiln building tile",
        "out": "assets/art/tiles/bld_tile_pottery_kiln.png",
        "description": (
            "Top-down RPG tile, slightly elevated view ~60-70 degrees above horizon. "
            "A domed clay pottery kiln: rounded dome body made of fired clay bricks, "
            "a small arched fire-mouth opening on the front face (~3x3 px), faint orange "
            "glow visible inside. A small chimney hole at the dome top. Two finished pots "
            "stacked beside the kiln as a distinguishing detail. Light source upper-left, "
            "shadows lower-right. Earthy muted palette. 2-3 shading levels per color. "
            "No outline around the whole object, only internal depth lines. Object exactly "
            "centered with 2-4 px clearance to all edges. Everything outside the kiln "
            "silhouette is fully transparent. "
            "Color palette: dome highlight #C8905A, dome midtone #A06830, dome shadow #6B3D18, "
            "fire glow #E87830, brick mortar #8C6040, pots #B07848."
        ),
    },
    # ── Tannery ───────────────────────────────────────────────────────────────
    {
        "label": "Tannery building tile",
        "out": "assets/art/tiles/bld_tile_tannery.png",
        "description": (
            "Top-down RPG tile, slightly elevated view ~60-70 degrees above horizon. "
            "A small tannery building: wooden-walled structure with saddle roof, "
            "left side highlighted, right side in shadow. Distinguishing detail: two "
            "stretched animal hides hanging on a wooden rack in front of the building "
            "(flat stretched squares of pale tan leather on a horizontal pole). A small "
            "round tanning vat visible beside the entrance. Light source upper-left, "
            "shadows lower-right. Earthy muted palette. 2-3 shading levels per color. "
            "No outline around the whole object, only internal depth lines. Object exactly "
            "centered with 2-4 px clearance to all edges. Everything outside the building "
            "silhouette is fully transparent. "
            "Color palette: roof highlight #A08050, roof midtone #7A5A30, roof shadow #4E3818, "
            "wall #C8A070, hides #D4B880, rack pole #8C6030, vat #5C4020."
        ),
    },
    # ── Clay UI icon ──────────────────────────────────────────────────────────
    {
        "label": "Clay UI icon",
        "out": "assets/ui/icons/resources/clay.png",
        "description": (
            "Top-down RPG item icon, slightly elevated view ~60-70 degrees above horizon. "
            "A lump of raw wet clay: irregular organic shape, moist reddish-brown surface "
            "with subtle finger-mark texture. Slightly flattened on the bottom. "
            "Light source upper-left, shadow lower-right. Earthy muted palette. "
            "2-3 shading levels. No outline around the whole object, only internal depth lines. "
            "Object exactly centered with 2-4 px clearance to all edges. "
            "Everything outside the clay lump is fully transparent. "
            "Color palette: highlight #A87050, midtone #8B5E3C, shadow #5C3820."
        ),
    },
    # ── Pottery UI icon ───────────────────────────────────────────────────────
    {
        "label": "Pottery UI icon",
        "out": "assets/ui/icons/resources/pottery.png",
        "description": (
            "Top-down RPG item icon, slightly elevated view ~60-70 degrees above horizon. "
            "A finished clay pottery vessel: round-bellied pot with a narrow neck and flared rim, "
            "fired terracotta colour. Smooth surface with subtle horizontal throwing lines. "
            "Light source upper-left, shadow curves around the right side. Earthy muted palette. "
            "2-3 shading levels. No outline around the whole object, only internal depth lines. "
            "Object exactly centered with 2-4 px clearance to all edges. "
            "Everything outside the pot silhouette is fully transparent. "
            "Color palette: highlight #C87848, midtone #A05830, shadow #6B3618, rim #D49060."
        ),
    },
    # ── Hide UI icon ──────────────────────────────────────────────────────────
    {
        "label": "Hide UI icon",
        "out": "assets/ui/icons/resources/hide.png",
        "description": (
            "Top-down RPG item icon, slightly elevated view ~60-70 degrees above horizon. "
            "A raw animal hide: roughly oval/irregular flat shape representing a stretched "
            "pelt, pale tan with darker edges where it has been scraped. Slight texture "
            "suggesting fur on one side. Light source upper-left, shadow lower-right. "
            "Earthy muted palette. 2-3 shading levels. No outline around the whole object, "
            "only internal depth lines. Object exactly centered with 2-4 px clearance to "
            "all edges. Everything outside the hide shape is fully transparent. "
            "Color palette: hide highlight #D4B880, hide midtone #B09058, hide shadow #7A6038, "
            "edge scrape #8C7048."
        ),
    },
    # ── Leather UI icon ───────────────────────────────────────────────────────
    {
        "label": "Leather UI icon",
        "out": "assets/ui/icons/resources/leather.png",
        "description": (
            "Top-down RPG item icon, slightly elevated view ~60-70 degrees above horizon. "
            "A piece of processed leather: a neatly cut rectangular panel of rich brown "
            "tanned leather, slightly curled at one corner to show thickness. Smooth surface "
            "with faint grain lines. Light source upper-left, shadow lower-right. "
            "Earthy muted palette. 2-3 shading levels. No outline around the whole object, "
            "only internal depth lines. Object exactly centered with 2-4 px clearance to "
            "all edges. Everything outside the leather piece is fully transparent. "
            "Color palette: highlight #A07040, midtone #7A5028, shadow #4E3018, "
            "grain lines #5C3C20."
        ),
    },
    # ── Knife UI icon ─────────────────────────────────────────────────────────
    {
        "label": "Knife UI icon",
        "out": "assets/ui/icons/resources/knife.png",
        "description": (
            "Top-down RPG item icon, slightly elevated view ~60-70 degrees above horizon. "
            "A simple crafting knife: short single-edge blade of polished grey stone or "
            "metal, wooden handle with visible grain. Blade oriented diagonally "
            "(lower-left handle to upper-right tip) so both blade and handle are readable. "
            "Light source upper-left, highlight runs along the blade's flat top edge. "
            "Earthy muted palette. 2-3 shading levels. No outline around the whole object, "
            "only internal depth lines. Object exactly centered with 2-4 px clearance to "
            "all edges. Everything outside the knife silhouette is fully transparent. "
            "Color palette: blade highlight #D0D0C8, blade midtone #909088, "
            "blade shadow #505048, handle #A07840, handle shadow #6B4E28."
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

    out = asset["out"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(png)
    print(f"  OK {asset['label']}: {out} ({len(png)} bytes)")


if __name__ == "__main__":
    print(f"Generating {len(ASSETS)} assets...")
    for asset in ASSETS:
        generate(asset)
    print("Done. Restart Godot editor to trigger .import sidecar generation.")
