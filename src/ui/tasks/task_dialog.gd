class_name TaskDialog extends CanvasLayer
## Player-facing Delivery Tasks drawer. A slim tab clings to the right screen edge; hovering it
## slides a non-modal panel in from the right (peek), and clicking the tab pins it open so the
## player can scroll and complete tasks without keeping the mouse on it. Each task is a card
## showing the required-item tiles (disabled until the player holds enough, then active) and the
## reward tile, with a Complete button that enables once all requirements are met.
##
## Open/close model: hover-peek + click-pin (non-modal — the game stays visible behind it).
##   - mouse enters tab          -> slide in (peek)
##   - mouse leaves tab+panel     -> slide out after CLOSE_DELAY (unless pinned)
##   - click tab / 📋 HUD button  -> toggle pin (stays open / closes immediately)
##   - ✕ or Esc                   -> unpin + close
##
## Pure renderer of TaskSystem + ProgressionSystem state (see .claude/rules/ui-code.md):
## the Complete button calls TaskSystem.complete_task(); points come from ProgressionSystem.
##
## See design/quick-specs/delivery-task-system-2026-06-20.md.

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

# --- Drawer geometry & timing ------------------------------------------------
const TAB_WIDTH := 44.0       # width of the always-visible edge tab
const TAB_HEIGHT := 96.0
## Distance of the tab's top from the screen top. Sits below the fertility indicators (top-right,
## roughly y 56–88; see fertility_indicator.gd MARGIN_TOP + circle height) with a small gap.
const TAB_TOP_MARGIN := 104.0
const PANEL_WIDTH := 520.0    # width of the slide-in panel
const SLIDE_TIME := 0.2       # seconds for the slide tween
const CLOSE_DELAY := 0.25     # grace period before an un-pinned drawer slides out
## Set true to skip the slide animation (motion-accessibility — see ui-code.md).
const REDUCE_MOTION := false

var _points_label: Label
var _task_list: VBoxContainer
var _empty_label: Label

var _slider: Control          # moving group [tab | panel], anchored to the right edge
var _tab_badge: Label
var _slide := 0.0             # 0 = closed (tab peeks), 1 = open (panel visible)
var _target_open := false    # current slide target (independent of _pinned)
var _pinned := false         # stays open regardless of hover
var _slide_tween: Tween
var _close_timer := 0.0


func _ready() -> void:
	layer = 21  # above the Progression Tree overlay (layer 20)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true  # the tab is always on screen
	_build_ui()
	_apply_slide(0.0)
	_update_badge()
	_connect_signals()
	set_process(true)


# --- Open / close (pin control) ----------------------------------------------

func open() -> void:
	_pinned = true
	_set_target(true)


func close() -> void:
	_pinned = false
	_set_target(false)


func toggle() -> void:
	if _pinned:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not _target_open:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- Hover / pin interaction -------------------------------------------------

func _on_tab_mouse_entered() -> void:
	_close_timer = 0.0
	if not _target_open:
		_set_target(true)


func _on_tab_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# Swallow the wheel so scrolling over the tab can't fall through to the camera zoom.
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		toggle()
		get_viewport().set_input_as_handled()


## Swallows mouse-wheel events over the panel. Wheel events bubble up through STOP controls until
## accepted; if the list isn't scrollable they would otherwise reach camera_controller's
## _unhandled_input and zoom the map. The ScrollContainer still consumes the wheel when it can scroll.
func _on_panel_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		get_viewport().set_input_as_handled()


## Closes an un-pinned drawer once the mouse has left the tab+panel area for CLOSE_DELAY.
func _process(delta: float) -> void:
	if _pinned or not _target_open:
		_close_timer = 0.0
		return
	if _slider.get_global_rect().has_point(get_viewport().get_mouse_position()):
		_close_timer = 0.0
	else:
		_close_timer += delta
		if _close_timer >= CLOSE_DELAY:
			_close_timer = 0.0
			_set_target(false)


# --- Slide animation ---------------------------------------------------------

func _set_target(want_open: bool) -> void:
	_target_open = want_open
	if want_open:
		_rebuild()
	_animate_slide(1.0 if want_open else 0.0)


