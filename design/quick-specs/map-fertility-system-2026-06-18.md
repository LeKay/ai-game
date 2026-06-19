# Quick Spec — Map Fertility System

> **Status**: Planning (pre-GDD)
> **Author**: User + Claude
> **Created**: 2026-06-18
> **Scope**: Implementation plan, no tests. Intended to grow into `design/gdd/map-fertility-system.md`.
> **Engine**: Godot 4.6 / GDScript

## Overview

Each map has a **fertility set** — the special resources that can exist or be exploited there. A
new map rolls **3 random** entries from the fertility pool; the **starting map is fixed** to all
three current entries: **clay, wheat, wild**. The game currently runs a single map
(`map_root.gd:89` `grid.generate(randi())`), so fertility becomes a property of that map now,
structured so a future multi-map system simply rolls a different set. Map-switching itself is out
of scope.

Three special resources, each with distinct discovery/behaviour:
- **Wheat** — visible crop; present at generation and/or found as seeds on normal fields. Seeds are
  transportable but only *plantable* on a wheat-fertile map.
- **Clay** — hidden at generation; found via a new **Search** action that reports distance to the
  nearest deposit and reveals clay when searched on its exact tile.
- **Wild (game)** — dynamic; lives in forests (≥10 contiguous tree tiles), marked with a small deer
  icon, moves/spawns daily. Feeds a new **Hunting Lodge** whose efficiency scales with the number of
  wild groups in the adjacent forest.

### Fertility pool (v1)

`FERTILITY_POOL = [clay, wheat, wild]` → starting map = all three (pool size == 3). The roll-3-of-N
logic is written now but only bites once the pool grows beyond 3.

## New data & assets (do first)

`data/resources.json` (+ AI prompts in a new `assets/art/ai-prompts/` file):

| id | category | notes |
|----|----------|-------|
| `clay` | production_good / raw_material | non-clearable node (like stone) once revealed |
| `wheat` | consumable / food | crop resource on `WHEAT` tiles |
| `wheat_seed` | production_good / raw_material, `plantable` | gated by fertility on plant |
| `meat` ("Meat") | consumable / food | Hunting Lodge output |
| `hide` | production_good / raw_material | Hunting Lodge output (→ future leather chain) |

Tiles/icons: clay node, wheat crop, meat icon, hide icon, **deer marker** (small, drawn in
tile corner), **hunting lodge** building tile.

**Generation method note:** the **ground tiles** for the new terrain types — **clay pit**
(`env_tile_clay_NN.png`) and **wheat field** (`env_tile_wheat_NN.png`) — are edge-to-edge
tileable terrain, so they are generated via the PixelLab **top-down tileset endpoint**
(`POST /v2/create-tileset`, async: `tile_size {64,64}`, `view "high top-down"`,
`detail "highly detailed"`, `lower_description == upper_description` for flat variations —
the web-UI labels "square / 90° / thickness 0 %" map onto these), **not** the pixen single-image
endpoint. The endpoint returns **16 tiles** (`tileset.tiles[].image.base64`), all of which are
saved and wired into
`src/scenes/map_root/terrain_renderer.gd` → `_TERRAIN_PNG_VARIANTS`, exactly like the existing
tree/berry/grass tiles (16 variants each). The centered overlay/UI icons (resource icons, seed,
meat, hide, deer marker, lodge) stay on the pixen endpoint. See the `add-production-chain` skill
§3d and `assets/art/ai-prompts/fertility-prompts.md`.

## Detailed plan by component

### 1. Map Fertility core (`WorldGrid`)

- Add `_fertility: Array[StringName]`, set in `generate()`.
- `generate(world_seed, fertility_override := [])`: starting map passes `[clay, wheat, wild]`;
  otherwise deterministically roll 3 from `FERTILITY_POOL` using `world_seed`.
- API: `has_fertility(id) -> bool`, `get_fertility() -> Array`.
- Extend `serialize()/deserialize()` (the save anchor) with `_fertility`.
- Generation order: terrain → fertility → wheat placement → hidden clay placement → wild seeding
  (each gated by `has_fertility`).

**HUD indicator**: the map's 3 fertilities are shown as small **circles in the top-right corner,
just under the HUD**, each circle displaying that resource's icon (clay / wheat / wild). Read-only
status display, built from `WorldGrid.get_fertility()`; refresh on load.

