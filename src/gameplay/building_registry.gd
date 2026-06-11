extends Node
## BuildingRegistry — Autoload singleton for building placement, construction progress,
## production cycle advancement, and building instance tracking.
## ADR: Buildings Story 001 (placement), Story 002 (production cycles).
##
## WorldGrid and PlayerCharacter are NOT Autoloads — they are injected via
## init_dependencies() after the scene tree is ready (called by MapRoot).

# ---- Enums ------------------------------------------------------------------

enum BuildingType {
	COLLECTION_POINT,    ## 0 cost, instant, 50 slots — starter gathering depot
	STORAGE_BUILDING,    ## 8 Wood + 2 Stone, 120 ticks, 150 slots
	RESIDENTIAL_HOUSE,   ## 10 Wood + 3 Stone, 150 ticks
	LUMBER_CAMP,         ## 15 Wood + 3 Stone, 200 ticks
	ROAD,                ## 0 cost, instant, passable infrastructure — movement cost 0.5
	GATHERING_HUT,       ## 5 Wood + 2 Stone, 80 ticks — harvests Berry/Fiber from adjacent terrain
	STONE_MASON,         ## 10 Wood + 5 Stone, 200 ticks — produces Stone from adjacent STONE terrain
	TOOL_WORKSHOP,       ## 10 Wood + 5 Stone, 250 ticks — crafts Tools from Wood + Stone + Fiber
}

## Building operational status codes — exposed for cross-system API use (e.g. LogisticsSystem).
## Values mirror BuildingInstance.State — both must stay in sync.
enum Status {
	CONSTRUCTING = 0,
	OPERATING    = 1,
	BLOCKED      = 2,
	DEMOLISHED   = 3,
}

## Mirrors WorldGrid.PlacementResult with additional codes for resource/energy/adjacency checks.
enum PlacementResult {
	SUCCESS,
	BLOCKED_BY_BOUNDS,
	BLOCKED_BY_IMPASSABLE,
	BLOCKED_BY_BUILDING,
	BLOCKED_BY_RESOURCE_TILE,
	INSUFFICIENT_RESOURCES,
	INSUFFICIENT_ENERGY,
	BLOCKED_BY_ADJACENCY,   ## building requires a specific terrain type in an adjacent tile
}

## Return codes for _try_start_production_cycle. Private — not part of public API.
enum _CycleStartResult {
	SUCCESS,
	BLOCKED_NO_NPC,
	BLOCKED_NO_INPUT,
	BLOCKED_NO_CARRIER,
	OUTPUT_FULL,
}

# ---- Inner classes ----------------------------------------------------------

class BuildingInstance:
	enum State { CONSTRUCTING, OPERATING, BLOCKED, DEMOLISHED }

	var building_id: String
	var type: int           ## BuildingType
	var tile: Vector2i
	var state: int          ## State
	var accumulated_ticks: int
	var build_time: int
	var assigned_container_id: StringName  ## set for storage buildings on placement
	var visual_node: Node2D                ## set by registry when visual is instantiated
	## Manually-loaded input items waiting to be consumed by this production building.
	var input_buffer: Dictionary[StringName, float] = {}

	## Production cycle fields (story-002) ----------------------------------

	## Ticks elapsed in the current production cycle.
	var production_cycle_ticks: int = 0
	## Total ticks required for one production cycle (Formula 5: always base_cycle_ticks).
	var production_cycle_duration: int = 0
	## True while a production cycle is running.
	var cycle_running: bool = false
	## Holds completed output waiting for carrier pickup.
	var buffered_output: Dictionary[StringName, int] = {}
	## ID of the NPC assigned to this building (empty = no NPC).
	var assigned_npc_id: StringName = &""
	## Player-assigned custom name. Empty string means use the type name as display name.
	var custom_name: String = ""
	## Count of NPCs spawned by a Residential House.
	var npc_count: int = 0
	## Ticks accumulated toward next NPC spawn (Residential House only).
	var npc_spawn_timer: int = 0
	## Set to true when input is added; prevents production from starting on the same tick.
	var input_pending: bool = false
	## Carrier NPCs assigned to deliver inputs — one per active input route.
	var input_carrier_ids: Array[StringName] = []
	## Carrier NPC assigned to collect output (stub — carrier system in future story).
	var output_carrier_id: StringName = &""
	## Efficiency fields (ADR-0012). upgrade_bonus is 0.0 at VS scope.
	var upgrade_bonus: float = 0.0
	var efficiency: float = 1.0
	## Count of adjacent terrain tiles satisfying ADJACENCY_REQUIREMENTS for this type.
	## Managed by BuildingRegistry. Only relevant for types in ADJACENCY_REQUIREMENTS.
	var adjacency_tile_count: int = 0
	## Computed output for GATHERING_HUT based on adjacent terrain types.
	## Keys are resource IDs; values are quantities per cycle.
	var gathering_output: Dictionary[StringName, int] = {}

	## Recomputes efficiency.
	## Buildings with adjacency requirements use F6 (tile_count × 0.25), base 0.0.
	## All other buildings use F2 (1.0 + worker delta + upgrade_bonus).
	func recalculate_efficiency(assigned_workers: Array) -> void:
		if ADJACENCY_REQUIREMENTS.has(type):
			efficiency = EfficiencyFormulas.calculate_adjacency_efficiency(adjacency_tile_count)
			return
		var worker_efficiencies: Array[float] = []
		for worker in assigned_workers:
			worker_efficiencies.append(worker.efficiency)
		efficiency = EfficiencyFormulas.calculate_building_efficiency(
				worker_efficiencies, upgrade_bonus)

	func _init(p_id: String, p_type: int, p_tile: Vector2i) -> void:
		building_id = p_id
		type = p_type
		tile = p_tile
		state = State.CONSTRUCTING
		accumulated_ticks = 0
		build_time = 0
		assigned_container_id = &""
		visual_node = null

# ---- Build tables -----------------------------------------------------------

const BUILD_COST: Dictionary = {
	BuildingType.COLLECTION_POINT:  {},
	BuildingType.STORAGE_BUILDING:  {&"wood": 8, &"stone": 2},
	BuildingType.RESIDENTIAL_HOUSE: {&"wood": 10, &"stone": 3},
	BuildingType.LUMBER_CAMP:       {&"wood": 15, &"stone": 3},
	BuildingType.ROAD:              {},
	BuildingType.GATHERING_HUT:     {&"wood": 5, &"stone": 2},
	BuildingType.STONE_MASON:       {&"wood": 10, &"stone": 5},
	BuildingType.TOOL_WORKSHOP:     {&"wood": 10, &"stone": 5},
}

