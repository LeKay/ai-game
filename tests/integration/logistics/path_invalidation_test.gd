## GdUnit4 integration test suite for Logistics System Story 012:
## Path Invalidation on Terrain Change (ADR-0013, TR-logistics-018).
##
## Tests verify that:
##   - LogisticsSystem subscribes to WorldGrid.terrain_changed via set_grid_map()
##   - terrain_changed marks intersecting cached paths invalid synchronously
##   - Deferred recalculation updates path when a detour exists
##   - Active routes with no recalculated path transition to DEACTIVATED
##   - DEACTIVATED routes are NOT auto-reactivated when terrain clears (player reactivates)
##   - In-flight carrier completes current leg using original remaining_ticks
##   - Carriers in WAITING state are not immediately interrupted
##   - Routes whose cached path doesn't cross the changed tile are unaffected
##
## AC coverage:
##   AC-1 — set_grid_map() connects terrain_changed signal
##   AC-2 — terrain_changed marks routes intersecting pos as path_valid = false
##   AC-3 — Successful recalculation: cached_path updated, path_valid = true
##   AC-4 — Failed recalculation: active route transitions to DEACTIVATED
##   AC-5 — In-flight carrier: remaining_ticks unchanged after path recalculation
##   AC-6 — DEACTIVATED route: path_valid updated but lifecycle stays DEACTIVATED
##   AC-7 — WAITING carrier not interrupted; carrier_state preserved

extends GdUnitTestSuite

const LogisticsSystemScript := preload("res://src/systems/logistics/logistics_system.gd")
const LogisticsRouteScript  := preload("res://src/systems/logistics/logistics_route.gd")

# ---- MockGridWithSignal -----------------------------------------------------

## Mock WorldGrid implementing the duck-typed pathfinder interface plus terrain_changed signal.
## Extends Node so it can be passed to set_grid_map(grid: Node) without type mismatch.
class MockGridWithSignal extends Node:
	signal terrain_changed(pos: Vector2i, layer: int)

	var _tile_costs: Dictionary = {}
	var _blocked: Dictionary = {}
	const GRID_SIZE: int = 30

	func set_tile_cost(pos: Vector2i, cost: float) -> void:
		_tile_costs[pos] = cost

	func block_tile(pos: Vector2i) -> void:
		_blocked[pos] = true

	func block_column(x: int) -> void:
		for y in range(GRID_SIZE):
			block_tile(Vector2i(x, y))

	func get_tile_movement_cost(pos: Vector2i) -> float:
		if pos.x < 0 or pos.y < 0 or pos.x >= GRID_SIZE or pos.y >= GRID_SIZE:
			return INF
		if _blocked.has(pos):
			return INF
		return _tile_costs.get(pos, 1.0)

	func is_tile_passable(pos: Vector2i) -> bool:
		return get_tile_movement_cost(pos) != INF

	func emit_terrain_changed(pos: Vector2i, layer: int = 1) -> void:
		terrain_changed.emit(pos, layer)

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
	var building_tiles: Dictionary = {}

	func get_building_tile(building_id: String) -> Vector2i:
		return building_tiles.get(StringName(building_id), Vector2i(-1, -1))

	func has_output_buffer(_building_id: String) -> bool:
		return false

	func get_output_buffer_total(_building_id: String) -> int:
		return 0

	func get_output_buffer_resource(_building_id: String) -> StringName:
		return &""

	func remove_from_output(_building_id: String, _resource: StringName, _qty: int) -> void:
		pass

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


class InventoryStub extends Node:
	func get_slot_count(_id: StringName) -> int:
		return 100

	func get_occupied_slots(_id: StringName) -> int:
		return 0

# ---- Fixtures ---------------------------------------------------------------

var _logistics: LogisticsSystemScript
var _npc: NPCStub
var _buildings: BuildingRegistryStub
var _grid: MockGridWithSignal

const SRC: StringName = &"building_src"
const DST: StringName = &"building_dst"
const NPC: StringName = &"npc_001"

## Source at (2,5); destination at (8,5) — 6 tiles apart on a flat row.
const SRC_TILE: Vector2i = Vector2i(2, 5)
const DST_TILE: Vector2i = Vector2i(8, 5)
## NPC home at (0,5) — 2 tiles from source on flat ground.
const HOME_TILE: Vector2i = Vector2i(0, 5)
## Mid-path tile lying on the straight SRC→DST route.
const MID_TILE: Vector2i = Vector2i(4, 5)


func before_test() -> void:
	_npc = NPCStub.new()
	add_child(_npc)
	auto_free(_npc)

	_buildings = BuildingRegistryStub.new()
	add_child(_buildings)
	auto_free(_buildings)
	_buildings.building_tiles[SRC] = SRC_TILE
	_buildings.building_tiles[DST] = DST_TILE

	var inventory := InventoryStub.new()
	add_child(inventory)
	auto_free(inventory)

	_grid = MockGridWithSignal.new()
	add_child(_grid)
	auto_free(_grid)

	_logistics = LogisticsSystemScript.new()
	add_child(_logistics)
	auto_free(_logistics)
	_logistics._npc_system = _npc
	_logistics._building_registry = _buildings
	_logistics._inventory_system = inventory
	_logistics.set_grid_map(_grid)


