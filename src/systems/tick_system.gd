extends Node
## TickSystem: deterministic tick accumulator (accessible as autoload singleton)


## Autoload singleton: deterministic, frame-rate-independent tick accumulator.
##
## Converts real-time engine delta into discrete tick units (10 ticks/sec at 1x).
## Fractional remainder carry ensures exact tick rates regardless of FPS.
## Lag spikes are clamped to MAX_TICKS_PER_FRAME per frame.
##
## **Story 001**: Accumulator core + remainder carry.
## **Story 002**: Speed modes and pause state machine.
## **Story 003**: `advance_ticks_manual()` — manual action tick advancement.
## **Story 004**: Day transition — fires `day_transition` signal at day boundary, auto-pauses the game.
## **Story 005**: `serialize()` / `deserialize()` — save/load tick state for persistence.

const TICKS_PER_DAY: int = 1440
const TICKS_PER_SECOND_BASE: float = 10.0
const MAX_TICKS_PER_FRAME: int = 100
const SPEED_OPTIONS: Array[float] = [0.5, 1.0, 2.0]

## Emitted every frame when tick accumulation advances.
## `delta_ticks` is the number of ticks added this frame.
signal ticks_advanced(delta_ticks: int)

## Emitted when the speed multiplier changes to a new valid value.
signal speed_changed(new_speed: float)

## Emitted when the pause state changes.
signal pause_state_changed(is_paused: bool)

## Emitted when the day counter increments (at tick_count >= TICKS_PER_DAY).
## `days_elapsed` is the number of days advanced by this transition.
signal day_transition(days_elapsed: int)

## Total accumulated ticks since project start.
var _tick_count: int = 0

## Returns the total number of accumulated ticks.
func get_tick_count() -> int:
	return _tick_count

var _speed_multiplier: float = 1.0

var speed_multiplier: float:
	get:
		return _speed_multiplier
	set(value):
		_set_speed_and_notify(value)

func _clamp_speed(value: float) -> float:
	if is_nan(value):
		return _speed_multiplier  # keep old value
	if SPEED_OPTIONS.has(value):
		return value
	var clamped: float = SPEED_OPTIONS[0]
	for s in SPEED_OPTIONS:
		if is_equal_approx(s, value):
			return s
		if absf(s - value) < absf(clamped - value):
			clamped = s
	return clamped

func _set_speed_and_notify(value: float) -> void:
	var clamped: float = _clamp_speed(value)
	if clamped != _speed_multiplier:
		_speed_multiplier = clamped
		speed_changed.emit(_speed_multiplier)

var _is_paused: bool = true  # Default paused: game world starts frozen until player begins

## Current day number, starting at 1. Increments at each day boundary.
var _current_day: int = 1

## Returns the current day number.
func get_current_day() -> int:
	return _current_day

# Fractional tick remainder carried across frames to prevent drift.
var _tick_remainder: float = 0.0

## Returns the current fractional tick remainder.
func get_tick_remainder() -> float:
	return _tick_remainder

## For serialization/deserialization support — restores tick remainder state.
func set_tick_remainder(value: float) -> void:
	_tick_remainder = value

## Query: whether the system is paused.
func is_paused() -> bool:
	return _is_paused

## Returns the current speed multiplier value.
# Removed: redundant with speed_multiplier property getter (lines 44-48).

## Set the speed multiplier, clamped to valid SPEED_OPTIONS values.
## Accepts NaN (keeps old value), rejects negatives (clamps to nearest option).
func set_speed(multiplier: float) -> void:
	_set_speed_and_notify(multiplier)

## Toggle pause state. Pauses _process() (no accumulation), toggles set_process(), emits pause_state_changed if state differs.
func set_pause(paused: bool) -> void:
	if paused != _is_paused:
		_is_paused = paused
		set_process(not paused)
		pause_state_changed.emit(paused)

func _enter_tree() -> void:
	## Fatal check: this Autoload must be registered in project.godot to function.
	if not ProjectSettings.has_setting("autoload/TickSystem"):
		push_error("[TickSystem] Not registered as Autoload in project.godot")
		queue_free()
		return
	set_process(not _is_paused)


