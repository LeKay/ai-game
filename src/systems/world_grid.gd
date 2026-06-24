class_name WorldGrid extends Node
## Grid world data model — single source of truth for terrain, resource, and building state.
## ADR-0004: 30x30 three-layer model. TileMapLayer nodes are rendering targets only.
## Not an Autoload — instantiated as a child of MapRoot.

const GRID_SIZE: int = 30
const TILE_SIZE: int = 64  # pixels per tile
const MAX_RESOURCES_PER_TILE: int = 4

## Layer identifiers for terrain_changed signal.
const BUILDING_LAYER: int = 1
const RESOURCE_LAYER: int = 2

## WHEAT and CLAY are appended last so existing TileType integer values are unchanged.
## They are placed post-generation (wheat fields / revealed clay pits), never by noise.
## WATER (ordinal 8) is carved in a dedicated generation step; impassable and non-buildable.
## Rivers may split the map — crossing water is done by building a Bridge (a BuildingType
## placed on a WATER tile), not by a terrain type.
## COAST (ordinal 9) is carved in the same pass as WATER but marks ocean coastline
## specifically — distinguishable from river/lake WATER, required by SALT_WORKS.
## IRON..GEMSTONE (ordinals 10-15) are revealed ore/gem pit tiles, mechanical siblings of
## CLAY: hidden at generation, exposed by the Search action, then hand-mined. Appended last so
## existing integer values (and saved terrain) are unchanged.
## FLAX..PEARL (ordinals 16-24) are the second fertility wave (ADR-0015 addendum 2026-06-23):
##   FLAX/HOPS/GRAPES — opaque field crops placed on EMPTY tiles (wheat-like).
##   SAND            — opaque beach tile placed on land bordering WATER/COAST.
##   OLIVE/BEES      — transparent overlay sprites placed on EMPTY tiles (composited over sand).
##   MARBLE          — transparent overlay sprite ("like stone"), mountain-biased.
##   AMBER           — hidden deposit (clay-like): Search reveals it as an AMBER overlay.
##   PEARL           — visible overlay on the ocean (COAST base); impassable like water.
## All appended last so existing integer values (and saved terrain) are unchanged.
enum TileType { EMPTY, TREE, STONE, BERRY, GRASS, IMPASSABLE, WHEAT, CLAY, WATER, COAST,
		IRON, COPPER, TIN, SILVER, GOLD, GEMSTONE,
		FLAX, HOPS, GRAPES, SAND, OLIVE, BEES, MARBLE, AMBER, PEARL }

enum PlacementResult {
	SUCCESS,
	BLOCKED_BY_BOUNDS,
	BLOCKED_BY_IMPASSABLE,
	BLOCKED_BY_BUILDING,
	BLOCKED_BY_RESOURCE_TILE
}

enum DistanceMetric { MANHATTAN, EUCLIDEAN }

## Terrain bias driven by the overworld biome of the tile this map represents. Shifts the
## elevation bands in _sample_noise: FOREST grows the TREE band; MOUNTAIN grows STONE and adds
## IMPASSABLE rocky peaks. PLAINS leaves the original behaviour untouched. Kept WorldGrid-local
## (no OverworldSystem dependency) so the generator stays standalone-testable.
enum TerrainProfile { PLAINS, FOREST, MOUNTAIN }

## Elevation band cutoffs per profile: [impassable_lo, veg_lo, empty_hi, tree_hi, stone_hi].
## elev < impassable_lo → IMPASSABLE; < veg_lo → BERRY/GRASS (by moisture); < empty_hi → EMPTY;
## < tree_hi → TREE; < stone_hi → STONE; ≥ stone_hi → IMPASSABLE (rocky peak).
## PLAINS uses stone_hi = 1.01 so the peak branch is unreachable — byte-identical to the
## original thresholds (0.15 / 0.30 / 0.55 / 0.75, else STONE).
const _ELEV_BANDS: Dictionary = {
	TerrainProfile.PLAINS:   [0.15, 0.30, 0.55, 0.68, 1.01],  # tree_hi lowered 0.75→0.68 (~35% fewer trees)
	TerrainProfile.FOREST:   [0.15, 0.30, 0.45, 0.82, 1.01],
	TerrainProfile.MOUNTAIN: [0.12, 0.24, 0.40, 0.47, 0.82],  # tree_hi lowered 0.58→0.47 (~61% fewer trees)
}

## Tile types that cluster exclusively with their own kind during smoothing.
## Cross-type neighbors are treated as EMPTY so BERRY/STONE/GRASS don't absorb one another.
const _EXCLUSIVE_CLUSTER_TYPES: Array[int] = [TileType.BERRY, TileType.STONE, TileType.GRASS]

## Resource data for a single tile. Null when the tile has no resource.
class ResourceTileData:
	var resource_id: StringName
	var clearable: bool

	func _init(p_resource_id: StringName, p_clearable: bool) -> void:
		resource_id = p_resource_id
		clearable = p_clearable

## Read-only snapshot of all three layers at a single tile position.
class TileView:
	var terrain: TileType
	var resources: Array  ## Array[ResourceTileData], empty when tile has no resources
	var building_id: String

	func _init(p_terrain: TileType, p_resources: Array, p_building_id: String) -> void:
		terrain = p_terrain
		resources = p_resources
		building_id = p_building_id

## Emitted when a terrain tile type changes at runtime (e.g. via clear_terrain_tile or seed growth).
## Listeners can use this to update systems that depend on terrain adjacency.
signal terrain_tile_changed(tile: Vector2i)

## Emitted when the BuildingLayer or ResourceLayer changes at pos.
## layer is BUILDING_LAYER or RESOURCE_LAYER. Subscribers (e.g. LogisticsSystem)
## use this to invalidate cached pathfinder routes that cross pos.
signal terrain_changed(pos: Vector2i, layer: int)

## Emitted when a seed is planted and a tile enters the growing state.
signal terrain_growing_started(tile: Vector2i, target_type: int)

## Resource definitions for newly grown terrain tiles (parallel to _populate_resources).
const TERRAIN_RESOURCE_INIT: Dictionary = {
	TileType.TREE:  {&"id": &"wood",  &"clearable": true,  &"count": 3},
	TileType.BERRY: {&"id": &"berry", &"clearable": true,  &"count": 3},
	TileType.GRASS: {&"id": &"fiber", &"clearable": true,  &"count": 3},
	TileType.WHEAT: {&"id": &"wheat", &"clearable": true,  &"count": 3},
}

## Growth durations for each plantable terrain type (1 tick ≈ 1 minute).
const SEED_GROWTH_TICKS: Dictionary = {
	TileType.TREE:  2880,  ## 2 in-game days
	TileType.BERRY: 2160,  ## 1.5 in-game days
	TileType.GRASS: 1440,  ## 1 in-game day
	TileType.WHEAT: 1440,  ## 1 in-game day
}

var _terrain: Array[Array]   # [x][y] -> TileType (int)  — write-once after generate()
var _resources: Array[Array] # [x][y] -> Array[ResourceTileData], empty when no resources
var _buildings: Array[Array] # [x][y] -> String (building_id) or null
## Set true by generate(); TerrainLayer immutability enforced in Story 002.
var _generation_done: bool = false
## tile → {target_type: int, ticks_remaining: int} for in-progress seed growth.
var _growing_tiles: Dictionary = {}
## Special resources this map supports (subset of FERTILITY_POOL). Set by generate().
var _fertility: Array[StringName] = []
## Hidden ore/gem deposits (clay, iron, …) keyed by tile → resource_id. Not rendered;
## located via the player's Search action (find_nearest_hidden / reveal_hidden_deposit).
var _hidden_resources: Dictionary = {}


func _ready() -> void:
	_init_arrays()
	TickSystem.ticks_advanced.connect(_on_ticks_advanced)


func _init_arrays() -> void:
	_terrain = []
	_resources = []
	_buildings = []
	for x in range(GRID_SIZE):
		var terrain_row: Array[int] = []
		var resource_row: Array = []
		var building_row: Array = []
		_terrain.append(terrain_row)
		_resources.append(resource_row)
		_buildings.append(building_row)
		for _y in range(GRID_SIZE):
			_terrain[x].append(TileType.EMPTY)
			_resources[x].append([])
			_buildings[x].append(null)


# --- Generation ---

const _MIN_TREE: int = 8
const _MIN_STONE: int = 4
const _MIN_BERRY: int = 6
const _MIN_GRASS: int = 6
const _SMOOTH_SEED_OFFSET: int = 100000

