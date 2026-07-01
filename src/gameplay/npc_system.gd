extends Node
## NPCSystem — Autoload singleton for NPC identity tracking, recruitment, and task cycle.
## ADR: ADR-0009 (NPC State Machine and Movement)
## Stories: npc-001 (Identity and Recruitment) — TR-npc-001, TR-npc-004
##          npc-002 (Task Cycle — Travel and Work) — TR-npc-002, TR-npc-003
##          npc-003 (Deposit and Storage Coordination) — TR-npc-005
##          npc-004 (Disconnection and Demolition) — TR-npc-006

# ---- Constants ---------------------------------------------------------------

## Maximum NPCs allowed per Residential House.
const NPC_CAPACITY_PER_HOUSE: int = 2
## Ticks that must elapse after first recruitment before the second slot opens.
const NPC_SPAWN_DELAY_TICKS: int = 1000
## Base travel ticks per tile at 100% efficiency (matches LogisticsSystem). Travel is then
## scaled by the NPC's food-efficiency (F4). Anchored 2026-06-12 so 50% efficiency = 10/tile.
const TICKS_PER_TILE: int = 5
## Nutrition cost step per recruitment. Total cost scales with colony size (+5 nutrition per villager).
## Actual food amount = ceili(nutrition_cost / food.nutrition). berry(1)→5,10…; bread(5)→1,2…
const RECRUIT_COST_PER_NPC: int = 5

# ---- Enums -------------------------------------------------------------------

enum TaskState {
	IDLE,
	TRAVEL_TO_BUILDING,
	WORK_AT_BUILDING,
	TRAVEL_TO_STORAGE,
	DEPOSIT,
	RETURN_TO_BASE,
	WAITING,
}

## Result codes for assign_npc().
enum AssignmentResult {
	SUCCESS,
	INVALID_NPC_STATE,   ## NPC not found or not in IDLE state
	BUILDING_NOT_FOUND,  ## _building_system could not resolve the building tile
}

# ---- Inner classes -----------------------------------------------------------

## Per-NPC state container. One instance per NPC in the village.
class NPCInstance:
	var npc_id: StringName
	var position: Vector2i        ## current tile coordinates
	var home_base: Vector2i       ## residential house tile (set at recruitment)
	var state: int                ## TaskState
	## assignment data — &"" means unassigned
	var assigned_building_id: StringName = &""
	var assigned_storage_id: StringName = &""
	## travel state
	var travel_progress: int = 0
	var travel_destination: Vector2i
	var travel_ticks_total: int = 0
	## A* path for the current journey. Non-empty when grid is available; empty falls back to linear lerp.
	var travel_path: Array[Vector2i] = []
	## Whether the production cycle completed while the NPC was at the building.
	var work_cycle_complete: bool = false
	## Resource ID the NPC is carrying to deposit at assigned_storage_id.
	var current_output_resource: StringName = &""
	## Quantity the NPC is carrying to deposit.
	var current_output_amount: int = 0
	## Player-assigned display name. Empty string means use str(npc_id) as display name.
	var display_name: String = ""
	## Experience System (cosmetic at this scope — see design/gdd/experience-system.md).
	## Cumulative lifetime XP — only ever increases. Source of truth; `level` is derived from it.
	var xp: int = 0
	## Cached level in [1, ExperienceFormulas.MAX_LEVEL], derived from `xp` via F2.
	var level: int = 1
	## XP earned during the current day, not yet applied. Flushed into `xp` on day_transition.
	var pending_xp: int = 0
	## Perk System (design/perks/perk-catalog.md). Profession = a BuildingRegistry.BuildingType
	## the NPC specialised into; -1 = none. Permanent once set (via the Berufung perk).
	var profession: int = -1
	## Acquired perk instances. Each: {perk_id: StringName, good: StringName, building_type: int}.
	var perks: Array = []
	## Unresolved level-up perk choices, presented in the Day Overview before the next day starts.
	var pending_perk_choices: int = 0
	## Pre-rolled card sets — one Array[Dictionary] per pending choice, generated once at level-up
	## so closing the picker cannot reroll them. Not serialized as raw StringNames; use the
	## helper in NPCSystem. Falls back to live generation if empty (old save files).
	var pending_perk_cards: Array = []
	## Perk instances whose bound good was supplied this day (transient — recomputed each day_transition).
	## Only these grant their effect today. Not serialized.
	var active_perks: Array = []
	## Efficiency modifiers — written by external systems via signals (ADR-0012).
	var food_modifier: float = EfficiencyFormulas.calculate_food_modifier(0.0)  ## set by HungerSystem; default = unfed (0 nutrition)
	var satisfaction_modifier: float = 1.0  ## set by future SatisfactionSystem
	var equipment_modifier: float = 1.0     ## set by future EquipmentSystem
	## Computed efficiency [0.0–2.0]. Call recalculate_efficiency() after any modifier change.
	var efficiency: float = EfficiencyFormulas.calculate_npc_efficiency(
			EfficiencyFormulas.calculate_food_modifier(0.0), 1.0, 1.0)

	## Recomputes efficiency from current modifiers using F1 (ADR-0012).
	func recalculate_efficiency() -> void:
		efficiency = EfficiencyFormulas.calculate_npc_efficiency(
				food_modifier, satisfaction_modifier, equipment_modifier)

## Per-house recruitment tracking.
class _HouseState:
	var npc_ids: Array[StringName] = []
	## Tick count when the first NPC was recruited at this house (-1 = none yet).
	var first_recruit_tick: int = -1

# ---- Signals -----------------------------------------------------------------

## Emitted when a new NPC is successfully recruited.
signal npc_recruited(npc_id: StringName, home_base: Vector2i)
## Emitted when an NPC begins travel to an assigned building.
signal npc_assigned(npc_id: StringName, building_id: StringName)
## Emitted when an NPC is released from an assignment and returns home.
signal npc_released(npc_id: StringName)
## Emitted at the start of any travel segment (assign or return home).
signal npc_travel_started(npc_id: StringName, destination: Vector2i, ticks_total: int)
## Emitted when an NPC arrives at a travel destination.
signal npc_travel_completed(npc_id: StringName, destination: Vector2i)
## Emitted when an NPC returns to its home base tile and enters IDLE.
signal npc_returned_home(npc_id: StringName)
## Emitted when an NPC successfully deposits output at a storage building.
signal npc_deposit_completed(npc_id: StringName, storage_id: StringName)
## Emitted when an NPC arrives at storage but it is full — NPC enters WAITING state.
signal npc_storage_full(npc_id: StringName, storage_id: StringName)
## Emitted when an NPC is permanently removed from the game (house demolished, player confirmed).
signal npc_removed(npc_id: StringName)
## Emitted when an NPC's residential house is demolished; UI (Story 005) shows reassignment dialog.
signal house_demolished(npc_ids: Array[StringName])
## Emitted when the player renames an NPC.
signal npc_renamed(npc_id: StringName, new_name: String)
## Emitted on every XP grant (Experience System). xp_into_level / xp_span drive the UI bar (F3).
signal npc_xp_gained(npc_id: StringName, total_xp: int, xp_into_level: int, xp_span: int)
## Emitted only when an NPC's level actually increases. Drives the "Level Up!" map float and badges.
signal npc_leveled_up(npc_id: StringName, new_level: int)
## Emitted when a perk choice is applied to an NPC (Perk System). Drives UI refresh.
signal npc_perk_chosen(npc_id: StringName, perk_id: StringName)
## Emitted at the day transition with the perk bound-goods consumed that day: {resource_id: qty}.
## Mirrors HungerSystem.food_consumed_daily so the Day Overview can show perk upkeep as consumption.
signal perk_goods_consumed_daily(items: Dictionary)

