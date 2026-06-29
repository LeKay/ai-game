class_name ResourceBadgeLayer extends Node2D
## Owns the world resource-icon data (`_resource_icons`) and its display: initial
## spawn, per-badge construction, the idle float animation, hit-testing and the
## "+N" pickup floats.
##
## Extracted from DragController (Phase 5 follow-up split). DragController and
## ActionFeedback mutate `_resource_icons` and call the spawn/hit-test helpers via
## a reference (one-directional: they depend on this layer, not vice versa).
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 5).

var _root: MapRoot
## Persistent parent for all auto-spawned badges (initial map load + later reconciliation
## via terrain_changed). Drag-spawned badges still parent to _root with their own animation.
var _badge_container: Node2D = null

## One entry per spawned resource icon: {node, tile, resource_idx, resource_id, base_pos, phase}.
var _resource_icons: Array = []


func setup(root: MapRoot) -> void:
	_root = root


## Spawns individual icon nodes for every resource instance at map load. Also subscribes
## to grid.terrain_changed so that resources added later (rescue cargo dumps, future
## auto-drops) get a badge without the caller having to call _spawn_badge manually.
func _spawn_resource_badges() -> void:
	_badge_container = Node2D.new()
	_badge_container.name = "ResourceBadges"
	_badge_container.z_index = 1
	_root.add_child(_badge_container)
	for x in range(WorldGrid.GRID_SIZE):
		for y in range(WorldGrid.GRID_SIZE):
			var tile := Vector2i(x, y)
			var resources: Array = _root.grid.get_resources(tile)
			if resources.is_empty():
				continue
			var ids: Array[StringName] = []
			for rd: WorldGrid.ResourceTileData in resources:
				ids.append(rd.resource_id)
			_spawn_badge(tile, ids, _badge_container)
	if _root.grid != null and not _root.grid.terrain_changed.is_connected(_on_terrain_changed):
		_root.grid.terrain_changed.connect(_on_terrain_changed)


## Schedules a reconciliation pass for `tile`. Deferred so manual _spawn_badge calls from
## the drag controller (which run after add_resource_to_tile in the same frame) finish
## first; otherwise we'd double-spawn for drag-dropped items.
func _on_terrain_changed(tile: Vector2i, layer: int) -> void:
	if layer != WorldGrid.RESOURCE_LAYER or _badge_container == null:
		return
	_reconcile_tile.call_deferred(tile)


## Adds badges for resources present in the grid but not yet visualised (e.g. items dumped
## by the logistics rescue). Doesn't remove badges — the drag controller owns the remove
## path with its own animations.
func _reconcile_tile(tile: Vector2i) -> void:
	if _badge_container == null or _root == null or _root.grid == null:
		return
	var resources: Array = _root.grid.get_resources(tile)
	# Count displayed badges per resource_id on this tile (in-transit drag icons excluded —
	# they aren't backed by grid state until they land).
	var displayed_counts: Dictionary = {}
	for entry: Dictionary in _resource_icons:
		if entry.tile != tile or entry.get("in_transit", false):
			continue
		var rid: StringName = entry.resource_id
		displayed_counts[rid] = displayed_counts.get(rid, 0) + 1
	# Count grid truth per resource_id.
	var grid_counts: Dictionary = {}
	for rd: WorldGrid.ResourceTileData in resources:
		grid_counts[rd.resource_id] = grid_counts.get(rd.resource_id, 0) + 1
	# Spawn badges for the surplus (grid > displayed).
	var to_spawn: Array[StringName] = []
	for rid: StringName in grid_counts:
		var diff: int = grid_counts[rid] - displayed_counts.get(rid, 0)
		for _i in range(diff):
			to_spawn.append(rid)
	if not to_spawn.is_empty():
		_spawn_badge(tile, to_spawn, _badge_container, 0.0, true, Time.get_ticks_msec())


## Unified badge builder: one independent Node2D per resource instance, parented to
## `parent`. icon_scale_override > 0 bypasses the per-count scale; pos_seed_offset
## varies positions so repeated spawns on the same tile don't overlap.
func _spawn_badge(tile: Vector2i, resource_ids: Array[StringName], parent: Node2D,
		icon_scale_override: float = 0.0, pop_in: bool = false, pos_seed_offset: int = 0) -> void:
	var tile_px: int = WorldGrid.TILE_SIZE
	var base_pos: Vector2 = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	var count: int = resource_ids.size()
	var scale_factor: float = icon_scale_override if icon_scale_override > 0.0 else ResourceBadgeFactory.ICON_SCALE_BY_COUNT[mini(count - 1, ResourceBadgeFactory.ICON_SCALE_BY_COUNT.size() - 1)]
	var icon_px: int = roundi(tile_px * scale_factor)
	var positions: Array = ResourceBadgeFactory.icon_positions(tile, count, icon_px, pos_seed_offset)
	var phase: float = fmod(base_pos.x * 7.0 + base_pos.y * 13.0, TAU)

	for i in range(count):
		var icon_pos: Vector2 = base_pos + positions[i]
		var icon_node := ResourceBadgeFactory.build_icon_node(resource_ids[i], icon_px)
		icon_node.position = icon_pos
		if pop_in:
			icon_node.scale = Vector2.ZERO
		icon_node.z_index = 2
		parent.add_child(icon_node)
		_resource_icons.append({
			"node": icon_node,
			"tile": tile,
			"resource_idx": i,
			"resource_id": resource_ids[i],
			"base_pos": icon_pos,
			"phase": phase,
		})

		if pop_in:
			var tween := create_tween()
			tween.tween_property(icon_node, "scale", Vector2(1.3, 1.3), 0.12).set_trans(Tween.TRANS_BACK)
			tween.tween_property(icon_node, "scale", Vector2(1.0, 1.0), 0.08)


## Idle bob animation for all icons; the dragged icon (if any) follows the cursor.
func animate_float(dragged_icon: Node2D) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for entry: Dictionary in _resource_icons:
		if entry.get("in_transit", false):
			continue
		var icon_node: Node2D = entry.node as Node2D
		if dragged_icon != null and icon_node == dragged_icon:
			icon_node.global_position = get_global_mouse_position()
			continue
		icon_node.position.y = entry.base_pos.y + sin(t * TAU / 2.5 + entry.phase) * 4.0


## Hit-tests the world resource icons against a world position. Returns the icon
## entry dict (node/tile/resource_idx/resource_id) or empty if none within tap radius.
func _hit_test_resource_icon(world_pos: Vector2) -> Dictionary:
	var tile_pos: Vector2i = _root.grid.world_to_tile(world_pos)
	var tap_radius: float = WorldGrid.TILE_SIZE * 0.5
	var best_dist: float = tap_radius
	var best: Dictionary = {}
	for entry: Dictionary in _resource_icons:
		if entry.tile != tile_pos:
			continue
		if entry.get("in_transit", false):
			continue
		var icon_node: Node2D = entry.node as Node2D
		var dist: float = icon_node.global_position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = entry
	return best


## Spawns a floating "+N resource" label that drifts up and fades out.
func _spawn_pickup_float(world_pos: Vector2, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = world_pos + Vector2(-32.0, -48.0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.94, 0.93, 0.9, 1))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 52.0, 1.4)
	tween.tween_property(label, "modulate:a", 0.0, 1.4)
	tween.finished.connect(label.queue_free)
