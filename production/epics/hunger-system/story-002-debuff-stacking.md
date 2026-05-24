# Story 002: Debuff Stacking

> **Epic**: Hunger System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Integration — ADR-0010
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/hunger-system.md`
**Requirements**:
- `TR-hunger-002` (Hunger debuff: 2x tick cost for all NPC travel and work when food runs out)
- `TR-hunger-003` (Combined debuff: hunger debuff multiplies with energy depletion penalty for 4x total tick cost cap)

**ADR Governing Implementation**: ADR-0010: Hunger System and Debuff Stacking
**ADR Decision Summary**: HungerSystem exposes `hunger_tick_multiplier` (1.0 when FED, 2.0 when HUNGRY) as a read-only query. The Player Character System multiplies this with its own `depletion_tick_multiplier` (1.0 when energized, 2.0 when depleted) to get `effective_tick_cost = base_tick_cost × depletion_tick_multiplier × hunger_tick_multiplier`. When both are active: 80 × 2.0 × 2.0 = 320 ticks (4× baseline). Hunger does NOT modify output (output multiplier always 1.0). Energy depletion independently halves output. Player eats food while HUNGRY: player's depletion debuff clears immediately (energy restored), but NPC-side hunger debuff persists because consume_food() hasn't run yet.

**Engine**: Godot 4.6 | **Risk**: LOW (signal-based, multiplier queries)
**Engine Notes**: No post-cutoff APIs. Query-based — other systems call `get_hunger_tick_multiplier()` on the HungerSystem singleton and multiply with their own multiplier.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/hunger-system.md`, scoped to this story:*

- [ ] **AC-6** GIVEN the village is HUNGRY WHEN a manual action is executed THEN the tick cost is `base_tick_cost × 2` (hunger_tick_multiplier = 2.0), and output quantity is unchanged by hunger
- [ ] **AC-7** GIVEN the village is HUNGRY AND the player has 0 energy WHEN a manual action is executed THEN both debuffs stack multiplicatively: `tick_cost = base × 2.0 (hunger) × 2.0 (depletion) = base × 4`
- [ ] **AC-8** GIVEN the village is HUNGRY WHEN an NPC building executes a production cycle THEN the cycle takes 2× base ticks (e.g., 100-tick cycle completes at 200 ticks)
- [ ] **AC-9** GIVEN the player eats food while HUNGRY (but NPCs remain unsatisfied at day transition) THEN the player's energy depletion debuff clears immediately, but the NPC-side debuff persists (buildings still at 2×)
- [ ] **AC-19** GIVEN the player is HUNGRY and at 0 energy WHEN the player eats 1 berry from storage THEN the player's actions use normal tick cost (energy restored, depletion cleared) but the village remains HUNGRY (NPC debuff persists, 1 less food unit available for NPCs)

---

## Implementation Notes

*Derived from ADR-0010 Implementation Guidelines:*

**Multiplier queries (from ADR-0010):**
```
func get_hunger_tick_multiplier() -> float:
    return hunger_tick_multiplier  # 1.0 (FED) or 2.0 (HUNGRY)

func get_hunger_output_multiplier() -> float:
    return 1.0  # hunger does not affect output

func is_hunger_debuff_active() -> bool:
    return hunger_debuff_active
```

**Debuff stacking formula (from GDD Formula 2):**
```
# Player Character System — manual actions:
effective_tick_cost = base_tick_cost × depletion_tick_multiplier × hunger_tick_multiplier
effective_output = max(1, ceil(base_output × depletion_output_multiplier × hunger_output_multiplier))

# When both debuffs active:
#   T_eff = 80 × 2.0 × 2.0 = 320 ticks
#   O_eff = max(1, ceil(5 × 0.5 × 1.0)) = 3

# Building System — NPC building production:
effective_cycle = base_cycle × hunger_tick_multiplier
# When HUNGRY: 100 → 200 ticks

# Output: hunger_output_multiplier is ALWAYS 1.0.
# Only energy depletion affects output (0.5x).
```

**Player eats while HUNGRY (from GDD Rule 3, EC-6):**
```
# Player eating is separate from NPC consumption:
# 1. Player eats → PlayerCharacter consumes food for energy refill
# 2. Energy depletion debuff clears (energy > 0)
# 3. NPC-side hunger debuff PERSISTS because consume_food() hasn't run at day transition
# 4. Buildings remain at 2× tick cost
# 5. Storage food decreased by amount eaten (may make NPC consumption harder next day)
#
# Key tension: "I can eat to work faster, but that uses food my NPCs need."
```

