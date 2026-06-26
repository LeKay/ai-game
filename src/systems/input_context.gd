## Input Context Stack — Foundation layer Autoload.
## Manages push/pop context stack, action rebinding, and keybinding persistence.
## Per ADR-0003.

extends Node

enum Context { WORLD_ACTIVE, UI_ACTIVE, PAUSED }

signal context_changed(new_context: Context)

const KEYBINDINGS_PATH: String = "user://settings/keybindings.cfg"
const DEBOUNCE_DELAY_MSEC: int = 250
const _MAX_STACK_DEPTH: int = 3

## Actions that always pass through regardless of active context.
const _GLOBAL_ACTIONS: Array[StringName] = [&"pause_toggle", &"speed_increase", &"speed_decrease"]
## Actions permitted when context is PAUSED.
const _PAUSE_ACTIONS: Array[StringName] = [&"pause_toggle"]

## Game actions eligible for rebinding and keybinding persistence.
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"interact", &"cancel_action", &"open_build_menu",
	&"camera_pan", &"camera_zoom",
	&"pause_toggle", &"speed_increase", &"speed_decrease", &"camera_reset",
	&"ui_confirm", &"ui_cancel",
]

var _context_stack: Array[Context] = [Context.WORLD_ACTIVE]
var _debounce_timers: Dictionary[StringName, int] = {}
## Snapshot of project-default bindings, captured before any runtime changes.
var _default_bindings: Dictionary = {}


func _ready() -> void:
	_capture_defaults()
	load_bindings()


## Snapshot InputMap events for all rebindable actions.
## Called at startup before load_bindings() so defaults are available for reset_bindings().
func _capture_defaults() -> void:
	_default_bindings.clear()
	for action: StringName in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			_default_bindings[action] = InputMap.action_get_events(action).duplicate()


# --- Context Stack ---

## Returns the active context (top of stack). Default: WORLD_ACTIVE.
func get_current() -> Context:
	return _context_stack.back()


## Push a new context onto the stack.
## Fires context_changed signal if context actually changes.
func push_context(ctx: Context) -> void:
	var previous: Context = _context_stack.back()
	if _context_stack.size() >= _MAX_STACK_DEPTH:
		push_warning("InputContext: stack depth %d reached limit — possible missing pop_context() call" % _context_stack.size())
	_context_stack.append(ctx)
	if ctx != previous:
		context_changed.emit(ctx)


## Pop the top context, restoring the previous one.
## No-op if stack has only 1 element.
## Fires context_changed signal only if the restored context differs.
func pop_context() -> void:
	if _context_stack.size() > 1:
		var previous: Context = _context_stack.back()
		_context_stack.pop_back()
		var restored: Context = _context_stack.back()
		if restored != previous:
			context_changed.emit(restored)


## Quick check: is the given context at the top of the stack?
func is_context_active(ctx: Context) -> bool:
	return _context_stack.back() == ctx


## Returns true if action is currently debounced (discard the input).
## Updates the timer on every non-debounced call.
func request_debounce(action: StringName) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	if _debounce_timers.has(action) and now_msec - _debounce_timers[action] < DEBOUNCE_DELAY_MSEC:
		return true
	_debounce_timers[action] = now_msec
	return false


# --- Rebinding ---

## Rebind action_id to new_key. Returns true on success, false if new_key conflicts with another action.
## Returns true without change if new_key is already the current binding for action_id.
## On success, persists bindings to KEYBINDINGS_PATH.
func rebind_action(action_id: StringName, new_key: InputEventKey) -> bool:
	if not InputMap.has_action(action_id):
		push_warning("InputContext: rebind_action called for unknown action: %s" % action_id)
		return false

	# No-op: new_key already bound to this action.
	for ev: InputEvent in InputMap.action_get_events(action_id):
		if ev is InputEventKey and ev.physical_keycode == new_key.physical_keycode:
			return true

	# Conflict: new_key is already bound to a different action.
	var conflict: StringName = get_conflicting_action(new_key)
	if conflict != &"" and conflict != action_id:
		return false

	# Erases all events including any gamepad bindings — keyboard-only rebinding is intentional for current scope.
	InputMap.action_erase_events(action_id)
	InputMap.action_add_event(action_id, new_key)
	save_bindings()
	return true


## Returns the action name currently bound to new_key, or empty StringName if none.
func get_conflicting_action(new_key: InputEventKey) -> StringName:
	for action: StringName in InputMap.get_actions():
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventKey and ev.physical_keycode == new_key.physical_keycode:
				return action
	return &""


