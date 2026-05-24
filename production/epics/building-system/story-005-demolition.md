# Story 005: Demolition

> **Epic**: Building System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration — ADR-0008
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/building-system.md`
**Requirements**:
- `TR-build-002` (4 building types — demolition applies to all types equally)

**ADR Governing Implementation**: ADR-0008: Building Placement and Production System Architecture
**ADR Decision Summary**: Demolition is initiated via `demolish_building(building_id)`. Transitions from any state (CONSTRUCTING, OPERATING, BLOCKED, STALLED) to DEMOLISHED — no intermediate state. The building's PackedScene is destroyed (`queue_free()`). Building is removed from Grid System's BuildingLayer (`grid.remove_building()`). No resource refund (Formula 6 with `refund_rate = 0.00`). All pending production cycles cancelled. Any NPC assigned is released (`release_npc(npc_id)`). Resource tiles beneath building remain cleared. If building was STALLED and holding output internally: held output is discarded (EC-H3). If building was assigned to a storage container that no longer exists (EC-H5 path): container reference cleared, no action needed (building is gone). After demolition: building removed from `all_buildings` array, `building_demolished` signal emitted, `building_state_changed` signal emitted with reason "demolished".

**Engine**: Godot 4.6 | **Risk**: LOW (`queue_free()`, array filtering — stable APIs)
**Engine Notes**: No post-cutoff APIs. `queue_free()` is stable since Godot 1.0. Array filtering for `all_buildings` removal is O(n) but only happens on player action (not tick-driven). `StringName` for building IDs.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/building-system.md`, scoped to this story:*

- [ ] **AC-08** GIVEN a building is in CONSTRUCTING state (e.g., Lumber Camp at 100/200 ticks) WHEN the player demolishes it THEN the building is destroyed, no resources are refunded, and all construction progress is lost
- [ ] **AC-18** GIVEN a building is STALLED holding output (e.g., 3 Wood) WHEN the player demolishes the building THEN the building is destroyed, the held output is discarded (not returned to storage), no resources are refunded, and the building is removed from the registry
- [ ] **AC-19** GIVEN a player initiates demolition on any building via the interaction panel WHEN the player confirms THEN the building is destroyed, no resources are refunded, the assigned NPC is released, and all pending cycles are cancelled
- [ ] **AC-24** GIVEN a production building's storage container is demolished WHEN the container is removed from the Inventory System THEN the building receives the `on_container_removed` signal, enters BLOCKED state, `assigned_container_id` is set to `null`, and the tooltip displays "No storage assigned"

---

## Implementation Notes

*Derived from ADR-0008 Implementation Guidelines:*

**Demolish flow (from ADR-0008):**
```
func demolish_building(building_id: String) -> bool:
    var building := _get_building(building_id)
    if building == null:
        return false

    var building_type := building.type
    var tile := building.tile

    # Step 1: Handle NPC release (if assigned)
    if building.assigned_npc_id != null:
        NPCSystem.release_npc(building.assigned_npc_id)
        building.assigned_npc_id = null

    # Step 2: Handle held output (STALLED buildings only)
    # If STALLED, the held output in stalled_output is discarded (no destination, no refund)
    # This is the consequence per EC-H3: "If the building was STALLED and holding output
    # internally: the held output is discarded."
    if building.state == STALLED:
        building.stalled_output.clear()
        # Note: output is NOT returned to storage — it's discarded with the building

    # Step 3: Cancel any running production cycle
    # Production cycle ticks, accumulated ticks, and npc_spawn_timer are all discarded
    # No explicit cleanup needed — the building is being removed from the array

    # Step 4: Remove from Grid System's BuildingLayer
    GridMap.remove_building(tile)

    # Step 5: Destroy visual scene
    building.destroy_visual()  # calls queue_free() on the PackedScene instance

    # Step 6: Remove from all_buildings array
    all_buildings.erase(building)

    # Step 7: Emit signals
    building.emit_signal("building_demolished", building_id)
    building.emit_signal("building_state_changed", building_id, "DEMOLISHED", "demolished")

    return true
```

**Orphaned container handling (from ADR-0008 signal subscription):**
```
# BuildingRegistry subscribes to InventorySystem.on_container_removed:
func _on_container_removed(container_id: StringName) -> void:
    for building in all_buildings:
        if building.state == DEMOLISHED:
            continue  # skip demolished buildings
        if building.assigned_container_id == container_id:
            # This building's storage was demolished
            building.assigned_container_id = null

            if building.state in [OPERATING, BLOCKED]:
                building.state = BLOCKED
                building.emit_signal("building_blocked", building.building_id, "No storage assigned")
                building.emit_signal("building_container_removed", building.building_id)
                sync_visual_to_state(building)
            # STALLED buildings are unaffected — they don't need a container to hold output
            # (the output is held internally, not in storage)
            # CONSTRUCTING buildings are unaffected — they don't use a container yet
```

