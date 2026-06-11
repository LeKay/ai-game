class_name NpcDetailPanel extends Control
## NPC Detail Panel — per-NPC food assignment and daily amount UI.
## Opened from the NPCs tab when clicking an NPC tile.
## All state writes go via signals; this panel is display-only.

signal food_assigned(npc_id: StringName, resource_id: StringName)
signal food_cleared(npc_id: StringName)
signal food_amount_changed(npc_id: StringName, amount: int)
signal panel_closed

## Food resource IDs the picker will offer (order = display order).
const FOOD_ITEM_IDS: Array[StringName] = [&"berry", &"bread"]
const PANEL_WIDTH   := 300
const PANEL_HEIGHT  := 300
const ANIM_DURATION := 0.12
## Horizontal shift applied after PRESET_CENTER so the panel sits right of the inventory modal.
## Matches InventoryScreen.MODAL_WIDTH / 2 (= 450) plus an 8 px gap.
const PANEL_LEFT_OFFSET := 458.0

## Override before adding to the scene tree to reposition the panel.
## Default keeps the panel to the right of the inventory modal.
## Set to 0.0 to center the panel (e.g. when opening from BuildingDetailPanel).
var panel_x_offset: float = PANEL_LEFT_OFFSET

const COLOR_BG         := Color(0.176, 0.176, 0.176, 0.97)
const COLOR_TEXT       := Color(0.941, 0.929, 0.902)
const COLOR_TEXT_DIM   := Color(0.659, 0.643, 0.612)
const COLOR_BTN_NORMAL := Color(0.353, 0.353, 0.353)
const COLOR_BTN_HOVER  := Color(0.290, 0.494, 0.659)
const COLOR_SEP        := Color(0.35, 0.35, 0.35, 1.0)

var _panel:           DraggableWindow
var _rename_btn:      Button
var _rename_dialog:   Control
var _rename_input:    LineEdit
var _npc_state_lbl:     Label
var _npc_efficiency_lbl: Label
var _food_slot_tile:  PanelContainer
var _food_slot_style: StyleBoxFlat
var _food_slot_icon:  Label
var _food_slot_qty:   Label
var _food_delta_lbl:  Label
var _amount_row:      Control
var _minus_btn:       Button
var _amount_label:    Label
var _plus_btn:        Button
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
	_refresh_food_slot()
	if not NPCSystem.npc_renamed.is_connected(_on_npc_renamed):
		NPCSystem.npc_renamed.connect(_on_npc_renamed)
	_animate_in()


func close() -> void:
	_close_food_popup()
	_close_rename_dialog()
	if NPCSystem.npc_renamed.is_connected(_on_npc_renamed):
		NPCSystem.npc_renamed.disconnect(_on_npc_renamed)
	_animate_out()
	panel_closed.emit()

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh_efficiency() -> void:
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc == null or _npc_efficiency_lbl == null:
		return
	var pct: int = roundi(npc.efficiency * 100.0)
	_npc_efficiency_lbl.text = "Efficiency: %d%%" % pct
	if npc.efficiency >= 1.0:
		_npc_efficiency_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
	elif npc.efficiency >= 0.5:
		_npc_efficiency_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
	else:
		_npc_efficiency_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))


func _refresh_food_slot() -> void:
	if _assigned_food == &"":
		_food_slot_icon.text   = "+"
		_food_slot_qty.visible = false
		_amount_row.visible    = false
		_refresh_food_delta()
		return
	var qty: int = InventorySystem.get_global_quantity(_assigned_food)
	_food_slot_icon.text   = _food_icon(_assigned_food)
	_food_slot_qty.text    = "×%d" % qty
	_food_slot_qty.visible = true
	_amount_label.text     = str(_food_amount)
	_amount_row.visible    = true
	_refresh_food_delta()


## Shows the potential efficiency delta above the food tile: +X% / -X% vs current locked efficiency.
## Hidden when no food is assigned.
func _refresh_food_delta() -> void:
	if _food_delta_lbl == null:
		return
	var npc: NPCSystem.NPCInstance = NPCSystem.get_npc_instance(_npc_id)
	if npc == null or _assigned_food == &"":
		_food_delta_lbl.visible = false
		return
	var food_mod := EfficiencyFormulas.calculate_food_modifier(_food_amount)
	var potential := EfficiencyFormulas.calculate_npc_efficiency(
			food_mod, npc.satisfaction_modifier, npc.equipment_modifier)
	var delta_pct := roundi((potential - npc.efficiency) * 100.0)
	if delta_pct > 0:
		_food_delta_lbl.text = "+%d%%" % delta_pct
		_food_delta_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
	elif delta_pct < 0:
		_food_delta_lbl.text = "%d%%" % delta_pct
		_food_delta_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	else:
		_food_delta_lbl.text = "±0%"
		_food_delta_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_food_delta_lbl.visible = true

# ── Food picker ───────────────────────────────────────────────────────────────

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
	_refresh_food_slot()

# ── Amount controls ───────────────────────────────────────────────────────────

func _on_minus_pressed() -> void:
	if _food_amount <= 1:
		return
	_food_amount -= 1
	_amount_label.text = str(_food_amount)
	food_amount_changed.emit(_npc_id, _food_amount)
	_refresh_food_delta()


func _on_plus_pressed() -> void:
	_food_amount += 1
	_amount_label.text = str(_food_amount)
	food_amount_changed.emit(_npc_id, _food_amount)
	_refresh_food_delta()

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

