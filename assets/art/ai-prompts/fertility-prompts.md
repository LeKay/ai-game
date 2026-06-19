# AI Asset Generation Prompts — Map Fertility System

Prompts für Pixellab. Pixellab übernimmt Pixel-Art-Stil, Auflösung und Perspektive.
Referenz: Art Bible `design/art/art-bible.md`, Basis-Regeln in `sprite-prompts.md`.
Spec: `design/quick-specs/map-fertility-system-2026-06-18.md`.

**Es gelten alle Perspektiv-, Konsistenz- und Kompositions-Regeln aus `sprite-prompts.md`:**
- Resource-Overlay-Tiles: leicht isometrisch (~60–70°), Objekt zentriert, transparenter
  Hintergrund, mindestens 4 px Abstand zu jeder Kante, kein Teil abgeschnitten.
- Building-Tiles: leicht isometrisch (~60–70°), Dach von oben + schmaler Frontstreifen,
  Footprint ~18–20×14–16 px, transparenter Hintergrund.
- Lichtquelle oben-links (Schatten nach unten-rechts), erdige gedämpfte Palette,
  2–3 Schattierungsstufen, keine Umrandung um das ganze Tile.

**Generierungs-Endpoint je Asset-Typ:**
- **Boden-/Terrain-Tiles** (randlos, kachelbar — Lehmgrube, Weizenfeld): **Tileset-Endpoint**
  `POST https://api.pixellab.ai/v2/create-tileset` (async, Job + Poll). Echte API-Felder:
  `tile_size {64,64}`, `view "high top-down"`, `detail "highly detailed"`, `lower_description`
  == `upper_description` (= flache Varianten, kein Höhenübergang), `outline` default,
  Farben via `color_palette`. Web-UI-Labels „tiletype square / thickness 0 % / view angle 90°"
  bilden sich hierauf ab. Response liefert **16 Tiles** (`tileset.tiles[i].image.base64`), die
  **alle** als `env_tile_<type>_NN.png` gespeichert und in `terrain_renderer.gd` →
  `_TERRAIN_PNG_VARIANTS` eingebunden werden — genau wie Tree/Berry/Grass je 16 Varianten.
  Details + Feld-Verifikation: `add-production-chain` Skill §3d.
- **Zentrierte Einzel-Assets** (Resource-Overlays, UI-Icons, Marker, Gebäude): pixen-Endpoint
  `create-image-pixen`, transparenter Hintergrund (Details siehe `add-production-chain` Skill 3c/3d).

---

## Boden-/Terrain-Tiles (Tileset-Endpoint, Varianten)

Randlose, kachelbare Boden-Tiles — strikt von direkt oben (view angle 90°), opak bis in jede
Ecke. **Alle vom Endpoint gelieferten Varianten** als `env_tile_<type>_NN.png` ablegen und in
`src/scenes/map_root/terrain_renderer.gd` → `_TERRAIN_PNG_VARIANTS[<TileType>]` eintragen.

### T1. Lehmgrube / Clay Pit — `env_tile_clay_NN.png`

Aufgedeckte Lehmgrube als Boden. Feuchter, rot-oranger erdiger Untergrund — klar von Sand
(EMPTY, warm-tan) und Stein (grau) unterscheidbar. Füllt den Tile lückenlos.

**Prompt:**
```
Exposed wet clay pit ground seen from directly straight above (90-degree top-down view),
covering the entire tile from edge to edge with no gaps and no transparency — the surface is
the ground itself, opaque in every corner. The base is a warm reddish-orange earthen clay,
distinctly redder and damper-looking than dry tan sand and not gray like stone. Across the
interior, subtle dug-out depressions and trowel scrapes give a worked, slightly uneven
surface: 4 to 6 short curved gouge marks and a few small flat puddle-sheen spots in a
slightly lighter tone, suggesting moist clay. A few tiny darker clay clods, each 1 to 2
pixels, are scattered around. All marks stay at least 3 pixels from every tile edge so
nothing appears cut off when tiles are placed side by side, and no crack or line runs exactly
parallel to or ends on an edge. Light comes from the upper-left: the upper-left of the tile
is slightly lighter, the lower-right slightly darker. No grass, no rocks, no objects.
```

**Zielfarben:** Highlight `#C88A5A` · Basis `#A86438` · Schatten `#6E3C20` · Sheen `#E0A878`
**Hintergrund:** Opak (randloses Boden-Tile)

### T2. Weizenfeld / Wheat Field — `env_tile_wheat_NN.png`

Reifes Weizenfeld als Boden. Dichtes goldenes Ährenmeer — klar von hohem Gras (grün, GRASS)
unterscheidbar. Füllt den Tile lückenlos.

