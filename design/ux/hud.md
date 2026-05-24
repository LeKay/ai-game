# HUD Design

> **Status**: In Design
> **Author**: user + ux-designer
> **Last Updated**: 2026-05-15
> **Template**: HUD Design

---

## HUD Philosophy

The HUD is information-dense: all decision-relevant data is always visible through efficient placement at screen edges and corners. The player is managing a complex system — energy levels, hunger, production chains, storage — and every second spent toggling menus is a second not spent building. The HUD respects the game world's atmosphere by confining all text and data display to the periphery, keeping the center of screen unobstructed for the pixel art diorama.

**Design constraint:** No HUD element may occupy the center 60% of the horizontal axis or the center 40% of the vertical axis. All information lives in corners and edges.

---

## Information Architecture

### Full Information Inventory

The following items were pulled from GDD UI Requirements across all 11 game systems (tick-system, resource-system, input-system, grid-map-system, inventory-storage-system, player-character-system, building-system, npc-system, hunger-system, recipe-database, camera-system):

| System | Item | Category | Notes |
|--------|------|----------|-------|
| Tick | Day counter (time remaining) | Must Show | Top band |
| Tick | Tick speed (0.5/1/2) + play/pause | Must Show | Top band |
| Player | Energy bar | Must Show | Top band |
| Player | In-transit counter | Must Show | Top band — small badge showing "1" when player carries item in transit; disappears when transport completes |
| NPC | NPC count | Must Show | Top band |
| Resource | Resource warning icons (2-tier) | Must Show | Warning < 3 days / Alert < today + tooltip |
| Inventory | Storage capacity (collapsed) | Must Show | Edge panel — total used/total capacity always visible |
| Inventory | Full resource breakdown | Contextual | Edge panel — expands to show individual resource counts |
| Building | Production chain warnings | Contextual | Missing input / missing NPC / full output |
| Building | NPC hunger alert icon | Contextual | Floating icon above NPC's house when hungry |
| Building | Placement ghost | Contextual | Build mode only |
| Building | Construction preview | Contextual | Building under construction |
| Building | Building detail view | On Demand | NPC assignment, input, output — shows when building selected |
| Hunger | Food status indicator | Must Show | "X days remaining" or "⚠️ Low food" — top band (Element 4b) |
| Hunger | Debuff indicator | Contextual | "HUNGRY — actions slowed" below energy bar (Element 4c) |

### Categorization

**Must Show (always visible):**
- Day counter, tick speed + play/pause, energy bar, in-transit counter, food status indicator, NPC count, resource warning icons, storage capacity (collapsed)
- These items are required for the player's core management loop — every tick, every decision about energy management, and every resource warning affects gameplay immediately

**Contextual (shown when relevant):**
- Full resource breakdown (panel expand state), production chain warnings, NPC hunger alert icons, building placement ghost, construction preview
- These appear based on game state — the player doesn't need resource detail unless they're checking, but production warnings must be visible because they require immediate action

**On Demand (player-queried):**
- Building detail view (NPC assignment, input, output)
- Shown only when the player explicitly selects a building — this is a deliberate choice to avoid cluttering the HUD with per-building data

**Screen-space vs World-space:**
- Screen-space (fixed): day counter, tick speed, energy bar, NPC count, resource warning icons, storage panel — anchored to screen edges
- World-space (camera-following): NPC hunger alert icons, building placement ghost, construction preview, building detail view — rendered relative to the camera view

---

## Layout Zones

### Zone 1 — Top Band (full width)
Fixed horizontal strip at the top of the screen. Contains:
- Day counter (left-aligned)
- Tick speed + play/pause buttons (left-center)
- NPC count (right of tick controls)
- Energy bar (right-aligned, horizontal fill bar)

### Zone 2 — Gameplay View
Unobstructed area below the top band. The center 60% horizontal and 40% vertical must never contain HUD elements. All world-space HUD icons (NPC hunger alerts, building production warnings, construction previews) render over this area with camera-relative positioning.

### Zone 3 — Storage Panel (top-right, beneath top band)
Collapsible panel anchored to the top-right corner. Collapsed state shows storage capacity (used/total). Expands downward when toggled to reveal individual resource counts. Maximum expansion height: 300px.

### Zone 4 — Toast/Alert Area (bottom-right corner)
Transient notification zone. Toast messages (resource warnings, building completion alerts) appear here and auto-dismiss after 3 seconds. Does not have permanent content. Stacks up to 3 simultaneous toasts vertically.

**Screen-space vs World-space:**
- Screen-space (fixed): top band, storage panel — anchored to screen edges
- World-space (camera-following): NPC hunger alert icons, building production warnings, placement ghost, construction preview — rendered relative to camera view

---

## HUD Elements

### Element 1: Day Display
- **Category:** Must Show
- **Content:** Day number ("Day 12") + tick progress bar (fills 0→1000, resets on day transition)
- **Visual:** Day number: Silkscreen 16px, `#F0EDE6`. Progress bar: horizontal fill, background `#3A3A3A`, fill `#D4A85C` (golden). Height: 24px.
- **Update:** Progress bar subscribes to `ticks_advanced` event from Tick System — fills incrementally
- **Position:** Day number on left, progress bar immediately adjacent

### Element 2: Tick Speed + Play/Pause
- **Category:** Must Show
- **Content:** Current speed (0.5x/1x/2x) + play/pause toggle
- **Visual:** Three-state speed indicator. Play/Pause button: sharp rectangle, `#5A5A5A` fill, `#A8A49C` text. Hover: `#4A7EA8` fill. Active speed highlighted.
- **Interaction:** Click to cycle speeds (0.5x → 1x → 2x → 0.5x). Play/Pause toggles RUNNING ↔ PAUSED.
- **Update:** Instant on input; subscribed to `speed_changed` and `pause_state_changed` events from Tick System

