## GdUnit4 integration test suite for Logistics System Story 002:
## Carrier FSM Core Loop.
##
## Tests wire LogisticsSystem with stub implementations of NPCSystem,
## BuildingRegistry, and InventorySystem to verify FSM state transitions
## without Autoload dependencies.
##
## AC coverage:
##   AC-1 — Complete carrier loop IDLE → IDLE (no waits)
##   AC-2 — AT_SOURCE picks up min(buffer, capacity)
##   AC-3 — AT_DESTINATION unloads if space; waits if full
##   AC-4 — set_carrier_state called only on transitions (not per-tick)
##   AC-5 — Carrier polls AT_SOURCE after building produces (same-tick pickup)

extends GdUnitTestSuite

const LogisticsSystemScript := preload("res://src/systems/logistics/logistics_system.gd")
const LogisticsRouteScript  := preload("res://src/systems/logistics/logistics_route.gd")

# ---- Test doubles -----------------------------------------------------------

## Stub NPCSystem — records set_carrier_state calls and provides configurable position.
class NPCStub extends Node:
	var carrier_state_calls: Array = []  # [{npc_id, state}]
	var at_location_calls: Array = []    # [{npc_id, building_id}]
	var release_calls: Array = []        # [npc_id]
	var npc_position: Vector2i = Vector2i.ZERO

	func set_carrier_state(npc_id: StringName, state: int) -> void:
		carrier_state_calls.append({"npc_id": npc_id, "state": state})

	func get_npc_position(_npc_id: StringName) -> Vector2i:
		return npc_position

	func is_available(_npc_id: StringName) -> bool:
		return true

	func release_npc(npc_id: StringName) -> void:
		release_calls.append(npc_id)

	func on_npc_at_location(npc_id: StringName, building_id: StringName) -> void:
		at_location_calls.append({"npc_id": npc_id, "building_id": building_id})

	func set_carrier_state_call_count() -> int:
		return carrier_state_calls.size()


## Stub BuildingRegistry — configurable per-building output buffer and tile positions.
class BuildingRegistryStub extends Node:
	var building_tiles: Dictionary = {}    # StringName → Vector2i
	var output_buffers: Dictionary = {}    # StringName → {resource: qty}

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


## Stub InventorySystem — configurable free-slot state.
class InventoryStub extends Node:
	var slot_counts: Dictionary = {}     # StringName → int (total)
	var occupied_counts: Dictionary = {} # StringName → int (used)
	var deposit_calls: Array = []        # [{container_id, resource_id, quantity}]

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

## Source building ID
const SRC: StringName = &"building_src"
## Destination building ID
const DST: StringName = &"building_dst"
## NPC ID
const NPC: StringName = &"npc_001"

## Home/source tile (0,0). TRAVEL_TO_SOURCE = 0 ticks (carrier starts at source).
const HOME_TILE: Vector2i  = Vector2i(0, 0)
## Source tile at (5,5) — distance from home = 10 → 30 ticks.
const SRC_TILE: Vector2i   = Vector2i(5, 5)
## Dest tile at (10,5) — distance from source = 5 → 15 ticks.
const DST_TILE: Vector2i   = Vector2i(10, 5)
## Return: from (10,5) to (0,0) = 10+5 = 15 → 45 ticks.

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
	_logistics._npc_system       = _npc
	_logistics._building_registry = _buildings
	_logistics._inventory_system  = _inventory

	_npc.npc_position = HOME_TILE


## Creates a route and returns it. Helper shared across test cases.
func _make_route() -> LogisticsRouteScript:
	var result: Dictionary = _logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)
	assert_bool(result["success"]).is_true()
	return result["route"]

# =============================================================================
# AC-1: Complete carrier loop IDLE → IDLE (no waits)
# =============================================================================

func test_carrier_loop_idle_to_idle_travel_to_source_counts_down() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route()
	_logistics.start_route(route.id)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_SOURCE)
	var expected_ticks: int = _logistics._calc_travel_time(HOME_TILE, SRC_TILE)

	# Act — advance all but last tick
	_logistics._advance_tick(expected_ticks - 1)

	# Assert — still traveling
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_SOURCE)
	assert_int(route.remaining_ticks).is_equal(1)


func test_carrier_loop_arrives_at_source_after_travel_ticks() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 5)
	_logistics.start_route(route.id)
	var travel_ticks: int = _logistics._calc_travel_time(HOME_TILE, SRC_TILE)

	# Act
	_logistics._advance_tick(travel_ticks)

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)
	assert_int(route.cargo).is_equal(1)  # CARRIER_CAPACITY = 1
	assert_str(str(route.cargo_resource)).is_equal("wood")


