class_name DayLedgerTest
extends GdUnitTestSuite
## Unit tests for DayLedger — Story 007: Daily Resource Delta Accumulation.
## Tests: AC-1 through AC-5 per QA test cases in story-007-day-ledger.md.

var _ledger: DayLedger

func before_each() -> void:
	_ledger = DayLedger.new()
	# _enter_tree() tries Engine.get_singleton() — returns null in test env, warnings are safe
	add_child(_ledger)

func after_each() -> void:
	_ledger.queue_free()

# AC-1: DayLedger instantiates without error (singleton reachability tested via Autoload in runtime)
func test_day_ledger_instantiates_without_error() -> void:
	assert_that(_ledger).is_not_null()

# AC-2: Deposit accumulates positively for same resource
func test_deposit_accumulates_same_resource() -> void:
	_ledger._on_deposited(&"wood", 5)
	_ledger._on_deposited(&"wood", 3)
	assert_that(_ledger._current_deltas.get(&"wood", 0)).is_equal(8)

# AC-2: Two different resources remain independent
func test_deposit_two_resources_stay_independent() -> void:
	_ledger._on_deposited(&"wood", 5)
	_ledger._on_deposited(&"berry", 2)
	assert_that(_ledger._current_deltas.get(&"wood", 0)).is_equal(5)
	assert_that(_ledger._current_deltas.get(&"berry", 0)).is_equal(2)

# AC-2b: Withdraw accumulates negatively
func test_withdraw_accumulates_negatively() -> void:
	_ledger._on_withdrawn(&"berry", 2)
	assert_that(_ledger._current_deltas.get(&"berry", 0)).is_equal(-2)

# AC-2b: Withdraw before deposit — negative values are allowed
func test_withdraw_before_deposit_goes_negative() -> void:
	_ledger._on_withdrawn(&"stone", 3)
	_ledger._on_deposited(&"stone", 1)
	assert_that(_ledger._current_deltas.get(&"stone", 0)).is_equal(-2)

# AC-3: Day transition freezes deltas and resets buffer
func test_day_transition_freezes_and_resets() -> void:
	_ledger._on_deposited(&"wood", 8)
	_ledger._on_withdrawn(&"berry", 2)
	_ledger._on_day_transition(1)
	assert_that(_ledger.get_last_day_deltas().get(&"wood", 0)).is_equal(8)
	assert_that(_ledger.get_last_day_deltas().get(&"berry", 0)).is_equal(-2)
	assert_that(_ledger._current_deltas.is_empty()).is_true()

# AC-3: Second day transition with no activity yields empty last_day_deltas
func test_second_day_transition_empty_gives_empty_deltas() -> void:
	_ledger._on_deposited(&"wood", 5)
	_ledger._on_day_transition(1)
	_ledger._on_day_transition(2)
	assert_that(_ledger.get_last_day_deltas().is_empty()).is_true()

# AC-4: get_last_day_deltas returns empty before first day completes
func test_get_last_day_deltas_empty_before_first_day() -> void:
	assert_that(_ledger.get_last_day_deltas().is_empty()).is_true()

# AC-5: Hunger consumption stored separately, not mixed with general deltas
func test_hunger_consumed_stored_separately() -> void:
	_ledger._on_deposited(&"berry", 10)
	_ledger._on_hunger_consumed({&"berry": 3})
	assert_that(_ledger.get_last_hunger_consumed().get(&"berry", 0)).is_equal(3)
	# General delta unaffected by hunger signal
	assert_that(_ledger._current_deltas.get(&"berry", 0)).is_equal(10)

# AC-5: get_last_hunger_consumed returns empty before any signal fires
func test_get_last_hunger_consumed_empty_initially() -> void:
	assert_that(_ledger.get_last_hunger_consumed().is_empty()).is_true()

# AC-5: Hunger consumed is independent from day deltas after transition
func test_hunger_consumed_independent_from_day_deltas() -> void:
	_ledger._on_hunger_consumed({&"berry": 3})
	_ledger._on_deposited(&"wood", 5)
	_ledger._on_day_transition(1)
	assert_that(_ledger.get_last_day_deltas().get(&"wood", 0)).is_equal(5)
	assert_that(_ledger.get_last_day_deltas().has(&"berry")).is_false()
	assert_that(_ledger.get_last_hunger_consumed().get(&"berry", 0)).is_equal(3)
