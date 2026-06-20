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
enum TileType { EMPTY, TREE, STONE, BERRY, GRASS, IMPASSABLE, WHEAT, CLAY }

enum PlacementResult {
	SUCCESS,
	BLOCKED_BY_BOUNDS,
	BLOCKED_BY_IMPASSABLE,
	BLOCKED_BY_BUILDING,
	BLOCKED_BY_RESOURCE_TILE
}

enum DistanceMetric { MANHATTAN, EUCLIDEAN }

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
## Hidden resource deposits (e.g. clay) keyed by tile → resource_id. Not rendered;
## located via the player's Search action (find_nearest_hidden / reveal_hidden_clay).
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
## Pool of special resources a map can support. A new map rolls FERTILITY_COUNT random
## entries from this pool; the starting map is fixed via generate()'s fertility_override.
const FERTILITY_POOL: Array[StringName] = [&"clay", &"wheat", &"wild"]
## How many fertilities a freshly rolled (non-starting) map receives.
const FERTILITY_COUNT: int = 3
## The starting map's fixed fertility set (not rolled). Spec: clay, wheat, wild.
const STARTING_FERTILITY: Array[StringName] = [&"clay", &"wheat", &"wild"]
## RNG offset so the fertility roll never aligns with the terrain / smoothing seeds.
const _FERTILITY_SEED_OFFSET: int = 200000
## Number of hidden clay deposits placed on a clay-fertile map.
const CLAY_DEPOSIT_COUNT: int = 6
## Number of wheat-field tiles placed on a wheat-fertile map.
const WHEAT_FIELD_COUNT: int = 6
## Max Manhattan radius the Search action reports a clay distance for.
const CLAY_SEARCH_MAX_RADIUS: int = 58
const _HIDDEN_SEED_OFFSET: int = 300000
const _WHEAT_SEED_OFFSET: int = 400000

## Generates terrain and resource layers via 5-step Perlin noise pipeline.
## Deterministic: same seed always produces identical terrain, resources and fertility.
## Locks TerrainLayer on completion — assert fires on any subsequent call.
## fertility_override: pass a fixed fertility set (e.g. STARTING_FERTILITY) to skip the
## random roll; an empty array rolls FERTILITY_COUNT entries from FERTILITY_POOL.
func generate(world_seed: int, fertility_override: Array = []) -> void:
	assert(not _generation_done, "generate() called after terrain was locked")

	var terrain: Array
	var succeeded := false
	for attempt in range(5):
		terrain = _sample_noise(world_seed + attempt)
		terrain = _smooth_terrain(terrain, world_seed + attempt)
		terrain = _cleanup_clusters(terrain)
		if _meets_minimums(terrain):
			succeeded = true
			break

	_apply_terrain(terrain)

	if not succeeded:
		push_warning("Map generation forced-fix on attempt 5")
		_force_fix_minimums()

	_roll_fertility(world_seed, fertility_override)
	if has_fertility(&"wheat"):
		_populate_wheat_fields(world_seed)
	if has_fertility(&"clay"):
		_populate_hidden_clay(world_seed)

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


## Scatters hidden clay deposits across passable tiles. Deterministic via world_seed.
## Deposits are not rendered — the player finds them with the Search action.
func _populate_hidden_clay(world_seed: int) -> void:
	var candidates: Array[Vector2i] = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if _terrain[x][y] != TileType.IMPASSABLE:
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _HIDDEN_SEED_OFFSET
	_shuffle_tiles(candidates, rng)
	for i in range(mini(CLAY_DEPOSIT_COUNT, candidates.size())):
		_hidden_resources[candidates[i]] = &"clay"


