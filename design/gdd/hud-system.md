# HUD System

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-05-12
> **Implements Pillar**: Pillar 2 (Information Transparency)

## Overview

The HUD System is the player-facing data layer of From Scratch — the channel through which the simulation's state (resources, time, energy, storage, building status) is communicated to the player. It does not model gameplay; it displays it. Every HUD element is a read-only query against another system: the Tick System for time and speed, the Inventory/Storage System for resources and capacity, the Building System for production states, the Player Character System for energy. The HUD's purpose is Information Transparency (Pillar 2): the player must be able to see, at a glance or on demand, where resources are, which processes are active, which are blocked, and why — without permanent UI clutter that obscures the map.

For the Vertical Slice, the HUD comprises: a resource display (wood, berries, item charge bars), an energy bar, a tick control bar (speed buttons, pause/play, day counter), a building status hover, and a storage quick-access indicator.

## Player Fantasy

The HUD creates the feeling of **instant understanding** — every time the player glances at the top info band, they immediately know the state of their village without reading, without searching, without cognitive friction. The design fantasy is "zero-clutter information": the map stays clear, the eyes naturally scan up and return, and the player always knows the answer to "am I running out of anything?" before they even think to ask.

This maps directly to Pillar 2 (Information Transparency): the HUD doesn't hide complexity behind abstraction — it shows the raw numbers, the progress bars, the status indicators so the player can **debug their own systems**. A Factorio player reads their logistics stats to find a bottleneck; a From Scratch player reads their storage summary to find a food shortage. The feeling is the same: "I see the problem, I know the solution."

The HUD should feel **calm, not urgent** — even at 0 energy, the pulsing skull is a clear signal, not a panic-inducing warning. The color bands are wide (30-point ranges) so the player always knows which zone they're in. No flickering, no flashing numbers, no anxiety — just clean, readable information at a glance.

## Detailed Design

### Core Rules

1. **HUD Architecture — Single CanvasLayer, Read-Only Queries**
   - The HUD is implemented as a single `CanvasLayer` containing a hierarchy of `Control` nodes. All HUD elements (always-visible and modal) live in this one layer.
   - The HUD is **read-only**: it queries game systems but never modifies game state. Each system exposes a public query API; the HUD calls it. Systems do not call HUD methods.
   - Data flow is **hybrid**: signals for event-driven updates (speed change, pause toggle, day transition) and polling for display values (tick counter, energy bar) that change every frame or at the player's discretion.
   - The HUD is loaded as a scene-root node (`hud_root.tscn`) with a static reference getter (`HudManager.get_instance()`). For VS scope this can be an autoload singleton, but **systems must never call HUD methods** — the HUD is a pure display leaf. If a system needs to "flash" the energy bar or "pulse" a resource count, it emits its own signal or changes its state; the HUD observes via signals, never via direct calls. For MVP, replace autoload with scene-loaded root to avoid accidental reverse dependencies.

2. **Information Hierarchy — Unified Top Info Band**
   - All always-visible HUD elements occupy a single compact band across the top edge of the screen, occupying no more than 8-12% of vertical screen space.
   - **Left-to-right reading order:** Day counter + Tick controls (left/center) → Energy bar (right) → Resource display (far right).
   - This creates a predictable scanning path: player glances top → reads → returns gaze to map center. The center map area remains unobstructed (Pillar 2: Information Transparency).

3. **Always-Visible HUD Elements (Vertical Slice)**

   | Element | Screen Position | Data Source | Update Method |
   |---------|----------------|-------------|---------------|
   | Day counter | Top-left | Tick System `get_current_day()` | Poll every frame; animate on `day_transition` signal |
   | Speed buttons (0.5x/1x/2x) | Top-left (next to day) | Tick System `get_speed_multiplier()` | Signal-driven (`speed_changed`) |
   | Pause/Play button | Top-left (next to speed) | Tick System `is_paused()` | Signal-driven (`pause_state_changed`) |
   | Energy bar | Top-right | Player Character System `get_energy_state()` | Poll every frame; color gradient (green/yellow/orange/red); skull icon at 0 |
   | Resource display | Top-right (next to energy) | Inventory System `get_total_quantity(resource_id)` across all containers | Poll every 500ms |
   | In-transit counter | Top-right (next to resources) | Inventory System `get_in_transit_count()` | Poll every frame during active transport |
   | Map-wide storage summary | Top-right (integrated with resources) | Inventory System `get_total_capacity()` across all containers | Poll every 500ms |
   | Transportation button | Top-right (next to storage summary) | Logistics System `get_pending_transport_count()` | Signal-driven (`transport_task_changed`); highlighted (pulsing icon) when pending transport tasks exist; clicking opens the Transportation panel (`design/ux/transportation.md`) |

4. **Hover Tooltip System — HUD-Owned, Three-Tier Architecture**
   - The HUD owns **all** tooltip rendering. Systems only define the data that goes in; the HUD handles rendering.
   - A single shared tooltip `Control` node is shown/hidden/updated. No per-hover node creation.
   - **Hover delay:** 250ms before tooltip appears. Prevents flicker during fast cursor movement.
   - **Three tiers of hover targets:**
     - **Tier 1 — Tile Hover:** Tile type name, current state, one-line contextual hint ("Click to harvest" or "Drag building here"). Density: 2-3 lines.
     - **Tier 2 — Building Hover:** Building name, current output/status (e.g., "Producing: 3/6 ticks"), input resource → output resource, worker count, blocked reason (if applicable). Density: 4-5 lines. Resolved via: Grid System `get_tile_building(tile_x, tile_y)` → Building Registry `get_building_state(building_id)`.
     - **Tier 3 — Resource/Storage Hover:** Resource name, current quantity, storage capacity, utilization percentage, production/consumption rate (if applicable). Density: 4-5 lines.
   - **Tooltip behavior:** Follows the cursor (not anchored to the hovered object) to avoid occlusion. Tooltip position updated every frame while visible.
   - **Keyboard equivalent:** All hover targets are focusable via Tab; pressing Enter or Space shows the tooltip.

