class_name PlayerCharacter extends Node
## PlayerCharacter: Foundation autoload singleton for player state and manual actions.
## ADR-0007: Energy pool (001), action dispatch (002), drag-drop transport (003),
## depletion-food (004), architect mode (005).

# ---- Signals ----------------------------------------------------------------

signal energy_changed(current: int, max_energy: int)
signal energy_depletion_changed(is_depleted: bool)
signal action_started(action_id: int, tick_cost: int, tile: Vector2i)
signal action_completed(action_id: int, output: Array)
## Emitted when a PLANT_SEED action finishes. map_root calls WorldGrid.plant_seed() on receipt.
signal seed_planted(seed_type: StringName, tile: Vector2i)
signal action_failed(action_id: int, reason: String)
signal action_queued(action_id: int, position_in_queue: int, tile: Vector2i)
signal action_queue_cleared()
signal action_interrupted(tile: Vector2i)
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
	CHOP_TREE,
	MINE_STONE,
	HARVEST_FIBER,
	CLEAR_TREE,
	CLEAR_STONE,
	CLEAR_BERRY,
	CLEAR_GRASS,
	CONSTRUCT_BUILDING,
	CONSTRUCT_PATH,
	INSTALL_UPGRADE,
	PLANT_SEED,  ## Plants a seed on an EMPTY tile; terrain grows after SEED_GROWTH_TICKS ticks.
	HARVEST_WHEAT,  ## Harvests a WHEAT field tile → wheat (+ chance of wheat_seed byproduct).
	CLEAR_WHEAT,    ## Clears a WHEAT field tile for building → wheat (+ wheat_seed byproduct).
	MINE_CLAY,      ## Mines a revealed CLAY pit tile → clay. Unlocked by the Prospecting node.
	MINE_IRON,      ## Mines a revealed IRON pit tile → iron. Unlocked by the Prospecting node.
	MINE_COPPER,    ## Mines a revealed COPPER pit tile → copper. Unlocked by the Prospecting node.
	MINE_TIN,       ## Mines a revealed TIN pit tile → tin. Unlocked by the Prospecting node.
	MINE_SILVER,    ## Mines a revealed SILVER pit tile → silver. Unlocked by the Prospecting node.
	MINE_GOLD,      ## Mines a revealed GOLD pit tile → gold. Unlocked by the Prospecting node.
	MINE_GEMSTONE,  ## Mines a revealed GEMSTONE pit tile → gemstones. Unlocked by the Prospecting node.
	HARVEST_FLAX,   ## Harvests a FLAX field tile → flax.
	HARVEST_HOPS,   ## Harvests a HOPS field tile → hops.
	HARVEST_GRAPES, ## Harvests a GRAPES vineyard tile → grapes.
	HARVEST_OLIVES, ## Harvests an OLIVE grove tile → olives.
	HARVEST_HONEY,  ## Harvests a BEES flower tile → honey.
	GATHER_SAND,    ## Gathers from a SAND beach tile → sand.
	MINE_MARBLE,    ## Mines a MARBLE outcrop tile → marble.
	MINE_AMBER,     ## Mines a revealed AMBER deposit tile → amber. Unlocked by the Prospecting node.
}

enum StartResult {
	SUCCESS,
	QUEUED,
	BLOCKED_SLOT,
	INSUFFICIENT_ENERGY,
	ARCHITECT_LOCKED,
	TOOL_REQUIRED,
	PROGRESSION_LOCKED,  ## gather action not yet unlocked in the Progression Tree
}

enum RelocationResult {
	SUCCESS,
	SUCCESS_LOW_ENERGY, ## moved but energy was insufficient — tick penalty applied
	SNAP_BACK_ENERGY,   ## (unused for transport — kept for API compatibility)
	SNAP_BACK_INVALID,  ## target impassable / out-of-bounds
	SNAP_BACK_FULL,     ## target tile already at MAX_RESOURCES_PER_TILE
	SNAP_BACK_SAME_TILE, ## distance 0 — icon stays
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

