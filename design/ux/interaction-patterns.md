# Interaction Pattern Library

> **Status**: In Design
> **Author**: user + ux-designer
> **Last Updated**: 2026-05-19
> **Cross-Reference Check**: 2026-05-19 — All 11 patterns verified: GDD coverage complete, accessibility tier Standard compliant, navigation consistent, 6 gaps identified for future work
> **Template**: Interaction Pattern Library

---

## Overview

This library catalogs every interaction pattern used across "From Scratch" UX specs. It serves as a single reference for consistency: when designing a new screen, check the library first to see if an existing pattern covers the interaction before inventing a new one.

Patterns are extracted from approved UX specs and formalized here with full specification. Each pattern includes category, behavior rules, input mappings, accessibility requirements, and guidance on when to use (or avoid) it.

**Input scope**: Keyboard/Mouse (primary) + Gamepad (partial, navigation + core gameplay). All patterns must support mouse interaction. Gamepad navigation applies to screens with focusable UI elements per the Standard accessibility tier.

**Visual grammar** (from Art Bible, Functional Clarity direction):
- Buttons: sharp rectangles (0px normal → 2px hover → 4px active)
- Pure text labels, no icons (except status indicator icons)
- Color encodes meaning but is never the sole indicator

---

## Pattern Catalog

This catalog is the index for the full pattern library. Each pattern is listed here with a one-line description and its source screen. The full pattern detail appears in Section 3 below.

| # | Pattern | Category | Source Screen(s) |
|---|---------|----------|-----------------|
| 1 | Ghost Preview | Visual Feedback | Build Placement |
| 2 | Toast/Alert Notifications | Feedback | HUD |
| 3 | Speed Cycle Toggle | Input | HUD |
| 4 | Resource Counters | Data Display | HUD |
| 5 | Storage Panel Toggle | Navigation | HUD |
| 6 | Status Badge Indicators | Visual Feedback | Build Placement, Building Detail, Transportation |
| 7 | Confirmation Dialog | Modal | Build Placement |
| 8 | Hover Tooltip | Visual Feedback | Building Detail |
| 9 | Tabbed Navigation | Navigation | Building Detail |
| 10 | NPC Assignment List | Data Display + Input | Building Detail |
| 11 | Map-Select Interaction | Input + Navigation | Transportation |

**Patterns Needed (gaps identified):**
- **Build Menu Grid** — building selection grid from build-placement (referenced in spec but not formalized)
- **Building Selection (Gameplay)** — clicking a building on the map from gameplay view
- **Drag-and-Drop Transport** — player-character-system describes drag-and-drop; no UX spec formalizes this pattern yet

---

## Patterns

### Ghost Preview

**Category**: Visual Feedback
**Used In**: Build Placement

**Description**: A semi-transparent outline (ghost) of a building appears under the cursor during placement mode, showing the exact tile footprint before resources are committed. The ghost changes color to indicate placement validity: green tint for valid placement, red tint for invalid placement (occupied tile, impassable, out of bounds, blocked by resource, insufficient resources/energy). The ghost locks to the tile grid.

**Specification**:
- Ghost is a tinted overlay, not a full building sprite — uses reduced opacity (~30%)
- Valid placement: green overlay; Invalid placement: red overlay
- Tooltip displays the specific block reason on invalid placement (not just "invalid")
- Ghost appears immediately on building selection from Build Menu
- Ghost follows cursor with 1-tile grid snapping; color recalculation on cursor tile change, debounced to ~100ms to prevent flicker
- Resources are NOT deducted on ghost appearance — only on confirmed placement
- Ghost disappears on: Escape, right-click, clicking outside menu, confirming placement

**Input mapping**:
- Mouse: cursor follows, left-click to confirm, escape/right-click to cancel
- Gamepad: D-pad/nub to move ghost cursor, A to confirm, B to cancel

**Accessibility**: Invalid state uses red tint + icon indicator (not color alone). Per Standard tier, colorblind players need an alternative indicator — add a small X icon next to the block reason tooltip for invalid placement.

**When to Use**: Any placement or positioning interaction where commitment is pending and the player needs immediate validity feedback before confirming.
**When NOT to Use**: Not needed for single-step confirmations where the placement is the final action (e.g., quick-delete).

---

### Toast/Alert Notifications

**Category**: Feedback
**Used In**: HUD

