# Story 007: Manual Resource Relocation (Tile-to-Tile Drag Transport)

> **Epic**: Player Character System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/player-character-system.md`
**Requirement**: Player-driven manual transport of individual resource items between map tiles.

**Design rationale**: Resources on the map are represented as individual instances
(`ResourceTileData` entries). Each instance is independently draggable. Moving a resource
costs energy proportional to the Manhattan distance, making long-range manual transport
expensive and encouraging strategic placement.

**Engine**: Godot 4.6 | **Risk**: MEDIUM (LMB drag input alongside existing right-click
tile interaction; badge refactoring touches per-frame `_process` animation loop)

---

## Acceptance Criteria

- [ ] **AC1** GIVEN a tile with one or more resource icons WHEN the player presses and holds
  LMB on a single icon THEN that icon detaches and follows the cursor; all other icons on
  the same tile remain in place
- [ ] **AC2** GIVEN an active drag WHEN the cursor moves THEN a label shows the current
  Manhattan distance and `energy_cost = max(1, distance)` live (updated every frame)
- [ ] **AC3** GIVEN an active drag WHEN the cursor hovers over a tile THEN passable in-bounds
  tiles highlight green; impassable or out-of-bounds positions highlight red
- [ ] **AC4** GIVEN a drag over a valid target tile AND the player has sufficient energy WHEN
  LMB is released THEN `WorldGrid.move_one_resource()` is called, the icon moves to the
  target tile position, and `max(1, distance)` energy is deducted
- [ ] **AC5** GIVEN a drag over a valid target tile AND the player has insufficient energy
  WHEN LMB is released THEN the icon snaps back to its source tile and no energy is deducted
- [ ] **AC6** GIVEN a drag over an invalid tile (impassable or out-of-bounds) WHEN LMB is
  released THEN the icon snaps back to its source tile and no energy is deducted
- [ ] **AC7** GIVEN a drag over a tile that already holds 4 resource icons WHEN LMB is
  released THEN the icon snaps back and no energy is deducted (tile is full)
- [ ] **AC8** GIVEN the player energy pool is at 0 (depleted state) WHEN a relocation drag
  completes on a valid target THEN the transport succeeds but energy cost is `max(1, distance) × 2`
  (uses existing `DepletionMod` from `EnergyPool`)
- [ ] **AC9** GIVEN a drag where source tile equals target tile (distance = 0) WHEN LMB is
  released THEN energy cost = 1, icon returns to its original position, `WorldGrid` state
  is unchanged (no move required)

---

## Implementation Notes

### Energy Formula

```
energy_cost = max(1, manhattan_distance(source_tile, target_tile))
```

Minimum cost of 1 even at distance 0 (same-tile drop). When depleted: `energy_cost × 2`.

### MAX_RESOURCES_PER_TILE

```gdscript
const MAX_RESOURCES_PER_TILE: int = 4
```

Defined in `WorldGrid`. Enforced by `move_one_resource()` and by the drag validator in
`map_root.gd`. Matches the visual limit in `_ICON_SCALE_BY_COUNT`.

---

### 1. WorldGrid — new write API

Add to `world_grid.gd`:

```gdscript
## Moves one ResourceTileData entry from source[source_idx] to target.
## Returns false if: target out-of-bounds, target IMPASSABLE, source_idx invalid,
## or target already holds MAX_RESOURCES_PER_TILE entries.
func move_one_resource(source: Vector2i, source_idx: int, target: Vector2i) -> bool:
    if not is_in_bounds(source) or not is_in_bounds(target):
        return false
    if _terrain[target.x][target.y] == TileType.IMPASSABLE:
        return false
    var src_arr: Array = _resources[source.x][source.y]
    if source_idx < 0 or source_idx >= src_arr.size():
        return false
    if _resources[target.x][target.y].size() >= MAX_RESOURCES_PER_TILE:
        return false
    var entry: ResourceTileData = src_arr[source_idx]
    src_arr.remove_at(source_idx)
    _resources[target.x][target.y].append(entry)
    return true
```

---

### 2. Badge tracking refactor in `map_root.gd`

**Current structure** (one entry per tile):
```gdscript
_resource_badges: Array  # [{node: Node2D, base_y: float, phase: float}]
```

**New structure** (one entry per resource instance):
```gdscript
_resource_icons: Array  # [{node: Node2D, tile: Vector2i, resource_idx: int,
                        #    base_y: float, phase: float}]
```

Each resource instance gets its own `Node2D` wrapper (a single `Sprite2D` child + backdrop).
The `_spawn_resource_badges()` and `_spawn_badge()` methods are updated to populate
`_resource_icons` instead of `_resource_badges`. The bob animation in `_process()` iterates
`_resource_icons`.

`tile` and `resource_idx` are updated after every successful `move_one_resource()` call so
the icon can be found again for future drags.

---

### 3. RelocationDrag inner class in `player_character.gd`

```gdscript
class RelocationDrag:
    enum DragState { IDLE, DRAGGING, SNAP_BACK }

    var state: DragState = DragState.IDLE
    var source_tile: Vector2i = Vector2i(-1, -1)
    var source_idx: int = -1          # index into WorldGrid._resources[x][y]
    var resource_id: StringName = &""
    var cached_cost: int = 1          # updated each frame during drag
```

New public methods on `PlayerCharacter`:

```gdscript
## Called when LMB press lands on a resource icon.
## Returns false if slot is occupied or architect mode blocks gathering.
func try_start_relocation(tile: Vector2i, resource_idx: int) -> bool

## Called each frame during drag with the current cursor tile.
## Returns the energy preview cost (does not spend energy).
func get_relocation_preview(target_tile: Vector2i) -> int

