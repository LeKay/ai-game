class_name NpcDetailPanel extends Control
## NPC Detail Panel — per-NPC supply assignment (Daily Food + perk goods) and identity UI.
## Opened from the NPCs tab when clicking an NPC tile. All state writes go via signals / system
## calls; this panel is display-only.
##
## Daily Food and perks share one uniform "supply grid" (2 columns, scrollable): each cell has a
## title (perk name, or "Daily Food"), a tile showing the REQUIRED amount of its good, and [− n +]
## controls for the ASSIGNED amount. A tile is greyed out when the perk/food was not consumed at the
## last day transition (inactive). Hover shows the effect plus, when inactive, why.

signal food_assigned(npc_id: StringName, resource_id: StringName)
signal food_cleared(npc_id: StringName)
signal food_amount_changed(npc_id: StringName, amount: int)
signal panel_closed

## Food resource IDs the picker will offer (order = display order).
const FOOD_ITEM_IDS: Array[StringName] = [&"berry", &"bread"]
const PANEL_WIDTH   := 320
const PANEL_HEIGHT  := 520
const ANIM_DURATION := 0.12
## Horizontal shift applied after PRESET_CENTER so the panel sits right of the inventory modal.
const PANEL_LEFT_OFFSET := 458.0

## Override before adding to the scene tree to reposition the panel.
var panel_x_offset: float = PANEL_LEFT_OFFSET

const COLOR_BG         := UiPalette.PANEL_BG
const COLOR_TEXT       := Color(0.941, 0.929, 0.902)
const COLOR_TEXT_DIM   := Color(0.659, 0.643, 0.612)
const COLOR_BTN_NORMAL := Color(0.353, 0.353, 0.353)
const COLOR_BTN_HOVER  := Color(0.290, 0.494, 0.659)
const COLOR_SEP        := UiPalette.SEPARATOR
const COLOR_XP_BAR_BG   := Color("#2A2A2A")
const COLOR_XP_BAR_FILL := Color("#D4A85C")
const COLOR_XP_BAR_MAX  := Color("#E8C860")
const COLOR_DISABLED    := Color(0.5, 0.5, 0.5, 0.45)

var _panel:           DraggableWindow
var _rename_btn:      Button
var _rename_dialog:   Control
var _rename_input:    LineEdit
var _npc_state_lbl:     Label
var _npc_efficiency_lbl: Label
var _npc_level_lbl:     Label
var _levelup_btn:       Button
var _xp_bar_outer:      Control
var _xp_bar_fill:       ColorRect
var _xp_label:          Label
var _profession_lbl:  Label
var _supply_grid:     GridContainer
var _food_popup:      Control
var _food_popup_flow: HFlowContainer

var _npc_id:       StringName = &""
var _assigned_food: StringName = &""
var _food_amount:   int = 1
var _tween: Tween = null


func _ready() -> void:
	_build_ui()
	visible = false
	modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		if _rename_dialog != null and _rename_dialog.visible:
			_close_rename_dialog()
		elif _food_popup != null and _food_popup.visible:
			_close_food_popup()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if _rename_dialog != null and _rename_dialog.visible:
			return
		if _food_popup != null and _food_popup.visible:
			if not _food_popup.get_global_rect().has_point(click.global_position):
				_close_food_popup()
			return
		if not _panel.get_global_rect().has_point(click.global_position):
			close()
			get_viewport().set_input_as_handled()


# ── Public API ────────────────────────────────────────────────────────────────

