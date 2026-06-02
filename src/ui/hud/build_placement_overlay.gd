class_name BuildPlacementOverlay extends CanvasLayer
## Ghost overlay for building placement mode.
## Activates via InventoryScreen.build_mode_requested signal (found via "inventory_screen" group).
## Draws a coloured tile highlight snapped to the world grid.
## Left-click places; ESC or right-click cancels. Opening inventory also cancels.

const TILE_SIZE := WorldGrid.TILE_SIZE

## Blue tint when placement is valid, red when blocked.
const COLOR_VALID   := Color(0.4, 0.65, 1.0, 0.65)
const COLOR_INVALID := Color(1.0, 0.3,  0.3, 0.65)
## Highlights tiles that satisfy an adjacency requirement (e.g. TREE for Lumber Camp).
const COLOR_HINT    := Color(1.0, 0.85, 0.1, 0.35)

var _active:        bool = false
var _building_type: int  = -1

var _ghost: TextureRect
var _label: Label
var _hint_rects: Array[ColorRect] = []


func _ready() -> void:
	layer   = 5
	visible = false
	_build_ghost()
	_connect_inventory_screen()


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

	for i in range(4):
		var hr := ColorRect.new()
		hr.name         = "HintRect%d" % i
		hr.color        = COLOR_HINT
		hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hr.visible      = false
		add_child(hr)
		_hint_rects.append(hr)


func _connect_inventory_screen() -> void:
	var nodes := get_tree().get_nodes_in_group(&"inventory_screen")
	for node: Node in nodes:
		if node.has_signal(&"build_mode_requested"):
			node.build_mode_requested.connect(start_placement)
		if node.has_signal(&"inventory_opened"):
			node.inventory_opened.connect(_cancel)
		break


## Activates ghost placement for the given building type.
func start_placement(building_type: int) -> void:
	_active        = true
	_building_type = building_type
	var tex_path: String = BuildingRegistry.BUILDING_TEXTURES.get(
		building_type, "res://assets/art/tiles/bld_tile_storage.png")
	_ghost.texture = load(tex_path)
	visible        = true


func _cancel() -> void:
	_active        = false
	_building_type = -1
	visible        = false


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

	var result := BuildingRegistry.check_build_conditions(_building_type, tile)
	_ghost.modulate = COLOR_VALID if result == BuildingRegistry.PlacementResult.SUCCESS else COLOR_INVALID
	match result:
		BuildingRegistry.PlacementResult.SUCCESS:
			_label.text = "Click to place"
		BuildingRegistry.PlacementResult.INSUFFICIENT_RESOURCES:
			_label.text = "Not enough resources"
		BuildingRegistry.PlacementResult.INSUFFICIENT_ENERGY:
			_label.text = "Not enough energy"
		BuildingRegistry.PlacementResult.BLOCKED_BY_ADJACENCY:
			_label.text = _adjacency_hint_label(_building_type)
		_:
			_label.text = "Cannot place here"

	_update_hint_tiles(tile, zoom)


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
		if BuildingRegistry.check_build_conditions(_building_type, tile) == BuildingRegistry.PlacementResult.SUCCESS:
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
