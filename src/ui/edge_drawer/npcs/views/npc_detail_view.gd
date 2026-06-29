class_name NpcDetailView extends Control
## Detail view for a single worker inside the NPCs Drawer.
## Structural + visual sibling of BuildingDetailView: back-bar, inline-rename name row, and a
## header whose Efficiency / state readout matches the building header. Below the header sits the
## supply grid (Daily Food + perks), ported from the legacy NpcDetailPanel.
##
## All write actions go straight to the autoload systems (NPCSystem / HungerSystem) — matching the
## existing NPC UI convention. The view owns no game state.
##
## See: building_detail_view.gd (header/name template), npc_detail_panel.gd (supply logic origin).

# ── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the player taps the ← back button.
signal back_pressed()
## Emitted when the player taps the ✕ close button.
signal close_pressed()

# ── Constants (shared with BuildingDetailView for visual parity) ──────────────

const COLOR_SEPARATOR := Color(0.25, 0.26, 0.30, 1.0)
const COLOR_TEXT      := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_TEXT_DIM  := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_ACCENT    := Color(0.30, 0.70, 1.00, 1.0)

const COLOR_XP_BAR_BG   := Color("#2A2A2A")
const COLOR_XP_BAR_FILL := Color("#D4A85C")
const COLOR_XP_BAR_MAX  := Color("#E8C860")
const COLOR_DISABLED    := Color(0.5, 0.5, 0.5, 0.45)

## Food resource IDs the picker will offer (order = display order).
const FOOD_ITEM_IDS: Array[StringName] = [&"berry", &"bread"]

# ── Node refs ─────────────────────────────────────────────────────────────────

var _name_label:     Label
var _rename_btn:     Button
var _rename_edit:    LineEdit
var _rename_confirm: Button
var _rename_cancel:  Button

var _eff_label:      Label
var _state_dot:      ColorRect
var _state_label:    Label
var _level_label:    Label
var _levelup_btn:    Button
var _xp_label:       Label
var _xp_bar_fill:    ColorRect

var _profession_lbl: Label
var _supply_grid:    GridContainer

var _food_backdrop:  ColorRect
var _food_popup:     PanelContainer
var _food_popup_flow: HFlowContainer

# ── State ─────────────────────────────────────────────────────────────────────

var _npc_id:        StringName = &""
var _assigned_food: StringName = &""
var _food_amount:   int = 1
var _is_rename_active: bool = false

## State index → label, matching NpcGrid / NpcDetailPanel.
const STATE_LABELS: Array[String] = [
	"Idle", "Travelling", "Working", "Returning", "Depositing", "Returning", "Waiting",
]
const STATE_COLORS: Array[Color] = [
	Color("#808080"), Color("#D4A85C"), Color("#4CAF50"), Color("#D4A85C"),
	Color("#4CAF50"), Color("#D4A85C"), Color("#E05555"),
]

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 8)
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_spacer)
	vbox.add_child(_build_back_bar())
	vbox.add_child(_make_separator())
	vbox.add_child(_build_header())
	vbox.add_child(_make_separator())

	_profession_lbl = Label.new()
	_profession_lbl.add_theme_font_size_override("font_size", 12)
	_profession_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	_profession_lbl.visible = false
	var prof_pad := MarginContainer.new()
	prof_pad.add_theme_constant_override("margin_left", 14)
	prof_pad.add_theme_constant_override("margin_right", 14)
	prof_pad.add_theme_constant_override("margin_top", 6)
	prof_pad.add_child(_profession_lbl)
	vbox.add_child(prof_pad)

	# Supply grid: Daily Food + perks, 2 columns, scrollable.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	var grid_pad := MarginContainer.new()
	grid_pad.add_theme_constant_override("margin_left", 14)
	grid_pad.add_theme_constant_override("margin_right", 14)
	grid_pad.add_theme_constant_override("margin_top", 8)
	grid_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_pad)

	_supply_grid = GridContainer.new()
	_supply_grid.columns = 2
	_supply_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_supply_grid.add_theme_constant_override("h_separation", 14)
	_supply_grid.add_theme_constant_override("v_separation", 12)
	grid_pad.add_child(_supply_grid)
	vbox.add_child(scroll)

	var levelup_pad := MarginContainer.new()
	levelup_pad.add_theme_constant_override("margin_left", 14)
	levelup_pad.add_theme_constant_override("margin_right", 14)
	levelup_pad.add_theme_constant_override("margin_top", 6)
	levelup_pad.add_theme_constant_override("margin_bottom", 12)
	vbox.add_child(levelup_pad)

	_levelup_btn = Button.new()
	_levelup_btn.text         = "Level up"
	_levelup_btn.tooltip_text = "Level up this worker"
	_levelup_btn.focus_mode   = Control.FOCUS_ALL
	_levelup_btn.visible      = false
	_levelup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_levelup_btn.pressed.connect(_on_levelup_pressed)
	levelup_pad.add_child(_levelup_btn)

	_build_food_popup()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_disconnect_signals()


