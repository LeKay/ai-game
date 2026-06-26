class_name TransitItem
## TransitItem — represents an item stack moving between a source tile and a
## target container via the transport system.
##
## STUB — full implementation is Story 003 (start_transport / cancel_transport /
## _on_ticks_advanced). Only the data fields and is_ready() are defined here.

## Unique transport job identifier (e.g. &"transit_a7f3").
## Unique transport job identifier (e.g. &"transit_a7f3").
var transit_id: StringName = &""

## Grid tile the item departed from.
var source_tile: Vector2i = Vector2i.ZERO

## Destination container id.
var target_container_id: StringName = &""

## Resource being transported.
var resource_id: StringName = &""

## Unit count being transported.
var quantity: int = 0

## Ticks remaining until the item arrives.
var remaining_ticks: int = 0

## AP/energy cost of the transport job.
var energy_cost: int = 0

## Manhattan (or pathfinding) distance used to calculate remaining_ticks.
var distance: int = 0


## Returns true when the item has arrived (remaining_ticks reached zero).
func is_ready() -> bool:
	return remaining_ticks <= 0
