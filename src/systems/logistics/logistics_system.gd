extends Node
## LogisticsSystem — manages carrier routes between buildings.
## Autoload singleton. Registered in project settings as "LogisticsSystem".
## ADR: ADR-0011 (Logistics System — Carrier FSM and Route Architecture)
## Story: logistics-system/story-001 (route model + slot validation)
##        logistics-system/story-002 (carrier FSM core loop)

# ---- Signals -----------------------------------------------------------------

signal route_created(route: LogisticsRoute)
signal route_deleted(route_id: StringName)

# ---- Constants ---------------------------------------------------------------

## Maximum output carrier slots per building (MVP: always 1).
const MAX_OUTPUT_SLOTS: int = 1
## Fallback max input slots for buildings with no PRODUCTION_TABLE entry (storage, unknown).
const MAX_INPUT_SLOTS: int = 1
## Ticks per tile of Manhattan distance for carrier travel (matches NPC ticks_per_tile).
const TICKS_PER_TILE: float = 3.0
## Default carrier cargo capacity in items per trip (MVP).
const CARRIER_CAPACITY: int = 1
## Kept for save-file compatibility only — timeouts were removed because they caused
## carriers to discard held cargo and create pointless home-and-back movement.
var carrier_waiting_timeout: int = 300

# ---- Dependencies (injectable for tests) ------------------------------------

## Injected in _enter_tree() from Autoloads, or set directly in tests.
var _npc_system: Node = null
var _building_registry: Node = null
var _inventory_system: Node = null
## WorldGrid instance — not an Autoload; must be injected by scene setup or tests.
## When null, pathfinding is skipped and travel times fall back to Manhattan distance.
var _grid_map: Node = null

# ---- State -------------------------------------------------------------------

var _active_routes: Array[LogisticsRoute] = []
var _priority_offset: int = 0

# ---- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	_npc_system = NPCSystem
	_building_registry = BuildingRegistry
	_inventory_system = InventorySystem
	if not TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
		TickSystem.ticks_advanced.connect(_on_ticks_advanced)

# ---- Public API --------------------------------------------------------------

## Attempt to create a new carrier route.
##
## Returns a result Dictionary:
##   { "success": true,  "route": LogisticsRoute, "error": "" }
##   { "success": false, "route": null,            "error": String }
##
## Slot validation rules (ADR-0011):
##   OUTPUT route — source building must have a free output slot.
##   INPUT  route — destination building must have a free input slot.
##   Any route type — source and destination must be different buildings.
##
## Inactive/paused routes still occupy their slot until explicitly deleted.
func create_route(
		source_id: StringName,
		destination_id: StringName,
		npc_id: StringName,
		route_type: int,
		source_item_id: StringName = &"") -> Dictionary:

	if source_id == destination_id:
		return _failure("Source and destination cannot be the same building.")

	if route_type == LogisticsRoute.RouteType.OUTPUT:
		var used: int = _count_routes_by_type(source_id, LogisticsRoute.RouteType.OUTPUT, true)
		if used >= MAX_OUTPUT_SLOTS:
			return _failure("Building '%s' has no free output slots." % source_id)

	elif route_type == LogisticsRoute.RouteType.INPUT:
		var used: int = _count_routes_by_type(destination_id, LogisticsRoute.RouteType.INPUT, false)
		var max_slots: int = _get_max_input_slots(destination_id)
		if used >= max_slots:
			return _failure("Building '%s' has no free input slots." % destination_id)

	# Path validation gate (ADR-0013): block route creation when no viable path exists.
	if _grid_map != null:
		var src_tile: Vector2i = _get_building_tile(source_id)
		var dst_tile: Vector2i = _get_building_tile(destination_id)
		var path_result: PathResult = LogisticsPathfinder.find_path(src_tile, dst_tile, _grid_map)
		if not path_result.found:
			return _failure("No viable path between %s and %s. Check for blocking buildings." \
				% [source_id, destination_id])
		var route := LogisticsRoute.create(source_id, destination_id, npc_id, route_type, source_item_id)
		route.cached_path = path_result.path
		route.cached_path_cost = path_result.cost
		route.path_valid = true
		_active_routes.append(route)
		_assign_carrier_to_building(route)
		route_created.emit(route)
		return {"success": true, "route": route, "error": ""}

	var route := LogisticsRoute.create(source_id, destination_id, npc_id, route_type, source_item_id)
	_active_routes.append(route)
	_assign_carrier_to_building(route)
	route_created.emit(route)
	return {"success": true, "route": route, "error": ""}


