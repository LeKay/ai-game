## gdUnit4 test suite for Story 002: Save Slot Management and Metadata.
##
## Covers AC-6 through AC-10.
## Uses Engine.register_singleton() / unregister_singleton() to inject mock
## systems without touching the Autoload scene graph. File I/O uses user://
## which is ephemeral; after_each cleans up all written files.

extends GdUnitTestSuite

const SAVE_PATH := "user://saves/"
const WorldSaveManagerScript := preload("res://src/systems/save_world_save_manager.gd")


# ---- Inner test doubles ----

class MockSaveSystem extends Node:
	var data: Dictionary = {}

	func serialize() -> Dictionary:
		return data.duplicate(true)

	func deserialize(_d: Dictionary) -> void:
		pass


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


func _write_save_file(slot: int, data: Dictionary) -> void:
	DirAccess.make_dir_absolute(SAVE_PATH)
	var path := SAVE_PATH + "save_" + str(slot) + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _write_tmp_file(slot: int, content: String) -> void:
	DirAccess.make_dir_absolute(SAVE_PATH)
	var path := SAVE_PATH + "save_" + str(slot) + ".json.tmp"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()


func _cleanup_test_saves() -> void:
	DirAccess.make_dir_absolute(SAVE_PATH)
	for slot in [1, 2, 3]:
		for suffix in [".json", ".meta.json", ".json.tmp"]:
			var path := SAVE_PATH + "save_" + str(slot) + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


# ---- AC-6: get_available_slots() reports filled slots ----

func test_save_slot_get_available_slots_returns_all_saved_slots() -> void:
	# Arrange
	_make_mock("SlotSysA", {"v": 1})
	_manager.save_game(1)
	_manager.save_game(2)
	_manager.save_game(3)

	# Act
	var slots := _manager.get_available_slots()

	# Assert
	assert_array(slots).contains_exactly([1, 2, 3])


func test_save_slot_get_available_slots_excludes_empty_slots() -> void:
	# Arrange — only slot 2 saved
	_make_mock("SlotSysB", {"v": 2})
	_manager.save_game(2)

	# Act
	var slots := _manager.get_available_slots()

	# Assert
	assert_array(slots).contains_exactly([2])
	assert_bool(slots.has(1)).is_false()
	assert_bool(slots.has(3)).is_false()


func test_save_slot_get_available_slots_returns_sorted_ascending() -> void:
	# Arrange — save in reverse order to confirm sort is applied
	_make_mock("SlotSysC", {"v": 3})
	_manager.save_game(3)
	_manager.save_game(1)
	_manager.save_game(2)

	# Act
	var slots := _manager.get_available_slots()

	# Assert — result must be ascending without caller needing to sort
	var sorted_copy := slots.duplicate()
	sorted_copy.sort()
	assert_array(slots).is_equal(sorted_copy)


# ---- AC-7: save_game creates both data and meta files ----

func test_save_slot_save_game_creates_data_file() -> void:
	# Arrange
	_make_mock("SlotSysD", {"v": 7})

	# Act
	var ok := _manager.save_game(2)

	# Assert
	assert_bool(ok).is_true()
	assert_bool(FileAccess.file_exists(SAVE_PATH + "save_2.json")).is_true()


func test_save_slot_save_game_creates_meta_file() -> void:
	# Arrange
	_make_mock("SlotSysE", {"v": 7})

	# Act
	var ok := _manager.save_game(2)

	# Assert
	assert_bool(ok).is_true()
	assert_bool(FileAccess.file_exists(SAVE_PATH + "save_2.meta.json")).is_true()


func test_save_slot_meta_file_contains_schema_version() -> void:
	# Arrange
	_make_mock("SlotSysF", {"v": 7})
	_manager.save_game(2)

	# Act
	var info := _manager.get_save_info(2)

	# Assert
	assert_int(info.get("schema_version", -1)).is_equal(1)


