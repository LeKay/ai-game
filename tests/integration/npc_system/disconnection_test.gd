## GdUnit4 integration test suite for NPC System Story 004:
## Disconnection and Demolition (TR-npc-006).
##
## Tests AC-9 (building demolition releases NPC), AC-10 (house demolition removes NPC),
## AC-rule8a (storage demolition clears assignment), AC-rule8b (WAITING NPC on storage demolition).
## NPCSystem is instantiated directly with stubs for BuildingSystem and InventorySystem.

extends GdUnitTestSuite

const NPCSystemScript := preload("res://src/gameplay/npc_system.gd")

## Stub for _building_system — exposes building_demolished signal.
class _BuildingStub extends RefCounted:
	var tiles: Dictionary = {}
	signal building_demolished(building_id: StringName)

	func get_building_tile(building_id: StringName) -> Vector2i:
		return tiles.get(building_id, Vector2i(-1, -1))


## Stub for _inventory_system — exposes both storage_changed and container_removed signals.
class _InventoryStub extends RefCounted:
	var deposit_result: int = 0
	signal storage_changed(container_id: StringName)
	signal container_removed(container_id: StringName)

	func try_deposit(_container_id: StringName, _resource_id: StringName, _qty: int) -> int:
		return deposit_result


const BUILDING_ID: StringName = &"test_building"
const STORAGE_ID: StringName = &"test_storage"
const HOME := Vector2i(10, 20)
## Building 5 tiles west of HOME → travel_ticks = 5 × TICKS_PER_TILE(3) = 15.
const BUILDING_TILE := Vector2i(5, 20)
const BUILDING_TRAVEL_TICKS := 15
## Storage 5 tiles east of HOME → travel_ticks = 5 × TICKS_PER_TILE(3) = 15.
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
	_stub_build.tiles[BUILDING_ID] = BUILDING_TILE
	_stub_build.building_demolished.connect(_sys._on_building_demolished)
	_stub_inv.storage_changed.connect(_sys._on_storage_changed)
	_stub_inv.container_removed.connect(_sys._on_container_removed)


## Puts a freshly recruited NPC directly into WORK_AT_BUILDING at the building tile.
func _setup_npc_working() -> StringName:
	var npc_id := _sys.recruit_npc(HOME)
	var npc: NPCSystemScript.NPCInstance = _sys.all_npcs[npc_id]
	npc.state = NPCSystemScript.TaskState.WORK_AT_BUILDING
	npc.position = BUILDING_TILE
	npc.assigned_building_id = BUILDING_ID
	npc.assigned_storage_id = STORAGE_ID
	return npc_id


## Puts an NPC into TRAVEL_TO_BUILDING mid-travel (progress = 5 of 15 ticks).
func _setup_npc_traveling_to_building() -> StringName:
	var npc_id := _sys.recruit_npc(HOME)
	var npc: NPCSystemScript.NPCInstance = _sys.all_npcs[npc_id]
	npc.state = NPCSystemScript.TaskState.TRAVEL_TO_BUILDING
	npc.position = HOME
	npc.assigned_building_id = BUILDING_ID
	npc.assigned_storage_id = STORAGE_ID
	npc.travel_destination = BUILDING_TILE
	npc.travel_ticks_total = BUILDING_TRAVEL_TICKS
	npc.travel_progress = 5
	return npc_id


## Puts an NPC into WAITING at the storage tile (full-storage scenario).
func _setup_npc_waiting() -> StringName:
	var npc_id := _sys.recruit_npc(HOME)
	var npc: NPCSystemScript.NPCInstance = _sys.all_npcs[npc_id]
	npc.state = NPCSystemScript.TaskState.WAITING
	npc.position = STORAGE_TILE
	npc.assigned_building_id = BUILDING_ID
	npc.assigned_storage_id = STORAGE_ID
	npc.current_output_resource = &"wood"
	npc.current_output_amount = 5
	return npc_id


# =============================================================================
# AC-9: Building demolition releases NPC
# =============================================================================

func test_building_demolition_npc_transitions_to_return_to_base() -> void:
	var npc_id := _setup_npc_working()
	_stub_build.building_demolished.emit(BUILDING_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)


