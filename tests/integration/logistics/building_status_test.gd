## GdUnit4 integration test suite for Logistics System Story 004:
## Building Status Integration.
##
## Tests verify that LogisticsSystem drives BuildingRegistry status correctly
## via set_status(), add_input_carrier(), remove_input_carrier(), and assign_output_carrier() calls.
##
## AC coverage:
##   AC-1 — create_route assigns carrier slot so building knows it has an output/input carrier
##   AC-2 — INPUT route deleted → destination building transitions to BLOCKED
##   AC-3 — Carrier in WAITING_DESTINATION → destination building stays OPERATING
##   AC-4 — Route deletion frees carrier slot (assign_*_carrier called with empty ID)
##   AC-5 — OUTPUT route deactivated → source slot cleared

extends GdUnitTestSuite

const LogisticsSystemScript := preload("res://src/systems/logistics/logistics_system.gd")
const LogisticsRouteScript  := preload("res://src/systems/logistics/logistics_route.gd")

# ---- Test doubles -----------------------------------------------------------

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
	## Recorded set_status calls: Array of {building_id: String, new_state: int}
	var status_calls: Array = []
	## Recorded add_input_carrier calls: Array of {building_id: String, carrier_id: StringName}
	var add_input_carrier_calls: Array = []
	## Recorded remove_input_carrier calls: Array of {building_id: String, carrier_id: StringName}
	var remove_input_carrier_calls: Array = []
	## Recorded assign_output_carrier calls: Array of {building_id: String, carrier_id: StringName}
	var output_carrier_calls: Array = []
	var building_tiles: Dictionary = {}
	var output_buffers: Dictionary = {}

	## Status codes mirror BuildingRegistry.Status for test assertions.
	const STATUS_CONSTRUCTING := 0
	const STATUS_OPERATING    := 1
	const STATUS_BLOCKED      := 2
	const STATUS_DEMOLISHED   := 3

	func set_status(building_id: String, new_state: int) -> void:
		status_calls.append({"building_id": building_id, "new_state": new_state})

	func add_input_carrier(building_id: String, carrier_id: StringName) -> void:
		add_input_carrier_calls.append({"building_id": building_id, "carrier_id": carrier_id})

	func remove_input_carrier(building_id: String, carrier_id: StringName) -> void:
		remove_input_carrier_calls.append({"building_id": building_id, "carrier_id": carrier_id})

	func assign_output_carrier(building_id: String, carrier_id: StringName) -> void:
		output_carrier_calls.append({"building_id": building_id, "carrier_id": carrier_id})

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

	## Returns the most recent status set for a building, or -1 if none recorded.
	func last_status_for(building_id: String) -> int:
		for i in range(status_calls.size() - 1, -1, -1):
			if status_calls[i]["building_id"] == building_id:
				return status_calls[i]["new_state"]
		return -1


class InventoryStub extends Node:
	var slot_counts: Dictionary = {}
	var occupied_counts: Dictionary = {}

	func get_slot_count(id: StringName) -> int:
		return slot_counts.get(id, 100)

	func get_occupied_slots(id: StringName) -> int:
		return occupied_counts.get(id, 0)

	func try_deposit(_container_id: StringName, _resource_id: StringName, _quantity: int) -> Dictionary:
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

const PRODUCTION_BUILDING: StringName = &"lumber_camp_01"
const STORAGE_BUILDING: StringName    = &"storage_01"
const NPC_CARRIER: StringName         = &"npc_carrier_01"

const PROD_TILE: Vector2i    = Vector2i(2, 0)
const STORAGE_TILE: Vector2i = Vector2i(5, 0)


func before_test() -> void:
	_npc = NPCStub.new()
	add_child(_npc)
	auto_free(_npc)

	_buildings = BuildingRegistryStub.new()
	add_child(_buildings)
	auto_free(_buildings)
	_buildings.building_tiles[PRODUCTION_BUILDING] = PROD_TILE
	_buildings.building_tiles[STORAGE_BUILDING]    = STORAGE_TILE

	_inventory = InventoryStub.new()
	add_child(_inventory)
	auto_free(_inventory)
	_inventory.set_has_space(STORAGE_BUILDING)

	_logistics = LogisticsSystemScript.new()
	add_child(_logistics)
	auto_free(_logistics)
	_logistics._npc_system        = _npc
	_logistics._building_registry = _buildings
	_logistics._inventory_system  = _inventory
	_logistics.carrier_waiting_timeout = 300

# =============================================================================
# AC-1 — create_route assigns carrier slot to the building
# =============================================================================