**Description**: Transient notification messages appear in the bottom-right corner of the screen, stacking vertically. Each toast displays a brief message with an optional icon and auto-dismisses after a configurable timeout (default 3-5 seconds). Multiple simultaneous toasts stack with a small vertical offset (8px between toasts). Maximum stack height is 3 — when exceeded, the oldest toast is dismissed immediately.

**Specification**:
- Position: bottom-right corner, 16px from edge
- Content: small icon (left) + text message (right)
- Auto-dismiss: 3-5 seconds (configurable per toast type)
- Stack behavior: new toasts push existing toasts up; max 3 visible
- Duration per type: warnings (5s), info (3s), errors (5s)
- Toasts appear during gameplay (not only on specific screens)
- A single Notification Tray (from HUD GDD W6) consolidates all alerts before MVP

**Input mapping**:
- Passive — no player interaction required
- Optional: clicking a toast dismisses it early

**Accessibility**: Icon + text pairing ensures colorblind compliance. Toast text minimum 14px. Toasts must not obscure critical HUD elements (storage panel, energy bar).

**When to Use**: Transient feedback that the player should see but doesn't need to act on immediately (construction complete, NPC arrived, storage full).
**When NOT to Use**: For persistent or actionable warnings that need to stay until acknowledged (use Status Badge Indicators or Confirmation Dialog instead).

---

### Speed Cycle Toggle

**Category**: Input
**Used In**: HUD

**Description**: A single button on the HUD top band cycles through tick speed options in a fixed order with each press. The visual state shows the current speed multiplier (0.5x / 1x / 2x) and a play/pause indicator.

**Specification**:
- Cycle order: 0.5x → 1x → 2x → 0.5x (looping)
- Current speed displayed as a label (e.g., "1x")
- Play/Pause toggle adjacent to speed label — separate from speed cycle
- State persists across screen transitions and pauses
- Default on game start: 1x (real-time)

**Input mapping**:
- Mouse: click to cycle, click pause to toggle
- Keyboard: Q or E to cycle speed, Space to toggle pause
- Gamepad: left shoulder/bumper to cycle, A to toggle pause

**Accessibility**: No color-only state encoding. Speed state shown as text, not color. Pause state uses a distinct icon (▶ / ||) in addition to text.

**When to Use**: Any simulation or tick-driven system where the player needs to control time flow (speed up, slow down, pause).
**When NOT to Use**: Systems where speed adjustment should be a continuous slider rather than discrete steps.

---

### Resource Counters

**Category**: Data Display
**Used In**: HUD

**Description**: Numeric displays in the HUD top band showing current resource quantities. Each counter shows a label (resource name icon) and the current count. Updates are event-driven (changes only when the underlying system state changes, not on every tick).

**Specification**:
- Display format: icon + number (e.g., "Wood: 42")
- Color coding: neutral for normal, red for critical levels (below threshold defined in GDD)
- Update behavior: event-driven, not tick-driven (avoids flicker)
- Layout: horizontal row in top band, left to right in logical order (food first, then materials)
- Truncation: numbers over 999 shown as "1K+" or abbreviated format
- Zero values: display "0" with grayed icon (not hidden). Resources not yet discovered are hidden entirely from the counter row.

**Input mapping**:
- Read-only — no interaction
- Optional: hover over a counter to show storage breakdown (per GDD)

**Accessibility**: Numbers minimum 14px. Color changes (red for critical) paired with a warning icon per Standard tier.

**When to Use**: Displaying current quantities of persistent game resources in any always-visible UI.
**When NOT to Use**: When showing per-item details (use Resource List or Storage Panel instead).

---

### Storage Panel Toggle

**Category**: Navigation
**Used In**: HUD

**Description**: A collapsible panel anchored to the top-right corner of the screen beneath the HUD top band. When collapsed, it shows only the storage capacity summary (used/total). When expanded, it reveals individual resource counts with storage breakdown. The panel is toggled by a dedicated storage icon in the top band.

**Specification**:
- Collapsed state: shows "used/total" capacity line
- Expanded state: list of all resources with current count + max capacity per resource
- Maximum expansion height: 300px (scrollable if content exceeds)
- Toggle target: storage icon in top band
- Persisted state: remembers expanded/collapsed between screen transitions
- Expansion does NOT block gameplay view (floating panel, not modal)

