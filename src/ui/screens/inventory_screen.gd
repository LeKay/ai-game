class_name InventoryScreen extends CanvasLayer
## Inventory modal overlay — implements design/ux/inventory.md.
## Zone 1: tab bar | Zone 2: capacity bar | Zone 3: scrollable item grid.
## Toggle with I. Pauses TickSystem while open.
## Emits inventory_opened / inventory_closed for HUD storage panel wiring.
##
## Note: CanvasLayer has no modulate property. _panel_root (Control) is used
## as the single fade target for open/close animations.

signal inventory_opened()
signal inventory_closed()
signal build_mode_requested(building_type: int)
signal path_mode_requested()
signal demolish_mode_requested()

const MODAL_WIDTH      := 900
const MODAL_MIN_HEIGHT := 300
const MODAL_MAX_HEIGHT := 600

const COLOR_BACKDROP          := Color(0.0, 0.0, 0.0, 0.4)
const COLOR_MODAL_BG          := Color("#1a1a1a")
const COLOR_DIVIDER           := Color("#333333")
const COLOR_TAB_ACTIVE_BG     := Color("#F0EDE6")
const COLOR_TAB_ACTIVE_TEXT   := Color("#3A3A3A")
const COLOR_TAB_INACTIVE_BG   := Color("#5A5A5A")
const COLOR_TAB_INACTIVE_TEXT := Color("#A8A49C")
const COLOR_CAP_GREEN         := Color("#4CAF50")
const COLOR_CAP_AMBER         := Color("#D4A85C")
const COLOR_CAP_RED           := Color("#E05555")

const ANIM_OPEN_SEC  := 0.10
const ANIM_CLOSE_SEC := 0.08

const TABS: Array[String] = ["Inventory", "Crafting", "NPCs"]

var _is_open:    bool = false
var _active_tab: int  = 0  ## Default to Inventory.

## Root Control — single fade target (CanvasLayer has no modulate).
var _panel_root: Control
var _backdrop:   ColorRect
var _modal:      PanelContainer
var _tab_buttons: Array[Button] = []

var _capacity_label:    Label
var _capacity_bar_fill: ColorRect

var _zone3_vbox:     VBoxContainer
var _item_grid:      ItemGrid
var _crafting_grid:  CraftingGrid
var _npc_grid:        NpcGrid
var _npc_detail_panel: NpcDetailPanel
var _crafting_gate_label: Label
var _crafting_bench_dropdown: OptionButton

var _open_tween:       Tween = null
var _pulse_tween:      Tween = null
var _is_pulsing:       bool  = false
var _was_paused_before_open: bool = false


func _ready() -> void:
	layer = 10
	add_to_group(&"inventory_screen")
	_build_ui()
	_connect_signals()


