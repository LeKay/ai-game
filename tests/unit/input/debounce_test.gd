## gdUnit4 test suite for Story 002: Input Debounce System.
##
## Covers AC-1 through AC-4 of Story 002.
## Direct manipulation of _debounce_timers simulates elapsed time
## without real-time sleeps — all tests are deterministic.

extends GdUnitTestSuite

const InputContextScript = preload("res://src/systems/input_context.gd")

var _ctx: Node


func before_test() -> void:
	_ctx = InputContextScript.new()
	auto_free(_ctx)


# ---- AC-1: First call returns false; immediate second returns true ----

func test_input_debounce_first_call_returns_false() -> void:
	var result: bool = _ctx.request_debounce(&"pause_toggle")
	assert_bool(result).is_false()


func test_input_debounce_first_call_creates_timer_entry() -> void:
	_ctx.request_debounce(&"pause_toggle")
	assert_bool(_ctx._debounce_timers.has(&"pause_toggle")).is_true()


func test_input_debounce_second_immediate_call_returns_true() -> void:
	_ctx.request_debounce(&"pause_toggle")
	var result: bool = _ctx.request_debounce(&"pause_toggle")
	assert_bool(result).is_true()


# ---- AC-2: Debounce expires after DEBOUNCE_DELAY (250ms) ----

func test_input_debounce_allows_action_when_300ms_elapsed() -> void:
	# Simulate a timestamp 300ms in the past — delay has expired.
	_ctx._debounce_timers[&"pause_toggle"] = Time.get_ticks_msec() - 300
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_false()


func test_input_debounce_blocks_action_when_200ms_elapsed() -> void:
	# 200ms elapsed — still within 250ms window.
	_ctx._debounce_timers[&"pause_toggle"] = Time.get_ticks_msec() - 200
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()


func test_input_debounce_boundary_within_window_blocks() -> void:
	# 0ms elapsed — definitively within 250ms window, no timing race.
	_ctx._debounce_timers[&"pause_toggle"] = Time.get_ticks_msec()
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()


func test_input_debounce_boundary_250ms_allows() -> void:
	# Condition is (elapsed < DEBOUNCE_DELAY_MSEC), so exactly 250ms is allowed.
	_ctx._debounce_timers[&"pause_toggle"] = Time.get_ticks_msec() - 250
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_false()


func test_input_debounce_boundary_251ms_allows() -> void:
	_ctx._debounce_timers[&"pause_toggle"] = Time.get_ticks_msec() - 251
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_false()


# ---- AC-3: Different actions have independent debounce timers ----

func test_input_debounce_first_call_of_different_action_returns_false() -> void:
	# Debouncing pause_toggle must not affect speed_increase.
	_ctx.request_debounce(&"pause_toggle")
	assert_bool(_ctx.request_debounce(&"speed_increase")).is_false()


func test_input_debounce_actions_tracked_in_separate_timer_entries() -> void:
	_ctx.request_debounce(&"pause_toggle")
	_ctx.request_debounce(&"speed_increase")
	assert_bool(_ctx._debounce_timers.has(&"pause_toggle")).is_true()
	assert_bool(_ctx._debounce_timers.has(&"speed_increase")).is_true()


func test_input_debounce_blocked_action_does_not_gate_different_action() -> void:
	_ctx.request_debounce(&"pause_toggle")
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()   # blocked
	assert_bool(_ctx.request_debounce(&"speed_increase")).is_false() # independent


# ---- AC-4: Rapid spam of 10 presses at 100ms intervals ----

func test_input_debounce_spam_10_presses_100ms_apart_pattern() -> void:
	# 10 presses at 100ms intervals. A new window opens every 250ms.
	# Expected: false, true, true, false, true, true, false, true, true, false
	#           (allowed at presses 1, 4, 7, 10 when the 250ms window expires)
	#
	# Presses within a window are called immediately (real elapsed ~0ms < 250ms).
	# Window boundaries are simulated by backdating _debounce_timers 300ms.

	# Press 1: no entry — allowed.
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_false()

	# Presses 2–3: immediately after press 1 — blocked.
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()

	# Press 4: simulate 300ms elapsed since press 1 — allowed.
	_ctx._debounce_timers[&"pause_toggle"] = Time.get_ticks_msec() - 300
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_false()

	# Presses 5–6: immediately after press 4 — blocked.
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()

	# Press 7: simulate 300ms elapsed since press 4 — allowed.
	_ctx._debounce_timers[&"pause_toggle"] = Time.get_ticks_msec() - 300
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_false()

	# Presses 8–9: immediately after press 7 — blocked.
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_true()

	# Press 10: simulate 300ms elapsed since press 7 — allowed.
	_ctx._debounce_timers[&"pause_toggle"] = Time.get_ticks_msec() - 300
	assert_bool(_ctx.request_debounce(&"pause_toggle")).is_false()