5. **Storage Quick-Access — Map-Wide Summary**
   - The storage quick-access element shows a **map-wide summary**: total stored items across all containers vs. total capacity. Format: "📦 42/150".
   - This is NOT per-storage. Individual storage building fill levels are shown only when the player clicks/interacts with that specific storage building.
   - Clicking the storage quick-access element opens the full storage panel (modal overlay), showing all containers, their slots, and per-container breakdowns.

6. **Energy Bar — Triple Encoding**
   - **Color gradient:** Green (70-100) → Yellow (30-69) → Orange (10-29) → Red (0-9).
   - **Numeric readout:** "67/100" displayed inside or beside the bar.
   - **Critical state:** Skull icon + "DEPLETED" text at 0 energy. Pulsing animation.
   - **Hover the energy bar** to show: time until 50% threshold, time until empty at current consumption rate.

7. **Day Transition — HUD Coordinates, Day Overview System Owns Content**
   - When `day_transition` fires, the Tick System auto-pauses the game.
   - The HUD loads the Day Overview modal (owned by the Day Overview System, separate GDD).
   - The HUD does NOT define the day summary content. It handles the visual transition (fade-in/out of the modal overlay) and the resume action (`set_pause(false)` when the player dismisses).

8. **Hover Detection — Tile-Based, Not Area2D**
   - Hover detection uses tile-based resolution via the Grid System, NOT Area2D hit-testing on building nodes.
   - Flow: Mouse position → HUD converts to world coordinates via camera transform → floors to tile index → `GridSystem.get_tile_building(tile_x, tile_y)` → `BuildingRegistry.get_building_state(building_id)` → tooltip data.
   - This avoids physics server overhead for 100+ building nodes.

9. **Modal Overlays**
   - Modals (storage panel, building detail panel) are Control children at the same hierarchy level as always-visible elements.
   - Shown by setting `visible = true` and `mouse_filter = MOUSE_FILTER_STOP`.
   - Hidden by setting `visible = false` and `mouse_filter = MOUSE_FILTER_PASS`.

10. **Localization**
    - All HUD text MUST go through `tr()` (TranslationServer). No hardcoded strings.

### States and Transitions

**HUD View States:**

| State | Description | Trigger |
|-------|-------------|---------|
| **MINIMAL** (default) | Only the top info band is visible. Map is unobstructed. | Initial state, or after dismissing any modal |
| **HOVER** | A single tooltip appears near the cursor (250ms delay). Does not change the MINIMAL layout. | Cursor hovers over a tile, building, or resource for ≥250ms |
| **MODAL_OPEN** | An overlay panel (storage, building detail, transportation) covers the map center. Top info band remains visible. | Player clicks a storage area, building, storage quick-access, or the Transportation button |
| **DAY_TRANSITION** | Day Overview modal fades in over the map. Game is paused. | `day_transition` fires; `day_transition` dismissed by player |

**State Transitions:**

| From | To | Trigger |
|------|-----|---------|
| MINIMAL | HOVER | Cursor hovers target ≥250ms |
| HOVER | MINIMAL | Cursor leaves target |
| MINIMAL | MODAL_OPEN | Player clicks storage quick-access or interactable object |
| MODAL_OPEN | MINIMAL | Player clicks close button, presses Escape, or clicks outside panel |
| MINIMAL | DAY_TRANSITION | Tick System fires `day_transition` (auto-pause) |
| DAY_TRANSITION | MINIMAL | Player dismisses Day Overview modal |
| HOVER | DAY_TRANSITION | Day transition interrupts hover |
| MODAL_OPEN | DAY_TRANSITION | Day transition interrupts modal |

### Interactions with Other Systems

| System | Interaction | Data Flow | Interface |
|--------|-------------|-----------|-----------|
| **Tick System** | Displays day counter, speed buttons, pause state | HUD → Tick: `get_current_day()`, `get_speed_multiplier()`, `is_paused()`. HUD subscribes to `speed_changed`, `pause_state_changed`, `day_transition` | Poll for display; signal for state changes |
| **Player Character System** | Displays energy bar, in-transit count | HUD → PC System: `get_energy_state()` → `{energy, max_energy, state}` | Poll every frame in `_process()` |
| **Inventory/Storage System** | Displays resource totals, storage capacity, in-transit items | HUD → Inventory: `get_total_quantity(id)`, `get_total_capacity()`, `get_in_transit_count()` across all containers | Poll every 500ms (storage changes are infrequent) |
| **Building System** | Building hover tooltips, building status | HUD → Grid: `get_tile_building(x, y)` → Building Registry: `get_building_state(id)` | Poll on mouse move (O(1) lookup) |
| **Grid System** | Tile hover resolution (source of tile data for Tier 1 tooltips) | HUD → Grid: `get_tile_data(x, y)` | Poll on mouse move |
| **Day Overview System** | Coordinates day transition modal display | Day Overview → HUD: "show day modal"; HUD → Tick System: `set_pause(false)` on dismiss | Event-driven, not polled |
| **Building System (storage panels)** | Opening/closing per-storage detail panels | Building → HUD: "open storage panel for container X". HUD queries Inventory for data. | Event-driven on player click |
| **Logistics System** | Displays transportation button state (pending tasks, highlights) | HUD → Logistics: `get_pending_transport_count()`. HUD subscribes to `transport_task_changed` | Signal-driven; button highlighted when `pending > 0` |

