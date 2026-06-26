## gdUnit4 test suite for Story 001: Input Context Stack and Action Dispatch.
##
## Covers AC-1 through AC-5 of the Input System foundation story.
## Each test creates its own InputContext instance in isolation.

extends GdUnitTestSuite

const InputContextScript := preload("res://src/systems/input_context.gd")

var _ctx: Node


func before_test() -> void:
	_ctx = InputContextScript.new()
	auto_free(_ctx)


# ---- AC-1: Default context is WORLD_ACTIVE ----

func test_input_context_default_context_is_world_active() -> void:
	assert_that(_ctx.get_current()).is_equal(InputContextScript.Context.WORLD_ACTIVE)
	assert_int(_ctx._context_stack.size()).is_equal(1)


# ---- AC-2: Push/pop with correct stack semantics ----

func test_input_context_push_changes_active_context() -> void:
	_ctx.push_context(InputContextScript.Context.UI_ACTIVE)
	assert_that(_ctx.get_current()).is_equal(InputContextScript.Context.UI_ACTIVE)


func test_input_context_pop_restores_previous_context() -> void:
	_ctx.push_context(InputContextScript.Context.UI_ACTIVE)
	_ctx.pop_context()
	assert_that(_ctx.get_current()).is_equal(InputContextScript.Context.WORLD_ACTIVE)


func test_input_context_double_push_double_pop_restores_world_active() -> void:
	# Push UI_ACTIVE then PAUSED, double pop should restore WORLD_ACTIVE (not UI_ACTIVE).
	_ctx.push_context(InputContextScript.Context.UI_ACTIVE)
	_ctx.push_context(InputContextScript.Context.PAUSED)
	_ctx.pop_context()
	_ctx.pop_context()
	assert_that(_ctx.get_current()).is_equal(InputContextScript.Context.WORLD_ACTIVE)


func test_input_context_pop_on_min_stack_is_noop() -> void:
	_ctx.pop_context()
	assert_that(_ctx.get_current()).is_equal(InputContextScript.Context.WORLD_ACTIVE)
	assert_int(_ctx._context_stack.size()).is_equal(1)


# ---- AC-3: context_changed signal fires only on actual context change ----

func test_input_context_context_changed_fires_when_context_changes() -> void:
	var emitted: Array = []
	_ctx.context_changed.connect(func(ctx): emitted.append(ctx))

	_ctx.push_context(InputContextScript.Context.UI_ACTIVE)

	assert_int(emitted.size()).is_equal(1)
	assert_that(emitted[0]).is_equal(InputContextScript.Context.UI_ACTIVE)


func test_input_context_context_changed_silent_on_same_context_push() -> void:
	# Pushing WORLD_ACTIVE when already WORLD_ACTIVE must NOT fire signal.
	var emitted: Array = []
	_ctx.context_changed.connect(func(_c): emitted.append(true))

	_ctx.push_context(InputContextScript.Context.WORLD_ACTIVE)

	assert_int(emitted.size()).is_equal(0)


func test_input_context_context_changed_silent_on_pop_that_restores_same_context() -> void:
	# Push WORLD_ACTIVE twice, so pop restores WORLD_ACTIVE — signal must not fire.
	_ctx.push_context(InputContextScript.Context.WORLD_ACTIVE)
	_ctx.push_context(InputContextScript.Context.WORLD_ACTIVE)

	var emitted: Array = []
	_ctx.context_changed.connect(func(_c): emitted.append(true))
	_ctx.pop_context()

	assert_int(emitted.size()).is_equal(0)


# ---- AC-4: Global actions pass through any context ----

func test_input_context_pause_toggle_is_global_action() -> void:
	# Space is bound to pause_toggle in project InputMap.
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	assert_bool(_ctx._is_global_action(event)).is_true()


func test_input_context_speed_increase_is_global_action() -> void:
	# Q is bound to speed_increase in project InputMap.
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	event.pressed = true
	assert_bool(_ctx._is_global_action(event)).is_true()


func test_input_context_move_up_is_not_global_action() -> void:
	# Movement actions are context-gated, not global.
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	assert_bool(_ctx._is_global_action(event)).is_false()
	assert_bool(_ctx._is_pause_action(event)).is_false()


# ---- AC-5: move_up dispatched via InputMap when WORLD_ACTIVE ----

func test_input_context_move_up_dispatched_in_world_active() -> void:
	# W is bound to move_up; context is WORLD_ACTIVE by default.
	var dispatched: Array[StringName] = []
	var cb := func(a: StringName) -> void: dispatched.append(a)
	InputDispatcher.action_pressed.connect(cb)

	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	_ctx._unhandled_input(event)

	InputDispatcher.action_pressed.disconnect(cb)

	assert_bool(dispatched.has(&"move_up")).is_true()


func test_input_context_move_up_not_dispatched_in_ui_active() -> void:
	# Movement inputs must be discarded when UI is open.
	_ctx.push_context(InputContextScript.Context.UI_ACTIVE)

	var dispatched: Array[StringName] = []
	var cb := func(a: StringName) -> void: dispatched.append(a)
	InputDispatcher.action_pressed.connect(cb)

	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	_ctx._unhandled_input(event)

	InputDispatcher.action_pressed.disconnect(cb)

	assert_bool(dispatched.is_empty()).is_true()


func test_input_context_move_up_not_dispatched_in_paused() -> void:
	_ctx.push_context(InputContextScript.Context.PAUSED)

	var dispatched: Array[StringName] = []
	var cb := func(a: StringName) -> void: dispatched.append(a)
	InputDispatcher.action_pressed.connect(cb)

	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	_ctx._unhandled_input(event)

	InputDispatcher.action_pressed.disconnect(cb)

	assert_bool(dispatched.is_empty()).is_true()
