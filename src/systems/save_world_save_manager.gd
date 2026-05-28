## Save/Load Orchestrator — Foundation layer Autoload.
## Manages save file I/O, schema versioning, and load order invariant.
## Per ADR-0006.

extends Node

const SCHEMA_VERSION: int = 1
const SAVE_PATH: String = "user://saves/"
const MAX_SLOTS: int = 10

var _registered_systems: Array[String] = []


## Register a system's save handler. Called by each system in _ready().
func register_save_system(system_name: String) -> void:
	if not _registered_systems.has(system_name):
		_registered_systems.append(system_name)


## Returns list of available (non-empty) save slot numbers.
func get_available_slots() -> Array[int]:
	var slots: Array[int] = []
	DirAccess.make_dir_absolute(SAVE_PATH)
	var files: PackedStringArray = DirAccess.get_files_at(SAVE_PATH)
	for file_name in files:
		# Match save_N.json but not save_N.meta.json — iterate data files directly
		# so slots orphaned by a crash (no .meta.json) remain accessible.
		if file_name.begins_with("save_") and file_name.ends_with(".json") \
				and not file_name.ends_with(".meta.json"):
			var slot_str := file_name.trim_prefix("save_").trim_suffix(".json")
			if slot_str.is_valid_int():
				slots.append(slot_str.to_int())
	return slots


## Get metadata for a save slot. Returns null if slot is empty.
func get_save_info(slot: int) -> Dictionary:
	var meta_path := SAVE_PATH + "save_" + str(slot) + ".meta.json"
	var file := FileAccess.open(meta_path, FileAccess.READ)
	if file:
		var content := file.get_as_text()
		file.close()
		var result: Variant = JSON.parse_string(content)
		if result is Dictionary:
			return result
	return {}


## Save game state to the given slot.
func save_game(slot: int) -> bool:
	if slot < 1 or slot > MAX_SLOTS:
		printerr("[WorldSaveManager] Invalid slot: ", slot)
		return false

	DirAccess.make_dir_absolute(SAVE_PATH)

	# Collect serialize data from all registered systems
	var data := {"schema_version": SCHEMA_VERSION, "timestamp": int(Time.get_unix_time_from_system())}

	for system_name in _registered_systems:
		var system: Object = Engine.get_singleton(system_name)
		if system and system.has_method("serialize"):
			var serialized: Dictionary = system.serialize()
			data[system_name] = serialized

	# Write to temp file, then rename for atomicity
	var tmp_path := SAVE_PATH + "save_" + str(slot) + ".json.tmp"
	var final_path := SAVE_PATH + "save_" + str(slot) + ".json"

	var tmp_file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp_file:
		tmp_file.store_string(JSON.stringify(data))
		tmp_file.close()
	else:
		printerr("[WorldSaveManager] Failed to open temp file for writing: ", tmp_path)
		return false

	var rename_err := DirAccess.rename_absolute(tmp_path, final_path)
	if rename_err != OK:
		printerr("[WorldSaveManager] Failed to rename temp file to final path: ", rename_err)
		DirAccess.remove_absolute(tmp_path)
		return false

	# Write metadata
	var meta_path := SAVE_PATH + "save_" + str(slot) + ".meta.json"
	var meta_file := FileAccess.open(meta_path, FileAccess.WRITE)
	if meta_file:
		var meta: Dictionary = {
			"schema_version": SCHEMA_VERSION,
			"timestamp": data.get("timestamp", 0),
		}
		# Extract day/tick if available
		var tick_data: Dictionary = data.get("TickSystem", {})
		if tick_data is Dictionary:
			meta["current_day"] = tick_data.get("current_day", 0)
			meta["tick_count"] = tick_data.get("tick_count", 0)
		meta_file.store_string(JSON.stringify(meta))
		meta_file.close()
	else:
		printerr("[WorldSaveManager] Failed to open meta file for writing: ", meta_path)
		return false

	print("[WorldSaveManager] Saved slot ", slot)
	return true


## Load game from the given slot.
func load_game(slot: int) -> bool:
	if slot < 1 or slot > MAX_SLOTS:
		printerr("[WorldSaveManager] Invalid slot: ", slot)
		return false

	var save_path := SAVE_PATH + "save_" + str(slot) + ".json"
	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		printerr("[WorldSaveManager] Save file not found: ", save_path)
		return false

	var content := file.get_as_text()
	file.close()

	var result: Variant = JSON.parse_string(content)
	if not result is Dictionary:
		printerr("[WorldSaveManager] Failed to parse save file: ", save_path)
		return false

	var data: Dictionary = result

	# Schema version check
	if data.get("schema_version", 0) > SCHEMA_VERSION:
		printerr("[WorldSaveManager] Save from newer game version: ", save_path)
		return false

	if data.get("schema_version", 0) < SCHEMA_VERSION:
		print("[WorldSaveManager] Migrating save from v", data.get("schema_version", 0), " to v", SCHEMA_VERSION)

	# Process deserialize in load order
	_process_deserialize_order(data)

	print("[WorldSaveManager] Loaded slot ", slot)
	return true


## Convenience: load the most recently written save slot.
func load_last() -> bool:
	var slots := get_available_slots()
	if slots.is_empty():
		return false

	var best_slot: int = slots[0]
	var best_timestamp: int = -1
	for slot in slots:
		var info := get_save_info(slot)
		var ts: int = info.get("timestamp", -1)
		if ts > best_timestamp:
			best_timestamp = ts
			best_slot = slot

	if best_timestamp == -1:
		slots.sort()
		best_slot = slots.back()

	return load_game(best_slot)


## Delete a save slot.
func delete_save(slot: int) -> bool:
	if slot < 1 or slot > MAX_SLOTS:
		return false

	DirAccess.make_dir_absolute(SAVE_PATH)
	var save_path := SAVE_PATH + "save_" + str(slot) + ".json"
	var meta_path := SAVE_PATH + "save_" + str(slot) + ".meta.json"

	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(meta_path)

	return true


## Internal: process deserialize in load order.
## Load order: ResourceRegistry -> GridMap -> Inventory -> Buildings -> NPCs -> Hunger -> Player -> Tick
func _process_deserialize_order(data: Dictionary) -> void:
	# Load order invariant (from ADR-0006)
	var load_order := [
		"ResourceRegistry",
		"GridMap",
		"Inventory",
		"Buildings",
		"NPCs",
		"Hunger",
		"Player",
		"TickSystem",
	]

	for system_name in load_order:
		if not _registered_systems.has(system_name):
			continue

		var system: Object = Engine.get_singleton(system_name)
		if not system or not system.has_method("deserialize"):
			continue

		var system_data: Dictionary = data.get(system_name, {})
		if system_data is Dictionary:
			system.deserialize(system_data)
