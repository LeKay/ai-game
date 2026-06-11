## GdUnit4 integration test suite for Logistics System Story 003:
## Carrier Waiting and Timeout.
##
## Tests wire LogisticsSystem with stub implementations of NPCSystem,
## BuildingRegistry, and InventorySystem to verify timeout and early-resolution
## behavior of WAITING_SOURCE and WAITING_DESTINATION states.
##
## AC coverage:
##   AC-1 — WAITING_SOURCE times out after carrier_waiting_timeout ticks → RETURN_HOME + DEACTIVATED
##   AC-2 — WAITING_DESTINATION times out after carrier_waiting_timeout ticks → RETURN_HOME + DEACTIVATED
##   AC-3 — WAITING_DESTINATION unloads within 1 tick when space opens
##   AC-4 — WAITING_SOURCE picks up within 1 tick when buffer fills
##   AC-5 — carrier_waiting_timeout is configurable (default 300, range 100–1000)

extends GdUnitTestSuite

const LogisticsSystemScript := preload("res://src/systems/logistics/logistics_system.gd")
const LogisticsRouteScript  := preload("res://src/systems/logistics/logistics_route.gd")

# ---- Test doubles -----------------------------------------------------------

class NPCStub extends Node:
	var carrier_state_calls: Array = []
	var release_calls: Array = []
	var npc_position: Vector2i = Vector2i.ZERO

	func set_carrier_state(npc_id: StringName, state: int) -> void:
		carrier_state_calls.append({"npc_id": npc_id, "state": state})

	func get_npc_position(_npc_id: StringName) -> Vector2i:
		return npc_position

	func is_available(_npc_id: StringName) -> bool:
		return true

	func release_npc(npc_id: StringName) -> void:
		release_calls.append(npc_id)

	func on_npc_at_location(_npc_id: StringName, _building_id: StringName) -> void:
		pass


class BuildingRegistryStub extends Node:
	var building_tiles: Dictionary = {}
	var output_buffers: Dictionary = {}

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

	func collect_output(building_id: String) -> Dictionary:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		output_buffers[StringName(building_id)] = {}
		return buf

	func set_output(building_id: StringName, resource: StringName, qty: int) -> void:
		output_buffers[building_id] = {resource: qty}

	func clear_output(building_id: StringName) -> void:
		output_buffers[building_id] = {}


class InventoryStub extends Node:
	var slot_counts: Dictionary = {}
	var occupied_counts: Dictionary = {}
	var deposit_calls: Array = []

	func get_slot_count(id: StringName) -> int:
		return slot_counts.get(id, 100)

	func get_occupied_slots(id: StringName) -> int:
		return occupied_counts.get(id, 0)

	func try_deposit(container_id: StringName, resource_id: StringName, quantity: int) -> Dictionary:
		deposit_calls.append({"container_id": container_id, "resource_id": resource_id, "quantity": quantity})
		return {"success": true}

	func set_full(container_id: StringName) -> void:
		slot_counts[container_id] = 10
		occupied_counts[container_id] = 10

	func set_has_space(container_id: StringName) -> void:
		slot_counts[container_id] = 10
		occupied_counts[container_id] = 5

# ---- Fixtures ---------------------------------------------------------------

var _logistics: LogisticsSystemScript
var _npc: NPCStub
var _buildings: BuildingRegistryStub
var _inventory: InventoryStub

const SRC: StringName = &"building_src"
const DST: StringName = &"building_dst"
const NPC: StringName = &"npc_001"

const HOME_TILE: Vector2i = Vector2i(0, 0)
const SRC_TILE: Vector2i  = Vector2i(2, 0)
const DST_TILE: Vector2i  = Vector2i(4, 0)

## Short timeout used in most tests to avoid advancing 300 ticks.
const SHORT_TIMEOUT: int = 5


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
	_inventory.set_has_space(DST)

	_logistics = LogisticsSystemScript.new()
	add_child(_logistics)
	auto_free(_logistics)
	_logistics._npc_system        = _npc
	_logistics._building_registry = _buildings
	_logistics._inventory_system  = _inventory
	_logistics.carrier_waiting_timeout = SHORT_TIMEOUT

	_npc.npc_position = HOME_TILE


