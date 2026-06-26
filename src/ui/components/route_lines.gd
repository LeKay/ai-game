class_name RouteLines extends Node2D
## Renders active logistics routes as Line2D overlays in world space.
## Node2D in world tree (NOT CanvasLayer) — pans and zooms with the camera.
## ADR-0011: Route Visualization section.
## Story: logistics-system/story-006-route-visualization

# ---- Constants ---------------------------------------------------------------

const COLOR_ACTIVE:   Color = Color(0.298, 0.686, 0.314)  ## green  #4CAF50 — NPC actively running this route
const COLOR_QUEUED:   Color = Color(0.259, 0.522, 0.957)  ## blue   #4285F5 — route active but NPC serving another route
const COLOR_TRANSIT:  Color = Color(1.0,   0.757, 0.027)  ## yellow #FFC107 — NPC idle, waiting for resources at source
const COLOR_FULL:     Color = Color(0.957, 0.263, 0.212)  ## red    #F44336 — NPC holding cargo, destination storage full
const COLOR_INACTIVE: Color = Color(0.533, 0.533, 0.533)  ## gray   #888888 — route paused or deactivated

const OPACITY_ACTIVE:   float = 0.75
const OPACITY_HOVER:    float = 0.92
const OPACITY_INACTIVE: float = 0.28

const LINE_BASE_WIDTH:  float = 3.0
## World-space pixel radius for hover hit detection.
const HOVER_THRESHOLD:  float = 12.0
## Pixel radius of the circular carrier icon backdrop.
const ICON_RADIUS:      int   = 9

## Flow dot animation — matches the manual drag-path style from MapRoot.
const FLOW_DOT_COUNT: int   = 4
const FLOW_DOT_SPEED: float = 40.0
const FLOW_DOT_RADIUS: int  = 2


# ---- Dependencies ------------------------------------------------------------

var _grid: Node = null

# ---- Internal state ----------------------------------------------------------

## route_id → Line2D node
var _line_map: Dictionary = {}
## route_id → last observed carrier_state (dirty-flag)
var _state_cache: Dictionary = {}
## route_id → last observed active flag (dirty-flag)
var _active_cache: Dictionary = {}
## route_id → last observed "is this route the carrier's currently executing route" (dirty-flag)
var _carrier_active_cache: Dictionary = {}
## route_id → last observed carrier_state of the NPC's active route (dirty-flag for sibling routes)
var _carrier_active_state_cache: Dictionary = {}

## route_id → Node2D carrier icon node
var _icon_map: Dictionary = {}
## route_id → StringName of the resource the icon sprite was built for
var _icon_resource: Dictionary = {}
## route_id → Vector2 smooth-movement target (lerped in _process)
var _icon_target: Dictionary = {}

## route_id → Array[Sprite2D] flow dots (directional transport animation)
var _dot_map: Dictionary = {}
## route_id → float pixel offset along path (advances each frame)
var _dot_phase: Dictionary = {}
## route_id → float +1.0 = src→dst, -1.0 = dst→src
var _dot_direction: Dictionary = {}
## Shared dot texture (white circle, created once in _ready).
var _dot_texture: ImageTexture = null

var _hovered_id: StringName = &""

# ---- Visibility filter -------------------------------------------------------

## When false, routes are hidden unless a building or NPC filter is active.
var _global_show: bool = false
var _filter_building_id: StringName = &""
var _filter_npc_id: StringName = &""

var _tooltip_layer: CanvasLayer = null
var _tooltip_panel: PanelContainer = null
var _tooltip_label: Label = null

# ---- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	y_sort_enabled = true
	z_index = 3
	_dot_texture = TextureFactory.circle(FLOW_DOT_RADIUS, Color.WHITE)
	_build_tooltip()
	if TickSystem:
		TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	LogisticsSystem.route_created.connect(_on_route_changed)
	LogisticsSystem.route_deleted.connect(_on_route_changed)
	call_deferred(&"_sync_routes")


## Sets the WorldGrid reference used to convert tile coords to world positions.
func init_dependencies(grid: Node) -> void:
	_grid = grid


# ---- Visibility API ----------------------------------------------------------

## Toggles the global route overlay. When true all routes are shown regardless of filters.
func set_global_show(v: bool) -> void:
	_global_show = v
	_apply_visibility_all()


