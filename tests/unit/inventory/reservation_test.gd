## GdUnit4 test suite — InventoryContainer / InventorySystem reservation API.
##
## Reservations let a future depositor (e.g. a logistics carrier already carrying
## cargo) hold space in a container against concurrent depositors. They guarantee
## the cargo can be deposited on arrival even if other actors try to fill the
## container in the meantime.
##
## Regression context: prior to this API, carriers picked up cargo at the source
## with no destination guarantee — a player drag or another route could fill the
## storage between pickup and arrival, locking the carrier in WAITING_DESTINATION
## indefinitely and blocking all other routes assigned to that carrier.

extends GdUnitTestSuite

const InventorySystemScript := preload("res://src/systems/inventory/inventory_system.gd")

const CID := &"storage_0_0"
const WOOD := &"wood"
const STONE := &"stone"
const HOLDER_A := &"route_a"
const HOLDER_B := &"route_b"


func _make_inv(capacity: int = 10, quantity_based: bool = true) -> Node:
	var inv := InventorySystemScript.new()
	auto_free(inv)
	inv.create_container(CID, "Storage Area", capacity, quantity_based)
	return inv


# ---------------------------------------------------------------------------
# reserve_space
# ---------------------------------------------------------------------------

func test_reservation_reserve_space_succeeds_when_free_capacity() -> void:
	var inv := _make_inv(10)
	var ok: bool = inv.reserve_space(CID, HOLDER_A, WOOD, 3)
	assert_bool(ok).is_true()
	assert_int(inv.get_reserved_total(CID)).is_equal(3)


func test_reservation_reserve_space_fails_when_would_exceed_capacity() -> void:
	var inv := _make_inv(5)
	inv.try_deposit(CID, WOOD, 3)
	var ok: bool = inv.reserve_space(CID, HOLDER_A, WOOD, 3)
	assert_bool(ok).is_false()
	assert_int(inv.get_reserved_total(CID)).is_equal(0)


func test_reservation_two_holders_accumulate_against_capacity() -> void:
	var inv := _make_inv(5)
	assert_bool(inv.reserve_space(CID, HOLDER_A, WOOD, 3)).is_true()
	assert_bool(inv.reserve_space(CID, HOLDER_B, STONE, 2)).is_true()
	assert_int(inv.get_reserved_total(CID)).is_equal(5)
	# Third reservation would exceed capacity (0 used + 5 reserved + 1 = 6 > 5).
	assert_bool(inv.reserve_space(CID, &"route_c", WOOD, 1)).is_false()


func test_reservation_existing_items_count_against_capacity() -> void:
	var inv := _make_inv(10)
	inv.try_deposit(CID, WOOD, 8)
	assert_bool(inv.reserve_space(CID, HOLDER_A, WOOD, 3)).is_false()
	assert_bool(inv.reserve_space(CID, HOLDER_A, WOOD, 2)).is_true()


func test_reservation_holder_can_only_hold_one_reservation_at_a_time() -> void:
	# Calling reserve twice for the same holder replaces the previous reservation
	# (a route either holds cargo or doesn't — never two outstanding pickups).
	var inv := _make_inv(10)
	assert_bool(inv.reserve_space(CID, HOLDER_A, WOOD, 2)).is_true()
	assert_bool(inv.reserve_space(CID, HOLDER_A, WOOD, 3)).is_true()
	assert_int(inv.get_reserved_total(CID)).is_equal(3)


# ---------------------------------------------------------------------------
# release_reservation
# ---------------------------------------------------------------------------

func test_reservation_release_frees_capacity_for_others() -> void:
	var inv := _make_inv(5)
	inv.reserve_space(CID, HOLDER_A, WOOD, 3)
	inv.release_reservation(CID, HOLDER_A)
	assert_int(inv.get_reserved_total(CID)).is_equal(0)
	assert_bool(inv.reserve_space(CID, HOLDER_B, STONE, 5)).is_true()


func test_reservation_release_unknown_holder_is_noop() -> void:
	var inv := _make_inv(5)
	inv.release_reservation(CID, HOLDER_A)
	assert_int(inv.get_reserved_total(CID)).is_equal(0)


