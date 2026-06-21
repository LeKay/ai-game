extends Node
## BuildingRegistry — Autoload singleton for building placement, construction progress,
## production cycle advancement, and building instance tracking.
## ADR: Buildings Story 001 (placement), Story 002 (production cycles).
##
## WorldGrid and PlayerCharacter are NOT Autoloads — they are injected via
## init_dependencies() after the scene tree is ready (called by MapRoot).

# ---- Enums ------------------------------------------------------------------

## Costs and build times live in BUILD_COST / BUILD_TIME below — keep them there
## (single source of truth), not in these comments.
enum BuildingType {
	COLLECTION_POINT,    ## free, instant, 50 slots — starter gathering depot
	STORAGE_BUILDING,    ## 150 slots
	RESIDENTIAL_HOUSE,   ## spawns up to MAX_HOUSE_NPCS
	LUMBER_CAMP,         ## produces Wood; requires adjacent TREE terrain
	ROAD,                ## free, instant, passable infrastructure — movement cost 0.5
	GATHERING_HUT,       ## harvests Berry/Fiber from adjacent terrain
	STONE_MASON,         ## produces Stone; requires adjacent STONE terrain
	TOOL_WORKSHOP,       ## crafts Axe / Pickaxe / Spindle from Wood + Stone + Fiber
	WEAVER,              ## processes Fiber → Cloth; no terrain requirement
	TAILOR,              ## processes Cloth → Clothing; no terrain requirement
	SAWMILL,             ## processes Wood → Plank; no terrain requirement
	HUNTING_LODGE,       ## produces Game Meat + Hide; must border a forest containing wild
	FARM,                ## harvests Wheat; efficiency scales with adjacent WHEAT terrain
	MILL,                ## processes Wheat → Flour; built-in millstone
	BAKERY,              ## processes Flour → Bread; built-in oven
	CLAY_PIT,            ## extracts Clay from adjacent CLAY terrain; uses Pickaxe
	POTTERY_KILN,        ## fires Clay → Pottery vessels; with_tool uses Pickaxe
	TANNERY,             ## processes Hide → Leather; with_knife uses Knife
	BOWYERS_WORKSHOP,    ## crafts Hunting Bow from Wood + Fiber; supplies Hunting Lodge
	BRIDGE,              ## placed on a WATER tile; makes it passable (river crossing)
	CARPENTER,           ## processes Plank → Furniture; with_leather adds Leather for higher output
	FISHING_HUT,         ## catches Fish; requires ≥1 adjacent WATER tile; efficiency scales with water tile count
	BRICK_KILN,          ## fires Clay + Fiber → Brick; no terrain requirement
	CHARCOAL_KILN,       ## burns Wood → Charcoal; must border a WATER tile (no efficiency bonus)
	SALT_WORKS,          ## evaporates seawater → Salt; requires adjacent COAST tile; efficiency scales with coast count
	PRESERVATION_HOUSE,  ## preserves Meat/Fish with Salt + Pottery → Preserved Food (trade good)
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
	LOCKED,                 ## building type not yet unlocked in the Progression Tree
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
	## Completed-cycle counter (Perk System #8 Sparsam: every 4th cycle skips input). Transient.
	var cycle_count: int = 0
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
	## Optional flat efficiency bonus from terrain adjacency (e.g. Mill +0.20 next to water).
	## Set by BuildingRegistry._refresh_water_bonus; not a placement requirement, does not stack.
	var water_bonus: float = 0.0
	var efficiency: float = 1.0
	## Utilization tracking — fraction of the day the building was actively producing.
	## Accumulates while a cycle is advancing; snapshotted into *_last_day each day rollover.
	var util_active_ticks_today: int = 0
	var util_active_ticks_last_day: int = 0
	## False until the first full day has elapsed — UI shows "—" until then.
	var util_data_available: bool = false
	## Count of adjacent terrain tiles satisfying ADJACENCY_REQUIREMENTS for this type.
	## Managed by BuildingRegistry. Only relevant for types in ADJACENCY_REQUIREMENTS.
	var adjacency_tile_count: int = 0
	## Computed output for GATHERING_HUT based on adjacent terrain types.
	## Keys are resource IDs; values are quantities per cycle.
	var gathering_output: Dictionary[StringName, int] = {}
	## Index into BuildingRegistry.RECIPES[type] for the currently active recipe.
	var active_recipe_index: int = 0
	## True once the player has explicitly picked a recipe for this building.
	## While false, the detail panel opens straight into the recipe selection view.
	var recipe_selected: bool = false
	## Per-resource delivery limits for storage buildings (resource_id → max quantity).
	## 0 or absent = no limit. Transport routes will not deliver past the limit.
	var storage_limits: Dictionary[StringName, int] = {}
	## Per-resource minimum reserve for storage buildings (resource_id → min quantity to keep).
	## Transport routes will not take items below this threshold. -1 / absent = no minimum.
	var storage_min_limits: Dictionary[StringName, int] = {}
	## Upgrade IDs currently installed on this building (e.g. &"crafting_bench").
	var active_upgrades: Array[StringName] = []

	## Returns true if the named upgrade is currently installed on this building.
	func has_upgrade(upgrade_id: StringName) -> bool:
		return active_upgrades.has(upgrade_id)

	## Recomputes efficiency (additive model, 2026-06-18):
	##   efficiency = base 25% + resource_tiles × 5% + worker efficiency (+ upgrade_bonus),
	##   clamped to [0, BUILDING_EFFICIENCY_MAX]. Resource tiles only count for buildings with an
	##   adjacency requirement; all others contribute 0 there. Unstaffed → worker term is 0.
	func recalculate_efficiency(assigned_workers: Array) -> void:
		var worker_eff: float = 0.0
		for worker in assigned_workers:
			worker_eff += worker.efficiency
		var resource_tiles: int = adjacency_tile_count if (ADJACENCY_REQUIREMENTS.has(type) and not ADJACENCY_PLACEMENT_ONLY.has(type)) else 0
		efficiency = EfficiencyFormulas.calculate_building_efficiency(
				resource_tiles, worker_eff, upgrade_bonus, water_bonus)

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
	BuildingType.WEAVER:            {&"wood": 8,  &"stone": 3},
	BuildingType.TAILOR:            {&"wood": 10, &"stone": 5},
	BuildingType.SAWMILL:           {&"wood": 8,  &"stone": 3},
	BuildingType.HUNTING_LODGE:     {&"wood": 12, &"stone": 3},
	BuildingType.FARM:              {&"wood": 8, &"stone": 2},
	BuildingType.MILL:              {&"wood": 10, &"stone": 5},
	BuildingType.BAKERY:            {&"wood": 10, &"stone": 5},
	BuildingType.CLAY_PIT:          {&"wood": 8,  &"stone": 3},
	BuildingType.POTTERY_KILN:       {&"wood": 5,  &"stone": 8, &"clay": 5},
	BuildingType.TANNERY:            {&"wood": 8,  &"stone": 3},
	BuildingType.BOWYERS_WORKSHOP:   {&"wood": 8,  &"fiber": 3, &"stone": 2},
	BuildingType.BRIDGE:             {&"wood": 8},
	BuildingType.CARPENTER:          {&"wood": 10, &"stone": 5},
	BuildingType.FISHING_HUT:        {&"wood": 8,  &"stone": 2, &"fiber": 4},
	BuildingType.BRICK_KILN:         {&"wood": 8,  &"stone": 8, &"clay": 5},
	BuildingType.CHARCOAL_KILN:      {&"wood": 10, &"stone": 8},
	BuildingType.SALT_WORKS:         {&"wood": 12, &"stone": 8},
	BuildingType.PRESERVATION_HOUSE: {&"wood": 10, &"stone": 6},
}

