## In-Game Pause Menu — presentation layer overlay.
## Opens on Escape from active gameplay and offers Save / Load / Settings / Back to Menu,
## styled to match the main menu. Lives under GameWorld (see game.tscn), not as an Autoload,
## so it only exists while a game is running.
##
## While open it pushes InputContext.UI_ACTIVE (stopping the world camera) and pauses the
## TickSystem, restoring the prior pause state when resumed. Settings is disabled (VS scope,
## mirroring the main menu).
##
## Escape handling lives in _unhandled_input so context-owning overlays that consume Escape
## first (overworld view, build overlay, map-select) take priority; this menu only opens from
## the WORLD_ACTIVE context.

extends CanvasLayer


# ── Constants ────────────────────────────────────────────────────────────────

const MAIN_MENU_SCENE: String = "res://src/ui/screens/main_menu.tscn"
const GAME_SCENE: String = "res://src/scenes/game.tscn"
const SAVE_SLOT: int = 1   ## Matches the HUD quick-save button.
const FEEDBACK_DURATION: float = 1.5


# ── Node references ────────────────────────────────────────────────────────────

@onready var _save_btn: Button = %Save
@onready var _load_btn: Button = %Load
@onready var _settings_btn: Button = %Settings
@onready var _back_btn: Button = %BackToMenu
@onready var _feedback_label: Label = %Feedback


# ── State ────────────────────────────────────────────────────────────────────

var _open: bool = false
var _prev_paused: bool = false   ## TickSystem pause state captured on open, restored on resume.
var _transitioning: bool = false ## Guards against double-clicks during a scene rebuild.


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 64  # above the gameplay HUD, below the debug overlay (128)
	visible = false
	_save_btn.pressed.connect(_on_save_pressed)
	_load_btn.pressed.connect(_on_load_pressed)
	_back_btn.pressed.connect(_on_back_pressed)
	# Disable Load when no save exists yet.
	_load_btn.disabled = WorldSaveManager.get_available_slots().is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(InputActions.UI_CANCEL):
		return
	if _open:
		close()
		get_viewport().set_input_as_handled()
	elif InputContext.get_current() == InputContext.Context.WORLD_ACTIVE:
		open()
		get_viewport().set_input_as_handled()


# ── Open / close ─────────────────────────────────────────────────────────────

func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_feedback_label.visible = false
	_load_btn.disabled = WorldSaveManager.get_available_slots().is_empty()
	_prev_paused = TickSystem.is_paused()
	TickSystem.set_pause(true)
	InputContext.push_context(InputContext.Context.UI_ACTIVE)
	_save_btn.grab_focus()


## Closes the menu and resumes gameplay, restoring the pre-open pause state.
func close() -> void:
	if not _open:
		return
	_teardown_context()
	_open = false
	visible = false


## Pops the UI context and restores the prior TickSystem pause state. Used by close() and by
## the actions that leave the current game (Load, Back to Menu).
func _teardown_context() -> void:
	if not _open:
		return
	_open = false
	InputContext.pop_context()
	TickSystem.set_pause(_prev_paused)


# ── Button handlers ────────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	if _transitioning:
		return
	if WorldSaveManager.save_game(SAVE_SLOT):
		_load_btn.disabled = false
		_show_feedback("Game saved")
	else:
		_show_feedback("Save failed")


## Stages the most recent save and rebuilds the game scene so MapRoot._ready applies it.
func _on_load_pressed() -> void:
	if _transitioning:
		return
	if not WorldSaveManager.load_last():
		_show_feedback("Load failed")
		return
	_transitioning = true
	_teardown_context()
	visible = false
	_rebuild_scene.call_deferred(GAME_SCENE)


func _on_back_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	_teardown_context()
	visible = false
	_rebuild_scene.call_deferred(MAIN_MENU_SCENE)


# ── Scene transitions ────────────────────────────────────────────────────────

## Frees the live GameWorld subtree and instances `scene_path` under the same parent. Mirrors
## MapRoot's reload path: the game scene is add_child'd to the root (never SceneTree.current_scene),
## so reload_current_scene() would miss it. Deferred so we don't restructure the tree mid-signal.
func _rebuild_scene(scene_path: String) -> void:
	var game_root: Node = get_parent()        # GameWorld (game.tscn root)
	var holder: Node = game_root.get_parent() # SceneTree root
	holder.remove_child(game_root)
	game_root.queue_free()
	var fresh: Node = (load(scene_path) as PackedScene).instantiate()
	holder.add_child(fresh)


# ── Feedback toast ─────────────────────────────────────────────────────────────

## Shows a transient status line on the panel (e.g. "Game saved"), fading out after a delay.
func _show_feedback(text: String) -> void:
	_feedback_label.text = text
	_feedback_label.visible = true
	_feedback_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(FEEDBACK_DURATION)
	tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func() -> void: _feedback_label.visible = false)
