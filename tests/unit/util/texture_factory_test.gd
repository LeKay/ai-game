## GdUnit4 test suite for TextureFactory (Phase 1 utility extraction).
##
## Verifies procedural image dimensions and representative pixels — see
## docs/architecture/refactor-plan-code-consolidation-2026-06-13.md.

extends GdUnitTestSuite

const TextureFactoryScript := preload("res://src/util/texture_factory.gd")


# ---- circle ------------------------------------------------------------------

func test_circle_size_is_diameter() -> void:
	var tex := TextureFactoryScript.circle(5, Color.RED)
	assert_int(tex.get_width()).is_equal(10)
	assert_int(tex.get_height()).is_equal(10)


func test_circle_center_is_filled() -> void:
	var tex := TextureFactoryScript.circle(5, Color.RED)
	var px: Color = tex.get_image().get_pixel(5, 5)
	assert_float(px.a).is_equal(1.0)
	assert_float(px.r).is_equal(1.0)


func test_circle_corner_is_transparent() -> void:
	var tex := TextureFactoryScript.circle(5, Color.RED)
	# Corner (0,0) is dx=dy=-5 -> distance^2 = 50 > 25, outside the circle.
	assert_float(tex.get_image().get_pixel(0, 0).a).is_equal(0.0)


# ---- solid_tile --------------------------------------------------------------

func test_solid_tile_size() -> void:
	var img := TextureFactoryScript.solid_tile(8, Color.BLUE)
	assert_int(img.get_width()).is_equal(8)
	assert_int(img.get_height()).is_equal(8)


func test_solid_tile_interior_is_fill_color() -> void:
	var img := TextureFactoryScript.solid_tile(8, Color.BLUE)
	assert_bool(img.get_pixel(4, 4).is_equal_approx(Color.BLUE)).is_true()


func test_solid_tile_border_is_darkened() -> void:
	var img := TextureFactoryScript.solid_tile(8, Color.BLUE)
	# Edge pixel uses Color.darkened(0.25), strictly darker than the interior.
	assert_bool(img.get_pixel(0, 0).b < Color.BLUE.b).is_true()


# ---- tile_highlight ----------------------------------------------------------

func test_tile_highlight_size() -> void:
	var tex := TextureFactoryScript.tile_highlight(16, Color(0, 0, 1, 0.2), Color(0, 0, 1, 0.8))
	assert_int(tex.get_width()).is_equal(16)


func test_tile_highlight_interior_is_fill() -> void:
	var fill := Color(0, 0, 1, 0.2)
	var tex := TextureFactoryScript.tile_highlight(16, fill, Color(0, 0, 1, 0.8), 2)
	assert_bool(tex.get_image().get_pixel(8, 8).is_equal_approx(fill)).is_true()


func test_tile_highlight_edge_is_border() -> void:
	var border := Color(0, 0, 1, 0.8)
	var tex := TextureFactoryScript.tile_highlight(16, Color(0, 0, 1, 0.2), border, 2)
	assert_bool(tex.get_image().get_pixel(0, 0).is_equal_approx(border)).is_true()
