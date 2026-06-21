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


func test_overworld_land_is_single_connected_component() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var land := _land_coords(ow)
	assert_int(land.size()).is_greater(0)

	# Act — 4-connected flood from the first land tile.
	var offsets := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var land_set: Dictionary = {}
	for c in land:
		land_set[c] = true
	var visited: Dictionary = {}
	var stack: Array = [land[0]]
	visited[land[0]] = true
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		for off in offsets:
			var nb: Vector2i = t + off
			if land_set.has(nb) and not visited.has(nb):
				visited[nb] = true
				stack.append(nb)

	# Assert — the flood reached every land tile (one island).
	assert_int(visited.size()).is_equal(land.size())


# ---- Fertilities ----

func test_overworld_land_tiles_have_fertilities_ocean_has_none() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)

	# Act / Assert
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var tile = ow.get_tile(Vector2i(x, y))
			if tile.biome == OverworldScript.Biome.OCEAN:
				assert_int(tile.fertilities.size()).is_equal(0)
			else:
				var expected = mini(OverworldScript.FERTILITIES_PER_TILE, WorldGridScript.FERTILITY_POOL.size())
				assert_int(tile.fertilities.size()).is_equal(expected)


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
	var land := _land_coords(ow)

	# Act
	var ok: bool = ow.select_start(land[0])

	# Assert
	assert_bool(ok).is_true()
	assert_vector(ow.get_start_coord()).is_equal(land[0])
	var tile = ow.get_tile(land[0])
	assert_bool(tile.is_start).is_true()
	assert_array(tile.fertilities).is_equal(WorldGridScript.STARTING_FERTILITY)


# ---- Persistence ----

func test_overworld_serialize_round_trip_restores_seed_and_start() -> void:
	# Arrange
	var ow := _make_overworld()
	ow.generate(SEED_A)
	var land := _land_coords(ow)
	ow.select_start(land[0])
	var data: Dictionary = ow.serialize()

	# Act
	var restored := _make_overworld()
	restored.deserialize(data)

	# Assert — same start, and the grid regenerates identically.
	assert_vector(restored.get_start_coord()).is_equal(land[0])
	for x in range(OverworldScript.OVERWORLD_SIZE):
		for y in range(OverworldScript.OVERWORLD_SIZE):
			var coord := Vector2i(x, y)
			assert_int(restored.get_tile(coord).tile_seed).is_equal(ow.get_tile(coord).tile_seed)
