## gdUnit4 test suite for Story 002: Procedural Generation Pipeline.
##
## Covers AC-2 (determinism), AC-4 (minimum tile counts), AC-22 (force-fix),
## and AC-23 (cluster cleanup removes small components).

extends GdUnitTestSuite

const GridMapScript := preload("res://src/systems/world_grid.gd")


func _make_grid() -> Node:
	var grid := GridMapScript.new()
	add_child(grid)
	auto_free(grid)
	return grid


func _count_type(grid: Node, tile_type: int) -> int:
	var count := 0
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if grid._terrain[x][y] == tile_type:
				count += 1
	return count


# ---- AC-2: Deterministic generation ----

func test_generate_deterministic_seed_42_terrain_identical() -> void:
	# Arrange
	var grid_a := _make_grid()
	grid_a.generate(42)
	var terrain_copy: Array = []
	for x in range(GridMapScript.GRID_SIZE):
		var row: Array = []
		for y in range(GridMapScript.GRID_SIZE):
			row.append(grid_a._terrain[x][y])
		terrain_copy.append(row)

	# Act
	var grid_b := _make_grid()
	grid_b.generate(42)

	# Assert
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			assert_int(grid_b._terrain[x][y]).is_equal(terrain_copy[x][y])


func test_generate_deterministic_seed_42_resource_ids_identical() -> void:
	# Arrange
	var grid_a := _make_grid()
	grid_a.generate(42)

	# Act
	var grid_b := _make_grid()
	grid_b.generate(42)

	# Assert
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			var res_a: Variant = grid_a._resources[x][y]
			var res_b: Variant = grid_b._resources[x][y]
			if res_a == null:
				assert_object(res_b).is_null()
			else:
				assert_object(res_b).is_not_null()
				assert_str(str(res_b.resource_id)).is_equal(str(res_a.resource_id))
				assert_bool(res_b.clearable).is_equal(res_a.clearable)


func test_generate_deterministic_seed_0() -> void:
	# Arrange
	var grid_a := _make_grid()
	grid_a.generate(0)

	# Act
	var grid_b := _make_grid()
	grid_b.generate(0)

	# Assert
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			assert_int(grid_b._terrain[x][y]).is_equal(grid_a._terrain[x][y])


func test_generate_deterministic_seed_large() -> void:
	# Arrange
	var grid_a := _make_grid()
	grid_a.generate(999999)

	# Act
	var grid_b := _make_grid()
	grid_b.generate(999999)

	# Assert
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			assert_int(grid_b._terrain[x][y]).is_equal(grid_a._terrain[x][y])


# ---- AC-4: Minimum resource counts ----

func test_generate_minimum_tree_count_met_seed_42() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert
	assert_int(_count_type(grid, GridMapScript.TileType.TREE)).is_greater_equal(8)


func test_generate_minimum_stone_count_met_seed_42() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert
	assert_int(_count_type(grid, GridMapScript.TileType.STONE)).is_greater_equal(4)


func test_generate_minimum_berry_count_met_seed_42() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert
	assert_int(_count_type(grid, GridMapScript.TileType.BERRY)).is_greater_equal(6)


func test_generate_minimum_grass_count_met_seed_42() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert
	assert_int(_count_type(grid, GridMapScript.TileType.GRASS)).is_greater_equal(6)


func test_generate_multiple_seeds_all_meet_minimums() -> void:
	# Arrange
	var seeds := [1, 7, 13, 42, 100, 255, 1000, 5432, 12345, 999999]

	for seed_val in seeds:
		# Act
		var grid := _make_grid()
		grid.generate(seed_val)

		# Assert
		assert_int(_count_type(grid, GridMapScript.TileType.TREE)).is_greater_equal(8)
		assert_int(_count_type(grid, GridMapScript.TileType.STONE)).is_greater_equal(4)
		assert_int(_count_type(grid, GridMapScript.TileType.BERRY)).is_greater_equal(6)
		assert_int(_count_type(grid, GridMapScript.TileType.GRASS)).is_greater_equal(6)