func _animate_slide(target: float) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if REDUCE_MOTION:
		_apply_slide(target)
		return
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_method(_apply_slide, _slide, target, SLIDE_TIME)


## Positions the slider so t=0 leaves only the tab peeking past the right edge and t=1 brings
## the full tab+panel on screen. Anchored to the right edge, so this survives window resizing.
func _apply_slide(t: float) -> void:
	_slide = t
	_slider.offset_left = lerp(-TAB_WIDTH, -(TAB_WIDTH + PANEL_WIDTH), t)
	_slider.offset_right = lerp(PANEL_WIDTH, 0.0, t)


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
	if _target_open:
		_rebuild()


func _on_points_changed(total: int) -> void:
	if _points_label != null:
		_points_label.text = "%s %d" % [POINT_GLYPH, total]


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_slider = Control.new()
	_slider.anchor_left = 1.0
	_slider.anchor_right = 1.0
	_slider.anchor_top = 0.0
	_slider.anchor_bottom = 1.0
	_slider.offset_top = 0.0
	_slider.offset_bottom = 0.0
	_slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slider)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	# IGNORE (not PASS): the slider strip spans the full-height right edge, so a hit-testable row
	# would block clicks to whatever is below (the game, or the Progression Tree's close button on a
	# lower CanvasLayer). Only the tab and panel (both STOP) should catch clicks; children are still
	# hit-tested independently of this IGNORE.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slider.add_child(row)

	row.add_child(_build_tab())
	row.add_child(_build_panel())


## The always-visible edge tab: 📋 glyph + an active-task badge. Hovering opens the drawer,
## clicking pins it. Rounded only on the left so it reads as attached to the screen edge.
## Pinned to the top of the (full-height) holder, just below the fertility indicators.
func _build_tab() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(TAB_WIDTH, 0)
	holder.size_flags_vertical = Control.SIZE_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tab := PanelContainer.new()
	tab.custom_minimum_size = Vector2(TAB_WIDTH, TAB_HEIGHT)
	tab.anchor_left = 0.0
	tab.anchor_right = 1.0
	tab.anchor_top = 0.0
	tab.anchor_bottom = 0.0
	tab.offset_left = 0.0
	tab.offset_right = 0.0
	tab.offset_top = TAB_TOP_MARGIN
	tab.offset_bottom = TAB_TOP_MARGIN + TAB_HEIGHT
	tab.tooltip_text = "Tasks — hover to peek, click to pin"
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.add_theme_stylebox_override("panel", _tab_style())
	tab.mouse_entered.connect(_on_tab_mouse_entered)
	tab.gui_input.connect(_on_tab_gui_input)
	holder.add_child(tab)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(vbox)

	var glyph := Label.new()
	glyph.text = "📋"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(glyph)

	_tab_badge = Label.new()
	_tab_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tab_badge.add_theme_font_size_override("font_size", 13)
	_tab_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tab_badge)

	return holder


## The slide-in panel itself (header + scrollable task list).
func _build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_FILL
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks over the panel (non-modal elsewhere)
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.gui_input.connect(_on_panel_gui_input)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 60.0, 0)
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

	return panel


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


# --- Tab badge ---------------------------------------------------------------

## Updates the edge-tab badge: active-task count, tinted green when at least one is completable.
func _update_badge() -> void:
	if _tab_badge == null:
		return
	var active: Array[StringName] = TaskSystem.get_active_tasks()
	if active.is_empty():
		_tab_badge.visible = false
		_tab_badge.text = ""
		return
	var completable := 0
	for node_id: StringName in active:
		if TaskSystem.is_fulfilled(node_id):
			completable += 1
	_tab_badge.visible = true
	_tab_badge.text = str(active.size())
	_tab_badge.add_theme_color_override("font_color", MET_COLOR if completable > 0 else MUTED_COLOR)


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

## Drawer panel: rounded on the left only (attached to the right edge) with a soft drop shadow.
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.corner_radius_top_left = 12
	sb.corner_radius_bottom_left = 12
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 8
	return sb


## Edge tab: rounded on the left only, matching the panel's attached-to-edge look.
func _tab_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_COLOR
	sb.corner_radius_top_left = 10
	sb.corner_radius_bottom_left = 10
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 6
	return sb


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
