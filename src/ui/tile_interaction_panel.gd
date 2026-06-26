class_name TileInteractionPanel extends CanvasLayer
## Tile Interaction Panel — shows harvest cost preview on tile click.
## AC1-AC8: populated from PlayerCharacter.get_cost_preview(); closes on harvest,
## Escape, or click-outside. ADR-0007: reads cost-preview dict, calls try_start_action().

## Emitted when the user clicks outside the panel in the world area.
## map_root connects this to decide whether to update the panel (new tile, AC7)
## or close it (invalid/IMPASSABLE tile, AC6).
signal world_click_at(screen_pos: Vector2)

## Emitted when the player confirms an action (Harvest or Clear button pressed).
## map_root stores this to enable shift-click repeat on matching tiles.
signal action_confirmed(action_type: int)

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
var _current_tile: Vector2i = Vector2i(-1, -1)

## Dynamically populated plant section (separator + buttons), shown on EMPTY tiles.
var _plant_separator: HSeparator = null
var _plant_container: VBoxContainer = null

## Search section (separator + button + result), shown on harvest/forage tiles.
var _search_separator: HSeparator = null
var _search_button: Button = null
var _search_result_label: Label = null


func _ready() -> void:
	visible = false
	_wrap_in_window()
	_click_guard.gui_input.connect(_on_click_guard_input)
	_harvest_button.pressed.connect(_on_harvest_pressed)
	_clear_button.pressed.connect(_on_clear_pressed)
	_build_plant_section()


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


## Show or update the panel at screen_pos for action_type on tile.
## If already visible, updates in place without a duplicate context push (AC7).
func show_at(screen_pos: Vector2, action_type: int, tile: Vector2i) -> void:
	_current_action_type = action_type
	_current_clear_action_type = _harvest_to_clear_action(action_type)
	_current_tile = tile
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
	_current_tile = Vector2i(-1, -1)


func _populate(action_type: int) -> void:
	_window.title = _action_type_to_label(action_type)
	_output_label.visible = true  # reset; _populate_construct may hide it
	_harvest_button.visible = true  # reset; the progression gate may hide it below
	var pc := get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if pc == null:
		_harvest_button.disabled = true
		_harvest_button.text = "Harvest"
		_block_reason_label.visible = false
		_energy_cost_label.text = ""
		_tick_cost_label.text = ""
		_output_label.text = ""
		_set_clear_section_visible(false)
		_plant_separator.visible = false
		_plant_container.visible = false
		_set_search_section_visible(false)
		return

	if action_type == PlayerCharacter.ManualActionType.CONSTRUCT_BUILDING:
		_populate_construct(pc)
		return

	if action_type == PlayerCharacter.ManualActionType.CONSTRUCT_PATH:
		_populate_construct_path(pc)
		return

	# Progression gate (UI layer): a gather action not yet unlocked in the tech tree is
	# hidden entirely — the harvest row disappears (Clear/Search/Plant still apply).
	if not ProgressionSystem.is_gather_unlocked(action_type):
		_hide_harvest_action()
		_populate_clear_section(pc)
		_populate_plant_section(pc)
		_populate_search_section(pc)
		return

	_harvest_button.visible = true
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
	_populate_plant_section(pc)
	_populate_search_section(pc)


func _populate_construct(pc: PlayerCharacter) -> void:
	var preview: Dictionary = pc.get_cost_preview(PlayerCharacter.ManualActionType.CONSTRUCT_BUILDING, _current_tile)
	var blocked: bool = preview.get("blocked", true)
	_harvest_button.disabled = blocked
	_block_reason_label.visible = blocked
	_output_label.visible = false
	_set_clear_section_visible(false)
	_plant_separator.visible = false
	_plant_container.visible = false
	_set_search_section_visible(false)
	if blocked:
		_block_reason_label.text = preview.get("reason", "")
		_energy_cost_label.text = ""
		_tick_cost_label.text = ""
		_harvest_button.text = "Construct"
	else:
		_energy_cost_label.text = "⚡%d" % preview.get("energy_cost", 0)
		_tick_cost_label.text = "⏱️%d" % preview.get("tick_cost", 0)
		_harvest_button.text = "Construct"


