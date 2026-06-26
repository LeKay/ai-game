## gdUnit4 test suite for Story 004: Category System and Filtering.
##
## Covers AC-1 through AC-5: CONSUMABLE filter, PRODUCTION_GOOD filter,
## empty-category returns Array (not null), caller-side base_value filter,
## and mutation isolation of the returned Array.

extends GdUnitTestSuite

const ResourceRegistry := preload("res://src/systems/resource_registry.gd")

const _MIXED_PATH := "res://tests/fixtures/mixed_category_fixture.json"
const _PROD_ONLY_PATH := "res://tests/fixtures/production_goods_only_fixture.json"
const _VALID_PATH := "res://tests/fixtures/valid_resources_fixture.json"


func _make_registry(path: String) -> ResourceRegistry:
	var reg := ResourceRegistry.new()
	auto_free(reg)
	reg.load_from_file(path)
	return reg


# ---- AC-1: CONSUMABLE filter returns only consumables ----

func test_category_filter_consumable_returns_only_consumables() -> void:
	# Arrange — mixed fixture has berry + bread (consumable), wood + stone (production_good)
	var reg := _make_registry(_MIXED_PATH)

	# Act
	var result: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.CONSUMABLE)

	# Assert — length 2, all entries are consumable
	assert_int(result.size()).is_equal(2)
	for def in result:
		assert_int(def.category).is_equal(ResourceRegistry.ResourceCategory.CONSUMABLE)


func test_category_filter_consumable_excludes_production_goods() -> void:
	# Arrange
	var reg := _make_registry(_MIXED_PATH)

	# Act
	var result: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.CONSUMABLE)

	# Assert — wood and stone must not appear
	var ids: Array = []
	for def in result:
		ids.append(str(def.id))
	assert_bool(ids.has("wood")).is_false()
	assert_bool(ids.has("stone")).is_false()


# ---- AC-2: PRODUCTION_GOOD filter returns only production goods ----

func test_category_filter_production_good_returns_only_production_goods() -> void:
	# Arrange
	var reg := _make_registry(_MIXED_PATH)

	# Act
	var result: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)

	# Assert — length 2, all entries are production_good
	assert_int(result.size()).is_equal(2)
	for def in result:
		assert_int(def.category).is_equal(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)


func test_category_filter_production_good_excludes_consumables() -> void:
	# Arrange
	var reg := _make_registry(_MIXED_PATH)

	# Act
	var result: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)

	# Assert — berry and bread must not appear
	var ids: Array = []
	for def in result:
		ids.append(str(def.id))
	assert_bool(ids.has("berry")).is_false()
	assert_bool(ids.has("bread")).is_false()


# ---- AC-3: Empty category returns empty Array, not null ----

func test_category_filter_consumable_on_all_production_goods_returns_empty_array() -> void:
	# Arrange — production_goods_only fixture has no consumables
	var reg := _make_registry(_PROD_ONLY_PATH)

	# Act
	var result: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.CONSUMABLE)

	# Assert — empty Array, not null, no crash
	assert_object(result).is_not_null()
	assert_int(result.size()).is_equal(0)


# ---- AC-4: Caller-side tradeable filtering (get_all_by_category returns all; caller filters) ----

func test_category_filter_caller_filters_by_base_value_excludes_zero() -> void:
	# Arrange — mixed fixture: wood (production_good, base_value:2), stone (production_good, base_value:0)
	var reg := _make_registry(_MIXED_PATH)

	# Act — get all production goods then filter by base_value > 0
	var all_production: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)
	var tradeable: Array = []
	for def in all_production:
		if def.base_value > 0:
			tradeable.append(def)

	# Assert — only wood qualifies; stone (base_value:0) excluded
	assert_int(tradeable.size()).is_equal(1)
	assert_str(str(tradeable[0].id)).is_equal("wood")


# ---- AC-5: Returned Array mutation does not affect internal cache ----

func test_category_filter_mutating_result_does_not_affect_definitions() -> void:
	# Arrange — valid fixture has 2 resources
	var reg := _make_registry(_VALID_PATH)
	var initial_size: int = reg._definitions.size()

	# Act — mutate the returned Array by appending a dummy value
	var result: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)
	result.append("dummy_entry")

	# Assert — internal cache unchanged
	assert_int(reg._definitions.size()).is_equal(initial_size)
	var second_call: Array = reg.get_all_by_category(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)
	assert_bool(second_call.has("dummy_entry")).is_false()
