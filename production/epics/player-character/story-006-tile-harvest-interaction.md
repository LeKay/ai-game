# Story 006: Tile Harvest Interaction

> **Epic**: Player Character System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration — ADR-0007
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/player-character-system.md`
**Requirement**: `TR-player-002` (Manual action dispatch (forage/pick/craft/chop/mine/transport) each with defined energy and tick cost) — extended to include tile-type→action mapping and HARVEST_FIBER action

**ADR Governing Implementation**: ADR-0007: Player Character Energy Model and Manual Action System
**ADR Decision Summary**: The `ActionSlot` manages a single action at a time. Tile clicks are translated to a `ManualActionType` based on the `WorldGrid.TileType` at that position, then dispatched via `try_start_action()`. The new `HARVEST_FIBER` action is deterministic (always fiber, no randomness). FORAGE applies to EMPTY tiles with an equal 4-way loot table (wood/stone/berry/fiber, 25% each). Tile click input lives in `MapRoot` — it converts mouse position to grid coords via `local_to_map()` and delegates to `PlayerCharacter`.

**Engine**: Godot 4.6 | **Risk**: MEDIUM — `local_to_map()` is a TileMapLayer method; verify signature in Godot 4.6. `_unhandled_input()` preferred over `_input()` to avoid consuming events handled by UI.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton for PlayerCharacter — `try_start_action()` called on the autoload, not a local instance
- Required: StringName action constants — resource IDs must use StringName (`&"fiber"`, `&"wood"`, etc.)
- Forbidden: No hardcoded magic numbers in action configs — use the `_action_configs` Dictionary
- Guardrail: Tile click handler must not consume input events needed by camera (WASD, scroll wheel)

---

## Acceptance Criteria

- [ ] **AC1** GIVEN a TREE tile WHEN the player clicks it THEN `try_start_action(CHOP_TREE)` is called and the action starts (if slot free and energy sufficient)
- [ ] **AC2** GIVEN a STONE tile WHEN the player clicks it THEN `try_start_action(MINE_STONE)` is called
- [ ] **AC3** GIVEN a BERRY tile WHEN the player clicks it THEN `try_start_action(PICK_BERRIES)` is called
- [ ] **AC4** GIVEN a GRASS tile WHEN the player clicks it THEN `try_start_action(HARVEST_FIBER)` is called and always yields fiber (deterministic, never random)
- [ ] **AC5** GIVEN an EMPTY tile WHEN the player clicks it THEN `try_start_action(FORAGE)` is called; loot is one of wood/stone/berry/fiber with equal 25% probability each
- [ ] **AC6** GIVEN an IMPASSABLE tile WHEN the player clicks it THEN no action is started and no signal is emitted
- [ ] **AC7** GIVEN any action is already running WHEN the player clicks a tile THEN `action_failed` is emitted with reason "Another action is in progress" and the running action continues uninterrupted
- [ ] **AC8** GIVEN a GRASS or EMPTY tile WHEN the player clicks it THEN camera movement (WASD / scroll) continues to work normally — tile click does not consume camera input events

---

## Implementation Notes

### New ManualActionType

Add `HARVEST_FIBER` to the `ManualActionType` enum in `PlayerCharacter`:

```gdscript
enum ManualActionType {
    FORAGE,
    PICK_BERRIES,
    CRAFT_TOOL,
    CHOP_TREE,
    MINE_STONE,
    HARVEST_FIBER,  # NEW — GRASS tiles, deterministic fiber output
}
```

### New ManualActionConfig entry

Add to `_action_configs` in `_ready()`:

| Action | Tick Cost | Energy Cost | Base Output | Resource | Requires Tool |
|--------|-----------|-------------|-------------|----------|---------------|
| HARVEST_FIBER | 45 | 6 | 2 | fiber | No |

### Updated FORAGE_TABLE

Replace existing 3-entry table with 4-way equal distribution:

```gdscript
const FORAGE_TABLE: Array = [
    [&"wood",  25],
    [&"stone", 50],
    [&"berry", 75],
    [&"fiber", 100],
]
```

### Tile-click handler in MapRoot

Add `_unhandled_input()` to `map_root.gd`. Use `_unhandled_input` (not `_input`) so UI panels consuming the same click do not double-fire:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton:
        return
    if not (event as InputEventMouseButton).pressed:
        return
    if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
        return
    var local_pos: Vector2 = terrain_layer.to_local(get_global_mouse_position())
    var tile: Vector2i = terrain_layer.local_to_map(local_pos)
    _on_tile_clicked(tile)
```

