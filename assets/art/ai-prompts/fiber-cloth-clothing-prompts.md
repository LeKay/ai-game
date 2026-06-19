# AI Asset Generation Prompts — Fiber → Cloth → Clothing Chain

Prompts für Pixellab. Pixellab übernimmt Pixel-Art-Stil, Auflösung und Perspektive.
Referenz: Art Bible `design/art/art-bible.md`. Stil-Ankerpunkte aus `sprite-prompts.md`.

**Globale Perspektive:**
- Terrain-Tiles: strikt von direkt oben (Kamera senkrecht nach unten).
- Gebäude-Tiles: leicht erhöhter Winkel ~60–70° über dem Horizont — Oberseite plus schmaler
  Frontstreifen sichtbar. Gleiche Bauweise wie alle anderen `bld_tile_*`-Assets.

**Konsistenz-Regeln (für alle):**
- Lichtquelle oben-links, Schatten fallen nach unten-rechts.
- Palette erdig und gedämpft — keine gesättigten Neonfarben.
- 2–3 Schattierungsstufen pro Farbe (Highlight, Midtone, Shadow).
- Keine Outline um das gesamte Objekt — nur interne Tiefenlinien.

**Komposition (Gebäude + Resource-Icons):**
- Objekt exakt zentriert, gleicher Abstand zu allen vier Kanten.
- Vollständig sichtbar, kein Teil abgeschnitten, ≥ 2–4 px Abstand zu jeder Kante.
- Hintergrund vollständig transparent — kein Boden, kein Rahmen.
- Gebäude: Footprint ~18–20 px breit, ~14–16 px hoch; Satteldach (Highlight links,
  Schatten rechts), schmaler Frontwand-Streifen mit Tür (~3×4 px); ein
  charakteristisches Betriebs-Requisit zur Unterscheidbarkeit.

---

## Gebäude-Tiles (transparenter Hintergrund)

---

### 1. Weberei / Weaver — `bld_tile_weaver.png`

Kleines rustikales Weberei-Gebäude. Erkennbar durch einen kleinen Webstuhl-Rahmen
(zwei senkrechte Pfosten mit horizontalem Querbalken) seitlich vor dem Eingang.

**Prompt:**
```
A small rustic weaving workshop perfectly centered in the tile with equal empty space
on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above
the horizon, like a classic top-down RPG perspective. The entire building is fully
visible — no part touches or crosses any edge of the tile. Because of the slight angle,
you can see both the sloped roof from above and a narrow strip of the front wall, giving
the building clear visible height and mass.

The building has solid wooden plank walls on all sides in warm mid brown. The building
footprint is roughly square, 18 to 20 pixels wide and 14 to 16 pixels tall on the tile.

The roof is a shallow pitched gable roof running left to right. The top surface of the
roof is visible and covered in wooden shingles — short horizontal lines running parallel
to the ridge. The ridge sits at the center top. The left slope catches the overhead
light from the upper-left and is the lightest warm brown. The right slope is in shadow
and is the darkest brown. A narrow front wall strip is visible below the roof edge: flat
plank texture in mid brown, and a small dark rectangular door opening (3×4 pixels)
centered on the front face.

To the left side of the building, flush against the wall: a small vertical loom frame
made of two dark wooden posts with a single horizontal crossbar near the top, 4 to 5
pixels tall, in dark brown. A few horizontal thread lines cross between the posts
in pale cream or light grey, suggesting warp threads on the loom. Light source comes
from the upper-left. Everything outside the building and loom is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand `#7A6048` · Tür `#2A1E14` · Webstuhl-Rahmen `#4A3020` · Fäden `#E8E0C8`
**Hintergrund:** Transparent

---

### 2. Schneiderei / Tailor — `bld_tile_tailor.png`

Kleines Schneider-Atelier. Erkennbar durch einen kleinen Stoffballen (gerolltes
Tuch) auf einem niedrigen Holztisch seitlich vor dem Gebäude.