### 2. Wheat

- New `WorldGrid.TileType.WHEAT` (parallels `GRASS`); add to `TERRAIN_RESOURCE_INIT` (→ `wheat`)
  and `SEED_GROWTH_TICKS`. Ground rendered from `env_tile_wheat_NN.png` variants (tileset endpoint)
  wired into `terrain_renderer.gd` `_TERRAIN_PNG_VARIANTS` + `_TERRAIN_FALLBACK_COLORS`.
- **Generation** (if wheat-fertile): convert a few `EMPTY`/low-moisture tiles to `WHEAT`, reusing
  the minimum-count / `_force_fix_minimums` pattern.
- **Wheat seeds**: a harvest byproduct of WHEAT tiles, exactly like other seeds
  (`SEED_BYPRODUCT_CHANCES`: `HARVEST_WHEAT` 5%, `CLEAR_WHEAT` 20% → `wheat_seed`). NOT tied to the
  clay Search.
- **Planting gate**: `WorldGrid.plant_seed()` and `PlayerCharacter.try_start_plant_seed` reject
  `wheat_seed` unless `has_fertility(&"wheat")`. This single rule is what makes fertility matter.
- UI: add wheat to the plantable list (`tile_interaction_panel.gd:263`).

### 3. Clay — hidden resource + Search action

- **Hidden layer** in `WorldGrid`: `_hidden_resources: Dictionary` (tile → resource_id). Not
  rendered, not in the visible resource layer. Serialized.
- **Generation** (if clay-fertile): scatter `CLAY_DEPOSIT_COUNT` hidden clay deposits on passable
  tiles (deterministic from `world_seed`).
- **Search tile action** (player action via `tile_interaction_panel` → `PlayerCharacter`):
  - Hidden clay on this tile → **reveal** it via `add_resource_to_tile`, **only if the tile has no
    other resource** (requirement: any other resource must be cleared first; otherwise report
    "clear this tile first" and clay stays hidden).
  - Otherwise → report **Manhattan distance to nearest hidden clay** via a hidden-layer variant of
    the existing expanding-radius `find_nearest()` (`world_grid.gd:674`). Shown as a floating label /
    in the interaction panel.
  - Search is clay-only; wheat seeds come from harvesting WHEAT tiles (§2), not from Search.
- Revealed clay = non-clearable node. Downstream consumer (brickworks/clay use) is **out of scope** —
  listed as a dependency.