# ---- State -------------------------------------------------------------------

## Central NPC registry. Keys: npc_id (StringName), Values: NPCInstance.
## Untyped Dictionary — inner classes are not usable as typed Dictionary value params in GDScript 4.x.
var all_npcs: Dictionary = {}
## Frozen per-NPC XP summary from the last completed day (Experience System). Each entry:
## {npc_id, display_name, xp_before, level_before, xp_gained, xp_after, level_after, leveled_up}.
## Read by the Day Overview Panel; populated on day_transition.
var _last_day_xp_summary: Array = []
## Per-house state. Keys: tile (Vector2i), Values: _HouseState.
var _house_registry: Dictionary = {}
## Monotonic NPC ID counter.
var _npc_counter: int = 0
## Internal tick counter — updated by _on_ticks_advanced().
var _current_tick: int = 0
## Injected reference to BuildingRegistry; acquired in _enter_tree(), injectable for tests.
var _building_system: Object = null
## Injected reference to InventorySystem; acquired in _enter_tree(), injectable for tests.
var _inventory_system: Object = null
## WorldGrid instance — injected via set_grid_map(). When null, pathfinding uses Manhattan fallback.
var _grid: Object = null

# ---- Lifecycle ---------------------------------------------------------------

func _enter_tree() -> void:
	TickSystem.ticks_advanced.connect(_on_ticks_advanced)
	# Experience: accrued XP is flushed into NPC levels at the day boundary (autoload connects
	# before the Day Overview Panel, so the summary is ready when the panel reads it).
	TickSystem.day_transition.connect(_on_day_transition)
	_building_system = BuildingRegistry
	_building_system.building_demolished.connect(_on_building_demolished)
	# Experience: a building's assigned worker accrues XP each time a production cycle completes.
	_building_system.production_output_ready.connect(_on_production_output_ready)

	_inventory_system = InventorySystem
	if _inventory_system != null:
		_inventory_system.storage_changed.connect(_on_storage_changed)
		_inventory_system.container_removed.connect(_on_container_removed)
	else:
		push_warning("NPCSystem: InventorySystem not available — deposits will be skipped")


## Injects the WorldGrid instance for A* pathfinding. Call from scene setup after nodes are ready.
func set_grid_map(grid: Object) -> void:
	_grid = grid


func _exit_tree() -> void:
	if _building_system != null and _building_system.building_demolished.is_connected(_on_building_demolished):
		_building_system.building_demolished.disconnect(_on_building_demolished)
	if _building_system != null and _building_system.production_output_ready.is_connected(_on_production_output_ready):
		_building_system.production_output_ready.disconnect(_on_production_output_ready)
	if _inventory_system != null:
		if _inventory_system.storage_changed.is_connected(_on_storage_changed):
			_inventory_system.storage_changed.disconnect(_on_storage_changed)
		if _inventory_system.container_removed.is_connected(_on_container_removed):
			_inventory_system.container_removed.disconnect(_on_container_removed)

# ---- Public API --------------------------------------------------------------

## Creates a new NPC in IDLE state at home_base and registers it to that house.
## Enforces NPC_CAPACITY_PER_HOUSE and NPC_SPAWN_DELAY_TICKS for the second slot.
## resource_id must be a food resource (nutrition > 0). Returns &"" if blocked.
func recruit_npc(home_base: Vector2i, resource_id: StringName) -> StringName:
	var house := _get_or_create_house(home_base)

	if house.npc_ids.size() >= NPC_CAPACITY_PER_HOUSE:
		return &""

	var amount: int = get_recruit_amount_for_resource(resource_id)
	if not _pay_recruit_cost(resource_id, amount):
		return &""

	if house.npc_ids.is_empty():
		house.first_recruit_tick = _current_tick

	var npc_id := StringName("npc_%d" % _npc_counter)
	_npc_counter += 1

	var npc := NPCInstance.new()
	npc.npc_id = npc_id
	npc.position = home_base
	npc.home_base = home_base
	npc.state = TaskState.IDLE
	npc.travel_progress = 0
	npc.travel_ticks_total = 0

	all_npcs[npc_id] = npc
	house.npc_ids.append(npc_id)

	npc_recruited.emit(npc_id, home_base)
	return npc_id

## Nutrition units needed for the next recruitment. Scales with the whole colony:
## nutrition_cost = RECRUIT_COST_PER_NPC × (current NPC count + 1) → 5, 10, 15, …
func get_recruit_nutrition_cost() -> float:
	return float(RECRUIT_COST_PER_NPC * (get_npc_count() + 1))

## Amount of resource_id needed to recruit the next villager.
## Returns 0 when resource_id has no nutrition (i.e. is not edible food).
func get_recruit_amount_for_resource(resource_id: StringName) -> int:
	var nutrition: float = ResourceRegistry.get_nutrition(resource_id)
	if nutrition <= 0.0:
		return 0
	return ceili(get_recruit_nutrition_cost() / nutrition)

## True when the colony holds enough of resource_id to pay for the next recruitment.
## Returns true when no inventory is wired (e.g. unit tests) so recruitment stays usable.
func can_afford_recruit_with(resource_id: StringName) -> bool:
	if _inventory_system == null:
		return true
	var amount: int = get_recruit_amount_for_resource(resource_id)
	if amount <= 0:
		return false
	return _inventory_system.get_global_quantity(resource_id) >= amount

## Consumes `amount` of `resource_id` spread across all storage containers.
## Returns false (no change) when the colony cannot pay. Null inventory recruits for free.
func _pay_recruit_cost(resource_id: StringName, amount: int) -> bool:
	if amount <= 0 or _inventory_system == null:
		return true
	if _inventory_system.get_global_quantity(resource_id) < amount:
		return false
	var remaining: int = amount
	for container: Object in _inventory_system.get_all_containers():
		if remaining <= 0:
			break
		var available: int = _inventory_system.get_resource_quantity(
				container.container_id, resource_id)
		if available <= 0:
			continue
		var take: int = mini(available, remaining)
		_inventory_system.try_consume(container.container_id, resource_id, take)
		remaining -= take
	return true

