## GdUnit4 integration test suite for the shared-carrier waiting behavior
## (ADR-0011 Amendment 2026-06-13 — timeouts removed).
##
## Tests wire LogisticsSystem with stub implementations of NPCSystem,
## BuildingRegistry, and InventorySystem to verify the replacement semantics:
##
##   AC-W1 — a carrier whose only route has no work waits IN PLACE (IDLE), no travel
##   AC-W2 — work appearing at the source starts travel within 1 tick batch
##   AC-W3 — WAITING_DESTINATION holds cargo indefinitely (no timeout, never discards)
##   AC-W4 — WAITING_DESTINATION deposits within 1 tick of space freeing
##   AC-W5 — carrier_waiting_timeout survives only as a save-compat field (default 300)

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

	func get_npc_instance(_npc_id: StringName) -> Object:
		return null  # → LogisticsSystem falls back to carrier efficiency 1.0

	func is_available(_npc_id: StringName) -> bool:
		return true

	func release_npc(npc_id: StringName) -> void:
		release_calls.append(npc_id)

	func on_npc_at_location(_npc_id: StringName, _building_id: StringName) -> void:
		pass

	func add_pending_xp(_npc_id: StringName, _amount: int) -> void: pass
	func npc_perk_bonus(_npc_id: StringName, _effect: StringName) -> float: return 0.0


## Minimal building instance double exposing the fields LogisticsSystem reads.
class BuildingInstanceStub:
	var type: int = 0
	var assigned_container_id: StringName = &""
	var storage_limits: Dictionary = {}
	var storage_min_limits: Dictionary = {}


class BuildingRegistryStub extends Node:
	var building_tiles: Dictionary = {}
	var output_buffers: Dictionary = {}
	var instances: Dictionary = {}
	var received_inputs: Array = []

	func get_building_tile(building_id: String) -> Vector2i:
		return building_tiles.get(StringName(building_id), Vector2i(-1, -1))

	func get_building_instance(building_id: String) -> Object:
		return instances.get(StringName(building_id), null)

	func has_output_buffer(building_id: String) -> bool:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		return not buf.is_empty()

	func get_output_buffer_resource(building_id: String) -> StringName:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		if buf.is_empty():
			return &""
		return buf.keys()[0]

	func get_output_buffer_resource_quantity(building_id: String, resource_id: StringName) -> int:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		return buf.get(resource_id, 0)

	func remove_from_output(building_id: String, resource_id: StringName, qty: int) -> bool:
		var buf: Dictionary = output_buffers.get(StringName(building_id), {})
		if buf.get(resource_id, 0) < qty:
			return false
		buf[resource_id] -= qty
		if buf[resource_id] <= 0:
			buf.erase(resource_id)
		return true

	func receive_input_from_world(building_id: String, resource_id: StringName, qty: int) -> bool:
		received_inputs.append({"building_id": building_id, "resource_id": resource_id, "qty": qty})
		return true

	func is_input_full(_building_id: String, _resource_id: StringName) -> bool:
		return false

	func assign_output_carrier(_building_id: String, _carrier_id: StringName) -> void:
		pass

	func add_input_carrier(_building_id: String, _carrier_id: StringName) -> void:
		pass

	func remove_input_carrier(_building_id: String, _carrier_id: StringName) -> void:
		pass

	func set_status(_building_id: StringName, _new_state: int, _reason: String = "") -> void:
		pass

	func set_output(building_id: StringName, resource: StringName, qty: int) -> void:
		output_buffers[building_id] = {resource: qty}

	func clear_output(building_id: StringName) -> void:
		output_buffers[building_id] = {}


