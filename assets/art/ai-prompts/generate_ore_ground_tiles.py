"""Generate the 16-variant pit-floor ground tilesets for the six ore/gem deposits.

Uses the proven async ground-tile recipe (add-production-chain SKILL.md 3d):
  POST /v2/create-tiles-pro -> background_job_id
  GET  /v2/background-jobs/{id} until status == "completed"
  last_response.images[i].base64 is RAW RGBA8 (w*h*4 bytes), NOT a PNG -> encode via Pillow.
Saves assets/art/tiles/env_tile_<ore>_NN.png (NN = 01..16), wired into terrain_renderer.gd.

Centered overlay/UI icons are generated separately by generate_ore_deposit_assets.py (pixen).
"""
import urllib.request
import json
import base64
import time
import os
from pathlib import Path
from PIL import Image

API = "https://api.pixellab.ai/v2"


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "")
    if not key:
        key = (Path.home() / ".pixellab_key").read_text().strip()
    if not key:
        raise RuntimeError("No PixelLab API key. Set PIXELLAB_API_KEY or write to ~/.pixellab_key")
    return key


KEY = _load_key()
HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

# Per-ore ground prompt: shared template + the ore-specific detail line + inline palette.
_TEMPLATE = (
    "Exposed {name} ore pit ground seen from directly straight above (90-degree top-down view), "
    "covering the entire tile from edge to edge with no gaps and no transparency — the surface is "
    "the rocky pit floor itself, opaque in every corner. The base is broken grey-brown excavated "
    "rock. {detail} The veins and nuggets are scattered across the interior, 6 to 10 small marks "
    "each 1 to 3 pixels, distributed evenly, not clustered in one spot. Light comes from the "
    "upper-left: upper-left slightly lighter, lower-right slightly darker. All marks stay at least "
    "3 pixels from every tile edge so nothing appears cut off when tiles are placed side by side. "
    "No grass, no plants, no tools, no objects. Color palette: {palette}."
)

ORES = [
    {"id": "iron", "name": "iron",
     "detail": "Dull rusty-orange and dark-grey iron-ore veins and pitted nuggets streak the rock.",
     "palette": "highlight #8A766A, base #6E5A50, shadow #46382F, iron ore #9C6A4A"},
    {"id": "copper", "name": "copper",
     "detail": "Bright orange-bronze copper veins with greenish patina speckles run through the rock.",
     "palette": "highlight #A88A6A, base #7C6048, shadow #4E3A28, copper #C07838, patina #5FA07A"},
    {"id": "tin", "name": "tin",
     "detail": "Dull pewter-grey tin nuggets with a faint cool sheen dot the rock.",
     "palette": "highlight #9A9CA0, base #74767A, shadow #4A4C50, tin #B6B8BE"},
    {"id": "silver", "name": "silver",
     "detail": "Bright pale-silver metallic veins and glinting nuggets stand out sharply against dark rock.",
     "palette": "highlight #C8CBD2, base #8A8D94, shadow #54565C, silver #E6E8EE"},
    {"id": "gold", "name": "gold",
     "detail": "Rich warm-gold veins and bright glinting nuggets stand out against dark rock.",
     "palette": "highlight #E6C24A, base #A88A30, shadow #6E5A1E, gold #F4DC72"},
    {"id": "gemstone", "name": "gemstone",
     "detail": "Faceted teal and violet gem crystals are embedded in the rock, catching tiny bright glints.",
     "palette": "highlight #5FBFC2, base #3E8A8E, shadow #27585A, gem violet #9A6AD0, glint #DFFAFB"},
]

TILES_DIR = Path("assets/art/tiles")
POLL_SECONDS = 5
POLL_MAX = 120  # up to ~10 min per job


def _post_job(description: str) -> str:
    payload = {
        "description": description,
        "tile_type": "square_topdown",
        "tile_size": 64,
        "tile_view_angle": 90.0,
        "tile_depth_ratio": 0.0,
        "seed": 42,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API + "/create-tiles-pro", data=data, headers=HEADERS, method="POST")
    with urllib.request.urlopen(req) as resp:
        result = json.load(resp)
    job_id = result.get("background_job_id") or result.get("id")
    if not job_id:
        raise RuntimeError(f"No background_job_id in response: {json.dumps(result)[:300]}")
    return job_id


def _poll(job_id: str) -> list[dict]:
    req = urllib.request.Request(API + f"/background-jobs/{job_id}", headers=HEADERS)
    for _ in range(POLL_MAX):
        with urllib.request.urlopen(req) as resp:
            job = json.load(resp)
        status = job.get("status")
        if status == "completed":
            return job["last_response"]["images"]
        if status in ("failed", "error", "cancelled"):
            raise RuntimeError(f"Job {job_id} {status}: {json.dumps(job)[:300]}")
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"Job {job_id} did not complete after {POLL_MAX * POLL_SECONDS}s")


def _save_images(ore_id: str, images: list[dict]) -> None:
    TILES_DIR.mkdir(parents=True, exist_ok=True)
    for i, img in enumerate(images, start=1):
        w, h = int(img["width"]), int(img["height"])
        raw = base64.b64decode(img["base64"])
        if len(raw) != w * h * 4:
            raise RuntimeError(f"{ore_id} tile {i}: expected {w*h*4} RGBA bytes, got {len(raw)}")
        out = TILES_DIR / f"env_tile_{ore_id}_{i:02d}.png"
        Image.frombytes("RGBA", (w, h), raw).save(out)
    print(f"  OK {ore_id}: saved {len(images)} tiles -> {TILES_DIR}/env_tile_{ore_id}_NN.png")


def generate(ore: dict) -> None:
    desc = _TEMPLATE.format(name=ore["name"], detail=ore["detail"], palette=ore["palette"])
    print(f"  {ore['id']}: posting job...")
    job_id = _post_job(desc)
    print(f"  {ore['id']}: job {job_id}, polling...")
    images = _poll(job_id)
    _save_images(ore["id"], images)


if __name__ == "__main__":
    print(f"Generating ground tilesets for {len(ORES)} ores (square_topdown, 16 variants each)...")
    for ore in ORES:
        generate(ore)
    print("Done. Restart the Godot editor to trigger .import sidecar generation for the new tiles.")
