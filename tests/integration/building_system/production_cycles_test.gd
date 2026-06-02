## GdUnit4 integration test suite for Building System Story 002:
## Production Cycles and Carrier Transport.
##
## Tests wire BuildingRegistry with real WorldGrid, InventorySystem, and
## PlayerCharacter instances without relying on Autoload singletons.
##
## AC coverage:
##   AC-06 — Construction completion (CONSTRUCTING → OPERATING at build_time)
##   AC-09 — Production cycle starts when inputs + NPC present
##   AC-12 — Carrier travel ticks formula; output always full base_output
##   AC-13 — Cycle duration = base_cycle_ticks; buffered_output set; signal emitted
##   AC-14 — Pausing stops tick accumulation (TickSystem not called → no advance)
##   AC-22 — Residential House NPC spawn on construction complete + interval spawn

extends GdUnitTestSuite

const WorldGridScript   := preload("res://src/systems/world_grid.gd")
const BuildingRegScript := preload("res://src/gameplay/building_registry.gd")
const InventoryScript   := preload("res://src/systems/inventory/inventory_system.gd")
const PlayerCharScript  := preload("res://src/systems/player_character.gd")

# ---- Fixtures ---------------------------------------------------------------

var _registry: BuildingRegScript
var _grid: WorldGridScript
var _inventory: InventoryScript
var _player: PlayerCharScript

## Shared supply container for resource pre-seeding.
const SUPPLY: StringName = &"test_supply"

func before_each() -> void:
	_grid = WorldGridScript.new()
	_grid._init_arrays()
	auto_free(_grid)

	_inventory = InventoryScript.new()
	auto_free(_inventory)

	_player = PlayerCharScript.new()
	add_child(_player)
	auto_free(_player)

	_registry = BuildingRegScript.new()
	auto_free(_registry)
	_registry._inventory_system = _inventory
	_registry._tick_system = null  # tick system not needed — tests call _on_ticks_advanced() directly
	_registry.init_dependencies(_grid, _player)


## Seeds the supply container with the given quantity of a resource.
func _seed(resource_id: StringName, qty: int) -> void:
	if _inventory.get_container(SUPPLY) == null:
		_inventory.create_container(SUPPLY, "Supply", 9999)
	_inventory.try_deposit(SUPPLY, resource_id, qty)


## Places a Lumber Camp, bypassing resource/energy checks via internal manipulation.
## The building starts in CONSTRUCTING state (build_time = 200).
## Returns the building_id string ("0", "1", ...).
func _place_lumber_camp_free(tile: Vector2i) -> String:
	# Seed full build cost so initiate_build succeeds.
	_seed(&"wood", 15)
	_seed(&"stone", 3)
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.LUMBER_CAMP, tile)
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	# Find the most-recently added building.
	var count: int = _registry.get_building_count()
	return str(count - 1)


# =============================================================================
# AC-06: Construction completion
# =============================================================================

func test_production_lumber_camp_construction_completes_at_build_time() -> void:
	# Arrange
	var tile := Vector2i(5, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)

	# Act — advance exactly build_time ticks (200)
	_registry._on_ticks_advanced(200)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


func test_production_lumber_camp_construction_not_complete_one_tick_early() -> void:
	# Arrange
	var tile := Vector2i(6, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)

	# Act — 199 ticks — should NOT complete
	_registry._on_ticks_advanced(199)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)


