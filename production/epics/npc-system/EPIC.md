# Epic: NPC System

> **Layer**: Feature
> **GDD**: design/gdd/npc-system.md
> **Architecture Module**: NPCSystem (Autoload singleton — `res://src/gameplay/npc_system.gd`)
> **Status**: Ready
> **Stories**: 5 created (Story 001–005)

## Overview

The NPC System is the village's workforce — a pool of automated workers that transform the player's manual labor into passive production. It owns NPC identity and recruitment, a seven-state task cycle (IDLE → TRAVEL_TO_BUILDING → WORK_AT_BUILDING → TRAVEL_TO_STORAGE → DEPOSIT → RETURN_TO_BASE, plus WAITING), tick-driven travel progress using Manhattan distance, assignment coordination with the Building System, deposit operations with Inventory/Storage System, disconnection handling on building/storage/house demolition, and NPC serialization for Save/Load. NPCs have no visible sprites at VS scope; their state is communicated through building status indicators.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0009: NPC State Machine and Movement | Autoload singleton NPCSystem with NPCInstance state containers, 7-state task machine, tick-driven travel, Manhattan distance via GridMap, assignment/release via BuildingRegistry | LOW (pure GDScript data, stable APIs — `_process`, `Engine.get_singleton()`) |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-npc-001 | NPC data: id, name, state, assignment, current_task | ADR-0009 ✅ |
| TR-npc-002 | NPC state machine: IDLE → TRAVEL_TO_BUILDING → WORK → TRAVEL_TO_STORAGE → DEPOSIT → RETURN_TO_BASE | ADR-0009 ✅ |
| TR-npc-003 | Manhattan-distance abstract movement (no NavigationAgent2D for VS; ticks_per_tile = 3.0) | ADR-0009 ✅ |
| TR-npc-004 | Recruitment: up to 2 NPCs per Residential House; first spawns on completion, second after 1 day | ADR-0009 ✅ |
| TR-npc-005 | Task assignment: player assigns NPC to a building via building UI | ADR-0009 ✅ |
| TR-npc-006 | Building demolition disconnects NPC assignment and returns NPC to IDLE pool | ADR-0009 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/npc-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories npc-system` to break this epic into implementable stories.