**Prompt:**
```
A ripe golden wheat field seen from directly straight above (90-degree top-down view),
covering the entire tile from edge to edge with no gaps and no transparency — the surface is
the field itself, opaque in every corner. The base is a dense mass of golden-amber wheat,
clearly grain rather than green grass. Across the tile, many short clustered wheat-ear marks
read as a packed field of grain heads: 16 to 22 small oval ear-head marks, each 2 to 3 pixels,
in slightly varying golden tones, distributed evenly across the interior, not clustered in one
spot. The brighter golden heads catch the overhead light from the upper-left; mid-amber and
darker amber heads fill the rest, with the lower-right of the tile slightly darker for shadow.
All ear marks stay at least 3 pixels from every tile edge so none appear cut off when tiles
are placed side by side. No bare dirt patches, no single tall stalks standing apart, no objects.
```

**Zielfarben:** Ähren-Highlight `#F0D060` · Basis `#D4A838` · Schatten `#9A7420` · Tiefe `#7A5A18`
**Hintergrund:** Opak (randloses Boden-Tile)

---

## Resource-Overlay-Tiles (transparenter Hintergrund)

### 1. Lehm / Clay — `env_tile_resource_clay.png`

Ein freigelegter Lehmbrocken / kleine Lehmgrube. Soll klar von Stein (grau) und Holz
(braun-rund) unterscheidbar sein — warmer rot-oranger Ton, erdig und feucht wirkend.

**Prompt:**
```
A single mound of raw clay perfectly centered in the tile with equal empty space on all
four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the
horizon, like a classic top-down RPG perspective. The clay does not touch any edge of the
tile and the entire mound is fully visible — nothing is cut off. Because of the slight
angle you can see both the top surface of the mound and a narrow strip of its front face,
giving it clear visible height and mass. The shape is a soft, rounded, slightly lumpy
heap — smoother and wetter-looking than a hard angular rock, with no sharp facets. The
color is a warm reddish-orange earthen brown, distinctly different from gray stone. The
top surface and upper-left catch the overhead light and are the lightest warm tone. The
front-facing strip at the bottom is in shadow and is the darkest reddish-brown. The middle
tone fills most of the mound. Two or three short curved scrape or trowel marks are pressed
into the top surface, suggesting moist worked clay, staying well within the outline. One
or two tiny lighter specks suggest a damp sheen on the upper-left. Everything outside the
clay mound is fully transparent.
```

**Zielfarben:** Highlight `#C88A5A` · Basis `#A86438` · Schatten `#6E3C20` · Sheen `#E0A878`
**Hintergrund:** Transparent

---

### 2. Weizen / Wheat — `env_tile_resource_wheat.png`

Ein kleines Büschel reifer Weizenähren. Klar unterscheidbar von Faser (gelb-grün, dünn)
und hohem Gras — golden, mit deutlich erkennbaren Ähren-Köpfen oben.

**Prompt:**
```
A small cluster of ripe wheat stalks perfectly centered in the tile with equal empty space
on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above
the horizon, like a classic top-down RPG perspective. The entire cluster is fully visible —
no stalk tip or base reaches the edge of the tile. Because of the slight angle the stalks
have clear visible height and stand upright. The cluster has 5 to 7 thin straight stems
rising from a narrow base, fanning out very slightly toward the top. The lower stems are a
warm tan-gold. Each stem is topped with a plump elongated wheat ear head, 3 to 4 pixels
long, clearly bushier and rounder than a plain seed tip — a recognizable golden grain head
with tiny lateral awns suggested by 1-pixel marks. The ear heads are the brightest golden
yellow, catching the overhead light from the upper-left on their upper sides. The lower
stems near the base are in shadow and are the darkest amber tone. No bind point, no leaves
at the base, no ground. Everything outside the wheat is fully transparent.
```

**Zielfarben:** Ähren-Highlight `#F0D060` · Ähren-Mitte `#D4A838` · Stängel `#B88A30` · Basis-Schatten `#7A5A18`
**Hintergrund:** Transparent

---

### 3. Weizensamen / Wheat Seed — `env_tile_resource_wheat_seed.png`

Kleines Häufchen Weizenkörner / Saatgut. Gleiche Logik wie die anderen Samen-Overlays,
aber golden statt grün — passend zum Weizen-Tile.

