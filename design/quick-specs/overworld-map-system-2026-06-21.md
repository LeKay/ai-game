# Quick Design Spec: Overworld / World Map System

**Type**: New Small System
**Scope**: A RimWorld-style island world map of small biome tiles, generated once per
game and persisted. It is the **start-location picker** (player chooses one land tile to
spawn the tactical map) and a **read-only inspection layer** for other tiles. Tile-to-tile
travel / multi-map play is explicitly **out of scope** (reserved). Selecting a tile hands
its seed, fertility set, and coast orientation to the existing `WorldGrid.generate()`.
**Date**: 2026-06-21
**Estimated Implementation**: ~1 week (data model + island gen + render scene + start
flow + save). Upper edge of quick-design scope — see "Scope note" below.

## Overview

The Overworld is a fixed grid of small tiles (default 24×24 at 16 px) shaped into an
**island** by a radial falloff mask, so ocean forms a natural border. Each tile is one of
three biomes — **OCEAN** (pure water, unplayable), **COAST** (land touching ocean),
**INLAND** (land) — and carries a **permanent per-tile seed** and **3 rolled
fertilities**. The whole overworld is deterministic from a single master `world_seed`;
nothing re-rolls during play. At new game the player opens the overworld and clicks a land
tile to start: that tile's seed + fertilities + (for coast) ocean-facing edge drive the
tactical `WorldGrid` generation. The overworld stays openable as a toggleable view;
non-start tiles are inspectable (biome, fertilities) but not interactive — colonizing them
comes later.

## Core Rules

### 1. Overworld data model

```
OverworldTile = {
    coord:        Vector2i,
    biome:        Biome,             # OCEAN | COAST | INLAND
    tile_seed:    int,               # permanent; = hash(world_seed, coord). Never changes.
    fertilities:  Array[StringName], # 3 entries (empty for OCEAN)
    coast_edge:   int,               # Direction enum (N/E/S/W); -1 unless COAST
    is_start:     bool
}
```

The overworld holds `OVERWORLD_SIZE × OVERWORLD_SIZE` tiles plus `world_seed` and
`start_coord`. It is owned by a new node/autoload (`OverworldSystem` /
`src/systems/overworld_system.gd`) analogous to `WorldGrid`.

### 2. Generation pipeline (deterministic from `world_seed`)

1. **Island mask** — for each tile compute `falloff = (radial_distance_from_center /
   radius) ^ ISLAND_FALLOFF_POWER`; sample a low-frequency noise (`ISLAND_NOISE_SCALE`,
   seeded from `world_seed`); the tile is **land** if `noise - falloff > ISLAND_THRESHOLD`,
   else **OCEAN**. This yields an irregular island with a guaranteed ocean ring at the grid
   edges.
2. **Biome classification** — a land tile orthogonally adjacent to ≥1 OCEAN tile = **COAST**;
   its `coast_edge` = the direction toward that ocean neighbor. If several ocean neighbors,
   pick deterministically with priority N → E → S → W. All other land = **INLAND**.
3. **Per-tile seed** — `tile_seed = hash(world_seed, coord.x, coord.y)`, assigned to every
   tile, fixed for the whole game.
4. **Fertility roll** — each land tile rolls `FERTILITIES_PER_TILE` (3) fertilities from
   `FERTILITY_POOL` using its own `tile_seed` (reuses `WorldGrid._roll_fertility` logic).
   OCEAN tiles get none.
5. **Start tile** — set when the player picks it (Rule 3 below), not at generation: its
   fertilities are overwritten to `STARTING_FERTILITY` = `[clay, wheat, wild]` and
   `is_start = true`.

### 3. Start selection → tactical map

Clicking a **land** tile in new-game mode generates the tactical map from that tile:

- **INLAND** → `WorldGrid.generate(tile.tile_seed, STARTING_FERTILITY)` (normal algo, no
  forced coast).
- **COAST** → `WorldGrid.generate(tile.tile_seed, STARTING_FERTILITY,
  coast_edge = tile.coast_edge)` — forces a `_carve_coast` on exactly that edge (prob 1.0,
  bypassing the random `_COAST_CHANCE` / random-edge path), so the tactical coast faces the
  same way it does on the overworld.
- **OCEAN** → not selectable (no playable land; click rejected with a hint).
- The start map's fertilities are always `STARTING_FERTILITY` (clay/wheat/wild), per the
  fertility spec — overriding whatever the tile rolled.

> Note: non-start tiles keep their rolled fertilities for future travel; only the chosen
> start tile is forced to clay/wheat/wild.

### 4. Inspection (read-only)

Opening the overworld after start: clicking any tile shows a panel with biome, the 3
fertilities (icons), and a "start here / locked" state. Non-start tiles are display-only in
this version — no travel, no second tactical map.

### 5. View / camera

