## Input Dispatcher — Foundation layer Autoload.
## Routes gated InputEvents to subscriber signals.
## Per ADR-0003 architecture diagram.

extends Node

## Fires when an action key/button is first pressed.
signal action_pressed(action_id: StringName)

## Fires when an action key/button is released.
signal action_released(action_id: StringName)

## Fires on scroll wheel movement. Positive = up, negative = down.
signal scrolled(delta: float)


## Routes an InputEvent to the appropriate signal.
## Called by InputContext._unhandled_input() after context gating.
func dispatch(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				scrolled.emit(1.0)
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				scrolled.emit(-1.0)
				return

	for action: StringName in InputMap.get_actions():
		if event.is_action_pressed(action, false):
			action_pressed.emit(action)
		elif event.is_action_released(action):
			action_released.emit(action)
