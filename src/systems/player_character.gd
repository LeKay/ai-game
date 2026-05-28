class_name PlayerCharacter extends Node
## PlayerCharacter: Foundation autoload singleton for player state and manual actions.
## ADR-0007: Energy pool (001), action dispatch (002), drag-drop transport (003),
## depletion-food (004), architect mode (005).

# ---- Signals ----------------------------------------------------------------

signal energy_changed(current: int, max_energy: int)
signal energy_depletion_changed(is_depleted: bool)
signal action_started(action_id: int, tick_cost: int)
signal action_completed(action_id: int, output: Array)
signal action_failed(action_id: int, reason: String)
signal action_progress_update(progress: float, effective_tick_cost: int, effective_output: int)
signal food_consumed(food_type: StringName, energy_restored: int)
signal architect_mode_triggered()
signal relocation_started(source: Vector2i, resource_id: StringName)
signal relocation_completed(source: Vector2i, target: Vector2i, resource_id: StringName)
signal relocation_cancelled(source: Vector2i)

# ---- Enums ------------------------------------------------------------------

enum ManualActionType {
	FORAGE,
	PICK_BERRIES,
	CRAFT_TOOL,
	CHOP_TREE,
	MINE_STONE,
	HARVEST_FIBER,
}

enum StartResult {
	SUCCESS,
	BLOCKED_SLOT,
	INSUFFICIENT_ENERGY,
	ARCHITECT_LOCKED,
	TOOL_REQUIRED,
}

enum RelocationResult {
	SUCCESS,
	SNAP_BACK_ENERGY,   ## insufficient energy
	SNAP_BACK_INVALID,  ## target impassable / out-of-bounds
	SNAP_BACK_FULL,     ## target tile already at MAX_RESOURCES_PER_TILE
	SNAP_BACK_SAME_TILE, ## distance 0 — paid 1 energy, icon stays
	NOT_DRAGGING,       ## commit called when state is IDLE
}

# ---- Inner classes ----------------------------------------------------------

## Depletion modifier pair returned by EnergyPool.get_depletion_modifier().
class DepletionMod:
	var tick_multiplier: float
	var output_multiplier: float

	func _init(p_tick: float, p_output: float) -> void:
		tick_multiplier = p_tick
		output_multiplier = p_output


## Energy pool with depletion tracking.
## All operations clamp current to [0, max_energy].
class EnergyPool:
	var current: int = 100
	var max_energy: int = 100
	var _depletion_flag: bool = false
	var _on_energy_changed: Callable
	var _on_depletion_changed: Callable

	func _init(on_energy_changed: Callable, on_depletion_changed: Callable) -> void:
		_on_energy_changed = on_energy_changed
		_on_depletion_changed = on_depletion_changed

	## Returns false (no change) if current < amount; deducts and returns true otherwise.
	func try_spend(amount: int) -> bool:
		if current < amount:
			return false
		current = clampi(current - amount, 0, max_energy)
		_notify()
		return true

	## Deducts amount unconditionally; clamps to 0 if insufficient.
	func spend_unchecked(amount: int) -> void:
		current = clampi(current - amount, 0, max_energy)
		_notify()

	## Adds amount; clamps to max_energy.
	func restore(amount: int) -> void:
		current = clampi(current + amount, 0, max_energy)
		_notify()

	## True only when current == 0.
	func is_depleted() -> bool:
		return current == 0

	## 2x tick / 0.5x output when depleted; 1x / 1x otherwise.
	func get_depletion_modifier() -> DepletionMod:
		if current == 0:
			return DepletionMod.new(2.0, 0.5)
		return DepletionMod.new(1.0, 1.0)

	func _notify() -> void:
		var depleted := current == 0
		var changed := depleted != _depletion_flag
		if changed:
			_depletion_flag = depleted
		_on_energy_changed.call(current, max_energy)
		if changed:
			_on_depletion_changed.call(_depletion_flag)


