# Refactoring-Plan: Code-Konsolidierung & Modularisierung

| Feld | Wert |
|------|------|
| **Datum** | 2026-06-13 |
| **Status** | Phase 5 ABGESCHLOSSEN (2026-06-14) — Phasen 1–5 umgesetzt + in Godot verifiziert. map_root.gd 1929 → 250 Z. (−87 %), God-Object in 6 fokussierte Komponenten zerlegt. DragController inkrementell in 9 verifizierten Chunks extrahiert. NOCH OFFEN: Phase 6 (Asset-Move, am besten im Editor) + assets/ui-Dangling-Bug. |
| **Umsetzungs-Log** | 2026-06-13: P1 TextureFactory+PathGeometry, P2 world_to_tile, P3 data-driven glyph/world-icon, P4 UiPalette+StyleFactory+Grids (kein StyleBoxFlat.new mehr in Grids), P5 TerrainRenderer + BuildingIndicatorLayer (map_root 1929→1569 Z., −19 %). Rest = verzahnter Drag/Transport/Badge-Kern, pausiert bis Godot-Verifikation. Suite NICHT per Godot verifiziert (kein lokales Binary). |
| **Auslöser** | Systeme über Zeit gewachsen; `map_root.gd` (1929 Z.) ist God-Object, mehrfach duplizierte Helfer, hartcodierte Daten |
| **Engine** | Godot 4.6 / GDScript |
| **Ziel** | Übersicht & Wartbarkeit ohne Verhaltensänderung (reines Refactoring) |

> **Leitprinzip:** Jede Phase ist einzeln auslieferbar und durch die bestehende
> Test-Suite (bzw. neue Unit-Tests für extrahierte Pure-Functions) absicherbar.
> Reihenfolge: **risikoarm → risikoreich**. Kein Phasen-Merge ohne grüne Tests.
> Verhalten bleibt identisch — nur Struktur ändert sich.

---

## 1. Executive Summary

Die Codebasis (16.420 Z. GDScript) hat sich auf wenige Dateien konzentriert. Vier
Problemklassen mindern Wartbarkeit:

1. **God-Object `map_root.gd` (1929 Z.)** bündelt ~6 unabhängige Verantwortlichkeiten.
2. **Echte Code-Duplikate** (Textur-/Geometrie-Helfer) liegen 2–3× identisch vor.
3. **Hartcodierte Präsentationsdaten** (Resource-Icon-Pfade, Emoji-Maps) verletzen
   den Projekt-Standard „Gameplay values must be data-driven" und sind inkonsistent.
4. **UI-Copy-Paste**: 4 nahezu identische Grid-Komponenten, ~40 verstreute
   `StyleBoxFlat.new()`, eine über Magic-Color-Literale dupliziert Palette.

Der Plan führt **fünf neue, klar abgegrenzte Module** ein und zerlegt das God-Object
in fokussierte Szenen-Komponenten. Geschätzte Netto-Reduktion: `map_root.gd` von
1929 → ~500–600 Z. (reiner Koordinator), Eliminierung von ~250 Z. Duplikaten.

---

## 2. Befunde (mit Belegen)

### 2.1 God-Object `src/scenes/map_root.gd` (1929 Z.)

Funktions-Cluster nach Verantwortlichkeit (Zeilen aus aktuellem Stand):