func _input(event: InputEvent) -> void:
	if not _is_rename_active:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_submit_rename()
		accept_event()
	elif key.keycode == KEY_ESCAPE:
		_cancel_rename()
		accept_event()


# ── Public API ────────────────────────────────────────────────────────────────

## Loads data for [param npc_id] and refreshes the whole view.
func setup(npc_id: StringName) -> void:
	_cancel_rename()
	_close_food_popup()
	_npc_id        = npc_id
	_assigned_food = HungerSystem.get_assigned_food(npc_id)
	_food_amount   = HungerSystem.get_food_amount(npc_id)
	_connect_signals()
	refresh()


## Re-reads name / efficiency / XP / state / supply from the systems.
func refresh() -> void:
	if _npc_id == &"":
		return
	_name_label.text = NPCSystem.get_npc_display_name(_npc_id)
	_refresh_state()
	_refresh_efficiency()
	_refresh_xp()
	_refresh_supply()


## True while the inline rename LineEdit or the food popup is active — lets the drawer
## route ESC to this view first.
func wants_escape() -> bool:
	return _is_rename_active or (_food_popup != null and _food_popup.visible)


## Consumes ESC: cancels rename or closes the food popup. Returns false if neither was active.
func handle_escape() -> bool:
	if _is_rename_active:
		_cancel_rename()
		return true
	if _food_popup != null and _food_popup.visible:
		_close_food_popup()
		return true
	return false


## Cancels any active inline editor (called by the drawer when leaving this view).
func cancel_editors() -> void:
	_cancel_rename()
	_close_food_popup()

# ── Signal wiring ──────────────────────────────────────────────────────────────

func _connect_signals() -> void:
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


func _disconnect_signals() -> void:
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


func _on_npc_renamed(npc_id: StringName, _new_name: String) -> void:
	if npc_id == _npc_id:
		_name_label.text = NPCSystem.get_npc_display_name(_npc_id)


func _on_npc_xp_gained(npc_id: StringName, _total: int, _into: int, _span: int) -> void:
	if npc_id == _npc_id:
		_refresh_xp()


func _on_npc_leveled_up(npc_id: StringName, _new_level: int) -> void:
	if npc_id == _npc_id:
		_refresh_xp()


func _on_npc_perk_chosen(npc_id: StringName, _perk_id: StringName) -> void:
	if npc_id == _npc_id:
		_refresh_supply()
		_refresh_levelup_btn()


func _on_npc_level_cap_changed(_cap: int) -> void:
	_refresh_levelup_btn()

# ── Header refresh (state / efficiency / XP) ───────────────────────────────────

func _refresh_state() -> void:
	var s: int = clampi(NPCSystem.get_npc_state(_npc_id), 0, STATE_LABELS.size() - 1)
	_state_label.text = STATE_LABELS[s]
	_state_dot.color  = STATE_COLORS[s]


func _refresh_efficiency() -> void:
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc == null or _eff_label == null:
		return
	var pct: int = roundi(npc.efficiency * 100.0)
	var text: String = "Eff: %d%%" % pct
	# Pending change: realized efficiency only updates at the next day transition, so preview the
	# delta from the currently SELECTED food + amount as "(+/−X%)".
	var delta_pct: int = roundi(_projected_efficiency(npc) * 100.0) - pct
	if delta_pct != 0:
		text += " (%+d%%)" % delta_pct
	_eff_label.text = text
	_eff_label.tooltip_text = _efficiency_tooltip(npc)
	if npc.efficiency >= 1.0:
		_eff_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
	elif npc.efficiency >= 0.5:
		_eff_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
	else:
		_eff_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))


func _refresh_xp() -> void:
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc == null or _level_label == null:
		return
	_level_label.text = "Level %d" % npc.level
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
		panel.begin_for_npc(_npc_id)
	_refresh_xp()

