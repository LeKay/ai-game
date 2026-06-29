class_name BuildPlacementOverlay extends CanvasLayer
## Ghost overlay for building placement mode.
## Activated by HUD (_on_build_mode_requested) via start_placement / start_path_placement, driven by
## the Buildings drawer's build picker.
## Draws a coloured tile highlight snapped to the world grid.
## Left-click places; ESC or right-click cancels.

const TILE_SIZE := WorldGrid.TILE_SIZE

## Blue tint when placement is valid, red when blocked.
const COLOR_VALID   := Color(0.4, 0.65, 1.0, 0.65)
const COLOR_INVALID := Color(1.0, 0.3,  0.3, 0.65)
## Highlights tiles that satisfy an adjacency requirement (e.g. TREE for Lumber Camp).
const COLOR_HINT    := Color(1.0, 0.85, 0.1, 0.35)

var _active:           bool = false
var _building_type:    int  = -1
var _is_path_mode:     bool = false
var _is_demolish_mode: bool = false

var _ghost: TextureRect
var _label: Label
var _hint_rects: Array[ColorRect] = []


func _ready() -> void:
	layer   = 5
	visible = false
	_build_ghost()


func _build_ghost() -> void:
	_ghost = TextureRect.new()
	_ghost.name         = "Ghost"
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_ghost)

	_label = Label.new()
	_label.name = "GhostLabel"
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 3)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	for i in range(8):
		var hr := ColorRect.new()
		hr.name         = "HintRect%d" % i
		hr.color        = COLOR_HINT
		hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hr.visible      = false
		add_child(hr)
		_hint_rects.append(hr)


## Activates ghost placement for the given building type.
func start_placement(building_type: int) -> void:
	_active        = true
	_is_path_mode  = false
	_building_type = building_type
	var tex_path: String = BuildingRegistry.BUILDING_TEXTURES.get(
		building_type, "res://assets/art/buildings/bld_tile_storage.png")
	_ghost.texture = load(tex_path)
	visible        = true


## Activates demolish mode. Hover shows red highlight over buildings; click demolishes.
func start_demolish_mode() -> void:
	_active           = true
	_is_demolish_mode = true
	_is_path_mode     = false
	_building_type    = BuildingGrid.DEMOLISH_SENTINEL
	_ghost.texture    = null
	visible           = true


## Activates path placement mode. Stays active until ESC or right-click.
func start_path_placement() -> void:
	_active        = true
	_is_path_mode  = true
	_building_type = PathSystem.PATH_SENTINEL
	_ghost.texture = load(PathSystem.PATH_TEXTURES[10])  # EW straight as initial ghost
	visible        = true


func _cancel() -> void:
	_active           = false
	_is_path_mode     = false
	_is_demolish_mode = false
	_building_type    = -1
	visible           = false


func _process(_delta: float) -> void:
	if not _active:
		return
	var camera := get_viewport().get_camera_2d()
	var zoom   := camera.zoom if camera != null else Vector2.ONE
	var tile       := _hovered_tile()
	var screen_pos := _tile_to_screen(tile)
	var ghost_size := Vector2(TILE_SIZE, TILE_SIZE) * zoom

	_ghost.position = screen_pos
	_ghost.size     = ghost_size
	_label.position = screen_pos + Vector2(0.0, ghost_size.y + 4.0)

	if _is_demolish_mode:
		_process_demolish_ghost(tile)
		return

	if _is_path_mode:
		_process_path_ghost(tile)
		return

	var result := BuildingRegistry.check_build_conditions(_building_type, tile)
	var placeable: bool = result == BuildingRegistry.PlacementResult.SUCCESS \
			or result == BuildingRegistry.PlacementResult.INSUFFICIENT_ENERGY
	_ghost.modulate = COLOR_VALID if placeable else COLOR_INVALID
	match result:
		BuildingRegistry.PlacementResult.SUCCESS:
			_label.text = "Click to place"
		BuildingRegistry.PlacementResult.INSUFFICIENT_RESOURCES:
			_label.text = "Not enough resources"
		BuildingRegistry.PlacementResult.INSUFFICIENT_ENERGY:
			_label.text = "Click to place (needs construction work)"
		BuildingRegistry.PlacementResult.BLOCKED_BY_ADJACENCY:
			_label.text = _adjacency_hint_label(_building_type)
		BuildingRegistry.PlacementResult.LOCKED:
			_label.text = "Locked — unlock in the tech tree"
		_:
			_label.text = "Cannot place here"

	_update_hint_tiles(tile, zoom)


func _process_demolish_ghost(tile: Vector2i) -> void:
	var building_id := _building_id_at_tile(tile)
	var has_path    := PathSystem.has_path(tile)
	if building_id != "" or has_path:
		_ghost.modulate = COLOR_INVALID
		_label.text = "Click to demolish — ESC to stop"
	else:
		_ghost.modulate = Color(0.5, 0.5, 0.5, 0.4)
		_label.text = "Nothing here — ESC to stop"
	for hr: ColorRect in _hint_rects:
		hr.visible = false


func _building_id_at_tile(tile: Vector2i) -> String:
	for instance: BuildingRegistry.BuildingInstance in BuildingRegistry.get_all_buildings():
		if instance.tile == tile:
			return instance.building_id
	return ""


