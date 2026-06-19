extends Node
## HungerSystem — Autoload singleton for per-NPC daily food consumption and efficiency tracking.
## ADR: ADR-0010 (Hunger System and Debuff Stacking)
## Story: hunger-001 (Daily Consumption and State Machine)
##
## Food is manually assigned per NPC via the NPC detail UI. On each day transition
## the system tries to consume each NPC's assigned food from the global inventory.
## Efficiency is driven by TOTAL nutrition consumed (amount × food nutrition) through
## the curve eff = 0.25 + min(0.15 × nutrition, 0.75): unfed → 0.25, 5 nutrition → 1.0
## (5 berries == 1 bread == full). See EfficiencyFormulas.efficiency_from_nutrition / F5.

## Per-NPC food assignments: npc_id → { resource_id: StringName, amount: int }.
var _food_assignments: Dictionary = {}
## Per-NPC flag: was the assigned food actually consumed at the last day transition (UI active state).
var _last_consumed: Dictionary = {}

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

## True if the NPC's assigned food was successfully consumed at the last day transition (UI state).
func was_food_consumed(npc_id: StringName) -> bool:
	return _last_consumed.get(npc_id, false)

## True if at least one day transition has run for this NPC (i.e. _last_consumed has an entry).
func has_consumption_record(npc_id: StringName) -> bool:
	return _last_consumed.has(npc_id)

## Runs the daily consumption logic. Called by _on_day_transition; also callable directly for testing.
## For each NPC: tries to consume their assigned food from inventory (across all containers).
## On success: emits npc_food_efficiency_changed with the modifier for the consumed total nutrition.
## On failure or no assignment: emits the modifier for nutrition 0 (NPC drops to 25% efficiency).
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

		# TOTAL nutrition consumed = amount × food nutrition (5 berries == 1 bread == 100%).
		var consumed_nutrition: float = 0.0
		var did_consume: bool = false
		if food_id != &"" and _try_consume_across_containers(food_id, amount):
			did_consume = true
			consumed[food_id] = consumed.get(food_id, 0) + amount
			consumed_nutrition = _get_food_nutrition(food_id) * float(amount)
		_last_consumed[npc_id] = did_consume

		# Perk effects (#1 Genügsam: less nutrition needed; #9 Zäh: higher unfed floor;
		# #3 Meisterhand: raises the efficiency ceiling additively, like a level-up).
		var perk_nutrition: float = 0.0
		var floor_eff: float = 0.0
		var eff_cap_bonus: float = 0.0
		if _npc.has_method("npc_perk_bonus"):
			perk_nutrition = _npc.npc_perk_bonus(npc_id, PerkRegistry.EFFECT_NUTRITION_REDUCE)
			floor_eff = _npc.npc_perk_bonus(npc_id, PerkRegistry.EFFECT_UNFED_FLOOR)
			eff_cap_bonus = _npc.npc_perk_bonus(npc_id, PerkRegistry.EFFECT_NPC_EFF_CAP)

		# Level raises the reachable max efficiency by 5%/level; the extra ceiling must be filled
		# with more nutrition (Master's Touch adds to that same cap). 0 if level unknown.
		var level: int = 1
		var inst: Object = _npc.get_npc_instance(npc_id)
		if inst != null:
			level = int(inst.level)

		var modifier: float = EfficiencyFormulas.calculate_food_modifier(
				consumed_nutrition + perk_nutrition, level, eff_cap_bonus)
		if floor_eff > 0.0:
			modifier = maxf(modifier, floor_eff / EfficiencyFormulas.BASE_NPC_EFFICIENCY)
		npc_food_efficiency_changed.emit(npc_id, modifier)

	food_consumed_daily.emit(consumed)


## Consumes amount units of food_id across all storage containers in deterministic
## container-id order. All-or-nothing: returns false and consumes NOTHING when the
## total stock across containers is below amount. (Previously fed only from the first
## container holding the food — an NPC could starve while another container was full.)
func _try_consume_across_containers(food_id: StringName, amount: int) -> bool:
	var containers: Array = _inventory.get_all_containers()
	containers.sort_custom(func(a: Object, b: Object) -> bool:
		return str(a.container_id) < str(b.container_id))
	var total: int = 0
	for container: Object in containers:
		total += _inventory.get_resource_quantity(container.container_id, food_id)
	if total < amount:
		return false
	var remaining: int = amount
	for container: Object in containers:
		if remaining <= 0:
			break
		var available: int = _inventory.get_resource_quantity(container.container_id, food_id)
		if available <= 0:
			continue
		var to_consume: int = mini(available, remaining)
		_inventory.try_consume(container.container_id, food_id, to_consume)
		remaining -= to_consume
	return true

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
