## GdUnit4 integration test suite for Building System Story 003:
## Failed States — BLOCKED and Output-Full.
##
## Tests wire BuildingRegistry with real WorldGrid, InventorySystem, and
## PlayerCharacter instances without relying on Autoload singletons.
##
## AC coverage:
##   AC-10 — Production cycle starts normally (foundation covered by story-002; edge case added here)
##   AC-11 — BLOCKED → OPERATING auto-recovery when conditions resolve
##   AC-12 — No NPC assigned → BLOCKED state + building_blocked signal
##   AC-12b — No input carrier → BLOCKED state with "No carrier assigned (inputs)" reason
##   AC-12c — Output buffer full after cycle completes → OPERATING, output preserved
##   AC-14 — collect_output clears buffer; next cycle can start
##   AC-23 — Storage buildings never enter BLOCKED

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
	_registry._tick_system = null
	_registry.init_dependencies(_grid, _player)


func _seed(resource_id: StringName, qty: int) -> void:
	if _inventory.get_container(SUPPLY) == null:
		_inventory.create_container(SUPPLY, "Supply", 9999)
	_inventory.try_deposit(SUPPLY, resource_id, qty)


## Places and fully constructs a Lumber Camp at tile, returning its building_id.
func _make_operating_lumber_camp(tile: Vector2i) -> String:
	_seed(&"wood", 15)
	_seed(&"stone", 3)
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.LUMBER_CAMP, tile)
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	_registry._on_ticks_advanced(200)
	var count: int = _registry.get_building_count()
	return str(count - 1)


## Places, constructs, and fully wires a Lumber Camp for production
## (both carrier IDs set, NPC assigned, one full tool charge in buffer).
func _make_ready_lumber_camp(tile: Vector2i) -> String:
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_ready")
	instance.input_buffer[&"tool"] = 5.0
	return bid


# =============================================================================
# AC-12: No NPC assigned → BLOCKED
# =============================================================================

func test_failed_states_no_npc_transitions_to_blocked() -> void:
	# Arrange — carrier set, inputs set, NPC absent
	var tile := Vector2i(5, 5)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	instance.input_buffer[&"tool"] = 5.0
	# assigned_npc_id = &"" (default)

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.BLOCKED)
	assert_bool(instance.cycle_running).is_false()


func test_failed_states_no_npc_emits_building_blocked_signal() -> void:
	# Arrange
	var tile := Vector2i(6, 5)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	instance.input_buffer[&"tool"] = 5.0
	var blocked_reason: String = ""
	_registry.building_blocked.connect(func(_id: String, r: String) -> void: blocked_reason = r)

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_str(blocked_reason).is_equal("No NPC assigned")


# =============================================================================
# AC-12b: No input carrier → BLOCKED
# =============================================================================

func test_failed_states_no_input_carrier_transitions_to_blocked() -> void:
	# Arrange — NPC + inputs present, no input carrier assigned
	var tile := Vector2i(5, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	# input_carrier_ids = [] (default)
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_01")
	instance.input_buffer[&"tool"] = 5.0

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.BLOCKED)
	assert_bool(instance.cycle_running).is_false()


func test_failed_states_no_input_carrier_emits_blocked_signal_with_carrier_reason() -> void:
	# Arrange
	var tile := Vector2i(6, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_02")
	instance.input_buffer[&"tool"] = 5.0
	var blocked_reason: String = ""
	_registry.building_blocked.connect(func(_id: String, r: String) -> void: blocked_reason = r)

	# Act
	_registry._on_ticks_advanced(1)

	# Assert — carrier reason takes priority check order: NPC → carrier → input
	assert_str(blocked_reason).is_equal("No carrier assigned (inputs)")


func test_failed_states_no_input_carrier_blocked_id_matches_building() -> void:
	# Arrange
	var tile := Vector2i(7, 10)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	_registry.assign_npc(bid, &"npc_03")
	instance.input_buffer[&"tool"] = 5.0
	var blocked_id: String = ""
	_registry.building_blocked.connect(func(id: String, _r: String) -> void: blocked_id = id)

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_str(blocked_id).is_equal(bid)


# =============================================================================
# AC-11: BLOCKED → OPERATING auto-recovery
# =============================================================================

func test_failed_states_blocked_recovers_when_npc_assigned() -> void:
	# Arrange — start BLOCKED (no NPC), then assign NPC
	var tile := Vector2i(5, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	instance.input_buffer[&"tool"] = 5.0
	_registry._on_ticks_advanced(1)  # → BLOCKED
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.BLOCKED)

	# Resolve — assign NPC
	_registry.assign_npc(bid, &"npc_04")

	# Act — next tick should attempt recovery
	_registry._on_ticks_advanced(1)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)
	assert_bool(instance.cycle_running).is_true()


