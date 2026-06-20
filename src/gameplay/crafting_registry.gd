extends Node
## CraftingRegistry — recipe definitions and tick-based craft execution.
## Mirrors BuildingRegistry pattern: data constants + try_craft() execution method.
## Crafting is not instant: it accumulates ticks like a manual action.

# ---- Enums ------------------------------------------------------------------

enum CraftResult {
	SUCCESS,
	INSUFFICIENT_RESOURCES,
	INSUFFICIENT_ENERGY,
	NO_STORAGE,
	ALREADY_CRAFTING,
	LOCKED,  ## recipe not yet unlocked in the Progression Tree
}

# ---- Recipe tables ----------------------------------------------------------

## recipe_id → material cost { resource_id: quantity }
const RECIPE_COST: Dictionary = {
	&"axe":         {&"wood": 3, &"stone": 2},
	&"pickaxe":     {&"stone": 3, &"wood": 1},
	&"knife":       {&"wood": 2, &"stone": 1},
	&"spindle":     {&"wood": 2, &"fiber": 2},
	&"cloth":       {&"fiber": 4},
	&"clothing":    {&"cloth": 3, &"fiber": 2},
	&"hunting_bow": {&"wood": 2, &"fiber": 3},
}

## recipe_id → flat energy cost
const RECIPE_ENERGY_COST: Dictionary = {
	&"axe":         20,
	&"pickaxe":     20,
	&"knife":       20,
	&"spindle":     15,
	&"cloth":       20,
	&"clothing":    25,
	&"hunting_bow": 20,
}

## recipe_id → tick cost (1 tick ≈ 1 minute game-time).
const RECIPE_TICKS: Dictionary = {
	&"axe":         120,
	&"pickaxe":     120,
	&"knife":       90,
	&"spindle":     90,
	&"cloth":       180,
	&"clothing":    240,
	&"hunting_bow": 120,
}

## recipe_id → output { resource_id: StringName, quantity: int }
const RECIPE_OUTPUT: Dictionary = {
	&"axe":         {&"resource_id": &"axe",         &"quantity": 1},
	&"pickaxe":     {&"resource_id": &"pickaxe",     &"quantity": 1},
	&"knife":       {&"resource_id": &"knife",       &"quantity": 1},
	&"spindle":     {&"resource_id": &"spindle",     &"quantity": 1},
	&"cloth":       {&"resource_id": &"cloth",       &"quantity": 1},
	&"clothing":    {&"resource_id": &"clothing",    &"quantity": 1},
	&"hunting_bow": {&"resource_id": &"hunting_bow", &"quantity": 1},
}

## recipe_id → display name (shown in CraftingGrid)
const RECIPE_DISPLAY_NAME: Dictionary = {
	&"axe":         "Craft Axe",
	&"pickaxe":     "Craft Pickaxe",
	&"knife":       "Craft Knife",
	&"spindle":     "Craft Spindle",
	&"cloth":       "Weave Cloth",
	&"clothing":    "Sew Clothing",
	&"hunting_bow": "Craft Hunting Bow",
}

## Ordered list for display in CraftingGrid
const RECIPE_ORDER: Array[StringName] = [&"axe", &"pickaxe", &"knife", &"spindle", &"cloth", &"clothing", &"hunting_bow"]

# ---- Signals ----------------------------------------------------------------

## Emitted when a craft starts. UI uses this to show the progress ring.
signal crafting_started(recipe_id: StringName, total_ticks: int)

## Emitted each tick while a craft is in progress. progress is in [0.0, 1.0].
signal crafting_progress(recipe_id: StringName, progress: float)

## Emitted after a craft completes successfully.
signal recipe_crafted(recipe_id: StringName, quantity: int)

# ---- State ------------------------------------------------------------------

var _is_crafting: bool        = false
var _active_recipe: StringName = &""
var _accumulated_ticks: int   = 0
var _total_ticks: int         = 0
var _pending_target_id: StringName  = &""
var _pending_output_res: StringName = &""
var _pending_output_qty: int        = 0
## Building ID of the currently selected crafting bench storage. &"" = auto-select first.
var selected_crafting_storage: String = ""
## Building ID whose container the active craft will deposit into. Set in try_craft(), cleared in _complete_craft().
var _crafting_building_id: String = ""

