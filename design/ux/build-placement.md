# UX Spec: Build Placement

> **Status**: In Design
> **Author**: user + ux-designer
> **Platform Target**: PC (Steam / Epic)
> **Last Updated**: 2026-05-18
> **Journey Phase(s)**: unknown — no player journey map
> **Template**: UX Spec

---

## Purpose & Player Need

This screen serves two interrelated goals that the player cycles through during a session:

1. **Place a building** — The player selects a building type from the Building Menu, checks affordability (resources + energy), places it on a valid tile, and then manually initiates construction. Every placement is irreversible and consumes resources — no demolition refunds. The placement decision is a spatial puzzle: proximity to resources, proximity to storage, proximity to housing. The player wants to find the optimal position before committing.

2. **Manage existing buildings** — The player clicks on existing buildings to change NPC assignments, check production status, or demolish buildings. This interface is reactive — the player only enters when a decision is needed (missing NPC, missing storage, building wants demolition).

**What would go wrong:** Since resources are never refunded, a wrong placement permanently wastes 15 wood + 3 stone. Without clear visual feedback (ghost preview with block reason), the player places blindly. Bad placement = wasted resources + frustrated player. This undermines Pillar 1 ("Earned Automation") — automation must feel earned, not squandered through carelessness.

---

## Player Context on Arrival

Two arrival scenarios:

1. **Architect mode transition** — The player has just gathered enough resources for their first non-storage building (e.g., Lumber Camp). This is the first time they shift from manual labor to building management. They are cautious and deliberate: every decision matters because they don't yet know what works well and what doesn't. The emotional state is anticipatory — "I'm about to build something that changes how I play."

2. **Routine optimization** — The player already has a working village, multiple buildings, and known patterns. They enter intentionally (clicking the Build button to expand) or reactively (clicking a building to fix a bottleneck). Emotional state is focused and efficient: "I need another Lumber Camp near the forest, or I need to reassign an NPC to the stalled one."

In both cases, the player is **not time-pressured** — the game is paused or running at their chosen speed. They have the space to think before confirming.

---

## Navigation Position

```
Gameplay (map view — root)
├── Building Menu (overlay — build mode)
│   └── Ghost Preview (on map)
│       └── Build Mode Indicator (persistent banner)
│           └── Construction Decision Dialog (secondary modal)
└── Building Interaction Panel (separate overlay — management mode)
    ├── NPC Selection List (secondary popup)
    └── Demolish Confirmation (secondary dialog)

NOTE: The Building Interaction Panel (UI-3, UI-4, UI-5 from Building System GDD)
is a separate UI concern out of scope for this spec.
```

---

## Entry & Exit Points

### A. Building Menu (Placement Flow)

| Entry Source | Trigger | Player carries this context |
|---|---|---|
| HUD Building Button | Click | Current resource counts, energy level, map viewport, current build mode state |
| Keyboard shortcut (B) | Press B key | Same |

| Exit Destination | Trigger | Notes |
|---|---|---|
| Cancel — back to gameplay | Escape, right-click, click outside menu | Ghost disappears, menu closes, no resources spent |
| Confirm placement — ghost placed on tile | Left-click on valid tile | No resources deducted yet, ghost locks to tile |

### B. Ghost Preview (Placement Flow)

| Entry Source | Trigger | Player carries this context |
|---|---|---|
| Building Menu selection | Click building icon | Selected building type, build cost, energy cost |
| Re-open from Build Mode Indicator | Click building name in banner | Previously selected building type, ghost remains placed |

| Exit Destination | Trigger | Notes |
|---|---|---|
| Cancel placement | Escape, right-click, scroll-wheel away | Ghost disappears, returns to normal gameplay |
| Confirm tile placement | Left-click on valid tile | Ghost locks to tile (pending construction) |

### C. Construction Decision Dialog

| Entry Source | Trigger | Player carries this context |
|---|---|---|
| Click placed ghost | Left-click ghost on map | Building type, build cost, energy cost, tile position |

| Exit Destination | Trigger | Notes |
|---|---|---|
| Start construction | Click "Construct" | Resources deducted, energy deducted, ghost → CONSTRUCTING |
| Cancel placement | Click "Cancel", right-click, Escape | Ghost releases, back to preview mode |

