# Story 005: Save/Load Serialization Round-Trip

> **Epic**: Inventory/Storage System
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/inventory-storage-system.md`
**Requirement**: `TR-inv-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0005: Inventory and Item State Machine
**ADR Decision Summary**: `serialize()` returns `Array[_ContainerSnapshot]` containing all container state (slots in index order, containers in container_id alphabetical order) plus all IN_TRANSIT items. `deserialize()` reconstructs containers and resumes transports from remaining_ticks. Schema versioned via `schema_version: int = 1` field on ContainerSnapshot and TransitSnapshot. Save/Load System owns the call — InventorySystem only provides the data.

**Engine**: Godot 4.6 | **Risk**: LOW — no post-cutoff APIs
**Engine Notes**: None. GDScript Dictionary/Array serialization and nested class instances are stable pre-cutoff constructs.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Serializing items in DROPPED state (tile resources are owned by GridMap, not InventorySystem)
- Guardrail: Serialization must be deterministic — slots in index order, containers in container_id alphabetical order

---

## Acceptance Criteria

*From GDD `design/gdd/inventory-storage-system.md`, scoped to this story:*

- [ ] **AC-16**: Given a save-game during an active transport, loading the game restores the transport with correct `remaining_ticks`
- [ ] **AC-16b**: Given a transport whose target container no longer exists after reload, items transition to LOST (not restored, no energy refund)
- [ ] **AC-16c**: Given a transport whose source tile no longer exists after reload, items transition to LOST
- [ ] **AC-16d**: Given all containers across two containers with items in slots, a serialize→deserialize round-trip produces identical slot state (resource_id, quantity, current_charge preserved for every slot)

---

## Implementation Notes

*Derived from ADR-0005 Implementation Guidelines:*

**Snapshot classes (internal to InventorySystem):**
```gdscript
class _ContainerSnapshot:
    var schema_version: int = 1
    var container_id: StringName
    var name: String
    var capacity: int
    var slots: Array  # Array[_SlotSnapshot]

class _SlotSnapshot:
    var resource_id: StringName
    var quantity: int
    var current_charge: float = 0.0  # total charge for all units in slot

class _TransitSnapshot:
    var schema_version: int = 1
    var transit_id: StringName
    var source_tile: Vector2i
    var target_container_id: StringName
    var resource_id: StringName
    var quantity: int
    var remaining_ticks: int
    # energy_cost is re-derivable: stored for completeness
    var energy_cost: int
    var distance: int
```

**serialize() on InventorySystem:**
```gdscript
func serialize() -> Array:
    var result := []

    # Containers: alphabetical by container_id for determinism
    var sorted_ids := _containers.keys()
    sorted_ids.sort()
    for id in sorted_ids:
        var c: InventoryContainer = _containers[id]
        var snap := _ContainerSnapshot.new()
        snap.container_id = c.container_id
        snap.name = c.name
        snap.capacity = c.capacity
        # Slots in index order
        snap.slots = []
        for i in range(c.slots.size()):
            var slot: InventorySlot = c.slots[i]
            var ss := _SlotSnapshot.new()
            ss.resource_id = slot.resource_id
            ss.quantity = slot.quantity
            ss.current_charge = slot.current_charge
            snap.slots.append(ss)
        result.append(snap)

    # IN_TRANSIT items
    for transit in _transits.values():
        var ts := _TransitSnapshot.new()
        ts.transit_id = transit.transit_id
        ts.source_tile = transit.source_tile
        ts.target_container_id = transit.target_container_id
        ts.resource_id = transit.resource_id
        ts.quantity = transit.quantity
        ts.remaining_ticks = transit.remaining_ticks
        ts.energy_cost = transit.energy_cost
        ts.distance = transit.distance
        result.append(ts)

    return result
```