## Creates a route with empty source buffer and returns it directly in WAITING_SOURCE.
## Sets wait_ticks = 0 and records npc_home_pos so RETURN_HOME travel can be calculated.
func _make_route_at_waiting_source() -> LogisticsRouteScript:
	var result: Dictionary = _logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)
	assert_bool(result["success"]).is_true()
	var route: LogisticsRouteScript = result["route"]
	route.npc_home_pos = HOME_TILE
	route.carrier_state = LogisticsRouteScript.CarrierState.WAITING_SOURCE
	route.wait_ticks = 0
	return route


## Creates a route with cargo held and returns it directly in WAITING_DESTINATION.
## Destination is set to full so the unload is blocked.
func _make_route_at_waiting_destination() -> LogisticsRouteScript:
	var result: Dictionary = _logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)
	assert_bool(result["success"]).is_true()
	var route: LogisticsRouteScript = result["route"]
	route.npc_home_pos = HOME_TILE
	route.carrier_state = LogisticsRouteScript.CarrierState.WAITING_DESTINATION
	route.wait_ticks = 0
	route.cargo = 1
	route.cargo_resource = &"wood"
	_inventory.set_full(DST)
	return route

# =============================================================================
# AC-1: WAITING_SOURCE timeout — carrier returns home and route deactivates
# =============================================================================

func test_waiting_source_still_waiting_one_tick_before_timeout() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route_at_waiting_source()

	# Act — advance one tick short of timeout
	_logistics._advance_tick(SHORT_TIMEOUT - 1)

	# Assert — still waiting, wait_ticks = SHORT_TIMEOUT - 1
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)
	assert_int(route.wait_ticks).is_equal(SHORT_TIMEOUT - 1)


func test_waiting_source_times_out_and_enters_return_home() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route_at_waiting_source()

	# Act — advance exactly timeout ticks
	_logistics._advance_tick(SHORT_TIMEOUT)

	# Assert — carrier is now returning home
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)


func test_waiting_source_timeout_deactivates_route_with_reason() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route_at_waiting_source()

	# Act
	_logistics._advance_tick(SHORT_TIMEOUT)

	# Assert — route is deactivated with the correct diagnostic reason
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.DEACTIVATED)
	assert_bool(route.active).is_false()
	assert_str(route.deactivation_reason).is_equal("timeout at source")


func test_waiting_source_timeout_of_one_fires_on_first_tick() -> void:
	# Edge case: timeout = 1 should trigger on the very first WAITING_SOURCE tick.
	_logistics.carrier_waiting_timeout = 1
	var route: LogisticsRouteScript = _make_route_at_waiting_source()

	# Act
	_logistics._advance_tick(1)

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.DEACTIVATED)

# =============================================================================
# AC-2: WAITING_DESTINATION timeout — carrier returns home with item and route deactivates
# =============================================================================

func test_waiting_destination_still_waiting_one_tick_before_timeout() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route_at_waiting_destination()

	# Act
	_logistics._advance_tick(SHORT_TIMEOUT - 1)

	# Assert — still waiting, cargo still held
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)
	assert_int(route.wait_ticks).is_equal(SHORT_TIMEOUT - 1)
	assert_int(route.cargo).is_equal(1)


func test_waiting_destination_times_out_and_enters_return_home() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route_at_waiting_destination()

	# Act
	_logistics._advance_tick(SHORT_TIMEOUT)

	# Assert — carrier heading home
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)


func test_waiting_destination_timeout_deactivates_route_with_reason() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route_at_waiting_destination()

	# Act
	_logistics._advance_tick(SHORT_TIMEOUT)

	# Assert — route is deactivated with the correct diagnostic reason
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.DEACTIVATED)
	assert_bool(route.active).is_false()
	assert_str(route.deactivation_reason).is_equal("timeout at destination")

# =============================================================================
# AC-3: WAITING_DESTINATION resolves within 1 tick when space opens
# =============================================================================

func test_waiting_destination_unloads_within_1_tick_when_space_opens() -> void:
	# Arrange — carrier waiting for SHORT_TIMEOUT - 2 ticks (not yet timed out)
	var route: LogisticsRouteScript = _make_route_at_waiting_destination()
	_logistics._advance_tick(SHORT_TIMEOUT - 2)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)

	# Act — free up space, then advance exactly 1 tick
	_inventory.set_has_space(DST)
	_logistics._advance_tick(1)

	# Assert — deposited and moved to RETURN_HOME within the same tick
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)
	assert_int(route.cargo).is_equal(0)
	assert_bool(_inventory.deposit_calls.size() > 0).is_true()


