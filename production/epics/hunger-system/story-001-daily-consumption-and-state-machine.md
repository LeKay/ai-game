# Story 001: Daily Consumption and State Machine

> **Epic**: Hunger System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic — ADR-0010
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/hunger-system.md`
**Requirements**:
- `TR-hunger-001` (Daily food consumption: 1 food unit per NPC per day at day transition)

**ADR Governing Implementation**: ADR-0010: Hunger System and Debuff Stacking
**ADR Decision Summary**: HungerSystem is an Autoload singleton (`res://src/gameplay/hunger_system.gd`). Binary state machine: FED/HUNGRY. On `day_transition` from TickSystem, calls `InventorySystem.consume_food(daily_food_requirement)` where `daily_food_requirement = npc_count × npc_food_unit` (npc_food_unit = 1.0 at VS). InventorySystem returns `{hunger_debuff_applied: bool}`. If true → state = HUNGRY, `hunger_tick_multiplier = 2.0`. If false → state = FED, `hunger_tick_multiplier = 1.0`. Defensive guard: `tick_count % 1000 == 0` check before consumption. 0 NPCs = 0 requirement = immediate FED.

**Engine**: Godot 4.6 | **Risk**: LOW (pure GDScript data, stable APIs)
**Engine Notes**: No post-cutoff APIs. Signal subscription in `_enter_tree()`. `Engine.get_singleton()` null-checking for dependency readiness. GDScript static typing for `FoodConsumptionResult` Dictionary keys.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/hunger-system.md`, scoped to this story:*

- [ ] **AC-1** GIVEN 0 NPCs WHEN day transition fires THEN `consume_food(0)` is called, no storage is scanned, the village remains in FED state, and no debuff is applied
- [ ] **AC-2** GIVEN 2 NPCs and 3 food units in storage WHEN day transition fires THEN exactly 2 food units are consumed, `hunger_debuff_applied` is false, and the village remains in FED state
- [ ] **AC-3** GIVEN 2 NPCs and 1 food unit in storage WHEN day transition fires THEN exactly 1 food unit is consumed, remaining_deficit = 1, `hunger_debuff_applied` is true, and the village enters HUNGRY state
- [ ] **AC-4** GIVEN the village is in HUNGRY state WHEN 2 or more food units are added to storage and the next day transition fires THEN consumption succeeds, `hunger_debuff_applied` is false, the village returns to FED state, and the debuff is cleared
- [ ] **AC-5** GIVEN the village is HUNGRY AND exactly enough food exists (food_units == daily_requirement) WHEN the next day transition fires THEN the debuff is NOT applied, the village enters FED state, and `remaining_deficit` = 0

---

## Implementation Notes

*Derived from ADR-0010 Implementation Guidelines:*

**HungerSystem core (from ADR-0010):**
```
const NPC_FOOD_UNIT: float = 1.0

enum DebuffState { FED, HUNGRY }

var state: DebuffState = DebuffState.FED
var hunger_tick_multiplier: float = 1.0
var hunger_debuff_active: bool = false

func get_daily_food_requirement(npc_count: int) -> float:
    return float(npc_count) * NPC_FOOD_UNIT

func apply_daily_consumption() -> void:
    # Guard: only run during actual day transitions
    if _tick.tick_count % 1000 != 0:
        return

    var requirement := get_daily_food_requirement(_npc.get_npc_count())

    # 0 NPCs = 0 requirement = no consumption, stay FED
    if requirement == 0:
        state = DebuffState.FED
        hunger_tick_multiplier = 1.0
        hunger_debuff_active = false
        return

    # Delegate to InventorySystem
    var result: Dictionary = _inventory.consume_food(requirement)

    # Defensive fallback: null/error result → assume hungry
    if result.is_empty() or not result.has("hunger_debuff_applied") or result.get("hunger_debuff_applied", true):
        state = DebuffState.HUNGRY
        hunger_tick_multiplier = 2.0
        hunger_debuff_active = true
        hunger_state_changed.emit(hunger_tick_multiplier)
    else:
        state = DebuffState.FED
        hunger_tick_multiplier = 1.0
        hunger_debuff_active = false
        hunger_state_changed.emit(hunger_tick_multiplier)

func _on_day_transition(_days_elapsed: int) -> void:
    apply_daily_consumption()
    # Emit display update for HUD
    var food_total := _compute_total_food_units()
    var requirement := get_daily_food_requirement(_npc.get_npc_count())
    hunger_display_updated.emit(state == DebuffState.FED, food_total, requirement)
```

**Serialization (from ADR-0010):**
```
func serialize() -> Dictionary:
    return {
        "schema_version": 1,
        "state": state,
        "hunger_tick_multiplier": hunger_tick_multiplier,
        "hunger_debuff_active": hunger_debuff_active,
    }

