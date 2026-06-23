extends CanvasLayer
## DebugMenu — developer-only cheat overlay, toggled with F12.
##
## Autoload CanvasLayer. In an exported Release/Web build it removes itself in _ready()
## (see DebugSettings.is_available()), so players never see it and the F12 handler never runs.
##
## Flags live in the DebugSettings autoload; this panel is just their view/controller. The
## "Add resources" grid lists every resource with [− n +] controls (click = ±1, Shift+click
## = ±10, mirroring the NPC food-assignment UI) and deposits into / withdraws from colony
## storage. State is per-run only and is not saved.

const TOGGLE_KEY := KEY_F12
const STEP_SHIFT := 10
const PANEL_WIDTH := 360

const TILE_SIZE   := 56
const ICON_SIZE   := 40
const GRID_COLUMNS := 4

const COLOR_BG          := Color("#1E1E1E")
const COLOR_PANEL       := Color("#2A2A2A")
const COLOR_TEXT        := Color("#F0EDE6")
const COLOR_TEXT_DIM    := Color("#A8A49C")
const COLOR_BORDER      := Color("#4A4A4A")
const COLOR_HOVER       := Color("#4A7EA8")
const COLOR_ACCENT      := Color("#D4A85C")

var _root_panel: PanelContainer
var _resource_grid: GridContainer
## resource_id -> Label showing its current global quantity (updated in-place on +/-).
var _qty_labels: Dictionary = {}


func _ready() -> void:
	# Never exist outside a debug/editor build — keeps cheats out of shipped builds entirely.
	if not DebugSettings.is_available():
		queue_free()
		return
	layer = 128  # above all gameplay HUD layers
	_build_ui()
	_root_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == TOGGLE_KEY:
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not _root_panel.visible:
		return
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_root_panel.visible = false
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_root_panel.visible = not _root_panel.visible
	if _root_panel.visible:
		_refresh_quantities()


# ── Cheat actions ───────────────────────────────────────────────────────────────

func _on_ignore_costs_toggled(pressed: bool) -> void:
	DebugSettings.set_ignore_costs(pressed)


func _on_unlock_all_toggled(pressed: bool) -> void:
	DebugSettings.set_unlock_all_progression(pressed)


func _on_infinite_energy_toggled(pressed: bool) -> void:
	DebugSettings.set_no_energy_cost(pressed)
	if pressed:
		var player: Node = get_tree().get_first_node_in_group(&"player_character")
		if player != null:
			player.restore_energy(player.get_max_energy())


## Adds (delta > 0) or removes (delta < 0) up to abs(delta) units of resource_id from colony
## storage, one unit at a time so capacity limits across containers are respected.
func _on_resource_delta(resource_id: StringName, delta: int) -> void:
	if delta > 0:
		for _i in range(delta):
			if not _deposit_one(resource_id):
				break  # storage full — stop early
	elif delta < 0:
		for _i in range(-delta):
			if not _withdraw_one(resource_id):
				break  # none left
	_refresh_quantity(resource_id)


## Deposits a single unit into the first container that accepts it. Returns false if none did.
func _deposit_one(resource_id: StringName) -> bool:
	for container in InventorySystem.get_all_containers():
		var result: int = InventorySystem.try_deposit(container.container_id, resource_id, 1)
		if result == InventoryContainer.DepositResult.SUCCESS:
			return true
	return false


## Withdraws a single unit from any container holding it. Returns false if none held it.
func _withdraw_one(resource_id: StringName) -> bool:
	var container_id: StringName = InventorySystem.find_container_with(resource_id)
	if container_id == &"":
		return false
	return InventorySystem.try_consume(container_id, resource_id, 1) == InventoryContainer.ConsumeResult.SUCCESS