## Returns the number of NPCs registered to the given house tile.
func get_house_npc_count(home_base: Vector2i) -> int:
	var house: _HouseState = _house_registry.get(home_base)
	if house == null:
		return 0
	return house.npc_ids.size()

## Returns the total number of registered NPCs across all houses.
func get_npc_count() -> int:
	return all_npcs.size()

## Returns a copy of the NPC IDs registered to the given house tile.
func get_house_npcs(home_base: Vector2i) -> Array[StringName]:
	var house: _HouseState = _house_registry.get(home_base)
	if house == null:
		return []
	return house.npc_ids.duplicate()

## Returns all NPC IDs currently in IDLE state and not already serving as a carrier.
func get_available_npcs() -> Array[StringName]:
	var on_route: Dictionary = {}
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		if route.npc_id != &"":
			on_route[route.npc_id] = true
	var result: Array[StringName] = []
	for npc: NPCInstance in all_npcs.values():
		if npc.state == TaskState.IDLE and not on_route.has(npc.npc_id):
			result.append(npc.npc_id)
	return result


## Returns NPC IDs eligible to be a route carrier: idle non-workers PLUS NPCs already serving
## as carriers (so one carrier can be assigned to multiple routes — shared-carrier model).
func get_carrier_candidates() -> Array[StringName]:
	var on_route: Dictionary = {}
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		if route.npc_id != &"":
			on_route[route.npc_id] = true
	var result: Array[StringName] = []
	for npc: NPCInstance in all_npcs.values():
		if on_route.has(npc.npc_id):
			result.append(npc.npc_id)  # existing carrier — can take on more routes
		elif npc.state == TaskState.IDLE and npc.assigned_building_id == &"":
			result.append(npc.npc_id)  # idle, not a building worker — free to become a carrier
	return result

## Returns the TaskState of the given NPC, or -1 if not found.
func get_npc_state(npc_id: StringName) -> int:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return -1
	return npc.state

## Returns the NPCInstance for the given NPC ID, or null if not found.
func get_npc_instance(npc_id: StringName) -> NPCInstance:
	var npc: NPCInstance = all_npcs.get(npc_id)
	return npc


## Returns the display name for an NPC: display_name if set, otherwise str(npc_id).
func get_npc_display_name(npc_id: StringName) -> String:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return str(npc_id)
	if npc.display_name != "":
		return npc.display_name
	return str(npc_id)


## Returns a human-readable job label for an NPC, derived from what they currently do.
## Priority: active building assignment → logistics carrier → chosen profession → unemployed.
## Job labels live in BuildingRegistry.BUILDING_JOB_NAMES (the building data structure).
func get_npc_job_name(npc_id: StringName) -> String:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return ""
	if npc.assigned_building_id != &"" and _building_system != null:
		var inst: Object = _building_system.get_building_instance(str(npc.assigned_building_id))
		if inst != null:
			return BuildingRegistry.BUILDING_JOB_NAMES.get(inst.type, "Worker")
	for route: LogisticsRoute in LogisticsSystem.get_active_routes():
		if route.npc_id == npc_id:
			return "Carrier"
	if npc.profession == PerkRegistry.PROFESSION_CARRIER:
		return "Carrier"
	elif npc.profession != -1:
		return BuildingRegistry.BUILDING_JOB_NAMES.get(npc.profession, "Worker")
	return "Unemployed"


## Sets a player-defined display name for an NPC. Pass "" to revert to the generated ID.
## Emits npc_renamed on success.
func rename_npc(npc_id: StringName, new_name: String) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return
	npc.display_name = new_name.strip_edges()
	npc_renamed.emit(npc_id, npc.display_name)


