# Quick Design Spec: Overworld Biomes & Rivers

**Type**: Extension of an existing system (Overworld / World Map)
**Scope**: Add two land biomes — **FOREST** and **MOUNTAIN** — plus **rivers** to the
overworld island, draw them on the world map, and let them bias the tactical
`WorldGrid.generate()` per tile. Rivers spring in the mountains and flow to the coast; a
tile only carries a tactical river when its overworld tile has one (the same contract as
coast). Ore is **out of scope** here — mountains only get the terrain bias now; the ore
distribution (more ore in mountain maps) is reserved for a later pass.
**Date**: 2026-06-22
**Builds on**: `design/quick-specs/overworld-map-system-2026-06-21.md`

## Overview

The overworld currently classifies land as **COAST** or **INLAND**. This extension splits
the non-coast land into **MOUNTAIN**, **FOREST**, and plains **INLAND** via a
height + moisture noise pass, and lays **rivers** from mountain sources down to the coast.
Both are drawn on the world map and feed the tactical map generator: a mountain tile yields
a stony/rugged tactical map, a forest tile a denser one, and a river tile a tactical map
with a river aligned to the overworld flow. Everything stays deterministic from the single
`world_seed`; persistence is unchanged (seed + start_coord only).

## Core Rules

### 1. Data model additions (`overworld_system.gd`)

```
enum Biome { OCEAN, COAST, INLAND, FOREST, MOUNTAIN }   # append-only; 0/1/2 unchanged
```

`OverworldTile` gains:
```
has_river:    bool                 # true if a river crosses this tile
river_edges:  Array[int]           # WorldGrid edges (0 top,1 bottom,2 left,3 right) where the
                                    # river connects to its upstream/downstream neighbours;
                                    # empty unless has_river. Analogous to coast_edges.
```

Rivers are an **overlay attribute**, not a biome value — a FOREST or MOUNTAIN tile can also
have a river.

### 2. Biome classification (height + moisture)

A new step runs after `_classify_coasts()` and before fertilities. For every **non-COAST
land** tile:

1. `elev = noise_elev01(coord) - radial_falloff_blend` so elevation is highest toward the
   island interior (the radial term is reused from the island mask, lightly weighted), making
   mountains cluster inland and coasts stay low.
2. `moist = noise_moist01(coord)`.
3. Classify:
   - `elev > MOUNTAIN_ELEV_THRESHOLD` → **MOUNTAIN**
   - else `moist > FOREST_MOISTURE_THRESHOLD` → **FOREST**
   - else → **INLAND** (plains)

COAST tiles are never reclassified (the shore stays coast). Two independent FastNoiseLite
instances seeded from `world_seed + BIOME_*_SEED_OFFSET`.

### 3. River generation (mountains → coast)

A new step after classification. `RIVER_COUNT` rivers (tuning knob, default **6**):

1. Collect all MOUNTAIN tiles; deterministically shuffle (seed `world_seed + RIVER_SEED_OFFSET`)
   and take the first `RIVER_COUNT` as **sources**.
2. Each river walks **downhill** from its source: each step picks the orthogonal neighbour
   that most decreases `elev` while heading toward the nearest ocean, marking `has_river =
   true`, until it reaches a COAST/OCEAN tile or hits `RIVER_MAX_STEPS`.
3. For every consecutive pair (A → B) the step direction sets `river_edges`: the exit edge on
   A and the entry edge on B (a through-tile ends with two edges; a source/mouth with one).
4. Rivers are allowed to merge / share tiles; a tile already flagged just accumulates edges.

Determinism: same `world_seed` → identical river set, sources, and edges.

### 4. Tactical influence (`world_grid.gd`)

`generate()` gains two additive, defaulted params (no existing caller breaks):

```
enum TerrainProfile { PLAINS, FOREST, MOUNTAIN }   # WorldGrid-local; no OverworldSystem dep

func generate(world_seed, fertility_override := [], coast_edges := [],
              terrain_profile := TerrainProfile.PLAINS, river_edges := []) -> void
```

- **`terrain_profile`** shifts the `_sample_noise` elevation bands:
  - MOUNTAIN — elevation biased up: more STONE + IMPASSABLE, less EMPTY (harsh start; ore hook later).
  - FOREST — biased toward the TREE band: denser woods.
  - PLAINS — current behaviour unchanged.
- **`river_edges`** makes the river **conditional**: `_carve_river` runs **only** when
  `river_edges` is non-empty, tracing the river between those edges (aligned to the overworld
  flow). Empty ⇒ **no river** (behaviour change — the old mandatory `_RIVER_COUNT = 1` is
  removed). Coast and lakes are unchanged.

`OverworldSystem.generate_tactical_map()` maps `tile.biome` → profile (FOREST/MOUNTAIN, else
PLAINS) and forwards `tile.river_edges`.

