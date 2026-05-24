# UX Spec: Transportation

> **Status**: In Design
> **Author**: user + ux-designer
> **Last Updated**: 2026-05-19
> **Journey Phase(s)**: unknown — no player journey map
> **Template**: UX Spec

---

## Purpose & Player Need

The player opens the transportation menu wanting to **get a stalled production chain moving again by assigning an NPC carrier to a resource route**.

Transportation is the logistics layer of the village — it connects storage buildings to production buildings via NPC carriers. When a production building is idle because its inputs are stuck in a storage building, the player uses this screen to dispatch an NPC to bridge the gap. It is the manual routing interface before full automation (where NPCs self-assign tasks).

**What goes wrong if this is hard to use:** Bottlenecks pile up silently. The player can't see which buildings are starved, which carriers are free, or where to send them. The core loop — detect, route, solve — becomes opaque instead of transparent, violating Pillar 2 (Information Transparency).

---

## Player Context on Arrival

**First encounter:** Once the player has at least one storage building and one production building that needs inputs from that storage — typically Day 2–3, after the first NPC is recruited and the player discovers the storage→production building connection.

**Immediate prior action:** The player observed a production building in a blocked state (red status indicator on the building), hovered to read "Waits for [resource]," and then either opened the building detail or a "dispatch carrier" affordance to resolve the stall.

**Emotional state on arrival:** Problem-solving. Focused and methodical — the player has already identified *what* is blocked and is now seeking *how* to unblock it. Not stressed; the bottleneck is a puzzle, not a penalty.

**Arrival type:** Voluntary. The player opens the transportation menu to solve an observed problem, not because the game forces them into it. This means the screen should feel responsive to intent, not a chore to navigate.

---

## Navigation Position

The transportation menu is a **context-dependent secondary screen**, always accessed from the main game view. The player never leaves the map — all transportation decisions happen in an overlay panel.

**Navigation path:** Main Game View → Transportation Menu

**Entry points:**
- "Dispatch Carrier" / "Assign Transport" affordance on a building interaction panel (when the building has free input slots)
- "Open Transportation" button in the HUD (always available, but visually highlighted when transport tasks are pending)

**All paths exit back to:** Main Game View

The screen is always reachable while on the map — it is never gated behind pause or a separate menu layer.

---

## Entry & Exit Points

### Entry Sources

| Entry Source | Trigger | Player Carries This Context |
|---|---|---|
| Building Detail Panel (HUD) | "Dispatch Carrier" / "Assign Transport" button on a building with missing inputs | Building name, missing resource type, nearest storage with that resource |
| HUD Transportation Button | Player clicks the transportation icon in the HUD overview panel | Current pending transport tasks, idle NPC count |

### Exit Destinations

| Exit Destination | Trigger | Notes |
|---|---|---|
| Main Game View | "Save & Close" — assignments take effect immediately | NPC carriers begin routes on next tick cycle |
| Main Game View | "Cancel" — no changes applied | Panel closes without modifying assignments |
| Main Game View | Escape key — always cancels and closes | Standard overlay dismiss |
| Main Game View | Click outside panel — cancels and closes | Standard overlay dismiss |

---

## Layout Specification

### Information Hierarchy

1. **Active Routes list** (primary) — a list showing every existing transport route with minimal info: from building, to building, resource, NPC assigned, current status (transporting / idle / paused). This is what the player sees on first opening the panel.
2. **Route Detail view** (secondary) — opens when a route from the list is clicked, or when the "Dispatch Transport" button on a building triggers a new route. Contains: From selector, To selector, max capacity per day, NPC picker. Both selectors use a map-select interaction (panel closes, player clicks a building on the map).
3. **"Create New Route" button** (always visible, bottom of panel) — starts the route creation flow from scratch.

### Layout Zones

Two distinct views, full-panel each. Navigation between them is "next" (select route → detail) and "back" (detail → list).

**View 1 — Active Routes List (default)**

| Zone | Description |
|------|-------------|
| **Title bar** | "Transportation" header + close/cancel button |
| **Route list** (main area) | Scrollable vertical list of active routes. Each row shows: From → To, resource type, NPC assigned, status badge (Transporting / Idle / Paused). Row height optimized for 1-click readability. |
| **"Create New Route" button** (bottom) | Full-width button. Clicking starts a fresh route from scratch (same flow as building "Dispatch Transport" affordance). |

**View 2 — Route Detail**

