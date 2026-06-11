## gdUnit4 test suite for Story 003: Manual Action Tick Advancement.
##
## Tests `advance_ticks_manual()` covering AC-1 through AC-4 plus
## day-transition overflow and initial state verification.

extends GdUnitTestSuite

const TickSystem := preload("res://src/systems/tick_system.gd")


# ---- Helpers ----

## Spawn a running TickSystem instance, auto-freed after the test.
func _make_running_system() -> TickSystem:
	var system := TickSystem.new()
	system.set_process(true)
	auto_free(system)
	return system


# --- Initial state verification ---

func test_initial_current_day() -> void:
	var system := _make_running_system()
	assert_int(system.get_current_day()).is_equal(1)


func test_initial_speed_multiplier() -> void:
	var system := _make_running_system()
	assert_float(system.speed_multiplier).is_equal(1.0)


# --- Acceptance Criteria ---

func test_manual_advancement_while_paused() -> void:
	# AC-1: paused, advance 80 → tick_count=80, signal fires
	var system := TickSystem.new()
	system.set_pause(true)
	auto_free(system)

	var fired_with := [-1]  # [last_emitted_value] — array for GDScript lambda capture
	system.ticks_advanced.connect(func(c: int): fired_with[0] = c)

	system.advance_ticks_manual(80)

	assert_int(system.get_tick_count()).is_equal(80)
	assert_int(fired_with[0]).is_equal(80)


func test_pause_state_preserved_after_manual_action() -> void:
	# AC-2: pause remains true after manual action; pause_state_changed must NOT fire
	var system := TickSystem.new()
	system.set_pause(true)
	auto_free(system)

	var fired_with := [-1]  # [last_emitted_value] — array for GDScript lambda capture
	system.pause_state_changed.connect(func(_p: bool): fired_with[0] = _p)

	system.advance_ticks_manual(80)

	assert_bool(system.is_paused()).is_equal(true)
	assert_int(fired_with[0]).is_equal(-1)


func test_manual_action_respects_no_speed_multiplier() -> void:
	# AC-3: at 2x speed, manual action costs exactly 80 (not 160)
	var system := _make_running_system()
	system.set_speed(2.0)

	var fired_with := [-1]  # [last_emitted_value]
	system.ticks_advanced.connect(func(c: int): fired_with[0] = c)

	system.advance_ticks_manual(80)

	assert_int(system.get_tick_count()).is_equal(80)
	assert_int(fired_with[0]).is_equal(80)


func test_multiple_manual_actions_accumulate() -> void:
	# AC-4: 10× 10-tick → count=100, 10 signal emissions
	var system := _make_running_system()

	var counts := []  # [emitted_values]
	system.ticks_advanced.connect(func(c: int): counts.append(c))

	for _i in range(10):
		system.advance_ticks_manual(10)

	assert_int(system.get_tick_count()).is_equal(100)
	assert_int(counts.size()).is_equal(10)
	for c in counts:
		assert_int(c).is_equal(10)


# --- Day transition ---

func test_manual_day_transition_on_overflow() -> void:
	# Advance 1940 from 0 → tick_count = 1940 - 1440 = 500, day=2, 1 transition
	var system := _make_running_system()

	var days_fired := []  # [days_elapsed_per_emission]
	system.day_transition.connect(func(d: int): days_fired.append(d))

	system.advance_ticks_manual(1940)

	assert_int(system.get_tick_count()).is_equal(500)
	assert_int(system.get_current_day()).is_equal(2)
	assert_int(days_fired.size()).is_equal(1)
	assert_int(days_fired[0]).is_equal(1)


func test_manual_multi_day_overflow_on_large_cost() -> void:
	# Advance 3380 from 0 → tick_count = 3380 - 2880 = 500, day=3.
	# Single day_transition signal with days_elapsed=2 (Issue 2 fix).
	var system := _make_running_system()

	var days_fired := []
	system.day_transition.connect(func(d: int): days_fired.append(d))

	system.advance_ticks_manual(3380)

	assert_int(system.get_tick_count()).is_equal(500)
	assert_int(system.get_current_day()).is_equal(3)
	# One signal, carrying the total days crossed.
	assert_int(days_fired.size()).is_equal(1)
	assert_int(days_fired[0]).is_equal(2)


func test_manual_overflow_from_near_end_of_day() -> void:
	# Advance to 1390 first (day=1), then advance 80 → tick_count = 1470 - 1440 = 30, day=2, 1 transition
	var system := _make_running_system()
	system.advance_ticks_manual(1390)

	var days_fired := []
	system.day_transition.connect(func(d: int): days_fired.append(d))

	system.advance_ticks_manual(80)

	assert_int(system.get_tick_count()).is_equal(30)
	assert_int(system.get_current_day()).is_equal(2)
	assert_int(days_fired.size()).is_equal(1)
	assert_int(days_fired[0]).is_equal(1)


func test_manual_negative_cost_ignored() -> void:
	# Negative costs are rejected — early return prevents tick regression.
	var system := _make_running_system()

	var ticks_fired := [-1]
	system.ticks_advanced.connect(func(c: int): ticks_fired[0] = c)

	system.advance_ticks_manual(-100)

	assert_int(system.get_tick_count()).is_equal(0)
	assert_int(ticks_fired[0]).is_equal(-1)