**Demolition via interaction (from GDD UI-4):**
```
# The player initiates demolition through the Building Interaction Panel (UI-3).
# UI-4 defines the demolish button:
#   - Only shown for buildings in OPERATING, BLOCKED, or CONSTRUCTING state
#   - Not shown for DEMOLISHED buildings (already gone)
#   - Not shown for Storage types? Actually: GDD Rule 8 says "any building" — storage too.
#   - Confirming demolition requires a confirmation dialog ("Are you sure? No refund.")
#   - The actual demolition logic is in demolish_building(building_id)

# State-specific demolish behavior:
# CONSTRUCTING → DEMOLISHED: construction progress lost, no resource refund
# OPERATING (producing) → DEMOLISHED: running cycle cancelled, inputs consumed are lost
# OPERATING (idle) → DEMOLISHED: no cycle to cancel, just removed
# BLOCKED → DEMOLISHED: no cycle running, building removed
# STALLED → DEMOLISHED: held output discarded, building removed
```

**Deterministic ordering for concurrent demolitions (edge case):**
```
# Demolition is a player-initiated action, not a tick-driven event.
# True concurrent demolitions are impossible in single-player.
# If a player demolishes building A, then building B (in the same frame via rapid clicks),
# the array mutation is sequential: A is removed, then B is removed from the remaining array.
# No race condition possible.
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Placement and construction start (demolition is the reverse; placement cost tracking exists in Story 001's build_cost_table)
- Story 002: Production cycles (this story handles demolition of a production building; the production cycle mechanics themselves are Story 002)
- Story 003: BLOCKED/STALLED state machine (this story handles demolition while in those states; the state transitions to/from BLOCKED/STALLED are Story 003)
- Story 004: NPC assignment (this story releases NPC on demolition; the normal assignment workflow is Story 004)

---

## QA Test Cases

**AC-08**: Demolish CONSTRUCTING building
  - Given: Lumber Camp in CONSTRUCTING state, build_time = 200, accumulated_ticks = 100, build costs (15 Wood + 3 Stone) already deducted from storage
  - When: player confirms demolition
  - Then: state = DEMOLISHED, PackedScene destroyed, building removed from GridMap BuildingLayer, building removed from all_buildings array, no resources refunded (15 Wood + 3 Stone NOT returned), `building_demolished` signal emitted
  - Edge cases: Storage Area (0 build cost, 0 ticks) → demolished instantly, nothing to refund; Residential House at 149/150 ticks → construction progress lost, no refund; demolition at exactly build_time tick (150/150) → if tick fires before demolition, building transitions to OPERATING then is demolished; if demolition fires first, CONSTRUCTING → DEMOLISHED

**AC-18**: Demolish STALLED building with held output
  - Given: Lumber Camp in STALLED state, `stalled_output` = [5 Wood], assigned storage at capacity
  - When: player confirms demolition
  - Then: state = DEMOLISHED, `stalled_output` cleared (discarded, NOT returned to storage), building removed from registry, no resources refunded, `building_demolished` signal emitted
  - Edge cases: STALLED with multiple cycles of held output (`stalled_output` = [10 Wood]) → all discarded; STALLED for extended duration → held output discarded regardless of how long; storage gains capacity after demolition but before next tick → irrelevant (building is gone)

**AC-19**: Full demolition flow — no refund, NPC released
  - Given: Lumber Camp in OPERATING state, NPC assigned, assigned to storage container SA1, production cycle running (50/100 ticks)
  - When: player confirms demolition
  - Then: NPC released (`release_npc` called, NPC becomes unassigned), production cycle cancelled (50/100 ticks lost, inputs already consumed are not refunded), building removed from all_buildings, PackedScene destroyed, `building_demolished` signal emitted, `building_state_changed` signal emitted with reason "demolished"
  - Edge cases: demolition from BLOCKED state → same flow, no running cycle to cancel; demolition from idle OPERATING → no cycle, no held output, just remove; building has no NPC assigned → no release call needed; building has no storage assigned → no orphan handling needed

**AC-24**: Orphaned container reference (storage demolished)
  - Given: Lumber Camp in OPERATING state, assigned to storage container SA1
  - When: player demolishes SA1 (InventorySystem emits `on_container_removed("SA1")`)
  - Then: BuildingRegistry receives signal, iterates all_buildings, finds Lumber Camp with `assigned_container_id == "SA1"`, sets `assigned_container_id = null`, transitions to BLOCKED state, `building_blocked` signal emitted with reason "No storage assigned", yellow indicator shown
  - Edge cases: building in STALLED state with orphaned container → stays STALLED (STALLED buildings hold output internally, don't need container); building in CONSTRUCTING state → unaffected (construction doesn't use a container); building already in BLOCKED state → stays BLOCKED (no state change, but `assigned_container_id` is cleared); building assigned to multiple containers? → not possible (single `assigned_container_id` field); player assigns new storage after orphan → building transitions from BLOCKED back to OPERATING (AC-11 path from Story 003)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/building_system/demolition_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (production cycle mechanics), Story 003 (BLOCKED/STALLED states), Story 004 (NPC assignment — for NPC release on demolition)
- Unlocks: None — demolition is the terminal lifecycle event, no subsequent stories depend on it