### Element 3: NPC Count
- **Category:** Must Show
- **Content:** Active NPC count ("3/5 NPCs")
- **Visual:** Text label + number, Silkscreen 16px, `#F0EDE6`
- **Update:** On NPC state change (spawn, die, idle, working)

### Element 4: Energy Bar
- **Category:** Must Show
- **Content:** Player energy / max energy (horizontal fill bar)
- **Visual:** Background `#3A3A3A`. Fill thresholds: green `#4CAF50` (50–100%), yellow `#FFC107` (30–49%), orange `#FF9800` (10–29%), red `#E05555` (0–9%). Border `#5A5A5A`. Height: 24px. Color transitions use 300ms ease-out animation.
- **Colorblind-safe encoding:** In addition to color, a pattern overlay encodes urgency:
  - **>50%:** solid fill (no pattern)
  - **15–50%:** diagonal hatch lines overlaid on fill
  - **<15%:** crosshatch pattern overlaid on fill
  - **0%:** pulsing X pattern (same as depleted state, combined with skull icon)
- **Depleted state (0 energy):** Bar is solid red with pulsing X pattern (2Hz). Adjacent skull icon (24×24px, flat-shaded) + text "DEPLETED" in `#E05555`.
- **Interaction:** Hover tooltip shows: "~X actions remaining until 50% threshold", "~Y actions until empty at current consumption rate"
- **Update:** Signal-driven — subscribes to `energy_changed(current, max)` from PlayerCharacter system (no polling)
- **Position:** Right-aligned in top band, Row 2
- **GDD cross-reference:** Visual treatment (icon style, tooltip, audio) defined in `design/gdd/hud-system.md` Visual/Audio Requirements → Energy Bar section.

### Element 4b: Food Status Indicator
- **Category:** Must Show
- **Content:** Days of food remaining ("Food: 3 days") or depletion warning ("⚠️ Low food" when ≤ 1 day). Displays computed value from Hunger System Formula 4 (`days_of_food_remaining`). When 0 NPCs exist, shows "Unlimited".
- **Visual:** Text label, Silkscreen 14px, `#A8A49C`. Warning state (≤ 1 day) switches to `#D4A85C` with warning icon. "Unlimited" displayed when npc_count == 0.
- **Update:** Subscribes to `hunger_state(fed, food_available, food_required)` from Hunger System — updates on day transition and when food is manually consumed/deposited.
- **Position:** Between NPC count and food warning icons in top band, left of energy bar.
- **Data source:** Hunger System (Formula 4: `days_of_food_remaining`). Owner: Hunger System.

### Element 4c: Hunger Debuff Indicator
- **Category:** Contextual
- **Content:** "HUNGRY — actions slowed (2× tick cost)" shown when village is in HUNGRY state. Disappears when village returns to FED state.
- **Visual:** Small icon + text, 14px. Icon: red `#E05555` ⚠ shape. Text: `#E05555`, Silkscreen 14px. Positioned below energy bar in top band (secondary information, not at primary eye level).
- **Update:** Subscribes to `hunger_state(fed, food_available, food_required)` from Hunger System. Appears on HUNGRY → FED transition; disappears on FED → HUNGRY transition.
- **Position:** Below energy bar in top band.
- **Data source:** Hunger System state machine. Owner: Hunger System.

### Element 5: Storage Panel (Collapsed State)
- **Category:** Must Show
- **Content:** Total capacity ("Used: 4/12")
- **Visual:** Compact text line, Silkscreen 14px, `#A8A49C`. Panel: `#1a1a1a` at 85% opacity, border `#5A5A5A` (1px). Min height: 48px.
- **Interaction:** Click to expand
- **Position:** Top-right, beneath top band

### Element 6: Storage Panel (Expanded State)
- **Category:** Contextual
- **Content:** Per-resource counts (icon + label + count per row). Scrollable on overflow.
- **Visual:** Vertical list, Silkscreen 14px. Max expanded height: 300px. When resource count exceeds visible area, a vertical scrollbar appears. No sorting or filtering — all registered resource types are shown in the order defined by the Resource System.
- **Interaction:** Click toggle button to collapse; click outside or press Escape to collapse. Scroll wheel / trackpad scroll within the panel area.
- **Position:** Expands downward from collapsed position

### Element 7: Resource Warning Icons
- **Category:** Must Show
- **Content:** Icon when critical resource is at risk
- **Tiers:**
  - **Warning** (yellow `#D4A85C`): Resource will run out within 3 days
  - **Alert** (red `#E05555`): Resource will run out today
- **Visual:** 24×24px icon. Hover tooltip: which resource + remaining duration.
- **Update:** Event-driven — subscribed to resource projection calculations from Resource System
- **Position:** Between NPC count and storage panel in top band

### Element 8: NPC Hunger Alert Icon
- **Category:** Contextual
- **Content:** Floating icon above NPC's house when hungry
- **Visual:** 24×24px icon, world-space positioned above house tile. Scales with camera distance.
- **Update:** Event-driven — subscribed to `hunger_state_changed` from Hunger System
- **Position:** World-space — moves with camera

