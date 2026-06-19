## GdUnit4 test suite for the data-driven resource presentation API added in
## Phase 3 of the code-consolidation refactor: get_glyph / has_world_icon /
## get_world_icon_texture.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md.

extends GdUnitTestSuite

const ResourceRegistry := preload("res://src/systems/resource_registry.gd")

const _FIXTURE := "res://tests/fixtures/glyph_world_icon_fixture.json"


func _make_registry() -> ResourceRegistry:
	var reg := ResourceRegistry.new()
	auto_free(reg)
	reg.load_from_file(_FIXTURE)
	return reg


# ---- get_glyph ---------------------------------------------------------------

func test_get_glyph_returns_defined_glyph() -> void:
	var reg := _make_registry()
	assert_str(reg.get_glyph(&"wood")).is_equal("🪵")


func test_get_glyph_returns_glyph_for_consumable() -> void:
	var reg := _make_registry()
	assert_str(reg.get_glyph(&"bread")).is_equal("🍞")


func test_get_glyph_unknown_returns_package_fallback() -> void:
	var reg := _make_registry()
	assert_str(reg.get_glyph(&"does_not_exist")).is_equal("📦")


# ---- has_world_icon ----------------------------------------------------------

func test_has_world_icon_true_for_terrain_resource() -> void:
	var reg := _make_registry()
	assert_bool(reg.has_world_icon(&"wood")).is_true()


func test_has_world_icon_false_when_no_world_path() -> void:
	var reg := _make_registry()
	assert_bool(reg.has_world_icon(&"bread")).is_false()


func test_has_world_icon_false_for_unknown() -> void:
	var reg := _make_registry()
	assert_bool(reg.has_world_icon(&"does_not_exist")).is_false()


# ---- get_world_icon_texture --------------------------------------------------

func test_world_icon_texture_falls_back_to_circle_when_no_art() -> void:
	# bread has no world_icon_path -> fallback circle of diameter 2*radius.
	var reg := _make_registry()
	var tex := reg.get_world_icon_texture(&"bread", 9)
	assert_object(tex).is_not_null()
	assert_int(tex.get_width()).is_equal(18)


func test_world_icon_texture_unknown_returns_fallback_circle() -> void:
	var reg := _make_registry()
	var tex := reg.get_world_icon_texture(&"does_not_exist", 5)
	assert_object(tex).is_not_null()
	assert_int(tex.get_width()).is_equal(10)
