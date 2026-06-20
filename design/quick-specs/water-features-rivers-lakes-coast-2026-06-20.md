# Quick Design Spec: Water Features — Rivers, Lakes & Coast

**Type**: Addition
**System**: Grid/Map System
**GDD Reference**: `design/gdd/grid-map-system.md`
**Date**: 2026-06-20
**Estimated Implementation**: ~5 hours (generator + rules + renderer + tests)

## Change Summary

Add a single new `WATER` terrain type and a water-carving stage to the map generation
pipeline. Water appears as three independently-shaped features: **rivers** (mandatory —
every map gets ≥1), **lakes** and **coast** (both optional, probabilistic). Water is
impassable and non-buildable. A water-adjacency query is added now to reserve a future
fishing/water-economy hook.

## Motivation

The current map is all dry land — terrain variety comes only from resource clusters.
Rivers, lakes and a coastline give each map a readable natural backbone, more interesting
build-planning (routing logistics around water), and the visual "this is a place" feeling
the Grid GDD's Player Fantasy calls for. Water also opens a future economy axis (fishing,
water-needing buildings) without committing to it now.

## Design Delta

The Grid GDD's generation pipeline is currently **5 steps**
(`design/gdd/grid-map-system.md`, "Procedural Generation Pipeline"):

> Step 1 Perlin sampling → Step 2 threshold segmentation → Step 3 smoothing →
> Step 4 cluster cleanup → Step 5 minimum-count verification

This spec inserts a **water-carving step between cleanup and verification**, and adds
`WATER` to the `TileType` enum:

> Step 4 cluster cleanup → **Step 4.5 carve water (coast → lakes → river)** →
> Step 5 verification **(now also checks land connectivity)**

`enum TileType { EMPTY, TREE, STONE, BERRY, GRASS, IMPASSABLE, WHEAT, CLAY, WATER }` —
`WATER` is appended last (ordinal 8) so all existing integer values and saves are unchanged.

## New Rules / Values

### Terrain rules for `WATER`

- **Impassable**: `is_passable(WATER) == false`; `get_tile_movement_cost(WATER) == INF`.
  NPCs and the player cannot enter water.
- **Non-buildable**: `validate_placement` on a water tile returns `BLOCKED_BY_IMPASSABLE`
  (reuse existing result — `PlacementResult` enum is not extended, so all its consumers
  stay valid).
- **No occupation**: dropping/moving resources onto water is rejected, same as
  `IMPASSABLE` (`add_resource_to_tile`, `move_one_resource`).
- **Implementation note**: introduce a small helper `_blocks_occupation(type)` returning
  `true` for `IMPASSABLE` or `WATER`, and route the three checks above through it so the
  two blocking types never drift apart.

### Generation — carving order & shapes

All three features write `WATER` into the working terrain array (same pattern as
`_smooth_terrain` / `_cleanup_clusters`). Each uses a dedicated, seed-offset RNG for
determinism (consistent with the existing `_*_SEED_OFFSET` convention).

1. **Coast** (optional, prob `coast_chance`): pick one random map edge; carve a band of
   depth `coast_depth` tiles inward, with a jagged inner boundary (per-row/column depth
   jitter of ±1) so it isn't a straight line.
2. **Lakes** (optional, prob `lake_chance`, up to `lake_count_max`): pick a random
   interior tile; randomized region-grow (frontier flood) until `lake_size` tiles are
   carved. Blobby, irregular.
3. **River** (mandatory, `river_count` ≥ 1): pick a start point on one edge and an end
   point on a **different** edge; trace a meandering walk that steps toward the target,
   with `river_meander_chance` probability of a perpendicular jog instead. Carve each
   visited tile (width `river_width`, default 1). The walk ends at the target edge (the
   river "flows off-map"). If a lake/coast already exists, the river may be biased to end
   at it (nice-to-have, not required).

### Land-connectivity guarantee (keeps the map playable)

Because water is impassable, a feature could sever the map. After carving, generation
enforces connectivity:

- **In the attempt loop** (alongside the minimum-count check): the largest passable
  connected component must cover ≥ `min_land_fraction` of all passable tiles. If not, the
  attempt fails and regeneration retries with the next seed (which also re-rolls water).
  Total water is also capped at `max_water_fraction`.
- **Force-fix fallback** (if all 5 attempts fail): `_ensure_connectivity()` — while more
  than one significant passable region exists, convert the `WATER` tiles on the shortest
  straight line between the two largest regions back to `EMPTY` (a natural land bridge /
  ford). Guarantees a fully connected, playable map even in the worst case. Tiny isolated
  passable pockets (< `min_pocket_size`) are flooded to `WATER` (cosmetic islets).

### Reserved economy hook (query only, no gameplay yet)

- Add `WorldGrid.is_water_adjacent(tile) -> bool` and
  `WorldGrid.get_water_adjacent_tiles() -> Array[Vector2i]` — passable land tiles
  orthogonally adjacent to ≥1 `WATER` tile.
- **Reserved, not implemented this pass**: a future `&"fish"` fertility / fishing-hut
  building. `FERTILITY_POOL` is **not** changed now (so existing balance/saves are
  untouched). A `# RESERVED:` comment documents the intended hook.

### Rendering