**Signal propagation (from ADR-0010):**
```
signal hunger_state_changed(new_tick_multiplier: float)

# Other systems subscribe to this signal to react to debuff changes.
# PlayerCharacter System: on hunger_state_changed → update action tick cost
# Building System: on hunger_state_changed → update production cycle multipliers
# HUD System: on hunger_state_changed → update debuff indicator visibility
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Daily consumption and state transitions (the state machine produces the debuff state; Story 002 reads it)
- Story 003: Consumption priority and food unit conversion (how food is deducted, not how debuffs are applied)
- Story 004: Days of food remaining (HUD formula, not debuff logic)

---

## QA Test Cases

**AC-6**: Hunger debuff — tick cost doubles, output unchanged
  - Given: HUNGRY state (hunger_tick_multiplier = 2.0), player executes manual action with base_tick_cost = 80
  - When: effective tick cost is computed
  - Then: effective_tick_cost = 80 × 2.0 = 160 ticks, effective_output = base_output × 1.0 = unchanged
  - Edge cases: base_tick_cost = 5 (minimum) → effective = 10; base_tick_cost = 200 → effective = 400; base_output = 1 → output still 1 (hunger doesn't reduce output); base_output = 5 → output still 5

**AC-7**: Combined debuff — 4× tick cost
  - Given: HUNGRY state (hunger_tick_multiplier = 2.0) AND 0 energy (depletion_tick_multiplier = 2.0), player executes action with base_tick_cost = 80
  - When: effective tick cost is computed
  - Then: effective_tick_cost = 80 × 2.0 × 2.0 = 320 ticks, effective_output = max(1, ceil(5 × 0.5 × 1.0)) = 3 (output from depletion only)
  - Edge cases: only hunger (no depletion) → 160 ticks; only depletion (no hunger) → 160 ticks; both active → 320 ticks; output at 3 (not reduced by hunger); combined cap at 4× is the maximum (no additional multipliers at VS)

**AC-8**: NPC building at 2× under hunger
  - Given: HUNGRY state, NPC assigned to building with base 100-tick production cycle
  - When: production cycle starts
  - Then: effective_cycle = 100 × 2.0 = 200 ticks
  - Edge cases: base 50-tick cycle → 100 ticks; base 500-tick cycle → 1000 ticks (full day); building reads hunger_tick_multiplier via HungerSystem.get_hunger_tick_multiplier(); output quantity unchanged by hunger

**AC-9**: Player eats while HUNGRY — separate effects
  - Given: HUNGRY state, player at 0 energy, 5 food units in storage
  - When: player eats 1 berry (restores energy to > 0)
  - Then: player's depletion_tick_multiplier = 1.0 (depletion cleared), player actions use normal tick cost; HungerSystem state = HUNGRY (unchanged, no day transition yet), hunger_tick_multiplier = 2.0; NPC buildings still at 2×; storage food decreased from 5 to 4
  - Edge cases: eating doesn't call consume_food() — it's PlayerCharacter energy refill, not HungerSystem consumption; NPC debuff clears only at next successful day transition; if eating depletes food below NPC requirement, next day transition will definitely be HUNGRY (less buffer)

**AC-19**: Player eats from storage while HUNGRY — food trade-off
  - Given: HUNGRY state, player at 0 energy, 3 berries in storage (3 food units, 2 NPCs need 2)
  - When: player eats 1 berry
  - Then: player energy restored (depletion_tick_multiplier = 1.0), player actions normal speed; HungerSystem state = HUNGRY (still, no day transition), 2 food units left (enough for 2 NPCs for tomorrow, but tomorrow is tight); storage now has 2 berries
  - Edge cases: eating 2 berries → player energized, but only 1 food unit left for 2 NPCs → next day transition will be HUNGRY; the tension: "I ate and feel better, but tomorrow my NPCs will suffer again"

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/hunger_system/debuff_stacking_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (debuff state must exist before stacking can be tested)
- Unlocks: None — debuff stacking is read-only; the Building System and Player Character System consume these multipliers but the Hunger System doesn't need them implemented
