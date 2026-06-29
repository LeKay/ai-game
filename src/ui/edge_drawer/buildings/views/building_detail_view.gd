class_name BuildingDetailView extends Control
## Detail view for a single placed building inside the Buildings Drawer.
## Spec: design/gdd/buildings-drawer.md §5.1
##
## Layout (top-to-bottom):
##   Back-bar (24 px)
##   ─────────────────────────────────
##   Name row  [Name Label]  [✏️ Button]
##   Header    [Asset 56×56]  Eff: XX%  [Worker Tile]
##             [state badge]  Util: XX%
##   ─────────────────────────────────
##   Section stubs (B4–B7)
##
## All write actions are expressed as signals — this view owns no game state.

# ── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the player taps the ← back button.
signal back_pressed()
## Emitted when the player taps the ✕ close button.
signal close_pressed()
## Emitted when the player confirms a rename.
signal rename_building(building_id: String, new_name: String)
## Emitted when the player picks a free NPC from the worker picker.
signal npc_assigned(building_id: String, npc_id: StringName)
## Emitted when the player confirms recruitment for a residential house.
signal npc_recruit_requested(building_id: String, resource_id: StringName)
## Emitted when the player releases the current worker (future use by sections).
signal npc_released(building_id: String, npc_id: StringName)
## Emitted when the player taps the worker tile to open the NPC detail view.
signal npc_detail_requested(npc_id: StringName)
## Emitted when the player requests construction work on an under-construction building.
signal construction_work_requested(building_id: String)
## Forwarded from ProductionSection / InventorySection — player tapped a storage item.
signal storage_drag_started(resource_id: StringName, container_id: StringName, tile_pos: Vector2i)
## Forwarded from ProductionSection — player tapped an input-buffer item.
signal input_drag_started(resource_id: StringName, building_id: String, tile_pos: Vector2i)
## Forwarded from ProductionSection — player tapped an output-buffer item.
signal output_drag_started(resource_id: StringName, building_id: String, tile_pos: Vector2i)
## Forwarded from ProductionSection — player requested the recipe picker.
signal recipe_picker_requested(building_id: String)
## Forwarded from ProductionSection — player confirmed a recipe selection.
## Caller should invoke BuildingRegistry.set_active_recipe() with the matching index.
signal recipe_changed(building_id: String, recipe_id: StringName)
## Forwarded from TransportSection — player confirmed a new route creation.
signal route_create_requested(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
## Forwarded from TransportSection — player saved edits to an existing route.
signal route_update_requested(route_id: StringName, changes: Dictionary)
## Forwarded from TransportSection — player confirmed deletion of a route.
signal route_delete_requested(route_id: StringName)
## Forwarded from TransportSection — player wants to pick a building via map-select.
signal map_select_requested(step: String)
## Forwarded from UpgradesSection — player confirmed an upgrade install.
## Caller must deduct resources and then call BuildingRegistry.install_upgrade().
signal upgrade_install_requested(building_id: String, upgrade_id: StringName)
## Emitted when the player saves a production speed change via the editor.
## Caller should invoke BuildingRegistry.set_production_speed() with target_efficiency.
signal production_speed_changed(building_id: String, target_efficiency: float)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_BG        := Color(0.14, 0.15, 0.18, 1.0)
const COLOR_SEPARATOR := Color(0.25, 0.26, 0.30, 1.0)
const COLOR_TEXT      := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_TEXT_DIM  := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_ACCENT    := Color(0.30, 0.70, 1.00, 1.0)

const COLOR_STATE: Dictionary = {
	"PRODUCING":    Color(0.298, 0.686, 0.314),
	"OPERATING":    Color(0.298, 0.686, 0.314),
	"BLOCKED":      Color(1.0, 0.757, 0.027),
	"STALLED":      Color(0.898, 0.239, 0.239),
	"CONSTRUCTING": Color(1.0, 0.596, 0.0),
	"IDLE":         Color(0.6, 0.6, 0.6),
}

# ── Node refs ─────────────────────────────────────────────────────────────────

var _name_label:      Label
var _rename_btn:      Button
var _rename_edit:     LineEdit
var _rename_confirm:  Button
var _rename_cancel:   Button
var _name_row:        HBoxContainer

var _icon_rect:       TextureRect
var _icon_glyph:      Label
var _eff_label:       Label
var _eff_gear_btn:    Button        ## gear button next to Eff label — production buildings only
var _util_label:      Label
var _state_dot:       ColorRect
var _state_label:     Label
var _storage_fill_bar_host: Control  ## fill bar row — visible only for storage buildings
var _storage_fill_rect:     ColorRect  ## colored fill portion
var _progress_bar_host: Control   ## cycle/fill progress bar between stats and worker tile
var _progress_bar_fill: ColorRect  ## colored fill portion of the progress bar

var _worker_tile_host: Control   ## container that holds the worker tile
var _worker_tile:      DrawerTile

var _picker_popup:    Control    ## inline free-NPC picker
var _picker_title:    Label       ## title label inside _picker_popup
var _picker_list:     VBoxContainer  ## list container inside _picker_popup

## Active production or inventory section (ProductionSection | InventorySection | Control stub).
var _production_section:  Control
var _speed_editor:        ProductionSpeedEditor  ## inline speed-throttle editor
var _transport_section:   Control
var _upgrades_section:    Control
var _residents_section:   Control  ## residents grid — only visible for RESIDENTIAL_HOUSE

var _crafting_btn_host: Control    ## container for crafting button — storage+bench only
var _crafting_section:  Control    ## inline crafting view — replaces body sections when open
var _crafting_grid:     CraftingGrid  ## recipe grid inside crafting section

# ── State ─────────────────────────────────────────────────────────────────────

var _building_id: String = ""
var _is_rename_active: bool = false
var _crafting_view_open: bool = false

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

	# _production_section is built in setup() once the building_id is known.
	_production_section = _make_section_stub("")
	var transport_sec := TransportSection.new()
	_transport_section = transport_sec
	transport_sec.route_create_requested.connect(
		func(f: StringName, t: StringName, n: StringName, i: StringName) -> void:
			route_create_requested.emit(f, t, n, i))
	transport_sec.route_update_requested.connect(
		func(rid: StringName, changes: Dictionary) -> void:
			route_update_requested.emit(rid, changes))
	transport_sec.route_delete_requested.connect(
		func(rid: StringName) -> void:
			route_delete_requested.emit(rid))
	transport_sec.map_select_requested.connect(
		func(step: String) -> void:
			map_select_requested.emit(step))
	var upgrades_sec := UpgradesSection.new()
	_upgrades_section = upgrades_sec
	upgrades_sec.upgrade_install_requested.connect(
		func(bid: String, uid: StringName) -> void:
			upgrade_install_requested.emit(bid, uid))

	_residents_section = _build_residents_section()

	_speed_editor = ProductionSpeedEditor.new()
	_speed_editor.name    = "ProductionSpeedEditor"
	_speed_editor.visible = false
	_speed_editor.save_requested.connect(_on_speed_save)
	_speed_editor.cancel_requested.connect(_on_speed_cancel)

	vbox.add_child(_speed_editor)
	vbox.add_child(_production_section)
	vbox.add_child(_residents_section)
	vbox.add_child(_transport_section)
	vbox.add_child(_upgrades_section)

	_crafting_btn_host = _build_crafting_btn()
	vbox.add_child(_crafting_btn_host)
	_crafting_section = _build_crafting_section_view()
	vbox.add_child(_crafting_section)

	_picker_popup = _build_picker_popup()
	add_child(_picker_popup)

	CraftingRegistry.crafting_started.connect(_on_bdv_crafting_started)
	CraftingRegistry.crafting_progress.connect(_on_bdv_crafting_progress)
	CraftingRegistry.recipe_crafted.connect(_on_bdv_recipe_crafted)


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

## Loads data for [param building_id] and rebuilds the header and production/inventory section.
func setup(building_id: String) -> void:
	_building_id = building_id
	cancel_all_editors()
	_rebuild_production_section()
	if _transport_section is TransportSection:
		(_transport_section as TransportSection).setup(building_id)
	if _upgrades_section is UpgradesSection:
		(_upgrades_section as UpgradesSection).setup(building_id)
	if not InventorySystem.storage_changed.is_connected(_on_storage_changed):
		InventorySystem.storage_changed.connect(_on_storage_changed)
	if not TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
		TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if InventorySystem.storage_changed.is_connected(_on_storage_changed):
			InventorySystem.storage_changed.disconnect(_on_storage_changed)
		if TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
			TickSystem.ticks_advanced.disconnect(_on_ticks_advanced)
		if CraftingRegistry.crafting_started.is_connected(_on_bdv_crafting_started):
			CraftingRegistry.crafting_started.disconnect(_on_bdv_crafting_started)
		if CraftingRegistry.crafting_progress.is_connected(_on_bdv_crafting_progress):
			CraftingRegistry.crafting_progress.disconnect(_on_bdv_crafting_progress)
		if CraftingRegistry.recipe_crafted.is_connected(_on_bdv_recipe_crafted):
			CraftingRegistry.recipe_crafted.disconnect(_on_bdv_recipe_crafted)


func _on_ticks_advanced(_delta: int) -> void:
	if _building_id == "":
		return
	refresh()


func _on_storage_changed(_container_id: StringName) -> void:
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return
	if not BuildingRegistry.STORAGE_CAPACITY.has(instance.type):
		return
	# Only refresh if the changed container belongs to this building.
	if _container_id == instance.assigned_container_id:
		refresh()


## Forwards a completed map-select result into the embedded TransportSection / RouteEditorView.
## Called by the drawer controller after the player picks a building on the map.
func resume_map_select(step: String, building_id: StringName) -> void:
	if _transport_section is TransportSection:
		(_transport_section as TransportSection).resume_map_select(step, building_id)


## Replaces the production/inventory section node with the correct typed section.
func _rebuild_production_section() -> void:
	var parent: Node = _production_section.get_parent()
	var index: int = _production_section.get_index()
	_production_section.queue_free()

	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		_production_section = _make_section_stub("")
		parent.add_child(_production_section)
		parent.move_child(_production_section, index)
		return

	var is_storage: bool = BuildingRegistry.STORAGE_CAPACITY.has(instance.type)
	var is_production: bool = BuildingRegistry.is_production_building(instance.type)

	if is_storage:
		var sec := InventorySection.new()
		_production_section = sec
		parent.add_child(sec)
		parent.move_child(sec, index)
		sec.storage_drag_started.connect(func(r, c, t): storage_drag_started.emit(r, c, t))
		sec.setup(_building_id)
	elif is_production:
		var sec := ProductionSection.new()
		_production_section = sec
		parent.add_child(sec)
		parent.move_child(sec, index)
		sec.recipe_picker_requested.connect(
				func() -> void: recipe_picker_requested.emit(_building_id))
		sec.recipe_changed.connect(func(bid: String, rid: StringName) -> void:
				recipe_changed.emit(bid, rid))
		sec.storage_drag_started.connect(func(r, c, t): storage_drag_started.emit(r, c, t))
		sec.input_drag_started.connect(func(r, b, t): input_drag_started.emit(r, b, t))
		sec.output_drag_started.connect(func(r, b, t): output_drag_started.emit(r, b, t))
		sec.setup(_building_id)
	else:
		_production_section = _make_section_stub("")
		parent.add_child(_production_section)
		parent.move_child(_production_section, index)


## Re-reads Eff/Util, state badge, and worker tile from BuildingRegistry / NPCSystem.
func refresh() -> void:
	if _building_id == "":
		return
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return

	# ── Name ──────────────────────────────────────────────────────────────────
	var display_name: String = BuildingRegistry.get_building_display_name(_building_id)
	_name_label.text = display_name

	# ── Icon ──────────────────────────────────────────────────────────────────
	var tex: Texture2D = BuildingRegistry.get_building_texture(instance.type)
	if tex != null:
		_icon_rect.texture  = tex
		_icon_rect.visible  = true
		_icon_glyph.visible = false
	else:
		_icon_rect.visible  = false
		_icon_glyph.text    = "🏗"
		_icon_glyph.visible = true

	# ── Storage vs production header stats ───────────────────────────────────
	var is_storage: bool = BuildingRegistry.STORAGE_CAPACITY.has(instance.type)
	if is_storage:
		var container_id: StringName = instance.assigned_container_id
		var used: int = 0
		var total: int = 0
		if container_id != &"":
			var inv: InventoryContainer = InventorySystem.get_container(container_id)
			if inv != null:
				used = inv.get_total_quantity()
				total = inv.capacity
		_eff_label.text = "%d / %d" % [used, total]  # TODO: localize
		_util_label.visible = false
		_storage_fill_bar_host.visible = true
		var fill_ratio: float = float(used) / float(max(total, 1))
		_storage_fill_rect.anchor_right = clampf(fill_ratio, 0.0, 1.0)
	else:
		# ── Efficiency ────────────────────────────────────────────────────────
		_eff_label.text = "Eff: %d%%" % int(instance.get_effective_efficiency() * 100.0)  # TODO: localize
		var _is_prod: bool = BuildingRegistry.is_production_building(instance.type)
		_eff_gear_btn.visible = _is_prod and not _speed_editor.visible
		if _speed_editor.visible:
			_speed_editor.update_max(instance.efficiency)
		# ── Utilization ───────────────────────────────────────────────────────
		if instance.util_data_available:
			var day_ticks: float = float(TickSystem.TICKS_PER_DAY) \
					if TickSystem != null else 1.0
			var util_pct: int = 0
			if day_ticks > 0.0:
				util_pct = int((float(instance.util_active_ticks_last_day) / day_ticks) * 100.0)
			_util_label.text = "Util: %d%%" % util_pct  # TODO: localize
		else:
			_util_label.text = "Util: —"  # TODO: localize
		_util_label.visible = true
		_storage_fill_bar_host.visible = false

	# ── Progress bar ──────────────────────────────────────────────────────────
	if not is_storage and instance.cycle_running and instance.production_cycle_duration > 0:
		var ratio: float = float(instance.production_cycle_ticks) \
				/ float(instance.production_cycle_duration)
		_progress_bar_fill.anchor_right = clampf(ratio, 0.0, 1.0)
		_progress_bar_host.visible = true
	else:
		_progress_bar_host.visible = false

	# ── State dot ─────────────────────────────────────────────────────────────
	var state_key: String = _state_enum_to_key(instance.state)
	# OPERATING but cycle not running → building is idle/stalled (e.g. output full, no work queued)
	if state_key == "OPERATING" and not is_storage \
			and BuildingRegistry.is_production_building(instance.type) \
			and not instance.cycle_running:
		state_key = "STALLED"
	_state_dot.color = COLOR_STATE.get(state_key, Color(0.6, 0.6, 0.6))
	_state_label.text = state_key.capitalize()

	# ── Worker tile — hidden for building types with no worker slot ──────────
	var has_worker_slot: bool = BuildingRegistry.BUILDING_JOB_NAMES.has(instance.type)
	_worker_tile_host.visible = has_worker_slot
	if has_worker_slot:
		_rebuild_worker_tile(instance)

	# ── Transport section — hidden until shelter is researched, and not shown for residential houses
	var is_house: bool = instance.type == BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE
	_transport_section.visible = ProgressionSystem.is_unlocked(&"shelter") and not is_house

	# ── Residents section — only for residential houses ───────────────────────
	_residents_section.visible = is_house
	if is_house:
		_rebuild_residents(instance)

	# ── Production / Inventory section ────────────────────────────────────────
	if _production_section is ProductionSection or _production_section is InventorySection:
		(_production_section as Control).call("refresh")

	# ── Upgrades section ──────────────────────────────────────────────────────
	if _upgrades_section is UpgradesSection:
		var us := _upgrades_section as UpgradesSection
		us.refresh()
		us.visible = us.is_visible_section()

	# ── Crafting button — visible when storage has crafting bench upgrade ──────
	var has_bench: bool = is_storage and BuildingRegistry.has_upgrade(_building_id, &"crafting_bench")
	_crafting_btn_host.visible = has_bench and not _crafting_view_open

	# When crafting view is open, keep all body sections hidden.
	if _crafting_view_open:
		_production_section.visible = false
		_residents_section.visible = false
		_transport_section.visible = false
		_upgrades_section.visible = false


## Returns true while the inline rename LineEdit is active.
## Used by BuildingsDrawerContent to intercept ESC before the drawer handles it.
func is_rename_active() -> bool:
	return _is_rename_active


# ── Back-bar ─────────────────────────────────────────────────────────────────

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


# ── Header ────────────────────────────────────────────────────────────────────

func _build_header() -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Header"
	outer.add_theme_constant_override("separation", 4)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",  8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top",   6)
	pad.add_theme_constant_override("margin_bottom",6)
	outer.add_child(pad)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	pad.add_child(inner)

	inner.add_child(_build_name_row())

	# ── Icon + stats + worker ────────────────────────────────────────────────
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	inner.add_child(row)

	# Icon wrapper (56×56)
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(56, 56)
	icon_wrap.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_wrap)

	_icon_rect = TextureRect.new()
	_icon_rect.name          = "IconRect"
	_icon_rect.expand_mode   = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon_rect.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_rect.visible       = false
	icon_wrap.add_child(_icon_rect)

	_icon_glyph = Label.new()
	_icon_glyph.name                 = "IconGlyph"
	_icon_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_glyph.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_icon_glyph.add_theme_font_size_override("font_size", 28)
	_icon_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_glyph.visible              = false
	icon_wrap.add_child(_icon_glyph)

	# Stats column
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(stats)

	# Eff row: label + gear button
	var eff_row := HBoxContainer.new()
	eff_row.add_theme_constant_override("separation", 4)
	stats.add_child(eff_row)

	_eff_label = Label.new()
	_eff_label.name = "EffLabel"
	_eff_label.add_theme_font_size_override("font_size", 12)
	_eff_label.add_theme_color_override("font_color", COLOR_TEXT)
	_eff_label.text = "Eff: —"
	_eff_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eff_row.add_child(_eff_label)

	_eff_gear_btn = Button.new()
	_eff_gear_btn.name = "EffGearBtn"
	_eff_gear_btn.text = "⚙"
	_eff_gear_btn.flat = true
	_eff_gear_btn.tooltip_text = "Edit production speed"  # TODO: localize
	_eff_gear_btn.add_theme_font_size_override("font_size", 12)
	_eff_gear_btn.visible = false
	_eff_gear_btn.pressed.connect(_open_speed_editor)
	eff_row.add_child(_eff_gear_btn)

	_util_label = Label.new()
	_util_label.name = "UtilLabel"
	_util_label.add_theme_font_size_override("font_size", 12)
	_util_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_util_label.text = "Util: —"
	stats.add_child(_util_label)

	# Storage fill bar — shown in place of util label for storage buildings
	_storage_fill_bar_host = Control.new()
	_storage_fill_bar_host.name = "StorageFillBarHost"
	_storage_fill_bar_host.custom_minimum_size = Vector2(0, 7)
	_storage_fill_bar_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_fill_bar_host.visible = false

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.18, 0.19, 0.23, 1.0)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_storage_fill_bar_host.add_child(bar_bg)

	_storage_fill_rect = ColorRect.new()
	_storage_fill_rect.color = Color(0.30, 0.70, 1.00, 0.85)
	_storage_fill_rect.anchor_left   = 0.0
	_storage_fill_rect.anchor_top    = 0.0
	_storage_fill_rect.anchor_bottom = 1.0
	_storage_fill_rect.anchor_right  = 0.0
	_storage_fill_rect.offset_right  = 0.0
	_storage_fill_bar_host.add_child(_storage_fill_rect)

	stats.add_child(_storage_fill_bar_host)

	# Progress bar — cycle progress (production) or fill (storage), always visible
	_progress_bar_host = Control.new()
	_progress_bar_host.name = "ProgressBarHost"
	_progress_bar_host.custom_minimum_size = Vector2(0, 7)
	_progress_bar_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pb_bg := ColorRect.new()
	pb_bg.color = Color(0.18, 0.19, 0.23, 1.0)
	pb_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_bar_host.add_child(pb_bg)

	_progress_bar_fill = ColorRect.new()
	_progress_bar_fill.color = Color(0.30, 0.70, 1.00, 0.85)
	_progress_bar_fill.anchor_left   = 0.0
	_progress_bar_fill.anchor_top    = 0.0
	_progress_bar_fill.anchor_bottom = 1.0
	_progress_bar_fill.anchor_right  = 0.0
	_progress_bar_fill.offset_right  = 0.0
	_progress_bar_host.add_child(_progress_bar_fill)

	stats.add_child(_progress_bar_host)

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
	_state_label.text = ""
	state_row.add_child(_state_label)

	# Worker tile host
	_worker_tile_host = Control.new()
	_worker_tile_host.name                = "WorkerTileHost"
	_worker_tile_host.custom_minimum_size = DrawerTile.TILE_SIZE
	_worker_tile_host.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	row.add_child(_worker_tile_host)

	return outer


