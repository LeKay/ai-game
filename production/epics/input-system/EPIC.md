# Epic: Input System

> **Layer**: Foundation
> **GDD**: design/gdd/input-system.md
> **Architecture Module**: InputContext (Autoload singleton)
> **Status**: Ready
> **Stories**: 5 created — 4 Logic, 1 Integration

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Input Context Stack and Action Dispatch | Logic | Ready | ADR-0003 |
| 002 | Input Debounce System | Logic | Ready | ADR-0003 |
| 003 | Action Rebinding and Persistence | Logic | Ready | ADR-0003 |
| 004 | Context Transition on UI Open/Close | Integration | Ready | ADR-0003 |
| 005 | Input Discard in PAUSED and UI_ACTIVE Contexts | Logic | Ready | ADR-0003 |

## Overview

The Input System is the hardware-to-software bridge that converts raw keyboard, mouse, and (future) gamepad inputs into gameplay-meaningful events. It provides a centralized input abstraction layer where physical key presses and mouse actions are translated into semantic actions consumed by the Player Character System, Camera System, UI Systems, and Settings System. It manages input context switching (WORLD_ACTIVE / UI_ACTIVE / PAUSED), debouncing for rapid presses, and unified action mapping via Godot's native InputMap.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0003 | InputContext as Autoload singleton with push/pop context stack, Godot InputMap for action mapping, timer-based debounce (0.25s) | MEDIUM |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-input-001 | Unified action mapping: keyboard+mouse + gamepad map to the same semantic actions | ADR-0003 ✅ |
| TR-input-002 | Input context switching: WORLD_ACTIVE / UI_ACTIVE / PAUSED | ADR-0003 ✅ |
| TR-input-003 | Context transition on UI open/close via push_context/pop_context | ADR-0003 ✅ |
| TR-input-004 | Input debouncing for rapid presses (0.25s timer-based gate) | ADR-0003 ✅ |
| TR-input-005 | Mouse position to world tile coordinate conversion | ADR-0003 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/input-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories input-system` to break this epic into implementable stories.