## Opens the panel for the given NPC. Reads current assignment and amount from HungerSystem.
func open_for_npc(npc_id: StringName, npc_state: int) -> void:
	_npc_id        = npc_id
	_assigned_food = HungerSystem.get_assigned_food(npc_id)
	_food_amount   = HungerSystem.get_food_amount(npc_id)
	_panel.title  = NPCSystem.get_npc_display_name(npc_id)
	_npc_state_lbl.text = _state_label(npc_state)
	_refresh_efficiency()
	_refresh_xp()
	_refresh_supply()
	if not NPCSystem.npc_renamed.is_connected(_on_npc_renamed):
		NPCSystem.npc_renamed.connect(_on_npc_renamed)
	if not NPCSystem.npc_xp_gained.is_connected(_on_npc_xp_gained):
		NPCSystem.npc_xp_gained.connect(_on_npc_xp_gained)
	if not NPCSystem.npc_leveled_up.is_connected(_on_npc_leveled_up):
		NPCSystem.npc_leveled_up.connect(_on_npc_leveled_up)
	if not NPCSystem.npc_perk_chosen.is_connected(_on_npc_perk_chosen):
		NPCSystem.npc_perk_chosen.connect(_on_npc_perk_chosen)
	if not ProgressionSystem.npc_level_cap_changed.is_connected(_on_npc_level_cap_changed):
		ProgressionSystem.npc_level_cap_changed.connect(_on_npc_level_cap_changed)
	_animate_in()


func close() -> void:
	_close_food_popup()
	_close_rename_dialog()
	if NPCSystem.npc_renamed.is_connected(_on_npc_renamed):
		NPCSystem.npc_renamed.disconnect(_on_npc_renamed)
	if NPCSystem.npc_xp_gained.is_connected(_on_npc_xp_gained):
		NPCSystem.npc_xp_gained.disconnect(_on_npc_xp_gained)
	if NPCSystem.npc_leveled_up.is_connected(_on_npc_leveled_up):
		NPCSystem.npc_leveled_up.disconnect(_on_npc_leveled_up)
	if NPCSystem.npc_perk_chosen.is_connected(_on_npc_perk_chosen):
		NPCSystem.npc_perk_chosen.disconnect(_on_npc_perk_chosen)
	if ProgressionSystem.npc_level_cap_changed.is_connected(_on_npc_level_cap_changed):
		ProgressionSystem.npc_level_cap_changed.disconnect(_on_npc_level_cap_changed)
	_animate_out()
	panel_closed.emit()

# ── Header refresh (state / efficiency / XP) ───────────────────────────────────

func _refresh_efficiency() -> void:
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc == null or _npc_efficiency_lbl == null:
		return
	var pct: int = roundi(npc.efficiency * 100.0)
	var text: String = "Efficiency: %d%%" % pct
	# Pending change: the realized efficiency only updates at the next day transition, so preview the
	# delta from the currently SELECTED food + amount as "(+/−X%)" next to the live value.
	var delta_pct: int = roundi(_projected_efficiency(npc) * 100.0) - pct
	if delta_pct != 0:
		text += " (%+d%%)" % delta_pct
	_npc_efficiency_lbl.text = text
	_npc_efficiency_lbl.tooltip_text = _npc_efficiency_tooltip(npc)
	if npc.efficiency >= 1.0:
		_npc_efficiency_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
	elif npc.efficiency >= 0.5:
		_npc_efficiency_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
	else:
		_npc_efficiency_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))


## Updates the Level row, XP bar fill, and "x / y XP" readout (Experience System F3).
func _refresh_xp() -> void:
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc == null or _npc_level_lbl == null:
		return
	_npc_level_lbl.text = "Level %d" % npc.level
	var span: int = ExperienceFormulas.xp_span_of_level(npc.level)
	var into: int = ExperienceFormulas.xp_into_level(npc.xp, npc.level)
	if span <= 0:
		_xp_bar_fill.anchor_right = 1.0
		_xp_bar_fill.color        = COLOR_XP_BAR_MAX
		_xp_label.text            = "MAX"
	else:
		_xp_bar_fill.anchor_right = clampf(float(into) / float(span), 0.0, 1.0)
		_xp_bar_fill.color        = COLOR_XP_BAR_FILL
		_xp_label.text            = "%d / %d XP" % [into, span]
	_refresh_levelup_btn()


## Shows the header ⬆️ button when this NPC can be levelled now (cap raised, bar full) or still owes
## a perk choice. Tapping it raises the level and opens the shared Perk Choice panel.
func _refresh_levelup_btn() -> void:
	if _levelup_btn == null:
		return
	_levelup_btn.visible = NPCSystem.can_level_up(_npc_id) \
			or NPCSystem.get_pending_perk_choices(_npc_id) > 0


