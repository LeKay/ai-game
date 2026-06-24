# AI Asset Generation Prompts — "From Scratch"

Prompts für Pixellab. Pixellab übernimmt Pixel-Art-Stil, Auflösung und Perspektive.
Referenz: Art Bible `design/art/art-bible.md`.

**Perspektive (gilt für alle Tiles):**
- Strikt von direkt oben gesehen — die Kamera schaut senkrecht nach unten auf den Boden
- Es ist ausschließlich die Oberseite von Objekten sichtbar — keine Seitenflächen, keine Frontansicht
- Objekte auf dem Boden (Steine, Büsche, Baumkronen) zeigen nur ihre flache Draufsicht
- Tiefe wird ausschließlich durch Schattierung auf der Oberseite angedeutet, nicht durch sichtbare Seitenansichten
- Schatten fallen flach auf den Boden, leicht nach unten-rechts versetzt

**Konsistenz-Regeln für alle Tiles:**
- Lichtquelle kommt von oben-links (Schatten fallen nach unten-rechts)
- Palette: erdig und gedämpft — keine gesättigten Neonfarben
- 2–3 Schattierungsstufen pro Farbe (Highlight, Midtone, Shadow)
- Keine Outlines um den gesamten Tile — nur interne Tiefenlinien

**Kompositions-Regeln für Terrain-Tiles:**
- Die Grundfläche (Erde, Gras, Stein) füllt den gesamten Tile lückenlos von Kante zu Kante — keine Transparenz
- Dekorative Einzelelemente (Kieselsteine, Grashalme, Risse) enden mindestens 3 Pixel vor jeder Kante — kein Element berührt den Rand oder wird abgeschnitten, damit beim Kacheln mehrerer Tiles keine halbiert wirkenden Objekte an den Nähten entstehen
- Risse und Linien, die über den Tile laufen, verlaufen so, dass sie weder exakt parallel zu einer Kante noch direkt an einer Kante enden
- Die Tile-Fläche ist komplett opak — kein einziges transparentes Pixel

**Kompositions-Regeln für Resource-Overlay-Tiles:**
- Das Objekt ist exakt in der Mitte des Tiles zentriert — gleicher Abstand zu allen vier Kanten
- Das gesamte Objekt ist vollständig sichtbar — kein Teil wird abgeschnitten
- Das Objekt berührt keine der vier Kanten, mindestens 4 Pixel Abstand zu jeder Seite
- Kein zweites Objekt, kein Boden, kein Rahmen — nur das eine Objekt auf transparentem Hintergrund

---

## Terrain-Tiles

Atlas-Ziel: `assets/art/terrain/atlas_terrain.png`
Tile-Reihenfolge: `[EMPTY][TREE][STONE][BERRY][GRASS][IMPASSABLE]`

---

### 1. Empty / Gras — `env_tile_empty.png`

Helles Wiesengras. Standard-Untergrund, passend zur Baumkrone. Füllt den gesamten Tile lückenlos.

**Prompt:**
```
Lush meadow grass ground seen from directly above, covering the entire tile from edge
to edge with no gaps. The surface is the flat ground itself — fully green all the way
to every corner, not a patch on a background.

The base is a solid field of mid meadow green. On top of this base, small individual
grass blade marks are scattered across the tile interior: 10 to 14 tiny marks, each
1 pixel wide and 2 to 4 pixels tall, seen from above as short upright strokes in
slightly varying directions. The marks are distributed evenly across the tile — not
clustered in one area. All marks sit at least 3 pixels away from every tile edge so
none appear cut off when tiles are placed next to each other.

Roughly one third of the marks use a lighter green tone, suggesting tips of blades
catching the overhead light from the upper-left. Roughly one third use the base tone.
The remaining third, placed more toward the lower-right of the tile, use a slightly
darker green tone for shadow. The transitions between light and shadow zones are
gradual, not sharp. No flowers, no dirt patches, no pebbles, no bare ground visible.
```

**Zielfarben:** Highlight `#7AAE5C` · Basis `#5C8A4D` · Schatten `#3A6030`

---

### 1b. Wasser / Water — `env_tile_water.png` *(Assets vorhanden: env_tile_water_01–16.png)*

Dunkles Flusswasser. Generiert via `create-tiles-pro` (16 Variationen in einem Call).

<!-- v1 — 2026-06-21: Erstgenerierung Wasser-Terrain-Tiles -->

**Prompt (description-Feld für create-tiles-pro):**
```
Pixel art water terrain tiles for a top-down RPG game, seen from directly above. Each tile is deep muted river water covering the entire tile from edge to edge with no gaps, no transparency, opaque in every corner. Light source upper-left, earthy muted palette, 2-3 shading tones per color, no outline around the tile. Color palette: deep shadow #1A4D7A, mid blue #2E73B3, ripple highlight #6AAAD9, bright glint #A8D0F0.

1) Calm still water — 4 subtle horizontal ripple arcs scattered across the interior, faint glint upper-left
2) Calm still water — 5 ripple arcs leaning slightly diagonal top-right to bottom-left, glint near center
3) Gentle current — 6 short curved ripple marks flowing left to right, two bright glints upper-left area
4) Gentle current — 5 ripple marks flowing upper-left to lower-right, darker shadow patch lower-right corner area
5) Slight surface disturbance — small circular ripple ring near upper-center, 3 short arcs nearby
6) Slight surface disturbance — small circular ripple ring near lower-center, 4 short arcs scattered around it
7) Deep still water — only 2 very faint ripple marks, surface mostly dark and smooth, single glint upper-left
8) Deep still water — 3 faint marks near center, dark blue dominates, subtle shadow gradient lower-right
9) Active surface — 8 small ripple arcs densely scattered across tile interior, multiple glints
10) Active surface — 7 ripple arcs in two loose clusters left and right of center
11) Moving water with flow lines — 4 thin parallel arcs running left-to-right suggesting gentle current
12) Moving water with flow lines — 4 thin parallel arcs running diagonally upper-left to lower-right
13) Calm water with tiny foam cluster — 3 ripple arcs plus a small 3-pixel cluster of white foam dots near center
14) Calm water with tiny foam cluster — 4 ripple arcs plus small foam dot cluster offset toward upper-right
15) Light-catching surface — 5 ripple arcs, 4 bright glint marks scattered, light blue tone dominant
16) Shadow-pooled water — 5 ripple arcs, large dark shadow area occupying lower-right third, deep blue dominant
```

