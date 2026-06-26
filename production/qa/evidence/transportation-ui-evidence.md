# QA Evidence: Transportation Management UI

> **Story**: logistics-system/story-008-transportation-management-ui
> **Status**: [ ] Not yet verified
> **Tester**: —
> **Date**: —

## Test Environment

- Engine: Godot 4.6
- Build: Debug
- Setup: Start new game, build at least one Storage Area and one Lumber Camp, recruit at least one NPC

---

## AC Checklist

### Panel Open/Close

- [ ] **AC-1** Transportation panel opens within 100ms of clicking the 🚚 HUD button
  - Setup: Open game, click the transport icon (🚚) in the top band
  - Pass: Panel fades in as overlay immediately with route list visible

- [ ] **AC-2** Panel closes via "✕" button without applying changes
  - Setup: Panel open, no changes made
  - Pass: Panel fades out; no routes created; `panel_closed` signal emits `changes_made: false`

- [ ] **AC-2b** Escape key closes panel from any sub-view
  - Setup: Open panel, navigate to Route Detail
  - Pass: Escape → panel closes

- [ ] **AC-2c** Clicking outside panel area closes it
  - Setup: Panel open, click map tile outside panel rect
  - Pass: Panel closes

---

### Route List View

- [ ] **AC-3** Route List view shows all active routes as rows
  - Setup: Create 3 routes via LogisticsSystem (one active/transporting, one idle, one paused)
  - Pass: 3 rows visible; each shows From→To, NPC name, status badge (colored dot + text label)

- [ ] **AC-4** Empty state — "No routes configured yet." when zero routes exist
  - Setup: Fresh game with no routes
  - Pass: "No routes configured yet." text visible; "Create New Route" button still present

- [ ] **AC-19** Status badges include text labels AND colored dots
  - Setup: View route list with Transporting, Idle, and Paused statuses
  - Pass: Each badge shows dot color AND text label — "Transporting", "Idle", "Paused"

---

### Navigation

- [ ] **AC-5** Clicking a route row navigates to Route Detail with that route's data pre-filled
  - Setup: At least 1 route in list; click a route row
  - Pass: Route Detail opens; From shows source building; To shows destination; NPC shows assigned NPC

- [ ] **AC-6** "Create New Route" button opens Route Detail with all fields blank
  - Setup: Click "Create New Route"
  - Pass: Detail opens with title "New Route"; From selector shows "Select From Building"; To hidden; NPC list hidden

- [ ] **AC-7** "← Back" link returns to Route List without changes
  - Setup: In Route Detail (new route), select a From building, then click "← Back"
  - Pass: Route List appears; no route created

---

### Map-Select Interaction

- [ ] **AC-8** From selector closes panel and enables map-select mode with text prompt
  - Setup: In Route Detail (new route), click "Select From Building"
  - Pass: Panel disappears; text prompt "Select source building" appears near bottom of screen

- [ ] **AC-9** Clicking a building during map-select reopens panel with From filled
  - Setup: In map-select mode; scene calls `HUD.notify_building_selected_in_map_select(building_id)`
  - Pass: Panel reopens; From selector shows building name; To selector becomes visible

- [ ] **AC-10** Clicking empty space during map-select cancels and reopens panel (From blank)
  - Setup: In map-select mode; scene calls `HUD.notify_building_selected_in_map_select(&"")`
  - Pass: Panel reopens; From remains blank

---

### Route Detail Field Sequencing

- [ ] **AC-11** To selector appears only after From is selected
  - Setup: Open Route Detail for new route; verify To is hidden
  - Pass: To row not visible when From is blank; visible after From is set

- [ ] **AC-12** Route summary auto-calculates after both From and To are set
  - Setup: Select From and To buildings
  - Pass: Summary appears showing: "Distance: X tiles", "Round trip: X ticks", "Max: X / day"

- [ ] **AC-13** NPC picker appears only after route summary is calculated
  - Setup: Set From and To (summary visible)
  - Pass: NPC picker appears showing idle NPCs with names

---

### Route Confirmation

- [ ] **AC-14** Confirm/Save button disabled until NPC is selected
  - Setup: From + To set, no NPC selected
  - Pass: "Create & Close" button is grayed out / disabled

- [ ] **AC-15** "Create & Close" saves the new route and returns to Route List
  - Setup: From + To + NPC all selected; click "Create & Close"
  - Pass: Panel closes; new route appears in route list on next open; LogisticsSystem.get_active_routes() includes new route

- [ ] **AC-16** "Save & Close" edits an existing route and updates the list
  - Setup: Open existing route in detail; change NPC assignment; click "Save & Close"
  - Pass: Route updated in list; old route replaced by new one

- [ ] **AC-17** Delete icon removes route after confirmation dialog
  - Setup: Click "✕ Delete" on route row or in Route Detail
  - Pass: Confirmation dialog appears; on "Delete" confirm: route removed from list, NPC freed; on "Cancel": row stays

---

### Building Detail Panel Integration

- [ ] **AC-carrier-in** Lumber Camp building detail shows input carrier status
  - Setup: Create an INPUT route to a Lumber Camp
  - Pass: Transport section shows "NPC ← StorageBuilding" with carrier name

- [ ] **AC-carrier-out** Building detail shows output carrier status
  - Setup: Create an OUTPUT route from a Lumber Camp
  - Pass: Transport section shows "NPC → StorageArea" with carrier name

- [ ] **AC-efficiency** Efficiency badge color matches route state
  - Setup: Active route (green), WAITING route (yellow), DEACTIVATED route (red)
  - Pass: Tooltip on carrier label shows efficiency color per state

- [ ] **AC-no-carrier** Building detail shows "No input carrier" / "No output carrier" when unassigned
  - Setup: Lumber Camp with no routes
  - Pass: Both slots show warning-colored "No carrier" text

---

### Accessibility

- [ ] **AC-18** All interactive elements reachable via Tab cycling
  - Setup: Open Transportation panel; Tab through all elements
  - Pass: Route rows, "Create New Route" button, "← Back" link, From/To selectors, NPC picker, Confirm button — all receive Tab focus in logical order

- [ ] **AC-20** All text meets WCAG AA contrast ratio (≥4.5:1) against panel background (#3A3A3A)
  - Setup: Visual inspection with contrast checker
  - Pass: Route text (#F0EDE6 on #3A3A3A ≈ 11:1), status badge text (#D0D0D0 ≈ 8:1)

- [ ] **AC-21** Reduced-motion makes all transitions instant
  - Setup: Set `accessibility/reduced_motion = true` in Project Settings; open/close panel
  - Pass: No fade or slide — panel appears/disappears instantly

---

### Localization (Advisory)

- [ ] **AC-22** German and French locales display without text overflow
  - Setup: Set game locale to "de" or "fr"; open Transportation panel
  - Pass: Buttons auto-size; no text clipping on "Erstellen & Schließen" or "Créer & Fermer"

---

## Notes / Deviations

- Map-select mode requires parent scene (`map_root.gd`) to wire `HUD.notify_building_selected_in_map_select()` — not yet wired in `map_root.tscn` (post-story integration task)
- Efficiency badge uses story-007 stub (returns 1.0 / 0.5 / 0.0 by lifecycle state) — full Formula 3 implementation pending story 007
- UX spec `design/ux/transportation.md` status is "In Design" (not formally approved) at time of implementation
- Route update (AC-16) implemented as delete + recreate at MVP; preserving carrier mid-trip state is post-MVP
