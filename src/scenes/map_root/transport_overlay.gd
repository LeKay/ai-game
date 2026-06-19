class_name TransportOverlay
## Builders + animator for the visual nodes of a pending manual transport: the
## progress indicator at the source tile and the dotted path line to the target.
##
## Extracted from MapRoot (Phase 5). Pure rendering: nodes are added to a `parent`
## the caller supplies; MapRoot keeps the transport lifecycle (`_pending_transports`,
## completion callbacks and pause coordination), which is entangled with the manual-
## action indicator. Shares the dotted-line style with PathDotOverlay.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 5).


## Spawns a progress circle indicator at the given tile, parented to `parent`.
static func spawn_indicator(parent: Node, tile: Vector2i) -> BuildingStatusIndicator:
	var tile_px: int = WorldGrid.TILE_SIZE
	var indicator := BuildingStatusIndicator.new()
	indicator.position = (Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
		+ Vector2(tile_px * 0.32, tile_px * 0.32))
	indicator.z_index = 15
	parent.add_child(indicator)
	indicator.set_progress(0.0)
	return indicator


## Spawns a persistent path line + flow dots + destination marker, parented to
## `parent`. Returns {line, dots, dst_marker, path_points, path_len}.
static func spawn_path_overlay(parent: Node, from_tile: Vector2i, to_tile: Vector2i) -> Dictionary:
	var tile_px: float = float(WorldGrid.TILE_SIZE)
	var half: float = tile_px * 0.5
	var src_center: Vector2 = Vector2(from_tile) * tile_px + Vector2(half, half)
	var dst_center: Vector2 = Vector2(to_tile) * tile_px + Vector2(half, half)
	var path := PathDotOverlay.l_path(src_center, dst_center)
	var path_len: float = PathGeometry.length(path)
	var line := Line2D.new()
	line.width = PathDotOverlay.LINE_WIDTH
	line.default_color = PathDotOverlay.COLOR_VALID
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 5
	parent.add_child(line)
	for pt: Vector2 in path:
		line.add_point(pt)
	var dots: Array = []
	for _i in range(PathDotOverlay.DOT_COUNT):
		var dot := Sprite2D.new()
		dot.texture = TextureFactory.circle(PathDotOverlay.DOT_RADIUS, Color.WHITE)
		dot.modulate = PathDotOverlay.COLOR_VALID
		dot.z_index = 6
		parent.add_child(dot)
		dots.append(dot)
	var dst_marker := Sprite2D.new()
	dst_marker.texture = TextureFactory.circle(PathDotOverlay.DST_MARKER_RADIUS, Color.WHITE)
	dst_marker.modulate = PathDotOverlay.COLOR_VALID
	dst_marker.position = dst_center
	dst_marker.z_index = 6
	parent.add_child(dst_marker)
	return {
		"line": line, "dots": dots, "dst_marker": dst_marker,
		"path_points": path, "path_len": path_len,
	}


## Updates the flow-dot positions for an active transport (reads pt.path_phase).
static func animate(pt: Dictionary) -> void:
	var overlay: Dictionary = pt.get("path_overlay", {})
	if overlay.is_empty():
		return
	PathDotOverlay.place_dots(overlay.dots, overlay.path_points, pt.path_phase, PathDotOverlay.COLOR_VALID)


## Frees all nodes belonging to a transport path overlay.
static func free_overlay(overlay: Dictionary) -> void:
	if overlay.is_empty():
		return
	if is_instance_valid(overlay.get("line")):
		overlay.line.queue_free()
	for dot in overlay.get("dots", []):
		if is_instance_valid(dot):
			dot.queue_free()
	if is_instance_valid(overlay.get("dst_marker")):
		overlay.dst_marker.queue_free()
