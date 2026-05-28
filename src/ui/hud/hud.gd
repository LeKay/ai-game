class_name HUD extends CanvasLayer
## HUD: persistent gameplay overlay — energy bar, day counter, tick controls.
##
## Partial implementation (story-002): Energy + Tick controls are live.
## NPC count, food status, storage panel, and toast container are stubbed
## (hidden nodes) pending their system dependencies.
##
## Signal wiring is null-guarded: if TickSystem or PlayerCharacter are absent
## at _ready() the HUD degrades gracefully with a push_warning.

# --- Constants ---------------------------------------------------------------

const COLOR_ENERGY_HIGH := Color("#4CAF50")  ## ≥ 50 %
const COLOR_ENERGY_MED  := Color("#FFC107")  ## 30–49 %
const COLOR_ENERGY_LOW  := Color("#FF9800")  ## 10–29 %
const COLOR_ENERGY_CRIT := Color("#E05555")  ## 0–9 %
const COLOR_BAR_BG      := Color("#333333")  ## energy bar / segment background
const COLOR_SEG_EMPTY   := Color(0.2, 0.2, 0.2, 1.0)  ## unfilled segment

const TOP_BAND_HEIGHT   := 48
const BAND_PADDING      := 10   ## left / right inner padding in px
const ENERGY_BAR_WIDTH  := 120
const ENERGY_BAR_HEIGHT := 8
const ENERGY_SEGMENTS   := 10  ## number of discrete bar segments
const ENERGY_SEG_GAP    := 2   ## px gap between segments
const TICKS_PER_DAY     := 1000  ## mirrors TickSystem.TICKS_PER_DAY
const MINUTES_PER_DAY   := 1440  ## 24 × 60 — used for HH:MM conversion

## Speed options mirrored from TickSystem.SPEED_OPTIONS.
const TICK_SPEEDS: Array[float] = [0.5, 1.0, 2.0]

# --- Node references (populated in _build_ui) --------------------------------

var _day_label:       Label
var _time_label:      Label
var _speed_label:     Label
var _speed_dec_btn:   Button
var _speed_inc_btn:   Button
var _play_pause_btn:  Button
var _energy_segments: Array[ColorRect] = []

# --- System references (populated in _connect_systems) -----------------------

var _player_character: Node = null

## Within-day tick counter — mirrors TickSystem._tick_count, accumulated from signal deltas.
var _day_tick_count: int = 0


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
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
	if _player_character != null:
		_player_character.energy_changed.disconnect(_on_energy_changed)


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	var top_band := _make_top_band()
	add_child(top_band)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 12)
	top_band.add_child(hbox)

	# Left padding
	var left_pad := Control.new()
	left_pad.custom_minimum_size = Vector2(BAND_PADDING, 0)
	hbox.add_child(left_pad)

	_add_day_label(hbox)
	_add_tick_controls(hbox)

	# Push day/time + energy to the right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_add_time_display(hbox)
	_add_energy_bar(hbox)

	# Right padding
	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(BAND_PADDING, 0)
	hbox.add_child(right_pad)

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


## "Day N" label — anchored to the far left after the left padding.
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


## Clock display: ⏰ HH:MM — placed on the right side of the band.
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

	# Segmented fill: ENERGY_SEGMENTS ColorRects equally spaced inside bar_outer.
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


## Adds hidden placeholder nodes for elements pending system implementation.
func _add_stubs() -> void:
	for stub_name: String in [
		"NpcCountLabel", "FoodStatusLabel", "DebuffIndicator",
		"StoragePanel", "ToastContainer", "BuildingDetailPanel"
	]:
		var node := Control.new()
		node.name = stub_name
		node.visible = false
		add_child(node)


# --- System wiring -----------------------------------------------------------

func _connect_systems() -> void:
	# TickSystem is an Autoload — access via global name (same as map_root.gd).
	TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	TickSystem.speed_changed.connect(_on_speed_changed)
	TickSystem.pause_state_changed.connect(_on_pause_state_changed)

	_player_character = get_tree().get_first_node_in_group(&"player_character")
	if _player_character == null:
		push_warning("[HUD] PlayerCharacter not found in group — energy display disabled")
	else:
		_player_character.energy_changed.connect(_on_energy_changed)


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

func _on_ticks_advanced(delta_ticks: int) -> void:
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


# --- Visual helpers ----------------------------------------------------------

func _find_speed_idx(speed: float) -> int:
	for i: int in range(TICK_SPEEDS.size()):
		if is_equal_approx(speed, TICK_SPEEDS[i]):
			return i
	return 1  # default to 1x index


func _update_speed_label(speed: float) -> void:
	_speed_label.text = "%sx" % speed


func _update_speed_buttons(idx: int) -> void:
	_speed_dec_btn.disabled = (idx <= 0)
	_speed_inc_btn.disabled = (idx >= TICK_SPEEDS.size() - 1)


func _update_play_pause_btn(is_paused: bool) -> void:
	_play_pause_btn.text = "▶" if is_paused else "⏸"


## Maps tick count to HH:MM string. 0 ticks → "00:00", TICKS_PER_DAY → "24:00".
func _ticks_to_time_str(tick_count: int) -> String:
	var total_minutes := int(float(tick_count) / float(TICKS_PER_DAY) * float(MINUTES_PER_DAY))
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]


## Fills N of ENERGY_SEGMENTS segments based on current/max ratio; color reflects threshold.
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