The overworld renders in its own scene at `OVERWORLD_TILE_SIZE` (16 px, much smaller than
the tactical 48 px). It reuses the pan/zoom pattern of `camera_controller.gd`, bound to the
overworld's pixel bounds with its own zoom range (`OVERWORLD_ZOOM_RANGE`). It is a
**toggleable layer** (default key `M`) over/alongside the tactical view. Tiles are colored
by biome (ocean blue, coast tan, inland green); the start tile is marked.

### 6. Persistence

Since the whole overworld is deterministic from `world_seed`, the save stores only
`world_seed` + `start_coord` (the start tile's forced fertilities already live on
`WorldGrid`). On load the overworld regenerates identically and the start tile is re-flagged
from `start_coord`. No per-tile blob is serialized.

## Tuning Knobs

| Knob | Default | Range | Category | Rationale |
|------|---------|-------|----------|-----------|
| `OVERWORLD_SIZE` | 24 | 12–48 | curve | Tiles per axis. Too small = no choice; too big = unreadable at 16 px. |
| `OVERWORLD_TILE_SIZE` | 16 px | 8–32 | feel | RimWorld-small; distinct from tactical 48 px. |
| `ISLAND_THRESHOLD` | 0.10 | -0.1–0.4 | gate | Higher = smaller island / more ocean; guarantees the edge ring. |
| `ISLAND_FALLOFF_POWER` | 2.0 | 1.0–4.0 | curve | Steepness of the radial coast — higher = rounder island. |
| `ISLAND_NOISE_SCALE` | 3.0 | 1.0–8.0 | curve | Coastline raggedness. |
| `FERTILITIES_PER_TILE` | 3 | 1–`pool size` | gate | How many fertilities each map supports. |
| `OVERWORLD_ZOOM_RANGE` | 0.5–3.0 | — | feel | Pan/zoom limits for the overworld camera. |
| `STARTING_FERTILITY` | `[clay, wheat, wild]` | — | gate | Fixed start-map fertilities (existing constant). |

All values live as named constants / data, not inline magic numbers (per coding standards).

## Acceptance Criteria

- [ ] Same `world_seed` → byte-identical overworld (biomes, per-tile seeds, fertilities)
  every generation (determinism).
- [ ] Every edge tile of the grid is OCEAN; the land forms a single connected island
  surrounded by ocean.
- [ ] Each land tile has exactly `FERTILITIES_PER_TILE` fertilities from `FERTILITY_POOL`;
  OCEAN tiles have none.
- [ ] A tile's `tile_seed` is stable across save/load and across the whole session (never
  re-rolled).
- [ ] Selecting an INLAND tile generates a tactical map with that tile's seed and **no**
  forced coast.
- [ ] Selecting a COAST tile generates a tactical map whose `COAST` band is on the edge
  matching `coast_edge`; same seed → identical map.
- [ ] OCEAN tiles cannot be chosen as start (rejected with feedback).
- [ ] The chosen start map's fertilities are exactly `[clay, wheat, wild]`.
- [ ] Overworld view pans and zooms like the tactical map, with its own bounds and smaller
  tiles.
- [ ] Save stores `world_seed` + `start_coord`; reload reproduces the identical overworld
  and re-flags the start tile.
- [ ] **No regression**: existing single-map flow still works (a game with no overworld
  selection, or an old save, still generates/loads a valid tactical map).

## Affected Systems

| System | Impact | Action Required |
|--------|--------|-----------------|
| Grid/Map (`world_grid.gd`) | New optional `coast_edge` param on `generate()`; `_carve_coast` forced-edge path | Add param + branch; reuse `_roll_fertility` for overworld tiles |
| Camera (`camera_controller.gd`) | Overworld view reuses pan/zoom with its own bounds/zoom | Parameterize bounds + tile size, or instance a second controller |
| Save (`save_world_save_manager.gd`) | Store `world_seed` + `start_coord` | Add two fields; regenerate overworld on load |
| HUD / Input | New toggle (key `M`) + inspection panel | New overworld view + panel; input binding |
| Map Fertility | Fertilities now sourced per overworld tile; start = `STARTING_FERTILITY` | None to fertility logic — `generate()` already takes `fertility_override` |

## Scope note

This is genuinely ~1 week and adds a new scene, data model, and save field. It stays inside
quick-spec scope only because (a) travel/multi-map is deferred, and (b) the fertility and
coast plumbing already exist (`generate()`'s `fertility_override`, the `COAST` ordinal, and
`_carve_coast`). The single change to an existing system is the additive `coast_edge` param.

**Recommendation**: build from this spec now; graduate to a full GDD via `/design-system`
("Overworld System", Foundation/Core layer) when tile-to-tile travel becomes real.

## Systems Index

Not currently in `design/gdd/systems-index.md`. Suggested addition: **Overworld System**,
Foundation/Core layer — it sits above Grid/Map and feeds its `generate()` inputs. Add the
full GDD entry when travel ships.