### 5. Rendering & inspection (`overworld_view.gd`)

- New fill colours: FOREST (dark green), MOUNTAIN (grey-brown).
- River tiles are painted a distinct river-blue directly into the 1px/tile biome texture, so
  the single-draw-call rendering is preserved and rivers read as water.
- The inspection panel shows the real biome name and, when `has_river`, a "River runs through
  here" note.

### 6. Persistence — unchanged

Save still stores only `world_seed` + `start_coord`; biomes and rivers regenerate identically
on load.

## Tuning Knobs

| Knob | Default | Range | Rationale |
|------|---------|-------|-----------|
| `MOUNTAIN_ELEV_THRESHOLD` | 0.62 | 0.5–0.8 | Higher = fewer/smaller mountain ranges. |
| `FOREST_MOISTURE_THRESHOLD` | 0.55 | 0.4–0.7 | Higher = sparser forests. |
| `BIOME_RADIAL_WEIGHT` | 0.35 | 0–0.6 | How strongly mountains pull toward the interior. |
| `RIVER_COUNT` | 6 | 5–7 | Rivers per island. |
| `RIVER_MAX_STEPS` | OVERWORLD_SIZE | — | Safety bound on a river walk. |
| `MOUNTAIN_ELEV_BONUS` (tactical) | +0.18 | 0.1–0.3 | Stone/impassable bias for mountain maps. |
| `FOREST_TREE_BONUS` (tactical) | +0.12 | 0.05–0.25 | Tree bias for forest maps. |

## Acceptance Criteria

- [ ] Same `world_seed` → identical biomes (incl. FOREST/MOUNTAIN), `has_river`, and
  `river_edges` every generation.
- [ ] Every MOUNTAIN/FOREST tile is land (never OCEAN); COAST tiles are never reclassified.
- [ ] Every river tile chain starts on (or adjacent to) a MOUNTAIN and ends at a COAST/OCEAN
  tile; `has_river` tiles carry ≥1 `river_edge`.
- [ ] A MOUNTAIN start tile is selectable; its tactical map has more STONE/IMPASSABLE than a
  PLAINS map from the same seed.
- [ ] A FOREST start tile's tactical map has more TREE tiles than a PLAINS map from the same seed.
- [ ] A tile with `has_river` produces a tactical map with a river; a tile without produces
  **no** river. Same seed → identical river layout.
- [ ] Overworld view renders the four land biomes distinctly and rivers as water; inspection
  reports biome + river.
- [ ] No persistence change; old saves load (regenerate with the new biomes/rivers).

## Affected Systems

| System | Impact | Action |
|--------|--------|--------|
| `overworld_system.gd` | Biome enum, classification step, river step, tile fields, tactical mapping | Add steps + fields |
| `world_grid.gd` | `terrain_profile` band shift; `river_edges` makes river conditional | Add params + branch; **remove mandatory river** |
| `overworld_view.gd` | New biome colours + river overlay + inspection text | Render + panel |
| Tests | New biome/river coverage; update WorldGrid river-mandatory assertions | Add/adjust tests |

## Slicing

- **Slice A** — Forest/Mountain biomes (enum, classification, render, inspection, tests).
- **Slice B** — Overworld rivers (attributes, generation, render, inspection, tests).
- **Slice C** — Tactical influence (`terrain_profile` + conditional `river_edges`, wiring, tests).
</content>
</invoke>

---

## Revision 2 (2026-06-22) — Freshwater becomes real, non-selectable water tiles

Per follow-up direction: water must be **blocked for selection like the ocean**, and the
freshwater feature on a tactical map must come from **adjacency**, "replicating the coast logic".

- **New biomes** `Biome.RIVER` and `Biome.LAKE` (append-only). Both are freshwater and, like
  `OCEAN`, are **not selectable** (`is_selectable` now rejects any water; `_is_water` =
  OCEAN/RIVER/LAKE). Fertilities are not rolled for them.
- **Rivers** stop being a `has_river` overlay. `_carve_rivers`/`_trace_river` now **convert** the
  tiles a river flows through into `Biome.RIVER` (the source mountain stays land, so the first
  water tile springs beside a mountain; the walk ends at the shore — a COAST tile becomes the
  river mouth, its stale `coast_edges` cleared — or merges into existing freshwater).
- **Lakes** are new: `_carve_overworld_lakes` grows `LAKE_COUNT` blobs (`_grow_lake`, frontier
  flood) in interior plains/forest basins (never mountains/coast). Runs before rivers so a river
  can flow into a lake. The forced-land **centre tile is protected** from both carvers (stays a
  valid fallback start).
- **Adjacency classification** `_classify_water_adjacency` (the freshwater twin of
  `_classify_coasts`): each LAND tile records `river_edges` (edges facing a RIVER tile) and
  `lake_edges` (edges facing a LAKE tile). `OverworldTile.has_river` removed; `river_edges`
  re-meaning'd to adjacency; `lake_edges` added.
