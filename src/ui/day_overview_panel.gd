class_name DayOverviewPanel extends CanvasLayer
## Day Overview Panel — shown at each day transition.
## Displays day number, NPC count, daily consumption (food + perk goods), and resource deltas.
## Dismisses via "Next Day" button, resuming the game.
## Per ADR-0003 (InputContext push/pop). Story 008.

const BLOCK_WIDTH  := 72
const BLOCK_HEIGHT := 84
const ICON_SIZE    := 48

const COLOR_BLOCK_BG     := Color("#2a2a2a")
const COLOR_BLOCK_BORDER := Color("#4a4a4a")
const COLOR_QTY_TEXT     := Color("#F0EDE6")
const COLOR_GAIN         := Color("#4CAF50")
const COLOR_LOSS         := Color("#E05555")

## Experience XP-bar colours + per-segment animation duration (one segment = one level fill).
const COLOR_XP_BAR_BG   := Color("#2A2A2A")
const COLOR_XP_BAR_FILL := Color("#D4A85C")
const COLOR_XP_BAR_MAX  := Color("#E8C860")
const XP_SEG_SEC        := 0.45

@onready var _day_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HeaderRow/DayLabel
@onready var _npc_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HeaderRow/NpcLabel
@onready var _hunger_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/SectionsRow/LeftSection/HungerScroll/HungerList
@onready var _delta_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/SectionsRow/RightSection/DeltaScroll/DeltaList
@onready var _next_day_btn: Button = $PanelContainer/MarginContainer/VBoxContainer/NextDayButton
@onready var _npc_xp_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/NpcSection/NpcScroll/NpcXpList

## npc_id -> the per-row ⬆️ level-up Button, so their visibility can be refreshed after a perk
## choice is resolved without rebuilding (and re-animating) the whole list.
var _levelup_buttons: Dictionary = {}


func _ready() -> void:
	hide()
	TickSystem.day_transition.connect(_on_day_transition)
	_next_day_btn.pressed.connect(_on_next_day_pressed)


func _on_day_transition(_days: int) -> void:
	if visible:
		return
	var hud: HUD = get_tree().get_first_node_in_group(&"hud") as HUD
	if hud != null:
		hud.close_all_panels_for_day_transition()
	_populate()
	show()
	InputContext.push_context(InputContext.Context.UI_ACTIVE)
	_next_day_btn.grab_focus()


func _populate() -> void:
	_day_label.text = "Day %d" % TickSystem.get_current_day()
	_npc_label.text = "%d Residents" % NPCSystem.get_npc_count()
	_fill_item_grid(_hunger_list, DayLedger.get_last_consumed(), false)
	_fill_item_grid(_delta_list, DayLedger.get_last_day_deltas(), true)
	_fill_npc_xp(NPCSystem.get_last_day_xp_summary())
	_next_day_btn.text = "Next Day"


func _fill_item_grid(container: VBoxContainer, data: Dictionary, show_sign: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	if data.is_empty():
		var lbl := Label.new()
		lbl.text = "No changes" if show_sign else "Nothing consumed"
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.modulate = Color("#A8A49C")
		container.add_child(lbl)
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	container.add_child(flow)
	for resource_id: StringName in data:
		if show_sign and data[resource_id] == 0:
			continue
		flow.add_child(_make_item_block(resource_id, data[resource_id], show_sign))


func _make_item_block(resource_id: StringName, quantity: int, show_sign: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BLOCK_WIDTH, BLOCK_HEIGHT)
	panel.mouse_filter        = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color            = COLOR_BLOCK_BG
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	if show_sign:
		style.border_color = COLOR_GAIN if quantity >= 0 else COLOR_LOSS
	else:
		style.border_color = COLOR_BLOCK_BORDER
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size   = Vector2(ICON_SIZE, ICON_SIZE)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	var icon_rect := TextureRect.new()
	icon_rect.texture      = ResourceRegistry.get_icon_texture(resource_id, ICON_SIZE / 2)
	icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_rect)

	var qty_lbl := Label.new()
	if show_sign:
		var prefix := "+" if quantity >= 0 else ""
		qty_lbl.text = "%s%d" % [prefix, quantity]
		qty_lbl.add_theme_color_override("font_color", COLOR_GAIN if quantity >= 0 else COLOR_LOSS)
	else:
		qty_lbl.text = "×%d" % quantity
		qty_lbl.add_theme_color_override("font_color", COLOR_QTY_TEXT)
	qty_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_lbl.add_theme_font_size_override("font_size", 14)
	qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(qty_lbl)

	return panel




