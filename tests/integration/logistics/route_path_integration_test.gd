## GdUnit4 integration test suite for Logistics System Story 011:
## Logistics Route Path Integration (ADR-0013).
##
## Tests verify that:
##   - LogisticsRoute stores cached_path, cached_path_cost, and path_valid at creation
##   - create_route() returns FAILURE when A* finds no viable path
##   - Carrier FSM uses cached_path_cost (not Manhattan distance) for travel ticks
##   - Flat map degrades gracefully to the same result as the original formula
##   - Resource tiles increase carrier travel time proportionally
##
## AC coverage:
##   AC-1 — Route creation stores path and cost (path_valid == true)
##   AC-2 — Route creation blocked when impassable column separates buildings
##   AC-3 — TRAVEL_TO_DESTINATION uses cached_path_cost × TICKS_PER_TILE
##   AC-4 — Flat map: path_cost == Manhattan distance → same remaining_ticks
##   AC-5 — Resource belt increases travel time proportionally

extends GdUnitTestSuite

const LogisticsSystemScript := preload("res://src/systems/logistics/logistics_system.gd")
const LogisticsRouteScript  := preload("res://src/systems/logistics/logistics_route.gd")

const TICKS_PER_TILE: float = 3.0

# ---- MockGrid ---------------------------------------------------------------

## Minimal grid stub implementing the duck-typed pathfinder interface.
## Costs are set per-tile; all other tiles default to 1.0 (open ground).
## Impassable tiles are added to _blocked.
class MockGrid:
	var _tile_costs: Dictionary = {}   # Vector2i → float
	var _blocked: Dictionary = {}      # Vector2i → true
	var grid_size: int = 30

	func set_tile_cost(pos: Vector2i, cost: float) -> void:
		_tile_costs[pos] = cost

	func block_tile(pos: Vector2i) -> void:
		_blocked[pos] = true

	## Block every tile in a vertical column from y=0 to y=(grid_size-1).
	func block_column(x: int) -> void:
		for y in range(grid_size):
			block_tile(Vector2i(x, y))

	func get_tile_movement_cost(pos: Vector2i) -> float:
		if pos.x < 0 or pos.y < 0 or pos.x >= grid_size or pos.y >= grid_size:
			return INF
		if _blocked.has(pos):
			return INF
		return _tile_costs.get(pos, 1.0)

	func is_tile_passable(pos: Vector2i) -> bool:
		return get_tile_movement_cost(pos) != INF


# ---- Stubs ------------------------------------------------------------------

class NPCStub extends Node:
	var npc_position: Vector2i = Vector2i.ZERO

	func set_carrier_state(_npc_id: StringName, _state: int) -> void:
		pass

	func get_npc_position(_npc_id: StringName) -> Vector2i:
		return npc_position

	func is_available(_npc_id: StringName) -> bool:
		return true

	func release_npc(_npc_id: StringName) -> void:
		pass

	func on_npc_at_location(_npc_id: StringName, _building_id: StringName) -> void:
		pass


class BuildingRegistryStub extends Node:
	var building_tiles: Dictionary = {}   # StringName → Vector2i
	var output_buffers: Dictionary = {}   # StringName → {resource: qty}

	func get_building_tile(building_id: String) -> Vector2i:
		return building_tiles.get(StringName(building_id), Vector2i(-1, -1))

	func has_output_buffer(building_id: String) -> bool:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		return not buf.is_empty()

	func get_output_buffer_total(building_id: String) -> int:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		var total: int = 0
		for v: int in buf.values():
			total += v
		return total

	func get_output_buffer_resource(building_id: String) -> StringName:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		if buf.is_empty():
			return &""
		return buf.keys()[0]

	func remove_from_output(building_id: String, resource: StringName, qty: int) -> void:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		if buf.has(resource):
			buf[resource] = max(0, buf[resource] - qty)
			output_buffers[StringName(building_id)] = buf

	func assign_output_carrier(_building_id: String, _npc_id: StringName) -> void:
		pass

	func add_input_carrier(_building_id: String, _npc_id: StringName) -> void:
		pass

	func remove_input_carrier(_building_id: String, _npc_id: StringName) -> void:
		pass

	func set_status(_building_id: String, _status: int) -> void:
		pass

	func get_building_instance(_building_id: String) -> Object:
		return null

	func set_output(building_id: StringName, resource: StringName, qty: int) -> void:
		output_buffers[building_id] = {resource: qty}


class InventoryStub extends Node:
	func get_slot_count(_id: StringName) -> int:
		return 100

	func get_occupied_slots(_id: StringName) -> int:
		return 0

	func try_deposit(_container_id: StringName, _resource_id: StringName, _quantity: int) -> Dictionary:
		return {"success": true}


# ---- Fixtures ---------------------------------------------------------------

var _logistics: LogisticsSystemScript
var _npc: NPCStub
var _buildings: BuildingRegistryStub
var _inventory: InventoryStub
var _grid: MockGrid

const SRC: StringName = &"building_src"
const DST: StringName = &"building_dst"
const NPC: StringName = &"npc_001"