func test_generate_sets_generation_done_flag() -> void:
	# Arrange
	var grid := _make_grid()
	assert_bool(grid._generation_done).is_false()

	# Act
	grid.generate(42)

	# Assert
	assert_bool(grid._generation_done).is_true()


# ---- AC-22: Force-fix when all seed attempts fail ----

func test_force_fix_meets_all_minimums_from_all_empty_terrain() -> void:
	# Arrange: simulate all-failed noise — set _terrain to all EMPTY
	var grid := _make_grid()
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			grid._terrain[x][y] = GridMapScript.TileType.EMPTY

	# Act
	grid._force_fix_minimums()

	# Assert
	assert_int(_count_type(grid, GridMapScript.TileType.TREE)).is_greater_equal(8)
	assert_int(_count_type(grid, GridMapScript.TileType.STONE)).is_greater_equal(4)
	assert_int(_count_type(grid, GridMapScript.TileType.BERRY)).is_greater_equal(6)
	assert_int(_count_type(grid, GridMapScript.TileType.GRASS)).is_greater_equal(6)


func test_force_fix_prefers_tiles_adjacent_to_existing_cluster() -> void:
	# Arrange: 3 TREE tiles as anchor cluster; all others EMPTY
	var grid := _make_grid()
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			grid._terrain[x][y] = GridMapScript.TileType.EMPTY
	grid._terrain[10][10] = GridMapScript.TileType.TREE
	grid._terrain[10][11] = GridMapScript.TileType.TREE
	grid._terrain[10][12] = GridMapScript.TileType.TREE

	# Act
	grid._force_fix_minimums()

	# Assert: TREE minimum (8) met; tiles were added adjacent to the cluster
	assert_int(_count_type(grid, GridMapScript.TileType.TREE)).is_greater_equal(8)


# ---- AC-23: Cluster cleanup removes small components ----

func test_cleanup_clusters_two_tile_component_converted_to_empty() -> void:
	# Arrange: (3,3) and (3,4) are a 2-tile TREE cluster; (15,15)-(15,19) is a 5-tile anchor
	var grid := _make_grid()
	var terrain: Array = []
	for x in range(GridMapScript.GRID_SIZE):
		var row: Array[int] = []
		for y in range(GridMapScript.GRID_SIZE):
			row.append(GridMapScript.TileType.EMPTY)
		terrain.append(row)
	terrain[3][3] = GridMapScript.TileType.TREE
	terrain[3][4] = GridMapScript.TileType.TREE
	for i in range(5):
		terrain[15][15 + i] = GridMapScript.TileType.TREE

	# Act
	var result: Array = grid._cleanup_clusters(terrain)

	# Assert: 2-tile cluster removed
	assert_int(result[3][3]).is_equal(GridMapScript.TileType.EMPTY)
	assert_int(result[3][4]).is_equal(GridMapScript.TileType.EMPTY)
	# Anchor cluster untouched
	for i in range(5):
		assert_int(result[15][15 + i]).is_equal(GridMapScript.TileType.TREE)
	# Adjacent non-TREE tiles unmodified
	assert_int(result[3][2]).is_equal(GridMapScript.TileType.EMPTY)
	assert_int(result[3][5]).is_equal(GridMapScript.TileType.EMPTY)
	assert_int(result[2][3]).is_equal(GridMapScript.TileType.EMPTY)
	assert_int(result[4][4]).is_equal(GridMapScript.TileType.EMPTY)


func test_cleanup_clusters_three_tile_component_kept() -> void:
	# Arrange: exactly 3 STONE tiles at (5,5)-(5,7)
	var grid := _make_grid()
	var terrain: Array = []
	for x in range(GridMapScript.GRID_SIZE):
		var row: Array[int] = []
		for y in range(GridMapScript.GRID_SIZE):
			row.append(GridMapScript.TileType.EMPTY)
		terrain.append(row)
	terrain[5][5] = GridMapScript.TileType.STONE
	terrain[5][6] = GridMapScript.TileType.STONE
	terrain[5][7] = GridMapScript.TileType.STONE

	# Act
	var result: Array = grid._cleanup_clusters(terrain)

	# Assert: 3-tile component is kept
	assert_int(result[5][5]).is_equal(GridMapScript.TileType.STONE)
	assert_int(result[5][6]).is_equal(GridMapScript.TileType.STONE)
	assert_int(result[5][7]).is_equal(GridMapScript.TileType.STONE)


