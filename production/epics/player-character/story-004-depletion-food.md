# Story 004: Depletion Penalty and Food Refill

> **Epic**: Player Character System
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic — ADR-0007
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/player-character-system.md`
**Requirements**:
- `TR-player-004` (Energy depletion penalty at 0 energy: 2x tick cost + ceil(output * 0.5) minimum 1)
- `TR-player-005` (Food-to-energy refill: consuming food restores energy based on food type)

**ADR Governing Implementation**: ADR-0007: Player Character Energy Model and Manual Action System
**ADR Decision Summary**: Energy depletion is a flag (`current == 0`), not a separate state. When depleted at action start: `effective_tick_cost = base × 2.0`, `effective_output = max(1, ceil(base × 0.5))`. Energy cost is NOT modified — the player still pays the base energy cost (deducted, clamped to 0). Actions are never locked out at 0 Energy. Food consumption (`restore()`) instantly restores energy: berry = +10, bread = +25, clamped to max 100. Eating occupies the action slot (no tick cost but slot is blocked). Depletion penalty does NOT retroactively apply to actions already running.

**Engine**: Godot 4.6 | **Risk**: HIGH (same as ADR-0007)
**Engine Notes**: Depletion modifier computation is pure math — no engine API dependencies. The `ceil()` function and `max()` are standard GDScript. Verify `_process()` accumulator behavior at 144fps for the tick cost doubling.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/player-character-system.md`, scoped to this story:*

- [ ] **AC5** GIVEN the player has 0 Energy WHEN the player attempts to start a manual action with insufficient energy THEN the action is blocked and the energy bar displays the depleted state with subtitle text. At 0 Energy, actions with sufficient energy CAN start with depletion penalties applied.
- [ ] **AC6** GIVEN the player has 0 Energy WHEN the player initiates eating food THEN energy is instantly restored by the food's value (berry +10, bread +25) clamped to max 100 and the action slot is occupied (even though the eat action has no tick cost)
- [ ] **AC7** GIVEN the player is at 0 Energy WHEN a new action is started THEN tick cost is doubled and output is `max(1, ceil(base_output × 0.5))` per the Energy Depletion Modifier formula
- [ ] **AC8** GIVEN a manual action is running WHEN the player's energy drops to 0 during the action THEN the action completes at base cost and base output (depletion penalty does not retroactively apply)
- [ ] **AC9** GIVEN a day transition occurs WHEN a manual action or transport is running THEN the action continues without interruption and tick progress is preserved

---

## Implementation Notes

*Derived from ADR-0007 Implementation Guidelines:*

**Depletion modifier application (AC5, AC7):**

```
get_depletion_modifier():
    if energy.is_depleted():
        return {
            tick_multiplier: 2.0,
            output_multiplier: 0.5
        }
    return {
        tick_multiplier: 1.0,
        output_multiplier: 1.0
    }
```

**Effective values computed at action start:**
```
effective_tick_cost = int(base_tick_cost × modifier.tick_multiplier)
effective_output = max(1, ceil(base_output × modifier.output_multiplier))
```

**Key rules:**
- Depletion is checked at action **start**, not during action execution. If energy is > 0 when `try_start()` is called, the action starts at base values. If energy = 0, the depletion modifiers apply.
- Energy cost is **never** modified by depletion — only tick cost and output.
- The action slot is always available at 0 Energy — no lockout.
- `is_depleted()` is simply `energy.current == 0`.

**Action-in-progress immunity (AC8):**

```
# When action is already running and energy drops to 0:
# The action started at base values — those values are locked at start.
# Depletion only affects NEW actions started after the energy hit 0.
```

The `effective_tick_cost` and `effective_output` are set on the `ProgressUpdate` at action start and never change during the action's lifetime.

**Food consumption (AC6):**

```
# Food types and energy restoration:
#   berry → +10 energy
#   bread → +25 energy

# Eating has 0 tick cost but occupies the action slot.
# It runs as an action that completes instantly (total_ticks = 0).
# The action slot is blocked during this time — no other actions can start.
# Energy is restored instantly (no animation delay).
```