	## Returns false for all manual gathering actions when locked.
	## (Tool crafting is not a manual action — it runs through CraftingRegistry
	## and is unaffected by architect mode.)
	func can_gather(_action_type: int) -> bool:
		return not locked


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

## Maximum number of actions that can be queued behind the active one.
const MAX_QUEUE_SIZE: int = 5

## Energy spent per Search action (locating / exposing hidden clay).
const SURVEY_ENERGY: int = 5

## Energy restored per point of food nutrition when eating (GDD Rule 6).
## Energy gain = ResourceRegistry nutrition × this factor. Any resource with
## positive nutrition is edible: berry (1.0) → +10, bread (5.0) → +50,
## meat (4.0) → +40, wheat (0.5) → +5.
const ENERGY_PER_NUTRITION: int = 10

## Forage loot table: [resource_id, cumulative_weight]. Total weight = 100.
## Equal 25% distribution across all 4 resource types.
const FORAGE_TABLE: Array = [
	[&"wood",  25],
	[&"stone", 50],
	[&"berry", 75],
	[&"fiber", 100],
]

## Seed byproduct table: action_type → [chance 0-100, seed_resource_id].
const SEED_BYPRODUCT_CHANCES: Dictionary = {
	ManualActionType.CHOP_TREE:     [5,  &"tree_seed"],
	ManualActionType.PICK_BERRIES:  [5,  &"berry_seed"],
	ManualActionType.HARVEST_FIBER: [5,  &"grass_seed"],
	ManualActionType.CLEAR_TREE:    [20, &"tree_seed"],
	ManualActionType.CLEAR_BERRY:   [20, &"berry_seed"],
	ManualActionType.CLEAR_GRASS:   [20, &"grass_seed"],
	ManualActionType.HARVEST_WHEAT: [5,  &"wheat_seed"],
	ManualActionType.CLEAR_WHEAT:   [20, &"wheat_seed"],
}

# ---- State ------------------------------------------------------------------

var _energy_pool: EnergyPool
var _action_slot: ActionSlot
var _architect_mode: ArchitectMode
var _action_configs: Dictionary[int, ManualActionConfig]
var _rng: RandomNumberGenerator

var _inventory: Node = null   ## injected via init_dependencies()
var _tick_system: Node = null  ## injected via init_dependencies()
var _grid: Node = null         ## WorldGrid, injected via init_dependencies() (fertility + Search)
var _active_seed_type: StringName = &""  ## set when PLANT_SEED action is running
var _relocation_drag: RelocationDrag
var _action_queue: Array[Dictionary] = []  ## entries: {type: int, tile: Vector2i}
var _active_tile: Vector2i = Vector2i(-1, -1)
var _active_building_id: String = ""  ## set when CONSTRUCT_BUILDING action is running
var _active_upgrade_id: StringName = &""  ## set when INSTALL_UPGRADE action is running

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
		ManualActionType.CHOP_TREE:     ManualActionConfig.new(ManualActionType.CHOP_TREE,     80, 12, 5, &"wood",  true),
		ManualActionType.MINE_STONE:    ManualActionConfig.new(ManualActionType.MINE_STONE,    60, 10, 3, &"stone", true),
		ManualActionType.HARVEST_FIBER: ManualActionConfig.new(ManualActionType.HARVEST_FIBER, 45,  6, 2, &"fiber", false),
		ManualActionType.CLEAR_TREE:    ManualActionConfig.new(ManualActionType.CLEAR_TREE,    400, 40, 20, &"wood",  false),
		ManualActionType.CLEAR_STONE:   ManualActionConfig.new(ManualActionType.CLEAR_STONE,  400, 40, 20, &"stone", false),
		ManualActionType.CLEAR_BERRY:   ManualActionConfig.new(ManualActionType.CLEAR_BERRY,  400, 40, 20, &"berry", false),
		ManualActionType.CLEAR_GRASS:   ManualActionConfig.new(ManualActionType.CLEAR_GRASS,  400, 40, 20, &"fiber", false),
		ManualActionType.PLANT_SEED:    ManualActionConfig.new(ManualActionType.PLANT_SEED,    30,  8, 0, &"",     false),
		ManualActionType.HARVEST_WHEAT: ManualActionConfig.new(ManualActionType.HARVEST_WHEAT, 45,  6, 2, &"wheat", false),
		ManualActionType.CLEAR_WHEAT:   ManualActionConfig.new(ManualActionType.CLEAR_WHEAT,  400, 40, 20, &"wheat", false),
		ManualActionType.MINE_CLAY:     ManualActionConfig.new(ManualActionType.MINE_CLAY,    60, 10, 3, &"clay",      false),
		ManualActionType.MINE_IRON:     ManualActionConfig.new(ManualActionType.MINE_IRON,    60, 10, 3, &"iron",      false),
		ManualActionType.MINE_COPPER:   ManualActionConfig.new(ManualActionType.MINE_COPPER,  60, 10, 3, &"copper",    false),
		ManualActionType.MINE_TIN:      ManualActionConfig.new(ManualActionType.MINE_TIN,     60, 10, 3, &"tin",       false),
		ManualActionType.MINE_SILVER:   ManualActionConfig.new(ManualActionType.MINE_SILVER,  60, 10, 3, &"silver",    false),
		ManualActionType.MINE_GOLD:     ManualActionConfig.new(ManualActionType.MINE_GOLD,    60, 10, 3, &"gold",      false),
		ManualActionType.MINE_GEMSTONE: ManualActionConfig.new(ManualActionType.MINE_GEMSTONE, 60, 10, 3, &"gemstones", false),
		ManualActionType.HARVEST_FLAX:   ManualActionConfig.new(ManualActionType.HARVEST_FLAX,   45,  6, 2, &"flax",   false),
		ManualActionType.HARVEST_HOPS:   ManualActionConfig.new(ManualActionType.HARVEST_HOPS,   45,  6, 2, &"hops",   false),
		ManualActionType.HARVEST_GRAPES: ManualActionConfig.new(ManualActionType.HARVEST_GRAPES, 45,  6, 2, &"grapes", false),
		ManualActionType.HARVEST_OLIVES: ManualActionConfig.new(ManualActionType.HARVEST_OLIVES, 45,  6, 2, &"olives", false),
		ManualActionType.HARVEST_HONEY:  ManualActionConfig.new(ManualActionType.HARVEST_HONEY,  45,  6, 2, &"honey",  false),
		ManualActionType.GATHER_SAND:    ManualActionConfig.new(ManualActionType.GATHER_SAND,    50,  8, 3, &"sand",   false),
		ManualActionType.MINE_MARBLE:    ManualActionConfig.new(ManualActionType.MINE_MARBLE,    60, 10, 3, &"marble", true),
		ManualActionType.MINE_AMBER:     ManualActionConfig.new(ManualActionType.MINE_AMBER,     60, 10, 3, &"amber",  false),
	}


