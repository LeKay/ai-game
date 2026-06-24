extends Control
## OverworldView — full-screen, toggleable render layer for the OverworldSystem island.
## Draws the biome grid at small RimWorld-style tiles with its own pan/zoom (independent of
## the tactical Camera2D), a hover highlight, the start-tile marker, and a read-only tile
## inspection panel. Opening pushes UI_ACTIVE so the world camera stops; closing pops it.
##
## Two modes:
##  - Anytime layer (toggle with `overworld_toggle` / M): inspect tiles read-only.
##  - Start picker (open_for_pick(), used on a new game): the panel gains a "Start here"
##    button; committing emits OverworldSystem.start_selected and closes. The view cannot be
##    dismissed without choosing, so a new game always has a valid start tile.
## Spec: design/quick-specs/overworld-map-system-2026-06-21.md

## Biome fill colors (ocean / coast / inland / forest / mountain).
const _COLOR_OCEAN := Color(0.12, 0.32, 0.55)
const _COLOR_COAST := Color(0.85, 0.78, 0.55)
const _COLOR_INLAND := Color(0.30, 0.55, 0.28)
const _COLOR_FOREST := Color(0.13, 0.34, 0.16)     ## Dark green woodland.
const _COLOR_MOUNTAIN := Color(0.45, 0.42, 0.40)   ## Grey-brown rock.
const _COLOR_RIVER := Color(0.25, 0.55, 0.85)       ## River water — lighter than ocean to read on land.
const _COLOR_LAKE := Color(0.32, 0.62, 0.80)        ## Lake freshwater — teal-ish, distinct from salt ocean.
const _COLOR_BACKDROP := Color(0.05, 0.08, 0.12)
const _COLOR_GRID := Color(0.0, 0.0, 0.0, 0.15)
const _COLOR_START := Color(1.0, 0.84, 0.0)        ## Gold accent for the "Current start" panel note.
const _COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.7)
const _COLOR_SELECTED := Color(0.4, 0.85, 1.0)     ## Cyan border on the inspected tile.

const _MIN_ZOOM: float = 0.1   ## Low enough to fit the whole 256-tile island on screen.
const _MAX_ZOOM: float = 10.0
const _ZOOM_STEP: float = 1.15                     ## Multiplicative per wheel notch.
const _FIT_MARGIN: float = 0.85                    ## Island fills this fraction of the screen.
const _CLICK_MAX_TRAVEL: float = 6.0               ## Below this drag distance, a release is a click.
const _GRID_MIN_PX: float = 24.0                   ## Only draw tile grid lines once tiles are this big.

## Compass label per WorldGrid coast_edge (0 top, 1 bottom, 2 left, 3 right).
const _EDGE_COMPASS: Array[String] = ["North", "South", "West", "East"]

## World-space (overworld pixels) position shown at the view's top-left, and the pixel scale.
var _view_offset: Vector2 = Vector2.ZERO
var _view_zoom: float = 1.0
var _dragging: bool = false
var _drag_travel: float = 0.0                      ## Accumulated drag distance since press.
var _hover_tile: Vector2i = Vector2i(-1, -1)
var _selected_tile: Vector2i = Vector2i(-1, -1)    ## Tile shown in the inspection panel.
var _open: bool = false
var _pick_mode: bool = false                       ## True while choosing a new game's start.
var _was_paused: bool = false                      ## Pause state before the view opened; restored on close.

## One-pixel-per-tile biome image, drawn as a single nearest-filtered rect so rendering cost
## is independent of OVERWORLD_SIZE (a 256x256 grid is one draw call, not 65k).
var _biome_tex: ImageTexture = null

