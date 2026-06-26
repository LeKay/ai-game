# Quick Spec — Ore & Gem Deposits

> **Status**: Implemented 2026-06-22 (awaiting Godot verification + art)
> **Author**: User + Claude
> **Scope**: Generalizes the clay deposit mechanic to six new mineable fertilities.
> **Engine**: Godot 4.6 / GDScript
> **Builds on**: `map-fertility-system-2026-06-18.md`, ADR-0015.

## Overview

Adds six new map fertilities that work **exactly like clay's discovery loop** — hidden at
generation, located via the **Search** action, revealed as a pit tile, then **hand-mined** for the
raw resource:

- **Common** (clay-like frequency): `iron`, `copper`, `tin`
- **Precious** (very rare): `silver`, `gold`, `gemstones`

No extraction buildings yet — manual mining only (the per-ore pit building is deferred, exactly as
clay's `CLAY_PIT` was initially deferred).

## Detailed rules

1. **Fertility roll** is now **weighted** (`WorldGrid.FERTILITY_WEIGHTS`). Each land tile draws
   `FERTILITIES_PER_TILE` (3) entries without replacement; common weight 12, precious weight 1, so
   silver/gold/gemstones appear ~1/12 as often as a common fertility. Used by both single-map
   (`WorldGrid`) and per-tile overworld (`OverworldSystem`) via the shared static
   `WorldGrid.roll_fertility(seed, count)`.
2. **Hidden deposits**: `WorldGrid._populate_hidden_deposits()` scatters `DEPOSIT_COUNTS[id]` hidden
   deposits per supported deposit fertility — **6** for common, **1** for precious — one deposit per
   tile, deterministic from `world_seed`.
3. **Search** (`PlayerCharacter.survey_tile`) is now deposit-agnostic: reveals whatever deposit sits
   on the searched tile; otherwise reports the Manhattan distance to the nearest hidden deposit of
   **any** kind (within `DEPOSIT_SEARCH_MAX_RADIUS`) and names it. Gated by the **Prospecting** node.
4. **Reveal** (`WorldGrid.reveal_hidden_deposit`) converts the tile to the matching pit `TileType`
   (`DEPOSIT_TILE_TYPE`: clay→CLAY, iron→IRON, …). Requires the tile to be EMPTY with no other
   resource ("clear this tile first" otherwise).
5. **Mine**: each revealed pit maps to a manual `MINE_<ORE>` action yielding the raw resource
   (clay parity: 60 ticks / 10 energy / 3 output). All six gated by the **Prospecting** node.

## Data / code touch points

| Concern | Location |
|---|---|
| Resources | `data/resources.json` — `iron, copper, tin, silver, gold, gemstones` |
| Fertility pool / weights / deposit maps / counts | `world_grid.gd` `FERTILITY_POOL`, `FERTILITY_WEIGHTS`, `DEPOSIT_TILE_TYPE`, `DEPOSIT_COUNTS` |
| Tile types | `world_grid.gd` `TileType` (IRON…GEMSTONE appended) + movement cost |
| Weighted roll | `world_grid.gd` `roll_fertility` (static) ← `overworld_system.gd` `_roll_fertility` |
| Deposit scatter / reveal / nearest | `world_grid.gd` `_populate_hidden_deposits`, `reveal_hidden_deposit`, `find_nearest_any_hidden` |
| Search + mine actions | `player_character.gd` `survey_tile`, `MINE_IRON…MINE_GEMSTONE` |
| Tile→action | `map_root.gd` `_terrain_to_action` |
| Rendering | `terrain_renderer.gd` `_TERRAIN_PNG_VARIANTS` + `_TERRAIN_FALLBACK_COLORS` |
| Search UI | `tile_interaction_panel.gd` `_on_search_pressed` |
| Progression gate | `data/progression_tree.json` `prospecting` unlocks |
| Art | `assets/art/ai-prompts/ore-gem-deposit-prompts.md` + `generate_ore_deposit_assets.py` |

## Tuning knobs (defaults)

| Knob | Value |
|------|-------|
| `FERTILITY_WEIGHTS` common / precious | 12 / 1 |
| `DEPOSIT_COUNTS` common / precious | 6 / 1 |
| `DEPOSIT_SEARCH_MAX_RADIUS` | 58 |
| Mine action (ticks / energy / yield) | 60 / 10 / 3 |
| Precious set | silver, gold, gemstones |

## Dependencies

WorldGrid (tile types, hidden layer, fertility, serialize) · OverworldSystem (per-tile roll) ·
PlayerCharacter / tile_interaction_panel (Search + mine) · ProgressionSystem (Prospecting gate) ·
terrain_renderer (rendering) · WorldSaveManager (serialize round-trip).

## Where the ores appear (important)

The **start tile is forced to `STARTING_FERTILITY` (clay/wheat/wild)** by `select_start`, so the
**initial colony never has ores**. Ores reach the player on **travelled-to** overworld tiles —
`generate_tactical_map` builds those from the tile's *rolled* fertilities (`tile.fertilities`),
which now include the new ores (precious ones scarce). This is by design: fixed home base, varied
frontier. (To make the home base eligible for ores, `select_start` would need to stop forcing
`STARTING_FERTILITY` — out of scope here.)

## Acceptance criteria

- New game: overworld tiles roll the new fertilities; precious ones are visibly scarce.
- Travelling to an ore-fertile tile generates a tactical map carrying that ore's hidden deposits.
- Search on a deposit tile reveals the correct pit; off-tile reports nearest deposit + name.
- Mining a revealed pit yields the matching raw resource.
- `_populate_hidden_deposits` places 6 common / 1 precious deposits; never two on one tile.
- Save → reload round-trips new fertilities, hidden deposits, and revealed pit tiles.

## Out of scope / follow-ups

- Per-ore extraction buildings (smelting / pit buildings) and downstream production chains.
- ~~The 16-variant pit tilesets + overlay/UI icons~~ **Generated 2026-06-22** via PixelLab
  (`generate_ore_ground_tiles.py` = 96 pit tiles via `create-tiles-pro`;
  `generate_ore_deposit_assets.py` = 12 pixen icons). All 108 PNGs validated 64×64, filenames
  match `terrain_renderer.gd` + `resources.json`. Restart the Godot editor to import the sidecars.
