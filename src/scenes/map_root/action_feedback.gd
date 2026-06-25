class_name ActionFeedback
## Player manual-action feedback: queued / active / progress indicators on the
## harvested tile, plus loot spawning on completion.
##
## Driven by PlayerCharacter's action signals (a different input source than the
## mouse-driven DragController). Owns its own indicator state, but shares the
## transport list + pause coordination + badge spawning with DragController
## (held via `_drag`); scene refs (grid, terrain layer, add_child) via `_root`.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 5).

var _root: MapRoot
var _drag: DragController
var _badges: ResourceBadgeLayer

## Frozen at action-start; never overwritten by subsequent tile clicks.
var _active_action_tile: Vector2i = Vector2i(-1, -1)
## Yellow idle indicators for actions waiting in queue. Each entry: {tile, indicator}.
var _queued_indicators: Array[Dictionary] = []
## Green progress indicator shown at the harvested tile while an action runs.
var _action_indicator: BuildingStatusIndicator = null


func setup(root: MapRoot, drag: DragController, badges: ResourceBadgeLayer) -> void:
	_root = root
	_drag = drag
	_badges = badges


## True while a manual action's progress indicator is showing. DragController
## reads this for the shared transport/action pause coordination.
func is_action_running() -> bool:
	return _action_indicator != null


## Spawns a yellow idle indicator at tile for a queued action.
func _on_action_queued(_action_id: int, _position: int, tile: Vector2i) -> void:
	if tile == _active_action_tile:
		return
	var indicator := BuildingStatusIndicator.new()
	var tile_px: int = WorldGrid.TILE_SIZE
	indicator.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5 \
		+ Vector2(tile_px * 0.32, tile_px * 0.32)
	indicator.z_index = 3
	indicator.set_idle()
	_root.add_child(indicator)
	_queued_indicators.append({tile = tile, indicator = indicator})


## Unpauses the tick system and spawns a green progress circle at the harvested tile.
func _on_action_started(_action_id: int, _tick_cost: int, tile: Vector2i) -> void:
	_active_action_tile = tile
	for i in range(_queued_indicators.size() - 1, -1, -1):
		if _queued_indicators[i].tile == tile:
			(_queued_indicators[i].indicator as Node).queue_free()
			_queued_indicators.remove_at(i)
			break
	if _drag._pending_transports.is_empty() and _action_indicator == null:
		_drag._was_paused_before_action = TickSystem.is_paused()
	TickSystem.set_pause(false)
	_spawn_action_indicator(_active_action_tile)


func _spawn_action_indicator(tile: Vector2i) -> void:
	if _action_indicator != null:
		_action_indicator.queue_free()
		_action_indicator = null
	var tile_px: int = WorldGrid.TILE_SIZE
	var indicator := BuildingStatusIndicator.new()
	indicator.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5 \
		+ Vector2(tile_px * 0.32, tile_px * 0.32)
	indicator.z_index = 3
	_root.add_child(indicator)
	_action_indicator = indicator


## Clears all yellow queued indicators when the action queue is cancelled.
func _on_action_queue_cleared() -> void:
	for entry: Dictionary in _queued_indicators:
		(entry.indicator as Node).queue_free()
	_queued_indicators.clear()


func _on_action_progress_update(progress: float, _tick_cost: int, _output: int) -> void:
	if _action_indicator != null:
		_action_indicator.set_progress(progress)


## Spawns floating text and a loot-icon badge on the harvested tile.
## For CLEAR_* actions: removes terrain, clears all resource icons, then spawns loot.
func _on_action_completed(action_id: int, output: Array) -> void:
	if _drag._pending_transports.is_empty():
		TickSystem.set_pause(_drag._was_paused_before_action)
	if _action_indicator != null:
		_action_indicator.queue_free()
		_action_indicator = null
	if _active_action_tile == Vector2i(-1, -1):
		return

	var is_clear: bool = action_id in [
		PlayerCharacter.ManualActionType.CLEAR_TREE,
		PlayerCharacter.ManualActionType.CLEAR_STONE,
		PlayerCharacter.ManualActionType.CLEAR_BERRY,
		PlayerCharacter.ManualActionType.CLEAR_GRASS,
		PlayerCharacter.ManualActionType.CLEAR_WHEAT,
	]

	if is_clear:
		var tile := _active_action_tile
		var to_remove: Array = []
		for entry: Dictionary in _badges._resource_icons:
			if entry.tile == tile:
				(entry.node as Node2D).queue_free()
				to_remove.append(entry)
		for entry: Dictionary in to_remove:
			_badges._resource_icons.erase(entry)
		_root.grid.clear_terrain_tile(tile)
		_root.terrain_layer.set_cell(tile, -1, Vector2i(-1, -1))
		var world_pos: Vector2 = _root.grid.tile_to_world(tile)
		for item: Dictionary in output:
			var qty: int = item.get("quantity", 0)
			var resource_id: StringName = item.get("resource_id", &"")
			if qty <= 0 or resource_id == &"" or not ResourceRegistry.has_world_icon(resource_id):
				continue
			_badges._spawn_pickup_float(world_pos, "+%d %s" % [qty, str(resource_id)])
			var ids: Array[StringName] = []
			for _i in range(qty):
				_root.grid.add_resource_to_tile(tile, resource_id, true)
				ids.append(resource_id)
			_badges._spawn_badge(tile, ids, _root, 0.0, true, Time.get_ticks_msec())
		return

	var world_pos: Vector2 = _root.grid.tile_to_world(_active_action_tile)
	for item: Dictionary in output:
		var qty: int = item.get("quantity", 0)
		var resource_id: StringName = item.get("resource_id", &"")
		if qty <= 0 or resource_id == &"" or not ResourceRegistry.has_world_icon(resource_id):
			continue
		_badges._spawn_pickup_float(world_pos, "+%d %s" % [qty, str(resource_id)])
		var existing_count: int = _root.grid.get_resources(_active_action_tile).size()
		var ids: Array[StringName] = []
		for _i in range(qty):
			_root.grid.add_resource_to_tile(_active_action_tile, resource_id, true)
			ids.append(resource_id)
		var prev_len: int = _badges._resource_icons.size()
		_badges._spawn_badge(_active_action_tile, ids, _root, 0.0, true, Time.get_ticks_msec())
		for j in range(prev_len, _badges._resource_icons.size()):
			_badges._resource_icons[j].resource_idx = existing_count + (j - prev_len)


## Called when the building at the active action tile is demolished mid-action.
## Frees the progress indicator and restores tick-pause state.
func _on_action_interrupted(_tile: Vector2i) -> void:
	if _action_indicator != null:
		_action_indicator.queue_free()
		_action_indicator = null
	_active_action_tile = Vector2i(-1, -1)
	if _drag._pending_transports.is_empty():
		TickSystem.set_pause(_drag._was_paused_before_action)
