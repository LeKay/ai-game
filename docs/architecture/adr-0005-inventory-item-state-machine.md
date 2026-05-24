# ADR-0005: Inventory and Item State Machine

## Status

Accepted

## Date

2026-05-13

## Last Verified

2026-05-13

## Decision Makers

Technical Director, Lead Programmer, Game Designer (inventory mechanics)

## Summary

Defines the InventorySystem Autoload singleton as the authoritative owner of all inventory state — InventoryContainer slot arrays, DROPPED/IN_TRANSIT/STORED/LOST item state machine, first-fit stacking algorithm, and tick-based transport timers. Provides read-only query APIs for Building System, Hunger System, and HUD. Uses a Dictionary[StringName, InventoryContainer] registry indexed by container_id for O(1) lookups. No personal carry-inventory: carried items exist only in IN_TRANSIT state on the player character, never in a slot.

**Transport model (updated):** Production output is no longer deposited directly by the Building System. It is deposited by carrier NPCs (Transportation System) that call `try_deposit()` after picking up output from the building's `buffered_output` via `BuildingRegistry.collect_output()`. This means `try_deposit()` is called with the full `base_output` quantity — distance no longer reduces the deposited amount. Input wares are delivered to the building's input buffer via `BuildingRegistry.deliver_input()` — the carrier draws from storage via `try_consume()` and hands the items to the building. The Building System never calls `try_deposit()` directly for production output.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | LOW — basic Godot constructs (dictionaries, arrays, signals, autoloads) covered pre-cutoff |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
 **Depends On**  ADR-0001 (tick signal subscription — inventory must receive `ticks_advanced`), ADR-0002 (resource registry — inventory reads `stack_limit`, `max_charge`, `category` via `ResourceRegistry.get_definition()`), ADR-0004 (grid map — inventory queries `get_tile_drop()` for DROPPED items and `validate_placement()` for Storage Area placement)
| **Enables** | Building System stories (storage consumption), Production System stories (input/output flow), Hunger System stories (food consumption), Save/Load System (inventory serialization) |
| **Blocks** | Any story that reads or writes inventory state — all inventory-dependent stories are blocked until this ADR is Accepted |
| **Ordering Note** | Must be implemented after ADR-0001, ADR-0002, ADR-0004 but can be developed in parallel with Building System and Hunger System GDDs since interfaces are stable |

## Context

### Problem Statement

The Inventory/Storage GDD defines a rich state machine and spatial inventory model but no architectural decision governs how this state is owned, accessed, and mutated at the engine level. Without this decision, different programmers may choose different architectures (per-container nodes vs. centralized Autoload), leading to integration conflicts. The InventorySystem is queried by Building System (resource consumption), Production System (input/output), Hunger System (daily food deduction), HUD (storage display), and Save/Load System (serialization) — all of which need a consistent, well-defined interface.

### Constraints

- Must follow the Autoload singleton pattern established by ADR-0001 (TickSystem), ADR-0002 (ResourceRegistry), and ADR-0003 (InputContext)
- All resource metadata must come from ResourceRegistry (ADR-0002) — no hardcoded stack limits or categories
- Tile-drop queries go through GridMap (ADR-0004) — never read from TileMapLayer
- Must subscribe to TickSystem.ticks_advanced signal for IN_TRANSIT timer decrement
- All public methods must be unit-testable — dependency injection over Autoload coupling where possible
- Must use GDScript 2.0 static typing (typed Array, typed Dictionary, nullable types)

### Requirements

- **TR-inv-001**: InventoryContainer with first-fit stacking algorithm
- **TR-inv-002**: Resource state machine — DROPPED → IN_TRANSIT → STORED/LOST
- **TR-inv-003**: Transport energy/tick cost formulas
- **TR-inv-004**: Hunger consumption priority — lowest-quantity storage bin first
- **TR-inv-005**: Storage Area (50 slots) + Storage Building (150 slots)
- **TR-inv-006**: Items only consumed from STORED state

## Decision

### Architecture: Autoload Singleton with Dictionary-Indexed Containers

The InventorySystem is an Autoload singleton that owns a `Dictionary[StringName, InventoryContainer]` registry. Each InventoryContainer is a nested script class with fixed capacity, slot array, and transport tracking. The Autoload provides query and mutation methods that Building System, Hunger System, and HUD call.