**Key Interface Summary:**
- **Query methods (poll by HUD):** `TickSystem.get_current_day()`, `TickSystem.get_speed_multiplier()`, `TickSystem.is_paused()`, `PlayerCharacterSystem.get_energy_state()`, `InventorySystem.get_total_quantity(id)`, `InventorySystem.get_total_capacity()`, `InventorySystem.get_in_transit_count()`, `GridSystem.get_tile_building(x, y)`, `BuildingRegistry.get_building_state(id)`, `LogisticsSystem.get_pending_transport_count()`
- **Signals (subscribed by HUD):** `TickSystem.speed_changed`, `TickSystem.pause_state_changed`, `TickSystem.day_transition`, `LogisticsSystem.transport_task_changed`

## Formulas

**N/A.** The HUD System is a display layer — it queries game systems and renders their data. It performs no gameplay calculations. All formulas (transport cost, tick accumulation, energy consumption, first-fit slot allocation) live in the systems being displayed. The HUD's only computation is derived display math: energy bar percentage (`energy / max_energy × 100`) and tick progress bar percentage (`tick_count / 1000 × 100`) — these are trivial rendering calculations, not gameplay formulas requiring design specification.

## Edge Cases

### HIGH Severity

**EC-H1: HUD Querying a System That Doesn't Exist Yet (Unimplemented System)**

- **Scenario:** The HUD is coded against `PlayerCharacterSystem.get_energy_state()` but the PC System isn't ready or the autoload isn't registered.
- **Handling:** If a system autoload is not registered, the HUD logs a warning to the debug console on first access and renders a placeholder (e.g., "—/—") instead of crashing. The HUD degrades gracefully — missing elements are blank, not broken.

**EC-H2: Rapid Tooltip Flicker During Fast Cursor Movement**

- **Scenario:** Player moves cursor rapidly across the map over multiple buildings. Tooltip would flicker between different building tooltips.
- **Handling:** The 250ms hover delay acts as a filter — the tooltip only appears after sustained hover. Additionally, if the cursor leaves a hover target before the 250ms timer expires, the tooltip is immediately hidden and the timer resets. This prevents tooltip "chasing."

**EC-H3: Tooltip Rendering Behind Map Elements**

- **Scenario:** The tooltip appears near the cursor, but a building sprite or terrain feature blocks the tooltip from being visible.
- **Handling:** The tooltip position is adjusted if it would render off-screen or behind opaque map elements. The tooltip is always rendered on top of all other HUD controls (highest z-index within the CanvasLayer). If the tooltip would be clipped by the viewport edge, it is repositioned to the opposite side of the cursor.

**EC-H4: Tick Count Display Glitch During Day Transition**

- **Scenario:** The tick counter displays "999" one frame, then the day transition fires and it should show "0" — but the frame render vs. day transition ordering causes a brief flash of "1000" or a skipped frame.
- **Handling:** The Tick System resets `tick_count = 0` and fires `day_transition` before the next `_process()` call. The HUD's `day_transition` signal handler forces a day counter update (animate the new day number) and clears the tick counter display simultaneously. No intermediate value is rendered.

### MEDIUM Severity

**EC-M1: Building Registry Query Returns Null (Building Deleted Mid-Hover)**

- **Scenario:** Player is hovering over a building. While the 250ms hover delay is counting down, the building is demolished. At tooltip render time, `get_building_state(building_id)` returns null.
- **Handling:** The tooltip is not shown. No error is logged — this is a normal, expected scenario. The hover state transitions to MINIMAL.

**EC-M2: Multiple Storage Areas — Map-Wide Summary Ambiguity**

- **Scenario:** The HUD shows a map-wide storage summary (e.g., "120/350"). Player assumes this refers to the storage they're standing next to, but it's the total across all storages.
- **Handling:** The storage quick-access tooltip (on hover) explicitly states "All Storage (120/350)" to distinguish it from per-storage views. This ambiguity is an accepted tradeoff for VS scope (only 1 storage area exists).

**EC-M3: Energy Bar Color Threshold Jitter**

- **Scenario:** Energy is at 29 (orange zone). Player performs an action that costs 1 energy → energy = 28. The color hasn't changed yet (still orange). Next action: energy = 27. Still orange. The player can't see the change until 10 more points.
- **Handling:** The color bands are intentionally wide (30-point ranges). This is by design — granular color changes would be distracting. The numeric readout (e.g., "27/100") provides exact value. The color band change at each threshold (70, 30, 10, 0) is dramatic enough to be noticeable.

**EC-M4: Resource Display Staleness During Fast Production**

- **Scenario:** A building produces output every 100 ticks. The HUD polls the Inventory System every 500ms. The player sees resource counts that are up to 500ms behind actual state.
- **Handling:** This is an acceptable tradeoff. Resource counts don't change every frame — they change at production milestones. 500ms polling is sufficient for display purposes. If the player needs exact current values, they can check the full storage panel (which is queried fresh on open).

### LOW Severity

**EC-L1: Tooltip Overlaps With UI Elements**

- **Scenario:** The tooltip appears near the cursor, but the cursor is at the screen edge and the tooltip would overlap with the top info band or other HUD elements.
- **Handling:** The tooltip is repositioned to the nearest available screen space that doesn't overlap HUD elements. The repositioning is deterministic (check top, then bottom, then left, then right of cursor in priority order).

**EC-L2: Localization String Missing**

