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

# ---- Level → perk-group mapping -----------------------------------------------

## At a given NPC level (post-level-up), perk cards' bound goods are drawn ONLY
## from resources whose perk_group matches this value. Levels not listed fall
## back to the full perk-eligible pool (legacy behaviour). See
## docs/superpowers/specs/2026-06-28-perk-good-groups-design.md.
const LEVEL_PERK_GROUPS: Dictionary = {
	2: 1,
}

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
		BuildingRegistry.BuildingType.TRADING_POST,
	]

## Production buildings that consume input (eligible for input-reduction perks).
static func input_processing_types() -> Array[int]:
	return [
		BuildingRegistry.BuildingType.TOOL_WORKSHOP,
		BuildingRegistry.BuildingType.WEAVER,
		BuildingRegistry.BuildingType.TAILOR,
		BuildingRegistry.BuildingType.SAWMILL,
		BuildingRegistry.BuildingType.TRADING_POST,
	]

## Production building types whose Progression-Tree node is already unlocked — the only valid
## Calling/profession targets (an NPC may not specialise in a building the colony cannot build yet).
static func unlocked_production_types() -> Array[int]:
	var out: Array[int] = []
	for t: int in production_types():
		if ProgressionSystem.is_building_unlocked(t):
			out.append(t)
	return out

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
		BuildingRegistry.BuildingType.TRADING_POST:   return "Trading Post"
		_: return "Building"


## Returns the perk definition Dictionary for `perk_id`, or {} if unknown.
static func get_def(perk_id: StringName) -> Dictionary:
	for p: Dictionary in PERKS:
		if p["id"] == perk_id:
			return p
	return {}

# ---- Card generation ----------------------------------------------------------

## Returns the perk-eligible goods pool a level-up at `level` should draw from.
## Falls back to the full perk-eligible pool when no group is configured for this
## level OR when the configured group is empty (safety: never soft-lock).
static func _goods_pool_for_level(level: int) -> Array[StringName]:
	var group: int = int(LEVEL_PERK_GROUPS.get(level, 0))
	if group <= 0:
		return ResourceRegistry.get_perk_eligible_ids()
	var pool: Array[StringName] = ResourceRegistry.get_perk_eligible_ids_for_group(group)
	if pool.is_empty():
		return ResourceRegistry.get_perk_eligible_ids()
	return pool


## Builds up to `count` distinct perk cards for a level-up choice, respecting the profession gate.
## `npc` is an NPCSystem.NPCInstance (typed Object to avoid load-order coupling). Each card is a
## Dictionary: {perk_id, name, desc, effect, magnitude, good, building_type}.
## `good` is a perk-eligible resource id; `building_type` is an int (or -1 if not building-bound).
## Returns fewer than `count` cards only if the candidate pool is too small. The goods pool is
## level-restricted via LEVEL_PERK_GROUPS — when restricted, the same good may appear on multiple
## cards (cards differ in perk and/or building).
static func generate_choices(npc: Object, count: int = 3) -> Array:
	var has_profession: bool = npc != null and int(npc.profession) != -1

	# First perk choice (normally the level-2 level-up): force the profession decision. Offer ONLY
	# Calling cards — up to `count`, each bound to a DIFFERENT already-unlocked production building.
	# Falls through to the normal mix only if no production building is unlocked yet, so the choice
	# is never empty.
	if npc != null and not has_profession and (npc.perks as Array).is_empty():
		var calling_cards: Array = _calling_cards(npc, count)
		if not calling_cards.is_empty():
			return calling_cards

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

	# 2) Goods pool restricted by NPC level (LEVEL_PERK_GROUPS). May be small — duplicate goods
	#    across cards are allowed (cards still differ in perk).
	var level: int = int(npc.level) if npc != null else 0
	var goods: Array[StringName] = _goods_pool_for_level(level)

	# 3) Build up to `count` distinct cards.
	var cards: Array = []
	for p: Dictionary in candidates:
		if cards.size() >= count:
			break
		var good: StringName = &""
		if p["good_bound"]:
			if goods.is_empty():
				continue  # no eligible goods at all — cannot bind this perk
			good = goods[randi() % goods.size()]
		var building_type: int = -1
		if p["building_bound"]:
			if p["is_profession"]:
				var pool: Array[int] = unlocked_production_types()
				if pool.is_empty():
					continue  # no unlocked profession to offer — skip this Calling card
				building_type = pool[randi() % pool.size()]
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


## Builds up to `count` Calling (profession) cards, each bound to a DISTINCT already-unlocked
## production building. The bound good is drawn from the NPC's level-restricted pool
## (LEVEL_PERK_GROUPS) — duplicates across cards are allowed. Empty if no production building is
## unlocked yet. Used for the first level-up's forced profession choice.
static func _calling_cards(npc: Object, count: int) -> Array:
	var def: Dictionary = get_def(&"berufung")
	if def.is_empty():
		return []
	var pros: Array[int] = unlocked_production_types()
	pros.shuffle()
	var level: int = int(npc.level) if npc != null else 0
	var goods: Array[StringName] = _goods_pool_for_level(level)
	var cards: Array = []
	for t: int in pros:
		if cards.size() >= count:
			break
		var good: StringName = &""
		if def["good_bound"]:
			if goods.is_empty():
				break  # no eligible goods at all
			good = goods[randi() % goods.size()]
		cards.append({
			&"perk_id": def["id"],
			&"name": def["name"],
			&"desc": def["desc"],
			&"effect": def["effect"],
			&"magnitude": def["magnitude"],
			&"good": good,
			&"building_type": t,
		})
	return cards