## NPC-city marker icon, drawn over each city tile. Loaded (not preloaded) so a missing/unimported
## asset degrades to "no icon" instead of a compile error. See _CITY_ICON_PATH.
const _CITY_ICON_PATH := "res://assets/ui/icons/overworld/city.png"
const _PLAYER_ICON_PATH := "res://assets/ui/icons/overworld/player_settlement.png"
const _CITY_ICON_MIN_PX: float = 18.0   ## Icon never shrinks below this, so cities read at any zoom.
const _CITY_ICON_TILE_SPAN: float = 3.0 ## Icon covers this many tiles per side (3x3, city-centred).
const _FACTION_EMBLEM_SCALE: float = 0.6 ## Faction emblem size relative to the city icon.
const _PLAYER_PREVIEW_MODULATE := Color(1.0, 1.0, 1.0, 0.55)  ## Translucent while a start is only previewed.
const _FACTION_ICON_DIR := "res://assets/ui/icons/factions/"
var _city_tex: Texture2D = null
var _player_tex: Texture2D = null
var _faction_tex: Dictionary = {}  ## faction id -> Texture2D (loaded once; missing assets skipped)

## Emitted when the player double-clicks a land tile (other than the current one) after a start
## has been chosen. MapRoot listens and switches the tactical map to that tile.
signal map_opened(coord: Vector2i)

# Inspection panel widgets (built programmatically in _ready).
var _panel: PanelContainer = null
var _faction_icon: TextureRect = null   ## Faction emblem shown at the top of the panel for city tiles.
var _title_label: Label = null
var _biome_label: Label = null
var _fertility_label: Label = null
var _fertility_icons: VBoxContainer = null  ## Per-fertility icon + name chips, below _fertility_label.
var _note_label: Label = null
var _start_button: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp tile edges when zoomed in
	visible = false
	if ResourceLoader.exists(_CITY_ICON_PATH):
		_city_tex = load(_CITY_ICON_PATH)
	if ResourceLoader.exists(_PLAYER_ICON_PATH):
		_player_tex = load(_PLAYER_ICON_PATH)
	for faction: Dictionary in OverworldSystem.FACTIONS:
		var path: String = _FACTION_ICON_DIR + faction["id"] + ".png"
		if ResourceLoader.exists(path):
			_faction_tex[faction["id"]] = load(path)
	_build_panel()
	# Rebuild the biome texture on (re)generation; redraw the marker on start selection.
	OverworldSystem.overworld_generated.connect(_on_overworld_generated)
	OverworldSystem.start_selected.connect(func(_c: Vector2i) -> void: queue_redraw())


func _on_overworld_generated() -> void:
	_biome_tex = null  # invalidate; rebuilt lazily on next draw
	queue_redraw()


## Builds the one-pixel-per-tile biome image. Cheap and done once per generation.
func _rebuild_biome_texture() -> void:
	var n: int = OverworldSystem.OVERWORLD_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for x in range(n):
		for y in range(n):
			var coord := Vector2i(x, y)
			# River tiles read as water on top of their biome (rivers cross forest/mountain/plains).
			var color: Color = _biome_color(OverworldSystem.get_biome(coord))
			img.set_pixel(x, y, color)
	_biome_tex = ImageTexture.create_from_image(img)


# --- Toggle / open / close ---------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.OVERWORLD_TOGGLE):
		# In pick mode the player must commit a start before the view can be dismissed.
		if not _pick_mode:
			toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and not _pick_mode and event.is_action_pressed(InputActions.UI_CANCEL):
		close()
		get_viewport().set_input_as_handled()
		return
	if _open:
		_handle_view_input(event)


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## Opens the anytime inspection layer.
func open() -> void:
	if _open:
		return
	if not OverworldSystem.is_generated():
		OverworldSystem.generate(randi())
	_open = true
	visible = true
	InputContext.push_context(InputContext.Context.UI_ACTIVE)
	_fit_to_view()
	_hide_panel()
	if not _pick_mode:
		_enter_overlay_mode()
	queue_redraw()


## Opens the view as a blocking start picker (new game). Assumes the overworld is generated.
func open_for_pick() -> void:
	_pick_mode = true
	if _open:
		_hide_panel()
		queue_redraw()
		return
	open()