| Cluster | Funktionen | ca. Zeilen |
|---------|-----------|-----------|
| **Terrain-Tileset-Bau** | `_setup_tilesets`, `_build_terrain_tileset`, `_make_solid_tile`, `_make_tileset`, `_sync_tilemap`, `_terrain_type_to_atlas` + Konst. `_TERRAIN_PNG_VARIANTS`, `_TERRAIN_FALLBACK_COLORS`, `_terrain_type_offsets/_variant_counts` | ~150 |
| **Resource-Badges/Icons** | `_spawn_resource_badges`, `_spawn_badge`, `_random_icon_positions`, `_make_resource_icon_node`, `_load_resource_texture`, `_resource_id_to_index` + Konst. `_RESOURCE_PNG`, `_RESOURCE_FALLBACK_COLORS`, `_RESOURCE_ICON_SCALE`, `_ICON_SCALE_BY_COUNT` | ~150 |
| **Drag & Drop (Welt + Storage/Input/Output)** | `_setup_drag_overlays`, `_update_drag_overlays`, `_update_storage_drag_overlays`, `_on_*_drag_started` (3×), `_finish_*_drag` (3×), `_pay_drag_cost`, `_calc_drag_ticks`, `_cancel_drag_visual`, `_snap_back_drag_icon`, `_reset_drag_icon_visuals`, `_try_batch_collect`, `_restore_batch_extras`, `_hit_test_resource_icon`, `_park_panel_icon_pending` + alle `_drag_*`-Vars + `_PATH_*`/`_HOLD_*`-Konst. | **~700** |
| **Pending-Transports** | `_advance_pending_transports`, `_spawn_transport_indicator`, `_spawn_pending_path_overlay`, `_animate_pending_path_overlay`, `_free_pending_path_overlay` + `_pending_transports` | ~120 |
| **Building-Indikatoren** | `_spawn_action_indicator`, `_refresh_indicator`, `_on_building_state_changed`, `_building_indicators`, `_action_indicator` | ~80 |
| **Pfad-/Textur-Geometrie-Helfer** | `_path_length`, `_point_along_path`, `_make_circle_texture`, `_make_tile_highlight_texture` | ~60 |
| **Koordinator / Signal-Wiring** (legitim hier) | `_ready`, `_process`, `_input`, `_unhandled_input`, `_on_*` Handler, `_wire_*` | Rest |

### 2.2 Echte Duplikate über Dateien hinweg

| Funktion | Vorkommen |
|----------|-----------|
| `_make_circle_texture(radius, color)` | `map_root.gd:1047`, `npc_overlay.gd:260`, `route_lines.gd:535` — **3× identisch** |
| `_path_length(path)` | `map_root.gd:1029`, `route_lines.gd:585` — **2× identisch** |
| `_point_along_path(path, t)` | `map_root.gd:1036`, `route_lines.gd:592` — **2× identisch** |
| `_load_resource_texture(...)` | `map_root.gd:1061` (idx), `route_lines.gd:524` (id) — 2× ähnlich |
| Tile-Konversion `terrain_layer.local_to_map(terrain_layer.to_local(world_pos))` | `map_root.gd` **7×** (Z. 1000, 1107, 1120, 1131, 1164, 1269, …) obwohl `grid.world_to_tile()` (`world_grid.gd:542`) existiert |

### 2.3 Hartcodierte Präsentationsdaten (Standard-Verstoß)

- `map_root.gd:354 _RESOURCE_PNG` — feste Icon-Pfade, dupliziert das bereits
  data-driven gepflegte `_ResourceDefinition.icon_path` (`resource_registry.gd:23`,
  Quelle `data/resources.json`).
- `item_grid.gd:159 _resource_icon` und `building_grid.gd:145 _resource_emoji` —
  Emoji-`match` **2×** und **inkonsistent**: `building_grid` mappt `food`/`iron`,
  die in `resources.json` nicht existieren; `item_grid` mappt `berry`/`fiber`/`tool`.
  Ebenso `crafting_grid.gd:147`.
- `building_grid.gd:154 _building_icon` — Gebäude-Emoji ebenfalls hartcodiert.

### 2.4 UI-Copy-Paste

- **4 Grid-Komponenten** `item_grid` / `building_grid` / `crafting_grid` / `npc_grid`
  teilen Skelett (`_flow`, `_empty_label`, `_ready`, `populate`, `_make_block`) und
  Konstanten `BLOCK_WIDTH/HEIGHT/GAP`, `ICON_SIZE`, sowie identische Palette
  `COLOR_BLOCK_BG=#2a2a2a`, `COLOR_BLOCK_BORDER=#4a4a4a`, `COLOR_HOVER_BORDER=#A8A49C`,
  `COLOR_*_TEXT=#F0EDE6`.
- `StyleBoxFlat.new()` ~40× verteilt (`building_detail_panel` 7, `transportation_panel`
  10, `npc_detail_panel` 5, `draggable_window` 4, …).
- `_build_separator` 3× (`building_detail_panel:1480`, `npc_detail_panel:655`,
  `transportation_panel:1308`).
- Magic-Color-Literale (z. B. `Color(0.94, 0.93, 0.9, 1)` 10×) statt benannter Palette.

### 2.5 NICHT zu vereinheitlichen (bewusst getrennt lassen)