func _on_levelup_pressed() -> void:
	if NPCSystem.can_level_up(_npc_id):
		NPCSystem.level_up(_npc_id)
	var panel: Node = get_tree().get_first_node_in_group(&"perk_choice_panel")
	if panel != null:
		panel.begin_for_npc(_npc_id)  # resolve only this NPC's one choice, no chaining
	_refresh_xp()


## A cap node was unlocked in the progression tree — an open panel may now allow a level-up.
func _on_npc_level_cap_changed(_cap: int) -> void:
	if visible:
		_refresh_levelup_btn()


func _on_npc_xp_gained(npc_id: StringName, _total: int, _into: int, _span: int) -> void:
	if npc_id == _npc_id and visible:
		_refresh_xp()


func _on_npc_leveled_up(npc_id: StringName, _new_level: int) -> void:
	if npc_id == _npc_id and visible:
		_refresh_xp()


func _on_npc_perk_chosen(npc_id: StringName, _perk_id: StringName) -> void:
	if npc_id == _npc_id and visible:
		_refresh_supply()
		_refresh_levelup_btn()

# ── Supply grid (Daily Food + perks, uniform cells) ─────────────────────────────

## Rebuilds the supply grid: the Daily Food cell first, then one cell per acquired perk.
func _refresh_supply() -> void:
	if _supply_grid == null:
		return
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc != null and int(npc.profession) != -1:
		_profession_lbl.text    = "Profession: %s" % PerkRegistry.building_type_name(int(npc.profession))
		_profession_lbl.visible = true
	else:
		_profession_lbl.visible = false

	for child in _supply_grid.get_children():
		child.queue_free()
	_supply_grid.add_child(_make_food_cell())
	if npc != null:
		for i: int in range(npc.perks.size()):
			_supply_grid.add_child(_make_perk_cell(npc.perks[i], i))


## Daily Food cell: title, food tile (click to pick), and the assigned-amount controls.
func _make_food_cell() -> Control:
	var required: int = _food_required()
	var active: bool = _assigned_food != &"" and HungerSystem.was_food_consumed(_npc_id)
	var max_pct: int = roundi(_npc_max_efficiency() * 100.0)
	var tip: String
	if _assigned_food == &"":
		tip = "Daily Food — no food assigned. Click to choose."
	else:
		var fdef: Object = ResourceRegistry.get_definition(_assigned_food)
		var fname: String = fdef.display_name if fdef != null else str(_assigned_food)
		tip = "Daily Food: %s — feeds efficiency." % fname
		if required > 0:
			tip += "\nNeeds %d/day to reach max efficiency (%d%%)." % [required, max_pct]
		else:
			tip += "\nAlready at max efficiency (%d%%) — no food needed." % max_pct
		if not active:
			tip += "\nInactive — not consumed at the last day change."

	var cell := _new_cell("Daily Food")
	cell.add_child(_make_supply_tile(_assigned_food, required, active, tip, true))
	if _assigned_food != &"":
		cell.add_child(_make_amount_row(_food_amount, func(d: int) -> void: _on_food_amount_delta(d)))
	return cell


## Perk cell: perk name, bound-good tile (shows required), and the assigned-amount controls.
func _make_perk_cell(perk: Dictionary, index: int) -> Control:
	var def: Dictionary = PerkRegistry.get_def(perk.get(&"perk_id", &""))
	var good: StringName = perk.get(&"good", &"")
	var required: int = int(def.get("required", 1))
	var active: bool = bool(perk.get(&"active", false))
	var tip: String = str(def.get("desc", ""))
	var bt: int = int(perk.get(&"building_type", -1))
	if bt != -1:
		tip = tip.replace("this building type", PerkRegistry.building_type_name(bt))
	if not active:
		var assigned: int = int(perk.get(&"amount", 1))
		if assigned < required:
			tip += "\nDisabled — set to 0 (no good consumed; not reported as undersupplied)." if assigned <= 0 \
				else "\nDisabled — assigned below the required amount; no good consumed."
		else:
			tip += "\nInactive — the good could not be consumed at the last day change."

	var cell := _new_cell(str(def.get("name", perk.get(&"perk_id", "?"))))
	cell.add_child(_make_supply_tile(good, required, active, tip, false))
	cell.add_child(_make_amount_row(int(perk.get(&"amount", 1)),
			func(d: int) -> void: _on_perk_amount_changed(index, d)))
	return cell


