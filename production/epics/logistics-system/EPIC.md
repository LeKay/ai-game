# Epic: Logistics System

> **Layer**: Feature (Core Gameplay)
> **GDD**: design/gdd/logistics-system.md
> **Architecture Module**: LogisticsSystem (autoload singleton)
> **Status**: Ready
> **Stories**: 12 created (4 Logic, 6 Integration, 1 Visual/Feel, 1 UI)

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Route Model and Slot Validation | Logic | Ready | ADR-0011 |
| 002 | Carrier FSM Core Loop | Integration | Ready | ADR-0011, ADR-0009, ADR-0004 |
| 003 | Carrier Waiting and Timeout | Integration | Ready | ADR-0011 |
| 004 | Building Status Integration | Integration | Ready | ADR-0011, ADR-0008 |
| 005 | Save/Load for Logistics | Integration | Ready | ADR-0011, ADR-0006 |
| 006 | Route Visualization | Visual/Feel | Ready | ADR-0011 |
| 007 | Efficiency and Carrier Count Formulas | Logic | Ready | ADR-0011 |
| 008 | Transportation Management UI | UI | Ready | design/ux/transportation.md |
| 009 | Tile Movement Cost Data Model | Logic | Ready | ADR-0013 |
| 010 | Weighted A* Pathfinding | Logic | Ready | ADR-0013 |
| 011 | Logistics Route Path Integration | Integration | Ready | ADR-0013 |
| 012 | Path Invalidation on Terrain Change | Integration | Ready | ADR-0013 |

## Overview

The Logistics System is the village's supply chain — it connects buildings via NPC carriers that physically move resources across the map. Production buildings use carriers to deliver inputs (bringing them upstream goods) and collect outputs (taking finished goods away). Storage buildings receive outputs from production buildings and provide inputs to production buildings. Extraction buildings operate on resources in their proximity but still have output carriers. Buildings without the carriers they need enter BLOCKED or STALLED states.

The system implements a self-contained carrier FSM (8 states) that replaces the NPC task cycle for assigned NPCs, using a tick-driven deterministic loop with defined processing order. Route visualization uses always-visible lines with color/status encoding and line patterns for colorblind accessibility. Multi-hop chain planning and efficiency metrics are MVP+ features; the Vertical Slice focuses on the carrier assignment loop and building status feedback.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0011: Logistics System — Carrier FSM and Route Architecture | 8-state carrier FSM, route model, tick ordering (step 3), NPC contract, save/load serialization, RouteLines visualization | LOW |
| ADR-0001: Tick System | Carrier timing driven by `ticks_advanced()`; tick processing order slot 3 | LOW |
| ADR-0004: Grid Map Data Model | Manhattan distance via `GridMap.distance_between()` | MEDIUM (TileMapLayer) |
| ADR-0005: Inventory Item State Machine | `try_deposit()` / `try_consume()` via InventorySystem | LOW |
| ADR-0008: Building Placement & Production | Building slot definitions, `has_output_buffer()`, `collect_output()`, building status integration | LOW |
| ADR-0009: NPC State Machine | Carrier ↔ NPC task state mapping; `set_carrier_state()`, `release_npc()`, `on_npc_at_location()` | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-logistics-001 | Three route types: Storage→Production, Production→Storage, Production→Production | ADR-0011 ✅ |
| TR-logistics-002 | Carrier FSM with 8 states | ADR-0011 ✅ |
| TR-logistics-003 | Slot-based assignment: at most one carrier per slot type | ADR-0011 ✅ |
| TR-logistics-004 | Travel time = Manhattan distance × ticks_per_tile (Formula 1) | ADR-0011 ✅ |
| TR-logistics-005 | Building status integration: BLOCKED/STALLED/OPERATING | ADR-0011 ✅ |
| TR-logistics-006 | Carrier waiting timeout: 300 ticks | ADR-0011 ✅ |
| TR-logistics-007 | NPC ↔ Logistics precedence: carrier FSM replaces NPC task cycle | ADR-0011 ✅ |
| TR-logistics-011 | NPC carrier management interface (5 methods) | ADR-0011 ✅ |
| TR-logistics-012 | Carrier deposit/withdraw via InventorySystem | ADR-0011 ✅ |
| TR-logistics-013 | Building slot definitions validated in route creation | ADR-0011 ✅ |
| TR-logistics-008 | Save/load persistence of routes and carrier states | ADR-0011 ✅ |
| TR-logistics-009 | Route visualization (always-visible lines, color/status, line patterns) | ADR-0011 ✅ |
| TR-logistics-010 | Route efficiency and carrier count formulas (Formulas 3 and 4) | ADR-0011 ✅ |
| TR-logistics-014 | Transportation Management UI for route creation/editing/deletion | ❌ No ADR — UX spec pending |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/logistics-system.md` are verified (16 ACs)
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories logistics-system` to break this epic into implementable stories.