## Called on LMB release. Validates energy, calls WorldGrid.move_one_resource(),
## deducts energy. Returns RelocationResult enum value.
func try_commit_relocation(target_tile: Vector2i, grid: WorldGrid) -> int

## Cancels an in-progress drag. No energy spent.
func cancel_relocation() -> void
```

`RelocationResult` enum (add to `PlayerCharacter`):
```gdscript
enum RelocationResult {
    SUCCESS,
    SNAP_BACK_ENERGY,      # insufficient energy
    SNAP_BACK_INVALID,     # target impassable / out-of-bounds
    SNAP_BACK_FULL,        # target tile already at MAX_RESOURCES_PER_TILE
    SNAP_BACK_SAME_TILE,   # distance 0 — paid 1 energy, icon stays
    NOT_DRAGGING,          # commit called when state is IDLE
}
```

---

### 4. Input handling in `map_root.gd`

Extend `_unhandled_input()` to handle LMB:

```
LMB press  → hit-test _resource_icons by proximity to cursor world pos
             → if hit: call PlayerCharacter.try_start_relocation(), enter drag mode
LMB held   → update dragged icon position to cursor world pos
             → update cost label and tile highlight
LMB release → call PlayerCharacter.try_commit_relocation()
             → on SUCCESS: reposition icon, update _resource_icons entry
             → on SNAP_BACK_*: animate icon back to source position (Tween)
```

Hit-test approach: convert mouse world position to tile, then find the nearest icon
in `_resource_icons` whose `tile` matches — picks the icon whose sprite center is
closest to the cursor (within a tap radius of `TILE_SIZE * 0.5`).

---

### Drag visual spec

| State | Dragged icon appearance |
|-------|------------------------|
| DRAGGING | 70% opacity, scale 1.2×, z_index raised to 10 |
| SNAP_BACK | Tween back to source position over 0.18s (TRANS_BACK ease) |
| Placed | Tween to target position over 0.10s, opacity → 100%, scale → 1.0× |

Source tile: remaining icons re-layout their positions within the tile after the
dragged icon is removed (call `_relayout_tile_icons(tile)`).

Target tile: new icon appended; all icons on that tile re-layout.

---

### Signals to emit (on `PlayerCharacter`)

```gdscript
signal relocation_started(source: Vector2i, resource_id: StringName)
signal relocation_completed(source: Vector2i, target: Vector2i, resource_id: StringName)
signal relocation_cancelled(source: Vector2i)
```

---

## Out of Scope

- Moving a whole badge at once (multi-resource drag) — individual instances only
- Keyboard shortcut to cancel drag (Escape handling) — future story
- Sound / VFX on drop
- Merging different resource types onto a single tile is allowed implicitly (WorldGrid
  does not enforce same-type; visual system handles mixed tiles already)

---

## QA Test Cases

**AC4 + AC2**: Basic relocation with energy cost
- Given: Tile (5, 5) has `[wood, wood, stone]`, player energy = 50, icon at index 0 (wood)
- When: drag to (5, 10) → release
- Then: distance = 5, energy_cost = 5, energy → 45, `_resources[5][5]` = `[wood, stone]`,
  `_resources[5][10]` = `[wood]`, relocation_completed signal emitted

**AC5**: Insufficient energy snap-back
- Given: energy = 3, drag from (0, 0) to (0, 10)
- When: release at (0, 10)
- Then: distance = 10, energy_cost = 10 > 3, SNAP_BACK_ENERGY, energy unchanged (3),
  WorldGrid unchanged, relocation_cancelled signal emitted

**AC7**: Full target tile
- Given: Tile (8, 8) has 4 resources (MAX), drag any resource to (8, 8)
- When: release
- Then: SNAP_BACK_FULL, WorldGrid unchanged

**AC8**: Depleted energy
- Given: energy = 0, drag from (3, 3) to (3, 6)
- When: release
- Then: distance = 3, energy_cost = 3 × 2 = 6, but energy = 0 < 6 → SNAP_BACK_ENERGY
  (depleted state does NOT waive the energy check — it doubles the cost)

**AC9**: Same-tile drop
- Given: energy = 10, drag from (4, 4) → release on (4, 4)
- Then: distance = 0, energy_cost = max(1, 0) = 1, energy → 9, WorldGrid unchanged,
  icon returns to original position

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/player_character/resource_relocation_test.gd` — must exist and pass

**Status**: [x] Exists — `tests/integration/player_character/resource_relocation_test.gd` (16 tests)

---

## Dependencies

- Depends on: Story 001 (EnergyPool ✅), Story 002 (ActionSlot ✅)
- Does NOT depend on: InventorySystem, BuildingSystem, LogisticsSystem
- Unlocks: Visual polish story (drag VFX, sound)

---

## Completion Notes
**Completed**: 2026-05-28
**Criteria**: 9/9 passing (AC1–AC3 manual confirmed; AC4–AC9 integration tests)
**Deviations**:
- ADVISORY: No TR-ID for tile-to-tile relocation (nearest is TR-player-003 for storage transport)
- ADVISORY: ADR-0007 specifies `transport_*` signals; implementation uses `relocation_*` — intentional extension, ADR update pending
- FIXED: Pre-existing `get_first_node_in_group()` called on Node instead of SceneTree (replaced with direct `_player` reference)
**Test Evidence**: `tests/integration/player_character/resource_relocation_test.gd` — 16 tests (AC2, AC4–AC9 + state machine edges)
**Code Review**: Complete — 4 blocking bugs fixed (per-icon Node2D refactor, index corruption ×2, global_position hit-test)
