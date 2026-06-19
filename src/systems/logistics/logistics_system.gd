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
## Base ticks per tile of carrier travel = the travel time at 100% carrier efficiency.
## Effective travel is then divided by the carrier's food-efficiency (F4) in _set_carrier_state,
## so faster carriers traverse quicker. Anchored 2026-06-12 so that a 50%-efficient carrier
## travels at 10 ticks/tile (the previous value): base/0.5 = 10 → base = 5. Thus 100% = 5/tile,
## 50% = 10/tile, 25% = 20/tile. (Was a flat 10 = the 100% case before F4 was anchored.)
const TICKS_PER_TILE: float = 5.0
## Default carrier cargo capacity in items per trip. Raised to 2 (2026-06-12) so one carrier can
## keep pace with one producer out to ~typical distances (capacity 1 made the carrier the binding
## bottleneck and forced too many carriers). Intended to become a per-carrier upgradeable stat.
const CARRIER_CAPACITY: int = 2
## Kept for save-file compatibility only — timeouts were removed because they caused
## carriers to discard held cargo and create pointless home-and-back movement.
var carrier_waiting_timeout: int = 300
## Ticks between work-checks when a carrier finds all its routes have no work.
## Prevents calling _route_has_work for every route every tick when sources are empty.
const IDLE_RECHECK_INTERVAL: int = 10

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

## Shared-carrier model (2026-06-12): one NPC can be the carrier for several routes but serves
## ONE at a time. Maps npc_id (StringName) → route_id (StringName) the carrier is currently
## executing. Absent / &"" = carrier has no active route (free or idle-waiting).
var _carrier_active_route: Dictionary = {}
## Ticks remaining before an all-idle carrier re-checks its routes for work.
## Set to IDLE_RECHECK_INTERVAL when _carrier_pick_next finds no work; cleared on work found.
var _carrier_idle_cooldown: Dictionary = {}

## Per-day tracking — reset in _on_day_transition(). route_id (StringName) → int.
var _route_items_today: Dictionary = {}
var _route_active_ticks_today: Dictionary = {}

# ---- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	_npc_system = NPCSystem
	_building_registry = BuildingRegistry
	_inventory_system = InventorySystem
	if not TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
		TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	if not TickSystem.day_transition.is_connected(_on_day_transition):
		TickSystem.day_transition.connect(_on_day_transition)
	if not BuildingRegistry.building_recipe_changed.is_connected(_on_building_recipe_changed):
		BuildingRegistry.building_recipe_changed.connect(_on_building_recipe_changed)

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


## Registers a route with its carrier and lets the shared-carrier scheduler decide the next move.
## The carrier only travels to a route that actually HAS WORK (cargo at source + space at dest);
## otherwise it waits in place instead of trekking to an empty source. If the carrier is already
## executing another route, the new route just joins the round-robin (picked up after a delivery).
func start_route(route_id: StringName) -> bool:
	var route: LogisticsRoute = _get_route(route_id)
	if route == null:
		return false
	var npc_id: StringName = route.npc_id
	var home_pos: Vector2i = Vector2i.ZERO
	if _npc_system != null:
		home_pos = _npc_system.get_npc_position(npc_id)
	route.npc_home_pos = home_pos
	route.npc_start_pos = home_pos

	# Only (re)schedule when the carrier is free: no active route, or its active route is the
	# idle-waiting placeholder. A busy carrier keeps its current trip; the new route waits its turn.
	var active_id: StringName = _carrier_active_route.get(npc_id, &"")
	var active: LogisticsRoute = _get_route(active_id) if active_id != &"" else null
	if active == null or not active.active \
			or active.carrier_state == LogisticsRoute.CarrierState.IDLE:
		_carrier_idle_cooldown.erase(npc_id)
		_carrier_pick_next(npc_id, active)
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