## Highlights routes where building_id is source or destination. Pass &"" to clear.
func set_building_filter(id: StringName) -> void:
	_filter_building_id = id
	_apply_visibility_all()


## Highlights routes assigned to npc_id. Pass &"" to clear.
func set_npc_filter(id: StringName) -> void:
	_filter_npc_id = id
	_apply_visibility_all()


func _is_route_visible(route: LogisticsRoute) -> bool:
	if _global_show:
		return true
	if _filter_building_id != &"" and (
			route.source_building_id == _filter_building_id
			or route.destination_building_id == _filter_building_id):
		return true
	if _filter_npc_id != &"" and route.npc_id == _filter_npc_id:
		return true
	return false


func _apply_visibility_all() -> void:
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		var show: bool = _is_route_visible(route)
		var line: Line2D = _line_map.get(route.id)
		if line != null:
			line.visible = show
		# Flow dots follow the line; cargo icons stay visible regardless (like NPC sprites).
		if not show:
			for dot: Sprite2D in _dot_map.get(route.id, []):
				dot.visible = false


# ---- Tick-driven sync --------------------------------------------------------

func _on_ticks_advanced(_delta: int) -> void:
	_sync_routes()


func _on_route_changed(_ignored: Variant = null) -> void:
	_sync_routes()


## Adds/removes Line2D nodes to match active routes and redraws only dirty lines.
func _sync_routes() -> void:
	var routes: Array = LogisticsSystem.get_active_routes()

	var current_ids: Dictionary = {}
	for route: LogisticsRoute in routes:
		current_ids[route.id] = true

	for rid: StringName in _line_map.keys():
		if not current_ids.has(rid):
			_line_map[rid].queue_free()
			_line_map.erase(rid)
			_state_cache.erase(rid)
			_active_cache.erase(rid)
			_carrier_active_cache.erase(rid)
			_carrier_active_state_cache.erase(rid)
			if _icon_map.has(rid):
				_icon_map[rid].queue_free()
				_icon_map.erase(rid)
				_icon_resource.erase(rid)
				_icon_target.erase(rid)
			if _dot_map.has(rid):
				for dot: Sprite2D in _dot_map[rid]:
					dot.queue_free()
				_dot_map.erase(rid)
				_dot_phase.erase(rid)
				_dot_direction.erase(rid)

	for route: LogisticsRoute in routes:
		if not _line_map.has(route.id):
			var line := Line2D.new()
			line.width = LINE_BASE_WIDTH
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			add_child(line)
			_line_map[route.id] = line

			var dots: Array[Sprite2D] = []
			for _i in range(FLOW_DOT_COUNT):
				var dot := Sprite2D.new()
				dot.texture = _dot_texture
				dot.z_index = 4
				dot.visible = false
				add_child(dot)
				dots.append(dot)
			_dot_map[route.id] = dots
			_dot_phase[route.id] = 0.0
			_dot_direction[route.id] = 1.0

		var cached_state: int = _state_cache.get(route.id, -1)
		var cached_active: bool = _active_cache.get(route.id, not route.active)
		var active_route: LogisticsRoute = LogisticsSystem.get_active_route_for_npc(route.npc_id)
		var is_carrier_active: bool = active_route != null and active_route.id == route.id
		var cached_carrier_active: bool = _carrier_active_cache.get(route.id, not is_carrier_active)
		# Track the carrier's active route state so sibling routes redraw when carrier goes
		# IDLE↔working — that transition changes blue (queued) to yellow (no resources) or back.
		var carrier_active_state: int = active_route.carrier_state if active_route != null else -1
		var cached_carrier_active_state: int = _carrier_active_state_cache.get(route.id, -2)
		if cached_state != route.carrier_state or cached_active != route.active \
				or cached_carrier_active != is_carrier_active \
				or cached_carrier_active_state != carrier_active_state:
			_redraw_line(route)
			_state_cache[route.id] = route.carrier_state
			_active_cache[route.id] = route.active
			_carrier_active_cache[route.id] = is_carrier_active
			_carrier_active_state_cache[route.id] = carrier_active_state

		_dot_direction[route.id] = 1.0

		_update_carrier_icon(route)

	_apply_visibility_all()


