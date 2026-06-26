# Story 002: First-Fit Stacking Algorithm

> **Epic**: Inventory/Storage System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/inventory-storage-system.md`
**Requirement**: `TR-inv-001`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0005: Inventory and Item State Machine
**ADR Decision Summary**: `_first_fit_allocate()` scans slots in index order — Phase 1 extends existing matching slots, Phase 2 fills empty slots. If all items cannot be placed (insufficient capacity), returns FAILURE and the entire batch is returned to source (no partial deposit). Stack limits come exclusively from `ResourceRegistry.get_definition(resource_id).stack_limit`.

**Engine**: Godot 4.6 | **Risk**: LOW — pure GDScript array manipulation, no post-cutoff APIs
**Engine Notes**: None. All operations are standard GDScript 2.0 array and dictionary operations, stable since pre-4.0.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Hardcoded stack limits — all must query ResourceRegistry; partial deposit (all-or-nothing invariant)
- Guardrail: Slot scan bounded by max capacity (150 for VS) — O(n) is acceptable

---

## Acceptance Criteria

*From GDD `design/gdd/inventory-storage-system.md`, scoped to this story:*

- [ ] **AC-6**: Given an empty container and a deposit of N items where N ≤ stack_limit, all N items fit in a single slot
- [ ] **AC-7**: Given a container with an existing partial stack and a deposit that overflows that stack, items are split across exactly two slots
- [ ] **AC-8**: Given a full container (occupied_slots == capacity), a deposit attempt returns FAILURE and items are NOT partially deposited
- [ ] **AC-9**: Given a deposit where quantity > stack_limit, items split across the minimum number of slots needed (`ceil(quantity / stack_limit)`)
- [ ] **AC-10**: Given a container with 1 empty slot and a deposit of 5 items with stack_limit = 3, the deposit FAILS entirely (EC-L3 — partial deposit not allowed)
- [ ] **AC-23**: Given a building with production output, the output is deposited into storage via `try_deposit()` — never appears on a tile or in the player's possession
- [ ] **AC-25**: Given two buildings pulling from the same container with quantity = 7 available, building A (lower building_id) pulls 7, building B (higher building_id) pulls 0 (deterministic pull ordering by container_id ASC, then building_id ASC)

---

## Implementation Notes

*Derived from ADR-0005 Implementation Guidelines:*

Implement on `InventoryContainer` and surface on `InventorySystem`:

```gdscript
## On InventoryContainer:

enum DepositResult { SUCCESS, FAILURE_FULL, FAILURE_NO_CONTAINER }
enum ConsumeResult { SUCCESS, FAILURE_INSUFFICIENT, FAILURE_NO_CONTAINER }

func _first_fit_allocate(resource_id: StringName, quantity: int, stack_limit: int) -> Array:
    # Returns Array[SlotAllocation] on success, empty Array on failure
    var remaining := quantity
    var allocations := []

    # Phase 1: Extend existing matching slots (index 0 upward)
    for i in range(capacity):
        if remaining == 0:
            break
        var slot: InventorySlot = slots[i]
        if slot.resource_id == resource_id and slot.quantity < stack_limit:
            var fill_space := stack_limit - slot.quantity
            var add := min(remaining, fill_space)
            slot.quantity += add
            remaining -= add
            allocations.append({slot_index = i, quantity_added = add})

    # Phase 2: Fill empty slots (restart scan from 0)
    for i in range(capacity):
        if remaining == 0:
            break
        var slot: InventorySlot = slots[i]
        if slot.is_empty():
            var fill := min(remaining, stack_limit)
            slot.resource_id = resource_id
            slot.quantity = fill
            remaining -= fill
            allocations.append({slot_index = i, quantity_added = fill})

    if remaining > 0:
        # FAILURE — rollback all mutations
        for alloc in allocations:
            var slot: InventorySlot = slots[alloc.slot_index]
            slot.quantity -= alloc.quantity_added
            if slot.quantity == 0:
                slot.resource_id = StringName("")
        return []  # FAILURE signal

    return allocations  # SUCCESS

func try_deposit(resource_id: StringName, quantity: int) -> DepositResult:
    var stack_limit := ResourceRegistry.get_definition(resource_id).stack_limit
    var result := _first_fit_allocate(resource_id, quantity, stack_limit)
    if result.is_empty() and quantity > 0:
        return DepositResult.FAILURE_FULL
    return DepositResult.SUCCESS

func try_consume(resource_id: StringName, quantity: int) -> ConsumeResult:
    # Check sufficient quantity first (read-only pass)
    var available := 0
    for slot in slots:
        if slot.resource_id == resource_id and _is_slot_usable(slot):
            available += slot.quantity
    if available < quantity:
        return ConsumeResult.FAILURE_INSUFFICIENT
    # Deduct (first-fit scan, index 0 upward)
    var remaining := quantity
    for slot in slots:
        if remaining == 0:
            break
        if slot.resource_id == resource_id and _is_slot_usable(slot):
            var take := min(remaining, slot.quantity)
            slot.quantity -= take
            remaining -= take
            if slot.quantity == 0:
                slot.resource_id = StringName("")
    return ConsumeResult.SUCCESS
```

**Surface on InventorySystem:**
```gdscript
func try_deposit(container_id: StringName, resource_id: StringName, quantity: int) -> InventoryContainer.DepositResult:
    var c := get_container(container_id)
    if c == null:
        return InventoryContainer.DepositResult.FAILURE_NO_CONTAINER
    var result := c.try_deposit(resource_id, quantity)
    if result == InventoryContainer.DepositResult.SUCCESS:
        emit_signal("storage_changed", container_id)
    return result

