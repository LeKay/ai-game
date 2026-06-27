class_name BuildPickerView extends Control
## Picker view shown when the player taps "+ Build" in the Buildings Drawer.
## Lists every unlocked, player-buildable building type as a DrawerTile grid.
## Infrastructure types (ROAD, BRIDGE, RESIDENTIAL_HOUSE) are excluded — they are
## placed via dedicated tools, not this picker.
##
## Navigation:
##   back_pressed            — user tapped "← Back"; parent should return to BuildingListView.
##   building_type_selected  — user chose a type; parent should request build mode.
##
## See: docs/superpowers/buildings-drawer-ui-design.md

## Emitted when the "← Back" button is pressed.
signal back_pressed()
## Emitted when the player taps the ✕ close button.
signal close_pressed()
## Emitted when the player taps a building type tile.
signal building_type_selected(building_type: int)
## Emitted when the player taps the Demolish tile.
signal demolish_mode_requested()

## Building types that must never appear in the picker (infrastructure only).
const EXCLUDED_TYPES: Array[int] = [
	BuildingRegistry.BuildingType.ROAD,
	BuildingRegistry.BuildingType.BRIDGE,
]

var _flow: TileFlowContainer


const COLOR_ACCENT    := Color(0.30, 0.70, 1.00, 1.0)
const COLOR_TEXT      := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_SEPARATOR := Color(0.25, 0.26, 0.30, 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "RootVBox"
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# Top spacer
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 8)
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(top_spacer)

	# Back bar — matches BuildingDetailView._build_back_bar()
	var bar := HBoxContainer.new()
	bar.name = "BackBar"
	bar.custom_minimum_size = Vector2(0, 28)
	bar.add_theme_constant_override("separation", 4)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.14, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)

	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "← Back"
	back_btn.flat = true
	back_btn.add_theme_font_size_override("font_size", 12)
	back_btn.add_theme_color_override("font_color", COLOR_ACCENT)
	back_btn.add_theme_color_override("font_hover_color", COLOR_TEXT)
	back_btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_on_back_pressed)
	bar.add_child(back_btn)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.tooltip_text = "Close (Esc)"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.add_theme_color_override("font_color", COLOR_TEXT)
	close_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	close_btn.custom_minimum_size = Vector2(36, 28)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func() -> void: close_pressed.emit())
	bar.add_child(close_btn)
	root_vbox.add_child(bar)

	# Separator
	var sep := HSeparator.new()
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = COLOR_SEPARATOR
	sep_sb.content_margin_top    = 0
	sep_sb.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_sb)
	root_vbox.add_child(sep)

	# Scrollable tile grid
	var scroll := ScrollContainer.new()
	scroll.name                   = "Scroll"
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	_flow = TileFlowContainer.new()
	_flow.name = "TileFlow"
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(_flow)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			if visible:
				if not InventorySystem.storage_changed.is_connected(_on_storage_changed):
					InventorySystem.storage_changed.connect(_on_storage_changed)
			else:
				if InventorySystem.storage_changed.is_connected(_on_storage_changed):
					InventorySystem.storage_changed.disconnect(_on_storage_changed)
		NOTIFICATION_EXIT_TREE:
			if InventorySystem.storage_changed.is_connected(_on_storage_changed):
				InventorySystem.storage_changed.disconnect(_on_storage_changed)


func _on_storage_changed(_container_id: StringName) -> void:
	if visible:
		refresh()


## Rebuilds the tile grid from the current registry / progression state.
## Call each time the view becomes visible so unlocks are reflected immediately.
func refresh() -> void:
	_flow.clear_tiles()

	for btype: int in BuildingRegistry.BUILDABLE_TYPES:
		if EXCLUDED_TYPES.has(btype):
			continue
		if not ProgressionSystem.is_building_unlocked(btype):
			continue
		_add_type_tile(btype)

	_add_path_tile()
	_add_demolish_tile()


# --- Internals ----------------------------------------------------------------

func _add_type_tile(btype: int) -> void:
	var cost: Dictionary = BuildingRegistry.get_effective_build_cost(btype)
	var affordable: bool = _can_afford(cost)

	var tile := DrawerTile.new()
	tile.name = "Tile_%d" % btype
	_flow.add_tile(tile)

	var tex: Texture2D = BuildingRegistry.get_building_texture(btype)
	if tex != null:
		tile.set_icon_texture(tex)
	else:
		tile.set_icon_glyph(_building_glyph(btype))

	tile.set_label(BuildingRegistry.get_type_display_name(btype))
	tile.tooltip_text = _cost_tooltip(cost)

	if affordable:
		tile.set_state(DrawerTile.TileState.NORMAL)
		tile.pressed.connect(func() -> void: building_type_selected.emit(btype))
	else:
		tile.set_state(DrawerTile.TileState.DISABLED)


