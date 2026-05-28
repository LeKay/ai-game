## gdUnit4 test suite for Story 003: Action Rebinding and Persistence.
##
## Covers AC-1 (rebind changes key, multi-key clear), AC-2 (conflict detection),
## AC-3 (swap bindings), AC-4 (save/load persistence — fixture file, missing file, corrupt JSON, invalid key code).
## Uses isolated InputMap action names (__test_rebind_*__) to avoid polluting project bindings.

extends GdUnitTestSuite

const InputContextScript := preload("res://src/systems/input_context.gd")

const ACTION_A: StringName = &"__test_rebind_a__"
const ACTION_B: StringName = &"__test_rebind_b__"

var _ctx: Node
var _tmp_path: String


func before_test() -> void:
	_tmp_path = "user://test_rebinding_%d.cfg" % Time.get_ticks_msec()

	# Add isolated actions to InputMap, binding A→W and B→UP.
	for action: StringName in [ACTION_A, ACTION_B]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	InputMap.action_erase_events(ACTION_A)
	var ev_w := InputEventKey.new()
	ev_w.physical_keycode = KEY_W
	InputMap.action_add_event(ACTION_A, ev_w)

	InputMap.action_erase_events(ACTION_B)
	var ev_up := InputEventKey.new()
	ev_up.physical_keycode = KEY_UP
	InputMap.action_add_event(ACTION_B, ev_up)

	_ctx = InputContextScript.new()
	auto_free(_ctx)

	# _ready() is not called because the node is not in the scene tree.
	# Manually populate _default_bindings for the test actions so reset_bindings() works.
	var default_w := InputEventKey.new()
	default_w.physical_keycode = KEY_W
	_ctx._default_bindings[ACTION_A] = [default_w]
	var default_up := InputEventKey.new()
	default_up.physical_keycode = KEY_UP
	_ctx._default_bindings[ACTION_B] = [default_up]


func after_test() -> void:
	for action: StringName in [ACTION_A, ACTION_B]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	if FileAccess.file_exists(_tmp_path):
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove(_tmp_path.trim_prefix("user://"))


# ---- AC-1: Rebinding changes the bound key ----

func test_input_rebinding_rebind_action_changes_binding() -> void:
	# Arrange: ACTION_A → W. Rebind to Z.
	var new_key := InputEventKey.new()
	new_key.physical_keycode = KEY_Z

	# Act
	var result: bool = _ctx.rebind_action(ACTION_A, new_key)

	# Assert
	assert_bool(result).is_true()
	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_bool(keys.has(int(KEY_Z))).is_true()
	assert_bool(keys.has(int(KEY_W))).is_false()


func test_input_rebinding_rebind_action_same_key_returns_true_no_change() -> void:
	# Rebinding to the same key is a no-op — returns true, binding unchanged.
	var same_key := InputEventKey.new()
	same_key.physical_keycode = KEY_W

	var result: bool = _ctx.rebind_action(ACTION_A, same_key)

	assert_bool(result).is_true()
	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_int(keys.size()).is_equal(1)
	assert_bool(keys.has(int(KEY_W))).is_true()


func test_input_rebinding_rebind_action_multi_key_clears_all_old_bindings() -> void:
	# Bind a second key (S) to ACTION_A so it has both W and S.
	var ev_s := InputEventKey.new()
	ev_s.physical_keycode = KEY_S
	InputMap.action_add_event(ACTION_A, ev_s)

	# Rebind to Z — both W and S must be removed, only Z remains.
	var new_key := InputEventKey.new()
	new_key.physical_keycode = KEY_Z
	var result: bool = _ctx.rebind_action(ACTION_A, new_key)

	assert_bool(result).is_true()
	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_int(keys.size()).is_equal(1)
	assert_bool(keys.has(int(KEY_Z))).is_true()
	assert_bool(keys.has(int(KEY_W))).is_false()
	assert_bool(keys.has(int(KEY_S))).is_false()


# ---- AC-2: Conflict detection ----

func test_input_rebinding_conflict_returns_false_when_key_in_use() -> void:
	# ACTION_B → UP. Try to rebind ACTION_A to UP — should return false.
	var conflict_key := InputEventKey.new()
	conflict_key.physical_keycode = KEY_UP

	var result: bool = _ctx.rebind_action(ACTION_A, conflict_key)

	assert_bool(result).is_false()
	# ACTION_A must still be bound to W.
	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_bool(keys.has(int(KEY_W))).is_true()
	assert_bool(keys.has(int(KEY_UP))).is_false()


