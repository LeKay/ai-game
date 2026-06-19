## gdUnit4 test suite for Story 004 (PC-04): Depletion Penalty and Food Refill.
##
## AC5: At 0 Energy actions start with depletion penalty; non-zero insufficient → BLOCKED
## AC6: Food consumption restores energy (berry +10, bread +25), clamped to max
## AC7: Depletion penalty — tick cost × 2, output = max(1, ceil(base × 0.5))
## AC8: Actions started before depletion are immune to retroactive penalty
## AC9: Day transition does not interrupt a running action

extends GdUnitTestSuite


func _make_pc() -> PlayerCharacter:
	var pc := PlayerCharacter.new()
	add_child(pc)
	auto_free(pc)
	return pc


# ---- AC5: Depleted (0 energy) allows actions; non-zero insufficient blocks ----

func test_try_start_action_at_zero_energy_returns_success() -> void:
	# Arrange — depleted player attempts PICK_BERRIES (energy_cost = 5)
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	var result: int = pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	# Assert
	assert_int(result).is_equal(PlayerCharacter.StartResult.SUCCESS)


func test_try_start_action_insufficient_nonzero_energy_returns_blocked() -> void:
	# Arrange — 3 energy, action costs 5 → should be blocked (not depleted, not sufficient)
	var pc := _make_pc()
	pc._energy_pool.current = 3

	# Act
	var result: int = pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	# Assert
	assert_int(result).is_equal(PlayerCharacter.StartResult.INSUFFICIENT_ENERGY)


func test_try_start_action_sufficient_energy_returns_success() -> void:
	# Arrange — 50 energy, action costs 5 → normal start
	var pc := _make_pc()
	pc._energy_pool.current = 50

	# Act
	var result: int = pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	# Assert
	assert_int(result).is_equal(PlayerCharacter.StartResult.SUCCESS)


func test_try_start_action_at_zero_energy_does_not_drain_below_zero() -> void:
	# Arrange — at 0 energy, spend_unchecked clamps to 0
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	# Assert — energy stays at 0
	assert_int(pc._energy_pool.current).is_equal(0)


# ---- AC6: Food consumption restores energy ----

func test_consume_food_berry_restores_ten_energy() -> void:
	# Arrange
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	var ok: bool = pc.consume_food(&"berry")

	# Assert
	assert_bool(ok).is_true()
	assert_int(pc._energy_pool.current).is_equal(10)


func test_consume_food_bread_restores_fifty_energy() -> void:
	# Arrange — bread nutrition 5.0 × ENERGY_PER_NUTRITION 10 = 50
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	var ok: bool = pc.consume_food(&"bread")

	# Assert
	assert_bool(ok).is_true()
	assert_int(pc._energy_pool.current).is_equal(50)


func test_consume_food_clamps_to_max_energy() -> void:
	# Arrange — eating bread at 95 should cap at 100
	var pc := _make_pc()
	pc._energy_pool.current = 95

	# Act
	pc.consume_food(&"bread")

	# Assert
	assert_int(pc._energy_pool.current).is_equal(100)


func test_consume_food_at_full_energy_returns_false_and_does_not_consume() -> void:
	# Arrange — energy already at max; eating would waste the food
	var pc := _make_pc()
	pc._energy_pool.current = 100

	# Act
	var ok: bool = pc.consume_food(&"bread")

	# Assert — rejected so the caller refunds the item; energy unchanged
	assert_bool(ok).is_false()
	assert_int(pc._energy_pool.current).is_equal(100)


func test_consume_food_unknown_type_returns_false() -> void:
	# Arrange
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	var ok: bool = pc.consume_food(&"raw_fish")

	# Assert
	assert_bool(ok).is_false()
	assert_int(pc._energy_pool.current).is_equal(0)


func test_consume_food_emits_food_consumed_signal() -> void:
	# Arrange
	var pc := _make_pc()
	pc._energy_pool.current = 0
	var emitted_type: StringName = &""
	var emitted_amount: int = 0
	pc.food_consumed.connect(func(ft: StringName, amt: int) -> void:
		emitted_type = ft
		emitted_amount = amt
	)

	# Act
	pc.consume_food(&"berry")

	# Assert
	assert_str(emitted_type).is_equal("berry")
	assert_int(emitted_amount).is_equal(10)