## --- Map fertility (special map resources) ---
## Pool of special resources a map can support. A new map rolls FERTILITY_COUNT entries
## (weighted by FERTILITY_WEIGHTS); the starting map is fixed via generate()'s fertility_override.
const FERTILITY_POOL: Array[StringName] = [
	&"clay", &"wheat", &"wild",
	&"iron", &"copper", &"tin",        # common ore deposits (clay-like)
	&"silver", &"gold", &"gemstones",  # rare/precious deposits
	&"flax", &"hops", &"grapes", &"olives", &"bees",  # plains-biased crops/groves (ADR-0015 ph.4)
	&"marble",                         # mountain-biased stone overlay
	&"sand",                           # coast-only beach
	&"amber",                          # coast/forest hidden deposit (clay-like)
	&"pearl",                          # coast-only ocean overlay
]
## Relative weight of each fertility in the per-tile roll (sampling without replacement).
## Common = 12, precious (silver/gold/gemstones) = 1 → precious appears ~1/12 as often.
## Biome restrictions/boosts are layered on top of these base weights by _biome_fertility_weight.
const FERTILITY_WEIGHTS: Dictionary = {
	&"clay": 12, &"wheat": 12, &"wild": 12,
	&"iron": 12, &"copper": 12, &"tin": 12,
	&"silver": 1, &"gold": 1, &"gemstones": 1,
	&"flax": 12, &"hops": 12, &"grapes": 12, &"olives": 12, &"bees": 12,
	&"marble": 8, &"sand": 10, &"amber": 6, &"pearl": 6,
}
## Biome class passed to roll_fertility for biome-aware weighting (ADR-0015 addendum).
## BIOME_ANY preserves the pre-addendum behaviour (base weights, no restrictions).
const BIOME_ANY: int = -1
const BIOME_PLAINS: int = 0
const BIOME_FOREST: int = 1
const BIOME_MOUNTAIN: int = 2
const BIOME_COAST: int = 3
## Mineable-deposit fertilities → the pit TileType reveal converts the tile to. The single
## source of truth for "which fertilities are hidden deposits" (clay's mechanic, generalized).
const DEPOSIT_TILE_TYPE: Dictionary = {
	&"clay": TileType.CLAY,
	&"iron": TileType.IRON,
	&"copper": TileType.COPPER,
	&"tin": TileType.TIN,
	&"silver": TileType.SILVER,
	&"gold": TileType.GOLD,
	&"gemstones": TileType.GEMSTONE,
	&"amber": TileType.AMBER,
}
## How many hidden deposits a map scatters per deposit fertility it supports.
## Precious deposits are scarce (1) even when present; common deposits match clay (6).
const DEPOSIT_COUNTS: Dictionary = {
	&"clay": 6, &"iron": 6, &"copper": 6, &"tin": 6,
	&"silver": 1, &"gold": 1, &"gemstones": 1,
	&"amber": 4,
}
## Field-crop fertilities (FLAX/HOPS/GRAPES) → opaque TileType placed on EMPTY tiles (wheat-like).
const FIELD_CROP_TILE_TYPE: Dictionary = {
	&"flax": TileType.FLAX,
	&"hops": TileType.HOPS,
	&"grapes": TileType.GRAPES,
}
## Grass-overlay fertilities → transparent overlay TileType composited on a GRASS base.
const GRASS_OVERLAY_TILE_TYPE: Dictionary = {
	&"olives": TileType.OLIVE,
	&"bees": TileType.BEES,
}
## How many tiles each placed fertility scatters across the map.
const FIELD_CROP_COUNT: int = 6
const GRASS_OVERLAY_COUNT: int = 8
const MARBLE_COUNT: int = 6
const SAND_COUNT: int = 10
const PEARL_COUNT: int = 6
## How many fertilities a freshly rolled (non-starting) map receives.
const FERTILITY_COUNT: int = 3
## The starting map's fixed fertility set (not rolled). Spec: clay, wheat, wild.
const STARTING_FERTILITY: Array[StringName] = [&"clay", &"wheat", &"wild"]
## RNG offset so the fertility roll never aligns with the terrain / smoothing seeds.
const _FERTILITY_SEED_OFFSET: int = 200000
## Number of wheat-field tiles placed on a wheat-fertile map.
const WHEAT_FIELD_COUNT: int = 6
## Max Manhattan radius the Search action reports a deposit distance for.
const DEPOSIT_SEARCH_MAX_RADIUS: int = 58
const _HIDDEN_SEED_OFFSET: int = 300000
const _WHEAT_SEED_OFFSET: int = 400000
## Distinct large RNG offsets for the second fertility wave (ADR-0015 addendum).
const _FIELD_CROP_SEED_OFFSET: int = 900000
const _GRASS_OVERLAY_SEED_OFFSET: int = 1000000
const _MARBLE_SEED_OFFSET: int = 1100000
const _SAND_SEED_OFFSET: int = 1200000
const _PEARL_SEED_OFFSET: int = 1300000

## --- Water carving (Step 4.5: coast → lakes → river) ---
## All values are named constants per coding standards (no inline magic numbers).
## A river is carved only when the overworld tile has one (river_edges passed to generate());
## maps without an overworld river get no river — the same contract as coast.
const _RIVER_WIDTH: int = 1             ## Tiles carved per river step (odd-centered band).
const _RIVER_MEANDER_CHANCE: float = 0.35  ## Probability of a perpendicular jog per step.
const _LAKE_CHANCE: float = 0.5         ## Probability a map rolls any lakes.
const _LAKE_COUNT_MAX: int = 2          ## Upper bound on lakes per map.
const _LAKE_SIZE_MIN: int = 8           ## Min tiles per lake (randomized in range).
const _LAKE_SIZE_MAX: int = 14          ## Max tiles per lake.
const _COAST_DEPTH: int = 3             ## Inward depth of the coastal water band.
const _MAX_WATER_FRACTION: float = 0.25  ## Hard cap: water never dominates the map.
const _MIN_LAND_FRACTION: float = 0.80   ## Largest passable region must be ≥ this share.
const _MIN_POCKET_SIZE: int = 8         ## Passable pockets smaller than this are flooded.
## Distinct large RNG offsets so water never aligns with terrain / fertility seeds.
const _RIVER_SEED_OFFSET: int = 500000
const _LAKE_SEED_OFFSET: int = 600000
const _COAST_SEED_OFFSET: int = 700000
const _FRESHWATER_SEED_OFFSET: int = 800000
const _FRESHWATER_DEPTH: int = 3        ## Inward depth of a lakeshore freshwater band.
## Fallback water patch guaranteed on the start map when no river/lake/coast borders it.
const _FORCED_WATER_SIZE: int = 5
const _FORCED_WATER_SEED_OFFSET: int = 1400000
## Orthogonal neighbor offsets, shared by water carving / connectivity / adjacency.
const _ORTHO_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Generates terrain and resource layers via 5-step Perlin noise pipeline.
## Deterministic: same seed always produces identical terrain, resources and fertility.
## Locks TerrainLayer on completion — assert fires on any subsequent call.
## fertility_override: pass a fixed fertility set (e.g. STARTING_FERTILITY) to skip the
## random roll; an empty array rolls FERTILITY_COUNT entries from FERTILITY_POOL.
## coast_edges: carves a coastline on each listed edge (0 top, 1 bottom, 2 left, 3 right). Used
## by the Overworld so a coast tile's tactical map faces the ocean on every side it does on the
## world map (a peninsula tip carries several). Empty ⇒ NO coast — the ocean only borders maps
## that border it on the overworld (inland/forest/mountain tiles never get a coast).
## terrain_profile: biases the elevation bands by the tile's overworld biome (PLAINS / FOREST /
## MOUNTAIN); PLAINS is the unchanged default.
## river_edges: carves a river between the listed edges (the overworld river's crossing points).
## Empty ⇒ no river — a river is only present when the overworld tile has one (coast analogy).
## force_water: when true (start map only), guarantees at least one water patch even if the
## overworld tile has no river/lake/coast adjacency and the random lake roll misses.
func generate(world_seed: int, fertility_override: Array = [], coast_edges: Array = [],
		terrain_profile: int = TerrainProfile.PLAINS, river_edges: Array = [], lake_edges: Array = [],
		force_water: bool = false) -> void:
	assert(not _generation_done, "generate() called after terrain was locked")

	var terrain: Array
	var succeeded := false
	for attempt in range(5):
		terrain = _sample_noise(world_seed + attempt, terrain_profile)
		terrain = _smooth_terrain(terrain, world_seed + attempt)
		terrain = _cleanup_clusters(terrain)
		terrain = _carve_water(terrain, world_seed + attempt, coast_edges, river_edges, lake_edges, force_water)
		if _meets_minimums(terrain) and _meets_water_constraints(terrain):
			succeeded = true
			break

	_apply_terrain(terrain)

	if not succeeded:
		push_warning("Map generation forced-fix on attempt 5")
		_force_fix_minimums()
		_flood_tiny_pockets()

	_set_fertility(world_seed, fertility_override)
	if has_fertility(&"wheat"):
		_populate_wheat_fields(world_seed)
	_populate_field_crops(world_seed)
	_populate_grass_overlays(world_seed)
	_populate_marble(world_seed)
	_populate_sand_beaches(world_seed)
	_populate_pearls(world_seed)
	_populate_hidden_deposits(world_seed)

	_generation_done = true


