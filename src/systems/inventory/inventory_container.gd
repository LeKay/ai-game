class_name InventoryContainer
## InventoryContainer — owns a fixed-length Array of InventorySlots.
##
## Deposit and consume results use these enums. FAILURE_NO_CONTAINER is only
## returned by InventorySystem wrappers (the container itself always exists).

enum DepositResult { SUCCESS = 0, FAILURE_FULL = 1, FAILURE_NO_CONTAINER = 2 }
enum ConsumeResult { SUCCESS = 0, FAILURE_INSUFFICIENT = 1, FAILURE_NO_CONTAINER = 2 }
##
## Capacity is set at construction time and may be changed later by
## InventorySystem.set_container_capacity(). Reducing capacity does NOT trim
## existing slots — all occupied slots beyond the new capacity remain in memory
## and count as occupied (AC-14).
##
## Container IDs for tile-based storage follow the pattern:
##   &"storage_<col>_<row>"   e.g. &"storage_10_5" for tile (10, 5)
## This encoding is applied by InventorySystem.create_container() callers.

## Unique identifier for this container.
var container_id: StringName = &""

## Human-readable label (e.g. "Storage Area").
var display_name: String = ""

## Logical capacity — how many slots are accessible to new deposits (slot-based),
## or the maximum total item count across all active slots (quantity-based).
var capacity: int = 0

## When true, capacity limits total item count (sum of quantities) instead of slot count.
## Used by storage buildings: no per-slot stack limit, but total items are capped.
var quantity_based: bool = false

## All slots, including those beyond the current capacity (preserved on shrink).
## Index 0 … capacity-1 are "active"; capacity … slots.size()-1 are "overflow".
var slots: Array[InventorySlot] = []

## Outstanding space reservations, keyed by holder_id (e.g. logistics route id or NPC id).
## Each entry is {resource_id: StringName, quantity: int}. One reservation per holder; a
## second reserve() call with the same holder_id replaces the previous entry.
## Reservations count against capacity for foreign depositors (preventing them from filling
## space that's already promised to an in-flight carrier) but not for the holder itself,
## which may deposit against its own reservation.
var _reservations: Dictionary = {}


## Initialises the container with `initial_capacity` empty slots.
func _init(id: StringName, p_display_name: String, initial_capacity: int) -> void:
	container_id = id
	display_name = p_display_name
	capacity = initial_capacity
	_grow_slots_to(initial_capacity)


## Returns the number of slots that hold a resource (resource_id != &"").
## Counts ALL occupied slots — including those beyond capacity (AC-14 / AC-26).
func get_occupied_count() -> int:
	var count: int = 0
	for slot: InventorySlot in slots:
		if not slot.is_empty():
			count += 1
	return count


## Returns the sum of quantities across all active slots (index 0 … capacity-1).
## For quantity_based containers this is the authoritative "used" metric.
func get_total_quantity() -> int:
	var total: int = 0
	var active: int = mini(capacity, slots.size())
	for i: int in active:
		total += slots[i].quantity
	return total


## Returns true when every active slot (index 0 … capacity-1) is occupied.
## For quantity_based containers: returns true when total item count + reservations >= capacity.
## (Slot-based containers ignore reservations here — they were never quantity-summed.)
func is_full() -> bool:
	if quantity_based:
		return get_total_quantity() + get_reserved_total() >= capacity
	var active: int = mini(capacity, slots.size())
	for i: int in active:
		if slots[i].is_empty():
			return false
	return active > 0


# ---------------------------------------------------------------------------
# Reservations (story: logistics lockup fix, 2026-06-28)
# ---------------------------------------------------------------------------

## Total quantity reserved across all holders (sum of all _reservations entries).
func get_reserved_total() -> int:
	var total: int = 0
	for entry: Dictionary in _reservations.values():
		total += int(entry.get("quantity", 0))
	return total


## Total quantity reserved for a specific resource_id across all holders.
func get_reserved_for(resource_id: StringName) -> int:
	var total: int = 0
	for entry: Dictionary in _reservations.values():
		if entry.get("resource_id", &"") == resource_id:
			total += int(entry.get("quantity", 0))
	return total


## Quantity reserved by a specific holder (0 if none).
func get_reserved_for_holder(holder_id: StringName) -> int:
	if not _reservations.has(holder_id):
		return 0
	return int(_reservations[holder_id].get("quantity", 0))