## Redraws geometry and appearance for one route's Line2D. Called only when dirty.
func _redraw_line(route: LogisticsRoute) -> void:
	var line: Line2D = _line_map.get(route.id)
	if line == null or _grid == null:
		return

	var src_tile: Vector2i = _get_building_tile(route.source_building_id)
	var dst_tile: Vector2i = _get_building_tile(route.destination_building_id)
	if src_tile == Vector2i(-1, -1) or dst_tile == Vector2i(-1, -1):
		return

	var path: Array[Vector2] = _route_world_path(route, src_tile, dst_tile)
	var trimmed: Array[Vector2] = _trim_path_endpoints(path, WorldGrid.TILE_SIZE * 0.5)

	line.clear_points()
	for pt: Vector2 in trimmed:
		line.add_point(pt)

	line.default_color = _route_color(route)
	line.modulate = Color(1, 1, 1, OPACITY_INACTIVE if not route.active else OPACITY_ACTIVE)
	line.width = LINE_BASE_WIDTH


## Returns the display color for a route based on carrier status.
## Green  = NPC actively running this route (traveling, loading, depositing).
## Blue   = route active but NPC is currently serving another route (queued in round-robin).
## Yellow = NPC idle on this route — waiting for resources to appear at source.
## Red    = NPC holding cargo but destination storage is full (WAITING_DESTINATION).
## Gray   = route is paused or deactivated.
func _route_color(route: LogisticsRoute) -> Color:
	if not route.active:
		return COLOR_INACTIVE
	if route.carrier_state == LogisticsRoute.CarrierState.WAITING_DESTINATION:
		return COLOR_FULL
	var active_route: LogisticsRoute = LogisticsSystem.get_active_route_for_npc(route.npc_id)
	var is_carrier_active: bool = active_route != null and active_route.id == route.id
	if not is_carrier_active:
		# Blue only when the carrier is actively running a different route.
		# If the carrier itself is IDLE (no work on any route), show yellow — same as the keep route.
		var carrier_idle: bool = active_route == null \
			or active_route.carrier_state == LogisticsRoute.CarrierState.IDLE
		return COLOR_TRANSIT if carrier_idle else COLOR_QUEUED
	if route.carrier_state == LogisticsRoute.CarrierState.IDLE:
		return COLOR_TRANSIT
	return COLOR_ACTIVE

# ---- Hover detection ---------------------------------------------------------

## Uses _unhandled_input so that mouse-motion events consumed by UI Controls
## (e.g. DraggableWindow panels) do not trigger route hover while the window
## is open. Hover clearing is handled by _validate_hover() in _process so the
## state is cleaned up even when events stop arriving.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return

	var world_pos: Vector2 = get_global_mouse_position()
	var new_hover: StringName = &""

	for rid: StringName in _line_map.keys():
		var line: Line2D = _line_map[rid]
		if line.get_point_count() < 2:
			continue
		if not line.visible:
			continue
		var hit := false
		for j in range(line.get_point_count() - 1):
			var a: Vector2 = line.get_point_position(j)
			var b: Vector2 = line.get_point_position(j + 1)
			if _dist_to_segment(world_pos, a, b) <= HOVER_THRESHOLD:
				hit = true
				break
		if hit:
			new_hover = rid
			break

	if new_hover == _hovered_id:
		if _hovered_id != &"" and _tooltip_panel != null and _tooltip_panel.visible:
			_tooltip_panel.position = get_viewport().get_mouse_position() + Vector2(16, -80)
		return

	if _hovered_id != &"":
		_apply_hover(_hovered_id, false)

	_hovered_id = new_hover

	if _hovered_id != &"":
		_apply_hover(_hovered_id, true)
		_show_tooltip(_hovered_id)
	else:
		_hide_tooltip()


## Clears the active hover when the mouse has moved away from the hovered route
## — including cases where _unhandled_input stops firing because a UI panel is
## consuming the event.
func _validate_hover() -> void:
	if _hovered_id == &"":
		return
	var line: Line2D = _line_map.get(_hovered_id)
	if line == null or not line.visible:
		_apply_hover(_hovered_id, false)
		_hovered_id = &""
		_hide_tooltip()
		return
	var world_pos: Vector2 = get_global_mouse_position()
	for j in range(line.get_point_count() - 1):
		var a: Vector2 = line.get_point_position(j)
		var b: Vector2 = line.get_point_position(j + 1)
		if _dist_to_segment(world_pos, a, b) <= HOVER_THRESHOLD:
			return
	_apply_hover(_hovered_id, false)
	_hovered_id = &""
	_hide_tooltip()