| Zone | Description |
|------|-------------|
| **Back button + title** (header) | "← Back" to return to list. Title shows route state: "New Route" or building name if edited. |
| **From selector** | Prominent button: "Select From Building". Clicking closes the panel, highlights the player on the map with "Select source building" prompt, player clicks a building on the map, panel reopens with the selected building shown. |
| **To selector** | Same pattern as From selector. Only appears after From is selected. |
| **Route summary** (read-only) | Auto-calculated after both From and To are set: max resources per day, travel time (round trip), distance in tiles. |
| **NPC picker** | Dropdown or scrollable list of idle NPCs available for this route. Shows NPC name, current assignment status, and perk tier. |
| **Confirm / Save button** (bottom) | Finalizes the route. "Save & Close" for editing existing routes, "Create & Close" for new routes. |

### Component Inventory

**View 1 — Active Routes List:**

| Zone | Component | Type | Interactive | Notes | Pattern Alignment |
|------|-----------|------|-------------|-------|-------------------|
| Title bar | "Transportation" label | Label | No | 16px bold, Silkscreen | Standard panel title |
| Title bar | Close button | Icon Button (X) | Yes | Small (24×24px), right-aligned | Standard close |
| Route list | Route row (reusable) | Composite card | Yes | From → To, resource icon + name, NPC name, status badge. Click navigates to Route Detail. | New pattern (route list card) |
| Route list | Status badge | Text + colored dot | No | Transporting (green), Idle (yellow), Paused (gray). 14px + dot. | Follows building-state color scheme from building-detail |
| Action bar | "Create New Route" button | Primary Button | Yes | Full-width, "Create New Route" text | Primary button pattern (sharp rectangle, #5A5A5A fill, hover #4A7EA8) |

**View 2 — Route Detail:**

| Zone | Component | Type | Interactive | Notes | Pattern Alignment |
|------|-----------|------|-------------|-------|-------------------|
| Header | Back button | Text Link | Yes | "← Back" — returns to list view | Standard back navigation |
| Header | Title | Label | No | "New Route" or building name (editing mode) | Standard panel title |
| Selector | From selector button | Primary Button | Yes | "Select From Building" — initially blank. After selection: "[Building Name] (storage)" with icon. Closes panel, enables map-select, reopens with selection. | New pattern (map-select button) — see Gaps & Patterns Needed |
| Selector | To selector button | Primary Button | Yes | Same as From. Conditionally hidden until From is selected. | Map-select button (same as above) |
| Summary | Route summary text block | Read-only text | No | Auto-calculated after From + To set: distance (tiles), round-trip time (ticks), max resources per day. | New pattern (route info summary) |
| Selector | NPC picker | Scrollable list | Yes | Same component as building-detail NPC selection popup. Shows NPC name, house assignment, perk tier, idle status. Click to select and assign. | Reused from building-detail spec |
| Action bar | Confirm / Save button | Primary Button | Yes | "Create & Close" (new route) or "Save & Close" (edit). Only enabled when From + To + NPC are all selected. | Primary button pattern |

**Pattern library gaps introduced:**
- **Map-Select Button**: A button that closes the current panel, highlights the player on the map with a selection prompt, accepts a building click, then reopens the panel with the selection. Used by From/To selectors.
- **Route List Card**: Composite component showing transport route summary (from, to, resource, NPC, status).
- **Route Info Summary**: Read-only auto-calculated block showing distance, time, capacity.

### ASCII Wireframe

[To be designed]

---

## States & Variants

| State / Variant | Trigger | What Changes |
|-----------------|---------|--------------|
| **Empty list** | No routes exist (early game) | Route list shows "No routes configured yet." "Create New Route" button still present. |
| **Routes populated** | At least one route exists | Standard route list with row entries showing from→to, resource, NPC, status badge. |
| **New route creation** | "Create New Route" button or building "Dispatch Transport" trigger | Detail view opens with title "New Route." From selector blank. To selector hidden. NPC picker shows idle NPCs. |
| **Editing existing route** | Click an existing route row from the list | Detail view opens showing current from→to, resource, NPC, and status. All fields editable. |
| **From selected, To pending** | Player selects source building via map-select | From selector shows selected building name with icon. To selector becomes visible. Panel reopens automatically. |
| **Map-select mode** (transient) | Player clicks From or To selector | **Panel closes completely.** Map becomes the active UI layer. Prompt text: "Select source building" or "Select destination building." Player clicks a building on the map. Panel reopens with selection filled. |
| **Both selectors set, NPC pending** | From and To selected | Route summary auto-calculates and appears below selectors showing distance (tiles), round-trip time (ticks), and max resources per day. NPC picker becomes visible. |
| **All fields complete** | From + To + NPC all selected | Confirm/Save button becomes enabled. |
| **Paused route** | Route paused from list view or detail | Status badge shows "Paused." Player can unpause or reassign NPC from detail view. |

---

## Interaction Map

Mapping interactions for: Keyboard/Mouse (primary) + Gamepad (partial). Covering partial gamepad support.

| Component | Action | Keyboard/Mouse | Gamepad | Immediate Feedback | Outcome |
|-----------|--------|----------------|---------|-------------------|---------|
| **Open Transportation** | Open menu from HUD | Click transportation icon in HUD overview panel | Navigate to HUD transport icon (Analog stick) + A | Panel fades in as overlay | Route List view visible |
| **Close Transportation** | Exit menu | Click "X" close button, or Escape from anywhere in panel | B/Back button | Panel fades out | Back to gameplay, no changes |
| **Select route (list→detail)** | Navigate to Route Detail | Click any route row in the list | Analog stick to highlight row + A | Selected row highlights; detail view fades in | Route Detail view opens with that route's data |
| **Create New Route** | Start fresh route | Click "Create New Route" button | Navigate to button + A | Detail view opens with "New Route" title | Route Detail view (empty) visible |
| **Dispatch from building** | Triggered by building detail "Dispatch Transport" link | Click "Manage Transport →" → opens Transportation → auto-navigates to detail for that building | A on the link → opens Transportation → auto-navigates | Panel opens; detail view pre-filled with destination building | Route Detail view, To selector pre-filled with clicked building |
| **Map-select: From** | Select source building | Click "Select From Building" → panel closes → click building on map | A on selector → panel closes → Analog stick moves crosshair + A on building | **Panel disappears.** Map highlight ring appears around player. Text prompt: "Select source building" → On building click: building highlight flash → panel reopens | From selector shows selected building name. To selector becomes visible. |
| **Map-select: To** | Select destination building | Click "Select To Building" → panel closes → click building on map | A on selector → panel closes → Analog stick moves crosshair + A on building | Same as From: panel closes, prompt on map, panel reopens on selection | To selector shows selected building name. Route summary calculates. NPC picker appears. |
| **Select NPC** | Choose carrier from list | Click NPC name in the scrollable list | Analog stick to navigate list + A | Selected NPC highlights in list | NPC assigned to route; Confirm button enables |
| **Confirm route (new)** | Save and close | Click "Create & Close" or press Enter on focused button | Navigate to button + A | Panel fades out; route appears in list; NPC begins transport if conditions met | Back to Route List with new route shown |
| **Confirm route (edit)** | Save changes to existing route | Click "Save & Close" or press Enter | Navigate to button + A | Panel fades out; route updated in list; NPC assignment changes take effect | Back to Route List with updated route |
| **Back to list** | Return from detail to list | Click "← Back" link | Navigate to link + A | Detail view fades out; list view fades in | Route List view visible with same selection highlight |
| **Delete route** | Remove a route | Click delete icon on route row | Navigate to row + X (or side button) | Delete confirmation dialog appears | On confirm: route removed, NPC freed. On cancel: row stays |

**Focus order** (keyboard/gamepad, View 1 — Route List):
1. Route rows (scrollable, first visible)
2. "Create New Route" button (bottom)
3. Close button (top-right, reachable but not in primary Tab cycle)

**Focus order** (keyboard/gamepad, View 2 — Route Detail):
1. "← Back" link
2. From selector button
3. To selector button (hidden until From selected)
4. NPC picker (hidden until From + To selected)
5. Confirm/Save button (hidden until all fields complete)
6. Close button (top-right, reachable but not in primary Tab cycle)

**Map-select interaction notes:**
- When the panel closes for map-select, a **persistent text prompt** remains on screen: "Select source building" or "Select destination building" (14px, centered near bottom). This replaces the panel so the player knows the context.
- The player must click a **building** on the map — clicking empty space cancels the selection (same as pressing Escape).
- The crosshair follows the cursor (mouse) or Analog stick (gamepad). Snap-to-grid is not used for map-select — the player must position precisely.
- The selected building is briefly highlighted (blue outline, 2px) when clicked, then the panel reopens immediately.
- If the player has no idle NPCs available, the From/To selection still works — they'll see an empty NPC picker and know they need to free up a carrier first.

---

## Events Fired

| Player Action | Event Fired | Payload / Data |
|---|---|---|
| Open Transportation menu | `transportation_opened` | `{entry_point: "hud" \| "building_dispatch"}` |
| Close Transportation (no changes) | `transportation_closed` | `{changes_made: false}` |
| Create New Route | `transport_route_created` | `{from_building_id, to_building_id, npc_id, resource_type}` |
| Edit route (save) | `transport_route_updated` | `{route_id, changes: {from?, to?, npc?}}` |
| Delete route (confirm) | `transport_route_deleted` | `{route_id, npc_freed}` |
| Map-select: From building clicked | `transport_from_selected` | `{building_id}` |
| Map-select: To building clicked | `transport_to_selected` | `{building_id}` |
| Select NPC for route | `transport_npc_selected` | `{route_id, npc_id}` |
| Map-select: cancel (click empty space) | `transport_map_select_cancelled` | `{step: "from" \| "to"}` |
| Dispatch from building (pre-filled To) | `transport_dispatch_initiated` | `{from_building_id, pre_filled_to_id}` |

**No event for:** Hovering route rows, panel open/close animations, back-to-list navigation.

**Architectural note:** All route-creating/updating events modify persistent game state (NPC assignments, transport queues). These events must be handled by the Transportation System — the UI only initiates them.

---

## Transitions & Animations

| Transition | Enter | Exit | Notes |
|------------|-------|------|-------|
| **Panel open** | Fade in + slide up (150ms, ease-out) | Fade out (120ms, ease-in) | Panel slides in from bottom of screen. |
| **Route List → Detail** | Slide right (150ms, ease-out) | Slide left (120ms, ease-in) | Horizontal slide — detail enters from right, exits to right. |
| **Map-select mode** (panel close) | Instant + panel fades (100ms) | Fade in (120ms, ease-out) | Instant transition between panel and map. Brief fade avoids jarring panel disappearance. |
| **Route summary appearance** | Fade in + slide up (200ms, ease-out) | Fade out (100ms, ease-in) | Only when From + To are set and summary becomes visible. |
| **NPC picker appearance** | Fade in + slide up (200ms, ease-out) | Fade out (100ms, ease-in) | Only when summary is set and NPC picker becomes visible. |
| **Route row selection highlight** | Instant background color change | Instant background color change | No animation — immediate visual feedback for keyboard/gamepad navigation. |
| **Confirm/Save button state change** | Enabled/disabled (instant) | — | Button is grayed out until all fields are complete. No animation. |

**Motion sickness:** All transitions are short (under 200ms) and use no large-scale movement. Reduced-motion setting makes all transitions instant.

---

## Data Requirements

| Data | Source System | Read / Write | Notes |
|------|--------------|--------------|-------|
| Active route list | Transportation System | Read | Populated on panel open. Not polled every frame — updates on transport state change signals. |
| Route: from building (ID, name, icon) | Building Registry | Read | Source of wares. Shows as "[Building Name]" + building icon in route rows. |
| Route: to building (ID, name, icon) | Building Registry | Read | Destination of wares. Shows as "[Building Name]" + building icon in route rows. |
| Route: resource type | Transportation System | Read | Derived from the to-building's input requirements. Shown as resource icon + name. |
| Route: NPC assignment | Transportation System | Read | NPC assigned as carrier. Shows as NPC name in route row. |
| Route: status | Transportation System | Read | TRANSPORTING / IDLE / PAUSED — shown as status badge. |
| Available buildings (map-selectable) | Building Registry + Grid/Map System | Read | Filtered list of buildings the player can click on the map. Only buildings with storage capacity (From) or production input needs (To) are relevant. |
| Idle NPCs list | NPC System | Read | NPCs available as carriers. Populated when NPC picker becomes visible in Route Detail. |
| NPC name/ID/tier | NPC System | Read | Displayed in NPC picker. Used for assignment on confirm. |
| Route summary: distance | Grid/Map System | Read | Computed from From and To building coordinates (Manhattan distance on 2D grid). |
| Route summary: round-trip time | Grid/Map System | Read | Derived from distance: ticks = distance × ticks_per_tile × 2 (round trip). |
| Route summary: max resources/day | Grid/Map System + Building Registry | Read | Derived from round-trip time and building input rate: ticks_per_day / round_trip_ticks. Integer division, rounded down. |
| Transport capacity per NPC | NPC System | Read | Currently 1 item per NPC (MVP). Shows max throughput for the selected NPC. |

**Architectural note:** The panel is **read-only** — all data comes from the Transportation System, Building Registry, NPC System, and Grid/Map System. The only write operation is route creation/editing/deletion (which fires events to the Transportation System). The panel does NOT cache or own game state.

---

## Accessibility

| Requirement | Implementation |
|-------------|----------------|
| **Keyboard-only navigation** | Tab enters the Transportation panel. Arrow keys (Up/Down) cycle through interactive elements: route rows, "Create New Route" button, close button. In Route Detail: Back link, From selector, To selector, NPC picker, Confirm button. All elements reachable. Escape closes the panel from any sub-view. Enter/Space activates focused buttons and links. |
| **Gamepad navigation** | Analog stick moves through panel interactive elements in focus order. D-pad focus order matches keyboard. A confirms. B/Back closes the panel or navigates back to list view. Close button reachable via deliberate navigation to right edge. |
| **Text contrast** | All text meets WCAG AA (≥4.5:1) against panel background (#3A3A3A). Route row text: #F0EDE6 on #3A3A3A (~11:1). Status badge text: #D0D0D0 (~8:1). |
| **Color-independent communication** | Status badges use color + text label: "Transporting" (green dot), "Idle" (yellow dot), "Paused" (gray dot). A colorblind player can identify every state from the text label alone. Status badge dot shape/color is supplementary, never primary. |
| **Focus indicators** | Keyboard/gamepad focus on buttons and interactive elements has visible outline (blue #4A7EA8 ring, 2px). Route row highlight also serves as focus indicator in list view. |
| **Reduced motion** | All panel transitions (slide up 150ms, fade 120ms) are short. A global reduced-motion toggle makes all transitions instant. Route row selection highlight is already instant. |
| **Map-select accessibility** | When panel closes for map-select, a text prompt "Select source building" / "Select destination building" remains on screen (14px, high contrast). Clicking empty space cancels (same as Escape). The crosshair follows cursor or Analog stick — no snap-to-grid required. |

---

## Localization Considerations

| Text Element | EN | DE | FR | Max chars |
|--------------|----|----|----|-----------|
| Panel title | "Transportation" | "Transport" | "Transport" | ~15 EN / 12 DE / 10 FR |
| Status: Transporting | "Transporting" | "Transportiert" | "En transit" | ~15 EN / 15 DE / 11 FR |
| Status: Idle | "Idle" | "Leerlauf" | "Inactif" | ~6 EN / 10 DE / 9 FR |
| Status: Paused | "Paused" | "Pausiert" | "En pause" | ~7 EN / 10 DE / 9 FR |
| Status badge (text + dot) | See above | See above | See above | ~15 EN |
| Create New Route button | "Create New Route" | "Neue Route erstellen" | "Créer un itinéraire" | ~18 EN / 24 DE / 24 FR |
| Detail title: New Route | "New Route" | "Neue Route" | "Nouvel itinéraire" | ~10 EN / 12 DE / 18 FR |
| From selector (default) | "Select From Building" | "Quelle wählen" | "Sélectionner le dépôt" | ~21 EN / 17 DE / 25 FR |
| From selector (selected) | "[Building] (storage)" | "[Gebäude] (Lager)" | "[Bâtiment] (stockage)" | ~22 EN / 20 DE / 26 FR |
| To selector (default) | "Select To Building" | "Ziel wählen" | "Sélectionner le Ziel" | ~19 EN / 13 DE / 24 FR |
| To selector (selected) | "[Building] (production)" | "[Gebäude] (Produktion)" | "[Bâtiment] (production)" | ~22 EN / 24 DE / 28 FR |
| Route summary label | "Route Summary" | "Route-Zusammenfassung" | "Résumé de l'itinéraire" | ~15 EN / 25 DE / 23 FR |
| Distance label | "Distance: X tiles" | "Distanz: X Kacheln" | "Distance: X tuiles" | ~17 EN / 21 DE / 21 FR |
| Time label | "Round trip: X ticks" | "Rundweg: X Ticks" | "A/R: X ticks" | ~20 EN / 20 DE / 17 FR |
| Capacity label | "Max: X/day" | "Max: X/Tag" | "Max: X/jour" | ~10 EN / 11 DE / 13 FR |
| NPC picker title | "Assign Carrier" | "Träger zuweisen" | "Attribuer le transporteur" | ~16 EN / 18 DE / 28 FR |
| Confirm: create | "Create & Close" | "Erstellen & Schließen" | "Créer & Fermer" | ~15 EN / 24 DE / 18 FR |
| Confirm: save edit | "Save & Close" | "Speichern & Schließen" | "Enregistrer & Fermer" | ~12 EN / 22 DE / 21 FR |
| Back link | "← Back" | "← Zurück" | "← Retour" | ~7 EN / 9 DE / 9 FR |
| Close button | "X" | "X" | "X" | 1 char |
| Delete icon | Delete icon | Delete icon | Delete icon | icon-only |
| Map-select prompt (from) | "Select source building" | "Quellgebäude wählen" | "Sélectionner le dépôt" | ~24 EN / 22 DE / 25 FR |
| Map-select prompt (to) | "Select destination building" | "Zielgebäude wählen" | "Sélectionner le Ziel" | ~28 EN / 22 DE / 24 FR |

**HIGH PRIORITY for localization:**
- **NPC picker title** — French "Attribuer le transporteur" (28 chars) nearly doubles the English length. The NPC picker label area must auto-size or wrap to accommodate.
- **Confirm buttons** — German expands significantly ("Erstellen & Schließen" 24 chars, "Speichern & Schließen" 22 chars). Buttons must not have a fixed width — they should grow to fit content or truncate with ellipsis.
- **Route summary labels** — German "Route-Zusammenfassung" (25 chars) may overflow a compact panel width. Summary header should wrap to two lines on narrow panels.
- **Map-select prompts** — Maximum visible text at any time. Must remain within screen safe area (bottom 15%).

---

## Acceptance Criteria

- [ ] Transportation panel opens within 100ms of clicking the HUD transport icon
- [ ] Route List view shows all active routes as rows with from→to, resource, NPC name, and status badge
- [ ] Route List view shows "No routes configured yet" text when zero routes exist
- [ ] Clicking a route row navigates to Route Detail view with that route's data pre-filled
- [ ] "Create New Route" button opens Route Detail view with all fields blank
- [ ] Building "Dispatch Transport" link opens Transportation panel and auto-navigates to Route Detail with To pre-filled
- [ ] Route Detail "← Back" link returns to Route List view without changes
- [ ] From selector closes the panel and enables map-select mode with text prompt
- [ ] Clicking a building on the map during map-select reopens the panel with the selected building in the From field
- [ ] Clicking empty space during map-select cancels selection and reopens the panel (From remains blank)
- [ ] To selector appears only after From is selected
- [ ] Route summary (distance, round-trip time, max capacity/day) auto-calculates after both From and To are set
- [ ] NPC picker appears only after Route summary is calculated
- [ ] NPC picker shows only idle NPCs with name and perk tier
- [ ] Selecting an NPC enables the Confirm/Save button
- [ ] "Create & Close" saves the new route and returns to Route List
- [ ] "Save & Close" edits an existing route and updates the list
- [ ] Delete icon on route row removes the route after confirmation dialog
- [ ] All interactive elements are reachable via keyboard (Tab cycling) and gamepad (Analog stick)
- [ ] All status badges include text labels in addition to colored dots (colorblind-safe)
- [ ] All text meets WCAG AA contrast ratio against panel background
- [ ] When reduced-motion setting is enabled, all panel transitions are instant

---

## Open Questions

1. **Delete confirmation dialog** — The interaction map references a "delete" action on route rows but does not specify the confirmation dialog layout. Should it follow the demolish confirmation pattern from building-detail (red fill, large warning icon), or be lighter (text-only, two buttons)?

2. **Route priority** — When multiple routes compete for the same idle NPC, should there be a priority system? (Low/Medium/High) The current spec assigns one NPC per route with no queuing or preemption.

3. **NPC reassignment while transporting** — If a player changes the NPC on an active route mid-transport (via Route Detail edit), should the current NPC complete their trip first, or switch immediately?

4. **Route limit** — Is there a maximum number of active transport routes? (e.g., "one route per NPC" is implicit, but what about NPC scarcity limiting total routes?)

5. **Panel positioning** — The Transportation panel slides in from the bottom or is centered? (Building-detail is centered. Consistency suggests centering, but the panel shows a list which may need more vertical space.)