func test_carrier_loop_arrives_at_destination_after_transit() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 5)
	_logistics.start_route(route.id)
	var src_travel: int = _logistics._calc_travel_time(HOME_TILE, SRC_TILE)
	var dst_travel: int = _logistics._calc_travel_time(SRC_TILE, DST_TILE)

	# Act
	_logistics._advance_tick(src_travel + dst_travel)

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)
	assert_int(route.cargo).is_equal(0)
	assert_bool(_inventory.deposit_calls.size() > 0).is_true()


func test_carrier_loop_returns_to_idle_after_return_home() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 5)
	_logistics.start_route(route.id)
	var src_travel: int = _logistics._calc_travel_time(HOME_TILE, SRC_TILE)
	var dst_travel: int = _logistics._calc_travel_time(SRC_TILE, DST_TILE)
	var ret_travel: int = _logistics._calc_travel_time(DST_TILE, HOME_TILE)

	# Act
	_logistics._advance_tick(src_travel + dst_travel + ret_travel)

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.IDLE)
	assert_bool(_npc.release_calls.has(NPC)).is_true()


func test_carrier_loop_floor_applied_to_travel_ticks() -> void:
	# Arrange — tile distance that would be fractional if not floored
	# HOME(0,0) → tile(1,0): dist=1, 1×3.0=3.0 → floor → 3 ticks
	var route: LogisticsRouteScript = _make_route()
	route.npc_home_pos = Vector2i(0, 0)
	_buildings.building_tiles[SRC] = Vector2i(1, 0)

	# Act
	var ticks: int = _logistics._calc_travel_time(Vector2i(0, 0), Vector2i(1, 0))

	# Assert
	assert_int(ticks).is_equal(3)

# =============================================================================
# AC-2: AT_SOURCE picks up min(buffer, capacity)
# =============================================================================

func test_at_source_picks_up_min_buffer_capacity_when_buffer_larger() -> void:
	# Arrange — buffer has 5 items, capacity = 1 → pickup = 1
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 5)
	_logistics.start_route(route.id)
	_logistics._advance_tick(_logistics._calc_travel_time(HOME_TILE, SRC_TILE))

	# Assert
	assert_int(route.cargo).is_equal(1)


func test_at_source_picks_up_all_when_buffer_equals_capacity() -> void:
	# Arrange — buffer has 1 item, capacity = 1 → pickup = 1
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 1)
	_logistics.start_route(route.id)
	_logistics._advance_tick(_logistics._calc_travel_time(HOME_TILE, SRC_TILE))

	# Assert
	assert_int(route.cargo).is_equal(1)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)


func test_at_source_enters_waiting_when_buffer_empty() -> void:
	# Arrange — no output in buffer
	var route: LogisticsRouteScript = _make_route()
	_buildings.clear_output(SRC)
	_logistics.start_route(route.id)
	_logistics._advance_tick(_logistics._calc_travel_time(HOME_TILE, SRC_TILE))

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)
	assert_int(route.cargo).is_equal(0)


func test_waiting_source_resumes_when_buffer_filled() -> void:
	# Arrange — starts waiting, then buffer appears
	var route: LogisticsRouteScript = _make_route()
	_buildings.clear_output(SRC)
	_logistics.start_route(route.id)
	_logistics._advance_tick(_logistics._calc_travel_time(HOME_TILE, SRC_TILE))
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)

	# Act — fill buffer and advance one tick
	_buildings.set_output(SRC, &"stone", 3)
	_logistics._advance_tick(1)

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)
	assert_int(route.cargo).is_equal(1)
	assert_str(str(route.cargo_resource)).is_equal("stone")

# =============================================================================
# AC-3: AT_DESTINATION unloads if space; enters WAITING_DESTINATION if full
# =============================================================================

func test_at_destination_deposits_and_enters_return_home_when_space_available() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 5)
	_inventory.set_has_space(DST)
	_logistics.start_route(route.id)
	var src_travel: int = _logistics._calc_travel_time(HOME_TILE, SRC_TILE)
	var dst_travel: int = _logistics._calc_travel_time(SRC_TILE, DST_TILE)
	_logistics._advance_tick(src_travel + dst_travel)

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)
	assert_int(route.cargo).is_equal(0)
	assert_int(_inventory.deposit_calls.size()).is_equal(1)
	assert_str(str(_inventory.deposit_calls[0]["resource_id"])).is_equal("wood")


func test_at_destination_enters_waiting_destination_when_storage_full() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 5)
	_inventory.set_full(DST)
	_logistics.start_route(route.id)
	var src_travel: int = _logistics._calc_travel_time(HOME_TILE, SRC_TILE)
	var dst_travel: int = _logistics._calc_travel_time(SRC_TILE, DST_TILE)
	_logistics._advance_tick(src_travel + dst_travel)

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)
	assert_int(route.wait_ticks).is_equal(0)
	assert_int(_inventory.deposit_calls.size()).is_equal(0)