## Opens the view in blocking pick mode before generation has run — shows a loading message.
## Caller must await one frame, then call OverworldSystem.generate(); the overworld_generated
## signal will trigger a redraw that replaces the loading text with the biome map.
func open_for_loading() -> void:
	_pick_mode = true
	if _open:
		queue_redraw()
		return
	_open = true
	visible = true
	InputContext.push_context(InputContext.Context.UI_ACTIVE)
	_fit_to_view()
	_hide_panel()
	queue_redraw()


func close() -> void:
	if not _open:
		return
	if _pick_mode:
		return  # Must choose a start first.
	_open = false
	visible = false
	_dragging = false
	_hide_panel()
	InputContext.pop_context()
	_exit_overlay_mode()


func _enter_overlay_mode() -> void:
	_was_paused = TickSystem.is_paused()
	TickSystem.set_pause(true)
	for node: Node in get_tree().get_nodes_in_group(&"hud"):
		if node.has_method(&"enter_overworld_mode"):
			node.enter_overworld_mode()
	for node: Node in get_tree().get_nodes_in_group(&"fertility_indicator"):
		node.visible = false


func _exit_overlay_mode() -> void:
	TickSystem.set_pause(_was_paused)
	for node: Node in get_tree().get_nodes_in_group(&"hud"):
		if node.has_method(&"exit_overworld_mode"):
			node.exit_overworld_mode()
	for node: Node in get_tree().get_nodes_in_group(&"fertility_indicator"):
		node.visible = true


# --- Pan / zoom / hover / click ----------------------------------------------