## Returns the route the given carrier NPC is currently executing, or null if none/idle.
## Used by the overlay/route visuals so the icon follows the carrier's ONE active route.
func get_active_route_for_npc(npc_id: StringName) -> LogisticsRoute:
	var rid: StringName = _carrier_active_route.get(npc_id, &"")
	if rid == &"":
		return null
	return _get_route(rid)


## Remove a route by ID, free its building slot, and update building status.
## Shared carrier: the NPC is only sent home if it has no other routes left; otherwise it keeps
## serving its remaining routes.
func delete_route(route_id: StringName) -> void:
	for i in range(_active_routes.size()):
		if _active_routes[i].id == route_id:
			var route: LogisticsRoute = _active_routes[i]
			var npc_id: StringName = route.npc_id
			route.active = false
			_on_route_active_changed(route)   # clears the active-route map entry if this was it
			_active_routes.remove_at(i)
			if _carrier_routes(npc_id).is_empty():
				_carrier_active_route.erase(npc_id)
				_carrier_idle_cooldown.erase(npc_id)
				if _npc_system != null:
					_npc_system.release_npc(npc_id)
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
	_carrier_idle_cooldown.erase(route.npc_id)
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


## Snapshots per-day counters into each route's stats_* fields, then resets the accumulators.
## Called once per game-day via TickSystem.day_transition.
func _on_day_transition(_days_elapsed: int) -> void:
	for route: LogisticsRoute in _active_routes:
		route.stats_items_last_day = _route_items_today.get(route.id, 0)
		route.stats_active_ticks_last_day = _route_active_ticks_today.get(route.id, 0)
		route.stats_data_available = true
	_route_items_today.clear()
	_route_active_ticks_today.clear()


## Advances all active carrier FSMs by delta_ticks.
## Called as step 3 of tick processing order (after BuildingRegistry, before InventorySystem).
func _advance_tick(delta_ticks: int) -> void:
	var count: int = _active_routes.size()
	if count == 0:
		return
	# Shared-carrier service step: ensure every carrier has a valid active route and wake
	# idle (waiting-in-place) carriers that now have work. Runs once per tick batch.
	_service_carriers()
	var start: int = _priority_offset % count
	_priority_offset = (_priority_offset + 1) % maxi(count, 1)
	for j in range(count):
		var route: LogisticsRoute = _active_routes[(start + j) % count]
		if not route.active:
			continue
		# Only the carrier's currently-active route advances; its other routes stay dormant.
		if not _is_active_route(route):
			continue
		var active_ticks: int = 0
		for _i in range(delta_ticks):
			if route.carrier_state != LogisticsRoute.CarrierState.IDLE:
				active_ticks += 1
			_process_carrier(route)
		if active_ticks > 0:
			_route_active_ticks_today[route.id] = \
				_route_active_ticks_today.get(route.id, 0) + active_ticks
		if route.active:
			_update_building_status(route)


# ---- Shared-carrier scheduling ----------------------------------------------

## True when `route` is the one its carrier is currently executing.
func _is_active_route(route: LogisticsRoute) -> bool:
	return _carrier_active_route.get(route.npc_id, &"") == route.id

## Distinct carrier npc_ids that have at least one active route.
func _carrier_npc_ids() -> Array:
	var seen: Dictionary = {}
	for r: LogisticsRoute in _active_routes:
		if r.active and r.npc_id != &"":
			seen[r.npc_id] = true
	return seen.keys()

## All active routes assigned to a carrier npc, in stable creation order.
func _carrier_routes(npc_id: StringName) -> Array[LogisticsRoute]:
	var out: Array[LogisticsRoute] = []
	for r: LogisticsRoute in _active_routes:
		if r.active and r.npc_id == npc_id:
			out.append(r)
	return out

## A route "has work" when its source has cargo AND its destination has space.
func _route_has_work(route: LogisticsRoute) -> bool:
	return _source_has_cargo(route) and _destination_has_space(route)

## The carrier's current tile (last confirmed NPC position).
func _carrier_tile(npc_id: StringName) -> Vector2i:
	if _npc_system != null:
		return _npc_system.get_npc_position(npc_id)
	return Vector2i.ZERO

