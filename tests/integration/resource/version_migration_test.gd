## gdUnit4 integration test suite for Story 005: Version Migration and Deprecated Resources.
##
## Covers AC-1 (migration warning + weight default), AC-2 (deprecated resource in cache),
## AC-3 (deprecated included in get_all_by_category), AC-4 (version downgrade blocked),
## AC-5 (integer weight cast to float).

extends GdUnitTestSuite

const ResourceRegistry := preload("res://src/systems/resource_registry.gd")

const _V0_NO_WEIGHT_PATH := "res://tests/fixtures/version_v0_no_weight_fixture.json"
const _V2_FUTURE_PATH := "res://tests/fixtures/version_future_v2_fixture.json"
const _DEPRECATED_PATH := "res://tests/fixtures/deprecated_resource_fixture.json"
const _INTEGER_WEIGHT_PATH := "res://tests/fixtures/integer_weight_fixture.json"


func _make_registry(path: String) -> ResourceRegistry:
	var reg := ResourceRegistry.new()
	auto_free(reg)
	reg.load_from_file(path)
	return reg


# ---- AC-1: Schema version migration — optional field defaults to 0.0 ----

func test_version_migration_v0_load_succeeds() -> void:
	# Arrange / Act — v0 fixture (no weight field) with CURRENT_SCHEMA_VERSION = 1
	var reg := ResourceRegistry.new()
	auto_free(reg)

	# Assert — loading older version must succeed (migration path, not failure)
	var result: bool = reg.load_from_file(_V0_NO_WEIGHT_PATH)
	assert_bool(result).is_true()


func test_version_migration_v0_weight_defaults_to_zero() -> void:
	# Arrange
	var reg := _make_registry(_V0_NO_WEIGHT_PATH)

	# Act
	var def = reg.get_definition(&"wood")

	# Assert — weight absent in JSON → defaults to 0.0
	assert_object(def).is_not_null()
	assert_float(def.weight).is_equal(0.0)


# ---- AC-2: Deprecated resource is accessible via get_definition ----

func test_deprecated_resource_returned_by_get_definition() -> void:
	# Arrange
	var reg := _make_registry(_DEPRECATED_PATH)

	# Act
	var def = reg.get_definition(&"old_tool")

	# Assert — deprecated resource is in cache, not hidden
	assert_object(def).is_not_null()
	assert_bool(def.deprecated).is_true()


func test_deprecated_resource_get_definition_returns_correct_id() -> void:
	# Arrange
	var reg := _make_registry(_DEPRECATED_PATH)

	# Act
	var def = reg.get_definition(&"old_tool")

	# Assert
	assert_str(str(def.id)).is_equal("old_tool")


# ---- AC-3: get_all_by_category includes deprecated resources ----

func test_deprecated_resource_included_in_get_all_by_category() -> void:
	# Arrange — fixture has berry (consumable, not deprecated) + old_tool (consumable, deprecated)
	var reg := _make_registry(_DEPRECATED_PATH)

	# Act
	var result: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.CONSUMABLE)

	# Assert — both entries returned; caller is responsible for filtering deprecated
	assert_int(result.size()).is_equal(2)
	var ids: Array = []
	for def in result:
		ids.append(str(def.id))
	assert_bool(ids.has("old_tool")).is_true()
	assert_bool(ids.has("berry")).is_true()


# ---- AC-4: Version downgrade blocks load ----

func test_version_downgrade_load_returns_false() -> void:
	# Arrange — fixture has "version": 2, CURRENT_SCHEMA_VERSION = 1
	var reg := ResourceRegistry.new()
	auto_free(reg)

	# Act
	var result: bool = reg.load_from_file(_V2_FUTURE_PATH)

	# Assert — load blocked
	assert_bool(result).is_false()


func test_version_downgrade_definitions_remain_empty() -> void:
	# Arrange
	var reg := ResourceRegistry.new()
	auto_free(reg)

	# Act
	reg.load_from_file(_V2_FUTURE_PATH)

	# Assert — no definitions cached when load is blocked
	assert_int(reg._definitions.size()).is_equal(0)


# ---- AC-5: Integer weight field cast to float ----

func test_integer_weight_stored_as_float() -> void:
	# Arrange — fixture has "weight": 2 (integer JSON value)
	var reg := _make_registry(_INTEGER_WEIGHT_PATH)

	# Act
	var def = reg.get_definition(&"wood")

	# Assert — stored as float 2.0, no type error
	assert_object(def).is_not_null()
	assert_float(def.weight).is_equal(2.0)