**Prompt:**
```
A small loose pile of wheat grain seeds perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees
above the horizon, like a classic top-down RPG perspective. The entire pile is fully
visible and does not touch any edge of the tile. The pile is a small low heap of 7 to 10
individual grain kernels resting together on the ground. Each kernel is a tiny oval 2 to
3 pixels long, golden tan, with a single fine darker groove line down its length. The
kernels on the top and upper-left of the pile catch the overhead light and are the
lightest golden tone. The kernels toward the lower-right and the base are in shadow and
are the darkest amber-brown. One or two kernels sit slightly apart from the main heap as
if freshly scattered. No husk, no stems, no ground texture. Everything outside the seed
pile is fully transparent.
```

**Zielfarben:** Korn-Highlight `#E8C870` · Korn-Mitte `#C89A48` · Schatten `#8A6628` · Rille `#6A4E1C`
**Hintergrund:** Transparent

---

### 4. Fleisch / Meat — `assets/ui/icons/resources/meat.png`

<!-- v2 — 2026-06-19: `game` → generische `meat`-Ressource umbenannt; UI-Icon generiert (vorher Fallback-Kreis). -->

UI-/Inventar-Icon für die Ausgabe der Jagdhütte (`meat`). Ein rohes Fleischstück mit
Knochen. Klar als Nahrung erkennbar, deutlich von Beere/Brot unterscheidbar.

**Prompt (verwendet):**
```
Pixel art icon of a raw cut of red meat, top-down RPG inventory style, 64x64, seen from
~60-70 degrees above horizon. A single fresh chunk of red meat with marbled fat texture and
a small white bone protruding from one end, like a classic raw meat or ham item in RPGs.
NOT a cooked steak on a plate, no plate, no garnish, no flames, no fork. Centered, occupies
70-80% of the tile, ~4px margin on all sides. Similar to classic RPG meat icons in Stardew
Valley or Minecraft. Color palette: deep red #9e3b2e, pink-red #c75b4a, fat marbling cream
#e8d4b0, bone white #f2ead6, dark shadow #5a1f18.
```

**Zielfarben:** Fleisch-Tief `#9E3B2E` · Fleisch-Pink `#C75B4A` · Marmorierung `#E8D4B0` · Knochen `#F2EAD6` · Schatten `#5A1F18`
**Hintergrund:** Transparent

---

### 4b. Tierhaut / Hide — `env_tile_resource_hide.png`

Item-Icon für die zweite Ausgabe der Jagdhütte (Inventar / Karten-Badge). Eine zusammen-
gerollte oder ausgebreitete rohe Tierhaut. Klar von Stoff (Cloth, glatt-textil) und Fleisch
unterscheidbar — ledrig-braun, mit Fell-Andeutung am Rand.

**Prompt:**
```
A single raw animal hide perfectly centered in the tile with equal empty space on all four
sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the horizon,
like a classic top-down RPG perspective. The entire hide is fully visible and does not
touch any edge of the tile. The hide is a flat irregular pelt laid out roughly square with
soft rounded, slightly ragged edges — clearly an animal skin, not a folded cloth. The inner
surface is a warm leathery tan-brown. The top surface and upper-left catch the overhead
light and are the lightest tan; the lower-right is in shadow and is the darkest brown. A
narrow strip of short fluffy fur is suggested along two of the ragged outer edges in a
slightly darker brown with tiny 1-pixel tufts. Two or three faint curved tone variations
across the surface suggest the natural grain and folds of the skin. No frame, no stitching,
no ground. Everything outside the hide is fully transparent.
```

**Zielfarben:** Haut-Highlight `#B8946A` · Haut-Mitte `#8A6440` · Schatten `#5A3E22` · Fell-Rand `#4A3018`
**Hintergrund:** Transparent

---

## Marker-Icon (transparenter Hintergrund)

### 5. Wild-Marker / Deer Marker — `ui_icon_wild_deer.png`

Kleines Hirsch-Symbol, das in der **Ecke** von Tiles mit einer Wildgruppe angezeigt wird
(Wald-Markierung). Klein, hoher Kontrast, auf einen Blick als Hirsch lesbar — wird im Code
klein in die Tile-Ecke gezeichnet, daher silhouettenhaft und nicht detailverliebt.

**Prompt:**
```
A single small deer head silhouette icon perfectly centered with equal empty space on all
four sides, designed to read clearly at very small size in a corner badge. The icon is a
compact front-facing deer head and neck: a rounded muzzle below, a head, two upright ears
angling outward, and a pair of branching antlers rising and spreading above the head with
2 to 3 simple tines on each side. The whole shape is a clean high-contrast silhouette in a
warm mid-brown, with a single lighter highlight tone along the upper-left edges of the
antlers and head where the overhead light hits, and a darker shadow tone on the lower-right.
The antlers are clearly readable as antlers even at tiny size — bold simple branches, not
thin fragile lines. No body, no background scenery, no circular frame. Everything outside
the deer head is fully transparent.
```

