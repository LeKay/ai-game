class_name TileInteractionPanel extends CanvasLayer
## Tile Interaction Panel — shows harvest cost preview on tile click.
## AC1-AC8: populated from PlayerCharacter.get_cost_preview(); closes on harvest,
## Escape, or click-outside. ADR-0007: reads cost-preview dict, calls try_start_action().

## Emitted when the user clicks outside the panel in the world area.
## map_root connects this to decide whether to update the panel (new tile, AC7)
## or close it (invalid/IMPASSABLE tile, AC6).
signal world_click_at(screen_pos: Vector2)

@onready var _click_guard: ColorRect = $ClickGuard
@onready var _vbox: VBoxContainer = $Panel/VBox
@onready var _energy_cost_label: Label = $Panel/VBox/CostRow/EnergyCostLabel
@onready var _tick_cost_label: Label = $Panel/VBox/CostRow/TickCostLabel
@onready var _output_label: Label = $Panel/VBox/OutputLabel
@onready var _block_reason_label: Label = $Panel/VBox/BlockReasonLabel
@onready var _harvest_button: Button = $Panel/VBox/HarvestButton
@onready var _clear_separator: HSeparator = $Panel/VBox/ClearSeparator
@onready var _clear_energy_cost_label: Label = $Panel/VBox/ClearCostRow/ClearEnergyCostLabel
@onready var _clear_tick_cost_label: Label = $Panel/VBox/ClearCostRow/ClearTickCostLabel
@onready var _clear_output_label: Label = $Panel/VBox/ClearOutputLabel
@onready var _clear_block_reason_label: Label = $Panel/VBox/ClearBlockReasonLabel
@onready var _clear_button: Button = $Panel/VBox/ClearButton

## Shared draggable frame (ADR-0014). The .tscn body is reparented into its
## content at _ready; title + close are provided by the window.
var _window: DraggableWindow

var _current_action_type: int = -1
var _current_clear_action_type: int = -1


func _ready() -> void:
	visible = false
	_wrap_in_window()
	_click_guard.gui_input.connect(_on_click_guard_input)
	_harvest_button.pressed.connect(_on_harvest_pressed)
	_clear_button.pressed.connect(_on_clear_pressed)


## Move the .tscn panel body into a DraggableWindow so it gains the shared
## title bar (drag + close). Existing @onready node refs stay valid — they
## resolve before this runs; reparenting keeps the same instances.
func _wrap_in_window() -> void:
	var old_panel: PanelContainer = $Panel
	_window = DraggableWindow.new()
	_window.name = "Window"
	_window.custom_minimum_size = Vector2(200, 0)
	_window.close_requested.connect(close)
	add_child(_window)

	old_panel.remove_child(_vbox)
	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 12)
	body_margin.add_theme_constant_override("margin_right", 12)
	body_margin.add_theme_constant_override("margin_top", 10)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	_window.content.add_child(body_margin)
	body_margin.add_child(_vbox)
	old_panel.queue_free()


## Show or update the panel at screen_pos for action_type.
## If already visible, updates in place without a duplicate context push (AC7).
func show_at(screen_pos: Vector2, action_type: int) -> void:
	_current_action_type = action_type
	_current_clear_action_type = _harvest_to_clear_action(action_type)
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
	_current_clear_action_type = -1


func _populate(action_type: int) -> void:
	_window.title = _action_type_to_label(action_type)
	var pc := get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if pc == null:
		_harvest_button.disabled = true
		_harvest_button.text = "Harvest"
		_block_reason_label.visible = false
		_energy_cost_label.text = ""
		_tick_cost_label.text = ""
		_output_label.text = ""
		_set_clear_section_visible(false)
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
	else:
		var depleted: bool = preview.get("depleted", false)
		var qty: int = preview.get("output_qty", 0)
		var resource: StringName = preview.get("output_resource", &"")
		var resource_display: String = str(resource) if resource != &"" else "random"
		var suffix: String = " (depleted)" if depleted else ""
		_energy_cost_label.text = "⚡%d" % preview.get("energy_cost", 0)
		_tick_cost_label.text = "⏱️%d" % preview.get("tick_cost", 0)
		_output_label.text = "-> %d %s%s" % [qty, resource_display, suffix]
		_harvest_button.text = "Harvest -- %d %s" % [qty, resource_display]

	_populate_clear_section(pc)


func _position_at(screen_pos: Vector2) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = _window.get_minimum_size()
	if panel_size == Vector2.ZERO:
		panel_size = Vector2(240.0, 200.0)
	var pos: Vector2 = screen_pos + Vector2(8.0, 0.0)
	pos.x = clampf(pos.x, 0.0, viewport_size.x - panel_size.x)
	pos.y = clampf(pos.y, 0.0, viewport_size.y - panel_size.y)
	_window.set_position(pos)


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


func _on_clear_pressed() -> void:
	if _current_clear_action_type < 0:
		return
	var pc := get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if pc != null:
		pc.try_start_action(_current_clear_action_type)
	close()


func _populate_clear_section(pc: PlayerCharacter) -> void:
	if _current_clear_action_type < 0:
		_set_clear_section_visible(false)
		return
	_set_clear_section_visible(true)
	var preview: Dictionary = pc.get_cost_preview(_current_clear_action_type)
	var blocked: bool = preview.get("blocked", true)
	_clear_button.disabled = blocked
	_clear_block_reason_label.visible = blocked
	if blocked:
		_clear_block_reason_label.text = preview.get("reason", "")
		_clear_energy_cost_label.text = ""
		_clear_tick_cost_label.text = ""
		_clear_output_label.text = ""
		_clear_button.text = "Clear Tile"
	else:
		var qty: int = preview.get("output_qty", 0)
		var resource: StringName = preview.get("output_resource", &"")
		var resource_display: String = str(resource) if resource != &"" else "?"
		_clear_energy_cost_label.text = "⚡%d" % preview.get("energy_cost", 0)
		_clear_tick_cost_label.text = "⏱️%d" % preview.get("tick_cost", 0)
		_clear_output_label.text = "-> %d %s (tile removed)" % [qty, resource_display]
		_clear_button.text = "Clear Tile -- %d %s" % [qty, resource_display]


func _set_clear_section_visible(show: bool) -> void:
	_clear_separator.visible = show
	_clear_energy_cost_label.get_parent().visible = show
	_clear_output_label.visible = show
	_clear_button.visible = show
	if not show:
		_clear_block_reason_label.visible = false


func _harvest_to_clear_action(action_type: int) -> int:
	match action_type:
		PlayerCharacter.ManualActionType.CHOP_TREE:     return PlayerCharacter.ManualActionType.CLEAR_TREE
		PlayerCharacter.ManualActionType.MINE_STONE:    return PlayerCharacter.ManualActionType.CLEAR_STONE
		PlayerCharacter.ManualActionType.PICK_BERRIES:  return PlayerCharacter.ManualActionType.CLEAR_BERRY
		PlayerCharacter.ManualActionType.HARVEST_FIBER: return PlayerCharacter.ManualActionType.CLEAR_GRASS
		_: return -1


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



