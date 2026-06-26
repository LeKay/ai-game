class_name DailyConsumptionTest
extends GdUnitTestSuite
## Unit tests for HungerSystem: Per-NPC daily food consumption and efficiency modifier.
## Each NPC receives an individual food_modifier on day transition:
##   - No food assigned or insufficient → 1.0 (stays at 50% efficiency via F1).
##   - amount units consumed → 1.0 + amount (per F5).

# ---- Mocks -------------------------------------------------------------------

class _MockNPC extends Node:
	var _ids: Array[StringName] = []
	var all_npcs: Dictionary = {}

	func get_npc_count() -> int:
		return _ids.size()

	func add_npc(npc_id: StringName) -> void:
		_ids.append(npc_id)
		all_npcs[npc_id] = true


class _MockInventory extends Node:
	## Maps food_id → available quantity (int).
	var _stock: Dictionary = {}

	func find_container_with(food_id: StringName) -> StringName:
		if (_stock.get(food_id, 0) as int) > 0:
			return &"container_1"
		return &""

	func try_consume(_container_id: StringName, food_id: StringName, amount: int) -> int:
		var available: int = _stock.get(food_id, 0)
		if available < amount:
			return InventoryContainer.ConsumeResult.FAILURE_NOT_ENOUGH
		_stock[food_id] = available - amount
		return InventoryContainer.ConsumeResult.SUCCESS

# ---- Setup -------------------------------------------------------------------

var _hunger: HungerSystem
var _mock_npc: _MockNPC
var _mock_inv: _MockInventory

func before_each() -> void:
	_mock_npc = _MockNPC.new()
	_mock_inv = _MockInventory.new()
	add_child(_mock_npc)
	add_child(_mock_inv)
	_hunger = HungerSystem.new()
	_hunger._npc = _mock_npc
	_hunger._inventory = _mock_inv
	add_child(_hunger)

func after_each() -> void:
	_hunger.queue_free()
	_mock_npc.queue_free()
	_mock_inv.queue_free()

# ---- AC-1: 0 NPCs — no signals, empty consumed dict -------------------------

func test_zero_npcs_emits_empty_consumed() -> void:
	var monitor := monitor_signals(_hunger)
	_hunger.apply_daily_consumption()
	assert_signal_emitted_on_null(_hunger, "food_consumed_daily")
	# npc_food_efficiency_changed must not be emitted with no NPCs
	assert_signal_not_emitted(_hunger, "npc_food_efficiency_changed")

# ---- AC-2: NPC with no food assignment → modifier 1.0 -----------------------

func test_no_food_assignment_emits_modifier_1() -> void:
	_mock_npc.add_npc(&"npc_0")
	var received: Array = []
	_hunger.npc_food_efficiency_changed.connect(
		func(id: StringName, mod: float) -> void: received.append([id, mod]))

	_hunger.apply_daily_consumption()

	assert_that(received.size()).is_equal(1)
	assert_that((received[0] as Array)[0]).is_equal(&"npc_0")
	assert_that((received[0] as Array)[1] as float).is_equal_approx(1.0, 0.0001)

# ---- AC-3: Food assigned, sufficient in inventory → modifier = 1 + amount ---

func test_one_food_unit_consumed_emits_modifier_2() -> void:
	_mock_npc.add_npc(&"npc_0")
	_mock_inv._stock[&"berry"] = 5
	_hunger.assign_food(&"npc_0", &"berry")
	_hunger.set_food_amount(&"npc_0", 1)

	var received: Array = []
	_hunger.npc_food_efficiency_changed.connect(
		func(id: StringName, mod: float) -> void: received.append([id, mod]))

	_hunger.apply_daily_consumption()

	assert_that(received.size()).is_equal(1)
	assert_that((received[0] as Array)[1] as float).is_equal_approx(2.0, 0.0001)