- Visual: a revealed deposit renders as a **clay-pit ground tile** (`env_tile_clay_NN.png` variants
  via the tileset endpoint) → needs `WorldGrid.TileType.CLAY` + `terrain_renderer.gd` wiring
  (Touch-list #19/#20). The small `env_tile_resource_clay.png` overlay icon is the carry/UI icon.

### 4. Wild — dynamic forest system

New autoload **`WildSystem`** (`src/systems/wild_system.gd`; register in Project Settings →
Autoload and in `.claude/rules/godot-singletons.md`). Grid injected like `LogisticsSystem`/`NPCSystem`.

**Forest analysis**
- Connected components of `TileType.TREE`, **4-way** adjacency (matches `_cleanup_clusters`). Each
  component = a forest (id + member tiles).
- Recompute lazily: on init, on `WorldGrid.terrain_tile_changed` (trees cleared/grown), and once per
  day before the wild update.
- A forest is **wild-eligible** when `size >= FOREST_MIN_TILES` and `has_fertility(&"wild")`.

**Wild groups**
- `WildGroup = { forest_id, tile }`. Capacity per forest = `floori(size / TILES_PER_GROUP)`.
- **Daily update** on `TickSystem.day_transition`:
  1. Each wild-eligible forest under capacity: with `SPAWN_CHANCE`, add a group on a random member
     tile.
  2. Each group: with `MOVE_CHANCE`, move to a random adjacent **tree** tile (stays in-forest).
  3. Remove groups whose forest dropped below `FOREST_MIN_TILES`.
- **Save/reload**: serialize the actual group list (positions + forest ids) + next id. Reload
  restores exactly what the player saw (no reseed/recompute drift).

**Rendering**
- New overlay sibling to `building_indicator_layer` / `npc_overlay` under `map_root`: draws the deer
  icon in the corner of each tile holding a wild group. Refreshes on `WildSystem.wild_changed`.

**Query API**
- `forest_has_wild(tile) -> bool`
- `get_groups_in_forest_at(tile) -> int`

### 5. Hunting Lodge building (`BuildingRegistry`)

- New `BuildingType.HUNTING_LODGE`: cost, build time, energy, texture, recipe producing **both
  `meat` (food) and `hide` (raw material)** per cycle.
- **Placement rule** beyond plain `ADJACENCY_REQUIREMENTS` (terrain-type only): "adjacent to a forest
  tile that contains wild" — new branch in `_check_adjacency` calling `WildSystem.forest_has_wild()`
  on neighbours; reuses `PlacementResult.BLOCKED_BY_ADJACENCY`.
- **Efficiency from wild groups**: feed wild-group count as the scaling term into the existing
  additive model — `efficiency = 0.25 + wild_groups × WILD_GROUP_EFFICIENCY + worker_eff`
  (reuse `EfficiencyFormulas.calculate_building_efficiency` with `resource_tiles := wild_groups`).
  Recompute on `WildSystem.wild_changed`.
- v1: hunting does **not** deplete wild groups.

## Build order (each step independently shippable)

1. ✅ Resources + assets/prompts (`data/resources.json`, `assets/art/ai-prompts/fertility-prompts.md`).
2. ✅ Map fertility core in `WorldGrid` (+ serialize).
3. ✅ Wheat: `TileType.WHEAT`, generation, planting gate, UI.
4. ✅ Search action + hidden clay (reveal + distance). Wheat-seed = harvest byproduct of WHEAT tiles.
5. ✅ `WildSystem` (forest analysis + daily sim + serialize) + deer overlay.
6. ✅ Hunting Lodge (placement rule + group-scaled efficiency + recipe `meat`+`hide`).
7. ✅ Wire-up in `map_root.gd` (inject grid into `WildSystem`, add overlay, refresh hook) + ADR-0015.

**Implemented 2026-06-18.** Also done: tile/icon PNGs generated (pixen for icons, create-tiles-pro
for the 64×64 clay/wheat ground tiles), and the **fertility HUD indicator**
(`src/ui/components/fertility_indicator.gd`, top-right under the HUD; clay/wheat/game icons).
Remaining: the clay-consumer building. Godot runtime verification of the daily wild sim / lodge
placement still advisable via a playtest.

## Tuning knobs (defaults)

| Knob | Default |
|------|---------|
| `FERTILITY_POOL` / per-map count | `[clay, wheat, wild]` / 3 |
| `CLAY_DEPOSIT_COUNT` | 6 |
| `CLAY_SEARCH_MAX_RADIUS` | 30 |
| `FOREST_MIN_TILES` | 10 |
| `TILES_PER_GROUP` | 10 |
| `SPAWN_CHANCE` (per day) | 0.10 |
| `MOVE_CHANCE` (per day) | 0.50 |
| `WILD_GROUP_EFFICIENCY` (per group) | 0.10 |
| wheat-seed byproduct (harvest / clear) | 5% / 20% |

## Dependencies

- **WorldGrid** — new tile type, hidden layer, fertility, serialize (core anchor for all four).
- **TickSystem** — `day_transition` drives the daily wild sim.
- **BuildingRegistry / EfficiencyFormulas** — Hunting Lodge placement + group-scaled efficiency.
- **PlayerCharacter / tile_interaction_panel** — Search action, wheat planting gate.
- **WorldSaveManager** — serialize fertility, hidden clay, wild groups.
- **(Out of scope)** clay consumer building; multi-map switching.

## Decided defaults (2026-06-18)

1. Forest adjacency = **4-way**.
2. Hunting **does not deplete** wild in v1.
3. Revealed clay = **non-clearable node**; consumer building deferred.
4. Wild save/reload = **serialize group state** (no reseed/recompute).

## Open questions (for the GDD pass)

- Wheat: how much is placed at generation vs. found via search? Crop yield per tile.
- Clay: harvest model once a consumer exists (adjacency building vs. direct harvest).
- Wild: should very large forests cap total groups, or is `floor(size/10)` enough?
- Hunting balance: `meat` nutrition value and cycle time vs. existing food chains.