- `terrain_renderer.gd`: append an 8th entry to `_TERRAIN_PNG_VARIANTS` (`[]` →
  solid-color fallback for now) and to `_TERRAIN_FALLBACK_COLORS` (water blue, e.g.
  `Color(0.18, 0.45, 0.70)`). `sync()` already renders any non-EMPTY terrain, so water
  draws automatically over the sand background layer.
- **Asset follow-up (separate, not blocking)**: generate water tile variants (incl. simple
  shoreline edges) via PixelLab `/create-tileset` later.

### Serialization

No change needed — `serialize()`/`deserialize()` store raw terrain ints, so `WATER`
persists automatically. (Noted here so the implementer doesn't add redundant code.)

## Tuning Knobs

All values live in data / named constants, not inline magic numbers (per coding standards).

| Knob | Default | Range | Category | Rationale |
|------|---------|-------|----------|-----------|
| `river_count` | 1 | 1–3 | gate | Mandatory minimum 1 → satisfies "start map must have a river" (applies to every map). |
| `river_width` | 1 | 1–3 | feel | Thin rivers keep more buildable land and reduce bisection risk. |
| `river_meander_chance` | 0.35 | 0.0–0.6 | feel | Higher = wigglier river; too high = chaotic. |
| `lake_chance` | 0.5 | 0.0–1.0 | curve | Probability a map rolls any lakes. |
| `lake_count_max` | 2 | 0–4 | curve | Upper bound on lakes per map. |
| `lake_size` | 8–14 | 4–30 | curve | Tiles per lake (randomized in range). |
| `coast_chance` | 0.4 | 0.0–1.0 | curve | Probability a map has a coastline. |
| `coast_depth` | 3 | 1–6 | feel | Inward depth of the coastal water band. |
| `max_water_fraction` | 0.25 | 0.1–0.4 | gate | Hard cap so water never dominates the map. |
| `min_land_fraction` | 0.80 | 0.6–0.95 | gate | Largest passable region must be ≥ this share — playability guard. |
| `min_pocket_size` | 8 | 2–20 | gate | Passable pockets smaller than this are flooded to water. |
| `_RIVER/_LAKE/_COAST_SEED_OFFSET` | distinct large ints | — | — | Keep water RNG from aligning with terrain/fertility seeds (existing pattern). |

## Affected Systems

| System | Impact | Action Required |
|--------|--------|-----------------|
| Grid/Map (`world_grid.gd`) | New type, new generation step, connectivity guard, new queries | Update generator + rules + GDD |
| Terrain rendering (`terrain_renderer.gd`) | One new type to render | Extend the two parallel arrays (blue fallback) |
| Pathfinding / Logistics | Water = INF cost | None — already routes around INF tiles via `get_tile_movement_cost` |
| Building placement | Water blocks placement | Covered by `_blocks_occupation` + `validate_placement` (reuses `BLOCKED_BY_IMPASSABLE`) |
| Player/NPC spawn & initial buildings | Must start on the mainland | Verify spawn uses the largest passable component (edge case below) |
| Save/Load | Terrain ints already serialized | None |

## Acceptance Criteria

- [ ] `TileType.WATER` exists at ordinal 8; existing tile integer values and old saves load unchanged.
- [ ] Every generated map (any seed) contains ≥1 river tile; same seed → identical water layout (deterministic).
- [ ] `is_passable(water)` is false; `get_tile_movement_cost(water)` is `INF`; `validate_placement` on water returns `BLOCKED_BY_IMPASSABLE`.
- [ ] `add_resource_to_tile` / `move_one_resource` reject water targets.
- [ ] After generation the largest passable connected component is ≥ `min_land_fraction` of passable tiles (force-fix guarantees full connectivity in the worst case).
- [ ] Total water coverage ≤ `max_water_fraction`.
- [ ] Lakes and coast appear only per their roll (a map with `lake_chance`/`coast_chance` rolled false has none); both are absent gracefully.
- [ ] `is_water_adjacent(tile)` returns true exactly for passable land tiles orthogonally next to water.
- [ ] Water tiles render in distinct blue, visibly different from `IMPASSABLE` (near-black).
- [ ] Minimum resource counts (`TREE≥8, STONE≥4, BERRY≥6, GRASS≥6`) still hold after water carving.
- [ ] **No regression**: existing maps without the new code path (e.g. loaded saves) behave identically; pathfinding around water shows no INF-cost crashes.

### Edge Cases

- **River bisects the map** → connectivity guard rejects the attempt; force-fix punches a
  land bridge. Never ship a disconnected map.
- **Player/initial buildings would spawn on water or a cut-off islet** → spawn selection
  must use the largest passable component. Flagged for the implementer to verify against
  `player_character` / initial placement.
- **Water eats too many resource tiles** → handled by Step 5 retry + existing
  `_force_fix_minimums` (which only converts `EMPTY` tiles, never water).
- **All optional rolls fail** → map still has its mandatory river; valid.

## GDD Update Required?

**Yes** — `design/gdd/grid-map-system.md`:

- "Detailed Design → Procedural Generation Pipeline": 5 steps → 6 (add the carve-water
  step + connectivity in verification).
- Layer table & TileType list: add `WATER`.
- Tuning Knobs table: add the water knobs above.
- Visual Requirements: define water-blue terrain rendering.

GDD edits to be requested separately, after this spec is filed.