const BUILD_TIME: Dictionary = {
	BuildingType.COLLECTION_POINT:  0,
	BuildingType.STORAGE_BUILDING:  120,
	BuildingType.RESIDENTIAL_HOUSE: 150,
	BuildingType.LUMBER_CAMP:       200,
	BuildingType.ROAD:              0,
	BuildingType.GATHERING_HUT:     80,
	BuildingType.STONE_MASON:       200,
	BuildingType.TOOL_WORKSHOP:     250,
}

## Movement cost for buildings that NPCs and carriers can traverse.
## Types absent from this table are impassable (cost = INF).
const MOVEMENT_EFFICIENCY: Dictionary = {
	BuildingType.ROAD: 0.5,
}

const STORAGE_CAPACITY: Dictionary = {
	BuildingType.COLLECTION_POINT: 50,
	BuildingType.STORAGE_BUILDING: 150,
}

## Maps BuildingType → texture resource path. Used by placement ghost and building visuals.
const BUILDING_TEXTURES: Dictionary = {
	BuildingType.COLLECTION_POINT:  "res://assets/art/tiles/bld_tile_collection_point.png",
	BuildingType.STORAGE_BUILDING:  "res://assets/art/tiles/bld_tile_storage.png",
	BuildingType.RESIDENTIAL_HOUSE: "res://assets/art/tiles/bld_tile_house.png",
	BuildingType.LUMBER_CAMP:       "res://assets/art/tiles/bld_tile_lumber_camp.png",
	BuildingType.ROAD:              "res://assets/art/tiles/env_tile_path_nesw.png",
	BuildingType.GATHERING_HUT:     "res://assets/art/tiles/bld_tile_gathering_hut.png",
	BuildingType.STONE_MASON:       "res://assets/art/tiles/bld_tile_steinmetz.png",
	BuildingType.TOOL_WORKSHOP:     "res://assets/art/tiles/bld_tile_tool_workshop.png",
}

## Resource IDs accepted as manual input for each production building type.
const INPUT_RESOURCES: Dictionary = {
	BuildingType.LUMBER_CAMP:    [&"tool"],
	BuildingType.STONE_MASON:    [&"tool"],
	BuildingType.TOOL_WORKSHOP:  [&"wood", &"stone", &"fiber"],
}

## Terrain types required in at least one cardinal neighbor for a building to be placeable.
## Maps BuildingType → Array of WorldGrid.TileType values.
const ADJACENCY_REQUIREMENTS: Dictionary = {
	BuildingType.LUMBER_CAMP:    [WorldGrid.TileType.TREE],
	BuildingType.GATHERING_HUT:  [WorldGrid.TileType.BERRY, WorldGrid.TileType.GRASS],
	BuildingType.STONE_MASON:    [WorldGrid.TileType.STONE],
}

## Maps WorldGrid.TileType → resource output produced per cycle by GATHERING_HUT.
const TERRAIN_HARVEST_OUTPUT: Dictionary = {
	WorldGrid.TileType.BERRY: {&"berry": 3},
	WorldGrid.TileType.GRASS: {&"fiber": 2},
}

## Formula 7 scalar: energy cost per resource unit in build cost.
const ENERGY_PER_RESOURCE: float = 0.10

## Formula 3 scalar: ticks per map tile for carrier travel time calculation.
const TICKS_PER_TILE: float = 3.0

## NPC spawn interval for Residential House (Formula 8), in ticks.
const NPC_SPAWN_INTERVAL: int = 1000

## Maximum NPCs a Residential House can house.
const MAX_HOUSE_NPCS: int = 2

## Production table for production buildings (story-002).
## Each entry defines input costs, base output, and cycle duration.
## Inputs use float for tool charge_cost; wood uses quantity (int stored as float for uniformity).
## Format: { inputs: [{resource_id, quantity | charge_cost}], output: {resource_id: qty}, base_cycle_ticks: int, npc_required: bool }
const PRODUCTION_TABLE: Dictionary = {
	BuildingType.LUMBER_CAMP: {
		"inputs": [
			{"resource_id": &"tool", "charge_cost": 1.0},
		],
		"output": {&"wood": 5},
		"output_capacity": 20,
		"input_capacity": 5,
		"base_cycle_ticks": 100,
		"npc_required": true,
	},
	BuildingType.STONE_MASON: {
		"inputs": [
			{"resource_id": &"tool", "charge_cost": 1.0},
		],
		"output": {&"stone": 5},
		"output_capacity": 20,
		"input_capacity": 5,
		"base_cycle_ticks": 100,
		"npc_required": true,
	},
	BuildingType.GATHERING_HUT: {
		"inputs": [],
		"output": {},  ## actual output computed dynamically via gathering_output
		"output_capacity": 20,
		"input_capacity": 0,
		"base_cycle_ticks": 100,
		"npc_required": true,
	},
	BuildingType.TOOL_WORKSHOP: {
		"inputs": [
			{"resource_id": &"wood",  "quantity": 2},
			{"resource_id": &"stone", "quantity": 1},
			{"resource_id": &"fiber", "quantity": 1},
		],
		"output": {&"tool": 1},
		"output_capacity": 10,
		"input_capacity": 10,
		"base_cycle_ticks": 150,
		"npc_required": true,
	},
}

# ---- Signals ----------------------------------------------------------------

signal building_placed(building_id: String, type: int, tile: Vector2i)
signal building_construction_complete(building_id: String, type: int)
signal building_state_changed(building_id: String, new_state: int, reason: String)
signal building_input_changed(building_id: String)
## Emitted when a production cycle completes and output is placed in buffered_output.
signal production_output_ready(building_id: String, output: Dictionary[StringName, int])
## Emitted when buffered_output changes (items removed by drag or snap-back).
signal building_output_changed(building_id: String)
## Emitted to request an NPC spawn at the given tile (handled by NPC system stub).
signal building_npc_spawn_requested(building_id: String, tile: Vector2i, count: int)
## Emitted when a production building enters BLOCKED state.
## reason: "No NPC assigned" | "No carrier assigned (inputs)" | "Missing required input"
signal building_blocked(building_id: String, reason: String)
## Emitted when a BLOCKED building successfully resumes production on the next tick.
signal building_unblocked(building_id: String)
## Emitted by demolish_building() (story-005) when a building is permanently removed.
signal building_demolished(building_id: StringName)
## Emitted before buffers are cleared during demolition — carries all items that should
## be dropped onto the tile so the scene layer can spawn world pickups.
signal building_items_dropped(tile: Vector2i, items: Dictionary)
## Emitted when the player renames a building.
signal building_renamed(building_id: String, new_name: String)

