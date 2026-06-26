extends Node
## DebugSettings — Autoload singleton holding developer-only cheat flags.
##
## Single source of truth for the local debug mode (see DebugMenu, toggled with F12).
## Every flag defaults to false and is ONLY ever flipped by DebugMenu, which removes
## itself outside of debug builds — so in an exported Release/Web build these flags stay
## false and no gameplay system is affected.
##
## State here is intentionally NOT persisted in save files: it is a per-run dev aid.
## Access this autoload directly by name (DebugSettings.ignore_costs), never via
## Engine.get_singleton() — see .claude/rules/godot-singletons.md.

## Emitted whenever any flag changes, so open UI surfaces (build/craft grids) can refresh
## their affordability/lock styling immediately.
signal changed

## When true, building placement, crafting, and progression unlocks skip every resource,
## energy, and progression-point cost (both the affordability gate and the deduction).
var ignore_costs: bool = false

## When true, the player character never spends energy (consume_energy becomes a no-op).
var no_energy_cost: bool = false

## When true, every ProgressionSystem capability check (is_building_unlocked, is_recipe_unlocked,
## …) reports unlocked, opening all gated content without mutating the saved unlock state.
var unlock_all_progression: bool = false


## True only in editor/debug builds. DebugMenu uses this to decide whether to exist at all.
func is_available() -> bool:
	return OS.is_debug_build()


func set_ignore_costs(value: bool) -> void:
	if ignore_costs == value:
		return
	ignore_costs = value
	changed.emit()


func set_no_energy_cost(value: bool) -> void:
	if no_energy_cost == value:
		return
	no_energy_cost = value
	changed.emit()


func set_unlock_all_progression(value: bool) -> void:
	if unlock_all_progression == value:
		return
	unlock_all_progression = value
	changed.emit()
