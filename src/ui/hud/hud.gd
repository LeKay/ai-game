class_name HUD extends CanvasLayer
## HUD: persistent gameplay overlay — energy bar, day counter, tick controls.
##
## Partial implementation:
##   story-002: Energy + tick controls + day/time display are live.
##
## NPC count, food status, toast container, and building detail panel are stubbed
## (hidden nodes) pending their system dependencies.
##
## Signal wiring is null-guarded: absent systems degrade gracefully with push_warning.

# --- Constants ---------------------------------------------------------------

const COLOR_ENERGY_HIGH := Color("#4CAF50")  ## ≥ 50 %
const COLOR_ENERGY_MED  := Color("#FFC107")  ## 30–49 %
const COLOR_ENERGY_LOW  := Color("#FF9800")  ## 10–29 %
const COLOR_ENERGY_CRIT := Color("#E05555")  ## 0–9 %
const COLOR_BAR_BG      := Color("#333333")  ## energy bar / segment background
const COLOR_SEG_EMPTY   := Color(0.2, 0.2, 0.2, 1.0)

const TOP_BAND_HEIGHT   := 48
const BAND_PADDING      := 10
const ENERGY_BAR_WIDTH  := 120
const ENERGY_BAR_HEIGHT := 8
const ENERGY_SEGMENTS   := 10
const ENERGY_SEG_GAP    := 2

const TICK_SPEEDS: Array[float] = [0.5, 1.0, 2.0]

# --- Node references (populated in _build_ui) --------------------------------

var _day_label:       Label
var _time_label:      Label
var _speed_label:     Label
var _speed_dec_btn:   Button
var _speed_inc_btn:   Button
var _play_pause_btn:  Button
var _energy_segments: Array[ColorRect] = []

var _building_detail_panel: BuildingDetailPanel
var _npc_detail_panel:      NpcDetailPanel
var _transportation_panel:  TransportationPanel
var _transport_btn:          Button
var _route_toggle_btn:       Button
var _save_btn:               Button
var _progression_btn:        Button
var _progression_screen:     ProgressionTreeScreen
var _tasks_btn:              Button
var _task_dialog:           TaskDialog
var _map_select_prompt:      Label
var _map_select_step:        String = ""
var _toast_label:            Label
var _toast_tween:            Tween = null

# --- System references -------------------------------------------------------

var _player_character: Node = null

var _day_tick_count: int = 0
var _route_lines: RouteLines = null


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	add_to_group(&"hud")
	_build_ui()
	_connect_systems()
	_refresh_initial_state()


func _exit_tree() -> void:
	if TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
		TickSystem.ticks_advanced.disconnect(_on_ticks_advanced)
	if TickSystem.speed_changed.is_connected(_on_speed_changed):
		TickSystem.speed_changed.disconnect(_on_speed_changed)
	if TickSystem.pause_state_changed.is_connected(_on_pause_state_changed):
		TickSystem.pause_state_changed.disconnect(_on_pause_state_changed)
	if _player_character != null and _player_character.energy_changed.is_connected(_on_energy_changed):
		_player_character.energy_changed.disconnect(_on_energy_changed)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _map_select_step != "":
		if key != null and key.pressed and key.keycode == KEY_ESCAPE:
			notify_building_selected_in_map_select(&"")
			get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and event.is_action_pressed(InputActions.PAUSE_TOGGLE):
		TickSystem.set_pause(not TickSystem.is_paused())
		get_viewport().set_input_as_handled()


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	var top_band := _make_top_band()
	add_child(top_band)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 12)
	top_band.add_child(hbox)

	var left_pad := Control.new()
	left_pad.custom_minimum_size = Vector2(BAND_PADDING, 0)
	hbox.add_child(left_pad)

	_add_day_label(hbox)
	_add_tick_controls(hbox)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_add_time_display(hbox)
	_add_energy_bar(hbox)
	_add_transport_btn(hbox)
	_add_route_toggle_btn(hbox)
	_add_progression_btn(hbox)
	_add_tasks_btn(hbox)
	_add_save_btn(hbox)

	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(BAND_PADDING, 0)
	hbox.add_child(right_pad)

	_add_stubs()
	_add_toast()


func _make_top_band() -> Control:
	var band := Control.new()
	band.name = "TopBand"
	band.anchor_left   = 0.0
	band.anchor_right  = 1.0
	band.anchor_top    = 0.0
	band.anchor_bottom = 0.0
	band.offset_left   = 0
	band.offset_right  = 0
	band.offset_top    = 0
	band.offset_bottom = TOP_BAND_HEIGHT

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.1, 0.1, 0.1, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band.add_child(bg)

	return band


