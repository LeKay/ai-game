## gdUnit4 test suite for the ore/gem deposit system (clay generalized to N deposits).
##
## Covers: weighted fertility roll (determinism + rarity of silver/gold/gemstones),
## reveal_hidden_deposit terrain mapping, _populate_hidden_deposits counts (common 6 / rare 1,
## one deposit per tile), and serialize/deserialize round-trip of the new fertilities + deposits.

extends GdUnitTestSuite

const GridMapScript := preload("res://src/systems/world_grid.gd")


func _make_grid() -> Node:
	var grid := GridMapScript.new()
	add_child(grid)
	auto_free(grid)
	return grid


# ---- Weighted fertility roll: determinism ----

func test_roll_fertility_same_seed_is_identical() -> void:
	# Arrange / Act
	var a: Array = GridMapScript.roll_fertility(12345, 3)
	var b: Array = GridMapScript.roll_fertility(12345, 3)

	# Assert
	assert_array(a).is_equal(b)


func test_roll_fertility_returns_distinct_entries() -> void:
	# Act
	var roll: Array = GridMapScript.roll_fertility(98765, 3)

	# Assert — sampling without replacement: no duplicates, exactly `count` entries.
	assert_int(roll.size()).is_equal(3)
	var seen := {}
	for id in roll:
		assert_bool(seen.has(id)).is_false()
		seen[id] = true


# ---- Weighted fertility roll: rarity ----

func test_roll_fertility_precious_far_rarer_than_common() -> void:
	# Arrange — count appearances across a fixed seed range (deterministic).
	var gold := 0
	var clay := 0
	for s in range(3000):
		var roll: Array = GridMapScript.roll_fertility(s, 3)
		if roll.has(&"gold"):
			gold += 1
		if roll.has(&"clay"):
			clay += 1

	# Assert — gold (weight 1) appears, but far less than clay (weight 12).
	assert_int(gold).is_greater(0)
	assert_int(gold * 3).is_less(clay)


# ---- Biome-aware fertility roll (ADR-0015 addendum) ----

func test_roll_fertility_coast_only_resources_never_roll_off_coast() -> void:
	# Arrange — pearl and sand are hard-restricted to coast biomes.
	var off_coast_hits := 0
	for s in range(2000):
		var mountain: Array = GridMapScript.roll_fertility(s, 3, GridMapScript.BIOME_MOUNTAIN)
		var plains: Array = GridMapScript.roll_fertility(s, 3, GridMapScript.BIOME_PLAINS)
		var forest: Array = GridMapScript.roll_fertility(s, 3, GridMapScript.BIOME_FOREST)
		for roll: Array in [mountain, plains, forest]:
			if roll.has(&"pearl") or roll.has(&"sand"):
				off_coast_hits += 1

	# Assert — restricted resources are impossible outside their biome (weight forced to 0).
	assert_int(off_coast_hits).is_equal(0)


func test_roll_fertility_coast_resources_can_roll_on_coast() -> void:
	# Arrange — over a seed range, coast-only resources must appear on a coast tile.
	var pearl := 0
	var sand := 0
	for s in range(2000):
		var roll: Array = GridMapScript.roll_fertility(s, 3, GridMapScript.BIOME_COAST)
		if roll.has(&"pearl"):
			pearl += 1
		if roll.has(&"sand"):
			sand += 1

	# Assert
	assert_int(pearl).is_greater(0)
	assert_int(sand).is_greater(0)


func test_roll_fertility_amber_only_on_coast_or_forest() -> void:
	# Arrange — amber is restricted to coast and forest biomes.
	var bad_hits := 0
	for s in range(2000):
		var mountain: Array = GridMapScript.roll_fertility(s, 3, GridMapScript.BIOME_MOUNTAIN)
		var plains: Array = GridMapScript.roll_fertility(s, 3, GridMapScript.BIOME_PLAINS)
		if mountain.has(&"amber") or plains.has(&"amber"):
			bad_hits += 1

	# Assert
	assert_int(bad_hits).is_equal(0)


