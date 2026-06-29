class_name BuildingListView extends Control
## Displays the player's placed buildings as a tile grid inside the Buildings Drawer.
## The first tile is always a "+" add-building tile. Subsequent tiles are BuildingTiles,
## one per placed building, excluding Residential Houses and Road segments.
##
## See: docs/superpowers/buildings-drawer-ui-design.md

signal plus_tile_pressed()
signal building_tile_pressed(building_id: String)
signal close_pressed()

## Building types excluded from the list (shelter / infrastructure).
const EXCLUDED_TYPES: Array[int] = [
	BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE,
	BuildingRegistry.BuildingType.ROAD,
	BuildingRegistry.BuildingType.BRIDGE,
]

const COLOR_TEXT := Color(0.85, 0.85, 0.85, 1.0)

var _scroll: ScrollContainer
var _flow: TileFlowContainer
var _building_tiles: Array[BuildingTile] = []


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# ── Header ────────────────────────────────────────────────────────────────
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left",   18)
	header_margin.add_theme_constant_override("margin_right",  18)
	header_margin.add_theme_constant_override("margin_top",    18)
	header_margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(header_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_margin.add_child(header)

	var title := Label.new()
	title.text = "Buildings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = "Close (Esc)"
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close_btn)

	# ── Scrollable tile grid ──────────────────────────────────────────────────
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_flow = TileFlowContainer.new()
	_flow.name = "TileFlow"
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_flow)

	TickSystem.ticks_advanced.connect(_on_ticks_advanced)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
			TickSystem.ticks_advanced.disconnect(_on_ticks_advanced)


func _on_ticks_advanced(_delta: int) -> void:
	for tile: BuildingTile in _building_tiles:
		if is_instance_valid(tile):
			tile.refresh()


## Rebuilds the tile list from the current BuildingRegistry state.
## Called each time the drawer opens or whenever state changes warrant a visual update.
func refresh() -> void:
	_flow.clear_tiles()
	_building_tiles.clear()

	# Plus tile is recreated each refresh so clear_tiles() cannot free a kept reference.
	var plus_tile := DrawerTile.new()
	plus_tile.name = "PlusTile"
	plus_tile.pressed.connect(func() -> void: plus_tile_pressed.emit())
	_flow.add_tile(plus_tile)  # add_child triggers _ready() — must come before setup calls
	plus_tile.set_plus_glyph(true)
	plus_tile.set_label("Build")

	var buildings := BuildingRegistry.get_all_buildings()
	for instance: BuildingRegistry.BuildingInstance in buildings:
		if EXCLUDED_TYPES.has(instance.type):
			continue
		_add_building_tile(instance)


# --- Internals ----------------------------------------------------------------

func _add_building_tile(instance: BuildingRegistry.BuildingInstance) -> void:
	var tile := BuildingTile.new()
	tile.name = "Tile_%s" % instance.building_id

	# Connect before entering the tree so signals are active from the first frame.
	var bid := instance.building_id
	tile.pressed.connect(func() -> void: _on_building_tile_pressed(bid))

	_flow.add_tile(tile)
	_building_tiles.append(tile)

	# setup() uses BuildingRegistry calls, so we defer until the tile is in the tree.
	tile.setup(bid)

	# Under-construction tiles: add a tooltip.
	if instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
		var total: int = instance.build_time
		var pct: int = int(float(instance.accumulated_ticks) / float(total) * 100.0) \
				if total > 0 else 100
		tile.tooltip_text = "Under construction (%d%%) — click to inspect" % pct


func _on_building_tile_pressed(building_id: String) -> void:
	building_tile_pressed.emit(building_id)