## Source tile at (2, 5); destination at (8, 5) — 6 tiles apart on a flat row.
const SRC_TILE: Vector2i = Vector2i(2, 5)
const DST_TILE: Vector2i = Vector2i(8, 5)
## NPC home at (0, 5) — 2 tiles from source on flat ground.
const HOME_TILE: Vector2i = Vector2i(0, 5)


func before_test() -> void:
	_npc = NPCStub.new()
	add_child(_npc)
	auto_free(_npc)

	_buildings = BuildingRegistryStub.new()
	add_child(_buildings)
	auto_free(_buildings)
	_buildings.building_tiles[SRC] = SRC_TILE
	_buildings.building_tiles[DST] = DST_TILE

	_inventory = InventoryStub.new()
	add_child(_inventory)
	auto_free(_inventory)

	_grid = MockGrid.new()

	_logistics = LogisticsSystemScript.new()
	add_child(_logistics)
	auto_free(_logistics)
	_logistics._npc_system = _npc
	_logistics._building_registry = _buildings
	_logistics._inventory_system = _inventory
	_logistics._grid_map = _grid


func _create_flat_route() -> LogisticsRouteScript:
	_npc.npc_position = HOME_TILE
	var result: Dictionary = _logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)
	assert_bool(result["success"]).is_true()
	return result["route"]


# ---- AC-1: Route creation stores path and cost ------------------------------

func test_route_creation_stores_cached_path_and_cost_on_flat_map() -> void:
	# Arrange: flat grid, 6 tiles from SRC to DST
	# Act
	var result: Dictionary = _logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)

	# Assert
	assert_bool(result["success"]).is_true()
	var route: LogisticsRouteScript = result["route"]
	assert_bool(route.path_valid).is_true()
	assert_int(route.cached_path.size()).is_greater(0)
	assert_float(route.cached_path_cost).is_equal(6.0)


func test_route_creation_path_starts_at_source_ends_at_dest() -> void:
	# Arrange + Act
	var result: Dictionary = _logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]

	# Assert: path is ordered src → dst
	assert_object(route.cached_path.front()).is_equal(SRC_TILE)
	assert_object(route.cached_path.back()).is_equal(DST_TILE)


# ---- AC-2: Route creation blocked when no viable path ----------------------

func test_route_creation_fails_when_impassable_column_blocks_path() -> void:
	# Arrange: impassable column at x=5 between src(2,5) and dst(8,5)
	_grid.block_column(5)

	# Act
	var result: Dictionary = _logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)

	# Assert
	assert_bool(result["success"]).is_false()
	assert_str(result["error"]).contains("building_src")
	assert_str(result["error"]).contains("building_dst")


func test_route_creation_failure_leaves_no_active_routes() -> void:
	# Arrange: full impassable barrier
	_grid.block_column(5)

	# Act
	_logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)

	# Assert
	assert_int(_logistics.get_active_routes().size()).is_equal(0)


# ---- AC-3: TRAVEL_TO_DESTINATION uses cached_path_cost × TICKS_PER_TILE ----

func test_travel_to_destination_remaining_ticks_uses_path_cost_not_manhattan() -> void:
	# Arrange: resource tile at (5,5) cost 4.0; detour through (5,4) has cost 6.0;
	# direct (2,5)→(8,5) has cost 1+4+1+1+1+1 = but wait: (3,5)=1,(4,5)=1,(5,5)=4,(6,5)=1,(7,5)=1,(8,5)=1 = 9
	# Detour via row 4: (2,5)→(2,4)→...→(8,4)→(8,5) = 1+6+1 = 8 tiles (cost 8.0)
	# So A* takes detour (cheaper). Let's set cost to expect detour = 8.0 ticks × 3 = 24.
	# Actually let's simplify: resource tile has cost 4.0, detour cost = 8.0, direct = 9.0.
	# A* picks the detour: expected remaining_ticks = floor(8.0 × 3.0) = 24.
	_grid.set_tile_cost(Vector2i(5, 5), 4.0)
	_grid.set_tile_cost(Vector2i(4, 5), 4.0)
	_grid.set_tile_cost(Vector2i(3, 5), 4.0)
	# Direct path (3,5),(4,5),(5,5),(6,5),(7,5),(8,5) → cost = 4+4+4+1+1+1 = 15
	# Detour via row 4: cost = 1(2,4)+1(3,4)+1(4,4)+1(5,4)+1(6,4)+1(7,4)+1(8,4)+1(8,5) = 8
	# A* will pick detour at cost 8.0.
	_npc.npc_position = HOME_TILE
	var route: LogisticsRouteScript = _create_flat_route()

	# A* should have found the detour; cached_path_cost == 8.0
	# Give cargo so carrier transitions to TRAVEL_TO_DESTINATION
	_buildings.set_output(SRC, &"wood", 1)
	_logistics.start_route(route.id)

	# Advance until AT_SOURCE (home→source on flat = 2 tiles = 6 ticks)
	_logistics._advance_tick(10)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.AT_SOURCE)

	# One more tick: AT_SOURCE sees cargo, transitions to TRAVEL_TO_DESTINATION
	_logistics._advance_tick(1)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)

	# remaining_ticks must be floor(8.0 × 3.0) = 24 (not Manhattan 6 × 3 = 18)
	assert_int(route.remaining_ticks).is_equal(24)


