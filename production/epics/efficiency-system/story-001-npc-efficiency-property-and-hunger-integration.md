# Story 001: NPC Efficiency Property and Hunger Integration

> **Epic**: Efficiency System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**Quick Spec**: `design/quick-specs/efficiency-system-2026-06-03.md`
**Requirement**: `TR-efficiency-001`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0012: Efficiency System — Entity Property and Formula Architecture
**ADR Decision Summary**: NPCData gets `efficiency: float`, `hunger_modifier: float`, `satisfaction_modifier: float`, `equipment_modifier: float` properties. `recalculate_efficiency()` calls `EfficiencyFormulas.calculate_npc_efficiency(h, s, e)`. NPCSystem subscribes to `HungerSystem.hunger_state_changed` and converts the tick_multiplier to a modifier (`hunger_mod = 1.0 / tick_multiplier`), sets it on all NPCs, and calls `recalculate_efficiency()` on each. `EfficiencyFormulas` is a static class at `res://src/systems/efficiency/efficiency_formulas.gd`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `clampf`, `floori`, `maxi` stable since Godot 4.0. Signal connection in `_enter_tree()` with null-check per Foundation pattern (ADR-0012).

**Control Manifest Rules (Feature Layer)**:
- Required: Null-check Autoload references in `_enter_tree()` before signal connection
- Required: Static typing on all public methods
- Forbidden: No hardcoded modifier values — all defaults from EfficiencyFormulas constants

---

## Acceptance Criteria

*From Quick Spec `design/quick-specs/efficiency-system-2026-06-03.md`, scoped to this story:*

- [ ] NPCData (or equivalent NPC entity class) exposes `efficiency: float = 1.0`, `hunger_modifier: float = 1.0`, `satisfaction_modifier: float = 1.0`, `equipment_modifier: float = 1.0`
- [ ] `EfficiencyFormulas.calculate_npc_efficiency(hunger_mod, satisfaction_mod, equipment_mod) -> float` returns `clamp(1.0 × h × s × e, 0.0, 2.0)`
- [ ] NPCData.`recalculate_efficiency()` calls F1 and stores result in `efficiency`
- [ ] NPCSystem subscribes to `HungerSystem.hunger_state_changed(multiplier: float)` in `_enter_tree()` with null guard
- [ ] On `hunger_state_changed(2.0)` (hungry): all NPCs get `hunger_modifier = 0.5`, `efficiency` recalculates to 0.5 (with default sat=1.0, equip=1.0)
- [ ] On `hunger_state_changed(1.0)` (fed): all NPCs get `hunger_modifier = 1.0`, `efficiency` recalculates to 1.0
- [ ] NPC created after hunger_state_changed is emitted still picks up current hunger state (NPCSystem applies modifier to new NPCs on creation)
- [ ] efficiency is clamped: inputs producing result > 2.0 return 2.0; inputs producing result < 0.0 return 0.0

---

## Implementation Notes

*Derived from ADR-0012 Implementation Guidelines:*

**EfficiencyFormulas static class** (`res://src/systems/efficiency/efficiency_formulas.gd`):
```gdscript
class_name EfficiencyFormulas

const EFFICIENCY_MIN: float = 0.0
const EFFICIENCY_MAX: float = 2.0

static func calculate_npc_efficiency(
    hunger_mod: float,
    satisfaction_mod: float,
    equipment_mod: float
) -> float:
    return clampf(1.0 * hunger_mod * satisfaction_mod * equipment_mod,
                  EFFICIENCY_MIN, EFFICIENCY_MAX)
```

**NPCData extension** (add to existing NPCData or NPC entity class):
```gdscript
var hunger_modifier: float = 1.0
var satisfaction_modifier: float = 1.0
var equipment_modifier: float = 1.0
var efficiency: float = 1.0

func recalculate_efficiency() -> void:
    efficiency = EfficiencyFormulas.calculate_npc_efficiency(
        hunger_modifier, satisfaction_modifier, equipment_modifier
    )
```

**NPCSystem hunger integration** (in `_enter_tree()`):
```gdscript
var hunger := Engine.get_singleton("HungerSystem")
if hunger != null:
    hunger.hunger_state_changed.connect(_on_hunger_state_changed)

func _on_hunger_state_changed(new_tick_multiplier: float) -> void:
    var hunger_mod: float = 1.0 / new_tick_multiplier if new_tick_multiplier > 0.0 else 0.0
    for npc in get_all_npcs():
        npc.hunger_modifier = hunger_mod
        npc.recalculate_efficiency()
    _propagate_worker_efficiency_change()  # triggers building recalc (Story 002)
```

