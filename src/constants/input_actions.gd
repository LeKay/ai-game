## StringName constants for all InputMap action IDs.
## Required by ADR-0003 — never use string literals for action lookups.
class_name InputActions

const MOVE_UP: StringName = &"move_up"
const MOVE_DOWN: StringName = &"move_down"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const INTERACT: StringName = &"interact"
const CANCEL_ACTION: StringName = &"cancel_action"
const OPEN_BUILD_MENU: StringName = &"open_build_menu"
const CAMERA_PAN: StringName = &"camera_pan"
const CAMERA_ZOOM: StringName = &"camera_zoom"
const PAUSE_TOGGLE: StringName = &"pause_toggle"
const SPEED_INCREASE: StringName = &"speed_increase"
const SPEED_DECREASE: StringName = &"speed_decrease"
const CAMERA_RESET: StringName = &"camera_reset"
const UI_CONFIRM: StringName = &"ui_confirm"
const UI_CANCEL: StringName = &"ui_cancel"
