class_name NpcGrid extends VBoxContainer
## Reusable NPC tile grid — renders one block per NPC.
## Feed data via populate(). No coupling to NPCSystem.
## Mirrors ItemGrid's tile pattern but displays NPC identity and state.

signal npc_clicked(npc_id: StringName)

const BLOCK_WIDTH  := 72
const BLOCK_HEIGHT := 92
const BLOCK_GAP    := 8
const ICON_SIZE    := 40

const COLOR_BLOCK_BG     := Color("#2a2a2a")
const COLOR_BLOCK_BORDER := Color("#4a4a4a")
const COLOR_HOVER_BORDER := Color("#A8A49C")
const COLOR_TEXT_DIM     := Color("#A8A49C")

## TaskState index → display label.
const STATE_LABELS: Array[String] = [
	"Idle",        # 0 IDLE
	"Travelling",  # 1 TRAVEL_TO_BUILDING
	"Working",     # 2 WORK_AT_BUILDING
	"Returning",   # 3 TRAVEL_TO_STORAGE
	"Depositing",  # 4 DEPOSIT
	"Returning",   # 5 RETURN_TO_BASE
	"Waiting",     # 6 WAITING
]

## TaskState index → color.
const STATE_COLORS: Array[Color] = [
	Color("#808080"),  # 0 IDLE — gray
	Color("#D4A85C"),  # 1 TRAVEL_TO_BUILDING — amber
	Color("#4CAF50"),  # 2 WORK_AT_BUILDING — green
	Color("#D4A85C"),  # 3 TRAVEL_TO_STORAGE — amber
	Color("#4CAF50"),  # 4 DEPOSIT — green
	Color("#D4A85C"),  # 5 RETURN_TO_BASE — amber
	Color("#E05555"),  # 6 WAITING — red
]

## Set before adding to scene tree to centre tiles horizontally.
var center: bool = false

var _flow:        HFlowContainer
var _empty_label: Label


func _ready() -> void:
	_flow = HFlowContainer.new()
	_flow.name = "NpcFlow"
	_flow.add_theme_constant_override("h_separation", BLOCK_GAP)
	_flow.add_theme_constant_override("v_separation", BLOCK_GAP)
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.alignment = FlowContainer.ALIGNMENT_CENTER if center else FlowContainer.ALIGNMENT_BEGIN
	add_child(_flow)

	_empty_label = Label.new()
	_empty_label.name                 = "EmptyLabel"
	_empty_label.text                 = "No workers recruited yet"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.visible = false
	add_child(_empty_label)


## Replaces all tiles with a fresh render of `npcs`.
## Each entry must have keys: npc_id (StringName), state (int — NPCSystem.TaskState).
## Optional key: display_name (String) — shown instead of the raw npc_id.
func populate(npcs: Array[Dictionary]) -> void:
	for child in _flow.get_children():
		child.queue_free()

	if npcs.is_empty():
		_flow.visible        = false
		_empty_label.visible = true
		return

	_flow.visible        = true
	_empty_label.visible = false

	for npc: Dictionary in npcs:
		var display: String = npc.get(&"display_name", "")
		if display == "":
			display = str(npc[&"npc_id"])
		_flow.add_child(_make_block(npc[&"npc_id"], npc[&"state"], display))


func _make_block(npc_id: StringName, state: int, display_name: String) -> Control:
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
	icon_lbl.text                 = "🧑"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_lbl.add_theme_font_size_override("font_size", 24)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_lbl)

	var id_lbl := Label.new()
	id_lbl.text                  = display_name
	id_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	id_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	id_lbl.clip_text  = true
	id_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(id_lbl)

	var state_lbl := Label.new()
	state_lbl.text                  = STATE_LABELS[clampi(state, 0, STATE_LABELS.size() - 1)]
	state_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	state_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_lbl.add_theme_font_size_override("font_size", 11)
	state_lbl.add_theme_color_override("font_color",
		STATE_COLORS[clampi(state, 0, STATE_COLORS.size() - 1)])
	state_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(state_lbl)

	panel.mouse_entered.connect(func() -> void: style.border_color = COLOR_HOVER_BORDER)
	panel.mouse_exited.connect(func() -> void:  style.border_color = COLOR_BLOCK_BORDER)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			npc_clicked.emit(npc_id)
	)

	return panel