## Per-tick: assign an active route to carriers that lack one, and re-evaluate idle
## (waiting-in-place) carriers in case work appeared on one of their routes.
## Carriers that just found no work on any route observe IDLE_RECHECK_INTERVAL before
## the next full scan, avoiding repeated _route_has_work calls every tick.
func _service_carriers() -> void:
	for npc_id: StringName in _carrier_npc_ids():
		var active_id: StringName = _carrier_active_route.get(npc_id, &"")
		var active: LogisticsRoute = _get_route(active_id) if active_id != &"" else null
		if active == null or not active.active:
			_carrier_idle_cooldown.erase(npc_id)
			_carrier_pick_next(npc_id, null)
		elif active.carrier_state == LogisticsRoute.CarrierState.IDLE:
			var cooldown: int = _carrier_idle_cooldown.get(npc_id, 0)
			if cooldown > 0:
				_carrier_idle_cooldown[npc_id] = cooldown - 1
			else:
				_carrier_pick_next(npc_id, active)

## Decision point: the carrier has no cargo in hand and chooses its next route. Picks the next
## route WITH WORK round-robin (starting AFTER current_route — "switch after each delivery"),
## then travels to its source from the carrier's current tile. If no route has work, the carrier
## waits in place (active route → IDLE), re-checked each tick by _service_carriers.
func _carrier_pick_next(npc_id: StringName, current_route: LogisticsRoute) -> void:
	var routes: Array[LogisticsRoute] = _carrier_routes(npc_id)
	if routes.is_empty():
		_carrier_active_route.erase(npc_id)
		return
	var start: int = 0
	if current_route != null:
		var idx: int = routes.find(current_route)
		start = (idx + 1) if idx >= 0 else 0
	var from_tile: Vector2i = _carrier_tile(npc_id)
	for k in range(routes.size()):
		var cand: LogisticsRoute = routes[(start + k) % routes.size()]
		if _route_has_work(cand):
			# Mark the previously-active route dormant BEFORE starting the new leg so the NPC's
			# state ends up synced to the new route (not overwritten with IDLE).
			if current_route != null and current_route != cand:
				current_route.carrier_state = LogisticsRoute.CarrierState.IDLE
			_carrier_active_route[npc_id] = cand.id
			_carrier_idle_cooldown.erase(npc_id)
			_begin_travel_to_source(cand, from_tile)
			return
	# No route has work — wait in place. Set cooldown so _service_carriers doesn't rescan
	# every tick; the carrier is re-evaluated once the cooldown expires.
	var keep: LogisticsRoute = current_route if current_route != null else routes[0]
	_carrier_active_route[npc_id] = keep.id
	if keep.carrier_state != LogisticsRoute.CarrierState.IDLE:
		_set_carrier_state(keep, LogisticsRoute.CarrierState.IDLE)
	_carrier_idle_cooldown[npc_id] = IDLE_RECHECK_INTERVAL

