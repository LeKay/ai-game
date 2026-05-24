# UX Spec: Building Detail

> **Status**: APPROVED (2026-05-19 via /ux-review)
> **Author**: user + ux-designer
> **Last Updated**: 2026-05-18
> **Platform Target**: PC (Steam / Epic)
> **Accessibility Tier**: Undefined — no `accessibility-requirements.md` exists yet
> **Journey Phase(s)**: unknown — no player journey map
> **Template**: UX Spec
> **GDD**: design/gdd/building-system.md

---

## GDD Scope

This spec covers the **Building Interaction Panel** (UI-3, UI-4, UI-5) from `design/gdd/building-system.md`.

| GDD UI Element | Covered Here? | Covered In |
|---|---|---|
| UI-1: Building Menu | No | Separate build mode UX spec |
| UI-2: Placement Ghost Preview | No | Separate build mode UX spec |
| UI-3: Building Interaction Panel | Yes | This spec |
| UI-4: Demolish Confirmation | Yes | This spec |
| UI-5: Hover Tooltip | Yes (read-only) | This spec |
| UI-6: Build Mode Indicator | No | Separate build mode UX spec |
| UI-7: Construction Completion Notification | No | HUD spec |

## Purpose & Player Need

The building detail panel is the player's primary management interface for buildings already on the map. It has five responsibilities:

1. **Check building status** — The player wants to know what a building is doing: is it producing, idle, blocked, or under construction? What is its current progress? This is the most frequent use case — a quick scan while planning the next move.
2. **Assign or release NPCs** — The player wants to give a production building an operator (assign NPC) or free one up for another building (release NPC). This is a decision point: the player is managing scarce NPC labor across competing buildings.
3. **Demolish a building** — The player wants to remove a building from the map. This is a deliberate, irreversible action that permanently loses the build cost. The panel must surface demolition behind clear confirmation.
4. **Identify bottlenecks** — When a building is BLOCKED or STALLED, the player needs to see the reason immediately ("No NPC assigned", "Missing wood", "Storage full", "No carrier assigned") so they can take corrective action.
5. **Monitor and navigate to transportation** — Input wares must be carried to the building; output wares must be carried away. The panel shows a summary of the building's transport status (carrier assigned, idle, or missing) and provides a direct link to the Transportation UI where routes and carriers are configured. The full transport UI is defined in a separate spec (`design/ux/transportation.md`).

What would go wrong if this screen was hard to use? The player clicks a building expecting to assign an NPC, but can't find the action — production stalls silently and the player wastes time figuring out why nothing is producing. Demolish without clear confirmation risks permanent resource loss from accidental clicks. A building can produce perfectly yet never deliver output because no carrier route was set up — if the panel doesn't surface that gap the player has no idea where the chain is broken. Too much info crammed into the panel means the player can't quickly scan to find what they need.

"The player arrives at this panel wanting to make one decision: assign, release, or demolish — and to understand the building's current state first. Transport status is a supporting signal, not the primary decision."

---

## Player Context on Arrival

The primary arrival scenario: **The player has just finished building a production building and immediately clicks it to assign an NPC.**

This is the first time the player manages an NPC — the transition from "I do everything myself" to "I delegate tasks to workers." The emotional state is anticipatory: the player has just invested resources and time into constructing this building, and now needs to activate it. They are not time-pressured — the game runs at their pace.

Secondary scenarios:
- **Routine optimization** — The player clicks a building already in production to check its status or reassign an NPC for layout reasons.
- **Reactive management** — The player clicks a building because a production warning icon indicates a problem (blocked, stalled, or no carrier). Emotional state is focused: "What's wrong and how do I fix it?"
- **Transport setup** — The player clicks a newly constructed production building and notices the transport status shows "No carrier assigned." They use the "Manage Transport" link in the panel to open the Transportation UI and configure a route.
- **Demolition planning** — The player has decided a building is in the wrong location or is redundant, clicks to initiate demolition. Emotional state is deliberate: they have already weighed the sunk cost.

---

## Navigation Position

The building detail panel is a **non-modal overlay** centered on screen. It sits between the HUD and the gameplay view — visible on top of the game world but not above the HUD.

```
Gameplay View (root)
├── Building Detail Panel (contextual overlay — centered on screen)
│   └── NPC Selection List (secondary popup — child of Building Detail)
│   └── Demolish Confirmation (secondary dialog — child of Building Detail)
│   └── → Transportation UI (separate overlay — opened via "Manage Transport" link)
└── HUD (always visible, above the panel)
```

It is always reachable from the gameplay view by clicking on an existing building tile. It is never a top-level destination — it only exists as a direct response to player selection. It is mutually exclusive with build placement mode: build mode must be exited before the detail panel can be opened.

---

## Entry & Exit Points

### Entry Points

| Entry Source | Trigger | Player carries this context |
|---|---|---|
| Gameplay — building tile click | Left-click on existing building sprite | Building state (lifecycle state, production status, assigned NPC, assigned storage), tile position, current tick speed/pause state |

### Exit Points

