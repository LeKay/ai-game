## gdUnit4 integration test suite for Story 005: Save and Load Tick State.
##
## Covers AC-1 (full round-trip), AC-2 (resume from saved state),
## AC-3 (determinism), AC-4 (invalid data fail-fast).

extends GdUnitTestSuite

const TickSystem := preload("res://src/systems/tick_system.gd")


# ---- Helpers ----

func _make_system() -> Node:
	var system := TickSystem.new()
	system.set_process(false)  # no accumulation during tests
	auto_free(system)
	return system


# ---- AC-1: Full state round-trip ----

func test_roundtrip_all_fields_preserved() -> void:
	var system := _make_system()
	system._tick_count = 450
	system._tick_remainder = 0.73
	system._current_day = 7
	system._speed_multiplier = 2.0
	system._is_paused = true

	var saved := system.serialize() as Dictionary
	system.deserialize(saved)

	assert_int(system.get_tick_count()).is_equal(450)
	assert_float(system.get_tick_remainder()).is_equal_approx(0.73, 0.0001)
	assert_int(system.get_current_day()).is_equal(7)
	assert_float(system.speed_multiplier).is_equal_approx(2.0, 0.0001)
	assert_bool(system.is_paused()).is_equal(true)


func test_roundtrip_edge_zero_values() -> void:
	var system := _make_system()
	system._tick_count = 0
	system._tick_remainder = 0.0
	system._current_day = 1
	system._speed_multiplier = 1.0
	system._is_paused = false

	var saved := system.serialize() as Dictionary
	system.deserialize(saved)

	assert_int(system.get_tick_count()).is_equal(0)
	assert_float(system.get_tick_remainder()).is_equal_approx(0.0, 0.0001)
	assert_int(system.get_current_day()).is_equal(1)
	assert_float(system.speed_multiplier).is_equal_approx(1.0, 0.0001)
	assert_bool(system.is_paused()).is_equal(false)


func test_roundtrip_edge_boundary_values() -> void:
	var system := _make_system()
	system._tick_count = 999
	system._tick_remainder = 0.999
	system._current_day = 1
	system._speed_multiplier = 1.0
	system._is_paused = false

	var saved := system.serialize() as Dictionary
	system.deserialize(saved)

	assert_int(system.get_tick_count()).is_equal(999)
	assert_float(system.get_tick_remainder()).is_equal_approx(0.999, 0.0001)
	assert_int(system.get_current_day()).is_equal(1)
	assert_float(system.speed_multiplier).is_equal_approx(1.0, 0.0001)
	assert_bool(system.is_paused()).is_equal(false)


# ---- AC-2: Resume from saved state ----

func test_resume_from_saved_state() -> void:
	## State restored at near-day-boundary must allow correct continuation.
	var system := _make_system()
	system._tick_count = 999
	system._tick_remainder = 0.8
	system._current_day = 5
	system._speed_multiplier = 1.0
	system._is_paused = false

	var saved := system.serialize() as Dictionary
	system.deserialize(saved)

	assert_int(system.get_tick_count()).is_equal(999)
	assert_float(system.get_tick_remainder()).is_equal_approx(0.8, 0.0001)
	assert_int(system.get_current_day()).is_equal(5)
	assert_bool(system.is_paused()).is_equal(false)
	assert_float(system.speed_multiplier).is_equal_approx(1.0, 0.0001)


# ---- AC-3: Determinism ----

func test_determinism_identical_state_after_deserialize() -> void:
	var system_a := _make_system()
	system_a._tick_count = 500
	system_a._tick_remainder = 0.5
	system_a._current_day = 1
	system_a._speed_multiplier = 1.0
	system_a._is_paused = false
	system_a.set_process(true)

	var saved := system_a.serialize() as Dictionary
	system_a.queue_free()

	var system_b := _make_system()
	system_b.deserialize(saved)

	assert_int(system_b.get_tick_count()).is_equal(500)
	assert_float(system_b.get_tick_remainder()).is_equal_approx(0.5, 0.0001)
	assert_int(system_b.get_current_day()).is_equal(1)
	assert_float(system_b.speed_multiplier).is_equal_approx(1.0, 0.0001)
	assert_bool(system_b.is_paused()).is_equal(false)


# ---- AC-4: Invalid data fail-fast ----

func test_invalid_data_empty_dict_rejected() -> void:
	var system := _make_system()
	system._tick_count = 100
	system._tick_remainder = 0.5
	system._current_day = 3

	system.deserialize({})

	assert_int(system.get_tick_count()).is_equal(100)
	assert_float(system.get_tick_remainder()).is_equal_approx(0.5, 0.0001)
	assert_int(system.get_current_day()).is_equal(3)


func test_invalid_data_partial_dict_rejected() -> void:
	var system := _make_system()
	system._tick_count = 200
	system._tick_remainder = 0.3
	system._current_day = 3
	system._speed_multiplier = 2.0
	system._is_paused = true

	var partial := {"tick_count": 999, "current_day": 99}
	system.deserialize(partial)

	## State unchanged — partial data is rejected.
	assert_int(system.get_tick_count()).is_equal(200)
	assert_float(system.get_tick_remainder()).is_equal_approx(0.3, 0.0001)
	assert_int(system.get_current_day()).is_equal(3)
	assert_float(system.speed_multiplier).is_equal_approx(2.0, 0.0001)
	assert_bool(system.is_paused()).is_equal(true)


# ---- deserialize() set_process() correctness ----

func test_deserialize_sets_process_for_unpaused() -> void:
	var system := _make_system()
	system._is_paused = true
	system.set_process(false)

	var data := {
		"tick_count": 0,
		"tick_remainder": 0.0,
		"current_day": 1,
		"speed_multiplier": 1.0,
		"is_paused": false
	}
	system.deserialize(data)

	assert_bool(system.is_processing()).is_equal(true)


func test_deserialize_clears_process_for_paused() -> void:
	var system := _make_system()
	system._is_paused = false
	system.set_process(true)

	var data := {
		"tick_count": 0,
		"tick_remainder": 0.0,
		"current_day": 1,
		"speed_multiplier": 1.0,
		"is_paused": true
	}
	system.deserialize(data)

	assert_bool(system.is_processing()).is_equal(false)