# ---- State ------------------------------------------------------------------

var _tick_system: Node = null
var _inventory_system: Node = null
var _grid: Node = null            ## WorldGrid — injected by MapRoot
var _player_character: Node = null  ## PlayerCharacter — injected by MapRoot
var _npc_system: Object = null   ## lazily acquired; injectable for tests (ADR-0012)
var _all_buildings: Array[BuildingInstance] = []
var _build_counter: int = 0

# ---- Lifecycle --------------------------------------------------------------

func _enter_tree() -> void:
	_tick_system = TickSystem
	_inventory_system = InventorySystem
	if _tick_system != null:
		_tick_system.ticks_advanced.connect(_on_ticks_advanced)
	if _inventory_system != null:
		_inventory_system.container_removed.connect(_on_container_removed)


## Called by MapRoot after scene is ready to wire scene-tree dependencies.
func init_dependencies(grid: Node, player_character: Node) -> void:
	_grid = grid
	_player_character = player_character
	if _grid != null and _grid.has_signal("terrain_tile_changed"):
		_grid.terrain_tile_changed.connect(_on_terrain_tile_changed)

# ---- Placement API ----------------------------------------------------------

## Places a building at the given tile. Returns PlacementResult.
## On SUCCESS: resources deducted, building created, visual spawned, signal emitted.
func initiate_build(building_type: int, tile: Vector2i) -> int:
	if _grid == null:
		push_warning("BuildingRegistry: GridMap dependency not set — call init_dependencies() first")
		return PlacementResult.BLOCKED_BY_BOUNDS
	var grid_result: int = _grid.validate_placement(tile, building_type)
	if grid_result != 0:  # WorldGrid.PlacementResult.SUCCESS == 0
		return grid_result
	var adj_result: int = _check_adjacency(building_type, tile)
	if adj_result != PlacementResult.SUCCESS:
		return adj_result
	var afford_result: int = _check_resource_and_energy(building_type)
	if afford_result != PlacementResult.SUCCESS:
		return afford_result
	var building_id: String = str(_build_counter)
	_build_counter += 1
	var place_result: int = _grid.place_building(tile, building_id)
	if place_result != 0:
		_build_counter -= 1
		return place_result
	_deduct_build_cost(building_type)
	var instance: BuildingInstance = _create_instance(building_id, building_type, tile)
	_spawn_visual(instance)
	_insert_sorted(instance)
	building_placed.emit(building_id, building_type, tile)
	return PlacementResult.SUCCESS


## Places a starter building bypassing resource and energy checks.
## Clears any resource terrain on the tile before placing so map generation
## cannot accidentally block the fixed starter position.
## Use only during map initialisation (MapRoot._ready).
func place_starter_building(building_type: int, tile: Vector2i) -> int:
	if _grid == null:
		push_warning("BuildingRegistry: GridMap dependency not set")
		return PlacementResult.BLOCKED_BY_BOUNDS
	var building_id: String = str(_build_counter)
	var terrain: WorldGrid.TileType = _grid.get_terrain(tile)
	if terrain != WorldGrid.TileType.EMPTY and terrain != WorldGrid.TileType.IMPASSABLE:
		_grid.clear_terrain_tile(tile)
	var place_result: int = _grid.place_building(tile, building_id)
	if place_result != 0:
		return place_result
	_build_counter += 1
	var instance := BuildingInstance.new(building_id, building_type, tile)
	instance.build_time = BUILD_TIME.get(building_type, 0)
	instance.state = BuildingInstance.State.OPERATING
	_update_adjacency_efficiency(instance)
	if building_type == BuildingType.COLLECTION_POINT or building_type == BuildingType.STORAGE_BUILDING:
		_setup_storage_for(instance)
	_insert_sorted(instance)
	building_placed.emit(building_id, building_type, tile)
	return PlacementResult.SUCCESS

# ---- Query API --------------------------------------------------------------

## Returns the BuildingInstance for building_id, or null.
func get_building_instance(building_id: String) -> BuildingInstance:
	for instance: BuildingInstance in _all_buildings:
		if instance.building_id == building_id:
			return instance
	return null


## Returns the tile coordinates of the given building, or Vector2i(-1, -1) if not found.
func get_building_tile(building_id: String) -> Vector2i:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return Vector2i(-1, -1)
	return instance.tile


## Returns all BuildingInstances (shallow copy).
func get_all_buildings() -> Array[BuildingInstance]:
	return _all_buildings.duplicate()


## Returns building count.
func get_building_count() -> int:
	return _all_buildings.size()


## Returns the movement cost for a tile occupied by this building (used by WorldGrid A* layer).
## Returns INF for all building types not listed in MOVEMENT_EFFICIENCY (i.e. impassable).
func get_movement_cost(building_id: String) -> float:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return INF
	return float(MOVEMENT_EFFICIENCY.get(instance.type, INF))


## Transfers qty units of resource_id from any storage container into the
## building's input_buffer. Returns false if the building doesn't exist, the
## resource is not an accepted input for that building type, or there is not
## enough stock available.
func add_to_input(building_id: String, resource_id: StringName, qty: int) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	var allowed: Array[StringName] = []
	allowed.assign(INPUT_RESOURCES.get(instance.type, []))
	if not resource_id in allowed:
		return false
	if _inventory_system == null:
		return false
	var source_id: StringName = _find_container_with(resource_id)
	if source_id == &"":
		return false
	var consume_result: int = _inventory_system.try_consume(source_id, resource_id, qty)
	if consume_result != 0:  # InventoryContainer.ConsumeResult.SUCCESS == 0
		return false
	instance.input_buffer[resource_id] = instance.input_buffer.get(resource_id, 0.0) + float(qty)
	instance.input_pending = true
	building_input_changed.emit(building_id)
	return true


## Adds charge units (float) of a charged tool resource to the building's input_buffer.
## Used when a carrier delivers a tool with remaining charge.
## Returns false if the building or resource is not valid for this building type.
func add_charge_to_input(building_id: String, resource_id: StringName, charge: float) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	var allowed: Array[StringName] = []
	allowed.assign(INPUT_RESOURCES.get(instance.type, []))
	if not resource_id in allowed:
		return false
	instance.input_buffer[resource_id] = instance.input_buffer.get(resource_id, 0.0) + charge
	building_input_changed.emit(building_id)
	return true


## Removes qty units of resource_id from buffered_output. Returns false if not enough buffered.
## If the building is STALLED and the buffer now has room, transitions back to OPERATING.
func remove_from_output(building_id: String, resource_id: StringName, qty: int) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	var current: int = instance.buffered_output.get(resource_id, 0)
	if current < qty:
		return false
	var remaining: int = current - qty
	if remaining <= 0:
		instance.buffered_output.erase(resource_id)
	else:
		instance.buffered_output[resource_id] = remaining
	building_output_changed.emit(building_id)
	return true


