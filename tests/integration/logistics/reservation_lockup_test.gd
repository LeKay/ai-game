## GdUnit4 integration test — Carrier reservation prevents the storage-full lockup.
##
## Regression scenario (2026-06-28):
##   Before the fix, an NPC carrier could pick up cargo at a production building
##   bound for a storage that was nearly full. While the carrier was en route, a
##   player drag (or another route) could fill the storage to capacity. On arrival,
##   the carrier hit FAILURE_FULL and stayed in WAITING_DESTINATION forever — and
##   because one NPC serves one active route at a time, all of its other routes
##   were paused too. The fix: at pickup time, the carrier reserves destination
##   space, so foreign depositors see no free room and the carrier always has its
##   space waiting on arrival.
##
## These tests use a real InventorySystem (so the reservation API is exercised end
## to end) and stub buildings/NPCs to keep the test deterministic.

extends GdUnitTestSuite

const LogisticsSystemScript := preload("res://src/systems/logistics/logistics_system.gd")
const LogisticsRouteScript  := preload("res://src/systems/logistics/logistics_route.gd")
const InventoryScript       := preload("res://src/systems/inventory/inventory_system.gd")


class NPCStub extends Node:
	var npc_position: Vector2i = Vector2i.ZERO
	func set_carrier_state(_npc_id: StringName, _state: int) -> void: pass
	func get_npc_position(_npc_id: StringName) -> Vector2i: return npc_position
	func get_npc_instance(_npc_id: StringName) -> Object: return null
	func is_available(_npc_id: StringName) -> bool: return true
	func release_npc(_npc_id: StringName) -> void: pass
	func on_npc_at_location(_npc_id: StringName, _building_id: StringName) -> void: pass
	func add_pending_xp(_npc_id: StringName, _amount: int) -> void: pass
	func npc_perk_bonus(_npc_id: StringName, _effect: StringName) -> float: return 0.0


class BuildingInstanceStub:
	var type: int = 0
	var assigned_container_id: StringName = &""
	var storage_limits: Dictionary = {}
	var storage_min_limits: Dictionary = {}


class BuildingRegistryStub extends Node:
	var building_tiles: Dictionary = {}
	var output_buffers: Dictionary = {}
	var instances: Dictionary = {}

	func get_building_tile(building_id: String) -> Vector2i:
		return building_tiles.get(StringName(building_id), Vector2i(-1, -1))
	func get_building_instance(building_id: String) -> Object:
		return instances.get(StringName(building_id), null)
	func has_output_buffer(building_id: String) -> bool:
		return not output_buffers.get(StringName(building_id), {}).is_empty()
	func get_output_buffer_resource(building_id: String) -> StringName:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		return &"" if buf.is_empty() else buf.keys()[0]
	func get_output_buffer_resource_quantity(building_id: String, resource_id: StringName) -> int:
		return output_buffers.get(StringName(building_id), {}).get(resource_id, 0)
	func remove_from_output(building_id: String, resource_id: StringName, qty: int) -> bool:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		if buf.get(resource_id, 0) < qty: return false
		buf[resource_id] -= qty
		if buf[resource_id] <= 0: buf.erase(resource_id)
		return true
	func receive_input_from_world(_bid: String, _rid: StringName, _qty: int, _holder: StringName = &"") -> bool:
		return true
	func is_input_full(_bid: String, _rid: StringName) -> bool:
		return false
	func reserve_input_slot(_bid: String, _rid: StringName, _holder: StringName, _qty: int) -> bool:
		return true
	func release_input_reservation(_bid: String, _holder: StringName) -> void: pass
	func assign_output_carrier(_bid: String, _carrier_id: StringName) -> void: pass
	func add_input_carrier(_bid: String, _carrier_id: StringName) -> void: pass
	func remove_input_carrier(_bid: String, _carrier_id: StringName) -> void: pass
	func set_status(_bid: StringName, _new_state: int, _reason: String = "") -> void: pass
	func set_output(building_id: StringName, resource: StringName, qty: int) -> void:
		output_buffers[building_id] = {resource: qty}

	# Mimic the real BuildingRegistry.STORAGE_CAPACITY dictionary lookup used by LogisticsSystem
	# (`BuildingRegistry.STORAGE_CAPACITY.has(instance.type)`). The test routes destination type
	# to STORAGE_BUILDING so the lookup hits in production code paths.