func try_consume(container_id: StringName, resource_id: StringName, quantity: int) -> InventoryContainer.ConsumeResult:
    var c := get_container(container_id)
    if c == null:
        return InventoryContainer.ConsumeResult.FAILURE_NO_CONTAINER
    var result := c.try_consume(resource_id, quantity)
    if result == InventoryContainer.ConsumeResult.SUCCESS:
        emit_signal("storage_changed", container_id)
    return result
```

**No partial deposit** (AC-8, AC-10): If `_first_fit_allocate` returns `[]` (failure), the method rolls back all slot mutations performed during Phase 1 and Phase 2 before returning. The entire batch is rejected atomically — no items are partially placed.

**Deterministic withdrawal order** (AC-25): When multiple buildings withdraw from the same container in the same tick, the InventorySystem processes withdrawals in `building_id` ascending order (Building System passes its ID to `try_consume`). This ordering is enforced by the TickSystem signal dispatch order per ADR-0005 EC-H5.

**Stack limits from registry** (invariant): `ResourceRegistry.get_definition(resource_id).stack_limit` is called at deposit time. Never hardcode stack limits inside InventorySystem.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Container and slot data model (must be DONE before stacking can operate)
- Story 003: `start_transport()` — uses `try_deposit()` at transport completion
- Story 004: `consume_food()` — uses its own scan (not `try_consume`) for hunger consumption

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-6**: Single slot fits all items (N ≤ stack_limit)
  - Given: Empty 50-slot container; resource "wood" with stack_limit = 99
  - When: `try_deposit("sa1", "wood", 5)`
  - Then: returns SUCCESS; exactly 1 slot is now occupied with resource_id="wood", quantity=5

- **AC-7**: Overflow into second slot
  - Given: Container with Slot 0 holding {resource_id: "wood", quantity: 95}; stack_limit = 99
  - When: `try_deposit("sa1", "wood", 10)`
  - Then: returns SUCCESS; Slot 0 has quantity=99 (filled by 4); Slot 1 has {resource_id: "wood", quantity=6}; exactly 2 slots occupied by wood

- **AC-8**: Full container → FAILURE, no partial deposit
  - Given: Container with all 50 slots occupied (no empty slots, no matching partial stacks)
  - When: `try_deposit("sa1", "stone", 1)`
  - Then: returns FAILURE_FULL; no slots modified (all slot states identical before and after)

- **AC-9**: Quantity > stack_limit → minimum slots used
  - Given: Empty container; resource "wheat" with stack_limit = 99
  - When: `try_deposit("sa1", "wheat", 150)`
  - Then: returns SUCCESS; exactly 2 slots occupied (Slot 0: qty=99, Slot 1: qty=51); ceil(150/99) = 2 slots

- **AC-10**: EC-L3 — 1 empty slot, qty=5, stack_limit=3 → FAIL entirely
  - Given: Container with 49 occupied slots and 1 empty slot; resource "bar" with stack_limit = 3
  - When: `try_deposit("sa1", "bar", 5)`
  - Then: returns FAILURE_FULL; the 1 empty slot is NOT modified (no partial deposit of 3 items)

- **AC-23**: try_deposit is the only pathway to put items into a container
  - Given: InventorySystem initialized; no tile-drop resource access via InventorySystem
  - When: Building System deposits production output via `InventorySystem.try_deposit()`
  - Then: `get_resource_quantity()` reflects the deposited amount; no code path exists to add items to a container without calling try_deposit

- **AC-25**: Deterministic consumption order for concurrent consumers
  - Given: Container with 7 units of "wood"; Building A (id="building_a") and Building B (id="building_b") both call try_consume("wood", 7) in the same tick
  - When: tick processes building_a first (alphabetically lower id), then building_b
  - Then: building_a.try_consume returns SUCCESS, quantity = 0; building_b.try_consume returns FAILURE_INSUFFICIENT

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/inventory/first_fit_stacking_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (InventoryContainer, InventorySlot, and ResourceRegistry integration must exist)
- Unlocks: Story 003 (transport completion calls try_deposit), Story 004 (consume_food needs try_consume for the container scan pattern)

## Completion Notes
**Completed**: 2026-05-31
**Criteria**: 7/7 passing
**Deviations**:
- ADVISORY: `stack_limit` and `max_charge` moved to caller parameters on `InventoryContainer.try_deposit` for testability — registry lookup stays in `InventorySystem.try_deposit`. ADR intent preserved.
- ADVISORY: `max_charge` parameter added to `_first_fit_allocate`; `current_charge` now initialised on deposit per ADR-0005 guarantee. Story pseudocode omitted this; ADR compliance improved.
- ADVISORY: `try_consume` iteration bounded to active slots (capacity-bounded), consistent with `try_deposit`. Story pseudocode iterated all slots.
**Test Evidence**: `tests/unit/inventory/first_fit_stacking_test.gd` — 27 tests (21 story ACs + 6 added: AC-26 unusable path, overflow boundary, charge-on-deposit ×2, rollback-charge)
**Code Review**: Manual `/code-review` run this session; all required findings fixed (W-2 null crash, W-6 overflow consume, T-2 charge-on-deposit, T-1 AC-26 test). Lean mode — LP-CODE-REVIEW gate skipped.