func _exit_tree() -> void:
	if InventorySystem.storage_changed.is_connected(_on_inventory_changed):
		InventorySystem.storage_changed.disconnect(_on_inventory_changed)
	if InventorySystem.container_capacity_changed.is_connected(_on_capacity_changed):
		InventorySystem.container_capacity_changed.disconnect(_on_capacity_changed)
	if CraftingRegistry.crafting_started.is_connected(_on_crafting_started):
		CraftingRegistry.crafting_started.disconnect(_on_crafting_started)
	if CraftingRegistry.crafting_progress.is_connected(_on_crafting_progress):
		CraftingRegistry.crafting_progress.disconnect(_on_crafting_progress)
	if CraftingRegistry.recipe_crafted.is_connected(_on_crafting_completed):
		CraftingRegistry.recipe_crafted.disconnect(_on_crafting_completed)
	if BuildingRegistry.upgrade_installed.is_connected(_on_upgrade_changed_iv):
		BuildingRegistry.upgrade_installed.disconnect(_on_upgrade_changed_iv)
	if BuildingRegistry.upgrade_removed.is_connected(_on_upgrade_changed_iv):
		BuildingRegistry.upgrade_removed.disconnect(_on_upgrade_changed_iv)
	if ProgressionSystem.node_unlocked.is_connected(_on_progression_unlocked):
		ProgressionSystem.node_unlocked.disconnect(_on_progression_unlocked)
	var npc_sys: Node = NPCSystem
	if npc_sys != null:
		if npc_sys.npc_recruited.is_connected(_on_npc_recruited_iv):
			npc_sys.npc_recruited.disconnect(_on_npc_recruited_iv)
		if npc_sys.npc_removed.is_connected(_on_npc_sn_iv):
			npc_sys.npc_removed.disconnect(_on_npc_sn_iv)
		if npc_sys.npc_released.is_connected(_on_npc_sn_iv):
			npc_sys.npc_released.disconnect(_on_npc_sn_iv)
		if npc_sys.npc_assigned.is_connected(_on_npc_sn_sn_iv):
			npc_sys.npc_assigned.disconnect(_on_npc_sn_sn_iv)
		if npc_sys.npc_returned_home.is_connected(_on_npc_sn_iv):
			npc_sys.npc_returned_home.disconnect(_on_npc_sn_iv)
		if npc_sys.npc_renamed.is_connected(_on_npc_sn_sn_iv):
			npc_sys.npc_renamed.disconnect(_on_npc_sn_sn_iv)
		if npc_sys.npc_xp_gained.is_connected(_on_npc_xp_gained_iv):
			npc_sys.npc_xp_gained.disconnect(_on_npc_xp_gained_iv)
		if npc_sys.npc_leveled_up.is_connected(_on_npc_leveled_up_iv):
			npc_sys.npc_leveled_up.disconnect(_on_npc_leveled_up_iv)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_I or key.keycode == KEY_TAB:
		_toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and _is_open:
		_close()
		get_viewport().set_input_as_handled()


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel_root = Control.new()
	_panel_root.name         = "PanelRoot"
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.visible = false
	add_child(_panel_root)

	_backdrop = ColorRect.new()
	_backdrop.name         = "Backdrop"
	_backdrop.color        = COLOR_BACKDROP
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_on_backdrop_input)
	_panel_root.add_child(_backdrop)

	_modal = PanelContainer.new()
	_modal.name = "Modal"

	var modal_style := StyleBoxFlat.new()
	modal_style.bg_color                   = COLOR_MODAL_BG
	modal_style.corner_radius_top_left     = 4
	modal_style.corner_radius_top_right    = 4
	modal_style.corner_radius_bottom_left  = 4
	modal_style.corner_radius_bottom_right = 4
	modal_style.content_margin_left        = 0
	modal_style.content_margin_right       = 0
	modal_style.content_margin_top         = 0
	modal_style.content_margin_bottom      = 0
	_modal.add_theme_stylebox_override("panel", modal_style)

	_modal.anchor_left   = 0.5
	_modal.anchor_right  = 0.5
	_modal.anchor_top    = 0.5
	_modal.anchor_bottom = 0.5
	_modal.offset_left   = -MODAL_WIDTH / 2.0
	_modal.offset_right  =  MODAL_WIDTH / 2.0
	_modal.offset_top    = -MODAL_MAX_HEIGHT / 2.0
	_modal.offset_bottom =  MODAL_MAX_HEIGHT / 2.0
	_panel_root.add_child(_modal)

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "RootVBox"
	root_vbox.add_theme_constant_override("separation", 0)
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(root_vbox)

	_build_zone1(root_vbox)
	_add_divider(root_vbox)
	_build_zone2(root_vbox)
	_add_divider(root_vbox)
	_build_zone3(root_vbox)


