class_name TileHarvestInteractionTest extends GdUnitTestSuite
## Integration tests: tile→action dispatch and PlayerCharacter action-slot behavior.
## Covers MapRoot._terrain_to_action() mapping and try_start_action() dispatch path.
##
## Isolation strategy:
##   - MapRoot instantiated without add_child() so _ready() never fires; _terrain_to_action()
##     is a pure function with no instance-variable dependencies.
##   - PlayerCharacter instantiated directly (not via autoload) so tests run headless.
##   - TickSystem and Inventory are left null (PlayerCharacter tolerates this).

# ---- Helpers -----------------------------------------------------------------

func _make_player() -> PlayerCharacter:
	var pc := PlayerCharacter.new()
	add_child(pc)
	pc.init_dependencies(null, null, null, null)
	return pc


## Returns a MapRoot whose _ready() has NOT fired — safe for pure-function calls only.
func _make_map_root() -> MapRoot:
	return MapRoot.new()


# ---- Terrain → action mapping (AC1–AC6) -------------------------------------

## AC1: TREE tile maps to CHOP_TREE.
func test_tile_harvest_terrain_tree_maps_to_chop_tree() -> void:
	var mr := _make_map_root()
	assert_int(mr._terrain_to_action(WorldGrid.TileType.TREE)).is_equal(PlayerCharacter.ManualActionType.CHOP_TREE)
	mr.free()


## AC2: STONE tile maps to MINE_STONE.
func test_tile_harvest_terrain_stone_maps_to_mine_stone() -> void:
	var mr := _make_map_root()
	assert_int(mr._terrain_to_action(WorldGrid.TileType.STONE)).is_equal(PlayerCharacter.ManualActionType.MINE_STONE)
	mr.free()


## AC3: BERRY tile maps to PICK_BERRIES.
func test_tile_harvest_terrain_berry_maps_to_pick_berries() -> void:
	var mr := _make_map_root()
	assert_int(mr._terrain_to_action(WorldGrid.TileType.BERRY)).is_equal(PlayerCharacter.ManualActionType.PICK_BERRIES)
	mr.free()


## AC4: GRASS tile maps to HARVEST_FIBER.
func test_tile_harvest_terrain_grass_maps_to_harvest_fiber() -> void:
	var mr := _make_map_root()
	assert_int(mr._terrain_to_action(WorldGrid.TileType.GRASS)).is_equal(PlayerCharacter.ManualActionType.HARVEST_FIBER)
	mr.free()


## AC5: EMPTY tile maps to FORAGE.
func test_tile_harvest_terrain_empty_maps_to_forage() -> void:
	var mr := _make_map_root()
	assert_int(mr._terrain_to_action(WorldGrid.TileType.EMPTY)).is_equal(PlayerCharacter.ManualActionType.FORAGE)
	mr.free()


## AC6: IMPASSABLE tile returns -1 — no action dispatched.
func test_tile_harvest_terrain_impassable_maps_to_no_action() -> void:
	var mr := _make_map_root()
	assert_int(mr._terrain_to_action(WorldGrid.TileType.IMPASSABLE)).is_equal(-1)
	mr.free()


# ---- HARVEST_FIBER action dispatch ------------------------------------------

## HARVEST_FIBER starts successfully when energy is available and slot is free.
func test_tile_harvest_fiber_starts_when_slot_free() -> void:
	var pc := _make_player()
	var result: int = pc.try_start_action(PlayerCharacter.ManualActionType.HARVEST_FIBER)
	assert_int(result).is_equal(PlayerCharacter.StartResult.SUCCESS)
	free_children()


## AC7: Occupied slot emits action_failed with the correct reason string.
func test_tile_harvest_fiber_blocked_slot_emits_action_failed_with_message() -> void:
	var pc := _make_player()
	var failed_calls: Array = []
	pc.action_failed.connect(func(id: int, reason: String) -> void: failed_calls.append([id, reason]))
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)
	pc.try_start_action(PlayerCharacter.ManualActionType.HARVEST_FIBER)
	assert_int(failed_calls.size()).is_equal(1) \
		.override_failure_message("action_failed must fire exactly once")
	assert_str(failed_calls[0][1]).is_equal("Another action is in progress")
	free_children()


## HARVEST_FIBER deducts the correct energy cost (6) on success.
func test_tile_harvest_fiber_deducts_energy() -> void:
	var pc := _make_player()
	var energy_before: int = pc.get_current_energy()
	pc.try_start_action(PlayerCharacter.ManualActionType.HARVEST_FIBER)
	assert_int(energy_before - pc.get_current_energy()).is_equal(6)
	free_children()


## HARVEST_FIBER config: tick_cost=45, base_output=2, output_resource=fiber, energy_cost=6.
func test_tile_harvest_fiber_cost_preview_values() -> void:
	var pc := _make_player()
	var preview: Dictionary = pc.get_cost_preview(PlayerCharacter.ManualActionType.HARVEST_FIBER)
	assert_bool(preview.blocked).is_false()
	assert_int(preview.tick_cost).is_equal(45)
	assert_int(preview.output_qty).is_equal(2)
	assert_str(str(preview.output_resource)).is_equal("fiber")
	assert_int(preview.energy_cost).is_equal(6)
	free_children()


## HARVEST_FIBER does not require a tool.
func test_tile_harvest_fiber_no_tool_required() -> void:
	var pc := _make_player()
	var result: int = pc.try_start_action(PlayerCharacter.ManualActionType.HARVEST_FIBER)
	assert_int(result).is_not_equal(PlayerCharacter.StartResult.TOOL_REQUIRED)
	free_children()


# ---- FORAGE_TABLE weights ----------------------------------------------------

## FORAGE_TABLE cumulative weights are strictly ascending and sum to 100.
func test_tile_harvest_forage_table_weights_valid() -> void:
	var prev: int = 0
	for entry: Array in PlayerCharacter.FORAGE_TABLE:
		var weight: int = entry[1] as int
		assert_int(weight).is_greater(prev) \
			.override_failure_message("FORAGE_TABLE weight must be strictly ascending")
		prev = weight
	assert_int(prev).is_equal(100) \
		.override_failure_message("FORAGE_TABLE must sum to 100")


## Fiber appears in the FORAGE_TABLE loot pool.
func test_tile_harvest_forage_table_contains_fiber() -> void:
	var found := false
	for entry: Array in PlayerCharacter.FORAGE_TABLE:
		if entry[0] == &"fiber":
			found = true
			break
	assert_bool(found).is_true() \
		.override_failure_message("fiber must be present in FORAGE_TABLE")


# ---- Architect-mode gate -----------------------------------------------------

## HARVEST_FIBER is blocked by architect mode (gathering action).
func test_tile_harvest_fiber_blocked_by_architect_mode() -> void:
	var pc := _make_player()
	pc._architect_mode.on_npc_assigned(&"npc_01", &"building_01")
	var result: int = pc.try_start_action(PlayerCharacter.ManualActionType.HARVEST_FIBER)
	assert_int(result).is_equal(PlayerCharacter.StartResult.ARCHITECT_LOCKED)
	free_children()
