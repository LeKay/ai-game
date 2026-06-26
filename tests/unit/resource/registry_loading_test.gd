## gdUnit4 test suite for Story 001: Resource Registry JSON Loading and Schema.
##
## Covers AC-1 through AC-5: file loading, definition parsing, error paths, version storage.
## Each test creates its own ResourceRegistry instance; _ready() is not called
## (no scene tree), so load_from_file() is invoked explicitly.

extends GdUnitTestSuite

const ResourceRegistry := preload("res://src/systems/resource_registry.gd")

# Dedicated fixture — never the live data/resources.json (which changes as the game grows).
const _VALID_PATH := "res://tests/fixtures/valid_resources_fixture.json"
const _MALFORMED_PATH := "res://tests/fixtures/malformed_resources.json"
const _MISSING_PATH := "res://nonexistent/missing_file.json"
const _INVALID_RESOURCES_TYPE_PATH := "res://tests/fixtures/invalid_resources_type.json"
const _MISSING_RESOURCES_KEY_PATH := "res://tests/fixtures/missing_resources_key.json"


func _make_registry() -> ResourceRegistry:
	var reg := ResourceRegistry.new()
	auto_free(reg)
	return reg


# ---- AC-1: Valid file loads and caches all definitions ----

func test_registry_load_valid_file_returns_true() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_VALID_PATH)

	assert_bool(result).is_true()


func test_registry_load_valid_file_caches_wood() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	var wood = reg.get_definition(&"wood")

	assert_object(wood).is_not_null()


func test_registry_load_valid_file_caches_all_fixture_resources() -> void:
	# Checks every resource defined in valid_resources_fixture.json.
	# Update this list only when the fixture file itself changes.
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	var ids: Array[StringName] = [&"wood", &"berry"]
	for id: StringName in ids:
		assert_object(reg.get_definition(id)).is_not_null()


# ---- AC-2: get_definition returns full _ResourceDefinition struct ----

func test_registry_get_definition_display_name_correct() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	var wood = reg.get_definition(&"wood")

	assert_str(wood.display_name).is_equal("Wood")


func test_registry_get_definition_stack_limit_correct() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	var wood = reg.get_definition(&"wood")

	assert_int(wood.stack_limit).is_equal(99)


func test_registry_get_definition_optional_weight_loaded() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	var wood = reg.get_definition(&"wood")

	# valid_resources_fixture.json provides weight 2.5 for wood
	assert_float(wood.weight).is_equal_approx(2.5, 0.001)


func test_registry_get_definition_category_production_good() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	var wood = reg.get_definition(&"wood")

	assert_int(wood.category).is_equal(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)


func test_registry_get_definition_category_consumable() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	var berry = reg.get_definition(&"berry")

	assert_int(berry.category).is_equal(ResourceRegistry.ResourceCategory.CONSUMABLE)


func test_registry_get_definition_unknown_id_returns_null() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	var result = reg.get_definition(&"nonexistent_xyz")

	assert_object(result).is_null()


func test_registry_get_definition_before_load_returns_null() -> void:
	var reg := _make_registry()
	# No load_from_file() call

	var result = reg.get_definition(&"wood")

	assert_object(result).is_null()


# ---- AC-3: Missing file returns false ----

func test_registry_missing_file_returns_false() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_MISSING_PATH)

	assert_bool(result).is_false()


func test_registry_missing_file_leaves_definitions_empty() -> void:
	var reg := _make_registry()
	reg.load_from_file(_MISSING_PATH)

	var result = reg.get_definition(&"wood")

	assert_object(result).is_null()


# ---- AC-4: Malformed JSON returns false ----

func test_registry_malformed_json_returns_false() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_MALFORMED_PATH)

	assert_bool(result).is_false()


func test_registry_malformed_json_leaves_definitions_empty() -> void:
	var reg := _make_registry()
	reg.load_from_file(_MALFORMED_PATH)

	var result = reg.get_definition(&"wood")

	assert_object(result).is_null()


# ---- AC-5: Version field stored ----

func test_registry_version_stored_after_valid_load() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	# valid_resources_fixture.json has "version": 1
	assert_int(reg.get_registry_version()).is_equal(1)


func test_registry_version_zero_before_any_load() -> void:
	var reg := _make_registry()

	assert_int(reg.get_registry_version()).is_equal(0)


func test_registry_version_unchanged_after_missing_file() -> void:
	var reg := _make_registry()
	reg.load_from_file(_MISSING_PATH)

	assert_int(reg.get_registry_version()).is_equal(0)


func test_registry_version_unchanged_after_parse_failure() -> void:
	# invalid_resources_type.json has "version": 3 but "resources" is a string,
	# so JSON parses OK but _parse_resources returns false.
	# Verifies _registry_version is NOT updated when _parse_resources fails.
	var reg := _make_registry()
	reg.load_from_file(_INVALID_RESOURCES_TYPE_PATH)

	assert_int(reg.get_registry_version()).is_equal(0)


# ---- _parse_resources validation paths (previously uncovered) ----

func test_registry_invalid_resources_type_returns_false() -> void:
	# Exercises the _parse_resources Array-type guard — not reachable via malformed JSON.
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_INVALID_RESOURCES_TYPE_PATH)

	assert_bool(result).is_false()


func test_registry_invalid_resources_type_leaves_definitions_empty() -> void:
	var reg := _make_registry()
	reg.load_from_file(_INVALID_RESOURCES_TYPE_PATH)

	assert_object(reg.get_definition(&"wood")).is_null()


# ---- Missing 'resources' key ----

func test_registry_missing_resources_key_returns_false() -> void:
	var reg := _make_registry()

	var result: bool = reg.load_from_file(_MISSING_RESOURCES_KEY_PATH)

	assert_bool(result).is_false()


func test_registry_missing_resources_key_leaves_definitions_empty() -> void:
	var reg := _make_registry()
	reg.load_from_file(_MISSING_RESOURCES_KEY_PATH)

	assert_object(reg.get_definition(&"wood")).is_null()


# ---- Atomic swap: failed reload preserves previous valid state ----

func test_registry_failed_reload_preserves_prior_definitions() -> void:
	# First load succeeds; second load (invalid resources type) should return false
	# and leave the prior definitions intact — not destroy them.
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)

	reg.load_from_file(_INVALID_RESOURCES_TYPE_PATH)

	# Wood from the first load must still be reachable.
	assert_object(reg.get_definition(&"wood")).is_not_null()


func test_registry_failed_reload_preserves_prior_version() -> void:
	var reg := _make_registry()
	reg.load_from_file(_VALID_PATH)  # version 1

	reg.load_from_file(_INVALID_RESOURCES_TYPE_PATH)  # version 3, but parse fails

	assert_int(reg.get_registry_version()).is_equal(1)
