# Epic: Inventory/Storage System

> **Layer**: Core
> **GDD**: design/gdd/inventory-storage-system.md
> **Architecture Module**: InventorySystem
> **Status**: Ready
> **Stories**: 5 stories created

## Overview

The Inventory/Storage System is the player's material world — the containers that hold resources and the spatial act of moving them from where they're harvested to where they're needed. For the Vertical Slice, the system defines two concepts: tile-drop resources (items harvested by the player appear on the tile and are not accessible to buildings until placed in storage) and storage containers (Storage Area, a free 50-slot container, and Storage Building, an 8 Wood + 2 Stone upgrade to 150 slots). The InventorySystem is an Autoload singleton using a `Dictionary[StringName, InventoryContainer]` registry. First-fit stacking, transport state machine (DROPPED → IN_TRANSIT → STORED/LOST), tick-based transport timers, and hunger consumption priority (lowest-quantity-first) are the core mechanics. Buildings pull exclusively from storage; hunger deducts food globally across all containers at day transition.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0005: Inventory and Item State Machine | Autoload singleton with Dictionary[StringName, InventoryContainer], first-fit stacking, DROPPED/IN_TRANSIT/STORED/LOST state machine, tick-based transport timers | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-inv-001 | InventoryContainer with first-fit stacking algorithm: extend existing slots then fill empty | ADR-0005 ✅ |
| TR-inv-002 | Resource state machine: DROPPED -> IN_TRANSIT -> STORED/LOST | ADR-0005 ✅ |
| TR-inv-003 | Transport cost formulas: energy = 2*qty + 1*distance, time = 5*distance | ADR-0005 ✅ |
| TR-inv-004 | Hunger consumption priority: withdraw from lowest-quantity storage bin first | ADR-0005 ✅ |
| TR-inv-005 | Storage Area (50 slots, free) and Storage Building (150 slots, 8 Wood + 2 Stone) | ADR-0005 ✅ |
| TR-inv-006 | Items can only be consumed from STORED state — not DROPPED or IN_TRANSIT | ADR-0005 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/inventory-storage-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | InventorySystem Autoload and Container Data Model | Logic | Ready | ADR-0005 |
| 002 | First-Fit Stacking Algorithm | Logic | Ready | ADR-0005 |
| 003 | Item State Machine and Transport | Logic | Ready | ADR-0005 |
| 004 | Hunger Consumption Priority Algorithm | Logic | Ready | ADR-0005 |
| 005 | Save/Load Serialization Round-Trip | Integration | Ready | ADR-0005 |

## Next Step

Run `/story-readiness production/epics/inventory-system/story-001-inventory-container-data-model.md` to begin implementation.