func test_two_food_units_consumed_emits_modifier_3() -> void:
	_mock_npc.add_npc(&"npc_0")
	_mock_inv._stock[&"berry"] = 10
	_hunger.assign_food(&"npc_0", &"berry")
	_hunger.set_food_amount(&"npc_0", 2)

	var received: Array = []
	_hunger.npc_food_efficiency_changed.connect(
		func(id: StringName, mod: float) -> void: received.append([id, mod]))

	_hunger.apply_daily_consumption()

	assert_that((received[0] as Array)[1] as float).is_equal_approx(3.0, 0.0001)

# ---- AC-4: Food assigned but not in inventory → modifier 1.0 ----------------

func test_food_not_in_inventory_emits_modifier_1() -> void:
	_mock_npc.add_npc(&"npc_0")
	_hunger.assign_food(&"npc_0", &"berry")
	# no stock added → find_container_with returns &""

	var received: Array = []
	_hunger.npc_food_efficiency_changed.connect(
		func(id: StringName, mod: float) -> void: received.append([id, mod]))

	_hunger.apply_daily_consumption()

	assert_that((received[0] as Array)[1] as float).is_equal_approx(1.0, 0.0001)

# ---- AC-5: Insufficient stock (less than requested) → modifier 1.0 ----------

func test_insufficient_food_emits_modifier_1() -> void:
	_mock_npc.add_npc(&"npc_0")
	_mock_inv._stock[&"berry"] = 1
	_hunger.assign_food(&"npc_0", &"berry")
	_hunger.set_food_amount(&"npc_0", 2)  # wants 2, only 1 available

	var received: Array = []
	_hunger.npc_food_efficiency_changed.connect(
		func(id: StringName, mod: float) -> void: received.append([id, mod]))

	_hunger.apply_daily_consumption()

	assert_that((received[0] as Array)[1] as float).is_equal_approx(1.0, 0.0001)

# ---- AC-6: Multiple NPCs — independent modifiers ----------------------------

func test_multiple_npcs_independent_modifiers() -> void:
	_mock_npc.add_npc(&"npc_0")
	_mock_npc.add_npc(&"npc_1")
	_mock_npc.add_npc(&"npc_2")

	_mock_inv._stock[&"berry"] = 5
	_hunger.assign_food(&"npc_0", &"berry")  # fed with 1 unit → modifier 2.0
	# npc_1 has no assignment → modifier 1.0
	# npc_2 has no stock for bread → modifier 1.0
	_hunger.assign_food(&"npc_2", &"bread")  # no bread in stock

	var results: Dictionary = {}
	_hunger.npc_food_efficiency_changed.connect(
		func(id: StringName, mod: float) -> void: results[id] = mod)

	_hunger.apply_daily_consumption()

	assert_that(results.size()).is_equal(3)
	assert_that(results[&"npc_0"] as float).is_equal_approx(2.0, 0.0001)
	assert_that(results[&"npc_1"] as float).is_equal_approx(1.0, 0.0001)
	assert_that(results[&"npc_2"] as float).is_equal_approx(1.0, 0.0001)

# ---- AC-7: food_consumed_daily tracks consumed items ------------------------

func test_food_consumed_daily_tracks_items() -> void:
	_mock_npc.add_npc(&"npc_0")
	_mock_npc.add_npc(&"npc_1")
	_mock_inv._stock[&"berry"] = 10
	_hunger.assign_food(&"npc_0", &"berry")
	_hunger.assign_food(&"npc_1", &"berry")

	var consumed_out: Dictionary = {}
	_hunger.food_consumed_daily.connect(
		func(items: Dictionary) -> void: consumed_out = items.duplicate())

	_hunger.apply_daily_consumption()

	assert_that(consumed_out.get(&"berry", 0) as int).is_equal(2)

# ---- F5 formula correctness --------------------------------------------------

func test_f5_zero_units_returns_one() -> void:
	assert_that(EfficiencyFormulas.calculate_food_modifier(0)).is_equal_approx(1.0, 0.0001)

func test_f5_one_unit_returns_two() -> void:
	assert_that(EfficiencyFormulas.calculate_food_modifier(1)).is_equal_approx(2.0, 0.0001)

func test_f5_three_units_returns_four() -> void:
	assert_that(EfficiencyFormulas.calculate_food_modifier(3)).is_equal_approx(4.0, 0.0001)
