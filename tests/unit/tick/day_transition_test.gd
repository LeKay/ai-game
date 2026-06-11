## gdUnit4 test suite for Story 004: Day Transition Event and Auto-Pause.
##
## Covers AC-1 through AC-5 of the Tick System day transition story.

extends GdUnitTestSuite

const TickSystem := preload("res://src/systems/tick_system.gd")


# ---- Helpers ----

## Spawn a running TickSystem instance, auto-freed after the test.
func _make_running_system() -> TickSystem:
	var system := TickSystem.new()
	system.set_process(true)
	system.set_pause(false)
	system.set_tick_remainder(0.0)
	system.set_speed(1.0)
	auto_free(system)
	return system


# ---- AC-1: Day transition at exactly 1440 ticks ----

func test_day_transition_at_boundary() -> void:
	var system := _make_running_system()
	system._tick_count = 1439
	assert_int(system.get_tick_count()).is_equal(999)
	assert_int(system.get_current_day()).is_equal(1)
	assert_bool(system.is_paused()).is_equal(false)

	# Capture day_transition signal.
	var day_signal_fired := [false]
	var day_value := [-1]
	system.day_transition.connect(func(d: int): day_signal_fired[0] = true; day_value[0] = d)

	# Capture ticks_advanced signal.
	var ticks_signal_fired := [false]
	var ticks_value := [-1]
	system.ticks_advanced.connect(func(d: int): ticks_signal_fired[0] = true; ticks_value[0] = d)

	# Advance 1 tick → should trigger day transition.
	system._accumulate_ticks(1)

	assert_bool(day_signal_fired[0]).is_equal(true)
	assert_int(day_value[0]).is_equal(1)
	assert_bool(ticks_signal_fired[0]).is_equal(true)
	assert_int(ticks_value[0]).is_equal(1)
	assert_int(system.get_tick_count()).is_equal(0)
	assert_int(system.get_current_day()).is_equal(2)
	assert_bool(system.is_paused()).is_equal(true)


# ---- AC-2: Overflow ticks discarded ----

func test_overflow_discarded_at_boundary() -> void:
	var system := _make_running_system()
	system._tick_count = 1390
	assert_int(system.get_tick_count()).is_equal(1390)

	# Capture day_transition — should fire exactly once.
	var day_count := [0]
	system.day_transition.connect(func(_d: int): day_count[0] += 1)

	# Advance 100 ticks → 1390 + 100 = 1490 → day fires → tick_count = 1490 - 1440 = 50.
	# 1490 is not exactly divisible by 1440, so the remainder (50) is kept.

	system._accumulate_ticks(100)

	assert_int(day_count[0]).is_equal(1)
	assert_int(system.get_tick_count()).is_equal(50)
	assert_int(system.get_current_day()).is_equal(2)
	assert_bool(system.is_paused()).is_equal(true)


# ---- AC-3: Manual action crossing day boundary ----

func test_manual_advance_triggers_day_transition() -> void:
	var system := _make_running_system()
	system._tick_count = 1390

	# Capture day_transition.
	var day_fired := [false]
	system.day_transition.connect(func(_d: int): day_fired[0] = true)

	# Advance 80 manual ticks → 1390 + 80 = 1470 → day transition → tick_count = 30.
	system.advance_ticks_manual(80)

	assert_bool(day_fired[0]).is_equal(true)
	assert_int(system.get_tick_count()).is_equal(30)
	assert_int(system.get_current_day()).is_equal(2)
	assert_bool(system.is_paused()).is_equal(true)


# ---- AC-4: No accumulation after auto-pause ----

func test_no_accumulation_after_day_pause() -> void:
	var system := _make_running_system()
	system._tick_count = 1439

	# Trigger day transition.
	var day_fired := [false]
	system.day_transition.connect(func(_d: int): day_fired[0] = true)
	system._accumulate_ticks(1)

	assert_bool(day_fired[0]).is_equal(true)
	assert_bool(system.is_paused()).is_equal(true)

	# Now _process() should NOT accumulate because set_pause(true) was called.
	# Verify tick_count doesn't change despite _process being called.
	var initial_tick_count: int = system.get_tick_count()
	system._process(1.0)  # Simulate _process call while paused
	assert_int(system.get_tick_count()).is_equal(initial_tick_count)


# ---- AC-5: get_current_day() returns updated value ----

func test_get_current_day_returns_incremented_value() -> void:
	var system := _make_running_system()
	system._tick_count = 1439
	assert_int(system.get_current_day()).is_equal(1)

	system._accumulate_ticks(1)

	assert_int(system.get_current_day()).is_equal(2)


# ---- Additional: Multiple day transitions via manual action ----

func test_manual_advance_multi_day() -> void:
	var system := _make_running_system()
	system._tick_count = 1420

	var day_count := [0]
	system.day_transition.connect(func(_d: int): day_count[0] += 1)

	# Advance 40 ticks → 1420 + 40 = 1460 → day boundary fires → tick_count = 1460 - 1440 = 20.
	system.advance_ticks_manual(40)

	assert_int(day_count[0]).is_equal(1)
	assert_int(system.get_tick_count()).is_equal(20)
	assert_int(system.get_current_day()).is_equal(2)


# ---- Signal ordering: day_transition before ticks_advanced ----

func test_day_transition_before_ticks_advanced() -> void:
	var system := _make_running_system()
	system._tick_count = 1439

	var event_order := []  # ["day_transition" | "ticks_advanced"]
	system.day_transition.connect(func(_d: int): event_order.append("day_transition"))
	system.ticks_advanced.connect(func(_d: int): event_order.append("ticks_advanced"))

	system._accumulate_ticks(1)

	# day_transition MUST fire before ticks_advanced.
	assert_int(event_order.size()).is_equal(2)
	assert_str(event_order[0]).is_equal("day_transition")
	assert_str(event_order[1]).is_equal("ticks_advanced")