## Starts a carrier trip: transitions the carrier from IDLE → TRAVEL_TO_SOURCE.
## Records the NPC's current position as npc_home_pos for the RETURN_HOME leg.
## Returns false if the route is not found or carrier is not IDLE.
func start_route(route_id: StringName) -> bool:
	var route: LogisticsRoute = _get_route(route_id)
	if route == null or route.carrier_state != LogisticsRoute.CarrierState.IDLE:
		return false

	var home_pos: Vector2i = Vector2i.ZERO
	if _npc_system != null:
		home_pos = _npc_system.get_npc_position(route.npc_id)
	route.npc_home_pos = home_pos
	route.npc_start_pos = home_pos

	var source_tile: Vector2i = _get_building_tile(route.source_building_id)
	var travel_ticks: int

	if _grid_map != null:
		var dest_tile: Vector2i = _get_building_tile(route.destination_building_id)
		var h2s: PathResult = LogisticsPathfinder.find_path(home_pos, source_tile, _grid_map)
		var s2h: PathResult = LogisticsPathfinder.find_path(source_tile, home_pos, _grid_map)
		var d2h: PathResult = LogisticsPathfinder.find_path(dest_tile, home_pos, _grid_map)
		route.cached_path_cost_home_to_source = h2s.cost
		route.cached_path_cost_source_to_home = s2h.cost
		route.cached_path_cost_dest_to_home = d2h.cost
		route.home_legs_valid = true
		travel_ticks = int(floor(h2s.cost * TICKS_PER_TILE))
		route.cached_path_cost_current_leg = h2s.cost
		route.current_leg_path = h2s.path
		route.cached_leg_path_home_to_source = h2s.path
	else:
		travel_ticks = _calc_travel_time(home_pos, source_tile)
		route.cached_path_cost_current_leg = float(travel_ticks) / TICKS_PER_TILE
		route.current_leg_path = [home_pos, source_tile]
		route.cached_leg_path_home_to_source = [home_pos, source_tile]

	route.remaining_ticks = travel_ticks
	_set_carrier_state(route, LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE)
	return true


## Injects the WorldGrid instance and subscribes to terrain signals for path invalidation.
## Call from the parent scene after nodes are ready, or from tests after dependency injection.
func set_grid_map(grid: Node) -> void:
	_grid_map = grid
	if _grid_map != null:
		if not _grid_map.terrain_changed.is_connected(_on_terrain_changed):
			_grid_map.terrain_changed.connect(_on_terrain_changed)
		if not _grid_map.terrain_tile_changed.is_connected(_on_terrain_tile_changed):
			_grid_map.terrain_tile_changed.connect(_on_terrain_tile_changed)
	if not PathSystem.path_placed.is_connected(_on_path_layout_changed):
		PathSystem.path_placed.connect(_on_path_layout_changed)
	if not PathSystem.path_removed.is_connected(_on_path_layout_changed):
		PathSystem.path_removed.connect(_on_path_layout_changed)


## Return all routes currently tracked (active and inactive).
func get_active_routes() -> Array[LogisticsRoute]:
	return _active_routes


## Remove a route by ID, free its building slot, and update building status.
## If the carrier is mid-route (not IDLE), release the NPC immediately so they
## return home and become available for new routes.
func delete_route(route_id: StringName) -> void:
	for i in range(_active_routes.size()):
		if _active_routes[i].id == route_id:
			var route: LogisticsRoute = _active_routes[i]
			route.active = false
			_on_route_active_changed(route)
			if route.carrier_state != LogisticsRoute.CarrierState.IDLE \
					and _npc_system != null:
				_npc_system.release_npc(route.npc_id)
			_active_routes.remove_at(i)
			route_deleted.emit(route_id)
			return


