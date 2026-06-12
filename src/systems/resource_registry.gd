extends Node
## ResourceRegistry — Autoload singleton (ADR-0002)
## Loads resource definitions from JSON at startup and provides O(1) lookup.
## All systems that handle resources reference this registry instead of hardcoding.

enum ResourceCategory { CONSUMABLE, PRODUCTION_GOOD }

const REGISTRY_PATH: String = "res://data/resources.json"
const CURRENT_SCHEMA_VERSION: int = 1
const _CATEGORY_CONSUMABLE: String = "consumable"
const _CATEGORY_PRODUCTION_GOOD: String = "production_good"
const _VALID_CATEGORY_STRINGS: Array[String] = ["consumable", "production_good"]

var _definitions: Dictionary = {}  # StringName -> _ResourceDefinition
var _registry_version: int = 0


class _ResourceDefinition:
	var id: StringName
	var display_name: String
	var category: ResourceCategory
	var stack_limit: int
	var icon_path: String
	var subcategory: String = ""
	var weight: float = 0.0
	var base_value: int = 0
	var max_charge: float = 100.0
	var description: String = ""
	var tags: Array[String] = []
	var deprecated: bool = false
	var movement_cost: float = 4.0
	## Nutrition value — drives NPC efficiency via EfficiencyFormulas curve. 0 = inedible.
	var nutrition: float = 0.0


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
	file.close()
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

	if new_version > CURRENT_SCHEMA_VERSION:
		push_error("ResourceRegistry: Save version %d exceeds game version %d — cannot load" % [
				new_version, CURRENT_SCHEMA_VERSION])
		return false

	if new_version < CURRENT_SCHEMA_VERSION:
		push_warning("ResourceRegistry: Migrating registry from v%d to v%d — applying defaults" % [
				new_version, CURRENT_SCHEMA_VERSION])

	if not _parse_resources(data["resources"]):
		return false

	_registry_version = new_version
	return true


## Returns the _ResourceDefinition for id, or null if not found. O(1).
func get_definition(id: StringName) -> _ResourceDefinition:
	return _definitions.get(id, null)


## Returns true if id is present in the registry, false otherwise. O(1).
func is_valid_id(id: StringName) -> bool:
	return id in _definitions


## Returns a fresh Array of all definitions matching category. O(n).
## Intended for startup-only queries — callers that need repeated results should
## cache the returned Array. Mutating the Array does not affect _definitions.
func get_all_by_category(category: ResourceCategory) -> Array:
	var result: Array = []
	for def in _definitions.values():
		if def.category == category:
			result.append(def)
	return result


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
		var errors: Array[String] = _validate_resource(entry, i)
		if not errors.is_empty():
			for err: String in errors:
				push_error("ResourceRegistry validation: " + err)
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


## Validates a single resource entry Dictionary against the schema.
## Returns an Array of error strings; empty means valid.
## Recoverable errors (invalid category) emit push_warning; _build_definition defaults to PRODUCTION_GOOD.
## Fatal errors (missing required fields, invalid max_charge, stack_limit < 1) are returned as error strings.
func _validate_resource(entry: Dictionary, index: int) -> Array[String]:
	var errors: Array[String] = []
	var raw_id: Variant = entry.get("id")
	var resource_id: String = str(raw_id) if raw_id != null else "???"

	if raw_id == null or (raw_id is String and (raw_id as String).is_empty()):
		errors.append("Resource at index %d: missing or invalid 'id'" % index)

	if not entry.has("display_name") or entry.get("display_name") == null:
		errors.append("Resource at index %d: missing or invalid 'display_name'" % index)

	if not entry.has("category") or entry.get("category") == null:
		errors.append("Resource at index %d: missing 'category'" % index)
	elif entry["category"] not in _VALID_CATEGORY_STRINGS:
		# Invalid category is recoverable — _build_definition defaults to PRODUCTION_GOOD.
		push_warning("ResourceRegistry: Resource '%s' has invalid category '%s' — defaulting to 'production_good'" % [
				resource_id, entry["category"]])

	var raw_stack: Variant = entry.get("stack_limit")
	if raw_stack == null or not ((raw_stack is int or raw_stack is float) and raw_stack >= 1):
		errors.append("Resource at index %d: 'stack_limit' must be int >= 1 (got %s)" % [index, raw_stack])

	if not entry.has("icon_path") or entry.get("icon_path") == null:
		errors.append("Resource at index %d: missing or invalid 'icon_path'" % index)

	if entry.has("max_charge") and entry.get("max_charge") != null:
		var charge_val: Variant = entry.get("max_charge")
		if not (charge_val is float or charge_val is int):
			errors.append("Resource '%s': 'max_charge' must be a number" % resource_id)
		elif float(charge_val) <= 0.0:
			errors.append("Resource '%s': 'max_charge' must be > 0.0 (got %s)" % [resource_id, charge_val])

	return errors


## Builds a _ResourceDefinition from a validated entry. All required fields are
## guaranteed present and valid by _validate_resource — direct key access is safe.
func _build_definition(entry: Dictionary) -> _ResourceDefinition:
	var def := _ResourceDefinition.new()
	def.id = StringName(str(entry["id"]))
	def.display_name = str(entry["display_name"])
	var cat: String = str(entry["category"])
	def.category = ResourceCategory.CONSUMABLE if cat == _CATEGORY_CONSUMABLE else ResourceCategory.PRODUCTION_GOOD
	def.stack_limit = int(entry["stack_limit"])
	def.icon_path = str(entry["icon_path"])
	_apply_optional_fields(def, entry)
	return def


## Applies optional fields from entry onto an already-constructed definition.
func _apply_optional_fields(def: _ResourceDefinition, entry: Dictionary) -> void:
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
		push_warning("ResourceRegistry: 'deprecated' on resource '%s' is not a boolean (got %s), treating as false" % [def.id, type_string(typeof(raw_deprecated))])
		def.deprecated = false

	var raw_tags: Variant = entry.get("tags")
	if raw_tags is Array:
		for tag: Variant in raw_tags:
			if tag is String:
				def.tags.append(str(tag))

	var raw_movement_cost: Variant = entry.get("movement_cost")
	def.movement_cost = float(raw_movement_cost) if raw_movement_cost != null else 4.0

	var raw_nutrition: Variant = entry.get("nutrition")
	def.nutrition = float(raw_nutrition) if raw_nutrition != null else 0.0