- `PathSystem` (Pfad-Tile-Netz, Bitmask-Autotiling) vs. `LogisticsPathfinder` (A*)
  lösen verschiedene Probleme — **keine** Duplikation, nicht zusammenlegen.
- Distanz-Helfer sind bereits in `WorldGrid` zentralisiert (`manhattan_dist`,
  `euclidean_dist`, `distance_between`) — gut, beibehalten.

---

## 3. Ziel-Architektur

### 3.1 Neue Verzeichnisse / Module

```text
src/
├── util/                          # NEU — reine, zustandslose Helfer (static funcs)
│   ├── texture_factory.gd         # class_name TextureFactory
│   └── path_geometry.gd           # class_name PathGeometry
├── ui/
│   ├── ui_palette.gd              # NEU — class_name UiPalette (Farb-/Maß-Konstanten)
│   ├── style_factory.gd           # NEU — class_name StyleFactory (StyleBoxFlat-Builder)
│   └── components/
│       └── icon_block_grid.gd     # NEU — Basisklasse für die 4 Grids
└── scenes/
    └── map_root/                  # NEU — God-Object-Zerlegung in Szenen-Komponenten
        ├── terrain_renderer.gd    # class_name TerrainRenderer
        ├── resource_badge_layer.gd
        ├── drag_controller.gd
        ├── transport_overlay.gd
        └── building_indicator_layer.gd
```

### 3.2 Modul-Verantwortlichkeiten

**`TextureFactory` (static)** — ersetzt alle prozeduralen Textur-Erzeuger:
```gdscript
static func circle(radius: int, color: Color) -> ImageTexture
static func solid_tile(tile_px: int, color: Color) -> Image
static func tile_highlight(tile_px: int, color: Color, border: Color) -> ImageTexture
```
Aufrufer: `map_root`, `npc_overlay`, `route_lines`, neue Layer-Komponenten.

**`PathGeometry` (static)** — Polyline-Mathematik:
```gdscript
static func length(path: Array[Vector2]) -> float
static func point_along(path: Array[Vector2], t: float) -> Vector2
```
Aufrufer: `map_root`/`drag_controller`/`transport_overlay`, `route_lines`.

**`ResourceRegistry` (Erweiterung, kein neues Modul)** — Präsentation data-driven:
```gdscript
func get_icon_texture(id: StringName) -> Texture2D   # cached, aus icon_path
func get_glyph(id: StringName) -> String             # Emoji/Fallback aus neuem JSON-Feld "glyph"
```
- Neues optionales Feld `"glyph"` in `data/resources.json` (Fallback `📦`).
- Ersetzt `_RESOURCE_PNG`, `_resource_icon`, `_resource_emoji`, `_resource_id_to_index`.
- Gebäude-Emoji analog: optionales `glyph` in der `BUILDING_TEXTURES`/Metadaten von
  `BuildingRegistry` (oder neue kleine Map dort), ersetzt `_building_icon`.

**`UiPalette` (Konstanten)** — eine Quelle der Wahrheit für Farben/Maße:
```gdscript
const BLOCK_BG := Color("#2a2a2a")
const BLOCK_BORDER := Color("#4a4a4a")
const HOVER_BORDER := Color("#A8A49C")
const TEXT_PRIMARY := Color("#F0EDE6")
const TEXT_DIM := Color("#A8A49C")
const ICON_SIZE := 48
# … weitere wiederkehrende Werte aus 2.4
```

**`StyleFactory` (static)** — typisierte StyleBox-Builder:
```gdscript
static func block(bg: Color, border: Color, width := 1) -> StyleBoxFlat
static func panel(bg: Color, radius := 6) -> StyleBoxFlat
static func separator() -> Control   # ersetzt die 3× _build_separator
```

**`IconBlockGrid extends VBoxContainer` (Basisklasse)** — gemeinsames Grid-Skelett
(`_flow`, `_empty_label`, `_ready`, `populate`-Template, Hover-Logik). Die 4
konkreten Grids überschreiben nur `_make_block()` und ihr spezifisches Signal.

**`map_root/`-Komponenten** — jede ist ein eigener Node, von `MapRoot` als Kind
instanziiert; `MapRoot` wird zum schlanken Koordinator, der Abhängigkeiten injiziert
und Signale verdrahtet (DI-Muster wie bei den Autoload-Registries).

---

## 4. Phasen (geordnet: risikoarm → risikoreich)