func _build_zone1(parent: VBoxContainer) -> void:
	var tab_bar := HBoxContainer.new()
	tab_bar.name = "TabBar"
	tab_bar.custom_minimum_size = Vector2(0, 40)
	tab_bar.add_theme_constant_override("separation", 0)
	parent.add_child(tab_bar)

	for i: int in range(TABS.size()):
		var btn := Button.new()
		btn.name                = "Tab_%s" % TABS[i]
		btn.text                = TABS[i]
		btn.custom_minimum_size = Vector2(110, 40)
		btn.focus_mode          = Control.FOCUS_NONE
		btn.pressed.connect(_on_tab_pressed.bind(i))
		tab_bar.add_child(btn)
		_tab_buttons.append(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	tab_bar.add_child(spacer)

	var close_btn := Button.new()
	close_btn.name                = "CloseBtn"
	close_btn.text                = "×"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.focus_mode          = Control.FOCUS_NONE
	close_btn.pressed.connect(_close)
	tab_bar.add_child(close_btn)

	_apply_tab_styles()


func _build_zone2(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "CapacityRow"
	row.custom_minimum_size = Vector2(0, 36)
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var left_pad := Control.new()
	left_pad.custom_minimum_size = Vector2(16, 0)
	left_pad.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(left_pad)

	_capacity_label = Label.new()
	_capacity_label.name                = "CapacityLabel"
	_capacity_label.text                = "Storage: 0 / 0  0%"
	_capacity_label.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	_capacity_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_capacity_label.add_theme_font_size_override("font_size", 14)
	row.add_child(_capacity_label)

	var bar_outer := Control.new()
	bar_outer.name                  = "CapBarOuter"
	bar_outer.custom_minimum_size   = Vector2(200, 12)
	bar_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_outer.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	bar_outer.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_outer)

	var bar_bg := ColorRect.new()
	bar_bg.color        = Color("#333333")
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_outer.add_child(bar_bg)

	_capacity_bar_fill = ColorRect.new()
	_capacity_bar_fill.name          = "CapFill"
	_capacity_bar_fill.color         = COLOR_CAP_GREEN
	_capacity_bar_fill.anchor_left   = 0.0
	_capacity_bar_fill.anchor_right  = 0.0
	_capacity_bar_fill.anchor_top    = 0.0
	_capacity_bar_fill.anchor_bottom = 1.0
	_capacity_bar_fill.offset_right  = 0
	_capacity_bar_fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	bar_outer.add_child(_capacity_bar_fill)

	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(16, 0)
	right_pad.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(right_pad)


func _build_zone3(parent: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.name                = "Zone3Margin"
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	parent.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.name                   = "Zone3Scroll"
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	_zone3_vbox = VBoxContainer.new()
	_zone3_vbox.name                  = "Zone3VBox"
	_zone3_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_zone3_vbox)

	_item_grid = ItemGrid.new()
	_item_grid.name = "ItemGrid"
	_zone3_vbox.add_child(_item_grid)

	_crafting_gate_label = Label.new()
	_crafting_gate_label.name                = "CraftingGateLabel"
	_crafting_gate_label.text                = "Create a crafting bench in a storage building to start crafting."
	_crafting_gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crafting_gate_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crafting_gate_label.add_theme_font_size_override("font_size", 14)
	_crafting_gate_label.autowrap_mode       = TextServer.AUTOWRAP_WORD_SMART
	_crafting_gate_label.visible             = false
	_zone3_vbox.add_child(_crafting_gate_label)

	_crafting_bench_dropdown = OptionButton.new()
	_crafting_bench_dropdown.name    = "CraftingBenchDropdown"
	_crafting_bench_dropdown.visible = false
	_crafting_bench_dropdown.item_selected.connect(_on_crafting_bench_selected)
	_zone3_vbox.add_child(_crafting_bench_dropdown)

	_crafting_grid = CraftingGrid.new()
	_crafting_grid.name    = "CraftingGrid"
	_crafting_grid.visible = false
	_zone3_vbox.add_child(_crafting_grid)

	_npc_grid = NpcGrid.new()
	_npc_grid.name    = "NpcGrid"
	_npc_grid.center  = true
	_npc_grid.visible = false
	_zone3_vbox.add_child(_npc_grid)

	_npc_detail_panel = NpcDetailPanel.new()
	_npc_detail_panel.name = "NpcDetailPanel"
	_panel_root.add_child(_npc_detail_panel)


func _add_divider(parent: VBoxContainer) -> void:
	var sep := ColorRect.new()
	sep.color                 = COLOR_DIVIDER
	sep.custom_minimum_size   = Vector2(0, 1)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)


