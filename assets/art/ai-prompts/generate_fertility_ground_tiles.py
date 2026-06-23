"""Generate the 16-variant opaque ground tilesets for the opaque second-wave fertilities.

Covers the field crops (flax / hops / grapes) and the beach sand — the fertilities that fill
the whole tile with no transparency (wheat-like). The transparent overlay fertilities
(olive / bees / marble / amber / pearl) are NOT generated here: their terrain sprites need a
transparent background and are produced like the tree/stone overlays; their centered world/UI
icons come from generate_fertility_assets.py.

Uses the proven async ground-tile recipe (same as generate_ore_ground_tiles.py):
  POST /v2/create-tiles-pro -> background_job_id
  GET  /v2/background-jobs/{id} until status == "completed"
  last_response.images[i].base64 is RAW RGBA8 (w*h*4 bytes), NOT a PNG -> encode via Pillow.
Saves assets/art/tiles/env_tile_<id>_NN.png (NN = 01..16), wired into terrain_renderer.gd.
Until they exist the game falls back to _TERRAIN_FALLBACK_COLORS.
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

# Shared template: opaque, edge-to-edge, top-down, light from upper-left. {detail} + {palette}
# carry the per-crop specifics.
_TEMPLATE = (
    "Top-down view seen from directly straight above (90-degree angle) of {name}, covering the "
    "entire tile from edge to edge with no gaps and no transparency — the surface is opaque in "
    "every corner. {detail} The pattern fills the whole tile evenly and tiles seamlessly when "
    "placed side by side, with detail kept at least 2 pixels from every edge so nothing reads as "
    "cut off. Light comes from the upper-left: upper-left slightly lighter, lower-right slightly "
    "darker. No tools, no objects, no people. Color palette: {palette}."
)

CROPS = [
    {"id": "flax", "name": "a tended flax field in bloom",
     "detail": "Neat rows of slender green flax stalks topped with tiny pale blue flowers grow on "
               "brown tilled soil.",
     "palette": "soil #6E5A42, stalk green #5E7E3A, leaf highlight #7E9E50, flax bloom #8FB2D8"},
    {"id": "hops", "name": "a hop garden of climbing bines",
     "detail": "Tall yellow-green hop bines climb support strings in rows, hung with pale green "
               "papery hop cones, over brown soil.",
     "palette": "soil #6E5A42, bine green #7C9A3C, cone #C6D88A, shadow #4E6428"},
    {"id": "grapes", "name": "a vineyard of grape vines",
     "detail": "Rows of leafy grape vines on low trellises carry clusters of deep purple grapes "
               "over brown soil.",
     "palette": "soil #6E5A42, vine leaf #4E7A38, grape purple #6B2A6B, grape highlight #9A5AA0"},
    {"id": "sand", "name": "fine pale beach sand",
     "detail": "Smooth fine-grained pale golden beach sand with subtle ripple lines and a few tiny "
               "scattered pebbles and shell flecks.",
     "palette": "sand base #E6D8A8, sand highlight #F2E8C2, sand shadow #C8B884, pebble #B0A074"},
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


def _save_images(crop_id: str, images: list[dict]) -> None:
    TILES_DIR.mkdir(parents=True, exist_ok=True)
    for i, img in enumerate(images, start=1):
        w, h = int(img["width"]), int(img["height"])
        raw = base64.b64decode(img["base64"])
        if len(raw) != w * h * 4:
            raise RuntimeError(f"{crop_id} tile {i}: expected {w*h*4} RGBA bytes, got {len(raw)}")
        out = TILES_DIR / f"env_tile_{crop_id}_{i:02d}.png"
        Image.frombytes("RGBA", (w, h), raw).save(out)
    print(f"  OK {crop_id}: saved {len(images)} tiles -> {TILES_DIR}/env_tile_{crop_id}_NN.png")


def generate(crop: dict) -> None:
    desc = _TEMPLATE.format(name=crop["name"], detail=crop["detail"], palette=crop["palette"])
    print(f"  {crop['id']}: posting job...")
    job_id = _post_job(desc)
    print(f"  {crop['id']}: job {job_id}, polling...")
    images = _poll(job_id)
    _save_images(crop["id"], images)


if __name__ == "__main__":
    import sys
    only = set(sys.argv[1:]) or None  # pass ids to regenerate a subset, e.g. `... flax sand`
    crops = [c for c in CROPS if not only or c["id"] in only]
    print(f"Generating ground tilesets for {len(crops)} fertilities (square_topdown, 16 variants each)...")
    for crop in crops:
        generate(crop)
    print("Done. Restart the Godot editor to trigger .import sidecar generation for the new tiles.")
