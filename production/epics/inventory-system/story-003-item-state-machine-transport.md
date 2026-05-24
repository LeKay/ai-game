# Story 003: Item State Machine and Transport

> **Epic**: Inventory/Storage System
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/inventory-storage-system.md`
**Requirement**: `TR-inv-002`, `TR-inv-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0005: Inventory and Item State Machine
**ADR Decision Summary**: Item state machine: DROPPED (on grid tile) → IN_TRANSIT (tracked in InventorySystem transit registry) → STORED (in container slot) or LOST (source cleared, dest destroyed, or energy insufficient at arrival). Transport costs computed at initiation: `energy_cost = 2*qty + distance`, `time_cost = 5*distance`. `remaining_ticks` decremented each tick via `_on_ticks_advanced()`. Energy is checked at arrival — not at initiation.

**Engine**: Godot 4.6 | **Risk**: LOW — no post-cutoff APIs
**Engine Notes**: None. `TickSystem.ticks_advanced` signal subscription, Dictionary, and GDScript signal connections are stable pre-cutoff APIs.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Personal carry-inventory (no container holds IN_TRANSIT items); energy deducted at initiation (must be deducted at arrival)
- Guardrail: `_on_ticks_advanced()` processes all IN_TRANSIT items in O(n) where n = active transports (typically 0–2 in VS)

---

## Acceptance Criteria

*From GDD `design/gdd/inventory-storage-system.md`, scoped to this story:*

- [ ] **AC-1**: Given a tile with a dropped resource, the transport preview shows correct energy and time cost (Formula 1: `energy = 2*qty + distance`; Formula 2: `time = 5*distance`)
- [ ] **AC-2**: Given `energy_remaining < energy_cost`, the transport action is blocked (start_transport returns null/error, no TransitItem created)
- [ ] **AC-3**: Given a valid transport (energy sufficient), completing transport transitions the item from DROPPED to STORED and deducts the correct energy and tick costs
- [ ] **AC-4**: Given the player cancels a transport before arrival, items return to the source tile (DROPPED) and no energy is deducted
- [ ] **AC-5**: Given a resource in DROPPED state on a tile, buildings CANNOT access it — `try_consume()` from any container returns FAILURE_INSUFFICIENT for items not in STORED state
- [ ] **AC-15**: Given a transport arrives at a container that is full at that moment (even if it was not full at initiation), items are LOST and no energy is refunded

---

## Implementation Notes

*Derived from ADR-0005 Implementation Guidelines:*

**TransitItem class:**
```gdscript
class_name TransitItem

var transit_id: StringName
var source_tile: Vector2i
var target_container_id: StringName
var resource_id: StringName
var quantity: int
var remaining_ticks: int
var energy_cost: int   # computed at initiation, deducted at completion
var distance: int

func is_ready() -> bool:
    return remaining_ticks <= 0
```

**InventorySystem additions:**
```gdscript
var _transits: Dictionary  # [StringName, TransitItem]

signal transport_started(transit_id: StringName)
signal transport_completed(transit_id: StringName)
signal transport_failed(transit_id: StringName)

func get_transport_preview(source_tile: Vector2i, target_container_id: StringName, quantity: int) -> Dictionary:
    var distance := GridMap.manhattan_dist(source_tile, _container_tile(target_container_id))
    return {
        energy_cost = (2 * quantity) + distance,
        time_cost = 5 * distance,
        can_afford = PlayerCharacter.energy >= (2 * quantity) + distance
    }

func start_transport(source_tile: Vector2i, target_container_id: StringName, quantity: int) -> StringName:
    var distance := GridMap.manhattan_dist(source_tile, _container_tile(target_container_id))
    var energy_cost := (2 * quantity) + distance
    var time_cost := 5 * distance

    if PlayerCharacter.energy < energy_cost:
        return StringName("")   # blocked — insufficient energy

    var transit := TransitItem.new()
    transit.transit_id = StringName("transit_%d" % _next_transit_id)
    transit.source_tile = source_tile
    transit.target_container_id = target_container_id
    transit.resource_id = GridMap.get_resource(source_tile).resource_id
    transit.quantity = quantity
    transit.remaining_ticks = time_cost
    transit.energy_cost = energy_cost
    transit.distance = distance

    _transits[transit.transit_id] = transit
    emit_signal("transport_started", transit.transit_id)
    return transit.transit_id

func cancel_transport(transit_id: StringName) -> void:
    var transit := _transits.get(transit_id, null)
    if transit == null:
        return
    # Return items to source tile (grid tile-drop persists — no GridMap call needed)
    # No energy deducted
    _transits.erase(transit_id)
    emit_signal("transport_failed", transit_id)

func _on_ticks_advanced(delta_ticks: int) -> void:
    var completed: Array = []
    for transit in _transits.values():
        transit.remaining_ticks -= delta_ticks
        if transit.is_ready():
            completed.append(transit)
    for transit in completed:
        _complete_transport(transit)

func _complete_transport(transit: TransitItem) -> void:
    _transits.erase(transit.transit_id)
    var c := get_container(transit.target_container_id)
    if c == null:
        # Container destroyed — items LOST
        emit_signal("transport_failed", transit.transit_id)
        return
    var result := c.try_deposit(transit.resource_id, transit.quantity)
    if result != InventoryContainer.DepositResult.SUCCESS:
        # Container full — items LOST, no energy refund
        emit_signal("transport_failed", transit.transit_id)
        return
    # SUCCESS: deduct energy and tick cost
    PlayerCharacter.consume_energy(transit.energy_cost)
    emit_signal("transport_completed", transit.transit_id)
    emit_signal("storage_changed", transit.target_container_id)
```