func test_create_output_route_assigns_output_carrier_to_source_building() -> void:
	# Arrange + Act
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)

	# Assert — output_carrier_calls recorded a matching assign
	assert_bool(result["success"]).is_true()
	assert_bool(_buildings.output_carrier_calls.size() > 0).is_true()
	var last_call: Dictionary = _buildings.output_carrier_calls.back()
	assert_str(last_call["building_id"]).is_equal(str(PRODUCTION_BUILDING))
	assert_str(str(last_call["carrier_id"])).is_equal(str(NPC_CARRIER))


func test_create_input_route_assigns_input_carrier_to_destination_building() -> void:
	# Arrange + Act
	var result: Dictionary = _logistics.create_route(
		STORAGE_BUILDING, PRODUCTION_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.INPUT)

	# Assert — add_input_carrier_calls recorded a matching add
	assert_bool(result["success"]).is_true()
	assert_bool(_buildings.add_input_carrier_calls.size() > 0).is_true()
	var last_call: Dictionary = _buildings.add_input_carrier_calls.back()
	assert_str(last_call["building_id"]).is_equal(str(PRODUCTION_BUILDING))
	assert_str(str(last_call["carrier_id"])).is_equal(str(NPC_CARRIER))

# =============================================================================
# AC-2 — INPUT route deleted → destination building transitions to BLOCKED
# =============================================================================

func test_delete_input_route_sets_destination_building_blocked() -> void:
	# Arrange — create an INPUT route (storage → production)
	var result: Dictionary = _logistics.create_route(
		STORAGE_BUILDING, PRODUCTION_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.INPUT)
	var route: LogisticsRouteScript = result["route"]
	_buildings.status_calls.clear()

	# Act — delete the route
	_logistics.delete_route(route.id)

	# Assert — destination building (production) was set to BLOCKED
	assert_bool(_buildings.status_calls.size() > 0).is_true()
	var last_status: int = _buildings.last_status_for(str(PRODUCTION_BUILDING))
	assert_int(last_status).is_equal(BuildingRegistryStub.STATUS_BLOCKED)


func test_delete_input_route_removes_input_carrier_on_destination() -> void:
	# Arrange
	var result: Dictionary = _logistics.create_route(
		STORAGE_BUILDING, PRODUCTION_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.INPUT)
	var route: LogisticsRouteScript = result["route"]
	_buildings.remove_input_carrier_calls.clear()

	# Act
	_logistics.delete_route(route.id)

	# Assert — remove_input_carrier called with the carrier's NPC id
	assert_bool(_buildings.remove_input_carrier_calls.size() > 0).is_true()
	var last_call: Dictionary = _buildings.remove_input_carrier_calls.back()
	assert_str(last_call["building_id"]).is_equal(str(PRODUCTION_BUILDING))
	assert_str(str(last_call["carrier_id"])).is_equal(str(NPC_CARRIER))

# =============================================================================
# AC-3 — Carrier in WAITING_DESTINATION → destination building stays OPERATING
# =============================================================================

func test_waiting_destination_sets_destination_building_operating() -> void:
	# Arrange — OUTPUT route (production → storage), carrier at WAITING_DESTINATION
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]
	route.carrier_state = LogisticsRouteScript.CarrierState.WAITING_DESTINATION
	route.npc_home_pos  = Vector2i.ZERO
	_buildings.status_calls.clear()

	# Act — advance one tick (triggers _update_building_status)
	_logistics._advance_tick(1)

	# Assert — destination (storage) building stays OPERATING
	var last_status: int = _buildings.last_status_for(str(STORAGE_BUILDING))
	assert_int(last_status).is_equal(BuildingRegistryStub.STATUS_OPERATING)


func test_at_source_carrier_sets_destination_building_operating() -> void:
	# Arrange — OUTPUT route, carrier AT_SOURCE (actively collecting)
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]
	route.carrier_state = LogisticsRouteScript.CarrierState.AT_SOURCE
	route.npc_home_pos  = Vector2i.ZERO
	_buildings.set_output(PRODUCTION_BUILDING, &"wood", 5)
	_buildings.status_calls.clear()

	# Act
	_logistics._advance_tick(1)

	# Assert — destination building was set to OPERATING (carrier actively collecting)
	var last_status: int = _buildings.last_status_for(str(STORAGE_BUILDING))
	assert_int(last_status).is_equal(BuildingRegistryStub.STATUS_OPERATING)


func test_idle_carrier_does_not_call_set_status() -> void:
	# Arrange — route with carrier IDLE (waiting for start_route())
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]
	route.carrier_state = LogisticsRouteScript.CarrierState.IDLE
	_buildings.status_calls.clear()

	# Act
	_logistics._advance_tick(1)

	# Assert — no set_status call (IDLE is a do-not-override state)
	assert_int(_buildings.status_calls.size()).is_equal(0)


