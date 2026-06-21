class_name OverworldSystem extends Node
## Overworld / world map — an island of small biome tiles (ocean / coast / inland),
## generated once per game and fully deterministic from one world_seed. It is the
## start-location picker (the chosen land tile drives WorldGrid.generate()) and a
## read-only inspection layer for the other tiles. Tile-to-tile travel / multi-map play
## is reserved for later. See design/quick-specs/overworld-map-system-2026-06-21.md.
##
## Registered as an Autoload, but generate()/get_tile() are pure and have no autoload
## dependencies, so the generator is instantiable in tests (OverworldSystem.new()).

const OVERWORLD_SIZE: int = 24       ## Tiles per axis (square grid).
const OVERWORLD_TILE_SIZE: int = 16  ## Render size in px — RimWorld-small vs tactical 64.
const FERTILITIES_PER_TILE: int = 3  ## Fertilities each land tile supports.

## --- Island shape (radial falloff + low-frequency noise) ---
## A tile is land when (noise01 - radial_falloff) > _ISLAND_THRESHOLD. Higher threshold =
## smaller island / more ocean. The falloff guarantees an all-ocean ring at the grid edges.
const _ISLAND_THRESHOLD: float = 0.10
const _ISLAND_FALLOFF_POWER: float = 2.0    ## Steepness of the radial coast (rounder if higher).
const _ISLAND_NOISE_FREQUENCY: float = 0.12 ## Coastline raggedness.
const _ISLAND_NOISE_OCTAVES: int = 3

## Large seed offsets so the overworld RNG/noise never aligns with tactical-map seeds.
const _ISLAND_NOISE_SEED_OFFSET: int = 1000000

enum Biome { OCEAN, COAST, INLAND }
## Direction from a coast tile toward its adjacent ocean.
enum Direction { NORTH, EAST, SOUTH, WEST }

## Maps a coast Direction (toward the ocean) onto WorldGrid.generate()'s coast_edge
## convention (0 top, 1 bottom, 2 left, 3 right) so a coast tile's tactical map faces the
## ocean the same way it does on the world map.
const _DIRECTION_TO_COAST_EDGE: Dictionary = {
	Direction.NORTH: 0,
	Direction.SOUTH: 1,
	Direction.WEST: 2,
	Direction.EAST: 3,
}

## Orthogonal neighbor offsets in Direction order (N, E, S, W) — priority order for coast.
const _DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),  # NORTH
	Vector2i(1, 0),   # EAST
	Vector2i(0, 1),   # SOUTH
	Vector2i(-1, 0),  # WEST
]

## A single overworld cell. Immutable after generation except is_start / start fertilities.
class OverworldTile:
	var coord: Vector2i
	var biome: int               ## Biome enum value.
	var tile_seed: int           ## Permanent; derived from world_seed + coord. Never re-rolled.
	var fertilities: Array[StringName]  ## FERTILITIES_PER_TILE entries; empty for OCEAN.
	var coast_edge: int          ## WorldGrid coast_edge (0..3) for COAST tiles; -1 otherwise.
	var is_start: bool

	func _init(p_coord: Vector2i, p_biome: int, p_tile_seed: int) -> void:
		coord = p_coord
		biome = p_biome
		tile_seed = p_tile_seed
		fertilities = []
		coast_edge = -1
		is_start = false

## Emitted after generate() completes.
signal overworld_generated
## Emitted when the player picks a start tile.
signal start_selected(coord: Vector2i)

var _world_seed: int = 0
var _start_coord: Vector2i = Vector2i(-1, -1)
var _tiles: Dictionary = {}  ## Vector2i -> OverworldTile
var _generated: bool = false


# --- Generation --------------------------------------------------------------

