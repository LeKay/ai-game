# Story 002: Action Dispatch

> **Epic**: Player Character System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration — ADR-0007
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/player-character-system.md`
**Requirement**: `TR-player-002` (Manual action dispatch (forage/pick/craft/chop/mine/transport) each with defined energy and tick cost)

**ADR Governing Implementation**: ADR-0007: Player Character Energy Model and Manual Action System
**ADR Decision Summary**: The `ActionSlot` class manages a single action at a time (binary free/occupied). Five action types at VS scope: Forage, Pick Berries, Craft Tool, Chop Tree, Mine Stone. Each has discrete energy cost and tick cost. The `try_start()` method checks: slot state, energy availability, architect mode lockout, and tool requirement. Tick advancement comes via `ticks_advanced(n)` signal from TickSystem. Action completion triggers `action_completed` signal and frees the slot. Resource pins spawn on the clicked tile via ResourceSystem.

**Engine**: Godot 4.6 | **Risk**: HIGH (verification required: `_process()` at 144fps, `Tween` in 4.6)
**Engine Notes**: Post-cutoff APIs used are stable since Godot 1.0. Verify `_process()` accumulator at 144fps. HUD signals (`action_progress_update`) should be rate-limited to avoid per-frame signal spam at high tick rates.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/player-character-system.md`, scoped to this story:*

- [ ] **AC1** GIVEN a tile with a harvestable resource WHEN the player clicks it AND the player has sufficient energy THEN the manual action starts, the tick counter fills for the action's tick cost, and energy is deducted by the action's energy cost
- [ ] **AC2** GIVEN a manual action is running WHEN the tick counter reaches the action's tick cost THEN the resource appears on the tile as a pin icon and the action slot becomes free
- [ ] **AC11** GIVEN the player hovers over a harvestable tile WHEN the player has sufficient energy THEN a cost preview tooltip shows energy cost, tick cost, and expected output
- [ ] **AC13** GIVEN the player has energy in [91..99] WHEN the player consumes bread (+25 energy) THEN energy is clamped to exactly 100 and the food item is removed from its current source
- [ ] **AC14** GIVEN the player is at 0 Energy WHEN the player hovers over a harvestable tile THEN the tooltip shows the depleted tick cost (doubled) and depleted output (ceil × 0.5, min 1) with a "(depleted)" label
- [ ] **AC16** GIVEN a tool-requiring action WHEN the player has no tools OR all tools have `current_charge <= 0.0` THEN the action is blocked with the message "No tool available — craft one first"
- [ ] **AC18** GIVEN the player has 0 Energy WHEN the player uses WASD to move the camera THEN camera movement is NOT blocked and works normally

---

## Implementation Notes

*Derived from ADR-0007 Implementation Guidelines:*

**ActionSlot class structure:**
```
class ActionSlot:
    enum State { FREE, WORKING, TRANSPORT }

    - state: State
    - current_action: ManualAction?
    - accumulated_ticks: int
    - total_ticks: int
    - energy_cost: int

    Methods:
    - try_start(action: ManualAction, energy: EnergyPool) -> StartResult
    - advance_ticks(ticks: int) -> ProgressUpdate
    - is_complete() -> bool
    - cancel() -> void
```

**StartResult values:**
- `SUCCESS`
- `BLOCKED_SLOT` — another action is running
- `INSUFFICIENT_ENERGY` — energy < action cost (only when energy > 0)
- `ARCHITECT_LOCKED` — architect mode, this is a gathering action
- `TOOL_REQUIRED` — action needs a tool, none available

**Manual action config table (from GDD):**

| Action | Tick Cost | Energy Cost | Output |
|--------|-----------|-------------|--------|
| Meadow Foraging | 50 | 8 | Randomly drops: 1 Wood (40%), 1 Fiber (40%), 1 Stone (20%) |
| Pick Berries | 40 | 5 | 3 Berries |
 Craft Tool  100  15  1 Tool 
 Chop Tree  80  12  5 Wood (requires tool, deducts charge_cost charge) 
 Mine Stone  60  10  3 Stone (requires tool, deducts charge_cost charge) 

**Tick advancement flow (from ADR-0007):**
```
ticks_advanced(n):
    if ActionSlot.is_free:
        return
    accumulated_ticks += n
    if accumulated_ticks >= total_ticks:
        complete_action()
    action_progress_update.emit(progress, effective_tick_cost, effective_output)
```

**Cost preview tooltip (AC11, AC14):** On tile hover, query the action config for that tile type. If `energy.is_depleted()`, show modified tick cost (×2) and modified output (ceil × 0.5, min 1) with "(depleted)" label. Otherwise show base values.

**Tool requirement (AC16):** Chop Tree and Mine Stone require a tool. Query the shared tool pool in InventorySystem — if no tool exists OR all tools have `current_charge <= 0.0`, block with message "No tool available — craft one first."

**Camera movement (AC18):** WASD camera movement is handled by the Input System + Camera System, NOT by PlayerCharacter. PlayerCharacter only handles tile clicks and drag events. Camera movement must never be blocked by PlayerCharacter state.