func _populate_construct_path(pc: PlayerCharacter) -> void:
	var preview: Dictionary = pc.get_cost_preview(PlayerCharacter.ManualActionType.CONSTRUCT_PATH, _current_tile)
	var blocked: bool = preview.get("blocked", true)
	_harvest_button.disabled = blocked
	_block_reason_label.visible = blocked
	_output_label.visible = false
	_set_clear_section_visible(false)
	_plant_separator.visible = false
	_plant_container.visible = false
	_set_search_section_visible(false)
	if blocked:
		_block_reason_label.text = preview.get("reason", "")
		_energy_cost_label.text = ""
		_tick_cost_label.text = ""
		_harvest_button.text = "Build Path"
	else:
		_energy_cost_label.text = "⚡%d" % preview.get("energy_cost", 0)
		_tick_cost_label.text = "⏱️%d" % preview.get("tick_cost", 0)
		_harvest_button.text = "Build Path"


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
		pc.try_start_action(_current_action_type, _current_tile)
	action_confirmed.emit(_current_action_type)
	close()


func _on_clear_pressed() -> void:
	if _current_clear_action_type < 0:
		return
	var pc := get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if pc != null:
		pc.try_start_action(_current_clear_action_type, _current_tile)
	action_confirmed.emit(_current_clear_action_type)
	close()


## Hides the harvest row and its cost/output labels for a tech-tree-locked gather action.
func _hide_harvest_action() -> void:
	_harvest_button.visible = false
	_block_reason_label.visible = false
	_output_label.visible = false
	_energy_cost_label.text = ""
	_tick_cost_label.text = ""


func _populate_clear_section(pc: PlayerCharacter) -> void:
	if _current_clear_action_type < 0:
		_set_clear_section_visible(false)
		return
	# Progression gate: clearing a tile unlocks together with harvesting that tile's
	# resource, so hide the Clear option until its node is unlocked.
	if not ProgressionSystem.is_gather_unlocked(_current_clear_action_type):
		_set_clear_section_visible(false)
		return
	# Progression lock: the last stone tile on the map cannot be cleared.
	if _current_clear_action_type == PlayerCharacter.ManualActionType.CLEAR_STONE:
		var wg := get_parent().get_node_or_null("WorldGrid") as WorldGrid
		if wg != null and wg.count_tile_type(WorldGrid.TileType.STONE) <= 1:
			_set_clear_section_visible(true)
			_clear_button.disabled = true
			_clear_block_reason_label.visible = true
			_clear_block_reason_label.text = "Last stone tile — cannot be removed"
			_clear_energy_cost_label.text = ""
			_clear_tick_cost_label.text = ""
			_clear_output_label.text = ""
			_clear_button.text = "Clear Tile"
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


func _build_plant_section() -> void:
	_plant_separator = HSeparator.new()
	_plant_separator.visible = false
	_vbox.add_child(_plant_separator)
	_plant_container = VBoxContainer.new()
	_plant_container.visible = false
	_vbox.add_child(_plant_container)
	_search_separator = HSeparator.new()
	_search_separator.visible = false
	_vbox.add_child(_search_separator)
	_search_button = Button.new()
	_search_button.text = "Search (⚡%d)" % PlayerCharacter.SURVEY_ENERGY
	_search_button.visible = false
	_search_button.pressed.connect(_on_search_pressed)
	_vbox.add_child(_search_button)
	_search_result_label = Label.new()
	_search_result_label.visible = false
	_search_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_search_result_label)


func _populate_plant_section(pc: PlayerCharacter) -> void:
	if _current_action_type != PlayerCharacter.ManualActionType.FORAGE:
		_plant_separator.visible = false
		_plant_container.visible = false
		return
	var world_grid := get_parent().get_node_or_null("WorldGrid") as WorldGrid
	if world_grid != null and world_grid.is_tile_growing(_current_tile):
		_plant_separator.visible = false
		_plant_container.visible = false
		return
	for child in _plant_container.get_children():
		child.queue_free()
	var plant_preview: Dictionary = pc.get_cost_preview(PlayerCharacter.ManualActionType.PLANT_SEED)
	var plant_blocked: bool = plant_preview.get("blocked", false)
	var plant_energy: int = plant_preview.get("energy_cost", 0)
	const SEEDS: Array = [
		[&"tree_seed",  "Plant Tree Seed"],
		[&"grass_seed", "Plant Grass Seed"],
		[&"berry_seed", "Plant Berry Seed"],
		[&"wheat_seed", "Plant Wheat Seed"],
	]
	var any_shown: bool = false
	for entry: Array in SEEDS:
		var seed_id: StringName = entry[0]
		# Wheat only grows on a wheat-fertile map — hide the option elsewhere.
		if seed_id == &"wheat_seed" and (world_grid == null or not world_grid.has_fertility(&"wheat")):
			continue
		var qty: int = InventorySystem.get_global_quantity(seed_id)
		if qty <= 0:
			continue
		var btn := Button.new()
		btn.text = "%s (%d) ⚡%d" % [entry[1], qty, plant_energy]
		btn.disabled = plant_blocked
		var captured_seed: StringName = seed_id
		var captured_tile: Vector2i = _current_tile
		btn.pressed.connect(func() -> void:
			pc.try_start_plant_seed(captured_tile, captured_seed)
			close()
		)
		_plant_container.add_child(btn)
		any_shown = true
	_plant_separator.visible = any_shown
	_plant_container.visible = any_shown


