extends Node
## ResourceRegistry — Autoload singleton (ADR-0002)
## Loads resource definitions from JSON at startup and provides O(1) lookup.
## All systems that handle resources reference this registry instead of hardcoding.

enum ResourceCategory { CONSUMABLE, PRODUCTION_GOOD }

const REGISTRY_PATH: String = "res://data/resources.json"
const _CATEGORY_CONSUMABLE: String = "consumable"

var _definitions: Dictionary = {}  # StringName -> _ResourceDefinition
var _registry_version: int = 0


class _ResourceDefinition:
	var id: StringName
	var display_name: String
	var category: int  # ResourceCategory value
	var stack_limit: int
	var icon_path: String
	var subcategory: String = ""
	var weight: float = 0.0
	var base_value: int = 0
	var max_charge: float = 100.0
	var description: String = ""
	var tags: Array[String] = []
	var deprecated: bool = false


func _ready() -> void:
	load_from_file(REGISTRY_PATH)


## Opens path, parses JSON, and caches all resource definitions.
## Returns false on file-open failure or JSON parse error (fail-fast).
## Schema field validation is handled by Story 002 (_validate_resource).
func load_from_file(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		# FileAccess.open() returns null on failure in Godot 4.4+ (not a bool).
		push_error("ResourceRegistry: Cannot open '%s'" % path)
		return false

	var json_text: String = file.get_as_text()
	var json: JSON = JSON.new()
	var err: Error = json.parse(json_text)
	if err != OK:
		push_error("ResourceRegistry: JSON parse error at line %d: %s" % [
				json.get_error_line(), json.get_error_message()])
		return false

	var data: Variant = json.get_data()
	if not data is Dictionary:
		push_error("ResourceRegistry: Root JSON element must be an object")
		return false

	if not data.has("resources"):
		push_error("ResourceRegistry: JSON is missing required 'resources' key")
		return false

	# Read the candidate version but do NOT write to _registry_version yet —
	# state is only updated after _parse_resources confirms full success (atomic).
	var new_version: int = int(data.get("version", 0))
	if not _parse_resources(data["resources"]):
		return false

	_registry_version = new_version
	return true


## Returns the _ResourceDefinition for id, or null if not found. O(1).
## Full API (is_valid_id, get_all_by_category) implemented in Story 003.
func get_definition(id: StringName) -> _ResourceDefinition:
	return _definitions.get(id, null)


## Returns the schema version number stored in the loaded JSON file.
func get_registry_version() -> int:
	return _registry_version


func _parse_resources(entries: Variant) -> bool:
	if not entries is Array:
		push_error("ResourceRegistry: 'resources' field must be an array")
		return false

	# Build into a local dict first; swap into _definitions only on full success
	# so a mid-array failure never corrupts the previously loaded state.
	var new_defs: Dictionary = {}
	for i: int in entries.size():
		var entry: Variant = entries[i]
		if not entry is Dictionary:
			push_error("ResourceRegistry: Resource at index %d is not an object" % i)
			return false
		var def: _ResourceDefinition = _build_definition(entry)
		if def == null:
			return false
		if new_defs.has(def.id):
			push_error("ResourceRegistry: Duplicate resource id '%s' at index %d" % [def.id, i])
			return false
		new_defs[def.id] = def

	_definitions = new_defs
	return true


func _build_definition(entry: Dictionary) -> _ResourceDefinition:
	# Use the 1-arg form of .get() so both absent keys and explicit JSON nulls
	# are treated as null — the 2-arg default is only used when the key is absent,
	# but JSON null bypasses it and produces int(null)=0 / str(null)="Null".
	var raw_id: Variant = entry.get("id")
	var id_str: String = str(raw_id) if raw_id != null else ""
	if id_str.is_empty():
		push_error("ResourceRegistry: Resource entry has missing or empty 'id' field")
		return null

	var def := _ResourceDefinition.new()
	def.id = StringName(id_str)

	var raw_display_name: Variant = entry.get("display_name")
	def.display_name = str(raw_display_name) if raw_display_name != null else ""

	var raw_cat: Variant = entry.get("category")
	var cat: String = str(raw_cat) if raw_cat != null else "production_good"
	if cat == _CATEGORY_CONSUMABLE:
		def.category = ResourceCategory.CONSUMABLE
	elif cat == "production_good":
		def.category = ResourceCategory.PRODUCTION_GOOD
	else:
		push_warning("ResourceRegistry: Unknown category '%s' on resource '%s', defaulting to PRODUCTION_GOOD" % [cat, id_str])
		def.category = ResourceCategory.PRODUCTION_GOOD

	var raw_stack: Variant = entry.get("stack_limit")
	var stack_val: int = int(raw_stack) if raw_stack != null else 1
	if stack_val < 1:
		push_warning("ResourceRegistry: 'stack_limit' on resource '%s' is %d (< 1), clamping to 1" % [id_str, stack_val])
		stack_val = 1
	def.stack_limit = stack_val

	var raw_icon: Variant = entry.get("icon_path")
	def.icon_path = str(raw_icon) if raw_icon != null else ""

	var raw_sub: Variant = entry.get("subcategory")
	def.subcategory = str(raw_sub) if raw_sub != null else ""

	var raw_weight: Variant = entry.get("weight")
	def.weight = float(raw_weight) if raw_weight != null else 0.0

	var raw_base: Variant = entry.get("base_value")
	def.base_value = int(raw_base) if raw_base != null else 0

	var raw_charge: Variant = entry.get("max_charge")
	def.max_charge = float(raw_charge) if raw_charge != null else 100.0

	var raw_desc: Variant = entry.get("description")
	def.description = str(raw_desc) if raw_desc != null else ""

	var raw_deprecated: Variant = entry.get("deprecated")
	if raw_deprecated == null:
		def.deprecated = false
	elif raw_deprecated is bool:
		def.deprecated = raw_deprecated
	else:
		push_warning("ResourceRegistry: 'deprecated' on resource '%s' is not a boolean (got %s), treating as false" % [id_str, type_string(typeof(raw_deprecated))])
		def.deprecated = false

	var raw_tags: Variant = entry.get("tags")
	if raw_tags is Array:
		for tag: Variant in raw_tags:
			if tag is String:
				def.tags.append(str(tag))

	return def