```
┌─────────────────────────────────────────────┐
│              InventorySystem (Autoload)       │
│                                              │
│  _containers: Dictionary[StringName,         │
│                InventoryContainer]            │
│                                              │
│  + create_container(id, name, capacity)      │
│  + get_container(id) -> InventoryContainer?   │
│  + get_all_containers() -> Array[...]         │
│  + try_deposit(container_id, ...) -> Result   │
│  + try_consume(container_id, ...) -> Result   │
│  + consume_food(daily_requirement) -> Result  │
│  + start_transport(source, target, qty)      │
│  + advance_tick()                            │
│  + serialize() -> Array[ContainerSnapshot]    │
│  + deserialize(snapshots)                     │
│                                              │
│  signals:                                    │
│    storage_changed(container_id)              │
│    transport_started(item_data)               │
│    transport_completed(item_data)             │
│    transport_failed(item_data)                │
│    container_capacity_changed(id, old, new)   │
└──────────┬──────────────────┬────────────────┘
           │                  │
    ┌──────┴──────┐    ┌─────┴──────┐
    │Inventory     │    │Inventory    │
    │Container     │    │TransitItem  │
    │(per-storage) │    │(per-transport)│
    └─────────────┘    └─────────────┘
```

### Key Interfaces

```gdscript
## InventorySystem.gd — Autoload singleton
extends Node

signal storage_changed(container_id: StringName)
signal transport_started(transit_id: StringName)
signal transport_completed(transit_id: StringName)
signal transport_failed(transit_id: StringName)
signal container_capacity_changed(container_id: StringName, old_capacity: int, new_capacity: int)

# Container lifecycle
func create_container(id: StringName, name: String, capacity: int) -> void
func get_container(id: StringName) -> InventoryContainer?
func get_all_containers() -> Array[InventoryContainer]
func has_storage_at_tile(tile: Vector2i) -> bool

# Deposit (transport completion / building output)
enum DepositResult { SUCCESS, FAILURE_FULL, FAILURE_NO_CONTAINER }
func try_deposit(container_id: StringName, resource_id: StringName, quantity: int) -> DepositResult

# Consumption (building inputs / hunger)
enum ConsumeResult { SUCCESS, FAILURE_INSUFFICIENT, FAILURE_NO_CONTAINER }
func try_consume(container_id: StringName, resource_id: StringName, quantity: int) -> ConsumeResult
func consume_food(daily_requirement: int) -> FoodConsumptionResult

# Transport
func start_transport(source_tile: Vector2i, target_container_id: StringName, quantity: int) -> StringName
func cancel_transport(transit_id: StringName) -> void
func get_in_transit(transit_id: StringName) -> TransitItem?

# Queries (for HUD / building preview)
func get_slot_count(container_id: StringName) -> int
func get_occupied_slots(container_id: StringName) -> int
func get_slot_data(container_id: StringName, slot_index: int) -> SlotData?
func get_resource_quantity(container_id: StringName, resource_id: StringName) -> int

# Serialization
func serialize() -> Array[_ContainerSnapshot]
func deserialize(snapshots: Array[_ContainerSnapshot]) -> void

# Internal (called by _process and tick subscriber)
func _process(delta: float) -> void
func _on_ticks_advanced(delta_ticks: int) -> void

# Snapshot classes for typed serialization
class _ContainerSnapshot:
    var schema_version: int = 1
    var container_id: StringName
    var name: String
    var capacity: int
    var slots: Array[_SlotSnapshot]

class _SlotSnapshot:
    var resource_id: StringName  # null = empty
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
```

```gdscript
## inventory_container.gd — Nested script class (not a Node)
class_name InventoryContainer

# Capacity enforced by create_container() input — no internal cap.
# Max 150 for vertical slice (Storage Area 50 + Storage Building 100).

var container_id: StringName
var name: String
var capacity: int
var slots: Array[InventorySlot]  # size == capacity, fixed at creation

func try_deposit(resource_id: StringName, quantity: int) -> DepositResult
func try_consume(resource_id: StringName, quantity: int) -> ConsumeResult
func _first_fit_allocate(resource_id: StringName, quantity: int, stack_limit: int) -> Array[SlotAllocation]
func get_occupied_count() -> int
func is_full() -> bool
```

```gdscript
## inventory_slot.gd — Plain script class (not a Node, not a Resource)
class_name InventorySlot

var resource_id: StringName  # null = empty slot
var quantity: int = 0
var current_charge: float = 0.0  # total remaining charge for ALL units in slot
                                  # fully stocked: current_charge == quantity * max_charge
                                  # slot cleared when current_charge <= 0

func is_empty() -> bool:
    return resource_id == null
```