**Signals to emit:**
- `action_started(action_id, tick_cost)`
- `action_completed(action_id, output: Array)`
- `action_progress_update(progress, effective_tick_cost, effective_output)`
- `action_failed(action_id, reason)`

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: EnergyPool class (already implemented separately)
- [Story 003]: Drag-and-drop transport (separate interaction from tile-click actions)
- [Story 004]: Food-to-energy consumption (separate from manual labor actions)

---

## QA Test Cases

**AC-1**: Tile click starts manual action
  - Given: Tile with harvestable tree, PlayerCharacter with energy=100, ActionSlot is FREE
  - When: on_tile_clicked(tree_tile_pos)
  - Then: ActionSlot.state = WORKING, accumulated_ticks = 0, total_ticks = 80, energy deducted by 12, action_started signal emitted with action_id=CHOP
  - Edge cases: energy=12 (exact cost) → starts, energy=11 (insufficient) → BLOCKED_SLOT; action_running + another click → action_failed with BLOCKED_SLOT reason

**AC-2**: Action completes at tick cost, spawns resource pin
  - Given: Chop Tree action running, accumulated_ticks=80, total_ticks=80
  - When: advance_ticks(0) (or natural tick accumulation reaches 80)
  - Then: is_complete() = true, action_completed signal emitted with output=[5 Wood], ActionSlot.state = FREE, resource pin spawned on tile via ResourceSystem.spawn_resource()
  - Edge cases: action completes at 0 Energy → output = max(1, ceil(5 × 0.5)) = 3 Wood; action completes during day transition → no interruption, completes normally

**AC-11**: Hover over harvestable tile shows cost preview
  - Given: Player hovers over tree tile, energy=50, not depleted
  - When: get_cost_preview(tile_pos)
  - Then: returns {energy_cost: 12, tick_cost: 80, output: "5 Wood"}
  - Edge cases: energy=0 → {energy_cost: 12, tick_cost: 160, output: "3 Wood (depleted)"}; no tool → blocked with message; action running → still shows preview for other tiles

**AC-13**: Bread consumption at high energy clamps to 100
  - Given: energy=95, player has bread in storage
  - When: consume_food("bread")
  - Then: energy = min(95 + 25, 100) = 100, bread removed from storage, food_consumed signal emitted
  - Edge cases: energy=91 → clamped to 100 (not 116); energy=100 → still consumes food, no energy gain; energy=0 → restores to 25 (still works at depletion)

**AC-14**: Hover at 0 Energy shows depleted values
  - Given: energy=0, player hovers over tree tile
  - When: get_cost_preview(tree_tile_pos)
  - Then: returns {energy_cost: 12, tick_cost: 160, output: "3 Wood (depleted)"}
  - Edge cases: Pick Berries at 0 Energy → {energy_cost: 5, tick_cost: 80, output: "3 Berries (depleted)"} — depletion applies but action still starts (no lockout); Foraging at 0 Energy → {energy_cost: 8, tick_cost: 100, output: "1 random (depleted)"} (random output: ceil(1×0.5)=1)

**AC-16**: Tool-requiring action without tool
  - Given: No tools in inventory, player hovers over tree tile
  - When: get_cost_preview(tree_tile_pos)
  - Then: tooltip shows "No tool available — craft one first", energy_cost and tick_cost shown as 0 or hidden
  - Edge cases: all tools exist but `current_charge <= 0.0` → same message; tools exist with `current_charge > 0.0` → normal preview shown; Craft Tool action does NOT require a tool (it produces one)

**AC-18**: Camera movement not blocked at 0 Energy
  - Given: energy=0, any action state
  - When: player presses WASD
  - Then: camera moves normally (PlayerCharacter does not process WASD — handled by Input System + Camera System)
  - Edge cases: camera works during action running; camera works during drag; camera works during architect mode

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/player_character/action_dispatch_test.gd` — must exist and pass

**Status**: [x] `tests/integration/player_character/action_dispatch_test.gd` — 30 tests, all 7 ACs covered

---

## Dependencies

- Depends on: Story 001 (EnergyPool must be DONE)
- Unlocks: Story 003 (drag-and-drop needs ActionSlot in TRANSPORT state)

---

## Completion Notes
**Completed**: 2026-05-28
**Criteria**: 7/7 passing
**Deviations**:
- ADVISORY: ADR-0007 referenced but file does not exist — pre-existing gap from Story 001
- ADVISORY: `_action_configs`, `FOOD_ENERGY`, `FORAGE_TABLE` hardcoded — pre-existing; address in Story 004
- ADVISORY: `DepletionMod`/`get_depletion_modifier()` defined in Story 001 unused by this story — review in Story 004
**Test Evidence**: Integration — `tests/integration/player_character/action_dispatch_test.gd` (30 tests)
**Code Review**: Complete — dead `_is_gathering()` removed, misleading comment fixed, progress signal tests added
