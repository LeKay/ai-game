## GdUnit4 integration test suite for NPC System Story 003:
## Deposit and Storage Coordination (TR-npc-005).
##
## Tests AC-4 (persistent storage assignment across cycles) and
## AC-7 (WAITING state on full storage; resume on storage_changed signal).
## NPCSystem is instantiated directly with stubs for BuildingSystem and InventorySystem.

extends GdUnitTestSuite

const NPCSystemScript := preload("res://src/gameplay/npc_system.gd")

## Stub for _building_system.
class _BuildingStub extends RefCounted:
	var tiles: Dictionary = {}

	func get_building_tile(building_id: StringName) -> Vector2i:
		return tiles.get(building_id, Vector2i(-1, -1))


## Stub for _inventory_system — controls try_deposit() return value and emits storage_changed.
class _InventoryStub extends RefCounted:
	## Set to 0 (SUCCESS) or 1 (FAILURE_FULL) before each test as needed.
	var deposit_result: int = 0
	signal storage_changed(container_id: StringName)

	func try_deposit(_container_id: StringName, _resource_id: StringName, _qty: int) -> int:
		return deposit_result


const BUILDING_ID: StringName = &"test_building"
const STORAGE_ID: StringName = &"test_storage"
const HOME := Vector2i(10, 20)
## Storage 5 tiles east of HOME → travel_ticks_total = 5 × TICKS_PER_TILE(3) = 15.
const STORAGE_TILE := Vector2i(15, 20)
const STORAGE_TRAVEL_TICKS := 15

var _sys: NPCSystemScript
var _stub_build: _BuildingStub
var _stub_inv: _InventoryStub


func before_test() -> void:
	_stub_build = _BuildingStub.new()
	_stub_inv = _InventoryStub.new()
	_sys = NPCSystemScript.new()
	auto_free(_sys)
	_sys._building_system = _stub_build
	_sys._inventory_system = _stub_inv
	_stub_inv.storage_changed.connect(_sys._on_storage_changed)
	_stub_build.tiles[BUILDING_ID] = Vector2i(5, 20)


## Places a freshly recruited NPC directly into TRAVEL_TO_STORAGE state so deposit logic
## can be exercised without wiring up the full WORK_AT_BUILDING → carrier dispatch flow.
func _setup_npc_travel_to_storage() -> StringName:
	var npc_id := _sys.recruit_npc(HOME)
	var npc: NPCSystemScript.NPCInstance = _sys.all_npcs[npc_id]
	npc.state = NPCSystemScript.TaskState.TRAVEL_TO_STORAGE
	npc.assigned_building_id = BUILDING_ID
	npc.assigned_storage_id = STORAGE_ID
	npc.travel_destination = STORAGE_TILE
	npc.travel_ticks_total = STORAGE_TRAVEL_TICKS
	npc.travel_progress = 0
	npc.current_output_resource = &"wood"
	npc.current_output_amount = 5
	return npc_id


# =============================================================================
# AC-4: Persistent storage assignment
# =============================================================================

func test_storage_id_set_on_assign_npc() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal(str(STORAGE_ID))


func test_storage_id_retained_after_deposit_and_return_home() -> void:
	_stub_inv.deposit_result = 0  # SUCCESS
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)                   # arrive at storage → deposit
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)                   # return home
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.IDLE)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal(str(STORAGE_ID))


func test_storage_id_cleared_only_by_release_npc() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	_sys.assign_npc(npc_id, BUILDING_ID, STORAGE_ID)
	_sys.release_npc(npc_id)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal("")


func test_reassignment_with_new_storage_id_updates_field() -> void:
	_stub_inv.deposit_result = 0
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)   # deposit + RETURN_TO_BASE
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)   # arrive home → IDLE
	var new_storage_id: StringName = &"storage_b"
	_sys.assign_npc(npc_id, BUILDING_ID, new_storage_id)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal(str(new_storage_id))


func test_current_output_resource_survives_deposit_cycle() -> void:
	_stub_inv.deposit_result = 0
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	# Resource fields are not cleared by the deposit — carrier reloads them on next pickup.
	assert_str(str(_sys.all_npcs[npc_id].current_output_resource)).is_equal("wood")


# =============================================================================
# AC-7: WAITING state when storage full
# =============================================================================

func test_npc_enters_waiting_when_deposit_fails_full() -> void:
	_stub_inv.deposit_result = 1  # FAILURE_FULL
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WAITING)


func test_npc_storage_full_signal_emitted_on_deposit_failure_full() -> void:
	_stub_inv.deposit_result = 1
	var npc_id := _setup_npc_travel_to_storage()
	var fired := [false]
	_sys.npc_storage_full.connect(func(_id: StringName, _sid: StringName) -> void: fired[0] = true)
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_bool(fired[0]).is_true()


func test_npc_storage_full_signal_carries_correct_ids() -> void:
	_stub_inv.deposit_result = 1
	var npc_id := _setup_npc_travel_to_storage()
	var got_npc_id: StringName = &""
	var got_storage_id: StringName = &""
	_sys.npc_storage_full.connect(func(n: StringName, s: StringName) -> void:
		got_npc_id = n
		got_storage_id = s)
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_str(str(got_npc_id)).is_equal(str(npc_id))
	assert_str(str(got_storage_id)).is_equal(str(STORAGE_ID))




func test_waiting_npc_does_not_advance_timer_on_ticks() -> void:
	_stub_inv.deposit_result = 1
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)  # arrive → WAITING
	_sys._on_ticks_advanced(1000)                   # large tick burst
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WAITING)


func test_waiting_npc_not_in_available_npcs() -> void:
	_stub_inv.deposit_result = 1
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	var available := _sys.get_available_npcs()
	assert_bool(available.has(npc_id)).is_false()