# Fixtures ------------------------------------------------------------------

var _logistics: LogisticsSystemScript
var _npc: NPCStub
var _buildings: BuildingRegistryStub
var _inventory: InventoryScript

const SRC: StringName = &"src_b"
const DST: StringName = &"dst_b"
const DST2: StringName = &"dst_b2"  # second storage for multi-route test
const NPC: StringName = &"carrier_1"
const SRC_TILE := Vector2i(2, 0)
const DST_TILE := Vector2i(4, 0)
const DST2_TILE := Vector2i(6, 0)
const TICKS_PER_LEG: int = 10


func before_test() -> void:
	_npc = NPCStub.new()
	add_child(_npc); auto_free(_npc)

	_buildings = BuildingRegistryStub.new()
	add_child(_buildings); auto_free(_buildings)
	_buildings.building_tiles[SRC] = SRC_TILE
	_buildings.building_tiles[DST] = DST_TILE
	_buildings.building_tiles[DST2] = DST2_TILE
	var dst_inst := BuildingInstanceStub.new()
	dst_inst.type = BuildingRegistry.BuildingType.STORAGE_BUILDING
	dst_inst.assigned_container_id = DST
	_buildings.instances[DST] = dst_inst
	var dst2_inst := BuildingInstanceStub.new()
	dst2_inst.type = BuildingRegistry.BuildingType.STORAGE_BUILDING
	dst2_inst.assigned_container_id = DST2
	_buildings.instances[DST2] = dst2_inst

	_inventory = InventoryScript.new()
	auto_free(_inventory)
	_inventory.create_container(DST, "Storage", 10, true)
	_inventory.create_container(DST2, "Storage 2", 10, true)

	_logistics = LogisticsSystemScript.new()
	add_child(_logistics); auto_free(_logistics)
	_logistics.verbose_logging = false
	_logistics._npc_system = _npc
	_logistics._building_registry = _buildings
	_logistics._inventory_system = _inventory
	_npc.npc_position = Vector2i(0, 0)


func _start_route(src: StringName, dst: StringName) -> LogisticsRouteScript:
	var result: Dictionary = _logistics.create_route(src, dst, NPC, LogisticsRouteScript.RouteType.OUTPUT)
	assert_bool(result["success"]).is_true()
	var route: LogisticsRouteScript = result["route"]
	assert_bool(_logistics.start_route(route.id)).is_true()
	return route


# =============================================================================
# Reservation acquired on pickup
# =============================================================================

func test_carrier_reserves_destination_space_at_pickup() -> void:
	_buildings.set_output(SRC, &"wood", 2)
	var route: LogisticsRouteScript = _start_route(SRC, DST)

	# Travel to source + 1 tick AT_SOURCE for pickup → TRAVEL_TO_DESTINATION.
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)

	# After pickup, the cargo amount is reserved at the destination.
	assert_int(_inventory.get_reserved_for_holder(DST, route.id)).is_equal(2)


# =============================================================================
# Foreign depositor cannot steal reserved space (the lockup fix)
# =============================================================================

func test_player_drag_cannot_eat_reserved_capacity() -> void:
	# Storage is mostly full; only the carrier-reserved 2 units fit.
	_inventory.try_deposit(DST, &"stone", 8)
	_buildings.set_output(SRC, &"wood", 2)
	var route: LogisticsRouteScript = _start_route(SRC, DST)
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	# Carrier picked up & reserved.
	assert_int(_inventory.get_reserved_for_holder(DST, route.id)).is_equal(2)

	# Player drag tries to add 1 stone → must be blocked (foreigners see no space).
	var res: int = _inventory.try_deposit(DST, &"stone", 1)
	assert_int(res).is_equal(InventoryContainer.DepositResult.FAILURE_FULL)

	# Carrier arrives and deposits successfully — proving the reservation worked.
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	assert_int(route.carrier_state).is_not_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)
	assert_int(_inventory.get_total_quantity(DST)).is_equal(10)
	assert_int(_inventory.get_reserved_for_holder(DST, route.id)).is_equal(0)


# =============================================================================
# Pre-pickup capacity check considers foreign reservations
# =============================================================================

