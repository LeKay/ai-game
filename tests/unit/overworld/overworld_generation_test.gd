## gdUnit4 test suite for the Overworld System (Slice 1: data model + island generation).
##
## Covers determinism, the island/ocean structure, per-tile fertilities, coast
## classification, start selection (ocean rejected, start forced to clay/wheat/wild),
## and save/load round-trip.
## Spec: design/quick-specs/overworld-map-system-2026-06-21.md

extends GdUnitTestSuite

const OverworldScript := preload("res://src/systems/overworld_system.gd")
const WorldGridScript := preload("res://src/systems/world_grid.gd")

const SEED_A := 42
const SEED_B := 1337


func _make_overworld() -> Node:
	var ow := OverworldScript.new()
	add_child(ow)
	auto_free(ow)
	return ow


func _land_coords(ow: Node) -> Array:
	var coords: Array = []
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			if ow.is_selectable(Vector2i(x, y)):
				coords.append(Vector2i(x, y))
	return coords


## First tile the player may actually start on (land that no NPC city claims or borders).
func _first_start_tile(ow: Node) -> Vector2i:
	for coord: Vector2i in _land_coords(ow):
		if ow.is_start_allowed(coord):
			return coord
	return Vector2i(-1, -1)


# ---- Determinism ----

func test_overworld_generate_same_seed_identical_biomes_and_seeds() -> void:
	# Arrange
	var ow_a := _make_overworld()
	ow_a.generate(SEED_A)

	# Act
	var ow_b := _make_overworld()
	ow_b.generate(SEED_A)

	# Assert
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			var a = ow_a.get_tile(coord)
			var b = ow_b.get_tile(coord)
			assert_int(b.biome).is_equal(a.biome)
			assert_int(b.tile_seed).is_equal(a.tile_seed)
			assert_array(b.fertilities).is_equal(a.fertilities)
			assert_int(b.coast_edge).is_equal(a.coast_edge)


func test_overworld_different_seeds_differ() -> void:
	# Arrange
	var ow_a := _make_overworld()
	ow_a.generate(SEED_A)
	var ow_b := _make_overworld()
	ow_b.generate(SEED_B)

	# Act — compare the full biome grid.
	var identical := true
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			if ow_a.get_biome(Vector2i(x, y)) != ow_b.get_biome(Vector2i(x, y)):
				identical = false

	# Assert
	assert_bool(identical).is_false()


# ---- Island structure ----

func test_overworld_all_edge_tiles_are_ocean() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var n := OverworldScript.OVERWORLD_SIZE

	# Act / Assert — every border tile must be ocean (natural island boundary).
	for i in range(n):
		assert_int(ow.get_biome(Vector2i(i, 0))).is_equal(OverworldScript.Biome.OCEAN)
		assert_int(ow.get_biome(Vector2i(i, n - 1))).is_equal(OverworldScript.Biome.OCEAN)
		assert_int(ow.get_biome(Vector2i(0, i))).is_equal(OverworldScript.Biome.OCEAN)
		assert_int(ow.get_biome(Vector2i(n - 1, i))).is_equal(OverworldScript.Biome.OCEAN)


func test_overworld_island_is_single_connected_component() -> void:
	# The island (everything that is not ocean — land plus its interior freshwater rivers/lakes)
	# must be one connected landmass. Freshwater is carved out of that island in place, so the
	# island stays a single component even though rivers/lakes are no longer selectable land.
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var island: Array = []
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			if ow.get_biome(coord) != OverworldScript.Biome.OCEAN:
				island.append(coord)
	assert_int(island.size()).is_greater(0)

	# Act — 4-connected flood from the first island tile.
	var offsets := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var island_set: Dictionary = {}
	for c in island:
		island_set[c] = true
	var visited: Dictionary = {}
	var stack: Array = [island[0]]
	visited[island[0]] = true
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		for off in offsets:
			var nb: Vector2i = t + off
			if island_set.has(nb) and not visited.has(nb):
				visited[nb] = true
				stack.append(nb)

	# Assert — the flood reached every non-ocean tile (one island).
	assert_int(visited.size()).is_equal(island.size())


# ---- Fertilities ----

func test_overworld_land_tiles_have_fertilities_ocean_has_none() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act / Assert
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var tile = ow.get_tile(Vector2i(x, y))
			# Water tiles (ocean / river / lake) hold no land, so no fertilities.
			if ow.is_selectable(Vector2i(x, y)):
				var expected = mini(OverworldScript.FERTILITIES_PER_TILE, WorldGridScript.FERTILITY_POOL.size())
				assert_int(tile.fertilities.size()).is_equal(expected)
			else:
				assert_int(tile.fertilities.size()).is_equal(0)