class InventoryStub extends Node:
	var totals: Dictionary = {}
	var capacities: Dictionary = {}
	var deposit_calls: Array = []

	func get_total_quantity(id: StringName) -> int:
		return totals.get(id, 0)

	func get_capacity(id: StringName) -> int:
		return capacities.get(id, 100)

	func get_resource_quantity(_id: StringName, _resource_id: StringName) -> int:
		return 0

	func try_consume(_id: StringName, _resource_id: StringName, _qty: int) -> int:
		return 0

	func try_deposit(container_id: StringName, resource_id: StringName, quantity: int,
			_holder_id: StringName = &"") -> int:
		deposit_calls.append({"container_id": container_id, "resource_id": resource_id, "quantity": quantity})
		return InventoryContainer.DepositResult.SUCCESS

	# Reservation no-op stubs — these tests don't exercise reservation semantics.
	func reserve_space(_cid: StringName, _holder: StringName, _res: StringName, _qty: int) -> bool:
		return true
	func release_reservation(_cid: StringName, _holder: StringName) -> void: pass
	func get_reserved_total(_cid: StringName) -> int: return 0
	func get_reserved_for(_cid: StringName, _res: StringName) -> int: return 0
	func get_reserved_for_holder(_cid: StringName, _holder: StringName) -> int: return 0

	func set_full(container_id: StringName) -> void:
		totals[container_id] = 10
		capacities[container_id] = 10

	func set_has_space(container_id: StringName) -> void:
		totals[container_id] = 5
		capacities[container_id] = 10

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

## Manhattan(home→src)=2, (src→dst)=2 → 10 ticks per leg at TICKS_PER_TILE=5, eff 1.0.
const TICKS_PER_LEG: int = 10


func before_test() -> void:
	_npc = NPCStub.new()
	add_child(_npc)
	auto_free(_npc)

	_buildings = BuildingRegistryStub.new()
	add_child(_buildings)
	auto_free(_buildings)
	_buildings.building_tiles[SRC] = SRC_TILE
	_buildings.building_tiles[DST] = DST_TILE
	# Destination is a storage building so _destination_has_space checks the inventory.
	var dst_instance := BuildingInstanceStub.new()
	dst_instance.type = BuildingRegistry.BuildingType.STORAGE_BUILDING
	dst_instance.assigned_container_id = DST
	_buildings.instances[DST] = dst_instance

	_inventory = InventoryStub.new()
	add_child(_inventory)
	auto_free(_inventory)
	_inventory.set_has_space(DST)

	_logistics = LogisticsSystemScript.new()
	add_child(_logistics)
	auto_free(_logistics)
	_logistics.verbose_logging    = false
	_logistics._npc_system        = _npc
	_logistics._building_registry = _buildings
	_logistics._inventory_system  = _inventory

	_npc.npc_position = HOME_TILE


## Creates and starts an OUTPUT route SRC → DST for NPC. Returns the route.
func _start_route() -> LogisticsRouteScript:
	var result: Dictionary = _logistics.create_route(SRC, DST, NPC, LogisticsRouteScript.RouteType.OUTPUT)
	assert_bool(result["success"]).is_true()
	var route: LogisticsRouteScript = result["route"]
	assert_bool(_logistics.start_route(route.id)).is_true()
	return route

# =============================================================================
# AC-W1: no work on any route → carrier waits in place (IDLE), no travel
# =============================================================================

func test_carrier_with_empty_source_waits_in_place() -> void:
	# Arrange — source has no output
	var route: LogisticsRouteScript = _start_route()

	# Act — plenty of ticks; the old code would have timed out by now
	_logistics._advance_tick(400)

	# Assert — still parked IDLE on its route, never deactivated, never released
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.IDLE)
	assert_bool(route.active).is_true()
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.ACTIVE)
	assert_int(_npc.release_calls.size()).is_equal(0)


# =============================================================================
# AC-W2: work appearing at the source starts travel within 1 tick batch
# =============================================================================

func test_idle_carrier_starts_travel_when_output_appears() -> void:
	# Arrange — carrier idling in place on a workless route
	var route: LogisticsRouteScript = _start_route()
	_logistics._advance_tick(5)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.IDLE)

	# Act — building produces output, next tick batch services the carrier
	_buildings.set_output(SRC, &"wood", 3)
	_logistics._advance_tick(1)

	# Assert — travelling to source
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_SOURCE)