func test_cleanup_clusters_isolated_single_tile_converted_to_empty() -> void:
	# Arrange: single BERRY tile isolated at (10,10)
	var grid := _make_grid()
	var terrain: Array = []
	for x in range(GridMapScript.GRID_SIZE):
		var row: Array[int] = []
		for y in range(GridMapScript.GRID_SIZE):
			row.append(GridMapScript.TileType.EMPTY)
		terrain.append(row)
	terrain[10][10] = GridMapScript.TileType.BERRY

	# Act
	var result: Array = grid._cleanup_clusters(terrain)

	# Assert
	assert_int(result[10][10]).is_equal(GridMapScript.TileType.EMPTY)


# ---- Resource layer population ----

func test_generate_tree_tile_has_wood_resource_and_is_clearable() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert: first TREE tile has "wood" resource, clearable = true
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if grid._terrain[x][y] == GridMapScript.TileType.TREE:
				var res: Variant = grid._resources[x][y]
				assert_object(res).is_not_null()
				assert_str(str(res.resource_id)).is_equal("wood")
				assert_bool(res.clearable).is_true()
				return


func test_generate_stone_tile_has_stone_resource_and_is_not_clearable() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert: first STONE tile has clearable = false
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if grid._terrain[x][y] == GridMapScript.TileType.STONE:
				var res: Variant = grid._resources[x][y]
				assert_object(res).is_not_null()
				assert_bool(res.clearable).is_false()
				return


func test_generate_empty_and_impassable_tiles_have_null_resource() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			var t: int = grid._terrain[x][y]
			if t == GridMapScript.TileType.EMPTY or t == GridMapScript.TileType.IMPASSABLE:
				assert_object(grid._resources[x][y]).is_null()


func test_generate_different_seeds_produce_different_maps() -> void:
	# Arrange
	var grid_a := _make_grid()
	grid_a.generate(42)

	# Act
	var grid_b := _make_grid()
	grid_b.generate(1234)

	# Assert: at least one tile differs
	var differences := 0
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if grid_a._terrain[x][y] != grid_b._terrain[x][y]:
				differences += 1
	assert_int(differences).is_greater(0)


func test_generate_seed_plus_one_moisture_produces_different_map() -> void:
	# seed+1 is used for moisture — verify it contributes to map variation
	# Arrange
	var grid_a := _make_grid()
	grid_a.generate(42)

	# Act
	var grid_b := _make_grid()
	grid_b.generate(43)

	# Assert: at least one tile differs (different moisture layer shifts BERRY/GRASS split)
	var differences := 0
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if grid_a._terrain[x][y] != grid_b._terrain[x][y]:
				differences += 1
	assert_int(differences).is_greater(0)


func test_generate_berry_tile_has_berry_resource_and_is_clearable() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert: first BERRY tile has "berry" resource, clearable = true
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if grid._terrain[x][y] == GridMapScript.TileType.BERRY:
				var res: Variant = grid._resources[x][y]
				assert_object(res).is_not_null()
				assert_str(str(res.resource_id)).is_equal("berry")
				assert_bool(res.clearable).is_true()
				return


func test_generate_grass_tile_has_fiber_resource_and_is_clearable() -> void:
	# Arrange / Act
	var grid := _make_grid()
	grid.generate(42)

	# Assert: first GRASS tile has "fiber" resource, clearable = true
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if grid._terrain[x][y] == GridMapScript.TileType.GRASS:
				var res: Variant = grid._resources[x][y]
				assert_object(res).is_not_null()
				assert_str(str(res.resource_id)).is_equal("fiber")
				assert_bool(res.clearable).is_true()
				return