**Parameter:** `tile_type: square_topdown` · `tile_size: 64`
**Zielfarben:** Tief `#1A4D7A` · Basis `#2E73B3` · Ripple `#6AAAD9` · Glint `#A8D0F0`

---

### 1c. Sand / Boden — `env_tile_sand.png` *(Assets vorhanden: env_tile_sand_01–16.png)*

Warmer, sandiger Erdboden. Bereits generiert und gesplittet — Prompt zur Referenz.

**Prompt:**
```
Sandy dirt ground seen from directly above, covering the entire tile from edge to edge
with no gaps. The surface is a continuous flat expanse — the ground itself, not a patch
on a background. The base color is warm tan, the color of dry clay. Scattered across the
interior of the tile are 5 to 7 tiny pebbles seen from directly above — each pebble is
only 1 to 2 pixels across, appearing as small flat dots or very short ovals because of
the strict top-down view. No pebble is larger than 2 pixels in any direction. The pebbles
vary slightly in tone: some in the lighter highlight color, some in the darker shadow color.
All pebbles sit at least 3 pixels away from every edge of the tile so none are cut off.
The dirt between the pebbles has subtle tonal variation: slightly lighter near the
upper-left, slightly darker near the lower-right. No grass, no cracks.
```

**Zielfarben:** Basis `#C0AE8C` · Pebble-Highlight `#DDD0B8` · Pebble-Schatten `#9A8A6C`

---

### 2. Tree / Baum — `env_tile_tree.png`

2–3 Bäume von oben, erkennbare Kronen mit Stamm-Andeutung. Grasuntergrund.

**Prompt:**
```
Two or three deciduous trees seen from directly above, standing on a meadow grass ground
that fills the entire tile from edge to edge. The grass background is the same light
meadow green as the Grass tile — it covers every corner of the tile completely.

Each tree consists of a round canopy top and a tiny dark trunk stub visible just below
the canopy edge where the trunk meets the ground. The canopies are organic and irregular
— lumpy silhouettes with 5 to 8 small leaf-cluster bumps around the edge, clearly
recognizable as tree crowns, not plain circles. One tree is larger and positioned
slightly left of center. The other one or two trees are smaller and placed to the right
and slightly behind, partially overlapping or touching the large tree.

Each canopy top surface: the upper-left quarter is the lightest green, directly lit by
overhead light. The lower-right quarter is the darkest green, in deep shadow. The middle
tone covers the rest. The canopy colors are deep forest green with clear tonal variation
so they read as three-dimensional rounded masses, not flat discs. Each trunk stub is a
1 to 2 pixel wide dark brown vertical mark just visible beneath the canopy shadow edge.

All tree elements sit at least 2 pixels away from every tile edge so nothing is cut off.
The grass ground is fully visible between and around the trees.
```

**Zielfarben:** Schatten `#0D3A16` · Mitte `#1A612A` · Highlight `#2E8040` · Stamm `#3E2C1E`
**Hintergrund:** `#5C8A4D` (Gras — identisch mit Grass-Tile)

---

### 3. Stone / Felsblöcke — `env_tile_stone.png`

2–3 Felsblöcke von oben auf transparentem Hintergrund. Gras sieht durch die freien Flächen hindurch durch (BackgroundLayer).

**Prompt:**
```
Two or three large rock formations seen from directly above, filling most of the tile
the same way tree canopies fill the tree tile — the rocks are massive and dominant,
not small pebbles. The background is fully transparent — every pixel outside the rocks
must be transparent, with no white fill, no gray fill, no ground color of any kind.
Only the rock surfaces themselves are opaque.

The main rock formation is large and roughly centered, occupying roughly half the tile
area on its own. One or two smaller rock masses sit close beside it, slightly overlapping
or touching the main rock. Together the rocks fill about two thirds to three quarters of
the tile, similar to how tree canopies dominate their tile. The rocks are irregular and
angular — chunky flat-topped formations with 5 to 7 straight or gently curved facets
giving them a natural broken-rock silhouette, not a circle or blob.

Each rock top surface: the upper-left area is the lightest cool gray, directly lit by
the overhead light. The lower-right area is the darkest gray, in deep shadow. The middle
tone covers the rest. The contrast is strong and clear — three distinct gray tones so
the rocks read as solid three-dimensional masses. One or two thin dark crack lines run
across the top surfaces of the rocks, staying well within the outlines.

All rock elements sit at least 2 pixels away from every tile edge so nothing is cut off.
The areas between and around the rocks must remain fully transparent.
```