func test_failed_states_blocked_recovery_emits_building_unblocked_signal() -> void:
	# Arrange
	var tile := Vector2i(6, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	instance.input_buffer[&"tool"] = 5.0
	_registry._on_ticks_advanced(1)  # → BLOCKED
	_registry.assign_npc(bid, &"npc_05")
	var unblocked_id: String = ""
	_registry.building_unblocked.connect(func(id: String) -> void: unblocked_id = id)

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_str(unblocked_id).is_equal(bid)


func test_failed_states_blocked_stays_blocked_when_inputs_still_missing() -> void:
	# Arrange — BLOCKED for missing inputs, nothing resolved
	var tile := Vector2i(7, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_06")
	# tool not in buffer → BLOCKED_NO_INPUT
	_registry._on_ticks_advanced(1)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.BLOCKED)

	# Act — another tick with nothing resolved
	_registry._on_ticks_advanced(1)

	# Assert — still BLOCKED
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.BLOCKED)
	assert_bool(instance.cycle_running).is_false()


func test_failed_states_blocked_recovers_when_tool_added_to_buffer() -> void:
	# Arrange — BLOCKED for missing inputs, then tool is added
	var tile := Vector2i(8, 15)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_07")
	_registry._on_ticks_advanced(1)  # → BLOCKED (no tool)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.BLOCKED)

	# Resolve — add tool to buffer directly (simulates carrier delivery)
	instance.input_buffer[&"tool"] = 5.0

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)
	assert_bool(instance.cycle_running).is_true()


# =============================================================================
# AC-12c: Output buffer full after cycle completes → OPERATING, output preserved
# =============================================================================

func test_failed_states_output_buffer_full_after_cycle_complete() -> void:
	# Arrange — cycle can run (NPC + input + carrier present)
	var tile := Vector2i(5, 20)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_08")
	instance.input_buffer[&"tool"] = 5.0
	_registry._on_ticks_advanced(1)    # start cycle
	assert_bool(instance.cycle_running).is_true()

	# Act — complete cycle (output_capacity = 20, produces 5 → buffer = 5, not full)
	_registry._on_ticks_advanced(100)

	# Assert — OPERATING; output preserved in buffer
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)
	assert_int(instance.buffered_output.get(&"wood", 0)).is_equal(5)


func test_failed_states_output_full_output_preserved_across_ticks() -> void:
	# Arrange — fill buffer to capacity by running four cycles (4×5 = 20)
	var tile := Vector2i(7, 20)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_10")
	instance.input_buffer[&"tool"] = 20.0  # enough for four cycles
	for _i in range(4):
		_registry._on_ticks_advanced(1)    # start cycle
		_registry._on_ticks_advanced(100)  # complete cycle
	assert_int(instance.buffered_output.get(&"wood", 0)).is_equal(20)

	# Act — advance many more ticks (OUTPUT_FULL prevents new cycles)
	_registry._on_ticks_advanced(500)

	# Assert — output still present, still OPERATING
	assert_int(instance.buffered_output.get(&"wood", 0)).is_equal(20)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


func test_failed_states_output_full_does_not_start_new_cycle() -> void:
	# Arrange — fill buffer to capacity (4×5 = 20 = output_capacity)
	var tile := Vector2i(8, 20)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_11")
	instance.input_buffer[&"tool"] = 20.0
	for _i in range(4):
		_registry._on_ticks_advanced(1)
		_registry._on_ticks_advanced(100)
	assert_int(instance.buffered_output.get(&"wood", 0)).is_equal(20)

	# Act — one more tick
	_registry._on_ticks_advanced(1)

	# Assert — no new cycle started
	assert_bool(instance.cycle_running).is_false()
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