## Reserves `quantity` units against this container on behalf of `holder_id`.
## Replaces any previous reservation by the same holder (one reservation per holder).
## Quantity-based containers: fails if used + foreign_reservations + quantity > capacity.
## Slot-based containers: only quantity-based capacity is checked; first-fit at deposit time
## still applies, so reservations on slot-based containers are advisory (carriers should
## prefer quantity_based storage targets).
## Returns true on success, false when the reservation would exceed capacity.
func reserve(holder_id: StringName, resource_id: StringName, quantity: int) -> bool:
	if quantity <= 0:
		return false
	var existing: int = get_reserved_for_holder(holder_id)
	var foreign_reserved: int = get_reserved_total() - existing
	if quantity_based:
		if get_total_quantity() + foreign_reserved + quantity > capacity:
			return false
	else:
		# Slot-based capacity is approximated as occupied slots; reservation is a soft cap.
		if get_occupied_count() + foreign_reserved + quantity > capacity:
			return false
	_reservations[holder_id] = {"resource_id": resource_id, "quantity": quantity}
	return true


## Releases the reservation held by `holder_id`. No-op if the holder has none.
func release_reservation(holder_id: StringName) -> void:
	_reservations.erase(holder_id)


## Returns the total quantity of a given resource across all active slots.
## Slots beyond capacity are excluded (overflow items are inaccessible).
func get_resource_quantity(resource_id: StringName) -> int:
	var total: int = 0
	var active: int = mini(capacity, slots.size())
	for i: int in active:
		var slot: InventorySlot = slots[i]
		if slot.resource_id == resource_id:
			total += slot.quantity
	return total


## Returns true when the slot holds a resource known to ResourceRegistry.
## Slots with an unknown resource_id are occupied but not consumable (AC-26).
## Registry-absent escape hatch returns true to avoid false negatives in tests.
func _is_slot_usable(slot: InventorySlot) -> bool:
	if slot.is_empty():
		return false
	var registry: Object = Engine.get_singleton(&"ResourceRegistry") if Engine.has_singleton(&"ResourceRegistry") else null
	if registry == null:
		return true
	return registry.get_definition(slot.resource_id) != null


## Two-phase first-fit allocation. Returns an Array of {slot_index, quantity_added, charge_added}
## Dictionaries on success, or an empty Array if the full quantity cannot be placed.
## On failure, ALL slot mutations from both phases are rolled back atomically.
## Newly deposited items start at full charge: charge_added = quantity_added * max_charge.
func _first_fit_allocate(resource_id: StringName, quantity: int, stack_limit: int, max_charge: float) -> Array:
	var remaining: int = quantity
	var allocations: Array = []

	# Phase 1: extend existing matching partial stacks (index 0 upward).
	for i: int in range(capacity):
		if remaining == 0:
			break
		var slot: InventorySlot = slots[i]
		if slot.resource_id == resource_id and slot.quantity < stack_limit:
			var fill_space: int = stack_limit - slot.quantity
			var add: int = mini(remaining, fill_space)
			var charge: float = add * max_charge
			slot.quantity += add
			slot.current_charge += charge
			remaining -= add
			allocations.append({slot_index = i, quantity_added = add, charge_added = charge})

	# Phase 2: fill empty slots (restart scan from 0).
	for i: int in range(capacity):
		if remaining == 0:
			break
		var slot: InventorySlot = slots[i]
		if slot.is_empty():
			var fill: int = mini(remaining, stack_limit)
			var charge: float = fill * max_charge
			slot.resource_id = resource_id
			slot.quantity = fill
			slot.current_charge = charge
			remaining -= fill
			allocations.append({slot_index = i, quantity_added = fill, charge_added = charge})

	if remaining > 0:
		# FAILURE — roll back all mutations from both phases atomically.
		for alloc: Dictionary in allocations:
			var slot: InventorySlot = slots[alloc.slot_index]
			slot.quantity -= alloc.quantity_added
			slot.current_charge -= alloc.charge_added
			if slot.quantity == 0:
				slot.resource_id = &""
				slot.current_charge = 0.0
		return []

	return allocations


