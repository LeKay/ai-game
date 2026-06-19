class_name NpcOverlay extends Node2D
## Displays NPC icons on the map while NPCs are physically travelling between tiles.
## Logistics carriers: driven by route.carrier_state + remaining_ticks (not npc.state,
## which is unreliable due to NPCSystem's internal travel timer conflict).
## Direct-assignment NPCs: driven by npc.state as normal.

# ---- Constants ---------------------------------------------------------------

const NPC_ICON_RADIUS: int = 9

# ---- Dependencies ------------------------------------------------------------

var _grid: Node = null

# ---- Internal state ----------------------------------------------------------

## npc_id → Node2D icon node
var _icon_map: Dictionary = {}
## npc_id → Vector2 smooth-movement target (lerped in _process)
var _icon_target: Dictionary = {}
## npc_id → int cached carrier_state for dirty-flag detection on logistics transitions
var _carrier_state_cache: Dictionary = {}
## npc_id → Vector2i tile where the carrier was when RETURN_HOME began
var _return_from_tile: Dictionary = {}

## Shared NPC silhouette texture — loaded from asset in _ready().
var _npc_texture: Texture2D = null

# ---- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	y_sort_enabled = true
	z_index = 3
	_npc_texture = load("res://assets/art/tiles/npc_icon_villager.png")
	TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	NPCSystem.npc_removed.connect(_on_npc_removed)
	NPCSystem.npc_leveled_up.connect(_on_npc_leveled_up)


## Sets the WorldGrid reference used to convert tile coords to world positions.
func init_dependencies(grid: Node) -> void:
	_grid = grid

# ---- Tick-driven sync --------------------------------------------------------

func _on_ticks_advanced(_delta: int) -> void:
	_sync_npc_icons()


## Smoothly moves each visible NPC icon toward its tick-set target position.
func _process(delta: float) -> void:
	for npc_id: StringName in _icon_map.keys():
		var icon: Node2D = _icon_map[npc_id]
		if not icon.visible:
			continue
		var target: Vector2 = _icon_target.get(npc_id, icon.position)
		icon.position = icon.position.lerp(target, clampf(delta * 8.0, 0.0, 1.0))


## Creates/updates/hides NPC icons each tick based on current NPC states.
func _sync_npc_icons() -> void:
	if _grid == null:
		return

	var active_ids: Dictionary = {}

	for npc in NPCSystem.all_npcs.values():
		var npc_id: StringName = npc.npc_id
		var state: int = npc.state
		# Shared-carrier model: follow the carrier's ONE currently-active route (the one it is
		# executing), not an arbitrary route — a carrier can be assigned to several routes.
		var route: LogisticsRoute = LogisticsSystem.get_active_route_for_npc(npc_id)

		# Logistics carriers: use route.carrier_state directly.
		# npc.state is unreliable for carriers — NPCSystem's internal travel timer
		# overrides it immediately because travel_ticks_total is never set for logistics.
		# Only show when remaining_ticks > 0 to avoid a 1-frame flash on journey end.
		# Direct-assignment NPCs: use npc.state as normal.
		var should_show: bool
		if route != null:
			should_show = route.remaining_ticks > 0 and (
				route.carrier_state == LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE
				or route.carrier_state == LogisticsRoute.CarrierState.RETURN_HOME
			)
		else:
			should_show = (state == NPCSystem.TaskState.TRAVEL_TO_BUILDING \
					or state == NPCSystem.TaskState.RETURN_TO_BASE)

		if not should_show:
			if _icon_map.has(npc_id):
				_icon_map[npc_id].visible = false
			_carrier_state_cache.erase(npc_id)
			_return_from_tile.erase(npc_id)
			continue

		active_ids[npc_id] = true

		# Dirty-flag: detect carrier state transitions to capture RETURN_HOME start tile.
		if route != null:
			var cached: int = _carrier_state_cache.get(npc_id, -1)
			if cached != route.carrier_state:
				if route.carrier_state == LogisticsRoute.CarrierState.RETURN_HOME:
					match cached:
						LogisticsRoute.CarrierState.AT_SOURCE, \
						LogisticsRoute.CarrierState.WAITING_SOURCE:
							_return_from_tile[npc_id] = BuildingRegistry.get_building_tile(
								str(route.source_building_id))
						_:
							# AT_DESTINATION, WAITING_DESTINATION, or unknown → default to dest
							_return_from_tile[npc_id] = BuildingRegistry.get_building_tile(
								str(route.destination_building_id))
				_carrier_state_cache[npc_id] = route.carrier_state

		var world_pos: Vector2 = _calc_world_pos(npc, route)

		var icon: Node2D = _icon_map.get(npc_id)
		if icon == null:
			icon = _make_npc_icon()
			icon.position = world_pos
			add_child(icon)
			_icon_map[npc_id] = icon
		elif not icon.visible:
			icon.position = world_pos

		_icon_target[npc_id] = world_pos
		icon.visible = true

	# Hide icons for NPCs that are no longer in a movement state.
	for npc_id: StringName in _icon_map.keys():
		if not active_ids.has(npc_id):
			_icon_map[npc_id].visible = false