func _handle_view_input(event: InputEvent) -> void:
	# Let the inspection panel and the start button handle events over their own rects.
	if event is InputEventMouse:
		var mp: Vector2 = (event as InputEventMouse).position
		if _panel.visible and _panel.get_global_rect().has_point(mp):
			return
		if _start_button != null and _start_button.visible and _start_button.get_global_rect().has_point(mp):
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Don't grab clicks meant for HUD controls layered above the map (e.g. the ✕ close
		# button). _input() runs before GUI, so without this the press would start a map drag.
		if _is_over_external_ui():
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, _ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / _ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Double-click a land tile (after a start exists) to travel there. Handled on
				# press via the engine's double_click flag; a single click still inspects.
				if mb.double_click and _try_open_map(_screen_to_tile(mb.position)):
					get_viewport().set_input_as_handled()
					return
				_dragging = true
				_drag_travel = 0.0
			else:
				_dragging = false
				if _drag_travel <= _CLICK_MAX_TRAVEL:
					_on_tile_clicked(_screen_to_tile(mb.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# When not mid-drag, let HUD controls above the map receive hover (don't eat the motion).
		if not _dragging and _is_over_external_ui():
			return
		if _dragging:
			_drag_travel += mm.relative.length()
			_view_offset -= mm.relative / _view_zoom
			_clamp_offset()
			queue_redraw()
		var tile := _screen_to_tile(mm.position)
		if tile != _hover_tile:
			_hover_tile = tile
			queue_redraw()
		get_viewport().set_input_as_handled()


## True when the mouse is over a GUI control that isn't this view (or one of its children) — i.e.
## a HUD element layered above the map. Used to yield clicks/hover to that control instead of
## starting a map drag, since _input() runs before GUI input.
func _is_over_external_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	return hovered != self and not is_ancestor_of(hovered)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom: float = clampf(_view_zoom * factor, _MIN_ZOOM, _MAX_ZOOM)
	if is_equal_approx(new_zoom, _view_zoom):
		return
	# Keep the world point under the cursor fixed while zooming.
	var world_before: Vector2 = _view_offset + screen_pos / _view_zoom
	_view_zoom = new_zoom
	_view_offset = world_before - screen_pos / _view_zoom
	_clamp_offset()
	queue_redraw()


func _fit_to_view() -> void:
	var world_px: float = float(OverworldSystem.OVERWORLD_SIZE * OverworldSystem.OVERWORLD_TILE_SIZE)
	var screen: Vector2 = size
	if screen == Vector2.ZERO or world_px <= 0.0:
		return
	var fit: float = minf(screen.x, screen.y) / world_px * _FIT_MARGIN
	_view_zoom = clampf(fit, _MIN_ZOOM, _MAX_ZOOM)
	# Center the island in the viewport.
	_view_offset = Vector2(world_px, world_px) * 0.5 - screen / (2.0 * _view_zoom)


## Clamps _view_offset so the island never fully leaves the screen.
## Allows panning at most half a screen's worth of world-space beyond each map edge.
func _clamp_offset() -> void:
	var n: int = OverworldSystem.OVERWORLD_SIZE
	var ts: int = OverworldSystem.OVERWORLD_TILE_SIZE
	var world_size: float = n * ts
	var screen_world: Vector2 = size / _view_zoom
	var pad: Vector2 = screen_world * 0.5
	_view_offset.x = clampf(_view_offset.x, -pad.x, world_size - screen_world.x + pad.x)
	_view_offset.y = clampf(_view_offset.y, -pad.y, world_size - screen_world.y + pad.y)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world: Vector2 = _view_offset + screen_pos / _view_zoom
	var ts: int = OverworldSystem.OVERWORLD_TILE_SIZE
	return Vector2i(floori(world.x / ts), floori(world.y / ts))


## A tile was clicked (not dragged): select it and refresh the inspection panel.
func _on_tile_clicked(coord: Vector2i) -> void:
	if OverworldSystem.get_tile(coord) == null:
		_hide_panel()
		return
	_log_water_kind(coord)
	_selected_tile = coord
	_populate_panel(coord)
	queue_redraw()


## Logs whether the clicked tile is open sea, a lake or a river (water bodies only).
func _log_water_kind(coord: Vector2i) -> void:
	match OverworldSystem.get_biome(coord):
		OverworldSystem.Biome.OCEAN:
			print("[OVERWORLD] Tile %s: Meer (ocean)" % coord)
		OverworldSystem.Biome.LAKE:
			print("[OVERWORLD] Tile %s: See (lake)" % coord)
		OverworldSystem.Biome.RIVER:
			print("[OVERWORLD] Tile %s: Fluss (river)" % coord)


## Attempts to travel to coord's tactical map on a double-click. Allowed only outside pick mode,
## once a start exists, on a land tile that isn't the one already loaded. Closes the view (popping
## UI context) and emits map_opened; returns true if travel was started, false to fall through to
## the normal click/drag handling.
func _try_open_map(coord: Vector2i) -> bool:
	if _pick_mode:
		return false
	if OverworldSystem.get_start_coord() == Vector2i(-1, -1):
		return false
	if not OverworldSystem.is_selectable(coord):
		return false
	if coord == WorldSaveManager.get_current_map_coord():
		return false
	close()  # pop UI context before MapRoot reloads the scene
	map_opened.emit(coord)
	return true


# --- Inspection panel --------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "InfoPanel"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Pin to the top-right corner, content-sized, growing leftward/downward.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.offset_right = -24
	# Sit clear below the HUD's top band so the two don't overlap.
	_panel.offset_top = HUD.TOP_BAND_HEIGHT + 24
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(200, 0)
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Faction emblem, centred at the top — only shown for NPC-city tiles.
	_faction_icon = TextureRect.new()
	_faction_icon.visible = false
	_faction_icon.custom_minimum_size = Vector2(64, 64)
	_faction_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_faction_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel-art emblem
	vbox.add_child(_faction_icon)

	_title_label = _make_label(vbox, 18)
	_biome_label = _make_label(vbox, 14)
	_fertility_label = _make_label(vbox, 14)
	_fertility_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fertility_icons = VBoxContainer.new()
	_fertility_icons.add_theme_constant_override("separation", 4)
	vbox.add_child(_fertility_icons)
	_note_label = _make_label(vbox, 13)
	_note_label.modulate = _COLOR_START

	_build_start_button()


func _build_start_button() -> void:
	_start_button = Button.new()
	_start_button.name = "StartHereBtn"
	_start_button.text = "Start here"
	_start_button.visible = false
	_start_button.custom_minimum_size = Vector2(240, 52)
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.focus_mode = Control.FOCUS_NONE
	# Anchor bottom-center of the full view, clear of any bottom HUD elements.
	_start_button.anchor_left   = 0.5
	_start_button.anchor_right  = 0.5
	_start_button.anchor_top    = 1.0
	_start_button.anchor_bottom = 1.0
	_start_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_start_button.offset_left   = -120
	_start_button.offset_right  =  120
	_start_button.offset_top    = -80
	_start_button.offset_bottom = -28
	_start_button.pressed.connect(_on_start_here_pressed)
	add_child(_start_button)


func _make_label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _populate_panel(coord: Vector2i) -> void:
	var tile := OverworldSystem.get_tile(coord)
	if tile == null:
		_hide_panel()
		return
	# Faction emblem + title: cities are titled by their owning faction; other tiles by coords.
	var faction_idx: int = OverworldSystem.get_city_faction(coord)
	if faction_idx >= 0:
		var faction_id: String = OverworldSystem.get_faction_id(faction_idx)
		_faction_icon.texture = _faction_tex.get(faction_id, null)
		_faction_icon.visible = _faction_icon.texture != null
		_title_label.text = OverworldSystem.get_faction_name(faction_idx)
	else:
		_faction_icon.visible = false
		_title_label.text = "Tile (%d, %d)" % [coord.x, coord.y]
	var biome_line: String = _biome_text(tile)
	if not tile.river_edges.is_empty():
		biome_line += "  •  Borders a river"
	if not tile.lake_edges.is_empty():
		biome_line += "  •  Borders a lake"
	_biome_label.text = "Biome: %s" % biome_line
	# Fertilities are hidden while picking a start: the chosen tile's rolled set is replaced by
	# the fixed STARTING_FERTILITY (clay/wheat/wild), so showing them here would mislead.
	if _pick_mode:
		_fertility_label.visible = false
		_set_fertility_chips([])
	elif tile.fertilities.is_empty():
		_fertility_label.visible = true
		_fertility_label.text = "Open water — no land to settle."
		_set_fertility_chips([])
	else:
		_fertility_label.visible = true
		_fertility_label.text = "Fertilities:"
		_set_fertility_chips(tile.fertilities)
	# Note line: NPC-city status takes priority over the start marker.
	if OverworldSystem.is_city(coord):
		_note_label.visible = true
		_note_label.modulate = _COLOR_RIVER
		_note_label.text = "NPC city — cannot settle here"
	elif OverworldSystem.is_city_blocked(coord):
		_note_label.visible = true
		_note_label.modulate = _COLOR_RIVER
		_note_label.text = "Too close to an NPC city to settle"
	else:
		_note_label.visible = tile.is_start
		_note_label.modulate = _COLOR_START
		_note_label.text = "Current start"
	# Offer the start button only while picking and only on tiles the player may actually start on.
	_start_button.visible = _pick_mode and OverworldSystem.is_start_allowed(coord)
	_panel.visible = true


func _hide_panel() -> void:
	if _panel != null:
		_panel.visible = false
	if _start_button != null:
		_start_button.visible = false
	_selected_tile = Vector2i(-1, -1)


func _on_start_here_pressed() -> void:
	if not OverworldSystem.is_start_allowed(_selected_tile):
		return
	# Commit: this fires OverworldSystem.start_selected, which the map coordinator listens
	# for to generate the tactical map. Drop pick mode first so close() will proceed.
	var coord := _selected_tile
	_pick_mode = false
	_hide_panel()
	OverworldSystem.select_start(coord)
	close()


func _biome_text(tile) -> String:
	match tile.biome:
		OverworldSystem.Biome.INLAND:
			return "Plains"
		OverworldSystem.Biome.FOREST:
			return "Forest"
		OverworldSystem.Biome.MOUNTAIN:
			return "Mountain"
		OverworldSystem.Biome.RIVER:
			return "River (freshwater)"
		OverworldSystem.Biome.LAKE:
			return "Lake (freshwater)"
		OverworldSystem.Biome.COAST:
			var dirs: Array[String] = []
			for edge: int in tile.coast_edges:
				dirs.append(_EDGE_COMPASS[edge])
			var facing: String = ", ".join(dirs) if not dirs.is_empty() else "?"
			return "Coast (faces %s)" % facing
		_:
			return "Ocean"


const _WILD_DEER_ICON := "res://assets/ui/icons/various/ui_icon_wild_deer.png"
const _FERTILITY_ICON_PX: int = 20

## Rebuilds the per-fertility chip row (icon + display name) under the fertility header.
## Special cases: "wild" → Wildlife + deer icon; "bees" → Honey + honey icon.
func _set_fertility_chips(fertilities: Array) -> void:
	for child in _fertility_icons.get_children():
		child.queue_free()
	_fertility_icons.visible = not fertilities.is_empty()
	for f: StringName in fertilities:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(_FERTILITY_ICON_PX, _FERTILITY_ICON_PX)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)
		match f:
			&"wild":
				label.text = "Wildlife"
				if ResourceLoader.exists(_WILD_DEER_ICON):
					icon.texture = load(_WILD_DEER_ICON)
			&"bees":
				label.text = "Honey"
				icon.texture = ResourceRegistry.get_icon_texture(&"honey", _FERTILITY_ICON_PX)
			_:
				var def := ResourceRegistry.get_definition(f)
				if def != null:
					label.text = def.display_name
					icon.texture = ResourceRegistry.get_icon_texture(f, _FERTILITY_ICON_PX)
				else:
					label.text = String(f).capitalize()
		if icon.texture != null:
			chip.add_child(icon)
		chip.add_child(label)
		_fertility_icons.add_child(chip)


# --- Rendering ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _COLOR_BACKDROP)
	if not OverworldSystem.is_generated():
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0.0, size.y * 0.5), "Generating world...",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
		return
	if _biome_tex == null:
		_rebuild_biome_texture()
	var n: int = OverworldSystem.OVERWORLD_SIZE
	var ts: int = OverworldSystem.OVERWORLD_TILE_SIZE
	var px: float = ts * _view_zoom
	# Whole biome grid as one nearest-filtered rect (1 draw call regardless of size).
	var map_origin: Vector2 = (Vector2.ZERO - _view_offset) * _view_zoom
	var map_size: float = n * ts * _view_zoom
	draw_texture_rect(_biome_tex, Rect2(map_origin, Vector2(map_size, map_size)), false)
	# Grid lines only when zoomed in enough to matter, and only over the visible tile range.
	if px >= _GRID_MIN_PX:
		var tl: Vector2i = _clamp_tile(_screen_to_tile(Vector2.ZERO))
		var br: Vector2i = _clamp_tile(_screen_to_tile(size))
		for x in range(tl.x, br.x + 1):
			for y in range(tl.y, br.y + 1):
				draw_rect(_tile_rect(Vector2i(x, y), ts), _COLOR_GRID, false, 1.0)
	# NPC-city icons, each spanning a 3x3 tile block centred on the city tile, with the owning
	# faction's emblem floating smaller and diagonally above it.
	if _city_tex != null:
		for city: Vector2i in OverworldSystem.get_cities():
			_draw_settlement_icon(_city_tex, city, ts, px)
			_draw_city_faction_emblem(city, ts, px)
	# Player settlement: a translucent preview on the candidate tile while choosing a start, then a
	# solid marker fixed on the chosen tile once a start exists.
	if _player_tex != null:
		if _pick_mode:
			if _selected_tile != Vector2i(-1, -1) and OverworldSystem.is_start_allowed(_selected_tile):
				_draw_settlement_icon(_player_tex, _selected_tile, ts, px, _PLAYER_PREVIEW_MODULATE)
		else:
			var start_coord: Vector2i = OverworldSystem.get_start_coord()
			if start_coord != Vector2i(-1, -1):
				_draw_settlement_icon(_player_tex, start_coord, ts, px)
	# Inspected tile outline — only outside the start picker, where the settlement preview icon
	# already marks the selected tile.
	if not _pick_mode and _selected_tile != Vector2i(-1, -1):
		draw_rect(_tile_rect(_selected_tile, ts), _COLOR_SELECTED, false, 2.0)
	# Hover highlight: while picking, only over tiles you may actually start on; otherwise any land.
	var hover_ok: bool = (
		OverworldSystem.is_start_allowed(_hover_tile) if _pick_mode
		else OverworldSystem.is_selectable(_hover_tile))
	if hover_ok:
		draw_rect(_tile_rect(_hover_tile, ts), _COLOR_HOVER, false, 2.0)