func _new_cell(title: String) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	var lbl := Label.new()
	lbl.text = title
	lbl.clip_text = true
	lbl.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	cell.add_child(lbl)
	return cell


## Builds a supply tile: good icon (or "+" when none), the REQUIRED amount (×N), greyed when
## inactive, with a hover tooltip. When `clickable`, left-click opens the food picker.
func _make_supply_tile(good: StringName, required: int, active: bool, tooltip: String, clickable: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, ItemGrid.BLOCK_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = tooltip
	if clickable:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if good != &"" and not active:
		panel.modulate = COLOR_DISABLED

	var style := StyleBoxFlat.new()
	style.bg_color = ItemGrid.COLOR_BLOCK_BG
	style.set_border_width_all(1)
	style.border_color = ItemGrid.COLOR_BLOCK_BORDER
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size   = Vector2(ItemGrid.ICON_SIZE, ItemGrid.ICON_SIZE)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	if good == &"":
		var plus_lbl := Label.new()
		plus_lbl.text = "+"
		plus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		plus_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plus_lbl.add_theme_font_size_override("font_size", 28)
		plus_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(plus_lbl)
	else:
		var rect := TextureRect.new()
		rect.texture      = ResourceRegistry.get_icon_texture(good, ItemGrid.ICON_SIZE / 2)
		rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(rect)

	if required > 0:
		var qty := Label.new()
		qty.text                  = "×%d" % required
		qty.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qty.add_theme_font_size_override("font_size", 14)
		qty.add_theme_color_override("font_color", ItemGrid.COLOR_QTY_TEXT)
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(qty)

	if clickable:
		panel.mouse_entered.connect(func() -> void: style.border_color = ItemGrid.COLOR_HOVER_BORDER)
		panel.mouse_exited.connect(func() -> void:  style.border_color = ItemGrid.COLOR_BLOCK_BORDER)
		panel.gui_input.connect(func(event: InputEvent) -> void:
			var mb := event as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_open_food_popup()
		)
	return panel


## [− n +] controls (tile width). `on_delta` is called with -1 / +1 on the buttons.
func _make_amount_row(amount: int, on_delta: Callable) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_theme_constant_override("separation", 0)

	var minus := Button.new()
	minus.text = "−"
	minus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minus.focus_mode = Control.FOCUS_ALL
	minus.pressed.connect(func() -> void: on_delta.call(-1))
	_apply_icon_btn_style(minus)
	row.add_child(minus)

	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(lbl)

	var plus := Button.new()
	plus.text = "+"
	plus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plus.focus_mode = Control.FOCUS_ALL
	plus.pressed.connect(func() -> void: on_delta.call(1))
	_apply_icon_btn_style(plus)
	row.add_child(plus)
	return row


## Required food amount = units of the assigned food to reach this NPC's max efficiency.
## Units of the assigned food needed to raise this NPC to its MAX efficiency — the exact inverse
## of HungerSystem's daily consumption. Accounts for every related perk:
##   • Master's Touch (#3) and NPC level raise the cap that food must fill (more food needed),
##   • Frugal (#1) supplies free nutrition each day (less food needed),
##   • Hardy (#9) raises the unfed floor — if that floor already meets the max, no food is needed.
## Only counts perks currently active (good supplied), matching HungerSystem. -1 = none/inedible.
func _food_required() -> int:
	if _assigned_food == &"":
		return -1
	var def: Object = ResourceRegistry.get_definition(_assigned_food)
	var nut: float = def.nutrition if def != null else 0.0
	if nut <= 0.0:
		return -1
	var level: int = 1
	var eff_cap_bonus: float = 0.0
	var perk_nutrition: float = 0.0
	var floor_eff: float = 0.0
	var inst: Object = NPCSystem.get_npc_instance(_npc_id)
	if inst != null:
		level = int(inst.level)
		eff_cap_bonus = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_NPC_EFF_CAP)
		perk_nutrition = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_NUTRITION_REDUCE)
		floor_eff = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_UNFED_FLOOR)
	# Hardy: if the unfed floor already reaches the max, food adds nothing.
	if floor_eff >= _npc_max_efficiency():
		return 0
	# Frugal's free nutrition subtracts from the daily target before converting to food units.
	var needed_nutrition: float = EfficiencyFormulas.nutrition_for_full(level, eff_cap_bonus) - perk_nutrition
	return maxi(0, ceili(needed_nutrition / nut))


