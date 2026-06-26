# Epic: Player Character System

> **Layer**: Core
> **GDD**: design/gdd/player-character-system.md
> **Architecture Module**: PlayerCharacter (Autoload singleton)
> **Status**: Ready
> **Stories**: 001–005 (all Ready)

## Overview

The Player Character System is the player's interface with the game world — an Autoload singleton managing an energy pool (100 max, hourglass model), manual action execution (forage/pick/craft/chop/mine), drag-and-drop transport from harvested tiles to storage buildings, energy depletion penalties at 0 energy, and a one-way Architect Mode lockout triggered by assigning the first NPC. The player character has no visible sprite; they act remotely by clicking on world tiles. Energy constrains the manual labor rate, making earned automation meaningful.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0007: Player Character Energy Model and Manual Action System | Autoload singleton with EnergyPool, ActionSlot, TransportManager, ArchitectMode classes; tick-based action accumulation; signal-based communication | LOW (verification: `_process()` at 144fps, `Tween` in 4.6) |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-player-001 | Energy pool (0–100) with tick-based drain and depletion penalties | ADR-0007 ✅ |
| TR-player-002 | Manual action dispatch (forage/pick/craft/chop/mine) each with defined energy and tick cost | ADR-0007 ✅ |
| TR-player-003 | Drag-and-drop transport: carry item from tile to storage container | ADR-0007 ✅ |
| TR-player-004 | Energy depletion penalty at 0 energy: 2x tick cost + ceil(output * 0.5) minimum 1 | ADR-0007 ✅ |
| TR-player-005 | Food-to-energy refill: consuming food restores energy based on food type | ADR-0007 ✅ |
| TR-player-006 | Architect Mode lock: after first NPC assigned, manual gathering is permanently locked out | ADR-0007 ✅ |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | energy-pool | Logic | Ready | ADR-0007 |
| 002 | action-dispatch | Integration | Ready | ADR-0007 |
| 003 | drag-drop-transport | Integration | Ready | ADR-0007 |
| 004 | depletion-food | Logic | Ready | ADR-0007 |
| 005 | architect-mode | Integration | Ready | ADR-0007 |
| 006 | tile-harvest-interaction | UI | Ready | ADR-0007 |
| 007 | resource-relocation-drag | Integration | Ready | — |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/player-character-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories player-character` to break this epic into implementable stories.
