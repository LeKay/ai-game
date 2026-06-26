# AI Asset Prompts — Pottery Chain (clay → pottery)

Prompts für PixelLab API (`POST /v2/create-image-pixen`). Alle Tiles 64×64 px.

## Globale Stil-Orientierungen (Art-Bible DNA)

**Perspektive:**
- Gebäude / Ressourcen-Overlays: leicht erhöhter Winkel ~60–70° über dem Horizont
  („classic top-down RPG perspective") — Oberseite plus schmaler Frontstreifen sichtbar.

**Konsistenz-Regeln:**
- Lichtquelle oben-links, Schatten fallen nach unten-rechts.
- Palette erdig und gedämpft — keine gesättigten Neonfarben.
- 2–3 Schattierungsstufen pro Farbe (Highlight, Midtone, Shadow).
- Keine Outline um das gesamte Objekt — nur interne Tiefenlinien.

**Komposition (transparenter Hintergrund):**
- Objekt exakt zentriert, gleicher Abstand zu allen vier Kanten.
- Vollständig sichtbar, kein Teil abgeschnitten, ≥ 4 px Abstand zu jeder Kante.
- Hintergrund vollständig transparent — kein Boden, kein Rahmen.
- Gebäude-Footprint ~18–20 px breit, ~14–16 px hoch; Satteldach (Highlight links,
  Schatten rechts), schmaler Frontwand-Streifen; ein charakteristisches Requisit.

---

## Gebäude-Tiles

### 1. Lehmgrube / Clay Pit — `bld_tile_clay_pit.png`

Einfaches Grubengebäude mit Holzabstützung und einem Haufen rohes Lehm davor; Kennzeichen ist der freiliegende Erdschnitt.

**Prompt:**
```
A small clay pit building seen from a classic top-down RPG perspective (~60-70 degrees above horizon), pixel art style, highly detailed, lineless (no black outline around the whole object). The structure has a low timber-framed shed roof with wooden support beams, seen at a slight angle showing the top and a narrow front strip. In front of the shed lies a mound of raw reddish-brown clay freshly dug from the earth. The pit entrance is visible as a dark earthy recess. Light comes from the upper-left; shadows fall to the lower-right. Roof boards are weathered grey-brown wood. Walls are rough timber planks. Everything outside the building silhouette is fully transparent.
Color palette: roof highlight #A08060, roof midtone #7A6040, roof shadow #4E3C20, wall #8C6E48, clay mound highlight #C87840, clay mound midtone #A05820, clay mound shadow #6B3810.
```

**Zielfarben:** Dach-Highlight `#A08060` · Dach-Mitte `#7A6040` · Dach-Schatten `#4E3C20` · Wand `#8C6E48` · Lehmhaufen-Highlight `#C87840` · Lehmhaufen-Mitte `#A05820` · Lehmhaufen-Schatten `#6B3810`
**Hintergrund:** Transparent

---

### 2. Töpferofen / Pottery Kiln — `bld_tile_pottery_kiln.png`

Runder Brennofen aus Lehm-Ziegeln mit Rauchloch oben und fertigem Gefäß daneben.

**Prompt:**
```
A pottery kiln building seen from a classic top-down RPG perspective (~60-70 degrees above horizon), pixel art style, highly detailed, lineless (no black outline around the whole object). The kiln is a squat rounded dome structure made of fired clay bricks in warm terracotta tones, with a small smoke hole visible on the top surface. A narrow front strip shows a sealed brick arch entrance. Beside the kiln stands a finished clay pot as the operational requisite. Light comes from the upper-left; shadows fall to the lower-right. Brick highlights are warm orange-tan, shadows are deep brown. Everything outside the building silhouette is fully transparent.
Color palette: brick highlight #C8784A, brick midtone #A05830, brick shadow #6B3818, dome top #8C4820, pot #D49060, pot shadow #9A6038.
```

**Zielfarben:** Ziegel-Highlight `#C8784A` · Ziegel-Mitte `#A05830` · Ziegel-Schatten `#6B3818` · Kuppel-Oben `#8C4820` · Topf `#D49060` · Topf-Schatten `#9A6038`
**Hintergrund:** Transparent

---

## UI-Icons (Carrier-Animation)

### 3. Pottery Icon — `assets/ui/icons/resources/pottery.png`

Einfaches Tongefäß, zentriert auf transparentem Hintergrund, für die Transport-Animation.

**Prompt:**
```
A single clay pottery vessel (amphora-style pot) seen from a slightly elevated angle, pixel art style, highly detailed, lineless. The pot has a round belly, narrow neck, and two small handles. Warm terracotta color with light catch on the upper-left shoulder and deep shadow on the lower-right. Everything outside the pot silhouette is fully transparent. Object is centered with at least 4 pixels margin on all sides.
Color palette: pot highlight #D4905A, pot midtone #B06830, pot shadow #7A4018, rim #C87848.
```

**Zielfarben:** Topf-Highlight `#D4905A` · Topf-Mitte `#B06830` · Topf-Schatten `#7A4018` · Rand `#C87848`
**Hintergrund:** Transparent

---

## API-Call-Parameter (für alle drei Assets)

```python
# Gemeinsame Parameter — NICHT ändern:
{
	"image_size": {"width": 64, "height": 64},
	"view": "high top-down",
	"detail": "highly detailed",
	"outline": "lineless",
	"no_background": True,
}
# Zielpfade:
# bld_tile_clay_pit.png     → assets/art/tiles/bld_tile_clay_pit.png
# bld_tile_pottery_kiln.png → assets/art/tiles/bld_tile_pottery_kiln.png
# pottery.png               → assets/ui/icons/resources/pottery.png
```

---

## Nächste Schritte

1. PixelLab API-Call für jedes Asset (3c aus dem Skill) — Balance vorab prüfen, Freigabe einholen.
2. PNGs in die Zielpfade ablegen.
3. Godot-Editor starten → `.import`-Sidecars entstehen automatisch beim Editor-Scan.
4. Im FileSystem-Dock prüfen: Import-Settings Filter=Nearest, Mipmaps=Disabled.
5. Gebäude im Spiel platzieren und Screenshot machen (Phase 9).
