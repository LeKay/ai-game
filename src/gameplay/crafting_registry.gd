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
	&"rope":        {&"fiber": 4},
}

## recipe_id → flat energy cost
const RECIPE_ENERGY_COST: Dictionary = {
	&"axe":         20,
	&"pickaxe":     20,
	&"knife":       20,
	&"spindle":     15,
	&"rope":        15,
}

## recipe_id → tick cost (1 tick ≈ 1 minute game-time).
const RECIPE_TICKS: Dictionary = {
	&"axe":         120,
	&"pickaxe":     120,
	&"knife":       90,
	&"spindle":     90,
	&"rope":        90,
}

## recipe_id → output { resource_id: StringName, quantity: int }
const RECIPE_OUTPUT: Dictionary = {
	&"axe":         {&"resource_id": &"axe",         &"quantity": 1},
	&"pickaxe":     {&"resource_id": &"pickaxe",     &"quantity": 1},
	&"knife":       {&"resource_id": &"knife",       &"quantity": 1},
	&"spindle":     {&"resource_id": &"spindle",     &"quantity": 2},
	&"rope":        {&"resource_id": &"rope",        &"quantity": 1},
}

## recipe_id → display name (shown in CraftingGrid)
const RECIPE_DISPLAY_NAME: Dictionary = {
	&"axe":         "Craft Axe",
	&"pickaxe":     "Craft Pickaxe",
	&"knife":       "Craft Knife",
	&"spindle":     "Craft Spindle",
	&"rope":        "Twist Rope",
}

## Ordered list for display in CraftingGrid
const RECIPE_ORDER: Array[StringName] = [&"axe", &"pickaxe", &"knife", &"spindle", &"rope"]

# ---- Signals ----------------------------------------------------------------

## Emitted when a craft starts. UI uses this to show the progress ring.
signal crafting_started(recipe_id: StringName, total_ticks: int)

## Emitted each tick while a craft is in progress. progress is in [0.0, 1.0].
signal crafting_progress(recipe_id: StringName, progress: float)

## Emitted after a craft completes successfully.
signal recipe_crafted(recipe_id: StringName, quantity: int)

# ---- Constants --------------------------------------------------------------

## Holder id used for the active craft's storage reservation. A single craft runs at
## a time (guarded by _is_crafting), so one fixed holder is sufficient. Distinct from
## any logistics route id, so a craft and a route can both hold space in the same
## container without clobbering each other's reservation.
const _CRAFT_HOLDER_ID: StringName = &"__crafting__"

## Radius (in tiles) searched outward from the crafting building when the finished
## item cannot be deposited and must be dropped on the map. Mirrors the logistics
## rescue-dump search.
const _DROP_SEARCH_RADIUS: int = 4

# ---- State ------------------------------------------------------------------

## WorldGrid node used for the map-drop fallback. Injected via set_grid_map() (same
## wiring point as LogisticsSystem/NPCSystem in map_root). Null in headless unit tests.
var _grid_map: Node = null

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
	var out_res: StringName = output.get(&"resource_id", &"")
	var out_qty: int        = output.get(&"quantity", 1)

	# 1. Resource check (skipped when the debug "ignore costs" cheat is active)
	if not DebugSettings.ignore_costs:
		for res_id: StringName in cost:
			if _get_total_resource(res_id) < cost[res_id]:
				return CraftResult.INSUFFICIENT_RESOURCES

	# 2. Energy check
	var player: Node = get_tree().get_first_node_in_group(&"player_character")
	if not DebugSettings.ignore_costs and player != null and energy_cost > 0:
		if player.get_current_energy() < energy_cost:
			return CraftResult.INSUFFICIENT_ENERGY

	# 3. Storage check — use selected crafting bench container, or auto-select first with
	#    room for the full output. The lookup is reservation-aware so space already promised
	#    to an in-flight transport carrier does not count as free.
	var target_id: StringName = _find_bench_container_with_space(out_qty)
	if target_id == &"":
		return CraftResult.NO_STORAGE

	# 3a. Reserve that space for the whole craft duration. This is the same mechanism
	#     transport routes use, so a route finishing mid-craft sees the space as taken and
	#     cannot fill it — eliminating the race that made the finished item disappear.
	#     reserve_space is the authoritative capacity check (the find above is advisory).
	if not InventorySystem.reserve_space(target_id, _CRAFT_HOLDER_ID, out_res, out_qty):
		return CraftResult.NO_STORAGE

	# 4. Deduct resources + energy (skipped under the debug "ignore costs" cheat)
	if not DebugSettings.ignore_costs:
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
	_pending_output_res = out_res
	_pending_output_qty = out_qty

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
	var building_id: String       = _crafting_building_id
	_crafting_building_id = ""

	# Deposit against our own reservation (holder id), so the space we held for the whole
	# craft is consumed atomically. Because routes treat that reservation as occupied, this
	# fits even if a carrier finished a delivery mid-craft.
	var result: InventoryContainer.DepositResult = InventorySystem.try_deposit(
			target_id, res_id, qty, _CRAFT_HOLDER_ID)
	if result != InventoryContainer.DepositResult.SUCCESS:
		# Fallback: deposit failed despite the reservation (container removed mid-craft,
		# capacity shrunk, slot-based first-fit edge). Release the now-unconsumed reservation
		# and spawn the item on the map near the bench so it is never silently lost.
		InventorySystem.release_reservation(target_id, _CRAFT_HOLDER_ID)
		_spawn_output_on_map(building_id, res_id, qty)

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