### Element 9: Production Chain Warning Icons
- **Category:** Contextual
- **Content:** Icon near building when production chain is broken
- **Tiers:**
  - **Missing input** (yellow): Building can't produce (no resources delivered to input buffer)
  - **Missing NPC** (blue): No NPC assigned
  - **No carrier** (purple): No input carrier or output carrier assigned — building cannot receive inputs or dispatch outputs
  - **Full output buffer / no carrier collecting** (orange): Output produced but carrier not collecting
- **Visual:** 24×24px icon, world-space above building tile. Resolution details visible in Building Detail View (no tooltip).
- **Update:** Event-driven — subscribed to `production_state_changed` and `building_stalled` / `building_blocked` from Building System
- **Position:** World-space — above building tile

### Element 10: Building Info Panel
- **Category:** On Demand
- **Content:** NPC assignment, input slots, output slots — shown when a placed building is selected on the map
- **Visual:** Panel: `#1a1a1a` at 85% opacity. Sections: header (building name), NPC section, input section, output section.
- **Interaction:** Click empty space or Escape to dismiss. Re-select building to update content.
- **Position:** Right-side fixed panel
- **Max size:** 300px width, auto height

### Element 5b: In-transit Counter
- **Category:** Must Show
- **Content:** Badge showing "1" when player carries an item in transit (carrying between source and destination). Disappears when transport completes.
- **Visual:** Small numeric badge, Silkscreen 12px, `#F0EDE6`, rendered as a floating badge above the storage quick-access icon (Element 6). No background — just the number.
- **Update:** On `item_in_transit_changed(active: bool, count: int)` from Inventory/Storage System. When `active` is false, the badge is hidden entirely (zero screen space).
- **Position:** Above the storage quick-access icon (top-right, same anchor column)
- **GDD cross-reference:** Defined in `design/gdd/hud-system.md` Section C, row 6 — listed as "Must Show" in the top info band.

### Notification Tray (Architecture Note — GDD OQ6)

The GDD (OQ6) mandates a consolidated **Notification Tray** before MVP: all alert types (storage full, NPC hungry, tool broken, building BLOCKED) must route through one consolidated panel to prevent cognitive overload from 7+ concurrent information sinks. This is **REQUIRED before MVP** but **deferred from Vertical Slice scope** because the VS has no alert-generating mechanics yet beyond the resource warning icons.

- **Architecture decision**: The Toast/Alert system (Element 11) must be designed as the entry point into a Notification Tray — not as a free-floating toast stack. This means toasts should be addressable by alert type/category so the tray can later consolidate them.
- **VS implementation**: Element 11 currently implements a simple FIFO stack in the bottom-right corner. This is accepted for VS because: (1) no multi-source alert convergence exists at VS scope, (2) the bottom-right position is consistent with where a tray would anchor, and (3) the FIFO eviction pattern is the tray's core behavior. The spec for Element 11 is written to be a compatible subset of the full tray.
- **MVP migration path**: When OQ6 is implemented, Element 11's free-floating toasts become items within a tray panel. The bottom-right anchor, 3-second auto-dismiss, and FIFO eviction remain unchanged — only the container changes from "floating stack" to "panel with header."

### Element 11: Toast/Alert Notifications
- **Category:** Contextual
- **Content:** Transient messages (resource warnings, building completion, NPC events)
- **Visual:** 4px corner radius, `#1a1a1a` at 90% opacity. Text `#F0EDE6`, Silkscreen 14px. Color-coded: yellow=warning, red=alert, green=success.
- **Behavior:** Appears bottom-right, auto-dismisses after 3 seconds. Stacks up to 3 vertically. When a 4th toast arrives, the oldest toast is evicted (FIFO eviction, no queuing). The new toast pushes existing toasts up.
- **Update:** Event-driven (new toast = new event)
- **Position:** Bottom-right corner

### Element 12: Building Placement Ghost
- **Category:** Contextual
- **Content:** Semi-transparent building preview on hovered tile
- **Visual:** Building silhouette at 60% opacity. Green tint = valid placement, red tint = invalid (conflict, missing resources).
- **Update:** Every frame during build mode (follows cursor/crosshair)
- **Position:** World-space — follows camera + cursor

### Element 13: Construction Preview
- **Category:** Contextual
- **Content:** Semi-transparent building under construction with progress bar
- **Visual:** Building silhouette at 50% opacity, progress bar beneath showing completion percentage.
- **Update:** Event-driven — updates on construction progress change
- **Position:** World-space — fixed above construction tile

### Element 14: Building Placement Menu
- **Category:** Contextual
- **Content:** List of buildable building types — icon, name, resource cost per entry. Only shows buildings currently available (researched/unlocked). Buildings not yet researched are hidden entirely — no "Not Available" placeholder shown. Availability is driven by the Building System (depends on Building System GDD for unlock mechanics).
- **Visual:** Panel: `#1a1a1a` at 85% opacity. Each entry: building icon + name + cost line (e.g., "Lumber Mill — Wood: 5, Stone: 2"). When no buildings are available, shows "No buildings available" centered text.
- **Interaction:** Click building type → placement ghost appears on map. Click different type to switch selection. Escape/click toggle to close
- **Position:** Right-side below top band

### Element 15: Buildings Toggle Button
- **Category:** Must Show
- **Content:** "Buildings" button
- **Visual:** Sharp rectangle, `#5A5A5A` fill, `#A8A49C` text, Silkscreen 16px. Hover: `#4A7EA8` fill. Active: `#F0EDE6` fill, `#3A3A3A` text.
- **Interaction:** Click toggles Building Placement Menu open/closed
- **Position:** Bottom-left corner

---

## Dynamic Behaviors