# ---- Position calculation ----------------------------------------------------

## Returns the world-space position for an NPC currently in an active state.
## Logistics carriers follow current_leg_path when available; direct NPCs follow travel_path.
## Falls back to linear lerp when no path is stored.
func _calc_world_pos(npc: Variant, route: LogisticsRoute) -> Vector2:
	if route != null:
		match route.carrier_state:
			LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE:
				# F4: use the effective leg duration captured at leg start, so the icon's
				# speed matches the carrier's (efficiency-scaled) real travel time.
				var total: int = route.current_leg_total_ticks
				var elapsed: int = maxi(0, total - route.remaining_ticks)
				if route.current_leg_path.size() >= 2:
					return _follow_path(route.current_leg_path, total, elapsed)
				return _lerp_travel(
					route.npc_start_pos,
					BuildingRegistry.get_building_tile(str(route.source_building_id)),
					total,
					route.remaining_ticks
				)
			LogisticsRoute.CarrierState.RETURN_HOME:
				var from_tile: Vector2i = _return_from_tile.get(npc.npc_id,
					BuildingRegistry.get_building_tile(str(route.destination_building_id)))
				var total_r: int = route.current_leg_total_ticks
				var elapsed_r: int = maxi(0, total_r - route.remaining_ticks)
				if route.current_leg_path.size() >= 2:
					return _follow_path(route.current_leg_path, total_r, elapsed_r)
				return _lerp_travel(from_tile, route.npc_home_pos, total_r, route.remaining_ticks)

	# Direct NPC assignment — follow path if computed, otherwise linear lerp.
	if npc.travel_ticks_total <= 0:
		return _grid.tile_to_world(npc.travel_destination)
	var elapsed: int = npc.travel_progress
	var total: int = npc.travel_ticks_total
	if npc.travel_path.size() >= 2:
		return _follow_path(npc.travel_path, total, elapsed)
	var progress: float = clampf(float(elapsed) / float(total), 0.0, 1.0)
	return _grid.tile_to_world(npc.position).lerp(
		_grid.tile_to_world(npc.travel_destination), progress)


