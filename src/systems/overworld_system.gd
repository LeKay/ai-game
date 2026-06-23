extends Node
## OverworldSystem (Autoload — registered in project.godot; no class_name to avoid hiding
## the autoload singleton). Access via the global `OverworldSystem` per the singletons rule.
## Overworld / world map — an island of small biome tiles (ocean / coast / inland),
## generated once per game and fully deterministic from one world_seed. It is the
## start-location picker (the chosen land tile drives WorldGrid.generate()), a tile inspection
## layer, and the entry point for tile-to-tile travel: after a start is chosen, double-clicking
## another land tile switches the active tactical map (MapRoot + WorldSaveManager snapshot/restore
## per-tile colonies in memory). See design/quick-specs/overworld-map-system-2026-06-21.md.
##
## Registered as an Autoload, but generate()/get_tile() are pure and have no autoload
## dependencies, so the generator is instantiable in tests (OverworldSystem.new()).

const OVERWORLD_SIZE: int = 128      ## Tiles per axis (square grid).
const OVERWORLD_TILE_SIZE: int = 16  ## Render size in px — RimWorld-small vs tactical 64.
const FERTILITIES_PER_TILE: int = 3  ## Fertilities each land tile supports.

## --- Island shape (radial falloff + low-frequency noise) ---
## A tile is land when (noise01 - radial_falloff) > _ISLAND_THRESHOLD. Higher threshold =
## smaller island / more ocean. The falloff guarantees an all-ocean ring at the grid edges.
const _ISLAND_THRESHOLD: float = 0.10
const _ISLAND_FALLOFF_POWER: float = 2.0    ## Steepness of the radial coast (rounder if higher).
## Coastline raggedness expressed as noise periods across the whole map, so the island keeps
## the same overall shape at any OVERWORLD_SIZE (frequency = periods / size).
const _ISLAND_NOISE_PERIODS: float = 2.9
const _ISLAND_NOISE_OCTAVES: int = 3

## Large seed offsets so the overworld RNG/noise never aligns with tactical-map seeds.
const _ISLAND_NOISE_SEED_OFFSET: int = 1000000

## --- Biome classification (height + moisture) ---
## Non-coast land splits into MOUNTAIN / FOREST / plains INLAND from two independent noise
## fields. Elevation gets a radial term (interior = higher) so mountains cluster inland.
const _MOUNTAIN_ELEV_THRESHOLD: float = 0.62   ## Higher = fewer / smaller mountain ranges.
const _FOREST_MOISTURE_THRESHOLD: float = 0.55 ## Higher = sparser forests.
const _BIOME_RADIAL_WEIGHT: float = 0.35       ## How strongly elevation pulls toward the interior.
const _BIOME_NOISE_PERIODS: float = 5.0        ## Biome blob size, expressed as periods across the map.
const _BIOME_NOISE_OCTAVES: int = 3
const _ELEV_NOISE_SEED_OFFSET: int = 2000000
const _MOIST_NOISE_SEED_OFFSET: int = 3000000

## --- Rivers (springs in the mountains, flows downhill to the coast) ---
const RIVER_COUNT: int = 6                ## Rivers per island (tuning knob; 5–7 reads well).
const _RIVER_MAX_STEPS: int = OVERWORLD_SIZE * 2  ## Safety bound on a single river walk.
## Pulls each downhill step outward (toward the low-elevation coast) so rivers don't stall in
## interior noise pits — added to the height score as -bias * radial_distance.
const _RIVER_OCEAN_BIAS: float = 0.15
const _RIVER_SEED_OFFSET: int = 4000000

## --- Lakes (freshwater blobs grown in interior basins) ---
const LAKE_COUNT: int = 4                 ## Lakes per island (tuning knob).
const _LAKE_SIZE_MIN: int = 4             ## Smallest lake (tiles).
const _LAKE_SIZE_MAX: int = 14            ## Largest lake (tiles).
const _LAKE_SEED_OFFSET: int = 5000000

## --- NPC cities (claimed land you cannot settle on or beside) ---
const CITY_COUNT: int = 4                 ## NPC cities per island (tuning knob).
const _CITY_EXCLUSION_RADIUS: int = 5     ## Tiles around a city that are off-limits as a start.
const _CITY_MIN_SPACING: int = 12         ## Cities sit at least this far apart (spread them out).
const _CITY_SEED_OFFSET: int = 6000000

