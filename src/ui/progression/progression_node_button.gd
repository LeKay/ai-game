class_name ProgressionNodeButton extends Button
## A single clickable node in the Progression Tree. Pure view: it renders one
## ProgressionSystem node in one of three states and reports clicks upward — it never
## mutates unlock state itself (see .claude/rules/ui-code.md).
##
## STEP 1: hosted by ProgressionTreeScreen. The node is a circular badge showing the
## node's icon glyph, with its display name on a label beneath the circle. Styling is
## code-built so the node has no scene dependency; the UX spec
## (design/ux/progression-tree.md) will refine exact art/colors/feel before final polish.

enum State { LOCKED, AVAILABLE, UNLOCKED }

const DIAMETER := 72.0
const NODE_SIZE := Vector2(DIAMETER, DIAMETER)
## How far below the circle the name label sits, and how wide it may grow (centered on
## the circle). Wider than the circle so two-word names stay readable without resizing it.
const LABEL_TOP := DIAMETER + 6.0
const LABEL_WIDTH := 132.0
const FALLBACK_ICON := "●"

const COLOR_TEXT := Color("#F0EDE6")
const COLOR_LABEL_LOCKED := Color(0.55, 0.55, 0.58)
const COLOR_LOCKED_BG := Color(0.16, 0.16, 0.18, 0.9)
const COLOR_LOCKED_BORDER := Color(0.3, 0.3, 0.33, 1.0)
const COLOR_AVAILABLE_BORDER := Color("#FFD24A")
const BORDER_AVAILABLE := 3
const BORDER_DEFAULT := 2

## Emitted when the player clicks this node. The screen decides what to do with it.
signal node_clicked(node_id: StringName)

var node_id: StringName
var _branch_color: Color = Color(0.4, 0.45, 0.5)
var _state: State = State.LOCKED
var _label: Label


func setup(p_node_id: StringName, display_name: String, icon: String, branch_color: Color) -> void:
	node_id = p_node_id
	text = icon if not icon.is_empty() else FALLBACK_ICON
	tooltip_text = display_name
	_branch_color = branch_color
	custom_minimum_size = NODE_SIZE
	size = NODE_SIZE
	focus_mode = Control.FOCUS_NONE
	add_theme_font_size_override("font_size", 30)
	add_theme_color_override("font_color", COLOR_TEXT)
	add_theme_color_override("font_hover_color", COLOR_TEXT)
	add_theme_color_override("font_pressed_color", COLOR_TEXT)
	add_theme_color_override("font_disabled_color", COLOR_LABEL_LOCKED)

	_build_label(display_name)

	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	set_state(State.LOCKED)


## Name label centered under the circle. It is a child of the button but sits outside the
## circular hit area, so clicks on it do not register — only the circle is clickable.
func _build_label(display_name: String) -> void:
	_label = Label.new()
	_label.text = display_name
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2((DIAMETER - LABEL_WIDTH) * 0.5, LABEL_TOP)
	_label.size = Vector2(LABEL_WIDTH, 0)
	_label.add_theme_font_size_override("font_size", 12)
	add_child(_label)


## Sets the visual state and re-applies the matching styleboxes.
func set_state(new_state: State) -> void:
	_state = new_state
	disabled = (new_state == State.LOCKED)
	var box := _style_for_state(new_state)
	add_theme_stylebox_override("normal", box)
	add_theme_stylebox_override("hover", _style_for_state(new_state, 1.15))
	add_theme_stylebox_override("pressed", _style_for_state(new_state, 0.9))
	add_theme_stylebox_override("disabled", box)
	if _label != null:
		var label_color := COLOR_TEXT if new_state != State.LOCKED else COLOR_LABEL_LOCKED
		_label.add_theme_color_override("font_color", label_color)


func get_state() -> State:
	return _state


## Builds a circular StyleBoxFlat (corner radius = half the diameter) for the given state.
func _style_for_state(state: State, brightness: float = 1.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	var r := int(DIAMETER * 0.5)
	box.corner_radius_top_left = r
	box.corner_radius_top_right = r
	box.corner_radius_bottom_left = r
	box.corner_radius_bottom_right = r
	match state:
		State.UNLOCKED:
			box.bg_color = (_branch_color * brightness).clamp()
			box.border_color = (_branch_color * 1.4).clamp()
			_set_border(box, BORDER_DEFAULT)
		State.AVAILABLE:
			var bg := _branch_color * 0.35
			bg.a = 0.95
			box.bg_color = (bg * brightness).clamp()
			box.border_color = COLOR_AVAILABLE_BORDER
			_set_border(box, BORDER_AVAILABLE)
		State.LOCKED:
			box.bg_color = COLOR_LOCKED_BG
			box.border_color = COLOR_LOCKED_BORDER
			_set_border(box, BORDER_DEFAULT)
	return box


func _set_border(box: StyleBoxFlat, width: int) -> void:
	box.border_width_left = width
	box.border_width_right = width
	box.border_width_top = width
	box.border_width_bottom = width


func _on_pressed() -> void:
	node_clicked.emit(node_id)
