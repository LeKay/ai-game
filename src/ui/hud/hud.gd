class_name HUD extends CanvasLayer
## HUD: persistent gameplay overlay — energy bar, day counter, tick controls, storage panel.
##
## Partial implementation:
##   story-002: Energy + tick controls + day/time display are live.
##   story-006: Storage panel (collapsed/expanded global resource overview) is live.
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
const MINUTES_PER_DAY   := 1440

const TICK_SPEEDS: Array[float] = [0.5, 1.0, 2.0]

## Storage panel (Element 5 / 6 in UX spec)
const STORAGE_PANEL_WIDTH      := 160
const STORAGE_PANEL_MAX_HEIGHT := 300
const STORAGE_ROW_HEIGHT       := 22   ## estimated height per resource row in px
const PANEL_ANIM_DURATION      := 0.20 ## 200 ms ease-out per UX spec

# --- Node references (populated in _build_ui) --------------------------------

var _day_label:       Label
var _time_label:      Label
var _speed_label:     Label
var _speed_dec_btn:   Button
var _speed_inc_btn:   Button
var _play_pause_btn:  Button
var _energy_segments: Array[ColorRect] = []

var _storage_panel:      PanelContainer
var _storage_label:      Label
var _storage_toggle_btn: Button
var _resource_scroll:    ScrollContainer
var _resource_list:      VBoxContainer
var _in_transit_badge:   Label

var _building_detail_panel: BuildingDetailPanel

# --- System references -------------------------------------------------------

var _player_character: Node = null

var _day_tick_count: int = 0