func test_waiting_npc_transitions_to_return_to_base_on_storage_changed() -> void:
	_stub_inv.deposit_result = 1
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)  # → WAITING
	_stub_inv.deposit_result = 0                    # space freed
	_stub_inv.storage_changed.emit(STORAGE_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)


func test_npc_deposit_completed_signal_emitted_after_waiting_deposit() -> void:
	_stub_inv.deposit_result = 1
	_setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	var fired := [false]
	_sys.npc_deposit_completed.connect(func(_n: StringName, _s: StringName) -> void: fired[0] = true)
	_stub_inv.deposit_result = 0
	_stub_inv.storage_changed.emit(STORAGE_ID)
	assert_bool(fired[0]).is_true()




func test_waiting_npc_remains_waiting_when_storage_still_full_on_storage_changed() -> void:
	_stub_inv.deposit_result = 1  # stays full
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	_stub_inv.storage_changed.emit(STORAGE_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WAITING)


func test_storage_changed_different_container_does_not_affect_waiting_npc() -> void:
	_stub_inv.deposit_result = 1
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	_stub_inv.deposit_result = 0
	_stub_inv.storage_changed.emit(&"other_storage")  # wrong container
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WAITING)


func test_idle_npc_not_affected_by_storage_changed() -> void:
	var idle_id := _sys.recruit_npc(Vector2i(0, 0))
	_stub_inv.storage_changed.emit(STORAGE_ID)
	assert_int(_sys.get_npc_state(idle_id)).is_equal(NPCSystemScript.TaskState.IDLE)


# =============================================================================
# Deposit mechanics — immediate success
# =============================================================================

func test_npc_transitions_to_return_to_base_after_immediate_deposit() -> void:
	_stub_inv.deposit_result = 0
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)


func test_npc_deposit_completed_signal_emitted_on_immediate_deposit() -> void:
	_stub_inv.deposit_result = 0
	_setup_npc_travel_to_storage()
	var fired := [false]
	_sys.npc_deposit_completed.connect(func(_n: StringName, _s: StringName) -> void: fired[0] = true)
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_bool(fired[0]).is_true()


func test_npc_position_updates_to_storage_tile_on_arrival() -> void:
	_stub_inv.deposit_result = 0
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	var pos := _sys.get_npc_position(npc_id)
	assert_int(pos.x).is_equal(STORAGE_TILE.x)
	assert_int(pos.y).is_equal(STORAGE_TILE.y)


func test_return_travel_ticks_computed_from_storage_tile() -> void:
	# STORAGE_TILE(15,20) → HOME(10,20): 5 tiles × 3 = 15 ticks
	_stub_inv.deposit_result = 0
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_int(_sys.all_npcs[npc_id].travel_ticks_total).is_equal(15)


func test_npc_arrives_home_after_deposit_and_return_travel() -> void:
	_stub_inv.deposit_result = 0
	var npc_id := _setup_npc_travel_to_storage()
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)  # deposit → RETURN_TO_BASE
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)  # return home → IDLE
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.IDLE)
	var pos := _sys.get_npc_position(npc_id)
	assert_int(pos.x).is_equal(HOME.x)
	assert_int(pos.y).is_equal(HOME.y)


func test_npc_travel_completed_signal_emitted_on_storage_arrival() -> void:
	_stub_inv.deposit_result = 0
	_setup_npc_travel_to_storage()
	var fired := [false]
	_sys.npc_travel_completed.connect(func(_id: StringName, _dest: Vector2i) -> void: fired[0] = true)
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_bool(fired[0]).is_true()


# =============================================================================
# AC-7 edge case: multiple WAITING NPCs for same storage
# =============================================================================

func test_multiple_waiting_npcs_only_first_unblocked_per_storage_changed() -> void:
	# Arrange: two NPCs from different houses, both assigned to same storage
	const HOME_B := Vector2i(30, 20)
	const BUILDING_B: StringName = &"building_b"
	_stub_build.tiles[BUILDING_B] = Vector2i(35, 20)
	_stub_inv.deposit_result = 1  # FAILURE_FULL — both will enter WAITING

	var npc_a := _setup_npc_travel_to_storage()  # first inserted → processed first in loop

	var npc_b := _sys.recruit_npc(HOME_B)
	var inst_b: NPCSystemScript.NPCInstance = _sys.all_npcs[npc_b]
	inst_b.state = NPCSystemScript.TaskState.TRAVEL_TO_STORAGE
	inst_b.assigned_building_id = BUILDING_B
	inst_b.assigned_storage_id = STORAGE_ID  # same storage as npc_a
	inst_b.travel_destination = STORAGE_TILE
	inst_b.travel_ticks_total = STORAGE_TRAVEL_TICKS
	inst_b.travel_progress = 0
	inst_b.current_output_resource = &"stone"
	inst_b.current_output_amount = 3

	# Act: both arrive at storage → both enter WAITING
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_int(_sys.get_npc_state(npc_a)).is_equal(NPCSystemScript.TaskState.WAITING)
	assert_int(_sys.get_npc_state(npc_b)).is_equal(NPCSystemScript.TaskState.WAITING)

	# First storage_changed: only npc_a (insertion-order first) is unblocked
	_stub_inv.deposit_result = 0
	_stub_inv.storage_changed.emit(STORAGE_ID)
	assert_int(_sys.get_npc_state(npc_a)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)
	assert_int(_sys.get_npc_state(npc_b)).is_equal(NPCSystemScript.TaskState.WAITING)

	# Second storage_changed: npc_b now gets unblocked
	_stub_inv.storage_changed.emit(STORAGE_ID)
	assert_int(_sys.get_npc_state(npc_b)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)