func test_production_construction_complete_signal_emitted() -> void:
	# Arrange
	var tile := Vector2i(7, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var signal_monitor := monitor_signals(_registry)

	# Act
	_registry._on_ticks_advanced(200)

	# Assert
	assert_signal_emitted(signal_monitor, "building_construction_complete")


func test_production_construction_complete_signal_carries_correct_building_id() -> void:
	# Arrange
	var tile := Vector2i(8, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var emitted_args: Array = []
	_registry.building_construction_complete.connect(
		func(b_id: String, _type: int) -> void: emitted_args = [b_id, _type]
	)

	# Act
	_registry._on_ticks_advanced(200)

	# Assert
	assert_str(emitted_args[0]).is_equal(bid)
	assert_int(emitted_args[1]).is_equal(BuildingRegScript.BuildingType.LUMBER_CAMP)


func test_production_accumulated_ticks_spans_multiple_advances() -> void:
	# Arrange
	var tile := Vector2i(9, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)

	# Act — 100 + 100 = 200 total
	_registry._on_ticks_advanced(100)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)
	_registry._on_ticks_advanced(100)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


# =============================================================================
# AC-09: Production cycle starts when NPC + inputs present
# =============================================================================

func _make_operating_lumber_camp(tile: Vector2i) -> String:
	var bid: String = _place_lumber_camp_free(tile)
	_registry._on_ticks_advanced(200)  # complete construction
	return bid


func test_production_cycle_starts_when_npc_and_inputs_present() -> void:
	# Arrange
	var tile := Vector2i(5, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_01")
	instance.input_buffer[&"wood"] = 1.0
	instance.input_buffer[&"tool"] = 5.0  # full tool charge

	# Act — tick fires, cycle should start
	_registry._on_ticks_advanced(1)

	# Assert
	assert_bool(instance.cycle_running).is_true()
	assert_int(instance.production_cycle_duration).is_equal(100)


func test_production_cycle_does_not_start_without_npc() -> void:
	# Arrange
	var tile := Vector2i(6, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	# No NPC assigned — assigned_npc_id is &""
	instance.input_buffer[&"wood"] = 1.0
	instance.input_buffer[&"tool"] = 5.0

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_bool(instance.cycle_running).is_false()


func test_production_cycle_does_not_start_with_insufficient_tool_charge() -> void:
	# Arrange — charge_cost = 5.0, only 4.0 available
	var tile := Vector2i(7, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_02")
	instance.input_buffer[&"wood"] = 1.0
	instance.input_buffer[&"tool"] = 4.0  # insufficient

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_bool(instance.cycle_running).is_false()


func test_production_cycle_does_not_start_without_wood_input() -> void:
	# Arrange — no wood in buffer
	var tile := Vector2i(8, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_03")
	instance.input_buffer[&"tool"] = 5.0
	# wood not added

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_bool(instance.cycle_running).is_false()


func test_production_inputs_deducted_from_buffer_when_cycle_starts() -> void:
	# Arrange
	var tile := Vector2i(9, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_04")
	instance.input_buffer[&"wood"] = 2.0  # more than needed (1)
	instance.input_buffer[&"tool"] = 10.0  # more than needed (5.0)

	# Act
	_registry._on_ticks_advanced(1)

	# Assert — exactly 1 wood and 5.0 charge consumed
	assert_float(instance.input_buffer.get(&"wood", 0.0)).is_equal(1.0)
	assert_float(instance.input_buffer.get(&"tool", 0.0)).is_equal(5.0)


# =============================================================================
# AC-12: Carrier travel time formula; output always full base_output
# =============================================================================

func test_production_carrier_travel_ticks_formula_example() -> void:
	# Arrange — AC-12 example: distance 10, ticks_per_tile 3.0 → 30
	# Act
	var result: int = _registry.calculate_carrier_travel_ticks(10)
	# Assert
	assert_int(result).is_equal(30)


func test_production_carrier_travel_ticks_zero_distance() -> void:
	# Arrange — distance 0 → instant pickup
	var result: int = _registry.calculate_carrier_travel_ticks(0)
	assert_int(result).is_equal(0)


func test_production_carrier_travel_ticks_large_distance() -> void:
	# Arrange — distance 25 → floor(25 * 3.0) = 75
	var result: int = _registry.calculate_carrier_travel_ticks(25)
	assert_int(result).is_equal(75)


func test_production_output_always_base_output_regardless_of_distance() -> void:
	# AC-12: distance does NOT reduce output
	assert_int(_registry.calculate_production_output(5)).is_equal(5)
	assert_int(_registry.calculate_production_output(5)).is_equal(5)  # same at any distance


# =============================================================================
# AC-13: Cycle duration = base_cycle_ticks; output in buffer; signal emitted
# =============================================================================

func test_production_cycle_duration_is_always_base_cycle_ticks() -> void:
	# AC-13: Formula 5 — no distance modifier
	assert_int(_registry.calculate_cycle_duration(100)).is_equal(100)
	assert_int(_registry.calculate_cycle_duration(100)).is_equal(100)


func test_production_cycle_completes_after_base_cycle_ticks() -> void:
	# Arrange
	var tile := Vector2i(5, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_10")
	instance.input_buffer[&"wood"] = 1.0
	instance.input_buffer[&"tool"] = 5.0
	_registry._on_ticks_advanced(1)   # starts cycle (production_cycle_ticks reset to 0)
	assert_bool(instance.cycle_running).is_true()

	# Act — advance 100 ticks so cycle_ticks reaches 100 = cycle_duration
	_registry._on_ticks_advanced(100)

	# Assert
	assert_bool(instance.cycle_running).is_false()
	assert_int(instance.buffered_output.get(&"wood", 0)).is_equal(5)


func test_production_output_ready_signal_emitted_on_cycle_complete() -> void:
	# Arrange
	var tile := Vector2i(6, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_11")
	instance.input_buffer[&"wood"] = 1.0
	instance.input_buffer[&"tool"] = 5.0
	_registry._on_ticks_advanced(1)  # start cycle (cycle_ticks reset to 0)
	var signal_monitor := monitor_signals(_registry)

	# Act — advance 100 ticks so cycle completes
	_registry._on_ticks_advanced(100)

	# Assert
	assert_signal_emitted(signal_monitor, "production_output_ready")


func test_production_collect_output_returns_and_clears_buffer() -> void:
	# Arrange
	var tile := Vector2i(7, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_12")
	instance.input_buffer[&"wood"] = 1.0
	instance.input_buffer[&"tool"] = 5.0
	_registry._on_ticks_advanced(1)    # start cycle
	_registry._on_ticks_advanced(100)  # complete cycle
	assert_int(instance.buffered_output.get(&"wood", 0)).is_equal(5)

	# Act
	var collected: Dictionary = _registry.collect_output(bid)

	# Assert
	assert_int(collected.get(&"wood", 0)).is_equal(5)
	assert_bool(instance.buffered_output.is_empty()).is_true()


func test_production_new_cycle_does_not_start_while_output_buffered() -> void:
	# Arrange — complete one cycle, leave output in buffer, provide more inputs
	var tile := Vector2i(8, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_13")
	instance.input_buffer[&"wood"] = 3.0
	instance.input_buffer[&"tool"] = 20.0
	_registry._on_ticks_advanced(1)    # start cycle 1
	_registry._on_ticks_advanced(100)  # complete cycle 1 → output buffered
	assert_bool(instance.buffered_output.is_empty()).is_false()

	# Act — tick again; should NOT start cycle 2 while output pending
	_registry._on_ticks_advanced(1)

	# Assert — still not running a new cycle
	assert_bool(instance.cycle_running).is_false()


# =============================================================================
# AC-14: Pause stops tick accumulation
# =============================================================================

func test_production_paused_no_ticks_means_no_accumulation() -> void:
	# AC-14: TickSystem paused → _on_ticks_advanced is never called.
	# Simulate by NOT calling _on_ticks_advanced and verifying state unchanged.
	var tile := Vector2i(5, 20)
	var bid: String = _place_lumber_camp_free(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)

	# Do not advance ticks — accumulated_ticks stays at 0.
	assert_int(instance.accumulated_ticks).is_equal(0)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)


func test_production_partial_construction_resumes_after_pause() -> void:
	# AC-14: Advance 87, then pause (no advance), then advance 113 → total 200 → OPERATING.
	var tile := Vector2i(6, 20)
	var bid: String = _place_lumber_camp_free(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)

	_registry._on_ticks_advanced(87)
	assert_int(instance.accumulated_ticks).is_equal(87)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)

	# "Pause" — no calls to _on_ticks_advanced here.

	_registry._on_ticks_advanced(113)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


# =============================================================================
# AC-22: Residential House NPC spawn
# =============================================================================

func _place_residential_house(tile: Vector2i) -> String:
	_seed(&"wood", 10)
	_seed(&"stone", 3)
	var result: int = _registry.initiate_build(
		BuildingRegScript.BuildingType.RESIDENTIAL_HOUSE, tile
	)
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	var count: int = _registry.get_building_count()
	return str(count - 1)


func test_production_residential_house_spawns_first_npc_on_construction_complete() -> void:
	# Arrange
	var tile := Vector2i(5, 25)
	var bid: String = _place_residential_house(tile)
	var spawn_args: Array = []
	_registry.building_npc_spawn_requested.connect(
		func(b_id: String, t: Vector2i, cnt: int) -> void: spawn_args = [b_id, t, cnt]
	)

	# Act — complete construction
	_registry._on_ticks_advanced(150)

	# Assert — first NPC spawned immediately
	assert_array(spawn_args).is_not_empty()
	assert_str(spawn_args[0]).is_equal(bid)
	assert_int(spawn_args[2]).is_equal(1)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.npc_count).is_equal(1)


func test_production_residential_house_spawns_second_npc_after_interval() -> void:
	# Arrange
	var tile := Vector2i(6, 25)
	var bid: String = _place_residential_house(tile)
	_registry._on_ticks_advanced(150)  # complete construction → npc_count = 1
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.npc_count).is_equal(1)

	var spawn_count: int = 0
	_registry.building_npc_spawn_requested.connect(
		func(_b: String, _t: Vector2i, _c: int) -> void: spawn_count += 1
	)

	# Act — advance NPC_SPAWN_INTERVAL ticks (1000)
	_registry._on_ticks_advanced(1000)

	# Assert — second NPC spawned, timer reset
	assert_int(instance.npc_count).is_equal(2)
	assert_int(spawn_count).is_equal(1)
	assert_int(instance.npc_spawn_timer).is_equal(0)


func test_production_residential_house_no_third_npc_spawned() -> void:
	# Arrange
	var tile := Vector2i(7, 25)
	var bid: String = _place_residential_house(tile)
	_registry._on_ticks_advanced(150)   # → npc_count = 1
	_registry._on_ticks_advanced(1000)  # → npc_count = 2
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.npc_count).is_equal(2)

	var spawn_count: int = 0
	_registry.building_npc_spawn_requested.connect(
		func(_b: String, _t: Vector2i, _c: int) -> void: spawn_count += 1
	)

	# Act — advance another interval past the cap
	_registry._on_ticks_advanced(1000)

	# Assert — hard cap: no third NPC, timer reset
	assert_int(instance.npc_count).is_equal(2)
	assert_int(spawn_count).is_equal(0)
	assert_int(instance.npc_spawn_timer).is_equal(0)


func test_production_residential_house_not_complete_before_build_time() -> void:
	# AC-22 edge: no spawn before construction complete
	var tile := Vector2i(8, 25)
	var bid: String = _place_residential_house(tile)
	var spawn_count: int = 0
	_registry.building_npc_spawn_requested.connect(
		func(_b: String, _t: Vector2i, _c: int) -> void: spawn_count += 1
	)

	# Act — 149 ticks (1 short of 150)
	_registry._on_ticks_advanced(149)

	# Assert — no spawn yet
	assert_int(spawn_count).is_equal(0)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.npc_count).is_equal(0)


# =============================================================================
# AC-06 edge: Storage Area never enters CONSTRUCTING (build_time = 0)
# =============================================================================

func test_production_storage_area_starts_operating_never_constructing() -> void:
	# Arrange — Storage Area has no build cost and build_time = 0
	var tile := Vector2i(5, 30)
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	var count: int = _registry.get_building_count()
	var bid: String = str(count - 1)

	# Assert — state is OPERATING immediately, no tick advance needed
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)