```gdscript
## slot_allocation.gd — Plain script class (not a Node, not a Resource)
class_name SlotAllocation

var slot_index: int
var quantity_added: int

func copy(p_slot_index: int, p_quantity: int) -> SlotAllocation:
    var a := SlotAllocation.new()
    a.slot_index = p_slot_index
    a.quantity_added = p_quantity
    return a
```

```gdscript
## transit_item.gd — Plain script class (not a Node, not a Resource)
class_name TransitItem

var transit_id: StringName
var source_tile: Vector2i
var target_container_id: StringName
var resource_id: StringName
var quantity: int
var remaining_ticks: int
var energy_cost: int
var distance: int

func is_ready() -> bool:
    return remaining_ticks <= 0
```

### State Machine: Item States

```
┌─────────┐    manual harvest     ┌──────────┐
│  DROPPED │ ───────────────────> │ IN_TRANSIT│
│  (tile)  │                    │  (carrying)│
└─────────┘                    └─────┬──────┘
     │                               │
     │ building placed on tile       │ transport completes
     │ or player drop                ▼
     ▼                    ┌───────────┐      success     ┌────────┐
   LOST  <─────────────── │  STORED   │ ───────────────> │ STORED │
   (tile gone / cancel)   │           │                   │(container)
                        └───────────┘
                             │
                     transport fails (energy
                     insufficient at arrival)
                             │
                             ▼
                        ┌───────────┐
                        │  LOST     │
                        │(items lost)│
                        └───────────┘
```

**State rules:**
- **DROPPED** — Item exists on a grid tile. Visible as pile sprite. Accessible only via `InventorySystem.get_tile_drop()` or player click initiation. Managed by GridMap (tile resource layer).
- **IN_TRANSIT** — Player is carrying item. Not in any container. Tracked by InventorySystem transit registry. Decrementing `remaining_ticks` each tick via `_on_ticks_advanced()`. Player is occupied — cannot perform other actions.
- **STORED** — Item in an InventoryContainer slot. Accessible to all consumers (Building, Hunger, Production). This is the only state from which items can be consumed.
- **LOST** — Item removed from game. No visual representation. Caused by: building placed on dropped tile, source tile cleared, destination container destroyed mid-transit, insufficient energy at transport arrival.

### First-Fit Stacking Algorithm

```
func _first_fit_allocate(resource_id: StringName, quantity: int, stack_limit: int, max_charge: float) -> Array[SlotAllocation]:
    var remaining = quantity
    var allocations: Array[SlotAllocation] = []

    # Phase 1: Extend existing matching slots
    for i in range(capacity):
        if remaining == 0:
            break
        if slots[i].resource_id == resource_id and slots[i].quantity < stack_limit:
            var fill_space = stack_limit - slots[i].quantity
            var add = min(remaining, fill_space)
            slots[i].quantity += add
            slots[i].current_charge += add * max_charge  # new items always fully charged
            remaining -= add
            allocations.append(SlotAllocation.new().copy(i, add))

    # Phase 2: Fill empty slots
    for i in range(capacity):
        if remaining == 0:
            break
        if slots[i].is_empty():
            var fill = min(remaining, stack_limit)
            slots[i].resource_id = resource_id
            slots[i].quantity = fill
            slots[i].current_charge = fill * max_charge  # initialize fully charged
            remaining -= fill
            allocations.append(SlotAllocation.new().copy(i, fill))

    if remaining > 0:
        return []  # FAILURE — no slots remaining
    return allocations
```

**Guarantees:**
- No partial deposit: if the algorithm cannot place all `quantity` items, it returns FAILURE and the ENTIRE batch is returned to source
- Stack limits enforced per-slot by ResourceRegistry (never hardcoded)
- Newly deposited items always start at full charge (`current_charge += quantity * max_charge`)
- Slot indices strictly ascending (first-fit ordering)
- No slot holds mixed resource types

### Transport Cost Formulas (from GDD)

```
energy_cost = (2 × quantity) + (1 × distance_to_storage)
time_cost   = 5 × distance_to_storage
```

Costs are computed at transport initiation (preview) and deducted at completion. If energy is insufficient at arrival, transport fails, items return to source tile (become DROPPED), no energy deducted.

### Container Modification Order

All modifications processed in deterministic order each tick cycle (per GDD EC-H5):
1. Hunger consumption (highest priority)
2. Building withdrawals (container_id ascending, then building_id)
3. Transport deposits (remaining_ticks = 0 order)
4. Day-transition events (lowest priority)

This ordering is enforced by the TickSystem signal dispatch order and InventorySystem's internal processing pipeline in `_on_ticks_advanced()`.