func test_save_slot_meta_file_timestamp_within_test_window() -> void:
	# Arrange
	_make_mock("SlotSysG", {"v": 7})
	var before := int(Time.get_unix_time_from_system())
	_manager.save_game(2)
	var after := int(Time.get_unix_time_from_system()) + 1

	# Act
	var info := _manager.get_save_info(2)

	# Assert — timestamp is within the test execution window
	var ts: int = info.get("timestamp", 0)
	assert_int(ts).is_greater_equal(before)
	assert_int(ts).is_less_equal(after)


# ---- AC-8: Missing .meta.json → get_save_info returns {} ----

func test_save_slot_get_save_info_returns_empty_dict_when_meta_missing() -> void:
	# Arrange — data file exists but no meta file
	_write_save_file(2, {"schema_version": 1, "timestamp": 0})
	var meta_path := SAVE_PATH + "save_2.meta.json"
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(meta_path)

	# Act
	var info := _manager.get_save_info(2)

	# Assert — empty dict, not null, so caller can use .is_empty()
	assert_bool(info is Dictionary).is_true()
	assert_bool(info.is_empty()).is_true()


func test_save_slot_get_save_info_returns_dict_not_null_for_missing_slot() -> void:
	# Arrange — no files at all for slot 3

	# Act
	var info := _manager.get_save_info(3)

	# Assert — returns a Dictionary (not null), caller checks .is_empty()
	assert_object(info).is_not_null()
	assert_bool(info is Dictionary).is_true()


# ---- AC-9: Atomic write preserves existing save on crash ----

func test_save_slot_existing_save_untouched_after_orphaned_tmp() -> void:
	# Arrange — write a known valid save to slot 1, then simulate orphaned .tmp
	var valid_data := {"schema_version": 1, "timestamp": 99999, "marker": "original"}
	_write_save_file(1, valid_data)
	_write_tmp_file(1, "{corrupted partial write")

	# Act — startup cleanup removes the orphan; original file stays
	_manager._startup_cleanup()

	# Assert — save_1.json is still valid and unmodified
	var file := FileAccess.open(SAVE_PATH + "save_1.json", FileAccess.READ)
	assert_object(file).is_not_null()
	if file:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		assert_bool(parsed is Dictionary).is_true()
		assert_int((parsed as Dictionary).get("timestamp", 0)).is_equal(99999)


func test_save_slot_no_tmp_file_remains_after_successful_save() -> void:
	# Arrange
	_make_mock("SlotSysH", {"v": 9})

	# Act
	_manager.save_game(1)

	# Assert — successful save leaves no orphaned .tmp
	assert_bool(FileAccess.file_exists(SAVE_PATH + "save_1.json.tmp")).is_false()


# ---- AC-10: _startup_cleanup removes orphaned .tmp files ----

func test_save_slot_startup_cleanup_removes_orphaned_tmp_file() -> void:
	# Arrange
	_write_tmp_file(1, "{partial}")
	assert_bool(FileAccess.file_exists(SAVE_PATH + "save_1.json.tmp")).is_true()

	# Act
	_manager._startup_cleanup()

	# Assert
	assert_bool(FileAccess.file_exists(SAVE_PATH + "save_1.json.tmp")).is_false()


func test_save_slot_startup_cleanup_does_not_remove_valid_save_files() -> void:
	# Arrange — valid save alongside an orphaned tmp
	_write_save_file(1, {"schema_version": 1})
	_write_tmp_file(2, "{partial}")

	# Act
	_manager._startup_cleanup()

	# Assert — valid save untouched; tmp removed
	assert_bool(FileAccess.file_exists(SAVE_PATH + "save_1.json")).is_true()
	assert_bool(FileAccess.file_exists(SAVE_PATH + "save_2.json.tmp")).is_false()


func test_save_slot_startup_cleanup_handles_empty_saves_dir_without_crash() -> void:
	# Arrange — clean directory, nothing to clean up
	_cleanup_test_saves()

	# Act — must not crash or error
	_manager._startup_cleanup()

	# Assert — trivially passes if no exception was raised
	assert_bool(true).is_true()
