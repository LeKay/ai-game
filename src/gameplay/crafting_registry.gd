extends Node
## CraftingRegistry — recipe definitions and instant-craft execution.
## Mirrors BuildingRegistry pattern: data constants + try_craft() execution method.

# ---- Enums ------------------------------------------------------------------

enum CraftResult {
	SUCCESS,
	INSUFFICIENT_RESOURCES,
	INSUFFICIENT_ENERGY,
	NO_STORAGE,
}

# ---- Recipe tables ----------------------------------------------------------

## recipe_id → material cost { resource_id: quantity }
const RECIPE_COST: Dictionary = {
	&"tool": {&"wood": 2, &"stone": 1, &"fiber": 1},
}

## recipe_id → flat energy cost
const RECIPE_ENERGY_COST: Dictionary = {
	&"tool": 15,
}

## recipe_id → output { resource_id: StringName, quantity: int }
const RECIPE_OUTPUT: Dictionary = {
	&"tool": {&"resource_id": &"tool", &"quantity": 1},
}

## recipe_id → display name (shown in CraftingGrid)
const RECIPE_DISPLAY_NAME: Dictionary = {
	&"tool": "Werkzeuge",
}

## Ordered list for display in CraftingGrid
const RECIPE_ORDER: Array[StringName] = [&"tool"]

# ---- Signals ----------------------------------------------------------------

## Emitted after a successful craft. Useful for HUD / feedback layers.
signal recipe_crafted(recipe_id: StringName, quantity: int)

# ---- Craft API --------------------------------------------------------------

## Attempts to craft recipe_id. On SUCCESS: resources deducted, energy deducted,
## output deposited into the first container with enough free slots.
## Returns a CraftResult value.
func try_craft(recipe_id: StringName) -> int:
	var cost: Dictionary        = RECIPE_COST.get(recipe_id, {})
	var energy_cost: int        = RECIPE_ENERGY_COST.get(recipe_id, 0)
	var output: Dictionary      = RECIPE_OUTPUT.get(recipe_id, {})

	# 1. Resource check
	for res_id: StringName in cost:
		if _get_total_resource(res_id) < cost[res_id]:
			return CraftResult.INSUFFICIENT_RESOURCES

	# 2. Energy check
	var player: Node = get_tree().get_first_node_in_group(&"player_character")
	if player != null and energy_cost > 0:
		if player.get_current_energy() < energy_cost:
			return CraftResult.INSUFFICIENT_ENERGY

	# 3. Storage check — need at least one free slot for the output
	var out_res: StringName = output.get(&"resource_id", &"")
	var out_qty: int        = output.get(&"quantity", 1)
	var target_id: StringName = _find_container_with_space(1)
	if target_id == &"":
		return CraftResult.NO_STORAGE

	# 4. Deduct resources
	for res_id: StringName in cost:
		_consume_resource_any(res_id, cost[res_id])

	# 5. Deduct energy
	if player != null and energy_cost > 0:
		player.consume_energy(energy_cost)

	# 6. Deposit output
	InventorySystem.try_deposit(target_id, out_res, out_qty)

	recipe_crafted.emit(recipe_id, out_qty)
	return CraftResult.SUCCESS

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
		if container.capacity - container.get_occupied_count() >= space:
			return container.container_id
	return &""
