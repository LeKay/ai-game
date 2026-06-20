extends Node
## TaskSystem — Autoload singleton.
## Owns the player's Delivery Tasks. A task is granted when its Progression Tree node is
## unlocked; the player fulfils it by holding the required goods in inventory, then Completes
## it to consume those goods and receive the task's reward (currently +1 progression point).
##
## This is the SOURCE of progression points; ProgressionSystem is the SINK (it spends them in
## unlock()). The UI (TaskDialog) is a pure renderer of this state — it never owns it.
##
## Task definitions are data-driven from data/progression_tasks.json, keyed by node_id.
## See design/quick-specs/delivery-task-system-2026-06-20.md.

const TASKS_PATH: String = "res://data/progression_tasks.json"
const CURRENT_SCHEMA_VERSION: int = 1

const STATUS_ACTIVE: StringName = &"active"
const STATUS_COMPLETED: StringName = &"completed"

## Emitted when a task is first granted (node unlocked). The dialog appends a card.
signal task_granted(node_id: StringName)
## Emitted when a task's fulfilment may have changed (inventory moved). The dialog refreshes.
signal task_updated(node_id: StringName)
## Emitted when a task is completed (goods consumed, reward paid). The dialog drops the card.
signal task_completed(node_id: StringName)

## node_id -> task definition Dictionary:
##   { title: String, requires: Array[{resource: StringName, amount: int}], reward: Dictionary }
var _defs: Dictionary = {}
## node_id -> StringName status (STATUS_ACTIVE / STATUS_COMPLETED). Absent = not yet granted.
var _status: Dictionary = {}


func _ready() -> void:
	load_from_file(TASKS_PATH)
	if not ProgressionSystem.node_unlocked.is_connected(_on_node_unlocked):
		ProgressionSystem.node_unlocked.connect(_on_node_unlocked)
	if not InventorySystem.storage_changed.is_connected(_on_storage_changed):
		InventorySystem.storage_changed.connect(_on_storage_changed)


# --- Loading -----------------------------------------------------------------

## Opens path, parses JSON, caches the per-node task definitions. Returns false on
## file-open failure, parse error, or schema mismatch (fail-fast).
func load_from_file(path: String) -> bool:
	_defs.clear()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TaskSystem: Cannot open '%s'" % path)
		return false

	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("TaskSystem: JSON parse error at line %d: %s" % [
				json.get_error_line(), json.get_error_message()])
		return false

	var data: Variant = json.get_data()
	if not data is Dictionary:
		push_error("TaskSystem: Root JSON element must be an object")
		return false

	var version: int = int(data.get("version", 0))
	if version > CURRENT_SCHEMA_VERSION:
		push_error("TaskSystem: Data version %d exceeds game version %d" % [
				version, CURRENT_SCHEMA_VERSION])
		return false

	var tasks: Variant = data.get("tasks", {})
	if not tasks is Dictionary:
		push_error("TaskSystem: 'tasks' field must be an object")
		return false

	for raw_node_id: Variant in tasks:
		var node_id := StringName(str(raw_node_id))
		var def: Dictionary = _build_def(node_id, tasks[raw_node_id])
		if not def.is_empty():
			_defs[node_id] = def

	_validate_defs()
	return true