func test_building_demolition_clears_assigned_building_id() -> void:
	var npc_id := _setup_npc_working()
	_stub_build.building_demolished.emit(BUILDING_ID)
	assert_str(str(_sys.all_npcs[npc_id].assigned_building_id)).is_equal("")


func test_building_demolition_clears_assigned_storage_id() -> void:
	var npc_id := _setup_npc_working()
	_stub_build.building_demolished.emit(BUILDING_ID)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal("")


func test_building_demolition_emits_npc_released_signal() -> void:
	var npc_id := _setup_npc_working()
	var released_id: StringName = &""
	_sys.npc_released.connect(func(id: StringName) -> void: released_id = id)
	_stub_build.building_demolished.emit(BUILDING_ID)
	assert_str(str(released_id)).is_equal(str(npc_id))


func test_building_demolition_npc_at_home_transitions_directly_to_idle() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	var npc: NPCSystemScript.NPCInstance = _sys.all_npcs[npc_id]
	npc.state = NPCSystemScript.TaskState.WORK_AT_BUILDING
	npc.position = HOME  # already at home tile
	npc.assigned_building_id = BUILDING_ID
	_stub_build.building_demolished.emit(BUILDING_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.IDLE)


func test_building_demolition_npc_in_travel_transitions_to_return_to_base() -> void:
	var npc_id := _setup_npc_traveling_to_building()
	_stub_build.building_demolished.emit(BUILDING_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)


func test_building_demolition_npc_arrives_home_and_becomes_idle() -> void:
	var npc_id := _setup_npc_working()
	_stub_build.building_demolished.emit(BUILDING_ID)
	# BUILDING_TILE(5,20) → HOME(10,20): 5 tiles × 3 = 15 ticks
	_sys._on_ticks_advanced(BUILDING_TRAVEL_TICKS)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.IDLE)
	var pos := _sys.get_npc_position(npc_id)
	assert_int(pos.x).is_equal(HOME.x)
	assert_int(pos.y).is_equal(HOME.y)


func test_building_demolition_different_building_does_not_release_npc() -> void:
	var npc_id := _setup_npc_working()
	_stub_build.building_demolished.emit(&"other_building")
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WORK_AT_BUILDING)


func test_building_demolition_npc_in_waiting_transitions_to_return_to_base() -> void:
	var npc_id := _setup_npc_waiting()
	_stub_build.building_demolished.emit(BUILDING_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)


# =============================================================================
# AC-10: House demolition removes NPC
# =============================================================================

func test_on_house_demolished_emits_house_demolished_signal() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	var received_ids: Array[StringName] = []
	_sys.house_demolished.connect(func(ids: Array[StringName]) -> void: received_ids = ids)
	_sys.on_house_demolished([npc_id])
	assert_bool(received_ids.has(npc_id)).is_true()


func test_remove_npc_erases_from_all_npcs() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	assert_bool(_sys.all_npcs.has(npc_id)).is_true()
	_sys.remove_npc(npc_id)
	assert_bool(_sys.all_npcs.has(npc_id)).is_false()


func test_remove_npc_emits_npc_removed_signal() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	var removed_id: StringName = &""
	_sys.npc_removed.connect(func(id: StringName) -> void: removed_id = id)
	_sys.remove_npc(npc_id)
	assert_str(str(removed_id)).is_equal(str(npc_id))


func test_remove_npc_decrements_npc_count() -> void:
	var npc_id := _sys.recruit_npc(HOME)
	assert_int(_sys.get_npc_count()).is_equal(1)
	_sys.remove_npc(npc_id)
	assert_int(_sys.get_npc_count()).is_equal(0)


func test_remove_npc_unknown_id_no_crash_and_no_signal() -> void:
	var fired := [false]
	_sys.npc_removed.connect(func(_id: StringName) -> void: fired[0] = true)
	_sys.remove_npc(&"nonexistent_npc")
	assert_int(_sys.get_npc_count()).is_equal(0)
	assert_bool(fired[0]).is_false()