**Input mapping**:
- Mouse: click storage icon to toggle expand/collapse
- Keyboard: Tab to reach storage icon, Enter to toggle
- Gamepad: d-pad to navigate to storage icon, A to toggle

**Accessibility**: Per Standard tier, the expanded panel must be keyboard-reachable via Tab order. Each resource row must have focusable indicators for accessibility.

**When to Use**: Any always-available panel that should be discoverable but not permanently visible.
**When NOT to Use**: For panels that are context-dependent (only visible when relevant) — use Contextual panels instead.

---

### Status Badge Indicators

**Category**: Visual Feedback
**Used In**: Build Placement, Building Detail, Transportation

**Description**: Small icon+color badges adjacent to buildings, list items, or UI elements that communicate the current state of a system component. Each state has a unique icon and color combination. Per accessibility requirements, no state is communicated by color alone — every badge uses an icon paired with a color.

**Specification**:
- Each state maps to a unique icon + color (e.g., operating = green check, blocked = red X, stalled = orange triangle, no carrier = blue info)
- Badges are small (16x16px) — used inline with text or as overlay on building sprites
- State changes are animated (brief flash or icon swap) for awareness
- Colorblind-safe encoding: icon must be independently recognizable

**Input mapping**:
- Passive display
- Optional: hover over a badge to see a tooltip explaining the state

**Accessibility**: Icon + color pairing required. Badge colors must meet 4.5:1 contrast ratio against background. Per reduced-motion toggle, badge animations (flash/swing) can be disabled.

**When to Use**: Communicating the operational state of any game entity or system component at a glance.
**When NOT to Use**: For detailed status information — use a tooltip or detail panel instead.

---

### Tabbed Navigation

**Category**: Navigation
**Used In**: Building Detail

**Description**: A horizontal tab bar at the top of a detail panel allows switching between different views of the same entity (NPC, Input, Output, Transport). Only one tab is active at a time. Tab content replaces rather than scrolls.

**Specification**:
- Tabs are horizontal, positioned at the top of the panel
- Active tab: underline or filled background to distinguish from inactive tabs
- Content area below tabs changes entirely on tab switch
- Tab order follows logical priority (NPC assignment → Input → Output → Transport)
- Tab selection is immediately effective — no "apply" button needed

**Input mapping**:
- Mouse: click a tab to switch
- Keyboard: Tab to reach tab bar, then Tab/Shift+Tab or Arrow keys to navigate tabs, Enter to activate
- Gamepad: d-pad/nub to navigate tabs, A to select

**Accessibility**: All tabs must be focusable and activatable via keyboard. Focus order within tab bar must match visual left-to-right order. Per Standard tier, focus indicator (2px outline ring) must be visible on each tab.

**When to Use**: When a single screen has multiple distinct data views that can't all fit simultaneously.
**When NOT to Use**: When all views are equally important and should be visible together — use a multi-column layout instead.

---

### NPC Assignment List

**Category**: Data Display + Input
**Used In**: Building Detail

**Description**: A scrollable list showing available NPCs for assignment to a building slot. Each row displays the NPC's name, state, and availability. The player can assign or unassign NPCs from this list. The list updates dynamically as NPCs become available or assigned.

**Specification**:
- Each row: NPC name + state indicator (idle/assigned/traveling) + assign/unassign button
- Available NPCs: shown at top, highlighted
- Assigned NPCs: shown at bottom, grayed out
- Scroll behavior: vertical scroll when list exceeds visible area (max height: 300px). Gamepad: each d-pad press scrolls one row, auto-scroll keeps focused item visible in viewport. No scroll wrapping.
- Assignment is immediate — no confirmation dialog needed for simple assignments
- Unassignment requires confirmation if the building might stall

**Input mapping**:
- Mouse: click assign/unassign button, scroll wheel for overflow
- Keyboard: Tab through list rows, Enter/Space to assign, Delete to unassign
- Gamepad: d-pad to navigate rows, A to assign, B to cancel assignment

**Accessibility**: Each row must have a focusable action button. Per colorblind requirements, NPC state uses icon + text (not color alone). Row height optimized for 1-click readability.

**When to Use**: Any list where the player selects from available entities to fill slots or assign roles.
**When NOT to Use**: For read-only lists — use a simple data display pattern instead.

---

### Confirmation Dialog

**Category**: Modal
**Used In**: Build Placement