## Converts a few EMPTY tiles to WHEAT and seeds them with wheat resources.
## Deterministic via world_seed. Only called on wheat-fertile maps.
func _populate_wheat_fields(world_seed: int) -> void:
	var empties: Array[Vector2i] = _get_empty_tiles_in_terrain()
	if empties.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _WHEAT_SEED_OFFSET
	_shuffle_tiles(empties, rng)
	# Wheat fields are terrain only — no resource overlays at generation (matches how
	# noise-generated tree/grass tiles carry no overlay anchors).
	for i in range(mini(WHEAT_FIELD_COUNT, empties.size())):
		_terrain[empties[i].x][empties[i].y] = TileType.WHEAT


## Converts EMPTY tiles to opaque field-crop terrain (flax/hops/grapes) for each crop fertility
## this map supports. Wheat-like: terrain only, no resource overlays. Deterministic per crop.
func _populate_field_crops(world_seed: int) -> void:
	var offset: int = 0
	for resource_id: StringName in FIELD_CROP_TILE_TYPE:
		offset += 1
		if not has_fertility(resource_id):
			continue
		var empties: Array[Vector2i] = _get_empty_tiles_in_terrain()
		if empties.is_empty():
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed + _FIELD_CROP_SEED_OFFSET + offset * 1009
		_shuffle_tiles(empties, rng)
		var tile_type: int = FIELD_CROP_TILE_TYPE[resource_id]
		for i in range(mini(FIELD_CROP_COUNT, empties.size())):
			_terrain[empties[i].x][empties[i].y] = tile_type


## Converts EMPTY tiles to transparent-overlay terrain (olives/bees) for each grove fertility
## this map supports. The overlay sprite is composited over an EMPTY (sand) base by the renderer.
func _populate_grass_overlays(world_seed: int) -> void:
	var offset: int = 0
	for resource_id: StringName in GRASS_OVERLAY_TILE_TYPE:
		offset += 1
		if not has_fertility(resource_id):
			continue
		var empties: Array[Vector2i] = _get_empty_tiles_in_terrain()
		if empties.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed + _GRASS_OVERLAY_SEED_OFFSET + offset * 1009
		_shuffle_tiles(empties, rng)
		var tile_type: int = GRASS_OVERLAY_TILE_TYPE[resource_id]
		for i in range(mini(GRASS_OVERLAY_COUNT, empties.size())):
			_terrain[empties[i].x][empties[i].y] = tile_type


## Converts STONE tiles to MARBLE ("treated like stone", transparent overlay) when this map is
## marble-fertile. Falls back to EMPTY tiles if the map carries too few stone outcrops.
func _populate_marble(world_seed: int) -> void:
	if not has_fertility(&"marble"):
		return
	var candidates: Array[Vector2i] = _get_type_tiles_in_terrain(TileType.STONE)
	if candidates.size() < MARBLE_COUNT:
		candidates.append_array(_get_empty_tiles_in_terrain())
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _MARBLE_SEED_OFFSET
	_shuffle_tiles(candidates, rng)
	for i in range(mini(MARBLE_COUNT, candidates.size())):
		_terrain[candidates[i].x][candidates[i].y] = TileType.MARBLE


## Converts land tiles bordering WATER/COAST into opaque SAND beaches when this map is
## sand-fertile (spec: "sand spawns at the water tiles"). Deterministic per map.
func _populate_sand_beaches(world_seed: int) -> void:
	if not has_fertility(&"sand"):
		return
	var candidates: Array[Vector2i] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if _terrain[x][y] != TileType.EMPTY:
				continue
			for off: Vector2i in _ORTHO_OFFSETS:
				var n: Vector2i = Vector2i(x, y) + off
				if not is_in_bounds(n):
					continue
				if _terrain[n.x][n.y] == TileType.WATER or _terrain[n.x][n.y] == TileType.COAST:
					candidates.append(Vector2i(x, y))
					break
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _SAND_SEED_OFFSET
	_shuffle_tiles(candidates, rng)
	for i in range(mini(SAND_COUNT, candidates.size())):
		_terrain[candidates[i].x][candidates[i].y] = TileType.SAND


## Converts a few ocean COAST tiles into visible PEARL overlays when this map is pearl-fertile
## (spec: "pearls can only be in the water", visible at spawn — not a Search resource). Pearls
## stay impassable like the water they sit on.
func _populate_pearls(world_seed: int) -> void:
	if not has_fertility(&"pearl"):
		return
	var candidates: Array[Vector2i] = _get_type_tiles_in_terrain(TileType.COAST)
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _PEARL_SEED_OFFSET
	_shuffle_tiles(candidates, rng)
	for i in range(mini(PEARL_COUNT, candidates.size())):
		_terrain[candidates[i].x][candidates[i].y] = TileType.PEARL


## Scatters hidden deposits across passable tiles for every mineable fertility this map
## supports (clay, iron, …). Deterministic via world_seed; each resource gets its own seed
## offset so placements don't all overlap. One deposit per tile (a tile already holding a
## hidden deposit is skipped). Deposits are not rendered — the player finds them via Search.
func _populate_hidden_deposits(world_seed: int) -> void:
	var passable: Array[Vector2i] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if _terrain[x][y] != TileType.IMPASSABLE:
				passable.append(Vector2i(x, y))
	if passable.is_empty():
		return
	# Deterministic order independent of Dictionary iteration: walk FERTILITY_POOL.
	var offset: int = 0
	for resource_id: StringName in FERTILITY_POOL:
		if not DEPOSIT_TILE_TYPE.has(resource_id) or not has_fertility(resource_id):
			continue
		offset += 1
		var candidates: Array[Vector2i] = passable.duplicate()
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed + _HIDDEN_SEED_OFFSET + offset * 1009
		_shuffle_tiles(candidates, rng)
		var placed: int = 0
		var want: int = DEPOSIT_COUNTS.get(resource_id, 6)
		for tile: Vector2i in candidates:
			if placed >= want:
				break
			if _hidden_resources.has(tile):
				continue
			_hidden_resources[tile] = resource_id
			placed += 1