## Pause an active route. The carrier completes its current leg then returns home IDLE.
## EC-L6: route transitions to PAUSED lifecycle, active flag set to false.
func pause_route(route_id: StringName) -> void:
	var route: LogisticsRoute = _get_route(route_id)
	if route == null or not route.active:
		return
	route.lifecycle_state = LogisticsRoute.LifecycleState.PAUSED
	route.active = false
	_on_route_active_changed(route)


## Resume a previously paused route. Sets active = true and lifecycle to ACTIVE.
func resume_route(route_id: StringName) -> void:
	var route: LogisticsRoute = _get_route(route_id)
	if route == null or route.active:
		return
	if route.lifecycle_state != LogisticsRoute.LifecycleState.PAUSED:
		return
	route.lifecycle_state = LogisticsRoute.LifecycleState.ACTIVE
	route.active = true
	_assign_carrier_to_building(route)


## Returns route efficiency as a float in [0.0, 1.0+].
## Story 007 (TR-logistics-010) will implement Formula 3; this stub approximates based on lifecycle.
## UI interpretation: green ≥ 1.0, yellow 0.5–1.0, red < 0.5.
func get_route_efficiency(route: LogisticsRoute) -> float:
	if not route.active:
		return 0.0
	match route.carrier_state:
		LogisticsRoute.CarrierState.WAITING_SOURCE, \
		LogisticsRoute.CarrierState.WAITING_DESTINATION:
			return 0.5
	return 1.0

# ---- Tick handler -----------------------------------------------------------

func _on_ticks_advanced(delta_ticks: int) -> void:
	_advance_tick(delta_ticks)


## Advances all active carrier FSMs by delta_ticks.
## Called as step 3 of tick processing order (after BuildingRegistry, before InventorySystem).
func _advance_tick(delta_ticks: int) -> void:
	var count: int = _active_routes.size()
	if count == 0:
		return
	var start: int = _priority_offset % count
	_priority_offset = (_priority_offset + 1) % maxi(count, 1)
	for j in range(count):
		var route: LogisticsRoute = _active_routes[(start + j) % count]
		if not route.active:
			continue
		for _i in range(delta_ticks):
			_process_carrier(route)
		if route.active:
			_update_building_status(route)

# ---- Carrier FSM ------------------------------------------------------------

