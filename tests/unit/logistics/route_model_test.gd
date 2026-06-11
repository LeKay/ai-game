## GdUnit4 test suite for Logistics System Story 001:
## Route Model and Slot Validation.
##
## Covers AC-1 through AC-5 and edge cases from QA test plan.

extends GdUnitTestSuite

const LogisticsRouteScript := preload("res://src/systems/logistics/logistics_route.gd")
const LogisticsSystemScript := preload("res://src/systems/logistics/logistics_system.gd")

var _system: LogisticsSystemScript


func before_test() -> void:
	_system = LogisticsSystemScript.new()
	auto_free(_system)


# ---- AC-1: Route factory sets correct initial state --------------------------

func test_route_create_sets_active_true() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_bool(route.active).is_equal(true)


func test_route_create_sets_lifecycle_active() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_int(route.lifecycle_state).is_equal(LogisticsRouteScript.LifecycleState.ACTIVE)


func test_route_create_sets_carrier_idle() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_int(route.carrier_state).is_equal(LogisticsRouteScript.CarrierState.IDLE)


func test_route_create_sets_cargo_zero() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_int(route.cargo).is_equal(0)


func test_route_create_sets_cargo_resource_null() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_object(route.cargo_resource).is_null()


func test_route_create_id_uses_npc_name() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_str(str(route.id)).is_equal("route_npc_1")


# ---- AC-2: Route factory sets all fields correctly ---------------------------

func test_route_create_sets_source_building_id() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_7",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_str(str(route.source_building_id)).is_equal("storage_A")


func test_route_create_sets_destination_building_id() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_7",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_str(str(route.destination_building_id)).is_equal("lumber_camp_B")


func test_route_create_sets_npc_id() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_7",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_str(str(route.npc_id)).is_equal("npc_7")


func test_route_create_sets_route_type_output() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_7",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_int(route.route_type).is_equal(LogisticsRouteScript.RouteType.OUTPUT)


func test_route_create_sets_remaining_ticks_zero() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_7",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_int(route.remaining_ticks).is_equal(0)


func test_route_create_sets_wait_ticks_zero() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp_B", &"npc_7",
			LogisticsRouteScript.RouteType.OUTPUT)
	assert_int(route.wait_ticks).is_equal(0)


# ---- AC-3: Duplicate OUTPUT slot is blocked ----------------------------------

func test_create_route_blocks_second_output_on_same_source() -> void:
	_system.create_route(&"lumber_camp", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)

	var result := _system.create_route(&"lumber_camp", &"storage_B", &"npc_2",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_bool(result["success"]).is_equal(false)


func test_create_route_second_output_returns_no_route() -> void:
	_system.create_route(&"lumber_camp", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)

	var result := _system.create_route(&"lumber_camp", &"storage_B", &"npc_2",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_object(result["route"]).is_null()


func test_create_route_second_output_does_not_increase_route_count() -> void:
	_system.create_route(&"lumber_camp", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)
	_system.create_route(&"lumber_camp", &"storage_B", &"npc_2",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_int(_system.get_active_routes().size()).is_equal(1)


func test_create_route_second_output_error_mentions_output_slots() -> void:
	_system.create_route(&"lumber_camp", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)

	var result := _system.create_route(&"lumber_camp", &"storage_B", &"npc_2",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_str(result["error"]).contains("no free output slots")


# Edge case: paused/deactivated route still occupies the output slot.
func test_create_route_paused_output_route_still_blocks_new_output() -> void:
	var first := _system.create_route(&"lumber_camp", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)
	first["route"].lifecycle_state = LogisticsRouteScript.LifecycleState.PAUSED

	var result := _system.create_route(&"lumber_camp", &"storage_B", &"npc_2",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_bool(result["success"]).is_equal(false)


# ---- AC-4: Duplicate INPUT slot is blocked -----------------------------------

func test_create_route_blocks_second_input_on_same_destination() -> void:
	_system.create_route(&"storage_A", &"sawmill", &"npc_1",
			LogisticsRouteScript.RouteType.INPUT)

	var result := _system.create_route(&"storage_B", &"sawmill", &"npc_2",
			LogisticsRouteScript.RouteType.INPUT)

	assert_bool(result["success"]).is_equal(false)


func test_create_route_second_input_error_mentions_input_slots() -> void:
	_system.create_route(&"storage_A", &"sawmill", &"npc_1",
			LogisticsRouteScript.RouteType.INPUT)

	var result := _system.create_route(&"storage_B", &"sawmill", &"npc_2",
			LogisticsRouteScript.RouteType.INPUT)

	assert_str(result["error"]).contains("no free input slots")


func test_create_route_second_input_does_not_increase_route_count() -> void:
	_system.create_route(&"storage_A", &"sawmill", &"npc_1",
			LogisticsRouteScript.RouteType.INPUT)
	_system.create_route(&"storage_B", &"sawmill", &"npc_2",
			LogisticsRouteScript.RouteType.INPUT)

	assert_int(_system.get_active_routes().size()).is_equal(1)


# Edge case: deactivated route still occupies the input slot.
func test_create_route_deactivated_input_route_still_blocks_new_input() -> void:
	var first := _system.create_route(&"storage_A", &"sawmill", &"npc_1",
			LogisticsRouteScript.RouteType.INPUT)
	first["route"].lifecycle_state = LogisticsRouteScript.LifecycleState.DEACTIVATED

	var result := _system.create_route(&"storage_B", &"sawmill", &"npc_2",
			LogisticsRouteScript.RouteType.INPUT)

	assert_bool(result["success"]).is_equal(false)


# ---- AC-5: Same source and destination is blocked ----------------------------

func test_create_route_blocks_same_source_and_destination() -> void:
	var result := _system.create_route(&"storage_A", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_bool(result["success"]).is_equal(false)


func test_create_route_same_building_error_message_is_exact() -> void:
	var result := _system.create_route(&"storage_A", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_str(result["error"]).is_equal("Source and destination cannot be the same building.")


func test_create_route_same_building_no_route_created() -> void:
	_system.create_route(&"storage_A", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_int(_system.get_active_routes().size()).is_equal(0)


# ---- Edge case: empty NPC ID still creates a route ---------------------------

func test_route_create_with_empty_npc_id_succeeds() -> void:
	var route := LogisticsRouteScript.create(&"storage_A", &"lumber_camp", &"",
			LogisticsRouteScript.RouteType.OUTPUT)

	assert_object(route).is_not_null()
	assert_bool(route.active).is_equal(true)


# ---- Verify OUTPUT block does not affect INPUT slot on same building ---------

func test_create_route_output_block_does_not_block_input_on_same_building() -> void:
	# Fill the output slot on "sawmill".
	_system.create_route(&"sawmill", &"storage_A", &"npc_1",
			LogisticsRouteScript.RouteType.OUTPUT)

	# INPUT route to "sawmill" as destination should still succeed.
	var result := _system.create_route(&"storage_B", &"sawmill", &"npc_2",
			LogisticsRouteScript.RouteType.INPUT)

	assert_bool(result["success"]).is_equal(true)
