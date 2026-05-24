# Story 004: NPC Assignment and Residential House Production

> **Epic**: Building System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration — ADR-0008
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/building-system.md`
**Requirements**:
- `TR-build-005` (NPC assignment slot per production building; building cannot produce without assigned NPC)

**ADR Governing Implementation**: ADR-0008: Building Placement and Production System Architecture
**ADR Decision Summary**: NPC assignment is bidirectional — both Building Registry and NPC System track it. Canonical record: NPC System (NPCs are the owned resource). Building System queries `get_available_npcs()` to show assignable NPCs and calls `assign_npc(npc_id, building_id)` to make the assignment. On assignment: NPC System validates availability (not already assigned), records canonical assignment, Building Registry updates `assigned_npc_id`. On release: Building Registry clears `assigned_npc_id`, NPC System marks NPC as unassigned. Production buildings cannot start a cycle without NPC — `try_start_production_cycle()` checks `assigned_npc_id != null` before proceeding. Residential House spawns first NPC immediately on construction completion (emits `building_npc_spawn_requested` signal). Second NPC spawns after 1000 ticks (Formula 8), hard-capped at 2. `npc_spawn_timer` resets to 0 on spawn, prevents third spawn by clearing timer without emitting signal.

**Engine**: Godot 4.6 | **Risk**: LOW (signal emission, RPC-like calls to NPC System Autoload)
**Engine Notes**: No post-cutoff APIs. Signal emission (`emit_signal`) is stable since Godot 1.0. StringName for NPC IDs to avoid string comparison overhead.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/building-system.md`, scoped to this story:*

- [ ] **AC-07** GIVEN a production building in OPERATING state WITH an NPC assigned WHEN the next tick cycle fires THEN the building calls `try_start_production_cycle()` which first checks for NPC assignment (`assigned_npc_id != null`), then checks input availability, and only starts the cycle if both conditions are met
- [ ] **AC-08** GIVEN a player selects an available NPC and clicks "Assign NPC" on a production building WHEN the assignment is confirmed THEN `assign_npc(npc_id, building_id)` is called, the NPC System validates the NPC is available, canonical assignment is recorded, Building Registry updates `assigned_npc_id`, and the building transitions from BLOCKED to OPERATING if it was previously blocked due to missing NPC
- [ ] **AC-20** GIVEN a Residential House completes construction and enters OPERATING state WHEN the tick cycle fires THEN it immediately spawns the first NPC (npc_spawn_timer = 0, `building_npc_spawn_requested` signal emitted with npc_count = 1) and begins counting toward the second NPC
- [ ] **AC-21** GIVEN a Residential House has spawned 1 NPC and is in OPERATING state WHEN the npc_spawn_timer reaches 1000 ticks THEN the second NPC spawns (npc_spawn_timer = 0, `building_npc_spawn_requested` signal emitted with npc_count = 2)
- [ ] **AC-24** GIVEN a Residential House has spawned 2 NPCs WHEN the npc_spawn_timer continues advancing past 1000 ticks THEN no third NPC is spawned — the hard cap is enforced, the timer is reset to 0, and no signal is emitted
- [ ] **AC-25** GIVEN a production building is assigned an NPC WHEN the building is later reassigned a DIFFERENT NPC THEN the previous NPC is released (`release_npc` called for old NPC), the old `assigned_npc_id` is cleared, and the new NPC is assigned (`assign_npc` called for new NPC)

---

## Implementation Notes

*Derived from ADR-0008 Implementation Guidelines:*

**NPC assignment flow (from ADR-0008 public API):**
```
func assign_npc(building_id: String, npc_id: StringName) -> AssignmentResult:
    var building := _get_building(building_id)
    if building == null:
        return AssignmentResult.NOT_FOUND

    # Validate NPC is available (canonical check — NPC System owns the truth)
    var npc := NPCSystem.get_npc(npc_id)
    if npc == null:
        return AssignmentResult.INVALID_NPC

    var availability := NPCSystem.is_npc_available(npc_id)
    if not availability:
        return AssignmentResult.ALREADY_ASSIGNED

    # Make canonical assignment in NPC System
    NPCSystem.assign_npc_to_building(npc_id, building_id)

    # Update local reference in Building Registry
    building.assigned_npc_id = npc_id
    building.emit_signal("building_state_changed", building_id, "OPERATING", "NPC assigned")

    # If building was BLOCKED due to missing NPC, transition to OPERATING
    if building.state == BLOCKED:
        building.state = OPERATING
        building.emit_signal("building_unblocked", building_id)

    return AssignmentResult.SUCCESS
```

**try_start_production_cycle() NPC check (from ADR-0008):**
```
func try_start_production_cycle() -> ProductionStartResult:
    # Step 1: Check NPC assignment (required for production buildings)
    if building.type in [LUMBER_CAMP] and assigned_npc_id == null:
        return ProductionStartResult.BLOCKED

    # Step 2: Check input availability via InventorySystem
    var recipe := _get_recipe(building.type)
    var inputs_available := true
    for input in recipe.inputs:
        if not InventorySystem.try_consume(assigned_container_id, input.resource_id, input.quantity):
            # Revert any partial consumes — atomic check
            inputs_available = false
            break

    if not inputs_available:
        return ProductionStartResult.BLOCKED

    # Step 3: Start the cycle
    production_cycle_ticks = 0
    accumulated_ticks = 0  # reset for production cycle tracking
    return ProductionStartResult.SUCCESS
```