## In-place deterministic Fisher–Yates shuffle of a tile array.
func _shuffle_tiles(tiles: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(tiles.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = tiles[i]
		tiles[i] = tiles[j]
		tiles[j] = tmp


## Populates _fertility. With a non-empty override the set is fixed (starting map);
## otherwise FERTILITY_COUNT entries are drawn from FERTILITY_POOL via a deterministic
## seed-driven Fisher–Yates shuffle (same seed → same fertility).
func _roll_fertility(world_seed: int, override_set: Array) -> void:
	_fertility.clear()
	if not override_set.is_empty():
		for id: Variant in override_set:
			_fertility.append(StringName(id))
		return
	var pool: Array[StringName] = FERTILITY_POOL.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _FERTILITY_SEED_OFFSET
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: StringName = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for k in range(mini(FERTILITY_COUNT, pool.size())):
		_fertility.append(pool[k])


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


## Reveals a hidden clay deposit at tile, converting the terrain to a CLAY pit.
## Requires the tile to be EMPTY with no resources — any existing resource must be
## cleared first (spec). Returns true on success, false if blocked or no deposit here.
func reveal_hidden_clay(tile: Vector2i) -> bool:
	if not is_in_bounds(tile):
		return false
	if _hidden_resources.get(tile, &"") != &"clay":
		return false
	if _terrain[tile.x][tile.y] != TileType.EMPTY:
		return false
	if not _resources[tile.x][tile.y].is_empty():
		return false
	_hidden_resources.erase(tile)
	_terrain[tile.x][tile.y] = TileType.CLAY
	terrain_tile_changed.emit(tile)
	return true


## Step 1: samples elevation and moisture Perlin noise for all 30×30 tiles.
## Returns Array[Array[int]] — raw TileType values before smoothing.
## Uses FastNoiseLite (Godot 4.x noise class — FastNoise does not exist in Godot 4).
func _sample_noise(noise_seed: int) -> Array:
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

	var terrain: Array = []
	for x in range(GRID_SIZE):
		var row: Array[int] = []
		terrain.append(row)
		for y in range(GRID_SIZE):
			var elev_norm: float = (elevation.get_noise_2d(x, y) + 1.0) / 2.0
			var mois_norm: float = (moisture.get_noise_2d(x, y) + 1.0) / 2.0
			var tile_type: int
			if elev_norm < 0.15:
				tile_type = TileType.IMPASSABLE
			elif elev_norm < 0.30:
				tile_type = TileType.BERRY if mois_norm < 0.5 else TileType.GRASS
			elif elev_norm < 0.55:
				tile_type = TileType.EMPTY
			elif elev_norm < 0.75:
				tile_type = TileType.TREE
			else:
				tile_type = TileType.STONE
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
				var dominant: int = _find_dominant_type(neighbors)
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
	if _terrain[tile.x][tile.y] == TileType.IMPASSABLE:
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


## Returns false only for IMPASSABLE tiles. Asserts on out-of-bounds access.
func is_passable(tile: Vector2i) -> bool:
	assert(is_in_bounds(tile), "is_passable: tile %s is out of bounds" % str(tile))
	return _terrain[tile.x][tile.y] != TileType.IMPASSABLE


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
		TileType.TREE:       return 4.0
		TileType.STONE:      return 4.0
		TileType.BERRY:      return 4.0
		TileType.GRASS:      return 4.0
		TileType.WHEAT:      return 4.0
		TileType.CLAY:       return 4.0
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
## Returns false if: out-of-bounds or IMPASSABLE. No per-tile cap.
func add_resource_to_tile(tile: Vector2i, resource_id: StringName, clearable: bool = true) -> bool:
	if not is_in_bounds(tile):
		return false
	if _terrain[tile.x][tile.y] == TileType.IMPASSABLE:
		return false
	_resources[tile.x][tile.y].append(ResourceTileData.new(resource_id, clearable))
	terrain_changed.emit(tile, RESOURCE_LAYER)
	return true


func move_one_resource(source: Vector2i, source_idx: int, target: Vector2i) -> bool:
	if not is_in_bounds(source) or not is_in_bounds(target):
		return false
	if _terrain[target.x][target.y] == TileType.IMPASSABLE:
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