## Builds the whole overworld deterministically from world_seed. Same seed → identical
## biomes, per-tile seeds and fertilities. Re-callable (resets prior state).
func generate(world_seed: int) -> void:
	_world_seed = world_seed
	_start_coord = Vector2i(-1, -1)
	_tiles.clear()

	var land_mask := _build_island_mask(world_seed)
	# Guarantee a non-empty island: the center is always land, so there is always at least
	# one connected landmass and a selectable start tile, for any seed.
	land_mask[Vector2i(OVERWORLD_SIZE / 2, OVERWORLD_SIZE / 2)] = true
	_keep_largest_island(land_mask)

	for x in range(OVERWORLD_SIZE):
		for y in range(OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			var biome: int = Biome.INLAND if land_mask[coord] else Biome.OCEAN
			_tiles[coord] = OverworldTile.new(coord, biome, _tile_seed(world_seed, coord))

	_classify_coasts()
	_roll_all_fertilities()

	_generated = true
	overworld_generated.emit()


## Radial-falloff + noise island mask. Returns Vector2i -> bool (true = land).
func _build_island_mask(world_seed: int) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = world_seed + _ISLAND_NOISE_SEED_OFFSET
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = _ISLAND_NOISE_OCTAVES
	noise.frequency = _ISLAND_NOISE_FREQUENCY

	var center: float = (OVERWORLD_SIZE - 1) * 0.5
	var mask: Dictionary = {}
	for x in range(OVERWORLD_SIZE):
		for y in range(OVERWORLD_SIZE):
			# Normalized radial distance from center: 0 at center, 1 at edge midpoints.
			var dx: float = (x - center) / center
			var dy: float = (y - center) / center
			var radial: float = clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var falloff: float = pow(radial, _ISLAND_FALLOFF_POWER)
			var n01: float = (noise.get_noise_2d(x, y) + 1.0) / 2.0
			mask[Vector2i(x, y)] = (n01 - falloff) > _ISLAND_THRESHOLD
	return mask


## Keeps only the largest 4-connected land component; smaller islets become ocean.
## Guarantees the AC "land forms a single connected island".
func _keep_largest_island(mask: Dictionary) -> void:
	var visited: Dictionary = {}
	var best_component: Array[Vector2i] = []
	for coord: Vector2i in mask:
		if not mask[coord] or visited.has(coord):
			continue
		var component: Array[Vector2i] = []
		var stack: Array[Vector2i] = [coord]
		visited[coord] = true
		while not stack.is_empty():
			var tile: Vector2i = stack.pop_back()
			component.append(tile)
			for off: Vector2i in _DIR_OFFSETS:
				var nb: Vector2i = tile + off
				if mask.get(nb, false) and not visited.has(nb):
					visited[nb] = true
					stack.append(nb)
		if component.size() > best_component.size():
			best_component = component
	# Flip everything not in the largest component to ocean.
	var keep: Dictionary = {}
	for tile: Vector2i in best_component:
		keep[tile] = true
	for coord: Vector2i in mask:
		mask[coord] = keep.has(coord)


## Marks land tiles touching ocean as COAST and records the ocean-facing edge.
func _classify_coasts() -> void:
	for coord: Vector2i in _tiles:
		var tile: OverworldTile = _tiles[coord]
		if tile.biome == Biome.OCEAN:
			continue
		for dir in range(_DIR_OFFSETS.size()):
			var nb: Vector2i = coord + _DIR_OFFSETS[dir]
			if _is_ocean_or_outside(nb):
				tile.biome = Biome.COAST
				tile.coast_edge = _DIRECTION_TO_COAST_EDGE[dir]
				break  # N → E → S → W priority


## Out-of-bounds counts as ocean (the world is surrounded by sea).
func _is_ocean_or_outside(coord: Vector2i) -> bool:
	if not _tiles.has(coord):
		return true
	return (_tiles[coord] as OverworldTile).biome == Biome.OCEAN


## Rolls FERTILITIES_PER_TILE fertilities for every land tile from WorldGrid.FERTILITY_POOL,
## seeded by each tile's own permanent seed (deterministic, independent per tile).
func _roll_all_fertilities() -> void:
	for coord: Vector2i in _tiles:
		var tile: OverworldTile = _tiles[coord]
		if tile.biome == Biome.OCEAN:
			continue
		tile.fertilities = _roll_fertility(tile.tile_seed)


## Deterministic Fisher–Yates draw of FERTILITIES_PER_TILE from the shared fertility pool.
## Mirrors WorldGrid._roll_fertility so the two stay consistent.
func _roll_fertility(tile_seed: int) -> Array[StringName]:
	var pool: Array[StringName] = WorldGrid.FERTILITY_POOL.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = tile_seed
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: StringName = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var result: Array[StringName] = []
	for k in range(mini(FERTILITIES_PER_TILE, pool.size())):
		result.append(pool[k])
	return result


## Stable integer hash of (world_seed, coord) — the tile's permanent seed.
func _tile_seed(world_seed: int, coord: Vector2i) -> int:
	var h: int = world_seed * 73856093 + coord.x * 19349663 + coord.y * 83492791
	return h & 0x7fffffff


# --- Queries -----------------------------------------------------------------

func is_generated() -> bool:
	return _generated


func get_size() -> int:
	return OVERWORLD_SIZE


## Returns the tile at coord, or null if out of bounds.
func get_tile(coord: Vector2i) -> OverworldTile:
	return _tiles.get(coord, null)


func get_biome(coord: Vector2i) -> int:
	var tile := get_tile(coord)
	return tile.biome if tile != null else Biome.OCEAN


## A tile can be a start location only if it is land (COAST or INLAND).
func is_selectable(coord: Vector2i) -> bool:
	var tile := get_tile(coord)
	return tile != null and tile.biome != Biome.OCEAN


func get_start_coord() -> Vector2i:
	return _start_coord


# --- Start selection ---------------------------------------------------------

## Picks coord as the start location. Forces the start map's fertilities to
## WorldGrid.STARTING_FERTILITY (clay/wheat/wild). Returns false for ocean / out-of-bounds.
func select_start(coord: Vector2i) -> bool:
	if not is_selectable(coord):
		return false
	if _start_coord != Vector2i(-1, -1):
		var prev: OverworldTile = _tiles[_start_coord]
		prev.is_start = false
		prev.fertilities = _roll_fertility(prev.tile_seed)  # restore rolled set
	var tile: OverworldTile = _tiles[coord]
	tile.is_start = true
	tile.fertilities = WorldGrid.STARTING_FERTILITY.duplicate()
	_start_coord = coord
	start_selected.emit(coord)
	return true


## Generates the tactical map for the given tile onto an existing WorldGrid: passes the
## tile's permanent seed and fertilities, and (for COAST) forces the matching coast edge.
func generate_tactical_map(grid: WorldGrid, coord: Vector2i) -> bool:
	var tile := get_tile(coord)
	if tile == null or tile.biome == Biome.OCEAN:
		return false
	grid.generate(tile.tile_seed, tile.fertilities, tile.coast_edge)
	return true


# --- Persistence -------------------------------------------------------------

## The overworld is fully reproducible from world_seed, so the save stores only the seed
## and the chosen start coord.
func serialize() -> Dictionary:
	return {
		"world_seed": _world_seed,
		"start_coord": [_start_coord.x, _start_coord.y],
	}


func deserialize(data: Dictionary) -> void:
	generate(int(data.get("world_seed", 0)))
	var sc: Array = data.get("start_coord", [-1, -1])
	var coord := Vector2i(int(sc[0]), int(sc[1]))
	if coord != Vector2i(-1, -1):
		select_start(coord)