func test_waiting_destination_resumes_when_space_opens() -> void:
	# Arrange — carrier stuck at destination, then space opens
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 5)
	_inventory.set_full(DST)
	_logistics.start_route(route.id)
	var src_travel: int = _logistics._calc_travel_time(HOME_TILE, SRC_TILE)
	var dst_travel: int = _logistics._calc_travel_time(SRC_TILE, DST_TILE)
	_logistics._advance_tick(src_travel + dst_travel)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)

	# Act — free up space and advance one tick
	_inventory.set_has_space(DST)
	_logistics._advance_tick(1)

	# Assert
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.RETURN_HOME)
	assert_int(_inventory.deposit_calls.size()).is_equal(1)

# =============================================================================
# AC-4: set_carrier_state called only on transitions, not per-tick no-ops
# =============================================================================

func test_set_carrier_state_not_called_while_idle() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route()
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.IDLE)
	_npc.carrier_state_calls.clear()

	# Act — advance 5 ticks while IDLE
	_logistics._advance_tick(5)

	# Assert — no set_carrier_state calls while staying IDLE
	assert_int(_npc.set_carrier_state_call_count()).is_equal(0)


func test_set_carrier_state_called_exactly_once_per_transition() -> void:
	# Arrange
	var route: LogisticsRouteScript = _make_route()
	_buildings.set_output(SRC, &"wood", 5)
	_npc.carrier_state_calls.clear()

	# Act — start_route triggers IDLE → TRAVEL_TO_SOURCE (1 call)
	_logistics.start_route(route.id)
	assert_int(_npc.set_carrier_state_call_count()).is_equal(1)
	assert_int(_npc.carrier_state_calls[0]["state"]).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_SOURCE)

	# Advance to AT_SOURCE → TRAVEL_TO_DESTINATION (2 calls: AT_SOURCE + TRAVEL_TO_DESTINATION)
	_logistics._advance_tick(_logistics._calc_travel_time(HOME_TILE, SRC_TILE))
	assert_int(_npc.set_carrier_state_call_count()).is_equal(3)  # +AT_SOURCE, +TRAVEL_TO_DESTINATION


func test_set_carrier_state_not_called_while_traveling() -> void:
	# Arrange — carrier is TRAVEL_TO_SOURCE with 10 ticks remaining
	var route: LogisticsRouteScript = _make_route()
	_logistics.start_route(route.id)
	var travel_ticks: int = _logistics._calc_travel_time(HOME_TILE, SRC_TILE)
	_npc.carrier_state_calls.clear()

	# Act — advance all but the final tick (stays in TRAVEL_TO_SOURCE)
	_logistics._advance_tick(travel_ticks - 1)

	# Assert — no state change calls while counting down
	assert_int(_npc.set_carrier_state_call_count()).is_equal(0)

# =============================================================================
# AC-5: Carrier polls AT_SOURCE after building produces (same-tick pickup)
# =============================================================================

func test_at_source_picks_up_output_produced_this_tick() -> void:
	# Simulates tick ordering: BuildingRegistry produces (step 2), then
	# LogisticsSystem polls AT_SOURCE (step 3) and picks up on the same tick.
	#
	# Arrange — carrier is waiting at AT_SOURCE with empty buffer
	var route: LogisticsRouteScript = _make_route()
	_buildings.clear_output(SRC)
	_logistics.start_route(route.id)
	_logistics._advance_tick(_logistics._calc_travel_time(HOME_TILE, SRC_TILE))
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)

	# Simulate building produces output this tick (step 2 of tick order)
	_buildings.set_output(SRC, &"wood", 5)

	# Act — logistics advances (step 3 of tick order)
	_logistics._advance_tick(1)

	# Assert — carrier picks up the item produced this tick
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)
	assert_int(route.cargo).is_equal(1)


func test_at_source_misses_output_if_logistics_ran_before_building() -> void:
	# Verifies the ordering bug AC-5 guards against: if logistics ran BEFORE
	# building production, the carrier would go to WAITING_SOURCE.
	# This test documents the expected WRONG behavior when order is reversed.
	#
	# Arrange — carrier arrives AT_SOURCE with empty buffer (no output yet)
	var route: LogisticsRouteScript = _make_route()
	_buildings.clear_output(SRC)
	_logistics.start_route(route.id)
	_logistics._advance_tick(_logistics._calc_travel_time(HOME_TILE, SRC_TILE))

	# Act — logistics advances BEFORE building produces (wrong order)
	_logistics._advance_tick(1)
	# Building produces AFTER (too late)
	_buildings.set_output(SRC, &"wood", 5)

	# Assert — carrier missed the output and is WAITING (ordering bug manifested)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_SOURCE)