## Returns qty units of resource_id back to buffered_output (snap-back on failed drag).
func receive_output_to_buffer(building_id: String, resource_id: StringName, qty: int) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return
	instance.buffered_output[resource_id] = instance.buffered_output.get(resource_id, 0) + qty
	building_output_changed.emit(building_id)


## Removes qty units of resource_id from input_buffer. Returns false if not enough buffered.
func remove_from_input(building_id: String, resource_id: StringName, qty: int) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null or instance.cycle_running:
		return false
	var current: float = instance.input_buffer.get(resource_id, 0.0)
	if current < float(qty):
		return false
	var remaining: float = current - float(qty)
	if remaining <= 0.0:
		instance.input_buffer.erase(resource_id)
	else:
		instance.input_buffer[resource_id] = remaining
	building_input_changed.emit(building_id)
	return true


## Adds qty units directly to the building's input_buffer without consuming from
## any InventoryContainer. The caller must have already removed the resource from
## its source (WorldGrid tile).
func receive_input_from_world(building_id: String, resource_id: StringName, qty: int) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	var allowed: Array[StringName] = []
	allowed.assign(INPUT_RESOURCES.get(instance.type, []))
	if not resource_id in allowed:
		return false
	instance.input_buffer[resource_id] = instance.input_buffer.get(resource_id, 0.0) + float(qty)
	instance.input_pending = true
	building_input_changed.emit(building_id)
	return true


## Returns the first container ID that holds at least one unit of resource_id.
func _find_container_with(resource_id: StringName) -> StringName:
	if _inventory_system == null:
		return &""
	for container: Object in _inventory_system.get_all_containers():
		if _inventory_system.get_resource_quantity(container.container_id, resource_id) > 0:
			return container.container_id
	return &""


## Returns the PlacementResult for a proposed tile without committing anything.
## Checks grid only — use check_build_conditions() for the full pre-flight check.
func get_placement_validity(tile: Vector2i, building_type: int) -> int:
	if _grid == null:
		return PlacementResult.BLOCKED_BY_BOUNDS
	return _grid.validate_placement(tile, building_type)


## Full pre-flight check: grid + adjacency + resource affordability + energy. No side effects.
func check_build_conditions(building_type: int, tile: Vector2i) -> int:
	if _grid == null:
		return PlacementResult.BLOCKED_BY_BOUNDS
	var grid_result: int = _grid.validate_placement(tile, building_type)
	if grid_result != 0:
		return grid_result
	var adj_result: int = _check_adjacency(building_type, tile)
	if adj_result != PlacementResult.SUCCESS:
		return adj_result
	return _check_resource_and_energy(building_type)


## Returns neighbor tiles that satisfy the adjacency requirement for building_type at tile.
## Returns an empty array if the building type has no adjacency requirements.
func get_adjacency_hint_tiles(building_type: int, tile: Vector2i) -> Array[Vector2i]:
	if _grid == null or not ADJACENCY_REQUIREMENTS.has(building_type):
		return []
	var required_types: Array = ADJACENCY_REQUIREMENTS[building_type]
	var result: Array[Vector2i] = []
	for neighbor: Vector2i in _grid.get_neighbors(tile, true):
		if _grid.get_terrain(neighbor) in required_types:
			result.append(neighbor)
	return result

# ---- Tick handler -----------------------------------------------------------

func _on_ticks_advanced(delta: int) -> void:
	for instance: BuildingInstance in _all_buildings:
		if instance.state == BuildingInstance.State.DEMOLISHED:
			continue
		if instance.state == BuildingInstance.State.CONSTRUCTING:
			_advance_construction(instance, delta)
			continue
		if instance.type == BuildingType.RESIDENTIAL_HOUSE and instance.state == BuildingInstance.State.OPERATING:
			_advance_npc_timer(instance, delta)
			continue
		if instance.state == BuildingInstance.State.OPERATING and PRODUCTION_TABLE.has(instance.type):
			_advance_production_cycle(instance, delta)
		elif instance.state == BuildingInstance.State.BLOCKED and PRODUCTION_TABLE.has(instance.type):
			_try_recover_blocked(instance)


## Advances construction timer; transitions to OPERATING at build_time threshold.
func _advance_construction(instance: BuildingInstance, delta: int) -> void:
	instance.accumulated_ticks += delta
	if instance.accumulated_ticks < instance.build_time:
		return
	instance.state = BuildingInstance.State.OPERATING
	_update_adjacency_efficiency(instance)
	building_construction_complete.emit(instance.building_id, instance.type)
	building_state_changed.emit(instance.building_id, instance.state, "construction_complete")
	if instance.type == BuildingType.RESIDENTIAL_HOUSE:
		instance.npc_count = 1
		instance.npc_spawn_timer = 0
		building_npc_spawn_requested.emit(instance.building_id, instance.tile, 1)


## Advances NPC spawn timer for Residential House; spawns up to MAX_HOUSE_NPCS (AC-22).
func _advance_npc_timer(instance: BuildingInstance, delta: int) -> void:
	instance.npc_spawn_timer += delta
	if instance.npc_spawn_timer < NPC_SPAWN_INTERVAL:
		return
	instance.npc_spawn_timer = 0
	if instance.npc_count < MAX_HOUSE_NPCS:
		instance.npc_count += 1
		building_npc_spawn_requested.emit(instance.building_id, instance.tile, 1)
	# else: hard cap reached — reset timer, no spawn


## Advances or starts the production cycle for an OPERATING production building (AC-09/10/12/13).
func _advance_production_cycle(instance: BuildingInstance, delta: int) -> void:
	if not instance.cycle_running:
		var result: int = _try_start_production_cycle(instance)
		match result:
			_CycleStartResult.BLOCKED_NO_NPC, _CycleStartResult.BLOCKED_NO_INPUT, _CycleStartResult.BLOCKED_NO_CARRIER:
				instance.state = BuildingInstance.State.BLOCKED
				var reason: String = _cycle_blocked_reason(result)
				building_blocked.emit(instance.building_id, reason)
				building_state_changed.emit(instance.building_id, instance.state, reason)
		return
	instance.production_cycle_ticks += delta
	if instance.production_cycle_ticks < instance.production_cycle_duration:
		return
	# Cycle complete — deposit output to buffer.
	var cycle_output: Dictionary
	if instance.type == BuildingType.GATHERING_HUT:
		cycle_output = instance.gathering_output
	else:
		cycle_output = PRODUCTION_TABLE[instance.type]["output"]
	for resource_id: StringName in cycle_output:
		instance.buffered_output[resource_id] = instance.buffered_output.get(resource_id, 0) + cycle_output[resource_id]
	instance.cycle_running = false
	instance.production_cycle_ticks = 0
	# Inputs delivered mid-cycle set input_pending to delay same-tick consumption.
	# After a full cycle the delay is no longer needed — clear it so the restart
	# attempt below can succeed without waiting an extra tick.
	instance.input_pending = false
	production_output_ready.emit(instance.building_id, instance.buffered_output)
	# Attempt next cycle immediately so cycle_running is true again before the
	# indicator refresh fires — prevents a one-tick yellow flash between cycles.
	_advance_production_cycle(instance, 0)