func _add_tick_controls(parent: HBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.name = "TickControls"
	hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_theme_constant_override("separation", 4)
	parent.add_child(hbox)

	_speed_dec_btn = Button.new()
	_speed_dec_btn.name = "SpeedDecBtn"
	_speed_dec_btn.text = "-"
	_speed_dec_btn.custom_minimum_size = Vector2(24, 24)
	_speed_dec_btn.focus_mode = Control.FOCUS_NONE
	_speed_dec_btn.pressed.connect(_on_speed_dec_pressed)
	hbox.add_child(_speed_dec_btn)

	_speed_label = Label.new()
	_speed_label.name = "SpeedLabel"
	_speed_label.text = "1x"
	_speed_label.custom_minimum_size = Vector2(32, 0)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_speed_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(_speed_label)

	_speed_inc_btn = Button.new()
	_speed_inc_btn.name = "SpeedIncBtn"
	_speed_inc_btn.text = "+"
	_speed_inc_btn.custom_minimum_size = Vector2(24, 24)
	_speed_inc_btn.focus_mode = Control.FOCUS_NONE
	_speed_inc_btn.pressed.connect(_on_speed_inc_pressed)
	hbox.add_child(_speed_inc_btn)

	_play_pause_btn = Button.new()
	_play_pause_btn.name = "PlayPauseBtn"
	_play_pause_btn.text = "▶"
	_play_pause_btn.custom_minimum_size = Vector2(36, 24)
	_play_pause_btn.focus_mode = Control.FOCUS_NONE
	_play_pause_btn.pressed.connect(_on_play_pause_pressed)
	hbox.add_child(_play_pause_btn)


func _add_day_label(parent: HBoxContainer) -> void:
	_day_label = Label.new()
	_day_label.name = "DayLabel"
	_day_label.text = "Day 1"
	_day_label.custom_minimum_size = Vector2(52, 0)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_day_label.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	_day_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(_day_label)


func _add_time_display(parent: HBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.name = "TimeDisplay"
	hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_theme_constant_override("separation", 4)
	parent.add_child(hbox)

	var clock_lbl := Label.new()
	clock_lbl.name = "ClockEmoji"
	clock_lbl.text = "⏰"
	clock_lbl.add_theme_font_size_override("font_size", 16)
	clock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(clock_lbl)

	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.text = "00:00"
	_time_label.custom_minimum_size = Vector2(44, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(_time_label)


func _add_energy_bar(parent: HBoxContainer) -> void:
	var container := HBoxContainer.new()
	container.name = "EnergyContainer"
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_theme_constant_override("separation", 6)
	parent.add_child(container)

	var lbl := Label.new()
	lbl.text = "⚡"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(lbl)

	var bar_outer := Control.new()
	bar_outer.name = "EnergyBarOuter"
	bar_outer.custom_minimum_size = Vector2(ENERGY_BAR_WIDTH, ENERGY_BAR_HEIGHT)
	bar_outer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_child(bar_outer)

	var bg := ColorRect.new()
	bg.name = "EnergyBackground"
	bg.color = COLOR_BAR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_outer.add_child(bg)

	var seg_hbox := HBoxContainer.new()
	seg_hbox.name = "EnergySegments"
	seg_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seg_hbox.add_theme_constant_override("separation", ENERGY_SEG_GAP)
	bar_outer.add_child(seg_hbox)

	_energy_segments.clear()
	for i: int in range(ENERGY_SEGMENTS):
		var seg := ColorRect.new()
		seg.name = "Seg%d" % i
		seg.color = COLOR_SEG_EMPTY
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_vertical = Control.SIZE_FILL
		seg_hbox.add_child(seg)
		_energy_segments.append(seg)


## Adds the transport icon button to the HUD top band.
func _add_transport_btn(parent: HBoxContainer) -> void:
	_transport_btn = Button.new()
	_transport_btn.name = "TransportBtn"
	_transport_btn.text = "🚚"
	_transport_btn.tooltip_text = "Transportation"
	_transport_btn.custom_minimum_size = Vector2(36, 28)
	_transport_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_transport_btn.focus_mode = Control.FOCUS_NONE
	_transport_btn.pressed.connect(_on_transport_btn_pressed)
	parent.add_child(_transport_btn)


## Adds the route overlay toggle button to the HUD top band (next to transport icon).
func _add_route_toggle_btn(parent: HBoxContainer) -> void:
	_route_toggle_btn = Button.new()
	_route_toggle_btn.name = "RouteToggleBtn"
	_route_toggle_btn.text = "↔"
	_route_toggle_btn.tooltip_text = "Toggle route overlay"
	_route_toggle_btn.toggle_mode = true
	_route_toggle_btn.custom_minimum_size = Vector2(36, 28)
	_route_toggle_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_route_toggle_btn.focus_mode = Control.FOCUS_NONE
	_route_toggle_btn.toggled.connect(_on_route_toggle_toggled)
	parent.add_child(_route_toggle_btn)


## Adds the Progression Tree toggle button to the HUD top band.
func _add_progression_btn(parent: HBoxContainer) -> void:
	_progression_btn = Button.new()
	_progression_btn.name = "ProgressionBtn"
	_progression_btn.text = "🌳"
	_progression_btn.tooltip_text = "Progression Tree"
	_progression_btn.custom_minimum_size = Vector2(36, 28)
	_progression_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progression_btn.focus_mode = Control.FOCUS_NONE
	_progression_btn.pressed.connect(_on_progression_btn_pressed)
	parent.add_child(_progression_btn)


## Adds the Delivery Tasks toggle button to the HUD top band.
func _add_tasks_btn(parent: HBoxContainer) -> void:
	_tasks_btn = Button.new()
	_tasks_btn.name = "TasksBtn"
	_tasks_btn.text = "📋"
	_tasks_btn.tooltip_text = "Tasks"
	_tasks_btn.custom_minimum_size = Vector2(36, 28)
	_tasks_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tasks_btn.focus_mode = Control.FOCUS_NONE
	_tasks_btn.pressed.connect(_on_tasks_btn_pressed)
	parent.add_child(_tasks_btn)


## Adds the save icon button to the HUD top band.
func _add_save_btn(parent: HBoxContainer) -> void:
	_save_btn = Button.new()
	_save_btn.name = "SaveBtn"
	_save_btn.text = "💾"
	_save_btn.tooltip_text = "Save Game"
	_save_btn.custom_minimum_size = Vector2(36, 28)
	_save_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_save_btn.focus_mode = Control.FOCUS_NONE
	_save_btn.pressed.connect(_on_save_btn_pressed)
	parent.add_child(_save_btn)


## Builds the transient toast label shown at the bottom-center of the screen
## (e.g. "Game saved"). Hidden until show_toast() is called.
func _add_toast() -> void:
	_toast_label = Label.new()
	_toast_label.name = "Toast"
	_toast_label.visible = false
	_toast_label.modulate.a = 0.0
	_toast_label.anchor_left   = 0.5
	_toast_label.anchor_right  = 0.5
	_toast_label.anchor_top    = 1.0
	_toast_label.anchor_bottom = 1.0
	_toast_label.offset_left   = -180
	_toast_label.offset_right  =  180
	_toast_label.offset_top    = -96
	_toast_label.offset_bottom = -60
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 15)
	_toast_label.add_theme_color_override("font_color", Color("#F0EDE6"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 12
	style.content_margin_right  = 12
	style.content_margin_top    = 6
	style.content_margin_bottom = 6
	_toast_label.add_theme_stylebox_override("normal", style)
	add_child(_toast_label)


## Shows a transient toast message that fades in, holds, then fades out.
## Pass is_error = true to display the message in red (e.g. blocked actions).
func show_toast(text: String, hold_seconds: float = 1.6, is_error: bool = false) -> void:
	if _toast_label == null:
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color",
		Color("#E57373") if is_error else Color("#F0EDE6"))
	_toast_label.visible = true
	_toast_label.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_label, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(hold_seconds)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func() -> void: _toast_label.visible = false)


## Adds hidden placeholder nodes for elements pending system implementation.
func _add_stubs() -> void:
	for stub_name: String in [
		"NpcCountLabel", "FoodStatusLabel", "DebuffIndicator", "ToastContainer"
	]:
		var node := Control.new()
		node.name = stub_name
		node.visible = false
		add_child(node)

	_building_detail_panel = BuildingDetailPanel.new()
	_building_detail_panel.name = "BuildingDetailPanel"
	_building_detail_panel.transport_management_opened.connect(_on_transport_management_opened)
	_building_detail_panel.transport_route_edit_requested.connect(_on_transport_route_edit_requested)
	_building_detail_panel.npc_detail_requested.connect(_on_npc_detail_requested)
	_building_detail_panel.building_selected.connect(_on_building_selected_routes)
	_building_detail_panel.building_deselected.connect(_on_building_deselected_routes)
	add_child(_building_detail_panel)

	_npc_detail_panel = NpcDetailPanel.new()
	_npc_detail_panel.name = "NpcDetailPanel"
	_npc_detail_panel.panel_x_offset = 0.0
	_npc_detail_panel.panel_closed.connect(_on_npc_panel_closed_routes)
	_npc_detail_panel.food_assigned.connect(
		func(npc_id: StringName, resource_id: StringName) -> void:
			HungerSystem.assign_food(npc_id, resource_id))
	_npc_detail_panel.food_cleared.connect(
		func(npc_id: StringName) -> void:
			HungerSystem.clear_food_assignment(npc_id))
	_npc_detail_panel.food_amount_changed.connect(
		func(npc_id: StringName, amount: int) -> void:
			HungerSystem.set_food_amount(npc_id, amount))
	add_child(_npc_detail_panel)

	_transportation_panel = TransportationPanel.new()
	_transportation_panel.name = "TransportationPanel"
	add_child(_transportation_panel)

	# Progression Tree overlay — its own CanvasLayer, toggled by the 🌳 HUD button.
	_progression_screen = preload(
		"res://src/ui/progression/ProgressionTreeScreen.tscn").instantiate()
	add_child(_progression_screen)

	# Delivery Tasks overlay — its own CanvasLayer, toggled by the 📋 HUD button.
	_task_dialog = TaskDialog.new()
	_task_dialog.name = "TaskDialog"
	add_child(_task_dialog)

	# Map-select text prompt — shown during map-select mode over the gameplay view.
	_map_select_prompt = Label.new()
	_map_select_prompt.name = "MapSelectPrompt"
	_map_select_prompt.visible = false
	_map_select_prompt.anchor_left   = 0.5
	_map_select_prompt.anchor_right  = 0.5
	_map_select_prompt.anchor_top    = 1.0
	_map_select_prompt.anchor_bottom = 1.0
	_map_select_prompt.offset_left   = -160
	_map_select_prompt.offset_right  =  160
	_map_select_prompt.offset_top    = -60
	_map_select_prompt.offset_bottom = -30
	_map_select_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_select_prompt.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_map_select_prompt.add_theme_font_size_override("font_size", 14)
	_map_select_prompt.add_theme_color_override("font_color", Color("#F0EDE6"))
	var prompt_style := StyleBoxFlat.new()
	prompt_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	prompt_style.corner_radius_top_left     = 4
	prompt_style.corner_radius_top_right    = 4
	prompt_style.corner_radius_bottom_left  = 4
	prompt_style.corner_radius_bottom_right = 4
	prompt_style.content_margin_left   = 12
	prompt_style.content_margin_right  = 12
	prompt_style.content_margin_top    = 6
	prompt_style.content_margin_bottom = 6
	_map_select_prompt.add_theme_stylebox_override("normal", prompt_style)
	add_child(_map_select_prompt)


# --- System wiring -----------------------------------------------------------

func _connect_systems() -> void:
	TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	TickSystem.speed_changed.connect(_on_speed_changed)
	TickSystem.pause_state_changed.connect(_on_pause_state_changed)

	_player_character = get_tree().get_first_node_in_group(&"player_character")
	if _player_character == null:
		push_warning("[HUD] PlayerCharacter not found in group — energy display disabled")
	else:
		_player_character.energy_changed.connect(_on_energy_changed)

	_transportation_panel.route_created.connect(_on_transport_route_created)
	_transportation_panel.route_updated.connect(_on_transport_route_updated)
	_transportation_panel.route_deleted.connect(_on_transport_route_deleted)
	_transportation_panel.map_select_requested.connect(_on_map_select_requested)
	_transportation_panel.panel_closed.connect(_on_transport_panel_closed)
	WorldSaveManager.load_completed.connect(_on_save_load_completed)


func _refresh_initial_state() -> void:
	_day_tick_count = TickSystem.get_tick_count()
	_day_label.text = "Day %d" % TickSystem.get_current_day()
	_time_label.text = _ticks_to_time_str(_day_tick_count)
	_update_speed_label(TickSystem.speed_multiplier)
	_update_play_pause_btn(TickSystem.is_paused())
	_update_speed_buttons(_find_speed_idx(TickSystem.speed_multiplier))
	if _player_character != null:
		_update_energy_bar(
			_player_character.get_current_energy(),
			_player_character.get_max_energy()
		)


# --- Signal handlers ---------------------------------------------------------

func _on_ticks_advanced(_delta_ticks: int) -> void:
	_day_tick_count = TickSystem.get_tick_count()
	_day_label.text = "Day %d" % TickSystem.get_current_day()
	_time_label.text = _ticks_to_time_str(_day_tick_count)


func _on_speed_changed(new_speed: float) -> void:
	_update_speed_label(new_speed)
	_update_speed_buttons(_find_speed_idx(new_speed))


func _on_pause_state_changed(is_paused: bool) -> void:
	_update_play_pause_btn(is_paused)


func _on_energy_changed(current: int, max_energy: int) -> void:
	_update_energy_bar(current, max_energy)


func _on_progression_btn_pressed() -> void:
	if _progression_screen != null:
		_progression_screen.toggle()


func _on_tasks_btn_pressed() -> void:
	if _task_dialog != null:
		_task_dialog.toggle()


func _on_transport_btn_pressed() -> void:
	if _transportation_panel.visible:
		_transportation_panel.close()
	else:
		_transportation_panel.open("hud")


func _on_transport_management_opened(building_id: String, role: String) -> void:
	_transportation_panel.open_for_building(StringName(building_id), role)


func _on_transport_route_edit_requested(route: LogisticsRoute) -> void:
	_transportation_panel.open_for_route(route)


func _on_transport_route_created(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName) -> void:
	# Storage→production: INPUT type (fills input slot on destination).
	# Production→anywhere: OUTPUT type (fills output slot on source).
	var from_instance := BuildingRegistry.get_building_instance(str(from_id))
	var route_type: int = LogisticsRoute.RouteType.INPUT \
		if from_instance != null and BuildingRegistry.STORAGE_CAPACITY.has(from_instance.type) \
		else LogisticsRoute.RouteType.OUTPUT
	var result: Dictionary = LogisticsSystem.create_route(
		from_id, to_id, npc_id, route_type, item_id)
	if not result.get("success", false):
		push_warning("[HUD] Route creation failed: %s" % result.get("error", ""))
	else:
		var route: LogisticsRoute = result.get("route")
		if route != null:
			LogisticsSystem.start_route(route.id)
	_transportation_panel.refresh()


func _on_transport_route_updated(route_id: StringName, changes: Dictionary) -> void:
	var route: LogisticsRoute = null
	for r: LogisticsRoute in LogisticsSystem.get_active_routes():
		if r.id == route_id:
			route = r
			break
	if route == null:
		return
	var new_from    := changes.get("from", route.source_building_id) as StringName
	var new_to      := changes.get("to",   route.destination_building_id) as StringName
	var new_npc     := changes.get("npc",  route.npc_id) as StringName
	var new_item_id := changes.get("item", route.source_item_id) as StringName
	LogisticsSystem.delete_route(route_id)
	var result := LogisticsSystem.create_route(new_from, new_to, new_npc, route.route_type, new_item_id)
	if result.get("success", false) and result.get("route") != null:
		LogisticsSystem.start_route(result["route"].id)
	elif not result.get("success", false):
		push_warning("[HUD] Route update failed: %s" % result.get("error", ""))
	_transportation_panel.refresh()


func _on_transport_route_deleted(route_id: StringName) -> void:
	LogisticsSystem.delete_route(route_id)
	_transportation_panel.refresh()


func _on_transport_panel_closed(_changes_made: bool) -> void:
	_exit_map_select_mode()


func _on_save_load_completed() -> void:
	_transportation_panel.refresh()


## Returns true while the player is selecting a building on the map for a route.
func is_map_select_active() -> bool:
	return _map_select_step != ""


## Enters map-select mode: hides all open panels, shows a text prompt.
## The map_root should call notify_building_selected_in_map_select() when the player
## clicks a building on the map.
func _on_map_select_requested(step: String) -> void:
	_map_select_step = step
	_transportation_panel.hide_for_map_select()
	if _building_detail_panel != null and _building_detail_panel.visible:
		_building_detail_panel.close()
	var prompt_text := "Select source building" if step == "from" else "Select destination building"
	_map_select_prompt.text = prompt_text
	_map_select_prompt.visible = true
	_transport_btn.disabled = true


func _exit_map_select_mode() -> void:
	_map_select_step = ""
	_map_select_prompt.visible = false
	_transport_btn.disabled = false


## Called by map_root when the player clicks a building during map-select.
## Pass building_id = &"" to cancel (clicked empty space).
func notify_building_selected_in_map_select(building_id: StringName) -> void:
	if _map_select_step == "":
		return
	var step := _map_select_step
	_exit_map_select_mode()
	_transportation_panel.resume_map_select(step, building_id)


# --- Button handlers ---------------------------------------------------------

func _on_speed_dec_pressed() -> void:
	var idx := _find_speed_idx(TickSystem.speed_multiplier)
	if idx > 0:
		TickSystem.set_speed(TICK_SPEEDS[idx - 1])


func _on_speed_inc_pressed() -> void:
	var idx := _find_speed_idx(TickSystem.speed_multiplier)
	if idx < TICK_SPEEDS.size() - 1:
		TickSystem.set_speed(TICK_SPEEDS[idx + 1])


func _on_play_pause_pressed() -> void:
	TickSystem.set_pause(not TickSystem.is_paused())


func _on_save_btn_pressed() -> void:
	if WorldSaveManager.save_game(1):
		show_toast("Game saved")
	else:
		show_toast("Save failed")


# --- Visual helpers ----------------------------------------------------------

func _find_speed_idx(speed: float) -> int:
	for i: int in range(TICK_SPEEDS.size()):
		if is_equal_approx(speed, TICK_SPEEDS[i]):
			return i
	return 1


func _update_speed_label(speed: float) -> void:
	var num: String = "%d" % int(speed) if is_equal_approx(speed, roundf(speed)) else "%.1f" % speed
	_speed_label.text = num + "x"


func _update_speed_buttons(idx: int) -> void:
	_speed_dec_btn.disabled = (idx <= 0)
	_speed_inc_btn.disabled = (idx >= TICK_SPEEDS.size() - 1)


func _update_play_pause_btn(is_paused: bool) -> void:
	_play_pause_btn.text = "▶" if is_paused else "⏸"


func _ticks_to_time_str(tick_count: int) -> String:
	var tph: int = TickSystem.TICKS_PER_DAY / 24  ## 60 ticks per hour; 1 tick = 1 minute
	return "%02d:%02d" % [tick_count / tph, tick_count % tph]


## Opens the Building Detail Panel for the given building_id.
## If the same building is already shown, closes the panel (toggle).
func open_building_detail(building_id: String) -> void:
	if _building_detail_panel != null:
		_building_detail_panel.open_for(building_id)


## Closes the Building Detail Panel if open.
func close_building_detail() -> void:
	if _building_detail_panel != null:
		_building_detail_panel.close()


## Returns the building_id currently shown in the detail panel, or "".
func get_shown_building_id() -> String:
	if _building_detail_panel == null:
		return ""
	return _building_detail_panel.get_current_building_id()


func _on_npc_detail_requested(npc_id: StringName, npc_state: int) -> void:
	if _npc_detail_panel != null:
		_npc_detail_panel.open_for_npc(npc_id, npc_state)
	if _route_lines != null:
		_route_lines.set_npc_filter(npc_id)


## Called by MapRoot after RouteLines is ready — wires the overlay to this HUD.
func set_route_lines(rl: RouteLines) -> void:
	_route_lines = rl


func _on_route_toggle_toggled(pressed: bool) -> void:
	if _route_lines != null:
		_route_lines.set_global_show(pressed)


func _on_building_selected_routes(building_id: String, _tile: Vector2i) -> void:
	if _route_lines != null:
		_route_lines.set_building_filter(StringName(building_id))


func _on_building_deselected_routes(_building_id: String) -> void:
	if _route_lines != null:
		_route_lines.set_building_filter(&"")


func _on_npc_panel_closed_routes() -> void:
	if _route_lines != null:
		_route_lines.set_npc_filter(&"")


func _update_energy_bar(current: int, max_energy: int) -> void:
	if max_energy <= 0:
		return
	var ratio := clampf(float(current) / float(max_energy), 0.0, 1.0)
	var filled := int(round(ratio * ENERGY_SEGMENTS))
	var pct := ratio * 100.0
	var fill_color: Color
	if pct >= 50.0:
		fill_color = COLOR_ENERGY_HIGH
	elif pct >= 30.0:
		fill_color = COLOR_ENERGY_MED
	elif pct >= 10.0:
		fill_color = COLOR_ENERGY_LOW
	else:
		fill_color = COLOR_ENERGY_CRIT
	for i: int in range(_energy_segments.size()):
		_energy_segments[i].color = fill_color if i < filled else COLOR_SEG_EMPTY