- **Scenario:** A HUD text string (e.g., "DEPLETED") has no translation entry. `tr()` returns the key itself (e.g., "DEPLETED").
- **Handling:** The missing key is displayed as-is. This is not a crash — Godot's TranslationServer returns the key string if no translation is found. It looks unpolished but does not break functionality. CI/integration should include a missing-string check.

**EC-L3: Multiple `pause_state_changed` Events in Quick Succession**

- **Scenario:** The pause state is toggled multiple times rapidly (e.g., day transition auto-pauses, then player immediately presses Play). The HUD receives two `pause_state_changed` events in rapid succession.
- **Handling:** The HUD's pause button icon is updated on each event. Since `mouse_filter` and visibility of the Day Overview modal are also handled by the same event pipeline, there may be a brief flash of the modal. The modal fade-in/out animation (using `Tween` or `AnimationPlayer`) makes this visually acceptable — the player doesn't perceive a "flash."

**EC-L4: High-DPI / Scaling Display**

- **Scenario:** The game runs at a resolution where the top info band is extremely thin (e.g., 1080p with small font). HUD elements become cramped or overlap.
- **Handling:** The HUD uses anchor-based positioning (not pixel offsets) so elements scale with resolution. The top info band has a minimum height constraint (48px at smallest supported resolution). If the window is resized smaller than this, the HUD is scaled proportionally but never below the minimum. This is a Godot CanvasLayer behavior — no special handling needed.

## Dependencies

### Upstream (HUD System depends on)

| System | Dependency Type | Interface Used | Notes |
|--------|----------------|----------------|-------|
| **Tick System** | Hard — time, speed, pause state | `get_current_day()`, `get_speed_multiplier()`, `is_paused()`, subscribes to `speed_changed`, `pause_state_changed`, `day_transition` | The HUD cannot display time-related information without the Tick System. It is the primary driver of the top info band. |
| **Player Character System** | Hard — energy display | `get_energy_state()` → `{energy, max_energy, state}` | Energy bar is a required VS HUD element. Without the PC System, the HUD cannot render energy. |
| **Inventory/Storage System** | Hard — resource display, storage capacity | `get_total_quantity(id)`, `get_total_capacity()`, `get_in_transit_count()` across all containers | The HUD displays what's stored and what's moving. Without Inventory, the resource display and storage quick-access are empty. |
| **Building System (Registry)** | Soft — building hover tooltips | Grid System `get_tile_building(x, y)` → Building Registry `get_building_state(id)` | Building hover info is a VS element. Without buildings, the hover system has nothing to render, but the HUD itself remains functional. |
| **Grid System** | Soft — tile hover resolution | `get_tile_data(x, y)` | Tile hover tooltips require tile data. Without the Grid System, the HUD has no tile information to display. |
| **Day Overview System** | Soft — day transition modal coordination | Event-driven: Day Overview System signals "show day modal"; HUD calls `set_pause(false)` on dismiss | The Day Overview System is separate but closely coupled. If it doesn't exist, the HUD still shows day counter and tick controls — the day summary modal is deferred. |

### Downstream (systems that depend on HUD)

| System | Dependency Type | Notes |
|--------|----------------|-------|
| **None** | — | The HUD is the leaf of the dependency tree. No gameplay system depends on the HUD for logic. The HUD is a display-only layer. |

### Cross-System Consistency Notes

- **Tick System GDD** lists HUD as a downstream consumer (polls `get_tick_count()`, `get_current_day()`, `get_speed_multiplier()`, `is_paused()`). This is consistent with this GDD's interface definition.
- **Inventory/Storage GDD** lists HUD/UI as a soft downstream dependency (polls `get_storage_contents()`, `get_capacity()`, `get_in_transit_items()`). This GDD simplifies to `get_total_quantity()`, `get_total_capacity()`, `get_in_transit_count()` for VS scope — the full slot-level query API (`get_storage_contents()`) is only needed when the storage modal panel is opened.
- **Building System GDD** defines UI-5 (Hover Tooltip) with its own data format. This HUD GDD takes ownership of **all tooltip rendering** — the Building System provides data via `get_building_state()`, the HUD renders it. No conflicting interfaces.

## Tuning Knobs

| Knob | Default | Safe Range | Effect |
|------|---------|------------|--------|
| **Hover delay** | 250ms | 100 – 500ms | Time cursor must sustain hover before tooltip appears. Lower values make tooltips feel snappy but increase flicker risk. Higher values make tooltips feel sluggish. 250ms is the sweet spot between responsiveness and stability. |
| **Poll interval (resources/capacity)** | 500ms | 200 – 1000ms | How frequently the HUD re-reads resource totals from Inventory. 500ms is sufficient — production cycles are measured in 100+ ticks (10+ seconds), so 500ms polling is responsive enough. Lower values waste CPU on unnecessary queries. |
| **Energy bar color thresholds** | 70/30/10 | 60-80 / 20-40 / 5-15 | Energy level percentages at which the bar changes color. Wide bands are intentional — they prevent jitter and give the player a clear "zone" feeling. Narrow bands create anxiety; wide bands feel relaxed. |
| **Top info band height** | 48px | 36 – 64px | Vertical space the HUD band occupies. Must accommodate icon + label + button elements. 48px is the minimum comfortable height for clickable UI elements on PC. Taller bands are more readable but obscure more of the map. |
| **Storage summary update rate** | 500ms | 200 – 2000ms | Separate from resource poll rate — controls how often the storage capacity indicator updates. Storage capacity changes very rarely (only on building completion or upgrade), so 2000ms would be acceptable. Kept at 500ms to match resource polling for consistency. |
| **Modal fade-in duration** | 200ms | 100 – 500ms | Speed of the fade animation when opening/closing modals (storage panel, day overview). 200ms feels snappy without being jarring. Higher values create a "slow dissolve" that feels premium but may slow perceived responsiveness. |
| **Storage fill color thresholds** | 75% / 90% | 70-80% / 85-95% | Storage utilization percentages at which the fill bar changes color. 90%+ triggers the pulsing icon (EC-M2). These are display-only thresholds — they don't affect gameplay. 75% gives a "nearing capacity" yellow warning; 90% gives "critical — find more storage" red warning. |