func _can_afford(cost: Dictionary) -> bool:
	for res_id: StringName in cost:
		if InventorySystem.get_global_quantity(res_id) < cost[res_id]:
			return false
	return true


func _cost_tooltip(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free to place"
	var lines: PackedStringArray = PackedStringArray()
	for res_id: StringName in cost:
		var have: int = InventorySystem.get_global_quantity(res_id)
		var need: int = cost[res_id]
		lines.append("%s %d/%d" % [res_id, have, need])
	return "\n".join(lines)


func _building_glyph(btype: int) -> String:
	match btype:
		BuildingRegistry.BuildingType.COLLECTION_POINT:   return "📦"
		BuildingRegistry.BuildingType.STORAGE_BUILDING:   return "🏗️"
		BuildingRegistry.BuildingType.LUMBER_CAMP:        return "🪚"
		BuildingRegistry.BuildingType.STONE_MASON:        return "⛏️"
		BuildingRegistry.BuildingType.GATHERING_HUT:      return "🧺"
		BuildingRegistry.BuildingType.TOOL_WORKSHOP:      return "🔨"
		BuildingRegistry.BuildingType.WEAVER:             return "🧶"
		BuildingRegistry.BuildingType.TAILOR:             return "✂️"
		BuildingRegistry.BuildingType.SAWMILL:            return "🪚"
		BuildingRegistry.BuildingType.HUNTING_LODGE:      return "🦌"
		BuildingRegistry.BuildingType.FARM:               return "🌾"
		BuildingRegistry.BuildingType.MILL:               return "⚙️"
		BuildingRegistry.BuildingType.BAKERY:             return "🥖"
		BuildingRegistry.BuildingType.CLAY_PIT:           return "🧱"
		BuildingRegistry.BuildingType.POTTERY_KILN:       return "🏺"
		BuildingRegistry.BuildingType.TANNERY:            return "🪣"
		BuildingRegistry.BuildingType.BOWYERS_WORKSHOP:   return "🏹"
		BuildingRegistry.BuildingType.CARPENTER:          return "🪑"
		BuildingRegistry.BuildingType.FISHING_HUT:        return "🎣"
		BuildingRegistry.BuildingType.BRICK_KILN:         return "🔥"
		BuildingRegistry.BuildingType.CHARCOAL_KILN:      return "⬛"
		BuildingRegistry.BuildingType.SALT_WORKS:         return "🧂"
		BuildingRegistry.BuildingType.PRESERVATION_HOUSE: return "🥫"
		BuildingRegistry.BuildingType.COOPERAGE:          return "🛢️"
		BuildingRegistry.BuildingType.WHEEL_MAKER:        return "🛞"
		BuildingRegistry.BuildingType.CART_WORKSHOP:      return "🛒"
		BuildingRegistry.BuildingType.TRADING_POST:       return "🏪"
	return "🏛️"


func _add_path_tile() -> void:
	var tile := DrawerTile.new()
	tile.name = "PathTile"
	_flow.add_tile(tile)
	var tex: Texture2D = BuildingRegistry.get_building_texture(BuildingRegistry.BuildingType.ROAD)
	if tex != null:
		tile.set_icon_texture(tex)
	else:
		tile.set_icon_glyph("🛤️")
	tile.set_label(BuildingRegistry.get_type_display_name(BuildingRegistry.BuildingType.ROAD))
	tile.tooltip_text = "Free to place"
	tile.set_state(DrawerTile.TileState.NORMAL)
	tile.pressed.connect(func() -> void:
		building_type_selected.emit(BuildingRegistry.BuildingType.ROAD))


func _add_demolish_tile() -> void:
	var tile := DrawerTile.new()
	tile.name = "DemolishTile"
	_flow.add_tile(tile)
	tile.set_icon_glyph("🗑️")
	tile.set_label("Demolish")

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.28, 0.10, 0.10, 1.0)
	sb.corner_radius_top_left     = 4
	sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_left  = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left   = 4
	sb.content_margin_right  = 4
	sb.content_margin_top    = 6
	sb.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", sb)
	tile.set_state(DrawerTile.TileState.NORMAL)
	tile.pressed.connect(func() -> void: demolish_mode_requested.emit())


# --- Signal handlers ----------------------------------------------------------

func _on_back_pressed() -> void:
	back_pressed.emit()