## In-place deterministic Fisher–Yates shuffle of a tile array.
func _shuffle_tiles(tiles: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(tiles.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = tiles[i]
		tiles[i] = tiles[j]
		tiles[j] = tmp


## Populates _fertility. With a non-empty override the set is fixed (starting map);
## otherwise FERTILITY_COUNT entries are drawn via the shared weighted roll.
func _set_fertility(world_seed: int, override_set: Array) -> void:
	_fertility.clear()
	if not override_set.is_empty():
		for id: Variant in override_set:
			_fertility.append(StringName(id))
		return
	_fertility.assign(roll_fertility(world_seed + _FERTILITY_SEED_OFFSET, FERTILITY_COUNT))


## Draws `count` distinct fertilities from FERTILITY_POOL, weighted by FERTILITY_WEIGHTS,
## sampling without replacement. Deterministic from `roll_seed` (same seed → same result).
## Shared by WorldGrid (single-map) and OverworldSystem (per-tile) so the two stay consistent.
## biome (BIOME_*) applies biome-aware boosts and hard restrictions on top of base weights;
## BIOME_ANY (the default) leaves base weights untouched (pre-addendum behaviour).
static func roll_fertility(roll_seed: int, count: int, biome: int = BIOME_ANY) -> Array[StringName]:
	var pool: Array[StringName] = FERTILITY_POOL.duplicate()
	var weights: Array[int] = []
	for id: StringName in pool:
		weights.append(_biome_fertility_weight(id, int(FERTILITY_WEIGHTS.get(id, 1)), biome))
	var rng := RandomNumberGenerator.new()
	rng.seed = roll_seed
	var result: Array[StringName] = []
	for _n in range(mini(count, pool.size())):
		var total: int = 0
		for w: int in weights:
			total += w
		if total <= 0:
			break
		var pick: int = rng.randi_range(0, total - 1)
		var idx: int = 0
		while idx < weights.size() - 1 and pick >= weights[idx]:
			pick -= weights[idx]
			idx += 1
		result.append(pool[idx])
		pool.remove_at(idx)
		weights.remove_at(idx)
	return result


## Adjusts a fertility's base roll weight for the rolling tile's biome (ADR-0015 addendum).
## Restricted resources return 0 (never roll) outside their biomes; biased resources get a
## multiplier inside their preferred biome. BIOME_ANY returns the base weight unchanged.
static func _biome_fertility_weight(id: StringName, base: int, biome: int) -> int:
	if biome == BIOME_ANY:
		return base
	match id:
		&"pearl", &"sand":
			return base if biome == BIOME_COAST else 0
		&"amber":
			return base if biome == BIOME_COAST or biome == BIOME_FOREST else 0
		&"marble":
			return base * 3 if biome == BIOME_MOUNTAIN else base
		&"flax", &"hops", &"grapes", &"olives", &"bees":
			return base * 2 if biome == BIOME_PLAINS else base
	return base


## Returns true if this map supports the given fertility resource (&"clay", &"wheat", &"wild").
func has_fertility(resource_id: StringName) -> bool:
	return _fertility.has(resource_id)


## Returns a copy of this map's fertility set.
func get_fertility() -> Array[StringName]:
	return _fertility.duplicate()


# --- Hidden resources (clay) + Search ----------------------------------------

## Returns true if a hidden deposit of resource_id sits exactly on tile.
func has_hidden_resource(tile: Vector2i, resource_id: StringName) -> bool:
	return _hidden_resources.get(tile, &"") == resource_id


## Returns the nearest hidden tile (by Manhattan distance) holding resource_id within
## max_radius, or null when none is in range. Hidden deposits are few, so a linear scan suffices.
func find_nearest_hidden(tile: Vector2i, resource_id: StringName, max_radius: int) -> Variant:
	var best: Variant = null
	var best_d: int = max_radius + 1
	for h_tile: Vector2i in _hidden_resources:
		if _hidden_resources[h_tile] != resource_id:
			continue
		var d: int = manhattan_dist(tile, h_tile)
		if d < best_d:
			best_d = d
			best = h_tile
	return best


## Returns the nearest hidden deposit of ANY mineable resource within max_radius as
## {tile: Vector2i, id: StringName}, or an empty Dictionary when none is in range.
func find_nearest_any_hidden(tile: Vector2i, max_radius: int) -> Dictionary:
	var best_tile: Variant = null
	var best_id: StringName = &""
	var best_d: int = max_radius + 1
	for h_tile: Vector2i in _hidden_resources:
		var d: int = manhattan_dist(tile, h_tile)
		if d < best_d:
			best_d = d
			best_tile = h_tile
			best_id = _hidden_resources[h_tile]
	if best_tile == null:
		return {}
	return {"tile": best_tile, "id": best_id}


## Reveals the hidden deposit at tile, converting the terrain to its pit TileType (clay → CLAY,
## iron → IRON, …). Requires the tile to be EMPTY with no resources — any existing resource must
## be cleared first (spec). Returns the revealed resource id, or &"" if blocked / no deposit here.
func reveal_hidden_deposit(tile: Vector2i) -> StringName:
	if not is_in_bounds(tile):
		return &""
	var resource_id: StringName = _hidden_resources.get(tile, &"")
	if not DEPOSIT_TILE_TYPE.has(resource_id):
		return &""
	if _terrain[tile.x][tile.y] != TileType.EMPTY:
		return &""
	if not _resources[tile.x][tile.y].is_empty():
		return &""
	_hidden_resources.erase(tile)
	_terrain[tile.x][tile.y] = DEPOSIT_TILE_TYPE[resource_id]
	terrain_tile_changed.emit(tile)
	return resource_id


## Step 1: samples elevation and moisture Perlin noise for all 30×30 tiles.
## Returns Array[Array[int]] — raw TileType values before smoothing.
## Uses FastNoiseLite (Godot 4.x noise class — FastNoise does not exist in Godot 4).
## terrain_profile selects the elevation band cutoffs (_ELEV_BANDS) so forest/mountain maps
## skew toward trees / stone+peaks respectively; PLAINS reproduces the original thresholds.
func _sample_noise(noise_seed: int, terrain_profile: int = TerrainProfile.PLAINS) -> Array:
	var elevation := FastNoiseLite.new()
	elevation.noise_type = FastNoiseLite.TYPE_PERLIN
	elevation.seed = noise_seed
	elevation.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation.fractal_octaves = 4
	elevation.fractal_gain = 0.5
	elevation.fractal_lacunarity = 2.0
	elevation.frequency = 0.05

	var moisture := FastNoiseLite.new()
	moisture.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture.seed = noise_seed + 1
	moisture.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture.fractal_octaves = 3
	moisture.frequency = 0.08

	var bands: Array = _ELEV_BANDS[terrain_profile]
	var terrain: Array = []
	for x in range(GRID_SIZE):
		var row: Array[int] = []
		terrain.append(row)
		for y in range(GRID_SIZE):
			var elev_norm: float = (elevation.get_noise_2d(x, y) + 1.0) / 2.0
			var mois_norm: float = (moisture.get_noise_2d(x, y) + 1.0) / 2.0
			var tile_type: int
			if elev_norm < bands[0]:
				tile_type = TileType.IMPASSABLE
			elif elev_norm < bands[1]:
				tile_type = TileType.BERRY if mois_norm < 0.5 else TileType.GRASS
			elif elev_norm < bands[2]:
				tile_type = TileType.EMPTY
			elif elev_norm < bands[3]:
				tile_type = TileType.TREE
			elif elev_norm < bands[4]:
				tile_type = TileType.STONE
			else:
				tile_type = TileType.IMPASSABLE  # rocky peak (mountain profile only)
			terrain[x].append(tile_type)
	return terrain


## Step 2: 2 smoothing iterations. Adopts dominant 8-neighbor type with 60% probability.
## Uses RNG seeded from smooth_seed for determinism.
func _smooth_terrain(terrain: Array, smooth_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = smooth_seed + _SMOOTH_SEED_OFFSET
	var current := _copy_terrain(terrain)

	for _iter in range(2):
		var next := _copy_terrain(current)
		for x in range(GRID_SIZE):
			for y in range(GRID_SIZE):
				var neighbors: Array[int] = _get_raw_neighbors(current, x, y)
				if neighbors.is_empty():
					continue
				var current_type: int = current[x][y]
				var dominant: int
				if current_type in _EXCLUSIVE_CLUSTER_TYPES:
					# Replace cross-type exclusive neighbors with EMPTY so each type
					# only reinforces itself and is not absorbed by the others.
					var filtered: Array[int] = []
					for t: int in neighbors:
						if t in _EXCLUSIVE_CLUSTER_TYPES and t != current_type:
							filtered.append(TileType.EMPTY)
						else:
							filtered.append(t)
					dominant = _find_dominant_type(filtered)
				else:
					dominant = _find_dominant_type(neighbors)
				if rng.randf() < 0.6:
					next[x][y] = dominant
		current = next

	return current


## Step 3: removes connected resource components of size < 3 (4-way adjacency).
## Only tiles in the small component are modified — surrounding tiles are untouched.
func _cleanup_clusters(terrain: Array) -> Array:
	var result := _copy_terrain(terrain)
	var visited: Array = []
	for x in range(GRID_SIZE):
		var row: Array = []
		for _y in range(GRID_SIZE):
			row.append(false)
		visited.append(row)

	for start_x in range(GRID_SIZE):
		for start_y in range(GRID_SIZE):
			if visited[start_x][start_y]:
				continue
			var tile_type: int = result[start_x][start_y]
			if tile_type == TileType.EMPTY or tile_type == TileType.IMPASSABLE:
				visited[start_x][start_y] = true
				continue

			var component: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(start_x, start_y)]
			visited[start_x][start_y] = true
			while not queue.is_empty():
				var tile: Vector2i = queue.pop_back()
				component.append(tile)
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = tile.x + offset.x
					var ny: int = tile.y + offset.y
					if nx < 0 or nx >= GRID_SIZE or ny < 0 or ny >= GRID_SIZE:
						continue
					if visited[nx][ny]:
						continue
					if result[nx][ny] != tile_type:
						continue
					visited[nx][ny] = true
					queue.append(Vector2i(nx, ny))

			if component.size() < 3:
				for tile in component:
					result[tile.x][tile.y] = TileType.EMPTY

	return result


## Returns true if terrain Array contains at least the minimum count of each resource type.
func _meets_minimums(terrain: Array) -> bool:
	var tree_count := 0
	var stone_count := 0
	var berry_count := 0
	var grass_count := 0
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			match int(terrain[x][y]):
				TileType.TREE: tree_count += 1
				TileType.STONE: stone_count += 1
				TileType.BERRY: berry_count += 1
				TileType.GRASS: grass_count += 1
	return (tree_count >= _MIN_TREE
		and stone_count >= _MIN_STONE
		and berry_count >= _MIN_BERRY
		and grass_count >= _MIN_GRASS)


## Returns true for terrain types that block both movement and occupation.
## Routing the three occupation checks (placement / drop / move) and passability through
## this single predicate keeps IMPASSABLE and WATER from ever drifting apart.
func _blocks_occupation(type: int) -> bool:
	return type == TileType.IMPASSABLE or type == TileType.WATER or type == TileType.COAST \
			or type == TileType.PEARL


## Step 4.5: carves WATER into the working terrain array. Order is coast → freshwater band →
## lakes → river so later features can flow into earlier ones. Each feature uses a dedicated
## seed-offset RNG for determinism (same seed → identical water layout).
## force_water: if true, appends a guaranteed _FORCED_WATER_SIZE patch when no water exists yet.
func _carve_water(terrain: Array, water_seed: int, coast_edges: Array = [], river_edges: Array = [], lake_edges: Array = [], force_water: bool = false) -> Array:
	var result := _copy_terrain(terrain)
	_carve_coast(result, water_seed, coast_edges)
	_carve_freshwater(result, water_seed, lake_edges)
	_carve_lakes(result, water_seed)
	_carve_river(result, water_seed, river_edges)
	if force_water and not _has_water_tiles(result):
		_carve_forced_patch(result, water_seed)
	return result


## True if terrain already contains at least one WATER or COAST tile (used by force_water guard).
func _has_water_tiles(terrain: Array) -> bool:
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if terrain[x][y] == TileType.WATER or terrain[x][y] == TileType.COAST:
				return true
	return false


## Grows a small blob of _FORCED_WATER_SIZE WATER tiles at a seed-deterministic interior point.
## Only called when force_water is true and no water tiles exist after normal carving.
func _carve_forced_patch(terrain: Array, water_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = water_seed + _FORCED_WATER_SEED_OFFSET
	var margin: int = 4
	var start := Vector2i(
		rng.randi_range(margin, GRID_SIZE - 1 - margin),
		rng.randi_range(margin, GRID_SIZE - 1 - margin))
	_region_grow_water(terrain, start, _FORCED_WATER_SIZE, rng)


## Conditional lakeshore: the freshwater twin of _carve_coast. For each edge facing an overworld
## LAKE it carves a band of depth _FRESHWATER_DEPTH inward, jittered ±1, as WATER (fresh) rather
## than COAST (salt) — "a lake is like a coast, only freshwater". Empty lake_edges ⇒ no band.
func _carve_freshwater(terrain: Array, water_seed: int, lake_edges: Array = []) -> void:
	if lake_edges.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = water_seed + _FRESHWATER_SEED_OFFSET
	for edge: int in lake_edges:
		# `i` runs across the chosen edge, `d` inward to a jittered depth.
		for i in range(GRID_SIZE):
			var depth: int = maxi(0, _FRESHWATER_DEPTH + rng.randi_range(-1, 1))
			for d in range(depth):
				var tile: Vector2i
				match edge:
					0: tile = Vector2i(i, d)
					1: tile = Vector2i(i, GRID_SIZE - 1 - d)
					2: tile = Vector2i(d, i)
					_: tile = Vector2i(GRID_SIZE - 1 - d, i)
				if is_in_bounds(tile):
					terrain[tile.x][tile.y] = TileType.WATER


## Conditional coastline: carves a band of depth _COAST_DEPTH inward from each forced edge, with
## the inner boundary jittered by ±1 so it isn't straight. A coast is carved ONLY when the
## overworld tile is a COAST tile (forced_edges non-empty); inland/forest/mountain tiles pass an
## empty array and get NO coast — the ocean only borders maps that border it on the overworld.
## forced_edges: each 0 top, 1 bottom, 2 left, 3 right; a peninsula tip carries several.
func _carve_coast(terrain: Array, water_seed: int, forced_edges: Array = []) -> void:
	if forced_edges.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = water_seed + _COAST_SEED_OFFSET
	var edges: Array = forced_edges
	for edge: int in edges:
		# Iterate along the edge; `i` runs across the chosen edge, `d` inward to a jittered depth.
		for i in range(GRID_SIZE):
			var depth: int = maxi(0, _COAST_DEPTH + rng.randi_range(-1, 1))
			for d in range(depth):
				var tile: Vector2i
				match edge:
					0: tile = Vector2i(i, d)
					1: tile = Vector2i(i, GRID_SIZE - 1 - d)
					2: tile = Vector2i(d, i)
					_: tile = Vector2i(GRID_SIZE - 1 - d, i)
				if is_in_bounds(tile):
					terrain[tile.x][tile.y] = TileType.COAST


## Optional lakes: with prob _LAKE_CHANCE, grows 1.._LAKE_COUNT_MAX blobby water regions
## via randomized frontier flood from random interior seed points.
func _carve_lakes(terrain: Array, water_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = water_seed + _LAKE_SEED_OFFSET
	if rng.randf() >= _LAKE_CHANCE:
		return
	var lake_count: int = rng.randi_range(1, _LAKE_COUNT_MAX)
	for _i in range(lake_count):
		var start := Vector2i(rng.randi_range(3, GRID_SIZE - 4), rng.randi_range(3, GRID_SIZE - 4))
		var target_size: int = rng.randi_range(_LAKE_SIZE_MIN, _LAKE_SIZE_MAX)
		_region_grow_water(terrain, start, target_size, rng)


## Randomized region-grow: floods up to target_size tiles starting at start, picking a
## random frontier tile each step for an irregular, blobby shape.
func _region_grow_water(terrain: Array, start: Vector2i, target_size: int, rng: RandomNumberGenerator) -> void:
	var carved: Dictionary = {}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty() and carved.size() < target_size:
		var idx: int = rng.randi_range(0, frontier.size() - 1)
		var tile: Vector2i = frontier[idx]
		frontier.remove_at(idx)
		if carved.has(tile) or not is_in_bounds(tile):
			continue
		terrain[tile.x][tile.y] = TileType.WATER
		carved[tile] = true
		for offset: Vector2i in _ORTHO_OFFSETS:
			var n := tile + offset
			if is_in_bounds(n) and not carved.has(n):
				frontier.append(n)


## Conditional river: carved only when the overworld tile has one (river_edges non-empty).
## Traces a meandering band of width _RIVER_WIDTH from one of the tile's river edges to another,
## so the tactical river crosses the same sides the overworld river connects to its neighbours.
## With a single river edge (a source/mouth tile) it runs to the opposite edge so a full river
## still crosses the map. Empty river_edges ⇒ no river. The walk jogs perpendicular with
## _RIVER_MEANDER_CHANCE probability.
func _carve_river(terrain: Array, water_seed: int, river_edges: Array = []) -> void:
	if river_edges.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = water_seed + _RIVER_SEED_OFFSET
	var start_edge: int = int(river_edges[0])
	# Opposite edge pairs are top↔bottom (0↔1) and left↔right (2↔3), i.e. edge XOR 1.
	var end_edge: int = int(river_edges[1]) if river_edges.size() >= 2 else (start_edge ^ 1)
	var start := _edge_point(start_edge, rng)
	var goal := _edge_point(end_edge, rng)
	_trace_river(terrain, start, goal, rng)


## Returns a random tile on the given edge (0 top, 1 bottom, 2 left, 3 right).
func _edge_point(edge: int, rng: RandomNumberGenerator) -> Vector2i:
	match edge:
		0: return Vector2i(rng.randi_range(0, GRID_SIZE - 1), 0)
		1: return Vector2i(rng.randi_range(0, GRID_SIZE - 1), GRID_SIZE - 1)
		2: return Vector2i(0, rng.randi_range(0, GRID_SIZE - 1))
		_: return Vector2i(GRID_SIZE - 1, rng.randi_range(0, GRID_SIZE - 1))


func _trace_river(terrain: Array, start: Vector2i, goal: Vector2i, rng: RandomNumberGenerator) -> void:
	var pos := start
	var max_steps: int = GRID_SIZE * 4  # bound: non-meander steps always close distance
	for _step in range(max_steps):
		_carve_river_tile(terrain, pos)
		if pos == goal:
			return
		var toward := _step_toward(pos, goal)
		var dir := toward
		if rng.randf() < _RIVER_MEANDER_CHANCE:
			dir = Vector2i(toward.y, toward.x)  # perpendicular to the toward-step axis
			if rng.randf() < 0.5:
				dir = -dir
		var next := pos + dir
		next.x = clampi(next.x, 0, GRID_SIZE - 1)
		next.y = clampi(next.y, 0, GRID_SIZE - 1)
		pos = next


## Carves a _RIVER_WIDTH-wide band centered on tile (width 1 → just the center tile).
func _carve_river_tile(terrain: Array, center: Vector2i) -> void:
	var half: int = _RIVER_WIDTH / 2
	for ox in range(-half, _RIVER_WIDTH - half):
		for oy in range(-half, _RIVER_WIDTH - half):
			var t := center + Vector2i(ox, oy)
			if is_in_bounds(t):
				terrain[t.x][t.y] = TileType.WATER


## Returns a single-axis unit step from `from` toward `to` (the dominant axis wins).
func _step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	if abs(dx) >= abs(dy):
		return Vector2i(signi(dx), 0)
	return Vector2i(0, signi(dy))


## Verification guard (run alongside the minimum-count check). Passes only when total water
## is within _MAX_WATER_FRACTION and the largest passable component covers ≥ _MIN_LAND_FRACTION
## of all passable tiles — i.e. the map is effectively connected and not water-dominated.
func _meets_water_constraints(terrain: Array) -> bool:
	var water := 0
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if terrain[x][y] == TileType.WATER:
				water += 1
	if float(water) / float(GRID_SIZE * GRID_SIZE) > _MAX_WATER_FRACTION:
		return false
	var components := _passable_components(terrain)
	if components.is_empty():
		return false
	var passable_total := 0
	var largest := 0
	for comp: Array in components:
		passable_total += comp.size()
		largest = maxi(largest, comp.size())
	if passable_total == 0:
		return false
	return float(largest) / float(passable_total) >= _MIN_LAND_FRACTION


## Returns the connected components (4-way) of passable (non-blocking) tiles in terrain.
## Each component is an Array[Vector2i]. Used by the connectivity guard and force-fix.
func _passable_components(terrain: Array) -> Array:
	var visited: Array = []
	for x in range(GRID_SIZE):
		var row: Array = []
		for _y in range(GRID_SIZE):
			row.append(false)
		visited.append(row)

	var components: Array = []
	for start_x in range(GRID_SIZE):
		for start_y in range(GRID_SIZE):
			if visited[start_x][start_y]:
				continue
			if _blocks_occupation(terrain[start_x][start_y]):
				visited[start_x][start_y] = true
				continue
			var component: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(start_x, start_y)]
			visited[start_x][start_y] = true
			while not queue.is_empty():
				var tile: Vector2i = queue.pop_back()
				component.append(tile)
				for offset: Vector2i in _ORTHO_OFFSETS:
					var nx: int = tile.x + offset.x
					var ny: int = tile.y + offset.y
					if nx < 0 or nx >= GRID_SIZE or ny < 0 or ny >= GRID_SIZE:
						continue
					if visited[nx][ny] or _blocks_occupation(terrain[nx][ny]):
						continue
					visited[nx][ny] = true
					queue.append(Vector2i(nx, ny))
			components.append(component)
	return components


## Worst-case cleanup (all 5 attempts failed the connectivity preference). Rivers are allowed
## to split the map — the player crosses by building a Bridge — so this does NOT force a land
## connection; it only floods tiny passable pockets (< _MIN_POCKET_SIZE) to WATER as cosmetic
## islets, leaving the larger regions intact (reachable via a player-built bridge).
func _flood_tiny_pockets() -> void:
	var components := _passable_components(_terrain)
	if components.size() <= 1:
		return
	var largest_idx := 0
	for i in range(components.size()):
		if components[i].size() > components[largest_idx].size():
			largest_idx = i
	for i in range(components.size()):
		if i == largest_idx:
			continue
		var comp: Array = components[i]
		if comp.size() < _MIN_POCKET_SIZE:
			for tile: Vector2i in comp:
				_terrain[tile.x][tile.y] = TileType.WATER


func _apply_terrain(terrain: Array) -> void:
	assert(not _generation_done, "TerrainLayer is immutable after generation")
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			_terrain[x][y] = terrain[x][y]


## Step 5 fallback: converts EMPTY tiles nearest to existing resource clusters to meet minimums.
## Called only when all 5 seed attempts fail minimum count verification.
func _force_fix_minimums() -> void:
	assert(not _generation_done, "TerrainLayer is immutable after generation")
	for tile_type in [TileType.TREE, TileType.STONE, TileType.BERRY, TileType.GRASS]:
		var min_count: int = _get_min_count(tile_type)
		var current := _count_type_in_terrain(tile_type)
		if current >= min_count:
			continue

		var needed := min_count - current
		var empty_tiles := _get_empty_tiles_in_terrain()
		if empty_tiles.is_empty():
			continue

		var type_tiles := _get_type_tiles_in_terrain(tile_type)

		if type_tiles.is_empty():
			var center := Vector2i(GRID_SIZE >> 1, GRID_SIZE >> 1)
			empty_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var da: int = abs(a.x - center.x) + abs(a.y - center.y)
				var db: int = abs(b.x - center.x) + abs(b.y - center.y)
				return da < db
			)
		else:
			var dist_map: Dictionary = {}
			for tile: Vector2i in empty_tiles:
				var min_d: int = 99999
				for t: Vector2i in type_tiles:
					var d: int = abs(tile.x - t.x) + abs(tile.y - t.y)
					if d < min_d:
						min_d = d
				dist_map[tile] = min_d
			empty_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				return dist_map[a] < dist_map[b]
			)

		for i in range(min(needed, empty_tiles.size())):
			_terrain[empty_tiles[i].x][empty_tiles[i].y] = tile_type


## Populates the resource layer: one tile per terrain type receives multiple resources.
## The chosen tile is selected deterministically from all tiles of that type using world_seed.
func _populate_resources(world_seed: int) -> void:
	# Map terrain type → resource definition and how many to place on the chosen tile.
	const RESOURCE_DEFS: Dictionary = {
		TileType.TREE:  {"id": &"wood",  "clearable": true,  "count": 3},
		TileType.STONE: {"id": &"stone", "clearable": false, "count": 3},
		TileType.BERRY: {"id": &"berry", "clearable": true,  "count": 3},
		TileType.GRASS: {"id": &"fiber", "clearable": true,  "count": 3},
	}

	# Collect all tile positions per terrain type.
	var tiles_by_type: Dictionary = {}
	for type_key: TileType in RESOURCE_DEFS:
		tiles_by_type[type_key] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var t: int = _terrain[x][y]
			if tiles_by_type.has(t):
				tiles_by_type[t].append(Vector2i(x, y))

	# For each type, pick one tile and fill it with multiple resources.
	for type_key: TileType in RESOURCE_DEFS:
		var tiles: Array = tiles_by_type[type_key]
		if tiles.is_empty():
			continue
		var def: Dictionary = RESOURCE_DEFS[type_key]
		var chosen: Vector2i = tiles[(world_seed + type_key * 7919) % tiles.size()]
		var entries: Array = []
		for _i in range(def["count"]):
			entries.append(ResourceTileData.new(def["id"], def["clearable"]))
		_resources[chosen.x][chosen.y] = entries


func _copy_terrain(terrain: Array) -> Array:
	var copy: Array = []
	for x in range(GRID_SIZE):
		var row: Array[int] = []
		for y in range(GRID_SIZE):
			row.append(int(terrain[x][y]))
		copy.append(row)
	return copy


func _get_raw_neighbors(terrain: Array, x: int, y: int) -> Array[int]:
	var result: Array[int] = []
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < GRID_SIZE and ny >= 0 and ny < GRID_SIZE:
				result.append(int(terrain[nx][ny]))
	return result


## Returns the most frequent type. Iterates enum values in fixed order for deterministic tie-breaking.
func _find_dominant_type(types: Array[int]) -> int:
	var counts: Dictionary = {}
	for t: int in types:
		counts[t] = counts.get(t, 0) + 1
	var dominant: int = types[0]
	var max_count := 0
	for t in [TileType.EMPTY, TileType.TREE, TileType.STONE, TileType.BERRY, TileType.GRASS, TileType.IMPASSABLE]:
		if counts.get(t, 0) > max_count:
			max_count = counts[t]
			dominant = t
	return dominant


func _get_min_count(tile_type: int) -> int:
	match tile_type:
		TileType.TREE: return _MIN_TREE
		TileType.STONE: return _MIN_STONE
		TileType.BERRY: return _MIN_BERRY
		TileType.GRASS: return _MIN_GRASS
		_: return 0


func _count_type_in_terrain(tile_type: int) -> int:
	var count := 0
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if _terrain[x][y] == tile_type:
				count += 1
	return count


func _get_empty_tiles_in_terrain() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if _terrain[x][y] == TileType.EMPTY:
				result.append(Vector2i(x, y))
	return result


func _get_type_tiles_in_terrain(tile_type: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if _terrain[x][y] == tile_type:
				result.append(Vector2i(x, y))
	return result


# --- Placement validation (implemented in Story 003) ---

## Validates building placement against all 3 layers. Never mutates state.
func validate_placement(tile: Vector2i, _building_type: int) -> PlacementResult:
	if not is_in_bounds(tile):
		return PlacementResult.BLOCKED_BY_BOUNDS
	if _blocks_occupation(_terrain[tile.x][tile.y]):
		return PlacementResult.BLOCKED_BY_IMPASSABLE
	if _terrain[tile.x][tile.y] != TileType.EMPTY:
		return PlacementResult.BLOCKED_BY_RESOURCE_TILE
	if _buildings[tile.x][tile.y] != null:
		return PlacementResult.BLOCKED_BY_BUILDING
	var resources: Array = _resources[tile.x][tile.y]
	for res: ResourceTileData in resources:
		if not res.clearable:
			return PlacementResult.BLOCKED_BY_RESOURCE_TILE
	return PlacementResult.SUCCESS


## Atomically validates and places a building. Updates BuildingLayer; clears clearable resources.
## building_id uniquely identifies the placed building instance.
func place_building(tile: Vector2i, building_id: String) -> PlacementResult:
	var result: PlacementResult = validate_placement(tile, 0)
	if result != PlacementResult.SUCCESS:
		return result
	_buildings[tile.x][tile.y] = building_id
	if not _resources[tile.x][tile.y].is_empty():
		_resources[tile.x][tile.y] = []
	terrain_changed.emit(tile, BUILDING_LAYER)
	return PlacementResult.SUCCESS


## Validates placement of a water-only building (the Bridge) without mutating state.
## Mirrors validate_placement but inverts the terrain rule: the tile MUST be WATER and free
## of any existing building. Non-water tiles return BLOCKED_BY_IMPASSABLE (invalid bridge spot).
func validate_water_placement(tile: Vector2i) -> PlacementResult:
	if not is_in_bounds(tile):
		return PlacementResult.BLOCKED_BY_BOUNDS
	if _terrain[tile.x][tile.y] != TileType.WATER:
		return PlacementResult.BLOCKED_BY_IMPASSABLE
	if _buildings[tile.x][tile.y] != null:
		return PlacementResult.BLOCKED_BY_BUILDING
	return PlacementResult.SUCCESS


## Places a water-only building (the Bridge) on a WATER tile. The terrain stays WATER; the
## building on the layer makes the tile passable via get_tile_movement_cost (building wins).
## Use for the Bridge BuildingType; demolish clears it back to impassable water.
func place_building_on_water(tile: Vector2i, building_id: String) -> PlacementResult:
	var result: PlacementResult = validate_water_placement(tile)
	if result != PlacementResult.SUCCESS:
		return result
	_buildings[tile.x][tile.y] = building_id
	terrain_changed.emit(tile, BUILDING_LAYER)
	return PlacementResult.SUCCESS


## Removes building from BuildingLayer at tile. Returns true if a building was present.
func remove_building(tile: Vector2i) -> bool:
	if not is_in_bounds(tile):
		return false
	if _buildings[tile.x][tile.y] == null:
		return false
	_buildings[tile.x][tile.y] = null
	terrain_changed.emit(tile, BUILDING_LAYER)
	return true


# --- Read API ---

## Returns terrain type at tile. Asserts on out-of-bounds access.
func get_terrain(tile: Vector2i) -> TileType:
	assert(is_in_bounds(tile), "get_terrain: tile %s is out of bounds" % str(tile))
	return _terrain[tile.x][tile.y]


## Returns all resources at tile as an Array[ResourceTileData]. Empty when tile has no resources.
func get_resources(tile: Vector2i) -> Array[ResourceTileData]:
	assert(is_in_bounds(tile), "get_resources: tile %s is out of bounds" % str(tile))
	var result: Array[ResourceTileData] = []
	result.assign(_resources[tile.x][tile.y])
	return result


## Returns building ID at tile, or empty string if no building.
func get_building(tile: Vector2i) -> String:
	assert(is_in_bounds(tile), "get_building: tile %s is out of bounds" % str(tile))
	var b: Variant = _buildings[tile.x][tile.y]
	return b if b != null else ""


## Returns a composite read-only snapshot of all layers at tile.
func get_tile_view(tile: Vector2i) -> TileView:
	assert(is_in_bounds(tile), "get_tile_view: tile %s is out of bounds" % str(tile))
	return TileView.new(
		_terrain[tile.x][tile.y],
		_resources[tile.x][tile.y],
		get_building(tile)
	)


## Returns false for blocking tiles (IMPASSABLE or WATER). Asserts on out-of-bounds access.
func is_passable(tile: Vector2i) -> bool:
	assert(is_in_bounds(tile), "is_passable: tile %s is out of bounds" % str(tile))
	return not _blocks_occupation(_terrain[tile.x][tile.y])


## Returns the movement cost for a tile used by the A* pathfinder (ADR-0013).
## Priority: BuildingLayer (INF) > path (0.5) > terrain type.
## Terrain type is the sole source of movement difficulty — dropped items are ignored.
## Out-of-bounds positions return INF (treated as impassable wall).
func get_tile_movement_cost(pos: Vector2i) -> float:
	if not is_in_bounds(pos):
		return INF
	if _buildings[pos.x][pos.y] != null:
		return BuildingRegistry.get_movement_cost(str(_buildings[pos.x][pos.y]))
	if PathSystem.has_path(pos):
		return 0.5
	match _terrain[pos.x][pos.y]:
		TileType.IMPASSABLE: return INF
		TileType.WATER:      return INF
		TileType.TREE:       return 4.0
		TileType.STONE:      return 4.0
		TileType.BERRY:      return 4.0
		TileType.GRASS:      return 4.0
		TileType.WHEAT:      return 4.0
		TileType.CLAY:       return 4.0
		TileType.IRON:       return 4.0
		TileType.COPPER:     return 4.0
		TileType.TIN:        return 4.0
		TileType.SILVER:     return 4.0
		TileType.GOLD:       return 4.0
		TileType.GEMSTONE:   return 4.0
		TileType.FLAX:       return 4.0
		TileType.HOPS:       return 4.0
		TileType.GRAPES:     return 4.0
		TileType.SAND:       return 4.0
		TileType.OLIVE:      return 4.0
		TileType.BEES:       return 4.0
		TileType.MARBLE:     return 4.0
		TileType.AMBER:      return 4.0
		TileType.PEARL:      return INF
		_:                   return 1.0  # EMPTY


## Returns false if and only if get_tile_movement_cost(pos) == INF (ADR-0013).
func is_tile_passable(pos: Vector2i) -> bool:
	return get_tile_movement_cost(pos) != INF


## Returns true if tile is within grid bounds. Safe to call without a pre-check.
func is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < GRID_SIZE and tile.y >= 0 and tile.y < GRID_SIZE


# --- Resource mutation ---

## Clears a terrain tile: sets it to EMPTY and removes all resources.
## Gameplay mutation only — bypasses generation immutability guard intentionally.
## Returns false if tile is out of bounds.
func clear_terrain_tile(tile: Vector2i) -> bool:
	if not is_in_bounds(tile):
		return false
	_growing_tiles.erase(tile)
	_terrain[tile.x][tile.y] = TileType.EMPTY
	_resources[tile.x][tile.y] = []
	terrain_tile_changed.emit(tile)
	return true


## Plants a seed on an EMPTY tile, beginning the growth countdown.
## Returns false if the tile is out of bounds, not EMPTY, or already occupied.
func plant_seed(tile: Vector2i, target_type: TileType) -> bool:
	if not is_in_bounds(tile):
		return false
	if _terrain[tile.x][tile.y] != TileType.EMPTY:
		return false
	if _buildings[tile.x][tile.y] != null:
		return false
	if _growing_tiles.has(tile):
		return false
	var ticks: int = SEED_GROWTH_TICKS.get(target_type, 1440)
	_growing_tiles[tile] = {"target_type": int(target_type), "ticks_remaining": ticks}
	terrain_growing_started.emit(tile, int(target_type))
	return true


## Returns true if the tile currently has a seed growing on it.
func is_tile_growing(tile: Vector2i) -> bool:
	return _growing_tiles.has(tile)


## Returns a shallow copy of the growing-tiles dictionary (tile → growth data).
func get_growing_tiles() -> Dictionary:
	return _growing_tiles.duplicate()


## Growth completion fraction (0.0–1.0) for a growing tile, or 0.0 if not growing.
func get_growth_progress(tile: Vector2i) -> float:
	if not _growing_tiles.has(tile):
		return 0.0
	var data: Dictionary = _growing_tiles[tile]
	var total: int = SEED_GROWTH_TICKS.get(data.target_type as TileType, 1440)
	if total <= 0:
		return 1.0
	return clampf(1.0 - float(data.ticks_remaining) / float(total), 0.0, 1.0)


func _on_ticks_advanced(delta: int) -> void:
	if _growing_tiles.is_empty():
		return
	var to_convert: Array[Vector2i] = []
	for tile: Vector2i in _growing_tiles:
		_growing_tiles[tile].ticks_remaining -= delta
		if _growing_tiles[tile].ticks_remaining <= 0:
			to_convert.append(tile)
	for tile: Vector2i in to_convert:
		var target_type: TileType = _growing_tiles[tile].target_type as TileType
		_growing_tiles.erase(tile)
		_terrain[tile.x][tile.y] = target_type
		if TERRAIN_RESOURCE_INIT.has(target_type):
			var def: Dictionary = TERRAIN_RESOURCE_INIT[target_type]
			for _i: int in range(def[&"count"]):
				add_resource_to_tile(tile, def[&"id"], def[&"clearable"])
		terrain_tile_changed.emit(tile)


## Clears the resource at tile if one is present. Returns 1 if cleared, 0 if none.
## Anno-style: resources are spatial anchors — present or cleared, no quantity tracking.
## _amount is reserved for future quantity systems; currently ignored.
func harvest_resource(tile: Vector2i, _amount: int) -> int:
	assert(is_in_bounds(tile), "harvest_resource: tile %s is out of bounds" % str(tile))
	if _resources[tile.x][tile.y].is_empty():
		return 0
	var count: int = _resources[tile.x][tile.y].size()
	_resources[tile.x][tile.y] = []
	terrain_changed.emit(tile, RESOURCE_LAYER)
	return count


# --- Coordinate conversion (implemented in Story 004) ---

## Converts world-space position to tile coordinate using floor division.
## Negative or out-of-bounds results are valid — callers must check is_in_bounds().
func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))


