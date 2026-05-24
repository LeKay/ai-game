# Story 002: Task Cycle — Travel and Work

> **Epic**: NPC System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration — ADR-0009
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/npc-system.md`
**Requirements**:
- `TR-npc-002` (NPC state machine: IDLE → TRAVEL_TO_BUILDING → WORK → TRAVEL_TO_STORAGE → DEPOSIT → RETURN_TO_BASE)
- `TR-npc-003` (Manhattan-distance abstract movement, ticks_per_tile = 3.0)

**ADR Governing Implementation**: ADR-0009: NPC State Machine and Movement
**ADR Decision Summary**: Task Cycle Engine iterates all NPCs on each `ticks_advanced(delta)` call. Travel Manager advances `travel_progress` for NPCs in TRAVEL_TO_BUILDING, TRAVEL_TO_STORAGE, and RETURN_TO_BASE states. When `travel_progress >= travel_ticks_total`, the NPC arrives and state transitions. Manhattan distance via GridMap, travel_ticks = distance × ticks_per_tile (Formula 1).

**NPC Role Split (Transportation System update):** The 7-state task cycle now covers two NPC roles:
- **Operator NPCs** (assigned via Building Detail panel): execute TRAVEL_TO_BUILDING → WORK_AT_BUILDING. They do NOT travel to storage — the operator stays at the building permanently until released. `production_output_ready` is consumed by the Transportation System, not by the operator NPC.
- **Carrier NPCs** (configured via Transportation Management UI): execute the full cycle including TRAVEL_TO_STORAGE, DEPOSIT, RETURN_TO_BASE, and WAITING. Carrier scheduling is governed by the Transportation System (spec: `design/ux/transportation-management.md`).
This story covers the **operator NPC** cycle (TRAVEL_TO_BUILDING → WORK_AT_BUILDING) and the shared travel mechanics used by both NPC types.

**Engine**: Godot 4.6 | **Risk**: LOW (pure GDScript data, stable APIs — `_process`, `Engine.get_singleton()`)
**Engine Notes**: No post-cutoff APIs. `ticks_advanced` signal from TickSystem subscription. Integer arithmetic for travel progress (no float drift). Deterministic iteration order via Dictionary.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/npc-system.md`, scoped to this story:*

- [ ] **AC-5** GIVEN an NPC is assigned to a building at known Manhattan distance WHEN travel begins THEN travel time = Manhattan distance × ticks_per_tile (Formula 1). For example: distance 3, ticks_per_tile 3.0 → travel_ticks_total = 9. After 9 accumulated ticks, the NPC arrives at the building.
- [ ] **AC-6** GIVEN an NPC is assigned to a production building as **operator** WHEN the task cycle proceeds THEN the NPC executes: TRAVEL_TO_BUILDING → WORK_AT_BUILDING (stays at building, repeating work cycles). The operator does NOT transition to TRAVEL_TO_STORAGE — that is the carrier NPC's responsibility (Transportation System). The operator returns home only via RETURN_TO_BASE when explicitly released.
- [ ] **AC-6b** GIVEN a **carrier NPC** is assigned a transport route WHEN the full carrier task cycle proceeds THEN the carrier executes: TRAVEL_TO_BUILDING (to collect output) → TRAVEL_TO_STORAGE → DEPOSIT → RETURN_TO_BASE → IDLE. Carrier assignment and dispatch is governed by the Transportation System (spec: `design/ux/transportation-management.md`).
- [ ] **AC-3** (from GDD — task assignment) GIVEN an idle NPC and a production building with free slots WHEN the player assigns the NPC THEN the NPC state changes to TRAVEL_TO_BUILDING, travel_ticks_total is computed, and travel_progress starts at 0

---

## Implementation Notes

*Derived from ADR-0009 Implementation Guidelines:*

**assign_npc() flow (from ADR-0009):**
```
func assign_npc(npc_id: StringName, building_id: StringName, storage_id: StringName) -> AssignmentResult:
    var npc := all_npcs.get(npc_id)
    if npc == null or npc.state != TaskState.IDLE:
        return AssignmentResult.INVALID_NPC_STATE

    var building_tile := building.get_building_tile(building_id)
    var travel_ticks := _compute_travel_ticks(npc.position, building_tile)

    npc.assigned_building_id = building_id
    npc.assigned_storage_id = storage_id
    npc.travel_destination = building_tile
    npc.travel_ticks_total = travel_ticks
    npc.travel_progress = 0
    npc.state = TaskState.TRAVEL_TO_BUILDING

    npc_assigned.emit(npc_id, building_id)
    return AssignmentResult.SUCCESS

func _compute_travel_ticks(from: Vector2i, to: Vector2i) -> int:
    var distance := grid_manhattan_dist(from, to)
    return distance * ticks_per_tile  # default 3.0
```