**Zielfarben:** Highlight `#C8C8C8` · Basis `#8A8B8A` · Schatten `#484848` · Riss `#333333`
**Hintergrund:** Transparent (Gras kommt von BackgroundLayer)

---

### 4. Berry / Beerenstrauch — `env_tile_berry.png`

Runder Beerenstrauch, leicht isometrisch. Gras kommt von BackgroundLayer.

**Prompt:**
```
A round berry bush on a fully transparent background, viewed from a slightly elevated
angle — not straight down, but from about 60 to 70 degrees above the horizon, like a
classic top-down RPG perspective. This means you can see both the rounded top of the
bush and a narrow strip of its front face, giving it clear visible height and volume.
The background must be completely transparent — no grass, no ground color, no fill of
any kind. Only the bush itself is opaque.

The bush is large, filling about two thirds of the tile. It is positioned slightly
above center in the tile so the front face is visible at the bottom without being cut
off — the outer edge of the bush sits at least 2 pixels away from every tile edge.
The bush silhouette is organic and rounded — lumpy with 5 to 7 leaf-cluster bumps
around the top edge, clearly a dense leafy shrub, not a plain circle.

The top surface of the bush catches the overhead light: upper-left is the lightest
green, lower-right of the top is mid green. The front-facing strip at the bottom of
the bush is the darkest green — in shadow because the light comes from above and
slightly from the left. Three clear shading levels make the bush read as a solid
three-dimensional rounded mass with real height.

Nestled among the leaves on the top and front face are two small clusters of berries:
one cluster of 3 berries visible on the upper-left area, one cluster of 2 berries on
the lower-front area. Each berry is a circle 2 to 3 pixels wide in bright red, with
a single lighter highlight pixel in its upper-left.

Everything outside the bush is fully transparent.
```

**Zielfarben:** Blatt-Highlight `#4A8A30` · Blatt-Mitte `#3A7225` · Blatt-Schatten (Front) `#1E4A12` · Beere `#CC3340` · Beere-Highlight `#FF6070`
**Hintergrund:** Transparent (Gras kommt von BackgroundLayer)

---

### 5. Grass / Hohes Gras — `env_tile_grass.png`

Wildes, hohes Gras mit einzelnen Wildblumen, leicht isometrisch. Klar unterscheidbar vom EMPTY-Tile.

**Prompt:**
```
Tall wild grass covering the tile, viewed from a slightly elevated angle — not straight
down, but from about 60 to 70 degrees above the horizon, like a classic top-down RPG
perspective. This means the grass blades have visible height: you can see both their
tips from above and a short stretch of their front faces, making the tile read as
genuinely tall overgrown vegetation rather than flat marks on the ground. The surface
is fully opaque in every corner, no transparent pixels.

The base is a slightly deeper, richer green than plain short meadow grass. The grass
blades are dense and upright — 14 to 18 blades visible, most 1 pixel wide and 4 to
6 pixels tall, a few 2 pixels wide and 5 to 7 pixels tall. The upper portions of the
blades (tips) are the lightest green, catching the overhead light from the upper-left.
The lower portions of the blades (near the base, in shadow from the blades in front)
are the darkest green. The mid tone fills the middle stretch of each blade. All blade
bases sit at least 3 pixels away from every tile edge.

Among the grass, 3 to 5 tiny wildflower clusters are visible — each is a 1 to 2 pixel
dot or short stalk topped with a small pale head in muted yellow or off-white, placed
at least 4 pixels from any edge. No bare dirt, no pebbles.
```

**Zielfarben:** Basis `#446E30` · Halme-Highlight (Spitzen) `#6A9E48` · Halme-Schatten (Basis) `#2C4E20` · Blüten `#D4C870`

---

### 6. Impassable / Unpassierbar — `env_tile_impassable.png`

Massiver Felsblock. Nimmt fast den gesamten Tile ein. Wirkt schwer und unüberwindbar.

**Prompt:**
```
A solid angular rock formation seen from directly above, filling the tile completely
from edge to edge with no transparent or empty areas. This is the terrain itself —
the entire tile surface is rock, opaque in every corner. Only the flat top surface of
the rock is visible because the view is straight down. The rock surface is dark,
irregular, and angular — no smooth curves anywhere. The top surface is predominantly
the mid dark tone. The left side of the top surface catches the overhead light and is
the lightest tone, in an irregular strip. The right and lower areas of the top surface
are the darkest tone, nearly black. A thin diagonal crack crosses the rock surface from
upper-right toward lower-left, staying at least 3 pixels away from the tile edges.
Two or three jagged angular protrusions are visible on the top surface, seen from above
as slightly raised irregular shapes in the lighter tone. The overall color is near-black
with a slight cool blue-gray tint. Along the very bottom edge of the tile, a narrow strip
of meadow green grass is visible where the rock meets the surrounding ground.
```

**Zielfarben:** Linke Seite (Licht) `#4A4A5E` · Oben (Mitte) `#2A2A3A` · Schatten `#141422`
**Boden-Streifen:** `#3A6030` (Gras)

---

## Resource-Overlay-Tiles (transparenter Hintergrund)

Kleine Icons, zentriert in der Tile-Fläche. Transparenter Hintergrund.
Atlas-Ziel: `assets/art/resources/atlas_resources.png`
Tile-Reihenfolge: `[WOOD][STONE][BERRY][FIBER][PLANK]`

Das Icon füllt ca. 60–65% der Tile-Fläche (etwa 20×20 px im 32×32 Tile).
Keine Umrandung, kein Schatten außerhalb des Icons.

