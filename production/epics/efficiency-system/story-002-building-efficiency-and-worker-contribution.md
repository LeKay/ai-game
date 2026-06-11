# Story 002: Building Efficiency and Worker Contribution

> **Epic**: Efficiency System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**Quick Spec**: `design/quick-specs/efficiency-system-2026-06-03.md`
**Requirement**: `TR-efficiency-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0012: Efficiency System — Entity Property and Formula Architecture
**ADR Decision Summary**: BuildingData gets `efficiency: float = 1.0` and `upgrade_bonus: float = 0.0`. `recalculate_efficiency(workers: Array)` calls `EfficiencyFormulas.calculate_building_efficiency(worker_efficiencies, upgrade_bonus)`. BuildingRegistry calls `recalculate_efficiency()` when a worker is assigned or unassigned. NPCSystem calls `_propagate_worker_efficiency_change()` after updating NPC efficiencies (from Story 001).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: No post-cutoff APIs. Array iteration over worker list.

**Control Manifest Rules (Feature Layer)**:
- Required: Static typing on `worker_efficiencies: Array[float]`
- Required: Building recalculate called on every worker assignment change — not deferred

---

## Acceptance Criteria

*From Quick Spec `design/quick-specs/efficiency-system-2026-06-03.md`, scoped to this story:*

- [ ] BuildingData (or equivalent building instance class) exposes `efficiency: float = 1.0` and `upgrade_bonus: float = 0.0`
- [ ] `EfficiencyFormulas.calculate_building_efficiency(worker_efficiencies: Array[float], upgrade_bonus: float) -> float` returns `clamp(1.0 + Σ(w − 1.0) + upgrade_bonus, 0.0, 2.0)`
- [ ] `BuildingData.recalculate_efficiency(assigned_workers)` collects worker efficiencies and calls F2
- [ ] Building with no workers: efficiency = 1.0 (base only)
- [ ] Building with one worker at efficiency=0.5 (hungry): building.efficiency = 0.5
- [ ] Building with one worker at efficiency=1.2: building.efficiency = 1.2
- [ ] Building with two workers at 1.2 and 0.8: efficiency = 1.0 (deltas cancel: +0.2 − 0.2)
- [ ] Building with two workers both at 1.5: efficiency = 2.0 (clamped from 2.0)
- [ ] BuildingRegistry calls `recalculate_efficiency()` when a worker is assigned or unassigned
- [ ] upgrade_bonus = 0.0 at Vertical Slice scope — field exists but has no effect until Upgrade System

---

## Implementation Notes

*Derived from ADR-0012 Implementation Guidelines:*

**F2 in EfficiencyFormulas** (add to `efficiency_formulas.gd` from Story 001):
```gdscript
static func calculate_building_efficiency(
    worker_efficiencies: Array[float],
    upgrade_bonus: float
) -> float:
    var delta: float = 0.0
    for eff in worker_efficiencies:
        delta += (eff - 1.0)
    return clampf(1.0 + delta + upgrade_bonus, EFFICIENCY_MIN, EFFICIENCY_MAX)
```

**BuildingData extension** (add to existing BuildingData or building instance):
```gdscript
var upgrade_bonus: float = 0.0  # 0.0 at VS scope; future UpgradeSystem sets this
var efficiency: float = 1.0

func recalculate_efficiency(assigned_workers: Array) -> void:
    var worker_efficiencies: Array[float] = []
    for worker in assigned_workers:
        worker_efficiencies.append(worker.efficiency)
    efficiency = EfficiencyFormulas.calculate_building_efficiency(
        worker_efficiencies, upgrade_bonus
    )
```

**BuildingRegistry hooks** — call recalculate on any worker assignment change:
```gdscript
func assign_worker_to_building(npc: NPCData, building: BuildingData) -> void:
    # ... existing assignment logic ...
    building.recalculate_efficiency(get_assigned_workers(building))

func unassign_worker_from_building(npc: NPCData, building: BuildingData) -> void:
    # ... existing unassignment logic ...
    building.recalculate_efficiency(get_assigned_workers(building))
```

**NPCSystem propagation hook** (called from Story 001's _on_hunger_state_changed):
```gdscript
func _propagate_worker_efficiency_change() -> void:
    var building_registry := Engine.get_singleton("BuildingRegistry")
    if building_registry == null:
        return
    for building in building_registry.get_all_buildings():
        building.recalculate_efficiency(get_assigned_workers_for_building(building.id))
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: NPC efficiency property and hunger integration (worker.efficiency must exist before this story)
- [Story 003]: BuildingRegistry using building.efficiency for cycle tick computation
- [Story 005]: JSON config for upgrade_bonus values

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**AC-1**: F2 — no workers
  - Given: worker_efficiencies=[], upgrade_bonus=0.0
  - When: `calculate_building_efficiency([], 0.0)` is called
  - Then: Result = 1.0 (base only, no delta)
  - Edge cases: empty array; upgrade_bonus=0.25 with no workers → 1.25

**AC-2**: F2 — hungry worker
  - Given: worker_efficiencies=[0.5], upgrade_bonus=0.0
  - When: `calculate_building_efficiency([0.5], 0.0)` is called
  - Then: Result = 1.0 + (0.5 − 1.0) = 0.5
  - Edge cases: worker_efficiencies=[0.0] → 1.0 + (0.0 − 1.0) = 0.0 (clamped to 0.0)

**AC-3**: F2 — efficient worker
  - Given: worker_efficiencies=[1.2], upgrade_bonus=0.0
  - When: `calculate_building_efficiency([1.2], 0.0)` is called
  - Then: Result = 1.0 + (1.2 − 1.0) = 1.2

**AC-4**: F2 — two workers with cancelling deltas
  - Given: worker_efficiencies=[1.2, 0.8], upgrade_bonus=0.0
  - When: `calculate_building_efficiency([1.2, 0.8], 0.0)` is called
  - Then: Result = 1.0 + 0.2 + (−0.2) = 1.0

**AC-5**: F2 — clamp at maximum
  - Given: worker_efficiencies=[1.5, 1.5], upgrade_bonus=0.0
  - When: `calculate_building_efficiency([1.5, 1.5], 0.0)` is called
  - Then: Raw = 1.0 + 0.5 + 0.5 = 2.0 → result = 2.0 (exactly at cap, not clamped beyond)
  - Edge cases: [2.0, 2.0] → raw = 3.0 → clamped to 2.0

**AC-6**: BuildingRegistry triggers recalculate on assign
  - Given: Building with no workers (efficiency=1.0); NPC with efficiency=0.5 (hungry)
  - When: NPC is assigned to building via BuildingRegistry
  - Then: building.efficiency == 0.5 immediately after assignment

**AC-7**: BuildingRegistry triggers recalculate on unassign
  - Given: Building with one worker at efficiency=0.5 (building.efficiency=0.5)
  - When: NPC is unassigned from building via BuildingRegistry
  - Then: building.efficiency == 1.0 (back to base with no workers)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/efficiency/building_efficiency_test.gd` — must exist and pass

**Status**: [x] `tests/unit/efficiency/building_efficiency_test.gd` — 15 test functions

---

## Dependencies

- Depends on: Story 001 (NPCData.efficiency must exist; NPCSystem._propagate_worker_efficiency_change hook must be present)
- Unlocks: Story 003 (production cycle uses building.efficiency)

---

## Completion Notes
**Completed**: 2026-06-04
**Criteria**: 10/10 passing
**Deviations**: None
**Test Evidence**: Logic — `tests/unit/efficiency/building_efficiency_test.gd` (15 tests, AC-1 through AC-7)
**Code Review**: Skipped (Lean mode)