var _is_panel_expanded: bool = false
var _panel_tween: Tween = null


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
	if InventorySystem.storage_changed.is_connected(_on_storage_changed):
		InventorySystem.storage_changed.disconnect(_on_storage_changed)
	if InventorySystem.container_capacity_changed.is_connected(_on_container_capacity_changed):
		InventorySystem.container_capacity_changed.disconnect(_on_container_capacity_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_panel_expanded:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_toggle_storage_panel()
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if not _storage_panel.get_global_rect().has_point(click.global_position):
			_toggle_storage_panel()
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

	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(BAND_PADDING, 0)
	hbox.add_child(right_pad)

	_add_storage_panel()
	_add_stubs()


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
	_speed_dec_btn.focus_mode = Control.FOCUS_ALL
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
	_speed_inc_btn.focus_mode = Control.FOCUS_ALL
	_speed_inc_btn.pressed.connect(_on_speed_inc_pressed)
	hbox.add_child(_speed_inc_btn)

	_play_pause_btn = Button.new()
	_play_pause_btn.name = "PlayPauseBtn"
	_play_pause_btn.text = "▶"
	_play_pause_btn.custom_minimum_size = Vector2(36, 24)
	_play_pause_btn.focus_mode = Control.FOCUS_ALL
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


## Builds the storage panel (Element 5/5b/6) anchored to the top-right corner
## beneath the top band. Panel starts collapsed — only "Used: X/Y" is visible.
func _add_storage_panel() -> void:
	_storage_panel = PanelContainer.new()
	_storage_panel.name = "StoragePanel"
	_storage_panel.anchor_left   = 1.0
	_storage_panel.anchor_right  = 1.0
	_storage_panel.anchor_top    = 0.0
	_storage_panel.anchor_bottom = 0.0
	_storage_panel.offset_left   = -STORAGE_PANEL_WIDTH
	_storage_panel.offset_right  = 0
	_storage_panel.offset_top    = TOP_BAND_HEIGHT
	_storage_panel.offset_bottom = TOP_BAND_HEIGHT  # PanelContainer sizes to content
	add_child(_storage_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_storage_panel.add_child(vbox)

	# Header row — always visible (collapsed state)
	var header := HBoxContainer.new()
	header.name = "CollapseRow"
	header.add_theme_constant_override("separation", 4)
	header.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(header)

	_storage_label = Label.new()
	_storage_label.name = "StorageLabel"
	_storage_label.text = "—/—"
	_storage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_storage_label.add_theme_font_size_override("font_size", 14)
	header.add_child(_storage_label)

	_storage_toggle_btn = Button.new()
	_storage_toggle_btn.name = "ToggleBtn"
	_storage_toggle_btn.text = "▼"
	_storage_toggle_btn.custom_minimum_size = Vector2(24, 24)
	_storage_toggle_btn.focus_mode = Control.FOCUS_ALL
	_storage_toggle_btn.pressed.connect(_on_storage_toggle_pressed)
	header.add_child(_storage_toggle_btn)

	# Scrollable resource list — hidden until expanded
	_resource_scroll = ScrollContainer.new()
	_resource_scroll.name = "ResourceScroll"
	_resource_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_resource_scroll.custom_minimum_size = Vector2(0, 0)
	_resource_scroll.visible = false
	vbox.add_child(_resource_scroll)

	_resource_list = VBoxContainer.new()
	_resource_list.name = "ResourceList"
	_resource_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_list.add_theme_constant_override("separation", 2)
	_resource_scroll.add_child(_resource_list)

	# In-transit badge (Element 5b) — floating above the toggle button.
	# Hidden until story-003 (start_transport) is implemented.
	_in_transit_badge = Label.new()
	_in_transit_badge.name = "InTransitBadge"
	_in_transit_badge.text = ""
	_in_transit_badge.visible = false
	_in_transit_badge.add_theme_font_size_override("font_size", 12)
	add_child(_in_transit_badge)


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
	add_child(_building_detail_panel)


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

	InventorySystem.storage_changed.connect(_on_storage_changed)
	InventorySystem.container_capacity_changed.connect(_on_container_capacity_changed)


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
	_refresh_storage_panel()


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


func _on_storage_changed(_container_id: StringName) -> void:
	_refresh_storage_panel()


func _on_container_capacity_changed(_container_id: StringName, _old: int, _new: int) -> void:
	_refresh_storage_panel()


func _on_storage_toggle_pressed() -> void:
	_toggle_storage_panel()


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


# --- Storage panel logic -----------------------------------------------------

## Recomputes used/total and per-resource counts; rebuilds the resource list rows.
## Called on every storage_changed or container_capacity_changed signal.
func _refresh_storage_panel() -> void:
	var summary := _compute_storage_summary()
	var used: int  = summary[&"used"]
	var total: int = summary[&"total"]

	if total == 0:
		_storage_label.text = "—/—"
	else:
		_storage_label.text = "Used: %d/%d" % [used, total]

	# Rebuild resource rows — clear existing, add one row per resource type.
	for child in _resource_list.get_children():
		child.queue_free()

	var resources: Dictionary = summary[&"resources"]
	if resources.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No storage available"
		empty_lbl.add_theme_font_size_override("font_size", 14)
		_resource_list.add_child(empty_lbl)
	else:
		for res_id: StringName in resources:
			_resource_list.add_child(_make_resource_row(res_id, resources[res_id]))

	# If the panel is expanded, update the scroll height to match new row count.
	if _is_panel_expanded:
		var row_count: int = _resource_list.get_child_count()
		var target_h: float = minf(row_count * STORAGE_ROW_HEIGHT, STORAGE_PANEL_MAX_HEIGHT)
		_resource_scroll.custom_minimum_size = Vector2(0, target_h)


## Returns {used: int, total: int, resources: Dictionary[StringName, int]}.
## Sums across all registered containers.
func _compute_storage_summary() -> Dictionary:
	var used: int = 0
	var total: int = 0
	var resources: Dictionary[StringName, int] = {}
	for container: InventoryContainer in InventorySystem.get_all_containers():
		used  += container.get_occupied_count()
		total += container.capacity
		for slot: InventorySlot in container.slots:
			if not slot.is_empty():
				var cur: int = resources.get(slot.resource_id, 0)
				resources[slot.resource_id] = cur + slot.quantity
	return {&"used": used, &"total": total, &"resources": resources}


func _make_resource_row(res_id: StringName, quantity: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, STORAGE_ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var name_lbl := Label.new()
	name_lbl.text = str(res_id)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var qty_lbl := Label.new()
	qty_lbl.text = str(quantity)
	qty_lbl.custom_minimum_size = Vector2(30, 0)
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	qty_lbl.add_theme_font_size_override("font_size", 14)
	qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(qty_lbl)

	row.set_meta(&"is_dragging", false)
	row.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			row.set_meta(&"is_dragging", false)
			return
		var mm := event as InputEventMouseMotion
		if mm != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
				and not row.get_meta(&"is_dragging", false):
			if mm.relative.length() > 3.0:
				row.set_meta(&"is_dragging", true)
				row.force_drag({&"resource_id": res_id, &"qty": 1},
						_make_drag_preview(res_id, quantity))
	)

	return row


func _make_drag_preview(res_id: StringName, _quantity: int) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	style.corner_radius_top_left     = 3
	style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left  = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left   = 8
	style.content_margin_right  = 8
	style.content_margin_top    = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = "%s ×1" % str(res_id)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color("#F0EDE6"))
	panel.add_child(lbl)
	return panel


## Toggles the resource list between collapsed (hidden) and expanded (visible).
## Uses a 200 ms ease-out tween on the scroll container's minimum height.
func _toggle_storage_panel() -> void:
	_is_panel_expanded = not _is_panel_expanded
	_storage_toggle_btn.text = "▲" if _is_panel_expanded else "▼"

	# Kill any in-progress tween to avoid conflicts on rapid toggling.
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()

	if _is_panel_expanded:
		var row_count: int = _resource_list.get_child_count()
		var target_h: float = minf(row_count * STORAGE_ROW_HEIGHT, STORAGE_PANEL_MAX_HEIGHT)
		_resource_scroll.custom_minimum_size = Vector2(0, 0)
		_resource_scroll.visible = true
		_panel_tween = create_tween()
		_panel_tween.set_ease(Tween.EASE_OUT)
		_panel_tween.set_trans(Tween.TRANS_QUAD)
		_panel_tween.tween_property(
			_resource_scroll, "custom_minimum_size:y", target_h, PANEL_ANIM_DURATION
		)
	else:
		_panel_tween = create_tween()
		_panel_tween.set_ease(Tween.EASE_OUT)
		_panel_tween.set_trans(Tween.TRANS_QUAD)
		_panel_tween.tween_property(
			_resource_scroll, "custom_minimum_size:y", 0.0, PANEL_ANIM_DURATION
		)
		_panel_tween.tween_callback(func() -> void: _resource_scroll.visible = false)


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
	var total_minutes := int(float(tick_count) / float(TickSystem.TICKS_PER_DAY) * float(MINUTES_PER_DAY))
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]


## Hides the HUD storage panel while the inventory overlay is open (UX spec AC: HUD storage panel).
func hide_storage_panel() -> void:
	_storage_panel.visible = false


## Restores the HUD storage panel when the inventory overlay closes.
func show_storage_panel() -> void:
	_storage_panel.visible = true


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