**Food source (from GDD Rule 6):** Food is consumed from whichever container it currently resides in (tile drop pin or storage building). If food is on a tile pin, the player can eat it by clicking the pin. If food is in storage, eating requires the storage UI.

**Day transition handling (AC9):** From GDD Rule 7 — the player character persists across day boundaries. Energy, tick state, and pending manual actions are unaffected by day transitions. The Tick System fires `day_transition` at tick 1000 → tick 0. Player character subscribes to this signal but performs no action (subscribe for notification only). Running actions continue uninterrupted.

**Energy values (from GDD):**
- Max energy: 100
- Berry restore: +10
- Bread restore: +25

**Signals to emit:**
- `energy_depletion_changed(is_depleted: bool)` when depletion flag transitions
- `food_consumed(food_type, energy_restored)` when food is eaten

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: EnergyPool class (already implemented — just consumes this story's depletion behavior)
- [Story 002]: Action dispatch (this story handles the *penalty* applied to dispatched actions, not the dispatch mechanism itself)
- [Story 005]: Architect mode (unrelated to depletion/food)

---

## QA Test Cases

**AC5**: 0 Energy allows actions with depletion, insufficient energy blocks
  - Given: energy = 0, action slot FREE
  - When: try_start(Pick Berries, energy_pool)
  - Then: starts with depletion modifiers (tick_cost = 80, output = 3), energy = 0 (clamped), action_started signal emitted
  - Edge cases: energy = 0, action requires 5 energy → starts anyway (spend_unchecked), depletion applies; energy = 5, action requires 5 energy → starts normally (not depleted, energy is sufficient); energy = 0 → is_depleted() = true

**AC6**: Food consumption at 0 energy
  - Given: energy = 0, action slot FREE, player has berries
  - When: consume_food("berry")
  - Then: action slot occupied, energy restored to 10, food_consumed signal emitted with food_type="berry", energy_restored=10
  - Edge cases: energy = 0, eat bread → energy = 25; energy = 95, eat bread → energy = 100 (clamped), food still consumed; eating occupies action slot — no other action can start during eat

**AC7**: Depletion penalty applied to new actions
  - Given: energy = 0, action slot FREE, player attempts Chop Tree (base: 80 ticks, 5 Wood)
  - When: ActionSlot.try_start() with depleted EnergyPool
  - Then: effective_tick_cost = 80 × 2 = 160, effective_output = max(1, ceil(5 × 0.5)) = max(1, 3) = 3
  - Edge cases: Pick Berries at 0 Energy → effective_output = max(1, ceil(3 × 0.5)) = 3; Foraging at 0 Energy → effective_output = max(1, ceil(1 × 0.5)) = 1; Craft Tool at 0 Energy → output = 1 (same, producing 1 tool); Mine Stone at 0 Energy → effective_output = max(1, ceil(3 × 0.5)) = 2

**AC8**: Action running at energy drop to 0 — no retroactive penalty
  - Given: energy = 50, Chop Tree running (80 ticks, 5 Wood, effective values locked at start)
  - When: energy drops to 0 during action (e.g., another action consumed energy? No — energy is deducted at action start only. So to test this: start action at energy=12, it costs 12, energy drops to 0 mid-action)
  - Then: action completes at base values (80 ticks → 5 Wood), NOT depleted values
  - Edge cases: action at 50% progress when energy hits 0 → completes at base; action just started (0% progress) when energy hits 0 → still completes at base; action was started at 0 Energy → uses depletion values (was already depleted at start)

**AC9**: Day transition during running action
  - Given: Chop Tree action running, accumulated_ticks = 40, total_ticks = 80
  - When: day_transition signal fires
  - Then: action continues, accumulated_ticks stays at 40 (not reset), tick counter keeps accumulating on next ticks_advanced event
  - Edge cases: day transition during transport → transport continues; day transition at action start (accumulated_ticks = 0) → starts normally; day transition with energy = 0 → depletion penalty preserved

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/player_character/depletion_food_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (EnergyPool must be DONE)
- Unlocks: None directly — depletion logic feeds into Story 002's action dispatch (which consumes the modifier)