func test_travel_to_source_carrier_does_not_call_set_status() -> void:
	# Arrange — carrier mid-travel (TRAVEL_TO_SOURCE), 10 ticks remaining
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]
	route.carrier_state  = LogisticsRouteScript.CarrierState.TRAVEL_TO_SOURCE
	route.remaining_ticks = 10
	route.npc_home_pos   = Vector2i.ZERO
	_buildings.status_calls.clear()

	# Act — advance 1 tick (carrier still travelling, remaining_ticks = 9)
	_logistics._advance_tick(1)

	# Assert — no set_status call (TRAVEL_TO_SOURCE is a do-not-override state)
	assert_int(_buildings.status_calls.size()).is_equal(0)

# =============================================================================
# AC-4 — Route deletion frees carrier slot
# =============================================================================

func test_delete_output_route_clears_output_carrier_on_source() -> void:
	# Arrange — OUTPUT route (production → storage)
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]
	_buildings.output_carrier_calls.clear()

	# Act
	_logistics.delete_route(route.id)

	# Assert — output slot cleared on source (production) building
	assert_bool(_buildings.output_carrier_calls.size() > 0).is_true()
	var last_call: Dictionary = _buildings.output_carrier_calls.back()
	assert_str(last_call["building_id"]).is_equal(str(PRODUCTION_BUILDING))
	assert_str(str(last_call["carrier_id"])).is_equal("")


func test_deleted_route_is_removed_from_active_routes() -> void:
	# Arrange
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]
	assert_int(_logistics.get_active_routes().size()).is_equal(1)

	# Act
	_logistics.delete_route(route.id)

	# Assert
	assert_int(_logistics.get_active_routes().size()).is_equal(0)

# =============================================================================
# AC-5 — OUTPUT route deactivated → source slot cleared, NOT immediately STALLED
# =============================================================================

func test_deactivated_output_route_clears_output_carrier_slot() -> void:
	# Arrange — OUTPUT route (timeouts no longer exist; deactivation is triggered
	# directly, as path invalidation / NPC removal would do)
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]
	route.npc_home_pos = Vector2i.ZERO
	_buildings.output_carrier_calls.clear()

	# Act — deactivate → _on_route_active_changed
	_logistics._deactivate_route(route, "test deactivation")

	# Assert — output carrier slot on source (production) building was cleared
	assert_bool(_buildings.output_carrier_calls.size() > 0).is_true()
	var last_call: Dictionary = _buildings.output_carrier_calls.back()
	assert_str(last_call["building_id"]).is_equal(str(PRODUCTION_BUILDING))
	assert_str(str(last_call["carrier_id"])).is_equal("")


func test_deactivated_output_route_does_not_immediately_stall_source_building() -> void:
	# Arrange — OUTPUT route deactivated directly (timeouts removed)
	var result: Dictionary = _logistics.create_route(
		PRODUCTION_BUILDING, STORAGE_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.OUTPUT)
	var route: LogisticsRouteScript = result["route"]
	route.npc_home_pos = Vector2i.ZERO
	_buildings.status_calls.clear()

	# Act
	_logistics._deactivate_route(route, "test deactivation")

	# Assert — source (production) building NOT set to STALLED immediately
	# (deferred until next production cycle completes with empty output_carrier_id,
	#  per GDD Core Rules 6)
	var last_status: int = _buildings.last_status_for(str(PRODUCTION_BUILDING))
	assert_int(last_status).is_not_equal(BuildingRegistryStub.STATUS_STALLED)


func test_deactivated_input_route_sets_destination_building_blocked() -> void:
	# Arrange — INPUT route deactivated directly (timeouts removed)
	var result: Dictionary = _logistics.create_route(
		STORAGE_BUILDING, PRODUCTION_BUILDING, NPC_CARRIER,
		LogisticsRouteScript.RouteType.INPUT)
	var route: LogisticsRouteScript = result["route"]
	route.npc_home_pos   = Vector2i.ZERO
	route.cargo          = 1
	route.cargo_resource = &"wood"
	_inventory.set_full(PRODUCTION_BUILDING)
	_buildings.status_calls.clear()

	# Act
	_logistics._deactivate_route(route, "test deactivation")

	# Assert — destination (production) building was set to BLOCKED
	var last_status: int = _buildings.last_status_for(str(PRODUCTION_BUILDING))
	assert_int(last_status).is_equal(BuildingRegistryStub.STATUS_BLOCKED)