## Sets or clears the hover highlight on a route line.
func _apply_hover(route_id: StringName, hovered: bool) -> void:
	var line: Line2D = _line_map.get(route_id)
	if line == null:
		return
	var cached_active: bool = _active_cache.get(route_id, true)
	var base_opacity: float = OPACITY_ACTIVE if cached_active else OPACITY_INACTIVE
	line.modulate = Color(1, 1, 1, OPACITY_HOVER if hovered else base_opacity)

# ---- Tooltip -----------------------------------------------------------------

func _show_tooltip(route_id: StringName) -> void:
	if _tooltip_panel == null:
		return
	var route: LogisticsRoute = _find_route(route_id)
	if route == null:
		return

	var npc_name: String = str(route.npc_id)
	var src_tile: Vector2i = _get_building_tile(route.source_building_id)
	var dst_tile: Vector2i = _get_building_tile(route.destination_building_id)
	var distance: int = 0
	if src_tile != Vector2i(-1, -1) and dst_tile != Vector2i(-1, -1):
		distance = absi(dst_tile.x - src_tile.x) + absi(dst_tile.y - src_tile.y)
	var round_trip: int = int(floor(float(distance * 2) * LogisticsSystem.TICKS_PER_TILE))
	var efficiency: float = LogisticsSystem.get_route_efficiency(route)

	_tooltip_label.text = "NPC: %s\nDistance: %d tiles\nRound-trip: %d ticks\nEfficiency: %.0f%%" \
		% [npc_name, distance, round_trip, efficiency * 100.0]

	_tooltip_panel.position = get_viewport().get_mouse_position() + Vector2(16, -80)
	_tooltip_panel.visible = true


func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false