# =============================================================================
# AC-14: collect_output clears buffer; next cycle can start
# =============================================================================

func test_failed_states_collect_output_clears_buffer() -> void:
	# Arrange — run a cycle to fill the buffer
	var tile := Vector2i(5, 25)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_12")
	instance.input_buffer[&"tool"] = 5.0
	_registry._on_ticks_advanced(1)
	_registry._on_ticks_advanced(100)
	assert_int(instance.buffered_output.get(&"wood", 0)).is_equal(5)

	# Act — carrier collects output
	var collected: Dictionary = _registry.collect_output(bid)

	# Assert — output returned, buffer cleared, still OPERATING
	assert_int(collected.get(&"wood", 0)).is_equal(5)
	assert_bool(instance.buffered_output.is_empty()).is_true()
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


func test_failed_states_after_collect_output_next_cycle_can_start() -> void:
	# Arrange — fill buffer, collect, provide more input
	var tile := Vector2i(7, 25)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_14")
	instance.input_buffer[&"tool"] = 10.0  # two cycles worth
	_registry._on_ticks_advanced(1)
	_registry._on_ticks_advanced(100)  # cycle 1 done
	_registry.collect_output(bid)      # buffer cleared

	# Act — next tick: cycle 2 can start
	_registry._on_ticks_advanced(1)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)
	assert_bool(instance.cycle_running).is_true()


func test_failed_states_collect_output_noop_when_not_stalled_and_buffer_empty() -> void:
	# Arrange — no output in buffer
	var tile := Vector2i(8, 25)
	var bid: String = _make_operating_lumber_camp(tile)

	# Act
	var collected: Dictionary = _registry.collect_output(bid)

	# Assert — empty dict, no crash
	assert_bool(collected.is_empty()).is_true()


# =============================================================================
# AC-23: Storage buildings never enter BLOCKED
# =============================================================================

func test_failed_states_storage_area_never_blocked_after_many_ticks() -> void:
	# Arrange
	var tile := Vector2i(5, 30)
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.COLLECTION_POINT, tile)
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	var count: int = _registry.get_building_count()
	var bid: String = str(count - 1)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)

	# Act — advance many ticks with no carrier or NPC
	_registry._on_ticks_advanced(1000)

	# Assert — still OPERATING, never BLOCKED
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


func test_failed_states_storage_building_never_stalled_after_construction() -> void:
	# Arrange
	_seed(&"wood", 8)
	_seed(&"stone", 2)
	var tile := Vector2i(6, 30)
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_BUILDING, tile)
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	var count: int = _registry.get_building_count()
	var bid: String = str(count - 1)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)

	# Act — complete construction and tick further
	_registry._on_ticks_advanced(120)  # build_time = 120
	_registry._on_ticks_advanced(500)

	# Assert — OPERATING
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


# =============================================================================
# building_state_changed signal emitted on all state transitions
# =============================================================================

func test_failed_states_state_changed_signal_emitted_on_blocked() -> void:
	# Arrange
	var tile := Vector2i(5, 35)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.input_buffer[&"tool"] = 5.0
	var signal_monitor := monitor_signals(_registry)

	# Act
	_registry._on_ticks_advanced(1)

	# Assert
	assert_signal_emitted(signal_monitor, "building_state_changed")


func test_failed_states_output_changed_signal_emitted_on_collect_output() -> void:
	# Arrange — run a cycle to put output in buffer
	var tile := Vector2i(6, 35)
	var bid: String = _make_operating_lumber_camp(tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance(bid)
	instance.input_carrier_ids = [&"mock_carrier"]
	instance.output_carrier_id = &"mock_carrier"
	_registry.assign_npc(bid, &"npc_15")
	instance.input_buffer[&"tool"] = 5.0
	_registry._on_ticks_advanced(1)
	_registry._on_ticks_advanced(100)
	var signal_monitor := monitor_signals(_registry)

	# Act
	_registry.collect_output(bid)

	# Assert
	assert_signal_emitted(signal_monitor, "building_output_changed")
