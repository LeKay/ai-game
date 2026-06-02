extends Node
## InventorySystem — Autoload singleton (ADR-0005).
##
## Owns all InventoryContainers in the world. Plain GDScript classes — no Nodes.
## Container IDs for tile-based storage should use the pattern:
##   &"storage_<col>_<row>"   e.g. &"storage_10_5"
## Callers (GridMap placement, building demolition) are responsible for generating
## the correct ID string before calling create_container() / set_container_capacity().
##
## Story scope:
##   inv-001 — data model + query API (this story)
##   inv-002 — try_deposit / try_consume / first-fit stacking
##   inv-003 — start_transport / cancel_transport / _on_ticks_advanced
##   inv-004 — consume_food hunger algorithm
##   inv-005 — serialize / deserialize

## Emitted whenever a container's contents change.
## Not emitted by inv-001 operations — first emit site is inv-002 (try_deposit / try_consume).
signal storage_changed(container_id: StringName)

## Emitted when a container's capacity is changed via set_container_capacity().
signal container_capacity_changed(container_id: StringName, old_capacity: int, new_capacity: int)

## Primary store: container_id → InventoryContainer
var _containers: Dictionary[StringName, InventoryContainer] = {}



# ---------------------------------------------------------------------------
# Container lifecycle
# ---------------------------------------------------------------------------

## Creates a new container with the given id, display name, and capacity.
## If a container with the same id already exists, a warning is pushed and the
## call is ignored (containers are immutable at creation; use set_container_capacity
## to resize).
func create_container(id: StringName, p_display_name: String, p_capacity: int) -> void:
	if _containers.has(id):
		push_warning("InventorySystem: container '%s' already exists — ignoring create_container call" % id)
		return
	_containers[id] = InventoryContainer.new(id, p_display_name, p_capacity)
	container_capacity_changed.emit(id, 0, p_capacity)


## Returns the container for the given id, or null if it does not exist.
func get_container(id: StringName) -> InventoryContainer:
	return _containers.get(id, null)


## Returns an Array of all InventoryContainers (unordered).
func get_all_containers() -> Array[InventoryContainer]:
	var result: Array[InventoryContainer] = []
	result.assign(_containers.values())
	return result


## Returns true if any container ID encodes the given tile position using the
## standard pattern &"storage_<col>_<row>".
func has_storage_at_tile(tile: Vector2i) -> bool:
	var tile_id: StringName = StringName("storage_%d_%d" % [tile.x, tile.y])
	return _containers.has(tile_id)


# ---------------------------------------------------------------------------
# Capacity management
# ---------------------------------------------------------------------------

## Changes the capacity of an existing container and fires container_capacity_changed.
## If new_capacity > current slot array size, new empty slots are appended.
## If new_capacity < current slot array size, existing slots are NOT trimmed —
## occupied slots beyond the new capacity remain and keep their contents (AC-14).
func set_container_capacity(id: StringName, new_capacity: int) -> void:
	var container: InventoryContainer = _containers.get(id, null)
	if container == null:
		push_warning("InventorySystem: set_container_capacity called on unknown id '%s'" % id)
		return
	var old_capacity: int = container.capacity
	if old_capacity == new_capacity:
		return
	container.capacity = new_capacity
	# Grow the backing array if the new capacity exceeds the existing slot count.
	container._grow_slots_to(new_capacity)
	container_capacity_changed.emit(id, old_capacity, new_capacity)


# ---------------------------------------------------------------------------
# Query API
# ---------------------------------------------------------------------------

## Returns the logical capacity of the named container, or 0 if not found.
func get_capacity(id: StringName) -> int:
	var container: InventoryContainer = _containers.get(id, null)
	if container == null:
		return 0
	return container.capacity


## Returns the total number of slots in the backing array (>= capacity when
## capacity has been reduced without trimming).
func get_slot_count(id: StringName) -> int:
	var container: InventoryContainer = _containers.get(id, null)
	if container == null:
		return 0
	return container.slots.size()


## Returns the number of occupied slots across the entire backing array,
## including slots beyond current capacity (AC-14 / AC-26).
func get_occupied_slots(id: StringName) -> int:
	var container: InventoryContainer = _containers.get(id, null)
	if container == null:
		return 0
	return container.get_occupied_count()