func _build_tooltip() -> void:
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 10
	_tooltip_layer.name = "RouteTooltipLayer"
	add_child(_tooltip_layer)

	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_layer.add_child(_tooltip_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_tooltip_panel.add_child(margin)

	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip_label.add_theme_color_override("font_color", Color(0.94, 0.93, 0.9))
	margin.add_child(_tooltip_label)

# ---- Helpers -----------------------------------------------------------------

func _get_building_tile(building_id: StringName) -> Vector2i:
	return BuildingRegistry.get_building_tile(str(building_id))


func _find_route(route_id: StringName) -> LogisticsRoute:
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		if route.id == route_id:
			return route
	return null


## Returns the shortest distance from point p to line segment [a, b].
func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ---- Carrier icon ------------------------------------------------------------

## Smoothly moves each visible carrier icon toward its tick-set target position.
## Also advances the flow dot animation on each active route line.
func _process(delta: float) -> void:
	_validate_hover()
	for rid: StringName in _icon_map.keys():
		var icon: Node2D = _icon_map[rid]
		if not icon.visible:
			continue
		var target: Vector2 = _icon_target.get(rid, icon.position)
		icon.position = icon.position.lerp(target, clampf(delta * 8.0, 0.0, 1.0))

	for rid: StringName in _dot_map.keys():
		_animate_flow_dots(rid, delta)


## Animates the flow dots for one route, moving them in the carrier's travel direction.
## Forward (src→dst): dots march from start to end of the line.
## Backward (dst→src): dots march from end to start — mirrored position on path.
func _animate_flow_dots(route_id: StringName, delta: float) -> void:
	var dots: Array = _dot_map.get(route_id, [])
	var line: Line2D = _line_map.get(route_id)
	if line == null or line.get_point_count() < 2:
		for dot: Sprite2D in dots:
			dot.visible = false
		return

	var path: Array[Vector2] = []
	for i in range(line.get_point_count()):
		path.append(line.get_point_position(i))
	var path_len: float = PathGeometry.length(path)
	if path_len < 1.0:
		for dot: Sprite2D in dots:
			dot.visible = false
		return

	var opacity: float = line.modulate.a
	if opacity < 0.05 or line.default_color != COLOR_ACTIVE or not line.visible:
		for dot: Sprite2D in dots:
			dot.visible = false
		return

	var dir: float = _dot_direction.get(route_id, 1.0)
	var new_phase: float = _dot_phase.get(route_id, 0.0) + delta * FLOW_DOT_SPEED * dir
	new_phase = fmod(new_phase, path_len)
	if new_phase < 0.0:
		new_phase += path_len
	_dot_phase[route_id] = new_phase

	var phase: float = _dot_phase[route_id]
	var spacing: float = path_len / float(FLOW_DOT_COUNT)
	var base: Color = line.default_color
	var dot_color := Color(base.r, base.g, base.b, minf(opacity * 2.0, 0.85))

	for i in range(FLOW_DOT_COUNT):
		var dot: Sprite2D = dots[i]
		var t: float = fmod(phase + float(i) * spacing, path_len)
		dot.position = PathGeometry.point_along(path, t)
		dot.modulate = dot_color
		dot.visible = true


## Updates or hides the carrier icon for one route.
## Icon is shown during TRAVEL_TO_DESTINATION while the carrier holds cargo,
## independent of whether the route line itself is currently visible.
func _update_carrier_icon(route: LogisticsRoute) -> void:
	var icon: Node2D = _icon_map.get(route.id)

	var should_show: bool = (
		route.carrier_state == LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION
		and route.cargo > 0
		and route.cargo_resource != null
		and route.active
		and _grid != null
	)

	if not should_show:
		if icon != null:
			icon.visible = false
		return

	var src_tile: Vector2i = _get_building_tile(route.source_building_id)
	var dst_tile: Vector2i = _get_building_tile(route.destination_building_id)
	if src_tile == Vector2i(-1, -1) or dst_tile == Vector2i(-1, -1):
		return

	var path: Array[Vector2] = _route_world_path(route, src_tile, dst_tile)
	var icon_pos: Vector2 = _calc_carrier_world_pos(route, path, src_tile, dst_tile)

	var res_id: StringName = route.cargo_resource
	if icon == null or _icon_resource.get(route.id) != res_id:
		if icon != null:
			icon.queue_free()
		icon = _make_carrier_icon(res_id)
		icon.position = icon_pos
		add_child(icon)
		_icon_map[route.id] = icon
		_icon_resource[route.id] = res_id
	elif not icon.visible:
		icon.position = icon_pos

	# Show the "×N" cargo-count badge when carrying more than one item (carrier capacity > 1).
	var count_lbl: Label = icon.get_node_or_null("CountLabel")
	if count_lbl != null:
		count_lbl.visible = route.cargo > 1
		if count_lbl.visible:
			count_lbl.text = "×%d" % route.cargo

	_icon_target[route.id] = icon_pos
	icon.visible = true


## Returns the carrier's world-space position accounting for per-tile movement costs.
## Each tile in cached_path contributes get_tile_movement_cost() * TICKS_PER_TILE ticks.
## High-cost tiles (TREE/STONE = 4.0) are traversed slowly; path tiles (0.5) quickly.
func _calc_carrier_world_pos(route: LogisticsRoute, world_path: Array[Vector2],
		src_tile: Vector2i, dst_tile: Vector2i) -> Vector2:
	if world_path.is_empty():
		return Vector2.ZERO
	if world_path.size() == 1:
		return world_path[0]

	if route.path_valid and route.cached_path.size() == world_path.size() and _grid != null \
			and route.cached_path.size() >= 2:
		# Snap to destination when the carrier has fully arrived.
		if route.remaining_ticks <= 0:
			return world_path[world_path.size() - 1]

		var total_ticks: int = int(floor(route.cached_path_cost * LogisticsSystem.TICKS_PER_TILE))
		# F4: the leg's real duration is efficiency-scaled (captured at leg start). Derive the
		# 0..1 progress from that, then map it onto the base-cost-weighted tile budget below so
		# high-cost tiles still slow the icon proportionally.
		var leg_total: int = route.current_leg_total_ticks if route.current_leg_total_ticks > 0 else total_ticks
		var t: float = clampf(float(leg_total - route.remaining_ticks) / float(maxi(leg_total, 1)), 0.0, 1.0)
		var elapsed: float = t * float(total_ticks)
		var accumulated: float = 0.0

		# Leaving-tile semantics: segment world_path[i] → world_path[i+1] uses cost(cached_path[i]).
		# Icon appears at world_path[1] (first tile after source building) at elapsed=0.
		# Loop excludes the destination tile (N-1) since building entry has cost 0.
		for i in range(1, route.cached_path.size() - 1):
			var tile_ticks: float = _grid.get_tile_movement_cost(route.cached_path[i]) \
				* LogisticsSystem.TICKS_PER_TILE
			if tile_ticks <= 0.0:
				continue
			if elapsed < accumulated + tile_ticks:
				var frac: float = (elapsed - accumulated) / tile_ticks
				return world_path[i].lerp(world_path[i + 1], clampf(frac, 0.0, 1.0))
			accumulated += tile_ticks
		return world_path[world_path.size() - 1]

	# Fallback: linear progress when no path cache is available. Use the F4-scaled leg
	# duration when known, else the base estimate.
	var total_cost: float = route.cached_path_cost if route.path_valid else float(
		absi(dst_tile.x - src_tile.x) + absi(dst_tile.y - src_tile.y))
	var fallback_ticks: int = int(floor(total_cost * LogisticsSystem.TICKS_PER_TILE))
	var leg_total: int = route.current_leg_total_ticks if route.current_leg_total_ticks > 0 else fallback_ticks
	var progress: float = 1.0 if leg_total <= 0 else \
		clampf(1.0 - float(route.remaining_ticks) / float(leg_total), 0.0, 1.0)
	return PathGeometry.point_along(world_path, progress * PathGeometry.length(world_path))


## Builds the Node2D icon node (backdrop circle + resource sprite).
func _make_carrier_icon(resource_id: StringName) -> Node2D:
	var container := Node2D.new()
	container.z_index = 5

	var backdrop := Sprite2D.new()
	backdrop.texture = TextureFactory.circle(ICON_RADIUS, Color(0.0, 0.0, 0.0, 0.50))
	container.add_child(backdrop)

	var icon_spr := Sprite2D.new()
	icon_spr.texture = _load_resource_texture(resource_id)
	var icon_px: float = float(ICON_RADIUS) * 1.5
	var tex_size: Vector2 = icon_spr.texture.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		icon_spr.scale = Vector2(icon_px / tex_size.x, icon_px / tex_size.y)
	container.add_child(icon_spr)

	# Cargo-count badge ("×N") — shown only when the carrier hauls more than one item.
	var count_lbl := Label.new()
	count_lbl.name = "CountLabel"
	count_lbl.add_theme_font_size_override("font_size", 10)
	count_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	count_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	count_lbl.add_theme_constant_override("outline_size", 4)
	count_lbl.position = Vector2(float(ICON_RADIUS) * 0.5, -float(ICON_RADIUS) * 1.9)
	count_lbl.z_index = 1
	count_lbl.visible = false
	container.add_child(count_lbl)

	return container


## Loads the route-icon texture for a resource: world art → UI icon → circle fallback.
func _load_resource_texture(resource_id: StringName) -> Texture2D:
	return ResourceRegistry.get_icon_texture(resource_id, ICON_RADIUS)



# ---- Path helpers ------------------------------------------------------------

## Moves the first and last path points inward by amount, following the segment direction.
## Used so the visible line stops at building edges rather than overlapping the sprites.
func _trim_path_endpoints(path: Array[Vector2], amount: float) -> Array[Vector2]:
	if path.size() < 2:
		return path
	var result: Array[Vector2] = path.duplicate()
	var dir_start: Vector2 = (result[1] - result[0]).normalized()
	result[0] = result[0] + dir_start * amount
	var last: int = result.size() - 1
	var dir_end: Vector2 = (result[last] - result[last - 1]).normalized()
	result[last] = result[last] - dir_end * amount
	return result


## Returns the world-space path for a route.
## Uses route.cached_path (A* tile list) when valid; falls back to L-shape otherwise.
func _route_world_path(route: LogisticsRoute, src_tile: Vector2i, dst_tile: Vector2i) -> Array[Vector2]:
	if route.path_valid and route.cached_path.size() >= 2:
		var world_path: Array[Vector2] = []
		for tile: Vector2i in route.cached_path:
			world_path.append(_grid.tile_to_world(tile))
		return world_path
	return _build_route_path(_grid.tile_to_world(src_tile), _grid.tile_to_world(dst_tile))


## Builds the L-shaped (horizontal-first) world-space path between two positions.
func _build_route_path(src_pos: Vector2, dst_pos: Vector2) -> Array[Vector2]:
	return PathDotOverlay.l_path(src_pos, dst_pos)