## Converts tile coordinate to world-space center position.
func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile) * TILE_SIZE + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)


# --- Distance and spatial queries ---

## Returns Manhattan distance (|dx| + |dy|) between two tiles.
func manhattan_dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


## Returns Euclidean distance between two tiles.
func euclidean_dist(a: Vector2i, b: Vector2i) -> float:
	var dx := float(a.x - b.x)
	var dy := float(a.y - b.y)
	return sqrt(dx * dx + dy * dy)


## Returns distance between two tiles using the given metric.
## MANHATTAN is the primary metric (NPC movement, logistics travel time).
## EUCLIDEAN is for Anno-style circular proximity checks — post-filter get_tiles_in_radius results.
func distance_between(a: Vector2i, b: Vector2i, metric: DistanceMetric) -> float:
	match metric:
		DistanceMetric.MANHATTAN:
			return float(manhattan_dist(a, b))
		DistanceMetric.EUCLIDEAN:
			return euclidean_dist(a, b)
	return 0.0


## Returns all tiles within a square bounding box of given radius around center, clipped to grid bounds.
## NOT circular — callers needing circular proximity must post-filter:
##   euclidean_dist(center, tile) <= radius
func get_tiles_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x_min := clampi(center.x - radius, 0, GRID_SIZE - 1)
	var x_max := clampi(center.x + radius, 0, GRID_SIZE - 1)
	var y_min := clampi(center.y - radius, 0, GRID_SIZE - 1)
	var y_max := clampi(center.y + radius, 0, GRID_SIZE - 1)
	for x in range(x_min, x_max + 1):
		for y in range(y_min, y_max + 1):
			result.append(Vector2i(x, y))
	return result


