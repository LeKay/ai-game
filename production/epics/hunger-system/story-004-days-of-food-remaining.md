# Story 004: Days of Food Remaining

> **Epic**: Hunger System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic — ADR-0010
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/hunger-system.md`
**Requirements**: N/A — this is a HUD-facing formula, not a TR-ID. Covered by AC-16, AC-17, AC-18.

**ADR Governing Implementation**: ADR-0010: Hunger System and Debuff Stacking
**ADR Decision Summary**: `get_days_of_food_remaining(total_food_units, daily_requirement)` returns `floor(total_food_units / daily_requirement)`. Division by zero guard: if `daily_requirement == 0` (no NPCs), returns 9999 (`HUNGER_INFINITY` — HUD displays "Unlimited"). This formula is used by the HUD System only — it is NOT used by gameplay logic.

**Engine**: Godot 4.6 | **Risk**: LOW (pure math, no engine APIs)
**Engine Notes**: No post-cutoff APIs. `floor()` is a GDScript built-in. Integer arithmetic only.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/hunger-system.md`, scoped to this story:*

- [ ] **AC-16** GIVEN 30 food units and daily requirement of 2, WHEN `get_days_of_food_remaining(30, 2)` is called THEN the result is 15 days
- [ ] **AC-17** GIVEN 3 food units and daily requirement of 2, WHEN `get_days_of_food_remaining(3, 2)` is called THEN the result is 1 day (floor division — 1.5 floors to 1)
- [ ] **AC-18** GIVEN 0 NPCs (daily requirement = 0) WHEN `get_days_of_food_remaining(total_food, 0)` is called THEN the result is 9999 (displayed as "Unlimited" by HUD)

---

## Implementation Notes

*Derived from ADR-0010 and GDD Implementation Guidelines:*

**Days of food remaining formula (from GDD Formula 4):**
```
const HUNGER_INFINITY: int = 9999

func get_days_of_food_remaining(total_food: int, daily_requirement: int) -> int:
    if daily_requirement == 0:
        return HUNGER_INFINITY
    return floor(total_food / daily_requirement)
```

**Usage (HUD System):**
```
# HUD System calls this on day_transition or when food storage changes:
var total_food := HungerSystem._compute_total_food_units()  # internal, not public API
var npc_count := NPCSystem.get_npc_count()
var requirement := HungerSystem.get_daily_food_requirement(npc_count)
var days := HungerSystem.get_days_of_food_remaining(total_food, requirement)

# Display:
if days >= 9999:
    hud.show_days("Unlimited")
elif days >= 5:
    hud.show_days("Food: %d days remaining" % days)
elif days >= 2:
    hud.show_days("Food: %d days remaining" % days)
elif days >= 1:
    hud.show_days("⚠️ Low food: %d day(s) remaining" % days)
else:
    hud.show_days("⚠️ No food remaining!")
```

**Output range:** [0, 9999]. Floor of 0 = 0. Division by zero guard returns 9999.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Daily consumption and state machine (this story computes a prediction, not consumption)
- Story 003: Consumption priority (how food is deducted is not relevant to this formula)

---

## QA Test Cases

**AC-16**: 30 food / 2 requirement = 15 days
  - Given: total_food = 30, daily_requirement = 2
  - When: get_days_of_food_remaining(30, 2)
  - Then: result = floor(30 / 2) = 15
  - Edge cases: 100 food / 2 = 50; 0 food / 2 = 0; 1 food / 2 = 0 (floor(0.5) = 0, meaning "no full days remaining")

**AC-17**: 3 food / 2 requirement = 1 day (floor)
  - Given: total_food = 3, daily_requirement = 2
  - When: get_days_of_food_remaining(3, 2)
  - Then: result = floor(3 / 2) = 1
  - Edge cases: 4 / 2 = 2 (exact); 5 / 2 = 2 (floor(2.5) = 2); 1 / 2 = 0 (floor(0.5) = 0)

**AC-18**: Division by zero guard
  - Given: daily_requirement = 0
  - When: get_days_of_food_remaining(0, 0)
  - Then: result = HUNGER_INFINITY = 9999
  - Edge cases: get_days_of_food_remaining(30, 0) = 9999 (any food with 0 NPCs = infinite); get_days_of_food_remaining(0, 0) = 9999 (no food AND no NPCs = still infinite, no consumption); this guard must prevent both ZeroDivisionError and the logical error of 0/0 = NaN

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/hunger_system/days_remaining_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None — pure formula, can be tested standalone
- Unlocks: Story 005 (UI displays the days-of-food-remaining value)
