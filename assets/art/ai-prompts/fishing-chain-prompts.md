# AI Asset Generation Prompts — Fishing Chain

Kette: Fiber → (Weaver) → Fishing Net → (Fishing Hut, adj. WATER) → Fish

**Globale Stil-Orientierungen (aus sprite-prompts.md):**
- Terrain-Tiles: strikt von direkt oben, nur Oberseite sichtbar
- Gebäude / Resource-Overlays: leicht erhöhter Winkel ~60–70° über dem Horizont
- Lichtquelle oben-links, Schatten nach unten-rechts
- Palette erdig und gedämpft — keine gesättigten Neonfarben
- 2–3 Schattierungsstufen pro Farbe
- Keine Gesamt-Outline — nur interne Tiefenlinien
- Gebäude: Footprint ~18–20 px breit, ~14–16 px hoch; erkennbares Betriebs-Requisit
- Resource-Overlays: Objekt zentriert, transparenter Hintergrund, ≥ 4 px Abstand zu jeder Kante

---

### 1. Fishing Hut / Fischerhütte — `bld_tile_fishing_hut.png`

Kleine Hütte direkt am Wasser gebaut; charakteristisches Requisit ist ein hängendes Fischernetz (gefaltet über eine Stange neben dem Eingang).

**Prompt:**
```
A small fishing hut seen from a slightly elevated angle (~60–70° above the horizon,
classic top-down RPG perspective), showing the roof from above and a narrow front wall
strip. The hut has a low gabled roof in weathered dark-teal shingles — roof highlight
#5C8A7A, midtone #3D6B5E, shadow #244D43. Walls are rough timber planks in a
sun-bleached warm tan — wall highlight #C4A97A, wall midtone #A08760, wall shadow
#705F44. A small door (~3×4 px) centered on the front strip. To the left of the door,
a short horizontal wooden pole leans against the wall with a draped fishing net hanging
from it — net in muted gray-blue #7A9EA8 with thin dark mesh lines. Light source
upper-left; shadows fall lower-right. Footprint approximately 18–20 px wide,
14–16 px tall. Everything outside the building silhouette is fully transparent.
No ground, no border, no fill behind the structure.
Color palette: roof highlight #5C8A7A, roof midtone #3D6B5E, roof shadow #244D43,
wall highlight #C4A97A, wall midtone #A08760, wall shadow #705F44, net #7A9EA8, door #5C3D20.
```

**Zielfarben:** Dach-Highlight `#5C8A7A` · Dach-Mitte `#3D6B5E` · Dach-Schatten `#244D43` · Wand `#A08760` · Tür `#5C3D20` · Netz `#7A9EA8`
**Hintergrund:** Transparent

---

### 2. Fishing Net / Fischernetz (UI-Icon) — `assets/ui/icons/resources/fishing_net.png`

Rundes Wurfnetz von oben gesehen, leicht gefaltet, auf transparentem Hintergrund.

**Prompt:**
```
A small circular fishing net seen from a slightly elevated top-down angle (~60–70°),
centered in the tile. The net is folded in a loose rounded shape, showing a radiating
mesh pattern from the center outward. Net cords in muted gray-blue #7A9EA8 with darker
mesh intersections #4A6E78. A few edge weights (small dark dots #3A4A50) visible around
the outer rim. Light source upper-left; the left side of the net is slightly lighter
#9BBCC8, the lower-right edge darker #4A6E78. The object is fully centered, at least
4 pixels from every edge. Everything outside the net silhouette is fully transparent.
No ground, no background, no border.
Color palette: net cord #7A9EA8, net highlight #9BBCC8, mesh shadow #4A6E78,
weights #3A4A50.
```

**Zielfarben:** Netz-Highlight `#9BBCC8` · Netz-Mitte `#7A9EA8` · Netz-Schatten `#4A6E78` · Gewichte `#3A4A50`
**Hintergrund:** Transparent

---

### 3. Fish / Fisch (UI-Icon) — `assets/ui/icons/resources/fish.png`

Einzelner Fisch von leicht oben gesehen, horizontal ausgerichtet, auf transparentem Hintergrund.

**Prompt:**
```
A single fish seen from a slightly elevated top-down angle (~60–70°), centered in the
tile, oriented horizontally with head facing left. The fish has silver-blue scales —
body highlight #A8C8D8, body midtone #7099B0, body shadow #4A6E88. The dorsal fin is
visible from above in a slightly darker blue-gray #5A7A90. The belly is lighter #C8DDE8.
A small round eye #2A2A2A on the head side. Tail fin spread slightly. Light source
upper-left; the upper-left of the body is lightest, lower-right darkest. The fish is
fully centered with at least 4 pixels clearance from every edge. Everything outside
the fish silhouette is fully transparent. No water, no ground, no border.
Color palette: body highlight #A8C8D8, body midtone #7099B0, body shadow #4A6E88,
fin #5A7A90, belly #C8DDE8, eye #2A2A2A.
```

**Zielfarben:** Körper-Highlight `#A8C8D8` · Körper-Mitte `#7099B0` · Körper-Schatten `#4A6E88` · Flosse `#5A7A90` · Bauch `#C8DDE8`
**Hintergrund:** Transparent

---

## Atlas-Assembly

Alle drei Assets sind Einzelobjekte auf transparentem Hintergrund — kein Atlas nötig.

## Nächste Schritte

1. Generierung via `assets/art/ai-prompts/generate_fishing_assets.py` (Phase 3c)
2. PNGs nach Godot-Import prüfen (Filter = Nearest, Mipmaps = Disabled)
3. `bld_tile_fishing_hut.png` → `assets/art/tiles/`
4. `fishing_net.png` + `fish.png` → `assets/ui/icons/resources/`
5. Im Editor gegen Art Bible prüfen (Palette, Perspektive, Transparenz)
6. Bei Stil-Abweichung: erneute Generierung mit präzisierterer description