---

### 7. Holz / Wood — `env_tile_resource_wood.png`

Ein einzelnes gefälltes Holzscheit, leicht isometrisch.

**Prompt:**
```
A single short wooden log perfectly centered in the tile with equal empty space on all
four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the
horizon, like a classic top-down RPG perspective. The log does not touch any edge of
the tile. The entire log is fully visible — nothing is cut off. The log is oriented
diagonally from upper-left to lower-right. Because of the slight angle, you can see
both the top face of the log and a narrow strip of its front-facing side, giving it
clear visible thickness and volume. It is rounded in cross-section — wider in the
center, tapering at both ends where it was cut. The cut ends show a small circle of
wood grain: a dark center point surrounded by two concentric rings in slightly lighter
tones. The bark along the length of the log is the darkest brown. The top face of the
log catches the light and is the mid warm brown. The front-facing side strip is darker,
in shadow. A thin curved highlight line of the lightest brown runs along the upper-left
edge of the top face. Everything outside the log is fully transparent.
```

**Zielfarben:** Bark `#3E2C1E` · Holz-Mitte `#6B5240` · Highlight `#9A7A5A`

---

### 8. Stein / Stone Resource — `env_tile_resource_stone.png`

Ein einzelner Steinbrocken, leicht isometrisch.

**Prompt:**
```
A single stone chunk perfectly centered in the tile with equal empty space on all four
sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the horizon,
like a classic top-down RPG perspective. The stone does not touch any edge of the tile.
The entire stone is fully visible — nothing is cut off. Because of the slight angle, you
can see both the top face of the stone and a narrow strip of its front-facing side, giving
it clear visible height and mass. The shape is roughly rounded but irregular — not a
perfect circle, with 5 to 6 slightly flat facets giving it a broken-rock appearance. The
top face and left side are the lightest gray, catching the light from above and the
upper-left. The front-facing side strip at the bottom is the darkest gray, in deep shadow.
The middle tone fills most of the stone. A single thin dark crack runs across the top face.
Everything outside the stone is fully transparent.
```

**Zielfarben:** Highlight `#C8C8C8` · Basis `#8A8B8A` · Schatten `#484848`

---

### 9. Beere / Berry Resource — `env_tile_resource_berry.png`

Drei Beeren dicht zusammen als kleine Traube, leicht isometrisch.

**Prompt:**
```
Three round berries clustered tightly together, perfectly centered in the tile with equal
empty space on all four sides, viewed from a slightly elevated angle — about 60 to 70
degrees above the horizon, like a classic top-down RPG perspective. The entire cluster is
fully visible — no berry touches or crosses any edge of the tile. Because of the slight
angle, the berries read as proper spheres with visible roundness, not flat circles. The
berries are arranged in a small triangle: two berries side by side at the bottom, one
berry centered above them. Each berry is roughly 6 to 7 pixels across. The top and upper-
left of each berry catches the light and is the lightest red tone. The lower front of each
berry is in shadow and is the darkest red tone. Each berry has a single white highlight
pixel in its upper-left. The berries are a deep vivid red. Where the berries touch each
other, a 1-pixel dark gap separates them. No stem, no leaves, no ground.
Everything outside the berries is fully transparent.
```

**Zielfarben:** Beere-Mitte `#CC3340` · Beere-Schatten `#8A1020` · Highlight `#FF6878`

---

### 10. Faser / Fiber Resource — `env_tile_resource_fiber.png`

Ein kleines Bündel Faserpflanzen-Stängel, leicht isometrisch.

**Prompt:**
```
A small bundle of plant stalks perfectly centered in the tile with equal empty space on
all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the
horizon, like a classic top-down RPG perspective. The entire bundle is fully visible —
no stalk tip or base reaches the edge of the tile. Because of the slight angle, the
stalks have clear visible height and stand upright convincingly rather than lying flat.
The bundle has 5 to 6 thin stems tied together at the lower third. Below the tie, the
stems splay outward slightly into a narrow base. Above the tie, the stems fan out toward
the top — the outermost stems lean gently left and right, the inner stems stand more
vertical. The tops of the stems have small elongated seed heads or leaf tips, each 2 to
3 pixels long. The stalks are yellow-green. The tips catch the light from above and are
the lightest tone. The lower stalks near the base are in shadow and are the darkest tone.
The front-facing side of each stalk is slightly darker than the top edge. The bind point
is a single darker horizontal stripe across all stems. No ground, no shadow beneath the
bundle. Everything outside the stalks is fully transparent.
```

**Zielfarben:** Spitzen `#D4E840` · Stängel-Mitte `#A8C220` · Basis `#6A7A10`

---

### 11. Bretter / Plank Resource — `env_tile_resource_plank.png`

Ein kleiner Stapel bearbeiteter Holzbretter, leicht isometrisch.

**Prompt:**
```
A small stack of two or three flat wooden planks perfectly centered in the tile with equal
empty space on all four sides, viewed from a slightly elevated angle — about 60 to 70
degrees above the horizon, like a classic top-down RPG perspective. The entire stack is
fully visible — nothing is cut off. The planks are horizontal, slightly overlapping each
other with the nearest plank in front. Each plank is a thin flat rectangle — much wider
than it is tall, with visible thickness on the front face because of the slight viewing
angle. The planks are pale processed wood — lighter and more uniform than raw bark, with
a warm yellowish-tan color. The top face of each plank catches the light from the upper-
left and is the lightest tone. The front-facing side strip shows the plank thickness and
is in shadow, the darkest tone. Fine straight grain lines run along the length of each
plank on the top face — three or four parallel lines, each 1 pixel thick in a slightly
darker mid-tone. Where the planks overlap, a thin 1-pixel dark shadow gap separates them.
No ground, no binding, no knots. Everything outside the stack is fully transparent.
```