# ── Signal wiring ─────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	InventorySystem.storage_changed.connect(_on_inventory_changed)
	InventorySystem.container_capacity_changed.connect(_on_capacity_changed)
	_item_grid.item_clicked.connect(_on_item_clicked)
	_crafting_grid.recipe_selected.connect(_on_recipe_selected)
	_npc_grid.npc_clicked.connect(_open_npc_detail)
	_npc_detail_panel.food_assigned.connect(_on_npc_food_assigned)
	_npc_detail_panel.food_cleared.connect(_on_npc_food_cleared)
	_npc_detail_panel.food_amount_changed.connect(_on_npc_food_amount_changed)
	CraftingRegistry.crafting_started.connect(_on_crafting_started)
	CraftingRegistry.crafting_progress.connect(_on_crafting_progress)
	CraftingRegistry.recipe_crafted.connect(_on_crafting_completed)
	BuildingRegistry.upgrade_installed.connect(_on_upgrade_changed_iv)
	BuildingRegistry.upgrade_removed.connect(_on_upgrade_changed_iv)
	ProgressionSystem.node_unlocked.connect(_on_progression_unlocked)
	var npc_sys: Node = NPCSystem
	if npc_sys != null:
		npc_sys.npc_recruited.connect(_on_npc_recruited_iv)
		npc_sys.npc_removed.connect(_on_npc_sn_iv)
		npc_sys.npc_released.connect(_on_npc_sn_iv)
		npc_sys.npc_assigned.connect(_on_npc_sn_sn_iv)
		npc_sys.npc_returned_home.connect(_on_npc_sn_iv)
		npc_sys.npc_renamed.connect(_on_npc_sn_sn_iv)
		npc_sys.npc_xp_gained.connect(_on_npc_xp_gained_iv)
		npc_sys.npc_leveled_up.connect(_on_npc_leveled_up_iv)


func _on_inventory_changed(_container_id: StringName) -> void:
	if _is_open:
		_refresh()


func _on_capacity_changed(_id: StringName, _old: int, _new: int) -> void:
	if _is_open:
		_refresh()


# ── Open / close ──────────────────────────────────────────────────────────────

func _toggle() -> void:
	if _is_open:
		_close()
	else:
		_open()


func _open() -> void:
	_was_paused_before_open = TickSystem.is_paused()
	_is_open            = true
	_panel_root.visible = true
	if not CraftingRegistry.is_crafting():
		TickSystem.set_pause(true)
	if not _is_tab_unlocked(_active_tab):
		for i: int in range(TABS.size()):
			if _is_tab_unlocked(i):
				_active_tab = i
				break
	_apply_tab_styles()
	_refresh_zone3()
	_refresh()
	_animate_in()
	inventory_opened.emit()


func _close() -> void:
	_is_open = false
	_stop_pulse()
	if not CraftingRegistry.is_crafting():
		TickSystem.set_pause(_was_paused_before_open)
	_animate_out()
	inventory_closed.emit()


func _animate_in() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_panel_root.modulate.a = 0.0
	_open_tween = create_tween()
	_open_tween.set_ease(Tween.EASE_IN)
	_open_tween.tween_property(_panel_root, "modulate:a", 1.0, ANIM_OPEN_SEC)


func _animate_out() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = create_tween()
	_open_tween.set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_panel_root, "modulate:a", 0.0, ANIM_CLOSE_SEC)
	_open_tween.tween_callback(func() -> void:
		_panel_root.visible    = false
		_panel_root.modulate.a = 1.0
	)


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	var summary := _compute_summary()
	_refresh_capacity(summary[&"used"], summary[&"total"])
	if _active_tab == 0:
		_item_grid.populate(_to_item_list(summary[&"resources"]))
	elif _active_tab == 1:
		if CraftingRegistry.has_crafting_bench():
			_crafting_grid.populate(_crafting_list(), CraftingRegistry.get_active_recipe_id(), CraftingRegistry.get_crafting_progress())
	elif _active_tab == 2:
		_npc_grid.populate(_npc_list())


