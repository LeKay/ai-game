# ADR-0015: Map Fertility System (Wheat, Clay, Wild)

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-18 |
| **Deciders** | User + Claude |
| **Supersedes** | — |
| **Related** | ADR-0004 (Grid/Map Data Model), ADR-0008 (Building Placement/Production), ADR-0012 (Efficiency System) |
| **Design source** | `design/quick-specs/map-fertility-system-2026-06-18.md` |

## Context

Each map should support a small set of **special resources** ("fertilities"). A new map rolls 3
random fertilities from a pool; the starting map is fixed to **clay, wheat, wild**. The three
resources have distinct discovery/behaviour and touch the grid, tick, building, and efficiency
systems. The game currently runs a single map, so fertility is implemented as a property of the
live map, structured so a future multi-map mode only changes which set is rolled.

## Decision

### 1. Fertility as a WorldGrid property
`WorldGrid` owns `_fertility: Array[StringName]`, set in `generate(world_seed, fertility_override)`.
An override fixes the set (starting map → `STARTING_FERTILITY`); otherwise a deterministic
seed-driven Fisher–Yates shuffle of `FERTILITY_POOL` selects `FERTILITY_COUNT` (3). Exposed via
`has_fertility()` / `get_fertility()`, serialized with the grid.

### 2. Wheat — new terrain type, fertility-gated planting
`TileType.WHEAT` (appended last so existing enum ints are stable). Wheat fields are placed at
generation on wheat-fertile maps and seeds grow into `WHEAT` via the existing seed/growth path.
The defining rule: `wheat_seed` is transportable but only **plantable** where `has_fertility(&"wheat")`
— enforced in `PlayerCharacter.try_start_plant_seed` and hidden in the tile panel elsewhere.
Wheat seeds are obtained as a **harvest byproduct** of WHEAT tiles (`HARVEST_WHEAT` 5% /
`CLEAR_WHEAT` 20% via `SEED_BYPRODUCT_CHANCES`), exactly like tree/berry/grass seeds — not via the
clay Search. Generated wheat fields carry no resource overlays (terrain only).

### 3. Clay — hidden deposits + Search action
A separate `_hidden_resources` layer (tile → resource_id), not rendered. Placed at generation on
clay-fertile maps. The new **Search** action (`PlayerCharacter.survey_tile`, synchronous, small
energy cost) reports the Manhattan distance to the nearest hidden clay, or reveals it
(`reveal_hidden_clay` → `TileType.CLAY` pit) when searched on its exact tile — but only if any other
resource there has been cleared first. Search is clay-only.

### 4. Wild — `WildSystem` autoload
Forests are 4-connected `TREE` components. A forest ≥ `FOREST_MIN_TILES` (10) on a wild-fertile map
hosts wild groups, capacity `size / TILES_PER_GROUP`. Each day (`TickSystem.day_transition`) groups
may spawn (under capacity) and move to adjacent tree tiles; groups in shrunken forests are pruned.
Group state is **serialized**; forests are recomputed from terrain on load. Emits `wild_changed`.

### 5. Hunting Lodge — wild-gated placement + group-scaled efficiency
`BuildingType.HUNTING_LODGE` produces `game` + `hide` per cycle. Placement requires a neighbouring
forest that currently contains wild (`WildSystem.forest_has_wild_adjacent`, special-cased in
`_check_adjacency`). Efficiency reuses the additive model (ADR-0012) by feeding the adjacent
wild-group count as the `resource_tiles` term (+5%/group); recomputed on `wild_changed` via
`BuildingRegistry.refresh_wild_efficiency`.

## Consequences

- **Positive:** Fertility is one source of truth on the grid; wheat/clay reuse the existing
  terrain/seed/serialize machinery; wild is isolated in its own autoload; the lodge reuses the
  efficiency formula with no new math.
- **Enum stability:** `WHEAT`/`CLAY` are appended last; `terrain_renderer.gd` was extended with
  matching variant lists (`/create-tileset` assets) and fallback colours, so the atlas covers the
  new indices.
- **Determinism:** fertility roll, wheat fields and hidden clay are seed-deterministic; the daily
  wild simulation uses runtime RNG with serialized state (no replay drift on load).
- **HUD:** the fertility set is shown top-right under the HUD via
  `src/ui/components/fertility_indicator.gd` (clay/wheat/game icons in circles).
- **Deferred / out of scope:** clay-consumer building (brickworks) and multi-map switching.
  Tile/icon PNGs are generated (pixen for centered icons, create-tiles-pro for the 64×64
  clay/wheat ground tiles); code still falls back to colours/glyphs if an asset is missing.
- **Efficiency note:** group scaling is +5%/group (reused `ADJACENCY_EFFICIENCY_PER_TILE`), not the
  0.10 originally sketched in the quick-spec — folded into the existing additive formula for
  simplicity.