**Zielfarben:** Highlight `#ECCF88` · Basis `#D4A860` · Schatten `#8A6A30`

---

## Buildings (transparenter Hintergrund)

Gebäude-Tiles, zentriert in der Tile-Fläche. Transparenter Hintergrund.
Perspektive: leicht isometrisch (~60–70°), wie Resource-Overlay-Tiles.

---

### 11. Lagergebäude / Storage Barn — `bld_tile_storage.png`

Kleines rustikales Holzlager. Dach von oben und schmaler Frontstreifen sichtbar.

<!-- v2 — 2026-06-24: Building too large, filled entire tile; added explicit scale/margin constraint -->

**Prompt:**
```
A small rustic wooden storage barn perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70
degrees above the horizon, like a classic top-down RPG perspective. The entire
building is fully visible — no part touches or crosses any edge of the tile.
Because of the slight angle, you can see both the sloped roof from above and a
narrow strip of the front wall, giving the building clear visible height and
mass.

IMPORTANT — scale: the building occupies roughly 55 to 60 percent of the tile
width and height. At least 8 pixels of fully transparent empty space must remain
on every side (left, right, top, bottom). The building does NOT fill the tile —
it sits as a small object in the center with clear surrounding space. This matches
the same scale as other small buildings on the map, such as a house or lumber camp.

The roof is a shallow pitched gable roof running left to right. The top surface
of the roof is visible and covered in dark wooden planks — horizontal plank lines
running parallel to the ridge. The ridge sits at the center top. The left slope
of the roof catches the overhead light from the upper-left and is the lightest
warm brown. The right slope is in shadow and is the darkest brown. A narrow
front wall strip is visible below the roof edge: two vertical plank lines in
mid brown, and a small dark rectangular door opening (3×4 pixels) centered on
the front face.

The walls are made of horizontal wooden planks in warm mid brown. Everything
outside the building is fully transparent.

Color palette: roof highlight #9A7A5A, roof mid #6B5240, roof shadow #3E2C1E,
wall #7A6048, door #2A1E14.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand `#7A6048` · Tür `#2A1E14`
**Hintergrund:** Transparent

---

### 12. Holzfäller-Hütte / Lumber Camp — `bld_tile_lumber_camp.png`

Kleines rustikales Holzfäller-Gebäude. Gleiche Bauweise wie das Lagergebäude, aber mit Holzstapel an der Seite als erkennbarem Hinweis auf den Betrieb.

**Prompt:**
```
A small rustic wooden lumberjack cabin perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees
above the horizon, like a classic top-down RPG perspective. The entire building is fully
visible — no part touches or crosses any edge of the tile. Because of the slight angle,
you can see both the sloped roof from above and a narrow strip of the front wall, giving
the building clear visible height and mass.

The cabin has solid log walls on all sides — the walls are built from stacked horizontal
round logs, each log 2 pixels tall with a dark gap line between them, in warm mid brown.
The building footprint is roughly square, 18 to 20 pixels wide and 14 to 16 pixels tall
on the tile — the same size as a storage barn.

The roof is a shallow pitched gable roof running left to right. The top surface of the
roof is visible and covered in rough wooden shingles — short horizontal plank lines
running parallel to the ridge. The ridge sits at the center top. The left slope of the
roof catches the overhead light from the upper-left and is the lightest warm brown. The
right slope is in shadow and is the darkest brown. A narrow front wall strip is visible
below the roof edge: log-wall texture in mid brown, and a small dark rectangular door
opening (3×4 pixels) centered on the front face.

To the right side of the building, flush against the right wall: a small neat stack of
two or three short log segments, seen slightly from above and the front. Each log segment
shows a small wood-grain circle on its cut top face in warm tan. The stack is 4 to 5
pixels wide and 3 to 4 pixels tall. The stack is part of the building composition and
does not touch the tile edge.

Everything outside the building and log stack is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand-Log `#7A6048` · Wand-Fuge `#3E2C1E` · Tür `#2A1E14` · Holzstapel-Top `#A88860`
**Hintergrund:** Transparent

---

### 13. Wohnhaus / Residential House — `bld_tile_house.png`

Kleines Holzwohnhaus. Erkennbar durch Fenster und Kamin — klar vom Lager und der
Holzfäller-Hütte unterscheidbar.

