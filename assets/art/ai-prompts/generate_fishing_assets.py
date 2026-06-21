"""Generate fishing chain assets via PixelLab API (pixen endpoint, 64x64)."""
import urllib.request, json, base64, os
from pathlib import Path

def _load_key():
    key = os.environ.get('PIXELLAB_API_KEY', '')
    if not key:
        key = (Path.home() / '.pixellab_key').read_text().strip()
    return key

KEY = _load_key()
HEADERS = {'Authorization': f'Bearer {KEY}', 'Content-Type': 'application/json'}

ASSETS = [
    {
        'description': (
            'A small fishing hut seen from a slightly elevated angle (~60-70 degrees above '
            'the horizon, classic top-down RPG perspective), showing the roof from above and '
            'a narrow front wall strip. The hut has a low gabled roof in weathered dark-teal '
            'shingles. Walls are rough timber planks in a sun-bleached warm tan. A small door '
            'centered on the front strip. To the left of the door, a short horizontal wooden '
            'pole leans against the wall with a draped fishing net hanging from it in muted '
            'gray-blue with thin dark mesh lines. Light source upper-left; shadows fall '
            'lower-right. Footprint approximately 18-20 px wide, 14-16 px tall. Everything '
            'outside the building silhouette is fully transparent. No ground, no border. '
            'Color palette: roof highlight #5C8A7A, roof midtone #3D6B5E, roof shadow #244D43, '
            'wall highlight #C4A97A, wall midtone #A08760, wall shadow #705F44, net #7A9EA8, door #5C3D20.'
        ),
        'out': 'assets/art/tiles/bld_tile_fishing_hut.png',
        'label': 'Fishing Hut tile',
    },
    {
        'description': (
            'A small circular fishing net seen from a slightly elevated top-down angle (~60-70 '
            'degrees), centered in the tile. The net is folded in a loose rounded shape, showing '
            'a radiating mesh pattern from the center outward. Net cords in muted gray-blue with '
            'darker mesh intersections. A few small edge weights visible around the outer rim. '
            'Light source upper-left. The object is fully centered, at least 4 pixels from every '
            'edge. Everything outside the net silhouette is fully transparent. No ground, no '
            'background, no border. '
            'Color palette: net cord #7A9EA8, net highlight #9BBCC8, mesh shadow #4A6E78, weights #3A4A50.'
        ),
        'out': 'assets/ui/icons/resources/fishing_net.png',
        'label': 'Fishing Net UI icon',
    },
    {
        'description': (
            'A single fish seen from a slightly elevated top-down angle (~60-70 degrees), '
            'centered in the tile, oriented horizontally with head facing left. The fish has '
            'silver-blue scales. The dorsal fin is visible from above in a slightly darker '
            'blue-gray. The belly is lighter. A small round dark eye on the head side. Tail '
            'fin spread slightly. Light source upper-left; the upper-left of the body is '
            'lightest, lower-right darkest. The fish is fully centered with at least 4 pixels '
            'clearance from every edge. Everything outside the fish silhouette is fully '
            'transparent. No water, no ground, no border. '
            'Color palette: body highlight #A8C8D8, body midtone #7099B0, body shadow #4A6E88, '
            'fin #5A7A90, belly #C8DDE8, eye #2A2A2A.'
        ),
        'out': 'assets/ui/icons/resources/fish.png',
        'label': 'Fish UI icon',
    },
]

BASE_DIR = Path(__file__).parent.parent.parent.parent

for asset in ASSETS:
    print(f"Generating: {asset['label']} ...")
    payload = {
        'description': asset['description'],
        'image_size': {'width': 64, 'height': 64},
        'view': 'high top-down',
        'detail': 'highly detailed',
        'outline': 'lineless',
        'no_background': True,
    }
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        'https://api.pixellab.ai/v2/create-image-pixen',
        data=data, headers=HEADERS, method='POST',
    )
    with urllib.request.urlopen(req) as resp:
        d = json.load(resp)
    img = d['image']['base64']
    if ',' in img:
        img = img.split(',', 1)[1]
    png = base64.b64decode(img)
    out_path = BASE_DIR / asset['out']
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(png)
    print(f"  Saved {len(png)} bytes -> {asset['out']}")

print("Done.")
