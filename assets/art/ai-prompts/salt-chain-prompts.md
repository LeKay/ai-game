# AI Asset Generation Prompts — Salt Chain

Prompts für die Coastal-Salt-Produktionskette (Salt Works + UI-Icon).
Stil-Referenz: `assets/art/ai-prompts/sprite-prompts.md` (Art Bible DNA).

---

## Globale Perspektive & Konsistenz-Regeln

**Terrain-Tiles** (Boden, von direkt oben): Kamera senkrecht nach unten, nur Oberseite
sichtbar, Tiefe nur durch Schattierung.

**Gebäude / Resource-Overlays** (~60–70° über Horizont, "classic top-down RPG perspective"):
Oberseite plus schmaler Frontstreifen sichtbar.

- Lichtquelle oben-links, Schatten nach unten-rechts.
- Palette erdig und gedämpft — keine Neonfarben.
- 2–3 Schattierungsstufen pro Farbe (Highlight, Midtone, Shadow).
- Keine Gesamt-Outline — nur interne Tiefenlinien.
- Objekt exakt zentriert, ≥ 2–4 px Abstand zu allen vier Kanten, Hintergrund transparent.

---

## Assets dieser Kette

### 1. Salt Works / Salz-Siederei — `bld_tile_salt_works.png`

Coastal salt evaporation facility — a series of shallow stone-edged pans filled
with seawater, with a small worker's shelter and a wooden rake leaning against it.

**Prompt:**
```
Top-down RPG pixel art building tile, 64x64 pixels, no background, transparent
background outside the structure. Classic top-down RPG perspective, camera elevated
~60-70° above horizon, showing rooftop and a thin front wall strip.
A coastal salt works: two shallow rectangular evaporation pans made of low stone
walls, filled with pale crystalline water showing salt deposits forming at the
edges. A tiny stone storage hut sits top-left with a flat sandy-beige roof
(highlight #D4C890, midtone #B8A868, shadow #8C7840). A wooden rake leans against
the hut front wall. Stone pan walls: #8C7A6A highlight, #6E5E50 midtone, #50423A
shadow. Pan water surface: #A8D4E8 with white salt crystal speckles #F0F0EC.
Light source top-left, shadows fall bottom-right. Eroded stone and sun-bleached
wood textures. No outline around the entire tile. Everything outside the structure
footprint is fully transparent.
Color palette: hut roof highlight #D4C890, roof midtone #B8A868, roof shadow
#8C7840, hut wall #9A8870, stone pan #8C7A6A, pan shadow #50423A, brine water
#A8D4E8, salt crystals #F0F0EC.
```

**Zielfarben:** Hüttendach-Highlight `#D4C890` · Midtone `#B8A868` · Shadow `#8C7840` · Hüttenwand `#9A8870` · Steinpfanne `#8C7A6A` · Sole `#A8D4E8` · Salzkristalle `#F0F0EC`
**Hintergrund:** Transparent

---

### 2. Salt UI-Icon — `assets/ui/icons/resources/salt.png`

Small pile of white-grey salt crystals for UI inventory icon and carrier animation.

**Prompt:**
```
Top-down RPG pixel art resource icon, 64x64 pixels, transparent background.
Classic top-down RPG perspective (~60-70°). A small heap of coarse salt crystals
— angular white and pale-grey grains piled in a loose mound. Largest crystals
at top catching the light (#F4F2EC highlight, #D8D4C8 midtone, #B0AAA0 shadow).
A few scattered individual crystals on the transparent ground around the mound.
Light source top-left, crisp hard-edged pixel shading. No outline around the
entire object. Everything outside the salt pile is fully transparent.
Color palette: crystal highlight #F4F2EC, midtone #D8D4C8, shadow #B0AAA0,
accent mineral blue-grey #9AAAB8.
```

**Zielfarben:** Kristall-Highlight `#F4F2EC` · Midtone `#D8D4C8` · Shadow `#B0AAA0` · Akzent `#9AAAB8`
**Hintergrund:** Transparent

---

## Atlas-Assembly-Hinweis

Beide Assets sind Einzel-Tiles (kein Atlas nötig). Nach Generierung:
1. `bld_tile_salt_works.png` → `assets/art/tiles/`
2. `salt.png` → `assets/ui/icons/resources/`
3. Godot-Editor öffnen → Import-Settings: Filter=Nearest, Mipmaps=Disabled
4. Visuell gegen Art-Bible-Palette prüfen (besonders Salzpfannen-Farben)

## Generator-Script

Für direkten PixelLab-API-Aufruf: `assets/art/ai-prompts/generate_salt_assets.py`
(noch anzulegen — Key aus `~/.pixellab_key`, 64×64, `view: "high top-down"`,
`outline: "lineless"`, `detail: "highly detailed"`, `no_background: true`).