**Prompt:**
```
A small wooden residential house perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70
degrees above the horizon, like a classic top-down RPG perspective. The entire
building is fully visible — no part touches or crosses any edge of the tile.
Because of the slight angle, you can see both the sloped roof from above and a
narrow strip of the front wall, giving the building clear visible height and mass.

The house has smooth flat wooden plank walls — horizontal planks, each 2 pixels
tall with a fine dark gap line between them, in warm mid brown. The building
footprint is roughly square, 18 to 20 pixels wide and 14 to 16 pixels tall on
the tile — the same size as a storage barn.

The roof is a shallow pitched gable roof running left to right, covered in
overlapping wooden shingles — short horizontal rows staggered so each row
slightly overlaps the one below. The ridge sits at the center top. The left
slope of the roof catches the overhead light from the upper-left and is the
lightest warm brown. The right slope is in shadow and is the darkest brown.

A narrow front wall strip is visible below the roof edge: plank-wall texture in
mid brown. Near the left of center is a small dark rectangular door opening
(3×4 pixels). To the right of the door is a small window opening (3×3 pixels)
with a single pale blue-gray highlight pixel in its upper-left corner.

Rising from the right third of the roof, just behind the ridge, is a small
square chimney stub: 3 pixels wide and 3 to 4 pixels tall, built from tiny
dark brick-red blocks. The chimney top face is slightly lighter than its sides.

Everything outside the building is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand `#7A6048` · Wand-Fuge `#3E2C1E` · Tür `#2A1E14` · Fenster `#1A2A3A` · Fenster-Highlight `#8AB0D0` · Kamin `#7A3020` · Kamin-Top `#9A4030`
**Hintergrund:** Transparent

---

### 14. Sammlerhütte / Collector's Hut — `bld_tile_collector_hut.png`

Kleine rustikale Sammlerhütte. Erkennbar durch Körbe und eine Trockenrute vor der Hütte — klar vom Lager und dem Wohnhaus unterscheidbar.

**Prompt:**
```
A small rustic wooden collector's hut perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees
above the horizon, like a classic top-down RPG perspective. The entire building is fully
visible — no part touches or crosses any edge of the tile. Because of the slight angle,
you can see both the sloped roof from above and a narrow strip of the front wall, giving
the building clear visible height and mass.

The hut has flat wooden plank walls — horizontal planks, each 2 pixels tall with a fine
dark gap line between them, in warm mid brown. The building footprint is slightly smaller
than a storage barn: roughly 16 to 18 pixels wide and 12 to 14 pixels tall on the tile.

The roof is a shallow pitched gable roof running left to right, covered in rough thatched
material — short diagonal stroke marks in muted straw yellow, dense and overlapping, to
suggest dried grass or reed bundles. The ridge sits at the center top. The left slope of
the roof catches the overhead light from the upper-left and is the lightest warm straw
tone. The right slope is in shadow and is the darkest brown-straw tone. A narrow front
wall strip is visible below the roof edge: plank-wall texture in mid brown, and a small
dark rectangular door opening (2×3 pixels) slightly left of center on the front face.

To the left side of the hut, flush against the left wall: two small wicker baskets sitting
on the ground, seen from slightly above. Each basket is an oval 3 pixels wide and 2 pixels
tall in warm tan, with a single darker horizontal weave line across the center. The two
baskets sit side by side.

In front of the hut, just below the front wall strip: a small horizontal drying rack —
two thin vertical post marks (1 pixel each) with a single horizontal line connecting them
at the top, 5 to 6 pixels wide total. Across the rack, two or three tiny dark hanging
marks suggest dried herbs or bundled plants, each 1 to 2 pixels long.

Everything outside the building, baskets, and drying rack is fully transparent.
```

**Zielfarben:** Dach-Highlight `#C8B050` · Dach-Mitte `#9A8030` · Dach-Schatten `#5A4A18` · Wand `#7A6048` · Wand-Fuge `#3E2C1E` · Tür `#2A1E14` · Körbe `#B89060` · Korb-Fuge `#7A5830` · Trockengestell `#5A4030`
**Hintergrund:** Transparent

---

### 15. Steinmetz / Stonemason — `bld_tile_stonemason.png`

Kleines Steinmetz-Werkstattgebäude. Steinmauern statt Holzplanken. Erkennbar durch Steinquader und einen Bearbeitungsblock vor der Hütte.

**Prompt:**
```
A small stone masonry workshop perfectly centered in the tile with equal empty space on
all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the
horizon, like a classic top-down RPG perspective. The entire building is fully visible —
no part touches or crosses any edge of the tile. Because of the slight angle, you can see
both the flat roof from above and a narrow strip of the front wall, giving the building
clear visible height and mass.

Unlike wooden buildings, the walls of this workshop are built from rough-cut stone blocks —
the front wall strip shows a stacked masonry pattern: rectangular stone blocks roughly
4 pixels wide and 2 pixels tall, with 1-pixel dark mortar gaps between them, in cool
mid gray. The building footprint is roughly square, 18 to 20 pixels wide and 14 to 16
pixels tall on the tile.

The roof is a shallow pitched gable roof running left to right, covered in rough wooden
shingles — short horizontal rows in warm mid brown, staggered so each row slightly
overlaps the one below. The ridge sits at the center top. The left slope of the roof
catches the overhead light from the upper-left and is the lightest warm brown. The right
slope is in shadow and is the darkest brown. This warm wooden roof directly over cool
gray stone walls creates a clear visual contrast that makes the building readable at a
glance. A narrow front wall strip of stone masonry is visible below the roof edge, and
a small dark rectangular door opening (3×4 pixels) is centered on the front face.

To the right side of the workshop, flush against the right wall: a rough stone cutting
block sitting on the ground — a chunky rectangular stone mass, 5 pixels wide and 3 pixels
tall, in the same cool gray as the walls. Its top face is the lightest tone, its front
face is in shadow. One or two thin chisel-mark lines are scratched across the top face
of the cutting block. Beside the block, a single tiny L-shaped mark in dark gray
suggests a stone chisel resting against the block.

Scattered at the base of the building along the front wall: 3 to 4 single-pixel stone
chip marks in light gray, suggesting stone dust and debris from cutting work. These chips
sit between the cutting block and the door, at least 1 pixel away from the tile edge.

Everything outside the building, cutting block, and stone chips is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Mauer-Block `#9A9A9E` · Mauer-Mörtel `#4A4A52` · Tür `#1E1E28` · Schneidblock-Top `#B8B8BC` · Schneidblock-Front `#606068` · Steinstaub `#ACACB0`
**Hintergrund:** Transparent