---

## Layout Specification

### Information Hierarchy

| # | Information | Source | Priority |
|---|---|--------|----------|
| 1 | Ghost placement feedback (valid/blocked + reason) | UI-2 | **Must Show** — most critical, shown continuously during placement |
| 2 | Affordability (resources + energy + storage capacity) | UI-1, GDD Rule 2 | **Must Show** — shown before and during placement |
| 3 | Building identity (name, icon, cost, construction time) | UI-1, UI-2 | **Must Show** — shown in menu and ghost tooltip |
| 4 | Build mode state awareness (banner) | UI-6 | **Must Show** — persistent |

### Layout Zones

**Zone A — Building Menu (non-modal overlay panel):**

| Zone | Position | Components |
|------|----------|------------|
| Menu Panel | Bottom-center, anchored to bottom. Width scales to viewport (min 350px, max 600px). Height: shows up to 4 rows at once, scrolls if more. | Building icon grid (2-3 columns dynamically), per-row: icon (32×32 sprite) + name + cost + affordability + construction time + energy cost |
| Close target | Click outside panel, Escape, right-click | |

**Column layout:**
- ≤ 800px viewport width: 2 columns
- > 800px viewport width: 3 columns
- Scrollbar appears automatically when building count exceeds visible rows

**Zone B — Ghost Preview (rendered on map):**

