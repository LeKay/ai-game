# Epic: Building System

> **Layer**: Feature
> **GDD**: design/gdd/building-system.md
> **Architecture Module**: BuildingRegistry (Autoload singleton — `res://src/gameplay/building_registry.gd`)
> **Status**: Ready
> **Stories**: 5 — see table below

## Overview

The Building System is the player's primary interface with the game's spatial logic — where the village takes physical form on the map. It owns building placement validation (delegating to GridMap), construction cost consumption (delegating to InventorySystem), tick-based build-time progression, building lifecycle management (PLACE → CONSTRUCT → OPERATE → DEMOLISH), production cycles for Lumber Camp, NPC assignment slots, and failure states (BLOCKED when missing inputs, STALLED when storage is full). Buildings are PackedScene instances at tile centers under a YSort node — visual targets synced from the central registry state.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0008: Building Placement and Production System Architecture | Autoload singleton BuildingRegistry with BuildingInstance state machines, single-loop tick subscription, PackedScene visual rendering, 4 building types at VS scope | LOW (PackedScene.instantiate(), queue_free(), stable APIs) |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-build-001 | 1-tile footprint building placement with atomic resource cost deduction from storage | ADR-0008 ✅ |
| TR-build-002 | 4 building types for Vertical Slice: Storage Area, Storage Building, Residential House, Lumber Camp | ADR-0008 ✅ |
| TR-build-003 | Tick-based build time progression: CONSTRUCTING state with accumulated tick counter | ADR-0008 ✅ |
| TR-build-004 | Production cycle tick advancement for Lumber Camp: input consume → cycle timer → output deposit | ADR-0008 ✅ |
| TR-build-005 | NPC assignment slot per production building; building cannot produce without assigned NPC | ADR-0008 ✅ |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Building Placement and Construction Start | Integration | Ready | ADR-0008 |
| 002 | Production Cycles and Distance Formulas | Integration | Ready | ADR-0008 |
| 003 | Failed States — BLOCKED and STALLED | Integration | Ready | ADR-0008 |
| 004 | NPC Assignment and Residential House Production | Integration | Ready | ADR-0008 |
| 005 | Demolition | Integration | Ready | ADR-0008 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/building-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories building-system` to break this epic into implementable stories.