# ── Name row ─────────────────────────────────────────────────────────────────

func _build_name_row() -> Control:
	_name_row = HBoxContainer.new()
	_name_row.name = "NameRow"
	_name_row.add_theme_constant_override("separation", 4)

	_name_label = Label.new()
	_name_label.name                = "NameLabel"
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text             = true
	_name_row.add_child(_name_label)

	_rename_btn = Button.new()
	_rename_btn.name = "RenameBtn"
	_rename_btn.text = "✏️"
	_rename_btn.flat = true
	_rename_btn.tooltip_text = "Rename building"  # TODO: localize
	_rename_btn.add_theme_font_size_override("font_size", 12)
	_rename_btn.pressed.connect(_build_rename_inline)
	_name_row.add_child(_rename_btn)

	# LineEdit + confirm / cancel — hidden until rename is activated.
	_rename_edit = LineEdit.new()
	_rename_edit.name                 = "RenameEdit"
	_rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_edit.placeholder_text     = "Building name…"  # TODO: localize
	_rename_edit.add_theme_font_size_override("font_size", 13)
	_rename_edit.visible              = false
	_name_row.add_child(_rename_edit)

	_rename_confirm = Button.new()
	_rename_confirm.name    = "RenameConfirm"
	_rename_confirm.text    = "✓"
	_rename_confirm.flat    = true
	_rename_confirm.visible = false
	_rename_confirm.add_theme_color_override("font_color", Color(0.298, 0.686, 0.314))
	_rename_confirm.pressed.connect(_submit_rename)
	_name_row.add_child(_rename_confirm)

	_rename_cancel = Button.new()
	_rename_cancel.name    = "RenameCancel"
	_rename_cancel.text    = "✕"
	_rename_cancel.flat    = true
	_rename_cancel.visible = false
	_rename_cancel.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_rename_cancel.pressed.connect(_cancel_rename)
	_name_row.add_child(_rename_cancel)

	return _name_row


