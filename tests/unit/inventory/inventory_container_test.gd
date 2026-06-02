## GdUnit4 test suite for Story inv-001: InventorySystem Autoload and Container
## Data Model.
##
## Covers AC-11, AC-12, AC-13, AC-14, AC-24, AC-26.

extends GdUnitTestSuite

const InventorySystemScript := preload("res://src/systems/inventory/inventory_system.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Creates a fresh InventorySystem instance (not registered as Autoload).
func _make_inv() -> Node:
	var inv := InventorySystemScript.new()
	auto_free(inv)
	return inv


# ---------------------------------------------------------------------------
# AC-11: Storage Area capacity = 50
# ---------------------------------------------------------------------------

func test_inventory_create_container_has_50_slots() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_0_0", "Storage Area", 50)
	assert_int(inv.get_slot_count(&"storage_0_0")).is_equal(50)


func test_inventory_create_container_capacity_is_50() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_0_0", "Storage Area", 50)
	assert_int(inv.get_capacity(&"storage_0_0")).is_equal(50)


func test_inventory_create_container_all_slots_empty() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_0_0", "Storage Area", 50)
	assert_int(inv.get_occupied_slots(&"storage_0_0")).is_equal(0)


# ---------------------------------------------------------------------------
# AC-12: Storage Building upgrades container to 150 slots
# ---------------------------------------------------------------------------

func test_inventory_set_capacity_to_150_upgrades_container() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_3_7", "Storage Area", 50)
	inv.set_container_capacity(&"storage_3_7", 150)
	assert_int(inv.get_capacity(&"storage_3_7")).is_equal(150)


func test_inventory_set_capacity_to_150_grows_slot_array() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_3_7", "Storage Area", 50)
	inv.set_container_capacity(&"storage_3_7", 150)
	assert_int(inv.get_slot_count(&"storage_3_7")).is_equal(150)


# ---------------------------------------------------------------------------
# AC-13: get_capacity returns correct value at 50 and after upgrade to 150
# ---------------------------------------------------------------------------

func test_inventory_get_capacity_returns_correct_values() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_5_5", "Storage Area", 50)
	assert_int(inv.get_capacity(&"storage_5_5")).is_equal(50)
	inv.set_container_capacity(&"storage_5_5", 150)
	assert_int(inv.get_capacity(&"storage_5_5")).is_equal(150)


func test_inventory_get_capacity_unknown_id_returns_zero() -> void:
	var inv := _make_inv()
	assert_int(inv.get_capacity(&"nonexistent")).is_equal(0)


# ---------------------------------------------------------------------------
# AC-14: Demolish reverts to 50; items in overflow slots are preserved
# ---------------------------------------------------------------------------

func test_inventory_demolish_reverts_to_50_items_remain() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_2_2", "Storage Area", 50)
	inv.set_container_capacity(&"storage_2_2", 150)

	# Place an item in slot 100 (beyond capacity=50 after demolish)
	var slot: InventorySlot = inv.get_slot_data(&"storage_2_2", 100)
	slot.resource_id = &"wood"
	slot.quantity = 10

	inv.set_container_capacity(&"storage_2_2", 50)

	assert_int(inv.get_capacity(&"storage_2_2")).is_equal(50)
	var overflow_slot: InventorySlot = inv.get_slot_data(&"storage_2_2", 100)
	assert_object(overflow_slot).is_not_null()
	assert_str(str(overflow_slot.resource_id)).is_equal("wood")
	assert_int(overflow_slot.quantity).is_equal(10)


func test_inventory_demolish_occupied_count_includes_overflow() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_2_2", "Storage Area", 50)
	inv.set_container_capacity(&"storage_2_2", 150)

	var slot_a: InventorySlot = inv.get_slot_data(&"storage_2_2", 60)
	slot_a.resource_id = &"stone"
	slot_a.quantity = 5
	var slot_b: InventorySlot = inv.get_slot_data(&"storage_2_2", 80)
	slot_b.resource_id = &"wood"
	slot_b.quantity = 3

	inv.set_container_capacity(&"storage_2_2", 50)

	assert_int(inv.get_occupied_slots(&"storage_2_2")).is_equal(2)


# ---------------------------------------------------------------------------
# AC-24: current_charge is preserved through storage operations
# ---------------------------------------------------------------------------

## Note: this test verifies reference identity (get_slot_data returns the same
## object), not a true storage round-trip. The stronger AC-24 test is below.
func test_inventory_slot_charge_preserved_through_operations() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_9_1", "Storage Area", 50)

	var slot: InventorySlot = inv.get_slot_data(&"storage_9_1", 0)
	slot.resource_id = &"tool"
	slot.quantity = 1
	slot.current_charge = 75.0

	var retrieved: InventorySlot = inv.get_slot_data(&"storage_9_1", 0)
	assert_float(retrieved.current_charge).is_equal(75.0)


func test_inventory_slot_charge_not_reset_by_capacity_change() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_9_2", "Storage Area", 50)

	var slot: InventorySlot = inv.get_slot_data(&"storage_9_2", 0)
	slot.resource_id = &"tool"
	slot.quantity = 1
	slot.current_charge = 33.5

	inv.set_container_capacity(&"storage_9_2", 150)
	inv.set_container_capacity(&"storage_9_2", 50)

	var retrieved: InventorySlot = inv.get_slot_data(&"storage_9_2", 0)
	assert_float(retrieved.current_charge).is_equal(33.5)


# ---------------------------------------------------------------------------
# AC-26: Unknown resource_id is occupied but unusable
# ---------------------------------------------------------------------------

## AC-26 "occupied" half only. The "unusable" path (_is_slot_usable returns false)
## is deferred to inv-002: try_consume provides the public surface to test it.
func test_inventory_unknown_resource_id_is_occupied() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_4_4", "Storage Area", 50)

	var slot: InventorySlot = inv.get_slot_data(&"storage_4_4", 0)
	slot.resource_id = &"deleted_resource_xyz"
	slot.quantity = 5

	assert_int(inv.get_occupied_slots(&"storage_4_4")).is_equal(1)


func test_inventory_unknown_resource_slot_is_not_empty() -> void:
	var slot := InventorySlot.new()
	slot.resource_id = &"ghost_item"
	slot.quantity = 1
	assert_bool(slot.is_empty()).is_false()


func test_inventory_empty_slot_is_empty() -> void:
	var slot := InventorySlot.new()
	slot.resource_id = &""
	slot.quantity = 0
	assert_bool(slot.is_empty()).is_true()


# ---------------------------------------------------------------------------
# AC-17 integration boundary
# ---------------------------------------------------------------------------

func test_inventory_create_container_idempotent_duplicate_ignored() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_1_1", "Storage Area", 50)
	inv.create_container(&"storage_1_1", "Storage Area", 50)
	assert_int(inv.get_capacity(&"storage_1_1")).is_equal(50)
	assert_int(inv.get_all_containers().size()).is_equal(1)


func test_inventory_has_storage_at_tile_returns_true_after_create() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_10_5", "Storage Area", 50)
	assert_bool(inv.has_storage_at_tile(Vector2i(10, 5))).is_true()


func test_inventory_has_storage_at_tile_returns_false_for_empty_tile() -> void:
	var inv := _make_inv()
	assert_bool(inv.has_storage_at_tile(Vector2i(99, 99))).is_false()


# ---------------------------------------------------------------------------
# Signal: container_capacity_changed fires correctly
# ---------------------------------------------------------------------------

func test_inventory_container_capacity_changed_signal_fires_on_upgrade() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_6_6", "Storage Area", 50)

	var signal_fired: bool = false
	var received_old: int = -1
	var received_new: int = -1

	inv.container_capacity_changed.connect(
		func(_id: StringName, old_cap: int, new_cap: int) -> void:
			signal_fired = true
			received_old = old_cap
			received_new = new_cap
	)

	inv.set_container_capacity(&"storage_6_6", 150)

	assert_bool(signal_fired).is_true()
	assert_int(received_old).is_equal(50)
	assert_int(received_new).is_equal(150)


func test_inventory_container_capacity_changed_signal_fires_on_demolish() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_7_7", "Storage Area", 50)
	inv.set_container_capacity(&"storage_7_7", 150)

	var signal_fired: bool = false
	inv.container_capacity_changed.connect(
		func(_id: StringName, _old: int, _new: int) -> void:
			signal_fired = true
	)

	inv.set_container_capacity(&"storage_7_7", 50)

	assert_bool(signal_fired).is_true()