func test_remove_npc_working_npc_erased_without_return_travel() -> void:
	var travel_started := [false]
	_sys.npc_travel_started.connect(func(_id: StringName, _dest: Vector2i, _ticks: int) -> void: travel_started[0] = true)
	var npc_id := _setup_npc_working()
	_sys.remove_npc(npc_id)
	assert_bool(_sys.all_npcs.has(npc_id)).is_false()
	assert_bool(travel_started[0]).is_false()


# =============================================================================
# AC-rule8a: Storage demolition clears NPC storage assignment
# =============================================================================

func test_container_removed_clears_assigned_storage_id() -> void:
	var npc_id := _setup_npc_working()
	_stub_inv.container_removed.emit(STORAGE_ID)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal("")


func test_container_removed_transitions_npc_to_return_to_base() -> void:
	var npc_id := _setup_npc_working()
	_stub_inv.container_removed.emit(STORAGE_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)


func test_container_removed_npc_arrives_home_and_becomes_idle() -> void:
	var npc_id := _setup_npc_working()
	_stub_inv.container_removed.emit(STORAGE_ID)
	# BUILDING_TILE(5,20) → HOME(10,20): 5 tiles × 3 = 15 ticks
	_sys._on_ticks_advanced(BUILDING_TRAVEL_TICKS)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.IDLE)
	var pos := _sys.get_npc_position(npc_id)
	assert_int(pos.x).is_equal(HOME.x)
	assert_int(pos.y).is_equal(HOME.y)


func test_container_removed_different_container_does_not_affect_npc() -> void:
	var npc_id := _setup_npc_working()
	_stub_inv.container_removed.emit(&"other_storage")
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.WORK_AT_BUILDING)


func test_container_removed_emits_npc_released_signal() -> void:
	var npc_id := _setup_npc_working()
	var released_id: StringName = &""
	_sys.npc_released.connect(func(id: StringName) -> void: released_id = id)
	_stub_inv.container_removed.emit(STORAGE_ID)
	assert_str(str(released_id)).is_equal(str(npc_id))


# =============================================================================
# AC-rule8b: WAITING NPC immediately exits on storage demolition
# =============================================================================

func test_waiting_npc_transitions_to_return_to_base_on_container_removed() -> void:
	var npc_id := _setup_npc_waiting()
	_stub_inv.container_removed.emit(STORAGE_ID)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)


func test_waiting_npc_storage_assignment_cleared_on_container_removed() -> void:
	var npc_id := _setup_npc_waiting()
	_stub_inv.container_removed.emit(STORAGE_ID)
	assert_str(str(_sys.all_npcs[npc_id].assigned_storage_id)).is_equal("")


func test_waiting_npc_arrives_home_and_becomes_idle_after_container_removed() -> void:
	var npc_id := _setup_npc_waiting()
	_stub_inv.container_removed.emit(STORAGE_ID)
	# STORAGE_TILE(15,20) → HOME(10,20): 5 tiles × 3 = 15 ticks
	_sys._on_ticks_advanced(STORAGE_TRAVEL_TICKS)
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.IDLE)
	var pos := _sys.get_npc_position(npc_id)
	assert_int(pos.x).is_equal(HOME.x)
	assert_int(pos.y).is_equal(HOME.y)


func test_waiting_npc_released_via_return_to_base_not_deposit_on_container_removed() -> void:
	# Verify the NPC is in RETURN_TO_BASE (not attempting deposit) after storage gone.
	# deposit_result = 0 (SUCCESS) by default — if try_deposit were called it would succeed,
	# but the NPC should skip deposit entirely and start return travel.
	var npc_id := _setup_npc_waiting()
	_stub_inv.container_removed.emit(STORAGE_ID)
	# RETURN_TO_BASE confirms deposit was not attempted (DEPOSIT state is skipped).
	assert_int(_sys.get_npc_state(npc_id)).is_equal(NPCSystemScript.TaskState.RETURN_TO_BASE)
	var npc: NPCSystemScript.NPCInstance = _sys.all_npcs[npc_id]
	assert_int(npc.travel_progress).is_equal(0)