## Normalises one raw task entry into the internal definition shape. Returns {} on a
## malformed entry (logged) so a single bad task never aborts the whole load.
func _build_def(node_id: StringName, raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		push_error("TaskSystem: task '%s' is not an object" % node_id)
		return {}

	var requires: Array = []
	for entry: Variant in raw.get("requires", []):
		if entry is Dictionary and entry.has("resource") and entry.has("amount"):
			requires.append({
				"resource": StringName(str(entry["resource"])),
				"amount": maxi(1, int(entry["amount"])),
			})
	if requires.is_empty():
		push_error("TaskSystem: task '%s' has no valid 'requires' entries" % node_id)
		return {}

	var raw_reward: Variant = raw.get("reward", {})
	var reward: Dictionary = raw_reward if raw_reward is Dictionary else {}
	if not reward.has("type"):
		reward = {"type": "progression_point", "amount": 1}

	return {
		"title": str(raw.get("title", str(node_id).capitalize())),
		"requires": requires,
		"reward": reward,
	}


## Advisory load-time check: every required resource must be a real resource id, and every
## task must key a real progression node. Logs loudly so authoring typos fail fast.
## (Full prerequisite-closure reachability is enforced by hand-authoring per the spec.)
func _validate_defs() -> void:
	for node_id: StringName in _defs:
		if not ProgressionSystem.has_progression_node(node_id):
			push_error("TaskSystem: task references unknown node '%s'" % node_id)
		for req: Dictionary in _defs[node_id]["requires"]:
			var res: StringName = req["resource"]
			if not ResourceRegistry.is_valid_id(res):
				push_error("TaskSystem: task '%s' requires unknown resource '%s'" % [node_id, res])


# --- Queries (read-only; the dialog renders from these) ----------------------

## Active (granted, not-yet-completed) task node ids, in graph order for stable display.
func get_active_tasks() -> Array[StringName]:
	var out: Array[StringName] = []
	for node_id: StringName in ProgressionSystem.get_all_node_ids():
		if _status.get(node_id, &"") == STATUS_ACTIVE:
			out.append(node_id)
	return out


func has_task(node_id: StringName) -> bool:
	return _defs.has(node_id)


func get_task_title(node_id: StringName) -> String:
	return str(_defs.get(node_id, {}).get("title", ""))


## The requirement list for a task: Array of { resource: StringName, amount: int }.
func get_requirements(node_id: StringName) -> Array:
	return _defs.get(node_id, {}).get("requires", [])


## The reward payload for a task: { type: String, amount: int, ... }.
func get_reward(node_id: StringName) -> Dictionary:
	return _defs.get(node_id, {}).get("reward", {})


## How many of resource the player currently holds across all inventory containers.
func get_have(resource: StringName) -> int:
	return InventorySystem.get_global_quantity(resource)


## True when every required resource is present in sufficient quantity (possession-only).
func is_fulfilled(node_id: StringName) -> bool:
	for req: Dictionary in get_requirements(node_id):
		if InventorySystem.get_global_quantity(req["resource"]) < int(req["amount"]):
			return false
	return true


# --- Mutations ---------------------------------------------------------------

## Completes an active, fulfilled task: consumes the required goods from inventory (across
## containers), grants the reward, and marks the task completed. Returns false (no side
## effects) if the task is not active or not currently fulfilled.
func complete_task(node_id: StringName) -> bool:
	if _status.get(node_id, &"") != STATUS_ACTIVE:
		return false
	if not is_fulfilled(node_id):
		return false

	for req: Dictionary in get_requirements(node_id):
		_consume_global(req["resource"], int(req["amount"]))

	_grant_reward(get_reward(node_id))
	_status[node_id] = STATUS_COMPLETED
	task_completed.emit(node_id)
	return true


## Removes `amount` units of resource from inventory, drawing across containers as needed.
## Callers must pre-check availability (complete_task does via is_fulfilled).
func _consume_global(resource: StringName, amount: int) -> void:
	var remaining: int = amount
	while remaining > 0:
		var container_id: StringName = InventorySystem.find_container_with(resource)
		if container_id == &"":
			break
		var here: int = InventorySystem.get_resource_quantity(container_id, resource)
		var take: int = mini(remaining, here)
		if take <= 0:
			break
		InventorySystem.try_consume(container_id, resource, take)
		remaining -= take


## Dispatches a task reward by type. progression_point credits the ProgressionSystem balance;
## other types are reserved for future tasks (logged until implemented).
func _grant_reward(reward: Dictionary) -> void:
	match str(reward.get("type", "")):
		"progression_point":
			ProgressionSystem.add_points(int(reward.get("amount", 1)))
		_:
			push_warning("TaskSystem: unhandled reward type '%s'" % reward.get("type", ""))


# --- Signal handlers ---------------------------------------------------------

## A node was unlocked: grant its task (once) if one is authored. The root grants none.
func _on_node_unlocked(node_id: StringName) -> void:
	if _defs.has(node_id) and not _status.has(node_id):
		_status[node_id] = STATUS_ACTIVE
		task_granted.emit(node_id)


## Inventory changed somewhere: every active task's fulfilment may have flipped — nudge the UI.
func _on_storage_changed(_container_id: StringName) -> void:
	for node_id: StringName in get_active_tasks():
		task_updated.emit(node_id)


# --- Save / Load -------------------------------------------------------------

## Serializes per-node task status for save files.
func serialize() -> Dictionary:
	var status: Dictionary = {}
	for node_id: StringName in _status:
		status[str(node_id)] = str(_status[node_id])
	return {"status": status}


## Restores task status. Runs AFTER ProgressionSystem.deserialize() (see WorldSaveManager
## LOAD_ORDER), which restores the unlocked set without emitting node_unlocked — so tasks are
## not re-granted here. Any unlocked node that has a task but no saved status (e.g. an older
## save predating this system) is grandfathered as completed so it can never block progress.
func deserialize(data: Variant) -> void:
	_status.clear()
	if data is Dictionary:
		var status: Variant = data.get("status", {})
		if status is Dictionary:
			for raw_node_id: Variant in status:
				_status[StringName(str(raw_node_id))] = StringName(str(status[raw_node_id]))
	for node_id: StringName in _defs:
		if ProgressionSystem.is_unlocked(node_id) and not _status.has(node_id):
			_status[node_id] = STATUS_COMPLETED