func _make_route() -> LogisticsRouteScript:
	_npc.npc_position = HOME_TILE
	var result: Dictionary = _logistics.create_route(
			SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)
	assert_bool(result["success"]).is_true()
	return result["route"]


# ---- AC-1: Signal subscription ----------------------------------------------

func test_set_grid_map_connects_terrain_changed_signal() -> void:
	# Assert that _on_terrain_changed is connected after set_grid_map() is called.
	assert_bool(_grid.terrain_changed.is_connected(_logistics._on_terrain_changed)).is_true()


# ---- AC-2: Path invalidation ------------------------------------------------

func test_terrain_changed_marks_intersecting_route_path_invalid() -> void:
	# Arrange: route whose cached path passes through MID_TILE(4,5)
	var route := _make_route()
	assert_bool(route.path_valid).is_true()

	# Act: terrain changes at MID_TILE
	_grid.emit_terrain_changed(MID_TILE)

	# Assert: path_valid = false immediately (synchronous, before deferred recalculation)
	assert_bool(route.path_valid).is_false()


# ---- AC-6 (unrelated route unaffected) -------------------------------------

func test_terrain_changed_does_not_mark_unrelated_route_invalid() -> void:
	# Arrange: route SRC→DST along row 5; terrain changes at a tile not on the path
	var route := _make_route()
	const OFF_ROUTE: Vector2i = Vector2i(4, 10)

	# Act
	_grid.emit_terrain_changed(OFF_ROUTE)

	# Assert: route unaffected
	assert_bool(route.path_valid).is_true()


# ---- AC-3: Successful recalculation -----------------------------------------

func test_recalculation_restores_path_when_detour_exists() -> void:
	# Arrange: block MID_TILE(4,5) after route creation; detour via row 4 is open
	var route := _make_route()
	_grid.block_tile(MID_TILE)

	# Act: invalidation + recalculation
	_grid.emit_terrain_changed(MID_TILE)
	_logistics._recalculate_invalid_paths()

	# Assert: new path found; MID_TILE not in path; path_valid restored
	assert_bool(route.path_valid).is_true()
	assert_bool(route.cached_path.has(MID_TILE)).is_false()
	assert_int(route.cached_path.size()).is_greater(0)
	assert_bool(route.active).is_true()


# ---- AC-4: Failed recalculation → DEACTIVATED --------------------------------

func test_recalculation_deactivates_active_route_when_no_path_exists() -> void:
	# Arrange: block a full column so no detour is possible
	var route := _make_route()
	_grid.block_column(4)

	# Act
	_grid.emit_terrain_changed(Vector2i(4, 5))
	_logistics._recalculate_invalid_paths()

	# Assert: route DEACTIVATED; active = false; path still invalid
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.DEACTIVATED)
	assert_bool(route.active).is_false()
	assert_bool(route.path_valid).is_false()


# ---- AC-6 (DEACTIVATED not auto-reactivated on unblock) ---------------------

func test_deactivated_route_not_reactivated_when_terrain_clears() -> void:
	# Arrange: deactivate route by blocking all paths
	var route := _make_route()
	_grid.block_column(4)
	_grid.emit_terrain_changed(Vector2i(4, 5))
	_logistics._recalculate_invalid_paths()
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.DEACTIVATED)

	# Act: clear the block (terrain unblocked) and trigger recalculation
	_grid._blocked.clear()
	_grid.emit_terrain_changed(Vector2i(4, 5))
	_logistics._recalculate_invalid_paths()

	# Assert: path is valid again but lifecycle state stays DEACTIVATED (player must reactivate)
	assert_bool(route.path_valid).is_true()
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.DEACTIVATED)
	assert_bool(route.active).is_false()


# ---- AC-5: In-flight carrier not interrupted --------------------------------

func test_inflight_carrier_remaining_ticks_unchanged_after_path_recalculation() -> void:
	# Arrange: carrier manually placed in TRAVEL_TO_DESTINATION with remaining_ticks = 10
	var route := _make_route()
	route.carrier_state = LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION
	route.remaining_ticks = 10

	# Act: terrain change on a tile in the path; recalculation succeeds (no block, new path found)
	_grid.emit_terrain_changed(MID_TILE)
	_logistics._recalculate_invalid_paths()

	# Assert: remaining_ticks untouched — carrier finishes current leg with original countdown
	assert_int(route.remaining_ticks).is_equal(10)


# ---- AC-7: WAITING carrier not immediately interrupted ----------------------

func test_waiting_carrier_state_preserved_after_deactivation() -> void:
	# Arrange: carrier in WAITING_SOURCE (legacy state from an old save)
	var route := _make_route()
	route.carrier_state = LogisticsRouteScript.CarrierState.WAITING_SOURCE

	# Act: block all paths → route deactivated during recalculation
	_grid.block_column(4)
	_grid.emit_terrain_changed(Vector2i(4, 5))
	_logistics._recalculate_invalid_paths()

	# Assert: route DEACTIVATED but carrier_state unchanged;
	# interruption deferred to next tick processing cycle (not applied synchronously).
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.DEACTIVATED)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)