# ---- Helpers ----------------------------------------------------------------

## Returns BLOCKED_BY_ADJACENCY when building_type has adjacency requirements and no
## neighbor (cardinal or diagonal) of tile satisfies them. Returns SUCCESS when met or absent.
func _check_adjacency(building_type: int, tile: Vector2i) -> int:
	if not ADJACENCY_REQUIREMENTS.has(building_type):
		return PlacementResult.SUCCESS
	var required_types: Array = ADJACENCY_REQUIREMENTS[building_type]
	for neighbor: Vector2i in _grid.get_neighbors(tile, true):
		if _grid.get_terrain(neighbor) in required_types:
			return PlacementResult.SUCCESS
	return PlacementResult.BLOCKED_BY_ADJACENCY


## Validates resource and energy affordability for building_type. No side effects.
func _check_resource_and_energy(building_type: int) -> int:
	var cost: Dictionary = BUILD_COST.get(building_type, {})
	for resource_id: StringName in cost:
		if _get_total_resource(resource_id) < cost[resource_id]:
			return PlacementResult.INSUFFICIENT_RESOURCES
	var energy_cost: int = _calc_energy_cost(building_type)
	if energy_cost > 0:
		if _player_character == null:
			push_warning("BuildingRegistry: PlayerCharacter dependency not set — call init_dependencies() first")
			return PlacementResult.BLOCKED_BY_BOUNDS
		if _player_character.get_current_energy() < energy_cost:
			return PlacementResult.INSUFFICIENT_ENERGY
	return PlacementResult.SUCCESS


## Deducts energy and resource costs for a confirmed build.
func _deduct_build_cost(building_type: int) -> void:
	var energy_cost: int = _calc_energy_cost(building_type)
	if _player_character != null and energy_cost > 0:
		_player_character.consume_energy(energy_cost)
	var cost: Dictionary = BUILD_COST.get(building_type, {})
	for resource_id: StringName in cost:
		_consume_resource_any(resource_id, cost[resource_id])


## Creates and configures a new BuildingInstance, including storage containers.
func _create_instance(building_id: String, building_type: int, tile: Vector2i) -> BuildingInstance:
	var instance := BuildingInstance.new(building_id, building_type, tile)
	instance.build_time = BUILD_TIME.get(building_type, 0)
	if building_type == BuildingType.COLLECTION_POINT or building_type == BuildingType.STORAGE_BUILDING:
		_setup_storage_for(instance)
	instance.state = BuildingInstance.State.OPERATING \
		if building_type == BuildingType.COLLECTION_POINT or building_type == BuildingType.ROAD \
		else BuildingInstance.State.CONSTRUCTING
	return instance


## Creates and registers the InventorySystem container for a storage-type building.
func _setup_storage_for(instance: BuildingInstance) -> void:
	var capacity: int = STORAGE_CAPACITY.get(instance.type, 0)
	var container_id: StringName = StringName("storage_%d_%d" % [instance.tile.x, instance.tile.y])
	if _inventory_system != null:
		_inventory_system.create_container(container_id, _building_type_name(instance.type), capacity, true)
	instance.assigned_container_id = container_id


## Appends instance to _all_buildings and maintains ascending building_id sort order.
func _insert_sorted(instance: BuildingInstance) -> void:
	_all_buildings.append(instance)
	_all_buildings.sort_custom(func(a: BuildingInstance, b: BuildingInstance) -> bool:
		return a.building_id.naturalnocasecmp_to(b.building_id) < 0
	)


## Attempts to start a production cycle. Returns a _CycleStartResult code.
## On SUCCESS: deducts inputs from input_buffer, sets cycle_running = true.
## Does NOT set building state — caller is responsible for BLOCKED transitions.
func _try_start_production_cycle(instance: BuildingInstance) -> int:
	if not PRODUCTION_TABLE.has(instance.type):
		return _CycleStartResult.OUTPUT_FULL
	if instance.input_pending:
		instance.input_pending = false
		return _CycleStartResult.OUTPUT_FULL  # skip this tick without entering BLOCKED
	var table_entry: Dictionary = PRODUCTION_TABLE[instance.type]
	var output_capacity: int = table_entry.get("output_capacity", 0)
	var buffered_total: int = 0
	for qty: int in instance.buffered_output.values():
		buffered_total += qty
	if buffered_total >= output_capacity:
		return _CycleStartResult.OUTPUT_FULL
	if table_entry.get("npc_required", false) and instance.assigned_npc_id == &"":
		return _CycleStartResult.BLOCKED_NO_NPC
	if instance.type == BuildingType.GATHERING_HUT and instance.gathering_output.is_empty():
		return _CycleStartResult.BLOCKED_NO_INPUT
	# Check whether the input buffer already has everything needed.
	# If it does, no carrier is required — manually loaded inputs are sufficient.
	var input_sufficient: bool = true
	for input_spec: Dictionary in table_entry["inputs"]:
		var resource_id: StringName = input_spec["resource_id"]
		var needed: float = input_spec.get("charge_cost", float(input_spec.get("quantity", 0)))
		if instance.input_buffer.get(resource_id, 0.0) < needed:
			input_sufficient = false
			break
	if not input_sufficient:
		if instance.input_carrier_ids.is_empty():
			return _CycleStartResult.BLOCKED_NO_CARRIER
		return _CycleStartResult.BLOCKED_NO_INPUT
	# Validate all inputs before deducting any.
	for input_spec: Dictionary in table_entry["inputs"]:
		var resource_id: StringName = input_spec["resource_id"]
		var cost: float = input_spec.get("charge_cost", float(input_spec.get("quantity", 0)))
		instance.input_buffer[resource_id] = instance.input_buffer.get(resource_id, 0.0) - cost
		if instance.input_buffer[resource_id] <= 0.0:
			instance.input_buffer.erase(resource_id)
	instance.production_cycle_duration = calculate_cycle_duration(table_entry.get("base_cycle_ticks", 0))
	instance.production_cycle_ticks = 0
	instance.cycle_running = true
	return _CycleStartResult.SUCCESS


