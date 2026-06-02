extends Node
## BuildingRegistry — Autoload singleton for building placement, construction progress,
## production cycle advancement, and building instance tracking.
## ADR: Buildings Story 001 (placement), Story 002 (production cycles).
##
## WorldGrid and PlayerCharacter are NOT Autoloads — they are injected via
## init_dependencies() after the scene tree is ready (called by MapRoot).

# ---- Enums ------------------------------------------------------------------

enum BuildingType {
	STORAGE_AREA,        ## 0 cost, instant, 50 slots
	STORAGE_BUILDING,    ## 8 Wood + 2 Stone, 120 ticks, 150 slots
	RESIDENTIAL_HOUSE,   ## 10 Wood + 3 Stone, 150 ticks
	LUMBER_CAMP,         ## 15 Wood + 3 Stone, 200 ticks
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

# ---- Inner classes ----------------------------------------------------------

class BuildingInstance:
	enum State { CONSTRUCTING, OPERATING, BLOCKED, STALLED, DEMOLISHED }

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
	## Count of NPCs spawned by a Residential House.
	var npc_count: int = 0
	## Ticks accumulated toward next NPC spawn (Residential House only).
	var npc_spawn_timer: int = 0
	## Set to true when input is added; prevents production from starting on the same tick.
	var input_pending: bool = false

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
	BuildingType.STORAGE_AREA:      {},
	BuildingType.STORAGE_BUILDING:  {&"wood": 8, &"stone": 2},
	BuildingType.RESIDENTIAL_HOUSE: {&"wood": 10, &"stone": 3},
	BuildingType.LUMBER_CAMP:       {&"wood": 15, &"stone": 3},
}

const BUILD_TIME: Dictionary = {
	BuildingType.STORAGE_AREA:      0,
	BuildingType.STORAGE_BUILDING:  120,
	BuildingType.RESIDENTIAL_HOUSE: 150,
	BuildingType.LUMBER_CAMP:       200,
}

const STORAGE_CAPACITY: Dictionary = {
	BuildingType.STORAGE_AREA:     50,
	BuildingType.STORAGE_BUILDING: 150,
}

## Maps BuildingType → texture resource path. Used by placement ghost and building visuals.
const BUILDING_TEXTURES: Dictionary = {
	BuildingType.STORAGE_AREA:      "res://assets/art/tiles/bld_tile_storage.png",
	BuildingType.STORAGE_BUILDING:  "res://assets/art/tiles/bld_tile_storage.png",
	BuildingType.RESIDENTIAL_HOUSE: "res://assets/art/tiles/bld_tile_storage.png",
	BuildingType.LUMBER_CAMP:       "res://assets/art/tiles/bld_tile_lumber_camp.png",
}

## Resource IDs accepted as manual input for each production building type.
const INPUT_RESOURCES: Dictionary = {
	BuildingType.LUMBER_CAMP: [&"tool"],
}