# ── NPC experience section ──────────────────────────────────────────────────

## Builds one animated row per NPC that gained XP this day (Experience System).
## `summary` entries: {display_name, xp_before, level_before, xp_gained, xp_after, level_after}.
func _fill_npc_xp(summary: Array) -> void:
	_levelup_buttons.clear()
	for child in _npc_xp_list.get_children():
		child.queue_free()
	# Only show NPCs whose XP total actually increased (bar was not already clamped at the cap).
	var visible: Array = summary.filter(
		func(e: Dictionary) -> bool: return int(e[&"xp_after"]) > int(e[&"xp_before"])
	)
	if visible.is_empty():
		var lbl := Label.new()
		lbl.text = "No experience gained"
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.modulate = Color("#A8A49C")
		_npc_xp_list.add_child(lbl)
		return
	for entry: Dictionary in visible:
		_npc_xp_list.add_child(_make_npc_xp_row(entry))


func _make_npc_xp_row(entry: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	row.add_child(top)

	var name_lbl := Label.new()
	var job: String = NPCSystem.get_npc_job_name(entry[&"npc_id"])
	name_lbl.text                  = "%s (%s)" % [str(entry[&"display_name"]), job] if job != "" \
			else str(entry[&"display_name"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", COLOR_QTY_TEXT)
	top.add_child(name_lbl)

	var level_lbl := Label.new()
	level_lbl.text = "Lv %d" % int(entry[&"level_before"])
	level_lbl.add_theme_font_size_override("font_size", 13)
	level_lbl.add_theme_color_override("font_color", COLOR_XP_BAR_MAX)
	top.add_child(level_lbl)

	var gain_lbl := Label.new()
	gain_lbl.text = "+%d XP" % int(entry[&"xp_gained"])
	gain_lbl.add_theme_font_size_override("font_size", 13)
	gain_lbl.add_theme_color_override("font_color", COLOR_GAIN)
	top.add_child(gain_lbl)

	# ⬆️ level-up button — only when this NPC is held at the cap with a full bar, or still has an
	# unresolved perk choice from an auto-level. Tapping it raises the level (if possible) and opens
	# the shared Perk Choice panel. Leveling no longer gates the day, so this is purely optional.
	var npc_id: StringName = entry[&"npc_id"]
	var levelup_btn := Button.new()
	levelup_btn.text         = "⬆"
	levelup_btn.tooltip_text = "Level up"
	levelup_btn.focus_mode   = Control.FOCUS_NONE
	levelup_btn.add_theme_font_size_override("font_size", 13)
	levelup_btn.visible      = _npc_can_levelup(npc_id)
	levelup_btn.pressed.connect(_on_row_levelup_pressed.bind(npc_id))
	top.add_child(levelup_btn)
	_levelup_buttons[npc_id] = levelup_btn

	var bar_outer := Control.new()
	bar_outer.custom_minimum_size   = Vector2(0, 10)
	bar_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_outer.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_outer)

	var bg := ColorRect.new()
	bg.color        = COLOR_XP_BAR_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_outer.add_child(bg)

	var fill := ColorRect.new()
	fill.color         = COLOR_XP_BAR_FILL
	fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	fill.anchor_left   = 0.0
	fill.anchor_top    = 0.0
	fill.anchor_bottom = 1.0
	fill.offset_left   = 0.0
	fill.offset_top    = 0.0
	fill.offset_right  = 0.0
	fill.offset_bottom = 0.0
	bar_outer.add_child(fill)

	_animate_xp_row(fill, level_lbl, entry)
	return row


## Animates the bar from the day's starting fill to its end fill, replaying each level-up:
## fill current level to 100%, snap to 0 and bump the "Lv N" label, repeat, then settle on
## the final partial fill. Handles multiple level-ups in one day and the MAX-level colour.
func _animate_xp_row(fill: ColorRect, level_lbl: Label, entry: Dictionary) -> void:
	var xp_before: int    = int(entry[&"xp_before"])
	var level_before: int = int(entry[&"level_before"])
	var xp_after: int     = int(entry[&"xp_after"])
	var level_after: int  = int(entry[&"level_after"])

	fill.anchor_right = ExperienceFormulas.progress_in_level(xp_before, level_before)

	var tween := create_tween()
	var cur_level: int = level_before
	while cur_level < level_after:
		tween.tween_property(fill, "anchor_right", 1.0, XP_SEG_SEC)
		cur_level += 1
		tween.tween_callback(_advance_level_visual.bind(fill, level_lbl, cur_level))
	var end_frac: float = ExperienceFormulas.progress_in_level(xp_after, level_after)
	tween.tween_property(fill, "anchor_right", end_frac, XP_SEG_SEC)
	if level_after >= ExperienceFormulas.MAX_LEVEL:
		tween.tween_callback(func() -> void: fill.color = COLOR_XP_BAR_MAX)


## Tween callback: reset the bar to empty and show the newly reached level.
func _advance_level_visual(fill: ColorRect, level_lbl: Label, new_level: int) -> void:
	fill.anchor_right = 0.0
	level_lbl.text    = "Lv %d" % new_level


## True when this NPC can be manually levelled (held at the cap with a full bar) or still owes a
## perk choice from an auto-level. Drives the per-row ⬆️ button visibility.
func _npc_can_levelup(npc_id: StringName) -> bool:
	return NPCSystem.can_level_up(npc_id) or NPCSystem.get_pending_perk_choices(npc_id) > 0


## Re-evaluates every row's ⬆️ button visibility (e.g. after a perk choice was resolved).
func _refresh_levelup_buttons() -> void:
	for npc_id: StringName in _levelup_buttons:
		var btn: Button = _levelup_buttons[npc_id]
		if is_instance_valid(btn):
			btn.visible = _npc_can_levelup(npc_id)


## Row ⬆️ pressed: raise the level if one is banked, then open the Perk Choice panel for THIS NPC
## only — one choice per press, never chaining into other NPCs' pending choices.
func _on_row_levelup_pressed(npc_id: StringName) -> void:
	if NPCSystem.can_level_up(npc_id):
		NPCSystem.level_up(npc_id)
	var panel: Node = get_tree().get_first_node_in_group(&"perk_choice_panel")
	if panel == null:
		return  # no panel wired — nothing to resolve; day advances independently now
	if not panel.resolved.is_connected(_on_perk_choices_resolved):
		panel.resolved.connect(_on_perk_choices_resolved, CONNECT_ONE_SHOT)
	panel.begin_for_npc(npc_id)


func _on_perk_choices_resolved() -> void:
	_refresh_levelup_buttons()
	_next_day_btn.grab_focus()


func _advance_day() -> void:
	hide()
	InputContext.pop_context()
	var hud: HUD = get_tree().get_first_node_in_group(&"hud") as HUD
	if hud != null:
		hud.unlock_panels_after_day_transition()
	TickSystem.set_pause(false)


func _on_next_day_pressed() -> void:
	# Leveling is no longer a prerequisite — the day always advances.
	_advance_day()
