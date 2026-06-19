class_name DragController extends Node2D
## World drag-and-drop interaction controller — being extracted from MapRoot
## incrementally (Phase 5, step 3d, leaf-first).
##
## Holds a back-reference to MapRoot for the shared scene state (grid, player,
## registry, overlays) that the not-yet-migrated drag logic still needs. As more
## of the interaction core moves here, the `_root.` accesses shrink and MapRoot
## becomes a thin coordinator.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 5, 3d).

var _root: MapRoot
## Player manual-action feedback (separate component). Shares state both ways:
## ActionFeedback reads _pending_transports/_was_paused/_badges._resource_icons here;
## DragController reads _action.is_action_running() for pause coordination.
var _action: ActionFeedback
## World resource-icon data + display (spawn / float / hit-test / pickup floats).
var _badges: ResourceBadgeLayer

# ── Drag / interaction state (owned here; MapRoot holds only the scene refs) ───


## World-drag state — set while the player holds LMB on a resource icon.
var _drag_icon: Node2D = null
var _drag_icon_entry: Dictionary = {}
var _drag_src_tile: Vector2i = Vector2i(-1, -1)
var _drag_collected_count: int = 1      ## total items in the current drag batch
var _drag_hold_timer: float = 0.0       ## LMB hold time during an active world drag
var _drag_path_phase: float = 0.0

## Persistent drag visual overlays (created in _setup_drag_overlays).
var _drag_cost_label: Label = null
var _drag_energy_label: Label = null
var _drag_path_line: Line2D = null
var _drag_path_dots: Array = []
var _drag_path_dst_marker: Sprite2D = null
var _drag_count_label: Label = null     ## "×N" badge shown near the cursor when batch > 1

## Building-panel drag state — set while dragging out of a container / input / output buffer.
var _drag_from_container_id: StringName = &""
var _drag_resource_id: StringName = &""
var _drag_from_building_tile: Vector2i = Vector2i(-1, -1)
var _drag_from_input_building_id: String = ""
var _drag_from_output_building_id: String = ""

## Pending manual transports (in transit after a drag commit) + pause coordination.
var _pending_transports: Array = []
var _was_paused_before_action: bool = false

const _HOLD_COLLECT_DELAY: float = 0.5         ## hold time before first batch collect
const _HOLD_COLLECT_BASE_INTERVAL: float = 0.35 ## interval after first collect
const _HOLD_COLLECT_DECAY: float = 0.85         ## interval multiplier per item collected
const _HOLD_COLLECT_MIN_INTERVAL: float = 0.05  ## fastest possible interval (floor)


## Injects the owning MapRoot. Call right after instancing, before use.
func setup(root: MapRoot) -> void:
	_root = root


## Injects the ActionFeedback sibling (wired after both exist).
func set_action(action: ActionFeedback) -> void:
	_action = action


## Injects the ResourceBadgeLayer sibling.
func set_badges(badges: ResourceBadgeLayer) -> void:
	_badges = badges


# ── Building-panel drag cost ──────────────────────────────────────────────────

## Returns the tick duration for a building-panel drag from from_tile to to_tile.
## Does NOT advance ticks (caller starts the pending transport).
func _calc_drag_ticks(from_tile: Vector2i, to_tile: Vector2i, _res_id: StringName) -> int:
	var dist: int = abs(to_tile.x - from_tile.x) + abs(to_tile.y - from_tile.y)
	var base_cost: int = maxi(1, dist)
	return base_cost * 5


# ── Drag-icon snap-back / reset ───────────────────────────────────────────────

## Tweens the dragged icon back to its origin and restores any batch extras.
func _snap_back_drag_icon() -> void:
	if _drag_icon == null:
		return
	_restore_batch_extras()
	var icon_node: Node2D = _drag_icon
	var tween := create_tween()
	tween.tween_property(icon_node, "position", _drag_icon_entry.base_pos, 0.18).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void: _reset_drag_icon_visuals(icon_node))


## Resets a dragged icon's visuals (opacity / scale / z-index) to the resting state.
func _reset_drag_icon_visuals(icon_node: Node2D) -> void:
	icon_node.modulate.a = 1.0
	icon_node.scale = Vector2(1.0, 1.0)
	icon_node.z_index = 2


# ── Drag overlays (per-frame) ─────────────────────────────────────────────────

## Updates cost label + path line overlay each frame during an active world drag.
func _update_drag_overlays() -> void:
	if _drag_icon == null:
		_drag_cost_label.visible = false
		_drag_energy_label.visible = false
		_drag_count_label.visible = false
		_drag_path_line.visible = false
		_drag_path_dst_marker.visible = false
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	if _drag_from_container_id != &"" or _drag_from_input_building_id != "" or _drag_from_output_building_id != "":
		_update_storage_drag_overlays()
		return

	var cursor_world: Vector2 = get_global_mouse_position()
	var hovered_tile: Vector2i = _root.grid.world_to_tile(cursor_world)
	var preview: Dictionary = _root._player.get_relocation_preview(hovered_tile)
	_drag_cost_label.text = "⏱️%d" % (preview.tick_cost * _drag_collected_count)
	_drag_cost_label.position = cursor_world + Vector2(16.0, -32.0)
	_drag_cost_label.visible = true

	_drag_energy_label.visible = false

	if not _root.grid.is_in_bounds(hovered_tile) or _drag_src_tile == Vector2i(-1, -1):
		_drag_path_line.visible = false
		_drag_path_dst_marker.visible = false
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	var passable: bool = _root.grid.is_passable(hovered_tile)
	var valid: bool = passable
	var path_color: Color = PathDotOverlay.COLOR_VALID if valid else PathDotOverlay.COLOR_INVALID
	var tile_px: float = float(WorldGrid.TILE_SIZE)
	var half: float = tile_px * 0.5
	var src_center: Vector2 = Vector2(_drag_src_tile) * tile_px + Vector2(half, half)
	var dst_center: Vector2 = Vector2(hovered_tile) * tile_px + Vector2(half, half)
	var path := PathDotOverlay.l_path(src_center, dst_center)
	PathDotOverlay.render(_drag_path_line, _drag_path_dots, _drag_path_dst_marker,
		path, path_color, _drag_path_phase)


