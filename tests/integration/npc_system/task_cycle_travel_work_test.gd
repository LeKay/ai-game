## GdUnit4 integration test suite for NPC System Story 002:
## Task Cycle — Travel and Work (TR-npc-002, TR-npc-003).
##
## Tests AC-3 (assignment starts travel), AC-5 (travel time formula),
## AC-6 (operator NPC cycle: no storage travel, release returns home).
## NPCSystem is instantiated directly with a BuildingSystem stub injected.

extends GdUnitTestSuite

const NPCSystemScript := preload("res://src/gameplay/npc_system.gd")

## Minimal stub satisfying NPCSystem._building_system.get_building_tile() contract.
class _BuildingStub extends RefCounted:
	var tiles: Dictionary = {}
	func get_building_tile(building_id: StringName) -> Vector2i:
		return tiles.get(building_id, Vector2i(-1, -1))

var _sys: NPCSystemScript
var _stub: _BuildingStub

const BUILDING_ID: StringName = &"test_building"
const STORAGE_ID: StringName = &"test_storage"
const HOME := Vector2i(10, 20)

func before_test() -> void:
	_stub = _BuildingStub.new()
	_sys = NPCSystemScript.new()
	auto_free(_sys)
	_sys._building_system = _stub


# =============================================================================
# AC-3: Task assignment starts travel
# =============================================================================

func test_assign_npc_returns_success_for_idle_npc() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	var result := _sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_int(result).is_equal(NPCSystemScript.AssignmentResult.SUCCESS)


func test_assign_npc_sets_state_to_travel_to_building() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.TRAVEL_TO_BUILDING)


func test_assign_npc_sets_travel_progress_to_zero() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_int(_sys.all_npcs[npc_id].travel_progress).is_equal(0)


func test_assign_npc_sets_assigned_building_id() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_str(str(_sys.all_npcs[npc_id].assigned_building_id)).is_equal(str(BUILDING_ID))


func test_assign_npc_sets_assigned_storage_id() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal(str(STORAGE_ID))


func test_assign_npc_emits_npc_assigned_signal() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	var fired := [false]
	_sys.npc_assigned.connect(func(_id: StringName, _bid: StringName) -> void: fired[0] = true)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_bool(fired[0]).is_true()


func test_assign_npc_emits_npc_travel_started_signal() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	var fired := [false]
	_sys.npc_travel_started.connect(func(_id: StringName, _dest: Vector2i, _t: int) -> void: fired[0] = true)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_bool(fired[0]).is_true()


func test_assign_npc_non_idle_returns_invalid_state() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)  # now TRAVEL_TO_BUILDING
	var result := _sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_int(result).is_equal(NPCSystemScript.AssignmentResult.INVALID_NPC_STATE)


func test_assign_npc_unknown_npc_returns_invalid_state() -> void:
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	var result := _sys.assign_npc(&"nonexistent", BUILDING_ID, STORAGE_ID)
	assert_int(result).is_equal(NPCSystemScript.AssignmentResult.INVALID_NPC_STATE)


func test_assign_npc_unknown_building_returns_building_not_found() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	# No tile registered for BUILDING_ID → stub returns (-1,-1)
	var result := _sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_int(result).is_equal(NPCSystemScript.AssignmentResult.BUILDING_NOT_FOUND)


func test_assigned_npc_not_in_available_npcs() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	var available := _sys.get_available_npcs()
	assert_bool(available.has(npc_id)).is_false()


# =============================================================================
# AC-5: Travel time = Manhattan distance × TICKS_PER_TILE
# =============================================================================

func test_ticks_per_tile_constant_is_3() -> void:
	assert_int(NPCSystemScript.TICKS_PER_TILE).is_equal(3)


func test_travel_ticks_total_equals_manhattan_distance_times_ticks_per_tile() -> void:
	# NPC at (2,3), building at (5,3): Manhattan = 3, ticks = 3 × 3 = 9
	var npc_id := _sys.recruit_npc(Vector2i(2, 3))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 3)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_int(_sys.all_npcs[npc_id].travel_ticks_total).is_equal(9)


func test_travel_ticks_total_zero_when_building_on_same_tile() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(5, 5))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 5)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_int(_sys.all_npcs[npc_id].travel_ticks_total).is_equal(0)