# ---- AC-4: Flat map produces same result as original Manhattan formula ------

func test_flat_map_travel_ticks_equal_manhattan_formula() -> void:
	# Arrange: completely flat grid (default cost 1.0 per tile)
	# SRC_TILE(2,5) → DST_TILE(8,5): Manhattan distance = 6, path_cost = 6.0
	# Expected remaining_ticks = floor(6.0 × 3.0) = 18
	_npc.npc_position = HOME_TILE
	var route: LogisticsRouteScript = _create_flat_route()

	_buildings.set_output(SRC, &"wood", 1)
	_logistics.start_route(route.id)

	# Advance to AT_SOURCE
	_logistics._advance_tick(10)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.AT_SOURCE)

	# Transition to TRAVEL_TO_DESTINATION
	_logistics._advance_tick(1)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)
	assert_int(route.remaining_ticks).is_equal(18)


# ---- AC-5: Resource belt increases travel time proportionally ---------------

func test_resource_belt_increases_travel_time() -> void:
	# Arrange: resource tiles at (3,5),(4,5),(5,5) cost 4.0; walls block detour (y=4 row blocked).
	# Path MUST go through resource belt: cost = 4+4+4+1+1 = 14.0... wait let me recalculate.
	# SRC=(2,5), DST=(8,5), resource at (3,5),(4,5),(5,5) cost 4.0.
	# Direct path enters: (3,5)=4, (4,5)=4, (5,5)=4, (6,5)=1, (7,5)=1, (8,5)=1 → cost = 15.0
	# Block y=3 and y=7 rows to force direct path.
	for x in range(30):
		_grid.block_tile(Vector2i(x, 4))
		_grid.block_tile(Vector2i(x, 6))
	_grid.set_tile_cost(Vector2i(3, 5), 4.0)
	_grid.set_tile_cost(Vector2i(4, 5), 4.0)
	_grid.set_tile_cost(Vector2i(5, 5), 4.0)

	# HOME_TILE(0,5) is on row 5 — make sure walls don't block source tile row
	# (we only blocked y=4 and y=6, so row 5 is open)

	_npc.npc_position = HOME_TILE
	var route: LogisticsRouteScript = _create_flat_route()

	# cached_path_cost should be 15.0 (forced through belt)
	assert_float(route.cached_path_cost).is_equal(15.0)

	_buildings.set_output(SRC, &"wood", 1)
	_logistics.start_route(route.id)

	# Advance to AT_SOURCE (home(0,5)→src(2,5) = 2 tiles, no resource tiles on home path)
	_logistics._advance_tick(10)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.AT_SOURCE)

	# Transition to TRAVEL_TO_DESTINATION
	_logistics._advance_tick(1)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)

	# remaining_ticks = floor(15.0 × 3.0) = 45
	assert_int(route.remaining_ticks).is_equal(45)


# ---- Home leg caching -------------------------------------------------------

func test_start_route_caches_home_to_source_cost() -> void:
	# Arrange: flat grid, home(0,5)→src(2,5) = 2 tiles
	_npc.npc_position = HOME_TILE
	var route: LogisticsRouteScript = _create_flat_route()

	# Act
	_logistics.start_route(route.id)

	# Assert
	assert_bool(route.home_legs_valid).is_true()
	assert_float(route.cached_path_cost_home_to_source).is_equal(2.0)


func test_start_route_caches_dest_to_home_cost() -> void:
	# Arrange: flat grid, dst(8,5)→home(0,5) = 8 tiles
	_npc.npc_position = HOME_TILE
	var route: LogisticsRouteScript = _create_flat_route()

	# Act
	_logistics.start_route(route.id)

	# Assert
	assert_float(route.cached_path_cost_dest_to_home).is_equal(8.0)


func test_return_home_from_destination_uses_cached_cost() -> void:
	# Arrange: flat grid, dst(8,5)→home(0,5) = 8 tiles → floor(8 × 3) = 24
	_npc.npc_position = HOME_TILE
	var route: LogisticsRouteScript = _create_flat_route()

	_buildings.set_output(SRC, &"wood", 1)
	_logistics.start_route(route.id)

	# Advance to AT_SOURCE then to TRAVEL_TO_DESTINATION, then to AT_DESTINATION
	_logistics._advance_tick(10)   # reach AT_SOURCE
	_logistics._advance_tick(1)    # pickup → TRAVEL_TO_DESTINATION (18 ticks remaining)
	_logistics._advance_tick(18)   # reach AT_DESTINATION
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.AT_DESTINATION)

	# One tick: deposit → RETURN_HOME
	_logistics._advance_tick(1)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)
	assert_int(route.remaining_ticks).is_equal(24)
