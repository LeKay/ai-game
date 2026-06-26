class_name PathDotOverlay
## Shared visual style + math for the dotted L-shaped path overlays used by the
## world-drag preview, storage-drag preview and pending-transport animations.
##
## Previously these three overlays duplicated the L-path construction, the line/
## marker setup and the flow-dot distribution, and each referenced its own copy of
## the `_PATH_*` constants. This is the single home for that style and the pure
## geometry helpers, so the interaction code can be decoupled from MapRoot later.
##
## NOTE: RouteLines uses a *different* flow style (fewer, slower dots) and keeps its
## own constants on purpose — only `l_path()` is shared with it.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 5).

const LINE_WIDTH: float = 2.5
const DOT_COUNT: int = 5
const DOT_RADIUS: int = 3
const DST_MARKER_RADIUS: int = 5
const DOT_SPEED: float = 80.0

const COLOR_VALID: Color = Color(0.290, 0.494, 0.659, 1.0)
const COLOR_INVALID: Color = Color(0.769, 0.353, 0.290, 1.0)


## Builds the L-shaped (horizontal-first) world-space path between two tile centers.
static func l_path(src_center: Vector2, dst_center: Vector2) -> Array[Vector2]:
	var path: Array[Vector2] = [src_center]
	var corner := Vector2(dst_center.x, src_center.y)
	if corner != src_center and corner != dst_center:
		path.append(corner)
	path.append(dst_center)
	return path


## Distributes `dots` evenly along `path` at flow offset `phase` (pixels), tinting
## them `color` and showing them. Hides all dots and returns false for a degenerate
## path (length < 1); returns true otherwise.
static func place_dots(dots: Array, path: Array[Vector2], phase: float, color: Color) -> bool:
	var path_len: float = PathGeometry.length(path)
	if path_len < 1.0:
		for d: Sprite2D in dots:
			d.visible = false
		return false
	var spacing: float = path_len / float(dots.size())
	var phase_wrapped: float = fmod(phase, path_len)
	for i in range(dots.size()):
		var dot: Sprite2D = dots[i]
		var t: float = fmod(phase_wrapped + float(i) * spacing, path_len)
		dot.position = PathGeometry.point_along(path, t)
		dot.modulate = color
		dot.visible = true
	return true


## Renders `path` onto the persistent drag-overlay nodes: sets the line points +
## color, positions and tints the destination marker, and distributes the flow dots.
## On a degenerate path the line and marker stay visible while the dots are hidden
## (matching the original per-frame drag behaviour).
static func render(line: Line2D, dots: Array, dst_marker: Sprite2D,
		path: Array[Vector2], color: Color, phase: float) -> void:
	line.clear_points()
	for p: Vector2 in path:
		line.add_point(p)
	line.default_color = color
	line.visible = true

	var dot_color: Color = color
	dot_color.a = 1.0
	dst_marker.position = path[path.size() - 1]
	dst_marker.modulate = dot_color
	dst_marker.visible = true

	place_dots(dots, path, phase, dot_color)