**deserialize() on InventorySystem:**
```gdscript
func deserialize(snapshots: Array) -> void:
    _containers.clear()
    _transits.clear()

    for snap in snapshots:
        if snap is _ContainerSnapshot:
            var c := InventoryContainer.new()
            c.container_id = snap.container_id
            c.name = snap.name
            c.capacity = snap.capacity
            c.slots = []
            for ss in snap.slots:
                var slot := InventorySlot.new()
                slot.resource_id = ss.resource_id
                slot.quantity = ss.quantity
                slot.current_charge = ss.current_charge
                c.slots.append(slot)
            _containers[c.container_id] = c

        elif snap is _TransitSnapshot:
            # Validate target container exists
            if not _containers.has(snap.target_container_id):
                # Target container gone → LOST
                emit_signal("transport_failed", snap.transit_id)
                continue
            # Source tile validation is caller's responsibility (GridMap not available here)
            # GridMap must call validate_transit_source() after deserialize()
            var transit := TransitItem.new()
            transit.transit_id = snap.transit_id
            transit.source_tile = snap.source_tile
            transit.target_container_id = snap.target_container_id
            transit.resource_id = snap.resource_id
            transit.quantity = snap.quantity
            transit.remaining_ticks = snap.remaining_ticks
            transit.energy_cost = snap.energy_cost
            transit.distance = snap.distance
            _transits[transit.transit_id] = transit
```

**Source tile validation** (post-deserialize, called by Save/Load System coordination layer):
```gdscript
func validate_transit_source(transit_id: StringName, source_exists: bool) -> void:
    if not source_exists:
        var transit := _transits.get(transit_id, null)
        if transit != null:
            _transits.erase(transit_id)
            emit_signal("transport_failed", transit_id)
```

**Key design invariants:**
- DROPPED items are NOT serialized — they live in GridMap, which owns tile state
- Serialization order is deterministic: containers alphabetically, slots by index
- `schema_version = 1` on ContainerSnapshot and TransitSnapshot — deserializer must check and reject unknown versions
- Energy is NOT refunded if transit is lost on reload (EC-H3: non-interruptible transport)
- `deserialize()` performs a full replace — clears existing state before reconstructing
- `_next_transit_id` counter must be restored to `max(existing transit IDs) + 1` to avoid ID collisions after reload

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Container structure (slot arrays must exist before serialization)
- Story 002: `try_deposit()` — transport completion uses it, but load restores via direct slot assignment (not deposit)
- Story 003: IN_TRANSIT state machine (transit state is created here by deserializing, but the state machine transitions are Story 003's responsibility)
- The Save/Load System itself — that system calls `serialize()`/`deserialize()`; InventorySystem only provides the data

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-16**: Round-trip preserves IN_TRANSIT remaining_ticks
  - Given: Container "sa1" exists; transport "transit_1" is active with `remaining_ticks = 20`, `resource_id = "wood"`, `quantity = 5`, `target_container_id = "sa1"`
  - When: `serialize()` called, then `deserialize(result)` called
  - Then: `_transits["transit_1"]` exists with `remaining_ticks == 20`, `resource_id == "wood"`, `quantity == 5`

- **AC-16b**: Missing target container on reload → LOST
  - Given: `_TransitSnapshot` references `target_container_id = "sa_missing"` which is NOT in the container snapshots
  - When: `deserialize(snapshots)` called
  - Then: transit is NOT added to `_transits`; `transport_failed` signal fires with transit_id; no items appear in any container

- **AC-16c**: Source tile validation → LOST
  - Given: Transit "transit_2" deserialized successfully; `validate_transit_source("transit_2", false)` called (source tile gone)
  - When: `validate_transit_source()` runs
  - Then: `_transits` does not contain "transit_2"; `transport_failed` fires

- **AC-16d**: Container slot round-trip fidelity
  - Given: Container "sa1" with 3 occupied slots: `{resource_id="axe", qty=1, current_charge=47.0}`, `{resource_id="wood", qty=50, current_charge=5000.0}`, `{resource_id="", qty=0, current_charge=0.0}` (empty)
  - When: `serialize()` then `deserialize()`
  - Then: all 3 slots restored in correct index order with matching resource_id, quantity, and current_charge; empty slot remains empty

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/inventory/inventory_save_load_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (container structure), Story 002 must be DONE (slot mutation patterns), Story 003 must be DONE (IN_TRANSIT state and TransitItem class must exist)
- Unlocks: Save/Load System stories (which call `InventorySystem.serialize()` as part of the full game save)
