## gdUnit4 test suite for Story 001 (PC-01): Energy Pool.
##
## AC1: Energy pool clamps to [0, 100] on all operations
## AC2: try_spend returns false when insufficient, true+deducts when sufficient
## AC3: spend_unchecked always succeeds, clamps to 0
## AC4: is_depleted returns true only when current == 0
## AC5: get_depletion_modifier returns correct multipliers

extends GdUnitTestSuite


func _make_pool() -> PlayerCharacter.EnergyPool:
	var pc := PlayerCharacter.new()
	add_child(pc)
	auto_free(pc)
	return pc._energy_pool


# ---- AC1: clamp to [0, max] on all operations ----

func test_energy_pool_restore_200_with_max_100_clamps_to_100() -> void:
	# Arrange
	var pool := _make_pool()
	pool.current = 0

	# Act
	pool.restore(200)

	# Assert
	assert_int(pool.current).is_equal(100)


func test_energy_pool_restore_partial_clamps_at_max() -> void:
	# Arrange — current=70, restoring 50 would exceed 100
	var pool := _make_pool()
	pool.current = 70

	# Act
	pool.restore(50)

	# Assert
	assert_int(pool.current).is_equal(100)


func test_energy_pool_spend_unchecked_200_from_50_clamps_to_0() -> void:
	# Arrange
	var pool := _make_pool()
	pool.current = 50

	# Act
	pool.spend_unchecked(200)

	# Assert
	assert_int(pool.current).is_equal(0)


# ---- AC2: try_spend ----

func test_energy_pool_try_spend_returns_false_when_insufficient() -> void:
	# Arrange
	var pool := _make_pool()
	pool.current = 50

	# Act
	var result: bool = pool.try_spend(60)

	# Assert
	assert_bool(result).is_false()
	assert_int(pool.current).is_equal(50)


func test_energy_pool_try_spend_returns_true_and_deducts_when_sufficient() -> void:
	# Arrange
	var pool := _make_pool()
	pool.current = 50

	# Act
	var result: bool = pool.try_spend(30)

	# Assert
	assert_bool(result).is_true()
	assert_int(pool.current).is_equal(20)


func test_energy_pool_try_spend_exact_amount_drains_to_zero() -> void:
	# Arrange — try_spend(50) with current=50 → returns true, current=0
	var pool := _make_pool()
	pool.current = 50

	# Act
	var result: bool = pool.try_spend(50)

	# Assert
	assert_bool(result).is_true()
	assert_int(pool.current).is_equal(0)


func test_energy_pool_try_spend_1_from_0_returns_false() -> void:
	# Arrange — energy already depleted
	var pool := _make_pool()
	pool.current = 0

	# Act
	var result: bool = pool.try_spend(1)

	# Assert
	assert_bool(result).is_false()
	assert_int(pool.current).is_equal(0)


# ---- AC3: spend_unchecked always succeeds ----

func test_energy_pool_spend_unchecked_always_succeeds_no_error() -> void:
	# Arrange
	var pool := _make_pool()
	pool.current = 50

	# Act — should not throw or fail
	pool.spend_unchecked(200)

	# Assert
	assert_int(pool.current).is_equal(0)


func test_energy_pool_spend_unchecked_zero_is_no_op() -> void:
	# Arrange
	var pool := _make_pool()
	pool.current = 50

	# Act
	pool.spend_unchecked(0)

	# Assert
	assert_int(pool.current).is_equal(50)


# ---- AC4: is_depleted ----

func test_energy_pool_is_depleted_returns_true_at_zero() -> void:
	# Arrange
	var pool := _make_pool()
	pool.current = 0

	# Act / Assert
	assert_bool(pool.is_depleted()).is_true()


func test_energy_pool_is_depleted_returns_false_at_one() -> void:
	var pool := _make_pool()
	pool.current = 1
	assert_bool(pool.is_depleted()).is_false()


func test_energy_pool_is_depleted_returns_false_at_100() -> void:
	var pool := _make_pool()
	# current starts at 100
	assert_bool(pool.is_depleted()).is_false()


func test_energy_pool_is_depleted_flips_after_full_spend() -> void:
	# Arrange — confirm not depleted, then drain to 0
	var pool := _make_pool()
	pool.current = 1
	assert_bool(pool.is_depleted()).is_false()

	# Act
	pool.spend_unchecked(1)

	# Assert
	assert_bool(pool.is_depleted()).is_true()


# ---- AC5: get_depletion_modifier ----

func test_energy_pool_get_depletion_modifier_when_depleted_returns_2x_tick_05x_output() -> void:
	# Arrange
	var pool := _make_pool()
	pool.current = 0

	# Act
	var mod: PlayerCharacter.DepletionMod = pool.get_depletion_modifier()

	# Assert
	assert_float(mod.tick_multiplier).is_equal_approx(2.0, 0.001)
	assert_float(mod.output_multiplier).is_equal_approx(0.5, 0.001)


func test_energy_pool_get_depletion_modifier_when_not_depleted_returns_1x_1x() -> void:
	# Arrange — current=50 (not depleted)
	var pool := _make_pool()
	pool.current = 50

	# Act
	var mod: PlayerCharacter.DepletionMod = pool.get_depletion_modifier()

	# Assert
	assert_float(mod.tick_multiplier).is_equal_approx(1.0, 0.001)
	assert_float(mod.output_multiplier).is_equal_approx(1.0, 0.001)