func test_travel_ticks_total_distance_10_gives_30() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(10, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_int(_sys.all_npcs[npc_id].travel_ticks_total).is_equal(30)


func test_npc_arrives_at_building_after_exact_travel_ticks() -> void:
	# NPC at (2,3), building at (5,3): travel_ticks_total = 9
	var npc_id := _sys.recruit_npc(Vector2i(2, 3))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 3)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(9)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WORK_AT_BUILDING)


func test_npc_position_updates_to_building_tile_on_arrival() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(2, 3))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 3)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(9)
	var pos := _sys.get_npc_position(npc_id)
	assert_int(pos.x).is_equal(5)
	assert_int(pos.y).is_equal(3)


func test_npc_still_travelling_one_tick_before_arrival() -> void:
	# travel_ticks_total = 9 — 8 ticks should not trigger arrival
	var npc_id := _sys.recruit_npc(Vector2i(2, 3))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 3)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(8)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.TRAVEL_TO_BUILDING)


func test_npc_arrives_with_excess_ticks() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(2, 3))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 3)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(500)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WORK_AT_BUILDING)


func test_npc_arrives_instantly_when_travel_ticks_total_is_zero() -> void:
	# Building on same tile as NPC — distance 0, NPC arrives on first tick
	var npc_id := _sys.recruit_npc(Vector2i(5, 5))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 5)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(1)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WORK_AT_BUILDING)


# =============================================================================
# AC-6: Operator NPC cycle (no storage travel)
# =============================================================================

func test_operator_stays_in_work_at_building_after_additional_ticks() -> void:
	# NPC at (0,0), building at (5,0): 5 tiles × 3 = 15 ticks to arrive
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)  # arrive at building
	_sys._on_ticks_advanced(200) # operator stays — no storage travel transition
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WORK_AT_BUILDING)


func test_release_npc_starts_return_to_base() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)
	_sys.release_npc(npc_id)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)


func test_release_npc_clears_assigned_building_id() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)
	_sys.release_npc(npc_id)
	assert_str(str(_sys.all_npcs[npc_id].assigned_building_id)).is_equal("")


func test_release_npc_clears_assigned_storage_id() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)
	_sys.release_npc(npc_id)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal("")


func test_release_npc_emits_npc_released_signal() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)
	var fired := [false]
	_sys.npc_released.connect(func(_id: StringName) -> void: fired[0] = true)
	_sys.release_npc(npc_id)
	assert_bool(fired[0]).is_true()


func test_npc_transitions_to_idle_after_returning_home() -> void:
	# NPC at (0,0), building at (5,0): 15 ticks to building, 15 ticks back home
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)  # arrive at building
	_sys.release_npc(npc_id)      # start return (5 tiles × 3 = 15 ticks)
	_sys._on_ticks_advanced(15)  # arrive home
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.IDLE)


func test_npc_position_is_home_base_after_return() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)
	_sys.release_npc(npc_id)
	_sys._on_ticks_advanced(15)
	var pos := _sys.get_npc_position(npc_id)
	assert_int(pos.x).is_equal(0)
	assert_int(pos.y).is_equal(0)


func test_npc_appears_in_available_npcs_after_returning_home() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)
	_sys.release_npc(npc_id)
	_sys._on_ticks_advanced(15)
	var available := _sys.get_available_npcs()
	assert_bool(available.has(npc_id)).is_true()


func test_npc_returned_home_signal_emitted_after_return_travel() -> void:
	var npc_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub.tiles[BUILDING_ID] = Vector2i(5, 0)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys._on_ticks_advanced(15)
	_sys.release_npc(npc_id)
	var fired := [false]
	_sys.npc_returned_home.connect(func(_id: StringName) -> void: fired[0] = true)
	_sys._on_ticks_advanced(15)
	assert_bool(fired[0]).is_true()


func test_get_assigned_npc_returns_npc_id_for_building() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_stub.tiles[BUILDING_ID] = Vector2i(10, 10)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_str(str(_sys.get_assigned_npc(BUILDING_ID))).is_equal(str(npc_id))


func test_get_assigned_npc_returns_empty_for_unassigned_building() -> void:
	assert_str(str(_sys.get_assigned_npc(BUILDING_ID))).is_equal("")
