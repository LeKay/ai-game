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

const COLOR_BLOCK_BG     := Color("#2a2a2a")
const COLOR_BLOCK_BORDER := Color("#4a4a4a")
const COLOR_HOVER_BORDER := Color("#A8A49C")
const COLOR_QTY_TEXT     := Color("#F0EDE6")

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
		return

	_flow.visible        = true
	_empty_label.visible = false

	for item: Dictionary in items:
		_flow.add_child(_make_block(item[&"resource_id"], item[&"quantity"]))


func _make_block(resource_id: StringName, quantity: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BLOCK_WIDTH, BLOCK_HEIGHT)
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color            = COLOR_BLOCK_BG
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color        = COLOR_BLOCK_BORDER
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

	var icon_lbl := Label.new()
	icon_lbl.text                = _resource_icon(resource_id)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_lbl.add_theme_font_size_override("font_size", 28)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_lbl)

	var qty_lbl := Label.new()
	qty_lbl.text                  = "×%d" % quantity
	qty_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_lbl.add_theme_font_size_override("font_size", 14)
	qty_lbl.add_theme_color_override("font_color", COLOR_QTY_TEXT)
	qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(qty_lbl)

	panel.mouse_entered.connect(func() -> void: style.border_color = COLOR_HOVER_BORDER)
	panel.mouse_exited.connect(func() -> void:  style.border_color = COLOR_BLOCK_BORDER)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			item_clicked.emit(resource_id)
			item_drag_started.emit(resource_id)
	)

	return panel


func _resource_icon(resource_id: StringName) -> String:
	match resource_id:
		&"wood":  return "🪵"
		&"stone": return "🪨"
		&"berry": return "🫐"
		&"fiber": return "🌿"
		&"tool":  return "🪓"
		_:        return "📦"