# ── Rename in-place ───────────────────────────────────────────────────────────

## Switches the name label to an editable LineEdit for renaming.
func _build_rename_inline() -> void:
	_is_rename_active = true
	_name_label.visible   = false
	_rename_btn.visible   = false
	_rename_edit.text     = _name_label.text
	_rename_edit.visible  = true
	_rename_confirm.visible = true
	_rename_cancel.visible  = true
	_rename_edit.grab_focus()
	_rename_edit.select_all()


## Emits [signal rename_building] with the new name and restores the label.
func _submit_rename() -> void:
	var new_name: String = _rename_edit.text.strip_edges()
	if new_name != "" and new_name != _name_label.text:
		rename_building.emit(_building_id, new_name)
		_name_label.text = new_name
	_cancel_rename()


## Cancels an active rename, restoring the name label. No-op if rename is not active.
func cancel_rename() -> void:
	_cancel_rename()


## Restores the name label without emitting.
func _cancel_rename() -> void:
	_is_rename_active      = false
	_rename_edit.visible   = false
	_rename_confirm.visible = false
	_rename_cancel.visible  = false
	_name_label.visible    = true
	_rename_btn.visible    = true


# ── Worker tile ───────────────────────────────────────────────────────────────

## Builds or rebuilds the worker tile inside [member _worker_tile_host].
func _rebuild_worker_tile(instance: BuildingRegistry.BuildingInstance) -> void:
	# Clear previous tile.
	if _worker_tile != null and is_instance_valid(_worker_tile):
		_worker_tile.queue_free()
		_worker_tile = null

	var assigned_id: StringName = instance.assigned_npc_id
	var tile := DrawerTile.new()
	_worker_tile = tile
	tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_worker_tile_host.add_child(tile)

	if assigned_id != &"":
		# Worker is assigned — show name, allow tap → detail; × releases the NPC.
		var npc_name: String = NPCSystem.get_npc_display_name(assigned_id)
		tile.set_icon_glyph("👤")
		tile.set_label(npc_name)
		tile.set_state(DrawerTile.TileState.ACTIVE)
		tile.pressed.connect(func() -> void: npc_detail_requested.emit(assigned_id))
		tile.set_remove_button(true, func() -> void:
			npc_released.emit(_building_id, assigned_id)
			refresh()
		)
	else:
		var free_npcs: Array[StringName] = NPCSystem.get_available_npcs()
		if free_npcs.is_empty():
			# No worker, no free NPCs — disabled tile.
			tile.set_icon_glyph("👤")
			tile.set_label("No worker")  # TODO: localize
			tile.set_state(DrawerTile.TileState.DISABLED)
			tile.tooltip_text = "No free workers"  # TODO: localize
		else:
			# No worker but free NPCs available — plus tile.
			tile.set_icon_glyph("+")
			tile.set_label("Assign")  # TODO: localize
			tile.set_state(DrawerTile.TileState.NORMAL)
			tile.pressed.connect(_open_worker_picker)


