# ADR-0014: Shared Draggable Window Frame for Floating Panels

## Status
Accepted

## Date
2026-06-07

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI (Frontend) |
| **Knowledge Risk** | LOW — uses stable Control APIs (`gui_input`, `_input`, `get_viewport_rect`, `mouse_default_cursor_shape`, `accept_event`); no post-cutoff signatures |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `.claude/rules/ui-code.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Confirm drag survives the cursor leaving the title bar (handled in `_input`, not `gui_input`); confirm clamp keeps the window inside the viewport at multiple resolutions |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (Input Context System — panels push/pop UI context unchanged) |
| **Enables** | Consistent window chrome (title + close + drag) for all future floating panels |
| **Blocks** | None — existing panel behaviour (open/close, click-outside, Escape) is preserved |

## Context

### Problem Statement

Floating UI panels (tile interaction, building detail, transportation, NPC detail)
were each built independently. Every panel hand-rolled its own header row and ✕
close button, and **none of them could be moved** — a panel could obscure the very
tile or building the player wanted to inspect, with no way to reposition it.

We want every opened window to share one consistent frame that provides:

1. A **close** affordance (✕).
2. A **move** affordance — the user can drag the window anywhere on screen.

### Constraints

- Panels have **heterogeneous roots**: `TileInteractionPanel` and `InventoryScreen`
  are `CanvasLayer`; `BuildingDetailPanel`, `TransportationPanel`, `NpcDetailPanel`
  are `Control`. A single base class cannot be the *root* of all of them
  (`CanvasLayer` is not a `Control`).
- The element that actually moves is always an inner `PanelContainer`, never the root.
- UI must not own game state (`.claude/rules/ui-code.md`); the frame is display-only.

## Decision

Introduce `DraggableWindow extends PanelContainer` (`src/ui/components/draggable_window.gd`)
as the **shared inner frame**, not the panel root. It provides:

- A **title bar** (`PanelContainer`) containing a `✥` drag-hint, a title `Label`,
  and a `✕` close `Button`. The **entire title bar is the drag surface**
  (`mouse_default_cursor_shape = CURSOR_MOVE`); per the design decision the bar
  carries a `✥` hint glyph rather than a separate move button.
- A public `content: VBoxContainer` into which each owner panel adds its body.
- Drag logic: press is detected on the title bar (`gui_input`); motion and release
  are handled in `_input()` so a fast drag survives the cursor leaving the bar.
  The window moves itself via `global_position`, clamped to the viewport.
- A `close_requested` signal. The window never hides or frees itself — owners wire
  `close_requested` to their existing `close()`, preserving InputContext push/pop.

### Inheritance vs. composition

Because of the mixed-root constraint, integration is **composition**: each panel
uses a `DraggableWindow` instance as its inner frame (the `Control`-rooted panels
swap their hand-built `PanelContainer`; the `CanvasLayer`-rooted `TileInteractionPanel`
reparents its `.tscn` body into the window at `_ready`). This yields a single shared
window type with unified close + move chrome without breaking root compatibility.

### Scope

Applied to the four floating panels. The centered `InventoryScreen` modal and the
forced `DayOverviewPanel` day-transition modal are intentionally **out of scope** —
they are full-screen modals where free dragging adds no value.

### Testable core

`DraggableWindow.clamp_position(pos, win_size, viewport_size)` is a pure static
helper (no node/viewport access), unit-tested in
`tests/unit/ui/draggable_window_test.gd` (BLOCKING logic gate).

## Consequences

### Positive
- One consistent, movable window frame; panels no longer obscure their subject.
- Per-panel close-button boilerplate removed; the bar replaces redundant headers.
- Drag geometry is unit-testable in isolation.

### Negative / Trade-offs
- Composition, not literal single-root inheritance (forced by mixed roots).
- A dragged window keeps `PRESET_CENTER` anchors, so it re-centers on viewport
  resize. Acceptable for now; a future change could switch to absolute anchors on
  first drag.

### Follow-ups
- Optional: persist window positions across sessions.
- Optional: extend the frame to the Inventory modal if free placement is later desired.