## Terrain types required in at least one cardinal neighbor for a building to be placeable.
## Maps BuildingType → Array of WorldGrid.TileType values.
const ADJACENCY_REQUIREMENTS: Dictionary = {
	BuildingType.LUMBER_CAMP: [WorldGrid.TileType.TREE],
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
		"output_capacity": 50,
		"base_cycle_ticks": 100,
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

# ---- State ------------------------------------------------------------------

var _tick_system: Node = null
var _inventory_system: Node = null
var _grid: Node = null            ## WorldGrid — injected by MapRoot
var _player_character: Node = null  ## PlayerCharacter — injected by MapRoot
var _all_buildings: Array[BuildingInstance] = []
var _build_counter: int = 0

# ---- Lifecycle --------------------------------------------------------------

func _enter_tree() -> void:
	_tick_system = TickSystem
	_inventory_system = InventorySystem
	if _tick_system != null:
		_tick_system.ticks_advanced.connect(_on_ticks_advanced)


## Called by MapRoot after scene is ready to wire scene-tree dependencies.
func init_dependencies(grid: Node, player_character: Node) -> void:
	_grid = grid
	_player_character = player_character

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
## Use only during map initialisation (MapRoot._ready).
func place_starter_building(building_type: int, tile: Vector2i) -> int:
	if _grid == null:
		push_warning("BuildingRegistry: GridMap dependency not set")
		return PlacementResult.BLOCKED_BY_BOUNDS
	var building_id: String = str(_build_counter)
	var place_result: int = _grid.place_building(tile, building_id)
	if place_result != 0:
		return place_result
	_build_counter += 1
	var instance := BuildingInstance.new(building_id, building_type, tile)
	instance.build_time = BUILD_TIME.get(building_type, 0)
	# [MOCK: NPC system not implemented — treat production buildings as always staffed]
	instance.state = BuildingInstance.State.OPERATING
	if PRODUCTION_TABLE.has(building_type):
		instance.assigned_npc_id = &"mock_npc"
	if building_type == BuildingType.STORAGE_AREA or building_type == BuildingType.STORAGE_BUILDING:
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


## Returns all BuildingInstances (shallow copy).
func get_all_buildings() -> Array[BuildingInstance]:
	return _all_buildings.duplicate()


## Returns building count.
func get_building_count() -> int:
	return _all_buildings.size()


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
	for neighbor: Vector2i in _grid.get_neighbors(tile):
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


## Advances construction timer; transitions to OPERATING at build_time threshold.
func _advance_construction(instance: BuildingInstance, delta: int) -> void:
	instance.accumulated_ticks += delta
	if instance.accumulated_ticks < instance.build_time:
		return
	instance.state = BuildingInstance.State.OPERATING
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


## Advances or starts the production cycle for an OPERATING production building (AC-09, AC-13).
func _advance_production_cycle(instance: BuildingInstance, delta: int) -> void:
	if not instance.cycle_running:
		_try_start_production_cycle(instance)
		return
	instance.production_cycle_ticks += delta
	if instance.production_cycle_ticks < instance.production_cycle_duration:
		return
	var table_entry: Dictionary = PRODUCTION_TABLE[instance.type]
	for resource_id: StringName in table_entry["output"]:
		instance.buffered_output[resource_id] = instance.buffered_output.get(resource_id, 0) + table_entry["output"][resource_id]
	instance.cycle_running = false
	instance.production_cycle_ticks = 0
	production_output_ready.emit(instance.building_id, instance.buffered_output)

# ---- Helpers ----------------------------------------------------------------

## Returns BLOCKED_BY_ADJACENCY when building_type has adjacency requirements and no cardinal
## neighbor of tile satisfies them. Returns SUCCESS when requirements are met or absent.
func _check_adjacency(building_type: int, tile: Vector2i) -> int:
	if not ADJACENCY_REQUIREMENTS.has(building_type):
		return PlacementResult.SUCCESS
	var required_types: Array = ADJACENCY_REQUIREMENTS[building_type]
	for neighbor: Vector2i in _grid.get_neighbors(tile):
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
	if building_type == BuildingType.STORAGE_AREA or building_type == BuildingType.STORAGE_BUILDING:
		_setup_storage_for(instance)
	instance.state = BuildingInstance.State.OPERATING if building_type == BuildingType.STORAGE_AREA \
		else BuildingInstance.State.CONSTRUCTING
	return instance


## Creates and registers the InventorySystem container for a storage-type building.
func _setup_storage_for(instance: BuildingInstance) -> void:
	var capacity: int = STORAGE_CAPACITY.get(instance.type, 0)
	var container_id: StringName = StringName("storage_%d_%d" % [instance.tile.x, instance.tile.y])
	if _inventory_system != null:
		_inventory_system.create_container(container_id, _building_type_name(instance.type), capacity)
	instance.assigned_container_id = container_id


## Appends instance to _all_buildings and maintains ascending building_id sort order.
func _insert_sorted(instance: BuildingInstance) -> void:
	_all_buildings.append(instance)
	_all_buildings.sort_custom(func(a: BuildingInstance, b: BuildingInstance) -> bool:
		return a.building_id.naturalnocasecmp_to(b.building_id) < 0
	)


## Attempts to start a production cycle for a production building (AC-09).
## Checks: NPC assigned, input buffer has required resources, no output buffered.
## On success: deducts inputs from input_buffer, sets cycle_running = true.
func _try_start_production_cycle(instance: BuildingInstance) -> void:
	if not PRODUCTION_TABLE.has(instance.type):
		return
	if instance.input_pending:
		instance.input_pending = false
		return
	var table_entry: Dictionary = PRODUCTION_TABLE[instance.type]
	var output_capacity: int = table_entry.get("output_capacity", 0)
	var buffered_total: int = 0
	for qty: int in instance.buffered_output.values():
		buffered_total += qty
	if buffered_total >= output_capacity:
		return
	if table_entry.get("npc_required", false) and instance.assigned_npc_id == &"":
		return
	# Validate all inputs before deducting any.
	for input_spec: Dictionary in table_entry["inputs"]:
		var resource_id: StringName = input_spec["resource_id"]
		var needed: float = input_spec.get("charge_cost", float(input_spec.get("quantity", 0)))
		if instance.input_buffer.get(resource_id, 0.0) < needed:
			return
	# All inputs available — deduct and start the cycle.
	for input_spec: Dictionary in table_entry["inputs"]:
		var resource_id: StringName = input_spec["resource_id"]
		var cost: float = input_spec.get("charge_cost", float(input_spec.get("quantity", 0)))
		instance.input_buffer[resource_id] = instance.input_buffer.get(resource_id, 0.0) - cost
		if instance.input_buffer[resource_id] <= 0.0:
			instance.input_buffer.erase(resource_id)
	instance.production_cycle_duration = calculate_cycle_duration(table_entry.get("base_cycle_ticks", 0))
	instance.production_cycle_ticks = 0
	instance.cycle_running = true


## Collects buffered output from a building (called by carrier NPC or tests).
## Returns the output dictionary and clears buffered_output. Returns empty if none.
func collect_output(building_id: String) -> Dictionary:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null or instance.buffered_output.is_empty():
		return {}
	var output: Dictionary = instance.buffered_output.duplicate()
	instance.buffered_output.clear()
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


## STUB: Spawns a placeholder visual for the building.
## Real PackedScene visuals deferred to MapRoot via the building_placed signal.
func _spawn_visual(_instance: BuildingInstance) -> void:
	pass  # MapRoot connects to building_placed and handles visual creation


func _building_type_name(building_type: int) -> String:
	match building_type:
		BuildingType.STORAGE_AREA:      return "Storage Area"
		BuildingType.STORAGE_BUILDING:  return "Storage Building"
		BuildingType.RESIDENTIAL_HOUSE: return "Residential House"
		BuildingType.LUMBER_CAMP:       return "Lumber Camp"
	return "Unknown"

# ---- Stub methods (future stories) -----------------------------------------

## STUB (story-005): Demolish a building. Returns true if found and removed.
func demolish_building(_building_id: String) -> bool:
	return false  # story-005


## Assigns an NPC to the named building (story-002). Required for production buildings.
## Replaces any previously assigned NPC without validation — NPC system handles lifecycle.
func assign_npc(building_id: String, npc_id: StringName) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance != null:
		instance.assigned_npc_id = npc_id


## STUB (story-005): Serialize all buildings.
func serialize() -> Dictionary:
	return {}  # story-005


## STUB (story-005): Restore buildings from snapshot.
func deserialize(_data: Dictionary) -> void:
	pass  # story-005