## Alternatives Considered

### Alternative 1: Per-Container Node Instances

Each Storage Area is its own Node2D with an InventoryComponent script attached. The scene hierarchy owns containers naturally.

- **Pros**: Natural Godot ownership model. Each container is a spatial object with position. Easier to add container-specific signals.
- **Cons**: Container is data, not a spatial object — it has no direct visual representation beyond the storage building sprite. Querying "all containers on map" requires scene traversal or an external registry anyway. Breaks consistency with ADR-0001/0002/0003 pattern. Harder to serialize (must traverse scene tree).
- **Rejection Reason**: The Autoload pattern is already established by 3 prior ADRs. Per-container nodes would add scene hierarchy complexity for a data structure that has no spatial behavior. The Dictionary[StringName, Container] approach is simpler, more testable, and more consistent.

### Alternative 2: Personal Carry-Inventory

Player has a personal inventory (like RPG-style backpack) separate from storage containers. Dropped items go into personal inventory first, then can be moved to storage.

- **Pros**: Familiar RPG pattern. Player can carry multiple items simultaneously without energy tradeoff.
- **Cons**: Directly contradicts GDD Rule 6 ("The player has no carry-inventory. Carried items exist in IN_TRANSIT state only"). The entire "burden of distance" fantasy relies on the player having NO persistent storage for carried items. Adding personal inventory breaks the core design tension.
- **Rejection Reason**: The GDD explicitly defines NO personal carry-inventory. This is a design-level (not technical) decision. The technical architecture must reflect the defined design.

### Alternative 3: Entity-Component (Tile as Entity)

Tile-drop resources are independent entities on the grid with their own state, position, and lifecycle. A component system manages state transitions.

- **Pros**: Scales to large numbers of items. Natural fit for multi-item tile drops. Entity system could manage lifecycle.
- **Cons**: Over-engineered for VS scope (typically 1-3 items per tile). Godot has no built-in ECS for GDScript. Would require a custom implementation or GDExtension. Violates the "no native extensions unless necessary" principle (no GDExtension approved yet).
- **Rejection Reason**: Tile-drop items are simple data — resource_id + quantity on a tile. They don't need entity overhead. GridMap already owns the tile layer; inventory observes it. Lightweight resource classes are sufficient.

## Consequences

### Positive

- Single authoritative source for inventory state — no ambiguity about which system "owns" container data
- Consistent with established Autoload pattern (TickSystem, ResourceRegistry, InputContext)
- Dictionary[StringName, InventoryContainer] provides O(1) lookups by container_id
- Nested script classes (InventoryContainer, InventorySlot, TransitItem) are lightweight — no Node overhead
- Transparent query API enables HUD polling and building preview without coupling
- Signal-based notifications (storage_changed, transport_started/completed/failed) enable reactive UI updates without polling
- Deterministic modification order prevents race conditions between Hunger, Building, and Transport

### Negative

- Autoload singleton introduces a global dependency — InventorySystem is accessible from anywhere, which can encourage loose coupling
- Serialization of Autoload state requires explicit serialize()/deserialize() methods — not automatic like scene-tree nodes
- All containers live in one Dictionary — no spatial partitioning. For VS (<5 containers total) this is fine, but the design doesn't support thousands of containers without scanning

### Neutral

- InventorySlots are resource classes, not nodes — they can't be inspected in the scene tree debugger. Trade-off between performance and debuggability.
- Transport items tracked in-memory only during IN_TRANSIT — no scene representation. Player visibility is through HUD, not the scene graph.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Autoload lifecycle issues (ready() called before dependent systems) | Low | High | Document Autoload load order in ADR-0001 or technical-preferences. Use _ready() guards to verify dependencies exist before processing signals. |
| Large deposits exceeding stack_limit split across many slots | Medium | Low | First-fit algorithm handles splits correctly. Only risk is performance on containers with hundreds of slots (150 max for VS — negligible). |
| Missing resource_id in registry (EC-L2) causing null lookups | Low | Medium | Defensive guard: if ResourceRegistry.get_definition() returns null, mark slot as "unknown" — don't crash. Slot treated as occupied but unusable. |
| Transport cancellation during _process tick | Low | Low | Cancelled transports revert source tile before tick processing. Energy not deducted. Deterministic ordering prevents race. |
| Serialization drift if new fields added to InventorySlot | Medium | High | Version the serialized format with a schema_version field. Deserializer must handle version mismatch gracefully. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (frame time) | 0ms | 0.05ms | 0.5ms — Dictionary lookups are O(1), slot scan bounded by 150 (max capacity). `_process()` only handles transit timer countdown (typically 0-2 active transports). |
| Memory | 0MB | ~50KB | Negligible — Dictionary of typed resource classes. Each container: 150 slots × ~64 bytes = ~10KB. 5 containers = ~50KB total. |
| Load Time | 0ms | 1ms | One-time deserialization on game start. Minimal. |
| Network | N/A | N/A | Single-player only. |