| Exit Destination | Trigger | Notes |
|---|---|---|
| Close panel — back to gameplay | Click empty space, press Escape, click same building again (toggle) | Panel closes, building deselected. No state changes. |
| NPC Selection List — assign NPC | Click "Assign NPC" button | Opens as child popup within the panel. Closes after selection or cancel. |
| Demolish Confirmation — initiate demolition | Click "Demolish" button | Opens as child dialog within the panel. If confirmed: building destroyed, panel closes. |
| Transportation UI | Click "Manage Transport →" link | Opens as a separate overlay on top of gameplay. Building Detail panel stays open beneath. The full transport spec is in `design/ux/transportation.md`. |


---

## Layout Specification

### Information Hierarchy

| # | Information | Source | Priority |
|---|-------------|--------|----------|
| 1 | State indicator (color + text) | Building Registry | **Must Show** — immediately tells the player if the building is working, waiting, broken, or under construction |
| 2 | Building name | Building Registry | **Must Show** — confirms they selected the right building |
| 3 | Progress bar (if constructing/producing) | Building Registry | **Must Show** — how far along is the current cycle |
| 4 | Production rate: input per cycle → output per cycle | Recipe Database + Building Registry | **Must Show** — tells the player what this building does and whether it meets their needs |
| 5 | Tool charge remaining (if applicable) | Building Registry | **Must Show** — impending tool depletion must be visible before it causes a block (Pillar 2: Information Transparency) |
| 6 | Distance to storage (if production building) | Grid/Map System (Formula 3) | **Must Show** — tells the player the carrier travel time between this building and its storage. Longer distance = longer carrier round trips = lower effective throughput. Distance itself does not reduce output quantity or extend the production cycle. |
| 7 | Assigned NPC name | NPC System | **Must Show** — if OPERATING, shows who is running it. If BLOCKED due to no NPC, shows "No NPC assigned" |
| 8 | Transport status summary | Transportation System | **Must Show** — shows whether a carrier is assigned to bring inputs and take away outputs. "No carrier assigned" must be clearly visible when missing, with a link to the Transportation UI. Full transport configuration is in `design/ux/transportation.md` |
| 9 | Action buttons: Assign NPC / Release NPC | Building UI | **Must Show** — only visible when relevant (appears/disappears based on state) |
| 10 | Demolish button | Building UI | **Must Show** — always present but visually de-emphasized (secondary button styling) |

**Priority grouping:**
- **Scan-first (top section):** State → Name → Progress → Production Rate → Tool Charge → Distance
- **Decision layer (middle section):** NPC info → Transport status → Action buttons
- **Destructive action (bottom section):** Demolish — separated visually from the decision layer

**Information flow:** The panel reads top to bottom as: "What is this?" → "What is it doing?" → "How well is it doing?" → "Who runs it and is it connected?" → "Can I change it?" → "Can I destroy it?"

### Layout Zones

**Zone 1 — Header Row (top, horizontal):**
- Left: Building name (bold, 16px)
- Right: Demolish icon button (small, icon-only, de-emphasized)
- Below name: State indicator (color dot + state text, 14px)

**Zone 2 — Progress Bar:**
- Horizontal fill bar showing construction/production progress (accumulated ticks / total ticks)
- Label with percentage: "Construction: 87/200 ticks (43%)" or "Production: 62/120 ticks (52%)"
- Only visible when applicable (CONSTRUCTING or producing)

**Zone 3 — Production Info (two-column: input left, output right):**
- **Input column (left):** Vertical list of required input resources per cycle. Each row shows: resource icon + name + quantity (e.g., 🪓 1 Tool, charge: 5.0). If charge is applicable, shown beneath the quantity in smaller text. Text turns red when ≤ 2 cycles worth remaining.
- **Output column (right):** Vertical list of produced output resources per cycle. Each row shows: resource icon + name + quantity (e.g., 🪵 5 Wood).
- A subtle vertical divider separates input and output columns.
- **Distance line (full-width, below both columns):** "Distance: 10 tiles → carrier ~30 ticks one-way" — informs the player of carrier round-trip time. Distance does NOT reduce output quantity or extend the production cycle; it affects how quickly the carrier can deliver inputs and collect outputs.

**Zone 4 — NPC Section (vertical):**
- Assigned NPC name (if assigned and OPERATING) or "No NPC assigned" (if BLOCKED)
- Action button(s) below name — only shown when relevant:
  - If has NPC assigned: "Release NPC" button
  - If no NPC assigned: "Assign NPC" button
  - Buttons are the primary interactive element of the panel — prominent styling
- "Assign NPC" opens the NPC Selection List showing only unassigned NPCs (assigned NPCs are not listed here)

**Zone 5 — Transport Section (vertical):**
- Single-line transport status for input carrier: "Carrier: [Name]" or "No carrier assigned (inputs)" in yellow when missing.
- Single-line transport status for output carrier: "Carrier: [Name]" or "No carrier assigned (outputs)" in yellow when missing.
- Below status lines: "Manage Transport →" link — opens the Transportation UI (separate overlay, spec: `design/ux/transportation.md`). Styled as a secondary text link, not a primary button — transport configuration is detailed work done in its own UI.
- This zone is always visible for production buildings. Hidden for residential/storage-only buildings that have no production inputs/outputs.

