class_name ItemTile extends VBoxContainer
## Tile that displays a single resource stack.
## Layout:
##   ┌──────────┐
##   │  [icon]  │  ← DrawerTile card (icon + "x4" in label slot, no badge)
##   │   x4     │
##   └──────────┘
##    Wood Plank   ← name label below the card
##
## Emits one of three drag signals depending on [member _container_type].

# ── Signals ───────────────────────────────────────────────────────────────────

signal storage_drag_started(resource_id: StringName, container_id: StringName, tile_pos: Vector2i)
signal input_drag_started(resource_id: StringName, building_id: String, tile_pos: Vector2i)
signal output_drag_started(resource_id: StringName, building_id: String, tile_pos: Vector2i)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_NAME := Color(0.70, 0.70, 0.74, 1.0)

# ── Node refs ─────────────────────────────────────────────────────────────────

var _tile: DrawerTile
var _name_label: Label

# ── State ─────────────────────────────────────────────────────────────────────

var _resource_id: StringName = &""
var _container_type: String = "storage"
var _container_id: StringName = &""
var _building_id: String = ""
var _tile_pos: Vector2i = Vector2i.ZERO
var _quantity: int = 0

## Set to the tile being held for drag; null once mouse leaves the tile.
## DragController reads this to gate panel-drag batch collection.
static var active_drag_source: ItemTile = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override("separation", 2)

	_tile = DrawerTile.new()
	_tile.pressed.connect(_on_pressed)
	add_child(_tile)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", COLOR_NAME)
	_name_label.custom_minimum_size  = Vector2(DrawerTile.TILE_SIZE.x, 0)
	_name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_name_label)


# ── Public API ────────────────────────────────────────────────────────────────

func setup(
		resource_id: StringName,
		quantity: int,
		container_type: String,
		owner_id: String,
		tile_pos: Vector2i) -> void:
	_resource_id    = resource_id
	_container_type = container_type
	_tile_pos       = tile_pos

	match container_type:
		"storage": _container_id = StringName(owner_id)
		_:         _building_id  = owner_id

	# Icon
	var tex: Texture2D = ResourceRegistry.get_icon_texture(resource_id, 28)
	if tex != null:
		_tile.set_icon_texture(tex)
	else:
		_tile.set_icon_glyph(ResourceRegistry.get_glyph(resource_id))

	_quantity = quantity
	# Quantity in the label slot ("x4"), no badge
	_tile.set_label("x%d" % quantity)
	_tile.set_badge("", Color.WHITE)

	# Resource name below the card
	var def: ResourceRegistry._ResourceDefinition = ResourceRegistry.get_definition(resource_id)
	_name_label.text = def.display_name if def != null else str(resource_id)

	if not _tile.pressed.is_connected(_on_pressed):
		_tile.pressed.connect(_on_pressed)


## Updates only the quantity label — cheaper than a full setup() during refresh.
func update_quantity(quantity: int) -> void:
	_quantity = quantity
	_tile.set_label("x%d" % quantity)


# ── Input ─────────────────────────────────────────────────────────────────────

func _on_pressed() -> void:
	ItemTile.active_drag_source = self
	_tile.mouse_exited.connect(_on_tile_mouse_exited, CONNECT_ONE_SHOT)
	match _container_type:
		"storage": storage_drag_started.emit(_resource_id, _container_id, _tile_pos)
		"input":   input_drag_started.emit(_resource_id, _building_id, _tile_pos)
		"output":  output_drag_started.emit(_resource_id, _building_id, _tile_pos)


func _on_tile_mouse_exited() -> void:
	if ItemTile.active_drag_source == self:
		ItemTile.active_drag_source = null