func _food_icon(resource_id: StringName) -> String:
	match resource_id:
		&"berry": return "🫐"
		&"bread": return "🍞"
		_:        return "🍽️"


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
	# Centre first (same pattern as TransportationPanel), then shift right of the inventory modal.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left  += panel_x_offset
	_panel.offset_right += panel_x_offset
	_panel.close_requested.connect(close)
	add_child(_panel)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 14)
	body_margin.add_theme_constant_override("margin_right", 14)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	_panel.content.add_child(body_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	body_margin.add_child(vbox)

	# NPC name lives in the DraggableWindow title bar (set in update()).
	# State + efficiency stay in the body; the window provides the close button.
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
	title_col.add_child(_npc_efficiency_lbl)

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

	# Food section label
	var food_lbl := Label.new()
	food_lbl.text = "Daily Food"
	food_lbl.add_theme_font_size_override("font_size", 12)
	food_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	vbox.add_child(food_lbl)

	# Efficiency delta label above food tile — hidden until food is assigned
	_food_delta_lbl = Label.new()
	_food_delta_lbl.visible = false
	_food_delta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_food_delta_lbl.add_theme_font_size_override("font_size", 13)
	_food_delta_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(_food_delta_lbl)

	# Food slot tile (click to open picker) — shrink to tile width, don't fill panel
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 0)
	slot_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(slot_row)

	_food_slot_tile = _build_food_slot_tile()
	slot_row.add_child(_food_slot_tile)

	# Amount controls row: [−]  n  [+]  — same width as food tile, hidden when no food assigned
	_amount_row = HBoxContainer.new()
	_amount_row.name = "AmountRow"
	_amount_row.visible = false
	_amount_row.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, 0)
	_amount_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_amount_row.add_theme_constant_override("separation", 0)
	vbox.add_child(_amount_row)

	_minus_btn = Button.new()
	_minus_btn.text = "−"
	_minus_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minus_btn.focus_mode = Control.FOCUS_ALL
	_minus_btn.pressed.connect(_on_minus_pressed)
	_apply_icon_btn_style(_minus_btn)
	_amount_row.add_child(_minus_btn)

	_amount_label = Label.new()
	_amount_label.text               = "1"
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_label.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_amount_label.add_theme_font_size_override("font_size", 15)
	_amount_label.add_theme_color_override("font_color", COLOR_TEXT)
	_amount_row.add_child(_amount_label)

	_plus_btn = Button.new()
	_plus_btn.text = "+"
	_plus_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plus_btn.focus_mode = Control.FOCUS_ALL
	_plus_btn.pressed.connect(_on_plus_pressed)
	_apply_icon_btn_style(_plus_btn)
	_amount_row.add_child(_plus_btn)

	_build_food_popup()
	_build_npc_rename_dialog()


func _build_food_slot_tile() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "FoodSlotTile"
	panel.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, ItemGrid.BLOCK_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_food_slot_style = StyleBoxFlat.new()
	_food_slot_style.bg_color            = ItemGrid.COLOR_BLOCK_BG
	_food_slot_style.border_width_left   = 1
	_food_slot_style.border_width_right  = 1
	_food_slot_style.border_width_top    = 1
	_food_slot_style.border_width_bottom = 1
	_food_slot_style.border_color        = ItemGrid.COLOR_BLOCK_BORDER
	panel.add_theme_stylebox_override("panel", _food_slot_style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size   = Vector2(ItemGrid.ICON_SIZE, ItemGrid.ICON_SIZE)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	_food_slot_icon = Label.new()
	_food_slot_icon.text                 = "+"
	_food_slot_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_food_slot_icon.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_food_slot_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_food_slot_icon.add_theme_font_size_override("font_size", 28)
	_food_slot_icon.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(_food_slot_icon)

	_food_slot_qty = Label.new()
	_food_slot_qty.text                  = ""
	_food_slot_qty.visible               = false
	_food_slot_qty.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_food_slot_qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_food_slot_qty.add_theme_font_size_override("font_size", 14)
	_food_slot_qty.add_theme_color_override("font_color", ItemGrid.COLOR_QTY_TEXT)
	_food_slot_qty.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_food_slot_qty)

	panel.mouse_entered.connect(func() -> void:
		_food_slot_style.border_color = ItemGrid.COLOR_HOVER_BORDER)
	panel.mouse_exited.connect(func() -> void:
		_food_slot_style.border_color = ItemGrid.COLOR_BLOCK_BORDER)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_food_popup()
	)

	return panel


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
	return _build_picker_tile(&"", "✕", "")


func _build_food_tile(food_id: StringName, qty: int) -> PanelContainer:
	var qty_text: String = "×%d" % qty if qty > 0 else "×0"
	return _build_picker_tile(food_id, _food_icon(food_id), qty_text)


func _build_picker_tile(resource_id: StringName, icon_text: String, sub_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ItemGrid.BLOCK_WIDTH, ItemGrid.BLOCK_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color            = ItemGrid.COLOR_BLOCK_BG
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
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

	var icon_lbl := Label.new()
	icon_lbl.text                 = icon_text
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_lbl.add_theme_font_size_override("font_size", 28)
	icon_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_lbl)

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
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color              = COLOR_SEP
	style.content_margin_top    = 0
	style.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", style)
	parent.add_child(sep)


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
