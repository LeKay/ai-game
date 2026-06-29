class_name TasksDrawerContent extends DrawerContentBase
## Content node for the Delivery Tasks edge drawer.
##
## Renders the task list (header + scrollable cards) inside the panel managed by
## EdgeDrawerController. This class owns only the content logic — no tab, no slide
## animation, no layer management. Those concerns belong to EdgeDrawerController.
##
## Each task card shows required-item tiles (greyed until the player holds enough,
## then highlighted green) and a reward tile, with a Complete button that enables
## once all requirements are met.
##
## Pure renderer of TaskSystem + ProgressionSystem state (see .claude/rules/ui-code.md):
## the Complete button calls TaskSystem.complete_task(); points come from ProgressionSystem.
##
## See design/quick-specs/delivery-task-system-2026-06-20.md.

## Emitted whenever the badge text / colour changes. EdgeDrawerController (or the
## wrapping TaskDialog) should connect this to controller.set_badge().
signal badge_updated(text: String, color: Color)

# --- Visual constants --------------------------------------------------------

const PANEL_COLOR := Color(0.12, 0.13, 0.16, 1.0)
const TAB_COLOR := Color(0.16, 0.17, 0.21, 1.0)
const CARD_COLOR := Color(0.16, 0.17, 0.21, 1.0)
const TILE_COLOR := Color(0.10, 0.11, 0.14, 1.0)
const TEXT_COLOR := Color("#F0EDE6")
const MUTED_COLOR := Color(0.6, 0.62, 0.66)
const MET_COLOR := Color(0.45, 0.85, 0.45)
const UNMET_COLOR := Color(0.85, 0.45, 0.45)
const ACCENT_COLOR := Color("#E8C15A")  # progression-point accent (generic)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)

## Generic glyph for a progression point (no bespoke icon asset — see design decision 7).
const POINT_GLYPH := "✦"

const TILE_SIZE := Vector2(64, 74)

# --- Content node references -------------------------------------------------

var _points_label: Label
var _task_list: VBoxContainer
var _empty_label: Label


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	# Build the panel content as our single child; the controller wraps it in
	# its own PanelContainer, so we just fill with margin + content.
	var panel := _build_panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	_connect_signals()
	_update_badge()


# --- DrawerContentBase API ---------------------------------------------------

## Refreshes the badge. Call after external state changes (e.g. save load).
func refresh() -> void:
	_update_badge()


## Called by EdgeDrawerController when the drawer slides open.
func on_drawer_opened() -> void:
	_rebuild()


## Called by EdgeDrawerController when the drawer slides closed.
func on_drawer_closed() -> void:
	pass  # no teardown needed


## This content has no internal sub-state that captures ESC.
func wants_escape_handled() -> bool:
	return false


## This content does not consume ESC — the controller closes the drawer instead.
func handle_escape() -> bool:
	return false


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
	_update_badge()
	_rebuild()


func _on_points_changed(total: int) -> void:
	if _points_label != null:
		_points_label.text = "%s %d" % [POINT_GLYPH, total]


# --- Badge -------------------------------------------------------------------

## Recomputes the edge-tab badge (active-task count, green when completable) and
## emits badge_updated so the controller can forward it to EdgeDrawerTab.
func _update_badge() -> void:
	var active: Array[StringName] = TaskSystem.get_active_tasks()
	if active.is_empty():
		badge_updated.emit("", MUTED_COLOR)
		return
	var completable := 0
	for node_id: StringName in active:
		if TaskSystem.is_fulfilled(node_id):
			completable += 1
	var color := MET_COLOR if completable > 0 else MUTED_COLOR
	badge_updated.emit(str(active.size()), color)


# --- Task list ---------------------------------------------------------------

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


# --- UI construction ---------------------------------------------------------

## The slide-in panel content: header + scrollable task list.
## No tab, no slider — those belong to EdgeDrawerController.
func _build_panel() -> Control:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	return margin


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
	close_btn.pressed.connect(func() -> void: request_close.emit())
	header.add_child(close_btn)

	return header


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
		if req.get("kind", TaskSystem.REQ_RESOURCE) == TaskSystem.REQ_BUILDING:
			row.add_child(_build_building_tile(int(req["building"]), int(req["amount"])))
		else:
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


## A "Kachel" for a building requirement: building icon (or 🏛 fallback) + built/need count.
## Greyed (disabled) until enough of the building type have been built, then highlighted green.
func _build_building_tile(building_type: int, need: int) -> Control:
	var have: int = TaskSystem.get_built_count(building_type)
	var met: bool = have >= need

	var tile := PanelContainer.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.tooltip_text = "Build: %s" % BuildingRegistry.get_type_display_name(building_type)
	tile.add_theme_stylebox_override("panel", _flat(TILE_COLOR, 6, MET_COLOR if met else Color.TRANSPARENT))
	tile.modulate = Color.WHITE if met else Color(1, 1, 1, 0.5)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	tile.add_child(vbox)

	var texture: Texture2D = BuildingRegistry.get_building_texture(building_type)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	else:
		var glyph := Label.new()
		glyph.text = "🏛"
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


# --- Styleboxes --------------------------------------------------------------

## Builds a flat rounded panel stylebox, optionally with a 2px coloured border.
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