## Advances a single carrier by one tick through its 8-state FSM.
func _process_carrier(route: LogisticsRoute) -> void:
	match route.carrier_state:
		LogisticsRoute.CarrierState.IDLE:
			pass  # Waiting for start_route() — no-op each tick.

		LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE:
			route.remaining_ticks -= 1
			if route.remaining_ticks <= 0:
				_set_carrier_state(route, LogisticsRoute.CarrierState.AT_SOURCE)
				if _npc_system != null:
					_npc_system.on_npc_at_location(route.npc_id, route.source_building_id)

		LogisticsRoute.CarrierState.AT_SOURCE:
			if _source_has_cargo(route):
				_do_pickup(route)
				if route.path_valid:
					route.remaining_ticks = int(floor(route.cached_path_cost * TICKS_PER_TILE))
					route.current_leg_path = route.cached_path
				else:
					var dest_tile: Vector2i = _get_building_tile(route.destination_building_id)
					var src_tile: Vector2i = _get_building_tile(route.source_building_id)
					route.remaining_ticks = _calc_travel_time(src_tile, dest_tile)
					route.current_leg_path = [src_tile, dest_tile]
				_set_carrier_state(route, LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION)
			else:
				route.wait_ticks = 0
				_set_carrier_state(route, LogisticsRoute.CarrierState.WAITING_SOURCE)

		LogisticsRoute.CarrierState.WAITING_SOURCE:
			# No timeout — carrier waits at source until cargo arrives.
			# Going home and back when the source is empty would create pointless movement.
			if _source_has_cargo(route):
				_do_pickup(route)
				if route.path_valid:
					route.remaining_ticks = int(floor(route.cached_path_cost * TICKS_PER_TILE))
					route.current_leg_path = route.cached_path
				else:
					var dest_tile: Vector2i = _get_building_tile(route.destination_building_id)
					var src_tile: Vector2i = _get_building_tile(route.source_building_id)
					route.remaining_ticks = _calc_travel_time(src_tile, dest_tile)
					route.current_leg_path = [src_tile, dest_tile]
				route.wait_ticks = 0
				_set_carrier_state(route, LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION)

		LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION:
			route.remaining_ticks -= 1
			if route.remaining_ticks <= 0:
				_set_carrier_state(route, LogisticsRoute.CarrierState.AT_DESTINATION)
				if _npc_system != null:
					_npc_system.on_npc_at_location(route.npc_id, route.destination_building_id)

		LogisticsRoute.CarrierState.AT_DESTINATION:
			var has_space: bool = _destination_has_space(route)
			if has_space:
				_do_deposit(route)
				route.cargo = 0
				route.cargo_resource = null
				var dest_tile: Vector2i = _get_building_tile(route.destination_building_id)
				var src_tile: Vector2i = _get_building_tile(route.source_building_id)
				route.npc_start_pos = dest_tile
				if route.path_valid:
					route.remaining_ticks = int(floor(route.cached_path_cost * TICKS_PER_TILE))
					route.cached_path_cost_current_leg = route.cached_path_cost
					var rev: Array[Vector2i] = route.cached_path.duplicate()
					rev.reverse()
					route.current_leg_path = rev
				else:
					route.remaining_ticks = _calc_travel_time(dest_tile, src_tile)
					route.cached_path_cost_current_leg = float(route.remaining_ticks) / TICKS_PER_TILE
					route.current_leg_path = [dest_tile, src_tile]
				route.wait_ticks = 0
				_set_carrier_state(route, LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE)
			else:
				route.wait_ticks = 0
				_set_carrier_state(route, LogisticsRoute.CarrierState.WAITING_DESTINATION)

		LogisticsRoute.CarrierState.WAITING_DESTINATION:
			# No timeout — carrier holds cargo and waits until space opens up.
			# Timing out would cause the carrier to pick up a new item before delivering
			# the held one, silently destroying cargo.
			var has_space: bool = _destination_has_space(route)
			if has_space:
				_do_deposit(route)
				route.cargo = 0
				route.cargo_resource = null
				var dest_tile2: Vector2i = _get_building_tile(route.destination_building_id)
				var src_tile2: Vector2i = _get_building_tile(route.source_building_id)
				route.npc_start_pos = dest_tile2
				if route.path_valid:
					route.remaining_ticks = int(floor(route.cached_path_cost * TICKS_PER_TILE))
					route.cached_path_cost_current_leg = route.cached_path_cost
					var rev2: Array[Vector2i] = route.cached_path.duplicate()
					rev2.reverse()
					route.current_leg_path = rev2
				else:
					route.remaining_ticks = _calc_travel_time(dest_tile2, src_tile2)
					route.cached_path_cost_current_leg = float(route.remaining_ticks) / TICKS_PER_TILE
					route.current_leg_path = [dest_tile2, src_tile2]
				route.wait_ticks = 0
				_set_carrier_state(route, LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE)

		LogisticsRoute.CarrierState.RETURN_HOME:
			route.remaining_ticks -= 1
			if route.remaining_ticks <= 0:
				if route.active:
					route.wait_ticks = 0
					route.npc_start_pos = route.npc_home_pos
					if route.home_legs_valid:
						route.remaining_ticks = int(floor(route.cached_path_cost_home_to_source * TICKS_PER_TILE))
						route.cached_path_cost_current_leg = route.cached_path_cost_home_to_source
						route.current_leg_path = route.cached_leg_path_home_to_source
					else:
						var source_tile: Vector2i = _get_building_tile(route.source_building_id)
						route.remaining_ticks = _calc_travel_time(route.npc_home_pos, source_tile)
						route.cached_path_cost_current_leg = float(route.remaining_ticks) / TICKS_PER_TILE
						route.current_leg_path = [route.npc_home_pos, source_tile]
					_set_carrier_state(route, LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE)
				else:
					_set_carrier_state(route, LogisticsRoute.CarrierState.IDLE)
					if _npc_system != null:
						_npc_system.release_npc(route.npc_id)

