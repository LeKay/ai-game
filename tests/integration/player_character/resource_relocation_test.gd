## Integration tests for PlayerCharacter resource relocation drag — Story 007.
## Covers AC2, AC4, AC5, AC7, AC8, AC9 (AC1/AC3/AC6 are visual and covered by QA walkthrough).
extends GdUnitTestSuite


# ---- Helpers ----------------------------------------------------------------

func _make_pc() -> PlayerCharacter:
	var pc := PlayerCharacter.new()
	add_child(pc)
	await pc.ready
	return pc


func _make_grid() -> WorldGrid:
	var g := WorldGrid.new()
	add_child(g)
	await g.ready
	return g


## Sets energy pool to an exact value.
func _set_energy(pc: PlayerCharacter, value: int) -> void:
	if value > pc.get_current_energy():
		pc._energy_pool.restore(value - pc.get_current_energy())
	elif value < pc.get_current_energy():
		pc._energy_pool.spend_unchecked(pc.get_current_energy() - value)


## Manually places a resource on a tile in the grid (bypasses generation).
func _place_resource(grid: WorldGrid, tile: Vector2i,
		resource_id: StringName, clearable: bool = true) -> void:
	grid._resources[tile.x][tile.y].append(
		WorldGrid.ResourceTileData.new(resource_id, clearable)
	)


## Sets a tile to a given TileType in the terrain layer.
func _set_terrain(grid: WorldGrid, tile: Vector2i, tile_type: WorldGrid.TileType) -> void:
	grid._terrain[tile.x][tile.y] = tile_type


# ---- AC4: Basic successful relocation ---------------------------------------

func test_resource_relocation_success_moves_resource_to_target() -> void:
	# Arrange
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 50)
	var src := Vector2i(5, 5)
	var tgt := Vector2i(5, 10)
	_place_resource(grid, src, &"wood")
	_place_resource(grid, src, &"stone")

	# Act
	pc.try_start_relocation(src, 0, &"wood")
	var result := pc.try_commit_relocation(tgt, grid)

	# Assert
	assert_int(result).is_equal(PlayerCharacter.RelocationResult.SUCCESS)
	assert_int(grid.get_resources(src).size()).is_equal(1)   # stone remains
	assert_int(grid.get_resources(tgt).size()).is_equal(1)   # wood moved


func test_resource_relocation_success_does_not_deduct_energy() -> void:
	# Arrange — distance 5 from (5,5) to (5,10)
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 50)
	var src := Vector2i(5, 5)
	var tgt := Vector2i(5, 10)
	_place_resource(grid, src, &"wood")

	# Act
	pc.try_start_relocation(src, 0, &"wood")
	pc.try_commit_relocation(tgt, grid)

	# Assert — energy unchanged
	assert_int(pc.get_current_energy()).is_equal(50)


func test_resource_relocation_success_emits_relocation_completed_signal() -> void:
	# Arrange
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 50)
	var src := Vector2i(2, 2)
	var tgt := Vector2i(2, 5)
	_place_resource(grid, src, &"stone")

	var monitor := monitor_signals(pc)

	# Act
	pc.try_start_relocation(src, 0, &"stone")
	pc.try_commit_relocation(tgt, grid)

	# Assert
	assert_signal_emitted(monitor, "relocation_completed")


# ---- AC2: Energy cost preview -----------------------------------------------

func test_resource_relocation_get_preview_returns_manhattan_distance() -> void:
	# Arrange
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 50)
	var src := Vector2i(0, 0)
	_place_resource(grid, src, &"wood")
	pc.try_start_relocation(src, 0, &"wood")

	# Act — 3 right, 4 down = distance 7
	var preview := pc.get_relocation_preview(Vector2i(3, 4))

	# Assert — energy cost is always 0; tick cost = distance × 5
	assert_int(preview.energy_cost).is_equal(0)
	assert_int(preview.tick_cost).is_equal(35)


func test_resource_relocation_get_preview_minimum_cost_is_1() -> void:
	# Arrange — same tile preview
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 10)
	var src := Vector2i(4, 4)
	_place_resource(grid, src, &"fiber")
	pc.try_start_relocation(src, 0, &"fiber")

	# Act
	var preview := pc.get_relocation_preview(src)

	# Assert — energy cost always 0; tick cost = max(1,0) × 5 = 5
	assert_int(preview.energy_cost).is_equal(0)
	assert_int(preview.tick_cost).is_equal(5)


func test_resource_relocation_get_preview_returns_zero_when_not_dragging() -> void:
	# Arrange — no active drag
	var pc := await _make_pc()
	_set_energy(pc, 50)

	# Act
	var preview := pc.get_relocation_preview(Vector2i(5, 5))

	# Assert
	assert_int(preview.energy_cost).is_equal(0)
	assert_int(preview.tick_cost).is_equal(0)