## Returns in-bounds neighbors of tile. Includes diagonals when diagonals is true.
func get_neighbors(tile: Vector2i, diagonals: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	if diagonals:
		offsets.append_array([Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)])
	for offset in offsets:
		var n := tile + offset
		if is_in_bounds(n):
			result.append(n)
	return result


## Returns the nearest passable, building-free tile to `preferred` (expanding Manhattan
## radius), or `preferred` itself if it already qualifies. Used to keep the starting
## building off water/impassable tiles after water carving. Falls back to `preferred`
## when nothing is found within max_radius (caller handles the unlikely failure).
func find_nearest_passable_tile(preferred: Vector2i, max_radius: int = GRID_SIZE) -> Vector2i:
	for r in range(max_radius + 1):
		for dx in range(-r, r + 1):
			var dy_abs: int = r - abs(dx)
			var dy_values := [dy_abs] if dy_abs == 0 else [dy_abs, -dy_abs]
			for dy: int in dy_values:
				var candidate := preferred + Vector2i(dx, dy)
				if not is_in_bounds(candidate):
					continue
				if _blocks_occupation(_terrain[candidate.x][candidate.y]):
					continue
				if _buildings[candidate.x][candidate.y] != null:
					continue
				return candidate
	return preferred


## Returns true if tile is a passable land tile orthogonally adjacent to ≥1 WATER tile.
## Reserved economy hook (fishing / water-needing buildings) — no gameplay reads this yet.
func is_water_adjacent(tile: Vector2i) -> bool:
	if not is_in_bounds(tile):
		return false
	if _blocks_occupation(_terrain[tile.x][tile.y]):
		return false
	for offset: Vector2i in _ORTHO_OFFSETS:
		var n := tile + offset
		if is_in_bounds(n) and _terrain[n.x][n.y] == TileType.WATER:
			return true
	return false