func test_pre_pickup_check_blocks_when_others_have_reserved_remaining_space() -> void:
	# 8 already used; another (foreign) carrier reserved the remaining 2.
	_inventory.try_deposit(DST, &"stone", 8)
	_inventory.reserve_space(DST, &"other_route", &"wood", 2)
	_buildings.set_output(SRC, &"wood", 2)
	var route: LogisticsRouteScript = _start_route(SRC, DST)

	# Carrier arrives at source, finds no room at destination → does NOT pick up.
	# (With one route assigned, it switches to IDLE per _carrier_pick_next when no work.)
	_logistics._advance_tick(TICKS_PER_LEG + 5)
	assert_int(route.cargo).is_equal(0)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.IDLE)
	# Source output untouched.
	assert_int(_buildings.get_output_buffer_resource_quantity(str(SRC), &"wood")).is_equal(2)


# =============================================================================
# Release on route deletion
# =============================================================================

func test_route_delete_releases_in_flight_reservation() -> void:
	_buildings.set_output(SRC, &"wood", 2)
	var route: LogisticsRouteScript = _start_route(SRC, DST)
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	assert_int(_inventory.get_reserved_for_holder(DST, route.id)).is_equal(2)

	_logistics.delete_route(route.id)
	assert_int(_inventory.get_reserved_for_holder(DST, route.id)).is_equal(0)


# =============================================================================
# Release on route pause
# =============================================================================

func test_route_pause_releases_reservation() -> void:
	_buildings.set_output(SRC, &"wood", 2)
	var route: LogisticsRouteScript = _start_route(SRC, DST)
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	assert_int(_inventory.get_reserved_for_holder(DST, route.id)).is_equal(2)

	_logistics.pause_route(route.id)
	assert_int(_inventory.get_reserved_for_holder(DST, route.id)).is_equal(0)


# =============================================================================
# WAITING_DESTINATION rescue: dump cargo and move on after grace period
# =============================================================================

## Minimal grid stub for the rescue helper. Records add_resource_to_tile calls so the test
## can assert the dropped items.
class GridStub extends Node:
	var dropped: Array = []  # of {tile, resource_id}
	var passable_tiles: Dictionary = {}  # tile → true

	func is_in_bounds(_t: Vector2i) -> bool: return true
	func is_passable(t: Vector2i) -> bool: return passable_tiles.get(t, true)
	func get_building(_t: Vector2i) -> String: return ""
	func add_resource_to_tile(t: Vector2i, res_id: StringName, _clearable: bool = true) -> bool:
		dropped.append({"tile": t, "resource_id": res_id})
		return true
	# Stub-out terrain change signal connection that LogisticsSystem.set_grid_map subscribes to.
	signal terrain_changed(pos: Vector2i, layer: int)
	signal terrain_tile_changed(tile: Vector2i)


func test_waiting_destination_dumps_cargo_after_grace_period() -> void:
	# Arrange — empty destination, pickup succeeds with reservation.
	_buildings.set_output(SRC, &"wood", 2)
	var route: LogisticsRouteScript = _start_route(SRC, DST)
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	assert_int(route.cargo).is_equal(2)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)

	# Simulate the deadlock: release the reservation (as a save/load round-trip without
	# reservation persistence would), then fill the storage so on-arrival there is no space.
	_inventory.release_reservation(DST, route.id)
	_inventory.try_deposit(DST, &"stone", 10)
	# Wire the grid stub now, after pathfinding has already happened — the rescue path needs
	# it for dumping; the earlier route creation did not.
	var grid := GridStub.new()
	add_child(grid); auto_free(grid)
	_logistics._grid_map = grid

	# Carrier arrives, sees no space → WAITING_DESTINATION.
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)

	# Act — wait out the grace period.
	_logistics._advance_tick(LogisticsSystemScript.WAITING_DESTINATION_RESCUE_TICKS + 1)

	# Assert — cargo dumped on a tile adjacent to the destination, carrier no longer holds it.
	assert_int(route.cargo).is_equal(0)
	assert_object(route.cargo_resource).is_null()
	assert_int(grid.dropped.size()).is_equal(2)
	for entry: Dictionary in grid.dropped:
		assert_str(str(entry["resource_id"])).is_equal("wood")
	assert_int(_inventory.get_reserved_for_holder(DST, route.id)).is_equal(0)