## Migration Plan

1. Create `InventorySystem.gd` as Autoload — no prior code to migrate. This is a greenfield system.
2. Create nested script classes: `inventory_container.gd`, `inventory_slot.gd`, `transit_item.gd` in `src/systems/inventory/`
3. Implement first-fit stacking and transport state machine per ADR specification
4. Wire up TickSystem signal subscription: `InventorySystem.connect("ticks_advanced", _on_ticks_advanced)` (connected via Autoload ready callback)
5. Wire up ResourceRegistry reads: all stack_limit/max_charge/category lookups go through `ResourceRegistry.get_definition(id)`
6. Integrate with Building System for `try_consume()` (build cost deduction)
7. Integrate with Hunger System for `consume_food()` (daily consumption)
8. Integrate with HUD for `get_slot_data()`, `get_occupied_slots()`, `get_resource_quantity()`
9. Implement serialize()/deserialize() for Save/Load System integration

**Rollback plan**: Remove InventorySystem Autoload registration, delete `src/systems/inventory/`. No other systems are affected because this ADR creates NEW interfaces — it does not modify existing ones.

## Validation Criteria

- [ ] InventoryContainer first-fit stacking matches GDD Formula 3 for all test cases (AC6–AC10)
- [ ] Transport state machine transitions correctly: DROPPED→IN_TRANSIT→STORED, DROPPED→LOST, IN_TRANSIT→LOST (AC3, AC4, AC15)
- [ ] Transport energy/time cost formulas match GDD Formulas 1 and 2 within tolerance (AC1)
- [ ] Hunger consumption follows lowest-quantity-first priority with slot_index tiebreaker (AC19–AC22)
- [ ] Container capacity enforcement: cannot exceed capacity, cannot partially deposit on failure (AC8, AC10, AC11)
- [ ] Items cannot be consumed from non-STORED state (AC5)
- [ ] Serialization round-trip preserves all container state including IN_TRANSIT items (AC16)
- [ ] All storage_changed and transport_* signals fire at correct transition points
- [ ] No hardcoded resource metadata — all stack_limit/max_charge/category via ResourceRegistry

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `inventory-storage-system.md` | Inventory | TR-inv-001: InventoryContainer with first-fit stacking algorithm | InventoryContainer class with `_first_fit_allocate()` implementing phased scan (extend existing → fill empty → FAILURE) |
| `inventory-storage-system.md` | Inventory | TR-inv-002: Resource state machine DROPPED→IN_TRANSIT→STORED/LOST | Four-state enum, TransitItem resource class tracking source/target/remaining_ticks, state transitions via try_deposit()/start_transport() |
| `inventory-storage-system.md` | Inventory | TR-inv-003: Transport energy/tick cost formulas | `energy_cost = (2 × quantity) + (1 × distance)` and `time_cost = 5 × distance` computed at initiation, deducted at completion in start_transport() |
| `inventory-storage-system.md` | Inventory | TR-inv-004: Hunger consumption priority lowest-quantity first | `consume_food()` implements Phase 1 (collect food-eligible slots) → Phase 2 (sort by quantity ASC, slot_index ASC) → Phase 3 (deduct) |
| `inventory-storage-system.md` | Inventory | TR-inv-005: Storage Area (50 slots) + Storage Building (150 slots) | `create_container()` accepts capacity parameter. Storage Area creates 50-slot container; Storage Building upgrade sets capacity to 150 via `container_capacity_changed` signal |
| `inventory-storage-system.md` | Inventory | TR-inv-006: Items only consumed from STORED state | `try_consume()` operates on InventoryContainer slots (STORED only). DROPPED items are on tiles, not in containers. IN_TRANSIT items are in TransitItem registry, not in containers. |

## Related

- ADR-0001: Tick System — signal subscription for transport timer advancement
- ADR-0002: Resource Data Registry — stack_limit, max_charge, category lookups
- ADR-0004: Grid Map Data Model — tile-drop observation, placement validation
- `design/gdd/inventory-storage-system.md` — complete GDD with 6 formulas, 26 acceptance criteria
- `docs/architecture/architecture.md` TR-inv-001 through TR-inv-006
