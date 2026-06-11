## gdUnit4 test suite for Story 001: WorldSaveManager Orchestrator.
##
## Covers AC-1 through AC-5.
## Uses Engine.register_singleton() / unregister_singleton() to inject mock
## systems without touching the Autoload scene graph. File I/O uses user://
## which is ephemeral; after_each cleans up all written files.

extends GdUnitTestSuite

const SAVE_PATH := "user://saves/"
const WorldSaveManagerScript := preload("res://src/systems/save_world_save_manager.gd")


# ---- Inner test doubles ----

class MockSaveSystem extends Node:
	var data: Dictionary = {}
	var last_deserialized: Dictionary = {}

	func serialize() -> Dictionary:
		return data.duplicate(true)

	func deserialize(d: Dictionary) -> void:
		last_deserialized = d.duplicate(true)


class OrderTrackingSystem extends Node:
	## call_log is a shared Array reference passed from the test; each
	## deserialize() call appends this system's tag so the test can assert
	## the exact call order across multiple systems.
	var call_log: Array
	var tag: String = ""

	func serialize() -> Dictionary:
		return {"tag": tag}

	func deserialize(_d: Dictionary) -> void:
		call_log.append(tag)


# ---- Fixtures ----

var _manager: Node
var _mock_nodes: Array[Node] = []
var _registered_names: Array[String] = []


func before_each() -> void:
	_manager = WorldSaveManagerScript.new()
	auto_free(_manager)
	_mock_nodes = []
	_registered_names = []
	_cleanup_test_saves()


func after_each() -> void:
	for name in _registered_names:
		if Engine.has_singleton(name):
			Engine.unregister_singleton(name)
	for node in _mock_nodes:
		if is_instance_valid(node):
			node.free()
	_cleanup_test_saves()


func _make_mock(system_name: String, serialize_data: Dictionary) -> MockSaveSystem:
	var mock := MockSaveSystem.new()
	mock.data = serialize_data
	_mock_nodes.append(mock)
	Engine.register_singleton(system_name, mock)
	_registered_names.append(system_name)
	_manager.register_save_system(system_name)
	return mock


func _make_tracker(system_name: String, tag: String, log: Array) -> OrderTrackingSystem:
	var tracker := OrderTrackingSystem.new()
	tracker.tag = tag
	tracker.call_log = log
	_mock_nodes.append(tracker)
	Engine.register_singleton(system_name, tracker)
	_registered_names.append(system_name)
	_manager.register_save_system(system_name)
	return tracker


func _write_save_file(slot: int, data: Dictionary) -> void:
	DirAccess.make_dir_absolute(SAVE_PATH)
	var path := SAVE_PATH + "save_" + str(slot) + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _read_save_json(slot: int) -> Dictionary:
	var path := SAVE_PATH + "save_" + str(slot) + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}


func _cleanup_test_saves() -> void:
	DirAccess.make_dir_absolute(SAVE_PATH)
	for slot in [1, 2, 3]:
		for suffix in [".json", ".meta.json", ".json.tmp"]:
			var path := SAVE_PATH + "save_" + str(slot) + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


# ---- Registration ----

func test_save_manager_register_tracks_system_name() -> void:
	_manager.register_save_system("TestSystemAlpha")
	assert_bool(_manager._registered_systems.has("TestSystemAlpha")).is_true()


func test_save_manager_register_idempotent_no_duplicates() -> void:
	_manager.register_save_system("TestSystemBeta")
	_manager.register_save_system("TestSystemBeta")
	var count: int = _manager._registered_systems.count("TestSystemBeta")
	assert_int(count).is_equal(1)


# ---- Slot bounds ----

func test_save_manager_save_rejects_slot_zero() -> void:
	var ok: bool = _manager.save_game(0)
	assert_bool(ok).is_false()


func test_save_manager_save_rejects_slot_above_max() -> void:
	var ok: bool = _manager.save_game(11)
	assert_bool(ok).is_false()


func test_save_manager_load_rejects_slot_zero() -> void:
	var ok: bool = _manager.load_game(0)
	assert_bool(ok).is_false()


func test_save_manager_load_rejects_slot_above_max() -> void:
	var ok: bool = _manager.load_game(11)
	assert_bool(ok).is_false()


# ---- AC-1: Multi-system save produces complete JSON ----

func test_save_manager_save_includes_all_registered_systems() -> void:
	# Arrange
	_make_mock("SystemAlpha", {"value": 10})
	_make_mock("SystemBeta", {"value": 20})
	_make_mock("SystemGamma", {"value": 30})

	# Act
	var ok: bool = _manager.save_game(1)

	# Assert
	assert_bool(ok).is_true()
	var data := _read_save_json(1)
	assert_bool(data.has("SystemAlpha")).is_true()
	assert_bool(data.has("SystemBeta")).is_true()
	assert_bool(data.has("SystemGamma")).is_true()
	assert_int(data["SystemAlpha"].get("value", -1)).is_equal(10)
	assert_int(data["SystemBeta"].get("value", -1)).is_equal(20)
	assert_int(data["SystemGamma"].get("value", -1)).is_equal(30)