func _update_storage_drag_overlays() -> void:
	var cursor_world: Vector2 = get_global_mouse_position()
	var hovered_tile: Vector2i = _root.grid.world_to_tile(cursor_world)

	# ── Cost labels ──────────────────────────────────────────────────────────
	var dist: int = (abs(hovered_tile.x - _drag_from_building_tile.x)
		+ abs(hovered_tile.y - _drag_from_building_tile.y))
	var base_cost: int = maxi(1, dist)
	var tick_cost: int = base_cost * 5

	_drag_cost_label.text = "⏱️%d" % tick_cost
	_drag_cost_label.position = cursor_world + Vector2(16.0, -32.0)
	_drag_cost_label.visible = true

	_drag_energy_label.visible = false

	# ── Path line + dots ─────────────────────────────────────────────────────
	if not _root.grid.is_in_bounds(hovered_tile) or _drag_from_building_tile == Vector2i(-1, -1):
		_drag_path_line.visible = false
		_drag_path_dst_marker.visible = false
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	var building_on_tile: String = _root.grid.get_building(hovered_tile)
	var valid: bool
	if building_on_tile != "":
		var inst: BuildingRegistry.BuildingInstance = _root._registry.get_building_instance(building_on_tile)
		if inst != null and inst.assigned_container_id != &"":
			valid = inst.assigned_container_id != _drag_from_container_id
		else:
			var allowed: Array[StringName] = BuildingRegistry.get_active_input_resource_ids(
				building_on_tile if inst != null else "")
			valid = _drag_resource_id in allowed
	else:
		valid = _root.grid.is_passable(hovered_tile)

	var path_color: Color = PathDotOverlay.COLOR_VALID if valid else PathDotOverlay.COLOR_INVALID
	var tile_px: float = float(WorldGrid.TILE_SIZE)
	var half: float = tile_px * 0.5
	var src_center: Vector2 = Vector2(_drag_from_building_tile) * tile_px + Vector2(half, half)
	var dst_center: Vector2 = Vector2(hovered_tile) * tile_px + Vector2(half, half)
	var path := PathDotOverlay.l_path(src_center, dst_center)
	PathDotOverlay.render(_drag_path_line, _drag_path_dots, _drag_path_dst_marker,
		path, path_color, _drag_path_phase)


# ── Batch collect / restore ───────────────────────────────────────────────────