## Returns all passable land tiles orthogonally adjacent to ≥1 WATER tile.
## RESERVED: future &"fish" fertility / fishing-hut hook. FERTILITY_POOL is intentionally
## left unchanged this pass so existing balance and saves stay untouched.
func get_water_adjacent_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var tile := Vector2i(x, y)
			if is_water_adjacent(tile):
				result.append(tile)
	return result


## Expanding Manhattan-radius search. Returns Vector2i of nearest tile containing resource_id,
## or null if no match is found within max_radius.
func find_nearest(tile: Vector2i, resource_id: StringName, max_radius: int) -> Variant:
	for r in range(max_radius + 1):
		if r == 0:
			if is_in_bounds(tile) and _tile_has_resource(tile, resource_id):
				return tile
			continue
		for dx in range(-r, r + 1):
			var dy_abs: int = r - abs(dx)
			var dy_values := [dy_abs] if dy_abs == 0 else [dy_abs, -dy_abs]
			for dy in dy_values:
				var candidate := tile + Vector2i(dx, dy)
				if is_in_bounds(candidate) and _tile_has_resource(candidate, resource_id):
					return candidate
	return null


func _tile_has_resource(tile: Vector2i, resource_id: StringName) -> bool:
	for res: ResourceTileData in _resources[tile.x][tile.y]:
		if res.resource_id == resource_id:
			return true
	return false


