## Integration tests for PlayerCharacter action dispatch — Story 002.
## Covers AC1, AC2, AC11, AC13, AC14, AC16, AC18.
extends GdUnitTestSuite


# ---- Helpers ----------------------------------------------------------------

## Minimal stub for InventorySystem used in tool-availability tests.
class MockInventory extends Node:
	var usable_tool: bool = true

	func has_usable_tool() -> bool:
		return usable_tool


func _make_pc() -> PlayerCharacter:
	var pc := PlayerCharacter.new()
	add_child(pc)
	await pc.ready
	return pc


func _set_energy(pc: PlayerCharacter, value: int) -> void:
	## Drive energy pool to the requested value by restoring or spending.
	if value > pc.get_current_energy():
		pc._energy_pool.restore(value - pc.get_current_energy())
	elif value < pc.get_current_energy():
		pc._energy_pool.spend_unchecked(pc.get_current_energy() - value)


# ---- AC1: Action starts and energy is deducted ------------------------------

func test_ac1_chop_tree_starts_and_deducts_energy() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_int(result).is_equal(PlayerCharacter.StartResult.SUCCESS)
	assert_int(pc.get_action_state()).is_equal(PlayerCharacter.ActionSlot.State.WORKING)
	assert_int(pc.get_current_energy()).is_equal(88)  # 100 - 12 energy cost


func test_ac1_action_slot_filled_with_correct_tick_cost() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)

	pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_int(pc._action_slot.total_ticks).is_equal(80)
	assert_int(pc._action_slot.accumulated_ticks).is_equal(0)


func test_ac1_exact_energy_cost_starts_action() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 12)  # exact cost for CHOP_TREE

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_int(result).is_equal(PlayerCharacter.StartResult.SUCCESS)


func test_ac1_insufficient_energy_blocks_action() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 11)  # one below CHOP_TREE cost

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_int(result).is_equal(PlayerCharacter.StartResult.INSUFFICIENT_ENERGY)
	assert_int(pc.get_action_state()).is_equal(PlayerCharacter.ActionSlot.State.FREE)


func test_ac1_second_click_while_action_running_returns_blocked_slot() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	assert_int(result).is_equal(PlayerCharacter.StartResult.BLOCKED_SLOT)


# ---- AC2: Action completes at tick cost, resource output generated ----------

func test_ac2_action_complete_when_ticks_reach_total() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)

	pc._action_slot.accumulated_ticks = 80  # reach tick cost directly

	assert_bool(pc._action_slot.is_complete()).is_true()


func test_ac2_complete_action_frees_slot_and_emits_signal() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)
	var completed_spy := monitor_signals(pc)

	pc._action_slot.accumulated_ticks = 80
	pc._on_ticks_advanced(0)  # trigger completion check

	assert_int(pc.get_action_state()).is_equal(PlayerCharacter.ActionSlot.State.FREE)
	assert_signal_emitted(completed_spy, "action_completed")


func test_ac2_output_5_wood_on_normal_chop() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)
	var received_output: Array = []
	pc.action_completed.connect(func(_id: int, out: Array) -> void:
		received_output = out)

	pc._action_slot.accumulated_ticks = 80
	pc._on_ticks_advanced(0)

	assert_int(received_output.size()).is_equal(1)
	assert_str(String(received_output[0].resource_id)).is_equal("wood")
	assert_int(received_output[0].quantity).is_equal(5)


func test_ac2_depleted_output_halved_min_1() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 0)  # depleted — output modifier applies
	pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)
	var received_output: Array = []
	pc.action_completed.connect(func(_id: int, out: Array) -> void:
		received_output = out)

	pc._action_slot.accumulated_ticks = 160  # depleted tick cost (80 * 2)
	pc._on_ticks_advanced(0)

	assert_int(received_output[0].quantity).is_equal(3)  # ceil(5 * 0.5) = 3


# ---- AC2 (continued): Progress update signal during partial tick advance ----

func test_ac2_progress_update_emitted_during_partial_advance() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)
	var spy := monitor_signals(pc)

	pc._on_ticks_advanced(40)  # half of the 80-tick cost

	assert_signal_emitted(spy, "action_progress_update")
	assert_int(pc.get_action_state()).is_equal(PlayerCharacter.ActionSlot.State.WORKING)


func test_ac2_progress_update_reports_correct_progress_value() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)
	var received_progress: float = -1.0
	pc.action_progress_update.connect(func(p: float, _tc: int, _o: int) -> void:
		received_progress = p)

	pc._on_ticks_advanced(20)  # 20/80 = 0.25

	assert_float(received_progress).is_equal_approx(0.25, 0.001)


# ---- AC11: Cost preview at normal energy ------------------------------------

func test_ac11_cost_preview_chop_tree_normal_energy() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 50)

	var preview := pc.get_cost_preview(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_bool(preview.blocked).is_false()
	assert_int(preview.energy_cost).is_equal(12)
	assert_int(preview.tick_cost).is_equal(80)
	assert_int(preview.output_qty).is_equal(5)
	assert_str(String(preview.output_resource)).is_equal("wood")
	assert_bool(preview.depleted).is_false()


func test_ac11_cost_preview_pick_berries_normal_energy() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 50)

	var preview := pc.get_cost_preview(PlayerCharacter.ManualActionType.PICK_BERRIES)

	assert_int(preview.energy_cost).is_equal(5)
	assert_int(preview.tick_cost).is_equal(40)
	assert_int(preview.output_qty).is_equal(3)


