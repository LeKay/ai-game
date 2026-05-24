# Story 003: Deposit and Storage Coordination

> **Epic**: NPC System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration — ADR-0009
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/npc-system.md`
**Requirements**:
- `TR-npc-005` (Task assignment with storage selection, AC-4 — persistent storage assignment)

**ADR Governing Implementation**: ADR-0009: NPC State Machine and Movement
**ADR Decision Summary**: NPC deposits produced output via `InventorySystem.try_deposit(container_id, resource_id, quantity)`. If storage is full (`FAILED_FULL`), NPC enters WAITING state and remains at the storage building. WAITING NPCs do not advance timers. When `storage_changed` signal fires from InventorySystem (space opened), NPCSystem attempts deposit again. If successful, transitions to RETURN_TO_BASE. If still full, NPC remains WAITING. Building enters STALLED (BuildingSystem) while NPC is waiting. NPC does NOT block other NPCs' pathfinding (abstract entities at VS scope).

**Engine**: Godot 4.6 | **Risk**: LOW (pure GDScript data, signal-based coordination)
**Engine Notes**: No post-cutoff APIs. `storage_changed` signal from InventorySystem. `try_deposit()` return value determines WAITING vs RETURN_TO_BASE transition.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/npc-system.md`, scoped to this story:*

- [ ] **AC-4** GIVEN an NPC is assigned to a building with a specific storage building WHEN the NPC completes production and travels to storage THEN the NPC deposits to that specific storage building, and this assignment persists across all subsequent production cycles until the NPC is reassigned
- [ ] **AC-7** GIVEN a storage building is full WHEN an NPC arrives to deposit output THEN the NPC enters WAITING state (remains at the storage building), the assigned building enters STALLED state, and the NPC immediately attempts deposit on each `storage_changed` signal — depositing and continuing the cycle (RETURN_TO_BASE → IDLE) when space becomes available

---

## Implementation Notes

*Derived from ADR-0009 Implementation Guidelines:*

**Deposit flow (from ADR-0009):**
```
func _npc_arrived_at_storage(npc: NPCInstance) -> void:
    npc.state = TaskState.DEPOSIT

    # Attempt deposit
    var result := inventory.try_deposit(npc.assigned_storage_id, npc.current_output_resource, npc.current_output_amount)
    if result == OK:
        # Deposit successful
        npc_deposit_completed.emit(npc.npc_id, npc.assigned_storage_id)
        npc.state = TaskState.RETURN_TO_BASE
        _start_return_travel(npc)
    elif result == FAILED_FULL:
        # Storage full — enter WAITING
        npc.state = TaskState.WAITING
        npc_storage_full.emit(npc.npc_id, npc.assigned_storage_id)

        # Notify building system — building enters STALLED
        building.on_npc_waiting(npc.assigned_building_id)

func _on_storage_changed(container_id: StringName) -> void:
    # Only check NPCs whose storage was the changed container
    for npc in all_npcs.values():
        if npc.assigned_storage_id == container_id and npc.state == TaskState.WAITING:
            # Attempt deposit
            var result := inventory.try_deposit(container_id, npc.current_output_resource, npc.current_output_amount)
            if result == OK:
                npc.state = TaskState.RETURN_TO_BASE
                npc_deposit_completed.emit(npc.npc_id, container_id)
                # Notify building system — building exits STALLED
                building.on_npc_deposited(npc.assigned_building_id)
                _start_return_travel(npc)
                break  # Only one NPC per storage in WAITING at VS scope (1 slot per building)
            # If still full, NPC remains WAITING — loop continues to next NPC (if any)
```

**Persistent storage assignment (from GDD Rule 3):**
```
# At assignment time, the player selects storage. This is stored on the NPCInstance.
npc.assigned_storage_id = storage_id

# This value persists across ALL production cycles.
# It is ONLY cleared when:
#   - Storage is demolished (_on_container_removed → assignment cleared, NPC returns home)
#   - NPC is reassigned (new assign_npc call sets new storage_id)
#   - NPC is IDLE and player changes assignment (future feature, not required at VS)
#
# OQ-2 Closed: editable only when NPC is IDLE at VS.
```

**WAITING state (from GDD EC-3):**
```
WAITING:
    - NPC remains at the storage building tile
    - No timer advancement (pass in _on_ticks_advanced)
    - No pathfinding impact — NPCs are abstract, not physical obstacles at VS
    - Building enters STALLED (per Building System)
    - When storage_changed fires: immediate retry of try_deposit()
    - On success: RETURN_TO_BASE → IDLE
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: NPC recruitment (NPCs must exist)
- Story 002: Travel and work (travel must complete before deposit)
- Story 004: Demolition of storage clears assignment (storage demolished = container_removed signal — Story 004)

---

## QA Test Cases

**AC-4**: Persistent storage assignment
  - Given: NPC assigned to building at (10,10) with storage_id = "storage_a" at (20,10)
  - When: NPC completes cycle, deposits to storage_a, returns IDLE, reassigns to new building at (5,5) with same storage_id = "storage_a"
  - Then: NPC deposits output to storage_a again (not a different storage)
  - Edge cases: storage demolished → _on_container_removed() clears assigned_storage_id = null, NPC returns home IDLE; NPC reassigned with different storage_id → new storage_id replaces old; NPC in IDLE state — storage assignment retained (not re-asked) until reassigned

**AC-7**: WAITING state when storage full
  - Given: Storage at capacity (0 free slots), NPC assigned to building, NPC arrives at storage to deposit
  - When: inventory.try_deposit(storage_id, resource, amount) returns FAILED_FULL
  - Then: NPC state = WAITING, npc_storage_full signal emitted, building.on_npc_waiting() called (building enters STALLED), no timer advancement while WAITING
  - When: another player action deposits items out of storage (opening a slot), storage_changed(storage_id) signal fires
  - Then: NPCSystem immediately retries try_deposit() on that container; if successful: state = RETURN_TO_BASE, npc_deposit_completed signal emitted, building.on_npc_deposited() called (building exits STALLED), NPC starts travel home; if still full: NPC remains WAITING, loop continues
  - Edge cases: multiple NPCs in WAITING for same storage (if capacity allows) — each attempts deposit in iteration order; NPC at home base when storage_changed fires — no effect (only NPCs in WAITING with matching storage_id react); storage_changed fires during NPC travel — no effect (NPC not yet in DEPOSIT state); storage_changed fires during NPC at building — no effect (NPC not in WAITING state)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/npc_system/deposit_storage_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (travel to storage requires travel mechanics to be implemented)
- Unlocks: Story 004 (disconnection on storage demolition — demolition flow tests WAITING interaction)