**Wire tick signal in `_ready()`:**
```gdscript
func _ready() -> void:
    TickSystem.ticks_advanced.connect(_on_ticks_advanced)
```

**DROPPED state**: Items in DROPPED state exist on the grid tile (managed by GridMap). InventorySystem does NOT own the DROPPED state — it observes it via `GridMap.get_resource(tile)`. Buildings query `InventorySystem.get_resource_quantity(container_id, resource_id)` which only reads container slots (STORED state). There is no API to consume items from a tile directly.

**Energy at arrival** (not initiation): Energy is checked at initiation only to show the preview and create the transit (if insufficient, transit is rejected). Energy is actually deducted at `_complete_transport()` — this means the player could theoretically gain energy between initiation and arrival. If energy at arrival is insufficient... the GDD states the check is on `energy_remaining < energy_cost` at initiation (see AC-2). At completion, energy is deducted unconditionally (the player committed at initiation). However, if `PlayerCharacter.consume_energy()` cannot cover the cost (energy drained by other actions), the transport still completes but leaves energy at 0 with possible depletion penalty (handled by Player Character System, not Inventory).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Container and TransitItem class skeleton (must be DONE first)
- Story 002: `try_deposit()` used at transport completion (must be DONE first)
- Story 004: `consume_food()` is a separate algorithm, not part of state machine
- Story 005: `serialize()`/`deserialize()` for IN_TRANSIT state persistence

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Transport preview cost calculation
  - Given: source_tile = Vector2i(3, 3), target at Vector2i(11, 3) (manhattan distance = 8), quantity = 5
  - When: `get_transport_preview(Vector2i(3,3), "sa1", 5)`
  - Then: energy_cost = (2×5) + 8 = 18; time_cost = 5×8 = 40; can_afford = (PlayerCharacter.energy >= 18)
  - Edge cases: distance = 0 (player adjacent to storage): energy_cost = 2*qty + 0; time_cost = 0

- **AC-2**: Insufficient energy → transport blocked
  - Given: PlayerCharacter.energy = 10; source at distance 8, quantity = 5 → energy_cost = 18
  - When: `start_transport(source_tile, "sa1", 5)`
  - Then: returns empty StringName (or error indicator); no TransitItem created; `_transits` unchanged

- **AC-3**: Valid transport → DROPPED→STORED, energy deducted
  - Given: Player has 50 energy; distance = 8, quantity = 5; container "sa1" has empty slots
  - When: `start_transport()` creates transit, then `_on_ticks_advanced(40)` fires
  - Then: `_complete_transport()` called; `get_resource_quantity("sa1", "wood")` == 5; PlayerCharacter.energy reduced by 18
  - Edge cases: transport_completed signal fires exactly once

- **AC-4**: Cancel → items return to DROPPED, no energy deducted
  - Given: Transit "transit_1" is IN_TRANSIT with remaining_ticks = 20
  - When: `cancel_transport("transit_1")`
  - Then: `_transits` no longer contains "transit_1"; PlayerCharacter.energy unchanged; source tile still has resource (GridMap state unchanged); transport_failed signal fires

- **AC-5**: Buildings cannot access DROPPED items
  - Given: GridMap tile (5,5) has DROPPED resource "wood", quantity 10; container "sa1" is empty
  - When: `InventorySystem.try_consume("sa1", "wood", 5)`
  - Then: returns FAILURE_INSUFFICIENT (container "sa1" has 0 wood in STORED state)

- **AC-15**: Full container at arrival → items LOST, no energy refund
  - Given: Transit "transit_1" created when "sa1" had 1 free slot; before arrival, "sa1" becomes full
  - When: `_on_ticks_advanced()` triggers `_complete_transport()`
  - Then: `try_deposit()` returns FAILURE_FULL; no items in "sa1"; PlayerCharacter.energy unchanged (no refund); transport_failed signal fires

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/inventory/inventory_transport_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (InventorySystem framework and TransitItem class must exist), Story 002 must be DONE (try_deposit used at transport completion)
- Unlocks: Story 005 (save/load must serialize IN_TRANSIT state created here)
