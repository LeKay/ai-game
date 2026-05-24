# Story 003: Consumption Priority and Guardrails

> **Epic**: Hunger System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Integration — ADR-0010
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/hunger-system.md`
**Requirements**:
- `TR-hunger-004` (Food unit conversion: Berry = 1 unit, Bread = 2 units)

**ADR Governing Implementation**: ADR-0010: Hunger System and Debuff Stacking
**ADR Decision Summary**: Consumption priority (lowest-quantity-first, then lower index) is delegated to `InventorySystem.consume_food()`. The Hunger System computes food units using `resource_food_unit` mapping (berry = 1.0, bread = 2.0). Defensive guards: `tick_count % 1000 == 0` ensures consume_food() only runs during day transitions; 0 NPCs = 0 requirement = immediate exit; null/error result from InventorySystem → defaults to HUNGRY (defensive fallback). Mid-day NPC spawns don't trigger mid-day consumption (only evaluated at next day transition).

**Engine**: Godot 4.6 | **Risk**: LOW (signal subscription, simple formula)
**Engine Notes**: No post-cutoff APIs. `_compute_total_food_units()` iterates containers internally — not a public API. Food unit lookup via match on StringName resource_id.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/hunger-system.md`, scoped to this story:*

- [ ] **AC-10** GIVEN two storage containers with food quantities [3 berries, 50 bread] WHEN hunger consumes 10 food units THEN the 3-berry slot is emptied first (3 food units, requirement remaining: 7), then bread slots are consumed next (4 bread = 8 food units, surplus of 1). Total: 3 berries + 4 bread consumed. The InventorySystem's consume_food() interface implements lowest-quantity-first priority.
- [ ] **AC-11** GIVEN two food slots with equal quantity (5 berries each) at different indices WHEN hunger consumes THEN the slot at the lower index is consumed first
- [ ] **AC-12** GIVEN no NPCs on Day 1 WHEN day transition fires THEN consume_food(0) exits immediately, no storage is scanned, no debuff is applied, and state = FED
- [ ] **AC-13** GIVEN 1 NPC spawned mid-day (after day transition) WHEN the day transitions THEN the consumption does NOT fire until the next day transition, and the new NPC count is reflected at that next transition
- [ ] **AC-14** GIVEN `consume_food()` is called outside a day transition (tick_count mod 1000 != 0) WHEN it is called directly THEN it returns immediately as a no-op with no food consumed and no state change
- [ ] **AC-15** GIVEN the InventorySystem's `consume_food()` interface returns an error or null WHEN day transition fires THEN the hunger system defaults to HUNGRY state (defensive fallback)

---

## Implementation Notes

*Derived from ADR-0010 and GDD Implementation Guidelines:*

**Food unit conversion (from GDD Formula 3):**
```
func _get_food_unit_value(resource_id: StringName) -> float:
    match resource_id:
        "bread": return 2.0
        _: return 1.0  # default: 1 unit per berry

# Total food units across all containers:
func _compute_total_food_units() -> int:
    var total: int = 0
    var vs_foods: Array[StringName] = ["berry", "bread"]
    for container_id in _inventory.get_all_containers():
        var container := _inventory.get_container(container_id)
        for slot in container.get_slots():
            if vs_foods.has(slot.resource_id):
                var food_units := slot.quantity * _get_food_unit_value(slot.resource_id)
                total += food_units
    return total
```

**Daily food requirement (from GDD Formula 1):**
```
func get_daily_food_requirement(npc_count: int) -> int:
    return npc_count * NPC_FOOD_UNIT  # NPC_FOOD_UNIT = 1
```

**Guard logic in apply_daily_consumption():**
```
func apply_daily_consumption() -> void:
    # Guard 1: tick mod 1000 check
    if _tick.tick_count % 1000 != 0:
        return

    # Guard 2: 0 NPCs = 0 requirement = FED
    var requirement := get_daily_food_requirement(_npc.get_npc_count())
    if requirement == 0:
        state = DebuffState.FED
        hunger_tick_multiplier = 1.0
        hunger_debuff_active = false
        return

    # Guard 3: defensive fallback on null/error result
    var result: Dictionary = _inventory.consume_food(requirement)
    if result.is_empty() or not result.has("hunger_debuff_applied") or result.get("hunger_debuff_applied", true):
        state = DebuffState.HUNGRY
        hunger_tick_multiplier = 2.0
        hunger_debuff_active = true
    else:
        state = DebuffState.FED
        hunger_tick_multiplier = 1.0
        hunger_debuff_active = false
```