**Prompt:**
```
A small rustic tailor's workshop perfectly centered in the tile with equal empty space
on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above
the horizon, like a classic top-down RPG perspective. The entire building is fully
visible — no part touches or crosses any edge of the tile. Because of the slight angle,
you can see both the sloped roof from above and a narrow strip of the front wall, giving
the building clear visible height and mass.

The building has solid wooden plank walls on all sides in warm mid brown. The building
footprint is roughly square, 18 to 20 pixels wide and 14 to 16 pixels tall on the tile.

The roof is a shallow pitched gable roof running left to right. The top surface is
visible and covered in wooden shingles — short horizontal lines running parallel to the
ridge. The ridge sits at the center top. The left slope catches the overhead light from
the upper-left and is the lightest warm brown. The right slope is in shadow and is the
darkest brown. A narrow front wall strip is visible below the roof edge: flat plank
texture in mid brown, and a small dark rectangular door opening (3×4 pixels) centered
on the front face.

To the right side of the building: a tiny low wooden work table (3 pixels wide, 2 pixels
tall, dark brown) with a rolled bolt of cloth on top — a small cylindrical roll, 3 pixels
wide and 2 pixels tall, in muted blue-grey with a slightly lighter top highlight
suggesting folded fabric. Light source comes from the upper-left. Everything outside
the building and table is fully transparent.
```

**Zielfarben:** Dach-Highlight `#9A7A5A` · Dach-Mitte `#6B5240` · Dach-Schatten `#3E2C1E` · Wand `#7A6048` · Tür `#2A1E14` · Tisch `#4A3020` · Stoffballen `#8090A8` · Ballen-Highlight `#A8B8C8`
**Hintergrund:** Transparent

---

## Resource-Icons (transparenter Hintergrund)

---

### 3. Tuch / Cloth — `cloth.png` (UI-Icon, `assets/ui/icons/resources/`)

Ein gefaltetes Stück Stoff, von leicht oben gesehen. Weicher, matter Blaugrau-Ton.

**Prompt:**
```
A small piece of folded cloth perfectly centered in the tile with equal empty space on
all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above
the horizon, like a classic top-down RPG icon perspective. The entire object is fully
visible — no part touches or crosses any edge. At least 4 pixels of empty space on
every side.

The cloth is a simple rectangular folded piece of woven fabric, approximately 12 pixels
wide and 8 pixels tall. The top surface is flat and smooth in a muted blue-grey tone.
The left edge catches the light from the upper-left and is slightly lighter. The right
edge and the bottom visible fold are in shadow, one shade darker. A single subtle
horizontal fold line runs across the middle of the fabric, slightly darker than the base
tone, suggesting the cloth is folded once. No buttons, no pattern, no texture detail —
just the fold line and the three-tone shading. Everything outside the cloth is fully
transparent.
```

**Zielfarben:** Highlight `#A8B8C8` · Mitte `#8090A8` · Schatten `#506070` · Faltlinie `#607080`
**Hintergrund:** Transparent

---

### 4. Kleidung / Clothing — `clothing.png` (UI-Icon, `assets/ui/icons/resources/`)

Ein einfaches gefaltetes Kleidungsstück (Hemd oder Tunika), von leicht oben gesehen.
Wärmerer Farbton als Tuch — erdiges Ocker oder Leinen-Beige.

**Prompt:**
```
A small folded tunic or simple garment perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees
above the horizon, like a classic top-down RPG icon perspective. The entire object is
fully visible — no part touches or crosses any edge. At least 4 pixels of empty space
on every side.

The garment is a folded rectangular piece of clothing approximately 12 pixels wide and
9 pixels tall, resembling a simple linen tunic or shirt folded flat. The fabric is in
a warm earthy linen tone — muted ocher or pale tan. The top surface catches the light
from the upper-left and is the lightest tone. The right side and bottom fold are one
shade darker. A subtle V-shaped neckline indentation (2 pixels wide, 1 pixel deep) is
visible at the top center, darker than the fabric, confirming it is a garment and not
just cloth. One horizontal fold line runs across the lower third, slightly darker than
the base. No buttons, no embroidery. Everything outside the garment is fully transparent.
```

**Zielfarben:** Highlight `#D4B880` · Mitte `#B09050` · Schatten `#7A6030` · Ausschnitt `#4A3010` · Faltlinie `#8A7040`
**Hintergrund:** Transparent

---

## Atlas-Assembly & Nächste Schritte

1. Assets in **Pixellab** aus den Prompts oben generieren.
2. Als PNG exportieren (je 32×32 px oder Projektstandard, transparenter Hintergrund).
3. Ablegen:
   - `bld_tile_weaver.png` → `assets/art/tiles/`
   - `bld_tile_tailor.png` → `assets/art/tiles/`
   - `cloth.png` → `assets/ui/icons/resources/`
   - `clothing.png` → `assets/ui/icons/resources/`
4. Godot Import-Settings: Filter = Nearest, Mipmaps = Disabled.
5. Im Editor gegen Art Bible prüfen (Farbpalette, Perspektive, Größe).
6. Bis PNGs existieren greift der Code-Fallback: Gebäude nutzen `storage`-Textur-Fallback,
   Ressourcen zeigen `glyph` (🧶 / 👘).