## Canonical list of player-buildable types, in build-menu display order.
## Single source of truth for the build menu (see inventory_screen._building_list()).
## Excludes COLLECTION_POINT (starter depot, auto-placed) and ROAD (placed via the Path tool).
## The future Progression Tree gates this list with a single is_building_unlocked() guard.
const BUILDABLE_TYPES: Array[int] = [
	BuildingType.STORAGE_BUILDING,
	BuildingType.RESIDENTIAL_HOUSE,
	BuildingType.LUMBER_CAMP,
	BuildingType.STONE_MASON,
	BuildingType.GATHERING_HUT,
	BuildingType.TOOL_WORKSHOP,
	BuildingType.WEAVER,
	BuildingType.TAILOR,
	BuildingType.SAWMILL,
	BuildingType.HUNTING_LODGE,
	BuildingType.FARM,
	BuildingType.MILL,
	BuildingType.BAKERY,
	BuildingType.CLAY_PIT,
	BuildingType.POTTERY_KILN,
	BuildingType.TANNERY,
	BuildingType.BOWYERS_WORKSHOP,
	BuildingType.BRIDGE,
	BuildingType.CARPENTER,
	BuildingType.FISHING_HUT,
	BuildingType.BRICK_KILN,
	BuildingType.CHARCOAL_KILN,
	BuildingType.SALT_WORKS,
	BuildingType.PRESERVATION_HOUSE,
]

## Build times rescaled for pacing (balancing 2026-06-11): anchor 1 tick ≈ 1 minute,
## 1440 ticks/day. Construction now takes hours-to-days (was seconds) so the in-game day
## is a real planning unit. Hut ≈ 0.4 day, house/camp/mason ≈ 0.8–1.1 days, workshop ≈ 2 days.
const BUILD_TIME: Dictionary = {
	BuildingType.COLLECTION_POINT:  0,
	BuildingType.STORAGE_BUILDING:  480,
	BuildingType.RESIDENTIAL_HOUSE: 600,
	BuildingType.LUMBER_CAMP:       800,
	BuildingType.ROAD:              0,
	BuildingType.GATHERING_HUT:     320,
	BuildingType.STONE_MASON:       800,
	BuildingType.TOOL_WORKSHOP:     1500,
	BuildingType.WEAVER:            600,
	BuildingType.TAILOR:            800,
	BuildingType.SAWMILL:           600,
	BuildingType.HUNTING_LODGE:     700,
	BuildingType.FARM:              480,
	BuildingType.MILL:              800,
	BuildingType.BAKERY:            900,
	BuildingType.CLAY_PIT:          800,
	BuildingType.POTTERY_KILN:       900,
	BuildingType.TANNERY:            700,
	BuildingType.BOWYERS_WORKSHOP:   700,
	BuildingType.BRIDGE:            400,
	BuildingType.CARPENTER:         800,
	BuildingType.FISHING_HUT:       480,
	BuildingType.BRICK_KILN:        900,
	BuildingType.CHARCOAL_KILN:     800,
	BuildingType.SALT_WORKS:        900,
	BuildingType.PRESERVATION_HOUSE: 900,
}

## Energy cost the player spends to manually construct a building (ManualActionType.CONSTRUCT_BUILDING).
const BUILD_ENERGY: Dictionary = {
	BuildingType.COLLECTION_POINT:  0,
	BuildingType.STORAGE_BUILDING:  20,
	BuildingType.RESIDENTIAL_HOUSE: 25,
	BuildingType.LUMBER_CAMP:       30,
	BuildingType.ROAD:              0,
	BuildingType.GATHERING_HUT:     15,
	BuildingType.STONE_MASON:       30,
	BuildingType.TOOL_WORKSHOP:     40,
	BuildingType.WEAVER:            22,
	BuildingType.TAILOR:            30,
	BuildingType.SAWMILL:           22,
	BuildingType.HUNTING_LODGE:     28,
	BuildingType.FARM:              15,
	BuildingType.MILL:              20,
	BuildingType.BAKERY:            22,
	BuildingType.CLAY_PIT:          22,
	BuildingType.POTTERY_KILN:       25,
	BuildingType.TANNERY:            22,
	BuildingType.BOWYERS_WORKSHOP:   22,
	BuildingType.BRIDGE:            18,
	BuildingType.CARPENTER:         25,
	BuildingType.FISHING_HUT:       18,
	BuildingType.BRICK_KILN:        25,
	BuildingType.CHARCOAL_KILN:     22,
	BuildingType.SALT_WORKS:        28,
	BuildingType.PRESERVATION_HOUSE: 25,
}

## Movement cost for buildings that NPCs and carriers can traverse.
## Types absent from this table are impassable (cost = INF).
const MOVEMENT_EFFICIENCY: Dictionary = {
	BuildingType.ROAD: 0.5,
	BuildingType.BRIDGE: 0.5,  ## passable river crossing
}

const STORAGE_CAPACITY: Dictionary = {
	BuildingType.COLLECTION_POINT: 50,
	BuildingType.STORAGE_BUILDING: 150,
}

## Upgrade definitions per building type.
## Each entry: { &"id", &"display_name", &"cost": {res_id: qty}, &"tick_cost": int }
const BUILDING_UPGRADES: Dictionary = {
	BuildingType.STORAGE_BUILDING: [
		{
			&"id":           &"crafting_bench",
			&"display_name": "Crafting Bench",
			&"cost":         {&"wood": 10, &"stone": 5},
			&"tick_cost":    200,
		},
	],
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
	BuildingType.WEAVER:            "res://assets/art/tiles/bld_tile_weaver.png",
	BuildingType.TAILOR:            "res://assets/art/tiles/bld_tile_tailor.png",
	BuildingType.SAWMILL:           "res://assets/art/tiles/bld_tile_sawmill.png",
	BuildingType.HUNTING_LODGE:     "res://assets/art/tiles/bld_tile_hunting_lodge.png",
	BuildingType.FARM:              "res://assets/art/tiles/bld_tile_farm.png",
	BuildingType.MILL:              "res://assets/art/tiles/bld_tile_mill.png",
	BuildingType.BAKERY:            "res://assets/art/tiles/bld_tile_bakery.png",
	BuildingType.CLAY_PIT:          "res://assets/art/tiles/bld_tile_clay_pit.png",
	BuildingType.POTTERY_KILN:       "res://assets/art/tiles/bld_tile_pottery_kiln.png",
	BuildingType.TANNERY:            "res://assets/art/tiles/bld_tile_tannery.png",
	BuildingType.BOWYERS_WORKSHOP:   "res://assets/art/tiles/bld_tile_bowyers_workshop.png",
	BuildingType.BRIDGE:             "res://assets/art/tiles/env_tile_bridge_h_01.png",
	BuildingType.CARPENTER:          "res://assets/art/tiles/bld_tile_carpenter.png",
	BuildingType.FISHING_HUT:        "res://assets/art/tiles/bld_tile_fishing_hut.png",
	BuildingType.BRICK_KILN:         "res://assets/art/tiles/bld_tile_brick_kiln.png",
	BuildingType.CHARCOAL_KILN:      "res://assets/art/tiles/bld_tile_charcoal_kiln.png",
	BuildingType.SALT_WORKS:         "res://assets/art/tiles/bld_tile_salt_works.png",
	BuildingType.PRESERVATION_HOUSE: "res://assets/art/tiles/bld_tile_preservation_house.png",
}

## Maps BuildingType → the job/profession label of a worker employed there.
## Non-production types (storage, road, house, collection point) have no worker and are absent;
## callers fall back to a generic "Worker" for any type not listed here.
const BUILDING_JOB_NAMES: Dictionary = {
	BuildingType.LUMBER_CAMP:   "Lumberjack",
	BuildingType.GATHERING_HUT: "Gatherer",
	BuildingType.STONE_MASON:   "Mason",
	BuildingType.TOOL_WORKSHOP: "Toolsmith",
	BuildingType.WEAVER:        "Weaver",
	BuildingType.TAILOR:        "Tailor",
	BuildingType.SAWMILL:       "Sawyer",
	BuildingType.HUNTING_LODGE: "Hunter",
	BuildingType.FARM:          "Farmer",
	BuildingType.MILL:          "Miller",
	BuildingType.BAKERY:        "Baker",
	BuildingType.CLAY_PIT:      "Clay Digger",
	BuildingType.POTTERY_KILN:       "Potter",
	BuildingType.TANNERY:            "Tanner",
	BuildingType.BOWYERS_WORKSHOP:   "Bowyer",
	BuildingType.CARPENTER:          "Carpenter",
	BuildingType.FISHING_HUT:        "Fisher",
	BuildingType.BRICK_KILN:         "Brick Maker",
	BuildingType.CHARCOAL_KILN:      "Charcoal Burner",
	BuildingType.SALT_WORKS:         "Salt Worker",
	BuildingType.PRESERVATION_HOUSE: "Preserver",
}

