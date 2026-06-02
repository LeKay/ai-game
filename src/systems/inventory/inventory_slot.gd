class_name InventorySlot
## InventorySlot — one cell in an InventoryContainer.
##
## resource_id == &"" means the slot is empty.
## current_charge is preserved through deposit/consume calls unrelated to recipe
## execution (AC-24) — the InventorySystem never resets it except when a slot
## is explicitly cleared.

## The resource held in this slot. &"" = empty.
var resource_id: StringName = &""

## How many units are stacked in this slot.
var quantity: int = 0

## Remaining charge (0.0–max_charge from ResourceRegistry).
## Preserved verbatim through storage operations (AC-24).
var current_charge: float = 0.0


## Returns true when the slot holds no resource.
func is_empty() -> bool:
	return resource_id == &""