## This NPC's maximum reachable efficiency [0.0–2.0], including level + Master's Touch (cap) and
## the Hardy floor. Drives the "max efficiency (xx%)" readout and the Hardy short-circuit above.
func _npc_max_efficiency() -> float:
	var level: int = 1
	var eff_cap_bonus: float = 0.0
	var floor_eff: float = 0.0
	var inst: Object = NPCSystem.get_npc_instance(_npc_id)
	if inst != null:
		level = int(inst.level)
		eff_cap_bonus = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_NPC_EFF_CAP)
		floor_eff = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_UNFED_FLOOR)
	var fed_max: float = EfficiencyFormulas.NUTRITION_UNFED_EFFICIENCY \
			+ EfficiencyFormulas.nutrition_bonus_cap(level, eff_cap_bonus)
	return maxf(fed_max, floor_eff)


## Projected NPC efficiency if the currently SELECTED food + amount were consumed at the next day
## change. Mirrors HungerSystem's daily calc (nutrition curve + Frugal/Hardy/Master's Touch perks),
## then applies this NPC's current satisfaction/equipment modifiers. Drives the "(+/−X%)" preview.
func _projected_efficiency(npc: NPCSystem.NPCInstance) -> float:
	var consumed_nutrition: float = 0.0
	if _assigned_food != &"" and _food_amount > 0:
		var def: Object = ResourceRegistry.get_definition(_assigned_food)
		var nut: float = def.nutrition if def != null else 0.0
		consumed_nutrition = nut * float(_food_amount)
	var perk_nutrition: float = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_NUTRITION_REDUCE)
	var floor_eff: float = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_UNFED_FLOOR)
	var eff_cap_bonus: float = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_NPC_EFF_CAP)
	var modifier: float = EfficiencyFormulas.calculate_food_modifier(
			consumed_nutrition + perk_nutrition, int(npc.level), eff_cap_bonus)
	if floor_eff > 0.0:
		modifier = maxf(modifier, floor_eff / EfficiencyFormulas.BASE_NPC_EFFICIENCY)
	return EfficiencyFormulas.calculate_npc_efficiency(
			modifier, npc.satisfaction_modifier, npc.equipment_modifier)


## Hover breakdown for the NPC efficiency label: unfed floor + food bonus (level/perk-capped),
## with the Hardy floor and any satisfaction/equipment multipliers (1.0 placeholders for now).
func _npc_efficiency_tooltip(npc: NPCSystem.NPCInstance) -> String:
	var floor_base: float = EfficiencyFormulas.NUTRITION_UNFED_EFFICIENCY
	var cap: float = EfficiencyFormulas.nutrition_bonus_cap(
			int(npc.level), NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_NPC_EFF_CAP))
	var hardy: float = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_UNFED_FLOOR)
	# food_modifier already carries the (post-Hardy) nutrition curve: e_food = 0.5 × modifier.
	var e_food: float = EfficiencyFormulas.BASE_NPC_EFFICIENCY * npc.food_modifier
	var binding_floor: float = floor_base
	var food_bonus: float = maxf(0.0, e_food - floor_base)
	if hardy > 0.0 and hardy >= e_food - 0.0001:
		binding_floor = hardy  # Hardy floor dominates; food has not yet exceeded it
		food_bonus = 0.0

	var lines: PackedStringArray = PackedStringArray()
	lines.append("Efficiency breakdown")
	lines.append("Unfed floor: %d%%%s" % [
			roundi(binding_floor * 100.0), " (Hardy)" if binding_floor > floor_base else ""])
	lines.append("Food: +%d%% (max +%d%%)" % [roundi(food_bonus * 100.0), roundi(cap * 100.0)])
	if not is_equal_approx(npc.satisfaction_modifier, 1.0):
		lines.append("× Satisfaction: %d%%" % roundi(npc.satisfaction_modifier * 100.0))
	if not is_equal_approx(npc.equipment_modifier, 1.0):
		lines.append("× Equipment: %d%%" % roundi(npc.equipment_modifier * 100.0))
	lines.append("= %d%% (max %d%%)" % [
			roundi(npc.efficiency * 100.0), roundi(_npc_max_efficiency() * 100.0)])
	return "\n".join(lines)


