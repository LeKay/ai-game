## gdUnit4 test suite for Story 002: Schema Validation and Fail-Fast.
##
## Covers AC-1 through AC-5: missing required fields, invalid max_charge,
## invalid category defaulting, valid data, and zero stack_limit.

extends GdUnitTestSuite

const ResourceRegistry := preload("res://src/systems/resource_registry.gd")

const _VALID_PATH := "res://tests/fixtures/valid_resources_fixture.json"
const _MISSING_ID_PATH := "res://tests/fixtures/missing_id_fixture.json"
const _INVALID_MAX_CHARGE_PATH := "res://tests/fixtures/invalid_max_charge_fixture.json"
const _INVALID_CATEGORY_PATH := "res://tests/fixtures/invalid_category_fixture.json"
const _ZERO_STACK_LIMIT_PATH := "res://tests/fixtures/zero_stack_limit_fixture.json"


func _make_registry() -> ResourceRegistry:
	var reg := ResourceRegistry.new()
	auto_free(reg)
	return reg


func _valid_entry() -> Dictionary:
	return {
		"id": "wood",
		"display_name": "Wood",
		"category": "production_good",
		"stack_limit": 99,
		"icon_path": "assets/ui/icons/resources/wood.png"
	}


# ---- AC-1: Missing required field halts load ----

func test_validation_missing_id_load_returns_false() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_MISSING_ID_PATH)

	assert_bool(result).is_false()


func test_validation_missing_id_leaves_definitions_empty() -> void:
	var reg := _make_registry()
	reg.load_from_file(_MISSING_ID_PATH)

	assert_object(reg.get_definition(&"wood")).is_null()


func test_validation_missing_id_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry.erase("id")

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_missing_display_name_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry.erase("display_name")

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_missing_icon_path_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry.erase("icon_path")

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_missing_category_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry.erase("category")

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


# ---- AC-2: Invalid max_charge halts load ----

func test_validation_zero_max_charge_load_returns_false() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_INVALID_MAX_CHARGE_PATH)

	assert_bool(result).is_false()


func test_validation_zero_max_charge_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["max_charge"] = 0.0

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_negative_max_charge_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["max_charge"] = -1.0

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_max_charge_error_names_resource_id() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["max_charge"] = 0.0

	var errors: Array[String] = reg._validate_resource(entry, 0)

	var combined: String = " ".join(errors)
	assert_str(combined).contains("wood")


# ---- AC-3: Invalid category defaults without halting ----

func test_validation_invalid_category_load_returns_true() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_INVALID_CATEGORY_PATH)

	assert_bool(result).is_true()


func test_validation_invalid_category_resource_cached() -> void:
	var reg := _make_registry()
	reg.load_from_file(_INVALID_CATEGORY_PATH)

	assert_object(reg.get_definition(&"wood")).is_not_null()


func test_validation_invalid_category_defaults_to_production_good_category() -> void:
	var reg := _make_registry()
	reg.load_from_file(_INVALID_CATEGORY_PATH)

	var wood = reg.get_definition(&"wood")

	assert_int(wood.category).is_equal(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)


func test_validation_invalid_category_returns_no_errors() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["category"] = "misc"

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_empty()


func test_validation_invalid_category_mutates_entry_to_production_good() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["category"] = "misc"

	reg._validate_resource(entry, 0)

	assert_str(entry["category"]).is_equal("production_good")


# ---- AC-4: All valid fields — no errors ----

func test_validation_all_valid_load_returns_true() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_VALID_PATH)

	assert_bool(result).is_true()


func test_validation_all_valid_returns_empty_errors() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_empty()


func test_validation_positive_max_charge_returns_empty_errors() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["max_charge"] = 100.0

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_empty()


# ---- AC-5: stack_limit 0 halts load ----

func test_validation_zero_stack_limit_load_returns_false() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_ZERO_STACK_LIMIT_PATH)

	assert_bool(result).is_false()


func test_validation_zero_stack_limit_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["stack_limit"] = 0

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_negative_stack_limit_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["stack_limit"] = -5

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_float_stack_limit_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["stack_limit"] = 1.0  # float — JSON authors may write "stack_limit": 1.0 instead of 1

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_missing_stack_limit_key_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry.erase("stack_limit")

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_empty_id_returns_error_string() -> void:
	var reg := _make_registry()
	var entry: Dictionary = _valid_entry()
	entry["id"] = ""  # present but empty — distinct from missing key

	var errors: Array[String] = reg._validate_resource(entry, 0)

	assert_array(errors).is_not_empty()


func test_validation_all_valid_load_caches_multiple_entries() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	assert_object(reg.get_definition(&"wood")).is_not_null()
	assert_object(reg.get_definition(&"berry")).is_not_null()
