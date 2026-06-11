class_name BuildingEfficiencyTest
extends GdUnitTestSuite
## Unit tests for Efficiency System Story 002: Building Efficiency and Worker Contribution.
## Covers AC-1 through AC-7 from the story acceptance criteria.

# ---- Helpers ------------------------------------------------------------------

## Minimal NPCSystem stub — exposes get_npc_instance() for BuildingRegistry injection.
class _MockNPCSystem extends Node:
	var _npcs: Dictionary = {}

	func get_npc_instance(npc_id: StringName) -> Object:
		return _npcs.get(npc_id)

	func add_npc(npc_id: StringName, efficiency_value: float) -> NPCSystem.NPCInstance:
		var npc := NPCSystem.NPCInstance.new()
		npc.npc_id = npc_id
		npc.efficiency = efficiency_value
		_npcs[npc_id] = npc
		return npc


## Minimal BuildingRegistry mock for NPCSystem._building_system in propagation tests.
class _MockBuildingSystem extends Node:
	signal building_demolished(building_id: StringName)
	var _buildings: Array = []

	func get_building_tile(_id: StringName) -> Vector2i:
		return Vector2i(-1, -1)

	func assign_npc(_building: String, _npc: StringName) -> void:
		pass

	func get_all_buildings() -> Array:
		return _buildings.duplicate()


## Creates a bare BuildingInstance for worker-delta formula tests.
## Uses STORAGE_BUILDING — no adjacency requirements, so F2 (worker delta) applies.
func _make_instance() -> BuildingRegistry.BuildingInstance:
	return BuildingRegistry.BuildingInstance.new(
			"b0", BuildingRegistry.BuildingType.STORAGE_BUILDING, Vector2i(0, 0))


## Creates a bare LUMBER_CAMP instance for adjacency-efficiency tests.
func _make_lumber_camp() -> BuildingRegistry.BuildingInstance:
	return BuildingRegistry.BuildingInstance.new(
			"b0", BuildingRegistry.BuildingType.LUMBER_CAMP, Vector2i(5, 5))


## Creates a BuildingRegistry with injected mocks and one pre-inserted BuildingInstance.
## Returns [registry, instance, mock_npc_system].
func _make_registry() -> Array:
	var mock_npc := _MockNPCSystem.new()
	add_child(mock_npc)

	var registry := BuildingRegistry.new()
	registry._npc_system = mock_npc
	registry._tick_system = null
	registry._inventory_system = null
	add_child(registry)

	var instance := _make_instance()
	registry._all_buildings.append(instance)

	return [registry, instance, mock_npc]

# ---- AC-1: F2 — no workers ----------------------------------------------------

func test_f2_no_workers_returns_base_one() -> void:
	var result := EfficiencyFormulas.calculate_building_efficiency([], 0.0)
	assert_that(result).is_equal_approx(1.0, 0.0001)


func test_f2_no_workers_with_upgrade_bonus() -> void:
	var result := EfficiencyFormulas.calculate_building_efficiency([], 0.25)
	assert_that(result).is_equal_approx(1.25, 0.0001)

# ---- AC-2: F2 — hungry worker -------------------------------------------------

func test_f2_hungry_worker_reduces_efficiency() -> void:
	# 1.0 + (0.5 − 1.0) = 0.5
	var result := EfficiencyFormulas.calculate_building_efficiency([0.5], 0.0)
	assert_that(result).is_equal_approx(0.5, 0.0001)


func test_f2_worker_at_zero_clamped_to_zero() -> void:
	# 1.0 + (0.0 − 1.0) = 0.0 — clamped to 0.0
	var result := EfficiencyFormulas.calculate_building_efficiency([0.0], 0.0)
	assert_that(result).is_equal(0.0)

# ---- AC-3: F2 — efficient worker ----------------------------------------------

func test_f2_efficient_worker_increases_efficiency() -> void:
	# 1.0 + (1.2 − 1.0) = 1.2
	var result := EfficiencyFormulas.calculate_building_efficiency([1.2], 0.0)
	assert_that(result).is_equal_approx(1.2, 0.0001)

# ---- AC-4: F2 — two workers with cancelling deltas ---------------------------

func test_f2_two_workers_cancelling_deltas_returns_one() -> void:
	# 1.0 + (1.2 − 1.0) + (0.8 − 1.0) = 1.0 + 0.2 − 0.2 = 1.0
	var result := EfficiencyFormulas.calculate_building_efficiency([1.2, 0.8], 0.0)
	assert_that(result).is_equal_approx(1.0, 0.0001)