# ---- Grid injection (map-drop fallback) -------------------------------------

## Injects the active WorldGrid so finished items can be dropped on the map when storage
## is unavailable. Wired from map_root alongside LogisticsSystem.set_grid_map().
func set_grid_map(grid: Node) -> void:
	_grid_map = grid

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


## Free space in a container, treating outstanding reservations (transport carriers,
## other in-flight holders) as already occupied. Keeps craft target selection in sync
## with the reservation a craft is about to place, so two systems can't both claim it.
func _container_free_space(c: InventoryContainer) -> int:
	var used: int = c.get_total_quantity() if c.quantity_based else c.get_occupied_count()
	return c.capacity - used - c.get_reserved_total()


func _find_container_with_space(space: int) -> StringName:
	for container: InventoryContainer in InventorySystem.get_all_containers():
		if _container_free_space(container) >= space:
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
			if c != null and _container_free_space(c) >= space:
				return c.container_id
	# Fall back to first bench with space.
	for bid: String in bench_buildings:
		var inst: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(bid)
		if inst == null or inst.assigned_container_id == &"":
			continue
		var c: InventoryContainer = InventorySystem.get_container(inst.assigned_container_id)
		if c == null:
			continue
		if _container_free_space(c) >= space:
			return c.container_id
	return &""


# ---- Map-drop fallback ------------------------------------------------------

## Drops `qty` units of `res_id` on the map near the crafting building when the finished
## item could not be deposited. Searches outward in concentric rings (mirrors the logistics
## rescue-dump) for tiles WorldGrid.add_resource_to_tile will accept. Items that find no
## tile in range are lost (extremely cramped layouts) and a warning is pushed.
func _spawn_output_on_map(building_id: String, res_id: StringName, qty: int) -> void:
	if qty <= 0 or res_id == &"" or _grid_map == null:
		push_warning("[CraftingRegistry] could not place %d×%s and no map drop possible" % [qty, res_id])
		return
	var drop_tile: Vector2i = _find_drop_tile_near(building_id)
	if drop_tile == Vector2i(-1, -1):
		push_warning("[CraftingRegistry] LOST %d×%s — no drop tile found near %s" % [qty, res_id, building_id])
		return
	var dropped: int = 0
	for _i: int in range(qty):
		if _grid_map.add_resource_to_tile(drop_tile, res_id, true):
			dropped += 1
	if dropped < qty:
		push_warning("[CraftingRegistry] dropped %d/%d×%s at %s (rest lost)" % [dropped, qty, res_id, drop_tile])


## Returns a tile near `building_id` where dropped output can be placed, or (-1,-1) if none
## within _DROP_SEARCH_RADIUS. Searches ring by ring outward from the building's tile.
func _find_drop_tile_near(building_id: String) -> Vector2i:
	if _grid_map == null:
		return Vector2i(-1, -1)
	var origin: Vector2i = BuildingRegistry.get_building_tile(building_id)
	if origin == Vector2i(-1, -1):
		return Vector2i(-1, -1)
	for radius: int in range(0, _DROP_SEARCH_RADIUS + 1):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				# Only the outer ring of this radius (skip interior — already searched).
				if radius > 0 and absi(dx) != radius and absi(dy) != radius:
					continue
				var t: Vector2i = origin + Vector2i(dx, dy)
				if _can_drop_on_tile(t):
					return t
	return Vector2i(-1, -1)


## True when `tile` is in-bounds, passable, and not occupied by a building — i.e. a tile
## WorldGrid.add_resource_to_tile will actually accept.
func _can_drop_on_tile(tile: Vector2i) -> bool:
	if not _grid_map.is_in_bounds(tile):
		return false
	if not _grid_map.is_passable(tile):
		return false
	if _grid_map.has_method("get_building") and _grid_map.get_building(tile) != "":
		return false
	return true
