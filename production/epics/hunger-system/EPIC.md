# Epic: Hunger System

> **Layer**: Foundation
> **GDD**: design/gdd/hunger-system.md
> **Architecture Module**: HungerSystem (Autoload singleton — `res://src/gameplay/hunger_system.gd`)
> **Status**: Ready
> **Stories**: 5 created (Story 001–005)

## Overview

The Hunger System is the village's daily bread ballot — the tension between growth and sustainability that makes automation necessary. It owns daily food consumption (1 food unit per NPC per day, triggered by `day_transition`), food unit conversion (berry=1, bread=2), binary debuff state (FED/HUNGRY) that applies a 2× tick cost multiplier to player actions and NPC building production, multiplicative debuff stacking with the Player Character's energy depletion (4× combined), consumption priority via delegation to InventorySystem, days-of-food-remaining calculation for HUD display, and defensive guards (tick mod 1000, 0 NPCs = FED indefinitely). NPCs never die from starvation — the 2× debuff is the sole consequence.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0010: Hunger System and Debuff Stacking | Autoload singleton HungerSystem with binary FED/HUNGRY state machine, `day_transition`-driven consumption via InventorySystem delegation, `hunger_tick_multiplier` (1.0/2.0) for multiplicative debuff stacking, 4× combined with energy depletion | LOW (pure GDScript data, stable APIs — `_enter_tree`, `Engine.get_singleton()`) |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-hunger-001 | Daily food consumption: 1 food unit per NPC per day at day transition | ADR-0010 ✅ |
| TR-hunger-002 | Hunger debuff: 2× tick cost for all NPC travel and work when food runs out | ADR-0010 ✅ |
| TR-hunger-003 | Combined debuff: hunger debuff multiplies with energy depletion penalty for 4x total tick cost cap | ADR-0010 ✅ |
| TR-hunger-004 | Food unit conversion: Berry = 1 unit, Bread = 2 units | ADR-0010 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/hunger-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/story-readiness production/epics/hunger-system/story-001-daily-consumption-and-state-machine.md` to begin implementation.