# ── Supply grid (Daily Food + perks) ────────────────────────────────────────────

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
		var in_stock: int = InventorySystem.get_global_quantity(_assigned_food)
		var enabled: bool = not active and _food_amount > 0 and in_stock >= _food_amount
		var btn_tip: String = "Consume the assigned food from inventory and apply efficiency now." if enabled \
			else ("Already consumed at the last day change." if active else "Not enough food in storage.")
		cell.add_child(_make_consume_button(enabled, btn_tip, _on_food_consume_pressed))
	return cell


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
	var assigned: int = int(perk.get(&"amount", 1))
	cell.add_child(_make_amount_row(assigned, func(d: int) -> void: _on_perk_amount_changed(index, d)))

	var in_stock: int = InventorySystem.get_global_quantity(good) if good != &"" else 0
	var enabled: bool = not active and good != &"" and assigned >= required and in_stock >= assigned
	var btn_tip: String
	if active:
		btn_tip = "Perk is already active — consumed at the last day change."
	elif good == &"":
		btn_tip = "This perk has no good to consume."
	elif assigned < required:
		btn_tip = "Assign at least the required amount first."
	elif in_stock < assigned:
		btn_tip = "Not enough of the good in storage."
	else:
		btn_tip = "Consume the good from inventory and activate this perk now."
	cell.add_child(_make_consume_button(enabled, btn_tip, func() -> void: _on_perk_consume_pressed(index)))
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
	row.add_child(plus)
	return row


## "Consume" button under a supply tile — exactly tile-width, aligned with the [− n +] row above.
## Disabled (greyed) when the supply cannot be consumed right now (see per-cell builders).
func _make_consume_button(enabled: bool, tooltip: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = "Consume"
	btn.disabled = not enabled
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size   = Vector2(ItemGrid.BLOCK_WIDTH, 0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.add_theme_font_size_override("font_size", 12)
	if enabled:
		btn.pressed.connect(on_pressed)
	return btn

# ── Efficiency math (ported from NpcDetailPanel) ────────────────────────────────

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
	if floor_eff >= _npc_max_efficiency():
		return 0
	var needed_nutrition: float = EfficiencyFormulas.nutrition_for_full(level, eff_cap_bonus) - perk_nutrition
	return maxi(0, ceili(needed_nutrition / nut))


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


func _efficiency_tooltip(npc: NPCSystem.NPCInstance) -> String:
	var floor_base: float = EfficiencyFormulas.NUTRITION_UNFED_EFFICIENCY
	var cap: float = EfficiencyFormulas.nutrition_bonus_cap(
			int(npc.level), NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_NPC_EFF_CAP))
	var hardy: float = NPCSystem.npc_perk_bonus(_npc_id, PerkRegistry.EFFECT_UNFED_FLOOR)
	var e_food: float = EfficiencyFormulas.BASE_NPC_EFFICIENCY * npc.food_modifier
	var binding_floor: float = floor_base
	var food_bonus: float = maxf(0.0, e_food - floor_base)
	if hardy > 0.0 and hardy >= e_food - 0.0001:
		binding_floor = hardy
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

# ── Consume / amount handlers ───────────────────────────────────────────────────

## Per-tile "Consume" for the Daily Food cell: immediately feeds the assigned food (extra ration;
## the daily auto-consumption still runs at the next day change).
func _on_food_consume_pressed() -> void:
	if HungerSystem.feed_npc_now(_npc_id):
		_refresh_efficiency()
		_refresh_supply()


## Per-tile "Consume" for a perk cell: immediately consumes the perk's good and activates it now.
func _on_perk_consume_pressed(index: int) -> void:
	if NPCSystem.consume_perk_now(_npc_id, index):
		_refresh_efficiency()
		_refresh_supply()


func _on_food_amount_delta(delta: int) -> void:
	if _assigned_food == &"":
		return
	_food_amount = maxi(0, _food_amount + delta)
	HungerSystem.set_food_amount(_npc_id, _food_amount)
	_refresh_efficiency()
	_refresh_supply()


func _on_perk_amount_changed(index: int, delta: int) -> void:
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc == null or index < 0 or index >= npc.perks.size():
		return
	var current: int = int((npc.perks[index] as Dictionary).get(&"amount", 1))
	NPCSystem.set_perk_amount(_npc_id, index, current + delta)
	_refresh_efficiency()
	_refresh_supply()

# ── Food picker popup ───────────────────────────────────────────────────────────

func _open_food_popup() -> void:
	for child in _food_popup_flow.get_children():
		child.queue_free()
	_food_popup_flow.add_child(_build_picker_tile(&"", ""))
	for food_id: StringName in FOOD_ITEM_IDS:
		var qty: int = InventorySystem.get_global_quantity(food_id)
		_food_popup_flow.add_child(_build_picker_tile(food_id, "×%d" % qty))
	_food_backdrop.visible = true
	_food_popup.visible = true


func _close_food_popup() -> void:
	if _food_popup != null:
		_food_popup.visible = false
	if _food_backdrop != null:
		_food_backdrop.visible = false


func _on_food_selected(resource_id: StringName) -> void:
	_close_food_popup()
	if resource_id == &"":
		_assigned_food = &""
		_food_amount   = 1
		HungerSystem.clear_food_assignment(_npc_id)
	else:
		_assigned_food = resource_id
		HungerSystem.assign_food(_npc_id, resource_id)
		var req := _food_required()
		_food_amount = maxi(1, req)
		HungerSystem.set_food_amount(_npc_id, _food_amount)
	_refresh_efficiency()
	_refresh_supply()

# ── Rename in-place (mirrors BuildingDetailView) ────────────────────────────────

func _build_rename_inline() -> void:
	_is_rename_active = true
	_name_label.visible     = false
	_rename_btn.visible     = false
	_rename_edit.text       = _name_label.text
	_rename_edit.visible    = true
	_rename_confirm.visible = true
	_rename_cancel.visible  = true
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _submit_rename() -> void:
	var new_name: String = _rename_edit.text.strip_edges()
	if new_name != "" and new_name != _name_label.text:
		NPCSystem.rename_npc(_npc_id, new_name)
		_name_label.text = new_name
	_cancel_rename()


func _cancel_rename() -> void:
	_is_rename_active = false
	if _rename_edit != null:
		_rename_edit.visible    = false
		_rename_confirm.visible = false
		_rename_cancel.visible  = false
		_name_label.visible     = true
		_rename_btn.visible     = true

# ── UI construction ─────────────────────────────────────────────────────────────

func _build_back_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "BackBar"
	bar.custom_minimum_size = Vector2(0, 28)
	bar.add_theme_constant_override("separation", 4)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.14, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)

	var btn := Button.new()
	btn.name = "BackButton"
	btn.text = "← Back"
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", COLOR_ACCENT)
	btn.add_theme_color_override("font_hover_color", COLOR_TEXT)
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void: back_pressed.emit())
	bar.add_child(btn)

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

	return bar


