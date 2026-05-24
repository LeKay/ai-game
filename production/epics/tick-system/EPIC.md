# Epic: Tick System

> **Epic Slug**: tick-system
> **Layer**: Foundation
> **System**: Tick System (time management)
> **GDD**: `design/gdd/tick-system.md`
> **Governing ADR**: `docs/architecture/adr-0001-tick-system.md`

## Overview

Implement the foundational time system that converts real-time engine delta into discrete tick units consumed by all gameplay systems. The Tick System provides player-controlled time flow (0.5x, 1x, 2x, pause/play), deterministic accumulation with fractional remainder carry, and day-transition events.

## Governing ADRs

| ADR | Title | Status |
|-----|-------|--------|
| ADR-0001 | Tick System Design and Time Management | Accepted |

## GDD Requirements Table

| TR-ID | Requirement | Status |
|-------|-------------|--------|
| TR-tick-001 | 1000-tick/day float accumulator with fractional remainder carry | Covered by ADR-0001 |
| TR-tick-002 | 3 speed modes (0.5x/1x/2x) + pause state | Covered by ADR-0001 |
| TR-tick-003 | Tick signal emission to all subscribers per tick | Covered by ADR-0001 |
| TR-tick-004 | Manual action tick advancement | Covered by ADR-0001 |
| TR-tick-005 | Day-transition event at 1000 ticks + auto-pause | Covered by ADR-0001 |
| TR-tick-006 | Determinism: same seed produces same tick sequence | Covered by ADR-0001 |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [Tick Accumulator Core](story-001-tick-accumulator-core.md) | Logic | Ready | ADR-0001 |
| 002 | [Speed Modes and Pause State](story-002-speed-modes-and-pause.md) | Logic | Ready | ADR-0001 |
| 003 | [Manual Action Tick Advancement](story-003-manual-action-advancement.md) | Logic | Ready | ADR-0001 |
| 004 | [Day Transition Event and Auto-Pause](story-004-day-transition-event.md) | Logic | Ready | ADR-0001 |
| 005 | [Save and Load Tick State](story-005-save-load-tick-state.md) | Integration | Ready | ADR-0001, ADR-0006 |

## Dependencies

- **Unlocks**: Production System, Manual Labor System, Hunger System, NPC System, Save/Load System, Day/Night Cycle System, HUD System

## Risks

- **Engine**: HIGH — versions 4.4-4.6 beyond LLM training data (though Tick System uses stable APIs)
- **Verification**: Test tick accumulation accuracy across frame rates (30fps, 60fps, 144fps)