func _compute_summary() -> Dictionary:
	var used:      int = 0
	var total:     int = 0
	var resources: Dictionary[StringName, int] = {}
	for container: InventoryContainer in InventorySystem.get_all_containers():
		used  += container.get_total_quantity() if container.quantity_based else container.get_occupied_count()
		total += container.capacity
		for slot: InventorySlot in container.slots:
			if not slot.is_empty():
				resources[slot.resource_id] = resources.get(slot.resource_id, 0) + slot.quantity
	return {&"used": used, &"total": total, &"resources": resources}


func _to_item_list(resources: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for res_id: StringName in resources:
		items.append({&"resource_id": res_id, &"quantity": resources[res_id]})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a[&"resource_id"]) < str(b[&"resource_id"])
	)
	return items


func _refresh_capacity(used: int, total: int) -> void:
	if total == 0:
		_capacity_label.text            = "Storage: 0 / 0  0%"
		_capacity_bar_fill.anchor_right = 0.0
		_capacity_bar_fill.color        = COLOR_CAP_GREEN
		_stop_pulse()
		return

	var ratio: float = clampf(float(used) / float(total), 0.0, 1.0)
	var pct:   int   = int(ratio * 100.0)
	_capacity_label.text            = "Storage: %d / %d  %d%%" % [used, total, pct]
	_capacity_bar_fill.anchor_right = ratio

	if ratio >= 0.90:
		_capacity_bar_fill.color = COLOR_CAP_RED
		_start_pulse()
	elif ratio >= 0.75:
		_capacity_bar_fill.color = COLOR_CAP_AMBER
		_stop_pulse()
	else:
		_capacity_bar_fill.color = COLOR_CAP_GREEN
		_stop_pulse()


func _start_pulse() -> void:
	if _is_pulsing:
		return
	_is_pulsing  = true
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_capacity_bar_fill, "modulate:a", 0.3, 0.5)
	_pulse_tween.tween_property(_capacity_bar_fill, "modulate:a", 1.0, 0.5)


func _stop_pulse() -> void:
	if not _is_pulsing:
		return
	_is_pulsing = false
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_capacity_bar_fill.modulate.a = 1.0


# ── Tab handling ──────────────────────────────────────────────────────────────

func _on_tab_pressed(idx: int) -> void:
	if not _is_tab_unlocked(idx):
		return
	_active_tab = idx
	_apply_tab_styles()
	_refresh_zone3()


func _apply_tab_styles() -> void:
	for i: int in range(_tab_buttons.size()):
		var btn: Button = _tab_buttons[i]
		var unlocked := _is_tab_unlocked(i)
		btn.visible = unlocked
		if not unlocked:
			continue
		var style := StyleBoxFlat.new()
		if i == _active_tab:
			style.bg_color = COLOR_TAB_ACTIVE_BG
			btn.add_theme_color_override("font_color", COLOR_TAB_ACTIVE_TEXT)
		else:
			style.bg_color = COLOR_TAB_INACTIVE_BG
			btn.add_theme_color_override("font_color", COLOR_TAB_INACTIVE_TEXT)
		for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
			btn.add_theme_stylebox_override(state, style)


