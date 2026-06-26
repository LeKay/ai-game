# Story 001: Energy Pool

> **Epic**: Player Character System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/player-character-system.md`
**Requirement**: `TR-player-001` (Energy pool (0–100) with tick-based drain and depletion penalties)

**ADR Governing Implementation**: ADR-0007: Player Character Energy Model and Manual Action System
**ADR Decision Summary**: Player Character is a Foundation Autoload singleton (`player_character.gd`) with an `EnergyPool` class managing current/max energy (int, clamped to [0, 100]). Two spend methods: `try_spend()` for normal operation (returns false if insufficient), `spend_unchecked()` for 0-energy state (deducts, clamps to 0). `restore()` for food refill. Depletion state is a boolean flag (`current == 0`), not a separate state.

**Engine**: Godot 4.6 | **Risk**: HIGH (verification required: `_process()` at 144fps, `Tween` in 4.6)
**Engine Notes**: Post-cutoff APIs used are stable since Godot 1.0 (`_process`, `Signal`, `Tween`, `Timer`). Verify that `_process()` accumulator for tick-based action progress works correctly at 144fps; verify `Tween` API compatibility for energy bar visual feedback in 4.6.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/player-character-system.md`, scoped to this story:*

- [ ] **AC1** Energy pool clamps to [0, 100] on all operations — `restore(200)` with max=100 → assert current = 100, `spend_unchecked(200)` with current=50 → assert current = 0
- [ ] **AC2** `try_spend(amount)` returns false when `current < amount` (energy > 0), returns true and deducts when sufficient
- [ ] **AC3** `spend_unchecked(amount)` always succeeds, clamps to 0 if insufficient
- [ ] **AC4** `is_depleted()` returns true only when `current == 0`
- [ ] **AC5** `get_depletion_modifier()` returns `{tick_multiplier: 2.0, output_multiplier: 0.5}` when depleted, `{tick_multiplier: 1.0, output_multiplier: 1.0}` when not

---

## Implementation Notes

*Derived from ADR-0007 Implementation Guidelines:*

**EnergyPool class structure:**
```
class EnergyPool:
	- current: int       # [0, max], clamped on all operations
	- max: int = 100    # configurable knob
	- depletion_flag: bool  # true when current == 0

	Methods:
	- try_spend(amount: int) -> bool       # check + deduct, returns false if insufficient
	- spend_unchecked(amount: int) -> void  # deduct and clamp to 0
	- restore(amount: int) -> void         # add and clamp to max
	- get_depletion_modifier() -> DepletionMod
	- is_depleted() -> bool
```

**Key rules:**
- `try_spend()` is used during normal operation (energy > 0). If it returns false, the action is blocked.
- `spend_unchecked()` is used at 0 Energy — the action proceeds, energy is deducted to 0 (already there), and depletion modifiers apply.
- `restore()` is called when the player eats food. Clamped to [0, max].
- Energy is deducted at **action start**, not gradually during action execution.
- `is_depleted()` is simply `current == 0`.

**Signals to emit:**
- `energy_changed(current: int, max: int)` on every energy operation
- `energy_depletion_changed(is_depleted: bool)` when depletion flag transitions

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 002]: Action dispatch (tile clicks, action slot, cost preview UI)
- [Story 004]: Depletion penalty application to actions, food-to-energy refill mechanics

---

## QA Test Cases

**AC-1**: Energy pool clamps to [0, 100] on all operations
  - Given: EnergyPool with max=100, current=0
  - When: restore(200)
  - Then: current = 100 (clamped)
  - Edge cases: restore(50) with current=70 → current=100 (partial clamp); restore(0) → no change; restore(100) with current=0 → current=100

**AC-2**: try_spend returns false when insufficient
  - Given: EnergyPool with current=50, max=100
  - When: try_spend(60)
  - Then: returns false, current still 50
  - Edge cases: try_spend(50) with current=50 → returns true, current=0; try_spend(1) with current=1 → returns true, current=0; try_spend(1) with current=0 → returns false

**AC-3**: spend_unchecked always succeeds
  - Given: EnergyPool with current=50, max=100
  - When: spend_unchecked(200)
  - Then: current = 0, no error thrown
  - Edge cases: spend_unchecked(0) → no change; spend_unchecked(1) with current=0 → no change

**AC-4**: is_depleted returns correct state
  - Given: EnergyPool with current=0
  - When: is_depleted()
  - Then: returns true
  - Edge cases: current=1 → false; current=50 → false; current=100 → false; current transitions 1→0 → is_depleted() flips true

**AC-5**: get_depletion_modifier returns correct values
  - Given: EnergyPool with current=0
  - When: get_depletion_modifier()
  - Then: {tick_multiplier: 2.0, output_multiplier: 0.5}
  - Edge cases: current=1 → {tick_multiplier: 1.0, output_multiplier: 1.0}; current=50 → same; values are constants, not computed

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/player_character/energy_pool_test.gd` — must exist and pass

**Status**: [x] `tests/unit/player_character/energy_pool_test.gd` — 15 tests, all 5 ACs covered

---

## Dependencies

- Depends on: None
- Unlocks: Story 002 (action dispatch needs EnergyPool), Story 004 (depletion/food needs EnergyPool)

---

## Completion Notes
**Completed**: 2026-05-28
**Criteria**: 5/5 passing (all auto-verified from implementation)
**Deviations**:
- ADVISORY: `max_energy = 100` and depletion multipliers (2.0/0.5) hardcoded — should be data-driven per coding standards. Address in Story 004 or config pass.
- ADVISORY: ADR-0007 §Core Design references `res://src/core/player_character.gd`; actual path is `res://src/systems/player_character.gd`. ADR should be corrected.
**Test Evidence**: Logic — `tests/unit/player_character/energy_pool_test.gd` (15 tests, 5 ACs covered)
**Code Review**: APPROVED WITH SUGGESTIONS (lean mode — LP-CODE-REVIEW skipped)
