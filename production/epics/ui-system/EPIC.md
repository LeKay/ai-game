# Epic: UI System

> **Epic Slug**: ui-system
> **Layer**: Presentation
> **System**: UI screens (Main Menu, HUD, Settings, Pause)
> **GDD**: N/A — UI governed by UX specs in `design/ux/`
> **Governing ADRs**: ADR-0003 (Input Context System), ADR-0006 (Save/Load)

## Overview

Implement player-facing UI screens that translate game state into readable visual feedback and translate player input into system actions. This epic covers the Main Menu (game launch navigation), with foundation hooks for HUD, Settings, and Pause screens added in later stories.

## Governing ADRs

| ADR | Title | Status |
|-----|-------|--------|
| ADR-0003 | Input Context System | Accepted — defines `push_context(UI_ACTIVE)` / `pop_context()` for UI screens |
| ADR-0006 | Save and Load Format and Serialization Order | Accepted — `WorldSaveManager` orchestrates load/save, UI triggers via signals |

## UX Specs

| Screen | Status | File |
|--------|--------|------|
| Main Menu | APPROVED | `design/ux/main-menu.md` |

## GDD Requirements

| TR-ID | Requirement | Source |
|-------|-------------|--------|
| TR-ui-001 | Main menu with New Game / Continue / Quit buttons | `design/ux/main-menu.md` § Layout Specification |
| TR-ui-002 | Input context switch to UI_ACTIVE on main menu open | ADR-0003 |
| TR-ui-003 | Continue button state tied to save file existence (ADR-0006) | ADR-0006 |
| TR-ui-004 | Input context switches back to gameplay on scene transition | ADR-0003 |
| TR-ui-005 | Quit button triggers save (if needed) then exits process | ADR-0006 |

> ⚠️ **No GDD exists** for UI System. Requirements traced from UX specs and governing ADRs.

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All UX spec acceptance criteria verified (layout, input, states, transitions)
- All Logic stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR/UX |
|---|-------|------|--------|--------|
| 001 | [Main Menu Screen](story-001-main-menu.md) | UI | Ready | UX: main-menu, ADR-0003 |
| 002 | HUD — Resource Bar & Play/Pause Button | UI | Complete | UX: hud.md, ADR-0003 |
| 003 | Settings Modal & Key Binding UI | UI | Ready | UX: TBD, ADR-0003 |
| 004 | Pause Menu & Return to Main Menu | UI | Ready | UX: TBD, ADR-0003, ADR-0006 |
| 005 | Tile Interaction Panel | UI | Complete | ADR-0007 |
| 006 | HUD — Storage Panel (Global Resource Overview) | UI | Ready | UX: hud.md, ADR-0005 |

## Dependencies

- **Unlocks by this epic**: None (UI is the presentation layer; gameplay systems are independent)
- **Depends on**: Save/Load System (TR-ui-003, TR-ui-005 — WorldSaveManager must exist)

## Risks

- **Engine**: LOW — Godot Control node system is well-documented, no post-cutoff APIs involved
- **Scope creep risk**: UI screens naturally attract polish. Keep VS scope minimal (hardcoded text, gradient background, no animations beyond fade). Defer diorama, settings modal, and locale extraction to MVP.