## Shows the Search section for harvest/forage tiles and refreshes the button enabled state.
func _populate_search_section(pc: PlayerCharacter) -> void:
	# Progression gate: the Search action is unlocked by the Prospecting node.
	if not ProgressionSystem.is_search_unlocked():
		_set_search_section_visible(false)
		return
	_search_separator.visible = true
	_search_button.visible = true
	_search_button.disabled = pc.get_current_energy() < PlayerCharacter.SURVEY_ENERGY
	_search_result_label.visible = false
	_search_result_label.text = ""


func _set_search_section_visible(show: bool) -> void:
	_search_separator.visible = show
	_search_button.visible = show
	if not show:
		_search_result_label.visible = false


func _on_search_pressed() -> void:
	if _current_tile == Vector2i(-1, -1):
		return
	var pc := get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if pc == null:
		return
	var result: Dictionary = pc.survey_tile(_current_tile)
	_search_result_label.visible = true
	if result.get("blocked", false):
		_search_result_label.text = result.get("reason", "Cannot search")
		return
	var parts: Array[String] = []
	var dist: int = result.get("deposit_distance", -1)
	var deposit_id: StringName = result.get("deposit_id", &"")
	var deposit_name: String = String(deposit_id).capitalize() if deposit_id != &"" else "deposit"
	if result.get("deposit_revealed", false):
		parts.append("%s pit exposed here!" % deposit_name)
	elif dist == 0 and result.get("reason", "") != "":
		parts.append(result.get("reason", ""))
	elif dist > 0:
		parts.append("Nearest deposit (%s): %d tiles away" % [deposit_name, dist])
	else:
		parts.append("No deposits found")
	_search_result_label.text = "\n".join(parts)
	_search_button.disabled = pc.get_current_energy() < PlayerCharacter.SURVEY_ENERGY


func _set_clear_section_visible(show: bool) -> void:
	_clear_separator.visible = show
	_clear_energy_cost_label.get_parent().visible = show
	_clear_output_label.visible = show
	_clear_button.visible = show
	if not show:
		_clear_block_reason_label.visible = false


func _harvest_to_clear_action(action_type: int) -> int:
	match action_type:
		PlayerCharacter.ManualActionType.CHOP_TREE:          return PlayerCharacter.ManualActionType.CLEAR_TREE
		PlayerCharacter.ManualActionType.MINE_STONE:         return PlayerCharacter.ManualActionType.CLEAR_STONE
		PlayerCharacter.ManualActionType.PICK_BERRIES:       return PlayerCharacter.ManualActionType.CLEAR_BERRY
		PlayerCharacter.ManualActionType.HARVEST_FIBER:      return PlayerCharacter.ManualActionType.CLEAR_GRASS
		PlayerCharacter.ManualActionType.HARVEST_WHEAT:      return PlayerCharacter.ManualActionType.CLEAR_WHEAT
		PlayerCharacter.ManualActionType.CONSTRUCT_BUILDING: return -1
		PlayerCharacter.ManualActionType.CONSTRUCT_PATH:     return -1
		_: return -1


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel_action"):
		close()
		get_viewport().set_input_as_handled()


func _action_type_to_label(action_type: int) -> String:
	match action_type:
		PlayerCharacter.ManualActionType.CHOP_TREE:          return "Wood"
		PlayerCharacter.ManualActionType.MINE_STONE:         return "Stone"
		PlayerCharacter.ManualActionType.PICK_BERRIES:       return "Berry"
		PlayerCharacter.ManualActionType.HARVEST_FIBER:      return "Fiber"
		PlayerCharacter.ManualActionType.HARVEST_WHEAT:      return "Wheat"
		PlayerCharacter.ManualActionType.FORAGE:             return "Forage"
		PlayerCharacter.ManualActionType.CONSTRUCT_BUILDING: return "Construct"
		PlayerCharacter.ManualActionType.CONSTRUCT_PATH:     return "Build Path"
		_:                                                   return "Unknown"