## Accumulate ticks from engine delta. Skips if delta is negative (clamps to 0)
## or if the system is paused. Applies speed multiplier, carries fractional
## remainder, clamps to MAX_TICKS_PER_FRAME.
func _process(delta: float) -> void:
	if _is_paused:
		return
	if delta < 0.0:
		delta = 0.0

	var raw_ticks: float = delta * TICKS_PER_SECOND_BASE * speed_multiplier
	raw_ticks += _tick_remainder

	var tick_delta: int = clampi(floori(raw_ticks), 0, MAX_TICKS_PER_FRAME)
	_tick_remainder = fposmod(raw_ticks, 1.0)

	if tick_delta > 0:
		_accumulate_ticks(tick_delta)


## Advance day(s) while _tick_count exceeds boundary. Returns number of days crossed.
func _advance_days() -> int:
	var days := 0
	while _tick_count >= TICKS_PER_DAY:
		_tick_count -= TICKS_PER_DAY
		_current_day += 1
		days += 1
	return days

## Add ticks to total and emit the ticks_advanced signal with the count.
func _accumulate_ticks(ticks: int) -> void:
	_tick_count += ticks
	var days := _advance_days()
	if days > 0:
		day_transition.emit(days)
		set_pause(true)
	ticks_advanced.emit(ticks)


## Advance tick count by a specific cost (for manual player actions).
##
## Bypasses the _process() accumulation formula — costs are always base
## values, never modified by speed_multiplier. Works regardless of pause
## state: a paused world advances by the action cost, then re-freezes.
## Handles day transitions via a while loop: if the cost pushes tick_count
## past TICKS_PER_DAY, the remainder after subtracting TICKS_PER_DAY wraps to the
## next day, current_day increments, and the game auto-pauses. Manual
## actions that cross a day boundary still trigger pause.
func advance_ticks_manual(cost: int) -> void:
	if cost < 0:
		return
	_tick_count += cost
	var days := _advance_days()
	if days > 0:
		day_transition.emit(days)
		set_pause(true)
	ticks_advanced.emit(cost)


## Serialize tick state to a plain Dictionary for save system integration.
## Returns all persistent fields as scalar values suitable for JSON encoding.
## Deterministic: same state always produces identical output.
## No node references, callables, or nested system calls.
func serialize() -> Dictionary:
	return {
		"tick_count": _tick_count,
		"tick_remainder": _tick_remainder,
		"current_day": _current_day,
		"speed_multiplier": _speed_multiplier,
		"is_paused": _is_paused
	}


## Restore tick state from a Dictionary produced by serialize().
## Uses .get() with defaults for safe access — never uses direct [key] access.
## Does NOT call set_pause() — calls set_process() directly to avoid emitting
## pause_state_changed during load (subscribers may not be connected yet).
## If required keys are missing, logs an error and leaves state unchanged.
func deserialize(data: Dictionary) -> void:
	var required_keys: Array[String] = [
		"tick_count", "tick_remainder", "current_day",
		"speed_multiplier", "is_paused"
	]
	for key in required_keys:
		if not data.has(key):
			push_error("TickSystem.deserialize(): missing required key '%s'" % key)
			return

	var raw_tc = data.get("tick_count")
	if raw_tc == null:
		push_warning("TickSystem.deserialize(): key 'tick_count' is null, using default 0")
		raw_tc = 0
	_tick_count = int(raw_tc)

	var raw_tr = data.get("tick_remainder")
	if raw_tr == null:
		push_warning("TickSystem.deserialize(): key 'tick_remainder' is null, using default 0.0")
		raw_tr = 0.0
	_tick_remainder = float(raw_tr)

	var raw_cd = data.get("current_day")
	if raw_cd == null:
		push_warning("TickSystem.deserialize(): key 'current_day' is null, using default 1")
		raw_cd = 1
	_current_day = int(raw_cd)

	var raw_sm = data.get("speed_multiplier")
	if raw_sm == null:
		push_warning("TickSystem.deserialize(): key 'speed_multiplier' is null, using default 1.0")
		raw_sm = 1.0
	_speed_multiplier = float(raw_sm)

	var raw_ip = data.get("is_paused")
	if raw_ip == null:
		push_warning("TickSystem.deserialize(): key 'is_paused' is null, using default true")
		raw_ip = true
	_is_paused = bool(raw_ip)
	set_process(not _is_paused)