## Returns the worker tile Control (exposed for testing / B4+ overrides if needed).
func _build_worker_tile() -> Control:
	return _worker_tile_host


# ── Worker picker popup ───────────────────────────────────────────────────────

## Builds the inline NPC picker panel (hidden by default).
func _build_picker_popup() -> Control:
	var panel := PanelContainer.new()
	panel.name    = "WorkerPickerPopup"
	panel.visible = false
	# Anchor to top-right where the worker tile lives.
	panel.anchor_left   = 1.0
	panel.anchor_top    = 0.0
	panel.anchor_right  = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left   = -170
	panel.offset_top    = 32
	panel.offset_right  = -4
	panel.offset_bottom = 180

	var sb := StyleBoxFlat.new()
	sb.bg_color              = Color(0.12, 0.13, 0.16, 0.97)
	sb.border_width_left     = 1
	sb.border_width_right    = 1
	sb.border_width_top      = 1
	sb.border_width_bottom   = 1
	sb.border_color          = Color(0.30, 0.70, 1.0, 0.5)
	sb.corner_radius_top_left    = 4
	sb.corner_radius_top_right   = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var title := Label.new()
	title.name                = "PickerTitle"
	title.text                = "Assign Worker"  # TODO: localize
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picker_title = title
	vbox.add_child(title)

	# The list is repopulated in _open_worker_picker() / _open_recruit_picker().
	var list := VBoxContainer.new()
	list.name = "PickerList"
	list.add_theme_constant_override("separation", 2)
	_picker_list = list
	vbox.add_child(list)

	return panel