func _refresh_zone3() -> void:
	for child in _zone3_vbox.get_children():
		if child != _item_grid and child != _crafting_grid and child != _npc_grid and child != _crafting_gate_label and child != _crafting_bench_dropdown:
			child.queue_free()

	_item_grid.visible              = false
	_crafting_grid.visible          = false
	_crafting_gate_label.visible    = false
	_crafting_bench_dropdown.visible = false
	_npc_grid.visible               = false

	if _active_tab == 0:
		_item_grid.visible = true
		var summary := _compute_summary()
		_item_grid.populate(_to_item_list(summary[&"resources"]))
	elif _active_tab == 1:
		if not CraftingRegistry.has_crafting_bench():
			_crafting_gate_label.visible = true
		else:
			_crafting_bench_dropdown.visible = true
			_crafting_grid.visible = true
			_refresh_bench_dropdown()
			_crafting_grid.populate(_crafting_list(), CraftingRegistry.get_active_recipe_id(), CraftingRegistry.get_crafting_progress())
	elif _active_tab == 2:
		_npc_grid.visible = true
		_npc_grid.populate(_npc_list())
	else:
		var placeholder := Label.new()
		placeholder.text                  = "%s — coming soon" % TABS[_active_tab]
		placeholder.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
		placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		placeholder.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		placeholder.add_theme_font_size_override("font_size", 14)
		_zone3_vbox.add_child(placeholder)


# ── Food consumption ──────────────────────────────────────────────────────────

func _on_item_clicked(resource_id: StringName) -> void:
	if not PlayerCharacter.is_food(resource_id):
		return
	var player: Node = get_tree().get_first_node_in_group(&"player_character")
	if player == null:
		return
	var container_id: StringName = _find_container_with(resource_id)
	if container_id == &"":
		return
	var consume_result := InventorySystem.try_consume(container_id, resource_id, 1)
	if consume_result != InventoryContainer.ConsumeResult.SUCCESS:
		return
	if not player.consume_food(resource_id):
		InventorySystem.try_deposit(container_id, resource_id, 1)
		return
	var energy_amount: int = PlayerCharacter.food_energy_value(resource_id)
	_spawn_energy_float("+%d ⚡" % energy_amount)


func _find_container_with(resource_id: StringName) -> StringName:
	for container: InventoryContainer in InventorySystem.get_all_containers():
		if container.get_resource_quantity(resource_id) > 0:
			return container.container_id
	return &""


func _spawn_energy_float(text: String) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var label := Label.new()
	label.text     = text
	label.position = mouse_pos + Vector2(-20.0, -32.0)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("#4CAF50"))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 52.0, 1.4)
	tween.tween_property(label, "modulate:a", 0.0, 1.4)
	tween.finished.connect(label.queue_free)


func _spawn_craft_float(text: String, color: Color = Color("#D4A85C")) -> void:
	var modal_rect: Rect2 = _modal.get_global_rect()
	var origin := Vector2(modal_rect.position.x + modal_rect.size.x * 0.5, modal_rect.position.y + 60.0)
	var label := Label.new()
	label.text     = text
	label.position = origin + Vector2(-40.0, 0.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 64.0, 1.6)
	tween.tween_property(label, "modulate:a", 0.0, 1.6)
	tween.finished.connect(label.queue_free)


# ── Crafting tab ──────────────────────────────────────────────────────────────

func _crafting_list() -> Array[Dictionary]:
	var resources: Dictionary = _compute_summary()[&"resources"]
	var player: Node = get_tree().get_first_node_in_group(&"player_character")
	var current_energy: int = player.get_current_energy() if player != null else 0
	var result: Array[Dictionary] = []
	for recipe_id: StringName in CraftingRegistry.RECIPE_ORDER:
		# Progression gate (UI layer): hide hand-craft recipes not yet unlocked.
		if not ProgressionSystem.is_recipe_unlocked(recipe_id):
			continue
		var cost: Dictionary        = CraftingRegistry.RECIPE_COST.get(recipe_id, {})
		var energy_cost: int        = CraftingRegistry.RECIPE_ENERGY_COST.get(recipe_id, 0)
		var display_name: String    = CraftingRegistry.RECIPE_DISPLAY_NAME.get(recipe_id, str(recipe_id))
		var available: Dictionary   = {}
		var can_afford: bool        = true
		for res_id: StringName in cost:
			var have: int         = resources.get(res_id, 0)
			available[res_id]     = have
			if have < cost[res_id]:
				can_afford = false
		if energy_cost > 0 and current_energy < energy_cost:
			can_afford = false
		if DebugSettings.ignore_costs:
			can_afford = true
		result.append({
			&"recipe_id":      recipe_id,
			&"display_name":   display_name,
			&"cost":           cost,
			&"available":      available,
			&"can_afford":     can_afford,
			&"energy_cost":    energy_cost,
			&"current_energy": current_energy,
		})
	return result