> Jede Phase endet mit grüner Test-Suite. Phasen 1–4 sind reine Extraktionen ohne
> Verhaltensänderung; Phase 5 ist die strukturelle Großoperation.

### Phase 1 — Pure-Function-Utilities (RISIKO: niedrig)
**Ziel:** Duplikate aus 2.2 eliminieren.
1. `src/util/texture_factory.gd` anlegen, Inhalt aus `map_root._make_circle_texture`
   etc. übernehmen.
2. `src/util/path_geometry.gd` anlegen aus `_path_length`/`_point_along_path`.
3. Aufrufer in `map_root`, `npc_overlay`, `route_lines` auf die neuen `static`-Calls
   umstellen; lokale Kopien löschen.
4. **Neue Unit-Tests**: `tests/unit/util/texture_factory_test.gd`,
   `tests/unit/util/path_geometry_test.gd` (deterministische Pure-Functions —
   ideal testbar: Länge einer bekannten Polyline, Mittelpunkt bei t=0.5).
**Akzeptanz:** Keine `_make_circle_texture`/`_path_length`-Definition außerhalb `util/`.

### Phase 2 — Tile-Konversion vereinheitlichen (RISIKO: niedrig)
**Ziel:** 2.2 letzte Zeile.
1. Alle 7 `terrain_layer.local_to_map(terrain_layer.to_local(world_pos))` in
   `map_root.gd` durch `grid.world_to_tile(world_pos)` ersetzen.
2. Verifizieren, dass Offsets identisch sind (TileMapLayer-Transform vs. WorldGrid-Formel
   — falls Abweichung, vorher angleichen und in diesem Plan vermerken).
**Akzeptanz:** Kein direkter `local_to_map(to_local(...))`-Aufruf mehr in `map_root`.

### Phase 3 — Präsentationsdaten data-driven (RISIKO: niedrig–mittel)
**Ziel:** 2.3 auflösen, Standard-Verstoß beheben.
1. Feld `"glyph"` in `data/resources.json` ergänzen (alle Ressourcen).
2. `ResourceRegistry.get_glyph()` + `get_icon_texture()` (mit Cache) implementieren.
3. `_RESOURCE_PNG`, `_resource_id_to_index`, `_load_resource_texture` (map_root) sowie
   `_resource_icon`/`_resource_emoji` (3 Grids) entfernen → Registry-Aufrufe.
4. Gebäude-Glyphen analog über `BuildingRegistry`.
5. **Test:** `resource_registry_test` um `get_glyph`/Fallback erweitern.
**Akzeptanz:** Keine Emoji-/Icon-Pfad-`match`-Tabelle mehr in UI- oder Scene-Code.
**Hinweis:** Inkonsistenz `food`/`iron` (existieren nicht) dabei bereinigen.

### Phase 4 — UI-Konsolidierung (RISIKO: mittel) — KERN ✅ / Rest ⏸️
**Ziel:** 2.4 auflösen. (Schritte 1, 3 + Palette-Zentralisierung umgesetzt 2026-06-13;
`IconBlockGrid` und vollständige Panel-Farbliteral-Migration noch offen.)
1. `UiPalette` + `StyleFactory` anlegen.
2. `IconBlockGrid`-Basisklasse extrahieren; `item_grid`/`building_grid`/`crafting_grid`/
   `npc_grid` darauf umstellen (nur `_make_block` bleibt spezifisch).
3. `_build_separator` (3×) durch `StyleFactory.separator()` ersetzen.
4. Magic-Color-Literale in den Panels schrittweise auf `UiPalette` umstellen
   (panel-weise, je ein Commit, visuell per Screenshot prüfen — UI-Gate ist ADVISORY).
**Akzeptanz:** `StyleBoxFlat.new()` nur noch in `StyleFactory`; Grid-Konstanten nur
noch in `UiPalette`/Basisklasse.

### Phase 5 — `map_root.gd` God-Object zerlegen (RISIKO: hoch) — BEGONNEN
**Ziel:** 2.1 auflösen. Reihenfolge nach Kopplung (lose zuerst):
1. ✅ **`TerrainRenderer`** (`src/scenes/map_root/terrain_renderer.gd`) extrahiert
   2026-06-13: Tileset-Bau + Tilemap-Sync + Atlas-Varianten + die 80 `_TERRAIN_PNG_VARIANTS`-
   Pfade. `map_root` ruft nur noch `build_and_assign()`/`sync()`. map_root 1843 → 1653 Z.
   (unverifiziert — Godot-Lauf ausstehend).