### Component Inventory

| Zone | Component | Type | Interactive | Notes |
|------|-----------|------|-------------|-------|
| Header | Building name | Label | No | 16px bold, Silkscreen |
| Header | State indicator | Text + colored dot | No | 14px. Color codes state: green=producing, yellow=blocked, red=stalled, orange=constructing, gray=idle |
| Header | Demolish icon button | Icon Button (icon only) | Yes | Small (24×24px), de-emphasized styling. Opens Demolish Confirmation dialog. Icon: crossed-out building |
| Progress | Progress bar | Fill Bar | No | Horizontal fill, background #3A3A3A, fill #D4A85C (golden) |
| Progress | Progress label | Text label | No | e.g., "87/200 ticks (43%)" |
| Input | Resource row (icon + name + qty) | Composite component | No | Each input resource gets its own row with icon, label, quantity. Charge shown as secondary line below qty |
| Input | Charge text | Text label | No | e.g., "charge: 5.0" — 14px, turns red when ≤ 2 cycles remaining |
| Output | Resource row (icon + name + qty) | Composite component | No | Each output resource gets its own row with icon, label, quantity |
| Input/Output | Column divider | Line/Border | No | Subtle vertical separator between input and output columns |
| Input/Output | Distance text | Text label | No | Full-width below both columns: "Distance: 10 tiles → carrier ~30 ticks one-way". No efficiency percentage — distance affects carrier schedule, not output quantity. |
| NPC | NPC name/status | Text label | No | 14px. "No NPC assigned" in yellow when blocked |
| NPC | Assign NPC button | Primary Button | Yes | Prominent styling, "Assign NPC" text |
| NPC | Release NPC button | Primary Button | Yes | Prominent styling, "Release NPC" text |
| Transport | Input carrier status | Text label | No | 14px. "No carrier assigned (inputs)" in yellow when missing |
| Transport | Output carrier status | Text label | No | 14px. "No carrier assigned (outputs)" in yellow when missing |
| Transport | Manage Transport link | Text Link | Yes | Secondary styling. "Manage Transport →" — opens Transportation UI (separate overlay) |

