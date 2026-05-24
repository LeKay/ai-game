# Story 004: Hunger Consumption Priority Algorithm

> **Epic**: Inventory/Storage System
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/inventory-storage-system.md`
**Requirement**: `TR-inv-004`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0005: Inventory and Item State Machine
**ADR Decision Summary**: `consume_food(daily_requirement)` collects all food-eligible slots across all containers (category == "consumable"), sorts them by quantity ASC then slot_index ASC, and deducts from lowest-quantity slots first. Returns `FoodConsumptionResult` with total_consumed, slots_affected, remaining_deficit, and hunger_debuff_applied. Called by Hunger System at each day transition.

**Engine**: Godot 4.6 | **Risk**: LOW — no post-cutoff APIs
**Engine Notes**: None. Sorting an Array of Dictionaries using a custom comparator (`sort_custom()` with a Callable) is stable GDScript 2.0 behaviour.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Consuming items not in STORED state (DROPPED/IN_TRANSIT items must be skipped); consuming items where ResourceRegistry returns null (unknown resource)
- Guardrail: Called once per day transition only; must complete deterministically

---

## Acceptance Criteria

*From GDD `design/gdd/inventory-storage-system.md`, scoped to this story:*

- [ ] **AC-19**: Given two containers with food slots of quantities [3, 50], hunger consuming 10 units deducts from the quantity-3 slot first (consumes all 3), then from the quantity-50 slot (consumes 7), leaving [0, 43]
- [ ] **AC-20**: Given total food across all containers < daily_food_requirement, `consume_food()` returns `hunger_debuff_applied = true` and `remaining_deficit > 0`
- [ ] **AC-21**: Given food slots across multiple containers, consumption prioritizes lowest quantity first regardless of which container holds the slot
- [ ] **AC-22**: Given slots with equal quantities, the slot with the lower slot_index is consumed first (deterministic tiebreaker)

---

## Implementation Notes

*Derived from ADR-0005 Implementation Guidelines:*

**FoodConsumptionResult class:**
```gdscript
class FoodConsumptionResult:
    var total_consumed: int = 0
    var slots_affected: int = 0
    var remaining_deficit: int = 0
    var hunger_debuff_applied: bool = false
```

**consume_food() on InventorySystem:**
```gdscript
func consume_food(daily_requirement: int) -> FoodConsumptionResult:
    var result := FoodConsumptionResult.new()
    var to_consume := daily_requirement

    # Phase 1: Collect all food-eligible slots across all containers
    # Containers scanned in container_id alphabetical order for determinism
    var food_entries := []
    var sorted_containers := get_all_containers()
    sorted_containers.sort_custom(func(a, b): return a.container_id < b.container_id)

    for container in sorted_containers:
        for i in range(container.capacity):
            var slot: InventorySlot = container.slots[i]
            if slot.is_empty():
                continue
            if not _is_slot_usable(slot):  # unknown resource_id guard from Story 001
                continue
            var resource_def := ResourceRegistry.get_definition(slot.resource_id)
            if resource_def == null:
                continue
            if resource_def.category == "consumable":
                food_entries.append({
                    container_id = container.container_id,
                    slot_index = i,
                    quantity = slot.quantity,
                    slot_ref = slot
                })

    # Phase 2: Sort by quantity ASC, then slot_index ASC as tiebreaker
    food_entries.sort_custom(func(a, b):
        if a.quantity != b.quantity:
            return a.quantity < b.quantity
        return a.slot_index < b.slot_index
    )

    # Phase 3: Deduct from sorted slots
    for entry in food_entries:
        if to_consume <= 0:
            break
        var slot: InventorySlot = entry.slot_ref
        var consume_amount := min(to_consume, slot.quantity)
        slot.quantity -= consume_amount
        result.total_consumed += consume_amount
        result.slots_affected += 1
        to_consume -= consume_amount
        if slot.quantity == 0:
            slot.resource_id = StringName("")

    result.remaining_deficit = max(0, to_consume)
    result.hunger_debuff_applied = result.remaining_deficit > 0

    if result.remaining_deficit > 0:
        # Signal to Hunger System — actual debuff application is Hunger System's job
        # InventorySystem only reports the deficit; it does NOT apply the debuff itself
        pass

    # Emit storage_changed for all containers that were modified
    # (simplified: emit for all containers — HUD will refresh)
    for container in sorted_containers:
        emit_signal("storage_changed", container.container_id)

    return result