# ---- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	BuildingRegistry.upgrade_removed.connect(_on_upgrade_removed)


func _exit_tree() -> void:
	if TickSystem.ticks_advanced.is_connected(_on_ticks_advanced):
		TickSystem.ticks_advanced.disconnect(_on_ticks_advanced)
	if BuildingRegistry.upgrade_removed.is_connected(_on_upgrade_removed):
		BuildingRegistry.upgrade_removed.disconnect(_on_upgrade_removed)

# ---- Craft API --------------------------------------------------------------

## Attempts to start crafting recipe_id. Resources and energy are deducted immediately;
## output is deposited when the tick accumulator completes.
## Returns a CraftResult value.
func try_craft(recipe_id: StringName) -> int:
	if _is_crafting:
		return CraftResult.ALREADY_CRAFTING

	# Progression gate (command layer): reject recipes not yet unlocked in the tech tree.
	if not ProgressionSystem.is_recipe_unlocked(recipe_id):
		return CraftResult.LOCKED

	var cost: Dictionary   = RECIPE_COST.get(recipe_id, {})
	var energy_cost: int   = RECIPE_ENERGY_COST.get(recipe_id, 0)
	var output: Dictionary = RECIPE_OUTPUT.get(recipe_id, {})

	# 1. Resource check
	for res_id: StringName in cost:
		if _get_total_resource(res_id) < cost[res_id]:
			return CraftResult.INSUFFICIENT_RESOURCES

	# 2. Energy check
	var player: Node = get_tree().get_first_node_in_group(&"player_character")
	if player != null and energy_cost > 0:
		if player.get_current_energy() < energy_cost:
			return CraftResult.INSUFFICIENT_ENERGY

	# 3. Storage check — use selected crafting bench container, or auto-select first with space.
	var target_id: StringName = _find_bench_container_with_space(1)
	if target_id == &"":
		return CraftResult.NO_STORAGE

	# 4. Deduct resources
	for res_id: StringName in cost:
		_consume_resource_any(res_id, cost[res_id])

	# 5. Deduct energy
	if player != null and energy_cost > 0:
		player.consume_energy(energy_cost)

	# 6. Resolve which building owns the target container (for map indicator).
	_crafting_building_id = ""
	for b: BuildingRegistry.BuildingInstance in BuildingRegistry.get_all_buildings():
		if b.assigned_container_id == target_id:
			_crafting_building_id = b.building_id
			break

	# 7. Start progressive craft
	_is_crafting        = true
	_active_recipe      = recipe_id
	_accumulated_ticks  = 0
	_total_ticks        = RECIPE_TICKS.get(recipe_id, 60)
	_pending_target_id  = target_id
	_pending_output_res = output.get(&"resource_id", &"")
	_pending_output_qty = output.get(&"quantity", 1)

	crafting_started.emit(recipe_id, _total_ticks)
	return CraftResult.SUCCESS


## Returns true while a craft is in progress.
func is_crafting() -> bool:
	return _is_crafting


## Returns the recipe_id of the active craft, or &"" if idle.
func get_active_recipe_id() -> StringName:
	return _active_recipe


## Returns the building ID the active craft will deposit into, or "" if idle.
func get_crafting_building_id() -> String:
	return _crafting_building_id


## Returns crafting progress in [0.0, 1.0], or 0.0 if idle.
func get_crafting_progress() -> float:
	if not _is_crafting or _total_ticks <= 0:
		return 0.0
	return clampf(float(_accumulated_ticks) / float(_total_ticks), 0.0, 1.0)

# ---- Tick handler -----------------------------------------------------------

func _on_ticks_advanced(n: int) -> void:
	if not _is_crafting:
		return
	_accumulated_ticks += n
	var progress := clampf(float(_accumulated_ticks) / float(_total_ticks), 0.0, 1.0)
	crafting_progress.emit(_active_recipe, progress)
	if _accumulated_ticks >= _total_ticks:
		_complete_craft()


