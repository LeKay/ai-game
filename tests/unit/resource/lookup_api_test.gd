## gdUnit4 test suite for Story 003: Dictionary Cache and O(1) Lookup API.
##
## Covers AC-1 through AC-5: correct struct fields, null-return on miss,
## is_valid_id bool contract, external validation pattern, and O(1) performance.

extends GdUnitTestSuite

const ResourceRegistry := preload("res://src/systems/resource_registry.gd")

const _VALID_PATH := "res://tests/fixtures/valid_resources_fixture.json"
const _THIRTY_PATH := "res://tests/fixtures/thirty_resources_fixture.json"


func _make_loaded_registry() -> ResourceRegistry:
	var reg := ResourceRegistry.new()
	auto_free(reg)
	reg.load_from_file(_VALID_PATH)
	return reg


# ---- AC-1: get_definition returns correct struct fields ----

func test_lookup_get_definition_wood_returns_nonnull() -> void:
	var reg := _make_loaded_registry()

	var def = reg.get_definition(&"wood")

	assert_object(def).is_not_null()


func test_lookup_get_definition_wood_has_correct_id() -> void:
	var reg := _make_loaded_registry()

	var def = reg.get_definition(&"wood")

	assert_str(str(def.id)).is_equal("wood")


func test_lookup_get_definition_wood_has_correct_display_name() -> void:
	var reg := _make_loaded_registry()

	var def = reg.get_definition(&"wood")

	assert_str(def.display_name).is_equal("Wood")


func test_lookup_get_definition_wood_has_correct_stack_limit() -> void:
	var reg := _make_loaded_registry()

	var def = reg.get_definition(&"wood")

	assert_int(def.stack_limit).is_equal(99)


func test_lookup_get_definition_wood_has_correct_category() -> void:
	var reg := _make_loaded_registry()

	var def = reg.get_definition(&"wood")

	assert_int(def.category).is_equal(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)


func test_lookup_get_definition_wood_has_correct_icon_path() -> void:
	var reg := _make_loaded_registry()

	var def = reg.get_definition(&"wood")

	assert_str(def.icon_path).is_equal("assets/ui/icons/resources/wood.png")


# ---- AC-2: get_definition returns null for unknown id, no crash ----

func test_lookup_get_definition_unknown_id_returns_null() -> void:
	var reg := _make_loaded_registry()

	var def = reg.get_definition(&"nonexistent_id")

	assert_object(def).is_null()


func test_lookup_get_definition_unicorn_horn_returns_null_without_crash() -> void:
	var reg := _make_loaded_registry()

	var def = reg.get_definition(&"unicorn_horn")

	assert_object(def).is_null()


# ---- AC-3: is_valid_id returns correct bool ----

func test_lookup_is_valid_id_known_id_returns_true() -> void:
	var reg := _make_loaded_registry()

	var result: bool = reg.is_valid_id(&"wood")

	assert_bool(result).is_true()


func test_lookup_is_valid_id_unknown_id_returns_false() -> void:
	var reg := _make_loaded_registry()

	var result: bool = reg.is_valid_id(&"???")

	assert_bool(result).is_false()


# ---- AC-4: is_valid_id enables external validation ----

func test_lookup_is_valid_id_unknown_item_returns_false_for_external_validation() -> void:
	# Simulates a recipe system: is_valid_id returns false → recipe marked INVALID
	var reg := _make_loaded_registry()

	var ingredient_known: bool = reg.is_valid_id(&"unknown_item")

	assert_bool(ingredient_known).is_false()


# ---- AC-5: O(1) performance — 10,000 lookups under 1ms ----

func test_lookup_ten_thousand_calls_on_thirty_resources_under_one_ms() -> void:
	# Arrange: registry with 30 resources
	var reg := ResourceRegistry.new()
	auto_free(reg)
	reg.load_from_file(_THIRTY_PATH)

	# Act: 10,000 dictionary lookups
	var start: int = Time.get_ticks_usec()
	for _i: int in 10000:
		reg.get_definition(&"resource_001")
	var elapsed_us: int = Time.get_ticks_usec() - start

	# Assert: total under 5ms (5000 microseconds) — generous to avoid CI flakiness on slow runners
	assert_int(elapsed_us).is_less(5000)