## Swap all event bindings between action_a and action_b. No-op if they are the same action.
## Persists bindings to KEYBINDINGS_PATH on success.
func swap_bindings(action_a: StringName, action_b: StringName) -> void:
	if action_a == action_b:
		return
	if not InputMap.has_action(action_a) or not InputMap.has_action(action_b):
		push_warning("InputContext: swap_bindings called with unknown action — a: %s, b: %s" % [action_a, action_b])
		return
	var events_a: Array[InputEvent] = InputMap.action_get_events(action_a).duplicate()
	var events_b: Array[InputEvent] = InputMap.action_get_events(action_b).duplicate()
	InputMap.action_erase_events(action_a)
	InputMap.action_erase_events(action_b)
	for ev in events_b:
		InputMap.action_add_event(action_a, ev)
	for ev in events_a:
		InputMap.action_add_event(action_b, ev)
	save_bindings()


## Restore all rebindable actions to their project defaults (captured at startup).
## Removes the saved keybindings file.
func reset_bindings() -> void:
	for action_key in _default_bindings:
		var action_id: StringName = action_key as StringName
		if InputMap.has_action(action_id):
			InputMap.action_erase_events(action_id)
			for ev in _default_bindings[action_id]:
				InputMap.action_add_event(action_id, ev)
	if FileAccess.file_exists(KEYBINDINGS_PATH):
		var dir := DirAccess.open(KEYBINDINGS_PATH.get_base_dir())
		if dir:
			dir.remove(KEYBINDINGS_PATH.get_file())


# --- Persistence ---

## Persist current rebindable action bindings to keybindings.cfg.
func save_bindings(path: String = KEYBINDINGS_PATH) -> void:
	var base_dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var bindings: Dictionary = {}
	for action: StringName in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var key_codes: Array[int] = []
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventKey:
				key_codes.append(int(ev.physical_keycode))
		if not key_codes.is_empty():
			bindings[action] = key_codes
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_warning("InputContext: failed to open keybindings file for writing: " + path)
		return
	file.store_string(JSON.stringify(bindings, "\t"))
	file.close()


## Load bindings from keybindings.cfg. Falls back silently to defaults if file is missing or corrupt.
## Invalid individual key codes are skipped; if no valid codes remain for an action, the
## existing binding is preserved.
func load_bindings(path: String = KEYBINDINGS_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("InputContext: cannot open keybindings file: " + path)
		return
	var content: String = file.get_as_text()
	file.close()
	var json_parser := JSON.new()
	if json_parser.parse(content) != OK:
		push_warning("InputContext: keybindings.cfg is corrupt — using defaults")
		return
	var data: Variant = json_parser.get_data()
	if not data is Dictionary:
		push_warning("InputContext: keybindings.cfg has invalid structure — using defaults")
		return
	for raw_action: Variant in (data as Dictionary):
		var action_id: StringName = StringName(str(raw_action))
		if not InputMap.has_action(action_id):
			push_warning("InputContext: unknown action '%s' in keybindings.cfg — skipping" % action_id)
			continue
		var raw_codes: Variant = (data as Dictionary)[raw_action]
		if not raw_codes is Array:
			continue
		var valid_events: Array[InputEventKey] = []
		for raw_code: Variant in (raw_codes as Array):
			var scancode: int = int(raw_code) if (raw_code is float or raw_code is int) else -1
			if scancode <= 0:
				push_warning("InputContext: invalid key code %s for action '%s' — skipping" % [str(raw_code), action_id])
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = scancode as Key
			valid_events.append(ev)
		if valid_events.is_empty():
			push_warning("InputContext: no valid bindings for action '%s' — keeping existing" % action_id)
			continue
		InputMap.action_erase_events(action_id)
		for ev in valid_events:
			InputMap.action_add_event(action_id, ev)


func _unhandled_input(event: InputEvent) -> void:
	var ctx: Context = get_current()

	# Global actions always pass through — pause/speed work in any context.
	if _is_global_action(event):
		InputDispatcher.dispatch(event)
		return

	# PAUSED: only pause actions are permitted.
	if ctx == Context.PAUSED:
		if _is_pause_action(event):
			InputDispatcher.dispatch(event)
		return

	# WORLD_ACTIVE: all non-UI actions pass through.
	if ctx == Context.WORLD_ACTIVE:
		InputDispatcher.dispatch(event)
		return

	# UI_ACTIVE: UI actions are consumed by Control nodes and never reach
	# _unhandled_input(). Anything that does reach here is a world action
	# arriving while UI is open — consume it to block game hotkeys (e.g. I for inventory).
	get_viewport().set_input_as_handled()


func _is_global_action(event: InputEvent) -> bool:
	for action: StringName in _GLOBAL_ACTIONS:
		if event.is_action(action):
			return true
	return false


func _is_pause_action(event: InputEvent) -> bool:
	for action: StringName in _PAUSE_ACTIONS:
		if event.is_action(action):
			return true
	return false