## During a world drag, auto-collects one more matching resource from the source tile.
func _try_batch_collect() -> void:
	if _drag_icon == null or _drag_src_tile == Vector2i(-1, -1):
		return
	var res_id: StringName = _drag_icon_entry.resource_id
	var src_tile: Vector2i = _drag_src_tile
	var target_entry: Dictionary = {}
	for entry: Dictionary in _badges._resource_icons:
		if entry.get("node") == _drag_icon_entry.get("node"):
			continue  # skip the icon currently being dragged
		if entry.tile != src_tile:
			continue
		if entry.resource_id != res_id:
			continue
		if entry.get("in_transit", false):
			continue
		target_entry = entry
		break
	if target_entry.is_empty():
		return
	var icon_node: Node2D = target_entry.node as Node2D
	var res_idx: int = target_entry.resource_idx
	_root.grid.remove_one_resource(src_tile, res_idx)
	for other: Dictionary in _badges._resource_icons:
		if other.tile == src_tile and other.resource_idx > res_idx:
			other.resource_idx -= 1
	target_entry.in_transit = true
	var cursor_pos: Vector2 = _drag_icon.global_position
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(icon_node, "global_position", cursor_pos, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(icon_node, "modulate:a", 0.0, 0.18)
	tween.tween_property(icon_node, "scale", Vector2(0.4, 0.4), 0.22)
	var cap_entry: Dictionary = target_entry
	var cap_node: Node2D = icon_node
	tween.chain().tween_callback(func() -> void:
		_badges._resource_icons.erase(cap_entry)
		cap_node.queue_free()
	)
	_drag_collected_count += 1
	_drag_count_label.text = "×%d" % _drag_collected_count
	_drag_count_label.visible = true


## Pulls one more matching resource from the source container into the current drag batch.
func _try_batch_collect_from_container() -> void:
	if _drag_icon == null or _drag_from_container_id == &"":
		return
	if InventorySystem.try_consume(_drag_from_container_id, _drag_resource_id, 1) != InventoryContainer.ConsumeResult.SUCCESS:
		return
	_drag_collected_count += 1
	_drag_count_label.text = "×%d" % _drag_collected_count
	_drag_count_label.visible = true


## Pulls one more matching resource from the output buffer into the current drag batch.
func _try_batch_collect_from_output() -> void:
	if _drag_icon == null or _drag_from_output_building_id == "":
		return
	if not _root._registry.remove_from_output(_drag_from_output_building_id, _drag_resource_id, 1):
		return
	_drag_collected_count += 1
	_drag_count_label.text = "×%d" % _drag_collected_count
	_drag_count_label.visible = true


## Pulls one more matching resource from the input buffer into the current drag batch.
func _try_batch_collect_from_input() -> void:
	if _drag_icon == null or _drag_from_input_building_id == "":
		return
	if not _root._registry.remove_from_input(_drag_from_input_building_id, _drag_resource_id, 1):
		return
	_drag_collected_count += 1
	_drag_count_label.text = "×%d" % _drag_collected_count
	_drag_count_label.visible = true


## Restores any batch-collected extras to the source tile when a drag is cancelled.
## Resets batch state. Called from _snap_back_drag_icon before the snap animation.
func _restore_batch_extras() -> void:
	var extra_count: int = _drag_collected_count - 1
	_drag_collected_count = 1
	_drag_hold_timer = 0.0
	if extra_count <= 0 or _drag_src_tile == Vector2i(-1, -1) or _drag_icon_entry.is_empty():
		return
	var res_id: StringName = _drag_icon_entry.resource_id
	for i in range(extra_count):
		if _root.grid.add_resource_to_tile(_drag_src_tile, res_id, true):
			var ids_r: Array[StringName] = [res_id]
			_badges._spawn_badge(_drag_src_tile, ids_r, _root, 0.0, true, Time.get_ticks_msec() + i * 37)
			_badges._resource_icons.back().resource_idx = _root.grid.get_resources(_drag_src_tile).size() - 1


# ── Drag start (building panels) ──────────────────────────────────────────────

func _on_storage_drag_started(resource_id: StringName, container_id: StringName, building_tile: Vector2i) -> void:
	if InventorySystem.try_consume(container_id, resource_id, 1) != InventoryContainer.ConsumeResult.SUCCESS:
		return
	var icon_node := ResourceBadgeFactory.build_icon_node(resource_id, ResourceBadgeFactory.icon_px_for_count(1))
	icon_node.z_index = 20
	icon_node.modulate.a = 0.85
	icon_node.position = get_global_mouse_position()
	_root.add_child(icon_node)
	_drag_icon = icon_node
	_drag_icon_entry = {}
	_drag_from_container_id = container_id
	_drag_resource_id = resource_id
	_drag_from_building_tile = building_tile
	_drag_src_tile = Vector2i(-1, -1)
	_drag_path_phase = 0.0
	_drag_hold_timer = 0.0
	_drag_collected_count = 1


func _on_input_drag_started(resource_id: StringName, building_id: String, building_tile: Vector2i) -> void:
	if not _root._registry.remove_from_input(building_id, resource_id, 1):
		return
	var icon_node := ResourceBadgeFactory.build_icon_node(resource_id, ResourceBadgeFactory.icon_px_for_count(1))
	icon_node.z_index = 20
	icon_node.modulate.a = 0.85
	icon_node.position = get_global_mouse_position()
	_root.add_child(icon_node)
	_drag_icon = icon_node
	_drag_icon_entry = {}
	_drag_from_container_id = &""
	_drag_resource_id = resource_id
	_drag_from_building_tile = building_tile
	_drag_from_input_building_id = building_id
	_drag_src_tile = Vector2i(-1, -1)
	_drag_path_phase = 0.0
	_drag_hold_timer = 0.0
	_drag_collected_count = 1


func _on_output_drag_started(resource_id: StringName, building_id: String, building_tile: Vector2i) -> void:
	if not _root._registry.remove_from_output(building_id, resource_id, 1):
		return
	var icon_node := ResourceBadgeFactory.build_icon_node(resource_id, ResourceBadgeFactory.icon_px_for_count(1))
	icon_node.z_index = 20
	icon_node.modulate.a = 0.85
	icon_node.position = get_global_mouse_position()
	_root.add_child(icon_node)
	_drag_icon = icon_node
	_drag_icon_entry = {}
	_drag_from_container_id = &""
	_drag_resource_id = resource_id
	_drag_from_building_tile = building_tile
	_drag_from_output_building_id = building_id
	_drag_src_tile = Vector2i(-1, -1)
	_drag_path_phase = 0.0
	_drag_hold_timer = 0.0
	_drag_collected_count = 1


# ── Drag finish (LMB release) ─────────────────────────────────────────────────

func _finish_output_drag() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = _root.grid.world_to_tile(world_pos)
	var res_id: StringName = _drag_resource_id
	var building_id: String = _drag_from_output_building_id
	var from_tile: Vector2i = _drag_from_building_tile
	var icon_node: Node2D = _drag_icon
	var batch_count: int = _drag_collected_count
	_drag_icon = null
	_drag_from_output_building_id = ""
	_drag_resource_id = &""
	_drag_from_building_tile = Vector2i(-1, -1)
	_drag_src_tile = Vector2i(-1, -1)
	_drag_collected_count = 1
	_drag_hold_timer = 0.0
	_drag_count_label.visible = false
	if _root.grid.is_in_bounds(target_tile):
		var target_building_id: String = _root.grid.get_building(target_tile)
		if target_building_id != "":
			var inst: BuildingRegistry.BuildingInstance = _root._registry.get_building_instance(target_building_id)
			if inst != null and inst.assigned_container_id != &"":
				if InventorySystem.get_occupied_slots(inst.assigned_container_id) < InventorySystem.get_capacity(inst.assigned_container_id):
					var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
					var target_cid: StringName = inst.assigned_container_id
					_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
						if InventorySystem.try_deposit(target_cid, res_id, batch_count) != InventoryContainer.DepositResult.SUCCESS:
							_root._registry.receive_output_to_buffer(building_id, res_id, batch_count)
						icon_node.queue_free()
					)
					get_viewport().set_input_as_handled()
					return
			elif inst != null and inst.assigned_container_id == &"":
				var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
				_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
					var deposited: int = 0
					for _i: int in range(batch_count):
						if _root._registry.receive_input_from_world(target_building_id, res_id, 1):
							deposited += 1
						else:
							break
					if deposited < batch_count:
						_root._registry.receive_output_to_buffer(building_id, res_id, batch_count - deposited)
					icon_node.queue_free()
				)
				get_viewport().set_input_as_handled()
				return
		elif _root.grid.is_passable(target_tile):
			var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
			_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
				var deposited: int = 0
				for _i: int in range(batch_count):
					if _root.grid.add_resource_to_tile(target_tile, res_id, true):
						deposited += 1
					else:
						break
				if deposited > 0:
					var ids: Array[StringName] = []
					for _j: int in range(deposited):
						ids.append(res_id)
					_badges._spawn_badge(target_tile, ids, _root, 0.0, true, Time.get_ticks_msec())
				if deposited < batch_count:
					_root._registry.receive_output_to_buffer(building_id, res_id, batch_count - deposited)
				icon_node.queue_free()
			)
			get_viewport().set_input_as_handled()
			return
	icon_node.queue_free()
	_root._registry.receive_output_to_buffer(building_id, res_id, batch_count)
	get_viewport().set_input_as_handled()


