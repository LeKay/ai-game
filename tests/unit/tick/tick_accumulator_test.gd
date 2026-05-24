## gdUnit4 test suite for Story 001: Tick Accumulator Core.
##
## Covers AC-1 through AC-4 of the Tick System foundation story.
## Each test creates its own TickSystem instance inside a NodeContainer
## so _process() fires without a running scene.

extends GdUnitTestSuite

const TickSystem := preload("res://src/systems/tick_system.gd")


# ---- Helpers ----

## Spawn a TickSystem and configure it for testing.
func _make_system() -> Node:
	var system := TickSystem.new()
	# Story 002 stub: _is_paused defaults to true, so _process() is disabled.
	# Enable processing directly since set_paused() belongs to Story 002.
	system.set_process(true)
	# TODO: Replace with system.set_paused(false) once Story 002 implements set_paused().
	system._is_paused = false
	# Register for automatic cleanup
	auto_free(system)
	return system


# ---- AC-1: 100 seconds at 1x = 1000 ticks ----

func test_tick_accumulator_hundred_seconds_thousand_ticks():
	var system := _make_system()
	system.speed_multiplier = 1.0

	# Simulate 99 frames with delta = 1.0s each (990 ticks, just under day boundary).
	for _i in range(99):
		system._process(1.0)

	assert_int(system.get_tick_count()).is_equal(990)


# ---- AC-1 variant: different FPS yields same result ----

func test_tick_accumulator_frame_rate_independent_60fps():
	var system := _make_system()
	system.speed_multiplier = 1.0

	# 60fps: 1000 ticks in 100s → delta = 100/6000 ≈ 0.0166667
	var delta := 100.0 / 6000.0
	for _i in range(6000):
		system._process(delta)

	# Allow ±1 tick tolerance due to floating point accumulation
	assert_int(system.get_tick_count()).is_between(999, 1000)


func test_tick_accumulator_frame_rate_independent_144fps():
	var system := _make_system()
	system.speed_multiplier = 1.0

	# 144fps: 1000 ticks in ~100s → delta = 100/14400 ≈ 0.0069444
	var delta := 100.0 / 14400.0
	for _i in range(14400):
		system._process(delta)

	# Allow ±1 tick tolerance due to floating point accumulation
	assert_int(system.get_tick_count()).is_between(999, 1000)


func test_tick_accumulator_frame_rate_independent_30fps():
	var system := _make_system()
	system.speed_multiplier = 1.0

	# 99.9s at 1x → 999 ticks (just under day boundary).
	var delta := 99.9 / 3000.0
	for _i in range(3000):
		system._process(delta)

	assert_int(system.get_tick_count()).is_equal(999)


# ---- AC-2: Lag spike clamping ----

func test_tick_accumulator_lag_spike_clamped_to_100():
	var system := _make_system()
	system.speed_multiplier = 1.0

	# 10s lag spike → raw_ticks = 10 * 10 * 1.0 = 100 → already under cap
	system._process(10.0)
	assert_int(system.get_tick_count()).is_equal(100)

	var system2 := _make_system()
	system2.speed_multiplier = 1.0

	# 20s lag spike → raw_ticks = 200 → clamped to 100
	system2._process(20.0)
	assert_int(system2.get_tick_count()).is_equal(100)


func test_tick_accumulator_speed_2x_under_cap():
	var system := _make_system()
	system.speed_multiplier = 2.0

	system._process(1.0)  # 1s * 10 * 2 = 20 ticks (under cap of 100)
	assert_int(system.get_tick_count()).is_equal(20)


func test_tick_accumulator_zero_delta_no_ticks():
	var system := _make_system()
	system.speed_multiplier = 1.0

	system._process(0.0)
	assert_int(system.get_tick_count()).is_equal(0)


func test_tick_accumulator_negative_delta_treated_as_zero():
	var system := _make_system()
	system.speed_multiplier = 1.0

	system._process(-1.0)
	assert_int(system.get_tick_count()).is_equal(0)


func test_tick_accumulator_nan_delta_treated_as_zero():
	var system := _make_system()
	system.speed_multiplier = 1.0

	system._process(NAN)
	assert_int(system.get_tick_count()).is_equal(0)


func test_tick_accumulator_speed_zero_produces_zero_ticks():
	var system := _make_system()
	# Story 002 clamps speed_multiplier via set_speed — use direct field to test
	# the accumulator at raw 0x multiplier (setter would clamp to 0.5).
	system._speed_multiplier = 0.0

	system._process(10.0)
	assert_int(system.get_tick_count()).is_equal(0)


# ---- AC-3: Signal emission ----

func test_tick_accumulator_signal_emits_correct_count():
	var system := _make_system()
	system.speed_multiplier = 1.0

	var result := [0, -1]  # [emissions, count]

	var _callback = func(count: int):
		result[0] += 1
		result[1] = count

	system.ticks_advanced.connect(_callback)
	system._process(1.0)  # 1s * 10 = 10 ticks

	assert_int(result[0]).is_equal(1)
	assert_int(result[1]).is_equal(10)


func test_tick_accumulator_no_signal_on_zero_ticks():
	var system := _make_system()
	system.speed_multiplier = 1.0

	var result := [0]  # [emissions]
	system.ticks_advanced.connect(func(_count: int): result[0] += 1)
	system._process(0.001)  # < 1 tick → no emission

	assert_int(result[0]).is_equal(0)


func test_tick_accumulator_signal_emits_once_for_batched_ticks():
	var system := _make_system()
	system.speed_multiplier = 1.0

	var result := [0, 0]  # [emissions, count]
	system.ticks_advanced.connect(func(count: int):
		result[0] += 1
		result[1] = count
	)
	system._process(10.0)  # 10s * 10 = 100 ticks (at cap)

	assert_int(result[0]).is_equal(1)
	assert_int(result[1]).is_equal(100)


# ---- AC-4: Remainder carry ----

func test_tick_accumulator_remainder_carry_prevents_drift():
	var system := _make_system()
	system.speed_multiplier = 1.0

	# Set initial remainder to 0.7.
	system.set_tick_remainder(0.7)

	# Frame with delta = 0.05s → raw_ticks = 0.05 * 10 * 1.0 = 0.5
	# Combined: 0.7 + 0.5 = 1.2 → tick_delta = 1, new_remainder = 0.2
	system._process(0.05)

	assert_int(system.get_tick_count()).is_equal(1)
	assert_float(system.get_tick_remainder()).is_equal_approx(0.2, 0.001)


func test_tick_accumulator_remainder_high_value_carry():
	var system := _make_system()
	system.speed_multiplier = 1.0

	# remainder = 0.999, delta = 0.02s → raw = 0.2
	# Combined: 1.199 → tick_delta = 1, remainder = 0.199
	system.set_tick_remainder(0.999)
	system._process(0.02)

	assert_int(system.get_tick_count()).is_equal(1)
	assert_float(system.get_tick_remainder()).is_equal_approx(0.199, 0.001)


# Note: Pause lifecycle tests (set_paused, is_processing) belong in Story 002 test suite.
