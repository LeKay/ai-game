class_name NpcListView extends Control
## Displays the player's recruited workers as a tile grid inside the NPCs Drawer.
## Mirrors BuildingListView: header + scrollable tile grid. Tiles are rendered by the
## reusable NpcGrid component; clicking one opens the detail view.
##
## See: building_list_view.gd (structural template) and design/gdd/buildings-drawer.md

signal npc_tile_pressed(npc_id: StringName)
signal close_pressed()

const COLOR_TEXT := Color(0.85, 0.85, 0.85, 1.0)

var _grid: NpcGrid


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
	title.text = "Workers"
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
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var grid_margin := MarginContainer.new()
	grid_margin.add_theme_constant_override("margin_left",   18)
	grid_margin.add_theme_constant_override("margin_right",  18)
	grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_margin)

	_grid = NpcGrid.new()
	_grid.name = "NpcGrid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.npc_clicked.connect(func(npc_id: StringName) -> void: npc_tile_pressed.emit(npc_id))
	grid_margin.add_child(_grid)


## Rebuilds the tile list from the current NPCSystem state.
func refresh() -> void:
	if _grid == null:
		return
	_grid.populate(_npc_list())


func _npc_list() -> Array[Dictionary]:
	var npc_sys: Node = NPCSystem
	if npc_sys == null:
		return []
	var result: Array[Dictionary] = []
	for npc_id: StringName in npc_sys.all_npcs:
		var npc: Object = npc_sys.get_npc_instance(npc_id)
		var level: int = npc.level if npc != null else 1
		var total_xp: int = npc.xp if npc != null else 0
		result.append({
			&"npc_id": npc_id,
			&"state": npc_sys.get_npc_state(npc_id),
			&"display_name": npc_sys.get_npc_display_name(npc_id),
			&"job": npc_sys.get_npc_job_name(npc_id),
			&"level": level,
			&"xp_into_level": ExperienceFormulas.xp_into_level(total_xp, level),
			&"xp_span": ExperienceFormulas.xp_span_of_level(level),
			&"warnings": NpcGrid.build_npc_warnings(npc_id, npc),
		})
	return result