# ---- Terrain profile (overworld biome bias) ----

func _count_in_terrain(terrain: Array, tile_type: int) -> int:
	var count := 0
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if terrain[x][y] == tile_type:
				count += 1
	return count


func _empty_terrain() -> Array:
	var terrain: Array = []
	for _x in range(GridMapScript.GRID_SIZE):
		var row: Array[int] = []
		for _y in range(GridMapScript.GRID_SIZE):
			row.append(GridMapScript.TileType.EMPTY)
		terrain.append(row)
	return terrain


func test_mountain_profile_has_more_rock_than_plains() -> void:
	# Same seed, MOUNTAIN profile must yield more STONE + IMPASSABLE (rock/peaks) than PLAINS.
	# Arrange / Act — sample the raw noise (pre-smoothing) so we test the band logic directly.
	var grid := _make_grid()
	var plains: Array = grid._sample_noise(42, GridMapScript.TerrainProfile.PLAINS)
	var mountain: Array = grid._sample_noise(42, GridMapScript.TerrainProfile.MOUNTAIN)

	# Assert
	var plains_rock := _count_in_terrain(plains, GridMapScript.TileType.STONE) \
		+ _count_in_terrain(plains, GridMapScript.TileType.IMPASSABLE)
	var mountain_rock := _count_in_terrain(mountain, GridMapScript.TileType.STONE) \
		+ _count_in_terrain(mountain, GridMapScript.TileType.IMPASSABLE)
	assert_int(mountain_rock).is_greater(plains_rock)


func test_forest_profile_has_more_trees_than_plains() -> void:
	# Same seed, FOREST profile must yield more TREE tiles than PLAINS.
	# Arrange / Act
	var grid := _make_grid()
	var plains: Array = grid._sample_noise(42, GridMapScript.TerrainProfile.PLAINS)
	var forest: Array = grid._sample_noise(42, GridMapScript.TerrainProfile.FOREST)

	# Assert
	var plains_trees := _count_in_terrain(plains, GridMapScript.TileType.TREE)
	var forest_trees := _count_in_terrain(forest, GridMapScript.TileType.TREE)
	assert_int(forest_trees).is_greater(plains_trees)


func test_plains_profile_matches_original_thresholds() -> void:
	# Regression: the PLAINS bands must reproduce the original hardcoded thresholds, so existing
	# (non-overworld) maps are byte-identical. The default profile is PLAINS.
	# Arrange / Act
	var grid := _make_grid()
	var explicit_plains: Array = grid._sample_noise(42, GridMapScript.TerrainProfile.PLAINS)
	var default_profile: Array = grid._sample_noise(42)

	# Assert
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			assert_int(default_profile[x][y]).is_equal(explicit_plains[x][y])


# ---- Conditional coast ----

func test_carve_coast_empty_edges_adds_no_coast() -> void:
	# Regression: an inland tile (empty coast_edges) must get NO coast on its tactical map — the
	# ocean only borders maps that border it on the overworld. Previously a random roll could
	# carve a coast on inland maps.
	# Arrange
	var grid := _make_grid()
	var terrain := _empty_terrain()

	# Act
	grid._carve_coast(terrain, 42, [])

	# Assert
	assert_int(_count_in_terrain(terrain, GridMapScript.TileType.COAST)).is_equal(0)


func test_carve_coast_with_edge_carves_top_band() -> void:
	# A forced top edge (0) carves a COAST band along the top row.
	# Arrange
	var grid := _make_grid()
	var terrain := _empty_terrain()

	# Act
	grid._carve_coast(terrain, 42, [0])

	# Assert — coast exists and the top row is coast.
	assert_int(_count_in_terrain(terrain, GridMapScript.TileType.COAST)).is_greater(0)
	var top_has_coast := false
	for x in range(GridMapScript.GRID_SIZE):
		if terrain[x][0] == GridMapScript.TileType.COAST:
			top_has_coast = true
	assert_bool(top_has_coast).is_true()


