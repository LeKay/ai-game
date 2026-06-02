## GdUnit4 test suite for Story inv-002: First-Fit Stacking Algorithm.
##
## Covers AC-6, AC-7, AC-8, AC-9, AC-10, AC-23, AC-25, AC-26.
## InventoryContainer.try_deposit takes explicit stack_limit and max_charge so tests run
## without a ResourceRegistry Autoload. InventorySystem.try_deposit tests use
## a null-registry fallback (stack_limit = 9999) which is adequate for AC-23.
## AC-26 "unusable" tests use MockRegistry registered via Engine.register_singleton.

extends GdUnitTestSuite

const InventoryContainerScript := preload("res://src/systems/inventory/inventory_container.gd")
const InventorySystemScript := preload("res://src/systems/inventory/inventory_system.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_container(capacity: int) -> InventoryContainer:
	var c := InventoryContainerScript.new(&"test_container", "Test", capacity)
	auto_free(c)
	return c


func _make_inv() -> Node:
	var inv := InventorySystemScript.new()
	auto_free(inv)
	return inv


# ---------------------------------------------------------------------------
# AC-6: N ≤ stack_limit → all items in one slot
# ---------------------------------------------------------------------------

func test_inventory_stacking_deposit_fits_in_single_slot_when_under_stack_limit() -> void:
	var c := _make_container(50)
	var result: int = c.try_deposit(&"wood", 5, 99, 0.0)
	assert_int(result).is_equal(InventoryContainer.DepositResult.SUCCESS)
	assert_int(c.get_occupied_count()).is_equal(1)


func test_inventory_stacking_deposit_single_slot_has_correct_resource_and_quantity() -> void:
	var c := _make_container(50)
	c.try_deposit(&"wood", 5, 99, 0.0)
	assert_str(str(c.slots[0].resource_id)).is_equal("wood")
	assert_int(c.slots[0].quantity).is_equal(5)


# ---------------------------------------------------------------------------
# AC-7: Overflow into second slot
# ---------------------------------------------------------------------------

func test_inventory_stacking_deposit_overflows_to_second_slot() -> void:
	var c := _make_container(50)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 95
	var result: int = c.try_deposit(&"wood", 10, 99, 0.0)
	assert_int(result).is_equal(InventoryContainer.DepositResult.SUCCESS)
	assert_int(c.get_occupied_count()).is_equal(2)


func test_inventory_stacking_deposit_slot_zero_fills_to_stack_limit_on_overflow() -> void:
	var c := _make_container(50)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 95
	c.try_deposit(&"wood", 10, 99, 0.0)
	assert_int(c.slots[0].quantity).is_equal(99)
	assert_str(str(c.slots[1].resource_id)).is_equal("wood")
	assert_int(c.slots[1].quantity).is_equal(6)


# ---------------------------------------------------------------------------
# AC-8: Full container → FAILURE_FULL, no modification
# ---------------------------------------------------------------------------

func test_inventory_stacking_deposit_returns_failure_full_when_container_full() -> void:
	var c := _make_container(50)
	for i: int in range(50):
		c.slots[i].resource_id = &"stone"
		c.slots[i].quantity = 99
	var result: int = c.try_deposit(&"wood", 1, 99, 0.0)
	assert_int(result).is_equal(InventoryContainer.DepositResult.FAILURE_FULL)


func test_inventory_stacking_deposit_does_not_modify_slots_when_full() -> void:
	var c := _make_container(50)
	for i: int in range(50):
		c.slots[i].resource_id = &"stone"
		c.slots[i].quantity = 99
	c.try_deposit(&"wood", 1, 99, 0.0)
	assert_int(c.get_resource_quantity(&"stone")).is_equal(50 * 99)


# ---------------------------------------------------------------------------
# AC-9: qty > stack_limit → minimum slots (ceil(qty/stack_limit))
# ---------------------------------------------------------------------------

func test_inventory_stacking_deposit_splits_across_minimum_slots() -> void:
	var c := _make_container(50)
	var result: int = c.try_deposit(&"wheat", 150, 99, 0.0)
	assert_int(result).is_equal(InventoryContainer.DepositResult.SUCCESS)
	assert_int(c.get_occupied_count()).is_equal(2)


func test_inventory_stacking_deposit_uses_correct_quantities_across_slots() -> void:
	var c := _make_container(50)
	c.try_deposit(&"wheat", 150, 99, 0.0)
	assert_int(c.slots[0].quantity).is_equal(99)
	assert_int(c.slots[1].quantity).is_equal(51)


# ---------------------------------------------------------------------------
# AC-10: EC-L3 — partial capacity not enough → FAILURE, rollback
# ---------------------------------------------------------------------------

func test_inventory_stacking_deposit_fails_when_items_cannot_all_fit() -> void:
	var c := _make_container(50)
	for i: int in range(49):
		c.slots[i].resource_id = &"stone"
		c.slots[i].quantity = 99
	# 1 empty slot remains; stack_limit=3 means max 3 of "bar" can fit, but qty=5
	var result: int = c.try_deposit(&"bar", 5, 3, 0.0)
	assert_int(result).is_equal(InventoryContainer.DepositResult.FAILURE_FULL)


func test_inventory_stacking_deposit_rollback_leaves_last_slot_untouched() -> void:
	var c := _make_container(50)
	for i: int in range(49):
		c.slots[i].resource_id = &"stone"
		c.slots[i].quantity = 99
	c.try_deposit(&"bar", 5, 3, 0.0)
	assert_bool(c.slots[49].is_empty()).is_true()


func test_inventory_stacking_deposit_rollback_restores_phase1_changes() -> void:
	# Container with 1 slot, partial match — phase 1 modifies then must roll back.
	var c := _make_container(1)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 90
	# Phase 1 adds 9 (→99), remaining=11, Phase 2 finds no empty slot → FAILURE
	var result: int = c.try_deposit(&"wood", 20, 99, 0.0)
	assert_int(result).is_equal(InventoryContainer.DepositResult.FAILURE_FULL)
	assert_int(c.slots[0].quantity).is_equal(90)


# ---------------------------------------------------------------------------
# AC-23: try_deposit is the pathway; get_resource_quantity reflects deposit
# ---------------------------------------------------------------------------

func test_inventory_stacking_deposit_through_system_reflects_in_quantity_query() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_0_0", "Test", 50)
	# Registry null → stack_limit fallback = 9999
	inv.try_deposit(&"storage_0_0", &"wood", 5)
	assert_int(inv.get_resource_quantity(&"storage_0_0", &"wood")).is_equal(5)


# ---------------------------------------------------------------------------
# AC-25: Deterministic consumption — first caller gets items, second fails
# ---------------------------------------------------------------------------

func test_inventory_stacking_consume_first_caller_succeeds_second_fails() -> void:
	var c := _make_container(50)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 7
	var result_a: int = c.try_consume(&"wood", 7)
	var result_b: int = c.try_consume(&"wood", 7)
	assert_int(result_a).is_equal(InventoryContainer.ConsumeResult.SUCCESS)
	assert_int(result_b).is_equal(InventoryContainer.ConsumeResult.FAILURE_INSUFFICIENT)


# ---------------------------------------------------------------------------
# try_consume correctness
# ---------------------------------------------------------------------------

func test_inventory_stacking_consume_reduces_slot_quantity() -> void:
	var c := _make_container(50)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 10
	var result: int = c.try_consume(&"wood", 3)
	assert_int(result).is_equal(InventoryContainer.ConsumeResult.SUCCESS)
	assert_int(c.slots[0].quantity).is_equal(7)


func test_inventory_stacking_consume_clears_slot_when_fully_emptied() -> void:
	var c := _make_container(50)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 5
	c.try_consume(&"wood", 5)
	assert_bool(c.slots[0].is_empty()).is_true()


func test_inventory_stacking_consume_spans_multiple_slots() -> void:
	var c := _make_container(50)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 5
	c.slots[1].resource_id = &"wood"
	c.slots[1].quantity = 5
	var result: int = c.try_consume(&"wood", 8)
	assert_int(result).is_equal(InventoryContainer.ConsumeResult.SUCCESS)
	assert_int(c.get_resource_quantity(&"wood")).is_equal(2)


func test_inventory_stacking_consume_returns_failure_and_leaves_items_when_insufficient() -> void:
	var c := _make_container(50)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 3
	var result: int = c.try_consume(&"wood", 5)
	assert_int(result).is_equal(InventoryContainer.ConsumeResult.FAILURE_INSUFFICIENT)
	assert_int(c.slots[0].quantity).is_equal(3)


# ---------------------------------------------------------------------------
# FAILURE_NO_CONTAINER via InventorySystem
# ---------------------------------------------------------------------------

func test_inventory_stacking_deposit_returns_failure_no_container_for_unknown_id() -> void:
	var inv := _make_inv()
	var result: int = inv.try_deposit(&"nonexistent", &"wood", 5)
	assert_int(result).is_equal(InventoryContainer.DepositResult.FAILURE_NO_CONTAINER)


func test_inventory_stacking_consume_returns_failure_no_container_for_unknown_id() -> void:
	var inv := _make_inv()
	var result: int = inv.try_consume(&"nonexistent", &"wood", 5)
	assert_int(result).is_equal(InventoryContainer.ConsumeResult.FAILURE_NO_CONTAINER)


# ---------------------------------------------------------------------------
# storage_changed signal
# ---------------------------------------------------------------------------

func test_inventory_stacking_storage_changed_emits_on_successful_deposit() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_1_1", "Test", 50)
	var fired: bool = false
	var fired_id: StringName = &""
	inv.storage_changed.connect(func(id: StringName) -> void:
		fired = true
		fired_id = id
	)
	inv.try_deposit(&"storage_1_1", &"wood", 5)
	assert_bool(fired).is_true()
	assert_str(str(fired_id)).is_equal("storage_1_1")


func test_inventory_stacking_storage_changed_not_emitted_on_failed_deposit() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_2_2", "Test", 50)
	for i: int in range(50):
		inv.get_slot_data(&"storage_2_2", i).resource_id = &"stone"
		inv.get_slot_data(&"storage_2_2", i).quantity = 99
	var fired: bool = false
	inv.storage_changed.connect(func(_id: StringName) -> void: fired = true)
	inv.try_deposit(&"storage_2_2", &"wood", 1)
	assert_bool(fired).is_false()


func test_inventory_stacking_storage_changed_emits_on_successful_consume() -> void:
	var inv := _make_inv()
	inv.create_container(&"storage_3_3", "Test", 50)
	inv.get_slot_data(&"storage_3_3", 0).resource_id = &"wood"
	inv.get_slot_data(&"storage_3_3", 0).quantity = 5
	var fired: bool = false
	inv.storage_changed.connect(func(_id: StringName) -> void: fired = true)
	inv.try_consume(&"storage_3_3", &"wood", 3)
	assert_bool(fired).is_true()


# ---------------------------------------------------------------------------
# MockRegistry — used by AC-26 and any test requiring a real registry presence.
# Register via Engine.register_singleton(&"ResourceRegistry", mock) and
# unregister at the end of the test function.
# ---------------------------------------------------------------------------

class MockRegistry:
	var _known: Array[StringName] = []

	func add_known(id: StringName) -> void:
		_known.append(id)

	func has_definition(id: StringName) -> bool:
		return _known.has(id)


# ---------------------------------------------------------------------------
# AC-26: Unknown resource_id slot cannot be consumed (try_consume skips it)
# ---------------------------------------------------------------------------

func test_inventory_stacking_consume_skips_unknown_resource_id_slot() -> void:
	var mock := MockRegistry.new()
	mock.add_known(&"wood")  # "ghost_item" is NOT registered
	Engine.register_singleton(&"ResourceRegistry", mock)

	var c := _make_container(50)
	c.slots[0].resource_id = &"ghost_item"
	c.slots[0].quantity = 10

	var result: int = c.try_consume(&"ghost_item", 10)
	assert_int(result).is_equal(InventoryContainer.ConsumeResult.FAILURE_INSUFFICIENT)
	assert_int(c.slots[0].quantity).is_equal(10)

	Engine.unregister_singleton(&"ResourceRegistry")


func test_inventory_stacking_consume_unknown_slot_does_not_block_known_resource() -> void:
	var mock := MockRegistry.new()
	mock.add_known(&"wood")  # "ghost_item" NOT registered
	Engine.register_singleton(&"ResourceRegistry", mock)

	var c := _make_container(50)
	c.slots[0].resource_id = &"ghost_item"
	c.slots[0].quantity = 10
	c.slots[1].resource_id = &"wood"
	c.slots[1].quantity = 5

	var result: int = c.try_consume(&"wood", 5)
	assert_int(result).is_equal(InventoryContainer.ConsumeResult.SUCCESS)
	assert_str(str(c.slots[0].resource_id)).is_equal("ghost_item")
	assert_int(c.slots[0].quantity).is_equal(10)

	Engine.unregister_singleton(&"ResourceRegistry")


# ---------------------------------------------------------------------------
# Overflow consume boundary (AC-14 consistency)
# ---------------------------------------------------------------------------

func test_inventory_stacking_consume_does_not_reach_overflow_slots() -> void:
	var c := _make_container(2)
	c.slots[0].resource_id = &"wood"
	c.slots[0].quantity = 5
	c.slots[1].resource_id = &"wood"
	c.slots[1].quantity = 5
	c.capacity = 1  # slots[1] is now overflow

	# Only 5 units are active; 5 sit in overflow — total available to consume is 5.
	var result: int = c.try_consume(&"wood", 10)
	assert_int(result).is_equal(InventoryContainer.ConsumeResult.FAILURE_INSUFFICIENT)
	assert_int(c.slots[0].quantity).is_equal(5)


# ---------------------------------------------------------------------------
# current_charge set on deposit (ADR-0005 guarantee)
# ---------------------------------------------------------------------------

func test_inventory_stacking_deposit_sets_current_charge_on_new_slot() -> void:
	var c := _make_container(50)
	c.try_deposit(&"battery", 5, 99, 100.0)
	assert_float(c.slots[0].current_charge).is_equal(500.0)


func test_inventory_stacking_deposit_adds_charge_to_partial_stack() -> void:
	var c := _make_container(50)
	c.slots[0].resource_id = &"battery"
	c.slots[0].quantity = 3
	c.slots[0].current_charge = 300.0
	c.try_deposit(&"battery", 2, 99, 100.0)
	assert_int(c.slots[0].quantity).is_equal(5)
	assert_float(c.slots[0].current_charge).is_equal(500.0)


func test_inventory_stacking_deposit_rollback_restores_current_charge() -> void:
	var c := _make_container(1)
	c.slots[0].resource_id = &"battery"
	c.slots[0].quantity = 90
	c.slots[0].current_charge = 9000.0
	# Phase 1 would add 9 (→99, charge→9900), remaining=11, Phase 2 no empty slot → FAILURE
	var result: int = c.try_deposit(&"battery", 20, 99, 100.0)
	assert_int(result).is_equal(InventoryContainer.DepositResult.FAILURE_FULL)
	assert_int(c.slots[0].quantity).is_equal(90)
	assert_float(c.slots[0].current_charge).is_equal(9000.0)