# ---- Internal helpers -------------------------------------------------------

## Marks a route as DEACTIVATED (lifecycle) and records a human-readable reason.
## Route record is preserved — player can reassign a new NPC (ADR-0011 EC-L4, EC-L5).
func _deactivate_route(route: LogisticsRoute, reason: String) -> void:
	route.lifecycle_state = LogisticsRoute.LifecycleState.DEACTIVATED
	route.active = false
	route.deactivation_reason = reason
	_on_route_active_changed(route)


## Calls NPCSystem.set_carrier_state on transition only (never per-tick no-op).
func _set_carrier_state(route: LogisticsRoute, new_state: int) -> void:
	route.carrier_state = new_state
	if _npc_system != null:
		_npc_system.set_carrier_state(route.npc_id, new_state)


## Returns the tile position of a building, or Vector2i(-1,-1) if not found.
func _get_building_tile(building_id: StringName) -> Vector2i:
	if _building_registry == null:
		return Vector2i(-1, -1)
	return _building_registry.get_building_tile(str(building_id))


## Returns true if the destination building can accept at least one more item.
## Storage buildings: checks InventoryContainer total against capacity.
## Production buildings: checks input_buffer total against input_capacity (PRODUCTION_TABLE).
func _destination_has_space(route: LogisticsRoute) -> bool:
	if _building_registry == null:
		return true
	var dest_id := str(route.destination_building_id)
	var instance: Object = _building_registry.get_building_instance(dest_id)
	if instance == null:
		return true
	# Storage buildings: check InventoryContainer capacity.
	if BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		if _inventory_system == null:
			return true
		var container_id: StringName = _get_container_id(route.destination_building_id)
		var used: int = _inventory_system.get_total_quantity(container_id)
		var cap: int = _inventory_system.get_capacity(container_id)
		return used < cap
	# Production buildings: check per-slot input_capacity from PRODUCTION_TABLE.
	return not _building_registry.is_input_full(dest_id, route.cargo_resource)


## Resolves a building ID to its inventory container ID via BuildingRegistry.
## Falls back to the building ID itself if the registry or container is unavailable.
func _get_container_id(building_id: StringName) -> StringName:
	if _building_registry == null:
		return building_id
	var instance: Object = _building_registry.get_building_instance(str(building_id))
	if instance == null:
		return building_id
	var container_id: StringName = instance.assigned_container_id
	if container_id == &"":
		return building_id
	return container_id


## Returns true if the source building is a storage type (items in InventoryContainer).
func _is_storage_source(route: LogisticsRoute) -> bool:
	if _building_registry == null:
		return false
	var instance: Object = _building_registry.get_building_instance(str(route.source_building_id))
	if instance == null:
		return false
	return BuildingRegistry.STORAGE_CAPACITY.has(instance.type)


## Returns true when the source has at least one item available for pickup.
## For storage sources: checks InventorySystem for route.source_item_id.
## For production sources: checks buffered_output, filtered by source_item_id when set.
func _source_has_cargo(route: LogisticsRoute) -> bool:
	if _is_storage_source(route):
		if route.source_item_id == &"" or _inventory_system == null:
			return false
		var container_id := _get_container_id(route.source_building_id)
		return _inventory_system.get_resource_quantity(container_id, route.source_item_id) >= 1
	if _building_registry == null:
		return false
	if route.source_item_id != &"":
		return _building_registry.get_output_buffer_resource_quantity(
			str(route.source_building_id), route.source_item_id) > 0
	return _building_registry.has_output_buffer(str(route.source_building_id))