## The factions that own NPC cities. `id` matches the emblem file assets/ui/icons/factions/<id>.png;
## `name` is the display label. Each city is assigned one faction (distinct while CITY_COUNT ≤ size).
const FACTIONS: Array[Dictionary] = [
	{"id": "ironhold", "name": "Ironhold"},
	{"id": "verdant", "name": "Verdant Pact"},
	{"id": "tidewatch", "name": "Tidewatch"},
	{"id": "goldfield", "name": "Goldfield"},
	{"id": "ravenmoor", "name": "Ravenmoor"},
]

## RIVER and LAKE are freshwater bodies: non-selectable like OCEAN, but they border their land
## neighbours with fresh — not salt — water (river / lake band on the tactical map).
enum Biome { OCEAN, COAST, INLAND, FOREST, MOUNTAIN, RIVER, LAKE }
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
	var coast_edge: int          ## Primary (first by N→E→S→W priority) coast edge; -1 if inland.
	var coast_edges: Array[int]  ## ALL ocean-facing edges (0..3) for COAST tiles; empty otherwise.
	var river_edges: Array[int]  ## WorldGrid edges (0..3) of a LAND tile that face an adjacent RIVER tile.
	var lake_edges: Array[int]   ## WorldGrid edges (0..3) of a LAND tile that face an adjacent LAKE tile.
	var is_start: bool

	func _init(p_coord: Vector2i, p_biome: int, p_tile_seed: int) -> void:
		coord = p_coord
		biome = p_biome
		tile_seed = p_tile_seed
		fertilities = []
		coast_edge = -1
		coast_edges = []
		river_edges = []
		lake_edges = []
		is_start = false

## Emitted after generate() completes.
signal overworld_generated
## Emitted when the player picks a start tile.
signal start_selected(coord: Vector2i)

var _world_seed: int = 0
var _start_coord: Vector2i = Vector2i(-1, -1)
var _tiles: Dictionary = {}  ## Vector2i -> OverworldTile
var _cities: Array[Vector2i] = []         ## NPC city tiles (deterministic from world_seed).
var _city_blocked: Dictionary = {}        ## Vector2i -> true: city tiles + their exclusion radius.
var _city_factions: Dictionary = {}       ## Vector2i (city) -> int index into FACTIONS.
var _generated: bool = false


# --- Generation --------------------------------------------------------------

## Builds the whole overworld deterministically from world_seed. Same seed → identical
## biomes, per-tile seeds and fertilities. Re-callable (resets prior state).
func generate(world_seed: int) -> void:
	_world_seed = world_seed
	_start_coord = Vector2i(-1, -1)
	_tiles.clear()
	_cities.clear()
	_city_blocked.clear()
	_city_factions.clear()

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
	_classify_biomes(world_seed)
	_carve_overworld_lakes(world_seed)  # before rivers, so a river can flow into a lake
	_carve_rivers(world_seed)
	_reclassify_river_pools_as_lakes()  # pooled (≥2-wide) river clusters read as lakes, not rivers
	_classify_water_adjacency()         # river_edges / lake_edges on land, mirroring _classify_coasts
	_place_cities(world_seed)           # NPC cities + their no-start exclusion radius
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
	noise.frequency = _ISLAND_NOISE_PERIODS / float(OVERWORLD_SIZE)

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
		# Record EVERY ocean-facing edge — a peninsula tip touches the sea on several sides and
		# its tactical map should carry coast on each of them. coast_edge keeps the first (by
		# N → E → S → W priority) for display / back-compat.
		for dir in range(_DIR_OFFSETS.size()):
			var nb: Vector2i = coord + _DIR_OFFSETS[dir]
			if _is_ocean_or_outside(nb):
				tile.biome = Biome.COAST
				tile.coast_edges.append(_DIRECTION_TO_COAST_EDGE[dir])
		if not tile.coast_edges.is_empty():
			tile.coast_edge = tile.coast_edges[0]


