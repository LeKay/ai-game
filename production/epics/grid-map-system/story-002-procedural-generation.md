# Story 002: Procedural Generation Pipeline

> **Epic**: Grid/Map System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: N/A (no control manifest)

## Context

**GDD**: `design/gdd/grid-map-system.md`
**Requirement**: `TR-grid-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004: Grid Map Data Model and TileMapLayer Rendering
**ADR Decision Summary**: `generate(seed: int)` implements a 5-step pipeline: Perlin noise sampling (elevation + moisture via `FastNoise` with `TYPE_PERLIN`) → threshold segmentation → 2-iteration smoothing pass (60% adoption probability) → cluster cleanup (min 3 tiles) → minimum count verification (max 5 seed attempts, then force-fix). Same seed produces identical maps.

**Engine**: Godot 4.6 | **Risk**: HIGH
**Engine Notes**: `PerlinNoise` was renamed to `FastNoise` in Godot 4.5+. Use `FastNoise` with `noise_type = FastNoise.TYPE_PERLIN`. Verify `FastNoise.TYPE_PERLIN` constant exists in Godot 4.6 editor before implementing (flagged in architecture review 2026-05-14). Use `FastNoise.get_noise_2d(x, y)` — confirm return range `[-1.0, 1.0]`. Do NOT use `FastNoiseLite`.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Hardcoded resource definitions; any write to `_terrain` after `_generation_done = true`
- Guardrail: Generation runs once at `_ready()`; no runtime regeneration path exposed to player

---

## Acceptance Criteria

*From GDD `design/gdd/grid-map-system.md`, scoped to this story:*

- [ ] **AC-2**: Given the grid is generated with seed 42 producing `TerrainLayer_A` and `ResourceLayer_A`, when the grid is regenerated with seed 42, then `TerrainLayer_B` equals `TerrainLayer_A` tile-for-tile and `ResourceLayer_B` equals `ResourceLayer_A` tile-for-tile (same `resource_id`, `clearable` per tile)
- [ ] **AC-4**: Given the grid, when generation completes, then the result contains at least 8 TREE tiles, 4 STONE tiles, 6 BERRY tiles, and 6 GRASS tiles
- [ ] **AC-22**: Given a grid where minimum count verification determines 5 seed attempts all fail, when force-fix runs, then EMPTY tiles adjacent to existing resource clusters are converted to the deficient resource type until the minimum count is met
- [ ] **AC-23**: Given a generated map where exactly two TREE tiles at `(3, 3)` and `(3, 4)` form a connected component of size 2, when cluster cleanup runs with `min_cluster_size = 3`, then only those two tiles are converted to EMPTY and no other tiles are modified

---

## Implementation Notes

*Derived from ADR-0004 Implementation Guidelines:*

Implement `generate(seed: int) -> void` on `WorldGrid`:

**Step 1 — Perlin Noise Sampling**:
```gdscript
var elevation_noise := FastNoise.new()
elevation_noise.noise_type = FastNoise.TYPE_PERLIN
elevation_noise.seed = seed
elevation_noise.octave_count = 4  # verify property name in 4.6
elevation_noise.persistence = 0.5
elevation_noise.lacunarity = 2.0
# scale property — verify API in 4.6; may be frequency or period