## Configuration for a single manual action type.
class ManualActionConfig:
	var action_type: int  ## ManualActionType value
	var tick_cost: int
	var energy_cost: int
	var base_output: int
	var output_resource: StringName  ## empty for variable-output actions (forage)
	var requires_tool: bool

	func _init(p_type: int, p_ticks: int, p_energy: int,
			p_output: int, p_resource: StringName, p_tool: bool) -> void:
		action_type = p_type
		tick_cost = p_ticks
		energy_cost = p_energy
		base_output = p_output
		output_resource = p_resource
		requires_tool = p_tool


## Single action slot — binary free/occupied model from ADR-0007.
## Data bag + tick accumulator; decision logic lives in PlayerCharacter.
class ActionSlot:
	enum State { FREE, WORKING, TRANSPORT }

	var state: State = State.FREE
	var action_type: int = -1  ## ManualActionType value
	var config: ManualActionConfig = null
	var accumulated_ticks: int = 0
	var total_ticks: int = 0
	var effective_output: int = 0  ## output quantity with depletion applied

	## Advance the tick accumulator. Returns progress in [0.0, 1.0].
	func advance_ticks(ticks: int) -> float:
		if state == State.FREE:
			return 0.0
		accumulated_ticks += ticks
		if total_ticks <= 0:
			return 1.0
		return clampf(float(accumulated_ticks) / float(total_ticks), 0.0, 1.0)

	## True when accumulated ticks have reached the action's total cost.
	func is_complete() -> bool:
		return state == State.WORKING and accumulated_ticks >= total_ticks

	## Reset slot to FREE state and clear all action data.
	func free_slot() -> void:
		state = State.FREE
		config = null
		action_type = -1
		accumulated_ticks = 0
		total_ticks = 0
		effective_output = 0

	## Abort the current action and free the slot.
	func cancel() -> void:
		free_slot()


## Architect mode: one-way lockout of manual gathering after first NPC assignment.
class ArchitectMode:
	var locked: bool = false

	## Called when an NPC is assigned to a building — triggers irreversible lockout.
	func on_npc_assigned(_npc_id: StringName, _building_id: StringName) -> void:
		locked = true

	## Returns false for gathering actions when locked; Craft Tool is always allowed.
	func can_gather(action_type: int) -> bool:
		if not locked:
			return true
		return action_type == PlayerCharacter.ManualActionType.CRAFT_TOOL


## Drag state machine for tile-to-tile resource relocation.
class RelocationDrag:
	## SNAP_BACK is reserved — snap-back visual is handled by map_root via RelocationResult, not this state.
	enum DragState { IDLE, DRAGGING, SNAP_BACK }

	var state: DragState = DragState.IDLE
	var source_tile: Vector2i = Vector2i(-1, -1)
	var source_idx: int = -1          ## index into WorldGrid._resources[x][y]
	var resource_id: StringName = &""
	var cached_cost: int = 1          ## updated each frame during drag

# ---- Constants --------------------------------------------------------------

## Food type → energy restoration amount (GDD Rule 6).
const FOOD_ENERGY: Dictionary = {
	&"berry": 10,
	&"bread": 25,
}

## Forage loot table: [resource_id, cumulative_weight]. Total weight = 100.
## Equal 25% distribution across all 4 resource types.
const FORAGE_TABLE: Array = [
	[&"wood",  25],
	[&"stone", 50],
	[&"berry", 75],
	[&"fiber", 100],
]

# ---- State ------------------------------------------------------------------

var _energy_pool: EnergyPool
var _action_slot: ActionSlot
var _architect_mode: ArchitectMode
var _action_configs: Dictionary  ## int (ManualActionType) -> ManualActionConfig
var _rng: RandomNumberGenerator

var _inventory: Node = null   ## injected via init_dependencies()
var _tick_system: Node = null  ## injected via init_dependencies()
var _relocation_drag: RelocationDrag