## Deposits `quantity` units of `resource_id` using first-fit stacking.
## `stack_limit` and `max_charge` must be supplied by the caller (InventorySystem looks
## them up from ResourceRegistry so this method stays testable without the Autoload).
## When `holder_id` is non-empty, the deposit may use that holder's existing reservation
## (up to its reserved quantity); only the portion exceeding the reservation has to fit
## in unreserved free capacity. The reservation is consumed proportionally: any portion
## used is subtracted from the reservation, and a zeroed reservation is released.
## Returns FAILURE_FULL if the full batch cannot be placed (no partial deposit).
## For quantity_based containers: ignores stack_limit; enforces capacity as total item count.
func try_deposit(resource_id: StringName, quantity: int, stack_limit: int, max_charge: float,
		holder_id: StringName = &"") -> DepositResult:
	var own_reserved: int = 0
	if holder_id != &"" and _reservations.has(holder_id):
		# Only a same-resource reservation can be consumed by the deposit. A wood-cargo
		# carrier cannot deposit stone into its wood reservation.
		if _reservations[holder_id].get("resource_id", &"") == resource_id:
			own_reserved = int(_reservations[holder_id].get("quantity", 0))
	var foreign_reserved: int = get_reserved_total() - own_reserved

	if quantity_based:
		# Reservation physically holds space (it never adds capacity beyond `capacity`).
		# Holder fits iff used + foreign_reserved + quantity <= capacity. The holder's own
		# reservation is bookkeeping (consumed below); it doesn't grant extra space.
		if get_total_quantity() + foreign_reserved + quantity > capacity:
			return DepositResult.FAILURE_FULL
		var result: Array = _first_fit_allocate(resource_id, quantity, capacity, max_charge)
		if result.is_empty() and quantity > 0:
			return DepositResult.FAILURE_FULL
		_consume_reservation(holder_id, quantity)
		return DepositResult.SUCCESS

	# Slot-based: reservations are advisory; first-fit allocation enforces the real cap.
	var result: Array = _first_fit_allocate(resource_id, quantity, stack_limit, max_charge)
	if result.is_empty() and quantity > 0:
		return DepositResult.FAILURE_FULL
	_consume_reservation(holder_id, quantity)
	return DepositResult.SUCCESS


## Decrements `holder_id`'s reservation by `quantity`; releases the reservation when it
## reaches zero. No-op if the holder has no reservation.
func _consume_reservation(holder_id: StringName, quantity: int) -> void:
	if holder_id == &"" or not _reservations.has(holder_id):
		return
	var entry: Dictionary = _reservations[holder_id]
	var remaining: int = int(entry.get("quantity", 0)) - quantity
	if remaining <= 0:
		_reservations.erase(holder_id)
	else:
		entry["quantity"] = remaining


## Withdraws `quantity` units of `resource_id` from usable active slots
## (index 0 … capacity-1). Overflow slots are excluded, consistent with try_deposit.
## Uses a read-only check first to guarantee all-or-nothing semantics.
## Returns FAILURE_INSUFFICIENT if available quantity is less than requested.
func try_consume(resource_id: StringName, quantity: int) -> ConsumeResult:
	var active: int = mini(capacity, slots.size())
	# Read-only pass: verify enough usable quantity exists before mutating.
	var available: int = 0
	for i: int in range(active):
		var slot: InventorySlot = slots[i]
		if slot.resource_id == resource_id and _is_slot_usable(slot):
			available += slot.quantity
	if available < quantity:
		return ConsumeResult.FAILURE_INSUFFICIENT

	# Deduct pass: first-fit, index 0 upward.
	var remaining: int = quantity
	for i: int in range(active):
		if remaining == 0:
			break
		var slot: InventorySlot = slots[i]
		if slot.resource_id == resource_id and _is_slot_usable(slot):
			var take: int = mini(remaining, slot.quantity)
			slot.quantity -= take
			remaining -= take
			if slot.quantity == 0:
				slot.resource_id = &""
	return ConsumeResult.SUCCESS


## Expands the slots Array to at least `target_size` entries, filling new
## positions with empty InventorySlot instances.
func _grow_slots_to(target_size: int) -> void:
	var old_size: int = slots.size()
	if old_size >= target_size:
		return
	for i: int in range(old_size, target_size):
		slots.append(InventorySlot.new())