func _build_header() -> Control:
	var pad := MarginContainer.new()
	pad.name = "Header"
	pad.add_theme_constant_override("margin_left",  8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top",   6)
	pad.add_theme_constant_override("margin_bottom",6)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	pad.add_child(inner)

	inner.add_child(_build_name_row())

	# ── Icon + stats ──────────────────────────────────────────────────────────
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	inner.add_child(row)

	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(56, 56)
	icon_wrap.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_wrap)

	var icon_glyph := Label.new()
	icon_glyph.name                 = "IconGlyph"
	icon_glyph.text                 = "🧑"
	icon_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_glyph.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon_glyph.add_theme_font_size_override("font_size", 32)
	icon_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_wrap.add_child(icon_glyph)

	# Stats column
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(stats)

	_eff_label = Label.new()
	_eff_label.name = "EffLabel"
	_eff_label.add_theme_font_size_override("font_size", 12)
	_eff_label.add_theme_color_override("font_color", COLOR_TEXT)
	_eff_label.text = "Eff: —"
	_eff_label.mouse_filter = Control.MOUSE_FILTER_STOP  # needed for the hover tooltip
	stats.add_child(_eff_label)

	# State row (dot + text)
	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 4)
	stats.add_child(state_row)

	_state_dot = ColorRect.new()
	_state_dot.name                = "StateDot"
	_state_dot.custom_minimum_size = Vector2(8, 8)
	_state_dot.color               = Color(0.6, 0.6, 0.6)
	_state_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state_row.add_child(_state_dot)

	_state_label = Label.new()
	_state_label.name = "StateLabel"
	_state_label.add_theme_font_size_override("font_size", 11)
	_state_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	state_row.add_child(_state_label)

	# Level row (the level-up action lives in a dedicated button at the bottom of the view).
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	stats.add_child(level_row)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 12)
	_level_label.add_theme_color_override("font_color", COLOR_XP_BAR_MAX)
	level_row.add_child(_level_label)

	_xp_label = Label.new()
	_xp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	level_row.add_child(_xp_label)

	# XP progress bar
	var xp_outer := Control.new()
	xp_outer.custom_minimum_size   = Vector2(0, 6)
	xp_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_outer.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	stats.add_child(xp_outer)

	var xp_bg := ColorRect.new()
	xp_bg.color        = COLOR_XP_BAR_BG
	xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	xp_outer.add_child(xp_bg)

	_xp_bar_fill = ColorRect.new()
	_xp_bar_fill.color         = COLOR_XP_BAR_FILL
	_xp_bar_fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_xp_bar_fill.anchor_left   = 0.0
	_xp_bar_fill.anchor_top    = 0.0
	_xp_bar_fill.anchor_right  = 0.0
	_xp_bar_fill.anchor_bottom = 1.0
	_xp_bar_fill.offset_right  = 0.0
	xp_outer.add_child(_xp_bar_fill)

	return pad


