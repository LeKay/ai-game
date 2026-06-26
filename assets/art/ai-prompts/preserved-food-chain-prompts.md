# AI Asset Prompts — Preserved Food Chain

Kette: meat/fish + salt + pottery → preserved_food
Gebäude: PRESERVATION_HOUSE

**Globale Orientierungen (Art-Bible):**
- Gebäude/Ressourcen-Overlays: ~60–70° erhöhter Winkel, Oberseite + schmaler Frontstreifen
- Lichtquelle oben-links, Schatten nach unten-rechts
- Palette erdig + gedämpft, 2–3 Schattierungsstufen, keine Gesamt-Outline
- Objekt zentriert, transparenter Hintergrund, ≥2 px Abstand zu Kanten

---

### 1. Räucherhaus / Preservation House — `bld_tile_preservation_house.png`

Kleines Steingebäude mit Schornstein. Erkennbar durch gestapelte Tongefäße und
hängende Fleischbündel seitlich vor dem Eingang als Betriebshinweis.

**Prompt:**
```
A small preservation house perfectly centered in the tile with equal empty space on all
four sides, viewed from a slightly elevated angle — about 60 to 70 degrees above the
horizon. The building uses rough stone walls with visible mortar joints. A squat stone
chimney rises slightly off-center on the roof, emitting a faint pixel smudge of smoke.
The saddle roof is covered with dark clay tiles: highlight on the left side, shadow on
the right. A narrow front wall strip shows a low wooden door with iron hinges. To the
right of the door, two stacked clay pottery jars in earthy ochre tones sit on a small
stone ledge — they are the key identifying feature of this building. To the left, a
small wooden hanging rack displays two dark cured meat bundles tied with thin fiber
cord. Light source upper-left. Everything outside the building silhouette is fully
transparent.
```

**Zielfarben:** Dach-Highlight `#8A7060` · Dach-Mitte `#5C4A38` · Dach-Schatten `#2E2018` · Mauer-Block `#8A8070` · Mauer-Mörtel `#4A4040` · Tür `#2A1A10` · Topf-Körper `#B07840` · Topf-Highlight `#D09860` · Fleisch-Dunkel `#6A2820`
**Hintergrund:** Transparent

---

### 2. UI-Icon Preserved Food — `assets/ui/icons/resources/preserved_food.png`

Einzelne versiegelte Töpferflasche mit Tuch-Verschluss — Handels-Konserve.

**Prompt:**
```
A single sealed ceramic preservation jar perfectly centered in the tile with equal empty
space on all four sides, viewed from a slightly elevated angle — about 60 to 70 degrees
above the horizon. The jar is a short round-bellied pottery vessel in warm ochre-brown
tones. A scrap of dark cloth is tied over the mouth with a thin cord, indicating a
hermetic seal. Light from upper-left creates a highlight arc on the left shoulder of
the vessel and a cast shadow on the lower-right. A faint ring of white crystalline salt
residue marks the neck where it was sealed. The jar stands alone on a fully transparent
background. Everything outside the jar silhouette is fully transparent.
```

**Zielfarben:** Topf-Highlight `#D09860` · Topf-Mitte `#A07040` · Topf-Schatten `#5A3820` · Tuch `#4A3828` · Salz-Ring `#D8D0C0` · Kordel `#8A6040`
**Hintergrund:** Transparent

---

## Atlas-Assembly / Nächste Schritte

- PNGs via PixelLab `POST /v2/create-image-pixen`, 64×64, `view: "high top-down"`, `outline: "lineless"`, `no_background: true`
- Speicherorte: `assets/art/tiles/bld_tile_preservation_house.png` · `assets/ui/icons/resources/preserved_food.png`
- Import-Settings (Godot): Filter = Nearest, Mipmaps = Disabled
- `.import`-Sidecars entstehen beim nächsten Editor-Start automatisch
