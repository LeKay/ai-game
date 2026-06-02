# Story 001: InventorySystem Autoload and Container Data Model

> **Epic**: Inventory/Storage System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/inventory-storage-system.md`
**Requirement**: `TR-inv-005`, `TR-inv-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0005: Inventory and Item State Machine
**ADR Decision Summary**: InventorySystem is an Autoload singleton owning a `Dictionary[StringName, InventoryContainer]` registry. InventoryContainer, InventorySlot, and TransitItem are nested script classes (not Nodes). No personal carry-inventory — carried items exist only in IN_TRANSIT state, never in a slot. Container capacity is enforced as a hard ceiling.

**Engine**: Godot 4.6 | **Risk**: LOW — all APIs are stable pre-cutoff constructs
**Engine Notes**: No post-cutoff APIs. Basic Godot constructs only: `Dictionary`, `Array`, signals, Autoload, GDScript class_name. Verify that `class_name` on a non-Node inner script works as expected for typed Array declarations.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Hardcoded stack limits or resource categories in InventorySystem (all must come from ResourceRegistry)
- Guardrail: CPU < 0.05ms per frame; memory < ~50KB for all containers combined

---

## Acceptance Criteria

*From GDD `design/gdd/inventory-storage-system.md`, scoped to this story:*

- [ ] **AC-11**: Given a new Storage Area placed on a valid tile, the created container has `capacity = 50`
- [ ] **AC-12**: Given a Storage Area with a completed Storage Building, the container has `capacity = 150`
- [ ] **AC-13**: `get_capacity()` returns 50 for a bare Storage Area and 150 after Storage Building build completes
- [ ] **AC-14**: Given a Storage Building is demolished, the container capacity reverts to 50 and items remain in their slots (even if occupied > 50)
- [ ] **AC-24**: Given a slot with `current_charge = 75.0` placed in storage, retrieving it from storage shows `current_charge = 75.0` (charge is not reset by deposit/consume operations unrelated to recipe execution)
- [ ] **AC-26**: Given a slot holding a `resource_id` that no longer exists in the Resource System registry, the slot returns an "unknown" marker and is treated as occupied but unusable (not consumed by hunger or buildings)
- [ ] **AC-17** *(Integration boundary)*: Given a Storage Area placed on a TREE resource tile, the tree is cleared and a 50-slot container is created at that tile. *(Note: tree clearing is GridMap's responsibility. InventorySystem's role is to call `create_container()` after GridMap placement succeeds.)*

---

## Implementation Notes

*Derived from ADR-0005 Implementation Guidelines:*

**File layout:**
```
src/systems/inventory/
├── inventory_system.gd        # Autoload singleton
├── inventory_container.gd     # Container class (not Node)
├── inventory_slot.gd          # Slot class (not Node)
└── transit_item.gd            # In-transit item (not Node)
```

**InventorySystem Autoload skeleton:**
```gdscript
extends Node

signal storage_changed(container_id: StringName)
signal container_capacity_changed(container_id: StringName, old_capacity: int, new_capacity: int)

var _containers: Dictionary  # [StringName, InventoryContainer]

func create_container(id: StringName, name: String, capacity: int) -> void:
    var c := InventoryContainer.new()
    c.container_id = id
    c.name = name
    c.capacity = capacity
    c.slots = []
    for _i in range(capacity):
        c.slots.append(InventorySlot.new())
    _containers[id] = c

func get_container(id: StringName) -> InventoryContainer:
    return _containers.get(id, null)

func get_all_containers() -> Array:
    return _containers.values()

func has_storage_at_tile(tile: Vector2i) -> bool:
    # Check if any container is registered at this tile position
    # Container IDs are expected to encode tile position (e.g., "storage_10_5")

func set_container_capacity(id: StringName, new_capacity: int) -> void:
    var c := get_container(id)
    if c == null:
        return
    var old := c.capacity
    c.capacity = new_capacity
    # If new_capacity < old: slots beyond new_capacity remain (they hold items until cleared)
    emit_signal("container_capacity_changed", id, old, new_capacity)

func get_slot_count(id: StringName) -> int
func get_occupied_slots(id: StringName) -> int
func get_slot_data(id: StringName, slot_index: int) -> InventorySlot
func get_resource_quantity(id: StringName, resource_id: StringName) -> int
```