## Returns all tiles for which predicate returns true. Iterates all 900 tiles.
func find_tiles_by_predicate(predicate: Callable) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var t := Vector2i(x, y)
			if predicate.call(t):
				result.append(t)
	return result


## Moves one ResourceTileData entry from source[source_idx] to target.
## Returns false if: target out-of-bounds, target IMPASSABLE, source_idx invalid,
## or target already holds MAX_RESOURCES_PER_TILE entries.
## Removes a single resource entry at source_idx from tile. Returns false on invalid args.
func remove_one_resource(tile: Vector2i, resource_idx: int) -> bool:
	if not is_in_bounds(tile):
		return false
	var arr: Array = _resources[tile.x][tile.y]
	if resource_idx < 0 or resource_idx >= arr.size():
		return false
	arr.remove_at(resource_idx)
	terrain_changed.emit(tile, RESOURCE_LAYER)
	return true


## Places a new resource on the given tile.
## Returns false if: out-of-bounds or a blocking tile (IMPASSABLE / WATER). No per-tile cap.
func add_resource_to_tile(tile: Vector2i, resource_id: StringName, clearable: bool = true) -> bool:
	if not is_in_bounds(tile):
		return false
	if _blocks_occupation(_terrain[tile.x][tile.y]):
		return false
	_resources[tile.x][tile.y].append(ResourceTileData.new(resource_id, clearable))
	terrain_changed.emit(tile, RESOURCE_LAYER)
	return true


func move_one_resource(source: Vector2i, source_idx: int, target: Vector2i) -> bool:
	if not is_in_bounds(source) or not is_in_bounds(target):
		return false
	if _blocks_occupation(_terrain[target.x][target.y]):
		return false
	var src_arr: Array = _resources[source.x][source.y]
	if source_idx < 0 or source_idx >= src_arr.size():
		return false
	var entry: ResourceTileData = src_arr[source_idx]
	src_arr.remove_at(source_idx)
	_resources[target.x][target.y].append(entry)
	return true


# --- Serialization ---

## Serializes terrain and resource layers. Buildings are owned by BuildingRegistry.
func serialize() -> Dictionary:
	var terrain_flat: Array[int] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			terrain_flat.append(_terrain[x][y])
	var resources_sparse: Array = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var tile_res: Array = _resources[x][y]
			if not tile_res.is_empty():
				var items: Array = []
				for rd: ResourceTileData in tile_res:
					items.append({"id": str(rd.resource_id), "clearable": rd.clearable})
				resources_sparse.append({"x": x, "y": y, "items": items})
	var growing_arr: Array = []
	for tile: Vector2i in _growing_tiles:
		growing_arr.append({
			"tile_x": tile.x, "tile_y": tile.y,
			"target_type": _growing_tiles[tile].target_type,
			"ticks_remaining": _growing_tiles[tile].ticks_remaining,
		})
	var fertility_arr: Array[String] = []
	for f: StringName in _fertility:
		fertility_arr.append(str(f))
	var hidden_arr: Array = []
	for h_tile: Vector2i in _hidden_resources:
		hidden_arr.append({"x": h_tile.x, "y": h_tile.y, "id": str(_hidden_resources[h_tile])})
	return {
		"terrain": terrain_flat,
		"resources": resources_sparse,
		"growing_tiles": growing_arr,
		"fertility": fertility_arr,
		"hidden": hidden_arr,
	}


## Restores terrain and resource layers from a serialized Dictionary.
## Called before BuildingRegistry.deserialize() so terrain is valid for placement validation.
func deserialize(data: Dictionary) -> void:
	_init_arrays()
	var terrain_flat: Array = data.get("terrain", [])
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var idx: int = x * GRID_SIZE + y
			if idx < terrain_flat.size():
				_terrain[x][y] = terrain_flat[idx]
	for entry: Dictionary in data.get("resources", []):
		var x: int = entry.get("x", -1)
		var y: int = entry.get("y", -1)
		if x < 0 or y < 0 or x >= GRID_SIZE or y >= GRID_SIZE:
			continue
		var tile_res: Array = []
		for item: Dictionary in entry.get("items", []):
			tile_res.append(ResourceTileData.new(StringName(item.get("id", "")), item.get("clearable", true)))
		_resources[x][y] = tile_res
	_growing_tiles.clear()
	for entry: Dictionary in data.get("growing_tiles", []):
		var gtile := Vector2i(entry.get("tile_x", 0), entry.get("tile_y", 0))
		if not is_in_bounds(gtile):
			continue
		_growing_tiles[gtile] = {
			"target_type": entry.get("target_type", 0),
			"ticks_remaining": entry.get("ticks_remaining", 0),
		}
		terrain_growing_started.emit(gtile, entry.get("target_type", 0))
	_fertility.clear()
	for f: Variant in data.get("fertility", []):
		_fertility.append(StringName(f))
	_hidden_resources.clear()
	for entry: Dictionary in data.get("hidden", []):
		var h_tile := Vector2i(entry.get("x", -1), entry.get("y", -1))
		if is_in_bounds(h_tile):
			_hidden_resources[h_tile] = StringName(entry.get("id", ""))
	_generation_done = true