func _finish_input_drag() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = _root.grid.world_to_tile(world_pos)
	var res_id: StringName = _drag_resource_id
	var building_id: String = _drag_from_input_building_id
	var from_tile: Vector2i = _drag_from_building_tile
	var icon_node: Node2D = _drag_icon
	var batch_count: int = _drag_collected_count
	_drag_icon = null
	_drag_from_input_building_id = ""
	_drag_resource_id = &""
	_drag_from_building_tile = Vector2i(-1, -1)
	_drag_src_tile = Vector2i(-1, -1)
	_drag_collected_count = 1
	_drag_hold_timer = 0.0
	_drag_count_label.visible = false
	if _root.grid.is_in_bounds(target_tile) and _root.grid.is_passable(target_tile):
		var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
		_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
			var deposited: int = 0
			for _i: int in range(batch_count):
				if _root.grid.add_resource_to_tile(target_tile, res_id, true):
					deposited += 1
				else:
					break
			if deposited > 0:
				var ids: Array[StringName] = []
				for _j: int in range(deposited):
					ids.append(res_id)
				_badges._spawn_badge(target_tile, ids, _root, 0.0, true, Time.get_ticks_msec())
			if deposited < batch_count:
				_root._registry.receive_input_from_world(building_id, res_id, batch_count - deposited)
			icon_node.queue_free()
		)
	else:
		icon_node.queue_free()
		_root._registry.receive_input_from_world(building_id, res_id, batch_count)
	get_viewport().set_input_as_handled()


func _finish_storage_drag() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = _root.grid.world_to_tile(world_pos)
	var res_id: StringName = _drag_resource_id
	var container_id: StringName = _drag_from_container_id
	var from_tile: Vector2i = _drag_from_building_tile
	var icon_node: Node2D = _drag_icon
	var batch_count: int = _drag_collected_count
	_drag_icon = null
	_drag_from_container_id = &""
	_drag_resource_id = &""
	_drag_from_building_tile = Vector2i(-1, -1)
	_drag_src_tile = Vector2i(-1, -1)
	_drag_collected_count = 1
	_drag_hold_timer = 0.0
	_drag_count_label.visible = false

	if _root.grid.is_in_bounds(target_tile):
		var building_id: String = _root.grid.get_building(target_tile)
		if building_id != "":
			var inst: BuildingRegistry.BuildingInstance = _root._registry.get_building_instance(building_id)
			var target_cid: StringName = inst.assigned_container_id if inst != null else &""
			if target_cid != &"" and target_cid != container_id \
					and InventorySystem.get_occupied_slots(target_cid) < InventorySystem.get_capacity(target_cid):
				var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
				_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
					if InventorySystem.try_deposit(target_cid, res_id, batch_count) != InventoryContainer.DepositResult.SUCCESS:
						InventorySystem.try_deposit(container_id, res_id, batch_count)
					icon_node.queue_free()
				)
				get_viewport().set_input_as_handled()
				return
			elif target_cid == &"":
				var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
				_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
					var deposited: int = 0
					for _i: int in range(batch_count):
						if _root._registry.receive_input_from_world(building_id, res_id, 1):
							deposited += 1
						else:
							break
					if deposited < batch_count:
						InventorySystem.try_deposit(container_id, res_id, batch_count - deposited)
					icon_node.queue_free()
				)
				get_viewport().set_input_as_handled()
				return
		elif _root.grid.is_passable(target_tile):
			var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
			_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
				var deposited: int = 0
				for _i: int in range(batch_count):
					if _root.grid.add_resource_to_tile(target_tile, res_id, true):
						deposited += 1
					else:
						break
				if deposited > 0:
					var ids: Array[StringName] = []
					for _j: int in range(deposited):
						ids.append(res_id)
					_badges._spawn_badge(target_tile, ids, _root, 0.0, true, Time.get_ticks_msec())
				if deposited < batch_count:
					InventorySystem.try_deposit(container_id, res_id, batch_count - deposited)
				icon_node.queue_free()
			)
			get_viewport().set_input_as_handled()
			return

	icon_node.queue_free()
	InventorySystem.try_deposit(container_id, res_id, batch_count)
	get_viewport().set_input_as_handled()