## Begins a TRAVEL_TO_SOURCE leg for `route` from `from_tile` (the carrier's current position),
## pathfinding when the grid is available. _set_carrier_state applies F4 + records leg duration.
func _begin_travel_to_source(route: LogisticsRoute, from_tile: Vector2i) -> void:
	var source_tile: Vector2i = _get_building_tile(route.source_building_id)
	route.npc_start_pos = from_tile
	if _grid_map != null:
		var pr: PathResult = LogisticsPathfinder.find_path(from_tile, source_tile, _grid_map)
		if pr.found:
			route.remaining_ticks = int(floor(pr.cost * TICKS_PER_TILE))
			route.cached_path_cost_current_leg = pr.cost
			route.current_leg_path = pr.path
		else:
			route.remaining_ticks = _calc_travel_time(from_tile, source_tile)
			route.cached_path_cost_current_leg = float(route.remaining_ticks) / TICKS_PER_TILE
			route.current_leg_path = [from_tile, source_tile]
	else:
		route.remaining_ticks = _calc_travel_time(from_tile, source_tile)
		route.cached_path_cost_current_leg = float(route.remaining_ticks) / TICKS_PER_TILE
		route.current_leg_path = [from_tile, source_tile]
	_set_carrier_state(route, LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE)

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
				# Pre-pickup space check: if the destination is already full, picking up cargo
				# would land the carrier in WAITING_DESTINATION with no way to unblock (the
				# building can't consume because it needs a *different* resource that this same
				# carrier would normally deliver on another route — deadlock). Skip this route
				# and let _carrier_pick_next try the other routes first.
				if not _destination_has_space(route):
					_carrier_pick_next(route.npc_id, route)
				else:
					_do_pickup(route)
					if route.path_valid:
						route.remaining_ticks = int(floor(route.cached_path_cost * TICKS_PER_TILE))
						route.current_leg_path = route.cached_path
					else:
						var dest_tile: Vector2i = _get_building_tile(route.destination_building_id)
						var src_tile: Vector2i = _get_building_tile(route.source_building_id)
						route.remaining_ticks = _calc_travel_time(src_tile, dest_tile)
						route.current_leg_path = [src_tile, dest_tile]
					# Capture the nominal delivery duration BEFORE _set_carrier_state applies F4
					# efficiency scaling — Experience System grants time-based XP from this at unload.
					route.delivery_leg_nominal_ticks = route.remaining_ticks
					_set_carrier_state(route, LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION)
			else:
				# No cargo here (carrier empty) → free to move on. Try the carrier's other routes;
				# if none has work, it idles in place. (Was: WAITING_SOURCE / wait forever.)
				_carrier_pick_next(route.npc_id, route)

		LogisticsRoute.CarrierState.WAITING_SOURCE:
			# Legacy state (no longer entered by new code; kept for save-file compatibility).
			# Carrier is empty here → route it through the shared-carrier decision point.
			_carrier_pick_next(route.npc_id, route)

		LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION:
			route.remaining_ticks -= 1
			if route.remaining_ticks <= 0:
				_set_carrier_state(route, LogisticsRoute.CarrierState.AT_DESTINATION)
				if _npc_system != null:
					_npc_system.on_npc_at_location(route.npc_id, route.destination_building_id)

		LogisticsRoute.CarrierState.AT_DESTINATION:
			var has_space: bool = _destination_has_space(route)
			if has_space:
				if _do_deposit(route):
					route.cargo = 0
					route.cargo_resource = null
					if _npc_system != null:
						_npc_system.add_pending_xp(route.npc_id,
								ExperienceFormulas.xp_for_carrier(route.delivery_leg_nominal_ticks))
					# Delivered → decision point: switch to the next route with work (round-robin).
					_carrier_pick_next(route.npc_id, route)
				else:
					_set_carrier_state(route, LogisticsRoute.CarrierState.WAITING_DESTINATION)
			else:
				_set_carrier_state(route, LogisticsRoute.CarrierState.WAITING_DESTINATION)

		LogisticsRoute.CarrierState.WAITING_DESTINATION:
			# Holding cargo and the destination was full — must wait here (switching now would
			# pick up new cargo before delivering the held one, destroying it). Once space frees,
			# deposit and go to the decision point.
			var has_space: bool = _destination_has_space(route)
			if has_space:
				if _do_deposit(route):
					route.cargo = 0
					route.cargo_resource = null
					if _npc_system != null:
						_npc_system.add_pending_xp(route.npc_id,
								ExperienceFormulas.xp_for_carrier(route.delivery_leg_nominal_ticks))
					_carrier_pick_next(route.npc_id, route)

		LogisticsRoute.CarrierState.RETURN_HOME:
			route.remaining_ticks -= 1
			if route.remaining_ticks <= 0:
				if route.active:
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
## On entry to a travel leg, scales the freshly-set base travel ticks by the carrier's
## food-efficiency (F4): effective = floor(base / efficiency). Starving carriers crawl;
## bread-fed carriers haul faster. Applied once per transition (remaining_ticks is the base
## value set by the caller just before this call).
func _set_carrier_state(route: LogisticsRoute, new_state: int) -> void:
	if new_state == LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE \
			or new_state == LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION \
			or new_state == LogisticsRoute.CarrierState.RETURN_HOME:
		route.remaining_ticks = EfficiencyFormulas.calculate_effective_travel_ticks(
				route.remaining_ticks, _carrier_efficiency(route))
		# Capture the effective leg duration so the overlay animations stay in sync with F4.
		route.current_leg_total_ticks = route.remaining_ticks
	route.carrier_state = new_state
	if _npc_system != null:
		_npc_system.set_carrier_state(route.npc_id, new_state)


