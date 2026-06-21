# Water Bridge — AI Asset Prompts

Asset for the **Bridge building** — a player-built `BuildingType.BRIDGE`
(`src/gameplay/building_registry.gd`) placed on a `WATER` tile to make it passable. Rivers
may split the map (see `design/quick-specs/water-features-rivers-lakes-coast-2026-06-20.md`);
the player bridges them. Gated behind the `paving` node (`data/progression_tree.json` →
`bridge_building`). The bridge renders via the standard building sprite layer
(`BUILDING_TEXTURES[BRIDGE]` → `env_tile_bridge_h_01.png`) as a wooden footbridge deck over
the blue water tile beneath it.

> The Bridge is **not** a terrain type — it is a building on the building layer; the WATER
> terrain underneath is unchanged (demolishing the bridge restores impassable water).
> `env_tile_bridge_v_01.png` (the rotated/vertical deck) is currently **unused** — kept for a
> future orientation pass (pick H/V by the bridged tile's water-neighbour axis).

## Verbindliche Stil-Orientierungen (DNA aller Projekt-Prompts)

**Perspektive:** Objekte (inkl. dieses Deck) leicht erhöhter Winkel ~60–70° über dem
Horizont ("classic top-down RPG perspective"). Boden-Tiles strikt von oben — hier rendert
das **Wasser** auf dem Hintergrund-Layer und das **Deck** als transparentes Objekt darüber,
daher pixen (transparenter Hintergrund), nicht `create-tiles-pro`.

**Konsistenz:** Lichtquelle oben-links, Schatten nach unten-rechts. Erdige, gedämpfte
Palette (verwittertes Holz), keine Neonfarben. 2–3 Schattierungsstufen pro Farbe. Keine
Outline um das gesamte Objekt — nur interne Tiefenlinien.

**Komposition:** Das Deck ist das **einzige** Objekt im Bild und spannt entlang einer Achse
von Kante zu Kante (verbindet die beiden Ufer). **Kein Wasser, kein Boden ins Tile backen** —
der gesamte Hintergrund ist 100 % transparent (Alpha 0). Das blaue Wasser kommt allein vom
Hintergrund-Layer darunter (siehe Render-Integration). Frühere Versuche, das Wasser in den
Prompt zu schreiben, führten zu gebackenem Wasser + Gischt im Tile (unruhig) — daher hier
strikt nur das Holzdeck.

## Render-Integration

- Die Brücke ist ein **Gebäude** (`BuildingType.BRIDGE`). Das Deck-Sprite (transparenter
  Hintergrund) wird vom Building-Layer (`building_indicator_layer.add_building`) 64×64 zentriert
  über dem `WATER`-Tile gezeichnet; das blaue Wasser darunter kommt vom Terrain-Layer
  (`Color(0.18,0.45,0.70)`-Fallback). Deshalb muss das Deck transparent sein (kein gebackenes
  Wasser).
- Platzierung nur auf Wasser: `WorldGrid.validate_water_placement` /
  `place_building_on_water`; passierbar via `MOVEMENT_EFFICIENCY[BRIDGE] = 0.5`.
- `env_tile_bridge_h_01.png` ist die genutzte Textur (`BUILDING_TEXTURES[BRIDGE]`). Die
  vertikale Variante (90°-Rotation via `generate_water_bridge_assets.py`) ist derzeit
  ungenutzt — Reserve für eine spätere Orientierungs-Logik.

---

### 1. Holzbrücke (horizontal) / Wooden Footbridge (horizontal) — `env_tile_bridge_h_01.png`

Ein schmales Holzplanken-Deck, das den Tile von der linken zur rechten Kante überspannt;
oben/unten transparent (Flusskanal).

**Prompt:**
```
Top-down RPG object on a fully transparent background. A simple horizontal wooden plank
footbridge deck running straight from the left edge to the right edge of the frame. Two
parallel wooden stringer beams run left-to-right, with short transverse planks laid across
them forming the walkway, and low wooden side railings along the top and bottom long edges.
The bridge deck is the ONLY thing in the image. Weathered brown timber, light source
upper-left, soft shadows lower-right. Earthy muted palette, 2-3 shading levels per colour,
no outline around the whole object, only internal plank and depth lines. NO water, NO river,
NO ground, NO background scenery whatsoever - the entire area around, above and below the
deck is 100% transparent (alpha zero).
```

**Zielfarben:** Planke-Highlight `#B08A52` · Planke-Mitte `#8A6638` · Planke-Schatten
`#5C4322` · Geländer `#9A7240` · Träger-Schatten `#4E3818`
**Hintergrund:** Transparent (Wasser scheint durch)

### 2. Holzbrücke (vertikal) / Wooden Footbridge (vertical) — `env_tile_bridge_v_01.png`

Identisches Deck, 90° rotiert (spannt oben↔unten). **Nicht separat generiert** — per
Pillow-Rotation aus Variante 1 abgeleitet.

---

## Atlas-Assembly & nächste Schritte

1. `python3 assets/art/ai-prompts/generate_water_bridge_assets.py` (pixen, 64×64; Key aus
   `~/.pixellab_key`).
2. PNGs landen in `assets/art/tiles/env_tile_bridge_h_01.png` + `_v_01.png`.
3. Import-Settings: Filter = Nearest, Mipmaps = Disabled (`.import`-Sidecars entstehen beim
   nächsten Editor-Scan automatisch).
4. Im Editor gegen die Art Bible prüfen; bei Stil-Abweichung mit präzisierter `description`
   neu generieren (`/fix-asset bridge_h '<Fehler>'`).