# ── UI construction ─────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root_panel.offset_left = 16
	_root_panel.offset_top = 16
	_root_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_apply_panel_style(_root_panel, COLOR_BG)
	add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_root_panel.add_child(vbox)

	var title := Label.new()
	title.text = "DEBUG MODE  (F12)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(title)

	vbox.add_child(_make_separator())

	vbox.add_child(_make_checkbox("Unlock all progression",
			DebugSettings.unlock_all_progression, _on_unlock_all_toggled))
	vbox.add_child(_make_checkbox("Ignore costs (build / craft / unlock)",
			DebugSettings.ignore_costs, _on_ignore_costs_toggled))
	vbox.add_child(_make_checkbox("Infinite energy (no cost)",
			DebugSettings.no_energy_cost, _on_infinite_energy_toggled))

	vbox.add_child(_make_separator())

	var res_title := Label.new()
	res_title.text = "Add resources   (Shift+click = ±10)"
	res_title.add_theme_font_size_override("font_size", 13)
	res_title.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	vbox.add_child(res_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_resource_grid = GridContainer.new()
	_resource_grid.columns = GRID_COLUMNS
	_resource_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_grid.add_theme_constant_override("h_separation", 8)
	_resource_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_resource_grid)

	_populate_resource_grid()


func _populate_resource_grid() -> void:
	_qty_labels.clear()
	for resource_id: StringName in ResourceRegistry.get_all_resource_ids():
		_resource_grid.add_child(_make_resource_cell(resource_id))


## One resource cell: icon tile with current stock, then a [− n +] amount row.
func _make_resource_cell(resource_id: StringName) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.tooltip_text = str(resource_id)
	_apply_panel_style(tile, COLOR_PANEL)

	var icon := TextureRect.new()
	icon.texture = ResourceRegistry.get_icon_texture(resource_id, ICON_SIZE / 2)
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.add_child(icon)
	cell.add_child(tile)

	var qty := Label.new()
	qty.text = "×%d" % InventorySystem.get_global_quantity(resource_id)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty.add_theme_font_size_override("font_size", 12)
	qty.add_theme_color_override("font_color", COLOR_TEXT)
	cell.add_child(qty)
	_qty_labels[resource_id] = qty

	cell.add_child(_make_amount_row(resource_id))
	return cell


## [− +] row. Click = ±1; holding Shift while clicking = ±STEP_SHIFT.
func _make_amount_row(resource_id: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var minus := Button.new()
	minus.text = "−"
	minus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(func() -> void: _on_resource_delta(resource_id, -_click_step()))
	_apply_btn_style(minus)
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "+"
	plus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(func() -> void: _on_resource_delta(resource_id, _click_step()))
	_apply_btn_style(plus)
	row.add_child(plus)
	return row


## Step size for the current click: ±10 while Shift is held, otherwise ±1.
func _click_step() -> int:
	return STEP_SHIFT if Input.is_key_pressed(KEY_SHIFT) else 1


func _make_checkbox(label: String, pressed: bool, on_toggled: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = pressed
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_color_override("font_color", COLOR_TEXT)
	cb.add_theme_font_size_override("font_size", 14)
	cb.toggled.connect(on_toggled)
	return cb


func _make_separator() -> Control:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BORDER
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", style)
	return sep


# ── Refresh ──────────────────────────────────────────────────────────────────

func _refresh_quantities() -> void:
	for resource_id: StringName in _qty_labels:
		_refresh_quantity(resource_id)


func _refresh_quantity(resource_id: StringName) -> void:
	var lbl: Label = _qty_labels.get(resource_id, null)
	if lbl != null:
		lbl.text = "×%d" % InventorySystem.get_global_quantity(resource_id)


# ── Style helpers ────────────────────────────────────────────────────────────

func _apply_panel_style(panel: PanelContainer, bg: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(1)
	style.border_color = COLOR_BORDER
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)


func _apply_btn_style(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = COLOR_HOVER if state == "hover" else COLOR_BORDER.darkened(0.2)
		s.set_corner_radius_all(3)
		s.content_margin_top = 2
		s.content_margin_bottom = 2
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_font_size_override("font_size", 16)