## Returns the carrier NPC's current efficiency (food-driven), or 1.0 if unavailable.
func _carrier_efficiency(route: LogisticsRoute) -> float:
	if _npc_system == null:
		return 1.0
	var npc: Object = _npc_system.get_npc_instance(route.npc_id)
	if npc == null or npc.efficiency <= 0.0:
		return 1.0
	return npc.efficiency


## Returns the tile position of a building, or Vector2i(-1,-1) if not found.
func _get_building_tile(building_id: StringName) -> Vector2i:
	if _building_registry == null:
		return Vector2i(-1, -1)
	return _building_registry.get_building_tile(str(building_id))


## Returns true if the destination building can accept the carrier's current cargo
## (or at least 1 item when cargo is not yet loaded — pre-trip check).
## Storage buildings: checks InventoryContainer total against capacity, accounting for cargo qty.
## Production buildings: checks input_buffer against input_capacity (PRODUCTION_TABLE).
func _destination_has_space(route: LogisticsRoute) -> bool:
	if _building_registry == null:
		return true
	var dest_id := str(route.destination_building_id)
	var instance: Object = _building_registry.get_building_instance(dest_id)
	if instance == null:
		return true
	# Storage buildings: check InventoryContainer capacity.
	# Use the actual cargo quantity so try_deposit won't fail atomically on a near-full store.
	# Before pickup cargo == 0, so we need at least 1 free unit — use needed = max(cargo, 1).
	if BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		if _inventory_system == null:
			return true
		var container_id: StringName = _get_container_id(route.destination_building_id)
		var used: int = _inventory_system.get_total_quantity(container_id)
		var cap: int = _inventory_system.get_capacity(container_id)
		var needed: int = maxi(route.cargo, 1)
		if used + needed > cap:
			return false
		# Per-resource delivery limit set by the player.
		var res_id: StringName = route.cargo_resource \
			if route.cargo_resource != null else route.source_item_id
		if res_id != &"":
			var limit: int = instance.storage_limits.get(res_id, -1)
			if limit >= 0:
				var current_of_res: int = _inventory_system.get_resource_quantity(container_id, res_id)
				if current_of_res >= limit:
					return false
		return true
	# Production buildings: check per-slot input_capacity from PRODUCTION_TABLE.
	# Before pickup cargo_resource is null — fall back to source_item_id so the pre-trip check
	# still gates on destination capacity instead of blindly returning true.
	var resource_to_check: StringName = route.cargo_resource \
		if route.cargo_resource != null else route.source_item_id
	if resource_to_check == &"":
		return true
	return not _building_registry.is_input_full(dest_id, resource_to_check)


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
## For storage sources: checks InventorySystem for route.source_item_id,
## then respects the storage_min_limit (items at or below the reserve are untouchable).
## For production sources: checks buffered_output, filtered by source_item_id when set.
func _source_has_cargo(route: LogisticsRoute) -> bool:
	if _is_storage_source(route):
		if route.source_item_id == &"" or _inventory_system == null:
			return false
		var container_id := _get_container_id(route.source_building_id)
		var qty: int = _inventory_system.get_resource_quantity(container_id, route.source_item_id)
		if _building_registry != null:
			var src: Object = _building_registry.get_building_instance(str(route.source_building_id))
			if src != null:
				var min_lim: int = src.storage_min_limits.get(route.source_item_id, -1)
				if min_lim >= 0:
					return qty > min_lim
		return qty >= 1
	if _building_registry == null:
		return false
	if route.source_item_id != &"":
		return _building_registry.get_output_buffer_resource_quantity(
			str(route.source_building_id), route.source_item_id) > 0
	return _building_registry.has_output_buffer(str(route.source_building_id))


