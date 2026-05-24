## gdUnit4 test suite for Story 002: Speed Modes and Pause State Machine.
##
## Covers AC-1 through AC-7 of the Tick System speed/pause story.
## Each test creates its own TickSystem instance in isolation
## so _process() fires without a running scene.

extends GdUnitTestSuite

const TickSystem := preload("res://src/systems/tick_system.gd")


# ---- Helpers ----

## Spawn a running TickSystem instance, auto-freed after the test.
func _make_running_system() -> TickSystem:
	var system := TickSystem.new()
	system.set_process(true)
	system.set_pause(false)
	system.set_tick_remainder(0.0)
	auto_free(system)
	return system


# ---- AC-1: PAUSED = no tick accumulation ----

func test_pause_no_accumulation() -> void:
	var system := TickSystem.new()
	system.set_pause(true)
	auto_free(system)

	# Verify ticks_advanced signal is NOT emitted during pause.
	var signal_triggered := [false]
	system.ticks_advanced.connect(func(_d: int): signal_triggered[0] = true)

	assert_bool(system.is_paused())
	assert_int(system.get_tick_count()).is_equal(0)

	# Simulate _process calls while paused — nothing accumulates.
	system._process(1.0)
	system._process(1.0)
	system._process(1.0)

	assert_int(system.get_tick_count()).is_equal(0)
	assert_bool(signal_triggered[0]).is_equal(false)


# ---- AC-2: 2x speed doubles accumulation rate ----

func test_speed_2x_50s_1000_ticks() -> void:
	var system := _make_running_system()
	system.set_speed(2.0)
	assert_float(system.speed_multiplier).is_equal(2.0)

	# 49 seconds of simulated time at 2x = 980 ticks (just under day boundary).
	for _i in range(49):
		system._process(1.0)

	assert_int(system.get_tick_count()).is_equal(980)


# ---- AC-3: 0.5x speed halves accumulation rate ----

func test_speed_05x_200s_1000_ticks() -> void:
	var system := _make_running_system()
	system.set_speed(0.5)
	assert_float(system.speed_multiplier).is_equal(0.5)

	# 199 seconds of simulated time at 0.5x = 995 ticks (just under day boundary).
	for _i in range(199):
		system._process(1.0)

	assert_int(system.get_tick_count()).is_equal(995)


# ---- AC-4: No duplicate speed_changed signals ----

func test_no_duplicate_speed_signals() -> void:
	var system := TickSystem.new()
	system.set_process(true)
	auto_free(system)

	# Start at neutral speed.
	system.set_speed(1.0)

	var state := [0]  # [signal_count] — array captured by reference (GDScript lambda quirk)
	system.speed_changed.connect(func(_new_speed: float): state[0] += 1)

	# Set to 1.0 multiple times — should NOT emit (same value = no-op).
	system.set_speed(1.0)
	system.set_speed(1.0)
	system.set_speed(1.0)

	assert_int(state[0]).is_equal(0)

	# Now change speed — should emit exactly once.
	system.set_speed(2.0)
	assert_int(state[0]).is_equal(1)

	# Switch back — emit again.
	system.set_speed(0.5)
	assert_int(state[0]).is_equal(2)


# ---- AC-5: Pause stability under rapid toggle ----

func test_rapid_pause_toggle_stability() -> void:
	var system := TickSystem.new()
	system.set_process(true)
	system.set_pause(false)
	system.set_tick_remainder(0.0)
	auto_free(system)

	# 10 toggles: running, paused, running, paused, ... (5 running, 5 paused).
	for i in range(10):
		if i % 2 == 0:  # even frames: running
			system.set_pause(false)
		else:  # odd frames: paused
			system.set_pause(true)
		system._process(1.0)

	# Only 5 frames ran while unpaused → 5 seconds × 10 ticks/sec = 50 ticks.
	assert_int(system.get_tick_count()).is_equal(50)


# ---- AC-6: Idempotent set_pause(true) when already paused ----

func test_idempotent_set_pause_already_paused() -> void:
	var system := TickSystem.new()
	system.set_pause(true)
	auto_free(system)

	var state := [0]  # [signal_count] — array for GDScript lambda capture
	system.pause_state_changed.connect(func(_is_paused: bool): state[0] += 1)

	# Call set_pause(true) while already paused — should NOT emit.
	system.set_pause(true)
	system.set_pause(true)
	system.set_pause(true)

	assert_int(state[0]).is_equal(0)

	# Pause again — signal fires once.
	system.set_pause(false)
	assert_int(state[0]).is_equal(1)
	assert_bool(system.is_paused()).is_equal(false)

	# Unpause again — signal fires once more.
	system.set_pause(true)
	assert_int(state[0]).is_equal(2)
	assert_bool(system.is_paused()).is_equal(true)