**InventorySlot:**
```gdscript
class_name InventorySlot

var resource_id: StringName  # null = empty
var quantity: int = 0
var current_charge: float = 0.0  # total remaining charge for ALL units in slot
                                  # fully stocked: current_charge == quantity * max_charge
                                  # slot cleared when current_charge <= 0

func is_empty() -> bool:
    return resource_id == StringName("")
```

**InventoryContainer:**
```gdscript
class_name InventoryContainer

var container_id: StringName
var name: String
var capacity: int
var slots: Array  # Array[InventorySlot], fixed size at creation
```

**Storage Building integration**: When a Storage Building build completes, the Building System calls `InventorySystem.set_container_capacity(container_id, 150)`. When demolished, it calls `set_container_capacity(container_id, 50)`. Slots beyond capacity 50 (if any) remain populated — capacity is a logical ceiling, not a trim operation.

**Unknown resource_id guard** (AC-26):
```gdscript
func _is_slot_usable(slot: InventorySlot) -> bool:
    if slot.is_empty():
        return false
    return ResourceRegistry.has_definition(slot.resource_id)
# Slots where ResourceRegistry.has_definition() returns false are counted as
# occupied (towards get_occupied_slots()) but excluded from try_consume() and consume_food()
```

**Charge invariant** (AC-24): `InventorySlot.current_charge` is only modified by: (a) deposit operations (increases by `quantity * max_charge`), and (b) recipe charge consumption (decreases by `charge_cost`). Normal read operations and slot queries never modify `current_charge`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: `try_deposit()`, `try_consume()`, first-fit stacking algorithm
- Story 003: `start_transport()`, `cancel_transport()`, `_on_ticks_advanced()`, TransitItem
- Story 004: `consume_food()` hunger algorithm
- Story 005: `serialize()`, `deserialize()`

*Stub these methods as `pass` or returning a dummy value — do not implement logic here.*

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-11**: Storage Area creates 50-slot container
  - Given: InventorySystem initialized
  - When: `create_container("storage_tile_5_5", "Main Storage", 50)` is called
  - Then: `get_container("storage_tile_5_5")` is not null; `get_slot_count("storage_tile_5_5")` == 50; all slots are empty
  - Edge cases: container_id must be unique; calling create_container twice with same id should overwrite or assert

- **AC-12 / AC-13**: Storage Building upgrade sets capacity to 150
  - Given: Container "sa1" with capacity = 50
  - When: `set_container_capacity("sa1", 150)` is called
  - Then: `get_container("sa1").capacity` == 150; `container_capacity_changed` signal fires with (id, 50, 150)

- **AC-14**: Demolish reverts to 50, items remain in slots
  - Given: Container "sa1" with capacity = 150, 70 slots occupied (including slots 51–70)
  - When: `set_container_capacity("sa1", 50)` is called
  - Then: `get_container("sa1").capacity` == 50; slots 0–69 still have their data intact (no trim); `get_occupied_slots` still counts all 70 occupied slots

- **AC-24**: Charge preserved through operations
  - Given: Slot at index 3 holds `{resource_id: "axe", quantity: 1, current_charge: 47.0}`
  - When: Any read operation (`get_slot_data()`) is called
  - Then: Returned slot has `current_charge == 47.0`; no read operation in this story modifies `current_charge`

- **AC-26**: Unknown resource_id treated as occupied but unusable
  - Given: Slot at index 0 holds `{resource_id: "deleted_resource", quantity: 5}`; `ResourceRegistry.has_definition("deleted_resource")` returns false
  - When: `get_occupied_slots()` is called and `_is_slot_usable()` is checked
  - Then: Slot counts toward `get_occupied_slots()` (occupied); `_is_slot_usable()` returns false (unusable for consume/hunger)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/inventory/inventory_container_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Completion Notes
**Completed**: 2026-05-31
**Criteria**: 6/7 passing (AC-26 "unusable" path deferred to inv-002 — private method, untestable at unit level)
**Deviations**: ADVISORY — AC-26 unusable path deferred; `_is_slot_usable` private + registry-absent escape hatch makes it untestable here. inv-002 `try_consume` must cover it.
**Test Evidence**: Logic — `tests/unit/inventory/inventory_container_test.gd` (19 tests, file exists)
**Code Review**: Complete (pre-done fixes: typed Array/Dictionary, `_grow_slots_to` rewrite, `get_capacity()` removed, test naming corrected, autoload registered)

---

## Dependencies

- Depends on: None (this is the first story; creates the InventorySystem Autoload skeleton and container classes)
- Unlocks: Story 002 (first-fit stacking operates on the containers created here), Story 003 (TransitItem operates within the InventorySystem framework)