## Deposits route.cargo into the destination building.
## Storage destination: deposits into InventoryContainer via InventorySystem.
## Production destination: adds directly to input_buffer via receive_input_from_world.
## Returns true on success; false when the deposit was rejected (cargo must NOT be cleared).
func _do_deposit(route: LogisticsRoute) -> bool:
	if _building_registry == null:
		return false
	var dest_id := str(route.destination_building_id)
	var instance: Object = _building_registry.get_building_instance(dest_id)
	if instance != null and BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		if _inventory_system == null:
			return false
		var result: InventoryContainer.DepositResult = _inventory_system.try_deposit(
			_get_container_id(route.destination_building_id),
			route.cargo_resource,
			route.cargo)
		if result != InventoryContainer.DepositResult.SUCCESS:
			return false
	else:
		if not _building_registry.receive_input_from_world(dest_id, route.cargo_resource, route.cargo):
			return false
	_route_items_today[route.id] = _route_items_today.get(route.id, 0) + route.cargo
	return true


## Picks up cargo from the source building and sets route.cargo / route.cargo_resource.
## Effective carrier capacity for a route's NPC: base + Packesel perk bonus (Perk System #5).
func _carrier_capacity(route: LogisticsRoute) -> int:
	var bonus: int = 0
	if _npc_system != null:
		bonus = int(_npc_system.npc_perk_bonus(route.npc_id, PerkRegistry.EFFECT_CARRIER_CAPACITY))
	return CARRIER_CAPACITY + bonus


## Storage source: consumes route.source_item_id from InventoryContainer.
## Production source: removes from buffered_output, filtered by source_item_id when set.
func _do_pickup(route: LogisticsRoute) -> void:
	if _is_storage_source(route):
		var container_id := _get_container_id(route.source_building_id)
		var available: int = _inventory_system.get_resource_quantity(container_id, route.source_item_id)
		var effective_available: int = available
		if _building_registry != null:
			var src: Object = _building_registry.get_building_instance(str(route.source_building_id))
			if src != null:
				var min_lim: int = src.storage_min_limits.get(route.source_item_id, -1)
				if min_lim >= 0:
					effective_available = maxi(0, available - min_lim)
		var pickup: int = mini(effective_available, _carrier_capacity(route))
		_inventory_system.try_consume(container_id, route.source_item_id, pickup)
		route.cargo = pickup
		route.cargo_resource = route.source_item_id
	else:
		var res_id: StringName
		if route.source_item_id != &"":
			res_id = route.source_item_id
		else:
			res_id = _building_registry.get_output_buffer_resource(str(route.source_building_id))
		var available: int = _building_registry.get_output_buffer_resource_quantity(
			str(route.source_building_id), res_id)
		var pickup: int = mini(available, _carrier_capacity(route))
		_building_registry.remove_from_output(str(route.source_building_id), res_id, pickup)
		route.cargo = pickup
		route.cargo_resource = res_id


## Manhattan distance travel time in ticks. Uses floor() per Formula 1 (ADR-0011).
func _calc_travel_time(from: Vector2i, to: Vector2i) -> int:
	var dist: int = absi(to.x - from.x) + absi(to.y - from.y)
	return int(floor(float(dist) * TICKS_PER_TILE))