# ---- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	add_to_group(&"player_character")
	_energy_pool = EnergyPool.new(
		func(c: int, m: int) -> void: energy_changed.emit(c, m),
		func(d: bool) -> void: energy_depletion_changed.emit(d)
	)
	_action_slot = ActionSlot.new()
	_architect_mode = ArchitectMode.new()
	_relocation_drag = RelocationDrag.new()
	_rng = RandomNumberGenerator.new()
	_action_configs = {
		ManualActionType.FORAGE:        ManualActionConfig.new(ManualActionType.FORAGE,       50,  8, 1, &"",      false),
		ManualActionType.PICK_BERRIES:  ManualActionConfig.new(ManualActionType.PICK_BERRIES,  40,  5, 3, &"berry", false),
		ManualActionType.CRAFT_TOOL:    ManualActionConfig.new(ManualActionType.CRAFT_TOOL,   100, 15, 1, &"tool",  false),
		ManualActionType.CHOP_TREE:     ManualActionConfig.new(ManualActionType.CHOP_TREE,     80, 12, 5, &"wood",  true),
		ManualActionType.MINE_STONE:    ManualActionConfig.new(ManualActionType.MINE_STONE,    60, 10, 3, &"stone", true),
		ManualActionType.HARVEST_FIBER: ManualActionConfig.new(ManualActionType.HARVEST_FIBER, 45,  6, 2, &"fiber", false),
	}


## Wire up Foundation system dependencies. Called by scene root or WorldSaveManager.
func init_dependencies(tick: Node, inventory: Node, _grid: Node, _input_ctx: Node) -> void:
	_inventory = inventory
	if _tick_system != null and _tick_system.ticks_advanced.is_connected(_on_ticks_advanced):
		_tick_system.ticks_advanced.disconnect(_on_ticks_advanced)
	_tick_system = tick
	if _tick_system != null:
		_tick_system.ticks_advanced.connect(_on_ticks_advanced)

# ---- Energy API (Story 001) -------------------------------------------------

## Returns the current energy value.
func get_current_energy() -> int:
	return _energy_pool.current


## Returns the maximum energy capacity.
func get_max_energy() -> int:
	return _energy_pool.max_energy


## Returns true when energy is at 0.
func is_depleted() -> bool:
	return _energy_pool.is_depleted()

# ---- Action API (Story 002) -------------------------------------------------

## Returns the current action slot state.
func get_action_state() -> ActionSlot.State:
	return _action_slot.state


## Returns the active action type value, or -1 if slot is free.
func get_active_action_id() -> int:
	return _action_slot.action_type


## Returns true once architect mode is permanently locked.
func is_architect_mode() -> bool:
	return _architect_mode.locked


## Attempt to start a manual action. Returns StartResult value.
## Emits action_started on success; action_failed on any failure.
func try_start_action(action_type: int) -> int:
	var config: ManualActionConfig = _action_configs.get(action_type, null)
	if config == null:
		return StartResult.BLOCKED_SLOT

	if _action_slot.state != ActionSlot.State.FREE:
		action_failed.emit(action_type, _start_result_to_reason(StartResult.BLOCKED_SLOT))
		return StartResult.BLOCKED_SLOT

	if _architect_mode.locked and not _architect_mode.can_gather(action_type):
		action_failed.emit(action_type, _start_result_to_reason(StartResult.ARCHITECT_LOCKED))
		return StartResult.ARCHITECT_LOCKED

	if config.requires_tool and not _has_usable_tool(action_type):
		action_failed.emit(action_type, _start_result_to_reason(StartResult.TOOL_REQUIRED))
		return StartResult.TOOL_REQUIRED

	var depleted := _energy_pool.is_depleted()
	if not depleted:
		if not _energy_pool.try_spend(config.energy_cost):
			action_failed.emit(action_type, _start_result_to_reason(StartResult.INSUFFICIENT_ENERGY))
			return StartResult.INSUFFICIENT_ENERGY
	else:
		_energy_pool.spend_unchecked(config.energy_cost)  # no-op at 0

	_action_slot.action_type = action_type
	_action_slot.config = config
	_action_slot.accumulated_ticks = 0
	_action_slot.state = ActionSlot.State.WORKING

	if depleted:
		_action_slot.total_ticks = config.tick_cost * 2
		_action_slot.effective_output = maxi(1, ceili(config.base_output * 0.5))
	else:
		_action_slot.total_ticks = config.tick_cost
		_action_slot.effective_output = config.base_output

	action_started.emit(action_type, _action_slot.total_ticks)
	return StartResult.SUCCESS