func test_save_manager_save_writes_schema_version_at_top_level() -> void:
	# Arrange (no systems needed)

	# Act
	var ok: bool = _manager.save_game(1)

	# Assert
	assert_bool(ok).is_true()
	var data := _read_save_json(1)
	assert_int(data.get("schema_version", -1)).is_equal(1)


# ---- AC-2 & AC-3: Load order — TickSystem last ----

func test_save_manager_load_deserializes_ticksystem_after_gridmap() -> void:
	# Arrange
	var log: Array = []
	_make_tracker("GridMap", "GridMap", log)
	_make_tracker("Inventory", "Inventory", log)
	_make_tracker("TickSystem", "TickSystem", log)

	_write_save_file(1, {
		"schema_version": 1,
		"timestamp": 0,
		"GridMap": {},
		"Inventory": {},
		"TickSystem": {},
	})

	# Act
	var ok: bool = _manager.load_game(1)

	# Assert
	assert_bool(ok).is_true()
	var tick_index: int = log.find("TickSystem")
	var grid_index: int = log.find("GridMap")
	var inv_index: int = log.find("Inventory")
	assert_int(tick_index).is_greater(grid_index)
	assert_int(tick_index).is_greater(inv_index)


func test_save_manager_load_ticksystem_is_final_call_in_full_order() -> void:
	# Arrange — register all systems present in the load-order invariant
	var log: Array = []
	_make_tracker("GridMap", "GridMap", log)
	_make_tracker("Buildings", "Buildings", log)
	_make_tracker("NPCs", "NPCs", log)
	_make_tracker("Hunger", "Hunger", log)
	_make_tracker("Player", "Player", log)
	_make_tracker("TickSystem", "TickSystem", log)

	_write_save_file(1, {
		"schema_version": 1,
		"timestamp": 0,
		"GridMap": {}, "Buildings": {}, "NPCs": {},
		"Hunger": {}, "Player": {}, "TickSystem": {},
	})

	# Act
	_manager.load_game(1)

	# Assert — TickSystem must be the last entry in the deserialize log
	assert_str(log.back()).is_equal("TickSystem")


# ---- AC-4: Auto-registration ----

func test_save_manager_newly_registered_system_appears_in_next_save() -> void:
	# Arrange — register after manager creation (simulates _ready() late call)
	var mock := MockSaveSystem.new()
	mock.data = {"new_field": 99}
	_mock_nodes.append(mock)
	Engine.register_singleton("LateSystem", mock)
	_registered_names.append("LateSystem")
	_manager.register_save_system("LateSystem")

	# Act
	var ok: bool = _manager.save_game(1)

	# Assert
	assert_bool(ok).is_true()
	var data := _read_save_json(1)
	assert_bool(data.has("LateSystem")).is_true()
	assert_int(data["LateSystem"].get("new_field", -1)).is_equal(99)


# ---- AC-5: Deterministic serialization ----

func test_save_manager_identical_state_produces_identical_system_data() -> void:
	# Arrange
	_make_mock("SystemDelta", {"count": 7, "label": "alpha"})

	# Act — two saves of the same state
	_manager.save_game(1)
	_manager.save_game(2)

	# Assert — system data fields are identical (timestamp may differ)
	var data1 := _read_save_json(1)
	var data2 := _read_save_json(2)
	assert_bool(data1.has("SystemDelta")).is_true()
	assert_bool(data2.has("SystemDelta")).is_true()
	assert_dict(data1["SystemDelta"]).is_equal(data2["SystemDelta"])
	assert_int(data1.get("schema_version", -1)).is_equal(data2.get("schema_version", -1))


# ---- Schema version validation ----

func test_save_manager_load_rejects_newer_schema_version() -> void:
	_write_save_file(1, {"schema_version": 9999, "timestamp": 0})
	var ok: bool = _manager.load_game(1)
	assert_bool(ok).is_false()


func test_save_manager_load_accepts_current_schema_version() -> void:
	_write_save_file(1, {"schema_version": 1, "timestamp": 0})
	var ok: bool = _manager.load_game(1)
	assert_bool(ok).is_true()


func test_save_manager_load_accepts_older_schema_version() -> void:
	_write_save_file(1, {"schema_version": 0, "timestamp": 0})
	var ok: bool = _manager.load_game(1)
	assert_bool(ok).is_true()


func test_save_manager_load_rejects_corrupted_json() -> void:
	DirAccess.make_dir_absolute(SAVE_PATH)
	var path := SAVE_PATH + "save_1.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("{not: valid json!!!")
		file.close()
	var ok: bool = _manager.load_game(1)
	assert_bool(ok).is_false()


func test_save_manager_load_rejects_missing_slot() -> void:
	# Arrange — ensure slot 3 has no file
	var ok: bool = _manager.load_game(3)
	assert_bool(ok).is_false()
