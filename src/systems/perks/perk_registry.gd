class_name PerkRegistry
## Static catalog + card generator for the Perk System.
## Design: design/perks/perk-catalog.md
##
## A perk *definition* is a template. A perk *instance* on an NPC binds the template to a concrete
## good (and, for building-bound perks, a building type). Level-up offers 3 cards (PerkCard dicts);
## the player picks one, turning it into an instance stored on the NPC. Effects are applied
## elsewhere (Phase 4); this file only defines the catalog and generates the choice.

# ---- Effect type keys (consumed by the Phase-4 effect hooks) ------------------

const EFFECT_NUTRITION_REDUCE := &"nutrition_reduce"   # flat reduction of daily nutrition need
const EFFECT_XP_SELF          := &"xp_self"            # +% own XP
const EFFECT_NPC_EFF_CAP      := &"npc_eff_cap"        # +x to this NPC's efficiency ceiling
const EFFECT_CARRIER_CAPACITY := &"carrier_capacity"   # +n carrier capacity
const EFFECT_OUTPUT_BONUS     := &"output_bonus"       # +n output per cycle (building type)
const EFFECT_XP_HOUSEMATE     := &"xp_housemate"       # +% XP for the housemate
const EFFECT_INPUT_SKIP       := &"input_skip"         # every Nth cycle consumes no input (type)
const EFFECT_UNFED_FLOOR      := &"unfed_floor"        # raise the unfed efficiency floor
const EFFECT_OUTPUT_CAPACITY  := &"output_capacity"    # x output buffer capacity (building type)
const EFFECT_PROFESSION_XP    := &"profession_xp"      # set profession + +% work XP at it

# ---- Building-type pools ------------------------------------------------------

const POOL_PRODUCTION_ALL := &"production_all"
const POOL_INPUT_PROCESSING := &"input_processing"

# ---- Perk catalog (data only) -------------------------------------------------
## Keys: id, name, desc, effect, magnitude, good_bound, building_bound, pool,
## is_profession, requires_profession.
const PERKS: Array[Dictionary] = [
	{
		"id": &"genuegsam", "name": "Frugal", "effect": EFFECT_NUTRITION_REDUCE, "magnitude": 2.0,
		"desc": "Needs 2 fewer food/day for full efficiency.",
		"good_bound": true, "building_bound": false, "pool": &"", "is_profession": false, "requires_profession": false, "required": 1,
	},
	{
		"id": &"lernbegierig", "name": "Eager Learner", "effect": EFFECT_XP_SELF, "magnitude": 0.25,
		"desc": "+25% own experience (work & delivery).",
		"good_bound": true, "building_bound": false, "pool": &"", "is_profession": false, "requires_profession": false, "required": 1,
	},
	{
		"id": &"meisterhand", "name": "Master's Touch", "effect": EFFECT_NPC_EFF_CAP, "magnitude": 0.2,
		"desc": "+20% to this NPC's max efficiency (feed more to reach it).",
		"good_bound": true, "building_bound": false, "pool": &"", "is_profession": false, "requires_profession": false, "required": 1,
	},
	{
		"id": &"packesel", "name": "Pack Mule", "effect": EFFECT_CARRIER_CAPACITY, "magnitude": 1.0,
		"desc": "Carries +1 item per trip as a carrier.",
		"good_bound": true, "building_bound": false, "pool": &"", "is_profession": false, "requires_profession": false, "required": 1,
	},
	{
		"id": &"ergiebig", "name": "Abundant", "effect": EFFECT_OUTPUT_BONUS, "magnitude": 1.0,
		"desc": "+1 output per production cycle of this building type.",
		"good_bound": true, "building_bound": true, "pool": POOL_PRODUCTION_ALL, "is_profession": false, "requires_profession": true, "required": 1,
	},
	{
		"id": &"lehrmeister", "name": "Mentor", "effect": EFFECT_XP_HOUSEMATE, "magnitude": 0.25,
		"desc": "+25% experience for the housemate.",
		"good_bound": true, "building_bound": false, "pool": &"", "is_profession": false, "requires_profession": false, "required": 1,
	},
	{
		"id": &"sparsam", "name": "Thrifty", "effect": EFFECT_INPUT_SKIP, "magnitude": 4.0,
		"desc": "Every 4th cycle of this building type consumes no input.",
		"good_bound": true, "building_bound": true, "pool": POOL_INPUT_PROCESSING, "is_profession": false, "requires_profession": true, "required": 1,
	},
	{
		"id": &"zaeh", "name": "Resilient", "effect": EFFECT_UNFED_FLOOR, "magnitude": 0.5,
		"desc": "Hunger floor: 25% -> 50% when undersupplied.",
		"good_bound": true, "building_bound": false, "pool": &"", "is_profession": false, "requires_profession": false, "required": 1,
	},
	{
		"id": &"geraeumig", "name": "Spacious", "effect": EFFECT_OUTPUT_CAPACITY, "magnitude": 0.5,
		"desc": "+50% output buffer capacity of this building type.",
		"good_bound": true, "building_bound": true, "pool": POOL_PRODUCTION_ALL, "is_profession": false, "requires_profession": true, "required": 1,
	},
	{
		"id": &"berufung", "name": "Calling", "effect": EFFECT_PROFESSION_XP, "magnitude": 0.5,
		"desc": "Sets profession: +50% work XP at this building type.",
		"good_bound": true, "building_bound": true, "pool": POOL_PRODUCTION_ALL, "is_profession": true, "requires_profession": false, "required": 1,
	},
]