## Attempts recovery for a BLOCKED production building on each tick (AC-11).
## Transitions to OPERATING and emits building_unblocked if conditions are now met.
func _try_recover_blocked(instance: BuildingInstance) -> void:
	var result: int = _try_start_production_cycle(instance)
	if result == _CycleStartResult.SUCCESS:
		instance.state = BuildingInstance.State.OPERATING
		building_unblocked.emit(instance.building_id)
		building_state_changed.emit(instance.building_id, instance.state, "unblocked")


## Maps a _CycleStartResult code to a human-readable BLOCKED reason string.
func _cycle_blocked_reason(result: int) -> String:
	match result:
		_CycleStartResult.BLOCKED_NO_NPC:     return "No NPC assigned"
		_CycleStartResult.BLOCKED_NO_CARRIER: return "No carrier assigned (inputs)"
		_CycleStartResult.BLOCKED_NO_INPUT:   return "Missing required input"
	return "Unknown"



## Returns true if the building has at least one item in its output buffer.
## Used by the carrier FSM to decide whether to pick up or enter WAITING_SOURCE.
func has_output_buffer(building_id: String) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	return not instance.buffered_output.is_empty()


## Returns the total number of items across all resource types in the building's output buffer.
## Used by the carrier FSM to calculate pickup quantity via min(total, carrier_capacity).
func get_output_buffer_total(building_id: String) -> int:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return 0
	var total: int = 0
	for qty: int in instance.buffered_output.values():
		total += qty
	return total


## Returns the first resource id in the output buffer, or &"" if empty.
## Used by the carrier FSM to record cargo_resource when picking up output.
func get_output_buffer_resource(building_id: String) -> StringName:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null or instance.buffered_output.is_empty():
		return &""
	return instance.buffered_output.keys()[0]


## Returns true when the given resource slot in the building's input buffer has reached
## its per-slot input_capacity. input_capacity == 0 means no limit.
## Used by LogisticsSystem to block carrier delivery when the target slot is full.
func is_input_full(building_id: String, resource_id: StringName) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	if not PRODUCTION_TABLE.has(instance.type):
		return false
	var input_capacity: int = PRODUCTION_TABLE[instance.type].get("input_capacity", 0)
	if input_capacity <= 0:
		return false
	return instance.input_buffer.get(resource_id, 0.0) >= float(input_capacity)


## Returns the quantity of a specific resource in the output buffer, or 0 if absent.
## Used by the carrier FSM when source_item_id filters to a specific resource type.
func get_output_buffer_resource_quantity(building_id: String, resource_id: StringName) -> int:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return 0
	return instance.buffered_output.get(resource_id, 0)


## Collects buffered output from a building (called by carrier NPC or tests).
## Returns the output dictionary and clears buffered_output. Returns empty if none buffered.
## If the building is STALLED, transitions it back to OPERATING (AC-14).
func collect_output(building_id: String) -> Dictionary:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null or instance.buffered_output.is_empty():
		return {}
	var output: Dictionary = instance.buffered_output.duplicate()
	instance.buffered_output.clear()
	building_output_changed.emit(building_id)
	return output

# ---- Transport formulas (Story 002) -----------------------------------------

## Formula 3: Carrier travel time = floor(distance × TICKS_PER_TILE). (AC-12)
## distance should be the Manhattan distance between building tile and storage tile.
func calculate_carrier_travel_ticks(distance: int) -> int:
	return int(floor(float(distance) * TICKS_PER_TILE))


## Formula 4: Production output — always base_output, no distance modifier. (AC-12)
func calculate_production_output(base_output: int) -> int:
	return base_output


## Formula 5: Production cycle duration — always base_cycle_ticks, no distance modifier. (AC-13)
func calculate_cycle_duration(base_cycle_ticks: int) -> int:
	return base_cycle_ticks


## Returns the NPCInstance array for the worker assigned to instance, or [] if none.
## Lazily acquires NPCSystem via Engine (load order: Buildings → NPCs, so no _enter_tree lookup).
## Injectable via _npc_system for unit tests.
func _get_assigned_workers(instance: BuildingInstance) -> Array:
	if instance.assigned_npc_id == &"":
		return []
	if _npc_system == null:
		_npc_system = Engine.get_singleton("NPCSystem")
	if _npc_system == null:
		return []
	var npc: Object = _npc_system.get_npc_instance(instance.assigned_npc_id)
	if npc == null:
		return []
	return [npc]


## Formula 7: placement energy cost = floor(sum(qty * ENERGY_PER_RESOURCE)).
func _calc_energy_cost(building_type: int) -> int:
	var cost: Dictionary = BUILD_COST.get(building_type, {})
	var total: int = 0
	for resource_id: StringName in cost:
		total += cost[resource_id]
	return int(floor(float(total) * ENERGY_PER_RESOURCE))


## Returns total quantity of resource_id across all inventory containers.
func _get_total_resource(resource_id: StringName) -> int:
	if _inventory_system == null:
		return 0
	var total: int = 0
	for container: Object in _inventory_system.get_all_containers():
		total += _inventory_system.get_resource_quantity(container.container_id, resource_id)
	return total


## Consumes quantity units of resource_id from containers in alphabetical order.
func _consume_resource_any(resource_id: StringName, quantity: int) -> void:
	if _inventory_system == null or quantity <= 0:
		return
	var remaining: int = quantity
	var containers: Array = _inventory_system.get_all_containers()
	containers.sort_custom(func(a: Object, b: Object) -> bool:
		return str(a.container_id) < str(b.container_id)
	)
	for container: Object in containers:
		if remaining <= 0:
			break
		var available: int = _inventory_system.get_resource_quantity(container.container_id, resource_id)
		if available <= 0:
			continue
		var to_consume: int = mini(available, remaining)
		_inventory_system.try_consume(container.container_id, resource_id, to_consume)
		remaining -= to_consume


## Updates adjacency_tile_count for instance and recalculates efficiency (F6).
## No-op when the building type has no adjacency requirements or _grid is not set.
func _update_adjacency_efficiency(instance: BuildingInstance) -> void:
	if not ADJACENCY_REQUIREMENTS.has(instance.type):
		return
	if _grid == null:
		return
	var required_types: Array = ADJACENCY_REQUIREMENTS[instance.type]
	var count: int = 0
	for neighbor: Vector2i in _grid.get_neighbors(instance.tile, true):
		if _grid.get_terrain(neighbor) in required_types:
			count += 1
	instance.adjacency_tile_count = count
	instance.recalculate_efficiency(_get_assigned_workers(instance))
	if instance.type == BuildingType.GATHERING_HUT:
		_update_gathering_output(instance)


