# AI Asset Generation Prompts — Charcoal Chain (Köhlerei)

Referenz: `assets/art/ai-prompts/sprite-prompts.md` (Stil-DNA des Projekts).

## Globale Perspektive und Konsistenz-Regeln

**Perspektive Gebäude / Icons (leicht isometrisch ~60–70°):**
- Kamera leicht erhöht über dem Horizont — Oberseite plus schmaler Frontstreifen sichtbar
- Lichtquelle oben-links, Schatten nach unten-rechts

**Konsistenz:**
- Palette erdig und gedämpft — keine gesättigten Neonfarben
- 2–3 Schattierungsstufen pro Farbe (Highlight, Midtone, Shadow)
- Keine Outline um das gesamte Objekt — nur interne Tiefenlinien
- Objekt exakt zentriert, ≥ 2–4 px Abstand zu jeder Kante
- Hintergrund vollständig transparent

---

### 1. Köhlerei / Charcoal Kiln — `bld_tile_charcoal_kiln.png`

Rundes Erdmound-Gebäude (Kohlenmeiler) mit gestapeltem Holz davor als charakteristischem Betriebs-Requisit. Kleiner Rauchaustritt an der Kuppel oben.

**Prompt:**
```
Pixel art charcoal kiln building tile for a top-down RPG, viewed from a slightly elevated angle of about 60-70 degrees (classic top-down RPG perspective) — the top surface and a narrow front strip are both visible. The building is a low rounded earth-and-stone mound kiln (Kohlenmeiler), dome-shaped, packed dark earth with stone reinforcement around the base. The dome top has a small vent hole with faint dark smoke wisps rising from it. To the front-left of the mound, a small stack of 2-3 dark logs is visible as a characteristic operational detail. Light source comes from the upper-left: the dome top-left face is the lightest, center midtone, lower-right shadow. The base stone ring has a slightly lighter highlight on the upper-left stones. Everything outside the building silhouette is fully transparent.
```

**Zielfarben:** Dome highlight `#8B7055` · Dome midtone `#5C4530` · Dome shadow `#362818` · Stone base `#706050` · Log stack `#4A3220` · Smoke vent `#2A1E14`
**Hintergrund:** Transparent

---

### 2. Charcoal Icon / Kohle-Icon — `charcoal.png`

Drei unregelmäßige schwarze Kohle-Brocken, leicht überlappend, auf transparentem Hintergrund. Dunkle matte Oberfläche mit sparsamen Highlight-Reflexen.

**Prompt:**
```
Pixel art icon of three pieces of charcoal (coal chunks) for a top-down RPG resource icon, viewed from a slightly elevated angle. Three irregularly shaped dark charcoal chunks arranged in a loose cluster, slightly overlapping. The chunks have rough, jagged edges and a matte dark black-grey surface. A sparse bright highlight glint on the upper-left face of each chunk catches the light source from the upper-left direction. No outline around the entire group — only internal edge lines between chunk faces. Everything outside the charcoal chunks is fully transparent. Highly detailed pixel art.
```

**Zielfarben:** Chunk highlight `#706868` · Chunk midtone `#302828` · Chunk shadow `#181010` · Internal edge `#100C0C`
**Hintergrund:** Transparent

---

## Atlas-Assembly und Nächste Schritte

1. Generierung via PixelLab `/v2/create-image-pixen` (64×64, `high top-down`, `lineless`, `highly detailed`, `no_background: true`)
2. PNGs in `assets/art/tiles/bld_tile_charcoal_kiln.png` bzw. `assets/ui/icons/resources/charcoal.png` ablegen
3. Godot Editor öffnen → FileSystem-Dock → Reimport triggern (Filter=Nearest, Mipmaps=Disabled)
4. Visuell gegen Art Bible prüfen (Perspektive, Palette, Licht)
5. Bei Stil-Abweichung: erneute Generierung mit präzisierterer `description`