**Zielfarben:** Highlight `#9A7A4E` · Basis `#6E5226` · Schatten `#3E2C14`
**Hintergrund:** Transparent (Eck-Badge wird im Code positioniert)

---

## Buildings (transparenter Hintergrund)

### 6. Jagdhütte / Hunting Lodge — `bld_tile_hunting_lodge.png`

Kleine rustikale Jägerhütte. Gleiche Bauweise wie die anderen Holzgebäude, aber durch ein
aufgehängtes Geweih über der Tür und einen Trockenständer mit Fleisch/Fell als Betriebs-
hinweis klar als Jagdgebäude erkennbar. Soll neben einem Wald stehen.

**Prompt:**
```
A small rustic wooden hunter's lodge perfectly centered in the tile with equal empty space
on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the
horizon, like a classic top-down RPG perspective. The entire building is fully visible — no
part touches or crosses any edge of the tile. Because of the slight angle you can see both
the sloped roof from above and a narrow strip of the front wall, giving the building clear
visible height and mass.

The lodge has log walls built from stacked horizontal round logs, each log 2 pixels tall
with a dark gap line between them, in warm mid brown. The building footprint is roughly
square, 18 to 20 pixels wide and 14 to 16 pixels tall on the tile. The roof is a shallow
pitched gable roof running left to right, covered in rough wooden shingles — short
horizontal rows parallel to the ridge. The ridge sits at the center top. The left slope
catches the overhead light from the upper-left and is the lightest warm brown; the right
slope is in shadow and is the darkest brown. A narrow front wall strip of log texture is
visible below the roof edge with a small dark rectangular door opening (3×4 pixels) centered
on the front face.

Mounted on the front wall just above the door: a small pair of antlers — a 4 to 5 pixel wide
trophy mark in pale bone tan, two simple branching shapes spreading left and right, clearly
readable as mounted antlers.

To the right side of the lodge, flush against the right wall: a small drying rack — two thin
vertical post marks (1 pixel each) with a horizontal top bar, 5 to 6 pixels wide. Draped
over it hangs a single small dark red-brown strip of meat or a hide, 2 to 3 pixels tall,
lightest along the top fold and darker at the hanging lower edge.

Everything outside the building, antlers, and drying rack is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand-Log `#7A6048` · Wand-Fuge `#3E2C1E` · Tür `#2A1E14` · Geweih `#D8CBA8` · Trockenfleisch `#7A3A2A`
**Hintergrund:** Transparent

---

## Datei-Ziele (Code-Referenzen)

| Asset | Pfad | Endpoint | Referenziert in |
|-------|------|----------|-----------------|
| **Clay pit (Boden)** | `assets/art/tiles/env_tile_clay_NN.png` (Varianten) | **tileset** | `terrain_renderer.gd` → `_TERRAIN_PNG_VARIANTS[CLAY]` |
| **Wheat field (Boden)** | `assets/art/tiles/env_tile_wheat_NN.png` (Varianten) | **tileset** | `terrain_renderer.gd` → `_TERRAIN_PNG_VARIANTS[WHEAT]` |
| Clay node (overlay) | `assets/art/tiles/env_tile_resource_clay.png` | pixen | `data/resources.json` → `clay.world_icon_path` |
| Wheat crop (overlay) | `assets/art/tiles/env_tile_resource_wheat.png` | pixen | `data/resources.json` → `wheat.world_icon_path` |
| Wheat seed | `assets/art/tiles/env_tile_resource_wheat_seed.png` | pixen | `data/resources.json` → `wheat_seed.world_icon_path` |
| Meat | `assets/ui/icons/resources/meat.png` | pixen | `data/resources.json` → `meat.icon_path` (inventory/badge icon) |
| Hide | `assets/art/tiles/env_tile_resource_hide.png` | pixen | `data/resources.json` → `hide.world_icon_path` |
| Deer marker | `assets/art/tiles/ui_icon_wild_deer.png` | pixen | WildSystem deer overlay (corner badge) |
| Hunting lodge | `assets/art/tiles/bld_tile_hunting_lodge.png` | pixen | `BuildingRegistry.BUILDING_TEXTURES[HUNTING_LODGE]` |

> **Hinweis:** Die `icon_path`-Einträge unter `assets/ui/icons/resources/` werden — wie die
> bestehenden Ressourcen — aktuell nicht real geliefert (bekannter Pre-Existing-Bug); die
> Welt-/Badge-Darstellung nutzt `world_icon_path` bzw. `fallback_color`/`glyph`.

---

*Erstellt: 2026-06-18 | Referenz: Art Bible, `sprite-prompts.md` | Stand: Map Fertility System (Step 1)*
