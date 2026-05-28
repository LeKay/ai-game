class_name TileInteractionPanel extends CanvasLayer
## Tile Interaction Panel — shows harvest cost preview on tile click.
## AC1-AC8: populated from PlayerCharacter.get_cost_preview(); closes on harvest,
## Escape, or click-outside. ADR-0007: reads cost-preview dict, calls try_start_action().

## Emitted when the user clicks outside the panel in the world area.
## map_root connects this to decide whether to update the panel (new tile, AC7)
## or close it (invalid/IMPASSABLE tile, AC6).
signal world_click_at(screen_pos: Vector2)

@onready var _click_guard: ColorRect = $ClickGuard
@onready var _panel: PanelContainer = $Panel
@onready var _resource_label: Label = $Panel/VBox/HeaderRow/ResourceLabel
@onready var _close_button: Button = $Panel/VBox/HeaderRow/CloseButton
@onready var _energy_cost_label: Label = $Panel/VBox/CostRow/EnergyCostLabel
@onready var _tick_cost_label: Label = $Panel/VBox/CostRow/TickCostLabel
@onready var _output_label: Label = $Panel/VBox/OutputLabel
@onready var _block_reason_label: Label = $Panel/VBox/BlockReasonLabel
@onready var _harvest_button: Button = $Panel/VBox/HarvestButton

var _current_action_type: int = -1


func _ready() -> void:
	visible = false
	_click_guard.gui_input.connect(_on_click_guard_input)
	_harvest_button.pressed.connect(_on_harvest_pressed)
	_close_button.pressed.connect(close)


## Show or update the panel at screen_pos for action_type.
## If already visible, updates in place without a duplicate context push (AC7).
func show_at(screen_pos: Vector2, action_type: int) -> void:
	_current_action_type = action_type
	_populate(action_type)
	_position_at(screen_pos)
	if not visible:
		InputContext.push_context(InputContext.Context.UI_ACTIVE)
		visible = true


## Close the panel and restore the input context.
func close() -> void:
	if visible:
		InputContext.pop_context()
	visible = false
	_current_action_type = -1


func _populate(action_type: int) -> void:
	_resource_label.text = _action_type_to_label(action_type)
	var pc := get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if pc == null:
		_harvest_button.disabled = true
		_harvest_button.text = "Harvest"
		_block_reason_label.visible = false
		_energy_cost_label.text = ""
		_tick_cost_label.text = ""
		_output_label.text = ""
		return
	var preview: Dictionary = pc.get_cost_preview(action_type)
	var blocked: bool = preview.get("blocked", true)
	_harvest_button.disabled = blocked
	_block_reason_label.visible = blocked
	if blocked:
		_block_reason_label.text = preview.get("reason", "")
		_energy_cost_label.text = ""
		_tick_cost_label.text = ""
		_output_label.text = ""
		_harvest_button.text = "Harvest"
		return
	var depleted: bool = preview.get("depleted", false)
	var qty: int = preview.get("output_qty", 0)
	var resource: StringName = preview.get("output_resource", &"")
	var resource_display: String = str(resource) if resource != &"" else "random"
	var suffix: String = " (depleted)" if depleted else ""
	_energy_cost_label.text = "⚡%d" % preview.get("energy_cost", 0)
	_tick_cost_label.text = "⏱️%d" % preview.get("tick_cost", 0)
	_output_label.text = "-> %d %s%s" % [qty, resource_display, suffix]
	_harvest_button.text = "Harvest -- %d %s" % [qty, resource_display]


func _position_at(screen_pos: Vector2) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = _panel.get_minimum_size()
	if panel_size == Vector2.ZERO:
		panel_size = Vector2(240.0, 200.0)
	var pos: Vector2 = screen_pos + Vector2(8.0, 0.0)
	pos.x = clampf(pos.x, 0.0, viewport_size.x - panel_size.x)
	pos.y = clampf(pos.y, 0.0, viewport_size.y - panel_size.y)
	_panel.set_position(pos)


func _on_click_guard_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			world_click_at.emit(mb.global_position)


func _on_harvest_pressed() -> void:
	if _current_action_type < 0:
		return
	var pc := get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if pc != null:
		pc.try_start_action(_current_action_type)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel_action"):
		close()
		get_viewport().set_input_as_handled()


func _action_type_to_label(action_type: int) -> String:
	match action_type:
		PlayerCharacter.ManualActionType.CHOP_TREE:     return "Wood"
		PlayerCharacter.ManualActionType.MINE_STONE:    return "Stone"
		PlayerCharacter.ManualActionType.PICK_BERRIES:  return "Berry"
		PlayerCharacter.ManualActionType.HARVEST_FIBER: return "Fiber"
		PlayerCharacter.ManualActionType.FORAGE:        return "Forage"
		_:                                              return "Unknown"
