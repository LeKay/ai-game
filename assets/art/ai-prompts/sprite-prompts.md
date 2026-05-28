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

### 1b. Sand / Boden — `env_tile_sand.png` *(Assets vorhanden: env_tile_sand_01–16.png)*

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
Tile-Reihenfolge: `[WOOD][STONE][BERRY][FIBER]`

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

## Buildings (transparenter Hintergrund)

Gebäude-Tiles, zentriert in der Tile-Fläche. Transparenter Hintergrund.
Perspektive: leicht isometrisch (~60–70°), wie Resource-Overlay-Tiles.

---

### 11. Lagergebäude / Storage Barn — `bld_tile_storage.png`

Kleines rustikales Holzlager. Dach von oben und schmaler Frontstreifen sichtbar.

**Prompt:**
```
A small rustic wooden storage barn perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70
degrees above the horizon, like a classic top-down RPG perspective. The entire
building is fully visible — no part touches or crosses any edge of the tile.
Because of the slight angle, you can see both the sloped roof from above and a
narrow strip of the front wall, giving the building clear visible height and
mass.

The roof is a shallow pitched gable roof running left to right. The top surface
of the roof is visible and covered in dark wooden planks — horizontal plank lines
running parallel to the ridge. The ridge sits at the center top. The left slope
of the roof catches the overhead light from the upper-left and is the lightest
warm brown. The right slope is in shadow and is the darkest brown. A narrow
front wall strip is visible below the roof edge: two vertical plank lines in
mid brown, and a small dark rectangular door opening (3×4 pixels) centered on
the front face.

The building footprint is roughly square, 18 to 20 pixels wide and 14 to 16
pixels tall on the tile. The walls are made of horizontal wooden planks in warm
mid brown. Everything outside the building is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand `#7A6048` · Tür `#2A1E14`
**Hintergrund:** Transparent

---

## Atlas-Assembly

Nach Generierung alle Einzel-Tiles horizontal zusammenfügen:

**Terrain** (6 Tiles → 192×32 px):
```bash
magick env_tile_empty.png env_tile_tree.png env_tile_stone.png \
	   env_tile_berry.png env_tile_grass.png env_tile_impassable.png \
	   +append assets/art/terrain/atlas_terrain.png
```

**Resources** (4 Tiles → 128×32 px):
```bash
magick env_tile_resource_wood.png env_tile_resource_stone.png \
	   env_tile_resource_berry.png env_tile_resource_fiber.png \
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