### 1. Build Mode Activation
- **Trigger:** Player enters build mode via placement action
- **What Changes:** Building Placement Ghost (Element 12) becomes visible, follows cursor. Construction Preview (Element 13) appears on tiles where buildings are under construction. All other HUD elements remain unchanged.
- **HUD Density:** +1 persistent element (placement ghost), +N transient elements (construction previews)

### 2. Storage Panel Expand/Collapse
- **Trigger:** Player clicks toggle button on storage panel
- **What Changes:** Panel expands downward (collapsed → expanded) revealing per-resource counts. Max height: 300px with scrollbar. Collapse returns to compact "Used: X/Y" state.
- **HUD Density:** Expanding adds up to 10 resource rows. Collapsing removes them.
- **Animation:** Slide transition, 200ms, ease-out

### 3. Building Detail View Appearance
- **Trigger:** Player selects a building
- **What Changes:** Building Detail View (Element 10) appears right-side panel with NPC assignment, input slots, output slots. The selected building's Production Warning Icon (Element 9) is hidden while its detail view is open (no duplication).
- **HUD Density:** +1 persistent panel (300px wide right-side overlay)
- **Dismiss:** Click empty space or press Escape → panel closes, production warning icon reappears if still active

### 4. Resource Warning Escalation
- **Trigger:** Resource projection calculation detects depletion within threshold
- **What Changes:**
  - **Plenty → Warning** (resource runs out within 3 days): Resource warning icon appears in top band, toast notification fires ("Resource running low: [name]")
  - **Warning → Alert** (resource runs out today): Icon color changes to red, toast fires ("Critical: [name] depletion today")
  - **Alert → Warning** (player restocked): Icon changes back to yellow, success toast ("Resource restocked: [name]")
  - **Warning → Plenty** (sufficient buffer restored): Icon disappears
- **HUD Density:** +1-3 warning icons in top band (one per critical resource)

### 5. NPC Hunger Alert Transitions
- **Trigger:** NPC hunger crosses into hungry state
- **What Changes:** NPC Hunger Alert Icon (Element 8) appears above NPC's house. Disappears when NPC is fed.
- **HUD Density:** +1 icon per hungry NPC (world-space, scales with camera distance)

### 6. Production Chain State Changes
- **Trigger:** Building production state changes (input received, NPC assigned, storage full, output consumed)
- **What Changes:** Production Warning Icon (Element 9) appears/disappears/changes color based on chain state. Building Detail View (Element 10) auto-updates to show new chain state when selected.
- **HUD Density:** +1 icon per affected building (world-space, camera-following)

### 7. Day Transition
- **Trigger:** `tick_count` reaches 1000
- **What Changes:** Progress bar (Element 1) fills to 100%, day number increments, Tick System fires `day_transition(1)`, game enters PAUSED state, Day Overview modal appears (separate system). All HUD elements remain visible during the transition.
- **HUD Density:** No change — Day Overview modal is a separate overlay system

### 8. Energy Depletion States
- **Trigger:** `energy_changed` signal from PlayerCharacter system crosses thresholds
- **What Changes:** Energy bar (Element 4) fill color transitions: green (>50%) → yellow (30-49%) → orange (10-29%) → red (0-9%). Each threshold crossing fires a 300ms ease-out color transition.
- **HUD Density:** No change — color only, no new elements
- **Animation:** Color transition, 300ms, ease-out

---

## HUD States by Gameplay Context

Specifies which elements hide, show, or change behavior in each gameplay context. The HUD always remains visible — no elements fully disappear — but contextual elements appear/disappear based on state.

### Context 1: Exploration (normal gameplay)
- **Elements visible:** All Must Show elements (top band + storage panel)
- **Contextual elements active:** Production warnings, NPC hunger alerts, resource warnings as triggered
- **Overlays:** None
- **HUD Density:** Baseline — 6 Must Show elements + 0-5 contextual icons

### Context 2: Game Paused (non-day-transition)
- **Trigger:** Player presses Escape or Pause button
- **Elements visible:** All Must Show elements remain visible and unchanged
- **Contextual elements active:** All active contextual elements remain visible
- **Overlays:** Pause overlay (separate system) — semi-transparent dim over game view, HUD unaffected
- **Changes from exploration:** No HUD element changes. Top band controls (tick speed, play/pause) remain interactive — player can resume without dismissing HUD.
- **HUD Density:** Same as exploration + pause overlay (non-HUD element)