# ---- reveal_hidden_deposit: terrain mapping ----

func test_reveal_hidden_deposit_sets_matching_tile_type() -> void:
	var cases := {
		&"clay": GridMapScript.TileType.CLAY,
		&"iron": GridMapScript.TileType.IRON,
		&"copper": GridMapScript.TileType.COPPER,
		&"tin": GridMapScript.TileType.TIN,
		&"silver": GridMapScript.TileType.SILVER,
		&"gold": GridMapScript.TileType.GOLD,
		&"gemstones": GridMapScript.TileType.GEMSTONE,
		&"amber": GridMapScript.TileType.AMBER,
	}
	for resource_id: StringName in cases:
		# Arrange — an EMPTY tile carrying a hidden deposit of resource_id.
		var grid := _make_grid()
		var tile := Vector2i(3, 3)
		grid._terrain[tile.x][tile.y] = GridMapScript.TileType.EMPTY
		grid._hidden_resources[tile] = resource_id

		# Act
		var revealed: StringName = grid.reveal_hidden_deposit(tile)

		# Assert
		assert_str(String(revealed)).is_equal(String(resource_id))
		assert_int(grid._terrain[tile.x][tile.y]).is_equal(cases[resource_id])
		assert_bool(grid._hidden_resources.has(tile)).is_false()


func test_reveal_hidden_deposit_blocked_when_tile_not_empty() -> void:
	# Arrange — a hidden deposit under a non-EMPTY (TREE) tile cannot be exposed yet.
	var grid := _make_grid()
	var tile := Vector2i(4, 4)
	grid._terrain[tile.x][tile.y] = GridMapScript.TileType.TREE
	grid._hidden_resources[tile] = &"iron"

	# Act
	var revealed: StringName = grid.reveal_hidden_deposit(tile)

	# Assert — refused, deposit stays hidden, terrain unchanged.
	assert_str(String(revealed)).is_equal("")
	assert_bool(grid._hidden_resources.has(tile)).is_true()
	assert_int(grid._terrain[tile.x][tile.y]).is_equal(GridMapScript.TileType.TREE)


# ---- _populate_hidden_deposits: counts & one-per-tile ----

func test_populate_hidden_deposits_counts_match_rarity() -> void:
	# Arrange / Act — a map fertile for one common (iron) and one rare (silver) deposit.
	var grid := _make_grid()
	grid.generate(7, [&"iron", &"silver"])

	# Assert — common deposit count = 6, rare = 1; no tile holds two deposits.
	var iron := 0
	var silver := 0
	for tile: Vector2i in grid._hidden_resources:
		match grid._hidden_resources[tile]:
			&"iron": iron += 1
			&"silver": silver += 1
	assert_int(iron).is_equal(GridMapScript.DEPOSIT_COUNTS[&"iron"])
	assert_int(silver).is_equal(GridMapScript.DEPOSIT_COUNTS[&"silver"])
	# Dictionary keyed by tile ⇒ inherently one deposit per tile; total confirms no loss.
	assert_int(grid._hidden_resources.size()).is_equal(iron + silver)


# ---- serialize / deserialize round-trip ----

func test_serialize_round_trips_new_fertilities_and_deposits() -> void:
	# Arrange — generate a gold-fertile map and serialize it.
	var grid := _make_grid()
	grid.generate(99, [&"gold", &"copper"])
	var data: Dictionary = grid.serialize()

	# Act — restore into a fresh grid.
	var restored := _make_grid()
	restored.deserialize(data)

	# Assert — fertility set and hidden deposits survive the round-trip.
	assert_bool(restored.has_fertility(&"gold")).is_true()
	assert_bool(restored.has_fertility(&"copper")).is_true()
	assert_int(restored._hidden_resources.size()).is_equal(grid._hidden_resources.size())
	for tile: Vector2i in grid._hidden_resources:
		assert_str(String(restored._hidden_resources.get(tile, &""))) \
			.is_equal(String(grid._hidden_resources[tile]))