func _on_food_amount_delta(delta: int) -> void:
	if _assigned_food == &"":
		return
	_food_amount = maxi(0, _food_amount + delta)
	food_amount_changed.emit(_npc_id, _food_amount)
	_refresh_efficiency()
	_refresh_supply()


func _on_perk_amount_changed(index: int, delta: int) -> void:
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc == null or index < 0 or index >= npc.perks.size():
		return
	var current: int = int((npc.perks[index] as Dictionary).get(&"amount", 1))
	# System clamps to [0, required] — 0 disables the perk like food set to 0.
	NPCSystem.set_perk_amount(_npc_id, index, current + delta)
	_refresh_efficiency()
	_refresh_supply()

# ── Food picker popup ───────────────────────────────────────────────────────────

func _open_food_popup() -> void:
	for child in _food_popup_flow.get_children():
		child.queue_free()
	_food_popup_flow.add_child(_build_clear_tile())
	for food_id: StringName in FOOD_ITEM_IDS:
		var qty: int = InventorySystem.get_global_quantity(food_id)
		_food_popup_flow.add_child(_build_food_tile(food_id, qty))
	_food_popup.visible = true


func _close_food_popup() -> void:
	if _food_popup != null:
		_food_popup.visible = false


func _on_food_selected(resource_id: StringName) -> void:
	_close_food_popup()
	if resource_id == &"":
		_assigned_food = &""
		_food_amount   = 1
		food_cleared.emit(_npc_id)
	else:
		_assigned_food = resource_id
		food_assigned.emit(_npc_id, resource_id)
	_refresh_efficiency()
	_refresh_supply()

# ── Animations ────────────────────────────────────────────────────────────────

func _animate_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	modulate.a = 0.0
	position.y = 10.0
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate:a", 1.0, ANIM_DURATION)
	_tween.tween_property(self, "position:y", 0.0, ANIM_DURATION)


