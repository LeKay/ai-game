## GdUnit4 test suite for PathDotOverlay geometry (Phase 5 path-overlay dedup).
##
## l_path is pure; place_dots mutates passed Sprite2D nodes. See
## docs/architecture/refactor-plan-code-consolidation-2026-06-13.md.

extends GdUnitTestSuite

const PathDotOverlayScript := preload("res://src/scenes/map_root/path_dot_overlay.gd")


# ---- l_path ------------------------------------------------------------------

func test_l_path_horizontal_has_no_corner() -> void:
	# Same y → the corner coincides with the destination, so only two points.
	var path := PathDotOverlayScript.l_path(Vector2(0, 0), Vector2(10, 0))
	assert_int(path.size()).is_equal(2)
	assert_vector(path[0]).is_equal(Vector2(0, 0))
	assert_vector(path[1]).is_equal(Vector2(10, 0))


func test_l_path_vertical_has_no_corner() -> void:
	# Same x → the corner coincides with the source, so only two points.
	var path := PathDotOverlayScript.l_path(Vector2(0, 0), Vector2(0, 10))
	assert_int(path.size()).is_equal(2)
	assert_vector(path[1]).is_equal(Vector2(0, 10))


func test_l_path_diagonal_inserts_horizontal_first_corner() -> void:
	var path := PathDotOverlayScript.l_path(Vector2(0, 0), Vector2(10, 5))
	assert_int(path.size()).is_equal(3)
	assert_vector(path[1]).is_equal(Vector2(10, 0))  # horizontal first
	assert_vector(path[2]).is_equal(Vector2(10, 5))


func test_l_path_same_point_is_degenerate_pair() -> void:
	var path := PathDotOverlayScript.l_path(Vector2(5, 5), Vector2(5, 5))
	assert_int(path.size()).is_equal(2)


# ---- place_dots --------------------------------------------------------------

func _make_dots(n: int) -> Array:
	var dots: Array = []
	for _i in range(n):
		var s := Sprite2D.new()
		add_child(s)
		auto_free(s)
		dots.append(s)
	return dots


func test_place_dots_positions_along_path_and_returns_true() -> void:
	var dots := _make_dots(3)
	var path: Array[Vector2] = [Vector2(0, 0), Vector2(9, 0)]
	var ok: bool = PathDotOverlayScript.place_dots(dots, path, 0.0, Color.WHITE)
	assert_bool(ok).is_true()
	# spacing = 9 / 3 = 3 → dots at x = 0, 3, 6
	assert_vector((dots[0] as Sprite2D).position).is_equal(Vector2(0, 0))
	assert_vector((dots[1] as Sprite2D).position).is_equal(Vector2(3, 0))
	assert_vector((dots[2] as Sprite2D).position).is_equal(Vector2(6, 0))
	assert_bool((dots[2] as Sprite2D).visible).is_true()


func test_place_dots_degenerate_hides_and_returns_false() -> void:
	var dots := _make_dots(3)
	var path: Array[Vector2] = [Vector2(5, 5), Vector2(5, 5)]
	var ok: bool = PathDotOverlayScript.place_dots(dots, path, 0.0, Color.WHITE)
	assert_bool(ok).is_false()
	assert_bool((dots[0] as Sprite2D).visible).is_false()