## Grants XP to an NPC and resolves level-ups (Experience System, Rule 3).
## `amount` <= 0 and unknown NPCs are no-ops. Emits npc_xp_gained on every grant; emits
## npc_leveled_up only when the derived level increases (capped at MAX_LEVEL). XP is cosmetic
## at this scope — it applies no gameplay modifier (see design/gdd/experience-system.md Rule 5).
func grant_xp(npc_id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return
	# The progression-tree Leadership branch caps how high an NPC may level. XP accrues normally up
	# to a full bar at the cap level, then stops banking — the NPC holds there until the player
	# raises the cap (then levels up manually via the ⬆️ button). See get_npc_level_cap().
	var cap: int = ProgressionSystem.get_npc_level_cap()
	npc.xp += amount
	var natural_level: int = ExperienceFormulas.level_for_total_xp(npc.xp)
	if natural_level > cap and cap < ExperienceFormulas.MAX_LEVEL:
		npc.xp = mini(npc.xp, ExperienceFormulas.cumulative_xp(cap + 1))
	var old_level: int = npc.level
	npc.level = mini(natural_level, cap)
	npc_xp_gained.emit(npc_id, npc.xp,
			ExperienceFormulas.xp_into_level(npc.xp, npc.level),
			ExperienceFormulas.xp_span_of_level(npc.level))
	if npc.level > old_level:
		# Each level gained queues one perk choice, resolved via the ⬆️ button (Perk System).
		var levels_gained: int = npc.level - old_level
		npc.pending_perk_choices += levels_gained
		for _i: int in levels_gained:
			npc.pending_perk_cards.append(PerkRegistry.generate_choices(npc, 3))
		npc_leveled_up.emit(npc_id, npc.level)


## True when an NPC has banked a full XP bar but is held below the progression-tree level cap —
## i.e. it can be manually advanced now that the player has (or could) raise the cap. Drives the
## ⬆️ "level up" button in the Day Overview and NPC detail panel.
func can_level_up(npc_id: StringName) -> bool:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return false
	if npc.level >= ExperienceFormulas.MAX_LEVEL:
		return false
	if npc.level >= ProgressionSystem.get_npc_level_cap():
		return false
	return npc.xp >= ExperienceFormulas.cumulative_xp(npc.level + 1)


## Manually advances a held NPC one level (player clicked the ⬆️ button) and queues its perk choice.
## No-op (returns false) unless can_level_up() holds. Because banked XP is clamped to one bar above
## the previous cap, this advances exactly one level per cap raise.
func level_up(npc_id: StringName) -> bool:
	if not can_level_up(npc_id):
		return false
	var npc: NPCInstance = all_npcs.get(npc_id)
	npc.level += 1
	npc.pending_perk_choices += 1
	npc.pending_perk_cards.append(PerkRegistry.generate_choices(npc, 3))
	npc_leveled_up.emit(npc_id, npc.level)
	return true


## Applies a chosen perk card to an NPC (Perk System). Adds the perk instance, sets the profession
## if it is a Berufung card, and decrements the NPC's pending choice count. `card` is a Dictionary
## from PerkRegistry.generate_choices. No-op if the NPC has no pending choices.
func apply_perk_choice(npc_id: StringName, card: Dictionary) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null or npc.pending_perk_choices <= 0:
		return
	var perk_id: StringName = card.get(&"perk_id", &"")
	var def: Dictionary = PerkRegistry.get_def(perk_id)
	npc.perks.append({
		&"perk_id": perk_id,
		&"good": card.get(&"good", &""),
		&"building_type": int(card.get(&"building_type", -1)),
		# Assigned daily units (player-adjustable, like food). Defaults to 0 — the perk starts
		# disabled (consumes nothing) and must be switched on manually in the NPC detail panel.
		&"amount": 0,
	})
	if def.get("is_profession", false):
		npc.profession = int(card.get(&"building_type", -1))
	npc.pending_perk_choices -= 1
	if not npc.pending_perk_cards.is_empty():
		npc.pending_perk_cards.pop_front()
	npc_perk_chosen.emit(npc_id, perk_id)


## Decrements a pending perk choice without granting a perk (used when no valid cards can be
## generated, e.g. no perk-eligible goods exist yet) — prevents the "next day" gate from soft-locking.
func skip_perk_choice(npc_id: StringName) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc != null and npc.pending_perk_choices > 0:
		npc.pending_perk_choices -= 1
		if not npc.pending_perk_cards.is_empty():
			npc.pending_perk_cards.pop_front()


## Pre-rolled cards for the NPC's next pending perk choice, or [] if none / unknown.
## Falls back to live generation when the cache is empty (e.g. old save files).
func get_pending_perk_cards(npc_id: StringName) -> Array:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null or npc.pending_perk_choices <= 0:
		return []
	if not npc.pending_perk_cards.is_empty():
		return npc.pending_perk_cards[0]
	# Fallback for old saves: generate live and cache so subsequent opens are stable.
	var cards: Array = PerkRegistry.generate_choices(npc, 3)
	npc.pending_perk_cards.append(cards)
	return cards


## Unresolved perk choices owed by a single NPC (drives the per-NPC ⬆️ button in the Day Overview
## and the NPC detail panel). 0 for unknown NPCs.
func get_pending_perk_choices(npc_id: StringName) -> int:
	var npc: NPCInstance = all_npcs.get(npc_id)
	return npc.pending_perk_choices if npc != null else 0


## Total unresolved perk choices across all NPCs.
func get_total_pending_perk_choices() -> int:
	var total: int = 0
	for npc: NPCInstance in all_npcs.values():
		total += npc.pending_perk_choices
	return total


## Sets the daily consumption amount for the perk at `index` on an NPC (like food amount).
## Clamped to [0, required]: 0 disables the perk (consumes nothing, same as food set to 0),
## and the perk's required amount is the ceiling — assigning more than it needs is pointless.
func set_perk_amount(npc_id: StringName, index: int, amount: int) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null or index < 0 or index >= npc.perks.size():
		return
	var perk: Dictionary = npc.perks[index]
	var required: int = int(PerkRegistry.get_def(perk.get(&"perk_id", &"")).get("required", 1))
	perk[&"amount"] = clampi(amount, 0, maxi(required, 0))


## Immediately consumes one perk's bound good from inventory and activates the perk for the rest of
## the current day, without waiting for the day transition. Mirrors HungerSystem.feed_npc_now — the
## daily resolution (_refresh_active_perks) still runs independently at the next day change. Returns
## true on success. No-op (false) when: unknown NPC/index, the perk is already active, it has no
## bound good, the assigned amount is below the requirement, or the good is out of stock.
func consume_perk_now(npc_id: StringName, index: int) -> bool:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null or index < 0 or index >= npc.perks.size():
		return false
	var perk: Dictionary = npc.perks[index]
	if bool(perk.get(&"active", false)):
		return false
	var good: StringName = perk.get(&"good", &"")
	if good == &"":
		return false
	var required: int = int(PerkRegistry.get_def(perk.get(&"perk_id", &"")).get("required", 1))
	var assigned: int = int(perk.get(&"amount", 1))
	if assigned < required:
		return false
	if not _consume_good_amount(good, assigned):
		return false
	# Inactive perks are never in active_perks (it is rebuilt active-only each day), so a plain
	# append is safe — no duplicate guard needed.
	perk[&"active"] = true
	npc.active_perks.append(perk)
	npc.recalculate_efficiency()
	return true


## Returns NPC IDs that still have at least one unresolved perk choice.
func get_npcs_with_pending_perk_choices() -> Array[StringName]:
	var result: Array[StringName] = []
	for npc: NPCInstance in all_npcs.values():
		if npc.pending_perk_choices > 0:
			result.append(npc.npc_id)
	return result


## Accrues XP toward the current day's total without applying it (Experience System).
## Accrued XP is flushed into `xp`/`level` at the next day_transition (_on_day_transition).
## `amount` <= 0 and unknown NPCs are no-ops.
func add_pending_xp(npc_id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return
	npc.pending_xp += amount


## Flushes each NPC's accrued daily XP into its level at the day boundary and records a
## per-NPC summary for the Day Overview Panel. Subscribed to TickSystem.day_transition.
## First consumes each NPC's perk goods to fix the day's active-perk set (Perk System), then
## applies perk XP multipliers (Lernbegierig / Lehrmeister / Berufung) to the flushed XP.
func _on_day_transition(_days: int) -> void:
	_refresh_active_perks()
	var summary: Array = []
	for npc: NPCInstance in all_npcs.values():
		if npc.pending_xp <= 0:
			continue
		var raw: int = npc.pending_xp
		var gained: int = int(round(float(raw) * _effective_xp_multiplier(npc)))
		var xp_before: int = npc.xp
		var level_before: int = npc.level
		npc.pending_xp = 0
		grant_xp(npc.npc_id, gained)  # applies XP, updates level, emits signals
		summary.append({
			&"npc_id": npc.npc_id,
			&"display_name": get_npc_display_name(npc.npc_id),
			&"xp_before": xp_before,
			&"level_before": level_before,
			&"xp_gained": gained,
			&"xp_after": npc.xp,
			&"level_after": npc.level,
			&"leveled_up": npc.level > level_before,
		})
	_last_day_xp_summary = summary


# ---- Perk System: daily active-perk resolution + effect queries ---------------

## Consumes one unit of each perk's bound good and records the perks that were supplied today
## into npc.active_perks. Perks whose good is out of stock are inactive (no effect) that day.
func _refresh_active_perks() -> void:
	var consumed: Dictionary = {}  # {good: total qty consumed this day} — for the Day Overview
	for npc: NPCInstance in all_npcs.values():
		npc.active_perks = []
		for perk: Dictionary in npc.perks:
			var good: StringName = perk.get(&"good", &"")
			var required: int = int(PerkRegistry.get_def(perk.get(&"perk_id", &"")).get("required", 1))
			var assigned: int = int(perk.get(&"amount", 1))
			# Binary (no partial): active only if the assigned amount meets the requirement AND is
			# available to consume. Under-assigning leaves the perk off and consumes nothing.
			var active: bool = false
			if good == &"":
				active = true
			elif assigned >= required:
				active = _consume_good_amount(good, assigned)
				if active:
					consumed[good] = int(consumed.get(good, 0)) + assigned
			perk[&"active"] = active  # transient flag for the UI
			if active:
				npc.active_perks.append(perk)
		# Perk #3 (Meisterhand) now raises the efficiency ceiling additively via the nutrition cap
		# (HungerSystem folds EFFECT_NPC_EFF_CAP into calculate_food_modifier), just like a level-up —
		# the higher max must be filled with more food. satisfaction_modifier stays a neutral
		# placeholder for the future Satisfaction System. HungerSystem re-emits food modifiers right
		# after (autoload order); recalc here too so efficiency is correct meanwhile.
		npc.satisfaction_modifier = 1.0
		npc.recalculate_efficiency()
	perk_goods_consumed_daily.emit(consumed)


## Consumes `amount` units of `good` across storage containers (all-or-nothing). Returns success.
func _consume_good_amount(good: StringName, amount: int) -> bool:
	if _inventory_system == null or good == &"" or amount <= 0:
		return false
	var containers: Array = _inventory_system.get_all_containers()
	var total: int = 0
	for c: Object in containers:
		total += _inventory_system.get_resource_quantity(c.container_id, good)
	if total < amount:
		return false
	var remaining: int = amount
	for c: Object in containers:
		if remaining <= 0:
			break
		var avail: int = _inventory_system.get_resource_quantity(c.container_id, good)
		if avail <= 0:
			continue
		var take: int = mini(avail, remaining)
		_inventory_system.try_consume(c.container_id, good, take)
		remaining -= take
	return true


## Combined XP multiplier for an NPC from its own active XP perks plus housemates' Lehrmeister.
func _effective_xp_multiplier(npc: NPCInstance) -> float:
	var mult: float = 1.0
	for perk: Dictionary in npc.active_perks:
		var def: Dictionary = PerkRegistry.get_def(perk.get(&"perk_id", &""))
		var effect: StringName = def.get("effect", &"")
		if effect == PerkRegistry.EFFECT_XP_SELF or effect == PerkRegistry.EFFECT_PROFESSION_XP:
			mult += float(def.get("magnitude", 0.0))
	# Housemate mentors (Lehrmeister) boost this NPC's XP.
	var house: _HouseState = _house_registry.get(npc.home_base)
	if house != null:
		for mate_id: StringName in house.npc_ids:
			if mate_id == npc.npc_id:
				continue
			var mate: NPCInstance = all_npcs.get(mate_id)
			if mate == null:
				continue
			for perk: Dictionary in mate.active_perks:
				var def: Dictionary = PerkRegistry.get_def(perk.get(&"perk_id", &""))
				if def.get("effect", &"") == PerkRegistry.EFFECT_XP_HOUSEMATE:
					mult += float(def.get("magnitude", 0.0))
	return mult


## Sum of magnitudes of this NPC's active perks with the given effect (0.0 if none / unknown NPC).
## Checks both primary ("effect"/"magnitude") and optional secondary ("secondary_effect"/"secondary_magnitude").
func npc_perk_bonus(npc_id: StringName, effect: StringName) -> float:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return 0.0
	var total: float = 0.0
	for perk: Dictionary in npc.active_perks:
		var def: Dictionary = PerkRegistry.get_def(perk.get(&"perk_id", &""))
		if def.get("effect", &"") == effect:
			total += float(def.get("magnitude", 0.0))
		if def.get("secondary_effect", &"") == effect:
			total += float(def.get("secondary_magnitude", 0.0))
	return total


## Sum of magnitudes of all active perks (across every NPC) that are bound to `building_type`
## and have the given effect. Checks primary and secondary effect fields.
func building_perk_bonus(building_type: int, effect: StringName) -> float:
	var total: float = 0.0
	for npc: NPCInstance in all_npcs.values():
		for perk: Dictionary in npc.active_perks:
			if int(perk.get(&"building_type", -1)) != building_type:
				continue
			var def: Dictionary = PerkRegistry.get_def(perk.get(&"perk_id", &""))
			if def.get("effect", &"") == effect:
				total += float(def.get("magnitude", 0.0))
			if def.get("secondary_effect", &"") == effect:
				total += float(def.get("secondary_magnitude", 0.0))
	return total


## True if any active perk bound to `building_type` has the given effect (primary or secondary).
func building_has_active_perk(building_type: int, effect: StringName) -> bool:
	for npc: NPCInstance in all_npcs.values():
		for perk: Dictionary in npc.active_perks:
			if int(perk.get(&"building_type", -1)) != building_type:
				continue
			var def: Dictionary = PerkRegistry.get_def(perk.get(&"perk_id", &""))
			if def.get("effect", &"") == effect or def.get("secondary_effect", &"") == effect:
				return true
	return false


## Returns the frozen per-NPC XP summary from the last completed day (see _last_day_xp_summary).
## Empty before the first day completes or when no NPC gained XP.
func get_last_day_xp_summary() -> Array:
	return _last_day_xp_summary


## Returns the tile position of the given NPC, or Vector2i(-1, -1) if not found.
func get_npc_position(npc_id: StringName) -> Vector2i:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return Vector2i(-1, -1)
	return npc.position

## Returns the npc_id of the NPC assigned to building_id, or &"" if none.
func get_assigned_npc(building_id: StringName) -> StringName:
	for npc: NPCInstance in all_npcs.values():
		if npc.assigned_building_id == building_id:
			return npc.npc_id
	return &""

## Assigns an idle NPC to a production building. Requires _building_system to be set.
## Returns AssignmentResult.SUCCESS on success, or an error code if blocked.
func assign_npc(npc_id: StringName, building_id: StringName, storage_id: StringName) -> AssignmentResult:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null or npc.state != TaskState.IDLE:
		return AssignmentResult.INVALID_NPC_STATE

	if _building_system == null:
		return AssignmentResult.BUILDING_NOT_FOUND
	var building_tile: Vector2i = _building_system.get_building_tile(building_id)
	if building_tile == Vector2i(-1, -1):
		return AssignmentResult.BUILDING_NOT_FOUND

	var travel_ticks := _compute_travel_path(npc, npc.position, building_tile)

	npc.assigned_building_id = building_id
	npc.assigned_storage_id = storage_id
	npc.travel_destination = building_tile
	npc.travel_ticks_total = travel_ticks
	npc.travel_progress = 0
	npc.state = TaskState.TRAVEL_TO_BUILDING

	_building_system.assign_npc(str(building_id), npc_id)

	npc_assigned.emit(npc_id, building_id)
	npc_travel_started.emit(npc_id, building_tile, travel_ticks)
	return AssignmentResult.SUCCESS

## Releases an NPC from its current assignment and sends it home.
## If already at home, transitions directly to IDLE.
## NOTE: position is the last *confirmed* tile (updated on arrival), not the in-flight tile.
## Calling release on a TRAVEL_TO_BUILDING NPC returns it from its previous confirmed position.
func release_npc(npc_id: StringName) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return

	var prev_building: StringName = npc.assigned_building_id
	npc.assigned_building_id = &""
	npc.assigned_storage_id = &""

	var home_tile := npc.home_base
	if npc.position != home_tile:
		var return_ticks := _compute_travel_path(npc, npc.position, home_tile)
		npc.travel_destination = home_tile
		npc.travel_ticks_total = return_ticks
		npc.travel_progress = 0
		npc.state = TaskState.RETURN_TO_BASE
		npc_travel_started.emit(npc_id, home_tile, return_ticks)
	else:
		npc.state = TaskState.IDLE

	if _building_system != null and prev_building != &"":
		_building_system.assign_npc(str(prev_building), &"")

	npc_released.emit(npc_id)

# ---- Logistics carrier interface (ADR-0011) ----------------------------------

## Called by LogisticsSystem on carrier state transitions only (not per-tick).
## Overwrites the NPC's TaskState to match the carrier FSM state per ADR-0011 mapping.
func set_carrier_state(npc_id: StringName, carrier_state: int) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return
	# Carrier FSM state → NPC TaskState mapping (ADR-0011 Table)
	match carrier_state:
		LogisticsRoute.CarrierState.IDLE:
			npc.state = TaskState.IDLE
		LogisticsRoute.CarrierState.TRAVEL_TO_SOURCE:
			npc.state = TaskState.TRAVEL_TO_BUILDING
		LogisticsRoute.CarrierState.AT_SOURCE:
			npc.state = TaskState.WORK_AT_BUILDING
		LogisticsRoute.CarrierState.WAITING_SOURCE:
			npc.state = TaskState.WAITING
		LogisticsRoute.CarrierState.TRAVEL_TO_DESTINATION:
			npc.state = TaskState.TRAVEL_TO_STORAGE
		LogisticsRoute.CarrierState.AT_DESTINATION:
			npc.state = TaskState.DEPOSIT
		LogisticsRoute.CarrierState.WAITING_DESTINATION:
			npc.state = TaskState.WAITING
		LogisticsRoute.CarrierState.RETURN_HOME:
			npc.state = TaskState.RETURN_TO_BASE


## Returns true if the NPC is available for carrier assignment (state == IDLE).
func is_available(npc_id: StringName) -> bool:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return false
	return npc.state == TaskState.IDLE


## Notifies the NPC system that a carrier NPC has arrived at a building location.
## Triggers any arrival-side NPC logic (visual update, event hooks).
func on_npc_at_location(npc_id: StringName, building_id: StringName) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return
	npc.position = _building_system.get_building_tile(str(building_id)) \
		if _building_system != null else npc.position

# ---- Tick subscription -------------------------------------------------------

## Advances the internal tick counter and all active travel timers.
## Subscribed to TickSystem.ticks_advanced.
## NOTE: iterates a snapshot of all_npcs.values(). Signal handlers that call
## recruit_npc() during iteration will not affect the current tick's loop.
func _on_ticks_advanced(delta: int) -> void:
	_current_tick += delta
	for npc: NPCInstance in all_npcs.values():
		match npc.state:
			TaskState.TRAVEL_TO_BUILDING:
				npc.travel_progress += delta
				if npc.travel_progress >= npc.travel_ticks_total:
					_npc_arrived_at_building(npc)
			TaskState.TRAVEL_TO_STORAGE:
				npc.travel_progress += delta
				if npc.travel_progress >= npc.travel_ticks_total:
					_npc_arrived_at_storage(npc)
			TaskState.RETURN_TO_BASE:
				npc.travel_progress += delta
				if npc.travel_progress >= npc.travel_ticks_total:
					_npc_returned_home_internal(npc)
			_:
				pass  # IDLE, WORK_AT_BUILDING, DEPOSIT, WAITING — no timer work

# ---- Private helpers ---------------------------------------------------------

func _get_or_create_house(home_base: Vector2i) -> _HouseState:
	if not _house_registry.has(home_base):
		_house_registry[home_base] = _HouseState.new()
	return _house_registry[home_base]

## Computes the A* path from `from` to `to`, stores it in npc.travel_path, and returns total ticks.
## Falls back to a straight two-tile path + Manhattan time when no grid or no viable path.
func _compute_travel_path(npc: NPCInstance, from: Vector2i, to: Vector2i) -> int:
	if from == to:
		npc.travel_path = [to]
		return 0
	# F4 (balancing 2026-06-11): travel scales with the NPC's food-efficiency — a hungry
	# worker walks slowly; effective = floor(base / efficiency).
	var eff: float = npc.efficiency if npc.efficiency > 0.0 else 1.0
	if _grid != null:
		var result: PathResult = LogisticsPathfinder.find_path(from, to, _grid)
		if result.found and result.path.size() >= 2:
			npc.travel_path = result.path
			var base_ticks: int = maxi(1, int(floor(result.cost * TICKS_PER_TILE)))
			return EfficiencyFormulas.calculate_effective_travel_ticks(base_ticks, eff)
	npc.travel_path = [from, to]
	var manhattan: int = (absi(to.x - from.x) + absi(to.y - from.y)) * TICKS_PER_TILE
	return EfficiencyFormulas.calculate_effective_travel_ticks(maxi(1, manhattan), eff)

func _npc_arrived_at_building(npc: NPCInstance) -> void:
	npc.position = npc.travel_destination
	npc.travel_progress = 0
	npc.state = TaskState.WORK_AT_BUILDING
	npc_travel_completed.emit(npc.npc_id, npc.travel_destination)

func _npc_returned_home_internal(npc: NPCInstance) -> void:
	npc.position = npc.home_base
	npc.travel_progress = 0
	npc.travel_ticks_total = 0
	npc.state = TaskState.IDLE
	npc_travel_completed.emit(npc.npc_id, npc.home_base)
	npc_returned_home.emit(npc.npc_id)

## Called when an NPC completes travel to the storage building.
## Attempts deposit via InventorySystem; transitions to WAITING if full, RETURN_TO_BASE if success.
func _npc_arrived_at_storage(npc: NPCInstance) -> void:
	npc.position = npc.travel_destination
	npc.travel_progress = 0
	npc.state = TaskState.DEPOSIT
	npc_travel_completed.emit(npc.npc_id, npc.travel_destination)

	if _inventory_system == null:
		push_warning("NPCSystem: no InventorySystem — skipping deposit for %s" % npc.npc_id)
		_begin_return_to_base(npc)
		return

	var result: int = _inventory_system.try_deposit(
		npc.assigned_storage_id, npc.current_output_resource, npc.current_output_amount)
	if result == InventoryContainer.DepositResult.SUCCESS:
		npc_deposit_completed.emit(npc.npc_id, npc.assigned_storage_id)
		_begin_return_to_base(npc)
	elif result == InventoryContainer.DepositResult.FAILURE_FULL:
		npc.state = TaskState.WAITING
		npc_storage_full.emit(npc.npc_id, npc.assigned_storage_id)
	else:
		push_warning("NPCSystem: deposit failed (code %d) for %s — returning home" % [result, npc.npc_id])
		_begin_return_to_base(npc)

## Called when InventorySystem emits storage_changed. Retries deposit for all WAITING NPCs
## whose assigned storage matches container_id. Breaks after first success (VS: 1 carrier per building).
func _on_storage_changed(container_id: StringName) -> void:
	for npc: NPCInstance in all_npcs.values():
		if npc.assigned_storage_id == container_id and npc.state == TaskState.WAITING:
			var result: int = _inventory_system.try_deposit(
				container_id, npc.current_output_resource, npc.current_output_amount)
			if result == InventoryContainer.DepositResult.SUCCESS:
				npc_deposit_completed.emit(npc.npc_id, container_id)
				_begin_return_to_base(npc)
				break

## Starts RETURN_TO_BASE travel from the NPC's current position to their home tile.
## If already at home, transitions directly to IDLE without emitting npc_travel_started.
func _begin_return_to_base(npc: NPCInstance) -> void:
	var home_tile := npc.home_base
	if npc.position == home_tile:
		npc.state = TaskState.IDLE
		return
	var return_ticks := _compute_travel_path(npc, npc.position, home_tile)
	npc.travel_destination = home_tile
	npc.travel_ticks_total = return_ticks
	npc.travel_progress = 0
	npc.state = TaskState.RETURN_TO_BASE
	npc_travel_started.emit(npc.npc_id, home_tile, return_ticks)

## Called when BuildingRegistry emits production_output_ready (a production cycle completed).
## Accrues daily work XP (Experience System) to the worker assigned to that building, if any.
## XP is time-based: proportional to the cycle's nominal duration (`cycle_ticks`), so a short-cycle
## building no longer levels its worker faster than a slow one for the same working time.
## Buildings producing without an assigned worker (e.g. unstaffed gathering) accrue nothing.
func _on_production_output_ready(building_id: String, _output: Dictionary, cycle_ticks: int) -> void:
	var npc_id: StringName = get_assigned_npc(StringName(building_id))
	if npc_id != &"":
		add_pending_xp(npc_id, ExperienceFormulas.xp_for_production(cycle_ticks))


## Called when BuildingRegistry emits building_demolished. Releases the NPC assigned to
## that building — they abandon the current task and return home (or go IDLE if already there).
## Single NPC per production building at VS scope: breaks after first match.
func _on_building_demolished(building_id: StringName) -> void:
	for npc: NPCInstance in all_npcs.values():
		if npc.assigned_building_id == building_id:
			release_npc(npc.npc_id)
			break

## Called when InventorySystem emits container_removed. Clears the storage assignment for the
## NPC using that container and releases them home. Held output is discarded — no item drop.
## Single storage-assignment match at VS scope: breaks after first match.
func _on_container_removed(container_id: StringName) -> void:
	for npc: NPCInstance in all_npcs.values():
		if npc.assigned_storage_id == container_id:
			npc.assigned_storage_id = &""
			release_npc(npc.npc_id)
			break

## Processes a residential house demolition event. Emits house_demolished so the UI
## (Story 005) can show the player a reassignment dialog. The caller then invokes
## remove_npc() if the player confirms removal, or sets a new home_base if reassigning.
func on_house_demolished(npc_ids: Array[StringName]) -> void:
	house_demolished.emit(npc_ids)

## Moves every NPC whose home_base == old_home to a different operating Residential
## House that still has a free slot. The old house's registry entry is emptied.
## Returns true when all residents were successfully rehomed, false if any were left over
## (caller should guard with _can_demolish before calling).
func reassign_house_residents(old_home: Vector2i) -> bool:
	var house: _HouseState = _house_registry.get(old_home)
	if house == null or house.npc_ids.is_empty():
		return true
	for npc_id: StringName in house.npc_ids.duplicate():
		var new_home := _find_free_house(old_home)
		if new_home == Vector2i(-1, -1):
			return false
		_move_npc_to_house(npc_id, old_home, new_home)
	return true


## Finds the first operating Residential House (excluding exclude_tile) with a free slot.
## Returns Vector2i(-1,-1) when none is available.
func _find_free_house(exclude_tile: Vector2i) -> Vector2i:
	if _building_system == null:
		return Vector2i(-1, -1)
	for b: Object in _building_system.get_all_buildings():
		if b.tile == exclude_tile:
			continue
		if b.type != BuildingRegistry.BuildingType.RESIDENTIAL_HOUSE:
			continue
		if b.state != BuildingRegistry.BuildingInstance.State.OPERATING:
			continue
		var h: _HouseState = _get_or_create_house(b.tile)
		if h.npc_ids.size() < NPC_CAPACITY_PER_HOUSE:
			return b.tile
	return Vector2i(-1, -1)


## Moves a single NPC from old_home to new_home, updating all state.
func _move_npc_to_house(npc_id: StringName, old_home: Vector2i, new_home: Vector2i) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return
	var old_house: _HouseState = _house_registry.get(old_home)
	if old_house != null:
		old_house.npc_ids.erase(npc_id)
	var new_house := _get_or_create_house(new_home)
	new_house.npc_ids.append(npc_id)
	npc.home_base = new_home
	if npc.state == TaskState.IDLE:
		npc.position = new_home


## Permanently removes an NPC from the game. Called when the player confirms removal
## after a house demolition. Any held output is discarded — no item drop, no refund.
## No-op (no signal) if the npc_id is not found.
func remove_npc(npc_id: StringName) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return
	var home: Vector2i = npc.home_base
	all_npcs.erase(npc_id)
	var house: _HouseState = _house_registry.get(home)
	if house != null:
		house.npc_ids.erase(npc_id)
	npc_removed.emit(npc_id)

# ---- Efficiency integration (ADR-0012) ----------------------------------------

## Called when HungerSystem emits npc_food_efficiency_changed.
## Updates the specific NPC's food_modifier, recomputes efficiency, then propagates
## the change to any building this NPC is assigned to (ADR-0012).
func _on_npc_food_efficiency_changed(npc_id: StringName, food_modifier: float) -> void:
	var npc: NPCInstance = all_npcs.get(npc_id)
	if npc == null:
		return
	npc.food_modifier = food_modifier
	npc.recalculate_efficiency()
	_propagate_worker_efficiency_change()


## Serialise all NPC state to a JSON-compatible dictionary.
func serialize() -> Dictionary:
	var npcs: Array = []
	for npc: NPCInstance in all_npcs.values():
		npcs.append(_serialize_npc(npc))
	var houses: Array = []
	for tile: Vector2i in _house_registry:
		var house: _HouseState = _house_registry[tile]
		var ids: Array = []
		for id: StringName in house.npc_ids:
			ids.append(str(id))
		houses.append({
			"tile": {"x": tile.x, "y": tile.y},
			"npc_ids": ids,
			"first_recruit_tick": house.first_recruit_tick,
		})
	return {
		"npcs": npcs,
		"houses": houses,
		"npc_counter": _npc_counter,
		"current_tick": _current_tick,
	}


## Restore NPC state from a previously serialised dictionary.
func deserialize(data: Dictionary) -> void:
	all_npcs.clear()
	_house_registry.clear()
	_npc_counter = data.get("npc_counter", 0)
	_current_tick = data.get("current_tick", 0)
	for npc_data in data.get("npcs", []):
		if not npc_data is Dictionary:
			continue
		var npc := _deserialize_npc(npc_data)
		all_npcs[npc.npc_id] = npc
	for house_data in data.get("houses", []):
		if not house_data is Dictionary:
			continue
		var tp: Dictionary = house_data.get("tile", {"x": 0, "y": 0})
		var tile := Vector2i(tp.get("x", 0), tp.get("y", 0))
		var house := _HouseState.new()
		for id in house_data.get("npc_ids", []):
			house.npc_ids.append(StringName(str(id)))
		house.first_recruit_tick = house_data.get("first_recruit_tick", -1)
		_house_registry[tile] = house


func _serialize_npc(npc: NPCInstance) -> Dictionary:
	return {
		"npc_id": str(npc.npc_id),
		"display_name": npc.display_name,
		"position": {"x": npc.position.x, "y": npc.position.y},
		"home_base": {"x": npc.home_base.x, "y": npc.home_base.y},
		"state": npc.state,
		"assigned_building_id": str(npc.assigned_building_id),
		"assigned_storage_id": str(npc.assigned_storage_id),
		"travel_progress": npc.travel_progress,
		"travel_destination": {"x": npc.travel_destination.x, "y": npc.travel_destination.y},
		"travel_ticks_total": npc.travel_ticks_total,
		"work_cycle_complete": npc.work_cycle_complete,
		"current_output_resource": str(npc.current_output_resource),
		"current_output_amount": npc.current_output_amount,
		"food_modifier": npc.food_modifier,
		"satisfaction_modifier": npc.satisfaction_modifier,
		"equipment_modifier": npc.equipment_modifier,
		"xp": npc.xp,
		"pending_xp": npc.pending_xp,
		"profession": npc.profession,
		"pending_perk_choices": npc.pending_perk_choices,
		"pending_perk_cards": npc.pending_perk_cards,
		"perks": _serialize_perks(npc.perks),
	}


func _deserialize_npc(data: Dictionary) -> NPCInstance:
	var npc := NPCInstance.new()
	npc.npc_id = StringName(data.get("npc_id", ""))
	npc.display_name = data.get("display_name", "")
	var pos: Dictionary = data.get("position", {"x": 0, "y": 0})
	npc.position = Vector2i(pos.get("x", 0), pos.get("y", 0))
	var hb: Dictionary = data.get("home_base", {"x": 0, "y": 0})
	npc.home_base = Vector2i(hb.get("x", 0), hb.get("y", 0))
	npc.state = data.get("state", TaskState.IDLE)
	npc.assigned_building_id = StringName(data.get("assigned_building_id", ""))
	npc.assigned_storage_id = StringName(data.get("assigned_storage_id", ""))
	npc.travel_progress = data.get("travel_progress", 0)
	var td: Dictionary = data.get("travel_destination", {"x": 0, "y": 0})
	npc.travel_destination = Vector2i(td.get("x", 0), td.get("y", 0))
	npc.travel_ticks_total = data.get("travel_ticks_total", 0)
	npc.work_cycle_complete = data.get("work_cycle_complete", false)
	npc.current_output_resource = StringName(data.get("current_output_resource", ""))
	npc.current_output_amount = data.get("current_output_amount", 0)
	npc.food_modifier = data.get("food_modifier", 1.0)
	npc.satisfaction_modifier = data.get("satisfaction_modifier", 1.0)
	npc.equipment_modifier = data.get("equipment_modifier", 1.0)
	npc.recalculate_efficiency()
	# Experience: xp is the source of truth; level is always re-derived (Rule 6 / EC-6 / EC-9),
	# then clamped to the progression-tree level cap (ProgressionSystem loads before NPCSystem, so
	# the cap is available here — see WorldSaveManager.LOAD_ORDER).
	npc.xp = int(data.get("xp", 0))
	npc.level = mini(ExperienceFormulas.level_for_total_xp(npc.xp), ProgressionSystem.get_npc_level_cap())
	npc.pending_xp = int(data.get("pending_xp", 0))
	npc.profession = int(data.get("profession", -1))
	npc.pending_perk_choices = int(data.get("pending_perk_choices", 0))
	npc.pending_perk_cards = data.get("pending_perk_cards", [])
	npc.perks = _deserialize_perks(data.get("perks", []))
	return npc


## Serializes an NPC's perk instances to JSON-safe dictionaries.
func _serialize_perks(perks: Array) -> Array:
	var out: Array = []
	for perk: Dictionary in perks:
		out.append({
			"perk_id": str(perk.get(&"perk_id", &"")),
			"good": str(perk.get(&"good", &"")),
			"building_type": int(perk.get(&"building_type", -1)),
			"amount": int(perk.get(&"amount", 1)),
		})
	return out


## Restores perk instances from serialized data, re-interning StringName keys/values.
func _deserialize_perks(data: Variant) -> Array:
	var out: Array = []
	if not data is Array:
		return out
	for entry in data:
		if not entry is Dictionary:
			continue
		out.append({
			&"perk_id": StringName(str(entry.get("perk_id", ""))),
			&"good": StringName(str(entry.get("good", ""))),
			&"building_type": int(entry.get("building_type", -1)),
			&"amount": int(entry.get("amount", 1)),
		})
	return out


## Recalculates efficiency for every building that has an assigned worker.
## Called after any NPC efficiency change so building.efficiency stays in sync.
func _propagate_worker_efficiency_change() -> void:
	if _building_system == null:
		return
	for building in _building_system.get_all_buildings():
		var workers: Array = []
		if building.assigned_npc_id != &"":
			var npc: NPCInstance = all_npcs.get(building.assigned_npc_id)
			if npc != null:
				workers.append(npc)
		building.recalculate_efficiency(workers)