# ---- Conditional river ----

func test_carve_river_empty_edges_adds_no_water() -> void:
	# A tile whose overworld counterpart has no river must get no tactical river.
	# Arrange
	var grid := _make_grid()
	var terrain := _empty_terrain()

	# Act
	grid._carve_river(terrain, 42, [])

	# Assert
	assert_int(_count_in_terrain(terrain, GridMapScript.TileType.WATER)).is_equal(0)


func test_carve_river_with_edges_carves_water_touching_both_edges() -> void:
	# river_edges [0, 1] (top, bottom) must carve a river that reaches both the top and bottom rows.
	# Arrange
	var grid := _make_grid()
	var terrain := _empty_terrain()
	var last := GridMapScript.GRID_SIZE - 1

	# Act
	grid._carve_river(terrain, 42, [0, 1])

	# Assert — water exists and a tile on the top row and the bottom row is water.
	assert_int(_count_in_terrain(terrain, GridMapScript.TileType.WATER)).is_greater(0)
	var top_has_water := false
	var bottom_has_water := false
	for x in range(GridMapScript.GRID_SIZE):
		if terrain[x][0] == GridMapScript.TileType.WATER:
			top_has_water = true
		if terrain[x][last] == GridMapScript.TileType.WATER:
			bottom_has_water = true
	assert_bool(top_has_water).is_true()
	assert_bool(bottom_has_water).is_true()


# ---- Conditional freshwater (lakeshore band) ----

func test_carve_freshwater_empty_edges_adds_no_water() -> void:
	# A tile not bordering an overworld lake gets no freshwater band.
	# Arrange
	var grid := _make_grid()
	var terrain := _empty_terrain()

	# Act
	grid._carve_freshwater(terrain, 42, [])

	# Assert
	assert_int(_count_in_terrain(terrain, GridMapScript.TileType.WATER)).is_equal(0)


func test_carve_freshwater_with_edge_carves_fresh_water_band_not_coast() -> void:
	# A lake edge carves a band of WATER (freshwater) — NOT COAST (saltwater) — along that edge.
	# "A lake is like a coast, only freshwater."
	# Arrange
	var grid := _make_grid()
	var terrain := _empty_terrain()

	# Act
	grid._carve_freshwater(terrain, 42, [0])

	# Assert — freshwater WATER on the top row, and no salt COAST anywhere.
	assert_int(_count_in_terrain(terrain, GridMapScript.TileType.WATER)).is_greater(0)
	assert_int(_count_in_terrain(terrain, GridMapScript.TileType.COAST)).is_equal(0)
	var top_has_water := false
	for x in range(GridMapScript.GRID_SIZE):
		if terrain[x][0] == GridMapScript.TileType.WATER:
			top_has_water = true
	assert_bool(top_has_water).is_true()


func test_force_fix_adds_tiles_adjacent_to_existing_cluster() -> void:
	# Arrange: 3 TREE tiles as anchor cluster at (10,10)-(10,12); all others EMPTY
	var grid := _make_grid()
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			grid._terrain[x][y] = GridMapScript.TileType.EMPTY
	grid._terrain[10][10] = GridMapScript.TileType.TREE
	grid._terrain[10][11] = GridMapScript.TileType.TREE
	grid._terrain[10][12] = GridMapScript.TileType.TREE

	# Act
	grid._force_fix_minimums()

	# Assert: at least one new TREE tile is adjacent (Manhattan dist 1) to the anchor cluster
	var cluster: Array[Vector2i] = [Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12)]
	var found_adjacent := false
	for x in range(GridMapScript.GRID_SIZE):
		for y in range(GridMapScript.GRID_SIZE):
			if cluster.has(Vector2i(x, y)):
				continue
			if grid._terrain[x][y] != GridMapScript.TileType.TREE:
				continue
			for anchor: Vector2i in cluster:
				var dist: int = abs(x - anchor.x) + abs(y - anchor.y)
				if dist == 1:
					found_adjacent = true
	assert_bool(found_adjacent).is_true()
