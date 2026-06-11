# Epic: Efficiency System

> **Layer**: Feature
> **Quick Spec**: design/quick-specs/efficiency-system-2026-06-03.md
> **Architecture Module**: EfficiencyFormulas (static class — `res://src/systems/efficiency/efficiency_formulas.gd`) + NPCData extension + BuildingData extension
> **Status**: Ready
> **Stories**: 5 created (Story 001–005)

## Overview

The Efficiency System is a unified numeric property (0.0–2.0, base 1.0) on buildings and NPCs that replaces ad-hoc debuff multipliers with a single formula layer. Worker NPCs contribute their efficiency delta to their assigned building; the building uses that efficiency to compute its production cycle speed via F3. Carrier NPCs apply their efficiency directly to travel time via F4. At Vertical Slice scope the only active modifier is the hunger debuff (hunger_modifier=0.5 when HUNGRY), which flows through `npc.efficiency → building.efficiency → cycle_ticks` and produces the same 2× slowdown as the existing implementation. Equipment and satisfaction modifiers are stubbed at 1.0, ready for future systems.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0012: Efficiency System | EfficiencyFormulas static class (F1–F4); efficiency as property on NPCData and BuildingData; signal-driven updates from HungerSystem.hunger_state_changed; BuildingRegistry uses F3 for cycle ticks; LogisticsSystem uses F4 for travel ticks | LOW (clampf, floori, maxi — stable since Godot 4.0) |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-efficiency-001 | NPC efficiency property (F1): clamp(1.0 × hunger_mod × satisfaction_mod × equipment_mod, 0.0, 2.0) | ADR-0012 ✅ |
| TR-efficiency-002 | Building efficiency (F2): clamp(1.0 + Σ worker deltas + upgrade_bonus, 0.0, 2.0) | ADR-0012 ✅ |
| TR-efficiency-003 | Production cycle ticks via F3; hunger debuff routed through efficiency | ADR-0012 ✅ |
| TR-efficiency-004 | Carrier travel ticks via F4 | ADR-0012 ✅ |
| TR-efficiency-005 | Config from JSON; UI thresholds (green/yellow/red) | ADR-0012 ✅ |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | NPC Efficiency Property and Hunger Integration | Logic | Ready | ADR-0012 |
| 002 | Building Efficiency and Worker Contribution | Logic | Ready | ADR-0012 |
| 003 | Production Cycle Integration | Integration | Ready | ADR-0012 |
| 004 | Carrier Travel Integration | Integration | Ready | ADR-0012 |
| 005 | Efficiency Config and UI Thresholds | Config/Data | Ready | ADR-0012 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/quick-specs/efficiency-system-2026-06-03.md` are verified
- Logic and Integration stories have passing test files in `tests/`
- Config/Data story has a smoke check pass in `production/qa/`
- Regression verified: hungry NPC still produces 2× slower cycle time (same behavior, new code path)

## Next Step

Run `/story-readiness production/epics/efficiency-system/story-001-npc-efficiency-property-and-hunger-integration.md` to begin implementation.