## Populates and shows the worker picker popup.
func _open_worker_picker() -> void:
	_picker_title.text = "Assign Worker"
	for child in _picker_list.get_children():
		child.queue_free()

	var free_npcs: Array[StringName] = NPCSystem.get_available_npcs()
	if free_npcs.is_empty():
		var lbl := Label.new()
		lbl.text = "No free workers"  # TODO: localize
		lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_picker_list.add_child(lbl)
	else:
		for npc_id: StringName in free_npcs:
			var npc_name: String = NPCSystem.get_npc_display_name(npc_id)
			var btn := Button.new()
			btn.text = npc_name
			btn.flat = false
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 12)
			var captured_id: StringName = npc_id
			btn.pressed.connect(func() -> void: _on_npc_picked(captured_id))
			_picker_list.add_child(btn)

	_picker_popup.visible = true


## Called when the player picks a free NPC from the popup.
func _on_npc_picked(npc_id: StringName) -> void:
	_picker_popup.visible = false
	npc_assigned.emit(_building_id, npc_id)
	refresh()


# ── Residents section (RESIDENTIAL_HOUSE only) ───────────────────────────────

func _build_residents_section() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "ResidentsSection"
	vbox.add_theme_constant_override("separation", 0)
	vbox.visible = false

	var sep := HSeparator.new()
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = COLOR_SEPARATOR
	sep_sb.content_margin_top    = 0
	sep_sb.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_sb)
	vbox.add_child(sep)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   12)
	margin.add_theme_constant_override("margin_right",  12)
	margin.add_theme_constant_override("margin_top",     8)
	margin.add_theme_constant_override("margin_bottom",  8)
	vbox.add_child(margin)

	var title := Label.new()
	title.name = "ResidentsTitle"
	title.text = "Residents"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	margin.add_child(title)

	var flow_margin := MarginContainer.new()
	flow_margin.name = "ResidentsTilesMargin"
	flow_margin.add_theme_constant_override("margin_left",   12)
	flow_margin.add_theme_constant_override("margin_right",  12)
	flow_margin.add_theme_constant_override("margin_top",     4)
	flow_margin.add_theme_constant_override("margin_bottom",  8)
	vbox.add_child(flow_margin)

	var hbox := HBoxContainer.new()
	hbox.name = "ResidentsTiles"
	hbox.add_theme_constant_override("separation", 8)
	flow_margin.add_child(hbox)

	return vbox