func _complete_craft() -> void:
	var finished_recipe: StringName = _active_recipe
	var qty: int                    = _pending_output_qty
	var res_id: StringName          = _pending_output_res
	var target_id: StringName       = _pending_target_id

	_is_crafting          = false
	_active_recipe        = &""
	_accumulated_ticks    = 0
	_total_ticks          = 0
	_pending_target_id    = &""
	_pending_output_res   = &""
	_pending_output_qty   = 0
	_crafting_building_id = ""

	InventorySystem.try_deposit(target_id, res_id, qty)
	recipe_crafted.emit(finished_recipe, qty)

# ---- Crafting bench API -----------------------------------------------------

## Returns true if at least one storage building with a crafting bench exists.
func has_crafting_bench() -> bool:
	return not BuildingRegistry.get_buildings_with_upgrade(&"crafting_bench").is_empty()


## Returns all storage building IDs that have a crafting bench installed.
func get_crafting_bench_buildings() -> Array[String]:
	return BuildingRegistry.get_buildings_with_upgrade(&"crafting_bench")


## Sets the building ID used as output storage for crafting.
## Pass "" to auto-select the first available bench.
func set_selected_storage(building_id: String) -> void:
	selected_crafting_storage = building_id


# ---- Upgrade cleanup --------------------------------------------------------

func _on_upgrade_removed(building_id: String, upgrade_id: StringName) -> void:
	if upgrade_id != &"crafting_bench":
		return
	if selected_crafting_storage == building_id:
		selected_crafting_storage = ""

# ---- Helpers ----------------------------------------------------------------

func _get_total_resource(resource_id: StringName) -> int:
	var total: int = 0
	for container: InventoryContainer in InventorySystem.get_all_containers():
		total += InventorySystem.get_resource_quantity(container.container_id, resource_id)
	return total


func _consume_resource_any(resource_id: StringName, quantity: int) -> void:
	if quantity <= 0:
		return
	var remaining: int = quantity
	var containers: Array[InventoryContainer] = InventorySystem.get_all_containers()
	containers.sort_custom(func(a: InventoryContainer, b: InventoryContainer) -> bool:
		return str(a.container_id) < str(b.container_id)
	)
	for container: InventoryContainer in containers:
		if remaining <= 0:
			break
		var available: int = InventorySystem.get_resource_quantity(container.container_id, resource_id)
		if available <= 0:
			continue
		var to_consume: int = mini(available, remaining)
		InventorySystem.try_consume(container.container_id, resource_id, to_consume)
		remaining -= to_consume


func _find_container_with_space(space: int) -> StringName:
	for container: InventoryContainer in InventorySystem.get_all_containers():
		var remaining: int = container.capacity - (container.get_total_quantity() if container.quantity_based else container.get_occupied_count())
		if remaining >= space:
			return container.container_id
	return &""


## Finds a container in a crafting-bench storage building that has space.
## Prefers selected_crafting_storage; falls back to first bench building.
## Falls back to any container if no bench buildings exist (backwards-compat).
func _find_bench_container_with_space(space: int) -> StringName:
	var bench_buildings: Array[String] = BuildingRegistry.get_buildings_with_upgrade(&"crafting_bench")
	if bench_buildings.is_empty():
		return _find_container_with_space(space)
	# Prefer the user-selected bench.
	if selected_crafting_storage != "" and bench_buildings.has(selected_crafting_storage):
		var inst: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(selected_crafting_storage)
		if inst != null and inst.assigned_container_id != &"":
			var c: InventoryContainer = InventorySystem.get_container(inst.assigned_container_id)
			if c != null:
				var rem: int = c.capacity - (c.get_total_quantity() if c.quantity_based else c.get_occupied_count())
				if rem >= space:
					return c.container_id
	# Fall back to first bench with space.
	for bid: String in bench_buildings:
		var inst: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(bid)
		if inst == null or inst.assigned_container_id == &"":
			continue
		var c: InventoryContainer = InventorySystem.get_container(inst.assigned_container_id)
		if c == null:
			continue
		var rem: int = c.capacity - (c.get_total_quantity() if c.quantity_based else c.get_occupied_count())
		if rem >= space:
			return c.container_id
	return &""