func test_waiting_destination_deposit_not_called_while_storage_remains_full() -> void:
	# Arrange — destination full throughout
	var route: LogisticsRouteScript = _make_route_at_waiting_destination()

	# Act — advance until just before timeout, storage stays full
	_logistics._advance_tick(SHORT_TIMEOUT - 1)

	# Assert — nothing deposited
	assert_int(_inventory.deposit_calls.size()).is_equal(0)
	assert_int(route.cargo).is_equal(1)

# =============================================================================
# AC-4: WAITING_SOURCE picks up within 1 tick when buffer fills
# =============================================================================

func test_waiting_source_picks_up_within_1_tick_when_buffer_fills() -> void:
	# Arrange — carrier waiting for SHORT_TIMEOUT - 2 ticks (not yet timed out)
	var route: LogisticsRouteScript = _make_route_at_waiting_source()
	_logistics._advance_tick(SHORT_TIMEOUT - 2)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)

	# Act — building produces output, then logistics advances 1 tick
	_buildings.set_output(SRC, &"wood", 3)
	_logistics._advance_tick(1)

	# Assert — carrier picked up item and moved to TRAVEL_TO_DESTINATION
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)
	assert_int(route.cargo).is_equal(1)


func test_waiting_source_wait_ticks_accumulates_before_pickup() -> void:
	# Arrange — carrier waits 3 ticks before buffer fills
	var route: LogisticsRouteScript = _make_route_at_waiting_source()
	_logistics._advance_tick(3)
	assert_int(route.wait_ticks).is_equal(3)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)

	# Act — buffer fills, 1 more tick
	_buildings.set_output(SRC, &"wood", 1)
	_logistics._advance_tick(1)

	# Assert — picked up on the tick the output appeared
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)

# =============================================================================
# AC-5: carrier_waiting_timeout is configurable
# =============================================================================

func test_carrier_waiting_timeout_default_is_300() -> void:
	# Arrange — a fresh system not affected by before_test's SHORT_TIMEOUT override
	var fresh_logistics: LogisticsSystemScript = LogisticsSystemScript.new()
	add_child(fresh_logistics)
	auto_free(fresh_logistics)

	# Assert — default matches GDD spec
	assert_int(fresh_logistics.carrier_waiting_timeout).is_equal(300)


func test_carrier_waiting_timeout_higher_value_prevents_early_timeout() -> void:
	# Arrange — set timeout to 500; carrier should not time out after 300 ticks
	_logistics.carrier_waiting_timeout = 500
	var route: LogisticsRouteScript = _make_route_at_waiting_source()

	# Act — advance 300 ticks (would time out with default 300, not with 500)
	_logistics._advance_tick(300)

	# Assert — carrier still waiting (higher timeout not yet reached)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)
	assert_int(route.wait_ticks).is_equal(300)


func test_carrier_waiting_timeout_applies_to_both_waiting_states() -> void:
	# Verify the same timeout value governs both WAITING_SOURCE and WAITING_DESTINATION.
	_logistics.carrier_waiting_timeout = 3

	var route_src: LogisticsRouteScript = _make_route_at_waiting_source()
	_logistics._advance_tick(3)
	assert_int(route_src.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)
	assert_str(route_src.deactivation_reason).is_equal("timeout at source")

	# Reset and test WAITING_DESTINATION with the same value
	_inventory.set_full(DST)
	var result2: Dictionary = _logistics.create_route(SRC, DST, &"npc_002", LogisticsRouteScript.RouteType.OUTPUT)
	var route_dst: LogisticsRouteScript = result2["route"]
	route_dst.npc_home_pos = HOME_TILE
	route_dst.carrier_state = LogisticsRouteScript.CarrierState.WAITING_DESTINATION
	route_dst.wait_ticks = 0
	route_dst.cargo = 1
	route_dst.cargo_resource = &"stone"

	_logistics._advance_tick(3)
	assert_int(route_dst.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)
	assert_str(route_dst.deactivation_reason).is_equal("timeout at destination")