func _clamp_tile(coord: Vector2i) -> Vector2i:
	var n: int = OverworldSystem.OVERWORLD_SIZE
	return Vector2i(clampi(coord.x, 0, n - 1), clampi(coord.y, 0, n - 1))


func _tile_rect(coord: Vector2i, ts: int) -> Rect2:
	var screen_pos: Vector2 = (Vector2(coord * ts) - _view_offset) * _view_zoom
	return Rect2(screen_pos, Vector2(ts * _view_zoom, ts * _view_zoom))


## Draws a settlement icon (NPC city or player home) spanning a 3x3 tile block centred on `coord`,
## floored at _CITY_ICON_MIN_PX so it stays readable at any zoom. `modulate` tints it (e.g. a
## translucent preview). `px` is the current pixels-per-tile.
func _draw_settlement_icon(tex: Texture2D, coord: Vector2i, ts: int, px: float,
		modulate: Color = Color.WHITE) -> void:
	var icon_px: float = maxf(px * _CITY_ICON_TILE_SPAN, _CITY_ICON_MIN_PX)
	var center: Vector2 = _tile_rect(coord, ts).get_center()
	draw_texture_rect(
		tex,
		Rect2(center - Vector2(icon_px, icon_px) * 0.5, Vector2(icon_px, icon_px)),
		false,
		modulate)