## Deposits route.cargo into the destination building.
## Storage destination: deposits into InventoryContainer via InventorySystem.
## Production destination: adds directly to input_buffer via receive_input_from_world.
func _do_deposit(route: LogisticsRoute) -> void:
	if _building_registry == null:
		return
	var dest_id := str(route.destination_building_id)
	var instance: Object = _building_registry.get_building_instance(dest_id)
	if instance != null and BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		if _inventory_system != null:
			_inventory_system.try_deposit(
				_get_container_id(route.destination_building_id),
				route.cargo_resource,
				route.cargo)
	else:
		_building_registry.receive_input_from_world(dest_id, route.cargo_resource, route.cargo)


## Picks up cargo from the source building and sets route.cargo / route.cargo_resource.
## Storage source: consumes route.source_item_id from InventoryContainer.
## Production source: removes from buffered_output, filtered by source_item_id when set.
func _do_pickup(route: LogisticsRoute) -> void:
	if _is_storage_source(route):
		var container_id := _get_container_id(route.source_building_id)
		_inventory_system.try_consume(container_id, route.source_item_id, 1)
		route.cargo = 1
		route.cargo_resource = route.source_item_id
	else:
		var res_id: StringName
		if route.source_item_id != &"":
			res_id = route.source_item_id
		else:
			res_id = _building_registry.get_output_buffer_resource(str(route.source_building_id))
		var available: int = _building_registry.get_output_buffer_resource_quantity(
			str(route.source_building_id), res_id)
		var pickup: int = mini(available, CARRIER_CAPACITY)
		_building_registry.remove_from_output(str(route.source_building_id), res_id, pickup)
		route.cargo = pickup
		route.cargo_resource = res_id


## Manhattan distance travel time in ticks. Uses floor() per Formula 1 (ADR-0011).
func _calc_travel_time(from: Vector2i, to: Vector2i) -> int:
	var dist: int = absi(to.x - from.x) + absi(to.y - from.y)
	return int(floor(float(dist) * TICKS_PER_TILE))


## Returns the maximum number of INPUT routes allowed for building_id.
## Derived from the number of distinct input resources in PRODUCTION_TABLE.
## Falls back to MAX_INPUT_SLOTS for storage buildings and unknown types.
func _get_max_input_slots(building_id: StringName) -> int:
	if _building_registry == null:
		return MAX_INPUT_SLOTS
	var instance: Object = _building_registry.get_building_instance(str(building_id))
	if instance == null:
		return MAX_INPUT_SLOTS
	if BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		return MAX_INPUT_SLOTS
	if not BuildingRegistry.PRODUCTION_TABLE.has(instance.type):
		return MAX_INPUT_SLOTS
	var inputs: Array = BuildingRegistry.PRODUCTION_TABLE[instance.type]["inputs"]
	return maxi(inputs.size(), 1)


## Returns the number of currently active INPUT routes whose destination is building_id.
## Routes with active == false (deleted, paused) are excluded.
func _count_active_input_routes(building_id: StringName) -> int:
	var count: int = 0
	for route in _active_routes:
		if route.active and route.route_type == LogisticsRoute.RouteType.INPUT \
				and route.destination_building_id == building_id:
			count += 1
	return count


func _count_routes_by_type(building_id: StringName, route_type: int, check_source: bool) -> int:
	var count: int = 0
	for route in _active_routes:
		if route.route_type != route_type:
			continue
		var match_id: StringName = route.source_building_id if check_source \
			else route.destination_building_id
		if match_id == building_id:
			count += 1
	return count


func _get_route(route_id: StringName) -> LogisticsRoute:
	for route in _active_routes:
		if route.id == route_id:
			return route
	return null


func _failure(error: String) -> Dictionary:
	return {"success": false, "route": null, "error": error}


## Assigns the carrier NPC to the corresponding building slot when a route is created.
## OUTPUT route — source building gets the output carrier ID.
## INPUT  route — destination building gets the input carrier ID.
func _assign_carrier_to_building(route: LogisticsRoute) -> void:
	if _building_registry == null:
		return
	if route.route_type == LogisticsRoute.RouteType.OUTPUT:
		_building_registry.assign_output_carrier(
			str(route.source_building_id), route.npc_id)
	elif route.route_type == LogisticsRoute.RouteType.INPUT:
		_building_registry.add_input_carrier(
			str(route.destination_building_id), route.npc_id)