func _animate_out() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate:a", 0.0, ANIM_DURATION * 0.8)
	_tween.tween_callback(func() -> void: visible = false)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _state_label(state: int) -> String:
	match state:
		0: return "Idle"
		1: return "Travelling"
		2: return "Working"
		3: return "Returning"
		4: return "Depositing"
		5: return "Returning"
		6: return "Waiting"
		_: return "Unknown"

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = DraggableWindow.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left  += panel_x_offset
	_panel.offset_right += panel_x_offset
	_panel.close_requested.connect(close)
	add_child(_panel)

	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 14)
	body_margin.add_theme_constant_override("margin_right", 14)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	_panel.content.add_child(body_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	body_margin.add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	vbox.add_child(header_row)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 2)
	header_row.add_child(title_col)

	_npc_state_lbl = Label.new()
	_npc_state_lbl.add_theme_font_size_override("font_size", 12)
	_npc_state_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	title_col.add_child(_npc_state_lbl)

	_npc_efficiency_lbl = Label.new()
	_npc_efficiency_lbl.add_theme_font_size_override("font_size", 12)
	_npc_efficiency_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_npc_efficiency_lbl.mouse_filter = Control.MOUSE_FILTER_STOP  # needed for the hover tooltip
	title_col.add_child(_npc_efficiency_lbl)

	# Experience: level row + XP bar + "x / y XP" readout.
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	title_col.add_child(level_row)

	_npc_level_lbl = Label.new()
	_npc_level_lbl.add_theme_font_size_override("font_size", 12)
	_npc_level_lbl.add_theme_color_override("font_color", COLOR_XP_BAR_MAX)
	level_row.add_child(_npc_level_lbl)

	# ⬆️ level-up button — appears when a newly raised cap lets this NPC level up while it already
	# holds a full bar, or when a perk choice from an auto-level is still unresolved. See _refresh_levelup_btn().
	_levelup_btn = Button.new()
	_levelup_btn.text         = "⬆"
	_levelup_btn.tooltip_text = "Level up"
	_levelup_btn.focus_mode   = Control.FOCUS_NONE
	_levelup_btn.visible      = false
	_levelup_btn.add_theme_font_size_override("font_size", 12)
	_levelup_btn.pressed.connect(_on_levelup_pressed)
	level_row.add_child(_levelup_btn)

	_xp_label = Label.new()
	_xp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	level_row.add_child(_xp_label)

	_xp_bar_outer = Control.new()
	_xp_bar_outer.custom_minimum_size   = Vector2(0, 6)
	_xp_bar_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar_outer.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	title_col.add_child(_xp_bar_outer)

	var xp_bg := ColorRect.new()
	xp_bg.color        = COLOR_XP_BAR_BG
	xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_bar_outer.add_child(xp_bg)

	_xp_bar_fill = ColorRect.new()
	_xp_bar_fill.color         = COLOR_XP_BAR_FILL
	_xp_bar_fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_xp_bar_fill.anchor_left   = 0.0
	_xp_bar_fill.anchor_top    = 0.0
	_xp_bar_fill.anchor_right  = 0.0
	_xp_bar_fill.anchor_bottom = 1.0
	_xp_bar_fill.offset_right  = 0.0
	_xp_bar_outer.add_child(_xp_bar_fill)

	_rename_btn = Button.new()
	_rename_btn.name = "RenameBtn"
	_rename_btn.text = "✏"
	_rename_btn.custom_minimum_size = Vector2(28, 28)
	_rename_btn.focus_mode = Control.FOCUS_ALL
	_rename_btn.tooltip_text = "Rename NPC"
	_rename_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rename_btn.pressed.connect(_on_rename_pressed)
	_apply_icon_btn_style(_rename_btn)
	header_row.add_child(_rename_btn)

	_build_separator(vbox)

	_profession_lbl = Label.new()
	_profession_lbl.add_theme_font_size_override("font_size", 12)
	_profession_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	_profession_lbl.visible = false
	vbox.add_child(_profession_lbl)

	# Uniform supply grid: Daily Food + perks, 2 columns, scrollable.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size    = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_supply_grid = GridContainer.new()
	_supply_grid.columns = 2
	_supply_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_supply_grid.add_theme_constant_override("h_separation", 14)
	_supply_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_supply_grid)

	_build_food_popup()
	_build_npc_rename_dialog()


