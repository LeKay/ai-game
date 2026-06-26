# Story 003: Production Cycle Integration

> **Epic**: Efficiency System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-05-14

## Context

**Quick Spec**: `design/quick-specs/efficiency-system-2026-06-03.md`
**Requirement**: `TR-efficiency-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0012: Efficiency System — Entity Property and Formula Architecture
**ADR Decision Summary**: BuildingRegistry replaces any direct `hunger_tick_multiplier` read for cycle computation with `EfficiencyFormulas.calculate_effective_cycle_ticks(base_cycle_ticks, building.efficiency)`. The hunger debuff is no longer applied as a direct multiplier on cycle ticks — it flows through `npc.efficiency → building.efficiency → F3`. End result is identical (hungry worker → 2× cycle time) but routed through the unified efficiency layer.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: No post-cutoff APIs. Integer floor division via `floori()` — stable.

**Control Manifest Rules (Feature Layer)**:
- Required: Remove direct `HungerSystem.get_hunger_tick_multiplier()` call from production cycle code
- Forbidden: Do not apply hunger multiplier AND efficiency — pick one path (efficiency path wins)

---

## Acceptance Criteria

*From Quick Spec `design/quick-specs/efficiency-system-2026-06-03.md`, scoped to this story:*

- [ ] BuildingRegistry uses `EfficiencyFormulas.calculate_effective_cycle_ticks(base_ticks, building.efficiency)` for all production cycle tick computation
- [ ] Direct `HungerSystem.get_hunger_tick_multiplier()` calls on building production cycles are removed
- [ ] Hungry worker (efficiency=0.5) → building.efficiency=0.5 → cycle_ticks = floor(base/0.5) = base × 2 (same observable behavior as before)
- [ ] Normal worker (efficiency=1.0) → building.efficiency=1.0 → cycle_ticks = base (no change)
- [ ] Efficient worker (efficiency=1.5) → building.efficiency=1.5 → cycle_ticks = floor(base/1.5) < base
- [ ] Building with efficiency=0.0 (edge case) → cycle_ticks = INT_MAX sentinel (building is frozen; status = STALLED or BLOCKED per Building System rules)
- [ ] Base cycle time example: base=100, building.efficiency=0.55 → effective = floor(100/0.55) = 181 ticks

---

## Implementation Notes

*Derived from ADR-0012 Implementation Guidelines:*

**F3 in EfficiencyFormulas** (add to `efficiency_formulas.gd`):
```gdscript
static func calculate_effective_cycle_ticks(base_ticks: int, building_efficiency: float) -> int:
    if building_efficiency <= 0.0:
        return 2147483647  # INT_MAX sentinel: building is frozen
    return maxi(1, floori(float(base_ticks) / building_efficiency))
```

**BuildingRegistry production cycle change** — locate where production cycle ticks are set.
Current code (approximate):
```gdscript
# BEFORE — direct hunger multiplier read:
var effective_ticks: int = base_cycle_ticks
if HungerSystem.is_hunger_debuff_active():
    effective_ticks = base_cycle_ticks * 2
```

Replace with:
```gdscript
# AFTER — route through efficiency:
var effective_ticks: int = EfficiencyFormulas.calculate_effective_cycle_ticks(
    base_cycle_ticks, building.efficiency
)
```

**INT_MAX sentinel handling**: If `calculate_effective_cycle_ticks` returns `2147483647`, the building should be treated as unable to advance production. The existing STALLED/BLOCKED states in the Building System FSM (ADR-0008) are the correct output — do not add new states. Only set if building.efficiency reaches 0.0, which requires all workers at exactly 0.0 efficiency (requires hunger_mod × equipment_mod × sat_mod = 0.0 for all workers).

**Regression guard**: The integration test must assert that the Hunger System path still produces the same result as before. The observable contract is: hungry village → production building takes 2× as many ticks per cycle.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: NPC efficiency and hunger integration
- [Story 002]: Building efficiency computation
- [Story 004]: Carrier travel integration (separate integration point)
- [Story 005]: Config values

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**AC-1**: F3 — base case (efficiency=1.0, no change)
  - Given: base_cycle_ticks=100, building.efficiency=1.0
  - When: `calculate_effective_cycle_ticks(100, 1.0)` is called
  - Then: Result = 100
  - Edge cases: base=1, eff=1.0 → 1; base=1000, eff=1.0 → 1000

**AC-2**: F3 — hungry worker (efficiency=0.5, 2× slower)
  - Given: base_cycle_ticks=100, building.efficiency=0.5
  - When: `calculate_effective_cycle_ticks(100, 0.5)` is called
  - Then: Result = floor(100/0.5) = 200
  - Edge cases: base=1 → floor(1/0.5) = 2; base=999 → floor(999/0.5) = 1998

**AC-3**: F3 — efficient worker (efficiency=1.5, faster)
  - Given: base_cycle_ticks=100, building.efficiency=1.5
  - When: `calculate_effective_cycle_ticks(100, 1.5)` is called
  - Then: Result = floor(100/1.5) = 66
  - Edge cases: base=100, eff=2.0 → floor(100/2.0) = 50 (half time at max efficiency)

**AC-4**: F3 — minimum 1 tick guardrail
  - Given: base_cycle_ticks=1, building.efficiency=2.0
  - When: `calculate_effective_cycle_ticks(1, 2.0)` is called
  - Then: Result = maxi(1, floor(1/2.0)) = maxi(1, 0) = 1
  - Edge cases: floor always returns ≥ 0; maxi(1, ...) ensures minimum 1

**AC-5**: F3 — zero efficiency sentinel
  - Given: building.efficiency=0.0
  - When: `calculate_effective_cycle_ticks(100, 0.0)` is called
  - Then: Result = 2147483647 (INT_MAX), no division-by-zero error
  - Edge cases: negative efficiency (should never occur after clamp, but guard handles it)

**AC-6**: Integration — hungry village → 2× production time (regression)
  - Given: Building with 1 assigned worker; village transitions to HUNGRY
  - When: `HungerSystem.hunger_state_changed.emit(2.0)` fires, then production cycle starts
  - Then: effective_cycle_ticks == base_cycle_ticks × 2
  - This is the critical regression test — behavior must match pre-efficiency-system hunger debuff

**AC-7**: Integration — direct hunger read removed from BuildingRegistry
  - Given: BuildingRegistry source code
  - When: grep for `get_hunger_tick_multiplier` in building production cycle path
  - Then: Zero matches found (it is only used for Player Character, not buildings)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/efficiency/production_cycle_efficiency_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (building.efficiency must be computed and current before cycle computation reads it)
- Unlocks: Story 005 (config values affect cycle behavior)