## Updates building status based on current carrier state (ADR-0011 Building Status Integration).
## Called once per active route at end of _advance_tick() — step 3 of tick ordering.
## IDLE/TRAVEL/RETURN states do not modify building status (carrier in transit).
## All other active states → destination building OPERATING.
func _update_building_status(route: LogisticsRoute) -> void:
	if _building_registry == null:
		return
	match route.carrier_state:
		LogisticsRoute.CarrierState.IDLE, \
		LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE, \
		LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION, \
		LogisticsRoute.CarrierState.RETURN_HOME:
			pass  # Carrier in transit — do not override building status.
		_:
			_building_registry.set_status(
				str(route.destination_building_id),
				BuildingRegistry.Status.OPERATING)


## Called when WorldGrid emits terrain_changed(pos, layer).
## Marks all routes whose cached path crosses pos as path_valid = false;
## queues recalculation deferred to end of frame to avoid mid-tick mutations.
func _on_terrain_changed(pos: Vector2i, _layer: int) -> void:
	for route in _active_routes:
		if route.cached_path.has(pos):
			route.path_valid = false
	_recalculate_invalid_paths.call_deferred()


## Called when WorldGrid emits terrain_tile_changed (terrain type changed — e.g. resource tile cleared).
## Any cost decrease can benefit routes that previously avoided the tile, so all routes are invalidated.
func _on_terrain_tile_changed(_tile: Vector2i) -> void:
	_invalidate_all_routes()


## Called when PathSystem emits path_placed or path_removed.
## Path tiles cost 0.5 vs 1.0 for open ground, so all routes may find shorter paths.
func _on_path_layout_changed(_tile: Vector2i) -> void:
	_invalidate_all_routes()


## Marks every route as path_valid = false and queues A* recalculation.
func _invalidate_all_routes() -> void:
	for route in _active_routes:
		route.path_valid = false
	_recalculate_invalid_paths.call_deferred()


## Recalculates A* for all routes with path_valid = false.
## Active routes with no found path are DEACTIVATED; DEACTIVATED routes have their
## cached_path updated but lifecycle state is unchanged — player must reactivate (ADR-0013 AC-4).
func _recalculate_invalid_paths() -> void:
	if _grid_map == null:
		return
	for route in _active_routes:
		if route.path_valid:
			continue
		var result: PathResult = LogisticsPathfinder.find_path(
			_get_building_tile(route.source_building_id),
			_get_building_tile(route.destination_building_id),
			_grid_map
		)
		if result.found:
			route.cached_path = result.path
			route.cached_path_cost = result.cost
			route.path_valid = true
		elif route.active:
			_deactivate_route(route, "Path blocked by terrain change.")


## Serialise all active routes to a JSON-compatible dictionary.
func serialize() -> Dictionary:
	var routes: Array = []
	for route in _active_routes:
		routes.append(_serialize_route(route))
	return {"routes": routes, "carrier_waiting_timeout": carrier_waiting_timeout}


## Restore routes from a previously serialised dictionary.
func deserialize(data: Dictionary) -> void:
	_active_routes.clear()
	carrier_waiting_timeout = data.get("carrier_waiting_timeout", 300)
	for route_data in data.get("routes", []):
		if not route_data is Dictionary:
			continue
		var route := _deserialize_route(route_data)
		_active_routes.append(route)
		_assign_carrier_to_building(route)