**Residential House NPC spawn (from ADR-0008):**
```
# In the tick loop, OPERATING state:
if building.type == RESIDENTIAL_HOUSE and building.state == OPERATING:
    building.npc_spawn_timer += delta

    # First NPC: spawns immediately on construction completion
    if building.npc_count == 0:
        # This should have been handled in CONSTRUCTING -> OPERATING transition
        # (see story-002). But as a safety net:
        building.emit_signal("building_npc_spawn_requested", building.building_id, building.tile, 1)
        building.npc_count = 1
        building.npc_spawn_timer = 0

    # Second NPC: after 1000 ticks
    elif building.npc_count == 1 and building.npc_spawn_timer >= 1000:
        building.emit_signal("building_npc_spawn_requested", building.building_id, building.tile, 2)
        building.npc_count = 2
        building.npc_spawn_timer = 0

    # Hard cap: no third NPC
    elif building.npc_count >= 2:
        building.npc_spawn_timer = 0  # prevent repeated spawns
```

**Release NPC on reassignment (from ADR-0008):**
```
func _reassign_npc(building_id: String, new_npc_id: StringName) -> AssignmentResult:
    var building := _get_building(building_id)
    if building.assigned_npc_id != null:
        # Release old NPC
        NPCSystem.release_npc(building.assigned_npc_id)
        building.assigned_npc_id = null

    # Assign new NPC (same flow as assign_npc)
    return assign_npc(building_id, new_npc_id)
```

**Bidirectional consistency (from ADR-0008):**
```
# The Building Registry stores assigned_npc_id as a REFERENCE.
# The NPC System stores the canonical assignment (npc_id -> building_id mapping).
# Before any NPC-dependent operation, the Building Registry validates:
func _validate_npc_assignment(building_id: String) -> bool:
    var building := _get_building(building_id)
    if building.assigned_npc_id == null:
        return false

    # Cross-check with NPC System (canonical authority)
    var canonical_building := NPCSystem.get_assigned_building(building.assigned_npc_id)
    return canonical_building == building_id
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: Construction completion (this story covers the behavior AFTER a building enters OPERATING; the tick accumulation to reach OPERATING is Story 002)
- Story 003: BLOCKED/STALLED state machine (this story assumes the building is in OPERATING or BLOCKED state and transitions between them; the state machine logic itself is Story 003)
- Story 005: Demolition (this story covers reassignment during normal operation; NPC release via demolition is Story 005)

---

## QA Test Cases

**AC-07**: NPC required for production cycle start
  - Given: Lumber Camp in OPERATING state, NPC assigned (`assigned_npc_id != null`), inputs available
  - When: tick cycle fires, `needs_production_cycle()` returns true
  - Then: `try_start_production_cycle()` checks NPC assignment → passes, checks inputs → passes, cycle starts
  - Edge cases: NPC assigned but inputs missing → BLOCKED (NPC check passes, input check fails); inputs available but no NPC → BLOCKED (NPC check fails immediately, no input deduction attempted)

**AC-08**: Assign NPC via UI
  - Given: Lumber Camp in OPERATING state, `assigned_npc_id == null`, 1 available NPC
  - When: player clicks building → "Assign NPC" → selects available NPC → confirms
  - Then: `assign_npc(npc_id, building_id)` called, NPC System records canonical assignment, Building Registry sets `assigned_npc_id`, if building was BLOCKED it transitions to OPERATING
  - Edge cases: NPC already assigned to another building → returns ALREADY_ASSIGNED, no state change; invalid NPC ID → returns INVALID_NPC; building in STALLED state → can assign NPC but production is blocked by storage, not by NPC (building stays STALLED)

**AC-20**: Residential House first NPC spawn
  - Given: Residential House completes construction at tick T, transitions to OPERATING
  - When: tick T fires (the same tick as the transition)
  - Then: `npc_spawn_timer = 0`, `npc_count = 1`, `building_npc_spawn_requested` signal emitted with npc_count = 1
  - Edge cases: house demolished before tick T processes → first NPC never spawns; house at 149 ticks in CONSTRUCTING, tick T=150 completes construction → first NPC spawns on tick 150

**AC-21**: Residential House second NPC spawn
  - Given: Residential House has 1 NPC, in OPERATING state, `npc_spawn_timer = 0`
  - When: 1000 ticks elapse (`npc_spawn_timer >= 1000`)
  - Then: `building_npc_spawn_requested` signal emitted with npc_count = 2, `npc_spawn_timer = 0`, `npc_count = 2`
  - Edge cases: 999 ticks → no spawn; exactly 1000 ticks → spawns; 1001 ticks → still spawns (condition is >=, not ==); house demolished at tick 999 → second NPC never spawns

**AC-24**: Residential House hard cap at 2 NPCs
  - Given: Residential House has 2 NPCs, `npc_spawn_timer` continues advancing
  - When: `npc_spawn_timer` exceeds 1000 ticks
  - Then: timer reset to 0, no `building_npc_spawn_requested` signal emitted, `npc_count` remains 2
  - Edge cases: 5000 ticks elapsed → still only 2 NPCs; 10000 ticks → still only 2 NPCs; house demolished at any point after 2nd spawn → no error, timer and count are discarded

**AC-25**: NPC reassignment
  - Given: Lumber Camp with NPC_A assigned (`assigned_npc_id = NPC_A`), NPC_B available
  - When: player assigns NPC_B to the building
  - Then: `release_npc(NPC_A)` called, `assigned_npc_id` cleared, `assign_npc(NPC_B, building_id)` called, building in OPERATING state
  - Edge cases: NPC_B already assigned to another building → assignment fails, no change; building in STALLED state → NPC released and new NPC assigned, but building stays STALLED (no NPC-related block)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/building_system/npc_assignment_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (buildings must be in OPERATING state to test NPC assignment), Story 003 (BLOCKED → OPERATING transitions require failed states to exist)
- Unlocks: None directly — but enables the full production loop when combined with Stories 002, 003, and 004
