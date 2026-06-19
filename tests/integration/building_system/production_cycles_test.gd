## GdUnit4 integration test suite for Building System Story 002:
## Production Cycles and Carrier Transport.
##
## Tests wire BuildingRegistry with real WorldGrid, InventorySystem, and
## PlayerCharacter instances without relying on Autoload singletons.
##
## AC coverage:
##   AC-06 — Construction completion via complete_construction_manually()
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

func before_test() -> void:
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
## The building starts in CONSTRUCTING state.
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

func test_production_lumber_camp_manual_construction_transitions_to_operating() -> void:
	# Arrange
	var tile := Vector2i(5, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)

	# Act
	_registry.complete_construction_manually(bid)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


func test_production_construction_not_auto_advanced_by_ticks() -> void:
	# Construction is now a manual player action — ticks must not advance it.
	var tile := Vector2i(6, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)

	_registry._on_ticks_advanced(99999)

	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)


func test_production_construction_complete_signal_emitted() -> void:
	# Arrange
	var tile := Vector2i(7, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var signal_monitor := monitor_signals(_registry)

	# Act
	_registry.complete_construction_manually(bid)

	# Assert
	await assert_signal(signal_monitor).is_emitted("building_construction_complete")


func test_production_construction_complete_signal_carries_correct_building_id() -> void:
	# Arrange
	var tile := Vector2i(8, 5)
	var bid: String = _place_lumber_camp_free(tile)
	var emitted_args: Array = []
	_registry.building_construction_complete.connect(
		func(b_id: String, _type: int) -> void: emitted_args = [b_id, _type]
	)

	# Act
	_registry.complete_construction_manually(bid)

	# Assert
	assert_str(emitted_args[0]).is_equal(bid)
	assert_int(emitted_args[1]).is_equal(BuildingRegScript.BuildingType.LUMBER_CAMP)


func test_production_manual_construction_idempotent_when_already_operating() -> void:
	# complete_construction_manually on an already-operating building must be a no-op.
	var tile := Vector2i(9, 5)
	var bid: String = _place_lumber_camp_free(tile)
	_registry.complete_construction_manually(bid)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)

	# Call again — should not emit a second signal or change state
	var signal_count: int = 0
	_registry.building_construction_complete.connect(
		func(_b: String, _t: int) -> void: signal_count += 1
	)
	_registry.complete_construction_manually(bid)

	assert_int(signal_count).is_equal(0)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


# =============================================================================
# AC-09: Production cycle starts when NPC + inputs present
# =============================================================================

func _make_operating_lumber_camp(tile: Vector2i) -> String:
	var bid: String = _place_lumber_camp_free(tile)
	_registry.complete_construction_manually(bid)
	return bid


## Returns an operating Lumber Camp with both carrier IDs pre-populated so production
## cycles can start and complete without BLOCKED/STALLED state transitions.
func _make_carrying_lumber_camp(tile: Vector2i) -> String:
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	return bid


func test_production_cycle_starts_when_npc_and_inputs_present() -> void:
	# Arrange
	var tile := Vector2i(5, 10)
	var bid: String = _make_carrying_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_01")
	instance.input_buffer[&"axe"] = 1.0

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
	instance.input_buffer[&"axe"] = 1.0

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_bool(instance.cycle_running).is_false()


func test_production_cycle_does_not_start_with_insufficient_tool_charge() -> void:
	# Arrange — charge_cost = 1.0, only 0.0 available
	var tile := Vector2i(7, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_02")
	instance.input_buffer[&"axe"] = 0.0  # insufficient

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_bool(instance.cycle_running).is_false()


func test_production_cycle_starts_when_tool_in_buffer() -> void:
	# Arrange — 1 tool satisfies quantity:1 requirement
	var tile := Vector2i(8, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_03")
	instance.input_buffer[&"axe"] = 1.0

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_bool(instance.cycle_running).is_true()


func test_production_inputs_deducted_from_buffer_when_cycle_starts() -> void:
	# Arrange
	var tile := Vector2i(9, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_04")
	instance.input_buffer[&"axe"] = 2.0  # more than needed (1.0)

	# Act
	_registry._on_ticks_advanced(1)

	assert_float(instance.input_buffer.get(&"axe", 0.0)).is_equal(1.0)


# =============================================================================
# AC-12/AC-13: Transport and cycle formulas moved out of BuildingRegistry.
# Carrier travel time lives in LogisticsSystem (TICKS_PER_TILE + F4);
# cycle duration uses EfficiencyFormulas.calculate_effective_cycle_ticks (F3).
# The legacy stubs (calculate_carrier_travel_ticks / calculate_production_output /
# calculate_cycle_duration) were removed 2026-06-13.
# =============================================================================

func test_production_cycle_duration_uses_f3_at_full_efficiency() -> void:
	# Arrange — F3: base / efficiency, efficiency 1.0 → base unchanged
	# Act
	var result: int = EfficiencyFormulas.calculate_effective_cycle_ticks(250, 1.0)
	# Assert
	assert_int(result).is_equal(250)


func test_production_cycle_duration_doubles_at_half_efficiency() -> void:
	# Arrange — F3: hungry worker (building efficiency 0.5) → 2× base
	# Act
	var result: int = EfficiencyFormulas.calculate_effective_cycle_ticks(250, 0.5)
	# Assert
	assert_int(result).is_equal(500)


func test_production_cycle_completes_after_base_cycle_ticks() -> void:
	# Arrange
	var tile := Vector2i(5, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_10")
	instance.input_buffer[&"axe"] = 1.0
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
	instance.input_buffer[&"axe"] = 1.0
	_registry._on_ticks_advanced(1)  # start cycle (cycle_ticks reset to 0)
	var signal_monitor := monitor_signals(_registry)

	# Act — advance 100 ticks so cycle completes
	_registry._on_ticks_advanced(100)

	# Assert
	await assert_signal(signal_monitor).is_emitted("production_output_ready")


func test_production_collect_output_returns_and_clears_buffer() -> void:
	# Arrange
	var tile := Vector2i(7, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_12")
	instance.input_buffer[&"axe"] = 1.0
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
	instance.input_buffer[&"axe"] = 20.0
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

	# Act — complete construction manually
	_registry.complete_construction_manually(bid)

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
	_registry.complete_construction_manually(bid)  # complete construction → npc_count = 1
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
	_registry.complete_construction_manually(bid)  # → npc_count = 1
	_registry._on_ticks_advanced(1000)             # → npc_count = 2
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


func test_production_residential_house_no_npc_without_manual_construction() -> void:
	# AC-22 edge: ticks alone must not spawn NPCs; player must manually complete construction.
	var tile := Vector2i(8, 25)
	var bid: String = _place_residential_house(tile)
	var spawn_count: int = 0
	_registry.building_npc_spawn_requested.connect(
		func(_b: String, _t: Vector2i, _c: int) -> void: spawn_count += 1
	)

	# Act — advance many ticks without calling complete_construction_manually
	_registry._on_ticks_advanced(99999)

	# Assert — no spawn, still CONSTRUCTING
	assert_int(spawn_count).is_equal(0)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.npc_count).is_equal(0)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)


# =============================================================================
# AC-06 edge: Storage Area never enters CONSTRUCTING (build_time = 0)
# =============================================================================

func test_production_storage_area_starts_operating_never_constructing() -> void:
	# Arrange — Storage Area has no build cost and build_time = 0
	var tile := Vector2i(5, 30)
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.COLLECTION_POINT, tile)
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	var count: int = _registry.get_building_count()
	var bid: String = str(count - 1)

	# Assert — state is OPERATING immediately, no tick advance needed
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)
