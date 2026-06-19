## GdUnit4 test suite for PathGeometry (Phase 1 utility extraction).
##
## Pure deterministic polyline math — see
## docs/architecture/refactor-plan-code-consolidation-2026-06-13.md.

extends GdUnitTestSuite

const PathGeometryScript := preload("res://src/util/path_geometry.gd")


# ---- length ------------------------------------------------------------------

func test_length_sums_segment_lengths() -> void:
	var path: Array[Vector2] = [Vector2(0, 0), Vector2(3, 0), Vector2(3, 4)]
	assert_float(PathGeometryScript.length(path)).is_equal_approx(7.0, 0.0001)


func test_length_single_point_is_zero() -> void:
	var path: Array[Vector2] = [Vector2(5, 5)]
	assert_float(PathGeometryScript.length(path)).is_equal(0.0)


func test_length_empty_is_zero() -> void:
	var path: Array[Vector2] = []
	assert_float(PathGeometryScript.length(path)).is_equal(0.0)


# ---- point_along -------------------------------------------------------------

func test_point_along_at_zero_returns_first_point() -> void:
	var path: Array[Vector2] = [Vector2(0, 0), Vector2(10, 0)]
	assert_vector(PathGeometryScript.point_along(path, 0.0)).is_equal(Vector2(0, 0))


func test_point_along_midpoint() -> void:
	var path: Array[Vector2] = [Vector2(0, 0), Vector2(10, 0)]
	assert_vector(PathGeometryScript.point_along(path, 5.0)).is_equal(Vector2(5, 0))


func test_point_along_crosses_segment_boundary() -> void:
	# First segment length 4 (0,0)->(4,0); t=6 lands 2 into the second segment (4,0)->(4,10).
	var path: Array[Vector2] = [Vector2(0, 0), Vector2(4, 0), Vector2(4, 10)]
	assert_vector(PathGeometryScript.point_along(path, 6.0)).is_equal(Vector2(4, 2))


func test_point_along_beyond_length_clamps_to_last() -> void:
	var path: Array[Vector2] = [Vector2(0, 0), Vector2(10, 0)]
	assert_vector(PathGeometryScript.point_along(path, 999.0)).is_equal(Vector2(10, 0))