### Tile-type → action mapping

```gdscript
func _on_tile_clicked(tile: Vector2i) -> void:
    var terrain: WorldGrid.TileType = grid.get_terrain(tile)
    match terrain:
        WorldGrid.TileType.TREE:        PlayerCharacter.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)
        WorldGrid.TileType.STONE:       PlayerCharacter.try_start_action(PlayerCharacter.ManualActionType.MINE_STONE)
        WorldGrid.TileType.BERRY:       PlayerCharacter.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)
        WorldGrid.TileType.GRASS:       PlayerCharacter.try_start_action(PlayerCharacter.ManualActionType.HARVEST_FIBER)
        WorldGrid.TileType.EMPTY:       PlayerCharacter.try_start_action(PlayerCharacter.ManualActionType.FORAGE)
        WorldGrid.TileType.IMPASSABLE:  pass  # no action
```

---

## Out of Scope

*Do not implement in this story:*

- [Story 005/UI]: Tile Interaction Panel (cost-preview popup, Harvest button) — clicking a tile dispatches directly; UI is a separate story
- [Story 002]: EnergyPool and ActionSlot logic — already implemented
- [Story 004]: Depletion/food mechanics — already implemented
- Resource removal from tile after harvest — requires ResourceLayer mutability design (future story)

---

## QA Test Cases

**Story Type**: Integration
**Required evidence**: `tests/integration/player_character/tile_harvest_interaction_test.gd`

**AC1–AC5**: Tile-type → action mapping

For each tile type, test that the correct `ManualActionType` is dispatched:
- Given: MapRoot with WorldGrid, PlayerCharacter with energy=100, slot FREE
- When: `_on_tile_clicked(tile_of_type_X)`
- Then: `action_started` signal emitted with expected action_id

**AC4 — HARVEST_FIBER deterministic:**
- Given: GRASS tile, 100 repeated calls with varying RNG seeds
- Then: output resource is always `&"fiber"` (never random)

**AC5 — FORAGE equal distribution:**
- Given: EMPTY tile, 1000 repeated calls, fixed RNG seed
- Then: each of wood/stone/berry/fiber appears in 20%–30% of results (approximate equality)

**AC6 — IMPASSABLE no-op:**
- Given: IMPASSABLE tile, slot FREE
- When: `_on_tile_clicked(impassable_tile)`
- Then: no signal emitted, slot remains FREE

**AC7 — BLOCKED_SLOT:**
- Given: slot WORKING, any tile type
- When: `_on_tile_clicked(tree_tile)`
- Then: `action_failed` emitted with reason "Another action is in progress", original action unchanged

**AC8 — Camera input passthrough:**
- Verified manually: WASD and scroll wheel work during and after tile clicks
- No automated test — covered by existing camera integration tests

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/player_character/tile_harvest_interaction_test.gd` — must exist and pass

**Status**: [x] Complete — `tests/integration/player_character/tile_harvest_interaction_test.gd` (13 tests)

---

## Dependencies

- Depends on: Story 002 (Action Dispatch — must be DONE) ✓ Complete
- Depends on: grid-map Story 001 (WorldGrid.TileType — must be DONE) ✓ Complete
- Unlocks: Story 005/UI (Tile Interaction Panel needs this dispatch layer)

---

## Completion Notes

**Completed**: 2026-05-28
**Criteria**: 8/8 passing (AC8 manually confirmed in-engine)
**Deviations**:
- ADVISORY: Control Manifest requires autoload singleton for PlayerCharacter. Godot 4.6 throws an error when class_name matches autoload name — resolved with `get_first_node_in_group(&"player_character")` group lookup. Manifest rule should be updated to reflect this pattern.
- ADVISORY (pre-existing): `_action_configs` hardcoded in `_ready()` — carried from Story 004.
**Test Evidence**: Integration — `tests/integration/player_character/tile_harvest_interaction_test.gd` (13 tests, all ACs covered)
**Code Review**: Complete (pre-story-done via `/code-review pc-06`)