func _build_food_popup() -> void:
	_food_popup = PanelContainer.new()
	_food_popup.name = "FoodPickerPopup"
	_food_popup.custom_minimum_size = Vector2(240, 0)
	_food_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_food_popup.visible = false
	_apply_panel_style(_food_popup)
	add_child(_food_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_food_popup.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title := Label.new()
	title.text                  = "Select Food"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(_close_food_popup)
	_apply_icon_btn_style(close_btn)
	header.add_child(close_btn)

	_build_separator(vbox)

	_food_popup_flow = HFlowContainer.new()
	_food_popup_flow.name = "FoodPickerFlow"
	_food_popup_flow.add_theme_constant_override("h_separation", ItemGrid.BLOCK_GAP)
	_food_popup_flow.add_theme_constant_override("v_separation", ItemGrid.BLOCK_GAP)
	_food_popup_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	vbox.add_child(_food_popup_flow)


func _build_clear_tile() -> PanelContainer:
	return _build_picker_tile(&"", "")


func _build_food_tile(food_id: StringName, qty: int) -> PanelContainer:
	var qty_text: String = "×%d" % qty if qty > 0 else "×0"
	return _build_picker_tile(food_id, qty_text)


## Picker popup tile. Shows current STOCK (helps the player choose); the detail grid tiles show
## the required amount instead.
func _build_picker_tile(resource_id: StringName, sub_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, ItemGrid.BLOCK_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color            = ItemGrid.COLOR_BLOCK_BG
	style.set_border_width_all(1)
	style.border_color        = ItemGrid.COLOR_BLOCK_BORDER
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size   = Vector2(ItemGrid.ICON_SIZE, ItemGrid.ICON_SIZE)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	if resource_id == &"":
		var x_lbl := Label.new()
		x_lbl.text                 = "✕"
		x_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		x_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		x_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		x_lbl.add_theme_font_size_override("font_size", 28)
		x_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(x_lbl)
	else:
		var icon_rect := TextureRect.new()
		icon_rect.texture      = ResourceRegistry.get_icon_texture(resource_id, ItemGrid.ICON_SIZE / 2)
		icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(icon_rect)

	if sub_text != "":
		var sub_lbl := Label.new()
		sub_lbl.text                  = sub_text
		sub_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub_lbl.add_theme_font_size_override("font_size", 14)
		sub_lbl.add_theme_color_override("font_color", ItemGrid.COLOR_QTY_TEXT)
		sub_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(sub_lbl)

	panel.mouse_entered.connect(func() -> void: style.border_color = ItemGrid.COLOR_HOVER_BORDER)
	panel.mouse_exited.connect(func() -> void:  style.border_color = ItemGrid.COLOR_BLOCK_BORDER)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_food_selected(resource_id)
	)
	return panel

# ── Rename ───────────────────────────────────────────────────────────────────

func _on_rename_pressed() -> void:
	if _npc_id == &"":
		return
	_rename_input.text = NPCSystem.get_npc_display_name(_npc_id)
	_rename_input.select_all()
	_rename_dialog.visible = true
	_rename_input.grab_focus()


func _close_rename_dialog() -> void:
	if _rename_dialog != null:
		_rename_dialog.visible = false


func _on_rename_confirmed() -> void:
	var new_name := _rename_input.text.strip_edges()
	NPCSystem.rename_npc(_npc_id, new_name)
	_close_rename_dialog()


func _on_npc_renamed(npc_id: StringName, _new_name: String) -> void:
	if npc_id == _npc_id and visible:
		_panel.title = NPCSystem.get_npc_display_name(_npc_id)


func _build_npc_rename_dialog() -> void:
	_rename_dialog = PanelContainer.new()
	_rename_dialog.name = "NpcRenameDialog"
	_rename_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rename_dialog.custom_minimum_size = Vector2(260, 0)
	_rename_dialog.visible = false
	_apply_panel_style(_rename_dialog)
	add_child(_rename_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_rename_dialog.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "Rename NPC"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(title_lbl)

	_rename_input = LineEdit.new()
	_rename_input.name = "NpcRenameInput"
	_rename_input.placeholder_text = "Enter NPC name..."
	_rename_input.clear_button_enabled = true
	_rename_input.add_theme_font_size_override("font_size", 14)
	_rename_input.text_submitted.connect(func(_t: String) -> void: _on_rename_confirmed())
	vbox.add_child(_rename_input)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = "Rename"
	confirm_btn.custom_minimum_size = Vector2(100, 30)
	confirm_btn.focus_mode = Control.FOCUS_ALL
	confirm_btn.pressed.connect(_on_rename_confirmed)
	_apply_icon_btn_style(confirm_btn)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(80, 30)
	cancel_btn.focus_mode = Control.FOCUS_ALL
	cancel_btn.pressed.connect(_close_rename_dialog)
	_apply_icon_btn_style(cancel_btn)
	btn_row.add_child(cancel_btn)

# ── Style helpers ─────────────────────────────────────────────────────────────

func _build_separator(parent: Control) -> void:
	parent.add_child(StyleFactory.separator(COLOR_SEP))


func _apply_panel_style(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color                   = COLOR_BG
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left        = 14
	style.content_margin_right       = 14
	style.content_margin_top         = 12
	style.content_margin_bottom      = 12
	panel.add_theme_stylebox_override("panel", style)


func _apply_icon_btn_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = COLOR_BTN_HOVER if state == "hover" else COLOR_BTN_NORMAL.darkened(0.2)
		s.corner_radius_top_left     = 3
		s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left  = 3
		s.corner_radius_bottom_right = 3
		s.content_margin_left   = 5
		s.content_margin_right  = 5
		s.content_margin_top    = 4
		s.content_margin_bottom = 4
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 14)