# ---- AC7: Full target tile --------------------------------------------------

func test_resource_relocation_full_target_tile_snaps_back() -> void:
	# Arrange — target tile already holds MAX_RESOURCES_PER_TILE (4) entries
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 50)
	var src := Vector2i(0, 0)
	var tgt := Vector2i(8, 8)
	_place_resource(grid, src, &"wood")
	for _i in range(WorldGrid.MAX_RESOURCES_PER_TILE):
		_place_resource(grid, tgt, &"stone")

	# Act
	pc.try_start_relocation(src, 0, &"wood")
	var result := pc.try_commit_relocation(tgt, grid)

	# Assert
	assert_int(result).is_equal(PlayerCharacter.RelocationResult.SNAP_BACK_FULL)
	assert_int(grid.get_resources(src).size()).is_equal(1)   # source unchanged
	assert_int(grid.get_resources(tgt).size()).is_equal(4)   # target unchanged




# ---- AC9: Same-tile drop ----------------------------------------------------

func test_resource_relocation_same_tile_snap_back_no_energy_cost() -> void:
	# Arrange — distance 0, energy 10
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 10)
	var src := Vector2i(4, 4)
	_place_resource(grid, src, &"berry")

	# Act
	pc.try_start_relocation(src, 0, &"berry")
	var result := pc.try_commit_relocation(src, grid)

	# Assert — no energy spent, WorldGrid unchanged
	assert_int(result).is_equal(PlayerCharacter.RelocationResult.SNAP_BACK_SAME_TILE)
	assert_int(pc.get_current_energy()).is_equal(10)
	assert_int(grid.get_resources(src).size()).is_equal(1)  # no move in grid


# ---- cancel_relocation ------------------------------------------------------

func test_resource_relocation_cancel_emits_cancelled_and_resets_state() -> void:
	# Arrange
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 20)
	var src := Vector2i(2, 2)
	_place_resource(grid, src, &"wood")
	pc.try_start_relocation(src, 0, &"wood")

	var monitor := monitor_signals(pc)

	# Act
	pc.cancel_relocation()

	# Assert
	assert_signal_emitted(monitor, "relocation_cancelled")
	assert_bool(pc.is_relocating()).is_false()
	assert_int(pc.get_current_energy()).is_equal(20)  # energy unchanged


func test_resource_relocation_cancel_when_idle_is_noop() -> void:
	# Arrange — no active drag
	var pc := await _make_pc()
	_set_energy(pc, 20)
	var monitor := monitor_signals(pc)

	# Act
	pc.cancel_relocation()

	# Assert — signal NOT emitted, no error
	assert_signal_not_emitted(monitor, "relocation_cancelled")


# ---- AC6: SNAP_BACK_INVALID — impassable and out-of-bounds targets ----------

func test_resource_relocation_impassable_target_returns_snap_back_invalid() -> void:
	# Arrange
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 50)
	var src := Vector2i(2, 2)
	var tgt := Vector2i(5, 5)
	_place_resource(grid, src, &"wood")
	_set_terrain(grid, tgt, WorldGrid.TileType.IMPASSABLE)

	# Act
	pc.try_start_relocation(src, 0, &"wood")
	var result := pc.try_commit_relocation(tgt, grid)

	# Assert
	assert_int(result).is_equal(PlayerCharacter.RelocationResult.SNAP_BACK_INVALID)
	assert_int(pc.get_current_energy()).is_equal(50)  # energy unchanged
	assert_int(grid.get_resources(src).size()).is_equal(1)  # grid unchanged


func test_resource_relocation_out_of_bounds_target_returns_snap_back_invalid() -> void:
	# Arrange
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 50)
	var src := Vector2i(2, 2)
	_place_resource(grid, src, &"stone")

	# Act
	pc.try_start_relocation(src, 0, &"stone")
	var result := pc.try_commit_relocation(Vector2i(-1, -1), grid)

	# Assert
	assert_int(result).is_equal(PlayerCharacter.RelocationResult.SNAP_BACK_INVALID)
	assert_int(pc.get_current_energy()).is_equal(50)
	assert_int(grid.get_resources(src).size()).is_equal(1)


# ---- try_commit_relocation when not dragging --------------------------------

func test_resource_relocation_commit_when_not_dragging_returns_not_dragging() -> void:
	# Arrange — no active drag
	var pc := await _make_pc()
	var grid := await _make_grid()
	_set_energy(pc, 50)

	# Act
	var result := pc.try_commit_relocation(Vector2i(5, 5), grid)

	# Assert
	assert_int(result).is_equal(PlayerCharacter.RelocationResult.NOT_DRAGGING)
