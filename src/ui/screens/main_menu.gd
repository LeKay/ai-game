## Main Menu Screen — Presentation layer UI.
## Handles game launch navigation: New Game, Continue, Quit.
## Per ADR-0003: pushes/pops InputContext.UI_ACTIVE.
## Per ADR-0006: checks WorldSaveManager for save file existence.
##
## Acceptance Criteria:
##   AC-1:  Loads within 500ms of engine ready signal
##   AC-2:  Functional layout at 800x600, 1920x1080, 3440x1440
##   AC-3:  All buttons reachable via Tab and gamepad D-pad
##   AC-4:  Continue disabled when no save file exists
##   AC-5:  Settings button disabled (VS scope)
##   AC-6:  New Game starts game scene, destroys main menu
##   AC-7:  Continue loads last save via WorldSaveManager
##   AC-8:  Quit exits process cleanly
##   AC-9:  Focus indicators visible on all focusable buttons
##   AC-10: Loading state appears within 200ms of Continue click
##   AC-11: Escape produces no action (root screen)

extends CanvasLayer


# ── Constants ────────────────────────────────────────────────────────────────

const GAME_SCENE: String = "res://src/scenes/game.tscn"
const FADE_IN_DURATION: float = 0.3
const FADE_OUT_DURATION: float = 0.3


# ── Signals ──────────────────────────────────────────────────────────────────

signal game_started()
signal game_loaded()
signal game_exited()


# ── Node references ─────────────────────────────────────────────────────────

@onready var title_label: Label = %Title
@onready var menu_container: VBoxContainer = %MenuButtons
@onready var new_game_btn: Button = %NewGame
@onready var continue_btn: Button = %Continue
@onready var settings_btn: Button = %Settings
@onready var quit_btn: Button = %Quit
@onready var loading_overlay: Panel = %LoadingOverlay
@onready var load_failed_overlay: Panel = %LoadFailedOverlay
@onready var try_again_btn: Button = %TryAgain
@onready var new_game_from_fail_btn: Button = %NewGameFromFail
@onready var version_label: Label = %VersionLabel


# ── State ────────────────────────────────────────────────────────────────────

var _has_save: bool = false
var _is_transitioning: bool = false


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Push UI context per ADR-0003
	_try_push_ui_context()

	# Check for save file per ADR-0006
	check_save_file_state()

	version_label.text = _read_version()

	# Connect button signals
	new_game_btn.pressed.connect(_on_new_game_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	try_again_btn.pressed.connect(_on_try_again_pressed)
	new_game_from_fail_btn.pressed.connect(_on_new_game_from_fail_pressed)

	# Fade-in animation from black (apply to background, not CanvasLayer)
	var background := $Background
	background.modulate = Color.BLACK
	var tween := create_tween()
	tween.tween_property(background, "modulate", Color.WHITE, FADE_IN_DURATION).set_trans(Tween.TRANS_SINE)



func _unhandled_input(event: InputEvent) -> void:
	# AC-11: Escape on main menu produces no action (root screen)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()


# ── Save file check ─────────────────────────────────────────────────────────

## Checks WorldSaveManager for available save slots.
## Disables Continue button if no save exists (AC-4).
func check_save_file_state() -> void:
	if WorldSaveManager:
		var slots: Array[int] = WorldSaveManager.get_available_slots()
		_has_save = not slots.is_empty()
	else:
		# WorldSaveManager not yet registered — assume no save
		_has_save = false

	continue_btn.disabled = not _has_save


# ── Button handlers ─────────────────────────────────────────────────────────

## New Game: start fresh game, destroy main menu (AC-6).
func _on_new_game_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	game_started.emit()
	_try_pop_ui_context()

	# Fade out, then load game scene
	var tween := create_tween()
	tween.tween_property($Background, "modulate", Color.BLACK, FADE_OUT_DURATION)
	tween.tween_callback(_load_game_scene)


## Continue: load last save, transition to game scene (AC-7).
func _on_continue_pressed() -> void:
	if _is_transitioning or not _has_save:
		return
	_is_transitioning = true

	_show_loading()
	await get_tree().process_frame

	if WorldSaveManager:
		var success: bool = WorldSaveManager.load_last()
		if success:
			game_loaded.emit()
			_try_pop_ui_context()
			var tween := create_tween()
			tween.tween_property($Background, "modulate", Color.BLACK, FADE_OUT_DURATION)
			tween.tween_callback(_load_game_scene)
		else:
			_show_load_failed()
			_is_transitioning = false
	else:
		# WorldSaveManager not available — show error
		_show_load_failed()
		_is_transitioning = false


## Settings: no-op, disabled in VS (AC-5).
func _on_settings_pressed() -> void:
	pass  # Disabled in VS — deferred to MVP


## Quit: exit process cleanly (AC-8).
func _on_quit_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	# Fade out, then exit
	var tween := create_tween()
	tween.tween_property($Background, "modulate", Color.BLACK, FADE_OUT_DURATION)
	tween.tween_callback(_quit_to_desktop)


## Try Again: retry the failed load.
func _on_try_again_pressed() -> void:
	if _is_transitioning:
		return
	_hide_overlays()
	_on_continue_pressed()


## New Game from fail: start new game, abandoning the failed load.
func _on_new_game_from_fail_pressed() -> void:
	_hide_overlays()
	_on_new_game_pressed()


# ── Helpers ─────────────────────────────────────────────────────────────────

## Attempt to push InputContext.UI_ACTIVE — safe when InputContext is absent.
func _try_push_ui_context() -> void:
	if InputContext:
		InputContext.push_context(InputContext.Context.UI_ACTIVE)


## Attempt to pop InputContext — safe when InputContext is absent.
func _try_pop_ui_context() -> void:
	if InputContext:
		InputContext.pop_context()


## Fade to black, then load the game scene and free the main menu.
func _load_game_scene() -> void:
	var game_scene: PackedScene = load(GAME_SCENE)
	if game_scene:
		var instance: Node = game_scene.instantiate()
		get_tree().root.add_child(instance)
		queue_free()
	else:
		push_error("[MainMenu] Failed to load game scene: " + GAME_SCENE)
		_try_push_ui_context()
		_hide_overlays()
		_is_transitioning = false


## Reads version.json and returns a display string like "v0.1.72 (abc1234)".
func _read_version() -> String:
	const PATH := "res://version.json"
	if not FileAccess.file_exists(PATH):
		return "dev"
	var f := FileAccess.open(PATH, FileAccess.READ)
	if not f:
		return "dev"
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return "dev"
	var major: int = data.get("major", 0)
	var minor: int = data.get("minor", 1)
	var build: int = data.get("build", 0)
	var commit: String = data.get("commit", "")
	return "v%d.%d.%d (%s)" % [major, minor, build, commit]


## Quit to desktop — clean process exit.
## Emits game_exited signal right before quitting so listeners receive it at exit time.
func _quit_to_desktop() -> void:
	game_exited.emit()
	get_tree().quit()


## Show the loading overlay.
func _show_loading() -> void:
	loading_overlay.visible = true
	menu_container.visible = false


## Show the load-failed overlay.
func _show_load_failed() -> void:
	loading_overlay.visible = false
	load_failed_overlay.visible = true
	menu_container.visible = false


## Hide all overlays and restore the menu.
func _hide_overlays() -> void:
	loading_overlay.visible = false
	load_failed_overlay.visible = false
	menu_container.visible = true
	_is_transitioning = false