func test_carrier_picks_up_capacity_limited_cargo_at_source() -> void:
	# Arrange — 3 wood buffered, CARRIER_CAPACITY = 2
	_buildings.set_output(SRC, &"wood", 3)
	var route: LogisticsRouteScript = _start_route()

	# Act — travel to source (10 ticks) + 1 tick for the AT_SOURCE pickup
	_logistics._advance_tick(TICKS_PER_LEG + 1)

	# Assert — picked up min(3, 2) = 2 and departed
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)
	assert_int(route.cargo).is_equal(2)
	assert_int(_buildings.get_output_buffer_resource_quantity(str(SRC), &"wood")).is_equal(1)


# =============================================================================
# AC-W3 (amended 2026-06-28): WAITING_DESTINATION holds cargo for the grace
# period (WAITING_DESTINATION_RESCUE_TICKS), then rescues — dumps cargo on the
# map and moves on. Replaces the prior "no timeout, hold forever" contract:
# the unbounded wait deadlocked carriers when a production building's input AND
# output were both full (cycle can't run → input never frees).
# =============================================================================

func test_waiting_destination_holds_cargo_during_grace_period() -> void:
	# Arrange — cargo at source; destination fills up while the carrier is en route
	# (a route with a full destination has no "work", so the trip must start first)
	_buildings.set_output(SRC, &"wood", 2)
	var route: LogisticsRouteScript = _start_route()
	_logistics._advance_tick(TICKS_PER_LEG + 1)  # arrive + pick up → TRAVEL_TO_DESTINATION
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_DESTINATION)
	_inventory.set_full(DST)
	_logistics._advance_tick(TICKS_PER_LEG + 1)  # arrive → destination full → wait
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)

	# Act — advance just under the rescue threshold
	_logistics._advance_tick(LogisticsSystemScript.WAITING_DESTINATION_RESCUE_TICKS - 1)

	# Assert — still waiting, cargo intact, nothing deposited (grace period still active)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)
	assert_int(route.cargo).is_equal(2)
	assert_bool(route.active).is_true()
	assert_int(_inventory.deposit_calls.size()).is_equal(0)


# =============================================================================
# AC-W4: WAITING_DESTINATION deposits within 1 tick of space freeing
# =============================================================================

func test_waiting_destination_deposits_within_1_tick_when_space_opens() -> void:
	# Arrange — carrier waiting at a destination that filled up mid-trip
	_buildings.set_output(SRC, &"wood", 2)
	var route: LogisticsRouteScript = _start_route()
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	_inventory.set_full(DST)
	_logistics._advance_tick(TICKS_PER_LEG + 1)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)

	# Act — free space, advance exactly 1 tick
	_inventory.set_has_space(DST)
	_logistics._advance_tick(1)

	# Assert — deposited; cargo cleared; carrier moved on via the decision point
	assert_int(_inventory.deposit_calls.size()).is_equal(1)
	assert_int(route.cargo).is_equal(0)
	assert_int(route.carrier_state).is_not_equal(LogisticsRouteScript.CarrierState.WAITING_DESTINATION)


func test_after_delivery_single_route_carrier_returns_for_remaining_cargo() -> void:
	# Arrange — 4 wood buffered: first trip carries 2, second trip should follow
	_buildings.set_output(SRC, &"wood", 4)
	var route: LogisticsRouteScript = _start_route()

	# Act — full first trip (leg + pickup + leg + deposit) and one service tick
	_logistics._advance_tick(2 * TICKS_PER_LEG + 3)

	# Assert — round-robin with a single route picks the same route again
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.TRAVEL_TO_SOURCE)
	assert_int(route.cargo).is_equal(0)


# =============================================================================
# AC-W5: carrier_waiting_timeout survives only for save-file compatibility
# =============================================================================

func test_carrier_waiting_timeout_field_kept_for_save_compat() -> void:
	# Arrange — fresh system
	var fresh_logistics: LogisticsSystemScript = LogisticsSystemScript.new()
	add_child(fresh_logistics)
	auto_free(fresh_logistics)

	# Assert — field still exists with its legacy default and is serialized
	assert_int(fresh_logistics.carrier_waiting_timeout).is_equal(300)
	assert_bool(fresh_logistics.serialize().has("carrier_waiting_timeout")).is_true()