2. ✅ **`BuildingIndicatorLayer`** (`src/scenes/map_root/building_indicator_layer.gd`)
   extrahiert 2026-06-13: Gebäude-Sprites + Status-Indikatoren + `_building_texture_path`/
   `_building_has_valid_input`/`_SKELETON_MODULATE`. MapRoot delegiert die `_on_building_*`-
   Handler. map_root 1653 → 1569 Z. (unverifiziert).
3a. ✅ **`PathDotOverlay`** (`src/scenes/map_root/path_dot_overlay.gd`) extrahiert
   2026-06-13: beheimatet die geteilten `_PATH_*`-Render-Konstanten und dedupliziert
   den L-Pfad-Builder (3× → `l_path`, auch route_lines) + die Punkt-Verteilung
   (`place_dots`) + das Drag-Pfad-Rendering (`render`, 2× identische ~25-Z.-Blöcke).
   Löst den „geteilte Konstanten"-Blocker. Tests: tests/unit/util/path_dot_overlay_test.gd.
   map_root 1569 → 1484 Z.
3b. ✅ **`ResourceBadgeFactory`** (`src/scenes/map_root/resource_badge_factory.gd`)
   extrahiert 2026-06-13: reine Badge-Icon-Konstruktion (`build_icon_node`/`world_texture`/
   `icon_positions`/`icon_px_for_count`) + die Icon-Skalierungs-Konstanten. Dedupliziert
   **5** Icon-Builder (Badge-Loop, `_make_resource_icon_node`, 3 Drag-Start-Handler).
   map_root 1484 → 1400 Z.
3c. ✅ **`TransportOverlay`** (`src/scenes/map_root/transport_overlay.gd`) extrahiert
   2026-06-13: Indikator-/Pfad-Overlay-Node-Bau + Animation + Freigabe (`spawn_indicator`/
   `spawn_path_overlay`/`animate`/`free_overlay`, `parent`-Param). MapRoot behält den
   Transport-Lifecycle + Pause-Koordination (mit Action-Indikator verzahnt). map_root 1400 → 1332 Z.
3d. ✅ **`DragController`** (`src/scenes/map_root/drag_controller.gd`, 1079 Z.) — KOMPLETT (inkrementell
   in 9 Chunks, leaf-first, jeder in Godot verifiziert). Enthält die gesamte Welt-Interaktion:
   Drag-Zustandsmaschine, `_input`/`_unhandled_input`, `_process`-Drag-Anteil, `_resource_icons`,
   Transport-Lifecycle + Pause, Deposit, Badge-Spawning, Action-Indikatoren — plus der komplette
   **State-Block** (state-autark; nutzt `_root.` nur für Szenen-Infra grid/player/registry/hud/
   terrain_layer/add_child/on_tile_clicked). 3 tote Methoden dabei gefunden+entfernt.
   **map_root.gd: 1929 → 250 Z. (−87 %).** Phase 5 abgeschlossen.

> **Phase-5-Ergebnis (2026-06-14):** God-Object zerlegt in `src/scenes/map_root/`:
> TerrainRenderer (201) · BuildingIndicatorLayer (118) · PathDotOverlay (73) ·
> ResourceBadgeFactory (64) · TransportOverlay (82) · DragController (1079).
> map_root = 250 Z. schlanker Koordinator. Optionale Zukunft: DragController weiter
> aufteilen (Transport/ActionFeedback), JSON-Config für Effizienz-Konstanten (Story 005).

   (Historische Chunk-Reihenfolge, je Runde mit Godot-Verifikation:)
   Drag-Zustandsmaschine + `_input`/`_unhandled_input` + `_process`-Anteil + `_resource_icons`-
   Mutationen + Transport-Lifecycle/Pause + Deposit + Action-Indikator. **Nicht mechanisch
   trennbar:** `grid` 74×, `_registry` 21×, `_player` 14×, `_hud` 10× — vermischt über Drag-
   UND Nicht-Drag-Code. Extraktion = atomarer Umbau mit ~120 Member-Zugriffen auf eine
   `_root`-Referenz + Aufteilung der Node-Callbacks; braucht iterative Editor-Sitzung
   (verschieben → starten → fixen), nicht einen Blind-Edit. Wenn angegangen: leaf-first
   (`_pay_drag_cost`/`_calc_drag_ticks` → Deposit → Transport-Lifecycle → Drag-Overlays → Input).
   Endziel danach: map_root < ~600 Z.
   Ziel-API: `MapRoot` injiziert grid/registry/inventory; Controller emittiert Signale
   (`transport_requested`, `deposit_requested`) statt direkt in fremde Systeme zu schreiben.