- **Tactical** `WorldGrid.generate(..., river_edges, lake_edges)`: `river_edges` → existing
  `_carve_river`; `lake_edges` → new `_carve_freshwater` = clone of `_carve_coast` but carving
  `TileType.WATER` (fresh) instead of `COAST` (salt) — "a lake is like a coast, only freshwater".
- **View**: RIVER/LAKE drawn as freshwater blue (distinct from salt ocean); inspection shows
  "River/Lake (freshwater)" for water tiles and "Borders a river/lake" for land that touches them.
- **Connectivity invariant** updated: the *island* (all non-OCEAN = land + interior freshwater)
  is the single connected component; freshwater is carved out of it in place. Rivers are
  boundary-reaching slits and lakes are interior blobs, so neither disconnects the island.

Queries: `is_freshwater(coord)`, `borders_river(coord)`, `borders_lake(coord)`.

## NPC cities (2026-06-22)

NPC-owned settlements on the overworld that the player may not start on or beside.

- **Placement** `OverworldSystem._place_cities(world_seed)` (runs after all water carving, before
  fertilities): **theme-driven** — each faction is placed on land matching its identity
  (`_matches_faction_theme`): Ironhold→`MOUNTAIN`, Verdant→`FOREST`, Goldfield→`INLAND` (plains),
  Tidewatch→`COAST`, Ravenmoor→a land tile **bordering a lake** (`lake_edges` non-empty; cities sit
  on land, not water). Factions are tried in a seeded-shuffle order; within a faction its matching
  tiles are seeded-shuffled and the first one ≥ `_CITY_MIN_SPACING` from every placed city is taken.
  A faction whose theme has no free tile this island is skipped. Stops at `CITY_COUNT`. Eligible
  tiles are `is_selectable` and outside the centre's exclusion radius. Deterministic from
  `world_seed` (`_CITY_SEED_OFFSET`).
- **Exclusion** `_city_blocked` = every land tile within `_CITY_EXCLUSION_RADIUS` (Euclidean) of a
  city, **except** the guaranteed-land centre (always kept clear so the fallback start survives).
- **Start gating** new `is_start_allowed(coord)` = `is_selectable` AND not `is_city_blocked`.
  `select_start` and the picker's "Start here" button / hover now use it. `is_selectable` is
  unchanged (still pure land) so **travel** to a city tile is not blocked — only *starting* there.
- **Tuning knobs**: `CITY_COUNT` (=4), `_CITY_EXCLUSION_RADIUS` (=5), `_CITY_MIN_SPACING` (=12).
- **Queries**: `is_city(coord)`, `is_city_blocked(coord)`, `get_cities()`, `is_start_allowed(coord)`.
- **Factions**: each city is assigned one faction from `FACTIONS` (5 entries: Ironhold, Verdant
  Pact, Tidewatch, Goldfield, Ravenmoor — `id` matches `assets/ui/icons/factions/<id>.png`).
  Faction is bound to the city **at placement** (each faction used once → distinct), so the city's
  biome always matches its theme; deterministic from `world_seed`.
  Queries: `get_city_faction(coord)→int` (-1 if not a city), `get_faction_id(idx)`,
  `get_faction_name(idx)`. Emblems generated by `assets/art/ai-prompts/generate_faction_icons.py`
  (heraldic shield crests). The inspection panel shows the emblem (top, `_faction_icon` TextureRect)
  and the faction name as the title when a city tile is clicked. On the map, each city also renders
  its faction emblem floating smaller and diagonally above-right of the city icon
  (`_draw_city_faction_emblem`, `_FACTION_EMBLEM_SCALE` = 0.6).
- **Icon**: `assets/ui/icons/overworld/city.png` (PixelLab, walled medieval town,
  `assets/art/ai-prompts/generate_overworld_city_assets.py`). `OverworldView` `load()`s it at
  runtime (graceful no-op if unimported) and draws it spanning a **3x3 tile block centred on the
  city tile** (`_CITY_ICON_TILE_SPAN`), with a floor size (`_CITY_ICON_MIN_PX`) so it reads at any
  zoom. Inspection panel notes "NPC city — cannot settle here" / "Too close to an NPC city to
  settle".
- **Player settlement icon**: `assets/ui/icons/overworld/player_settlement.png` (PixelLab, rustic
  log-cabin camp with a teal banner — same generator, `--force` to regenerate). Drawn by the same
  `_draw_settlement_icon` helper (3x3, centred, floor size). While **picking a start** it appears
  as a **translucent preview** (`_PLAYER_PREVIEW_MODULATE`) on the currently selected candidate
  tile (only when start-allowed); once a start exists it is drawn **solid and fixed** on the
  chosen tile.