func _rebuild_residents(instance: BuildingRegistry.BuildingInstance) -> void:
	var hbox: HBoxContainer = _residents_section.get_node("ResidentsTilesMargin/ResidentsTiles")
	for child in hbox.get_children():
		child.queue_free()

	var home_tile: Vector2i = BuildingRegistry.get_building_tile(_building_id)
	var residents: Array[StringName] = NPCSystem.get_house_npcs(home_tile)
	var capacity: int = NPCSystem.NPC_CAPACITY_PER_HOUSE

	for i: int in range(capacity):
		var tile := DrawerTile.new()
		if i < residents.size():
			var npc_id: StringName = residents[i]
			var npc_name: String = NPCSystem.get_npc_display_name(npc_id)
			tile.set_icon_glyph("👤")
			tile.set_label(npc_name)
			tile.set_state(DrawerTile.TileState.ACTIVE)
			tile.pressed.connect(func() -> void: npc_detail_requested.emit(npc_id))
		else:
			tile.set_icon_glyph("+")
			tile.set_label("Recruit")
			tile.set_state(DrawerTile.TileState.NORMAL)
			tile.pressed.connect(_open_recruit_picker)
		hbox.add_child(tile)


func _open_recruit_picker() -> void:
	_picker_title.text = "Recruit Villager"
	for child in _picker_list.get_children():
		child.queue_free()

	var cost: float = NPCSystem.get_recruit_nutrition_cost()
	var cost_lbl := Label.new()
	cost_lbl.text = "Cost: %.0f nutrition" % cost
	cost_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	cost_lbl.add_theme_font_size_override("font_size", 11)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picker_list.add_child(cost_lbl)

	var food_ids: Array[StringName] = ResourceRegistry.get_food_resource_ids()
	var any_affordable := false
	for res_id: StringName in food_ids:
		var amount: int = NPCSystem.get_recruit_amount_for_resource(res_id)
		if amount <= 0:
			continue
		var have: int = InventorySystem.get_global_quantity(res_id)
		var affordable: bool = have >= amount
		if affordable:
			any_affordable = true
		var def: Object = ResourceRegistry.get_definition(res_id)
		var res_name: String = def.display_name if def != null else str(res_id)
		var btn := Button.new()
		btn.text = "%s (%d/%d)" % [res_name, have, amount]
		btn.flat = false
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.disabled = not affordable
		var captured: StringName = res_id
		btn.pressed.connect(func() -> void: _on_recruit_food_picked(captured))
		_picker_list.add_child(btn)

	if not any_affordable:
		var lbl := Label.new()
		lbl.text = "Not enough food"
		lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_picker_list.add_child(lbl)

	_picker_popup.visible = true