## Wire up Foundation system dependencies. Called by scene root or WorldSaveManager.
func init_dependencies(tick: Node, inventory: Node, grid: Node, _input_ctx: Node) -> void:
	_inventory = inventory
	_grid = grid
	if _tick_system != null:
		if _tick_system.ticks_advanced.is_connected(_on_ticks_advanced):
			_tick_system.ticks_advanced.disconnect(_on_ticks_advanced)
		if _tick_system.day_transition.is_connected(_on_day_transition):
			_tick_system.day_transition.disconnect(_on_day_transition)
	_tick_system = tick
	if _tick_system != null:
		_tick_system.ticks_advanced.connect(_on_ticks_advanced)
		if not _tick_system.day_transition.is_connected(_on_day_transition):
			_tick_system.day_transition.connect(_on_day_transition)

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


## Deducts amount from energy pool. Drains to 0 if insufficient.
## Returns false when energy was insufficient; true when fully paid.
## Called by BuildingRegistry (placement cost) and MapRoot (transport cost).
func consume_energy(amount: int) -> bool:
	if DebugSettings.no_energy_cost:
		return true
	if amount <= 0:
		return true
	if _energy_pool.try_spend(amount):
		return true
	_energy_pool.spend_unchecked(amount)
	return false


## Restores up to `amount` energy, clamped to the max. Pass get_max_energy() to top up fully.
## Used by the debug menu's "infinite energy" cheat to refill on activation.
func restore_energy(amount: int) -> void:
	if amount <= 0:
		return
	_energy_pool.restore(amount)

# ---- Action API (Story 002) -------------------------------------------------

## Returns the number of actions waiting in the queue (not counting the active one).
func get_queue_size() -> int:
	return _action_queue.size()


## Returns a copy of the queued entries in order. Each entry: {type: int, tile: Vector2i}.
func get_queued_actions() -> Array[Dictionary]:
	return _action_queue.duplicate()


## Clears all queued actions without affecting the currently running action.
func clear_queue() -> void:
	_action_queue.clear()


## Returns the current action slot state.
func get_action_state() -> ActionSlot.State:
	return _action_slot.state


## Returns the active action type value, or -1 if slot is free.
func get_active_action_id() -> int:
	return _action_slot.action_type


## Returns true once architect mode is permanently locked.
func is_architect_mode() -> bool:
	return _architect_mode.locked


## Returns the building ID the active action targets (CONSTRUCT_BUILDING or INSTALL_UPGRADE).
func get_active_building_id() -> String:
	return _active_building_id


## Returns the upgrade ID being installed, or &"" if no INSTALL_UPGRADE action is running.
func get_active_upgrade_id() -> StringName:
	return _active_upgrade_id


## Returns current action progress in [0.0, 1.0], or 0.0 if idle.
func get_action_progress() -> float:
	if _action_slot.state != ActionSlot.State.WORKING or _action_slot.total_ticks <= 0:
		return 0.0
	return clampf(float(_action_slot.accumulated_ticks) / float(_action_slot.total_ticks), 0.0, 1.0)


## Returns action progress [0.0, 1.0] only if the active action targets tile; 0.0 otherwise.
func get_active_progress_for_tile(tile: Vector2i) -> float:
	if _active_tile != tile:
		return 0.0
	return get_action_progress()