```

**Key design invariants:**
- Container scan order: alphabetical by container_id (deterministic, independent of insertion order)
- Sort key: quantity ASC (primary), slot_index ASC (secondary tiebreaker)
- Unknown resource_id slots: excluded from food_entries entirely (not consumed, not counted toward total)
- IN_TRANSIT items: not in any container slot, never consumed by hunger algorithm
- DROPPED items (on tiles): not in any container slot, never consumed by hunger algorithm
- Hunger debuff is reported, not applied — Hunger System applies the debuff on receipt of `hunger_debuff_applied = true`

**GDD example verification** (from Formula 5):
```
Container "Backup" (scanned first alphabetically): Slot 0: berries × 5
Container "Main" (scanned second): Slot 0: berries × 3, Slot 1: bread × 50

food_entries before sort:
  {container_id="Backup", slot_index=0, quantity=5}
  {container_id="Main", slot_index=0, quantity=3}
  {container_id="Main", slot_index=1, quantity=50}

After sort by quantity ASC, slot_index ASC:
  {quantity=3, container_id="Main", slot_index=0}     ← lowest quantity
  {quantity=5, container_id="Backup", slot_index=0}
  {quantity=50, container_id="Main", slot_index=1}

Consume 10:
  Main Slot 0: consume 3 → 0 (empty), remaining=7
  Backup Slot 0: consume 5 → 0 (empty), remaining=2
  Main Slot 1: consume 2 → 48, remaining=0

Result: consumed=10, slots_affected=3, remaining_deficit=0, debuff=false
```

Note: This is different from the GDD's example which scans by container_id order first then sorts. The sort step produces the correct lowest-quantity-first ordering regardless of container scan order.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Container structure and slot data (must be DONE first)
- Story 002: `try_consume()` — hunger uses its own scan loop (not `try_consume()`) to support cross-container sorting
- The actual hunger debuff application — that is Hunger System's responsibility upon receiving `hunger_debuff_applied = true`

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-19**: Lowest quantity slot consumed first, then next lowest
  - Given: Container "sa1" with Slot 0 = {berry, qty=3} and Slot 1 = {bread, qty=50}; both "consumable"; daily_requirement=10
  - When: `consume_food(10)`
  - Then: total_consumed=10; Slot 0 = empty (was qty=3, fully consumed); Slot 1 = {bread, qty=43} (consumed 7)
  - Edge cases: if daily_requirement=3 exactly, only Slot 0 is consumed; if daily_requirement=53, all food consumed + remaining_deficit=0

- **AC-20**: Insufficient food triggers debuff flag
  - Given: Total food across all containers = 22 units; daily_requirement = 30
  - When: `consume_food(30)`
  - Then: total_consumed=22; remaining_deficit=8; hunger_debuff_applied=true
  - Edge cases: daily_requirement=0 → total_consumed=0, no debuff; all food exactly meets requirement → remaining_deficit=0, debuff=false

- **AC-21**: Cross-container lowest quantity first
  - Given: Container "sa1" has Slot 0 = {berry, qty=50}; Container "sa2" has Slot 0 = {berry, qty=3}
  - When: `consume_food(10)`
  - Then: sa2 Slot 0 consumed first (qty=3, lower quantity); then sa1 Slot 0 deducted by 7; sa2 Slot 0 is empty; sa1 Slot 0 has qty=43

- **AC-22**: Equal quantities → lower slot_index wins
  - Given: Single container with Slot 1 = {berry, qty=5} and Slot 3 = {berry, qty=5}
  - When: `consume_food(5)`
  - Then: Slot 1 is fully consumed (lower slot_index); Slot 3 remains unchanged
  - Edge cases: equal quantity in different containers → container_id sort determines final order (slot_index tiebreaker applies within same quantity group regardless of container)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/inventory/hunger_consumption_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (container structure and `_is_slot_usable()` must exist), Story 002 must be DONE (slot mutation patterns established)
- Unlocks: Hunger System stories (which call `consume_food()` at day transition)