4. `MapRoot` bleibt als Koordinator: Kinder instanziieren, DI, Signal-Routing.

**Stand 2026-06-13:** Die zwei sauber separierbaren Cluster (TerrainRenderer,
BuildingIndicatorLayer) sind extrahiert (map_root 1929 → 1569 Z., −19 %). Der Rest ist
der verzahnte Interaktionskern (Punkt 3) — bewusst pausiert bis Godot-Verifikation.
**Akzeptanz:** `map_root.gd` < ~600 Z., jede Komponente eine Verantwortlichkeit;
bestehende Integrationstests (`production_cycles`, `logistics/*`, `player_character/*`)
grün; manuelle Drag&Drop-Walkthrough-Evidenz in `production/qa/evidence/`.

### Phase 6 — Asset-Reorganisation (RISIKO: mittel)

**Problem:** Alle 121 Kunst-Assets liegen flach in `assets/art/tiles/` (Gebäude,
Terrain, Pfade, Resource-Badges, NPC-Icon, eine `.pxo`-Quelldatei gemischt).
Dateinamen-Präfixe (`bld_tile_`, `env_tile_`, `npc_icon_`) tragen die Typ-Info,
die eigentlich der Ordner tragen sollte.

**Befund (Scoping, Stand 2026-06-13):**
- Asset-Pfade werden **nur als String-Literale in Code/Daten** referenziert,
  **nicht** via `ext_resource`/UID in `.tscn`/`.tres`. Damit ist **keine**
  Szenen-/UID-Neuverdrahtung nötig — nur Pfad-Strings ändern.
- Referenz-Inventar (~119 Strings in 6 Dateien):
  | Datei | Vorkommen | Inhalt |
  |-------|-----------|--------|
  | `src/scenes/map_root.gd` | 81 | `_TERRAIN_PNG_VARIANTS` (Terrain-Varianten) |
  | `src/systems/path_system.gd` | 16 | `PATH_TEXTURES` (Pfad-Autotiles) |
  | `data/resources.json` | 12 | `world_icon_path` (5) + `icon_path` (7, s.u.) |
  | `src/gameplay/building_registry.gd` | 8 | `BUILDING_TEXTURES` |
  | `src/ui/components/npc_overlay.gd` | 1 | NPC-Icon |
  | `src/ui/hud/build_placement_overlay.gd` | 1 | (Vorschau-Textur) |
- **120 `.import`-Sidecars** müssen mit ihren PNGs mitwandern (Godot-Importcache).
- **Pre-existing Bug:** `icon_path` in `resources.json` zeigt auf
  `assets/ui/icons/resources/*.png`, die **nicht existieren** (`assets/ui/` fehlt).
  Deshalb greifen aktuell Glyph/Fallback. In dieser Phase mitbereinigen.

**Ziel-Struktur** (Dateinamen zunächst unverändert lassen — nur Ordner; optionale
Präfix-Entfernung als separater Folgeschritt, um Pfad-Churn zu trennen):
```text
assets/art/
├── buildings/    # bld_tile_*.png            (7)
├── terrain/      # env_tile_{empty,grass,sand,stone,tree,berry}_NN.png (96)
├── paths/        # env_tile_path_*.png        (11)
├── resources/    # env_tile_resource_*.png    (5)  — Welt-Badges
├── npc/          # npc_icon_*.png             (1)
├── sources/      # *.pxo (editierbare Quelldateien, nicht exportiert)
└── ai-prompts/   # sprite-prompts.md          (bestehend)
```

**Vorgehen — bevorzugt (sicher):**
1. **Im Godot-Editor** im FileSystem-Dock verschieben (Drag&Drop). Godot aktualisiert
   `.import`-Bindungen automatisch und hält UIDs stabil. PNG + `.import` wandern zusammen.
2. Danach die **String-Literale** in den 6 Dateien auf die neuen Pfade umstellen
   (Code lädt per Pfad, nicht per UID → muss manuell angepasst werden).