## Attempt to start a manual action. Returns StartResult value.
## Emits action_started on success; action_queued when deferred to queue; action_failed on any failure.
func try_start_action(action_type: int, tile: Vector2i = Vector2i(-1, -1)) -> int:
	if action_type == ManualActionType.CONSTRUCT_BUILDING:
		return _try_start_construct(tile)
	if action_type == ManualActionType.CONSTRUCT_PATH:
		return _try_start_construct_path(tile)
	if action_type == ManualActionType.INSTALL_UPGRADE:
		push_warning("PlayerCharacter: use try_start_upgrade() for INSTALL_UPGRADE")
		return StartResult.BLOCKED_SLOT

	var config: ManualActionConfig = _action_configs.get(action_type, null)
	if config == null:
		return StartResult.BLOCKED_SLOT

	# Progression gate (command layer): reject gather actions not yet unlocked in the
	# tech tree. Unmapped actions (clear/forage) default to unlocked. Rejected before
	# queueing so a locked action can never enter the queue.
	if not ProgressionSystem.is_gather_unlocked(action_type):
		action_failed.emit(action_type, _start_result_to_reason(StartResult.PROGRESSION_LOCKED))
		return StartResult.PROGRESSION_LOCKED

	if _action_slot.state != ActionSlot.State.FREE:
		if _action_queue.size() >= MAX_QUEUE_SIZE:
			action_failed.emit(action_type, _start_result_to_reason(StartResult.BLOCKED_SLOT))
			return StartResult.BLOCKED_SLOT
		_action_queue.append({type = action_type, tile = tile})
		action_queued.emit(action_type, _action_queue.size(), tile)
		return StartResult.QUEUED

	if _architect_mode.locked and not _architect_mode.can_gather(action_type):
		action_failed.emit(action_type, _start_result_to_reason(StartResult.ARCHITECT_LOCKED))
		return StartResult.ARCHITECT_LOCKED

	if config.requires_tool and not _has_usable_tool(action_type):
		action_failed.emit(action_type, _start_result_to_reason(StartResult.TOOL_REQUIRED))
		return StartResult.TOOL_REQUIRED

	var has_energy := _energy_pool.current >= config.energy_cost
	var is_food_action := is_food(config.output_resource)

	if not has_energy and not is_food_action:
		action_failed.emit(action_type, _start_result_to_reason(StartResult.INSUFFICIENT_ENERGY))
		return StartResult.INSUFFICIENT_ENERGY

	if has_energy:
		_energy_pool.try_spend(config.energy_cost)
	else:
		_energy_pool.spend_unchecked(config.energy_cost)  # ADR-0007: cost deducted at start, clamps to 0

	_action_slot.action_type = action_type
	_action_slot.config = config
	_action_slot.accumulated_ticks = 0
	_action_slot.state = ActionSlot.State.WORKING
	_active_tile = tile

	if not has_energy:
		_action_slot.total_ticks = config.tick_cost * 2
		_action_slot.effective_output = maxi(1, ceili(config.base_output * 0.5))
	else:
		_action_slot.total_ticks = config.tick_cost
		_action_slot.effective_output = config.base_output

	action_started.emit(action_type, _action_slot.total_ticks, tile)
	return StartResult.SUCCESS


func _try_start_construct(tile: Vector2i) -> int:
	if _action_slot.state != ActionSlot.State.FREE:
		if _action_queue.size() >= MAX_QUEUE_SIZE:
			action_failed.emit(ManualActionType.CONSTRUCT_BUILDING, _start_result_to_reason(StartResult.BLOCKED_SLOT))
			return StartResult.BLOCKED_SLOT
		_action_queue.append({type = ManualActionType.CONSTRUCT_BUILDING, tile = tile})
		action_queued.emit(ManualActionType.CONSTRUCT_BUILDING, _action_queue.size(), tile)
		return StartResult.QUEUED

	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_instance_at_tile(tile)
	if instance == null or instance.state != BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
		action_failed.emit(ManualActionType.CONSTRUCT_BUILDING, "No construction site here")
		return StartResult.BLOCKED_SLOT

	var tick_cost: int = BuildingRegistry.BUILD_TIME.get(instance.type, 100)
	var energy_cost: int = BuildingRegistry.BUILD_ENERGY.get(instance.type, 20)
	if _energy_pool.current < energy_cost:
		action_failed.emit(ManualActionType.CONSTRUCT_BUILDING, "Not enough energy")
		return StartResult.INSUFFICIENT_ENERGY

	_energy_pool.try_spend(energy_cost)
	_action_slot.action_type = ManualActionType.CONSTRUCT_BUILDING
	_action_slot.config = null
	_action_slot.accumulated_ticks = 0
	_action_slot.state = ActionSlot.State.WORKING
	_action_slot.total_ticks = tick_cost
	_action_slot.effective_output = 0
	_active_tile = tile
	_active_building_id = instance.building_id

	action_started.emit(ManualActionType.CONSTRUCT_BUILDING, _action_slot.total_ticks, tile)
	return StartResult.SUCCESS


func _try_start_construct_path(tile: Vector2i) -> int:
	# Progression gate (command layer): laying paths is unlocked by the Paving node.
	if not ProgressionSystem.is_gather_unlocked(ManualActionType.CONSTRUCT_PATH):
		action_failed.emit(ManualActionType.CONSTRUCT_PATH, _start_result_to_reason(StartResult.PROGRESSION_LOCKED))
		return StartResult.PROGRESSION_LOCKED
	if _action_slot.state != ActionSlot.State.FREE:
		if _action_queue.size() >= MAX_QUEUE_SIZE:
			action_failed.emit(ManualActionType.CONSTRUCT_PATH, _start_result_to_reason(StartResult.BLOCKED_SLOT))
			return StartResult.BLOCKED_SLOT
		_action_queue.append({type = ManualActionType.CONSTRUCT_PATH, tile = tile})
		action_queued.emit(ManualActionType.CONSTRUCT_PATH, _action_queue.size(), tile)
		return StartResult.QUEUED

	if not PathSystem.is_constructing(tile):
		action_failed.emit(ManualActionType.CONSTRUCT_PATH, "No path construction site here")
		return StartResult.BLOCKED_SLOT

	if _energy_pool.current < PathSystem.PATH_ENERGY_COST:
		action_failed.emit(ManualActionType.CONSTRUCT_PATH, "Not enough energy")
		return StartResult.INSUFFICIENT_ENERGY

	_energy_pool.try_spend(PathSystem.PATH_ENERGY_COST)
	_action_slot.action_type = ManualActionType.CONSTRUCT_PATH
	_action_slot.config = null
	_action_slot.accumulated_ticks = 0
	_action_slot.state = ActionSlot.State.WORKING
	_action_slot.total_ticks = PathSystem.PATH_CONSTRUCTION_TICKS
	_action_slot.effective_output = 0
	_active_tile = tile

	action_started.emit(ManualActionType.CONSTRUCT_PATH, _action_slot.total_ticks, tile)
	return StartResult.SUCCESS