func _on_recipe_selected(recipe_id: StringName) -> void:
	if not CraftingRegistry.has_crafting_bench():
		_spawn_craft_float("Need a crafting bench!", Color("#E05050"))
		return
	if CraftingRegistry.is_crafting():
		_spawn_craft_float("Already crafting!", Color("#E05050"))
		return
	var result: int = CraftingRegistry.try_craft(recipe_id)
	if result == CraftingRegistry.CraftResult.NO_STORAGE:
		_spawn_craft_float("No storage available!", Color("#E05050"))
		return
	if result == CraftingRegistry.CraftResult.LOCKED:
		_spawn_craft_float("Locked — unlock in the tech tree", Color("#E05050"))
		return
	if result != CraftingRegistry.CraftResult.SUCCESS:
		return
	# Unpause ticks so the craft can progress while the inventory is open.
	TickSystem.set_pause(false)


func _on_crafting_started(_recipe_id: StringName, _total_ticks: int) -> void:
	if _is_open and _active_tab == 1:
		_crafting_grid.populate(_crafting_list(), CraftingRegistry.get_active_recipe_id(), 0.0)


func _on_crafting_progress(_recipe_id: StringName, progress: float) -> void:
	if _is_open and _active_tab == 1:
		_crafting_grid.update_progress(progress)


func _on_crafting_completed(recipe_id: StringName, qty: int) -> void:
	if _is_open:
		if not CraftingRegistry.is_crafting():
			TickSystem.set_pause(true)
		if _active_tab == 1:
			_crafting_grid.populate(_crafting_list())
		var display_name: String = CraftingRegistry.RECIPE_DISPLAY_NAME.get(recipe_id, str(recipe_id))
		_spawn_craft_float("+%d %s" % [qty, display_name])


func _refresh_bench_dropdown() -> void:
	_crafting_bench_dropdown.clear()
	var bench_buildings: Array[String] = CraftingRegistry.get_crafting_bench_buildings()
	for bid: String in bench_buildings:
		var label: String = BuildingRegistry.get_building_display_name(bid)
		_crafting_bench_dropdown.add_item(label)
		_crafting_bench_dropdown.set_item_metadata(_crafting_bench_dropdown.item_count - 1, bid)
	# Re-select the previously selected bench if it still exists.
	var sel: String = CraftingRegistry.selected_crafting_storage
	if sel != "":
		for i: int in range(_crafting_bench_dropdown.item_count):
			if _crafting_bench_dropdown.get_item_metadata(i) == sel:
				_crafting_bench_dropdown.select(i)
				return
	# Default: first item.
	if _crafting_bench_dropdown.item_count > 0:
		_crafting_bench_dropdown.select(0)
		CraftingRegistry.set_selected_storage(_crafting_bench_dropdown.get_item_metadata(0))


func _on_crafting_bench_selected(index: int) -> void:
	var bid: String = _crafting_bench_dropdown.get_item_metadata(index)
	CraftingRegistry.set_selected_storage(bid)


func _on_upgrade_changed_iv(_building_id: String, _upgrade_id: StringName) -> void:
	if _is_open and _active_tab == 1:
		_refresh_zone3()


## A tech-tree node was unlocked — refresh tabs so newly-available ones become clickable,
## then rebuild the active tab so newly-unlocked buildings/recipes appear immediately.
func _on_progression_unlocked(_node_id: StringName) -> void:
	_apply_tab_styles()
	if _is_open:
		_refresh_zone3()