3. `assets/ui/icons/resources/`-Frage klären: entweder UI-Icons anlegen, oder
   `icon_path` auf die neuen `assets/art/resources/`-Pfade umbiegen.

**Vorgehen — alternativ (ohne Editor, riskanter):**
1. Pro Datei `git mv assets/art/tiles/X.png assets/art/<bucket>/X.png` **und**
   `git mv assets/art/tiles/X.png.import assets/art/<bucket>/X.png.import`.
2. Alle Pfad-Strings in den 6 Dateien aktualisieren.
3. Godot einmal öffnen → Reimport auslösen → Konsole auf „missing resource" prüfen.

**Reihenfolge-Hinweis:** Überschneidet sich mit Phase 5 (`TerrainRenderer` besitzt
künftig `_TERRAIN_PNG_VARIANTS`; `ResourceBadgeLayer` die Resource-Pfade). Effizient:
Asset-Move **vor** der jeweiligen Phase-5-Extraktion, oder beides je Cluster zusammen.

**Akzeptanz:** `assets/art/tiles/` existiert nicht mehr; alle Pfad-Strings zeigen auf
neue Ordner; Godot startet ohne „missing resource"-Fehler; Spiel rendert Tiles/Gebäude/
Badges korrekt (Screenshot-Evidenz). **Erfordert Godot-Verifikation.**

---

## 5. Risiken & Gegenmaßnahmen

| Risiko | Gegenmaßnahme |
|--------|---------------|
| Kein lokales Godot-Binary → Suite nicht ausführbar (siehe active.md) | Vor Phase 5 Godot-Lauf sicherstellen; Phasen 1–3 sind unit-testbar und niedrigrisiko |
| Drag&Drop-Verhalten subtil ändern | `DragController` zuletzt; vorher manuelle Referenz-Walkthrough-Doku aufnehmen, danach 1:1 vergleichen |
| TileMapLayer- vs. WorldGrid-Koordinaten-Offset (Phase 2) | Vorab numerisch verifizieren; bei Abweichung eigener Commit |
| UI-Farbangleich verändert Look | Panel-weise Commits + Screenshot-Vergleich (Gate ADVISORY) |
| Scope-Creep | Abschnitt 2.5 strikt respektieren; Pathfinder NICHT zusammenlegen |

## 6. Out of Scope (bewusst nicht Teil dieses Plans)

- Zusammenlegung von `PathSystem` und `LogisticsPathfinder` (verschiedene Aufgaben).
- Gameplay-/Balance-Änderungen jeglicher Art.
- Effizienz-Konstanten → JSON (separate Tech-Debt: Story 005).
- `recipes.json`-Registry (separates Designziel).

## 7. Reihenfolge-Empfehlung für Umsetzung

`Phase 1 → 2 → 3 → 4 → 5`. Phasen 1–3 können in einer Sitzung erledigt und committet
werden (geringes Risiko, hoher Aufräum-Nutzen). Phase 4 als eigene Sitzung. Phase 5
nur mit lauffähiger Test-Suite und ausreichend Kontext-Budget starten (Heavy-Task,
ggf. pro Komponente eine eigene `/clear`-Sitzung mit Bezug auf diese Datei).

---

## Anhang A — Betroffene Dateien (Übersicht)

**Neu:** `src/util/texture_factory.gd`, `src/util/path_geometry.gd`,
`src/ui/ui_palette.gd`, `src/ui/style_factory.gd`,
`src/ui/components/icon_block_grid.gd`, `src/scenes/map_root/*.gd` (5 Dateien),
zugehörige Tests unter `tests/unit/util/`.

**Geändert:** `src/scenes/map_root.gd` (stark), `src/ui/components/route_lines.gd`,
`npc_overlay.gd`, `item_grid.gd`, `building_grid.gd`, `crafting_grid.gd`,
`npc_grid.gd`, `building_detail_panel.gd`, `transportation_panel.gd`,
`npc_detail_panel.gd`, `draggable_window.gd`, `src/systems/resource_registry.gd`,
`src/gameplay/building_registry.gd`, `data/resources.json`.

**Begleitend:** ADR-Eintrag in `docs/architecture/` (neue `util/`- und
`ui/`-Konventionen dokumentieren), Eintrag im Technical-Preferences-Architektur-Log.