## Attempts to start installing an upgrade on building_id. Deducts resources and energy
## immediately; upgrade is finalized when ticks complete. Returns StartResult value.
func try_start_upgrade(building_id: String, upgrade_id: StringName) -> int:
	if _action_slot.state != ActionSlot.State.FREE:
		if _action_queue.size() >= MAX_QUEUE_SIZE:
			action_failed.emit(ManualActionType.INSTALL_UPGRADE, _start_result_to_reason(StartResult.BLOCKED_SLOT))
			return StartResult.BLOCKED_SLOT
		_action_queue.append({type = ManualActionType.INSTALL_UPGRADE,
			tile = Vector2i(-1, -1), building_id = building_id, upgrade_id = upgrade_id})
		action_queued.emit(ManualActionType.INSTALL_UPGRADE, _action_queue.size(), Vector2i(-1, -1))
		return StartResult.QUEUED

	var upgrades: Array = BuildingRegistry.get_available_upgrades(building_id)
	var upgrade_def: Dictionary = {}
	for d: Dictionary in upgrades:
		if d.get(&"id", &"") == upgrade_id:
			upgrade_def = d
			break
	if upgrade_def.is_empty():
		action_failed.emit(ManualActionType.INSTALL_UPGRADE, "Upgrade not found")
		return StartResult.BLOCKED_SLOT
	if BuildingRegistry.has_upgrade(building_id, upgrade_id):
		action_failed.emit(ManualActionType.INSTALL_UPGRADE, "Upgrade already installed")
		return StartResult.BLOCKED_SLOT

	var cost: Dictionary = upgrade_def.get(&"cost", {})
	var tick_cost: int = upgrade_def.get(&"tick_cost", 100)

	# Check and deduct resources from any container.
	for res_id: StringName in cost:
		var needed: int = cost[res_id]
		var total: int = 0
		for container: InventoryContainer in InventorySystem.get_all_containers():
			total += InventorySystem.get_resource_quantity(container.container_id, res_id)
		if total < needed:
			action_failed.emit(ManualActionType.INSTALL_UPGRADE, "Insufficient resources")
			return StartResult.INSUFFICIENT_ENERGY  # reuse closest code; extend StartResult if needed

	for res_id: StringName in cost:
		var remaining: int = cost[res_id]
		for container: InventoryContainer in InventorySystem.get_all_containers():
			if remaining <= 0:
				break
			var have: int = InventorySystem.get_resource_quantity(container.container_id, res_id)
			if have <= 0:
				continue
			var to_take: int = mini(have, remaining)
			InventorySystem.try_consume(container.container_id, res_id, to_take)
			remaining -= to_take

	_action_slot.action_type = ManualActionType.INSTALL_UPGRADE
	_action_slot.config = null
	_action_slot.accumulated_ticks = 0
	_action_slot.state = ActionSlot.State.WORKING
	_action_slot.total_ticks = tick_cost
	_action_slot.effective_output = 0
	_active_building_id = building_id
	_active_upgrade_id = upgrade_id

	action_started.emit(ManualActionType.INSTALL_UPGRADE, tick_cost, Vector2i(-1, -1))
	return StartResult.SUCCESS