## Recomputes gathering_output for a GATHERING_HUT based on which harvestable terrain
## types are currently adjacent. One output entry per distinct terrain type found;
## quantity comes from TERRAIN_HARVEST_OUTPUT regardless of how many tiles of that type exist.
func _update_gathering_output(instance: BuildingInstance) -> void:
	instance.gathering_output.clear()
	if _grid == null:
		return
	var seen_types: Dictionary = {}
	for neighbor: Vector2i in _grid.get_neighbors(instance.tile, true):
		var terrain: int = _grid.get_terrain(neighbor)
		if terrain in TERRAIN_HARVEST_OUTPUT and not seen_types.has(terrain):
			seen_types[terrain] = true
			for resource_id: StringName in TERRAIN_HARVEST_OUTPUT[terrain]:
				instance.gathering_output[resource_id] = TERRAIN_HARVEST_OUTPUT[terrain][resource_id]


## Handles WorldGrid.terrain_tile_changed: recalculates adjacency efficiency for every
## adjacency-requiring building whose tile is a cardinal neighbor of changed_tile.
func _on_terrain_tile_changed(changed_tile: Vector2i) -> void:
	for instance: BuildingInstance in _all_buildings:
		if instance.state == BuildingInstance.State.DEMOLISHED:
			continue
		if not ADJACENCY_REQUIREMENTS.has(instance.type):
			continue
		for neighbor: Vector2i in _grid.get_neighbors(instance.tile, true):
			if neighbor == changed_tile:
				_update_adjacency_efficiency(instance)
				break


## Handles InventorySystem.container_removed: clears the orphaned container reference on any
## building that was assigned to container_id and transitions it to BLOCKED (AC-24).
## STALLED and CONSTRUCTING buildings are unaffected — they don't consume a container.
func _on_container_removed(container_id: StringName) -> void:
	for instance: BuildingInstance in _all_buildings:
		if instance.state == BuildingInstance.State.DEMOLISHED:
			continue
		if instance.assigned_container_id != container_id:
			continue
		instance.assigned_container_id = &""
		if instance.state == BuildingInstance.State.OPERATING or instance.state == BuildingInstance.State.BLOCKED:
			instance.state = BuildingInstance.State.BLOCKED
			building_blocked.emit(instance.building_id, "No storage assigned")
			building_state_changed.emit(instance.building_id, instance.state, "No storage assigned")


## STUB: Spawns a placeholder visual for the building.
## Real PackedScene visuals deferred to MapRoot via the building_placed signal.
func _spawn_visual(_instance: BuildingInstance) -> void:
	pass  # MapRoot connects to building_placed and handles visual creation


func _building_type_name(building_type: int) -> String:
	match building_type:
		BuildingType.COLLECTION_POINT:  return "Collection Point"
		BuildingType.STORAGE_BUILDING:  return "Storage Building"
		BuildingType.RESIDENTIAL_HOUSE: return "Residential House"
		BuildingType.LUMBER_CAMP:       return "Lumber Camp"
		BuildingType.ROAD:              return "Road"
		BuildingType.GATHERING_HUT:     return "Gathering Hut"
		BuildingType.STONE_MASON:       return "Stone Mason"
		BuildingType.TOOL_WORKSHOP:     return "Tool Workshop"
	return "Unknown"

# ---- Stub methods (future stories) -----------------------------------------

## Sets the operational status of a building directly (called by LogisticsSystem — story-004).
## Maps the logistics status to the appropriate BuildingInstance.State and emits signals.
## Only OPERATING and BLOCKED transitions are valid via this API;
## CONSTRUCTING and DEMOLISHED are managed internally.
## reason: human-readable description of what triggered the status change.
func set_status(building_id: StringName, new_state: int, reason: String = "") -> void:
	var instance: BuildingInstance = get_building_instance(str(building_id))
	if instance == null:
		return
	if instance.state == BuildingInstance.State.CONSTRUCTING \
			or instance.state == BuildingInstance.State.DEMOLISHED:
		return
	if instance.state == new_state:
		return
	var prev_state: int = instance.state
	instance.state = new_state
	match new_state:
		BuildingInstance.State.OPERATING:
			if prev_state == BuildingInstance.State.BLOCKED:
				building_unblocked.emit(building_id)
			building_state_changed.emit(building_id, new_state, reason if reason != "" else "logistics_status_update")
		BuildingInstance.State.BLOCKED:
			var block_reason: String = reason if reason != "" else "no_input_carrier"
			building_blocked.emit(building_id, block_reason)
			building_state_changed.emit(building_id, new_state, block_reason)


## Sets a player-defined custom name for a building. Pass "" to revert to the type name.
## Emits building_renamed on success.
func rename_building(building_id: String, new_name: String) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return
	instance.custom_name = new_name.strip_edges()
	building_renamed.emit(building_id, instance.custom_name)


## Returns the display name for a building: custom_name if set, otherwise the type name.
func get_building_display_name(building_id: String) -> String:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return building_id
	if instance.custom_name != "":
		return instance.custom_name
	return _building_type_name(instance.type)


## Demolish a building. Returns true if found and removed.
## Releases any assigned NPC, discards buffered output, removes from grid and registry.
## Emits building_demolished and building_state_changed("demolished") on success.
func demolish_building(building_id: StringName) -> bool:
	var instance: BuildingInstance = get_building_instance(str(building_id))
	if instance == null:
		return false

	if instance.assigned_npc_id != &"":
		var npc_sys: Object = _npc_system if _npc_system != null else NPCSystem
		if npc_sys != null:
			npc_sys.release_npc(instance.assigned_npc_id)
		instance.assigned_npc_id = &""

	var drop_items: Dictionary = {}
	for res_id: StringName in instance.buffered_output:
		drop_items[res_id] = drop_items.get(res_id, 0) + instance.buffered_output[res_id]
	for res_id: StringName in instance.input_buffer:
		var qty: int = ceili(instance.input_buffer[res_id])
		if qty > 0:
			drop_items[res_id] = drop_items.get(res_id, 0) + qty
	if instance.assigned_container_id != &"" and _inventory_system != null:
		var container: InventoryContainer = _inventory_system.get_container(instance.assigned_container_id)
		if container != null:
			for slot: InventorySlot in container.slots:
				if slot.resource_id != &"" and slot.quantity > 0:
					drop_items[slot.resource_id] = drop_items.get(slot.resource_id, 0) + slot.quantity
	if not drop_items.is_empty():
		building_items_dropped.emit(instance.tile, drop_items)

	instance.buffered_output.clear()
	instance.input_buffer.clear()

	if _grid != null:
		_grid.remove_building(instance.tile)

	if instance.visual_node != null:
		instance.visual_node.queue_free()
		instance.visual_node = null

	_all_buildings.erase(instance)

	# Remove the storage container after erasing from _all_buildings so that
	# _on_container_removed does not re-process the already-demolished building.
	if instance.assigned_container_id != &"" and _inventory_system != null:
		_inventory_system.remove_container(instance.assigned_container_id)

	building_demolished.emit(building_id)
	building_state_changed.emit(str(building_id), BuildingInstance.State.DEMOLISHED, "demolished")

	return true