**Description**: A modal overlay appears before irreversible or high-cost actions to confirm the player's intent. The dialog displays the action details, the cost/resources involved, and explicit confirmation/cancel options. This pattern prevents accidental permanent changes (building placement consumes resources with no refund on demolition).

**Specification**:
- Modal overlay with dark semi-transparent background
- Dialog centered or positioned near the triggering element
- Content: action title, description of what will happen, cost/resources, confirmation and cancel buttons
- Confirmation button: visually distinct (higher contrast, larger)
- Cancel button: always available (Escape key, click outside dialog, X button)
- Cannot be bypassed — player must explicitly confirm or cancel
- Dialog locks all other UI interaction while open

**Input mapping**:
- Mouse: click confirm/cancel buttons, click outside dialog or Escape to cancel
- Keyboard: Tab to buttons, Enter to confirm, Escape to cancel
- Gamepad: d-pad to navigate buttons, A to confirm, B to cancel

**Accessibility**: Modal must trap focus (keyboard focus cannot reach background elements). Dialog title must be readable at 16px minimum. Per Standard tier, any urgency indicators in the dialog must use icon + color.

**When to Use**: Before any action that permanently consumes resources, cannot be undone, or has significant downstream consequences.
**When NOT to Use**: For reversible actions (e.g., toggling a setting, changing a visual preference).

---

### Hover Tooltip

**Category**: Visual Feedback
**Used In**: Building Detail, Build Placement, Transportation

**Description**: Contextual information appears near the cursor or element when the player hovers over it. Tooltips display concise information relevant to the hovered element (building status, resource count, NPC name, block reason). Tooltips do not block the underlying element.

**Specification**:
- Trigger: mouse hover or gamepad focus on an element
- Content: short text, optionally with icon
- Position: follows cursor, or appears above/below the element to avoid edge clipping
- Disappear: cursor leaves element, or gamepad focus moves away
- Delay: brief (~200ms) to avoid flicker on rapid cursor movement
- Stack: tooltips from nested elements show the outermost element's tooltip

**Input mapping**:
- Mouse: hover to show
- Keyboard: Tab-focus shows the same information (tooltip content must be accessible without hovering)
- Gamepad: focus on element shows tooltip content

**Accessibility**: Tooltip content must be available via keyboard focus (Tab) — do not rely solely on hover. Per Standard tier, tooltip text minimum 14px. If tooltip conveys state (valid/invalid), use icon + text.

**When to Use**: Providing supplementary information about an element without requiring the player to open a detail view.
**When NOT to Use**: For actions that require confirmation or multi-step interaction — tooltips are read-only.

---

### Map-Select Interaction

**Category**: Input + Navigation
**Used In**: Transportation

**Description**: A UI panel closes to let the player select an element on the game map. The player clicks a building, tile, or entity on the map to populate a field in the panel, which then reopens with the selection confirmed. This pattern bridges between screen-based UI and gameplay view.

**Specification**:
- Panel closes when the player enters "select mode" (e.g., clicking "Select From Building")
- Map highlights selectable elements (buildings, tiles) with a visible indicator (highlight outline, glow, or ghost)
- Non-selectable elements are dimmed or unhighlighted
- Player clicks a selectable element to confirm the selection
- Panel reopens with the selected element's information populated
- Escape or timeout cancels selection mode and closes the panel entirely
- Selectable range: only buildings within operational range are highlighted

**Input mapping**:
- Mouse: click building on map to select
- Keyboard: Arrow keys to navigate between highlighted buildings on map (not Tab — Tab is reserved for screen-level UI), Enter to select, Escape to cancel
- Gamepad: d-pad/nub to cycle through highlighted buildings, A to select, B to cancel

**Accessibility**: Keyboard navigation between buildings must have visible focus indicators on each building tile. Per Standard tier, building highlight state must be visible to colorblind players (outline style or icon, not color alone).

**When to Use**: When the player needs to select an in-world entity (building, tile, NPC) as part of a UI configuration flow.
**When NOT to Use**: When the selection is from a small, fixed list that fits on-screen — use a dropdown or list instead.

---

## Animation Standards

