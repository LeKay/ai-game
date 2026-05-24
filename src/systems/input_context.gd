## Input Context Stack — Foundation layer Autoload.
## Manages push/pop context stack for input gating.
## Per ADR-0003.

extends Node

enum Context { WORLD_ACTIVE, UI_ACTIVE, PAUSED }

signal context_changed(new_context: Context)

var _context_stack: Array[Context] = [Context.WORLD_ACTIVE]
var _debounce_timers: Dictionary[StringName, int] = {}
const DEBOUNCE_DELAY_MSEC: int = 250  # milliseconds


## Returns the active context (top of stack). Default: WORLD_ACTIVE.
func get_current() -> Context:
	return _context_stack.back()


## Push a new context onto the stack.
## Fires context_changed signal if context actually changes.
func push_context(ctx: Context) -> void:
	var previous: Context = _context_stack.back()
	_context_stack.append(ctx)
	if ctx != previous:
		context_changed.emit(ctx)


## Pop the top context, restoring the previous one.
## No-op if stack has only 1 element.
func pop_context() -> void:
	if _context_stack.size() > 1:
		_context_stack.pop_back()
		var restored: Context = _context_stack.back()
		context_changed.emit(restored)


## Quick check: is the given context at the top of the stack?
func is_context_active(ctx: Context) -> bool:
	return _context_stack.back() == ctx


## Returns true if action is currently debounced (discard the input).
## DEBOUNCE_DELAY_MSEC: 250ms. Updates timer on every call (both paths).
func request_debounce(action: StringName) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	if _debounce_timers.has(action) and now_msec - _debounce_timers[action] < DEBOUNCE_DELAY_MSEC:
		return true  # still debounced
	_debounce_timers[action] = now_msec
	return false