## Returns a cost preview dictionary for hovering over a harvestable tile.
## Keys: blocked (bool), reason (String), energy_cost (int), tick_cost (int),
##       output_qty (int), output_resource (StringName), depleted (bool).
func get_cost_preview(action_type: int) -> Dictionary:
	var config: ManualActionConfig = _action_configs.get(action_type, null)
	if config == null:
		return {blocked = true, reason = "Unknown action"}

	if config.requires_tool and not _has_usable_tool(action_type):
		return {
			blocked = true,
			reason = "No tool available — craft one first",
			energy_cost = 0,
			tick_cost = 0,
			output_qty = 0,
			output_resource = &"",
			depleted = false,
		}

	var depleted := _energy_pool.is_depleted()
	var tick_cost: int = config.tick_cost * 2 if depleted else config.tick_cost
	var output_qty: int = maxi(1, ceili(config.base_output * 0.5)) if depleted else config.base_output

	return {
		blocked = false,
		reason = "",
		energy_cost = config.energy_cost,
		tick_cost = tick_cost,
		output_qty = output_qty,
		output_resource = config.output_resource,
		depleted = depleted,
	}


## Restore energy by consuming a food item. Returns false if food type is unknown.
## Emits food_consumed on success.
func consume_food(food_type: StringName) -> bool:
	var energy_amount: int = FOOD_ENERGY.get(food_type, 0)
	if energy_amount == 0:
		return false
	_energy_pool.restore(energy_amount)
	food_consumed.emit(food_type, energy_amount)
	return true

# ---- Relocation API (Story 007) --------------------------------------------

## Called when LMB press lands on a resource icon.
## Returns false if another action is already in progress.
func try_start_relocation(tile: Vector2i, resource_idx: int, p_resource_id: StringName) -> bool:
	if _relocation_drag.state != RelocationDrag.DragState.IDLE:
		return false
	_relocation_drag.state = RelocationDrag.DragState.DRAGGING
	_relocation_drag.source_tile = tile
	_relocation_drag.source_idx = resource_idx
	_relocation_drag.resource_id = p_resource_id
	_relocation_drag.cached_cost = 1
	relocation_started.emit(tile, p_resource_id)
	return true


## Returns a preview dict {energy_cost, tick_cost} for dropping on target_tile.
## Does not spend energy. Returns zeroed dict when not dragging.
func get_relocation_preview(target_tile: Vector2i) -> Dictionary:
	if _relocation_drag.state != RelocationDrag.DragState.DRAGGING:
		return {energy_cost = 0, tick_cost = 0}
	var dist: int = (abs(target_tile.x - _relocation_drag.source_tile.x)
		+ abs(target_tile.y - _relocation_drag.source_tile.y))
	var base_cost: int = maxi(1, dist)
	var depleted := _energy_pool.is_depleted()
	var energy_cost: int = base_cost * 2 if depleted else base_cost
	var tick_cost: int = base_cost
	_relocation_drag.cached_cost = energy_cost
	return {energy_cost = energy_cost, tick_cost = tick_cost}