func test_consume_food_slot_remains_free_after_eating() -> void:
	# Arrange — eating is instantaneous; slot must stay FREE so multiple items can be eaten
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	var ok: bool = pc.consume_food(&"berry")

	# Assert
	assert_bool(ok).is_true()
	assert_int(pc._action_slot.state).is_equal(PlayerCharacter.ActionSlot.State.FREE)


func test_consume_food_blocked_returns_false_when_slot_occupied() -> void:
	# Arrange — start a running action, then attempt to eat
	var pc := _make_pc()
	pc._energy_pool.current = 100
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	# Act
	var ok: bool = pc.consume_food(&"berry")

	# Assert — slot occupied, eat blocked, energy unchanged since PICK_BERRIES already spent 5
	assert_bool(ok).is_false()
	assert_int(pc._energy_pool.current).is_equal(95)


# ---- AC7: Depletion penalty doubles tick cost, halves output (min 1) ----

func test_try_start_action_depletion_doubles_tick_cost() -> void:
	# Arrange — PICK_BERRIES base_tick = 40; depleted → 40 × 2 = 80
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	# Assert
	assert_int(pc._action_slot.total_ticks).is_equal(80)


func test_try_start_action_depletion_halves_output_rounded_up() -> void:
	# Arrange — PICK_BERRIES base_output = 3; ceil(3 × 0.5) = 2
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	# Assert
	assert_int(pc._action_slot.effective_output).is_equal(2)


func test_try_start_action_depletion_output_minimum_one() -> void:
	# Arrange — FORAGE base_output = 1; max(1, ceil(1 × 0.5)) = max(1, 1) = 1
	var pc := _make_pc()
	pc._energy_pool.current = 0

	# Act
	pc.try_start_action(PlayerCharacter.ManualActionType.FORAGE)

	# Assert
	assert_int(pc._action_slot.effective_output).is_equal(1)


func test_try_start_action_no_penalty_when_energy_sufficient() -> void:
	# Arrange — PICK_BERRIES base_tick = 40; full energy → no penalty
	var pc := _make_pc()
	pc._energy_pool.current = 100

	# Act
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)

	# Assert
	assert_int(pc._action_slot.total_ticks).is_equal(40)
	assert_int(pc._action_slot.effective_output).is_equal(3)


# ---- AC8: Effective values locked at action start — immune to later energy changes ----

func test_try_start_action_full_energy_slot_values_unchanged_after_drain() -> void:
	# Arrange — start action at full energy (no penalty), then drain to 0
	var pc := _make_pc()
	pc._energy_pool.current = 100

	# Act — start action (locks tick=40, output=3)
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)
	var locked_ticks: int = pc._action_slot.total_ticks
	var locked_output: int = pc._action_slot.effective_output

	# Drain energy to 0 mid-action
	pc._energy_pool.spend_unchecked(100)

	# Assert — slot values unchanged (depletion penalty does not retroactively apply)
	assert_int(pc._action_slot.total_ticks).is_equal(locked_ticks)
	assert_int(pc._action_slot.effective_output).is_equal(locked_output)
	assert_int(pc._action_slot.total_ticks).is_equal(40)
	assert_int(pc._action_slot.effective_output).is_equal(3)


# ---- AC9: Day transition does not interrupt a running action ----

func test_day_transition_does_not_reset_action_slot() -> void:
	# Arrange — start action and advance some ticks
	var pc := _make_pc()
	pc._energy_pool.current = 100
	pc.try_start_action(PlayerCharacter.ManualActionType.PICK_BERRIES)
	pc._action_slot.accumulated_ticks = 20

	# Act — fire day transition
	pc._on_day_transition(1)

	# Assert — action still in progress, accumulated ticks unchanged
	assert_int(pc._action_slot.state).is_equal(PlayerCharacter.ActionSlot.State.WORKING)
	assert_int(pc._action_slot.accumulated_ticks).is_equal(20)