# ---- AC-5: F2 — clamp at maximum (2.0) ----------------------------------------

func test_f2_two_workers_both_at_1_5_exactly_at_cap() -> void:
	# 1.0 + 0.5 + 0.5 = 2.0 — exactly at cap, not over
	var result := EfficiencyFormulas.calculate_building_efficiency([1.5, 1.5], 0.0)
	assert_that(result).is_equal_approx(2.0, 0.0001)


func test_f2_two_workers_both_at_2_0_clamped_to_max() -> void:
	# raw = 1.0 + 1.0 + 1.0 = 3.0 → clamped to 2.0
	var result := EfficiencyFormulas.calculate_building_efficiency([2.0, 2.0], 0.0)
	assert_that(result).is_equal(2.0)

# ---- BuildingInstance — recalculate_efficiency --------------------------------

func test_building_instance_default_efficiency_is_one() -> void:
	# STORAGE_BUILDING has no adjacency requirements — F2 base is 1.0
	var instance := _make_instance()
	assert_that(instance.efficiency).is_equal_approx(1.0, 0.0001)
	assert_that(instance.upgrade_bonus).is_equal(0.0)


func test_building_instance_recalculate_no_workers_returns_one() -> void:
	# STORAGE_BUILDING uses F2 — base 1.0 with no workers
	var instance := _make_instance()
	instance.recalculate_efficiency([])
	assert_that(instance.efficiency).is_equal_approx(1.0, 0.0001)


func test_building_instance_recalculate_with_hungry_worker() -> void:
	var instance := _make_instance()
	var npc := NPCSystem.NPCInstance.new()
	npc.npc_id = &"npc_hungry"
	npc.efficiency = 0.5
	instance.recalculate_efficiency([npc])
	assert_that(instance.efficiency).is_equal_approx(0.5, 0.0001)


func test_building_instance_recalculate_upgrade_bonus_with_no_workers() -> void:
	var instance := _make_instance()
	instance.upgrade_bonus = 0.5
	instance.recalculate_efficiency([])
	assert_that(instance.efficiency).is_equal_approx(1.5, 0.0001)

# ---- AC-6: BuildingRegistry triggers recalculate on assign --------------------

func test_registry_assign_npc_updates_building_efficiency() -> void:
	var arr := _make_registry()
	var registry: BuildingRegistry = arr[0]
	var instance: BuildingRegistry.BuildingInstance = arr[1]
	var mock_npc: _MockNPCSystem = arr[2]

	# NPC with 0.5 efficiency (hungry)
	mock_npc.add_npc(&"npc_hungry", 0.5)

	registry.assign_npc("b0", &"npc_hungry")

	assert_that(instance.efficiency).is_equal_approx(0.5, 0.0001)

# ---- AC-7: BuildingRegistry triggers recalculate on unassign ------------------

func test_registry_unassign_npc_resets_building_efficiency() -> void:
	var arr := _make_registry()
	var registry: BuildingRegistry = arr[0]
	var instance: BuildingRegistry.BuildingInstance = arr[1]
	var mock_npc: _MockNPCSystem = arr[2]

	# Assign a hungry NPC first — building efficiency drops to 0.5
	mock_npc.add_npc(&"npc_hungry", 0.5)
	registry.assign_npc("b0", &"npc_hungry")
	assert_that(instance.efficiency).is_equal_approx(0.5, 0.0001)

	# Unassign (pass &"") — building efficiency resets to 1.0 (no workers)
	registry.assign_npc("b0", &"")
	assert_that(instance.efficiency).is_equal_approx(1.0, 0.0001)

# ---- F6: EfficiencyFormulas.calculate_adjacency_efficiency --------------------

func test_f6_zero_tiles_returns_zero() -> void:
	var result := EfficiencyFormulas.calculate_adjacency_efficiency(0)
	assert_that(result).is_equal(0.0)


func test_f6_one_tile_returns_25_percent() -> void:
	var result := EfficiencyFormulas.calculate_adjacency_efficiency(1)
	assert_that(result).is_equal_approx(0.25, 0.0001)


func test_f6_four_tiles_returns_100_percent() -> void:
	var result := EfficiencyFormulas.calculate_adjacency_efficiency(4)
	assert_that(result).is_equal_approx(1.0, 0.0001)