## Assigns an NPC to the named building (story-002). Required for production buildings.
## Replaces any previously assigned NPC without validation — NPC system handles lifecycle.
## Triggers building efficiency recalculation per ADR-0012.
func assign_npc(building_id: String, npc_id: StringName) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance != null:
		instance.assigned_npc_id = npc_id
		instance.recalculate_efficiency(_get_assigned_workers(instance))


## Adds a carrier NPC to the input carrier list for a production building.
## Called by LogisticsSystem when an INPUT route is created.
func add_input_carrier(building_id: String, carrier_id: StringName) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance != null and not instance.input_carrier_ids.has(carrier_id):
		instance.input_carrier_ids.append(carrier_id)
		building_state_changed.emit(building_id, instance.state, "input_carrier_assigned")


## Removes a carrier NPC from the input carrier list for a production building.
## Called by LogisticsSystem when an INPUT route is deleted or paused.
func remove_input_carrier(building_id: String, carrier_id: StringName) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance != null:
		instance.input_carrier_ids.erase(carrier_id)
		building_state_changed.emit(building_id, instance.state, "input_carrier_removed")


## Assigns (or clears) the output carrier for a production building.
## Called by LogisticsSystem when an OUTPUT route is created or deleted.
func assign_output_carrier(building_id: String, carrier_id: StringName) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance != null:
		instance.output_carrier_id = carrier_id
		building_state_changed.emit(building_id, instance.state, "output_carrier_assigned")


## Serialises all placed buildings and the internal ID counter.
func serialize() -> Dictionary:
	var buildings_data: Array = []
	for instance: BuildingInstance in _all_buildings:
		var input_buf: Dictionary = {}
		for k: StringName in instance.input_buffer:
			input_buf[str(k)] = instance.input_buffer[k]
		var buf_out: Dictionary = {}
		for k: StringName in instance.buffered_output:
			buf_out[str(k)] = instance.buffered_output[k]
		buildings_data.append({
			"building_id": instance.building_id,
			"type": instance.type,
			"tile_x": instance.tile.x,
			"tile_y": instance.tile.y,
			"state": instance.state,
			"accumulated_ticks": instance.accumulated_ticks,
			"build_time": instance.build_time,
			"assigned_container_id": str(instance.assigned_container_id),
			"custom_name": instance.custom_name,
			"input_buffer": input_buf,
			"production_cycle_ticks": instance.production_cycle_ticks,
			"production_cycle_duration": instance.production_cycle_duration,
			"cycle_running": instance.cycle_running,
			"buffered_output": buf_out,
			"assigned_npc_id": str(instance.assigned_npc_id),
			"npc_count": instance.npc_count,
			"npc_spawn_timer": instance.npc_spawn_timer,
			"input_pending": instance.input_pending,
			"input_carrier_ids": instance.input_carrier_ids.map(func(id: StringName) -> String: return str(id)),
			"output_carrier_id": str(instance.output_carrier_id),
			"upgrade_bonus": instance.upgrade_bonus,
			"efficiency": instance.efficiency,
			"adjacency_tile_count": instance.adjacency_tile_count,
		})
	return {"build_counter": _build_counter, "buildings": buildings_data}


## Restores buildings from a snapshot produced by serialize().
## Requires _grid to be set via init_dependencies() before calling.
## Emits building_placed for each building so the scene layer can create visuals.
## InventorySystem must be deserialised first (containers already restored).
func deserialize(data: Dictionary) -> void:
	_all_buildings.clear()
	_build_counter = data.get("build_counter", 0)
	for bd: Dictionary in data.get("buildings", []):
		var building_id: String = bd.get("building_id", "")
		var type: int = bd.get("type", 0)
		var tile := Vector2i(bd.get("tile_x", 0), bd.get("tile_y", 0))
		if _grid != null:
			_grid.place_building(tile, building_id)
		var instance := BuildingInstance.new(building_id, type, tile)
		instance.state = bd.get("state", BuildingInstance.State.OPERATING)
		instance.accumulated_ticks = bd.get("accumulated_ticks", 0)
		instance.build_time = bd.get("build_time", 0)
		instance.assigned_container_id = StringName(bd.get("assigned_container_id", ""))
		instance.custom_name = bd.get("custom_name", "")
		var ib: Dictionary = bd.get("input_buffer", {})
		for k: String in ib:
			instance.input_buffer[StringName(k)] = float(ib[k])
		instance.production_cycle_ticks = bd.get("production_cycle_ticks", 0)
		instance.production_cycle_duration = bd.get("production_cycle_duration", 0)
		instance.cycle_running = bd.get("cycle_running", false)
		var bo: Dictionary = bd.get("buffered_output", {})
		for k: String in bo:
			instance.buffered_output[StringName(k)] = int(bo[k])
		instance.assigned_npc_id = StringName(bd.get("assigned_npc_id", ""))
		instance.npc_count = bd.get("npc_count", 0)
		instance.npc_spawn_timer = bd.get("npc_spawn_timer", 0)
		instance.input_pending = bd.get("input_pending", false)
		var iids: Array = bd.get("input_carrier_ids", [])
		if iids.is_empty():
			var legacy: String = bd.get("input_carrier_id", "")
			if legacy != "":
				iids = [legacy]
		for iid: String in iids:
			if iid != "":
				instance.input_carrier_ids.append(StringName(iid))
		instance.output_carrier_id = StringName(bd.get("output_carrier_id", ""))
		instance.upgrade_bonus = bd.get("upgrade_bonus", 0.0)
		instance.efficiency = bd.get("efficiency", 1.0)
		instance.adjacency_tile_count = bd.get("adjacency_tile_count", 0)
		_insert_sorted(instance)
		if instance.type == BuildingType.GATHERING_HUT:
			_update_gathering_output(instance)
		building_placed.emit(building_id, type, tile)