# ---- AC-7: Invalid speed clamps to nearest valid option ----

func test_invalid_speed_clamps_to_options() -> void:
	var system := TickSystem.new()
	system.set_process(true)
	system.set_pause(false)
	auto_free(system)

	# Start at 2.0 so subsequent clamped values differ → signals fire.
	system.set_speed(2.0)

	var signal_state := [0]  # [signal_count]
	system.speed_changed.connect(func(_new_speed: float): signal_state[0] += 1)

	# 1.5 → equidistant from 1.0 and 2.0 → clamps to 1.0 (first-index-wins tie-break).
	system.set_speed(1.5)
	assert_float(system.speed_multiplier).is_equal(1.0)
	assert_int(signal_state[0]).is_equal(1)

	# 0.0 → clamps to 0.5 (nearest option).
	system.set_speed(0.0)
	assert_float(system.speed_multiplier).is_equal(0.5)
	assert_int(signal_state[0]).is_equal(2)

	# 99.0 → clamps to 2.0 (nearest option).
	system.set_speed(99.0)
	assert_float(system.speed_multiplier).is_equal(2.0)
	assert_int(signal_state[0]).is_equal(3)

	# NaN → keeps old value, no signal.
	var old_speed: float = system.speed_multiplier
	system.set_speed(NAN)
	assert_float(system.speed_multiplier).is_equal(old_speed)

	# Negative → clamps to 0.5 (nearest option).
	system.set_speed(-5.0)
	assert_float(system.speed_multiplier).is_equal(0.5)


# ---- ticks_advanced positive signal emission ----

func test_ticks_advanced_signal_emits_with_correct_delta() -> void:
	var system := _make_running_system()
	system.set_speed(1.0)

	var captured_delta := [-1]  # [delta_ticks] — array captured by reference
	system.ticks_advanced.connect(func(d: int): captured_delta[0] = d)

	# 1 second at 1x → 10 ticks.
	system._process(1.0)

	assert_int(system.get_tick_count()).is_equal(10)
	assert_int(captured_delta[0]).is_equal(10)

# ---- Remainder preservation across pause/unpause cycle ----

func test_remainder_preserved_across_pause_unpause() -> void:
	var system := TickSystem.new()
	system.set_process(true)
	system.set_pause(false)
	system.set_tick_remainder(0.7)
	system.set_speed(1.0)
	auto_free(system)

	# Frame 1: accumulate some ticks while running.
	system._process(1.0)
	var ticks_after_frame1: int = system.get_tick_count()
	var remainder_after_frame1: float = system.get_tick_remainder()

	# Frame 2: pause — remainder must not change.
	system.set_pause(true)
	system._process(1.0)
	assert_float(system.get_tick_remainder()).is_equal(remainder_after_frame1)

	# Frame 3: unpause — accumulate more ticks.
	system.set_pause(false)
	system._process(1.0)
	var ticks_after_frame3: int = system.get_tick_count()

	# Total ticks after frame 3 should equal what you'd get without pausing:
	# both frame 1 and frame 3 had identical inputs (1.0s delta, 1.0x speed).
	assert_int(ticks_after_frame3 - ticks_after_frame1).is_equal(ticks_after_frame1)


# ---- set_pause() public API exercises ----

func test_set_pause_public_api() -> void:
	var system := TickSystem.new()
	system.set_pause(false)  # enables set_process via public API
	auto_free(system)

	# Initial state: not paused, process enabled.
	assert_bool(system.is_paused()).is_equal(false)

	var signal_state := [0]  # [signal_count]
	system.pause_state_changed.connect(func(_is_paused: bool): signal_state[0] += 1)

	# Pause via public API: process disabled, signal fires.
	system.set_pause(true)
	assert_bool(system.is_paused()).is_equal(true)
	assert_int(signal_state[0]).is_equal(1)

	# Idempotent set_pause(true) when already paused — should NOT emit.
	system.set_pause(true)
	assert_int(signal_state[0]).is_equal(1)

	# Unpause via public API: process enabled, signal fires again.
	system.set_pause(false)
	assert_bool(system.is_paused()).is_equal(false)
	assert_int(signal_state[0]).is_equal(2)
