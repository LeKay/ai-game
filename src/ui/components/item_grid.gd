class_name ItemGrid extends VBoxContainer
## Reusable fluid item grid — renders one block per resource type.
## Feed data via populate(). No coupling to InventorySystem.
## Reusable in the global inventory overlay and per-container building detail panels.
## Extends VBoxContainer so Godot's layout system propagates the available width
## to the inner HFlowContainer, enabling correct horizontal wrapping.

## Emitted when the player left-clicks an item block.
signal item_clicked(resource_id: StringName)
## Emitted on mousedown — callers that need drag-from-grid behaviour connect here.
signal item_drag_started(resource_id: StringName)

const BLOCK_WIDTH  := 72
const BLOCK_HEIGHT := 84
const BLOCK_GAP    := 8
const ICON_SIZE    := 48

const COLOR_BLOCK_BG     := UiPalette.BLOCK_BG
const COLOR_BLOCK_BORDER := UiPalette.BLOCK_BORDER
const COLOR_HOVER_BORDER := UiPalette.HOVER_BORDER
const COLOR_QTY_TEXT     := UiPalette.TEXT_PRIMARY

## Seconds the mouse must be held before a drag is initiated instead of a click.
const DRAG_HOLD_SECONDS := 0.3

## Set before adding to scene tree to center item blocks horizontally.
var center: bool = false
## Set before adding to scene tree to hide the empty-state label.
var hide_empty: bool = false

var _flow: HFlowContainer
var _empty_label: Label


func _ready() -> void:
	_flow = HFlowContainer.new()
	_flow.name = "ItemFlow"
	_flow.add_theme_constant_override("h_separation", BLOCK_GAP)
	_flow.add_theme_constant_override("v_separation", BLOCK_GAP)
	_flow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if center else Control.SIZE_EXPAND_FILL
	add_child(_flow)

	_empty_label = Label.new()
	_empty_label.name                = "EmptyLabel"
	_empty_label.text                = "No items in storage yet"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.visible = false
	if not hide_empty:
		add_child(_empty_label)


## Centers item blocks within the column instead of flowing left-to-right.
## Call after adding the node to the scene tree.
func center_items() -> void:
	_flow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

## Hides the empty-state label so the grid stays blank when no items are present.
func hide_empty_label() -> void:
	_empty_label.visible = false


## Replaces all item blocks with a fresh render of `items`.
## Each entry must have keys: resource_id (StringName), quantity (int).
func populate(items: Array[Dictionary]) -> void:
	for child in _flow.get_children():
		child.queue_free()

	if items.is_empty():
		_flow.visible        = false
		_empty_label.visible = true
		if center:
			_flow.custom_minimum_size.x = 0
		return

	_flow.visible        = true
	_empty_label.visible = false

	for item: Dictionary in items:
		_flow.add_child(_make_block(item[&"resource_id"], item[&"quantity"], item.get(&"subtitle", "")))

	if center:
		var n := items.size()
		_flow.custom_minimum_size.x = n * BLOCK_WIDTH + maxi(n - 1, 0) * BLOCK_GAP


func _make_block(resource_id: StringName, quantity: int, subtitle: String = "") -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BLOCK_WIDTH, BLOCK_HEIGHT)
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP
	if resource_id != &"*":
		var def := ResourceRegistry.get_definition(resource_id)
		if def != null:
			panel.tooltip_text = def.display_name

	var style := StyleFactory.block(COLOR_BLOCK_BG, COLOR_BLOCK_BORDER, 1, 0)
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

	if resource_id == &"*":
		var wc_lbl := Label.new()
		wc_lbl.text                 = "*"
		wc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wc_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		wc_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wc_lbl.add_theme_font_size_override("font_size", 28)
		wc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(wc_lbl)
	else:
		var icon_rect := TextureRect.new()
		icon_rect.texture      = ResourceRegistry.get_icon_texture(resource_id, ICON_SIZE / 2)
		icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(icon_rect)

	var qty_lbl := Label.new()
	qty_lbl.text                  = "×%d" % quantity
	qty_lbl.visible               = quantity >= 0
	qty_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_lbl.add_theme_font_size_override("font_size", 14)
	qty_lbl.add_theme_color_override("font_color", COLOR_QTY_TEXT)
	qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(qty_lbl)

	if subtitle != "":
		var sub_lbl := Label.new()
		sub_lbl.text = subtitle
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub_lbl.add_theme_font_size_override("font_size", 10)
		sub_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(sub_lbl)

	panel.mouse_entered.connect(func() -> void: style.border_color = COLOR_HOVER_BORDER)
	panel.mouse_exited.connect(func() -> void:  style.border_color = COLOR_BLOCK_BORDER)
	# Dictionary used as a mutable reference shared across lambdas —
	# GDScript captures primitives by value so bool would not propagate between callbacks.
	var state := {"drag_pending": false}
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			state["drag_pending"] = true
			get_tree().create_timer(DRAG_HOLD_SECONDS).timeout.connect(func() -> void:
				if state["drag_pending"]:
					state["drag_pending"] = false
					item_drag_started.emit(resource_id)
			)
		else:
			if state["drag_pending"]:
				state["drag_pending"] = false
				item_clicked.emit(resource_id)
	)

	return panel
