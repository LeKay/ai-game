extends Node
## DayLedger — Autoload singleton for daily resource delta accumulation.
## Subscribes to InventorySystem item_deposited/item_withdrawn signals and
## accumulates per-resource deltas. On TickSystem day_transition, freezes the
## accumulated deltas and resets the buffer. HungerSystem food_consumed_daily
## is stored separately so hunger consumption is not mixed with general deltas.
##
## ADR: ADR-0001 (Autoload pattern), ADR-0003 (Signal subscription)
## Story: ui-007 (DayLedger)

var _current_deltas: Dictionary = {}
var _last_day_deltas: Dictionary = {}
var _last_hunger_consumed: Dictionary = {}
var _last_perk_consumed: Dictionary = {}

func _enter_tree() -> void:
	InventorySystem.item_deposited.connect(_on_deposited)
	InventorySystem.item_withdrawn.connect(_on_withdrawn)
	TickSystem.day_transition.connect(_on_day_transition)
	HungerSystem.food_consumed_daily.connect(_on_hunger_consumed)
	NPCSystem.perk_goods_consumed_daily.connect(_on_perk_consumed)

func _on_deposited(resource_id: StringName, qty: int) -> void:
	_current_deltas[resource_id] = _current_deltas.get(resource_id, 0) + qty

func _on_withdrawn(resource_id: StringName, qty: int) -> void:
	_current_deltas[resource_id] = _current_deltas.get(resource_id, 0) - qty

func _on_day_transition(_days: int) -> void:
	_last_day_deltas = _current_deltas.duplicate()
	_current_deltas.clear()

func _on_hunger_consumed(items: Dictionary) -> void:
	_last_hunger_consumed = items.duplicate()

func _on_perk_consumed(items: Dictionary) -> void:
	_last_perk_consumed = items.duplicate()

## Returns the frozen resource deltas from the last completed day.
## Positive values = net gain, negative = net loss.
## Returns empty Dictionary before the first day completes.
func get_last_day_deltas() -> Dictionary:
	return _last_day_deltas

## Returns the hunger items consumed on the last completed day: {resource_id: qty}.
## Returns empty Dictionary if no day has completed or nothing was consumed.
func get_last_hunger_consumed() -> Dictionary:
	return _last_hunger_consumed

## Returns the perk bound-goods consumed on the last completed day: {resource_id: qty}.
func get_last_perk_consumed() -> Dictionary:
	return _last_perk_consumed

## Returns all daily consumption merged — food (hunger) + perk bound-goods — summed per resource.
## This is what the Day Overview "Daily Consumption" section shows.
func get_last_consumed() -> Dictionary:
	var merged: Dictionary = _last_hunger_consumed.duplicate()
	for resource_id: StringName in _last_perk_consumed:
		merged[resource_id] = int(merged.get(resource_id, 0)) + int(_last_perk_consumed[resource_id])
	return merged
