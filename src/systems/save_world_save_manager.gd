## Save/Load Orchestrator — Foundation layer Autoload.
## Manages save file I/O, schema versioning, and load order invariant.
## Per ADR-0006.

extends Node

const SCHEMA_VERSION: int = 1
const SAVE_PATH: String = "user://saves/"
const MAX_SLOTS: int = 10

## Systems serialised on save, in order.
const SAVE_SYSTEMS: Array[String] = ["OverworldSystem", "ProgressionSystem", "TaskSystem", "InventorySystem", "BuildingRegistry", "PathSystem", "NPCSystem", "HungerSystem", "LogisticsSystem", "WildSystem", "TickSystem"]

## Systems deserialised on load; InventorySystem must precede BuildingRegistry
## (containers must exist before buildings reference them). PathSystem follows
## BuildingRegistry so path bitmasks can connect to already-placed buildings.
## NPCSystem follows PathSystem so NPC home bases reference already-placed buildings.
## HungerSystem follows NPCSystem so food assignments can reference existing NPC IDs.
## LogisticsSystem follows NPCSystem so routes can reference already-restored NPCs.
## WildSystem follows the building/terrain systems; it only needs the (already restored)
## WorldGrid terrain to recompute forests before restoring serialized wild groups.
## ProgressionSystem leads: its unlock set has no dependency on other systems and
## buildings restored after it are never gated (place_building bypasses the gate anyway).
## TaskSystem follows ProgressionSystem so its grandfather pass sees the restored unlock set;
## it also precedes nothing it depends on (it only reads ProgressionSystem state on load).
## OverworldSystem leads: it only rebuilds its island model from world_seed + start_coord and
## depends on nothing else (the tactical map is restored separately from the WorldGrid blob).
const LOAD_ORDER: Array[String] = ["OverworldSystem", "ProgressionSystem", "TaskSystem", "InventorySystem", "BuildingRegistry", "PathSystem", "NPCSystem", "HungerSystem", "LogisticsSystem", "WildSystem", "TickSystem"]

## Per-map (tactical) systems for overworld tile-to-tile travel. Snapshotting/restoring just
## these (plus the WorldGrid) switches the active tile's colony while leaving the global
## systems (TickSystem time, ProgressionSystem tech, TaskSystem goals, OverworldSystem island)
## untouched, so they carry across maps. Order matches LOAD_ORDER's dependency chain:
## InventorySystem (storage containers) before BuildingRegistry; PathSystem/NPCSystem after
## buildings; HungerSystem/LogisticsSystem after NPCs; WildSystem after terrain/buildings.
const PER_MAP_SYSTEMS: Array[String] = ["InventorySystem", "BuildingRegistry", "PathSystem", "NPCSystem", "HungerSystem", "LogisticsSystem", "WildSystem"]

## Emitted after apply_pending_load() has finished deserialising all systems.
signal load_completed

var _registered_systems: Array[String] = []
## Scene-level WorldGrid node — not an Autoload, registered by MapRoot after it is ready.
var _world_grid: WorldGrid = null

## Staged load — populated by load_game(), consumed by apply_pending_load().
var _pending_load_data: Dictionary = {}
var _has_pending_load: bool = false

## --- Overworld multi-map (in-session) state ---
## Per-tile tactical colonies kept in memory while the session is alive: Vector2i -> snapshot
## Dictionary (the same shape save/load uses, but only WorldGrid + PER_MAP_SYSTEMS). This is
## NOT yet persisted to disk — a save still captures only the currently active map.
var _map_states: Dictionary = {}
## Overworld coord of the tactical map currently loaded into the live systems.
var _current_map_coord: Vector2i = Vector2i(-1, -1)
## Staged tile-to-tile travel — set before reload_current_scene(), consumed by MapRoot._ready.
var _pending_map_switch: bool = false
var _pending_map_coord: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_startup_cleanup()


## Register a system's save handler. Called by each system in _ready().
func register_save_system(system_name: String) -> void:
	if not _registered_systems.has(system_name):
		_registered_systems.append(system_name)


## Register the scene-level WorldGrid node. Called by MapRoot before apply_pending_load().
func register_world_grid(grid: WorldGrid) -> void:
	_world_grid = grid


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
	slots.sort()
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

	var data := {"schema_version": SCHEMA_VERSION, "timestamp": int(Time.get_unix_time_from_system())}

	if _world_grid != null:
		data["WorldGrid"] = _world_grid.serialize()

	for system_name in SAVE_SYSTEMS:
		var system: Node = get_node_or_null("/root/" + system_name)
		if system and system.has_method("serialize"):
			data[system_name] = system.serialize()

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


## Read a save slot from disk and stage it for application.
## Returns true if the file was read and validated successfully.
## Call apply_pending_load() after the game scene is fully initialised.
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

	if data.get("schema_version", 0) > SCHEMA_VERSION:
		printerr("[WorldSaveManager] Save from newer game version: ", save_path)
		return false

	if data.get("schema_version", 0) < SCHEMA_VERSION:
		print("[WorldSaveManager] Migrating save from v", data.get("schema_version", 0), " to v", SCHEMA_VERSION)

	_pending_load_data = data
	_has_pending_load = true
	print("[WorldSaveManager] Staged slot ", slot, " for load")
	return true


## Returns true if a staged save is waiting to be applied.
func has_pending_load() -> bool:
	return _has_pending_load


