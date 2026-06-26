# Rope Production Chain — AI Asset Prompts

Prompts für die Rope-Kette: ROPE_MAKER-Gebäude + Rope-Icon.

## Globale Stil-Orientierungen (Art-Bible-Auszug)

**Perspektive:**
- Gebäude / Ressourcen-Overlays: leicht erhöhter Winkel ~60–70° über dem Horizont
  ("classic top-down RPG perspective") — Oberseite plus schmaler Frontstreifen sichtbar.

**Konsistenz-Regeln:**
- Lichtquelle oben-links, Schatten fallen nach unten-rechts.
- Palette erdig und gedämpft — keine gesättigten Neonfarben.
- 2–3 Schattierungsstufen pro Farbe (Highlight, Midtone, Shadow).
- Keine Outline um das gesamte Objekt — nur interne Tiefenlinien.

**Komposition (Gebäude + Icons, transparenter Hintergrund):**
- Objekt exakt zentriert, gleicher Abstand zu allen vier Kanten.
- Vollständig sichtbar, kein Teil abgeschnitten, ≥ 2–4 px Abstand zu jeder Kante.
- Hintergrund vollständig transparent — kein Boden, kein Rahmen.
- Gebäude: Footprint ~18–20 px breit, ~14–16 px hoch; Satteldach (Highlight links,
  Schatten rechts), schmaler Frontwand-Streifen mit Tür (~3×4 px).

---

## Assets

### 1. Seilerei / Rope Maker — `bld_tile_rope_maker.png`

Kleines Holzgebäude einer Seilerei; charakteristisches Betriebs-Requisit: Seilspule und Faserbündel.

**Prompt:**
```
A small rustic wooden rope-making workshop perfectly centered in the tile with equal
empty space on all four sides, viewed from a slightly elevated angle — about 60 to 70
degrees above the horizon, like a classic top-down RPG perspective. The entire
building is fully visible — no part touches or crosses any edge of the tile. Because
of the slight angle, you can see both the sloped roof from above and a narrow strip of
the front wall, giving the building clear visible height and mass.

The roof is a shallow pitched gable roof running left to right. The left slope catches
the overhead light from the upper-left and is the lightest warm tan-brown. The right
slope is in shadow and is the darkest brown. A narrow front wall strip is visible below
the roof edge: plank-wall texture in mid warm brown, and a small dark rectangular door
opening (3x4 pixels) centered on the front face.

To the right side of the building, a large coiled bundle of twisted rope sits on the
ground — thick golden-brown coils stacked in a neat flat pile, showing the finished
output. At the front-left, two short vertical wooden posts with thin rope strands
strung between them form a simple rope-twisting rack, hinting at the craft inside.

The building footprint is roughly 18 to 20 pixels wide and 14 to 16 pixels tall on
the tile. The walls are made of horizontal wooden planks in warm mid brown. Everything
outside the building is fully transparent.

Color palette: roof highlight #A09060, roof midtone #706840, roof shadow #4A4428,
wall #8A7050, door #302010, rope coil highlight #C8A840, rope coil shadow #8A7228,
post #7A6040.
```

**Zielfarben:** Dach-Highlight `#A09060` · Dach-Mitte `#706840` · Dach-Schatten `#4A4428` · Wand `#8A7050` · Tür `#302010` · Seilspule `#C8A840`
**Hintergrund:** Transparent

---

### 2. Rope (UI-Icon) — `assets/ui/icons/resources/rope.png`

Seilspule als UI-Icon, zentriert auf transparentem Hintergrund.

**Prompt:**
```
A neatly coiled length of twisted brown rope perfectly centered on a fully transparent
background, viewed from a slightly elevated angle — about 60 to 70 degrees above the
horizon, like a classic top-down RPG perspective. The rope is wound into a compact
circular coil showing 3 to 4 overlapping loops of thick twisted fiber cord.

The rope surface clearly shows the characteristic twisted two-strand texture in warm
golden-brown. The upper-left portion of the coil catches overhead light and shows the
brightest warm gold-brown highlight. The lower-right portion is in shadow, darker
brown. The rope coil sits entirely within the tile, centered with equal empty space on
all sides and at least 6 pixels of transparent margin on every edge.

No ground, no shadow cast onto a surface, no background fill — only the rope coil
itself on a fully transparent background.

Color palette: rope highlight #D4A840, rope midtone #A07828, rope shadow #6A5018,
twist dark line #3A2808.
```

**Zielfarben:** Seil-Highlight `#D4A840` · Seil-Mitte `#A07828` · Seil-Schatten `#6A5018`
**Hintergrund:** Transparent

---

## Atlas-Assembly & Nächste Schritte

1. PNGs via `generate_rope_assets.py` aus dieser Datei generieren (PixelLab API).
2. Gebäude-Tile → `assets/art/buildings/bld_tile_rope_maker.png`
3. Icon → `assets/ui/icons/resources/rope.png`
4. Im Godot-Editor: FileSystem-Dock → Rechtsklick → "Reimport" auf beide Dateien.
   Import-Settings: Filter = Nearest, Mipmaps = Disabled.
5. Visuell gegen Art-Bible prüfen (Perspektive, Palette, Licht oben-links).
6. Bei Stil-Abweichung: Script erneut mit präzisierterer `description` ausführen.
