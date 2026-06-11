class_name DraggableWindowTest
extends GdUnitTestSuite
## Unit tests for DraggableWindow.clamp_position — ADR-0014.
## Pure, deterministic geometry: keeps a dragged window fully inside the viewport.

const VIEWPORT := Vector2(1000, 800)
const WIN := Vector2(200, 150)

# A position already fully inside the viewport is returned unchanged.
func test_clamp_position_inside_bounds_unchanged() -> void:
	# Arrange
	var pos := Vector2(300, 250)
	# Act
	var result := DraggableWindow.clamp_position(pos, WIN, VIEWPORT)
	# Assert
	assert_that(result).is_equal(Vector2(300, 250))

# Negative X is clamped to the left edge (0).
func test_clamp_position_negative_x_clamps_to_left() -> void:
	var result := DraggableWindow.clamp_position(Vector2(-50, 250), WIN, VIEWPORT)
	assert_that(result).is_equal(Vector2(0, 250))

# Negative Y is clamped to the top edge (0).
func test_clamp_position_negative_y_clamps_to_top() -> void:
	var result := DraggableWindow.clamp_position(Vector2(300, -30), WIN, VIEWPORT)
	assert_that(result).is_equal(Vector2(300, 0))

# Past the right edge clamps so the window's right side sits on the viewport edge.
func test_clamp_position_past_right_clamps_to_max_x() -> void:
	# max_x = 1000 - 200 = 800
	var result := DraggableWindow.clamp_position(Vector2(950, 250), WIN, VIEWPORT)
	assert_that(result).is_equal(Vector2(800, 250))

# Past the bottom edge clamps so the window's bottom sits on the viewport edge.
func test_clamp_position_past_bottom_clamps_to_max_y() -> void:
	# max_y = 800 - 150 = 650
	var result := DraggableWindow.clamp_position(Vector2(300, 770), WIN, VIEWPORT)
	assert_that(result).is_equal(Vector2(300, 650))

# Exact bottom-right corner placement is preserved (boundary value).
func test_clamp_position_exact_bottom_right_corner_preserved() -> void:
	var result := DraggableWindow.clamp_position(Vector2(800, 650), WIN, VIEWPORT)
	assert_that(result).is_equal(Vector2(800, 650))

# A window wider than the viewport is pinned to x=0 (never produces a negative max).
func test_clamp_position_window_wider_than_viewport_pins_x_to_zero() -> void:
	var oversized := Vector2(1200, 150)
	var result := DraggableWindow.clamp_position(Vector2(50, 100), oversized, VIEWPORT)
	assert_that(result.x).is_equal(0.0)

# A window taller than the viewport is pinned to y=0.
func test_clamp_position_window_taller_than_viewport_pins_y_to_zero() -> void:
	var oversized := Vector2(200, 900)
	var result := DraggableWindow.clamp_position(Vector2(100, 50), oversized, VIEWPORT)
	assert_that(result.y).is_equal(0.0)