## Splits non-COAST land into MOUNTAIN / FOREST / plains INLAND from two independent noise
## fields. Elevation blends in a radial term (interior = higher) so mountain ranges cluster
## toward the island's centre and rivers have high ground to spring from. Deterministic from
## world_seed; COAST tiles and OCEAN are left untouched.
func _classify_biomes(world_seed: int) -> void:
	var elev := _make_elev_noise(world_seed)

	var moist := FastNoiseLite.new()
	moist.noise_type = FastNoiseLite.TYPE_PERLIN
	moist.seed = world_seed + _MOIST_NOISE_SEED_OFFSET
	moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	moist.fractal_octaves = _BIOME_NOISE_OCTAVES
	moist.frequency = _BIOME_NOISE_PERIODS / float(OVERWORLD_SIZE)

	var center: float = (OVERWORLD_SIZE - 1) * 0.5
	for coord: Vector2i in _tiles:
		var tile: OverworldTile = _tiles[coord]
		# Only plains land is reclassified — coast stays coast, ocean stays ocean.
		if tile.biome != Biome.INLAND:
			continue
		var dx: float = (coord.x - center) / center
		var dy: float = (coord.y - center) / center
		var radial: float = clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
		var interior: float = 1.0 - radial  # 1 at centre, 0 at the edge
		var elev01: float = (elev.get_noise_2d(coord.x, coord.y) + 1.0) / 2.0
		var height: float = lerpf(elev01, interior, _BIOME_RADIAL_WEIGHT)
		var moist01: float = (moist.get_noise_2d(coord.x, coord.y) + 1.0) / 2.0
		if height > _MOUNTAIN_ELEV_THRESHOLD:
			tile.biome = Biome.MOUNTAIN
		elif moist01 > _FOREST_MOISTURE_THRESHOLD:
			tile.biome = Biome.FOREST


## Builds the elevation noise used both for biome classification and river descent, so the two
## agree on which way is "downhill". Same config, seeded from world_seed.
func _make_elev_noise(world_seed: int) -> FastNoiseLite:
	var elev := FastNoiseLite.new()
	elev.noise_type = FastNoiseLite.TYPE_PERLIN
	elev.seed = world_seed + _ELEV_NOISE_SEED_OFFSET
	elev.fractal_type = FastNoiseLite.FRACTAL_FBM
	elev.fractal_octaves = _BIOME_NOISE_OCTAVES
	elev.frequency = _BIOME_NOISE_PERIODS / float(OVERWORLD_SIZE)
	return elev


## Returns the blended elevation height (0..1) used for biome classification at coord.
## Reused by river generation to walk downhill. Returns 0 for out-of-bounds.
func _biome_height(coord: Vector2i, elev: FastNoiseLite) -> float:
	if not _tiles.has(coord):
		return 0.0
	var center: float = (OVERWORLD_SIZE - 1) * 0.5
	var dx: float = (coord.x - center) / center
	var dy: float = (coord.y - center) / center
	var radial: float = clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
	var interior: float = 1.0 - radial
	var elev01: float = (elev.get_noise_2d(coord.x, coord.y) + 1.0) / 2.0
	return lerpf(elev01, interior, _BIOME_RADIAL_WEIGHT)


# --- Lakes -------------------------------------------------------------------

## Grows LAKE_COUNT freshwater lakes as blobs in interior basins. Seeds are non-coast plains /
## forest land (lakes avoid mountains and the shore so they read as inland freshwater), drawn
## from a seeded shuffle for determinism. Must run after _classify_biomes (needs biomes set) and
## before _carve_rivers (so a river can flow into a lake). Converts land tiles to Biome.LAKE.
func _carve_overworld_lakes(world_seed: int) -> void:
	var candidates: Array[Vector2i] = []
	for coord: Vector2i in _tiles:
		if _is_lake_seed_biome((_tiles[coord] as OverworldTile).biome):
			candidates.append(coord)
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _LAKE_SEED_OFFSET
	for i in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var made: int = 0
	for seed_coord: Vector2i in candidates:
		if made >= LAKE_COUNT:
			break
		# A prior lake may already have flooded this seed — only start on still-dry basin land.
		if not _is_lake_seed_biome((_tiles[seed_coord] as OverworldTile).biome):
			continue
		_grow_lake(seed_coord, rng.randi_range(_LAKE_SIZE_MIN, _LAKE_SIZE_MAX), rng)
		made += 1


