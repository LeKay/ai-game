class_name WildOverlay extends Node2D
## Draws a small deer marker in the corner of each tile that holds a wild group.
## Rebuilds on WildSystem.wild_changed. ADR-0015 (Map Fertility System).

const MARKER_SIZE: float = 18.0

var _grid: Node = null
var _deer_texture: Texture2D = null
var _markers: Array[Node2D] = []


func _ready() -> void:
	z_index = 4
	if ResourceLoader.exists("res://assets/ui/icons/various/ui_icon_wild_deer.png"):
		_deer_texture = load("res://assets/ui/icons/various/ui_icon_wild_deer.png")
	WildSystem.wild_changed.connect(_refresh)


## Sets the WorldGrid used for tile→world conversion and draws the current groups.
func init_dependencies(grid: Node) -> void:
	_grid = grid
	_refresh()


func _refresh() -> void:
	for m: Node2D in _markers:
		m.queue_free()
	_markers.clear()
	if _grid == null:
		return
	var half: float = float(WorldGrid.TILE_SIZE) * 0.5
	for tile: Vector2i in WildSystem.get_group_tiles():
		var marker: Node2D = _make_marker()
		var center: Vector2 = _grid.tile_to_world(tile)
		# Upper-right corner of the tile.
		marker.position = center + Vector2(half - MARKER_SIZE * 0.5, -half + MARKER_SIZE * 0.5)
		add_child(marker)
		_markers.append(marker)


func _make_marker() -> Node2D:
	var container := Node2D.new()
	container.z_index = 6
	var backdrop := Sprite2D.new()
	backdrop.texture = TextureFactory.circle(int(MARKER_SIZE * 0.5), Color(0.0, 0.0, 0.0, 0.45))
	container.add_child(backdrop)
	if _deer_texture != null:
		var spr := Sprite2D.new()
		spr.texture = _deer_texture
		var ts: Vector2 = _deer_texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			spr.scale = Vector2(MARKER_SIZE / ts.x, MARKER_SIZE / ts.y)
		container.add_child(spr)
	else:
		# Fallback dot until the deer asset is generated.
		var dot := Sprite2D.new()
		dot.texture = TextureFactory.circle(int(MARKER_SIZE * 0.35), Color(0.43, 0.32, 0.14, 1.0))
		container.add_child(dot)
	return container
