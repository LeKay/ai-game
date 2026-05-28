# Epic: Camera System

> **Layer**: Core
> **GDD**: design/gdd/camera-system.md
> **Architecture Module**: CameraController
> **Status**: Ready
> **Stories**: 5 created — see table below

## Overview

The Camera System implements the viewport controller that maps world-space to
screen-space and back. It drives all pan input (WASD, arrow keys, middle-mouse
drag, edge scrolling), zoom anchored to the mouse cursor, boundary clamping to
the 30×30 grid, and the public coordinate conversion API (`screen_to_tile`,
`tile_to_screen`, `fit_to_world`). Downstream systems — Building System, HUD,
and Hover/Tooltip UI — all depend on `CameraController.get_tile_at_screen()` for
mouse-to-tile mapping. The Camera System has no simulation logic and no states
beyond position and zoom; it exists solely to keep the viewport in bounds and
expose coordinate queries to the rest of the game.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0003 (partial) | InputContext delegates mouse→tile conversion to CameraController | LOW |

> **No standalone Camera ADR required.** The architecture review explicitly
> deferred a Camera ADR as low-risk: Camera2D pan/zoom API is stable across
> Godot 4.4–4.6. All behaviour is fully specified in the GDD. ADR-0003 covers
> the input gating contract.

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-cam-001 | Pan: WASD / arrows / middle-drag / edge-scroll | ❌ Deferred — low risk, GDD fully specifies behaviour |
| TR-cam-002 | Zoom 0.85–2.0 anchored to mouse position | ❌ Deferred — low risk, GDD fully specifies behaviour |
| TR-cam-003 | Boundary clamping (cannot scroll outside world bounds) | ❌ Deferred — low risk, GDD fully specifies behaviour |
| TR-cam-004 | Screen → tile coordinate conversion (click → tile) | ADR-0003 ✅ (partial — delegated to CameraController) |
| TR-cam-005 | Fit-to-view on R key | ❌ Deferred — low risk, GDD fully specifies behaviour |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/camera-system.md` are verified (12 ACs)
- Logic stories (pan math, zoom anchor, boundary clamp, coordinate conversion) have passing unit tests in `tests/unit/camera/`
- Visual/feel stories (edge scroll feel, zoom feel) have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Pan Input | Logic | Ready | ADR-0003 (partial) |
| 002 | Zoom with Mouse Anchor | Logic | Ready | ADR-0003 (partial) |
| 003 | Boundary Clamping | Logic | Ready | ADR-0003 (partial) |
| 004 | Coordinate Conversion | Logic | Ready | ADR-0003 (partial) |
| 005 | Fit-to-View Reset | Logic | Ready | ADR-0003 (partial) |

## Next Step

Run `/story-readiness production/epics/camera-system/story-001-pan-input.md` then `/dev-story` to begin implementation. Work through stories in dependency order (001 → 002 → 003 → 004 → 005).