---

### 16. Werkzeugmacher / Toolmaker — `bld_tile_toolmaker.png`

Kleines Handwerksgebäude. Holzplanken-Wände wie beim Wohnhaus, aber mit kleinem
Amboss neben dem Eingang und einem Werkzeuggestell als erkennbarem Betriebshinweis.

**Prompt:**
```
A small wooden toolmaker's workshop perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees
above the horizon, like a classic top-down RPG perspective. The entire building is fully
visible — no part touches or crosses any edge of the tile. Because of the slight angle,
you can see both the sloped roof from above and a narrow strip of the front wall, giving
the building clear visible height and mass.

The workshop has flat wooden plank walls — horizontal planks, each 2 pixels tall with a
fine dark gap line between them, in warm mid brown. The building footprint is roughly
square, 18 to 20 pixels wide and 14 to 16 pixels tall on the tile.

The roof is a shallow pitched gable roof running left to right, covered in overlapping
wooden shingles — short horizontal rows staggered so each row slightly overlaps the one
below. The ridge sits at the center top. The left slope of the roof catches the overhead
light from the upper-left and is the lightest warm brown. The right slope is in shadow
and is the darkest brown. A narrow front wall strip is visible below the roof edge:
plank-wall texture in mid brown. A small dark rectangular door opening (3×4 pixels)
is placed slightly left of center on the front face. To the right of the door, a small
window opening (3×3 pixels) with a single pale blue-gray highlight pixel in its upper-left
corner hints at firelight from inside.

To the left side of the workshop, flush against the left wall: a small iron anvil sitting
on the ground, seen from slightly above and the front. The anvil is 4 pixels wide and
4 pixels tall. Its flat top face is the lightest cool gray, catching the overhead light.
Its horn — a short 1-pixel pointed extension to the left — protrudes at mid height. The
front face of the anvil body is the darkest gray, in deep shadow. The base is slightly
wider than the body: two pixels wider total, 1 pixel taller, in the darkest tone.

Leaning against the left wall, just behind the anvil: a single thin vertical mark (1 pixel
wide, 5 pixels tall) in dark iron gray represents a tool handle or bar stock. Beside it,
a tiny L-shaped mark (2 pixels) in the same dark gray suggests a hammer head resting
against the wall.

Scattered along the base of the front wall between the door and the right edge: 3 to 4
single-pixel marks in dark iron gray and warm orange-brown, suggesting metal filings and
scale from forging work. These marks sit at least 1 pixel from the tile edge.

Everything outside the building, anvil, and tool marks is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand `#7A6048` · Wand-Fuge `#3E2C1E` · Tür `#2A1E14` · Fenster `#1A2A3A` · Fenster-Highlight `#8AB0D0` · Amboss-Top `#ACACB0` · Amboss-Körper `#686870` · Amboss-Schatten `#2A2A32` · Metallspäne `#4A4A50`
**Hintergrund:** Transparent

---

### 17. Schneider / Tailor — `bld_tile_tailor.png`

Kleines Schneider-Werkstattgebäude. Holzplanken-Wände wie beim Wohnhaus, aber mit Stoffballen und einer Wäscheleine mit hängendem Tuch als erkennbarem Betriebshinweis (verarbeitet Fiber → Stoff).

**Prompt:**
```
A small wooden tailor's workshop perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees
above the horizon, like a classic top-down RPG perspective. The entire building is fully
visible — no part touches or crosses any edge of the tile. Because of the slight angle,
you can see both the sloped roof from above and a narrow strip of the front wall, giving
the building clear visible height and mass.

The workshop has flat wooden plank walls — horizontal planks, each 2 pixels tall with a
fine dark gap line between them, in warm mid brown. The building footprint is roughly
square, 18 to 20 pixels wide and 14 to 16 pixels tall on the tile.

The roof is a shallow pitched gable roof running left to right, covered in overlapping
wooden shingles — short horizontal rows staggered so each row slightly overlaps the one
below. The ridge sits at the center top. The left slope of the roof catches the overhead
light from the upper-left and is the lightest warm brown. The right slope is in shadow
and is the darkest brown. A narrow front wall strip is visible below the roof edge:
plank-wall texture in mid brown. A small dark rectangular door opening (3×4 pixels)
is placed slightly left of center on the front face. To the right of the door, a small
window opening (3×3 pixels) with a single pale blue-gray highlight pixel in its upper-left
corner hints at lamplight from inside.

To the left side of the workshop, flush against the left wall: two small bolts of folded
cloth stacked on the ground, seen from slightly above and the front. Each bolt is a
rounded rectangular roll 4 pixels wide and 2 pixels tall. The top bolt is dyed a muted
teal-blue, the lower bolt a soft dusty rose — each shows its lightest tone on the top
face and a darker shadow tone on the front-facing strip. A single 1-pixel highlight line
runs along the rolled upper edge of each bolt.

In front of the hut, just below the front wall strip: a small horizontal drying line —
two thin vertical post marks (1 pixel each) with a single horizontal line connecting them
at the top, 5 to 6 pixels wide total. Draped over the line hangs a single small piece of
cloth, 3 pixels wide and 2 to 3 pixels tall, in muted off-white linen, lightest at the
top fold and darker along the hanging lower edge.

Scattered along the base of the front wall between the door and the right edge: 3 to 4
single-pixel marks — two in pale yellow-green suggesting loose plant fiber, one or two
in dark gray suggesting a dropped needle or pin. These marks sit at least 1 pixel from
the tile edge.

Everything outside the building, cloth bolts, and drying line is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand `#7A6048` · Wand-Fuge `#3E2C1E` · Tür `#2A1E14` · Fenster `#1A2A3A` · Fenster-Highlight `#8AB0D0` · Stoffballen-Teal `#4A8A8E` · Stoffballen-Rosé `#C08A8E` · Tuch-Leinen `#D8D0BC` · Faser-Reste `#A8C220`
**Hintergrund:** Transparent