func test_f6_eight_tiles_clamped_to_max() -> void:
	# 8 × 0.25 = 2.0 — at cap, not over (EFFICIENCY_MAX = 2.0)
	var result := EfficiencyFormulas.calculate_adjacency_efficiency(8)
	assert_that(result).is_equal_approx(2.0, 0.0001)

# ---- BuildingInstance adjacency-based recalculate ----------------------------

func test_lumber_camp_instance_default_efficiency_is_zero() -> void:
	# LUMBER_CAMP uses F6 — no adjacent tiles by default → 0.0
	var instance := _make_lumber_camp()
	assert_that(instance.efficiency).is_equal_approx(1.0, 0.0001)  # initial field default
	instance.recalculate_efficiency([])
	assert_that(instance.efficiency).is_equal(0.0)


func test_lumber_camp_instance_two_tiles_returns_50_percent() -> void:
	var instance := _make_lumber_camp()
	instance.adjacency_tile_count = 2
	instance.recalculate_efficiency([])
	assert_that(instance.efficiency).is_equal_approx(0.5, 0.0001)


func test_lumber_camp_instance_four_tiles_returns_100_percent() -> void:
	var instance := _make_lumber_camp()
	instance.adjacency_tile_count = 4
	instance.recalculate_efficiency([])
	assert_that(instance.efficiency).is_equal_approx(1.0, 0.0001)


func test_lumber_camp_instance_workers_do_not_affect_adjacency_efficiency() -> void:
	# F6 buildings ignore worker delta — workers only boost NPC travel, not building production
	var instance := _make_lumber_camp()
	instance.adjacency_tile_count = 2
	var npc := NPCSystem.NPCInstance.new()
	npc.npc_id = &"npc_super"
	npc.efficiency = 2.0
	instance.recalculate_efficiency([npc])
	# Should still be 2 × 0.25 = 0.5, ignoring worker bonus
	assert_that(instance.efficiency).is_equal_approx(0.5, 0.0001)

# ---- BuildingRegistry: terrain cleared → adjacency update --------------------

class _MockWorldGrid extends Node:
	signal terrain_tile_changed(tile: Vector2i)
	var _terrain: Dictionary = {}

	func get_terrain(tile: Vector2i) -> int:
		return _terrain.get(tile, WorldGrid.TileType.EMPTY)

	func get_neighbors(tile: Vector2i, diags: bool = false) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		var offsets: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		if diags:
			offsets.append_array([Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)])
		for offset: Vector2i in offsets:
			var n := tile + offset
			if n.x >= 0 and n.x < 30 and n.y >= 0 and n.y < 30:
				result.append(n)
		return result

	func get_building(_tile: Vector2i) -> String:
		return ""

	func validate_placement(_tile: Vector2i, _type: int) -> int:
		return 0

	func place_building(tile: Vector2i, _id: String) -> int:
		_terrain[tile] = WorldGrid.TileType.EMPTY
		return 0

	func remove_building(_tile: Vector2i) -> bool:
		return true

	func has_signal(s: String) -> bool:
		return s == "terrain_tile_changed"


func test_registry_terrain_cleared_reduces_lumber_camp_efficiency() -> void:
	# Arrange: registry with a mock grid that has TREE tiles at (5,4) and (5,6)
	var mock_grid := _MockWorldGrid.new()
	add_child(mock_grid)
	mock_grid._terrain[Vector2i(5, 4)] = WorldGrid.TileType.TREE
	mock_grid._terrain[Vector2i(5, 6)] = WorldGrid.TileType.TREE

	var registry := BuildingRegistry.new()
	registry._tick_system = null
	registry._inventory_system = null
	add_child(registry)

	# Wire the grid — this connects terrain_tile_changed
	registry.init_dependencies(mock_grid, null)

	# Insert a LUMBER_CAMP at (5,5) directly so we can observe adjacency
	var instance := BuildingRegistry.BuildingInstance.new("b0",
			BuildingRegistry.BuildingType.LUMBER_CAMP, Vector2i(5, 5))
	instance.state = BuildingRegistry.BuildingInstance.State.OPERATING
	registry._all_buildings.append(instance)

	# Manually trigger adjacency calculation as init_dependencies would for a placed building
	registry._update_adjacency_efficiency(instance)
	assert_that(instance.adjacency_tile_count).is_equal(2)
	assert_that(instance.efficiency).is_equal_approx(0.5, 0.0001)

	# Act: clear one TREE tile
	mock_grid._terrain[Vector2i(5, 4)] = WorldGrid.TileType.EMPTY
	mock_grid.terrain_tile_changed.emit(Vector2i(5, 4))

	# Assert: efficiency drops to 1 tile = 25%
	assert_that(instance.adjacency_tile_count).is_equal(1)
	assert_that(instance.efficiency).is_equal_approx(0.25, 0.0001)