func test_reservation_release_unknown_container_is_noop() -> void:
	var inv := _make_inv(5)
	inv.release_reservation(&"does_not_exist", HOLDER_A)
	assert_int(inv.get_reserved_total(CID)).is_equal(0)


# ---------------------------------------------------------------------------
# Holder-aware try_deposit
# ---------------------------------------------------------------------------

func test_reservation_deposit_with_matching_holder_consumes_reservation() -> void:
	var inv := _make_inv(5)
	inv.reserve_space(CID, HOLDER_A, WOOD, 3)
	# Other depositors are blocked — only the holder's reservation makes this fit.
	inv.try_deposit(CID, STONE, 2)  # 2 used + 3 reserved = 5 (full for foreigners)
	var res: int = inv.try_deposit(CID, WOOD, 3, HOLDER_A)
	assert_int(res).is_equal(InventoryContainer.DepositResult.SUCCESS)
	assert_int(inv.get_reserved_total(CID)).is_equal(0)
	assert_int(inv.get_total_quantity(CID)).is_equal(5)


func test_reservation_deposit_without_holder_blocked_by_foreign_reservation() -> void:
	var inv := _make_inv(5)
	inv.reserve_space(CID, HOLDER_A, WOOD, 4)
	# Foreign depositor sees only 1 free slot (5 cap - 0 used - 4 reserved).
	var res_full: int = inv.try_deposit(CID, STONE, 2)
	assert_int(res_full).is_equal(InventoryContainer.DepositResult.FAILURE_FULL)
	var res_ok: int = inv.try_deposit(CID, STONE, 1)
	assert_int(res_ok).is_equal(InventoryContainer.DepositResult.SUCCESS)


func test_reservation_partial_deposit_against_reservation_keeps_remainder_reserved() -> void:
	# A holder may deposit less than reserved (cargo got partially eaten on the road
	# is hypothetical, but the holder might also choose to deposit in batches).
	# Remaining reservation stays held for the same holder.
	var inv := _make_inv(5)
	inv.reserve_space(CID, HOLDER_A, WOOD, 4)
	inv.try_deposit(CID, WOOD, 2, HOLDER_A)
	assert_int(inv.get_reserved_total(CID)).is_equal(2)
	assert_int(inv.get_total_quantity(CID)).is_equal(2)


func test_reservation_deposit_exceeding_reservation_still_checks_free_capacity() -> void:
	# Holder reserved 2 but tries to deposit 4. The extra 2 must fit in unreserved
	# free capacity; otherwise the deposit fails atomically.
	var inv := _make_inv(5)
	inv.try_deposit(CID, STONE, 2)  # 2 used
	inv.reserve_space(CID, HOLDER_A, WOOD, 2)  # 2 reserved
	# Total used+reserved = 4. Free for foreigners = 1; for HOLDER_A = 1 + own_reserved=2 = 3.
	# Holder tries to deposit 4 → 1 unreserved + reservation < 4 → FAILURE_FULL.
	var res_full: int = inv.try_deposit(CID, WOOD, 4, HOLDER_A)
	assert_int(res_full).is_equal(InventoryContainer.DepositResult.FAILURE_FULL)
	# Holder may deposit exactly 3 (1 unreserved + 2 reserved) → SUCCESS.
	var res_ok: int = inv.try_deposit(CID, WOOD, 3, HOLDER_A)
	assert_int(res_ok).is_equal(InventoryContainer.DepositResult.SUCCESS)
	assert_int(inv.get_reserved_total(CID)).is_equal(0)


# ---------------------------------------------------------------------------
# Query helpers
# ---------------------------------------------------------------------------

func test_reservation_get_reserved_for_resource_filters_by_id() -> void:
	var inv := _make_inv(10)
	inv.reserve_space(CID, HOLDER_A, WOOD, 3)
	inv.reserve_space(CID, HOLDER_B, STONE, 2)
	assert_int(inv.get_reserved_for(CID, WOOD)).is_equal(3)
	assert_int(inv.get_reserved_for(CID, STONE)).is_equal(2)
	assert_int(inv.get_reserved_for(CID, &"iron")).is_equal(0)


func test_reservation_get_reserved_total_unknown_container_returns_zero() -> void:
	var inv := _make_inv(5)
	assert_int(inv.get_reserved_total(&"does_not_exist")).is_equal(0)