## Lakes only flood plains / forest basins — never mountains, coast, ocean or existing water.
func _is_lake_seed_biome(biome: int) -> bool:
	return biome == Biome.INLAND or biome == Biome.FOREST


## Randomized frontier flood from `start`, converting up to `target_size` basin-land tiles to
## LAKE for an irregular blob. Determinism comes from the shared lake RNG.
func _grow_lake(start: Vector2i, target_size: int, rng: RandomNumberGenerator) -> void:
	var filled: int = 0
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty() and filled < target_size:
		var idx: int = rng.randi_range(0, frontier.size() - 1)
		var coord: Vector2i = frontier[idx]
		frontier.remove_at(idx)
		if coord == _center_coord():
			continue  # never flood the guaranteed-land centre
		var tile := get_tile(coord)
		if tile == null or not _is_lake_seed_biome(tile.biome):
			continue
		tile.biome = Biome.LAKE
		filled += 1
		for off: Vector2i in _DIR_OFFSETS:
			frontier.append(coord + off)


# --- Rivers ------------------------------------------------------------------

## Springs RIVER_COUNT rivers in the mountains and walks each one downhill to the sea, converting
## the tiles it flows through into Biome.RIVER (freshwater, non-selectable). The source mountain
## itself stays land, so the river's first water tile sits right beside a mountain. Deterministic
## from world_seed: the source set is a seeded shuffle of all mountain tiles and the descent is
## purely scored (no per-step randomness). Must run after _classify_biomes (needs MOUNTAIN/COAST).
func _carve_rivers(world_seed: int) -> void:
	var sources: Array[Vector2i] = []
	for coord: Vector2i in _tiles:
		if (_tiles[coord] as OverworldTile).biome == Biome.MOUNTAIN:
			sources.append(coord)
	if sources.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _RIVER_SEED_OFFSET
	for i in range(sources.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = sources[i]
		sources[i] = sources[j]
		sources[j] = tmp
	var elev := _make_elev_noise(world_seed)
	for k in range(mini(RIVER_COUNT, sources.size())):
		_trace_river(sources[k], elev)


## Walks one river from `source` (a mountain) downhill — lowest blended height, biased outward
## toward the low-elevation coast — converting each stepped land tile into Biome.RIVER. It never
## flows onto the OCEAN; instead it stops once it reaches the shore (a COAST tile, now its mouth)
## or merges into existing water (another RIVER / a LAKE), or runs out of steps.
func _trace_river(source: Vector2i, elev: FastNoiseLite) -> void:
	var pos := source  # the source mountain stays land; the river springs from its downhill neighbour
	var visited: Dictionary = {pos: true}
	for _step in range(_RIVER_MAX_STEPS):
		var best := Vector2i(-1, -1)
		var best_score: float = INF
		for dir in range(_DIR_OFFSETS.size()):
			var nb: Vector2i = pos + _DIR_OFFSETS[dir]
			if not _tiles.has(nb) or visited.has(nb) or nb == _center_coord():
				continue  # skip out-of-bounds, already-walked, and the protected centre tile
			# Never step onto the sea — a river meets the ocean at its coast mouth, not in it.
			if (_tiles[nb] as OverworldTile).biome == Biome.OCEAN:
				continue
			# Lower height is better; the outward bias subtracts more the closer nb is to the edge.
			var score: float = _biome_height(nb, elev) - _RIVER_OCEAN_BIAS * _radial_distance(nb)
			if score < best_score:
				best_score = score
				best = nb
		if best == Vector2i(-1, -1):
			return  # boxed in (all neighbours ocean or already visited)
		var bt: OverworldTile = _tiles[best]
		# Reaching the shore or any existing freshwater ends the river there.
		var reached_water: bool = bt.biome == Biome.COAST or bt.biome == Biome.RIVER or bt.biome == Biome.LAKE
		bt.biome = Biome.RIVER
		# A river mouth was a COAST tile; as water it no longer carries salt-coast edges.
		bt.coast_edges.clear()
		bt.coast_edge = -1
		visited[best] = true
		pos = best
		if reached_water:
			return


## Where rivers pool wider than a single tile they read as small lakes, not rivers. Any RIVER tile
## that belongs to a fully-RIVER 2×2 block is part of such a pool and is promoted to Biome.LAKE;
## genuine 1-tile-wide river lines (which never form a 2×2 block) stay RIVER. Runs after
## _carve_rivers and before _classify_water_adjacency so adjacency sees the final biomes.
func _reclassify_river_pools_as_lakes() -> void:
	var pooled: Dictionary = {}  # Vector2i -> true
	for coord: Vector2i in _tiles:
		if (_tiles[coord] as OverworldTile).biome != Biome.RIVER:
			continue
		# Test the 2×2 block whose top-left corner is `coord`; if all four are RIVER, it pools.
		var block := [coord, coord + Vector2i(1, 0), coord + Vector2i(0, 1), coord + Vector2i(1, 1)]
		var all_river := true
		for c: Vector2i in block:
			var t := get_tile(c)
			if t == null or t.biome != Biome.RIVER:
				all_river = false
				break
		if all_river:
			for c: Vector2i in block:
				pooled[c] = true
	for coord: Vector2i in pooled:
		(_tiles[coord] as OverworldTile).biome = Biome.LAKE


## The forced-land centre tile (generate() guarantees it is land). Freshwater must never flood it,
## so it always stays a selectable start — both for the player and the headless centre fallback.
func _center_coord() -> Vector2i:
	return Vector2i(OVERWORLD_SIZE / 2, OVERWORLD_SIZE / 2)


# --- NPC cities --------------------------------------------------------------

## Places up to CITY_COUNT NPC cities, each on land that matches its faction's theme biome
## (Ironhold→mountain, Verdant→forest, Goldfield→plains, Tidewatch→coast, Ravenmoor→beside a lake),
## and records the tiles they block for starts (the city tile plus everything within
## _CITY_EXCLUSION_RADIUS). Deterministic from world_seed: factions are tried in a seeded-shuffle
## order, and within each faction the matching tiles are seeded-shuffled and the first one far
## enough (≥ _CITY_MIN_SPACING) from every city already placed is taken. A faction whose theme has
## no free tile this island is simply skipped. The guaranteed-land centre and its radius are kept
## clear so the fallback start tile is never blocked. Must run after all water carving.
func _place_cities(world_seed: int) -> void:
	var center := _center_coord()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + _CITY_SEED_OFFSET
	# Try each faction once, in a shuffled order, placing it on a theme-matching tile.
	var faction_order: Array[int] = []
	for k in range(FACTIONS.size()):
		faction_order.append(k)
	_seeded_shuffle_ints(faction_order, rng)
	for faction_idx: int in faction_order:
		if _cities.size() >= CITY_COUNT:
			break
		var candidates: Array[Vector2i] = []
		for coord: Vector2i in _tiles:
			if not is_selectable(coord) or _within_radius(coord, center, _CITY_EXCLUSION_RADIUS):
				continue
			if _matches_faction_theme(coord, faction_idx):
				candidates.append(coord)
		_seeded_shuffle(candidates, rng)
		for coord: Vector2i in candidates:
			var too_close := false
			for placed: Vector2i in _cities:
				if _within_radius(coord, placed, _CITY_MIN_SPACING):
					too_close = true
					break
			if not too_close:
				_cities.append(coord)
				_city_factions[coord] = faction_idx
				break
	# Build the no-start exclusion set: every tile within the radius of a city (centre kept clear).
	for city: Vector2i in _cities:
		for dx in range(-_CITY_EXCLUSION_RADIUS, _CITY_EXCLUSION_RADIUS + 1):
			for dy in range(-_CITY_EXCLUSION_RADIUS, _CITY_EXCLUSION_RADIUS + 1):
				var t: Vector2i = city + Vector2i(dx, dy)
				if t != center and _tiles.has(t) and _within_radius(t, city, _CITY_EXCLUSION_RADIUS):
					_city_blocked[t] = true


## True if `coord` suits the themed faction `faction_idx`: a biome match for land themes, or
## adjacency to a lake for Ravenmoor. Cities only sit on selectable land, so water themes are
## expressed as "borders" the water rather than sitting on it.
func _matches_faction_theme(coord: Vector2i, faction_idx: int) -> bool:
	var tile: OverworldTile = _tiles[coord]
	match FACTIONS[faction_idx]["id"]:
		"ironhold":
			return tile.biome == Biome.MOUNTAIN     # the forge in the mountains
		"verdant":
			return tile.biome == Biome.FOREST        # the woodland pact
		"goldfield":
			return tile.biome == Biome.INLAND        # the farming plains
		"tidewatch":
			return tile.biome == Biome.COAST         # the seaside watch
		"ravenmoor":
			return not tile.lake_edges.is_empty()    # the moor beside a lake
		_:
			return false


## Euclidean "is `a` within `r` tiles of `b`" — the round exclusion zone around a city.
func _within_radius(a: Vector2i, b: Vector2i, r: int) -> bool:
	return Vector2(a - b).length() <= float(r)


## In-place seeded Fisher–Yates shuffle — deterministic candidate ordering for city placement.
func _seeded_shuffle(coords: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(coords.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = coords[i]
		coords[i] = coords[j]
		coords[j] = tmp


## In-place seeded Fisher–Yates shuffle of ints — deterministic faction-to-city assignment order.
func _seeded_shuffle_ints(values: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = values[i]
		values[i] = values[j]
		values[j] = tmp


## Normalized radial distance from the island centre (0 at centre, 1 at the edge).
func _radial_distance(coord: Vector2i) -> float:
	var center: float = (OVERWORLD_SIZE - 1) * 0.5
	var dx: float = (coord.x - center) / center
	var dy: float = (coord.y - center) / center
	return clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)


## Records, for every LAND tile, which edges face an adjacent RIVER tile (river_edges) and which
## face an adjacent LAKE tile (lake_edges) — the freshwater analogue of _classify_coasts. A
## tactical map then carves a river on its river_edges and a freshwater band on its lake_edges.
func _classify_water_adjacency() -> void:
	for coord: Vector2i in _tiles:
		var tile: OverworldTile = _tiles[coord]
		if _is_water(tile.biome):
			continue  # water tiles never generate a tactical map
		for dir in range(_DIR_OFFSETS.size()):
			var nb_biome: int = get_biome(coord + _DIR_OFFSETS[dir])
			var edge: int = _DIRECTION_TO_COAST_EDGE[dir]
			if nb_biome == Biome.RIVER and not tile.river_edges.has(edge):
				tile.river_edges.append(edge)
			elif nb_biome == Biome.LAKE and not tile.lake_edges.has(edge):
				tile.lake_edges.append(edge)


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
		if _is_water(tile.biome):
			continue
		tile.fertilities = _roll_fertility(tile.tile_seed, tile.biome)


## Weighted draw of FERTILITIES_PER_TILE from the shared fertility pool, seeded by the tile's
## own permanent seed and biased by its biome. Delegates to WorldGrid.roll_fertility so single-map
## and overworld stay consistent (precious deposits — silver/gold/gemstones — are rare via
## FERTILITY_WEIGHTS; coast/mountain/forest restrictions applied via the biome class).
func _roll_fertility(tile_seed: int, biome: int) -> Array[StringName]:
	return WorldGrid.roll_fertility(tile_seed, FERTILITIES_PER_TILE, _fertility_biome_class(biome))


## Maps an overworld Biome onto the WorldGrid.BIOME_* class that drives fertility weighting.
## Land biomes only — water tiles never roll fertilities.
func _fertility_biome_class(biome: int) -> int:
	match biome:
		Biome.MOUNTAIN: return WorldGrid.BIOME_MOUNTAIN
		Biome.FOREST:   return WorldGrid.BIOME_FOREST
		Biome.COAST:    return WorldGrid.BIOME_COAST
		_:              return WorldGrid.BIOME_PLAINS  # INLAND (RIVER/LAKE land share plains)


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


## OCEAN (salt) and RIVER / LAKE (fresh) are water — they cover no land and are never selectable.
func _is_water(biome: int) -> bool:
	return biome == Biome.OCEAN or biome == Biome.RIVER or biome == Biome.LAKE


## True if coord is a freshwater tile (river or lake).
func is_freshwater(coord: Vector2i) -> bool:
	var tile := get_tile(coord)
	return tile != null and (tile.biome == Biome.RIVER or tile.biome == Biome.LAKE)


## True if the land tile at coord borders a river (its tactical map will carry one).
func borders_river(coord: Vector2i) -> bool:
	var tile := get_tile(coord)
	return tile != null and not tile.river_edges.is_empty()


## True if the land tile at coord borders a lake (its tactical map will carry a freshwater band).
func borders_lake(coord: Vector2i) -> bool:
	var tile := get_tile(coord)
	return tile != null and not tile.lake_edges.is_empty()


## True if coord holds an NPC city.
func is_city(coord: Vector2i) -> bool:
	return _cities.has(coord)


## True if coord is an NPC city or within its exclusion radius (off-limits as a start location).
func is_city_blocked(coord: Vector2i) -> bool:
	return _city_blocked.has(coord)


## The NPC city tiles (deterministic from world_seed).
func get_cities() -> Array[Vector2i]:
	return _cities.duplicate()


## Index into FACTIONS for the city at coord, or -1 if coord is not a city.
func get_city_faction(coord: Vector2i) -> int:
	return _city_factions.get(coord, -1)


## Faction emblem id (e.g. "ironhold") for a FACTIONS index, or "" if out of range.
func get_faction_id(idx: int) -> String:
	return FACTIONS[idx]["id"] if idx >= 0 and idx < FACTIONS.size() else ""


## Faction display name (e.g. "Ironhold") for a FACTIONS index, or "" if out of range.
func get_faction_name(idx: int) -> String:
	return FACTIONS[idx]["name"] if idx >= 0 and idx < FACTIONS.size() else ""


## True if a tile is land (not ocean / river / lake). Governs travel and rendering; NOT the start
## picker — use is_start_allowed for that (it also excludes NPC cities and their radius).
func is_selectable(coord: Vector2i) -> bool:
	var tile := get_tile(coord)
	return tile != null and not _is_water(tile.biome)


## True if the player may pick coord as a start: selectable land that no NPC city claims or borders.
func is_start_allowed(coord: Vector2i) -> bool:
	return is_selectable(coord) and not is_city_blocked(coord)


func get_start_coord() -> Vector2i:
	return _start_coord


# --- Start selection ---------------------------------------------------------

## Picks coord as the start location. Forces the start map's fertilities to
## WorldGrid.STARTING_FERTILITY (clay/wheat/wild). Returns false for ocean / out-of-bounds.
func select_start(coord: Vector2i) -> bool:
	if not is_start_allowed(coord):
		return false
	if _start_coord != Vector2i(-1, -1):
		var prev: OverworldTile = _tiles[_start_coord]
		prev.is_start = false
		prev.fertilities = _roll_fertility(prev.tile_seed, prev.biome)  # restore rolled set
	var tile: OverworldTile = _tiles[coord]
	tile.is_start = true
	tile.fertilities = WorldGrid.STARTING_FERTILITY.duplicate()
	_start_coord = coord
	start_selected.emit(coord)
	return true


## Generates the tactical map for the given tile onto an existing WorldGrid: passes the tile's
## permanent seed and fertilities, the salt-coast edges (facing OCEAN), the terrain profile for
## its biome (FOREST/MOUNTAIN bias the terrain), its river edges (facing an overworld RIVER) and
## its lake edges (facing an overworld LAKE → a freshwater band). Each water feature is carved
## only on the edges that actually border that kind of water on the overworld.
func generate_tactical_map(grid: WorldGrid, coord: Vector2i) -> bool:
	var tile := get_tile(coord)
	if tile == null or _is_water(tile.biome):
		return false
	grid.generate(tile.tile_seed, tile.fertilities, tile.coast_edges, _biome_to_profile(tile.biome), tile.river_edges, tile.lake_edges)
	return true


## Maps an overworld biome onto the tactical WorldGrid.TerrainProfile that biases its terrain.
## COAST and plains INLAND both generate as PLAINS (coast adds its band separately).
func _biome_to_profile(biome: int) -> int:
	match biome:
		Biome.MOUNTAIN:
			return WorldGrid.TerrainProfile.MOUNTAIN
		Biome.FOREST:
			return WorldGrid.TerrainProfile.FOREST
		_:
			return WorldGrid.TerrainProfile.PLAINS


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