| Zone | Position | Components |
|------|----------|------------|
| Ghost sprite | Cursor position, snapped to tile center | Sprite asset at 60% opacity, green tint (#4CAF50) if valid, red tint (#E74C3C) if blocked |
| Ghost tooltip | Below ghost (follows cursor to avoid occlusion) | Building name, build cost, construction time, energy cost, or block reason |
| Build mode banner | Top-center of screen, semi-transparent | "Build Mode — [Building Name] — Press Esc to cancel" |

### Component Inventory

| Zone | Component | Type | Interactive | Notes |
|------|-----------|------|-------------|-------|
| Building Menu | Building icon (32×32) | Button | Yes — selects building | Sprite asset (not emoji) |
| Building Menu | Building name | Text label | No | Label |
| Building Menu | Cost row (resource sprites + qty) | Info display | No | Resource indicator, real-time affordability |
| Building Menu | Affordability indicator | Status badge | No | Green/red/! based on Formula 1, includes storage capacity check |
| Building Menu | Construction time | Small text | No | Info text |
| Building Menu | Energy cost | Small text | No | Info text, rounded to integer from Formula 7 |
| Building Menu | Scrollbar | Scrollbar | Yes | Standard scrollbar |
| Ghost Preview | Ghost sprite | Visual overlay | No — follows cursor, no click | 60% opacity, tinted green/red |
| Ghost Preview | Ghost tooltip | Tooltip | No | Hover tooltip, follows cursor. Distinct from GDD UI-5 (hover tooltip on existing buildings with 250ms delay). This is an instant-show placement-mode preview only. |
| Build Mode | Banner | Persistent indicator | Partial — building name clickable | Persistent state indicator |
| Ghost Placed | Placed ghost | Interactive building preview | **Yes** — click opens Construction Decision Dialog. Right-click releases. | Solid (100% opacity), no "click to start" prompt — visual change (60% → 100%) signals interactivity |
| Decision Dialog | "Construct" button | Primary button | Yes | Green, prominent |
| Decision Dialog | "Cancel" button | Secondary button | Yes | Gray |

### ASCII Wireframe

```
+---------------------------------------------------------------+
|  [Build Mode Banner: "Lumber Camp — Press Esc to cancel"]     |
|                                                               |
|          [  map view with green/red ghost at cursor  ]        |
|                                                               |
+---------------------------------------------------------------+
|  [ Building Menu Panel ]                                      |
|  +--------------------------+  +--------------------------+   |
|  | [sprite] Lumber Camp     |  | [sprite] Residential H.  |   |
|  | [15][3]  ⚡1  200t        |  | [10][3]  ⚡1  150t       |   |
|  | (affordable)             |  | (! need 2 more wood)     |   |
|  +--------------------------+  +--------------------------+   |
|  +--------------------------+  [more rows scrollable...]    |
|  | [sprite] Storage Bldg.   |                               |
|  | [8]  [2]  ⚡1  120t       |                               |
|  | (affordable)             |                               |
|  +--------------------------+                               |
+---------------------------------------------------------------+

Construction Decision Dialog (appears near placed ghost):
+------------------------------------------+
|  Place Lumber Camp?                      |
|                                          |
|  Cost: 15 Wood + 3 Stone + 1 Energy      |
|  Construction: 200 ticks (manual)        |
|                                          |
|  [Construct]    [Cancel]                 |
|  (green)          (gray)                 |
+------------------------------------------+
```

---

## States & Variants

| State / Variant | Trigger | What Changes |
|-----------------|---------|--------------|
| **Menu empty** | No buildings affordable or available | Menu shows only available building types. If no buildings can be placed, display "No buildings available — gather more resources." |
| **Menu — all affordable** | Resources + energy + storage sufficient | All rows green |
| **Menu — partially affordable** | Missing some resources/energy/capacity | Green/! mixed per row |
| **Ghost preview** | Building selected, ghost follows cursor, tile not confirmed | Green tint if valid, red tint if blocked. No resources consumed. Ghost is a preview only. |
| **Ghost placed (pending construction)** | Player confirms tile but hasn't started construction | Ghost locks to tile, appears solid (not semi-transparent). No resources deducted yet. Short soft click audio cue plays to signal interactivity. Tab focus / D-pad targeting shows a small tooltip near the ghost: "Place [Building] — Press Enter to confirm." Click, A button, or Enter activates the Construction Decision Dialog. Right-click or B button cancels and releases.
| **Construction Decision Dialog** | Player clicks placed ghost | Modal dialog: "Place [Building]?" with cost, construction time, Construct/Cancel buttons. No "click to start" prompt near the ghost — the visual change (60% → 100% opacity) alone signals interactivity. |
| **Ghost constructing** | Manual construction started via dialog | Construction progress bar visible on building. Scaffolding overlay. Resources deducted at dialog confirmation. Energy deducted. |
| **Game paused during ghost** | Player pauses while ghost is visible or placed | Ghost remains. If placed, construction progress halts. Dialog is disabled until resumed. |
| **Data unavailable (initial load)** | Building Registry or Inventory System not yet initialized | Menu shows "Loading…" placeholder. All rows disabled. Ghost does not appear. Resolves automatically when systems are ready. No resources can be selected or placed. |

---

## Interaction Map

Mapping interactions for: Keyboard/Mouse (primary) + Gamepad (partial). Covering partial gamepad support.

| Component | Action | Keyboard/Mouse | Gamepad | Immediate Feedback | Outcome |
|-----------|--------|----------------|---------|-------------------|---------|
| **Open Building Menu** | Open build mode | Click HUD Build Button | Press menu button (options/start) | Menu panel slides up from bottom | Building Menu visible, ghost not yet active |
| **Select building** | Select from menu | Left-click building icon | Analog stick → A button | Selected building highlighted with border | Menu closes, ghost appears at cursor |
| **Close menu** | Close without selection | Click outside menu, Escape | Back button | Menu panel slides down | Back to gameplay, no ghost |
| **Ghost — valid tile** | Hover over valid tile | Move cursor | Analog stick move | Green tint + green border | Visual feedback only |
| **Ghost — invalid tile** | Hover over invalid tile | Move cursor | Analog stick move | Red tint + red border + tooltip | Visual feedback only |
| **Confirm placement** | Place ghost on tile | Left-click on valid tile | A button | Ghost snaps to tile, becomes solid (100% opacity) | Ghost Placed state — no resources deducted |
| **Cancel ghost** | Cancel placement | Escape, right-click, scroll-wheel | Back button, Left shoulder | Ghost fades out | Back to gameplay, nothing committed |
| **Open decision dialog** | Activate placed ghost | Left-click placed ghost, Tab-focus + Enter | A button (when ghost is targeted), Analog stick to target ghost + Confirm | Dialog fades in near ghost, short "click" audio cue | Construction Decision Dialog visible |
| **Start construction** | Confirm in dialog | Click "Construct" | Confirm button (X/A) | Scaffolding overlay fades in, progress bar appears | Resources deducted, energy deducted, Ghost Constructing state |
| **Cancel placement** | Reject in dialog | Click "Cancel" | Cancel button (B/O) | Dialog fades out, ghost returns to preview | Ghost Placed → Ghost Preview |
| **Release ghost** | Release unstarted ghost | Right-click placed ghost | Cancel button (B/O) | Ghost fades out | Back to Ghost Preview (select again) |
| **Build Mode banner** | Close build mode | Press Escape | Back button | Banner fades out over 300ms | Back to gameplay |
| **Build Mode banner** | Reopen menu | Click building name in banner | Confirm button (X/A) on banner focus | Menu panel slides up, previous selection retained | Menu visible, ghost remains placed |
| **Menu scrollbar** | Scroll up | Mouse wheel, Page Up, Shift+Arrow Up | Analog stick Up (when scrollbar focused) | Scrollbar thumb moves, rows shift | Previous selection retained |
| **Menu scrollbar** | Scroll down | Mouse wheel, Page Down, Shift+Arrow Down | Analog stick Down (when scrollbar focused) | Scrollbar thumb moves, rows shift | Previous selection retained |

---

## Events Fired

| Player Action | Event Fired | Payload / Data |
|---|---|---|
| Open Building Menu | `build_mode_opened` | `{mode: "menu"}` |
| Select building | `building_type_selected` | `{building_id, build_cost, construction_time, placement_energy_cost}` |
| Confirm placement | `ghost_placed` | `{building_id, x, y}` |
| Open decision dialog | `construction_decision_requested` | `{building_id, x, y, build_cost, energy_cost}` |
| Start construction | `construction_started` | `{building_id, x, y, build_cost_deducted, energy_deducted}` |
| Cancel placement (dialog) | `construction_cancelled` | `{building_id, x, y}` |
| Release ghost | `ghost_released` | `{building_id, x, y}` |
| Close build mode | `build_mode_closed` | `{mode: "cancelled" | "construction_started"}` |

**No event for:** Hover preview (ghost valid/invalid) — this is frame-rate polling, not an event.

---

## Transitions & Animations

| Transition | Enter | Exit | Notes |
|------------|-------|------|-------|
| **Building Menu open** | Slide up from bottom (200ms, ease-out) | Slide down (150ms, ease-in) | Non-modal — does not block gameplay |
| **Ghost appears** | Fade in (100ms) | Fade out (150ms, ease-in) | Appears at cursor position |
| **Ghost locks to tile** | Snap to tile center (100ms), opacity 60% → 100% | Fade out (150ms) | "Placement confirmed" visual snap. Short soft click audio cue (150ms) signals the ghost is now interactive.
| **Decision dialog open** | Fade in + scale (200ms, ease-out) | Fade out (150ms, ease-in) | Positioned near placed ghost, never off-screen |
| **Ghost → Constructing** | Scaffolding overlay fades in (300ms), progress bar appears (instant) | N/A — building enters normal lifecycle | Transition from build-placement UI to game-world visual |
| **Build Mode banner** | Fade in (200ms) | Fade out (300ms, ease-out) | Persistent state indicator |
| **Ghost cancel** | Fade out (150ms, ease-in) | N/A | No audio cue — clean cancel |

**Motion sickness:** No large-scale animations, no camera movement during placement. No reduced-motion toggle needed for this screen specifically.

---

## Data Requirements

| Data | Source System | Read / Write | Notes |
|------|--------------|--------------|-------|
| Building type list + build costs | Building Registry | Read | Full table of available building types |
| Build cost validation | Inventory/Storage System | Read | `get_resource(container_id, resource_id)` for each cost row — queried **every frame** during ghost mode for live affordability |
| Energy cost (Formula 7) | Formula (internal) | Read | `floor(Σ build_qty × 0.10)`, rounded to integer for display |
| Current player energy | Player Character System | Read | Energy pool value for affordability check |
| Current storage capacity | Inventory/Storage System | Read | Storage capacity available — queried every frame for live affordability. UI must show deficit if capacity < build cost. |
| Placement validation | Grid/Map System | Read | `validate_placement(x, y, building_id)` per frame during ghost movement |
| Ghost placement persistence | Building System | Write | `ghost_placed(building_id, x, y)` — stores pending placement |
| Resource deduction | Inventory/Storage System | Write | `try_consume()` when dialog confirms "Construct" |
| Energy deduction | Player Character System | Write | `consume_energy()` when dialog confirms "Construct" |
| Construction timer | Tick System | Write/Read | `construction_started(building_id)` subscribes to `on_ticks_advanced` |
| Current viewport position | Camera System | Read | To position decision dialog relative to viewport, avoid off-screen |

**Architectural concern:** Resources are deducted **at dialog confirmation** (not at menu open or ghost placement). The UI must query Inventory System every frame during ghost mode to show live affordability (resources + energy + storage capacity). But the actual write only happens on `construction_started`.

---

## Accessibility

| Requirement | Implementation |
|-------------|----------------|
| **Keyboard-only navigation** | Tab enters the menu panel. Arrow keys (Up/Down) cycle through building rows. Enter selects a building. Escape closes the menu. Tab cycles focus between Construct/Cancel buttons in the decision dialog. Arrow keys or Enter confirm/deny in the dialog. Escape closes the decision dialog without confirming. Tab focus order: menu items first, then scrollbar (if visible), then dialog buttons (when dialog is open). |
| **Gamepad navigation** | Analog stick (acts as d-pad) moves through building rows. X (PlayStation) / A (Xbox) / ↵ (Switch) confirms selection. B (PlayStation) / ○ (Xbox) / - (Switch) cancels and returns to previous state. R1/L1 (shoulder buttons) scroll the menu when focus reaches top/bottom. A on placed ghost opens dialog — analog stick selects Construct/Cancel, then same confirm/cancel buttons apply. Back (PlayStation) / Start (Xbox) / + (Switch) re-opens the Building Menu from the Build Mode banner. |
| **Text contrast** | All text meets WCAG AA against background. Cost text is small but ≥ 14px. |
| **Color-independent communication** | Affordability uses color + icon (check/exclamation) + text. Ghost uses color + opacity change + ground border. |
| **Focus indicators** | Keyboard/gamepad focus on menu items has visible outline (blue ring). |
| **Reduced motion** | Menu slide and ghost fade are short (<300ms) and use no large-scale movement. No motion-sensitive elements. |

---

## Localization Considerations

| Element | EN | DE | FR | Max chars |
|---------|----|----|----|-----------|
| Building name | "Lumber Camp" | "Holzfällerhütte" | "Camp forestier" | 15 EN / 20 DE / 18 FR |
| Block reason | "Cannot build here — occupied" | "Nicht hier baubar — belegt" | "Impossible de construire ici — occupé" | ~38 chars |
| Block reason | "Cannot afford building" | "Nicht bezahlbar" | "Construction non financée" | ~27 chars |
| Block reason | "Not enough energy" | "Nicht genug Energie" | "Pas assez d'énergie" | ~24 chars |
| Build mode banner | "Build Mode — Lumber Camp — Press Esc to cancel" | "Bau-Modus — Holzfällerhütte — Esc zum Abbrechen" | "Mode construction — Camp forestier — Échap pour annuler" | ~60 chars |
| Decision dialog header | "Place Lumber Camp?" | "Holzfällerhütte platzieren?" | "Placer le camp forestier ?" | ~24 chars |
| Decision dialog cost | "Cost: 15 Wood + 3 Stone + 1 Energy" | "Kosten: 15 Holz + 3 Stein + 1 Energie" | "Coût : 15 Bois + 3 Pierre + 1 Énergie" | ~40 chars |
| Decision dialog action | "Construct" | "Bauen" | "Construire" | 7 EN / 4 DE / 9 FR |

**HIGH PRIORITY for localization:**
- Block reason tooltips have variable length — tooltip container must auto-size
- Build mode banner is the most layout-critical element (top-center, fixed position) — German text is ~30% longer than English
- Decision dialog cost line concatenates multiple strings — consider formatting strings to allow reordering for languages with different word order

**External dependency note:** Ghost placement persistence (Open Questions Q1) depends on the Save/Load System (System #20 in Systems Index, not yet designed). The save/load implementation must include pending ghost placements in the Building System serialization snapshot.

---

## Acceptance Criteria

- [ ] Building Menu opens within 100ms from HUD button click or B key press
- [ ] Ghost preview appears within 50ms of building selection
- [ ] Ghost shows green tint and green border when hovering a valid, clearable tile
- [ ] Ghost shows red tint and red border when hovering an invalid tile (occupied, impassable, out of bounds, resource tile)
- [ ] Tooltip under ghost shows correct block reason (e.g., "Cannot build here — occupied") for each invalid tile type
- [ ] Affordability indicator is green when resources + energy + storage capacity are sufficient, red with "!" when insufficient, showing deficit quantity
- [ ] Confirming placement locks ghost to tile as "pending construction" — no resources deducted
- [ ] Clicking placed ghost opens Construction Decision Dialog with build cost, construction time, Construct and Cancel buttons
- [ ] Clicking "Construct" in dialog deducts resources and energy, places building in CONSTRUCTING state
- [ ] Clicking "Cancel" or right-clicking places ghost releases it — no resources deducted, back to preview mode
- [ ] Build mode banner displays current building name and shows clickable building name to reopen menu
- [ ] Escape key cancels all build-mode states (ghost preview, placed ghost, decision dialog, construction) and returns to normal gameplay
- [ ] Building menu supports keyboard navigation (Tab enters menu, arrow keys cycle items) and gamepad analog stick navigation
- [ ] At least 4 interactive elements (building rows, scrollbar) are reachable via keyboard/gamepad navigation
- [ ] No HUD element from the build placement UI occupies the center 60% of the horizontal axis or center 40% of the vertical axis (HUD safe zone)
- [ ] Placement survives game save/load: ghost placed on tile persists after pause + save + reload (gated on Save/Load System completion — System #20 in Systems Index)

---

## Scope Notes

- **UI-3 (Building Interaction Panel)** and **UI-4 (Demolish Confirmation)** — handled by a separate Building Interaction Panel UX spec (management mode, not placement mode).
- **UI-7 (Construction Completion Notification)** — handled by the HUD UX spec as a top-right notification element. This spec covers placement-only interactions.

---

## New Patterns (for interaction pattern library)

The following patterns are invented in this spec and should be added to the interaction pattern library when it is created:

| Pattern | Description |
|---------|-------------|
| Ghost Preview | Cursor-following semi-transparent building overlay with validity tint (green/red). Not interactive — only follows cursor and snaps to tile on confirm. |
| Build Mode Banner | Persistent top-center state indicator showing current build mode, building name, and cancel hint. Building name is clickable to reopen menu. |
| Placement Decision Dialog | Contextual modal that appears near a placed ghost (never off-screen). Offers Construct/Cancel — no "click to start" prompt, visual opacity change signals interactivity. |
| Affordability Badge | Color + icon + text status indicator on menu rows. States: (1) **Affordable** — green check icon, no additional text. (2) **Insufficient resources** — red exclamation icon, text shows deficit quantity (e.g., "! Need 2 more wood"). (3) **Insufficient energy** — red exclamation icon, text shows "low energy". (4) **Insufficient storage capacity** — red exclamation icon, text shows "need X more capacity". (5) **Combination deficit** — red exclamation icon, text shows highest-priority deficit (resources > energy > capacity). Updates in real-time as inventory changes (every frame during ghost mode). Never static — always reflects current state. |

---

## Open Questions

1. **Ghost placement persistence** — If the player pauses the game while the ghost is placed (not yet constructing), should it persist across save/load? **Decision: YES.** If the player has committed to a position, losing it on reload would be frustrating.
2. **Energy cost display** — Formula 7 rounds to integer via `floor()`. Should the UI show only the rounded integer (e.g., "1") or the exact value (e.g., "1.3")? **Decision: Show rounded integer.** All non-free buildings cost 1 energy at the default formula, so the rounded value is already the game value.
3. **Resource indicators in cost row** — Should we use sprite assets or emoji-style icons? **Decision: Sprite assets.** Consistent with art direction. Each resource type needs a small icon (16×16px).
4. **Storage capacity check timing** — Should affordability indicator reflect storage capacity in real-time, or only at placement? **Decision: Real-time in the menu.** The player should see "need 2 more capacity" before selecting a building.