## Interpolates along a tile path, distributing total travel time equally across segments.
func _follow_path(path: Array[Vector2i], total_ticks: int, elapsed_ticks: int) -> Vector2:
	var num_segs: int = path.size() - 1
	if num_segs <= 0:
		return _grid.tile_to_world(path[0])
	# Weight each segment by the movement cost of the tile being left, so the icon slows on
	# high-cost tiles (TREE/STONE = 4, EMPTY = 1, road = 0.5) — matching the carrier's cargo-leg
	# animation and the cost-weighted travel time. (Was: equal time per segment = constant speed.)
	var weights: Array[float] = []
	var total_w: float = 0.0
	for i in range(num_segs):
		var w: float = _safe_tile_cost(path[i])
		weights.append(w)
		total_w += w
	var t: float = clampf(float(elapsed_ticks) / float(maxi(total_ticks, 1)), 0.0, 1.0)
	if total_w <= 0.0:
		var seg_t: float = t * float(num_segs)
		var seg_idx: int = clampi(int(seg_t), 0, num_segs - 1)
		return _grid.tile_to_world(path[seg_idx]).lerp(
			_grid.tile_to_world(path[seg_idx + 1]), seg_t - float(seg_idx))
	var target: float = t * total_w
	var acc: float = 0.0
	for i in range(num_segs):
		if target < acc + weights[i]:
			var frac: float = (target - acc) / weights[i] if weights[i] > 0.0 else 1.0
			return _grid.tile_to_world(path[i]).lerp(
				_grid.tile_to_world(path[i + 1]), clampf(frac, 0.0, 1.0))
		acc += weights[i]
	return _grid.tile_to_world(path[num_segs])


## Movement cost of a tile for animation weighting; INF / non-positive (buildings, OOB) → 1.0.
func _safe_tile_cost(tile: Vector2i) -> float:
	if _grid == null:
		return 1.0
	var c: float = _grid.get_tile_movement_cost(tile)
	if c == INF or c <= 0.0:
		return 1.0
	return c


## Linear interpolation from from_tile to to_tile using remaining_ticks and the effective
## leg duration (total_ticks already includes F4 efficiency scaling).
func _lerp_travel(from_tile: Vector2i, to_tile: Vector2i,
		total_ticks: int, remaining_ticks: int) -> Vector2:
	if total_ticks <= 0:
		return _grid.tile_to_world(to_tile)
	var elapsed: int = maxi(0, total_ticks - remaining_ticks)
	var progress: float = clampf(float(elapsed) / float(total_ticks), 0.0, 1.0)
	return _grid.tile_to_world(from_tile).lerp(_grid.tile_to_world(to_tile), progress)

# ---- Cleanup -----------------------------------------------------------------

## Spawns a short "Level Up!" float over the NPC when it gains a level (Experience System).
func _on_npc_leveled_up(npc_id: StringName, new_level: int) -> void:
	if _grid == null:
		return
	var pos: Vector2
	var icon: Node2D = _icon_map.get(npc_id)
	if icon != null and icon.visible:
		pos = icon.position
	else:
		pos = _grid.tile_to_world(NPCSystem.get_npc_position(npc_id))

	var lbl := Label.new()
	lbl.text = "Level Up!  Lv %d" % new_level
	lbl.z_index = 10
	lbl.position = pos + Vector2(-32.0, -28.0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color("#E8C860"))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	add_child(lbl)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(lbl, "position:y", lbl.position.y - 30.0, 1.4)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.4)
	tween.chain().tween_callback(lbl.queue_free)


func _on_npc_removed(npc_id: StringName) -> void:
	var icon: Node2D = _icon_map.get(npc_id)
	if icon != null:
		icon.queue_free()
		_icon_map.erase(npc_id)
	_icon_target.erase(npc_id)
	_carrier_state_cache.erase(npc_id)
	_return_from_tile.erase(npc_id)

# ---- Icon construction -------------------------------------------------------

## Builds the Node2D icon node: dark backdrop circle + NPC silhouette sprite.
func _make_npc_icon() -> Node2D:
	var container := Node2D.new()
	container.z_index = 5

	var backdrop := Sprite2D.new()
	backdrop.texture = TextureFactory.circle(NPC_ICON_RADIUS, Color(0.0, 0.0, 0.0, 0.50))
	container.add_child(backdrop)

	var spr := Sprite2D.new()
	spr.texture = _npc_texture
	var tex_size: Vector2 = _npc_texture.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		var target: float = float(NPC_ICON_RADIUS) * 1.5
		spr.scale = Vector2(target / tex_size.x, target / tex_size.y)
	container.add_child(spr)

	return container

