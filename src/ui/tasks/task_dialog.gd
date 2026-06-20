class_name TaskDialog extends CanvasLayer
## Player-facing Delivery Tasks overlay. Lists every active task as a card showing the
## required-item tiles (each disabled until the player holds enough, then active) and the
## reward tile, with a Complete button that enables once all requirements are met.
##
## Pure renderer of TaskSystem + ProgressionSystem state (see .claude/rules/ui-code.md):
## the Complete button calls TaskSystem.complete_task(); points come from ProgressionSystem.
##
## See design/quick-specs/delivery-task-system-2026-06-20.md.

const BG_COLOR := Color(0.05, 0.06, 0.08, 0.92)
const PANEL_COLOR := Color(0.12, 0.13, 0.16, 1.0)
const CARD_COLOR := Color(0.16, 0.17, 0.21, 1.0)
const TILE_COLOR := Color(0.10, 0.11, 0.14, 1.0)
const TEXT_COLOR := Color("#F0EDE6")
const MUTED_COLOR := Color(0.6, 0.62, 0.66)
const MET_COLOR := Color(0.45, 0.85, 0.45)
const UNMET_COLOR := Color(0.85, 0.45, 0.45)
const ACCENT_COLOR := Color("#E8C15A")  # progression-point accent (generic)

## Generic glyph for a progression point (no bespoke icon asset — see design decision 7).
const POINT_GLYPH := "✦"

const TILE_SIZE := Vector2(64, 74)

var _points_label: Label
var _task_list: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	layer = 21  # above the Progression Tree overlay (layer 20)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()


# --- Open / close ------------------------------------------------------------

func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- Signals -----------------------------------------------------------------

func _connect_signals() -> void:
	if not TaskSystem.task_granted.is_connected(_on_tasks_changed):
		TaskSystem.task_granted.connect(_on_tasks_changed)
	if not TaskSystem.task_completed.is_connected(_on_tasks_changed):
		TaskSystem.task_completed.connect(_on_tasks_changed)
	if not TaskSystem.task_updated.is_connected(_on_tasks_changed):
		TaskSystem.task_updated.connect(_on_tasks_changed)
	if not ProgressionSystem.points_changed.is_connected(_on_points_changed):
		ProgressionSystem.points_changed.connect(_on_points_changed)


func _on_tasks_changed(_node_id: StringName) -> void:
	if visible:
		_rebuild()


func _on_points_changed(total: int) -> void:
	if _points_label != null:
		_points_label.text = "%s %d" % [POINT_GLYPH, total]


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks reaching the game
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat(PANEL_COLOR, 10))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_task_list = VBoxContainer.new()
	_task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_task_list)

	_empty_label = Label.new()
	_empty_label.text = "No active tasks. Unlock a node in the Progression Tree to receive one."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_color_override("font_color", MUTED_COLOR)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_task_list.add_child(_empty_label)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Tasks"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_points_label = Label.new()
	_points_label.text = "%s %d" % [POINT_GLYPH, ProgressionSystem.progression_points]
	_points_label.tooltip_text = "Progression points — spend to unlock nodes"
	_points_label.add_theme_font_size_override("font_size", 20)
	_points_label.add_theme_color_override("font_color", ACCENT_COLOR)
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_points_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = "Close (Esc)"
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	return header


# --- Task list rebuild -------------------------------------------------------

func _rebuild() -> void:
	if _task_list == null:
		return
	for child: Node in _task_list.get_children():
		if child != _empty_label:
			child.queue_free()

	var active: Array[StringName] = TaskSystem.get_active_tasks()
	_empty_label.visible = active.is_empty()
	for node_id: StringName in active:
		_task_list.add_child(_build_card(node_id))


func _build_card(node_id: StringName) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _flat(CARD_COLOR, 8))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = TaskSystem.get_task_title(node_id)
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(title)

	# Single row: required-item tiles left-aligned, then (space-between) the reward tile
	# and a slightly smaller Complete button to its right.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	for req: Dictionary in TaskSystem.get_requirements(node_id):
		row.add_child(_build_requirement_tile(req["resource"], int(req["amount"])))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var reward_tile := _build_reward_tile(TaskSystem.get_reward(node_id))
	reward_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(reward_tile)

	var complete_btn := Button.new()
	complete_btn.text = "Complete"
	complete_btn.custom_minimum_size = Vector2(96, 30)
	complete_btn.focus_mode = Control.FOCUS_NONE
	complete_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	complete_btn.disabled = not TaskSystem.is_fulfilled(node_id)
	if complete_btn.disabled:
		complete_btn.tooltip_text = "Gather all required goods first"
	complete_btn.pressed.connect(_on_complete_pressed.bind(node_id))
	row.add_child(complete_btn)

	return card


## A "Kachel" for one required resource: glyph + have/need count. Greyed (disabled) until
## the player holds enough, then highlighted (active) with a green count.
func _build_requirement_tile(resource: StringName, need: int) -> Control:
	var have: int = TaskSystem.get_have(resource)
	var met: bool = have >= need

	var tile := PanelContainer.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.tooltip_text = ResourceRegistry.get_definition(resource).display_name \
			if ResourceRegistry.get_definition(resource) != null else str(resource)
	tile.add_theme_stylebox_override("panel", _flat(TILE_COLOR, 6, MET_COLOR if met else Color.TRANSPARENT))
	tile.modulate = Color.WHITE if met else Color(1, 1, 1, 0.5)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(vbox)

	var glyph := Label.new()
	glyph.text = ResourceRegistry.get_glyph(resource)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 28)
	vbox.add_child(glyph)

	var count := Label.new()
	count.text = "%d/%d" % [have, need]
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 13)
	count.add_theme_color_override("font_color", MET_COLOR if met else UNMET_COLOR)
	vbox.add_child(count)

	return tile


## A "Kachel" for the task reward, rendered from the reward type. progression_point uses the
## generic point glyph; future reward types render their own resource glyph without UI changes.
func _build_reward_tile(reward: Dictionary) -> Control:
	var glyph_text: String = POINT_GLYPH
	var amount: int = int(reward.get("amount", 1))
	match str(reward.get("type", "")):
		"progression_point":
			glyph_text = POINT_GLYPH
		"resource":
			glyph_text = ResourceRegistry.get_glyph(StringName(str(reward.get("resource", ""))))
		_:
			glyph_text = "?"

	var tile := PanelContainer.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.add_theme_stylebox_override("panel", _flat(TILE_COLOR, 6, ACCENT_COLOR))

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(vbox)

	var glyph := Label.new()
	glyph.text = glyph_text
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 28)
	glyph.add_theme_color_override("font_color", ACCENT_COLOR)
	vbox.add_child(glyph)

	var count := Label.new()
	count.text = "+%d" % amount
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 13)
	count.add_theme_color_override("font_color", ACCENT_COLOR)
	vbox.add_child(count)

	return tile


func _on_complete_pressed(node_id: StringName) -> void:
	TaskSystem.complete_task(node_id)  # task_completed/points_changed signals refresh the UI


# --- Helpers -----------------------------------------------------------------

## Builds a flat rounded panel stylebox, optionally with a 2px colored border.
func _flat(bg: Color, radius: int, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	return sb