func test_input_rebinding_get_conflicting_action_returns_correct_action() -> void:
	# UP is bound to ACTION_B — get_conflicting_action should report ACTION_B.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_UP

	var conflict: StringName = _ctx.get_conflicting_action(key)

	assert_that(conflict).is_equal(ACTION_B)


# ---- AC-3: Swap bindings ----

func test_input_rebinding_swap_bindings_exchanges_keys() -> void:
	# ACTION_A→W, ACTION_B→UP. After swap: ACTION_A→UP, ACTION_B→W.
	_ctx.swap_bindings(ACTION_A, ACTION_B)

	var keys_a: Array[int] = _get_bound_keycodes(ACTION_A)
	var keys_b: Array[int] = _get_bound_keycodes(ACTION_B)

	assert_bool(keys_a.has(int(KEY_UP))).is_true()
	assert_bool(keys_a.has(int(KEY_W))).is_false()
	assert_bool(keys_b.has(int(KEY_W))).is_true()
	assert_bool(keys_b.has(int(KEY_UP))).is_false()


func test_input_rebinding_swap_bindings_same_action_is_noop() -> void:
	# Swapping an action with itself must leave bindings unchanged.
	var keys_before: Array[int] = _get_bound_keycodes(ACTION_A)

	_ctx.swap_bindings(ACTION_A, ACTION_A)

	var keys_after: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_array(keys_before).is_equal(keys_after)


# ---- AC-4: Persistence ----

func test_input_rebinding_save_and_load_restores_bindings() -> void:
	# save_bindings only writes REBINDABLE_ACTIONS; test actions are not in that list.
	# Write the JSON fixture directly so load_bindings is tested in isolation.
	var json_data: Dictionary = {str(ACTION_A): [int(KEY_Z)]}
	var file := FileAccess.open(_tmp_path, FileAccess.WRITE)
	assert_that(file).is_not_null()
	file.store_string(JSON.stringify(json_data))
	file.close()

	# load_bindings should apply Z to ACTION_A.
	_ctx.load_bindings(_tmp_path)

	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_bool(keys.has(int(KEY_Z))).is_true()
	assert_bool(keys.has(int(KEY_W))).is_false()


func test_input_rebinding_load_missing_file_leaves_bindings_unchanged() -> void:
	# Loading a non-existent file must not change existing bindings.
	_ctx.load_bindings("user://nonexistent_rebinding_test_xyz.cfg")

	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_bool(keys.has(int(KEY_W))).is_true()


func test_input_rebinding_load_corrupt_json_leaves_bindings_unchanged() -> void:
	# Corrupt JSON file must not change existing bindings.
	var file := FileAccess.open(_tmp_path, FileAccess.WRITE)
	assert_that(file).is_not_null()
	file.store_string("{ not: valid json !!!")
	file.close()

	_ctx.load_bindings(_tmp_path)

	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_bool(keys.has(int(KEY_W))).is_true()


func test_input_rebinding_load_invalid_key_code_keeps_existing_binding() -> void:
	# All key codes for ACTION_A are invalid (−1) → no valid events → existing binding kept.
	var json_data: Dictionary = {ACTION_A: [-1]}
	var file := FileAccess.open(_tmp_path, FileAccess.WRITE)
	assert_that(file).is_not_null()
	file.store_string(JSON.stringify(json_data))
	file.close()

	_ctx.load_bindings(_tmp_path)

	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_bool(keys.has(int(KEY_W))).is_true()


# ---- reset_bindings ----

func test_input_rebinding_reset_bindings_restores_project_defaults() -> void:
	# Override ACTION_A with Z.
	InputMap.action_erase_events(ACTION_A)
	var new_key := InputEventKey.new()
	new_key.physical_keycode = KEY_Z
	InputMap.action_add_event(ACTION_A, new_key)

	# reset_bindings should restore ACTION_A to W (from _default_bindings).
	_ctx.reset_bindings()

	var keys: Array[int] = _get_bound_keycodes(ACTION_A)
	assert_bool(keys.has(int(KEY_W))).is_true()
	assert_bool(keys.has(int(KEY_Z))).is_false()


# ---- Helpers ----

func _get_bound_keycodes(action: StringName) -> Array[int]:
	var result: Array[int] = []
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			result.append(int(ev.physical_keycode))
	return result