## Parks a building-panel drag icon at the target tile and registers a pending transport.
## The icon stays with a progress circle until ticks_needed elapse, then on_complete runs.
func _park_panel_icon_pending(icon: Node2D, from_tile: Vector2i, target_tile: Vector2i,
		ticks_needed: int, on_complete: Callable) -> void:
	var tile_px: int = WorldGrid.TILE_SIZE
	icon.position = Vector2(target_tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	icon.modulate.a = 1.0
	icon.scale = Vector2(1.0, 1.0)
	icon.z_index = 2
	var indicator: BuildingStatusIndicator = TransportOverlay.spawn_indicator(_root, target_tile)
	var path_overlay: Dictionary = TransportOverlay.spawn_path_overlay(_root, from_tile, target_tile)
	if _pending_transports.is_empty() and not _action.is_action_running():
		_was_paused_before_action = TickSystem.is_paused()
	_pending_transports.append({
		"icon": icon, "icon_entry": {}, "source_tile": from_tile,
		"target_tile": target_tile,
		"ticks_total": ticks_needed, "ticks_elapsed": 0,
		"indicator": indicator,
		"path_overlay": path_overlay, "path_phase": 0.0,
		"on_complete": on_complete,
	})
	TickSystem.set_pause(false)


# ── World-drag deposit into a building ────────────────────────────────────────

## Attempts to deposit the currently world-dragged resource (and any batch extras)
## into a building, as a pending transport. Snaps back on an invalid target.
func _try_deposit_to_building(target_tile: Vector2i, building_id: String) -> void:
	var instance: Object = _root._registry.get_building_instance(building_id)
	var container_id: StringName = instance.assigned_container_id if instance != null else &""
	var src_tile: Vector2i = _drag_icon_entry.tile
	var src_idx: int = _drag_icon_entry.resource_idx
	var res_id: StringName = _drag_icon_entry.resource_id
	var dist: int = abs(target_tile.x - src_tile.x) + abs(target_tile.y - src_tile.y)
	var cost: int = maxi(1, dist)

	if container_id == &"":
		# Production building — route to input_buffer.
		var allowed: Array[StringName] = BuildingRegistry.get_active_input_resource_ids(
			instance.building_id if instance != null else "")
		if not res_id in allowed:
			_root._player.cancel_relocation()
			_snap_back_drag_icon()
			_drag_icon = null
			_drag_icon_entry = {}
			_drag_src_tile = Vector2i(-1, -1)
			return
		var cp_total: int = _drag_collected_count
		_drag_collected_count = 1
		if _pending_transports.is_empty() and not _action.is_action_running():
			_was_paused_before_action = TickSystem.is_paused()
		_root.grid.remove_one_resource(src_tile, src_idx)
		for entry: Dictionary in _badges._resource_icons:
			if entry.tile == src_tile and entry.resource_idx > src_idx:
				entry.resource_idx -= 1
		_drag_icon_entry.in_transit = true
		_drag_icon.position = _drag_icon_entry.base_pos
		_reset_drag_icon_visuals(_drag_icon)
		var indicator_prod: BuildingStatusIndicator = TransportOverlay.spawn_indicator(_root, src_tile)
		var path_overlay_prod: Dictionary = TransportOverlay.spawn_path_overlay(_root, src_tile, target_tile)
		var cp_icon: Node2D = _drag_icon
		var cp_entry: Dictionary = _drag_icon_entry
		var cp_bid: String = building_id
		var cp_res: StringName = res_id
		_pending_transports.append({
			"icon": cp_icon, "icon_entry": cp_entry, "source_tile": src_tile,
			"target_tile": target_tile,
			"ticks_total": cost * 5,
			"ticks_elapsed": 0, "indicator": indicator_prod,
			"path_overlay": path_overlay_prod, "path_phase": 0.0,
			"on_complete": func() -> void:
				_root._registry.receive_input_from_world(cp_bid, cp_res, cp_total)
				_badges._resource_icons.erase(cp_entry)
				cp_icon.queue_free()
		})
		_root._player.cancel_relocation()
		_drag_icon = null
		_drag_icon_entry = {}
		_drag_src_tile = Vector2i(-1, -1)
		TickSystem.set_pause(false)
		return

	# Pre-check: container must have space for at least 1 item.
	if InventorySystem.get_occupied_slots(container_id) >= InventorySystem.get_capacity(container_id):
		_snap_back_drag_icon()
		_root._player.cancel_relocation()
		_drag_icon = null
		_drag_icon_entry = {}
		_drag_src_tile = Vector2i(-1, -1)
		return

	var cs_total: int = _drag_collected_count
	_drag_collected_count = 1
	if _pending_transports.is_empty() and not _action.is_action_running():
		_was_paused_before_action = TickSystem.is_paused()
	_root.grid.remove_one_resource(src_tile, src_idx)
	for entry: Dictionary in _badges._resource_icons:
		if entry.tile == src_tile and entry.resource_idx > src_idx:
			entry.resource_idx -= 1
	_drag_icon_entry.in_transit = true
	_drag_icon.position = _drag_icon_entry.base_pos
	_reset_drag_icon_visuals(_drag_icon)
	var indicator_stor: BuildingStatusIndicator = TransportOverlay.spawn_indicator(_root, src_tile)
	var path_overlay_stor: Dictionary = TransportOverlay.spawn_path_overlay(_root, src_tile, target_tile)
	var cs_icon: Node2D = _drag_icon
	var cs_entry: Dictionary = _drag_icon_entry
	var cs_cid: StringName = container_id
	var cs_res: StringName = res_id
	var cs_src: Vector2i = src_tile
	_pending_transports.append({
		"icon": cs_icon, "icon_entry": cs_entry, "source_tile": src_tile,
		"target_tile": target_tile,
		"ticks_total": cost * 5,
		"ticks_elapsed": 0, "indicator": indicator_stor,
		"path_overlay": path_overlay_stor, "path_phase": 0.0,
		"on_complete": func() -> void:
			for _di in range(cs_total):
				var dep: int = InventorySystem.try_deposit(cs_cid, cs_res, 1)
				if dep != InventoryContainer.DepositResult.SUCCESS:
					# Container full during transit — put excess back on world grid.
					if _root.grid.add_resource_to_tile(cs_src, cs_res, true):
						var ids_fb: Array[StringName] = [cs_res]
						_badges._spawn_badge(cs_src, ids_fb, _root, 0.0, true, Time.get_ticks_msec() + _di * 37)
						_badges._resource_icons.back().resource_idx = _root.grid.get_resources(cs_src).size() - 1
			_badges._resource_icons.erase(cs_entry)
			cs_icon.queue_free()
	})
	_root._player.cancel_relocation()
	_drag_icon = null
	_drag_icon_entry = {}
	_drag_src_tile = Vector2i(-1, -1)
	TickSystem.set_pause(false)


# ── Pending transport lifecycle ───────────────────────────────────────────────

## Advances all pending manual transports and completes any that have finished.
func _advance_pending_transports(delta: int) -> void:
	if _pending_transports.is_empty():
		return
	var completed: Array = []
	for pt: Dictionary in _pending_transports:
		pt.ticks_elapsed += delta
		var progress: float = minf(float(pt.ticks_elapsed) / float(pt.ticks_total), 1.0)
		if is_instance_valid(pt.indicator):
			pt.indicator.set_progress(progress)
		if pt.ticks_elapsed >= pt.ticks_total:
			completed.append(pt)
	for pt: Dictionary in completed:
		_pending_transports.erase(pt)
		if is_instance_valid(pt.indicator):
			pt.indicator.queue_free()
		TransportOverlay.free_overlay(pt.get("path_overlay", {}))
		var icon_entry: Dictionary = pt.get("icon_entry", {})
		if not icon_entry.is_empty() and pt.has("target_tile"):
			# World drag: tween icon from source to destination, then commit.
			var icon: Node2D = pt.icon
			var tile_px: int = WorldGrid.TILE_SIZE
			var to_tile: Vector2i = pt.target_tile
			var new_pos: Vector2 = Vector2(to_tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
			var tween: Tween = create_tween()
			tween.tween_property(icon, "position", new_pos, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_callback(pt.on_complete)
		else:
			pt.on_complete.call()
	if _pending_transports.is_empty() and not _action.is_action_running():
		TickSystem.set_pause(_was_paused_before_action)


# ── Drag overlay setup + resource badges ──────────────────────────────────────

## Creates the persistent cost/energy/count labels and path-line overlay nodes.
func _setup_drag_overlays() -> void:
	_drag_cost_label = Label.new()
	_drag_cost_label.visible = false
	_drag_cost_label.z_index = 20
	_drag_cost_label.add_theme_font_size_override("font_size", 16)
	_drag_cost_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	_drag_cost_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_drag_cost_label.add_theme_constant_override("outline_size", 3)
	_root.add_child(_drag_cost_label)

	_drag_energy_label = Label.new()
	_drag_energy_label.visible = false
	_drag_energy_label.z_index = 20
	_drag_energy_label.add_theme_font_size_override("font_size", 16)
	_drag_energy_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_drag_energy_label.add_theme_constant_override("outline_size", 3)
	_root.add_child(_drag_energy_label)

	_drag_path_line = Line2D.new()
	_drag_path_line.width = PathDotOverlay.LINE_WIDTH
	_drag_path_line.default_color = PathDotOverlay.COLOR_VALID
	_drag_path_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_drag_path_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_drag_path_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_drag_path_line.visible = false
	_drag_path_line.z_index = 5
	_root.add_child(_drag_path_line)

	var dot_tex := TextureFactory.circle(PathDotOverlay.DOT_RADIUS, Color.WHITE)
	for _i in range(PathDotOverlay.DOT_COUNT):
		var dot := Sprite2D.new()
		dot.texture = dot_tex
		dot.visible = false
		dot.z_index = 6
		_root.add_child(dot)
		_drag_path_dots.append(dot)

	_drag_path_dst_marker = Sprite2D.new()
	_drag_path_dst_marker.texture = TextureFactory.circle(PathDotOverlay.DST_MARKER_RADIUS, Color.WHITE)
	_drag_path_dst_marker.visible = false
	_drag_path_dst_marker.z_index = 6
	_root.add_child(_drag_path_dst_marker)

	_drag_count_label = Label.new()
	_drag_count_label.visible = false
	_drag_count_label.z_index = 22
	_drag_count_label.add_theme_font_size_override("font_size", 15)
	_drag_count_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	_drag_count_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_drag_count_label.add_theme_constant_override("outline_size", 4)
	_root.add_child(_drag_count_label)


# ── Input (LMB release during a building-panel drag) ──────────────────────────

## Catches LMB release during a building-panel drag regardless of UI layering.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _drag_from_output_building_id != "":
		_finish_output_drag()
	elif _drag_from_input_building_id != "":
		_finish_input_drag()
	elif _drag_from_container_id != &"":
		_finish_storage_drag()


# ── Per-frame drag / badge / transport animation ──────────────────────────────

func _process(delta: float) -> void:
	_badges.animate_float(_drag_icon)

	if (_drag_from_container_id != &"" or _drag_from_input_building_id != "" or _drag_from_output_building_id != "") and _drag_icon != null:
		_drag_icon.global_position = get_global_mouse_position()

	if _drag_icon != null:
		_drag_path_phase += delta * PathDotOverlay.DOT_SPEED
		if (_drag_from_container_id == &"" and _drag_from_input_building_id == ""
				and _drag_from_output_building_id == ""):
			var cursor_tile: Vector2i = _root.grid.world_to_tile(get_global_mouse_position())
			if cursor_tile == _drag_src_tile:
				_drag_hold_timer += delta
				var _hold_threshold: float = (
					_HOLD_COLLECT_DELAY if _drag_collected_count == 1
					else maxf(_HOLD_COLLECT_MIN_INTERVAL,
						_HOLD_COLLECT_BASE_INTERVAL * pow(_HOLD_COLLECT_DECAY, _drag_collected_count - 1))
				)
				if _drag_hold_timer >= _hold_threshold:
					_drag_hold_timer -= _hold_threshold
					_try_batch_collect()
			else:
				_drag_hold_timer = 0.0
		elif _drag_from_container_id != &"" or _drag_from_output_building_id != "" or _drag_from_input_building_id != "":
			_drag_hold_timer += delta
			var _hold_threshold: float = (
				_HOLD_COLLECT_DELAY if _drag_collected_count == 1
				else maxf(_HOLD_COLLECT_MIN_INTERVAL,
					_HOLD_COLLECT_BASE_INTERVAL * pow(_HOLD_COLLECT_DECAY, _drag_collected_count - 1))
			)
			if _drag_hold_timer >= _hold_threshold:
				_drag_hold_timer -= _hold_threshold
				if _drag_from_container_id != &"":
					_try_batch_collect_from_container()
				elif _drag_from_output_building_id != "":
					_try_batch_collect_from_output()
				else:
					_try_batch_collect_from_input()
		if _drag_count_label.visible:
			_drag_count_label.position = get_global_mouse_position() + Vector2(18.0, 10.0)
	_update_drag_overlays()

	for pt: Dictionary in _pending_transports:
		pt.path_phase += delta * PathDotOverlay.DOT_SPEED
		TransportOverlay.animate(pt)


# ── Mouse input (world tile interaction + resource drag) ──────────────────────

## Handles mouse input for right-click tile interaction and LMB resource drag.
## Consumes the event so UI layers above are not re-notified.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton

	# ── Right-click: tile interaction panel ──────────────────────────────────
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var world_pos: Vector2 = get_global_mouse_position()
		var tile: Vector2i = _root.grid.world_to_tile(world_pos)
		if tile.x < 0 or tile.y < 0 or tile.x >= WorldGrid.GRID_SIZE or tile.y >= WorldGrid.GRID_SIZE:
			return
		_root._on_tile_clicked(tile, get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
		return

	# ── LMB press: begin resource relocation drag or open building detail ────
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		var world_pos: Vector2 = get_global_mouse_position()

		# In map-select mode all other clicks are blocked; route to HUD.
		if _root._hud != null and _root._hud.is_map_select_active():
			var sel_tile: Vector2i = _root.grid.world_to_tile(world_pos)
			var sel_building: String = ""
			if sel_tile.x >= 0 and sel_tile.y >= 0 and sel_tile.x < WorldGrid.GRID_SIZE and sel_tile.y < WorldGrid.GRID_SIZE:
				sel_building = _root.grid.get_building(sel_tile)
			_root._hud.notify_building_selected_in_map_select(StringName(sel_building))
			get_viewport().set_input_as_handled()
			return

		var hit := _badges._hit_test_resource_icon(world_pos)
		if hit.is_empty():
			# No resource icon hit — check if tile has a building.
			var click_tile: Vector2i = _root.grid.world_to_tile(world_pos)
			if (click_tile.x >= 0 and click_tile.y >= 0
					and click_tile.x < WorldGrid.GRID_SIZE and click_tile.y < WorldGrid.GRID_SIZE):
				var building_id: String = _root.grid.get_building(click_tile)
				if building_id != "":
					if _root._hud != null:
						_root._hud.open_building_detail(building_id)
						get_viewport().set_input_as_handled()
						return
			return
		var icon_node: Node2D = hit.node as Node2D
		var res_tile: Vector2i = hit.tile
		var res_idx: int = hit.resource_idx
		var res_id: StringName = hit.resource_id
		if not _root._player.try_start_relocation(res_tile, res_idx, res_id):
			return
		_drag_icon = icon_node
		_drag_icon_entry = hit
		_drag_src_tile = res_tile
		_drag_path_phase = 0.0
		_drag_hold_timer = 0.0
		_drag_collected_count = 1
		icon_node.modulate.a = 0.7
		icon_node.scale = Vector2(1.2, 1.2)
		icon_node.z_index = 10
		get_viewport().set_input_as_handled()
		return

	# ── LMB release: commit or cancel drag ───────────────────────────────────
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		if _drag_icon == null:
			return
		var world_pos: Vector2 = get_global_mouse_position()
		var target_tile: Vector2i = _root.grid.world_to_tile(world_pos)

		# If the target tile has a storage building, deposit instead of relocate.
		var building_id: String = _root.grid.get_building(target_tile)
		if building_id != "":
			_try_deposit_to_building(target_tile, building_id)
			get_viewport().set_input_as_handled()
			return

		var result: int = _root._player.try_commit_relocation(target_tile, _root.grid, true)
		match result:
			PlayerCharacter.RelocationResult.SUCCESS:
				var src_tile: Vector2i = _drag_icon_entry.tile
				var src_idx: int = _drag_icon_entry.resource_idx
				var move_dist: int = abs(target_tile.x - src_tile.x) + abs(target_tile.y - src_tile.y)
				var ticks_needed: int = maxi(1, move_dist) * 5
				# Remove resource from grid immediately so it is in transit.
				_root.grid.remove_one_resource(src_tile, src_idx)
				for entry: Dictionary in _badges._resource_icons:
					if entry.tile == src_tile and entry.resource_idx > src_idx:
						entry.resource_idx -= 1
				# Park icon at source; mark in-transit so it cannot be re-dragged.
				_drag_icon_entry.in_transit = true
				_drag_icon.position = _drag_icon_entry.base_pos
				_reset_drag_icon_visuals(_drag_icon)
				var indicator: BuildingStatusIndicator = TransportOverlay.spawn_indicator(_root, src_tile)
				var path_overlay: Dictionary = TransportOverlay.spawn_path_overlay(_root, src_tile, target_tile)
				var c_icon: Node2D = _drag_icon
				var c_entry: Dictionary = _drag_icon_entry
				var c_src_tile: Vector2i = src_tile
				var c_target_tile: Vector2i = target_tile
				var c_res_id: StringName = _drag_icon_entry.resource_id
				var c_tile_px: int = WorldGrid.TILE_SIZE
				# All batch extras are transported (no energy gate).
				var c_total_items: int = _drag_collected_count
				if _pending_transports.is_empty() and not _action.is_action_running():
					_was_paused_before_action = TickSystem.is_paused()
				_pending_transports.append({
					"icon": c_icon,
					"icon_entry": c_entry,
					"source_tile": src_tile,
					"target_tile": c_target_tile,
					"ticks_total": ticks_needed * c_total_items,
					"ticks_elapsed": 0,
					"indicator": indicator,
					"path_overlay": path_overlay,
					"path_phase": 0.0,
					"on_complete": func() -> void:
						var size_before: int = _root.grid.get_resources(c_target_tile).size()
						var placed_count: int = 0
						for _pi in range(c_total_items):
							if _root.grid.add_resource_to_tile(c_target_tile, c_res_id, true):
								placed_count += 1
							else:
								break
						var new_base: Vector2 = (Vector2(c_target_tile) * float(c_tile_px)
							+ Vector2(c_tile_px, c_tile_px) * 0.5)
						# First item — update the dragged icon entry.
						if placed_count >= 1:
							c_entry.tile = c_target_tile
							c_entry.resource_idx = size_before
							var c_scatter: Array = ResourceBadgeFactory.icon_positions(c_target_tile, 1,
								roundi(float(c_tile_px) * ResourceBadgeFactory.ICON_SCALE_BY_COUNT[0]),
								Time.get_ticks_msec())
							c_entry.base_pos = new_base + c_scatter[0]
							c_icon.position = c_entry.base_pos
							c_entry.in_transit = false
						else:
							if _root.grid.add_resource_to_tile(c_src_tile, c_res_id, true):
								c_entry.tile = c_src_tile
								c_entry.resource_idx = _root.grid.get_resources(c_src_tile).size() - 1
								c_entry.in_transit = false
							else:
								_badges._resource_icons.erase(c_entry)
								c_icon.queue_free()
						# Extra items that reached target — spawn new badges.
						for pi in range(1, placed_count):
							var ids_e: Array[StringName] = [c_res_id]
							_badges._spawn_badge(c_target_tile, ids_e, _root, 0.0, false,
								Time.get_ticks_msec() + pi * 31)
							_badges._resource_icons.back().resource_idx = size_before + pi
						# Extra items that couldn't be placed — restore to source.
						var failed_extras: int = c_total_items - maxi(placed_count, 1)
						var seed_off: int = Time.get_ticks_msec()
						for ri in range(failed_extras):
							if _root.grid.add_resource_to_tile(c_src_tile, c_res_id, true):
								var ids_r: Array[StringName] = [c_res_id]
								_badges._spawn_badge(c_src_tile, ids_r, _root, 0.0, true, seed_off + ri * 41)
								_badges._resource_icons.back().resource_idx = _root.grid.get_resources(c_src_tile).size() - 1
				})
				TickSystem.set_pause(false)
			PlayerCharacter.RelocationResult.SNAP_BACK_SAME_TILE:
				_snap_back_drag_icon()
			_:
				# All SNAP_BACK_* and NOT_DRAGGING cases.
				_snap_back_drag_icon()
		_drag_icon = null
		_drag_icon_entry = {}
		_drag_src_tile = Vector2i(-1, -1)
		get_viewport().set_input_as_handled()