---

## NPC / Unit Icons (transparenter Hintergrund)

Kleine Einheiten-Icons für den NPC-Overlay auf der Karte.
Stil: gleicher leicht isometrischer Blickwinkel wie Resource-Overlay-Tiles (~60–70°).
Größe: 32×32 px (wird im Code auf 18×18 skaliert via `NPC_ICON_RADIUS = 9`).
Kein Backdrop-Kreis nötig — wird im Code erzeugt.

---

### 18. Dorfbewohner / Villager NPC — `npc_icon_villager.png`

Kleines Dorfbewohner-Silhouettenicon. Erkennbar als Person auf einen Blick.

**Prompt:**
```
A single villager character icon perfectly centered in the tile with equal empty space on
all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the
horizon, like a classic top-down RPG perspective. The entire figure is fully visible —
no part touches or crosses any edge of the tile. The figure is small enough to read
clearly as a person at 18 pixels: roughly 10 pixels tall and 7 pixels wide. Everything
outside the figure is fully transparent.

The figure consists of three parts stacked vertically:

Head: a circle 3 pixels across, centered at the top of the figure. The top-left catches
the overhead light and is the lightest blue tone. The lower-right is the darkest blue
tone. A 1-pixel face detail — two adjacent single pixels side by side — is visible near
the center of the head in a very dark tone to suggest eyes seen from a slight downward
angle. No nose, no mouth.

Torso and arms: immediately below the head, a rounded rectangular body block 5 pixels
wide and 4 pixels tall. The top face catches the light and is the mid blue tone. The
front-facing strip at the bottom of the torso is the darkest tone, in shadow. Two arm
stubs protrude one pixel out from each side of the torso at mid-height — each arm is
1 pixel wide and 2 pixels tall, in the mid tone, slightly darker on the front face. The
overall torso silhouette is clearly wider than the head.

Legs: two legs descend from the bottom of the torso, each 1 pixel wide and 3 pixels
tall, in the mid blue tone. The legs are spaced 1 pixel apart at the top and taper
slightly toward the feet. The front face of each leg is 1 pixel darker than the top
edge. The feet are each 2 pixels wide and 1 pixel tall at the base.

The entire figure uses the cornflower blue palette — the same blue throughout, with
three shading levels only: one highlight tone, one mid tone, one shadow tone. No skin
color, no clothing detail, no outlines around the figure — the silhouette itself
defines the shape. The figure reads unambiguously as a person, not an object.

Everything outside the figure is fully transparent.
```

**Zielfarben:** Highlight `#7AB8FF` · Mitte `#4A8CD9` · Schatten `#2A5A9A` · Augen-Detail `#1A3A6A`
**Hintergrund:** Transparent (Backdrop-Kreis wird im Code gezeichnet)

---

## Atlas-Assembly

Nach Generierung alle Einzel-Tiles horizontal zusammenfügen:

**Terrain** (6 Tiles → 192×32 px):
```bash
magick env_tile_empty.png env_tile_tree.png env_tile_stone.png \
	   env_tile_berry.png env_tile_grass.png env_tile_impassable.png \
	   +append assets/art/terrain/atlas_terrain.png
```

**Path** (11 Tiles → 352×32 px):
```bash
magick env_tile_path_straight_h.png env_tile_path_straight_v.png \
	   env_tile_path_corner_nw.png env_tile_path_corner_ne.png \
	   env_tile_path_corner_sw.png env_tile_path_corner_se.png \
	   env_tile_path_t_n.png env_tile_path_t_s.png \
	   env_tile_path_t_e.png env_tile_path_t_w.png \
	   env_tile_path_cross.png \
	   +append assets/art/terrain/atlas_path.png
```

**Resources** (4 Tiles → 128×32 px):
```bash
magick env_tile_resource_wood.png env_tile_resource_stone.png \
	   env_tile_resource_berry.png env_tile_resource_fiber.png \
	   env_tile_resource_plank.png \
	   +append assets/art/resources/atlas_resources.png
```

---

## Nächste Schritte nach Asset-Erstellung

1. Tiles in Pixellab generieren und als PNG exportieren
2. Atlases zusammenfügen (ImageMagick oder manuell in Aseprite/GIMP)
3. In `assets/art/terrain/` und `assets/art/resources/` ablegen
4. `map_root.gd` → `_setup_tilesets()` ersetzen: statt Laufzeit-Farbgenerierung die Atlas-PNGs laden
5. Godot Import-Settings: Filter = Nearest, Mipmaps = Disabled
6. Map im Editor rendern und visuell gegen Art Bible prüfen

---

*Letzte Aktualisierung: 2026-05-27 | Referenz: Art Bible Section 3–6, 8 | Stand: Vertical Slice*