func _on_recruit_food_picked(resource_id: StringName) -> void:
	_picker_popup.visible = false
	npc_recruit_requested.emit(_building_id, resource_id)
	refresh()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var sb  := StyleBoxFlat.new()
	sb.bg_color = COLOR_SEPARATOR
	sb.content_margin_top    = 0
	sb.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sb)
	return sep


func _make_section_stub(stub_text: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 40)
	var lbl := Label.new()
	lbl.text                  = stub_text
	lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(lbl)
	return c


func _state_enum_to_key(state: int) -> String:
	match state:
		BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
			return "CONSTRUCTING"
		BuildingRegistry.BuildingInstance.State.OPERATING:
			return "OPERATING"
		BuildingRegistry.BuildingInstance.State.BLOCKED:
			return "BLOCKED"
		BuildingRegistry.BuildingInstance.State.DEMOLISHED:
			return "IDLE"
	return "IDLE"


# ── Production speed editor ───────────────────────────────────────────────────

func _open_speed_editor() -> void:
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return
	_speed_editor.setup(_building_id)
	_speed_editor.visible       = true
	_eff_gear_btn.visible       = false
	_production_section.visible = false


func _on_speed_save(target_efficiency: float) -> void:
	production_speed_changed.emit(_building_id, target_efficiency)
	_close_speed_editor()


func _on_speed_cancel() -> void:
	_close_speed_editor()


func _close_speed_editor() -> void:
	_speed_editor.visible       = false
	_production_section.visible = true
	refresh()


## Cancels an open speed editor without emitting production_speed_changed.
func cancel_speed_editor() -> void:
	if _speed_editor.visible:
		_on_speed_cancel()


## Cancels all active inline editors (rename, speed, recipe picker, route editor, worker popup).
## Safe to call at any time — all cancellations are no-ops when not active.
func cancel_all_editors() -> void:
	_cancel_rename()
	cancel_speed_editor()
	if _picker_popup != null and _picker_popup.visible:
		_picker_popup.visible = false
	if _production_section is ProductionSection:
		(_production_section as ProductionSection).cancel_picker()
	if _transport_section is TransportSection:
		(_transport_section as TransportSection).cancel_editor()
	if _crafting_view_open:
		_close_crafting_view()


# ── Crafting button ───────────────────────────────────────────────────────────

func _build_crafting_btn() -> Control:
	var host := VBoxContainer.new()
	host.name = "CraftingBtnHost"
	host.add_theme_constant_override("separation", 0)
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.visible = false

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(spacer)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   8)
	pad.add_theme_constant_override("margin_right",  8)
	pad.add_theme_constant_override("margin_top",    4)
	pad.add_theme_constant_override("margin_bottom", 8)
	host.add_child(pad)

	var btn := Button.new()
	btn.name = "CraftingBtn"
	btn.text = "⚒ Crafting"  # TODO: localize
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_open_crafting_view)
	pad.add_child(btn)
	return host


# ── Inline crafting section ───────────────────────────────────────────────────