func _build_name_row() -> Control:
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 4)

	_name_label = Label.new()
	_name_label.name                = "NameLabel"
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text             = true
	name_row.add_child(_name_label)

	_rename_btn = Button.new()
	_rename_btn.name = "RenameBtn"
	_rename_btn.text = "✏️"
	_rename_btn.flat = true
	_rename_btn.tooltip_text = "Rename worker"
	_rename_btn.add_theme_font_size_override("font_size", 12)
	_rename_btn.pressed.connect(_build_rename_inline)
	name_row.add_child(_rename_btn)

	_rename_edit = LineEdit.new()
	_rename_edit.name                  = "RenameEdit"
	_rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_edit.placeholder_text      = "Worker name…"
	_rename_edit.add_theme_font_size_override("font_size", 13)
	_rename_edit.visible               = false
	name_row.add_child(_rename_edit)

	_rename_confirm = Button.new()
	_rename_confirm.name    = "RenameConfirm"
	_rename_confirm.text    = "✓"
	_rename_confirm.flat    = true
	_rename_confirm.visible = false
	_rename_confirm.add_theme_color_override("font_color", Color(0.298, 0.686, 0.314))
	_rename_confirm.pressed.connect(_submit_rename)
	name_row.add_child(_rename_confirm)

	_rename_cancel = Button.new()
	_rename_cancel.name    = "RenameCancel"
	_rename_cancel.text    = "✕"
	_rename_cancel.flat    = true
	_rename_cancel.visible = false
	_rename_cancel.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_rename_cancel.pressed.connect(_cancel_rename)
	name_row.add_child(_rename_cancel)

	return name_row


func _build_food_popup() -> void:
	# Click-catching backdrop (closes the popup); transparent.
	_food_backdrop = ColorRect.new()
	_food_backdrop.name         = "FoodBackdrop"
	_food_backdrop.color        = Color(0.0, 0.0, 0.0, 0.25)
	_food_backdrop.visible      = false
	_food_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_food_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_food_backdrop.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_close_food_popup()
	)
	add_child(_food_backdrop)

	_food_popup = PanelContainer.new()
	_food_popup.name = "FoodPickerPopup"
	_food_popup.custom_minimum_size = Vector2(240, 0)
	_food_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_food_popup.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.16, 0.98)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.30, 0.70, 1.0, 0.5)
	sb.corner_radius_top_left     = 4
	sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_left  = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 12
	sb.content_margin_bottom = 12
	_food_popup.add_theme_stylebox_override("panel", sb)
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
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(_close_food_popup)
	header.add_child(close_btn)

	vbox.add_child(_make_separator())

	_food_popup_flow = HFlowContainer.new()
	_food_popup_flow.name = "FoodPickerFlow"
	_food_popup_flow.add_theme_constant_override("h_separation", ItemGrid.BLOCK_GAP)
	_food_popup_flow.add_theme_constant_override("v_separation", ItemGrid.BLOCK_GAP)
	_food_popup_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	vbox.add_child(_food_popup_flow)


## Picker popup tile — shows current STOCK (helps the player choose); detail tiles show required.
func _build_picker_tile(resource_id: StringName, sub_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, ItemGrid.BLOCK_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

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


func _make_separator() -> Control:
	var sep := ColorRect.new()
	sep.color               = COLOR_SEPARATOR
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	return sep