func _process_path_ghost(tile: Vector2i) -> void:
	var result := PathSystem.validate_placement(tile)
	if result == PathSystem.PathPlacementResult.SUCCESS:
		_ghost.modulate = COLOR_VALID
		_ghost.texture  = load(PathSystem.PATH_TEXTURES.get(PathSystem.compute_bitmask(tile), PathSystem.PATH_TEXTURES[0]))
		_label.text = "Click to place — ESC to stop"
	else:
		_ghost.modulate = COLOR_INVALID
		_ghost.texture  = load(PathSystem.PATH_TEXTURES[0])
		match result:
			PathSystem.PathPlacementResult.ALREADY_HAS_PATH:
				_label.text = "Path already here"
			PathSystem.PathPlacementResult.ALREADY_CONSTRUCTING:
				_label.text = "Under construction"
			PathSystem.PathPlacementResult.BLOCKED_BY_BUILDING:
				_label.text = "Blocked by building"
			_:
				_label.text = "Cannot place here"
	for hr: ColorRect in _hint_rects:
		hr.visible = false


func _update_hint_tiles(tile: Vector2i, zoom: Vector2) -> void:
	var hint_tiles := BuildingRegistry.get_adjacency_hint_tiles(_building_type, tile)
	for i in range(_hint_rects.size()):
		if i < hint_tiles.size():
			_hint_rects[i].position = _tile_to_screen(hint_tiles[i])
			_hint_rects[i].size     = Vector2(TILE_SIZE, TILE_SIZE) * zoom
			_hint_rects[i].visible  = true
		else:
			_hint_rects[i].visible = false


func _adjacency_hint_label(building_type: int) -> String:
	if building_type == BuildingRegistry.BuildingType.BRIDGE:
		return "Must bridge two shores across the water"
	var required: Array = BuildingRegistry.ADJACENCY_REQUIREMENTS.get(building_type, [])
	if required.is_empty():
		return "Cannot place here"
	var names: Array[String] = []
	for terrain_type: int in required:
		match terrain_type:
			WorldGrid.TileType.TREE:  names.append("a tree")
			WorldGrid.TileType.STONE: names.append("stone")
			WorldGrid.TileType.BERRY: names.append("berry bushes")
			WorldGrid.TileType.GRASS: names.append("grass")
			_:                        names.append("required terrain")
	return "Must be placed next to %s" % ", ".join(names)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()
		return

	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_cancel()
		get_viewport().set_input_as_handled()
		return

	if mb.button_index == MOUSE_BUTTON_LEFT:
		var tile := _hovered_tile()
		if _is_demolish_mode:
			var building_id := _building_id_at_tile(tile)
			if building_id != "":
				if _can_demolish(building_id):
					var inst := BuildingRegistry.get_building_instance(building_id)
					if inst != null and inst.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE:
						NPCSystem.reassign_house_residents(inst.tile)
					BuildingRegistry.demolish_building(building_id)
				else:
					var instance := BuildingRegistry.get_building_instance(building_id)
					var residents := NPCSystem.get_house_npc_count(instance.tile)
					_show_hud_error(
						"Cannot demolish: %d resident%s need a free house first" % [
							residents, "s" if residents != 1 else ""])
			elif PathSystem.has_path(tile):
				PathSystem.remove_path(tile)
			# Stay in demolish mode for continuous demolishing.
		elif _is_path_mode:
			PathSystem.initiate_path(tile)
			# Stay in path mode for continuous painting.
		else:
			var place_result := BuildingRegistry.check_build_conditions(_building_type, tile)
			if place_result == BuildingRegistry.PlacementResult.SUCCESS \
					or place_result == BuildingRegistry.PlacementResult.INSUFFICIENT_ENERGY:
				BuildingRegistry.initiate_build(_building_type, tile)
				_cancel()
		get_viewport().set_input_as_handled()


func _hovered_tile() -> Vector2i:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return Vector2i(-1, -1)
	var mouse   := get_viewport().get_mouse_position()
	var vp_size := get_viewport().get_visible_rect().size
	var world_pos := camera.get_screen_center_position() + (mouse - vp_size * 0.5) / camera.zoom
	return Vector2i(int(floor(world_pos.x / float(TILE_SIZE))),
	                int(floor(world_pos.y / float(TILE_SIZE))))


func _tile_to_screen(tile: Vector2i) -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return Vector2.ZERO
	var world_pos := Vector2(tile.x, tile.y) * float(TILE_SIZE)
	var vp_size   := get_viewport().get_visible_rect().size
	return vp_size * 0.5 + (world_pos - camera.get_screen_center_position()) * camera.zoom


## Returns false when building_id is an occupied Residential House and no other
## operating house has a free slot for each resident. True for all other buildings.
func _can_demolish(building_id: String) -> bool:
	var instance := BuildingRegistry.get_building_instance(building_id)
	if instance == null or instance.type != BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE:
		return true
	var residents: int = NPCSystem.get_house_npc_count(instance.tile)
	if residents == 0:
		return true
	var free_slots: int = 0
	for b: BuildingRegistry.BuildingInstance in BuildingRegistry.get_all_buildings():
		if b.building_id == building_id:
			continue
		if b.type != BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE:
			continue
		if b.state != BuildingRegistry.BuildingInstance.State.OPERATING:
			continue
		free_slots += NPCSystem.NPC_CAPACITY_PER_HOUSE - NPCSystem.get_house_npc_count(b.tile)
	return free_slots >= residents


## Shows a red error toast via the HUD.
func _show_hud_error(text: String) -> void:
	var huds := get_tree().get_nodes_in_group(&"hud")
	if huds.is_empty():
		return
	var hud: Node = huds[0]
	if hud.has_method("show_toast"):
		hud.show_toast(text, 2.5, true)