**Consumption priority** is delegated to InventorySystem.consume_food(). The Hunger System does not define its own deduction algorithm — it only provides the requirement argument and reads back the result.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Core state machine and daily consumption (this story covers edge cases and guards)
- Story 002: Debuff stacking and propagation (the guards are pre-consumption; debuff effect is Story 002)
- Story 004: Days of food remaining (HUD formula, not consumption)

---

## QA Test Cases

**AC-10**: Consumption priority — lowest quantity first
  - Given: Storage A: 3 berries, Storage B: 50 bread, requirement = 10 food units
  - When: consume_food(10) is called (delegated to InventorySystem)
  - Then: 3 berries consumed first (3 food units, Storage A cleared), 7 bread consumed next (14 food units from bread... wait, 7 bread = 14 food units. Total = 3 + 14 = 17 food units. But requirement is 10. So: 3 from berries, need 7 more → 7/2 = 3.5 bread → floor to 3 bread = 6 food units? No — the InventorySystem handles the exact math. The Hunger System just provides `requirement = 10`.)
  - Clarification: requirement is in food units (10). InventorySystem consumes 3 berries = 3 food units. Remaining need = 7. Bread = 2 units each → consume 4 bread = 8 food units. Total consumed = 11 food units (surplus of 1). Actually: InventorySystem Formula 5 determines exact consumption. The key assertion: **lowest-quantity slot (3 berries) is consumed before higher-quantity slot (50 bread)**
  - Result: Storage A has 0 berries, Storage B has 46 bread (assuming InventorySystem consumed 4 bread = 8 units, total 11 ≥ 10)
  - Edge cases: both containers equal quantity → lower index consumed first (AC-11); multiple containers with mixed food types → lowest total food units per slot consumed first

**AC-11**: Equal quantity — lower index first
  - Given: Slot 1: 5 berries, Slot 2: 5 berries (different container indices)
  - When: consume_food(5) is called
  - Then: Slot 1 is consumed first (entire 5 berries consumed), Slot 2 is untouched
  - Edge cases: different indices but same quantity is the tiebreak condition; if slots are in different containers, container index determines tiebreak order

**AC-12**: 0 NPCs = FED
  - Given: 0 NPCs, FED state, any amount of food in storage
  - When: day_transition fires
  - Then: requirement = 0, consume_food(0) exits immediately, no storage containers are scanned, state = FED, no signal emitted
  - Edge cases: storage has 0 food → still FED (no NPCs to feed); storage has 1000 food → still FED (no NPCs to feed); state transition from HUNGRY to FED when NPC count drops to 0 (should not happen at VS — NPCs don't get removed except via house demolition, and if all NPCs are removed, requirement = 0 → FED)

**AC-13**: Mid-day NPC spawn
  - Given: Day transition at tick 1000 (Day 1 → Day 2) consumed food for 0 NPCs, then at tick 500 of Day 2 (global tick 1500), an NPC is recruited
  - When: next day transition fires (tick 2000, Day 2 → Day 3)
  - Then: requirement = 1 × 1.0 = 1, consume_food(1) is called with 1 NPC, the newly recruited NPC's food requirement is reflected
  - Edge cases: NPC recruited at tick 1999 (1 tick before next day transition) → requirement already includes NPC at next transition; NPC recruited and removed on same day → NPC count at consumption time determines requirement

**AC-14**: consume_food guard
  - Given: Tick count = 500 (not a day transition, 500 % 1000 ≠ 0)
  - When: apply_daily_consumption() is called directly
  - Then: function returns immediately, no food consumed, no state change, no signals emitted
  - Edge cases: tick = 999 → no consumption (999 % 1000 ≠ 0); tick = 1000 → consumption runs (1000 % 1000 = 0); tick = 2000 → consumption runs (2000 % 1000 = 0); guard is a safety net against spurious day_transition signals

**AC-15**: Defensive fallback
  - Given: InventorySystem.consume_food() returns null or an empty Dictionary
  - When: day transition fires
  - Then: HungerSystem defaults to HUNGRY state, hunger_tick_multiplier = 2.0, hunger_debuff_active = true, hunger_state_changed signal emitted
  - Edge cases: result missing "hunger_debuff_applied" key → HUNGRY; result with "hunger_debuff_applied" = null → HUNGRY (false-y value); this is intentional — "assume hungry if we can't verify fed"

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/hunger_system/consumption_priority_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (state machine must be functional to test guards in context of state transitions)
- Unlocks: None — this is the final integration story for Hunger System core behavior