func deserialize(data: Dictionary) -> void:
    state = data.get("state", DebuffState.FED)
    hunger_tick_multiplier = data.get("hunger_tick_multiplier", 1.0)
    hunger_debuff_active = hunger_tick_multiplier == 2.0
```

**State transition rules:**
- FED → HUNGRY: day transition consumption fails (deficit > 0)
- HUNGRY → FED: day transition consumption succeeds

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: Debuff stacking with energy depletion (state machine is the foundation, stacking is Story 002)
- Story 003: Consumption priority and food unit conversion (Formula 5 logic delegated to InventorySystem, but the guardrails and EC-12 through EC-15 are Story 003)
- Story 004: Days of food remaining calculation and HUD integration (`get_days_of_food_remaining()` is defined in ADR-0010 but implemented here for API completeness; HUD display is Story 004)
- Serialization: `serialize()`/`deserialize()` methods are defined in ADR-0010 but implemented by the Save/Load story, not Story 001

---

## QA Test Cases

**AC-1**: 0 NPCs → FED state
  - Given: 0 NPCs (mock NPC System returning 0), FED state
  - When: day_transition signal fires
  - Then: `get_daily_food_requirement(0)` = 0, consume_food(0) called, no storage scan occurs, state = FED, `hunger_tick_multiplier` = 1.0, `hunger_debuff_active` = false
  - Edge cases: state transition from HUNGRY back to FED (if somehow 0 NPCs at consumption time during previously HUNGRY village); consume_food(0) must return early without scanning any containers; `tick_count % 1000 == 0` guard does not prevent the call (it's a valid day transition)

**AC-2**: 2 NPCs, 3 food → FED, 1 remaining
  - Given: 2 NPCs, storage has 3 berries
  - When: day_transition fires
  - Then: requirement = 2 × 1.0 = 2, consume_food(2) consumes 2 berries, result = {hunger_debuff_applied: false, food_consumed: 2, remaining_deficit: 0}, state = FED, `hunger_tick_multiplier` = 1.0, storage has 1 berry remaining
  - Edge cases: 3 berries = 3 food units, 2 consumed, 1 left; if food was 1 berry + 1 bread = 3 food units → 2 units consumed, 1 bread (2 units) remains; exact match (AC-5) is a separate test

**AC-3**: 2 NPCs, 1 food → HUNGRY
  - Given: 2 NPCs, storage has 1 berry (1 food unit)
  - When: day_transition fires
  - Then: requirement = 2, consume_food(2) consumes 1 berry, result = {hunger_debuff_applied: true, food_consumed: 1, remaining_deficit: 1}, state = HUNGRY, `hunger_tick_multiplier` = 2.0, `hunger_debuff_active` = true
  - Edge cases: storage has 1 bread (2 food units) → consume_food(2) succeeds, FED state (bread covers 2 NPCs); deficit = 1 means 1 food unit short; no partial food units tracked

**AC-4**: Refeed → FED
  - Given: HUNGRY state, 0 food in storage
  - When: player deposits 2 berries into storage
  - When: next day_transition fires
  - Then: requirement = 2, consume_food(2) consumes 2 berries, result = {hunger_debuff_applied: false}, state = FED, `hunger_tick_multiplier` = 1.0, `hunger_debuff_active` = false
  - Edge cases: player deposits only 1 berry → still HUNGRY (deficit = 1); player deposits 5 berries → FED with 3 surplus; state transition from HUNGRY to FED emits `hunger_state_changed(1.0)`

**AC-5**: Exact match → FED
  - Given: 2 NPCs, exactly 2 food units in storage
  - When: day_transition fires
  - Then: requirement = 2, consume_food(2) succeeds with deficit = 0, result = {hunger_debuff_applied: false}, state = FED
  - Edge cases: 2 berries = exact; 1 bread = exact; 1 berry + 1 bread = surplus (FED); `remaining_deficit = 0` is the critical differentiator between AC-3 (deficit > 0 → HUNGRY) and AC-5 (deficit = 0 → FED)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/hunger_system/daily_consumption_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None — state machine and daily requirement calculation can be unit tested with mocked dependencies
- Unlocks: Story 002 (debuff stacking requires the state machine to produce FED/HUNGRY states)

---

## Completion Notes
**Completed**: 2026-06-03
**Criteria**: 5/5 passing
**Deviations**:
- ADVISORY: `hunger_tick_multiplier = 2.0` (HUNGRY value) is an inline literal — could be a named const `HUNGRY_TICK_MULTIPLIER`
- ADVISORY: Story Manifest Version was "N/A" (story pre-dates manifest v2026-05-14); manifest rules are followed in implementation
**Test Evidence**: Logic — `tests/unit/hunger_system/daily_consumption_test.gd` (11 test functions)
**Scope additions**: `inventory_system.gd` consume_food stub signature corrected; `project.godot` HungerSystem Autoload registered
**Code Review**: Skipped — Lean mode