**Tick-driven travel advancement (from ADR-0009):**
```
func _on_ticks_advanced(delta: int) -> void:
    for npc in all_npcs.values():
        match npc.state:
            TaskState.TRAVEL_TO_BUILDING:
                npc.travel_progress += delta
                if npc.travel_progress >= npc.travel_ticks_total:
                    _npc_arrived_at_building(npc)

            TaskState.TRAVEL_TO_STORAGE:
                npc.travel_progress += delta
                if npc.travel_progress >= npc.travel_ticks_total:
                    _npc_arrived_at_storage(npc)

            TaskState.RETURN_TO_BASE:
                npc.travel_progress += delta
                if npc.travel_progress >= npc.travel_ticks_total:
                    _npc_returned_home(npc)

            _:
                pass  # IDLE, WORK_AT_BUILDING, DEPOSIT, WAITING — no timer work
```

**State transitions for this story (operator NPC):**
```
IDLE → TRAVEL_TO_BUILDING:  assign_npc() direct call
TRAVEL_TO_BUILDING → WORK_AT_BUILDING: travel_progress >= travel_ticks_total
WORK_AT_BUILDING → WORK_AT_BUILDING: production cycle repeats — operator stays at building
WORK_AT_BUILDING → RETURN_TO_BASE: operator released via release_npc()
RETURN_TO_BASE → IDLE: travel_progress >= travel_ticks_total (arrived at home)

# Note: TRAVEL_TO_STORAGE and DEPOSIT are carrier NPC states, not operator states.
# Carrier NPC cycle is governed by TransportationSystem — not implemented in this story.
```

**Tuning knob:**
```
const TICKS_PER_TILE: float = 3.0  # default — primary distance balance knob
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: NPC recruitment (NPCs must exist before they can be assigned)
- Story 003: WAITING state and storage-full handling for carrier NPCs — carrier deposit edge cases (separate from operator NPC concern)
- Story 004: Disconnection on demolition (NPC just assigned and working, not demolished)
- Transportation System stories: carrier NPC scheduling, `collect_output()`, `deliver_input()`, TRAVEL_TO_STORAGE / DEPOSIT states for carrier NPCs — governed by Transportation System epic

---

## QA Test Cases

**AC-5**: Travel time = Manhattan distance × ticks_per_tile
  - Given: NPC at (2, 3), building at (5, 3). Manhattan distance = |2-5| + |3-3| = 3. ticks_per_tile = 3.0.
  - When: assign_npc(npc_id, building_id, storage_id) is called
  - Then: travel_ticks_total = 9, travel_progress = 0, state = TRAVEL_TO_BUILDING
  - When: ticks_advanced(3) fires 3 times (total 9 ticks)
  - Then: after 3rd fire, travel_progress = 9 >= 9, _npc_arrived_at_building() called, state = WORK_AT_BUILDING
  - Edge cases: distance 0 (building on same tile as NPC) → travel_ticks_total = 0, instant transition to WORK_AT_BUILDING; distance 10 → travel_ticks_total = 30; distance 20 → travel_ticks_total = 60 (20% of a day); ticks_per_tile = 1.0 (minimum) → travel_ticks_total = 3; ticks_per_tile = 10.0 (maximum) → travel_ticks_total = 30

**AC-6**: Operator NPC task cycle (no storage travel)
  - Given: NPC assigned to Lumber Camp at (10,10) as operator. Home base at (10,20). Manhattan distance NPC→building = 10.
  - When: assign_npc() called
  - Then: state = TRAVEL_TO_BUILDING, travel_ticks_total = 30, travel_progress = 0
  - When: 30 ticks advance
  - Then: state = WORK_AT_BUILDING
  - When: production cycle completes (production_output_ready emitted by BuildingRegistry)
  - Then: operator NPC stays in WORK_AT_BUILDING — does NOT transition to TRAVEL_TO_STORAGE. The Transportation System's carrier NPC handles output pickup independently.
  - When: release_npc() called on operator
  - Then: state = RETURN_TO_BASE, travel_ticks_total = 30 (building→home), travel_progress = 0
  - When: 30 ticks advance
  - Then: state = IDLE, position = home_base, assigned_building_id = null

**AC-3**: Task assignment starts travel
  - Given: NPC in IDLE state, building with free slot at (15, 5)
  - When: player assigns NPC to building, providing storage_id
  - Then: NPC state = TRAVEL_TO_BUILDING, travel_ticks_total = manhattan(NPC.position, (15,5)) × 3.0, travel_progress = 0, assigned_building_id = building_id, assigned_storage_id = storage_id, npc_assigned signal emitted
  - Edge cases: NPC not in IDLE state → AssignmentResult.INVALID_NPC_STATE; building has no free slots → AssignmentResult.INVALID_NPC_STATE (BuildingRegistry rejects); null building_id → INVALID_NPC_STATE

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/npc_system/task_cycle_travel_work_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (NPCs must be recruited before they can be assigned)
- Unlocks: Story 003 (deposit/waiting requires travel and work to complete first)