# ---- Coast classification ----

func test_overworld_coast_tiles_have_valid_edge() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act / Assert — every COAST tile records an edge in 0..3; inland records -1.
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var tile = ow.get_tile(Vector2i(x, y))
			if tile.biome == OverworldScript.Biome.COAST:
				assert_int(tile.coast_edge).is_between(0, 3)
			elif tile.biome == OverworldScript.Biome.INLAND:
				assert_int(tile.coast_edge).is_equal(-1)


func test_overworld_coast_records_every_ocean_facing_edge() -> void:
	# Regression: a coast tile touching ocean on several sides must list ALL of those edges,
	# not just the first one — otherwise its tactical map only carves coast on a single side.
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	const DIR_TO_EDGE := {0: 0, 1: 3, 2: 1, 3: 2}  # N,E,S,W → WorldGrid edge (top,right,bottom,left)
	const OFFSETS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	# Act / Assert — recompute ocean-facing edges directly and compare with the recorded set.
	var multi_edge_tiles := 0
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			var tile = ow.get_tile(coord)
			if tile.biome != OverworldScript.Biome.COAST:
				assert_array(tile.coast_edges).is_empty()
				continue
			var expected: Array = []
			for dir in range(OFFSETS.size()):
				if ow.get_biome(coord + OFFSETS[dir]) == OverworldScript.Biome.OCEAN:
					expected.append(DIR_TO_EDGE[dir])
			assert_array(tile.coast_edges).contains_exactly(expected)
			assert_int(tile.coast_edge).is_equal(expected[0])
			if expected.size() > 1:
				multi_edge_tiles += 1

	# A 128² island has plenty of corners/peninsulas, so multi-edge coast tiles must exist.
	assert_int(multi_edge_tiles).is_greater(0)


# ---- Biome classification (forest / mountain) ----

func test_overworld_has_forest_and_mountain_land_biomes() -> void:
	# A 128² island has enough interior land for the height+moisture pass to produce both
	# mountain ranges and forests.
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act
	var mountains := 0
	var forests := 0
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			match ow.get_biome(Vector2i(x, y)):
				OverworldScript.Biome.MOUNTAIN: mountains += 1
				OverworldScript.Biome.FOREST: forests += 1

	# Assert
	assert_int(mountains).is_greater(0)
	assert_int(forests).is_greater(0)


func test_overworld_forest_and_mountain_are_selectable_land() -> void:
	# Mountain/forest are land → must be valid start tiles and never sit on the ocean ring.
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var n := OverworldScript.OVERWORLD_SIZE

	# Act / Assert
	for x in range(n):
		for y in range(n):
			var coord := Vector2i(x, y)
			var biome := ow.get_biome(coord)
			if biome == OverworldScript.Biome.MOUNTAIN or biome == OverworldScript.Biome.FOREST:
				assert_bool(ow.is_selectable(coord)).is_true()


func test_overworld_coast_never_reclassified_to_forest_or_mountain() -> void:
	# Coast tiles must stay coast (the shore is never turned into forest/mountain), so their
	# coast_edges and tactical coast carving remain intact.
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	const OFFSETS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	# Act / Assert — any land tile orthogonally adjacent to ocean must be COAST, not forest/mountain.
	# Freshwater tiles (a river mouth touches the ocean) are water, not land, so they are skipped.
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			if not ow.is_selectable(coord):
				continue
			var touches_ocean := false
			for off in OFFSETS:
				if ow.get_biome(coord + off) == OverworldScript.Biome.OCEAN:
					touches_ocean = true
			if touches_ocean:
				assert_int(ow.get_biome(coord)).is_equal(OverworldScript.Biome.COAST)


# ---- Rivers & lakes (freshwater tiles) ----

func test_overworld_rivers_exist_as_water_tiles() -> void:
	# Rivers are now real freshwater tiles (Biome.RIVER) carved through the island, and at least
	# one land tile must border one (river_edges) so a tactical map knows to carry a river.
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act
	var river_tiles := 0
	var land_borders_river := 0
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			if ow.get_biome(coord) == OverworldScript.Biome.RIVER:
				river_tiles += 1
			elif ow.is_selectable(coord) and not ow.get_tile(coord).river_edges.is_empty():
				land_borders_river += 1

	# Assert — the island has rivers, and land borders them.
	assert_int(river_tiles).is_greater(0)
	assert_int(land_borders_river).is_greater(0)


func test_overworld_freshwater_tiles_are_not_selectable() -> void:
	# River and lake tiles are water — like the ocean, they can never be a start location.
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act / Assert
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			var biome := ow.get_biome(coord)
			if biome == OverworldScript.Biome.RIVER or biome == OverworldScript.Biome.LAKE:
				assert_bool(ow.is_selectable(coord)).is_false()