## Called on LMB release. Validates energy, calls WorldGrid.move_one_resource(),
## deducts energy. Returns RelocationResult enum value.
func try_commit_relocation(target_tile: Vector2i, grid: Node) -> int:
	if _relocation_drag.state != RelocationDrag.DragState.DRAGGING:
		return RelocationResult.NOT_DRAGGING

	var source: Vector2i = _relocation_drag.source_tile
	var src_idx: int = _relocation_drag.source_idx
	var res_id: StringName = _relocation_drag.resource_id

	# Compute cost with depletion applied.
	var dist: int = abs(target_tile.x - source.x) + abs(target_tile.y - source.y)
	var base_cost: int = maxi(1, dist)
	var depleted := _energy_pool.is_depleted()
	var cost: int = base_cost * 2 if depleted else base_cost

	# Same-tile drop: pay 1 energy (min cost), no WorldGrid mutation.
	if dist == 0:
		if not _energy_pool.try_spend(cost):
			_relocation_drag.state = RelocationDrag.DragState.IDLE
			relocation_cancelled.emit(source)
			return RelocationResult.SNAP_BACK_ENERGY
		_relocation_drag.state = RelocationDrag.DragState.IDLE
		relocation_completed.emit(source, target_tile, res_id)
		return RelocationResult.SNAP_BACK_SAME_TILE

	# Validate target via WorldGrid.
	if grid == null or not grid.is_in_bounds(target_tile):
		_relocation_drag.state = RelocationDrag.DragState.IDLE
		relocation_cancelled.emit(source)
		return RelocationResult.SNAP_BACK_INVALID

	if grid.get_terrain(target_tile) == WorldGrid.TileType.IMPASSABLE:
		_relocation_drag.state = RelocationDrag.DragState.IDLE
		relocation_cancelled.emit(source)
		return RelocationResult.SNAP_BACK_INVALID

	if grid.get_resources(target_tile).size() >= WorldGrid.MAX_RESOURCES_PER_TILE:
		_relocation_drag.state = RelocationDrag.DragState.IDLE
		relocation_cancelled.emit(source)
		return RelocationResult.SNAP_BACK_FULL

	# Check energy before committing.
	if not _energy_pool.try_spend(cost):
		_relocation_drag.state = RelocationDrag.DragState.IDLE
		relocation_cancelled.emit(source)
		return RelocationResult.SNAP_BACK_ENERGY

	# Commit — mutate WorldGrid.
	grid.move_one_resource(source, src_idx, target_tile)
	_relocation_drag.state = RelocationDrag.DragState.IDLE
	relocation_completed.emit(source, target_tile, res_id)
	return RelocationResult.SUCCESS


## Cancels an in-progress drag. No energy spent.
func cancel_relocation() -> void:
	if _relocation_drag.state == RelocationDrag.DragState.IDLE:
		return
	var source: Vector2i = _relocation_drag.source_tile
	_relocation_drag.state = RelocationDrag.DragState.IDLE
	relocation_cancelled.emit(source)


## Returns true when a relocation drag is currently active.
func is_relocating() -> bool:
	return _relocation_drag.state == RelocationDrag.DragState.DRAGGING


# ---- Tick handler -----------------------------------------------------------

func _on_ticks_advanced(n: int) -> void:
	if _action_slot.state == ActionSlot.State.FREE:
		return
	var progress := _action_slot.advance_ticks(n)
	if _action_slot.is_complete():
		_complete_current_action()
	else:
		action_progress_update.emit(progress, _action_slot.total_ticks, _action_slot.effective_output)


func _complete_current_action() -> void:
	var completed_type: int = _action_slot.action_type
	var output := _build_output(_action_slot)
	_action_slot.free_slot()
	action_completed.emit(completed_type, output)


func _build_output(slot: ActionSlot) -> Array:
	var qty: int = slot.effective_output
	if slot.action_type == ManualActionType.FORAGE:
		return [{resource_id = _roll_forage_loot(), quantity = qty}]
	return [{resource_id = slot.config.output_resource, quantity = qty}]


func _roll_forage_loot() -> StringName:
	var roll := _rng.randi_range(1, 100)
	for entry: Array in FORAGE_TABLE:
		if roll <= entry[1]:
			return entry[0]
	return &"stone"

# ---- Helpers ----------------------------------------------------------------

## True when a usable tool exists for tool-requiring actions.
## Falls back to true when _inventory is not injected (test / pre-wire state).
func _has_usable_tool(action_type: int) -> bool:
	var config: ManualActionConfig = _action_configs.get(action_type, null)
	if config == null or not config.requires_tool:
		return true
	if _inventory == null:
		return true
	if _inventory.has_method("has_usable_tool"):
		return _inventory.has_usable_tool()
	return true


func _start_result_to_reason(result: int) -> String:
	match result:
		StartResult.BLOCKED_SLOT:         return "Another action is in progress"
		StartResult.INSUFFICIENT_ENERGY:  return "Not enough energy"
		StartResult.ARCHITECT_LOCKED:     return "Architect mode — manual gathering locked"
		StartResult.TOOL_REQUIRED:        return "No tool available — craft one first"
	return "Unknown"