## Returns the InventorySlot at slot_index, or null if the index is out of range
## or the container does not exist.
func get_slot_data(id: StringName, slot_index: int) -> InventorySlot:
	var container: InventoryContainer = _containers.get(id, null)
	if container == null:
		return null
	if slot_index < 0 or slot_index >= container.slots.size():
		return null
	return container.slots[slot_index]


## Returns the total quantity of resource_id across ALL registered containers.
func get_global_quantity(resource_id: StringName) -> int:
	var total: int = 0
	for container: InventoryContainer in _containers.values():
		total += container.get_resource_quantity(resource_id)
	return total


## Returns the ID of the first container that holds at least one unit of resource_id,
## or &"" if none found.
func find_container_with(resource_id: StringName) -> StringName:
	for id: StringName in _containers:
		if _containers[id].get_resource_quantity(resource_id) > 0:
			return id
	return &""


## Returns the summed quantity of resource_id across all ACTIVE slots
## (index 0 … capacity-1) in the named container.
func get_resource_quantity(id: StringName, resource_id: StringName) -> int:
	var container: InventoryContainer = _containers.get(id, null)
	if container == null:
		return 0
	return container.get_resource_quantity(resource_id)


# ---------------------------------------------------------------------------
# Deposit and consume (inv-002)
# ---------------------------------------------------------------------------

## Deposits `quantity` units of `resource_id` into the named container.
## Looks up stack_limit from ResourceRegistry (falls back to 9999 when the
## registry Autoload is not present, e.g. during unit tests).
## Emits storage_changed on SUCCESS. Returns FAILURE_NO_CONTAINER if the
## container does not exist.
func try_deposit(container_id: StringName, resource_id: StringName, quantity: int) -> InventoryContainer.DepositResult:
	var c: InventoryContainer = _containers.get(container_id, null)
	if c == null:
		return InventoryContainer.DepositResult.FAILURE_NO_CONTAINER
	var registry: Object = Engine.get_singleton(&"ResourceRegistry")
	var stack_limit: int = 9999
	var max_charge: float = 0.0
	if registry != null:
		var def: Object = registry.get_definition(resource_id)
		if def != null:
			stack_limit = def.stack_limit
			max_charge = def.max_charge
	var result: InventoryContainer.DepositResult = c.try_deposit(resource_id, quantity, stack_limit, max_charge)
	if result == InventoryContainer.DepositResult.SUCCESS:
		storage_changed.emit(container_id)
	return result


## Withdraws `quantity` units of `resource_id` from the named container.
## Emits storage_changed on SUCCESS. Returns FAILURE_NO_CONTAINER if the
## container does not exist.
func try_consume(container_id: StringName, resource_id: StringName, quantity: int) -> InventoryContainer.ConsumeResult:
	var c: InventoryContainer = _containers.get(container_id, null)
	if c == null:
		return InventoryContainer.ConsumeResult.FAILURE_NO_CONTAINER
	var result: InventoryContainer.ConsumeResult = c.try_consume(resource_id, quantity)
	if result == InventoryContainer.ConsumeResult.SUCCESS:
		storage_changed.emit(container_id)
	return result


# ---------------------------------------------------------------------------
# STUBS — implemented in future stories
# ---------------------------------------------------------------------------


## STUB (inv-004): Hunger consumption algorithm.
func consume_food(_entity_id: StringName, _calorie_demand: float) -> void:
	pass  # story inv-004


## STUB (inv-003): Enqueues a transport job; returns a unique transit_id.
func start_transport(_source_tile: Vector2i, _target_id: StringName,
		_resource_id: StringName, _quantity: int) -> StringName:
	return &""  # story inv-003


## STUB (inv-003): Cancels an in-flight transport job.
func cancel_transport(_transit_id: StringName) -> void:
	pass  # story inv-003


## STUB (inv-003): Returns the TransitItem for transit_id, or null.
func get_in_transit(_transit_id: StringName) -> TransitItem:
	return null  # story inv-003


## STUB (inv-005): Serialises all containers to an Array of Dictionaries.
func serialize() -> Array:
	return []  # story inv-005


## STUB (inv-005): Restores containers from a serialised snapshot.
func deserialize(_snapshots: Array) -> void:
	pass  # story inv-005