### Knob Interdependence

- **Hover delay × screen resolution/refresh rate:** On 120Hz displays, the 250ms hover delay allows ~30 frames of cursor movement before tooltip appears. This is still appropriate — the visual flicker risk is the same regardless of refresh rate.
- **Energy thresholds × color palette:** The numeric boundaries (70/30/10) must align with the visual color gradient. Changing one without the other creates a cognitive mismatch (e.g., threshold at 50% but color change at 60%).

## Visual/Audio Requirements

### Visual Style

The HUD follows the "Functional Clarity" visual identity: every element serves readability and system transparency. The aesthetic is clean and flat — no medieval textures on UI elements. The reference is **Oxygen Not Included**: functional, information-dense, but always readable at a glance. The world assets are pixel art; the UI is flat-shaded icons and pixel-font typography — a deliberate contrast that signals "this is the data layer, not the world."

### Top Info Band

| Element | Visual Treatment |
|---------|-----------------|
| **Background** | Semi-transparent dark overlay (`#1a1a1a` at 85% opacity). No border — the opacity change from the world is sufficient separation. Rounded corners only on the leftmost and rightmost edges (the band stretches edge-to-edge). |
| **Height** | **64px fixed** (2 rows of 32px). Accommodates all Must Show elements in a single band. Supersedes the 48px value previously stated — authoritative source is `design/ux/hud.md`. |
| **Typography** | Pixel font for all text (e.g., "Press Start 2P" or similar — 14px equivalent). Monospace-friendly for numbers. All text is white (`#ffffff`) with a 1px dark outline for readability over any map background. |
| **Icon style** | Flat-shaded 24×24px icons (energy, pause/play, speed buttons). No pixel art treatment — clean geometric shapes, 2-color palette per icon (foreground + outline). |
| **Resource icons** | Flat-shaded 24×24px icons matching the world's resource palette (wood = brown, berries = red, stone = gray). Stack counter displayed as a small white number in the bottom-right corner of the icon, scaled to fit. |

### Energy Bar

| Element | Visual Treatment |
|---------|-----------------|
| **Bar background** | Dark rectangle (`#2a2a2a`), 8px tall, 120px wide (or 15% of screen width, whichever is smaller). |
| **Bar fill** | Solid color fill matching the energy zone (green `#4caf50` / yellow `#ffc107` / orange `#ff9800` / red `#f44336`). |
| **Colorblind-safe encoding** | In addition to color: a subtle pattern overlay. Full energy = solid fill. Below 50% = diagonal hatch lines overlaid on the fill. Below 20% = crosshatch pattern. Below 0% = pulsing X pattern. This ensures urgency is perceivable without color. |
| **Numeric readout** | White pixel font text beside the bar: "67/100". |
| **Depleted state (0 energy)** | Bar is solid red with pulsing X pattern. Next to the bar: skull icon (flat-shaded, 24×24px) + "DEPLETED" text in red (`#f44336`). Pulsing animation at 2Hz. |
| **Hover tooltip** | On hover over the energy bar, a tooltip appears: "~X actions remaining until threshold" and "~Y actions until empty at current rate." |

### Tick Controls

| Element | Visual Treatment |
|---------|-----------------|
| **Speed buttons** | Three small buttons (24×24px each), side by side. Active button: filled background with white text. Inactive buttons: outline-only (transparent fill, white border, white text). |
| **Pause/Play button** | 24×24px icon button. Pause = two vertical bars (││). Play = triangle (▶). Active state = filled background. Inactive = outline-only. |
| **Day counter** | Pixel font text: "Day 12". No icon — the label "Day" is small and muted (`#aaaaaa`), the number is bright white. |
| **Speed change feedback** | When speed changes, the active button pulses briefly (200ms modulate-a flash to white, then back). |

### Storage Quick-Access

| Element | Visual Treatment |
|---------|-----------------|
| **Icon** | Small barrel/storage icon (24×24px, flat-shaded, brown `#8b6914`). |
| **Fill level** | A thin horizontal bar (32px wide, 4px tall) overlaid on the bottom edge of the icon. Bar fill color matches the storage utilization thresholds (green 0-74%, amber 75-89%, red 90-100%). |
| **Capacity text** | Small text next to icon: "42/150". |
| **Hover tooltip** | "All Storage — 42/150 (28%)" — explicitly states it is a map-wide summary. |
| **Critical threshold (90%+)** | Icon pulses at 1Hz (subtle scale animation, ±2%). |

### Hover Tooltips

| Element | Visual Treatment |
|---------|-----------------|
| **Background** | Semi-transparent dark panel (`#1a1a1a`, 90% opacity). Rounded rectangle, 8px corner radius. Padding: 8px all sides. |
| **Border** | 2px solid border. Color matches context: white (neutral tile info), green (active building), amber (building waiting for input), red (building blocked). |
| **Shadow** | Subtle drop shadow (4px offset, 20% black) to separate from map elements. |
| **Typography** | Pixel font, 12px equivalent. Title line bold/brighter. Detail lines standard weight. Text color: white with 1px dark outline. |
| **Max width** | 240px. If text exceeds this, wrap to next line. |
| **Pointer indicator** | Small triangle at the bottom-center of the tooltip pointing toward the cursor position. |
| **Animation** | Fade-in over 100ms when the 250ms hover delay expires. No fade-out animation — tooltip disappears immediately on cursor leave. |