# ---- Building-type pools (runtime — BuildingRegistry is an autoload) -----------

## All production building types (excludes storage/housing).
static func production_types() -> Array[int]:
	return [
		BuildingRegistry.BuildingType.LUMBER_CAMP,
		BuildingRegistry.BuildingType.GATHERING_HUT,
		BuildingRegistry.BuildingType.STONE_MASON,
		BuildingRegistry.BuildingType.TOOL_WORKSHOP,
		BuildingRegistry.BuildingType.WEAVER,
		BuildingRegistry.BuildingType.TAILOR,
		BuildingRegistry.BuildingType.SAWMILL,
	]

## Production buildings that consume input (eligible for input-reduction perks).
static func input_processing_types() -> Array[int]:
	return [
		BuildingRegistry.BuildingType.TOOL_WORKSHOP,
		BuildingRegistry.BuildingType.WEAVER,
		BuildingRegistry.BuildingType.TAILOR,
		BuildingRegistry.BuildingType.SAWMILL,
	]

# ---- Accessors ----------------------------------------------------------------

## Display name for a production building type (uses real enum values, not hardcoded ints).
static func building_type_name(t: int) -> String:
	match t:
		BuildingRegistry.BuildingType.LUMBER_CAMP:   return "Lumber Camp"
		BuildingRegistry.BuildingType.GATHERING_HUT:  return "Gathering Hut"
		BuildingRegistry.BuildingType.STONE_MASON:    return "Stone Mason"
		BuildingRegistry.BuildingType.TOOL_WORKSHOP:  return "Tool Workshop"
		BuildingRegistry.BuildingType.WEAVER:         return "Weaver"
		BuildingRegistry.BuildingType.TAILOR:         return "Tailor"
		BuildingRegistry.BuildingType.SAWMILL:        return "Sawmill"
		_: return "Building"


## Returns the perk definition Dictionary for `perk_id`, or {} if unknown.
static func get_def(perk_id: StringName) -> Dictionary:
	for p: Dictionary in PERKS:
		if p["id"] == perk_id:
			return p
	return {}

# ---- Card generation ----------------------------------------------------------

## Builds up to `count` distinct perk cards for a level-up choice, respecting the profession gate.
## `npc` is an NPCSystem.NPCInstance (typed Object to avoid load-order coupling). Each card is a
## Dictionary: {perk_id, name, desc, effect, magnitude, good, building_type}.
## `good` is a perk-eligible resource id; `building_type` is an int (or -1 if not building-bound).
## Returns fewer than `count` cards only if the candidate or good pools are too small.
static func generate_choices(npc: Object, count: int = 3) -> Array:
	var has_profession: bool = npc != null and int(npc.profession) != -1

	# 1) Candidate perk definitions, filtered by the profession gate.
	var candidates: Array[Dictionary] = []
	for p: Dictionary in PERKS:
		if p["is_profession"]:
			if has_profession:
				continue  # already specialised — one profession per NPC, permanent
		elif p["building_bound"]:
			if not has_profession:
				continue  # building-bound effect perks are locked until a profession is chosen
			if p["pool"] == POOL_INPUT_PROCESSING and not input_processing_types().has(int(npc.profession)):
				continue  # Thrifty only when the profession is an input-processing type
		candidates.append(p)
	candidates.shuffle()

	# 2) Pool of perk-eligible goods (distinct per draw).
	var goods: Array[StringName] = ResourceRegistry.get_perk_eligible_ids()
	goods.shuffle()

	# 3) Build up to `count` distinct cards.
	var cards: Array = []
	var good_idx: int = 0
	for p: Dictionary in candidates:
		if cards.size() >= count:
			break
		var good: StringName = &""
		if p["good_bound"]:
			if good_idx >= goods.size():
				continue  # ran out of distinct goods
			good = goods[good_idx]
			good_idx += 1
		var building_type: int = -1
		if p["building_bound"]:
			if p["is_profession"]:
				var pool: Array[int] = production_types()
				building_type = pool[randi() % pool.size()] if not pool.is_empty() else -1
			else:
				building_type = int(npc.profession)  # applies to the NPC's profession type
		cards.append({
			&"perk_id": p["id"],
			&"name": p["name"],
			&"desc": p["desc"],
			&"effect": p["effect"],
			&"magnitude": p["magnitude"],
			&"good": good,
			&"building_type": building_type,
		})
	return cards