**New NPCs**: When an NPC is created (recruited), apply the current hunger state immediately:
```gdscript
func _apply_current_hunger_to_npc(npc: NPCData) -> void:
    var hunger := Engine.get_singleton("HungerSystem")
    if hunger != null:
        var mult: float = hunger.get_hunger_tick_multiplier()
        npc.hunger_modifier = 1.0 / mult if mult > 0.0 else 0.0
    npc.recalculate_efficiency()
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 002]: Building efficiency computation from worker NPC efficiencies
- [Story 003]: BuildingRegistry using building.efficiency for cycle ticks
- [Story 004]: LogisticsSystem using carrier.efficiency for travel ticks
- [Story 005]: JSON config loading and UI threshold constants

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**AC-1**: F1 — basic formula correctness
  - Given: hunger_mod=1.0, satisfaction_mod=1.0, equipment_mod=1.0
  - When: `calculate_npc_efficiency(1.0, 1.0, 1.0)` is called
  - Then: Result = 1.0
  - Edge cases: all modifiers at minimum (0.0) → result = 0.0; all at 1.0 → 1.0; all at 2.0 → clamped to 2.0

**AC-2**: F1 — hunger modifier applied
  - Given: hunger_mod=0.5, satisfaction_mod=1.0, equipment_mod=1.0
  - When: `calculate_npc_efficiency(0.5, 1.0, 1.0)` is called
  - Then: Result = 0.5
  - Edge cases: hunger_mod=0.0 → result = 0.0; hunger_mod=1.5 (future) × equipment_mod=1.5 = 2.25 → clamped to 2.0

**AC-3**: NPCData.recalculate_efficiency stores result
  - Given: NPC with hunger_modifier=0.5, satisfaction_modifier=1.0, equipment_modifier=1.0
  - When: `npc.recalculate_efficiency()` is called
  - Then: `npc.efficiency` == 0.5

**AC-4**: hunger_state_changed(2.0) → all NPCs efficiency=0.5
  - Given: 3 NPCs all with efficiency=1.0, village transitions to HUNGRY (tick_multiplier=2.0)
  - When: `HungerSystem.hunger_state_changed.emit(2.0)` is fired
  - Then: All 3 NPCs have hunger_modifier=0.5 and efficiency=0.5
  - Edge cases: 0 NPCs (empty village) → no error, loop runs 0 iterations; 1 NPC → only that NPC updated

**AC-5**: hunger_state_changed(1.0) → all NPCs efficiency=1.0
  - Given: 2 NPCs with efficiency=0.5 (were hungry), village transitions to FED (tick_multiplier=1.0)
  - When: `HungerSystem.hunger_state_changed.emit(1.0)` is fired
  - Then: Both NPCs have hunger_modifier=1.0 and efficiency=1.0

**AC-6**: New NPC inherits current hunger state
  - Given: Village is HUNGRY (HungerSystem.hunger_tick_multiplier=2.0)
  - When: A new NPC is recruited
  - Then: New NPC has hunger_modifier=0.5 and efficiency=0.5 immediately (not 1.0)
  - Edge cases: Village is FED → new NPC gets hunger_modifier=1.0

**AC-7**: Clamp at boundaries
  - Given: Inputs that would produce efficiency < 0.0 or > 2.0
  - When: `calculate_npc_efficiency(hunger_mod, satisfaction_mod, equipment_mod)` is called
  - Then: Result is clamped to [0.0, 2.0]; never returns negative or > 2.0
  - Edge cases: hunger=0.0 → 0.0; hunger=1.0, equipment=3.0 → clamped to 2.0

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/efficiency/npc_efficiency_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None — EfficiencyFormulas is pure math; NPCData extension is standalone
- Unlocks: Story 002 (building efficiency uses worker NPC efficiencies), Story 004 (carrier travel uses carrier.efficiency)

## Completion Notes
**Completed**: 2026-06-03
**Criteria**: 8/8 passing
**Deviations**: ADVISORY — F2/F3/F4 included in EfficiencyFormulas ahead of Stories 002/004 (inert, ADR-aligned); EFFICIENCY_MIN/MAX as class constants pending Story 005 JSON config override
**Test Evidence**: Logic: `tests/unit/efficiency/npc_efficiency_test.gd` (17 test functions)
**Code Review**: Skipped — Lean mode
