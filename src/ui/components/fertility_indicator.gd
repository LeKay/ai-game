class_name FertilityIndicator extends CanvasLayer
## Shows the map's fertilities as small icon circles in the top-right corner, under the HUD.
## Read-only display, built once from WorldGrid.get_fertility(). ADR-0015 (Map Fertility System).
## Icon mapping: clay → clay overlay, wheat → wheat overlay, wild → deer marker
## (same icon the forest overlay uses; the "wild" fertility has no resource entry).

const CIRCLE_R: int = 16
const SEPARATION: int = 8
const MARGIN_RIGHT: float = 16.0
const MARGIN_TOP: float = 56.0   ## sits below the HUD's top bar

var _grid: Node = null


func _ready() -> void:
	layer = 50


## Sets the WorldGrid and builds the indicator. Call after the map's fertility is set
## (after generate() / load).
func init_dependencies(grid: Node) -> void:
	_grid = grid
	_rebuild()


func _rebuild() -> void:
	for c: Node in get_children():
		c.queue_free()
	if _grid == null:
		return
	var ferts: Array = _grid.get_fertility()
	if ferts.is_empty():
		return
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", SEPARATION)
	hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hbox.offset_right = -MARGIN_RIGHT
	hbox.offset_top = MARGIN_TOP
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hbox)
	for fid: StringName in ferts:
		hbox.add_child(_make_circle(fid))


func _make_circle(fid: StringName) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(CIRCLE_R * 2, CIRCLE_R * 2)
	c.tooltip_text = str(fid).capitalize()
	var bg := TextureRect.new()
	bg.texture = TextureFactory.circle(CIRCLE_R, Color(0.0, 0.0, 0.0, 0.55))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(bg)
	# wild has no resource entry — use the same deer marker the forest overlay shows.
	var tex: Texture2D
	if fid == &"wild":
		const DEER := "res://assets/ui/icons/various/ui_icon_wild_deer.png"
		tex = (load(DEER) as Texture2D) if ResourceLoader.exists(DEER) else TextureFactory.circle(CIRCLE_R, Color(0.43, 0.32, 0.14))
	else:
		tex = ResourceRegistry.get_icon_texture(fid, CIRCLE_R)
	if tex != null:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 4
		ic.offset_top = 4
		ic.offset_right = -4
		ic.offset_bottom = -4
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(ic)
	return c