func _serialize_route(route: LogisticsRoute) -> Dictionary:
	var path: Array = []
	for tile in route.cached_path:
		path.append({"x": tile.x, "y": tile.y})
	return {
		"id": str(route.id),
		"source_building_id": str(route.source_building_id),
		"destination_building_id": str(route.destination_building_id),
		"npc_id": str(route.npc_id),
		"route_type": route.route_type,
		"active": route.active,
		"lifecycle_state": route.lifecycle_state,
		"carrier_state": route.carrier_state,
		"cargo": route.cargo,
		"cargo_resource": str(route.cargo_resource) if route.cargo_resource != null else "",
		"remaining_ticks": route.remaining_ticks,
		"wait_ticks": route.wait_ticks,
		"npc_home_pos": {"x": route.npc_home_pos.x, "y": route.npc_home_pos.y},
		"npc_start_pos": {"x": route.npc_start_pos.x, "y": route.npc_start_pos.y},
		"cached_path_cost_current_leg": route.cached_path_cost_current_leg,
		"deactivation_reason": route.deactivation_reason,
		"source_item_id": str(route.source_item_id),
		"cached_path": path,
		"cached_path_cost": route.cached_path_cost,
		"path_valid": route.path_valid,
		"cached_path_cost_home_to_source": route.cached_path_cost_home_to_source,
		"cached_path_cost_source_to_home": route.cached_path_cost_source_to_home,
		"cached_path_cost_dest_to_home": route.cached_path_cost_dest_to_home,
		"home_legs_valid": route.home_legs_valid,
	}


func _deserialize_route(data: Dictionary) -> LogisticsRoute:
	var route := LogisticsRoute.new()
	route.id = StringName(data.get("id", ""))
	route.source_building_id = StringName(data.get("source_building_id", ""))
	route.destination_building_id = StringName(data.get("destination_building_id", ""))
	route.npc_id = StringName(data.get("npc_id", ""))
	route.route_type = data.get("route_type", 0)
	route.active = data.get("active", false)
	route.lifecycle_state = data.get("lifecycle_state", 0)
	route.carrier_state = data.get("carrier_state", 0)
	route.cargo = data.get("cargo", 0)
	var cr: String = data.get("cargo_resource", "")
	route.cargo_resource = StringName(cr) if cr != "" else null
	route.remaining_ticks = data.get("remaining_ticks", 0)
	route.wait_ticks = data.get("wait_ticks", 0)
	var hp: Dictionary = data.get("npc_home_pos", {"x": 0, "y": 0})
	route.npc_home_pos = Vector2i(hp.get("x", 0), hp.get("y", 0))
	var sp: Dictionary = data.get("npc_start_pos", hp)
	route.npc_start_pos = Vector2i(sp.get("x", 0), sp.get("y", 0))
	route.cached_path_cost_current_leg = data.get("cached_path_cost_current_leg", 0.0)
	route.deactivation_reason = data.get("deactivation_reason", "")
	route.source_item_id = StringName(data.get("source_item_id", ""))
	route.cached_path = []
	for tile in data.get("cached_path", []):
		if tile is Dictionary:
			route.cached_path.append(Vector2i(tile.get("x", 0), tile.get("y", 0)))
	route.cached_path_cost = data.get("cached_path_cost", 0.0)
	route.path_valid = data.get("path_valid", false)
	route.cached_path_cost_home_to_source = data.get("cached_path_cost_home_to_source", 0.0)
	route.cached_path_cost_source_to_home = data.get("cached_path_cost_source_to_home", 0.0)
	route.cached_path_cost_dest_to_home = data.get("cached_path_cost_dest_to_home", 0.0)
	route.home_legs_valid = data.get("home_legs_valid", false)
	return route


## Handles building status and slot changes when a route becomes inactive.
## Called from delete_route() and _deactivate_route().
## INPUT route deactivated → destination building BLOCKED (no input carrier).
## OUTPUT route deactivated → source slot cleared; STALLED is deferred until next
##   production cycle completes with empty output buffer (per GDD Core Rules 6).
func _on_route_active_changed(route: LogisticsRoute) -> void:
	if _building_registry == null:
		return
	if not route.active:
		if route.route_type == LogisticsRoute.RouteType.INPUT:
			_building_registry.remove_input_carrier(
				str(route.destination_building_id), route.npc_id)
			if _count_active_input_routes(route.destination_building_id) == 0:
				_building_registry.set_status(
					str(route.destination_building_id),
					BuildingRegistry.Status.BLOCKED)
		elif route.route_type == LogisticsRoute.RouteType.OUTPUT:
			_building_registry.assign_output_carrier(
				str(route.source_building_id), &"")
			# Do NOT set STALLED immediately — building transitions naturally when
			# next production cycle completes with output_carrier_id empty.
