class_name WorldGrid extends Node
## Grid world data model — single source of truth for terrain, resource, and building state.
## ADR-0004: 30x30 three-layer model. TileMapLayer nodes are rendering targets only.
## Not an Autoload — instantiated as a child of MapRoot.

const GRID_SIZE: int = 30
const TILE_SIZE: int = 64  # pixels per tile
const MAX_RESOURCES_PER_TILE: int = 4

enum TileType { EMPTY, TREE, STONE, BERRY, GRASS, IMPASSABLE }

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

var _terrain: Array[Array]   # [x][y] -> TileType (int)  — write-once after generate()
var _resources: Array[Array] # [x][y] -> Array[ResourceTileData], empty when no resources
var _buildings: Array[Array] # [x][y] -> String (building_id) or null
## Set true by generate(); TerrainLayer immutability enforced in Story 002.
var _generation_done: bool = false


func _ready() -> void:
	_init_arrays()


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

## Generates terrain and resource layers via 5-step Perlin noise pipeline.
## Deterministic: same seed always produces identical terrain and resource layers.
## Locks TerrainLayer on completion — assert fires on any subsequent call.
func generate(world_seed: int) -> void:
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

	_generation_done = true


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
	return PlacementResult.SUCCESS


## Removes building from BuildingLayer at tile. Returns true if a building was present.
func remove_building(tile: Vector2i) -> bool:
	if not is_in_bounds(tile):
		return false
	if _buildings[tile.x][tile.y] == null:
		return false
	_buildings[tile.x][tile.y] = null
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


## Returns true if tile is within grid bounds. Safe to call without a pre-check.
func is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < GRID_SIZE and tile.y >= 0 and tile.y < GRID_SIZE


# --- Resource mutation ---

## Clears the resource at tile if one is present. Returns 1 if cleared, 0 if none.
## Anno-style: resources are spatial anchors — present or cleared, no quantity tracking.
## _amount is reserved for future quantity systems; currently ignored.
func harvest_resource(tile: Vector2i, _amount: int) -> int:
	assert(is_in_bounds(tile), "harvest_resource: tile %s is out of bounds" % str(tile))
	if _resources[tile.x][tile.y].is_empty():
		return 0
	var count: int = _resources[tile.x][tile.y].size()
	_resources[tile.x][tile.y] = []
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
	return true


## Places a new resource on the given tile.
## Returns false if: out-of-bounds, IMPASSABLE, or tile already holds MAX_RESOURCES_PER_TILE.
func add_resource_to_tile(tile: Vector2i, resource_id: StringName, clearable: bool = true) -> bool:
	if not is_in_bounds(tile):
		return false
	if _terrain[tile.x][tile.y] == TileType.IMPASSABLE:
		return false
	if _resources[tile.x][tile.y].size() >= MAX_RESOURCES_PER_TILE:
		return false
	_resources[tile.x][tile.y].append(ResourceTileData.new(resource_id, clearable))
	return true


func move_one_resource(source: Vector2i, source_idx: int, target: Vector2i) -> bool:
	if not is_in_bounds(source) or not is_in_bounds(target):
		return false
	if _terrain[target.x][target.y] == TileType.IMPASSABLE:
		return false
	var src_arr: Array = _resources[source.x][source.y]
	if source_idx < 0 or source_idx >= src_arr.size():
		return false
	if _resources[target.x][target.y].size() >= MAX_RESOURCES_PER_TILE:
		return false
	var entry: ResourceTileData = src_arr[source_idx]
	src_arr.remove_at(source_idx)
	_resources[target.x][target.y].append(entry)
	return true


# --- Serialization (implemented with save/load system) ---

## Serializes grid state to a Dictionary for save/load.
func serialize() -> Dictionary:
	return {}


## Restores grid state from a serialized Dictionary.
func deserialize(_data: Dictionary) -> void:
	pass
