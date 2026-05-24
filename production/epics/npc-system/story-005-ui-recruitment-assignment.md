# Story 005: UI — Recruitment and Assignment

> **Epic**: NPC System
> **Status**: Ready
> **Layer**: Feature
> **Type**: UI — ADR-0009
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/npc-system.md`
**Requirements**:
- `TR-npc-005` (Task assignment with storage selection)
- UI-1 through UI-5 (all UI elements)

**ADR Governing Implementation**: ADR-0009: NPC State Machine and Movement
**ADR Decision Summary**: NPCs have no visible sprites at VS scope. All NPC state is communicated through building status indicators (green = producing, yellow = idle, red = blocked/stalled) and house worker counters. The UI layer provides the affordances for recruitment (house "Recruit" button) and assignment (building "Assign Worker" button with storage selection list). The player character's input system handles the click routing (through InputContext WORLD_ACTIVE gating).

**Engine**: Godot 4.6 | **Risk**: LOW (Control nodes, signals, simple UI patterns)
**Engine Notes**: Godot 4.6 dual-focus system (mouse hover and keyboard/gamepad focus are separate). HUD UI must handle both. No AccessKit requirements at VS scope (deferred). Control node hierarchy follows Building System scene structure — house and building nodes render their own UI overlays.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/npc-system.md`, scoped to this story:*

- [ ] **AC-UI-1** GIVEN a Residential House has empty worker slots WHEN the house is rendered on the map THEN a "Recruit" button (or localized equivalent) appears as an affordance on the house. Clicking it calls `NPCSystem.recruit_npc()` with the house tile position
- [ ] **AC-UI-2** GIVEN a Residential House WHEN the house is rendered THEN the worker counter displays "X/2 workers" (e.g., "0/2", "1/2", "2/2") and updates in real time as NPCs are recruited or removed
- [ ] **AC-UI-3** GIVEN a production building has free assignment slots WHEN the building is rendered THEN an "Assign Worker" affordance appears. Clicking it opens a list of idle NPCs (or auto-selects the nearest — OQ-1 closed: manual only at VS, so always presents a list)
- [ ] **AC-UI-4** GIVEN the player initiates NPC assignment on a building WHEN the assignment UI opens THEN available storage buildings are listed. The player selects one, confirming the persistent storage assignment. The UI shows storage building names and their current capacity
- [ ] **AC-UI-5** GIVEN an NPC is assigned to a building WHEN the NPC is in WORK_AT_BUILDING state THEN the building shows a green status indicator; when no NPC is assigned, the building shows yellow; when the NPC is in WAITING (storage full), the building shows red

---

## Implementation Notes

*Derived from ADR-0009 Implementation Guidelines:*

**UI elements (from GDD UI Requirements):**

| ID | Element | Description |
|----|---------|-------------|
| UI-1 | House recruit button | Appears on Residential Houses with empty slots. Text: "Recruit". Click triggers `NPCSystem.recruit_npc(house_tile)` |
| UI-2 | House worker counter | Shows "X/2 workers" on house tooltip. Updates via `NpcSystem.get_npc_count()` for the house's NPCs |
| UI-3 | Building assignment UI | Building with free slots shows "Assign Worker" affordance. Click opens list of idle NPCs from `NpcSystem.get_available_npcs()` |
| UI-4 | Storage selection | When assigning NPC, shows available storage buildings with capacity. Storage selected via `NpcSystem.assign_npc(npc_id, building_id, storage_id)` |
| UI-5 | NPC state indicator (abstract) | No direct NPC UI. Building status colors communicate NPC state: green = producing, yellow = idle, red = blocked/stalled |

**Building status color mapping (from GDD Visual/Audio Requirements):**
```
# Building status indicators (rendered as overlay on building visual):
if npc_assigned and npc.state == WORK_AT_BUILDING:  → green
if not npc_assigned:                                → yellow
if npc.state == WAITING (storage full):             → red
if npc.state in [IDLE, TRAVEL_TO_BUILDING]:          → yellow (effectively "idle" — NPC not yet at building)
if npc.state in [TRAVEL_TO_STORAGE, DEPOSIT, RETURN_TO_BASE]: → green (NPC is working on the cycle)
```