## Apply the staged save data to all registered systems.
## Must be called after the game scene (MapRoot, BuildingRegistry grid dependency) is ready.
func apply_pending_load() -> void:
	if not _has_pending_load:
		push_warning("[WorldSaveManager] apply_pending_load() called with no pending load")
		return
	var data := _pending_load_data
	_pending_load_data = {}
	# Flag stays true through deserialize so start-time listeners (e.g. DevStorageSetup,
	# which reacts to building_placed) can detect a load-in-progress and skip their seeding.
	_process_deserialize_order(data)
	_has_pending_load = false
	print("[WorldSaveManager] Applied pending load")
	load_completed.emit()


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


# ── Overworld tile-to-tile travel (in-session multi-map) ─────────────────────

## Records which overworld tile the live tactical systems currently represent. Set by MapRoot
## when a start is chosen, after a disk load, and after a map switch.
func set_current_map_coord(coord: Vector2i) -> void:
	_current_map_coord = coord


func get_current_map_coord() -> Vector2i:
	return _current_map_coord


## Captures the live tactical map (WorldGrid + PER_MAP_SYSTEMS) into the in-memory store under
## the current coord, so it can be restored when the player travels back. No-op if no current
## coord is set (e.g. before any start is chosen).
func snapshot_current_map_state() -> void:
	if _current_map_coord == Vector2i(-1, -1):
		return
	var snap: Dictionary = {}
	if _world_grid != null:
		snap["WorldGrid"] = _world_grid.serialize()
	for system_name in PER_MAP_SYSTEMS:
		var system: Node = get_node_or_null("/root/" + system_name)
		if system and system.has_method("serialize"):
			snap[system_name] = system.serialize()
	_map_states[_current_map_coord] = snap


func has_map_state(coord: Vector2i) -> bool:
	return _map_states.has(coord)


## Restores a previously snapshotted tactical map into the live systems. Each PER_MAP_SYSTEMS
## deserialize() clears its own prior state and re-emits its reconstruction signals (the same
## path a disk load uses), so the freshly reloaded scene repaints the restored colony.
func restore_map_state(coord: Vector2i) -> void:
	var snap: Variant = _map_states.get(coord)
	if not snap is Dictionary:
		return
	if _world_grid != null and (snap as Dictionary).get("WorldGrid") is Dictionary:
		_world_grid.deserialize((snap as Dictionary)["WorldGrid"])
	for system_name in PER_MAP_SYSTEMS:
		var system: Node = get_node_or_null("/root/" + system_name)
		if system == null or not system.has_method("deserialize"):
			continue
		var system_data: Variant = (snap as Dictionary).get(system_name)
		if system_data != null:
			system.deserialize(system_data)


## Clears every per-map system to its empty state. Needed when generating a fresh tile map: the
## PER_MAP_SYSTEMS are autoloads that survive the scene reload, so without this they would carry
## the previous tile's buildings/NPCs/containers onto the new terrain. Each deserialize() clears
## its own state first; InventorySystem and PathSystem take an Array, the rest take a Dictionary.
func reset_map_state() -> void:
	const ARRAY_TYPED: Array[String] = ["InventorySystem", "PathSystem"]
	for system_name in PER_MAP_SYSTEMS:
		var system: Node = get_node_or_null("/root/" + system_name)
		if system == null or not system.has_method("deserialize"):
			continue
		if ARRAY_TYPED.has(system_name):
			system.deserialize([] as Array)
		else:
			system.deserialize({} as Dictionary)


## Stages a tile-to-tile travel. MapRoot calls reload_current_scene() right after; the rebuilt
## MapRoot detects the pending switch in _ready and restores/generates the target tile's map.
func request_map_switch(coord: Vector2i) -> void:
	_pending_map_switch = true
	_pending_map_coord = coord


func has_pending_map_switch() -> bool:
	return _pending_map_switch


## Clears the pending-switch flag, marks the target as the current map, and returns its coord.
func consume_pending_map_switch() -> Vector2i:
	var coord: Vector2i = _pending_map_coord
	_pending_map_switch = false
	_pending_map_coord = Vector2i(-1, -1)
	_current_map_coord = coord
	return coord


## Internal: apply deserialized data in dependency order.
## WorldGrid is restored first so terrain is valid when BuildingRegistry calls place_building().
func _process_deserialize_order(data: Dictionary) -> void:
	if _world_grid != null:
		var grid_data: Variant = data.get("WorldGrid")
		if grid_data is Dictionary:
			_world_grid.deserialize(grid_data)
	for system_name in LOAD_ORDER:
		var system: Node = get_node_or_null("/root/" + system_name)
		if system == null or not system.has_method("deserialize"):
			continue
		var system_data: Variant = data.get(system_name)
		if system_data != null:
			system.deserialize(system_data)


## Resets every persistent system to game-start defaults before a new game is generated.
## Clears all global Autoload state (progression, tasks, time) and per-map state (buildings,
## NPCs, inventory, logistics) so nothing from a previously loaded save bleeds through.
## OverworldSystem is NOT reset here — _begin_new_game_start_pick calls generate() which clears it.
func reset_new_game() -> void:
	reset_map_state()
	ProgressionSystem.reset_to_initial()
	TaskSystem.deserialize({})
	TickSystem.reset()
	_map_states.clear()
	_current_map_coord = Vector2i(-1, -1)
	_pending_load_data = {}
	_has_pending_load = false


## Scan for and delete orphaned .tmp files left by a crashed save operation.
func _startup_cleanup() -> void:
	DirAccess.make_dir_absolute(SAVE_PATH)
	var files := DirAccess.get_files_at(SAVE_PATH)
	for file_name in files:
		if file_name.ends_with(".tmp"):
			DirAccess.remove_absolute(SAVE_PATH + file_name)
			push_warning("[WorldSaveManager] Cleaned up orphaned .tmp file: %s" % file_name)