### Modal Overlays (Storage Panel, Day Overview)

| Element | Visual Treatment |
|---------|-----------------|
| **Backdrop** | Semi-transparent dark overlay (`#0a0a0a`, 70% opacity) covering the entire viewport. Blocks clicks to the game world. |
| **Panel** | Centered panel, max-width 800px, max-height 70% viewport height. Background: `#1a1a1a` (same as top band). Border: 2px solid `#444444`. Rounded corners: 12px. Padding: 16px. |
| **Header** | Panel title in pixel font, 18px, white. Right-aligned close button (X icon, 24×24px). |
| **Transition** | Fade-in over 200ms (both backdrop and panel). Panel scales from 95% to 100% width during the animation (subtle "pop in" effect). |
| **Close** | Clicking backdrop, pressing Escape, or clicking the X button triggers fade-out (200ms) then removes both elements. |
| **Storage panel detail** | Grid of slots (same visual treatment as Inventory System's storage panel UI: 32×32px cells, resource icon, quantity counter, stack progress bar). Empty cells dimmed at 30% opacity. |

### Visual Feedback Animations

| Event | Visual Treatment | Frequency |
|-------|-----------------|-----------|
| **Day counter increment** | Day number text pulses (scale 1.0 → 1.1 → 1.0 over 300ms) | Once per day transition |
| **Speed change** | Active speed button flashes white (200ms), then returns to normal | Once per speed change |
| **Pause/Play toggle** | Button icon morphs (play ▶ → pause ││) with a 150ms crossfade | Once per toggle |
| **Storage full warning** | Storage quick-access icon pulses at 1Hz | Continuous until storage drops below 90% |
| **Energy depletion (0)** | Skull icon + "DEPLETED" text pulses at 2Hz | Continuous until energy > 0 |
| **Energy threshold crossing** | Bar color transitions with a 200ms crossfade (not instant) | Per threshold crossing |
| **Building state change (hovered)** | Tooltip border color transitions over 500ms | Per state change (only hovered building) |
| **Transport arrival (deposit)** | Brief white sparkle flash at the storage location on the map | Once per deposit |

### Audio Cues

| Event | Audio | Detail |
|-------|-------|--------|
| **Speed change** | Short click sound (different pitch per speed: lower → higher) | 3 distinct pitches for 0.5x/1x/2x |
| **Pause/Play toggle** | Subtle "tick" on Play (ascending), "tock" on Pause (descending) | Distinguishes Play from Pause without icon reading. ~100ms. |
| **Day transition** | Soft chime or ambient swell | Plays when Day Overview modal fades in |
| **Storage full warning (first crossing of 90%)** | Subtle click (once per session) | Not repeated on every deposit |
| **Energy depletion (crossing into 0)** | Low "wah" (descending tone, ~0.5 sec) | Same sound as transport failure — consistent meaning: something has stopped working |
| **No continuous HUD audio** | — | No ticking sound, no ambient UI hum. Audio is event-driven only. |

---

**📌 Asset Spec Flag — Visual/Audio requirements are defined. After the art bible is approved, run `/asset-spec system:HUD` to produce per-asset visual descriptions, dimensions, and generation prompts from this section.**

## UI Requirements

### Always-Visible HUD (Top Info Band)

All elements below are part of the top info band, arranged left-to-right:

| Element | Description | Detail |
|---------|-------------|--------|
| **Day counter** | "Day 12" in pixel font | Updates on day transition. Label "Day" is muted (`#aaaaaa`), number is white. |
| **Speed buttons** | Three buttons: 0.5x / 1x / 2x | Active button filled, inactive buttons outline-only. Pressing active button has no effect. |
| **Pause/Play button** | Toggles PAUSED ↔ RUNNING state | Pause icon (││) when running, Play icon (▶) when paused. |
| **Energy bar** | Horizontal bar showing energy level | Color gradient (green/yellow/orange/red) with pattern overlay (hatch/crosshatch). Numeric readout "67/100". Skull icon + "DEPLETED" at 0. Hover shows time-to-threshold projection. |
| **Resource display** | Icons + quantities for tracked resources | Flat-shaded 24×24px icons. Stack counter in bottom-right of icon. Shows: Wood, Berries, Stone (VS resources). Polls every 500ms. |
| **In-transit counter** | Small badge showing items being carried | Shows "1" when player has an item in transit. Disappears when transport completes. |
| **Storage quick-access** | Map-wide storage summary | Barrel icon (24×24px) + thin fill bar + capacity text "42/150". Clicking opens full storage panel. Hover: "All Storage — 42/150 (28%)". |

### Hover Tooltip System

| Element | Description | Detail |
|---------|-------------|--------|
| **Single tooltip Control** | One shared tooltip, shown/hidden/updated | Never more than one tooltip visible at a time. Position follows cursor + offset. |
| **Hover delay** | 250ms before tooltip appears | Prevents flicker during fast cursor movement. Resets if cursor leaves target. |
| **Tier 1 — Tile tooltip** | Tile type, state, contextual hint | "Clear Ground — Day 3 of 7 — Click to harvest" |
| **Tier 2 — Building tooltip** | Building name, status, inputs/outputs, workers | "Lumberjack Hut — Producing: 3/100 ticks — Input: Tool → Output: Wood — Workers: 1/1" |
| **Tier 3 — Resource tooltip** | Resource name, quantity, capacity, rate | "Wood — 42 in storage — 50 total capacity — Producing 5/day" |
| **Keyboard accessibility** | Tab to focus targets, Enter/Space to show | Hover is a mouse convenience, not the only inspection method. |

### Storage Panel (Modal)

| Element | Description | Detail |
|---------|-------------|--------|
| **Container selection** | List of all storage containers | Shown when player clicks a specific storage building on the map. |
| **Slot grid** | 10 columns × N rows per container | 32×32px cells. Resource icon (24×24px), quantity number (bottom-right). Empty cells dimmed at 30% opacity. |
| **Capacity bar** | Header showing occupied/total | "42 / 150 slots". Color matches utilization thresholds. |
| **Resource filter** | Row of icons below capacity bar | Shows only resources currently in storage. Clicking an icon filters the grid. "Show all" resets. |

### Building Detail Panel (Deferred — MVP Scope)

> This modal is out of scope for the Vertical Slice. Building hover tooltips (Section D) provide all VS-level building inspection. A full building detail panel is planned for MVP when the Dashboard UI (#26) is designed.

| Element | Description | Detail |
|---------|-------------|--------|
| **Building name** | Title line at top of panel | Pixel font, 18px. |
| **Production status** | Current state, progress bar, input/output | "Producing — ████████░░ 80% — Input: Tool → Output: Wood" |
| **Worker info** | Assigned workers, capacity | "Workers: 1/1" |
| **Blocked reason** | If production is blocked | Red text: "Blocked — No tools in storage" or similar. |
| **Close button** | X icon in top-right corner | Click, Escape, or backdrop click to close. |

### Day Overview Panel (Day Transition Modal)

| Element | Description | Detail |
|---------|-------------|--------|
| **Panel title** | "Day [N] Complete" | Pixel font, 18px. |
| **Production summary** | What was produced this day | Per-building output totals. Green checkmarks for buildings that produced, amber for blocked buildings. |
| **Consumption summary** | What was consumed this day | Food consumed, tools used, resources pulled from storage. |
| **Status overview** | Active warnings, new bottlenecks | Brief list of any issues discovered during the day. |
| **Dismiss button** | "Continue" or "▶" button | Closes the panel. HUD calls `TickSystem.set_pause(false)` on dismiss. |

### Interaction Patterns

| Pattern | Description | Detail |
|---------|-------------|--------|
| **Click-to-open modal** | Clicking a storage building or quick-access opens the storage panel | The modal blocks the game world (`mouse_filter = MOUSE_FILTER_STOP`). |
| **Escape to close** | Pressing Escape closes any open modal | Returns focus to the map. No intermediate "confirm close" dialog. |
| **Backdrop click to close** | Clicking outside the modal panel closes it | The semi-transparent backdrop is itself a clickable element. |
| **Sticky tooltips** | Clicking a tooltip pins it in place | MVP feature — deferred from VS. Clicking again un-pins it. Allows the player to reference info while acting. |
| **Cross-system highlighting** | Hovering a building highlights connected resources in the resource display | MVP feature — deferred from VS. If a building outputs Wood, the Wood count in the top-right briefly pulses green. Requires event routing from Building State → HUD Resource Display. |

## Acceptance Criteria

### Display Accuracy

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC1 | **GIVEN** the Tick System reports `current_day = 12`, **WHEN** the HUD renders, **THEN** the day counter displays "Day 12" | Manual verification |
| AC2 | **GIVEN** the speed multiplier is 2x, **WHEN** the HUD renders, **THEN** the "2x" button is filled (active) and the other buttons are outline-only | Manual verification |
| AC3 | **GIVEN** `TickSystem.is_paused()` returns true, **WHEN** the HUD renders, **THEN** the pause/play button shows the pause icon (││) | Manual verification |
| AC4 | **GIVEN** the player energy is 67/100, **WHEN** the HUD renders, **THEN** the energy bar is green with text "67/100" and fill level at 67% | Screenshot test |
| AC5 | **GIVEN** the player energy is 0, **WHEN** the HUD renders, **THEN** the bar is red with skull icon + "DEPLETED" text, both pulsing at 2Hz | Screenshot + animation timing verification |
| AC6 | **GIVEN** total wood in storage across all containers is 42, **WHEN** the HUD renders, **THEN** the wood resource icon shows the quantity "42" | Manual verification |

### Energy Bar

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC7 | **GIVEN** energy is 85, **WHEN** the HUD renders, **THEN** the energy bar is green (70-100 zone) | Screenshot test |
| AC8 | **GIVEN** energy is 45, **WHEN** the HUD renders, **THEN** the energy bar is yellow (30-69 zone) | Screenshot test |
| AC9 | **GIVEN** energy is 15, **WHEN** the HUD renders, **THEN** the energy bar is orange (10-29 zone) | Screenshot test |
| AC10 | **GIVEN** energy is 5, **WHEN** the HUD renders, **THEN** the energy bar is red (0-9 zone) | Screenshot test |
| AC11 | **GIVEN** energy drops from 75 to 65 (crosses green→yellow threshold), **WHEN** the change occurs, **THEN** the bar color transitions with a 200ms crossfade (not instant) | Screenshot + animation timing verification |

### Hover Tooltips

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC12 | **GIVEN** the cursor hovers over a building for ≥250ms, **WHEN** the hover delay expires, **THEN** the building tooltip appears with building name, status, and output | Screenshot + timer verification |
| AC13 | **GIVEN** the cursor hovers over a building for 100ms then moves away, **WHEN** the cursor leaves the target, **THEN** the tooltip does NOT appear (delay was not met) | Manual verification |
| AC14 | **GIVEN** the cursor hovers over a tile, **WHEN** the tooltip appears, **THEN** it shows tile type, state, and one contextual hint | Screenshot verification |
| AC15 | **GIVEN** a building is demolished while the cursor hovers over it (during the 250ms delay), **WHEN** the tooltip render time arrives, **THEN** no tooltip appears (graceful degradation) | Manual verification |
| AC16 | **GIVEN** a tooltip is visible, **WHEN** the player clicks it, **THEN** the tooltip pins in place (sticky). Clicking again un-pins it | Manual verification |

### Storage Quick-Access

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC17 | **GIVEN** total storage capacity is 150 with 42 items across all containers, **WHEN** the HUD renders, **THEN** the storage quick-access shows "42/150" | Manual verification |
| AC18 | **GIVEN** the storage quick-access tooltip is hovered, **WHEN** the tooltip appears, **THEN** it explicitly states "All Storage" (not per-building) | Screenshot verification |
| AC19 | **GIVEN** storage utilization crosses 90%, **WHEN** the threshold is crossed, **THEN** the storage icon begins pulsing at 1Hz | Screenshot + animation timing |
| AC20 | **GIVEN** the storage quick-access is clicked, **WHEN** the storage modal panel opens, **THEN** the backdrop covers the viewport and clicks pass through to the HUD only | Manual verification |

### Modal Overlays

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC21 | **GIVEN** any modal panel is open, **WHEN** the player presses Escape, **THEN** the modal closes and the game world becomes interactive | Manual verification |
| AC22 | **GIVEN** any modal panel is open, **WHEN** the player clicks the backdrop, **THEN** the modal closes | Manual verification |
| AC23 | **GIVEN** the day transition fires, **WHEN** the Day Overview modal appears, **THEN** the game is in PAUSED state | Manual verification |
| AC24 | **GIVEN** the Day Overview modal is displayed, **WHEN** the player dismisses it, **THEN** `TickSystem.set_pause(false)` is called and time resumes | Integration test |

### Cross-System Coordination

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC25 | **GIVEN** the player changes speed from 1x to 2x, **WHEN** the change occurs, **THEN** `TickSystem.speed_changed` fires and the HUD updates the active button highlight | Integration test (signal verification) |
| AC26 | **GIVEN** the player hovers a building that outputs Wood, **WHEN** the hover appears, **THEN** the Wood resource count in the top info band briefly pulses green (cross-system highlighting) | Screenshot + animation timing |
| AC27 | **GIVEN** the resource display is polling at 500ms intervals, **WHEN** a building deposits 5 wood into storage, **THEN** the HUD updates the wood count within 500ms of the deposit | Integration test with timing verification |

### Performance

| # | Acceptance Criteria | Test Method |
|---|---------------------|-------------|
| AC28 | **GIVEN** 100 buildings exist on the map, **WHEN** the player moves the cursor across the map at 60fps, **THEN** the frame rate does not drop below 60fps (hover detection via tile lookup must not introduce latency) | Performance test (frame timing) |
| AC29 | **GIVEN** 500ms resource polling is active, **WHEN** the HUD runs for 10 minutes, **THEN** memory usage does not grow beyond the HUD baseline (no memory leak from polling or tooltip management) | Performance test (memory profiling) |

## Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| OQ1 | Should the storage quick-access show per-resource dots (one per resource type) instead of a single map-wide summary? | A dot per resource type gives faster at-a-glance storage pressure for specific resources. But a single summary is simpler for VS scope (1 resource type in active production). | **Deferred to VS scope discussion.** Single summary is sufficient for VS with 3 resources. |
| OQ2 | Should the energy bar show a consumption rate projection by default (e.g., "67/100 — ~12 actions left")? | More information transparency — the player can plan ahead. But it requires the PC System to expose a "current consumption rate" API. | **Deferred to PC System GDD.** If PC System doesn't expose consumption rate, the hover tooltip can only show a rough estimate. |
| OQ3 | Should the tick progress bar (referenced in Tick System OQ2) be implemented in the HUD? | The Tick System lists it as optional: "shows tick_count progress from 0–1000 for the current day." This would be a horizontal bar in the top info band showing day progress. | **Deferred to VS scope.** The top info band is already information-dense. Adding a progress bar requires tradeoffs with existing elements. |
| OQ4 | Should the HUD support keyboard-only navigation (no mouse)? | The hover tooltip system already has Tab/Enter keyboard equivalents. But the tick control buttons (speed, pause) need keyboard shortcuts (e.g., Space for pause, 1/2/3 for speed). | **Deferred to accessibility audit.** For VS, mouse is the primary input. Keyboard shortcuts are important for MVP. |
| OQ5 | When should the HUD query Building State — on every mouse move (current design) or only on hover enter event? | Current design: poll tile-to-building on every mouse move. This is simple but means the query runs frequently. An event-driven approach (hover enter → one query → hover exit → clear) would be more efficient. | **Deferred — profiler decision.** Tile lookup is O(1), so performance is unlikely to be a concern. Event-driven is cleaner but more complex to implement. |
| OQ6 | **Cognitive load — alert consolidation.** The HUD currently has 7+ concurrent active information sinks: day counter, speed controls, energy bar, food reserve, storage quick-access, system alerts (storage full, hunger, tool broken), hover tooltips, and modal overlays. Research suggests 3–4 simultaneous active sinks is comfortable for most players. **Design requirement:** All system alerts (storage full, NPC hungry, tool broken, building BLOCKED) MUST route through a single **Notification Tray** (one consolidated panel, stacking alerts in chronological order, auto-dismissing after player acknowledgement or condition clears). The notification tray counts as one active sink regardless of how many alerts it contains. Implement before MVP — alert proliferation is the most likely source of cognitive overload. | **REQUIRED before MVP implementation.** Alert consolidation must be designed into the HUD architecture from the start — retrofitting a tray after building 5 separate alert systems is significantly more costly. |