**Interaction flow (from GDD Rule 3, OQ-1 closed):**
```
# Assignment is manual only at VS — no auto-select of nearest NPC.
# Flow:
# 1. Player clicks building with free slots → "Assign Worker" affordance appears
# 2. Player clicks affordance → opens NPC selection list (from NpcSystem.get_available_npcs())
# 3. Player selects an idle NPC from the list
# 4. Player selects storage building from storage selection list
# 5. NPCSystem.assign_npc(npc_id, building_id, storage_id) is called
# 6. If successful: building status → green, NPC begins travel
# 7. If failed (invalid state): error tooltip shown
```

**Real-time updates:**
```
# Worker counter: Update on npc_recruited and npc_removed signals
# Building status: Update on npc_assigned, npc_released, npc_state_changed signals
# Storage selection: Populate from InventorySystem.get_storage_containers() — query available storage buildings
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: NPC recruitment logic (only the UI affordance for triggering it)
- Story 002: Task cycle mechanics (NPC behavior is tested in the logic/integration stories)
- Story 004: Disconnection dialog (data-side logic; the reassignment dialog is part of this story's UI, but demolition-triggered behavior is tested in Story 004)

---

## QA Test Cases

**AC-UI-1**: Recruit button appears on house with empty slots
  - Setup: Place Residential House at tile (10,10), no NPCs recruited
  - Verify: House visual has "Recruit" button overlay; button is clickable; button text reads "Recruit"
  - Pass condition: Clicking "Recruit" calls NPCSystem.recruit_npc(Vector2i(10,10)), NPC created, worker counter updates to "1/2"

**AC-UI-2**: Worker counter updates in real time
  - Setup: House at (10,10), 0/2 workers
  - Verify: Worker counter shows "0/2"
  - When: NPC recruited (via UI or directly)
  - Verify: Counter updates to "1/2"
  - When: Second NPC recruited
  - Verify: Counter updates to "2/2", "Recruit" button disappears
  - When: NPC removed (via Story 004 demolition flow)
  - Verify: Counter updates to "1/2", "Recruit" button reappears
  - Pass condition: Counter always reflects current NPC count for the house, updates synchronously with NPCSystem state changes

**AC-UI-3**: Building assignment affordance and NPC list
  - Setup: Production building (Lumber Camp) placed with free assignment slot, at least one idle NPC exists
  - Verify: "Assign Worker" affordance visible on building; clicking opens NPC list
  - When: NPC list opens
  - Verify: List shows all idle NPCs (from NpcSystem.get_available_npcs()), each showing NPC identifier
  - Pass condition: Clicking an NPC from the list selects it for assignment; empty list shows "No idle NPCs"

**AC-UI-4**: Storage selection during assignment
  - Setup: NPC selected for assignment, building exists
  - Verify: Storage selection UI appears listing available storage buildings
  - When: Player selects a storage building
  - Verify: Selected storage is displayed in the confirmation dialog; storage shows current capacity (e.g., "Storage A — 50/150 slots used")
  - When: Player confirms assignment
  - Verify: NPCSystem.assign_npc(npc_id, building_id, storage_id) is called with correct parameters
  - Pass condition: Storage assignment is persistent across production cycles (stored on NPCInstance.assigned_storage_id)

**AC-UI-5**: Building status color indicators
  - Setup: NPC assigned to production building, NPC in WORK_AT_BUILDING state
  - Verify: Building status indicator is green
  - When: NPC completes cycle and returns to IDLE (no building assignment)
  - Verify: Building status indicator changes to yellow
  - When: Storage is filled to capacity, NPC arrives at storage to deposit
  - Verify: Building status indicator changes to red (STALLED / NPC in WAITING)
  - When: Storage space opens, NPC deposits and returns
  - Verify: Building status indicator returns to green (if NPC remains assigned)
  - Pass condition: Colors accurately reflect NPC state, update synchronously with state transitions

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/npc-ui-evidence.md` — screenshot-based evidence with sign-off

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (NPCs must exist to be recruited/assigned), Story 002 (building status indicators depend on NPC travel/work states)
- Unlocks: None — this is the final story for the NPC System epic
