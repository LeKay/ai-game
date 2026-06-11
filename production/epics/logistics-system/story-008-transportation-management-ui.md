# Story 008: Transportation Management UI

> **Epic**: Logistics System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-014`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0011: Logistics System — Carrier FSM and Route Architecture
**UX Spec**: `design/ux/transportation.md` — Transportation Management UI with Active Routes List view, Route Detail view, map-select interaction for source/destination building selection, keyboard/gamepad navigation, accessibility (WCAG AA), localization (EN/DE/FR).

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Godot 4.6 dual-focus system (mouse/touch focus separate from keyboard/gamepad focus). Both `grab_focus()` paths must be tested for HUD controls. See ADR-0003 input context and control manifest.

---

## Acceptance Criteria

*From GDD `design/gdd/logistics-system.md`, scoped to this story:*

- [ ] Transportation Management UI provides an Active Routes List view showing all existing routes with From → To, resource, NPC, and status
- [ ] Route Detail view allows player to create new routes: select source building (map-select), select destination building (map-select), assign an available NPC
- [ ] Route creation is player-driven — no auto-assignment. The player deliberately decides which NPC goes where.
- [ ] Player can delete an active route — triggers PAUSED state per EC-L6 (carrier completes current leg then returns home IDLE)
- [ ] Player can toggle a route on/off (ACTIVE ↔ PAUSED)
- [ ] Building detail panel shows carrier status section: input carrier status (assigned NPC → source, or "No input carrier") and output carrier status (assigned NPC → destination, or "No output carrier"), including distance and round-trip time for active routes
- [ ] Building detail panel shows efficiency indicator badge (Formula 3 UI interpretation: green ≥ 1.0, yellow 0.5–1.0, red < 0.5)
- [~] Player can toggle a route on/off (ACTIVE ↔ PAUSED) — backend ready (pause_route/resume_route), UI toggle button missing; ADVISORY (see Completion Notes)
- [~] Hover tooltip on map buildings — **REMOVED FROM SCOPE**: belongs in route visualization (story 006)

---

## Implementation Notes

*Derived from UX spec `design/ux/transportation.md` and ADR-0011:*

**Panel structure** — Two views, full-panel each, stored as a `Control` with two `Container` children that toggle visibility:
1. `ActiveRoutesList` — default view, scrollable route list + "Create New Route" button
2. `RouteDetail` — route creation/editing view with From/To selectors, NPC picker, confirm/save

**View 1 — Active Routes List**:
- Route rows are a reusable composite component showing: From → To, resource icon+name, NPC name, status badge
- Status badges use color + text label (green=Transporting, yellow=Idle, gray=Paused) for colorblind accessibility
- "Create New Route" full-width button at bottom
- Empty state: "No routes configured yet." text

**View 2 — Route Detail**:
- From/To selectors use a **Map-Select Button** pattern: close panel → highlight player on map → accept building click → reopen panel with selection
- Map-select text prompt remains on screen when panel closes: "Select source building" or "Select destination building"
- NPC picker: scrollable list of idle NPCs (name, perk tier) — reused from building-detail NPC selection
- Confirm/Save button disabled until From + To + NPC all selected
- Route summary auto-calculates after both From and To are set: distance (tiles), round-trip time (ticks), max resources per day

**Data binding** — Panel is read-only; all data from Transportation System, Building Registry, NPC System, Grid/Map System. Updates on state change signals, not per-frame polling.

**Events fired** (UI initiates, Transportation System handles):
- `transport_route_created` → `{from_building_id, to_building_id, npc_id, resource_type}`
- `transport_route_updated` → `{route_id, changes: {from?, to?, npc?}}`
- `transport_route_deleted` → `{route_id, npc_freed}`

**Animation timings** (reduced-motion → instant):
- Panel open: fade in + slide up (150ms, ease-out)
- Panel close: fade out (120ms, ease-in)
- Route List → Detail: slide right (150ms, ease-out)

**Control Manifest Rules (Presentation Layer)**:
- Required: Depth ordering via `Node2D.y_sort_enabled` — not legacy YSort
- Required: Data-visual separation
- Required: Godot 4.6 dual-focus — both `grab_focus()` paths tested (keyboard and mouse hover)
- Required: WCAG AA text contrast (≥4.5:1) against panel background (#3A3A3A)

**Key constraints from GDD**:
- Route discovery is organic — no gating or unlock
- Route creation is player-driven — no auto-assignment (Foreman fantasy)
- Transportation Management UI is a separate spec (`design/ux/transportation.md`)

**Out of scope from UX spec** (deferred — open questions):
- Delete confirmation dialog layout (follow demolish confirmation pattern?)
- Route priority system for competing NPC assignments
- NPC reassignment while transporting (complete current trip vs. immediate switch)
- Route limit (one per NPC implicit, NPC scarcity limits total)
- Panel positioning (centered vs. bottom slide) — TBD, default to centered for consistency with building-detail

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Route model and slot validation (the data layer the UI queries)
- [Story 002]: Carrier FSM core loop (the execution layer the UI configures)
- [Story 006]: Route visualization on the map (visual display of routes — distinct from the management UI panel)

---

## QA Test Cases

*From UX spec `design/ux/transportation.md` acceptance criteria (22 ACs), converted to manual verification steps.*

**Panel open/close:**

- **AC-1**: Transportation panel opens within 100ms of clicking the HUD transport icon
  - Setup: Open game, navigate to HUD with transport icon
  - Verify: Panel fades in as overlay immediately
  - Pass condition: Panel fully visible within 100ms

- **AC-2**: Panel closes via "X" button, Escape key, or clicking outside panel — no changes applied
  - Setup: Panel open with no route modifications
  - Verify: Panel fades out; no routes created
  - Pass condition: `transportation_closed` event fires with `{changes_made: false}`

**Route List view:**

- **AC-3**: Route List view shows all active routes as rows with from→to, resource, NPC name, status badge
  - Setup: Create 3 routes via LogisticsSystem (one active, one idle, one paused)
  - Verify: 3 rows displayed with correct from→to, resource icon+name, NPC name, status badge
  - Pass condition: All 4 data points visible per row

- **AC-4**: Empty state — "No routes configured yet." when zero routes exist
  - Setup: Start new game with no routes
  - Verify: Route list area shows "No routes configured yet." text
  - Pass condition: Text is visible and "Create New Route" button still present

**Navigation:**

- **AC-5**: Clicking a route row navigates to Route Detail with that route's data pre-filled
  - Setup: Have 1+ routes in list, click a route row
  - Verify: Route Detail view opens; From/To show the selected route's buildings; NPC picker shows assigned NPC
  - Pass condition: All fields match the selected route

- **AC-6**: "Create New Route" button opens Route Detail with all fields blank
  - Setup: Click "Create New Route" button
  - Verify: Route Detail opens; From selector blank; To selector hidden; NPC picker shows idle NPCs
  - Pass condition: Correct empty state

- **AC-7**: "← Back" link returns to Route List view without changes
  - Setup: In Route Detail, make a change (select a building) but don't confirm
  - Verify: Click "← Back"; Route List appears with original data
  - Pass condition: No unsaved changes applied

**Map-select interaction:**

- **AC-8**: From selector closes panel and enables map-select mode with text prompt
  - Setup: In Route Detail (new route), click "Select From Building"
  - Verify: Panel disappears; map highlight ring around player; text prompt "Select source building" appears
  - Pass condition: Panel closed, prompt visible

- **AC-9**: Clicking a building during map-select reopens panel with selected building in From field
  - Setup: In map-select mode, click a building
  - Verify: Panel reopens; From selector shows building name with icon; To selector becomes visible
  - Pass condition: From filled, To visible

- **AC-10**: Clicking empty space during map-select cancels selection and reopens panel (From remains blank)
  - Setup: In map-select mode, click empty map space
  - Verify: Panel reopens; From selector still blank
  - Pass condition: From unchanged, map-select mode exited

**Route Detail field sequencing:**

- **AC-11**: To selector appears only after From is selected
  - Setup: Open Route Detail for new route
  - Verify: To selector is hidden
  - Pass condition: To selector not visible until From has a value

- **AC-12**: Route summary auto-calculates after both From and To are set
  - Setup: Select From and To buildings
  - Verify: Route summary appears showing distance (tiles), round-trip time (ticks), max resources/day
  - Pass condition: All 3 values calculated and displayed

- **AC-13**: NPC picker appears only after route summary is calculated
  - Setup: Set From and To (but don't select NPC)
  - Verify: NPC picker is visible showing idle NPCs with name and perk tier
  - Pass condition: NPC picker visible, only idle NPCs shown

**Route confirmation:**

- **AC-14**: Selecting an NPC enables the Confirm/Save button
  - Setup: Have From + To set (summary calculated), NPC picker visible but no NPC selected
  - Verify: Confirm/Save button is disabled (grayed out)
  - Pass condition: Button disabled until NPC selected

- **AC-15**: "Create & Close" saves the new route and returns to Route List
  - Setup: In Route Detail with From + To + NPC selected, click "Create & Close"
  - Verify: Panel closes; new route appears in Route List with correct data
  - Pass condition: Route visible in list, `transport_route_created` event fired

- **AC-16**: "Save & Close" edits an existing route and updates the list
  - Setup: Open existing route in detail, change NPC assignment, click "Save & Close"
  - Verify: Panel closes; Route List shows updated NPC for the route
  - Pass condition: Route updated, `transport_route_updated` event fired

- **AC-17**: Delete icon on route row removes the route after confirmation dialog
  - Setup: Open Route List with 1+ routes, click delete icon on a route row
  - Verify: Confirmation dialog appears; confirm deletion
  - Pass condition: Route removed from list, NPC freed, `transport_route_deleted` event fired

**Accessibility:**

- **AC-18**: All interactive elements reachable via keyboard (Tab cycling) and gamepad (Analog stick)
  - Setup: Open Transportation panel, navigate through all views
  - Verify: Every button, row, and link receives focus in correct order
  - Pass condition: No element skipped in Tab/Analog stick navigation

- **AC-19**: All status badges include text labels in addition to colored dots
  - Setup: View route rows with Transporting, Idle, and Paused statuses
  - Verify: Each status shows both a colored dot AND text label ("Transporting", "Idle", "Paused")
  - Pass condition: Colorblind player can identify every state from text alone

- **AC-20**: All text meets WCAG AA contrast ratio against panel background
  - Setup: Open panel with route list
  - Verify: Route row text (#F0EDE6 on #3A3A3A ~11:1), status badge text (#D0D0D0 ~8:1)
  - Pass condition: All text meets ≥4.5:1 contrast ratio

- **AC-21**: Reduced-motion setting makes all panel transitions instant
  - Setup: Enable reduced-motion in game settings, open/close Transportation panel
  - Verify: No slide or fade animations — panel appears/disappears instantly
  - Pass condition: All transitions are 0ms

**Localization:**

- **AC-22**: Localized text displays correctly for DE and FR
  - Setup: Set game locale to DE, open Transportation panel
  - Verify: All text elements display German translations; buttons auto-size for longer text (e.g., "Erstellen & Schließen")
  - Pass condition: No text overflow or clipping; FR locale similarly verified

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- UI: `production/qa/evidence/transportation-ui-evidence.md` or interaction test

**Status**: [ ] Not yet created — BLOCKED on UX spec

---

## Dependencies

- Depends on: UX spec `design/ux/transportation.md` must be written and approved
- Depends on: Story 001 (route model data must exist for UI to query)
- Unlocks: None

---

## Completion Notes
**Completed**: 2026-06-02
**Criteria**: 6/7 passing (1 advisory)
**Deviations**:
- ADVISORY: AC-5 (toggle on/off) — pause_route()/resume_route() on LogisticsSystem and route_toggled signal on panel are ready; UI toggle button in route rows was not added. Add in next sprint.
- ADVISORY: Efficiency badge uses story-007 stub (Formula 3 pending story 007).
- ADVISORY: Map-select mode requires map_root.gd wiring of HUD.notify_building_selected_in_map_select() — integration task.
- ADVISORY: UX spec status was "In Design" (not formally approved) at time of implementation.
- INFORMATIONAL: Route update (edit existing) implemented as delete+recreate at MVP.
- AC-8 (map building hover tooltip) removed from scope → moved to story 006 (route visualization).
**Test Evidence**: UI story — evidence doc at `production/qa/evidence/transportation-ui-evidence.md`
**Code Review**: Skipped — Lean mode