# ── Tab gate helpers ──────────────────────────────────────────────────────────

func _is_tab_unlocked(idx: int) -> bool:
	if DebugSettings.unlock_all_progression:
		return true
	match idx:
		0:  ## Inventory — unlocked permanently once any Collection Point has been built
			return _has_collection_point() or ProgressionSystem.has_flag(&"collection_point_ever_built")
		1:  ## Crafting — requires Toolmaking node
			return ProgressionSystem.is_unlocked(&"toolmaking")
		2:  ## NPCs — requires Shelter node
			return ProgressionSystem.is_unlocked(&"shelter")
		_:
			return true


func _has_collection_point() -> bool:
	for b: BuildingRegistry.BuildingInstance in BuildingRegistry.get_all_buildings():
		if b.type == BuildingRegistry.BuildingType.COLLECTION_POINT:
			return true
	return false


func _tab_lock_hint(idx: int) -> String:
	match idx:
		0:  return "Build a Collection Point first"
		1:  return "Unlock Toolmaking in the Tech Tree"
		2:  return "Unlock Shelter in the Tech Tree"
		_:  return ""


# ── NPC tab ───────────────────────────────────────────────────────────────────

func _npc_list() -> Array[Dictionary]:
	var npc_sys: Node = NPCSystem
	if npc_sys == null:
		return []
	var result: Array[Dictionary] = []
	for npc_id: StringName in npc_sys.all_npcs:
		var npc: Object = npc_sys.get_npc_instance(npc_id)
		var level: int = npc.level if npc != null else 1
		var total_xp: int = npc.xp if npc != null else 0
		result.append({
			&"npc_id": npc_id,
			&"state": npc_sys.get_npc_state(npc_id),
			&"display_name": npc_sys.get_npc_display_name(npc_id),
			&"job": npc_sys.get_npc_job_name(npc_id),
			&"level": level,
			&"xp_into_level": ExperienceFormulas.xp_into_level(total_xp, level),
			&"xp_span": ExperienceFormulas.xp_span_of_level(level),
			&"warnings": _npc_warnings(npc_id, npc),
		})
	return result


func _npc_warnings(npc_id: StringName, npc: Object) -> Array:
	return NpcGrid.build_npc_warnings(npc_id, npc)


func _on_npc_recruited_iv(_npc_id: StringName, _home: Vector2i) -> void:
	if _is_open and _active_tab == 2:
		_npc_grid.populate(_npc_list())


func _on_npc_sn_iv(_npc_id: StringName) -> void:
	if _is_open and _active_tab == 2:
		_npc_grid.populate(_npc_list())


func _on_npc_sn_sn_iv(_npc_id: StringName, _other: StringName) -> void:
	if _is_open and _active_tab == 2:
		_npc_grid.populate(_npc_list())


func _on_npc_xp_gained_iv(_npc_id: StringName, _total_xp: int, _into: int, _span: int) -> void:
	if _is_open and _active_tab == 2:
		_npc_grid.populate(_npc_list())


func _on_npc_leveled_up_iv(_npc_id: StringName, _new_level: int) -> void:
	if _is_open and _active_tab == 2:
		_npc_grid.populate(_npc_list())


func _open_npc_detail(npc_id: StringName) -> void:
	var npc_state: int = NPCSystem.get_npc_state(npc_id)
	_npc_detail_panel.open_for_npc(npc_id, npc_state)


func _on_npc_food_assigned(npc_id: StringName, resource_id: StringName) -> void:
	HungerSystem.assign_food(npc_id, resource_id)


func _on_npc_food_cleared(npc_id: StringName) -> void:
	HungerSystem.clear_food_assignment(npc_id)


func _on_npc_food_amount_changed(npc_id: StringName, amount: int) -> void:
	HungerSystem.set_food_amount(npc_id, amount)


# ── Backdrop input ────────────────────────────────────────────────────────────

func _on_backdrop_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close()
		get_viewport().set_input_as_handled()