func test_overworld_rivers_spring_beside_mountains_and_reach_the_sea() -> void:
	# Contract: rivers spring in the mountains and flow to the coast. So at least one river tile
	# sits next to a mountain (its spring) and at least one next to the ocean (its mouth).
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	const OFFSETS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	# Act
	var spring_beside_mountain := false
	var mouth_at_sea := false
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			if ow.get_biome(coord) != OverworldScript.Biome.RIVER:
				continue
			for off in OFFSETS:
				match ow.get_biome(coord + off):
					OverworldScript.Biome.MOUNTAIN: spring_beside_mountain = true
					OverworldScript.Biome.OCEAN: mouth_at_sea = true

	# Assert
	assert_bool(spring_beside_mountain).is_true()
	assert_bool(mouth_at_sea).is_true()


func test_overworld_lakes_exist_as_interior_freshwater() -> void:
	# Lakes are freshwater blobs grown in interior basins; land tiles next to one record lake_edges.
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act
	var lake_tiles := 0
	var land_borders_lake := 0
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			if ow.get_biome(coord) == OverworldScript.Biome.LAKE:
				lake_tiles += 1
			elif ow.is_selectable(coord) and not ow.get_tile(coord).lake_edges.is_empty():
				land_borders_lake += 1

	# Assert
	assert_int(lake_tiles).is_greater(0)
	assert_int(land_borders_lake).is_greater(0)


func test_overworld_river_pools_become_lakes() -> void:
	# A 2×2 block of river tiles is a pool that reads as a lake, so it is promoted to LAKE, while a
	# 1-tile-wide river line (never part of a 2×2) stays RIVER.
	# Arrange — hand-build a tiny tile set: a 2×2 river pool plus a separate 1-wide river line.
	var ow := _make_overworld()
	var pool := [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]
	var line := [Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2)]
	for c in pool:
		ow._tiles[c] = OverworldScript.OverworldTile.new(c, OverworldScript.Biome.RIVER, 0)
	for c in line:
		ow._tiles[c] = OverworldScript.OverworldTile.new(c, OverworldScript.Biome.RIVER, 0)

	# Act
	ow._reclassify_river_pools_as_lakes()

	# Assert
	for c in pool:
		assert_int(ow.get_biome(c)).is_equal(OverworldScript.Biome.LAKE)
	for c in line:
		assert_int(ow.get_biome(c)).is_equal(OverworldScript.Biome.RIVER)


func test_overworld_freshwater_deterministic_for_same_seed() -> void:
	# Same seed → identical freshwater layout (biomes plus the recorded river / lake edges).
	# Arrange
	var ow_a := _make_overworld()
	ow_a.generate(SEED_A)
	var ow_b := _make_overworld()
	ow_b.generate(SEED_A)

	# Act / Assert
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			var a = ow_a.get_tile(coord)
			var b = ow_b.get_tile(coord)
			assert_int(b.biome).is_equal(a.biome)
			assert_array(b.river_edges).is_equal(a.river_edges)
			assert_array(b.lake_edges).is_equal(a.lake_edges)


# ---- Start selection ----

func test_overworld_select_start_ocean_is_rejected() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act — corner is always ocean.
	var ok: bool = ow.select_start(Vector2i(0, 0))

	# Assert
	assert_bool(ok).is_false()
	assert_vector(ow.get_start_coord()).is_equal(Vector2i(-1, -1))


func test_overworld_select_start_forces_starting_fertility() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var start := _first_start_tile(ow)

	# Act
	var ok: bool = ow.select_start(start)

	# Assert
	assert_bool(ok).is_true()
	assert_vector(ow.get_start_coord()).is_equal(start)
	var tile = ow.get_tile(start)
	assert_bool(tile.is_start).is_true()
	assert_array(tile.fertilities).is_equal(WorldGridScript.STARTING_FERTILITY)


# ---- Persistence ----

func test_overworld_serialize_round_trip_restores_seed_and_start() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var start := _first_start_tile(ow)
	ow.select_start(start)
	var data: Dictionary = ow.serialize()

	# Act
	var restored := _make_overworld()
	restored.deserialize(data)

	# Assert — same start, and the grid regenerates identically.
	assert_vector(restored.get_start_coord()).is_equal(start)
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			assert_int(restored.get_tile(coord).tile_seed).is_equal(ow.get_tile(coord).tile_seed)


# ---- NPC cities ----