# ---- AC13: Food consumption clamps energy at max ----------------------------

func test_ac13_bread_at_95_energy_clamps_to_100() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 95)

	pc.consume_food(&"bread")

	assert_int(pc.get_current_energy()).is_equal(100)


func test_ac13_bread_at_91_energy_clamps_to_100() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 91)

	pc.consume_food(&"bread")

	assert_int(pc.get_current_energy()).is_equal(100)


func test_ac13_food_consumed_signal_emitted() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 50)
	var spy := monitor_signals(pc)

	pc.consume_food(&"bread")

	assert_signal_emitted(spy, "food_consumed")


func test_ac13_bread_at_0_energy_restores_25() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 0)

	pc.consume_food(&"bread")

	assert_int(pc.get_current_energy()).is_equal(25)


func test_ac13_berry_restores_10_energy() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 60)

	pc.consume_food(&"berry")

	assert_int(pc.get_current_energy()).is_equal(70)


# ---- AC14: Cost preview at 0 energy shows depleted values -------------------

func test_ac14_cost_preview_chop_tree_at_0_energy_doubled_ticks() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 0)

	var preview := pc.get_cost_preview(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_bool(preview.depleted).is_true()
	assert_int(preview.tick_cost).is_equal(160)  # 80 * 2


func test_ac14_cost_preview_chop_tree_at_0_energy_halved_output() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 0)

	var preview := pc.get_cost_preview(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_int(preview.output_qty).is_equal(3)  # ceil(5 * 0.5)


func test_ac14_cost_preview_berries_at_0_energy() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 0)

	var preview := pc.get_cost_preview(PlayerCharacter.ManualActionType.PICK_BERRIES)

	assert_int(preview.tick_cost).is_equal(80)   # 40 * 2
	assert_int(preview.output_qty).is_equal(2)   # ceil(3 * 0.5) = 2


func test_ac14_depleted_action_still_starts() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 0)

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	assert_int(result).is_equal(PlayerCharacter.StartResult.SUCCESS)


func test_ac14_depleted_action_has_doubled_tick_cost() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 0)
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	assert_int(pc._action_slot.total_ticks).is_equal(80)  # 40 * 2


# ---- AC16: Tool-requiring action blocked without tool -----------------------

func test_ac16_chop_tree_blocked_when_no_tool() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	var mock_inv := MockInventory.new()
	mock_inv.usable_tool = false
	add_child(mock_inv)
	pc._inventory = mock_inv

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_int(result).is_equal(PlayerCharacter.StartResult.TOOL_REQUIRED)


func test_ac16_mine_stone_blocked_when_no_tool() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	var mock_inv := MockInventory.new()
	mock_inv.usable_tool = false
	add_child(mock_inv)
	pc._inventory = mock_inv

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.MINE_STONE)

	assert_int(result).is_equal(PlayerCharacter.StartResult.TOOL_REQUIRED)


func test_ac16_cost_preview_shows_blocked_when_no_tool() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	var mock_inv := MockInventory.new()
	mock_inv.usable_tool = false
	add_child(mock_inv)
	pc._inventory = mock_inv

	var preview := pc.get_cost_preview(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_bool(preview.blocked).is_true()
	assert_str(preview.reason).is_equal("No tool available — craft one first")


func test_ac16_chop_tree_succeeds_when_tool_available() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	var mock_inv := MockInventory.new()
	mock_inv.usable_tool = true
	add_child(mock_inv)
	pc._inventory = mock_inv

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.CHOP_TREE)

	assert_int(result).is_equal(PlayerCharacter.StartResult.SUCCESS)


func test_ac16_craft_tool_does_not_require_tool() -> void:
	var pc := await _make_pc()
	_set_energy(pc, 100)
	var mock_inv := MockInventory.new()
	mock_inv.usable_tool = false
	add_child(mock_inv)
	pc._inventory = mock_inv

	var result := pc.try_start_action(PlayerCharacter.ManualActionType.CRAFT_TOOL)

	assert_int(result).is_not_equal(PlayerCharacter.StartResult.TOOL_REQUIRED)


# ---- AC18: Camera movement not blocked by PlayerCharacter -------------------

func test_ac18_player_character_has_no_wasd_input_handling() -> void:
	## Structural check: PlayerCharacter must NOT override _input() or _unhandled_input()
	## for WASD keys. Camera movement is owned by the Input System + CameraController.
	var pc := await _make_pc()
	## PlayerCharacter processes tile clicks and drag events, not WASD.
	## Verify there is no _input method that would intercept movement keys.
	assert_bool(pc.has_method("_input")).is_false()


func test_ac18_camera_movement_not_affected_by_depletion_state() -> void:
	## Structural check: at 0 energy, PlayerCharacter still does not own WASD input.
	var pc := await _make_pc()
	_set_energy(pc, 0)
	assert_bool(pc.has_method("_input")).is_false()


func test_ac18_camera_movement_not_affected_by_running_action() -> void:
	## Structural check: with an action running, PlayerCharacter still does not own WASD.
	var pc := await _make_pc()
	_set_energy(pc, 100)
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)
	assert_bool(pc.has_method("_input")).is_false()