func test_registry_terrain_cleared_non_adjacent_does_not_change_efficiency() -> void:
	# Arrange
	var mock_grid := _MockWorldGrid.new()
	add_child(mock_grid)
	mock_grid._terrain[Vector2i(5, 4)] = WorldGrid.TileType.TREE

	var registry := BuildingRegistry.new()
	registry._tick_system = null
	registry._inventory_system = null
	add_child(registry)
	registry.init_dependencies(mock_grid, null)

	var instance := BuildingRegistry.BuildingInstance.new("b0",
			BuildingRegistry.BuildingType.LUMBER_CAMP, Vector2i(5, 5))
	instance.state = BuildingRegistry.BuildingInstance.State.OPERATING
	registry._all_buildings.append(instance)
	registry._update_adjacency_efficiency(instance)
	assert_that(instance.efficiency).is_equal_approx(0.25, 0.0001)

	# Act: clear a tile that is NOT adjacent to (5,5)
	mock_grid._terrain[Vector2i(0, 0)] = WorldGrid.TileType.EMPTY
	mock_grid.terrain_tile_changed.emit(Vector2i(0, 0))

	# Assert: efficiency unchanged
	assert_that(instance.efficiency).is_equal_approx(0.25, 0.0001)


func test_registry_diagonal_tree_tiles_count_toward_adjacency() -> void:
	# Arrange: only diagonal TREE tiles, no cardinal TREE tiles
	var mock_grid := _MockWorldGrid.new()
	add_child(mock_grid)
	mock_grid._terrain[Vector2i(4, 4)] = WorldGrid.TileType.TREE  # diagonal NW
	mock_grid._terrain[Vector2i(6, 6)] = WorldGrid.TileType.TREE  # diagonal SE

	var registry := BuildingRegistry.new()
	registry._tick_system = null
	registry._inventory_system = null
	add_child(registry)
	registry.init_dependencies(mock_grid, null)

	var instance := BuildingRegistry.BuildingInstance.new("b0",
			BuildingRegistry.BuildingType.LUMBER_CAMP, Vector2i(5, 5))
	instance.state = BuildingRegistry.BuildingInstance.State.OPERATING
	registry._all_buildings.append(instance)

	# Act
	registry._update_adjacency_efficiency(instance)

	# Assert: 2 diagonal TREE tiles → count 2 → efficiency 0.5
	assert_that(instance.adjacency_tile_count).is_equal(2)
	assert_that(instance.efficiency).is_equal_approx(0.5, 0.0001)


func test_registry_diagonal_terrain_changed_updates_lumber_camp_efficiency() -> void:
	# Arrange: TREE at diagonal (6,6) of building at (5,5)
	var mock_grid := _MockWorldGrid.new()
	add_child(mock_grid)
	mock_grid._terrain[Vector2i(6, 6)] = WorldGrid.TileType.TREE

	var registry := BuildingRegistry.new()
	registry._tick_system = null
	registry._inventory_system = null
	add_child(registry)
	registry.init_dependencies(mock_grid, null)

	var instance := BuildingRegistry.BuildingInstance.new("b0",
			BuildingRegistry.BuildingType.LUMBER_CAMP, Vector2i(5, 5))
	instance.state = BuildingRegistry.BuildingInstance.State.OPERATING
	registry._all_buildings.append(instance)
	registry._update_adjacency_efficiency(instance)
	assert_that(instance.adjacency_tile_count).is_equal(1)

	# Act: clear the diagonal TREE tile
	mock_grid._terrain[Vector2i(6, 6)] = WorldGrid.TileType.EMPTY
	mock_grid.terrain_tile_changed.emit(Vector2i(6, 6))

	# Assert: efficiency drops to 0 (no qualifying neighbors remain)
	assert_that(instance.adjacency_tile_count).is_equal(0)
	assert_that(instance.efficiency).is_equal_approx(0.0, 0.0001)