func _build_crafting_section_view() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "CraftingSection"
	vbox.add_theme_constant_override("separation", 0)
	vbox.visible = false

	vbox.add_child(_make_separator())

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   12)
	pad.add_theme_constant_override("margin_right",  12)
	pad.add_theme_constant_override("margin_top",     8)
	pad.add_theme_constant_override("margin_bottom",  0)
	vbox.add_child(pad)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 0)
	pad.add_child(header_row)

	var title := Label.new()
	title.name = "CraftingTitle"
	title.text = "Crafting"  # TODO: localize
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	header_row.add_child(title)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(fill)

	var close_btn := Button.new()
	close_btn.name = "CraftingCloseBtn"
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	close_btn.add_theme_color_override("font_hover_color", COLOR_TEXT)
	close_btn.pressed.connect(_close_crafting_view)
	header_row.add_child(close_btn)

	var grid_pad := MarginContainer.new()
	grid_pad.add_theme_constant_override("margin_left",   8)
	grid_pad.add_theme_constant_override("margin_right",  8)
	grid_pad.add_theme_constant_override("margin_top",    4)
	grid_pad.add_theme_constant_override("margin_bottom", 8)
	vbox.add_child(grid_pad)

	_crafting_grid = CraftingGrid.new()
	_crafting_grid.name = "BuildingCraftingGrid"
	_crafting_grid.recipe_selected.connect(_on_building_recipe_selected)
	grid_pad.add_child(_crafting_grid)

	return vbox


func _open_crafting_view() -> void:
	cancel_all_editors()  # closes rename, speed editor, pickers (_crafting_view_open still false here)
	_crafting_view_open = true
	_crafting_btn_host.visible = false
	_production_section.visible = false
	_residents_section.visible = false
	_transport_section.visible = false
	_upgrades_section.visible = false
	_crafting_section.visible = true
	CraftingRegistry.set_selected_storage(_building_id)
	_crafting_grid.populate(_build_crafting_list(),
			CraftingRegistry.get_active_recipe_id(), 0.0)


func _close_crafting_view() -> void:
	_crafting_view_open = false
	_crafting_section.visible = false
	_production_section.visible = true
	refresh()


func _build_crafting_list() -> Array[Dictionary]:
	var player: Node = get_tree().get_first_node_in_group(&"player_character")
	var current_energy: int = player.get_current_energy() if player != null else 0
	var result: Array[Dictionary] = []
	for recipe_id: StringName in CraftingRegistry.RECIPE_ORDER:
		if not ProgressionSystem.is_recipe_unlocked(recipe_id):
			continue
		var cost: Dictionary      = CraftingRegistry.RECIPE_COST.get(recipe_id, {})
		var energy_cost: int      = CraftingRegistry.RECIPE_ENERGY_COST.get(recipe_id, 0)
		var display_name: String  = CraftingRegistry.RECIPE_DISPLAY_NAME.get(recipe_id, str(recipe_id))
		var available: Dictionary = {}
		var can_afford: bool      = true
		for res_id: StringName in cost:
			var have: int     = InventorySystem.get_global_quantity(res_id)
			available[res_id] = have
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


func _on_building_recipe_selected(recipe_id: StringName) -> void:
	if CraftingRegistry.is_crafting():
		_spawn_bdv_craft_float("Already crafting!", Color("#E05050"))  # TODO: localize
		return
	var result: int = CraftingRegistry.try_craft(recipe_id)
	match result:
		CraftingRegistry.CraftResult.NO_STORAGE:
			_spawn_bdv_craft_float("No storage available!", Color("#E05050"))  # TODO: localize
		CraftingRegistry.CraftResult.LOCKED:
			_spawn_bdv_craft_float("Locked — unlock in tech tree", Color("#E05050"))  # TODO: localize
		CraftingRegistry.CraftResult.SUCCESS:
			TickSystem.set_pause(false)


func _on_bdv_crafting_started(_recipe_id: StringName, _total_ticks: int) -> void:
	if _crafting_view_open:
		_crafting_grid.populate(_build_crafting_list(),
				CraftingRegistry.get_active_recipe_id(), 0.0)


func _on_bdv_crafting_progress(_recipe_id: StringName, progress: float) -> void:
	if _crafting_view_open:
		_crafting_grid.update_progress(progress)


func _on_bdv_recipe_crafted(recipe_id: StringName, qty: int) -> void:
	if not _crafting_view_open:
		return
	_crafting_grid.populate(_build_crafting_list())
	var display_name: String = CraftingRegistry.RECIPE_DISPLAY_NAME.get(recipe_id, str(recipe_id))
	_spawn_bdv_craft_float("+%d %s" % [qty, display_name])


func _spawn_bdv_craft_float(text: String, color: Color = Color("#D4A85C")) -> void:
	var craft_rect: Rect2 = _crafting_grid.get_global_rect()
	var local_origin := Vector2(
		craft_rect.position.x + craft_rect.size.x * 0.5,
		craft_rect.position.y + 60.0
	) - global_position
	var label := Label.new()
	label.text     = text
	label.position = local_origin + Vector2(-40.0, 0.0)
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