func test_overworld_places_cities_on_land() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act
	var cities: Array = ow.get_cities()

	# Assert — up to CITY_COUNT cities, each on a land tile and flagged as a city.
	assert_int(cities.size()).is_greater(0)
	assert_int(cities.size()).is_less_equal(OverworldScript.CITY_COUNT)
	for city: Vector2i in cities:
		assert_bool(ow.is_selectable(city)).is_true()  # cities sit on land
		assert_bool(ow.is_city(city)).is_true()


func test_overworld_cities_and_radius_are_not_start_allowed() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var radius: int = OverworldScript._CITY_EXCLUSION_RADIUS

	# Act / Assert — a city and every land tile within its radius is blocked as a start.
	for city: Vector2i in ow.get_cities():
		assert_bool(ow.is_start_allowed(city)).is_false()
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var t := city + Vector2i(dx, dy)
				if ow.is_selectable(t) and Vector2(Vector2i(dx, dy)).length() <= float(radius):
					assert_bool(ow.is_city_blocked(t)).is_true()
					assert_bool(ow.is_start_allowed(t)).is_false()


func test_overworld_cities_are_spaced_apart() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var spacing: int = OverworldScript._CITY_MIN_SPACING
	var cities: Array = ow.get_cities()

	# Act / Assert — no two cities sit closer than the minimum spacing.
	for i in range(cities.size()):
		for j in range(i + 1, cities.size()):
			var d: float = Vector2(cities[i] - cities[j]).length()
			assert_float(d).is_greater_equal(float(spacing))


func test_overworld_center_start_survives_city_placement() -> void:
	# Arrange — the guaranteed-land centre must never be blocked, so a fallback start always exists.
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var center := Vector2i(OverworldScript.OVERWORLD_SIZE / 2, OverworldScript.OVERWORLD_SIZE / 2)

	# Act / Assert
	assert_bool(ow.is_city_blocked(center)).is_false()
	assert_bool(ow.is_start_allowed(center)).is_true()


func test_overworld_cities_match_their_faction_theme() -> void:
	# Arrange — each city is placed on land matching its faction's theme biome (Ravenmoor sits
	# beside a lake rather than on water).
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act / Assert
	for city: Vector2i in ow.get_cities():
		var fid: String = ow.get_faction_id(ow.get_city_faction(city))
		var tile = ow.get_tile(city)
		match fid:
			"ironhold":
				assert_int(tile.biome).is_equal(OverworldScript.Biome.MOUNTAIN)
			"verdant":
				assert_int(tile.biome).is_equal(OverworldScript.Biome.FOREST)
			"goldfield":
				assert_int(tile.biome).is_equal(OverworldScript.Biome.INLAND)
			"tidewatch":
				assert_int(tile.biome).is_equal(OverworldScript.Biome.COAST)
			"ravenmoor":
				assert_bool(tile.lake_edges.is_empty()).is_false()
			_:
				assert_bool(false).override_failure_message(
					"unexpected faction id: %s" % fid).is_true()


func test_overworld_each_city_has_a_distinct_valid_faction() -> void:
	# Arrange — CITY_COUNT (4) ≤ FACTIONS (5), so every city should get a distinct, valid faction.
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var seen: Dictionary = {}

	# Act / Assert
	for city: Vector2i in ow.get_cities():
		var idx: int = ow.get_city_faction(city)
		assert_int(idx).is_greater_equal(0)
		assert_int(idx).is_less(OverworldScript.FACTIONS.size())
		assert_str(ow.get_faction_name(idx)).is_not_empty()
		assert_bool(seen.has(idx)).is_false()  # no two cities share a faction
		seen[idx] = true


func test_overworld_non_city_tile_has_no_faction() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var center := Vector2i(OverworldScript.OVERWORLD_SIZE / 2, OverworldScript.OVERWORLD_SIZE / 2)

	# Act / Assert — the protected centre is never a city, so it has no faction.
	assert_int(ow.get_city_faction(center)).is_equal(-1)


func test_overworld_city_factions_deterministic_for_same_seed() -> void:
	# Arrange
	var ow_a := _make_overworld()
	ow_a.generate(SEED_A)
	var ow_b := _make_overworld()
	ow_b.generate(SEED_A)

	# Act / Assert — same seed assigns the same faction to each city.
	for city: Vector2i in ow_a.get_cities():
		assert_int(ow_b.get_city_faction(city)).is_equal(ow_a.get_city_faction(city))


func test_overworld_cities_deterministic_for_same_seed() -> void:
	# Arrange
	var ow_a := _make_overworld()
	ow_a.generate(SEED_A)
	var ow_b := _make_overworld()
	ow_b.generate(SEED_A)

	# Act / Assert — same seed yields the same cities in the same order.
	assert_array(ow_b.get_cities()).is_equal(ow_a.get_cities())