## Draws a city's faction emblem smaller and diagonally above the city icon (a floating badge at the
## upper-right). No-op if the faction has no loaded emblem.
func _draw_city_faction_emblem(city: Vector2i, ts: int, px: float) -> void:
	var faction_id: String = OverworldSystem.get_faction_id(OverworldSystem.get_city_faction(city))
	var tex: Texture2D = _faction_tex.get(faction_id, null)
	if tex == null:
		return
	var icon_px: float = maxf(px * _CITY_ICON_TILE_SPAN, _CITY_ICON_MIN_PX)
	var emblem_px: float = icon_px * _FACTION_EMBLEM_SCALE
	# Float it up and to the right of the city centre — "schräg darüber".
	var center: Vector2 = _tile_rect(city, ts).get_center() + Vector2(icon_px * 0.4, -icon_px * 0.5)
	draw_texture_rect(
		tex,
		Rect2(center - Vector2(emblem_px, emblem_px) * 0.5, Vector2(emblem_px, emblem_px)),
		false)


func _biome_color(biome: int) -> Color:
	match biome:
		OverworldSystem.Biome.INLAND:
			return _COLOR_INLAND
		OverworldSystem.Biome.FOREST:
			return _COLOR_FOREST
		OverworldSystem.Biome.MOUNTAIN:
			return _COLOR_MOUNTAIN
		OverworldSystem.Biome.RIVER:
			return _COLOR_RIVER
		OverworldSystem.Biome.LAKE:
			return _COLOR_LAKE
		OverworldSystem.Biome.COAST:
			return _COLOR_COAST
		_:
			return _COLOR_OCEAN