## Returns a cost preview dictionary for hovering over a harvestable tile.
## Keys: blocked (bool), reason (String), energy_cost (int), tick_cost (int),
##       output_qty (int), output_resource (StringName), depleted (bool).
## For CONSTRUCT_BUILDING, pass the tile so costs can be looked up from BuildingRegistry.
func get_cost_preview(action_type: int, tile: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if action_type == ManualActionType.CONSTRUCT_BUILDING:
		if tile == Vector2i(-1, -1):
			return {blocked = true, reason = "No tile selected"}
		var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_instance_at_tile(tile)
		if instance == null:
			return {blocked = true, reason = "No building here"}
		if instance.state != BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
			return {blocked = true, reason = "Already built"}
		var tick_cost: int = BuildingRegistry.BUILD_TIME.get(instance.type, 100)
		var energy_cost: int = BuildingRegistry.BUILD_ENERGY.get(instance.type, 20)
		var has_energy := _energy_pool.current >= energy_cost
		return {
			blocked = not has_energy,
			reason = "Not enough energy" if not has_energy else "",
			energy_cost = energy_cost,
			tick_cost = tick_cost,
			output_qty = 0,
			output_resource = &"",
			depleted = _energy_pool.current == 0,
			building_type = instance.type,
		}
	if action_type == ManualActionType.CONSTRUCT_PATH:
		if tile == Vector2i(-1, -1):
			return {blocked = true, reason = "No tile selected"}
		if not PathSystem.is_constructing(tile):
			return {blocked = true, reason = "No path construction site here"}
		var has_energy := _energy_pool.current >= PathSystem.PATH_ENERGY_COST
		return {
			blocked = not has_energy,
			reason = "Not enough energy" if not has_energy else "",
			energy_cost = PathSystem.PATH_ENERGY_COST,
			tick_cost = PathSystem.PATH_CONSTRUCTION_TICKS,
			output_qty = 0,
			output_resource = &"",
			depleted = _energy_pool.current == 0,
		}
	## --- all non-CONSTRUCT actions below ---
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

	var is_depleted := _energy_pool.current == 0
	var has_energy := _energy_pool.current >= config.energy_cost
	var is_food_action := is_food(config.output_resource)
	var is_blocked := not has_energy and not is_food_action
	var tick_cost: int = config.tick_cost * 2 if not has_energy else config.tick_cost
	var output_qty: int = maxi(1, ceili(config.base_output * 0.5)) if not has_energy else config.base_output

	return {
		blocked = is_blocked,
		reason = "Not enough energy" if is_blocked else "",
		energy_cost = config.energy_cost if has_energy else 0,
		tick_cost = tick_cost,
		output_qty = output_qty,
		output_resource = config.output_resource,
		depleted = is_depleted,
	}


## Restore energy by consuming a food item. Returns false if the resource is not
## edible (no positive nutrition) or if energy is already full (eating would waste
## the food). Can be called while a manual action is running.
## Emits food_consumed on success.
func consume_food(food_type: StringName) -> bool:
	var energy_amount: int = food_energy_value(food_type)
	if energy_amount == 0:
		return false
	if _energy_pool.current >= _energy_pool.max_energy:
		return false
	_energy_pool.restore(energy_amount)
	food_consumed.emit(food_type, energy_amount)
	return true


## Returns the energy a single unit of food_type restores, derived from its
## ResourceRegistry nutrition value × ENERGY_PER_NUTRITION. 0 for non-food.
static func food_energy_value(food_type: StringName) -> int:
	var def: Object = ResourceRegistry.get_definition(food_type)
	if def == null or def.nutrition <= 0.0:
		return 0
	return int(round(def.nutrition * ENERGY_PER_NUTRITION))


## True when resource_id is edible food (has positive nutrition).
static func is_food(resource_id: StringName) -> bool:
	var def: Object = ResourceRegistry.get_definition(resource_id)
	return def != null and def.nutrition > 0.0

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
	_relocation_drag.cached_cost = base_cost
	return {energy_cost = 0, tick_cost = base_cost * 5, energy_insufficient = false}


## Called on LMB release. Optionally calls WorldGrid.move_one_resource().
## Returns RelocationResult enum value.
## When deferred=true, skips the WorldGrid mutation and relocation_completed signal —
## the caller is responsible for executing the move after the pending transport completes.
func try_commit_relocation(target_tile: Vector2i, grid: Node, deferred: bool = false) -> int:
	if _relocation_drag.state != RelocationDrag.DragState.DRAGGING:
		return RelocationResult.NOT_DRAGGING

	var source: Vector2i = _relocation_drag.source_tile
	var src_idx: int = _relocation_drag.source_idx
	var res_id: StringName = _relocation_drag.resource_id

	var dist: int = abs(target_tile.x - source.x) + abs(target_tile.y - source.y)

	# Same-tile drop: no WorldGrid mutation.
	if dist == 0:
		_relocation_drag.state = RelocationDrag.DragState.IDLE
		relocation_completed.emit(source, target_tile, res_id)
		return RelocationResult.SNAP_BACK_SAME_TILE

	# Validate target via WorldGrid.
	if grid == null or not grid.is_in_bounds(target_tile):
		_relocation_drag.state = RelocationDrag.DragState.IDLE
		relocation_cancelled.emit(source)
		return RelocationResult.SNAP_BACK_INVALID

	if not grid.is_passable(target_tile):  # IMPASSABLE or WATER — cannot drop resources here
		_relocation_drag.state = RelocationDrag.DragState.IDLE
		relocation_cancelled.emit(source)
		return RelocationResult.SNAP_BACK_INVALID

	_relocation_drag.state = RelocationDrag.DragState.IDLE
	if not deferred:
		grid.move_one_resource(source, src_idx, target_tile)
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


## Cancels the active action and any queued actions targeting `tile`.
## Called when a building at `tile` is demolished while an action is running or queued.
func cancel_actions_at_tile(tile: Vector2i) -> void:
	var had_queued: bool = false
	for i in range(_action_queue.size() - 1, -1, -1):
		if _action_queue[i].get("tile") == tile:
			_action_queue.remove_at(i)
			had_queued = true
	if had_queued:
		action_queue_cleared.emit()
	if _action_slot.state != ActionSlot.State.FREE and _active_tile == tile:
		_action_slot.cancel()
		_active_building_id = ""
		action_interrupted.emit(tile)


# ---- Tick handler -----------------------------------------------------------

func _on_day_transition(_day: int) -> void:
	pass  # PC state is unaffected by day boundaries (AC9 — running actions continue uninterrupted)


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
	var building_id: String = _active_building_id
	var upgrade_id: StringName = _active_upgrade_id
	_active_building_id = ""
	_active_upgrade_id = &""
	var completed_path_tile: Vector2i = _active_tile
	_action_slot.free_slot()
	if completed_type == ManualActionType.CONSTRUCT_BUILDING and building_id != "":
		BuildingRegistry.complete_construction_manually(building_id)
	if completed_type == ManualActionType.CONSTRUCT_PATH:
		PathSystem.complete_construction(completed_path_tile)
	if completed_type == ManualActionType.INSTALL_UPGRADE and building_id != "" and upgrade_id != &"":
		BuildingRegistry.install_upgrade(building_id, upgrade_id)
	if completed_type == ManualActionType.PLANT_SEED:
		seed_planted.emit(_active_seed_type, completed_path_tile)
		_active_seed_type = &""
	if completed_type != -1:
		action_completed.emit(completed_type, output)
	if not _action_queue.is_empty():
		var next: Dictionary = _action_queue.pop_front()
		var result: int
		if next.get("type", -1) == ManualActionType.INSTALL_UPGRADE:
			result = try_start_upgrade(next.get("building_id", ""), next.get("upgrade_id", &""))
		elif next.get("type", -1) == ManualActionType.PLANT_SEED:
			result = try_start_plant_seed(next.tile, next.get("seed_type", &""))
		else:
			result = try_start_action(next.type, next.tile)
		if result == StartResult.INSUFFICIENT_ENERGY:
			_action_queue.clear()
			action_queue_cleared.emit()


## Plants seed_type on tile. Consumes one seed from storage and starts a PLANT_SEED action.
## Returns a StartResult value. Caller must ensure tile is EMPTY before calling.
func try_start_plant_seed(tile: Vector2i, seed_type: StringName) -> int:
	var config: ManualActionConfig = _action_configs.get(ManualActionType.PLANT_SEED, null)
	if config == null:
		return StartResult.BLOCKED_SLOT
	# Fertility gate: wheat seeds only grow on a wheat-fertile map (spec).
	if seed_type == &"wheat_seed" and _grid != null and not _grid.has_fertility(&"wheat"):
		action_failed.emit(ManualActionType.PLANT_SEED, "Wheat cannot grow on this land")
		return StartResult.BLOCKED_SLOT
	if _action_slot.state != ActionSlot.State.FREE:
		if _action_queue.size() >= MAX_QUEUE_SIZE:
			action_failed.emit(ManualActionType.PLANT_SEED, _start_result_to_reason(StartResult.BLOCKED_SLOT))
			return StartResult.BLOCKED_SLOT
		_action_queue.append({type = ManualActionType.PLANT_SEED, tile = tile, seed_type = seed_type})
		action_queued.emit(ManualActionType.PLANT_SEED, _action_queue.size(), tile)
		return StartResult.QUEUED
	if _energy_pool.current < config.energy_cost:
		action_failed.emit(ManualActionType.PLANT_SEED, _start_result_to_reason(StartResult.INSUFFICIENT_ENERGY))
		return StartResult.INSUFFICIENT_ENERGY
	if not _has_seed_in_storage(seed_type):
		action_failed.emit(ManualActionType.PLANT_SEED, "No %s available" % str(seed_type))
		return StartResult.BLOCKED_SLOT
	_consume_seed_from_storage(seed_type)
	_energy_pool.try_spend(config.energy_cost)
	_active_tile = tile
	_active_seed_type = seed_type
	_action_slot.state = ActionSlot.State.WORKING
	_action_slot.config = config
	_action_slot.action_type = ManualActionType.PLANT_SEED
	_action_slot.accumulated_ticks = 0
	_action_slot.total_ticks = config.tick_cost
	_action_slot.effective_output = 0
	action_started.emit(ManualActionType.PLANT_SEED, config.tick_cost, tile)
	return StartResult.SUCCESS


## Searches a tile for any hidden ore/gem deposit (clay, iron, …). Spends SURVEY_ENERGY.
## Returns a result dict:
##   blocked (bool), reason (String),
##   deposit_revealed (bool), deposit_distance (int: 0 on-tile, >0 nearest, -1 none),
##   deposit_id (StringName: revealed/nearest resource, &"" when none in range).
func survey_tile(tile: Vector2i) -> Dictionary:
	var result: Dictionary = {
		blocked = false, reason = "",
		deposit_revealed = false, deposit_distance = -1, deposit_id = &"",
	}
	if _grid == null:
		result.blocked = true
		result.reason = "No map"
		return result
	if _energy_pool.current < SURVEY_ENERGY:
		result.blocked = true
		result.reason = "Not enough energy"
		return result
	_energy_pool.try_spend(SURVEY_ENERGY)
	var on_tile: StringName = _grid.reveal_hidden_deposit(tile)
	if on_tile != &"":
		result.deposit_revealed = true
		result.deposit_distance = 0
		result.deposit_id = on_tile
		return result
	# A deposit sits here but couldn't be exposed yet (tile must be cleared first).
	var on_this_tile: Dictionary = _grid.find_nearest_any_hidden(tile, 0)
	if not on_this_tile.is_empty():
		result.deposit_distance = 0
		result.deposit_id = on_this_tile.get("id", &"")
		result.reason = "Clear this tile first to expose the deposit"
		return result
	var nearest: Dictionary = _grid.find_nearest_any_hidden(tile, WorldGrid.DEPOSIT_SEARCH_MAX_RADIUS)
	if not nearest.is_empty():
		result.deposit_distance = _grid.manhattan_dist(tile, nearest["tile"])
		result.deposit_id = nearest["id"]
	return result


func _has_seed_in_storage(seed_type: StringName) -> bool:
	return InventorySystem.get_global_quantity(seed_type) > 0


func _consume_seed_from_storage(seed_type: StringName) -> void:
	var container_id: StringName = InventorySystem.find_container_with(seed_type)
	if container_id != &"":
		InventorySystem.try_consume(container_id, seed_type, 1)


func _build_output(slot: ActionSlot) -> Array:
	if slot.action_type == ManualActionType.CONSTRUCT_BUILDING:
		return []
	if slot.action_type == ManualActionType.CONSTRUCT_PATH:
		return []
	if slot.action_type == ManualActionType.PLANT_SEED:
		return []  # terrain effect handled via seed_planted signal
	var qty: int = slot.effective_output
	if slot.config == null:
		return []
	if slot.action_type == ManualActionType.FORAGE:
		return [{resource_id = _roll_forage_loot(), quantity = qty}]
	var items: Array = [{resource_id = slot.config.output_resource, quantity = qty}]
	var seed: StringName = _roll_seed_byproduct(slot.action_type)
	if seed != &"":
		items.append({resource_id = seed, quantity = 1})
	return items


func _roll_seed_byproduct(action_type: int) -> StringName:
	if not SEED_BYPRODUCT_CHANCES.has(action_type):
		return &""
	var entry: Array = SEED_BYPRODUCT_CHANCES[action_type]
	if _rng.randi_range(1, 100) <= entry[0]:
		return entry[1]
	return &""


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
		StartResult.BLOCKED_SLOT:         return "Action queue is full"
		StartResult.QUEUED:               return ""
		StartResult.INSUFFICIENT_ENERGY:  return "Not enough energy"
		StartResult.ARCHITECT_LOCKED:     return "Architect mode — manual gathering locked"
		StartResult.TOOL_REQUIRED:        return "No tool available — craft one first"
		StartResult.PROGRESSION_LOCKED:   return "Locked — unlock in the tech tree"
	return "Unknown"


## Returns the display label for a manual action type (used by UI panels).
func get_action_label(action_type: int) -> String:
	match action_type:
		ManualActionType.CONSTRUCT_BUILDING: return "Construct"
		ManualActionType.CONSTRUCT_PATH:     return "Build Path"
		ManualActionType.CHOP_TREE:          return "Chop"
		ManualActionType.MINE_STONE:         return "Mine"
		ManualActionType.PICK_BERRIES:       return "Harvest"
		ManualActionType.HARVEST_FIBER:      return "Harvest"
		ManualActionType.FORAGE:             return "Forage"
		ManualActionType.CLEAR_TREE:         return "Clear"
		ManualActionType.CLEAR_STONE:        return "Clear"
		ManualActionType.CLEAR_BERRY:        return "Clear"
		ManualActionType.CLEAR_GRASS:        return "Clear"
		ManualActionType.INSTALL_UPGRADE:    return "Install"
		ManualActionType.PLANT_SEED:         return "Plant"
		ManualActionType.HARVEST_WHEAT:      return "Harvest"
		ManualActionType.CLEAR_WHEAT:        return "Clear"
		ManualActionType.MINE_CLAY:          return "Mine"
		ManualActionType.MINE_IRON:          return "Mine"
		ManualActionType.MINE_COPPER:        return "Mine"
		ManualActionType.MINE_TIN:           return "Mine"
		ManualActionType.MINE_SILVER:        return "Mine"
		ManualActionType.MINE_GOLD:          return "Mine"
		ManualActionType.MINE_GEMSTONE:      return "Mine"
		ManualActionType.HARVEST_FLAX:       return "Harvest"
		ManualActionType.HARVEST_HOPS:       return "Harvest"
		ManualActionType.HARVEST_GRAPES:     return "Harvest"
		ManualActionType.HARVEST_OLIVES:     return "Harvest"
		ManualActionType.HARVEST_HONEY:      return "Harvest"
		ManualActionType.GATHER_SAND:        return "Gather"
		ManualActionType.MINE_MARBLE:        return "Mine"
		ManualActionType.MINE_AMBER:         return "Mine"
	return "Action"


## Returns the primary output resource id of a manual action, or &"" if it has none
## (forage rolls a random resource; construct/plant produce nothing direct). Used by the
## Progression Tree to map gather unlocks back to the resources they make available.
func get_action_output_resource(action_type: int) -> StringName:
	var config: ManualActionConfig = _action_configs.get(action_type, null)
	if config == null:
		return &""
	return config.output_resource
