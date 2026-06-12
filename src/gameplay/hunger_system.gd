extends Node
## HungerSystem — Autoload singleton for per-NPC daily food consumption and efficiency tracking.
## ADR: ADR-0010 (Hunger System and Debuff Stacking)
## Story: hunger-001 (Daily Consumption and State Machine)
##
## Food is manually assigned per NPC via the NPC detail UI. On each day transition
## the system tries to consume each NPC's assigned food from the global inventory.
## NPCs that receive food gain an efficiency boost; those that don't stay at base efficiency.
## No food assigned or insufficient food → food_modifier = 1.0 (NPC stays at 50% efficiency).
## 1 food unit consumed → food_modifier = 2.0 (100% efficiency). See EfficiencyFormulas.F5.

## Per-NPC food assignments: npc_id → { resource_id: StringName, amount: int }.
var _food_assignments: Dictionary = {}

## Emitted after day-transition consumption for each NPC whose modifier changed.
## food_modifier = EfficiencyFormulas.calculate_food_modifier(nutrition_of_one_ration).
signal npc_food_efficiency_changed(npc_id: StringName, food_modifier: float)
## Emitted after daily consumption with the items actually consumed: {resource_id: qty}.
## Used by DayLedger to track food consumption separately from general inventory deltas.
signal food_consumed_daily(items: Dictionary)

## Injected dependency references. Set from _enter_tree(); injectable for tests.
var _tick: Node = null
var _inventory: Node = null
var _npc: Node = null

func _enter_tree() -> void:
	_tick = TickSystem
	_inventory = InventorySystem
	_npc = NPCSystem
	_tick.day_transition.connect(_on_day_transition)
	npc_food_efficiency_changed.connect(_npc._on_npc_food_efficiency_changed)

func _exit_tree() -> void:
	if _tick != null and _tick.day_transition.is_connected(_on_day_transition):
		_tick.day_transition.disconnect(_on_day_transition)
	if _npc != null and npc_food_efficiency_changed.is_connected(_npc._on_npc_food_efficiency_changed):
		npc_food_efficiency_changed.disconnect(_npc._on_npc_food_efficiency_changed)

## Assigns a food item to an NPC. Preserves existing amount; defaults to 1 on first assignment.
func assign_food(npc_id: StringName, resource_id: StringName) -> void:
	var existing: Dictionary = _food_assignments.get(npc_id, {})
	_food_assignments[npc_id] = {
		&"resource_id": resource_id,
		&"amount": existing.get(&"amount", 1),
	}

## Returns the resource_id assigned to the NPC, or &"" if none assigned.
func get_assigned_food(npc_id: StringName) -> StringName:
	return (_food_assignments.get(npc_id, {}) as Dictionary).get(&"resource_id", &"")

## Sets the daily consumption amount for an NPC (minimum 1).
func set_food_amount(npc_id: StringName, amount: int) -> void:
	if not _food_assignments.has(npc_id):
		return
	(_food_assignments[npc_id] as Dictionary)[&"amount"] = maxi(amount, 1)

## Returns the daily consumption amount for an NPC (1 if not yet assigned).
func get_food_amount(npc_id: StringName) -> int:
	return (_food_assignments.get(npc_id, {}) as Dictionary).get(&"amount", 1)

## Removes the food assignment for an NPC.
func clear_food_assignment(npc_id: StringName) -> void:
	_food_assignments.erase(npc_id)

## Runs the daily consumption logic. Called by _on_day_transition; also callable directly for testing.
## For each NPC: tries to consume their assigned food from inventory.
## On success: emits npc_food_efficiency_changed with modifier = 1.0 + units_consumed.
## On failure or no assignment: emits modifier = 1.0 (NPC stays at base 50% efficiency).
func apply_daily_consumption() -> void:
	if _inventory == null or _npc == null:
		push_warning("HungerSystem: dependencies not ready — skipping consumption")
		return

	var npc_count: int = _npc.get_npc_count()
	if npc_count == 0:
		food_consumed_daily.emit({})
		return

	var consumed: Dictionary = {}
	for npc_id: StringName in _npc.all_npcs:
		var entry: Dictionary = _food_assignments.get(npc_id, {})
		var food_id: StringName = entry.get(&"resource_id", &"")
		var amount: int = entry.get(&"amount", 1)

		if food_id == &"":
			npc_food_efficiency_changed.emit(npc_id, EfficiencyFormulas.calculate_food_modifier(0.0))
			continue

		var container_id: StringName = _inventory.find_container_with(food_id)
		if container_id == &"":
			npc_food_efficiency_changed.emit(npc_id, EfficiencyFormulas.calculate_food_modifier(0.0))
			continue

		if _inventory.try_consume(container_id, food_id, amount) != InventoryContainer.ConsumeResult.SUCCESS:
			# Unfed → nutrition 0 → modifier for 0.25 efficiency (very inefficient, never frozen).
			npc_food_efficiency_changed.emit(npc_id, EfficiencyFormulas.calculate_food_modifier(0.0))
		else:
			consumed[food_id] = consumed.get(food_id, 0) + amount
			# Efficiency is driven by TOTAL nutrition consumed = amount × food nutrition.
			# So 5 berries (5×1) == 1 bread (1×5) == 100%; bread just needs fewer items.
			var total_nutrition: float = _get_food_nutrition(food_id) * float(amount)
			npc_food_efficiency_changed.emit(npc_id, EfficiencyFormulas.calculate_food_modifier(total_nutrition))

	food_consumed_daily.emit(consumed)

func _on_day_transition(_days_elapsed: int) -> void:
	apply_daily_consumption()


## Returns the nutrition value of a food resource from ResourceRegistry (0.0 if unknown).
func _get_food_nutrition(food_id: StringName) -> float:
	var def: Object = ResourceRegistry.get_definition(food_id)
	if def == null:
		return 0.0
	return def.nutrition


## Serialise food assignments to a JSON-compatible dictionary.
func serialize() -> Dictionary:
	var assignments: Dictionary = {}
	for npc_id: StringName in _food_assignments:
		var entry: Dictionary = _food_assignments[npc_id]
		assignments[str(npc_id)] = {
			"resource_id": str(entry.get(&"resource_id", &"")),
			"amount": entry.get(&"amount", 1),
		}
	return {"food_assignments": assignments}


## Restore food assignments from a previously serialised dictionary.
func deserialize(data: Dictionary) -> void:
	_food_assignments.clear()
	var assignments: Dictionary = data.get("food_assignments", {})
	for npc_id_str: String in assignments:
		var entry: Dictionary = assignments[npc_id_str]
		_food_assignments[StringName(npc_id_str)] = {
			&"resource_id": StringName(entry.get("resource_id", "")),
			&"amount": entry.get("amount", 1),
		}