## Returns the maximum number of INPUT routes allowed for building_id.
## Derived from the number of distinct input resources in the building's active recipe.
## Falls back to MAX_INPUT_SLOTS for storage buildings and unknown types.
func _get_max_input_slots(building_id: StringName) -> int:
	if _building_registry == null:
		return MAX_INPUT_SLOTS
	var instance: Object = _building_registry.get_building_instance(str(building_id))
	if instance == null:
		return MAX_INPUT_SLOTS
	if BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		return MAX_INPUT_SLOTS
	if not BuildingRegistry.is_production_building(instance.type):
		return MAX_INPUT_SLOTS
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	var inputs: Array = recipe.get("inputs", [])
	return maxi(inputs.size(), 1)


## Deletes routes that are no longer compatible with a building's new active recipe.
## Called when BuildingRegistry emits building_recipe_changed.
## INPUT routes delivering a resource no longer in the recipe's inputs are deleted.
## OUTPUT routes picking up a specific resource no longer in the recipe's outputs are deleted.
## Wildcard OUTPUT routes (source_item_id == "") are kept — they work for any output.
func _on_building_recipe_changed(building_id: String, _recipe_index: int) -> void:
	if _building_registry == null:
		return
	var instance: Object = _building_registry.get_building_instance(building_id)
	if instance == null:
		return
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	var new_input_ids: Array[StringName] = []
	for spec: Dictionary in recipe.get("inputs", []):
		new_input_ids.append(spec["resource_id"])
	var new_output_ids: Array = recipe.get("output", {}).keys()
	var building_sn := StringName(building_id)
	var to_delete: Array[StringName] = []
	for route: LogisticsRoute in _active_routes:
		if not route.active:
			continue
		if route.route_type == LogisticsRoute.RouteType.INPUT \
				and route.destination_building_id == building_sn:
			if route.source_item_id != &"" and route.source_item_id not in new_input_ids:
				to_delete.append(route.id)
		elif route.route_type == LogisticsRoute.RouteType.OUTPUT \
				and route.source_building_id == building_sn:
			if route.source_item_id != &"" and route.source_item_id not in new_output_ids:
				to_delete.append(route.id)
	for route_id: StringName in to_delete:
		delete_route(route_id)


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
	# Reconstruct the shared-carrier active-route map: a non-IDLE route is the one its carrier
	# was executing. First non-IDLE route per carrier wins; the rest stay dormant.
	_carrier_active_route.clear()
	for route: LogisticsRoute in _active_routes:
		if route.active and route.carrier_state != LogisticsRoute.CarrierState.IDLE \
				and not _carrier_active_route.has(route.npc_id):
			_carrier_active_route[route.npc_id] = route.id


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
		"current_leg_total_ticks": route.current_leg_total_ticks,
		"delivery_leg_nominal_ticks": route.delivery_leg_nominal_ticks,
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
		"stats_items_last_day": route.stats_items_last_day,
		"stats_active_ticks_last_day": route.stats_active_ticks_last_day,
		"stats_data_available": route.stats_data_available,
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
	route.current_leg_total_ticks = data.get("current_leg_total_ticks", 0)
	route.delivery_leg_nominal_ticks = data.get("delivery_leg_nominal_ticks", 0)
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
	route.stats_items_last_day = data.get("stats_items_last_day", 0)
	route.stats_active_ticks_last_day = data.get("stats_active_ticks_last_day", 0)
	route.stats_data_available = data.get("stats_data_available", false)
	return route


## Handles building status and slot changes when a route becomes inactive.
## Called from delete_route() and _deactivate_route().
## INPUT route deactivated → destination building BLOCKED (no input carrier).
## OUTPUT route deactivated → source slot cleared; STALLED is deferred until next
##   production cycle completes with empty output buffer (per GDD Core Rules 6).
func _on_route_active_changed(route: LogisticsRoute) -> void:
	# Shared carrier: if this route was the one the carrier was executing, drop the active-route
	# entry so _service_carriers reassigns the carrier to another of its routes next tick.
	if not route.active and _carrier_active_route.get(route.npc_id, &"") == route.id:
		_carrier_active_route.erase(route.npc_id)
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