var moisture_noise := FastNoise.new()
moisture_noise.noise_type = FastNoise.TYPE_PERLIN
moisture_noise.seed = seed + 1
moisture_noise.octave_count = 3
```
Normalize: `elev_norm = (elevation_noise.get_noise_2d(x, y) + 1.0) / 2.0`

**Step 2 — Threshold Segmentation**:
```
elev_norm < 0.15  → IMPASSABLE
elev_norm < 0.30  → BERRY (mois < 0.5) or GRASS (mois >= 0.5)
elev_norm < 0.55  → EMPTY
elev_norm < 0.75  → TREE
else              → STONE
```

**Step 3 — Smoothing Pass (2 iterations)**:
For each tile: count 8-way neighbor types → find dominant type → with 60% probability, adopt it.
Run 2 iterations. Use `RandomNumberGenerator` seeded from the generation seed for determinism.

**Step 4 — Cluster Cleanup**:
Flood-fill connected components per terrain type. Convert any component of size < 3 to EMPTY. Only convert the tiles that are in the small component — do not modify surrounding tiles.

**Step 5 — Minimum Count Verification**:
Count TREE, STONE, BERRY, GRASS tiles. If any is below minimum (`TREE ≥ 8, STONE ≥ 4, BERRY ≥ 6, GRASS ≥ 6`):
- Retry with `seed + attempt_number` (max 5 attempts)
- If all 5 fail: force-fix by converting EMPTY tiles nearest to existing resource cluster tiles to the deficient type. Log `push_warning("Map generation forced-fix on attempt N")`

**ResourceLayer population**: After terrain is set, populate `_resources` based on terrain type:
- TREE → `resource_id = "wood"`, `clearable = true`
- STONE → `resource_id = "stone"`, `clearable = false`
- BERRY → `resource_id = "berry"`, `clearable = true`
- GRASS → `resource_id = "fiber"`, `clearable = true`
- EMPTY / IMPASSABLE → null

After generation completes, set `_generation_done = true` to lock TerrainLayer.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Data model arrays and read API (must be done first)
- Story 006: Calling `TileMapLayer.set_cell()` to sync rendering after generation

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-2**: Deterministic generation with same seed
  - Given: A fresh `WorldGrid` instance
  - When: `generate(42)` is called, terrain+resource arrays are copied, then `generate(42)` is called again
  - Then: Every tile in both runs has identical `TileType` and identical `resource_id`/`clearable` values
  - Edge cases: Test with seed 0, seed 999999; verify seed+1 moisture produces different map than seed alone

- **AC-4**: Minimum resource counts after generation
  - Given: A fresh `WorldGrid` instance
  - When: `generate(42)` completes
  - Then: count(TREE) >= 8, count(STONE) >= 4, count(BERRY) >= 6, count(GRASS) >= 6
  - Edge cases: Test 10 different seeds to confirm no seed fails minimum counts after force-fix

- **AC-22**: Force-fix when all seed attempts fail minimum counts
  - Given: A mock where Perlin noise always produces all EMPTY tiles (no resources)
  - When: `generate()` runs all 5 seed attempts
  - Then: Force-fix converts EMPTY tiles to deficient types until all minimums are met; `push_warning` is called
  - Edge cases: Force-fix on multiple deficient types simultaneously; force-fix selects tiles adjacent to existing resource tiles

- **AC-23**: Cluster cleanup — small components become EMPTY
  - Given: A grid where tiles `(3,3)` and `(3,4)` are TREE (component size 2) and all other TREE tiles form components of size ≥ 3
  - When: Cluster cleanup runs with `min_cluster_size = 3`
  - Then: `get_terrain(Vector2i(3, 3))` == EMPTY, `get_terrain(Vector2i(3, 4))` == EMPTY; no other TREE tiles changed
  - Edge cases: Component of exactly 3 tiles is kept; component of size 1 (isolated tile) is converted

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/grid/grid_generation_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Completion Notes
**Completed**: 2026-05-25
**Criteria**: 4/4 passing (push_warning assertion for AC-22 untested — GdUnit4 framework limitation)
**Deviations**: Noise thresholds and parameters hardcoded (ADVISORY — externalize during balance phase); story written against manifest N/A, current manifest 2026-05-14 (no new forbidden patterns apply)
**Test Evidence**: Logic: `tests/unit/grid/grid_generation_test.gd` (22 tests)
**Code Review**: Complete (APPROVED WITH SUGGESTIONS — all fixes applied)

## Dependencies

- Depends on: Story 001 must be DONE (WorldGrid class, arrays, and enums must exist before generation can fill them)
- Unlocks: Story 006 (TileMapLayer rendering — rendering wires to the populated grid data)
