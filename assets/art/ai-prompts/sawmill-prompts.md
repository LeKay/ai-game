# AI Asset Generation Prompts — Sawmill (Wood → Plank)

Prompts für Pixellab. Referenz: `assets/art/ai-prompts/sprite-prompts.md` (globale Stil-DNA).

**Globale Perspektive:**
- Gebäude-Tiles: leicht erhöhter Winkel ~60–70° über dem Horizont — Oberseite plus schmaler Frontstreifen sichtbar.
- Lichtquelle oben-links, Schatten fallen nach unten-rechts.
- Palette erdig und gedämpft — keine gesättigten Neonfarben.
- 2–3 Schattierungsstufen pro Farbe. Keine Gesamt-Outline, nur interne Tiefenlinien.
- Objekt zentriert, vollständig sichtbar, ≥ 2–4 px Abstand zu jeder Kante. Transparenter Hintergrund.

---

## 1. Sägewerk / Sawmill — `bld_tile_sawmill.png`

Kleines Holzgebäude mit Satteldach, erkennbarem Sägeblatt oder Baumstamm-Stapel als Betriebs-Requisit.

**Prompt:**
```
A small wooden sawmill building seen from a slightly elevated top-down angle (classic RPG perspective,
roughly 60-70 degrees above the horizon). The building has a gabled saddle roof with wood-plank
siding. Light source upper-left: left roof face is the brightest highlight, right roof face is in
shadow, a narrow front wall strip below with a small doorway (~3x4 px).

Distinctive operating prop: a short horizontal log on a sawhorse or log cradle sitting directly
in front of the building entrance, with a single large circular saw blade mounted on the right
side of the building wall (a ~6px diameter circle with a dark center). A small stack of two or
three finished planks (pale, thin rectangles) leans against the left wall.

Color palette: roof highlight #C8B068, roof midtone #A07840, roof shadow #6B4E28, wall planks #B89050,
door #5A3A20, log #8C6030, sawblade #888888 with highlight #CCCCCC, finished planks #D4A860.

Lineless style — no black outline around the whole structure, only internal depth lines between
surfaces. Everything outside the building footprint is fully transparent.
```

**Zielfarben:** Dach-Highlight `#C8B068` · Dach-Mitte `#A07840` · Dach-Schatten `#6B4E28` · Wand `#B89050` · Tür `#5A3A20` · Sägeblatt `#888888` · Bretter `#D4A860`
**Hintergrund:** Transparent

---

## Atlas-Assembly & Nächste Schritte

1. Generierung via PixelLab MCP (`create_map_object`, `view: "high top-down"`, 32×32)
2. PNG exportieren → `assets/art/tiles/bld_tile_sawmill.png`
3. `.import`-Sidecar entsteht automatisch beim nächsten Godot-Editor-Start (Filter=Nearest, Mipmaps=Disabled)
4. Im Godot-Editor gegen Art-Bible-Gebäude prüfen (Palette, Perspektive, Größe)
5. Bei Stil-Abweichung: erneut generieren mit präzisierterer `description`