| Animation | Duration | Easing | Reduced Motion |
|-----------|----------|--------|----------------|
| Ghost preview color change (green→red) | 100ms | instant | N/A — no animation |
| Ghost preview appear/disappear | 150ms | ease-out | instant |
| Status badge state change (flash/swap) | 200ms | ease-in-out | instant, icon swap only |
| Speed cycle label update | 50ms | instant | N/A — text only |
| Storage panel expand/collapse | 200ms | ease-out | instant (no slide) |
| Toast appear | 150ms | ease-out slide from bottom | instant fade |
| Toast dismiss | 150ms | ease-in fade out | instant |
| Confirmation dialog open/close | 200ms | ease-out | instant |
| Tab content replacement | 100ms | instant | N/A — no animation |
| NPC list row highlight | 100ms | ease-out | N/A — color only on bg |
| Building map highlight (map-select) | 150ms | ease-out | N/A — outline only |
| All other state transitions | 100ms | ease-out | instant |

**Global rule**: A reduced-motion toggle (defined in accessibility-requirements.md) replaces all non-essential animations with instant transitions. Essential animations (ghost preview color change for validity) are never removed — they are inherently non-animated.

---

## Sound Standards

| Interaction | Sound | Duration | Volume |
|-------------|-------|----------|--------|
| Ghost preview valid/invalid | No sound | — | — |
| Ghost preview confirm placement | Click | 80ms | 70% |
| Ghost preview cancel | Subtle release | 100ms | 50% |
| Speed cycle change | Click tick | 50ms | 60% |
| Play/pause toggle | Soft beep | 100ms | 50% |
| Toast appear (info) | No sound | — | — |
| Toast appear (warning/error) | Short chime | 200ms | 60% |
| Storage panel toggle | Click | 80ms | 50% |
| Status badge change | No sound | — | — |
| Tab switch | Click | 80ms | 50% |
| NPC assign/unassign | Click (confirm) | 80ms | 60% |
| Confirmation dialog open | Subtle click | 100ms | 40% |
| Confirmation dialog confirm | Click | 80ms | 70% |
| Confirmation dialog cancel | Release | 100ms | 40% |
| Tooltip show | No sound | — | — |
| Map-select building highlight | No sound | — | — |
| Map-select confirm | Click | 80ms | 60% |
| Map-select cancel | Release | 100ms | 40% |

**Global rule**: All sounds are muted when audio is set to zero in settings. Per reduced-motion toggle, no sound behavior changes — animation is reduced but audio feedback remains (sound and motion are separate accessibility dimensions).

---

## Gaps & Patterns Needed

The following patterns are referenced or implied in existing UX specs but are not yet formalized here. They should be added as their parent specs are reviewed and finalized.

| Pattern | Needed For | Source | Priority |
|---------|-----------|--------|----------|
| **Build Menu Grid** | Build Placement | build-placement.md references the building selection grid but does not formalize the grid interaction (scrollable icon grid, selection highlight, cost preview on hover) | HIGH |
| **Building Selection (Gameplay)** | Building Detail | building-detail.md assumes clicking a building tile on the map — no spec formalizes the gameplay-view-to-panel transition | HIGH |
| **Drag-and-Drop Transport** | Player Character | player-character-system GDD describes drag-and-drop transport (pick up item → carry → deposit), but no UX spec formalizes this pattern | MEDIUM |
| **Resource List** | HUD | hud.md mentions storage panel but the per-resource row pattern could be abstracted into a reusable list pattern | LOW |
| **Notification Tray** | HUD | W6 in hud-system GDD requires a single consolidated Notification Tray before MVP — not yet detailed in any spec | MEDIUM |
| **Pause Menu** | All | Pause menu spec does not exist yet — will need its own UX spec, then extract patterns (resume, settings navigation, quit) | MEDIUM |

Patterns with MEDIUM or HIGH priority should be formalized before the next `/gate-check pre-production`.

---

## Open Questions

- **Gamepad coverage**: Most patterns specify gamepad input, but the current UX specs (main-menu, hud, build-placement, building-detail, transportation) were primarily designed for mouse. Should gamepad navigation order be formally defined for each pattern, or deferred until the pause menu and full-screen UX specs are authored?
- **Toast consolidation (W6)**: The HUD GDD requires all alerts consolidate into a single Notification Tray. Is the Notification Tray a new pattern or an extension of the existing Toast pattern? If it's an extension, should "Notification Tray" be added as a variant of Toast rather than a separate pattern?
- **Route List Card**: transportation.md references "Route List Card" as a "new pattern (route list card)" in its component inventory. Should this be formalized as a separate pattern in the library, or is it a composite of existing patterns (tabbed navigation + status badges + NPC assignment list)?