### Context 3: Day Transition
- **Trigger:** `tick_count` reaches 1000 (see Dynamic Behavior #7)
- **Elements visible:** All Must Show elements remain visible. Progress bar (Element 1) fills to 100%.
- **Contextual elements active:** Food status (Element 4b) recalculates if consumption changed food days. Debuff indicator (Element 4c) appears/disappears based on consumption result.
- **Overlays:** Day Overview modal (separate system) — blocks interaction with game view but HUD remains fully visible above modal.
- **HUD Density:** No change from baseline exploration

### Context 4: Dialogue / Cutscene
- **Trigger:** NPC interaction or scripted event (separate system)
- **Elements visible:** All Must Show elements remain visible in top band and storage panel.
- **Contextual elements hidden:** All world-space elements (NPC hunger alerts, production warnings, placement ghost, construction preview) are hidden to prevent visual clutter behind dialogue box.
- **Overlays:** Dialogue text box (lower portion of screen, separate system)
- **Changes from exploration:** Only world-space HUD elements hidden. Screen-space elements (top band, storage panel, toasts) unaffected.
- **HUD Density:** -4 world-space elements (simpler visual state)

### Context 5: Inventory Modal Open
- **Trigger:** Player opens inventory (separate screen/overlay system)
- **Elements visible:** Top band elements (day counter, tick speed, play/pause, NPC count, energy bar, food status) remain visible. Storage panel collapses to hidden state (redundant with inventory modal content).
- **Contextual elements active:** Production warnings and NPC hunger alerts remain visible (world-space, still relevant during inventory management).
- **Overlays:** Inventory modal (full-screen or large overlay, separate system)
- **Changes from exploration:** Storage panel hidden. Toast notifications suspended (no new toasts queued while inventory is open).
- **HUD Density:** -1 persistent element (storage panel collapsed)

### Context 6: Settings Menu
- **Trigger:** Player opens settings (separate system)
- **Elements visible:** All Must Show elements remain visible. Settings menu is an overlay that does not obscure the top band.
- **Contextual elements active:** All active contextual elements remain visible.
- **Overlays:** Settings panel (right-side overlay, max 300px wide, below top band)
- **Changes from exploration:** None — settings panel sits alongside existing HUD.
- **HUD Density:** Same as exploration + settings panel overlay (non-HUD element)

### Context 7: Build Mode
- **Trigger:** Player enters build mode (see Dynamic Behavior #1)
- **Elements visible:** All Must Show elements + Building Placement Menu (Element 14) opens on right side.
- **Contextual elements active:** Placement ghost (Element 12) visible, construction previews (Element 13) visible on active builds.
- **Changes from exploration:** Storage panel hidden (redundant — player is looking at buildings, not resources).
- **HUD Density:** +1 panel (Element 14, right-side) + 1 ghost + N construction previews. -1 persistent (storage panel).

---

## Platform & Input Variants

### Input Mappings

| Element | Mouse (Primary) | Gamepad (Partial) |
|---------|-----------------|-------------------|
| Tick speed buttons | Click to cycle speeds | D-pad focus + A to activate |
| Play/Pause button | Click | D-pad focus + A to activate |
| Storage panel toggle | Click | D-pad focus + A to toggle |
| Building selection | Click tile | Crosshair on tile + A |
| Building detail view dismiss | Click empty space or Escape | B/back button |
| Toast notifications | Auto-dismiss (no input) | Auto-dismiss (no input) |

**Gamepad focus order** (top band, left to right): Tick speed → Play/Pause → Storage panel toggle.

### Build Mode Cursor
- **Mouse:** Cursor follows placement ghost at pointer position
- **Gamepad:** Crosshair cursor moves with D-pad/stick, placement ghost renders at crosshair position

### Resolution & Aspect Ratio
- PC desktop only — no console/mobile considerations
- HUD anchored to screen edges; top band fixed at 64px height
- Bottom-right toast zone avoids the bottom 120px
- Works on 1080p and wider aspect ratios (no HUD elements near screen left/right edges)

### Density Variants
- No runtime density switching (unlike adaptive HUDs). The HUD maintains consistent information density across all gameplay states
- Contextual elements (placement ghost, construction preview, production warnings, NPC hunger alerts) add temporary density during specific actions but do not require permanent screen space

---

## Top Band Height
- Fixed at **64px** (2 rows of 32px each) on all supported resolutions
- Row 1 (top 32px): day counter + tick progress bar + tick speed + play/pause + NPC count
- Row 2 (bottom 32px): food status + debuff indicator + resource warnings + energy bar
- At 1920×1080 this occupies 3.3% of screen height
- Supersedes the 48px value in `design/gdd/hud-system.md` Visual Style section — the HUD Design is the authoritative specification for pixel-level layout

## Pattern Library References

| Element | Pattern | Library Reference | Status |
|---------|---------|-------------------|--------|
| Storage panel toggle (Element 5/6) | Click to expand/collapse | Interaction: click-toggle-panel | New — flag for library |
| Building detail dismiss (Element 10) | Escape to dismiss, click outside to dismiss | Interaction: escape-dismiss + backdrop-dismiss | New — flag for library |
| Toast auto-dismiss (Element 11) | Transient, auto-dismiss after duration | Interaction: toast-transient | New — flag for library |
| Build menu toggle (Element 14/15) | Click to open/close | Interaction: click-toggle-panel | Same as storage toggle |
| Tab focus cycling | Tab order through top band | Pattern: keyboard-focus-ring | Standard pattern |
| Escape dismiss (Element 10) | Escape closes building detail | Interaction: escape-dismiss | Same as building detail dismiss |
| Hover tooltip (Element 16) | Cursor-following, 250ms delay | Interaction: hover-tooltip-tiered | New — flag for library |
| Click-to-select building (Element 10) | Click tile → select → show detail | Interaction: click-select-detail | New — flag for library |

## Accessibility
- **Keyboard navigation:** Tab cycles through focusable HUD elements in top band order: Tick Speed → Play/Pause → Storage Panel Toggle. Selected element uses `#F0EDE6` fill with `#3A3A3A` text as focus indicator.
- **Color-independent communication:** Warning/alert states use both color AND icon shape/pattern — resource warnings (yellow = ⚠, red = ✕) so colorblind players can distinguish tiers. Production chain warnings (yellow = triangle for missing input, blue = square for missing NPC, orange = diamond for full output).
- **Text contrast:** All HUD text meets WCAG AA (4.5:1) minimum. `#F0EDE6` on `#3A3A3A` ≈ 10:1. Button text `#A8A49C` on `#5A5A5A` ≈ 3.8:1 (acceptable for 16px+ per art bible typography rules).
- **Reduced motion:** All HUD animations (energy bar color transitions 300ms, storage panel slide 200ms) can be disabled via a global reduced-motion setting. When disabled, transitions are instant.
- **Minimum font sizes:** No HUD text below 14px. Day counter and tick controls at 16px. Resource counts and panel text at 14px.
- **Gamepad navigation:** D-pad cycles top band focus in same order as keyboard. A button activates. B/back dismisses building detail view.
- **Tooltips:** Hover tooltips on warning icons are keyboard-focusable (focus on tick speed/play/pause shows tooltip via Enter/Space).

---

## Tuning Knobs

| Knob | Default | Range | Affects | Notes |
|------|---------|-------|---------|-------|
| Energy bar green threshold | 50% | 30-70% | Energy bar (Element 4) | Boundary between green and yellow zones |
| Energy bar yellow threshold | 30% | 20-40% | Energy bar (Element 4) | Boundary between yellow and orange zones |
| Energy bar orange threshold | 10% | 5-20% | Energy bar (Element 4) | Boundary between orange and red zones |
| Energy bar critical threshold | 0% | 0% | Energy bar (Element 4) | Depleted state threshold — always 0% |
| Toast auto-dismiss duration | 3000ms | 1500-6000ms | Toasts (Element 11) | Shorter = risk missing info, longer = blocks other toasts |
| Storage panel scroll speed | system default | 0.5-2.0x | Storage panel (Element 6) | Per-resource lists may exceed 300px height |

---

## Acceptance Criteria

All criteria are independently testable. A QA tester who has not read the design docs should be able to verify pass/fail.

### Layout & Safe Zones

| # | Criterion | Test | Expected |
|---|-----------|------|----------|
| AC-HUD-01 | No HUD element occupies the center 60% horizontal × 40% vertical of the gameplay view at any resolution | Visual inspection at 1920×1080 and 2560×1440 | Zero HUD pixel in safe zone |
| AC-HUD-02 | Top band is exactly 64px height on all supported resolutions | Measure top band at 1920×1080 and 2560×1440 | Height = 64px ± 0px (supersedes HUD GDD 48px value) |
| AC-HUD-03 | All screen-space HUD elements remain anchored to screen edges during window resize | Resize window from 1920×1080 to 1280×720 and back | Elements re-anchor, no clipping or overlap |

### Performance

| # | Criterion | Test | Expected |
|---|-----------|------|----------|
| AC-HUD-04 | HUD frame render time stays under 0.5ms during peak state (all contextual elements visible) | Profile with HUD at full density for 60 frames | Average ≤ 0.5ms, p99 ≤ 1.0ms |
| AC-HUD-05 | Storage panel expand/collapse animation completes within 250ms | Toggle storage panel 10 times, measure frame count | All transitions ≤ 250ms |

### Input & Navigation

| # | criterion | Test | Expected |
|---|-----------|------|----------|
| AC-HUD-06 | Tab key cycles through top band focusable elements in order: Tick Speed → Play/Pause → Storage Panel | Press Tab repeatedly through all elements | Focus order matches specification, no missing elements |
| AC-HUD-07 | D-pad cycles top band in same order as keyboard; A button activates; B/back dismisses building detail view | Gamepad test on all interactive HUD elements | All interactions work, focus indicator visible |
| AC-HUD-08 | Escape key dismisses building detail view and closes building placement menu | Select building → press Escape | Both panels close, production warning icon reappears |

### Visual & Accessibility

| # | criterion | Test | Expected |
|---|-----------|------|----------|
| AC-HUD-09 | All HUD text meets WCAG AA 4.5:1 contrast ratio; buttons at 16px+ may use 3.8:1 with documented tradeoff | Measure with contrast tool (e.g., WebAIM) | Primary text ≥ 10:1, button text = 3.8:1 (documented tradeoff) |
| AC-HUD-10 | Warning and alert states are distinguishable without color (icon shape/pattern differs) | Grayscale screenshot at 100% | Yellow ⚠ (warning) and red ✕ (alert) remain distinguishable |
| AC-HUD-11 | No HUD text renders below 14px minimum font size | Inspect all HUD text elements | Minimum font = 14px |
| AC-HUD-12 | When reduced-motion setting is enabled, all HUD animations (300ms color transitions, 200ms panel slide) are instant | Toggle reduced-motion → observe HUD | Zero animation, all state changes immediate |

### State & Behavior

| # | criterion | Test | Expected |
|---|-----------|------|----------|
| AC-HUD-13 | During dialogue/cutscene, all world-space HUD elements (NPC hunger alerts, production warnings) are hidden | Trigger dialogue → inspect HUD | Zero world-space HUD icons visible |
| AC-HUD-14 | During inventory modal, storage panel is hidden and toast notifications are suspended | Open inventory → trigger toast event | Storage panel hidden, no toast appears |
| AC-HUD-15 | Toast queue drops oldest when 4th toast arrives (no queuing) | Trigger 4 toasts simultaneously within 100ms | Exactly 3 toasts visible; oldest dropped |
| AC-HUD-16 | Build mode: placement ghost follows cursor every frame; storage panel hidden; building placement menu visible | Enter build mode → move cursor | Ghost tracks cursor, storage panel gone, menu open |
| AC-HUD-17 | Food status indicator shows "Unlimited" when NPC count is 0 | Start new game (0 NPCs) → check HUD | Text reads "Unlimited", not a number |
| AC-HUD-18 | Debuff indicator appears within one frame of hunger state change | Feed NPCs while HUNGRY → debuff clears | Indicator disappears immediately |

---

## Visual Budget

| Budget Item | Limit | Current | Status |
|-------------|-------|---------|--------|
| Max simultaneous HUD elements | 20 | 17 (15 elements + in-transit counter + placement ghost + construction preview) | Within budget (15% headroom) |
| Max screen space coverage | < 35% of screen area | ~28% (top band 5.3% + storage panel 8% + building panel 7% + toasts < 2%) | Within budget |
| Max world-space HUD icons simultaneously | 10 | 10 — prioritized: (1) NPC hunger alerts (2) production chain warnings (3) construction previews. When cap exceeded, drop oldest world-space icon first. | Defined with prioritization rule |
| Center safe zone clearance | 100% clear | 100% clear | OK |

**Note:** The 17-element count represents the maximum possible simultaneous HUD elements at VS scope (now including the In-transit counter). In practice, 6-10 elements are visible in typical gameplay (Must Show baseline + 0-4 contextual icons). World-space icons have a hard cap of 10 with prioritization: NPC hunger alerts > production warnings > construction previews.

---

## Localization

| Text Element | Max Characters (EN) | 40% Expansion (DE/FR) | Notes |
|--------------|---------------------|----------------------|-------|
| Day number + "Day" prefix | 12 chars ("Day 99999") | 17 chars | Day number grows with digit count; "Day" = 3 chars, German "Tag" = 3 chars |
| Tick speed labels | 5 chars ("0.5x") | 5 chars | Numeric, no translation needed |
| Storage "Used: X/Y" | 15 chars ("Used: 999/999") | 21 chars | Label "Used:" expands; German "Belegt:" = 7 chars (+1) |
| NPC count | 10 chars ("3/5 NPCs") | 14 chars | "NPCs" may expand to localized plural |
| Food status | 20 chars ("Food: 99 days") | 28 chars | "Food" = 4 chars, German "Nahrung" = 9 chars (+5); "days" → localized |
| Low food warning | 12 chars ("⚠️ Low food") | 17 chars | Icon is non-text |
| Debuff indicator | 35 chars ("HUNGRY — actions slowed (2× tick cost)") | 49 chars | Longest HUD text; German overflow: truncates to 49 chars with ellipsis (e.g., "HUNGER — verlangsamt"). Overflow handling defined in Localization Notes below. |
| Toast messages | 60 chars | 84 chars | Max width constraint on toast panel |
| Building name + cost | 40 chars ("Lumber Mill — Wood: 5, Stone: 2") | 56 chars | Building/resource names localized |
| "No buildings available" | 25 chars | 35 chars | Empty state text |
| "Unlimited" (food) | 9 chars | 13 chars | German "Unbegrenzt" = 12 chars |

**Layout-critical text flagged for 40% expansion:**
- Energy bar label area: reserve for potential long localization
- Food status indicator: fixed-width area; text truncates with ellipsis if needed
- Debuff indicator: overflow handling via ellipsis at 49 chars. If ellipsis is unacceptable, reserve 60 chars minimum. Vertical space is sufficient for potential two-line wrap on very long translations.

---

## Data Requirements

| Element | Displayed Data | Source System | Owner | Update Frequency |
|---------|---------------|---------------|-------|-----------------|
| Day Display | Day number, tick progress (0-1000) | Tick System | Tick System | Every tick |
| Tick Speed | Current speed (0.5/1/2), play/pause state | Tick System | Tick System | On input |
| NPC Count | Active NPC count | NPC System | NPC System | On NPC state change |
| Energy Bar | Current energy, max energy | Player Character System | Player Character System | On energy change |
| Food Status | Days of food remaining | Hunger System | Hunger System | On day transition or food change |
| Debuff Indicator | HUNGRY/FED state | Hunger System | Hunger System | On day transition |
| Storage Capacity | Used/total capacity | Inventory System | Inventory System | On resource change |
| Resource Breakdown | Per-resource counts | Inventory System | Inventory System | On resource change |
| Resource Warnings | Resource depletion state (tier, icon) | Resource System | Resource System | On projection recalculation |
| NPC Hunger Alert | Alert icon position (world tile) | NPC System / Hunger System | NPC System | On hunger state change |
| Production Warning | Chain state (missing input/NPC/full output) | Building System | Building System | On production state change |
| Building Detail | NPC assignment, input/output slots | Building System | Building System | On building selection |
| Placement Ghost | Building silhouette, valid/invalid tint | Building System | Building System | Every frame in build mode |
| Construction Preview | Building silhouette, progress % | Building System | Building System | On construction progress change |
| Toast | Message text, color, timestamp | Multiple systems | HUD System | On event from any system |

---

## Events Fired

| Event | Source System | HUD Subscription | Payload | Affected Elements |
|-------|--------------|------------------|---------|------------------|
| `day_transition(tick_count)` | Tick System | Subscribe | `tick_count: int` | Day Display |
| `speed_changed(speed: float)` | Tick System | Subscribe | `speed: float` | Tick Speed |
| `pause_state_changed(running: bool)` | Tick System | Subscribe | `running: bool` | Play/Pause |
| `energy_changed(current: float, max: float)` | Player Character System | Subscribe | `current: float, max: float` | Energy Bar |
| `hunger_state(fed: bool, food_available: int, food_required: int)` | Hunger System | Subscribe | `fed: bool, food_available: int, food_required: int` | Food Status, Debuff Indicator |
| `npc_count_changed(count: int)` | NPC System | Subscribe | `count: int` | NPC Count |
| `storage_capacity_changed(used: int, total: int)` | Inventory System | Subscribe | `used: int, total: int` | Storage Capacity |
| `resource_count_changed(resource_id: String, quantity: int)` | Inventory System | Subscribe | `resource_id: String, quantity: int` | Storage Panel (expanded), Resource Warnings |
| `resource_depletion_state_changed(resource_id: String, tier: String)` | Resource System | Subscribe | `resource_id: String, tier: String` | Resource Warning Icons |
| `hunger_alert_changed(npc_id: String, hungry: bool)` | NPC System / Hunger System | Subscribe | `npc_id: String, hungry: bool` | NPC Hunger Alert Icon |
| `production_state_changed(building_id: String, state: String)` | Building System | Subscribe | `building_id: String, state: String` | Production Warning Icon |
| `building_selected(building_id: String)` | Input System | Subscribe | `building_id: String` | Building Detail View |
| `building_deselected()` | Input System | Subscribe | none | Building Detail View |
| `build_mode_entered()` | Building System | Subscribe | none | Placement Ghost, Building Placement Menu |
| `build_mode_exited()` | Building System | Subscribe | none | Placement Ghost, Building Placement Menu |
| `construction_progress_changed(building_id: String, progress: float)` | Building System | Subscribe | `building_id: String, progress: float` | Construction Preview |
| `toast_request(level: String, message: String)` | Any system | Subscribe | `level: String, message: String` | Toast |

---

## Null Handling

All HUD elements must degrade gracefully when source data is unavailable. The rule: **display placeholder, never crash, never leave blank space.**

| Element | Null/Unavailable Behavior |
|---------|--------------------------|
| Day Display | N/A — always available (Tick System is foundational) |
| Tick Speed | Show "—" if speed value is invalid; default to 1x |
| NPC Count | Show "—" if NPC System is offline; count is recalculated on reconnect |
| Energy Bar | Show "—/—" if Player Character System is offline |
| Food Status | Show "—" if Hunger System hasn't computed yet |
| Debuff Indicator | Hidden (default state = FED, no indicator to show) |
| Storage Capacity | Show "—/—" if Inventory System is offline |
| Storage Panel (expanded) | Show "No storage available" if no containers exist |
| Resource Warnings | Icon hidden if resource not yet discovered; appears when resource is first acquired |
| NPC Hunger Alert | Icon hidden if NPC hasn't been spawned yet; appears when `hunger_alert_changed` fires with `npc_id` |
| Production Warning | Icon hidden if building state is unknown; appears when `production_state_changed` fires |
| Building Detail View | Panel does not open if building ID is invalid |
| Placement Ghost | Hidden if build mode is inactive or building type is invalid |
| Construction Preview | Hidden if construction data is unavailable |
| Toast | Never shown if toast manager is offline |

## Hover Tooltip System (Element 16)

### Architecture
- **Category:** Contextual (transient, follows cursor)
- **Design:** Single shared `Control` node — never more than one tooltip visible simultaneously. All tooltip rendering is HUD-owned; systems only define the data that goes in.
- **Hover delay:** 250ms before tooltip appears. Prevents flicker during fast cursor movement. If cursor leaves target before 250ms, tooltip is immediately hidden and timer resets.
- **Positioning:** Follows cursor (not anchored to hovered object) to avoid occlusion. If tooltip would render off-screen or overlap HUD elements, repositioned to nearest available screen space (check top → bottom → left → right of cursor in priority order). Always rendered on top of all other HUD controls.
- **Keyboard accessibility:** All hover targets are focusable via Tab; pressing Enter or Space shows the tooltip.

### Tier 1 — Tile Tooltip
- **When to show:** Cursor hovers over a non-building tile ≥250ms
- **Content:** Tile type name, current state, one-line contextual hint (e.g., "Clear Ground — Day 3 of 7 — Click to harvest")
- **Data source:** Grid System → `get_tile_data(x, y)`
- **Visual:** Panel `#1a1a1a` at 90% opacity, 8px corner radius, 8px padding. Border: white (neutral). Max width: 240px. Text: `#F0EDE6`, Silkscreen 12px. Fade-in over 100ms when delay expires. No fade-out — disappears immediately on cursor leave.

### Tier 2 — Building Tooltip
- **When to show:** Cursor hovers over a building ≥250ms
- **Content:** Building name, current output/status (e.g., "Producing: 3/100 ticks"), input resource → output resource, worker count, blocked reason (if applicable)
- **Data source:** Grid System → `get_tile_building(x, y)` → Building System → `get_building_state(building_id)`
- **Visual:** Same panel style. Border color matches context: white (idle), green (producing), amber (blocked/waiting), red (stalled). Density: 4-5 lines.

### Tier 3 — Resource/Storage Tooltip
- **When to show:** Cursor hovers over resource icon, storage quick-access, or storage panel entry ≥250ms
- **Content:** Resource name, current quantity, storage capacity, utilization percentage, production/consumption rate (if applicable)
- **Data source:** Inventory System → `get_total_quantity(id)`, `get_total_capacity()`, utilization ratio from Resource System
- **Visual:** Same panel style. Border: white (neutral). Density: 4-5 lines.

### Null Handling
- **If tile data is unavailable:** Show "—" (placeholder) with no error
- **If building was demolished mid-hover:** No tooltip shown (graceful degradation, see HUD GDD EC-M1)
- **If resource ID is unknown:** Show `[Unknown Resource]` with quantity preserved

### Animation
- **Fade-in:** 100ms (after 250ms hover delay expires)
- **Fade-out:** None — immediate hide on cursor leave or focus loss

## Open Questions

All 5 questions resolved. See element specifications above for decisions.