**Pattern library alignment:** The Assign/Release NPC buttons follow the primary button pattern from the main-menu spec (sharp rectangle, #5A5A5A fill, #A8A49C text, hover #4A7EA8 fill). The demolish icon button is an icon-only control — a new pattern for the interaction library.

### ASCII Wireframe

**Default state — Producing building:**

```
+----------------------------------------------------------+
|  Lumber Camp                      [Demolish icon]        |
|  [●] Producing                                             |
+----------------------------------------------------------+
|  Production: 87/100 ticks (87%)                          |
+----------------------------------------------------------+
|  Input          |  Output                                |
|  ────────────── | ─────────────────                      |
|  🪓 1 Tool      |  🪵 5 Wood                             |
|  charge: 5.0    |                                        |
|  ────────────── |                                        |
|  7.0 / 100.0    |                                        |
+----------------------------------------------------------+
|  Distance: 10 tiles → carrier ~30 ticks one-way          |
+----------------------------------------------------------+
|  Assigned: Lumberjack Hans                               |
|  [Release NPC]                                           |
+----------------------------------------------------------+
|  Carrier (in):  Courier Karl                             |
|  Carrier (out): Courier Karl                             |
|  Manage Transport →                                      |
+----------------------------------------------------------+
```

**Blocked state — no NPC assigned:**

```
+----------------------------------------------------------+
|  Lumber Camp                      [Demolish icon]        |
|  [●] Blocked — No NPC assigned                           |
+----------------------------------------------------------+
|                                                          |
+----------------------------------------------------------+
|  Input          |  Output                                |
|  ────────────── | ─────────────────                      |
|  🪓 1 Tool      |  🪵 5 Wood                             |
|  charge: —      |                                        |
+----------------------------------------------------------+
|                                                          |
|  No NPC assigned                                         |
|  [Assign NPC]                                            |
+----------------------------------------------------------+
|  No carrier assigned (inputs)                            |
|  No carrier assigned (outputs)                           |
|  Manage Transport →                                      |
+----------------------------------------------------------+
```

**Constructing state — progress visible, auto NPC spawn:**

```
+----------------------------------------------------------+
|  Residential House                  [Demolish icon]      |
|  [🟠] Constructing — 150/150 ticks (100%)                |
+----------------------------------------------------------+
|  Construction: 120/150 ticks (80%)                       |
+----------------------------------------------------------+
|                                                          |
|  NPC: First NPC spawned                                  |
|                                                          |
|  (no action buttons — NPC spawns automatically)          |
+----------------------------------------------------------+
```

**Stalled state — storage full:**

```
+----------------------------------------------------------+
|  Lumber Camp                        [Demolish icon]      |
|  [●] Stalled — Storage full                              |
+----------------------------------------------------------+
|  Production: 95/100 ticks (95%)                          |
+----------------------------------------------------------+
|  Input          |  Output                                |
|  ────────────── | ─────────────────                      |
|  🪓 1 Tool      |  🪵 5 Wood                             |
|  charge: 3.0    |                                        |
|  ────────────── |                                        |
|  3.0 / 100.0    |                                        |
+----------------------------------------------------------+
|  Distance: 10 tiles → carrier ~30 ticks one-way          |
+----------------------------------------------------------+
|  Assigned: Lumberjack Hans                               |
|  [Release NPC]                                           |
+----------------------------------------------------------+
|  Carrier (in):  Courier Karl                             |
|  Carrier (out): Courier Karl                             |
|  Manage Transport →                                      |
+----------------------------------------------------------+
```

**Low tool charge (≤ 2 cycles worth) — red text:**

```
|  🪓 1 Tool      |  🪵 5 Wood                             |
|  charge: 0.0    |                                        |
|  (RED — will block next cycle)                         |
```

---

## States & Variants

| State / Variant | Trigger | What Changes |
|-----------------|---------|--------------|
| **Constructing** — progress visible, auto NPC spawn | Building in CONSTRUCTING state | Progress bar shows accumulated ticks / build_time. NPC spawns automatically on completion — no action buttons shown. State text: "[Orange Dot] Constructing — X/Y ticks (Z%)" |
| **Operating — Producing** | Building in OPERATING state with active production cycle | Progress bar shows production cycle progress. Full production info: input → output, tool charge, distance. Assigned NPC name shown. "Release NPC" button visible |
| **Operating — Idle** | Building in OPERATING state but missing inputs for a cycle | Progress bar hidden (no active cycle). Production info shown but input line reads "Waiting for [resource]." NPC name shown if assigned. "Release NPC" visible. State text: "[Gray Dot] Idle — No inputs" |
| **Blocked — No NPC** | Building is BLOCKED because no NPC is assigned | State text: "[Yellow Dot] Blocked — No NPC assigned." "Assign NPC" button visible (primary action). Production info partially shown (input/output lines visible but no progress) |
| **Blocked — Missing resource** | Building is BLOCKED due to missing resource or tool | State text: "[Yellow Dot] Blocked — [reason]." Shows missing item. "Assign NPC" button visible if NPC is available. Production info shown with red input line indicating deficit |
| **Blocked — Insufficient tool charge** | Building is BLOCKED because no tool has sufficient charge | State text: "[Yellow Dot] Blocked — Insufficient charge." Tool charge line in red. All other production info visible |
| **Stalled — No carrier / buffer full** | Building is STALLED (output produced but carrier not collecting) | State text: "[Red Dot] Stalled — No output carrier" or "Stalled — Output buffer full." Progress bar shows 100% (cycle complete). Production info visible. "Release NPC" button visible. Transport section shows output carrier status prominently. |
| **Blocked — No input carrier** | Building has no carrier assigned for inputs only (outputs are fine) | State text: "[Yellow Dot] Blocked — No input carrier assigned." Transport section shows "No carrier assigned (inputs)" in yellow, output carrier status unaffected. "Manage Transport →" link visible. Production info shown. |
| **Blocked — No output carrier** | Building has no carrier assigned for outputs AND the output buffer is empty (production not yet completed, nothing waiting to be collected) | State text: "[Yellow Dot] Blocked — No output carrier assigned." Transport section shows "No carrier assigned (outputs)" in yellow. "Manage Transport →" link visible. Building is in a blocked state because without an output carrier, the building cannot accept new inputs (the input/output carrier loop is bidirectional — the building waits for the carrier to return from an existing output before accepting new work). If production somehow completes while in this state, the building transitions to STALLED (red) rather than remaining BLOCKED. |
| **No storage assigned** (EC-H5) | Building's assigned storage container was demolished | State text: "[Yellow Dot] Blocked — No storage assigned." All production info shown but marked as inoperative. "Assign Storage" option available |
| **NPC Selection List — open** | Player clicks "Assign NPC" | Opens as child popup within the panel. Lists only unassigned NPCs. Clicking an NPC assigns and closes the popup. Escape or click outside cancels |
| **Demolish Confirmation — open** | Player clicks demolish icon | Opens as child modal dialog centered over the panel. Layout: (top) large "!" warning icon (red, 32px). (middle) Dialog title: "Demolish [Building Name]?" (bold, 14px). (middle) Warning text: "This action cannot be undone. No resources will be refunded." (wrap-enabled, 12px). (bottom row) "Confirm Demolish" button (red fill, ~140px wide) on left — primary destructive action, keyboard/gamepad focusable. "Cancel" button (gray fill, ~100px wide) on right. Building sprite pulses red (opacity 100% → 70% → 100%, 600ms cycle) while dialog is open. Escape or B/Back cancels. Confirm triggers VFX-8 demolition sequence, panel closes. Dialog is modal — no other panel interaction possible while open. |
| **Empty / Minimal Data** | Building exists in registry but lacks complete data (e.g., no recipe assigned, no storage assigned, or registry entry partially loaded) | Panel shows building name and state indicator "[Yellow Dot] Blocked — Incomplete data." Production info zone shows placeholder: "Data unavailable." No action buttons. NPC zone shows "No NPC assigned." Transport zone hidden. State persists until data is resolved by the game system (should not occur in normal gameplay — indicates a data pipeline gap). |
| **Building demolished while panel open** | Building destroyed externally (e.g., by save/load) or player confirms demolition | Panel closes automatically. No error shown — demolition is the expected outcome |
| **Low tool charge** (conditional) | Tool charge ≤ 2 cycles worth remaining | Tool charge line text turns red: "Tool Charge: X.X / max — will block in N cycles" |

---

## Interaction Map

Mapping interactions for: Keyboard/Mouse (primary) + Gamepad (partial). Covering partial gamepad support.

| Component | Action | Keyboard/Mouse | Gamepad | Immediate Feedback | Outcome |
|-----------|--------|----------------|---------|-------------------|---------|
| **Open panel** | Click building tile | Left-click on building sprite | Crosshair on tile + A button | Panel fades in at screen center | Building detail panel visible |
| **Close panel** | Dismiss | Click empty space, Escape, click same building again | B/Back button | Panel fades out | Building deselected, back to gameplay |
| **Demolish** | Initiate demolition | Click demolish icon button (top-right) | D-pad focus + A button | Demolish Confirmation dialog opens | See Demolish Confirmation row |
| **Confirm demolish** | Confirm in dialog | Click "Confirm Demolish" or press Enter | A button | Building destroyed (VFX-8), panel closes | Building removed, NPC released, no refund |
| **Cancel demolish** | Reject in dialog | Click "Cancel" or press Escape | B/Back button | Dialog closes, building returns to normal | Panel stays open |
| **Assign NPC** | Open NPC list | Click "Assign NPC" button | A button on focused button | NPC Selection List popup opens | See NPC Selection List row |
| **Select NPC** | Choose from list | Click NPC name in list | Analog stick to navigate + A button | Selected NPC highlighted | NPC assigned, panel updates, list closes |
| **Cancel assign** | Cancel NPC selection | Click outside list or press Escape | B/Back button | List closes, no assignment | Panel stays open, unchanged |
| **Release NPC** | Free NPC from building | Click "Release NPC" button | A button on focused button | NPC unassigned, panel updates | Building enters BLOCKED state if no other NPC |
| **Manage Transport** | Open Transportation UI | Click "Manage Transport →" link | A button on focused link | Transportation UI opens as separate overlay | Player configures carrier routes; panel stays beneath |

**Focus order** (keyboard/gamepad): State indicator (read-only, not focusable) → NPC name/status → Assign NPC button / Release NPC button → Manage Transport link. The demolish icon button is focusable but requires deliberate navigation (it's at the right edge, not in the default Tab/D-pad cycle).

**Note:** Zones 1–3 (Header, Progress Bar, Production Info) contain only read-only elements and are not focusable. The first keyboard/gamepad focusable interactive element is the NPC action button (Assign/Release NPC) in Zone 4.

**Input mappings:**
- **Mouse**: hover to select building, click to open/close panel, click buttons for actions
- **Gamepad**: Analog stick positions crosshair over building (D-pad is not used for crosshair control — analog stick only — per platform config "no d-pad required"). Analog stick has a 15% deadzone; crosshair speed is constant (1 tile/10 ticks). On gamepad "snap-to-grid" is not used — crosshair must be manually aimed. A selects the building under the crosshair. Within the panel, analog stick (not D-pad) navigates interactive elements, A confirms.
- **Keyboard**: Click to open, Tab to focus panel elements, Arrow keys to cycle buttons, Enter/Space to activate, Escape to close

---

## Events Fired

| Player Action | Event Fired | Payload / Data |
|---|---|---|
| Open panel | `building_selected` | `{building_id, tile_x, tile_y}` |
| Close panel | `building_deselected` | `{building_id}` |
| Confirm demolish | `building_demolish_confirmed` | `{building_id}` |
| Assign NPC | `npc_assigned` | `{building_id, npc_id}` |
| Release NPC | `npc_released` | `{building_id, npc_id}` |
| Cancel demolish | `building_demolish_cancelled` | `{building_id}` |
| Cancel NPC selection | `npc_assignment_cancelled` | `{building_id}` |
| Click "Manage Transport →" | `transport_management_opened` | `{building_id}` |

**No event for:** Hovering, panel open/close state changes (these are UI-only transitions).

**Architectural concern:** The `building_demolish_confirmed` event modifies persistent game state (building removal, NPC release, output discard). This is the only action in this spec that has irreversible consequences — it must be gated behind the Demolish Confirmation dialog.

---

## Transitions & Animations

| Transition | Enter | Exit | Notes |
|------------|-------|------|-------|
| **Panel open** | Fade in + slight scale up (200ms, ease-out) | Fade out (150ms, ease-in) | Panel appears at screen center. |
| **NPC Selection List open** | Fade in + slide up (150ms, ease-out) | Fade out (100ms, ease-in) | Child popup within panel |
| **Demolish Confirmation open** | Fade in + scale (200ms, ease-out) | Fade out (150ms, ease-in) | Modal dialog on top of panel |
| **Building demolition (VFX-8)** | Sprite shrinks (300ms) + debris particles (300ms) | N/A | Panel closes as part of this sequence |
| **Low tool charge text** | Color change (instant) | Color change (instant) | No animation — color change is immediate when charge crosses threshold |
| **Progress bar fill** | Smooth fill animation (300ms, ease-out) | N/A | Bar fill changes as construction/production progresses |

**Motion sickness:** No large-scale animations. Panel fade/slide is under 250ms. Reduced-motion setting makes all transitions instant.

---

## Data Requirements

| Data | Source System | Read / Write | Notes |
|------|--------------|--------------|-------|
| Building name | Building Registry | Read | Static — set at building creation |
| Building lifecycle state | Building Registry | Read | ENTERING/CONSTRUCTING/OPERATING/BLOCKED/STALLED — drives which info sections are shown |
| Construction progress (accumulated ticks) | Building Registry | Read | Shown as progress bar + label when CONSTRUCTING |
| Production cycle progress | Building Registry | Read | Shown as progress bar + label when producing |
| Production recipe (input → output) | Recipe Database | Read | Read at panel open; not polled every frame — static per building type |
| Tool charge remaining | Inventory/Storage System | Read | Queried from the building's assigned tool slot. Must be polled on every state change (not every frame) — changes only when resources move in storage |
| Distance to assigned storage | Grid/Map System (Formula 3) | Read | Computed from building coordinates and storage container coordinates. Used to display carrier travel time ("~30 ticks one-way"). Static per building — recalculated if storage container position changes. |
| Assigned NPC name/ID | NPC System | Read | Read when panel opens and on any NPC state change signal |
| Available NPC list | NPC System | Read | Populated when "Assign NPC" button is clicked — not pre-cached |
| Missing input reason (when BLOCKED) | Building Registry | Read | Derived from which input check failed: NPC, resource, or tool charge |
| Input carrier assignment | Transportation System | Read | Carrier NPC assigned to deliver input wares to this building. Shown as carrier name or "No carrier assigned (inputs)". Read when panel opens and on transport state change signal |
| Output carrier assignment | Transportation System | Read | Carrier NPC assigned to collect output wares from this building. Shown as carrier name or "No carrier assigned (outputs)". Read when panel opens and on transport state change signal |

**Architectural note:** The panel is **read-only** — it displays data owned by other systems. The only write operations are `npc_assigned` and `npc_released` (which call NPC System APIs) and `building_demolish_confirmed` (which triggers the full demolition procedure). The `transport_management_opened` event is a navigation signal only — transport configuration is handled entirely within the Transportation UI (`design/ux/transportation.md`). The panel does NOT own or cache game state.

**Out of scope (transport):** Carrier route details, in-transit wares count, carrier ETA, and carrier assignment/removal are all out of scope for this spec. These are managed entirely within `design/ux/transportation.md`. This panel shows only carrier *assignment status* (who is assigned, or that none is assigned), not route or cargo details.

---

## Accessibility

| Requirement | Implementation |
|-------------|----------------|
| **Keyboard-only navigation** | Tab enters the panel. Arrow keys (Up/Down) cycle through interactive elements: NPC name/status (if focusable), Assign NPC / Release NPC buttons, Manage Transport link. The demolish icon button is reachable via Tab but is at the right edge — it appears after all primary elements. Escape closes the panel and any open child dialogs/popups. Enter/Space activates focused buttons and links. |
| **Gamepad navigation** | Analog stick moves through panel interactive elements: NPC name/status → Assign NPC / Release NPC buttons → Manage Transport link. D-pad focus order matches keyboard. A confirms. B/Back closes the panel or cancels open child dialogs (NPC list, demolish dialog). The demolish icon button is reachable via analog stick (requires deliberate navigation to right edge). |
| **Text contrast** | All text meets WCAG AA (≥4.5:1) against panel background (#2D2D2D). See contrast table below. |
| **Color-independent communication** | State indicators use color + text + colored dot shape. Full state text follows localization table format (e.g., "Blocked — No NPC assigned"). A colorblind player can identify every state from the text label alone. Tool charge uses color (red) plus explicit text: "will block in N cycles" — the text conveys the warning independently of color. |
| **Focus indicators** | Keyboard/gamepad focus on buttons has visible outline (blue ring, 2px). |
| **Reduced motion** | All panel transitions (fade 200ms, slide 150ms) are short and use no large-scale movement. A global reduced-motion toggle makes all transitions instant. |

**Contrast ratios** (panel background: #2D2D2D):

| Text element | Color | Contrast ratio | WCAG AA |
|--------------|-------|----------------|---------|
| Building name (16px bold) | #F0F0F0 | 14.3:1 | Pass |
| State indicator text (14px) | #E0E0E0 | 12.6:1 | Pass |
| Production info text (14px) | #D0D0D0 | 11.0:1 | Pass |
| NPC name/status (14px) | #D0D0D0 | 11.0:1 | Pass |
| Transport carrier name (14px) | #D0D0D0 | 11.0:1 | Pass |
| "No NPC assigned" / "No carrier assigned" (yellow #FFC107, 14px) | #FFC107 | 8.2:1 | Pass (AA Large also requires ≥3:1) |
| Transport link text | #A8A49C | 6.5:1 | Pass |
| Button text | #F0F0F0 | 14.3:1 | Pass |
| Progress bar label | #C0C0C0 | 9.3:1 | Pass |
| Warning text (red, tool charge) | #E57373 | 6.8:1 | Pass |
| Demolish dialog text (12px) | #D0D0D0 | 11.0:1 | Pass (AA Large) |

---

## Localization Considerations

| Text Element | EN | DE | FR | Max chars |
|--------------|----|----|----|-----------|
| Building name | "Lumber Camp" | "Holzfällerhütte" | "Camp forestier" | 15 EN / 20 DE / 18 FR |
| State: Producing | "Producing — 5 wood/cycle" | "Produziert — 5 Holz/Zyklus" | "Production — 5 bois/cycle" | ~30 EN / 38 DE / 36 FR |
| State: Blocked | "Blocked — No NPC assigned" | "Blockiert — Kein NPC zugewiesen" | "Bloqué — Aucun PNJ attribué" | ~28 EN / 34 DE / 34 FR |
| State: Stalled | "Stalled — Storage full" | "Gestoppt — Lager voll" | "Bloqué — Stockage plein" | ~23 EN / 23 DE / 25 FR |
| State: Constructing | "Constructing — 120/200 ticks (60%)" | "Bauend — 120/200 Ticks (60%)" | "Construction — 120/200 ticks (60%)" | ~40 EN / 40 DE / 42 FR |
| State: Idle | "Idle — No inputs" | "Leerlauf — Keine Inputs" | "Inactif — Pas d'intrants" | ~18 EN / 23 DE / 24 FR |
| Construction label | "Construction:" | "Bau:" | "Construction:" | ~15 EN / 8 DE / 14 FR |
| Production label | "Production:" | "Produktion:" | "Production:" | ~15 EN / 14 DE / 13 FR |
| Tool charge | "Tool Charge: 7.0 / 100.0" | "Werkzeug-Ladung: 7.0 / 100.0" | "Charge d'outil: 7.0 / 100.0" | ~30 EN / 36 DE / 30 FR |
| Distance | "Distance: 10 tiles → carrier ~30 ticks" | "Distanz: 10 Kacheln → Träger ~30 Ticks" | "Distance: 10 tuiles → transporteur ~30 ticks" | ~42 EN / 42 DE / 48 FR |
| Assign NPC | "Assign NPC" | "NPC zuweisen" | "Attribuer PNJ" | ~11 EN / 13 DE / 14 FR |
| Release NPC | "Release NPC" | "NPC freigeben" | "Libérer PNJ" | ~12 EN / 15 DE / 14 FR |
| No NPC assigned | "No NPC assigned" | "Kein NPC zugewiesen" | "Aucun PNJ attribué" | ~17 EN / 21 DE / 21 FR |
| Storage full | "Storage full" | "Lager voll" | "Stockage plein" | ~12 EN / 11 DE / 13 FR |
| No storage assigned | "No storage assigned" | "Kein Lager zugewiesen" | "Aucun stockage attribué" | ~21 EN / 24 DE / 25 FR |
| Will block warning | "will block in N cycles" | "blockiert in N Zyklen" | "bloquera dans N cycles" | ~25 EN / 25 DE / 26 FR |
| Demolish confirm dialog | "Demolish [Building]?" | "Abreißen [Gebäude]?" | "Démolir [Bâtiment]?" | ~22 EN / 25 DE / 27 FR |
| Demolish warning | "This action cannot be undone. No resources will be refunded." | "Diese Aktion kann nicht rückgängig gemacht werden. Keine Rückerstattung." | "Cette action est irréversible. Aucun remboursement." | ~60 EN / 70 DE / 54 FR |
| Confirm Demolish | "Confirm Demolish" | "Abreißen bestätigen" | "Confirmer la démolition" | ~16 EN / 21 DE / 28 FR |
| Cancel | "Cancel" | "Abbrechen" | "Annuler" | ~6 EN / 10 DE / 8 FR |
| Carrier (input) | "Carrier (in): [Name]" | "Träger (ein): [Name]" | "Transporteur (entrée): [Name]" | ~22 EN / 22 DE / 32 FR |
| Carrier (output) | "Carrier (out): [Name]" | "Träger (aus): [Name]" | "Transporteur (sortie): [Name]" | ~23 EN / 22 DE / 32 FR |
| No carrier (inputs) | "No carrier assigned (inputs)" | "Kein Träger zugewiesen (Eingänge)" | "Aucun transporteur attribué (entrées)" | ~30 EN / 36 DE / 38 FR |
| No carrier (outputs) | "No carrier assigned (outputs)" | "Kein Träger zugewiesen (Ausgänge)" | "Aucun transporteur attribué (sorties)" | ~31 EN / 36 DE / 39 FR |
| Manage Transport link | "Manage Transport →" | "Transport verwalten →" | "Gérer le transport →" | ~19 EN / 22 DE / 21 FR |
| State: No carrier | "Blocked — No carrier assigned" | "Blockiert — Kein Träger zugewiesen" | "Bloqué — Aucun transporteur attribué" | ~30 EN / 37 DE / 38 FR |

**HIGH PRIORITY for localization:**
- **Demolish confirm dialog warning** — English is 60 chars, German is 70 chars. This is the longest text in the panel. The dialog container must auto-size or wrap.
- **Distance line** — "tiles" expands to "Kacheln" (8 chars) in German. Combined with the full line, this is layout-critical — the line may overflow if tool charge is also shown. Panel width must accommodate 40% text expansion.
- **Confirm Demolish button** — "Confirmer la démolition" (28 chars) in French may exceed the button's default width. Button label area should be flexible or truncate with ellipsis.
- **No carrier lines** — French expands to ~38–39 chars per line. The transport zone shows two such lines stacked — combined height must not push the panel below the viewport on small screens (800×600).

---

## Acceptance Criteria

- [ ] Building detail panel opens within 100ms of clicking a building tile
- [ ] Panel layout is functional at 800x600, 1920x1080, and 3440x1440 (21:9)
- [ ] All interactive buttons are reachable via keyboard (Tab cycling) and gamepad (D-pad/analog stick)
- [ ] Constructing state shows progress bar with correct tick count and percentage
- [ ] Producing state shows input → output, tool charge, distance, and assigned NPC name
- [ ] Blocked state shows specific reason ("No NPC assigned", "Missing resource", "Insufficient charge")
- [ ] Stalled state shows "No output carrier" or "Output buffer full" with red dot indicator
- [ ] "Assign NPC" button opens NPC selection list; selecting an NPC assigns and updates panel
- [ ] "Release NPC" button removes NPC assignment and updates panel to BLOCKED state
- [ ] Demolish icon button opens confirmation dialog; confirming destroys building, canceling keeps it
- [ ] Transport section shows carrier name(s) when assigned; shows "No carrier assigned (inputs/outputs)" in yellow when missing
- [ ] "Manage Transport →" link opens the Transportation UI overlay
- [ ] Transport section is hidden for residential/storage-only buildings with no production inputs/outputs
- [ ] All state indicators are distinguishable without color (text label + dot shape + color)
- [ ] All text meets WCAG AA contrast ratio against panel background
- [ ] When reduced-motion setting is enabled, all panel transitions are instant
- [ ] Panel is centered on screen regardless of building position
- [ ] Panel closes automatically when building is demolished

---

## Open Questions

1. **Panel width** — The panel must fit production info lines (tool charge + distance) without wrapping on a 1920×1080 viewport. Exact pixel width TBD during implementation.
2. ~~**Panel position**~~ — RESOLVED: Panel is centered on screen, not anchored to building. This avoids edge-of-screen repositioning issues and keeps layout consistent regardless of building location on the map. *(Intentional deviation from GDD UI-3 wording which says "adjacent to the clicked building" — centering was chosen to eliminate off-screen edge cases.)*
3. ~~**NPC Selection List source**~~ — RESOLVED: NPC Selection List shows only unassigned NPCs. Assigned NPCs are already working and cannot be reassigned through this list — the player must first release them from their current building.
4. ~~**Demolish icon**~~ — RESOLVED: Crossed-out building icon for the demolish button (top-right corner). Clearest semantic match but requires a dedicated asset.
5. **Panel height on 800×600** — Adding Zone 5 (transport section) increases panel height by ~3 text rows. On 800×600, this may push the panel close to the viewport edge. TBD during implementation whether the panel scrolls or the transport section collapses into a disclosure widget.
6. ~~**Transportation UI spec**~~ — RESOLVED: The "Manage Transport →" link is a primary action in the panel, not a placeholder. Engineering should implement it as a navigation signal (`transport_management_opened`) that opens the target overlay. If `design/ux/transportation.md` does not exist at implementation time, the link fires the event but no overlay appears — the link itself must remain visible and enabled (it is a designed feature, not a "coming soon" placeholder). Once the transport spec exists and is approved, the overlay wires up. This prevents the link from becoming dead UI while the transport spec is still in design.
7. **"Blocked — No carrier" state split** — RESOLVED: The single "Blocked — No carrier" row from the initial draft was split into "Blocked — No input carrier" (yellow dot) and "Blocked — No output carrier" (yellow dot) to distinguish input vs. output carrier states. The "Stalled" state (red dot) covers the case where output carrier is missing AND production completed (output buffer full). This is consistent with the GDD's BLOCKED vs. STALLED distinction.