## Multi-recipe table: BuildingType → Array of recipe dicts (index 0 = default recipe).
## Use is_production_building() to check membership.
const RECIPES: Dictionary = {
	BuildingType.LUMBER_CAMP: [
		{
			"id": &"with_tool",
			"label": "With Tool",
			"inputs": [{"resource_id": &"axe", "quantity": 1}],
			"output": {&"wood": 5},
			"output_capacity": 20,
			"input_capacity": 5,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
		{
			"id": &"bare_hands",
			"label": "Bare Hands (slow)",
			"inputs": [],
			"output": {&"wood": 2},
			"output_capacity": 20,
			"input_capacity": 0,
			"base_cycle_ticks": 750,
			"npc_required": true,
		},
	],
	BuildingType.STONE_MASON: [
		{
			"id": &"with_tool",
			"label": "With Tool",
			"inputs": [{"resource_id": &"pickaxe", "quantity": 1}],
			"output": {&"stone": 5},
			"output_capacity": 20,
			"input_capacity": 5,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
		{
			"id": &"bare_hands",
			"label": "Bare Hands (slow)",
			"inputs": [],
			"output": {&"stone": 2},
			"output_capacity": 20,
			"input_capacity": 0,
			"base_cycle_ticks": 750,
			"npc_required": true,
		},
	],
	BuildingType.GATHERING_HUT: [
		{
			"id": &"gather_berry",
			"label": "Gather Berries",
			"inputs": [],
			"output": {&"berry": 4},
			"output_capacity": 20,
			"input_capacity": 0,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
		{
			"id": &"gather_fiber",
			"label": "Gather Fiber",
			"inputs": [],
			"output": {&"fiber": 2},
			"output_capacity": 20,
			"input_capacity": 0,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
	],
	BuildingType.TOOL_WORKSHOP: [
		{
			"id": &"craft_axe",
			"label": "Craft Axe",
			"inputs": [
				{"resource_id": &"wood",  "quantity": 3},
				{"resource_id": &"stone", "quantity": 2},
			],
			"output": {&"axe": 1},
			"output_capacity": 10,
			"input_capacity": 10,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
		{
			"id": &"craft_pickaxe",
			"label": "Craft Pickaxe",
			"inputs": [
				{"resource_id": &"stone", "quantity": 3},
				{"resource_id": &"wood",  "quantity": 1},
			],
			"output": {&"pickaxe": 1},
			"output_capacity": 10,
			"input_capacity": 10,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
		{
			"id": &"craft_spindle",
			"label": "Craft Spindle",
			"inputs": [
				{"resource_id": &"wood",  "quantity": 2},
				{"resource_id": &"fiber", "quantity": 2},
			],
			"output": {&"spindle": 1},
			"output_capacity": 10,
			"input_capacity": 10,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
		{
			"id": &"craft_knife",
			"label": "Craft Knife",
			"inputs": [
				{"resource_id": &"wood",  "quantity": 2},
				{"resource_id": &"stone", "quantity": 1},
			],
			"output": {&"knife": 1},
			"output_capacity": 10,
			"input_capacity": 10,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
	],
	BuildingType.WEAVER: [
		{
			"id": &"with_tool",
			"label": "With Tool",
			"inputs": [
				{"resource_id": &"fiber",   "quantity": 3},
				{"resource_id": &"spindle", "quantity": 1},
			],
			"output": {&"cloth": 2},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
		{
			"id": &"bare_hands",
			"label": "Bare Hands (slow)",
			"inputs": [
				{"resource_id": &"fiber", "quantity": 5},
			],
			"output": {&"cloth": 1},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 750,
			"npc_required": true,
		},
		{
			"id": &"craft_fishing_net",
			"label": "Craft Fishing Net",
			"inputs": [
				{"resource_id": &"fiber", "quantity": 4},
			],
			"output": {&"fishing_net": 1},
			"output_capacity": 10,
			"input_capacity": 10,
			"base_cycle_ticks": 300,
			"npc_required": true,
		},
	],
	BuildingType.TAILOR: [
		{
			"id": &"with_tool",
			"label": "With Tool",
			"inputs": [
				{"resource_id": &"cloth",   "quantity": 2},
				{"resource_id": &"spindle", "quantity": 1},
			],
			"output": {&"clothing": 2},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 300,
			"npc_required": true,
		},
		{
			"id": &"bare_hands",
			"label": "Bare Hands (slow)",
			"inputs": [
				{"resource_id": &"cloth", "quantity": 2},
			],
			"output": {&"clothing": 1},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 900,
			"npc_required": true,
		},
		{
			"id": &"leather_garments",
			"label": "Leather Garments",
			"inputs": [
				{"resource_id": &"leather", "quantity": 2},
				{"resource_id": &"spindle", "quantity": 1},
			],
			"output": {&"clothing": 2},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 300,
			"npc_required": true,
		},
	],
	BuildingType.SAWMILL: [
		{
			"id": &"saw_planks",
			"label": "Saw Planks",
			"inputs": [
				{"resource_id": &"wood", "quantity": 2},
				{"resource_id": &"axe",  "quantity": 1},
			],
			"output": {&"plank": 3},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
	],
	BuildingType.HUNTING_LODGE: [
		{
			"id": &"hunt_with_bow",
			"label": "Hunt (with Bow)",
			"inputs": [{"resource_id": &"hunting_bow", "quantity": 1}],
			"output": {&"meat": 3, &"hide": 2},
			"output_capacity": 20,
			"input_capacity": 5,
			"base_cycle_ticks": 300,
			"npc_required": true,
		},
		{
			"id": &"hunt",
			"label": "Hunt (bare hands)",
			"inputs": [],
			"output": {&"meat": 2, &"hide": 1},
			"output_capacity": 20,
			"input_capacity": 0,
			"base_cycle_ticks": 450,
			"npc_required": true,
		},
	],
	BuildingType.FARM: [
		{
			"id": &"harvest_wheat",
			"label": "Harvest Wheat",
			"inputs": [],
			"output": {&"wheat": 3},
			"output_capacity": 20,
			"input_capacity": 0,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
	],
	BuildingType.MILL: [
		{
			"id": &"grind",
			"label": "Grind Flour",
			"inputs": [
				{"resource_id": &"wheat", "quantity": 2},
			],
			"output": {&"flour": 3},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
	],
	BuildingType.BAKERY: [
		{
			"id": &"bake",
			"label": "Bake Bread",
			"inputs": [
				{"resource_id": &"flour", "quantity": 2},
			],
			"output": {&"bread": 4},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 300,
			"npc_required": true,
		},
	],
	BuildingType.CLAY_PIT: [
		{
			"id": &"extract_clay",
			"label": "Extract Clay",
			"inputs": [{"resource_id": &"pickaxe", "quantity": 1}],
			"output": {&"clay": 5},
			"output_capacity": 20,
			"input_capacity": 5,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
	],
	BuildingType.POTTERY_KILN: [
		{
			"id": &"with_tool",
			"label": "Fire Pottery (with Tool)",
			"inputs": [
				{"resource_id": &"clay",    "quantity": 2},
				{"resource_id": &"pickaxe", "quantity": 1},
			],
			"output": {&"pottery": 3},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 300,
			"npc_required": true,
		},
		{
			"id": &"bare_hands",
			"label": "Fire Pottery (slow)",
			"inputs": [
				{"resource_id": &"clay", "quantity": 2},
			],
			"output": {&"pottery": 1},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 900,
			"npc_required": true,
		},
	],
	BuildingType.TANNERY: [
		{
			"id": &"with_knife",
			"label": "Tan Hide (with Knife)",
			"inputs": [
				{"resource_id": &"hide",  "quantity": 2},
				{"resource_id": &"knife", "quantity": 1},
			],
			"output": {&"leather": 3},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
		{
			"id": &"bare_hands",
			"label": "Tan Hide (slow)",
			"inputs": [
				{"resource_id": &"hide", "quantity": 2},
			],
			"output": {&"leather": 1},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 750,
			"npc_required": true,
		},
	],
	BuildingType.BOWYERS_WORKSHOP: [
		{
			"id": &"craft_bow",
			"label": "Craft Hunting Bow",
			"inputs": [
				{"resource_id": &"wood",  "quantity": 2},
				{"resource_id": &"fiber", "quantity": 3},
			],
			"output": {&"hunting_bow": 1},
			"output_capacity": 10,
			"input_capacity": 10,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
	],
	BuildingType.CARPENTER: [
		{
			"id": &"with_leather",
			"label": "Craft Furniture (Upholstered)",
			"inputs": [
				{"resource_id": &"plank",   "quantity": 2},
				{"resource_id": &"leather", "quantity": 1},
			],
			"output": {&"furniture": 3},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 350,
			"npc_required": true,
		},
		{
			"id": &"bare_planks",
			"label": "Craft Furniture (Basic)",
			"inputs": [
				{"resource_id": &"plank", "quantity": 2},
			],
			"output": {&"furniture": 1},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 500,
			"npc_required": true,
		},
	],
	BuildingType.FISHING_HUT: [
		{
			"id": &"with_net",
			"label": "Fish with Net",
			"inputs": [{"resource_id": &"fishing_net", "quantity": 1}],
			"output": {&"fish": 5},
			"output_capacity": 20,
			"input_capacity": 5,
			"base_cycle_ticks": 250,
			"npc_required": true,
		},
	],
	BuildingType.BRICK_KILN: [
		{
			"id": &"fire_bricks",
			"label": "Fire Bricks",
			"inputs": [
				{"resource_id": &"clay",  "quantity": 2},
				{"resource_id": &"fiber", "quantity": 1},
			],
			"output": {&"brick": 3},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
		{
			"id": &"fire_bricks_charcoal",
			"label": "Fire Bricks (Charcoal)",
			"inputs": [
				{"resource_id": &"clay",     "quantity": 2},
				{"resource_id": &"charcoal", "quantity": 1},
			],
			"output": {&"brick": 4},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 300,
			"npc_required": true,
		},
	],
	BuildingType.CHARCOAL_KILN: [
		{
			"id": &"burn_charcoal",
			"label": "Burn Charcoal",
			"inputs": [
				{"resource_id": &"wood", "quantity": 3},
			],
			"output": {&"charcoal": 3},
			"output_capacity": 20,
			"input_capacity": 10,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
	],
	BuildingType.SALT_WORKS: [
		{
			"id": &"evaporate",
			"label": "Evaporate Salt",
			"inputs": [],
			"output": {&"salt": 2},
			"output_capacity": 20,
			"input_capacity": 0,
			"base_cycle_ticks": 700,
			"npc_required": true,
		},
	],
	BuildingType.PRESERVATION_HOUSE: [
		{
			"id": &"preserve_meat",
			"label": "Preserve Meat",
			"inputs": [
				{"resource_id": &"meat",    "quantity": 2},
				{"resource_id": &"salt",    "quantity": 1},
				{"resource_id": &"pottery", "quantity": 1},
			],
			"output": {&"preserved_food": 3},
			"output_capacity": 20,
			"input_capacity": 5,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
		{
			"id": &"preserve_fish",
			"label": "Preserve Fish",
			"inputs": [
				{"resource_id": &"fish",    "quantity": 2},
				{"resource_id": &"salt",    "quantity": 1},
				{"resource_id": &"pottery", "quantity": 1},
			],
			"output": {&"preserved_food": 2},
			"output_capacity": 20,
			"input_capacity": 5,
			"base_cycle_ticks": 375,
			"npc_required": true,
		},
	],
}

## Terrain types required in at least one cardinal neighbor for a building to be placeable.
## Maps BuildingType → Array of WorldGrid.TileType values.
const ADJACENCY_REQUIREMENTS: Dictionary = {
	BuildingType.LUMBER_CAMP:    [WorldGrid.TileType.TREE],
	BuildingType.GATHERING_HUT:  [WorldGrid.TileType.BERRY, WorldGrid.TileType.GRASS],
	BuildingType.STONE_MASON:    [WorldGrid.TileType.STONE],
	## HUNTING_LODGE also needs a TREE neighbour, but with the extra runtime rule that the
	## adjacent forest must contain wild — enforced in _check_adjacency via WildSystem.
	BuildingType.HUNTING_LODGE:  [WorldGrid.TileType.TREE],
	BuildingType.FARM:           [WorldGrid.TileType.WHEAT],
	BuildingType.CLAY_PIT:       [WorldGrid.TileType.CLAY],
	BuildingType.FISHING_HUT:    [WorldGrid.TileType.WATER],
	BuildingType.CHARCOAL_KILN:  [WorldGrid.TileType.WATER],
	BuildingType.SALT_WORKS:     [WorldGrid.TileType.COAST],
}

## Optional flat efficiency bonus granted when the building has ≥1 adjacent WATER tile.
## NOT a placement requirement and NOT stacking — any amount of adjacent water grants the
## single flat bonus once (e.g. the Mill: +0.20 / +20% next to water).
const WATER_ADJACENCY_BONUS: Dictionary = {
	BuildingType.MILL: 0.20,
}

## Buildings in ADJACENCY_REQUIREMENTS whose adjacent tile count does NOT contribute to
## the resource_tiles efficiency bonus. The adjacency is a placement-only constraint.
## (Normal case: FISHING_HUT scales efficiency with water tile count — that is intentional.
##  Exception: CHARCOAL_KILN requires water for thematic/placement reasons only.)
const ADJACENCY_PLACEMENT_ONLY: Dictionary = {
	BuildingType.CHARCOAL_KILN: true,
}

## Maps WorldGrid.TileType → resource output produced per cycle by GATHERING_HUT.
const TERRAIN_HARVEST_OUTPUT: Dictionary = {
	WorldGrid.TileType.BERRY: {&"berry": 4},
	WorldGrid.TileType.GRASS: {&"fiber": 2},
	WorldGrid.TileType.WHEAT: {&"wheat": 5},
}

## Reverse of TERRAIN_HARVEST_OUTPUT: resource ID → terrain type required to harvest it.
## Used to compute per-recipe adjacency_tile_count for GATHERING_HUT efficiency.
const HARVEST_RESOURCE_TO_TERRAIN: Dictionary = {
	&"berry": WorldGrid.TileType.BERRY,
	&"fiber": WorldGrid.TileType.GRASS,
	&"wheat": WorldGrid.TileType.WHEAT,
}

## Formula 7 scalar: energy cost per resource unit in build cost.
const ENERGY_PER_RESOURCE: float = 0.10

## NPC spawn interval for Residential House (Formula 8), in ticks.
const NPC_SPAWN_INTERVAL: int = 1000

## Maximum NPCs a Residential House can house.
const MAX_HOUSE_NPCS: int = 2

## Legacy alias: maps each type to the same keys as its default recipe (index 0).
## Used only for .has() "is this a production building?" checks in external callers.
## For recipe data always use get_active_recipe() or RECIPES directly.
const PRODUCTION_TABLE: Dictionary = {
	BuildingType.LUMBER_CAMP:    true,
	BuildingType.STONE_MASON:    true,
	BuildingType.GATHERING_HUT:  true,
	BuildingType.TOOL_WORKSHOP:  true,
	BuildingType.WEAVER:         true,
	BuildingType.TAILOR:         true,
	BuildingType.SAWMILL:        true,
	BuildingType.HUNTING_LODGE:  true,
	BuildingType.FARM:           true,
	BuildingType.MILL:           true,
	BuildingType.BAKERY:         true,
	BuildingType.CLAY_PIT:       true,
	BuildingType.POTTERY_KILN:        true,
	BuildingType.TANNERY:             true,
	BuildingType.BOWYERS_WORKSHOP:    true,
	BuildingType.CARPENTER:           true,
	BuildingType.FISHING_HUT:         true,
	BuildingType.BRICK_KILN:          true,
	BuildingType.CHARCOAL_KILN:       true,
	BuildingType.SALT_WORKS:          true,
	BuildingType.PRESERVATION_HOUSE:  true,
}

# ---- Signals ----------------------------------------------------------------

signal building_placed(building_id: String, type: int, tile: Vector2i)
signal building_construction_complete(building_id: String, type: int)
signal building_state_changed(building_id: String, new_state: int, reason: String)
signal building_input_changed(building_id: String)
## Emitted when a production cycle completes and output is placed in buffered_output.
## `cycle_ticks` is the cycle's nominal (efficiency-independent) base duration, used by the
## Experience System to grant time-based work XP (ExperienceFormulas.xp_for_duration).
signal production_output_ready(building_id: String, output: Dictionary[StringName, int], cycle_ticks: int)
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
## Emitted when set_active_recipe() successfully switches the recipe for a building.
signal building_recipe_changed(building_id: String, recipe_index: int)
## Emitted when a per-resource delivery limit is set on a storage building.
signal building_storage_limit_changed(building_id: String, resource_id: StringName, limit: int)
## Emitted when a per-resource minimum reserve is set on a storage building.
signal building_storage_min_limit_changed(building_id: String, resource_id: StringName, limit: int)
## Emitted when an upgrade has been successfully installed on a building.
signal upgrade_installed(building_id: String, upgrade_id: StringName)
## Emitted when an upgrade is removed from a building (e.g. building demolished).
signal upgrade_removed(building_id: String, upgrade_id: StringName)

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
		_tick_system.day_transition.connect(_on_day_transition)
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
	# Progression gate (command layer): reject types not yet unlocked in the tech tree.
	# Unknown/ungated types default to unlocked (see ProgressionSystem.is_building_unlocked).
	if not ProgressionSystem.is_building_unlocked(building_type):
		return PlacementResult.LOCKED
	var grid_result: int = _validate_grid_placement(tile, building_type)
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
	var place_result: int = _place_building_on_grid(building_type, tile, building_id)
	if place_result != 0:
		_build_counter -= 1
		return place_result
	_deduct_build_cost(building_type)
	var instance: BuildingInstance = _create_instance(building_id, building_type, tile)
	_refresh_water_bonus(instance)
	_spawn_visual(instance)
	_insert_sorted(instance)
	building_placed.emit(building_id, building_type, tile)
	return PlacementResult.SUCCESS


## Grid placement validity, routed by domain: the Bridge is the only water-placed building
## (terrain MUST be WATER); every other type uses the standard land validation (terrain EMPTY).
func _validate_grid_placement(tile: Vector2i, building_type: int) -> int:
	if building_type == BuildingType.BRIDGE:
		return _grid.validate_water_placement(tile)
	return _grid.validate_placement(tile, building_type)


## Commits a building to the grid layer, routing the Bridge onto its water-placement path.
func _place_building_on_grid(building_type: int, tile: Vector2i, building_id: String) -> int:
	if building_type == BuildingType.BRIDGE:
		return _grid.place_building_on_water(tile, building_id)
	return _grid.place_building(tile, building_id)


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


## Returns the BuildingInstance whose tile matches, or null.
## Requires _grid to be initialised (call init_dependencies first).
func get_instance_at_tile(tile: Vector2i) -> BuildingInstance:
	if _grid == null:
		return null
	var building_id: String = _grid.get_building(tile)
	if building_id == "":
		return null
	return get_building_instance(building_id)


## Instantly transitions a CONSTRUCTING building to OPERATING.
## Called by PlayerCharacter when the manual CONSTRUCT_BUILDING action completes.
func complete_construction_manually(building_id: String) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null or instance.state != BuildingInstance.State.CONSTRUCTING:
		return
	instance.accumulated_ticks = instance.build_time
	instance.state = BuildingInstance.State.OPERATING
	_update_adjacency_efficiency(instance)
	building_construction_complete.emit(instance.building_id, instance.type)
	building_state_changed.emit(instance.building_id, instance.state, "construction_complete")
	if instance.type == BuildingType.RESIDENTIAL_HOUSE:
		instance.npc_count = 1
		instance.npc_spawn_timer = 0


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
	var allowed: Array[StringName] = get_active_input_resource_ids(building_id)
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
	var allowed: Array[StringName] = get_active_input_resource_ids(building_id)
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
	var allowed: Array[StringName] = get_active_input_resource_ids(building_id)
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
	return _validate_grid_placement(tile, building_type)


## Full pre-flight check: grid + adjacency + resource affordability + energy. No side effects.
func check_build_conditions(building_type: int, tile: Vector2i) -> int:
	if _grid == null:
		return PlacementResult.BLOCKED_BY_BOUNDS
	if not ProgressionSystem.is_building_unlocked(building_type):
		return PlacementResult.LOCKED
	var grid_result: int = _validate_grid_placement(tile, building_type)
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

# ---- Recipe API -------------------------------------------------------------

## Returns true when building_type is a production building (has at least one recipe).
func is_production_building(building_type: int) -> bool:
	return RECIPES.has(building_type)


## Returns all recipe dicts for building_type; empty array if not a production building.
func get_recipes(building_type: int) -> Array:
	return RECIPES.get(building_type, [])


## Returns the indices of recipes currently available given terrain / building conditions.
## For GATHERING_HUT: only recipes whose output resource is present in gathering_output.
## For all other production buildings: all recipe indices.
func get_available_recipe_indices(building_id: String) -> Array[int]:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return []
	var recipes: Array = RECIPES.get(instance.type, [])
	if recipes.is_empty():
		return []
	if instance.type != BuildingType.GATHERING_HUT and instance.type != BuildingType.FARM:
		var all_indices: Array[int] = []
		for i: int in range(recipes.size()):
			all_indices.append(i)
		return all_indices
	var result: Array[int] = []
	for i: int in range(recipes.size()):
		for res_id: StringName in recipes[i].get("output", {}).keys():
			if instance.gathering_output.has(res_id):
				result.append(i)
				break
	return result


## Returns the active recipe dict for instance. Falls back to index 0 on out-of-range.
func get_active_recipe(instance: BuildingInstance) -> Dictionary:
	var recipes: Array = RECIPES.get(instance.type, [])
	if recipes.is_empty():
		return {}
	return recipes[clampi(instance.active_recipe_index, 0, recipes.size() - 1)]


## Returns the resource IDs accepted as input by the given building's active recipe.
func get_active_input_resource_ids(building_id: String) -> Array[StringName]:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return []
	var result: Array[StringName] = []
	for spec: Dictionary in get_active_recipe(instance).get("inputs", []):
		result.append(spec["resource_id"])
	return result


## Switches the active recipe for a building. Aborts any running cycle immediately.
## Buffer items no longer needed by the new recipe are dropped at the building's tile.
## Returns false when building_id is invalid or recipe_index is out of range.
func set_active_recipe(building_id: String, recipe_index: int) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	var recipes: Array = RECIPES.get(instance.type, [])
	if recipe_index < 0 or recipe_index >= recipes.size():
		return false
	# The player has now made an explicit choice — even if it matches the default.
	instance.recipe_selected = true
	if instance.active_recipe_index == recipe_index:
		return true
	# Abort any running cycle — inputs consumed this cycle are gone.
	instance.cycle_running = false
	instance.production_cycle_ticks = 0
	instance.production_cycle_duration = 0
	instance.input_pending = false
	# Determine which resources the new recipe still accepts.
	var new_input_ids: Array[StringName] = []
	for spec: Dictionary in recipes[recipe_index].get("inputs", []):
		new_input_ids.append(spec["resource_id"])
	# Drop buffer items that don't match the new recipe's inputs.
	var drop_items: Dictionary = {}
	for res_id: StringName in instance.input_buffer.keys():
		if res_id not in new_input_ids:
			var qty: int = ceili(instance.input_buffer[res_id])
			if qty > 0:
				drop_items[res_id] = drop_items.get(res_id, 0) + qty
			instance.input_buffer.erase(res_id)
	if not drop_items.is_empty():
		building_items_dropped.emit(instance.tile, drop_items)
	instance.active_recipe_index = recipe_index
	if instance.type == BuildingType.GATHERING_HUT or instance.type == BuildingType.FARM:
		_update_adjacency_efficiency(instance)
	building_input_changed.emit(building_id)
	building_recipe_changed.emit(building_id, recipe_index)
	return true

# ---- Tick handler -----------------------------------------------------------

func _on_ticks_advanced(delta: int) -> void:
	for instance: BuildingInstance in _all_buildings:
		if instance.state == BuildingInstance.State.DEMOLISHED:
			continue
		if instance.state == BuildingInstance.State.CONSTRUCTING:
			continue  # construction is now a manual player action
		if instance.type == BuildingType.RESIDENTIAL_HOUSE and instance.state == BuildingInstance.State.OPERATING:
			_advance_npc_timer(instance, delta)
			continue
		if instance.state == BuildingInstance.State.OPERATING and RECIPES.has(instance.type):
			_advance_production_cycle(instance, delta)
		elif instance.state == BuildingInstance.State.BLOCKED and RECIPES.has(instance.type):
			_try_recover_blocked(instance)


		building_npc_spawn_requested.emit(instance.building_id, instance.tile, 1)


## Snapshots each building's per-day production time into util_active_ticks_last_day,
## then resets the accumulator. Called once per game-day via TickSystem.day_transition.
func _on_day_transition(_days_elapsed: int) -> void:
	for instance: BuildingInstance in _all_buildings:
		instance.util_active_ticks_last_day = instance.util_active_ticks_today
		instance.util_data_available = true
		instance.util_active_ticks_today = 0


## Returns the building's utilization for the last complete day as a fraction in [0, 1]:
## the share of the day it spent actively producing (100% = produced all day).
## Returns -1.0 if no full day has elapsed yet (caller should show "—").
func get_building_utilization(building_id: String) -> float:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null or not instance.util_data_available:
		return -1.0
	if _tick_system == null or _tick_system.TICKS_PER_DAY <= 0:
		return -1.0
	return clampf(float(instance.util_active_ticks_last_day) / float(_tick_system.TICKS_PER_DAY), 0.0, 1.0)


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
				var reason: String = _cycle_blocked_reason(result, instance)
				building_blocked.emit(instance.building_id, reason)
				building_state_changed.emit(instance.building_id, instance.state, reason)
		return
	instance.production_cycle_ticks += delta
	# Utilization: count every tick spent advancing an active cycle (blocked/idle ticks don't count).
	instance.util_active_ticks_today += delta
	# F3 (live): recompute the effective duration from the CURRENT building efficiency every tick,
	# so feeding / placement changes affect the in-progress cycle immediately (not only the next
	# one). base / efficiency: eff 1.0 → base, eff 0.5 → 2× base, eff 0.25 → 4× base.
	var _active_recipe: Dictionary = get_active_recipe(instance)
	if not _active_recipe.is_empty():
		instance.production_cycle_duration = EfficiencyFormulas.calculate_effective_cycle_ticks(
				_active_recipe.get("base_cycle_ticks", 0), instance.efficiency)
	if instance.production_cycle_ticks < instance.production_cycle_duration:
		return
	# Cycle complete — deposit output to buffer.
	var cycle_output: Dictionary = _active_recipe.get("output", {})
	for resource_id: StringName in cycle_output:
		instance.buffered_output[resource_id] = instance.buffered_output.get(resource_id, 0) + cycle_output[resource_id]
	# Perk #6 (Ergiebig): +output for this building type while a perked NPC is supplied today.
	var output_bonus: int = int(_perk_building_bonus(instance.type, PerkRegistry.EFFECT_OUTPUT_BONUS))
	if output_bonus > 0 and not cycle_output.is_empty():
		var primary: StringName = cycle_output.keys()[0]
		instance.buffered_output[primary] = instance.buffered_output.get(primary, 0) + output_bonus
	instance.cycle_running = false
	instance.production_cycle_ticks = 0
	instance.cycle_count += 1  # Perk #8: drives the "every 4th cycle is input-free" cadence.
	# Inputs delivered mid-cycle set input_pending to delay same-tick consumption.
	# After a full cycle the delay is no longer needed — clear it so the restart
	# attempt below can succeed without waiting an extra tick.
	instance.input_pending = false
	production_output_ready.emit(instance.building_id, instance.buffered_output,
			int(_active_recipe.get("base_cycle_ticks", 0)))
	# Attempt next cycle immediately so cycle_running is true again before the
	# indicator refresh fires — prevents a one-tick yellow flash between cycles.
	_advance_production_cycle(instance, 0)

# ---- Helpers ----------------------------------------------------------------

## Returns BLOCKED_BY_ADJACENCY when building_type has adjacency requirements and no
## neighbor (cardinal or diagonal) of tile satisfies them. Returns SUCCESS when met or absent.
func _check_adjacency(building_type: int, tile: Vector2i) -> int:
	# Bridge: must span between two opposite passable tiles (a real crossing).
	if building_type == BuildingType.BRIDGE:
		return _check_bridge_connects(tile)
	if not ADJACENCY_REQUIREMENTS.has(building_type):
		return PlacementResult.SUCCESS
	# Hunting Lodge: must border a forest that currently contains wild (not just any tree).
	if building_type == BuildingType.HUNTING_LODGE:
		if WildSystem.forest_has_wild_adjacent(tile):
			return PlacementResult.SUCCESS
		return PlacementResult.BLOCKED_BY_ADJACENCY
	var required_types: Array = ADJACENCY_REQUIREMENTS[building_type]
	for neighbor: Vector2i in _grid.get_neighbors(tile, true):
		if _grid.get_terrain(neighbor) in required_types:
			return PlacementResult.SUCCESS
	return PlacementResult.BLOCKED_BY_ADJACENCY


## A bridge must directly connect two opposite passable tiles (left+right OR up+down) — a real
## crossing, not a tile floating in open water. is_tile_passable counts existing bridges/roads
## as shore, so the player can chain bridges across wider water one tile at a time.
func _check_bridge_connects(tile: Vector2i) -> int:
	var horizontal: bool = _grid.is_tile_passable(tile + Vector2i(-1, 0)) \
			and _grid.is_tile_passable(tile + Vector2i(1, 0))
	var vertical: bool = _grid.is_tile_passable(tile + Vector2i(0, -1)) \
			and _grid.is_tile_passable(tile + Vector2i(0, 1))
	if horizontal or vertical:
		return PlacementResult.SUCCESS
	return PlacementResult.BLOCKED_BY_ADJACENCY


## Validates resource and energy affordability for building_type. No side effects.
func _check_resource_and_energy(building_type: int) -> int:
	var cost: Dictionary = BUILD_COST.get(building_type, {})
	for resource_id: StringName in cost:
		if _get_total_resource(resource_id) < cost[resource_id]:
			return PlacementResult.INSUFFICIENT_RESOURCES
	var energy_cost: int = BUILD_ENERGY.get(building_type, 0)
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
	if not RECIPES.has(instance.type):
		return _CycleStartResult.OUTPUT_FULL
	if instance.input_pending:
		instance.input_pending = false
		return _CycleStartResult.OUTPUT_FULL  # skip this tick without entering BLOCKED
	var table_entry: Dictionary = get_active_recipe(instance)
	# Perk #10 (Geräumig): an active building-bound perk raises this type's output buffer cap.
	var output_capacity: int = int(round(float(table_entry.get("output_capacity", 0))
			* (1.0 + _perk_building_bonus(instance.type, PerkRegistry.EFFECT_OUTPUT_CAPACITY))))
	var buffered_total: int = 0
	for qty: int in instance.buffered_output.values():
		buffered_total += qty
	if buffered_total >= output_capacity:
		return _CycleStartResult.OUTPUT_FULL
	# Production requires the assigned worker to be physically on-site, not merely assigned.
	# A freshly-assigned worker is still TRAVEL_TO_BUILDING for several ticks — the building
	# must not produce until they actually arrive (NPCSystem state WORK_AT_BUILDING).
	if table_entry.get("npc_required", false) and not _worker_present(instance):
		return _CycleStartResult.BLOCKED_NO_NPC
	if instance.type == BuildingType.GATHERING_HUT or instance.type == BuildingType.FARM:
		var terrain_match := false
		for res_id: StringName in table_entry.get("output", {}).keys():
			if instance.gathering_output.has(res_id):
				terrain_match = true
				break
		if not terrain_match:
			return _CycleStartResult.BLOCKED_NO_INPUT
	# Perk #8 (Sparsam): every 4th cycle of this building type runs without consuming input.
	var skip_input: bool = _building_skips_input(instance) and (instance.cycle_count % 4 == 3)
	if not skip_input:
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
	# F3 wired (balancing 2026-06-11): effective cycle = base / building_efficiency.
	# Hungry/poorly-placed buildings now actually run slower; well-fed/placed run faster.
	instance.production_cycle_duration = EfficiencyFormulas.calculate_effective_cycle_ticks(
			table_entry.get("base_cycle_ticks", 0), instance.efficiency)
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
## For BLOCKED_NO_NPC, distinguishes an unassigned building from one whose worker is en route.
func _cycle_blocked_reason(result: int, instance: BuildingInstance = null) -> String:
	match result:
		_CycleStartResult.BLOCKED_NO_NPC:
			if instance != null and instance.assigned_npc_id != &"":
				return "Worker not on-site"
			return "No NPC assigned"
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
	if not RECIPES.has(instance.type):
		return false
	var input_capacity: int = get_active_recipe(instance).get("input_capacity", 0)
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

## Returns the NPCInstance array for the worker assigned to instance, or [] if none.
## Lazily acquires NPCSystem via Engine (load order: Buildings → NPCs, so no _enter_tree lookup).
## Injectable via _npc_system for unit tests.
func _get_assigned_workers(instance: BuildingInstance) -> Array:
	if instance.assigned_npc_id == &"":
		return []
	# Direct Autoload access — Engine.get_singleton() returns null for GDScript Autoloads
	# (forbidden pattern, see .claude/rules/godot-singletons.md). This bug made the worker drop
	# out of building-efficiency recalcs at assign/adjacency time, so NPC efficiency didn't reach
	# production. _npc_system stays injectable for tests; fall back to the NPCSystem Autoload.
	var npc_sys: Object = _npc_system if _npc_system != null else NPCSystem
	if npc_sys == null:
		return []
	var npc: Object = npc_sys.get_npc_instance(instance.assigned_npc_id)
	if npc == null:
		return []
	return [npc]


## Returns true when this building's assigned worker is physically on-site and able to work.
## "On-site" = NPCSystem reports the worker in TaskState.WORK_AT_BUILDING (reached after travel).
## Falls back to true when the NPC is not tracked by NPCSystem (unit-test fixtures inject raw
## assigned_npc_id values with no backing NPCInstance) so legacy "assigned ⇒ working" tests hold.
func _worker_present(instance: BuildingInstance) -> bool:
	if instance.assigned_npc_id == &"":
		return false
	var npc_sys: Object = _npc_system if _npc_system != null else NPCSystem
	if npc_sys == null:
		return true
	var npc: Object = npc_sys.get_npc_instance(instance.assigned_npc_id)
	if npc == null:
		return true  # untracked fixture id — preserve legacy behaviour
	return npc.state == NPCSystem.TaskState.WORK_AT_BUILDING


## Sum of active building-bound perk magnitudes for `building_type` with `effect` (Perk System).
## Reads NPCSystem's per-day active-perk state; 0.0 when unavailable.
func _perk_building_bonus(building_type: int, effect: StringName) -> float:
	var npc_sys: Object = _npc_system if _npc_system != null else NPCSystem
	if npc_sys == null:
		return 0.0
	return npc_sys.building_perk_bonus(building_type, effect)


## True if a building of this type has an active Sparsam (input-skip) perk (Perk System #8).
func _building_skips_input(instance: BuildingInstance) -> bool:
	var npc_sys: Object = _npc_system if _npc_system != null else NPCSystem
	return npc_sys != null and npc_sys.building_has_active_perk(instance.type, PerkRegistry.EFFECT_INPUT_SKIP)


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


## Updates adjacency_tile_count for instance and recalculates efficiency (additive F2: +5%/tile).
## No-op when the building type has no adjacency requirements or _grid is not set.
func _update_adjacency_efficiency(instance: BuildingInstance) -> void:
	if not ADJACENCY_REQUIREMENTS.has(instance.type):
		return
	if _grid == null:
		return
	# Hunting Lodge efficiency scales with the number of wild groups in the adjacent forest(s),
	# fed through the additive model as the "resource tiles" term (ADR-0015).
	if instance.type == BuildingType.HUNTING_LODGE:
		instance.adjacency_tile_count = WildSystem.count_groups_adjacent(instance.tile)
		instance.recalculate_efficiency(_get_assigned_workers(instance))
		return
	if instance.type == BuildingType.GATHERING_HUT or instance.type == BuildingType.FARM:
		# Count only tiles relevant to the active recipe's output so efficiency
		# reflects the currently harvested terrain type, not all harvestable tiles.
		var active_recipe: Dictionary = get_active_recipe(instance)
		var recipe_terrains: Array = []
		for res_id: StringName in active_recipe.get("output", {}).keys():
			if HARVEST_RESOURCE_TO_TERRAIN.has(res_id):
				recipe_terrains.append(HARVEST_RESOURCE_TO_TERRAIN[res_id])
		var count: int = 0
		for neighbor: Vector2i in _grid.get_neighbors(instance.tile, true):
			if _grid.get_terrain(neighbor) in recipe_terrains:
				count += 1
		instance.adjacency_tile_count = count
		instance.recalculate_efficiency(_get_assigned_workers(instance))
		_update_gathering_output(instance)
		return
	var required_types: Array = ADJACENCY_REQUIREMENTS[instance.type]
	var count: int = 0
	for neighbor: Vector2i in _grid.get_neighbors(instance.tile, true):
		if _grid.get_terrain(neighbor) in required_types:
			count += 1
	instance.adjacency_tile_count = count
	instance.recalculate_efficiency(_get_assigned_workers(instance))


## Sets the optional water-adjacency efficiency bonus (WATER_ADJACENCY_BONUS) on the instance.
## Grants the flat bonus when ≥1 neighbour (8-way, the project's adjacency convention) is WATER;
## 0.0 otherwise or for types without a water bonus. Water terrain is static, so this only needs
## to run once at placement (and on load). Recalculates efficiency so the bonus takes effect.
func _refresh_water_bonus(instance: BuildingInstance) -> void:
	instance.water_bonus = _compute_water_bonus(instance.type, instance.tile)
	instance.recalculate_efficiency(_get_assigned_workers(instance))


## Returns the flat water-adjacency bonus for a building type at tile (0.0 if it has none or
## has no adjacent water). Pure read — used on load to restore water_bonus without recomputing
## efficiency (the saved efficiency value already accounts for it).
func _compute_water_bonus(building_type: int, tile: Vector2i) -> float:
	var bonus: float = WATER_ADJACENCY_BONUS.get(building_type, 0.0)
	if bonus <= 0.0 or _grid == null:
		return 0.0
	return bonus if _has_adjacent_water(tile) else 0.0


## Returns true if any 8-way neighbour of tile is a WATER terrain tile.
func _has_adjacent_water(tile: Vector2i) -> bool:
	for neighbor: Vector2i in _grid.get_neighbors(tile, true):
		if _grid.get_terrain(neighbor) == WorldGrid.TileType.WATER:
			return true
	return false


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


## Recomputes efficiency for all Hunting Lodges from the current wild-group counts.
## Connected to WildSystem.wild_changed (groups spawned / moved / pruned each day).
func refresh_wild_efficiency() -> void:
	for instance: BuildingInstance in _all_buildings:
		if instance.type != BuildingType.HUNTING_LODGE:
			continue
		if instance.state == BuildingInstance.State.DEMOLISHED:
			continue
		instance.adjacency_tile_count = WildSystem.count_groups_adjacent(instance.tile)
		instance.recalculate_efficiency(_get_assigned_workers(instance))
		building_state_changed.emit(instance.building_id, instance.state, "wild_efficiency")


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
		BuildingType.WEAVER:            return "Weaver"
		BuildingType.TAILOR:            return "Tailor"
		BuildingType.SAWMILL:           return "Sawmill"
		BuildingType.HUNTING_LODGE:     return "Hunting Lodge"
		BuildingType.FARM:              return "Farm"
		BuildingType.MILL:              return "Mill"
		BuildingType.BAKERY:            return "Bakery"
		BuildingType.CLAY_PIT:          return "Clay Pit"
		BuildingType.POTTERY_KILN:       return "Pottery Kiln"
		BuildingType.TANNERY:            return "Tannery"
		BuildingType.BOWYERS_WORKSHOP:   return "Bowyer's Workshop"
		BuildingType.BRIDGE:             return "Bridge"
		BuildingType.CARPENTER:          return "Carpenter's Workshop"
		BuildingType.FISHING_HUT:        return "Fishing Hut"
		BuildingType.BRICK_KILN:         return "Brick Kiln"
		BuildingType.CHARCOAL_KILN:      return "Charcoal Kiln"
		BuildingType.SALT_WORKS:         return "Salt Works"
		BuildingType.PRESERVATION_HOUSE: return "Preservation House"
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


## Sets a per-resource delivery limit on a storage building.
## limit < 0 removes the limit (transport routes may deliver freely).
## limit = 0 blocks all deliveries. limit > 0 caps deliveries at that quantity.
## No-op if the building does not exist or is not a storage building.
func set_storage_limit(building_id: String, resource_id: StringName, limit: int) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return
	if not STORAGE_CAPACITY.has(instance.type):
		return
	if limit < 0:
		instance.storage_limits.erase(resource_id)
	else:
		instance.storage_limits[resource_id] = limit
	building_storage_limit_changed.emit(building_id, resource_id, limit)


## Returns the delivery limit for a resource in a storage building (-1 = no limit).
func get_storage_limit(building_id: String, resource_id: StringName) -> int:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return -1
	return instance.storage_limits.get(resource_id, -1)


## Sets a per-resource minimum reserve on a storage building.
## limit < 0 removes the minimum (transport may take freely).
## limit >= 0 ensures at least that many items stay in storage.
func set_storage_min_limit(building_id: String, resource_id: StringName, limit: int) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return
	if not STORAGE_CAPACITY.has(instance.type):
		return
	if limit < 0:
		instance.storage_min_limits.erase(resource_id)
	else:
		instance.storage_min_limits[resource_id] = limit
	building_storage_min_limit_changed.emit(building_id, resource_id, limit)


## Returns the minimum reserve for a resource in a storage building (-1 = no minimum).
func get_storage_min_limit(building_id: String, resource_id: StringName) -> int:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return -1
	return instance.storage_min_limits.get(resource_id, -1)


## Returns the display name for a building: custom_name if set, otherwise the type name.
func get_building_display_name(building_id: String) -> String:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return building_id
	if instance.custom_name != "":
		return instance.custom_name
	return _building_type_name(instance.type)


## Returns the display name for a BuildingType enum value (e.g. for build menus / UI).
## Single source of truth for type names; works without a placed instance.
func get_type_display_name(building_type: int) -> String:
	return _building_type_name(building_type)


## Returns the Texture2D for a building type from BUILDING_TEXTURES, or null if missing.
func get_building_texture(building_type: int) -> Texture2D:
	var path: String = BUILDING_TEXTURES.get(building_type, "")
	if path == "":
		return null
	return load(path) as Texture2D


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

	for upg: StringName in instance.active_upgrades:
		upgrade_removed.emit(str(building_id), upg)

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
		# Worker removed mid-cycle (released / reassigned / demolished): abort the running
		# cycle so it cannot finish unmanned. Inputs already consumed this cycle are forfeit.
		if npc_id == &"" and instance.cycle_running:
			instance.cycle_running = false
			instance.production_cycle_ticks = 0
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


## Returns the upgrade definitions available for a building (may be empty).
func get_available_upgrades(building_id: String) -> Array:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return []
	# Progression gate: only offer upgrades whose Progression Tree node is unlocked.
	var result: Array = []
	for upgrade: Dictionary in BUILDING_UPGRADES.get(instance.type, []):
		if ProgressionSystem.is_upgrade_unlocked(upgrade.get(&"id", &"")):
			result.append(upgrade)
	return result


## Returns true if the building has the named upgrade installed.
func has_upgrade(building_id: String, upgrade_id: StringName) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	return instance.has_upgrade(upgrade_id)


## Installs an upgrade on a building. Does NOT deduct resources — caller must do that.
## Returns true on success, false if already installed or building/upgrade not found.
func install_upgrade(building_id: String, upgrade_id: StringName) -> bool:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		return false
	if instance.has_upgrade(upgrade_id):
		return false
	var defs: Array = BUILDING_UPGRADES.get(instance.type, [])
	var found := false
	for d: Dictionary in defs:
		if d.get(&"id", &"") == upgrade_id:
			found = true
			break
	if not found:
		return false
	instance.active_upgrades.append(upgrade_id)
	upgrade_installed.emit(building_id, upgrade_id)
	return true


## Returns all building IDs that have the named upgrade installed.
func get_buildings_with_upgrade(upgrade_id: StringName) -> Array[String]:
	var result: Array[String] = []
	for instance: BuildingInstance in _all_buildings:
		if instance.has_upgrade(upgrade_id):
			result.append(instance.building_id)
	return result


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
		var storage_lim: Dictionary = {}
		for k: StringName in instance.storage_limits:
			storage_lim[str(k)] = instance.storage_limits[k]
		var storage_min_lim: Dictionary = {}
		for k: StringName in instance.storage_min_limits:
			storage_min_lim[str(k)] = instance.storage_min_limits[k]
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
			"util_active_ticks_today": instance.util_active_ticks_today,
			"util_active_ticks_last_day": instance.util_active_ticks_last_day,
			"util_data_available": instance.util_data_available,
			"adjacency_tile_count": instance.adjacency_tile_count,
			"active_recipe_index": instance.active_recipe_index,
			"recipe_selected": instance.recipe_selected,
			"active_upgrades": instance.active_upgrades.map(func(u: StringName) -> String: return str(u)),
			"storage_limits": storage_lim,
			"storage_min_limits": storage_min_lim,
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
			_place_building_on_grid(type, tile, building_id)
		var instance := BuildingInstance.new(building_id, type, tile)
		instance.water_bonus = _compute_water_bonus(type, tile)
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
		instance.util_active_ticks_today = bd.get("util_active_ticks_today", 0)
		instance.util_active_ticks_last_day = bd.get("util_active_ticks_last_day", 0)
		instance.util_data_available = bd.get("util_data_available", false)
		instance.adjacency_tile_count = bd.get("adjacency_tile_count", 0)
		instance.active_recipe_index = bd.get("active_recipe_index", 0)
		# Default true so buildings from older saves don't re-prompt for a recipe.
		instance.recipe_selected = bd.get("recipe_selected", true)
		for u: String in bd.get("active_upgrades", []):
			if u != "":
				instance.active_upgrades.append(StringName(u))
		var sl: Dictionary = bd.get("storage_limits", {})
		for k: String in sl:
			instance.storage_limits[StringName(k)] = int(sl[k])
		var sml: Dictionary = bd.get("storage_min_limits", {})
		for k: String in sml:
			instance.storage_min_limits[StringName(k)] = int(sml[k])
		_insert_sorted(instance)
		if instance.type == BuildingType.GATHERING_HUT or instance.type == BuildingType.FARM:
			_update_gathering_output(instance)
		building_placed.emit(building_id, type, tile)
