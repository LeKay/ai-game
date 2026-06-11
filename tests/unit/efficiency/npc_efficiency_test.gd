class_name NpcEfficiencyTest
extends GdUnitTestSuite
## Unit tests for Efficiency System Story 001: NPC Efficiency Property and Food Integration.
## Covers AC-1 through AC-7 from the story acceptance criteria.
## BASE_NPC_EFFICIENCY = 0.5: default efficiency when all modifiers are 1.0 (no food).

# ---- Helpers ------------------------------------------------------------------

## Minimal HungerSystem stub — exposes the per-NPC signal used by NPCSystem.
class _MockFoodSystem extends Node:
	signal npc_food_efficiency_changed(npc_id: StringName, food_modifier: float)

	func emit_food_modifier(npc_id: StringName, modifier: float) -> void:
		npc_food_efficiency_changed.emit(npc_id, modifier)

## Minimal BuildingRegistry stub — satisfies NPCSystem._enter_tree() without real systems.
class _MockBuilding extends Node:
	signal building_demolished(building_id: StringName)
	func get_building_tile(_id: StringName) -> Vector2i:
		return Vector2i(-1, -1)
	func assign_npc(_building: String, _npc: StringName) -> void:
		pass

## Minimal InventorySystem stub.
class _MockInventory extends Node:
	signal storage_changed(container_id: StringName)
	signal container_removed(container_id: StringName)

## Builds an NPCSystem with injected mocks. Returns [npc_system, mock_food_system].
func _make_npc_system() -> Array:
	var mock_building := _MockBuilding.new()
	var mock_inventory := _MockInventory.new()
	var mock_food := _MockFoodSystem.new()
	add_child(mock_building)
	add_child(mock_inventory)
	add_child(mock_food)

	var npc_sys := NPCSystem.new()
	npc_sys._building_system = mock_building
	npc_sys._inventory_system = mock_inventory
	mock_food.npc_food_efficiency_changed.connect(npc_sys._on_npc_food_efficiency_changed)
	add_child(npc_sys)

	return [npc_sys, mock_food]

# ---- AC-1: F1 formula correctness --------------------------------------------

func test_formula_all_mods_at_one_returns_base() -> void:
	# BASE_NPC_EFFICIENCY × 1.0 × 1.0 × 1.0 = 0.5
	var result := EfficiencyFormulas.calculate_npc_efficiency(1.0, 1.0, 1.0)
	assert_that(result).is_equal_approx(EfficiencyFormulas.BASE_NPC_EFFICIENCY, 0.0001)

func test_formula_all_zeros_returns_zero() -> void:
	var result := EfficiencyFormulas.calculate_npc_efficiency(0.0, 0.0, 0.0)
	assert_that(result).is_equal(0.0)

func test_formula_large_mods_clamped_to_max() -> void:
	# 0.5 × 3.0 × 2.0 × 1.0 = 3.0 → clamped to 2.0
	var result := EfficiencyFormulas.calculate_npc_efficiency(3.0, 2.0, 1.0)
	assert_that(result).is_equal(2.0)

# ---- AC-2: food modifier applied ---------------------------------------------

func test_formula_food_mod_2_returns_full_efficiency() -> void:
	# 0.5 × 2.0 × 1.0 × 1.0 = 1.0 (100%)
	var result := EfficiencyFormulas.calculate_npc_efficiency(2.0, 1.0, 1.0)
	assert_that(result).is_equal_approx(1.0, 0.0001)

func test_formula_food_mod_zero_returns_zero() -> void:
	var result := EfficiencyFormulas.calculate_npc_efficiency(0.0, 1.0, 1.0)
	assert_that(result).is_equal(0.0)

func test_formula_combined_exceeds_max_clamped() -> void:
	# 0.5 × 2.0 × 2.0 × 2.0 = 4.0 → clamped to 2.0
	var result := EfficiencyFormulas.calculate_npc_efficiency(2.0, 2.0, 2.0)
	assert_that(result).is_equal(2.0)

# ---- AC-3: NPCInstance.recalculate_efficiency stores result ------------------

func test_npc_instance_recalculate_no_food_returns_base() -> void:
	var npc := NPCSystem.NPCInstance.new()
	npc.food_modifier = 1.0
	npc.satisfaction_modifier = 1.0
	npc.equipment_modifier = 1.0

	npc.recalculate_efficiency()

	# 0.5 × 1.0 = 0.5 (BASE)
	assert_that(npc.efficiency).is_equal_approx(EfficiencyFormulas.BASE_NPC_EFFICIENCY, 0.0001)

func test_npc_instance_recalculate_one_food_returns_full() -> void:
	var npc := NPCSystem.NPCInstance.new()
	npc.food_modifier = 2.0  # 1 food unit consumed
	npc.recalculate_efficiency()
	# 0.5 × 2.0 = 1.0
	assert_that(npc.efficiency).is_equal_approx(1.0, 0.0001)

func test_npc_instance_defaults_to_base_efficiency() -> void:
	var npc := NPCSystem.NPCInstance.new()
	assert_that(npc.efficiency).is_equal_approx(EfficiencyFormulas.BASE_NPC_EFFICIENCY, 0.0001)
	assert_that(npc.food_modifier).is_equal(1.0)
	assert_that(npc.satisfaction_modifier).is_equal(1.0)
	assert_that(npc.equipment_modifier).is_equal(1.0)

# ---- AC-4: per-NPC food signal updates correct NPC only ----------------------

func test_food_signal_updates_specific_npc() -> void:
	var arr := _make_npc_system()
	var npc_sys: NPCSystem = arr[0]
	var mock_food: _MockFoodSystem = arr[1]

	for i in range(3):
		var tile := Vector2i(i, 0)
		npc_sys._house_registry[tile] = NPCSystem._HouseState.new()
		var npc := NPCSystem.NPCInstance.new()
		npc.npc_id = StringName("npc_%d" % i)
		npc.position = tile
		npc.home_base = tile
		npc.state = NPCSystem.TaskState.IDLE
		npc_sys.all_npcs[npc.npc_id] = npc

	# Feed only npc_1 with modifier 2.0
	mock_food.emit_food_modifier(&"npc_1", 2.0)

	var npc0: NPCSystem.NPCInstance = npc_sys.all_npcs[&"npc_0"]
	var npc1: NPCSystem.NPCInstance = npc_sys.all_npcs[&"npc_1"]
	var npc2: NPCSystem.NPCInstance = npc_sys.all_npcs[&"npc_2"]

	assert_that(npc0.food_modifier).is_equal_approx(1.0, 0.0001)
	assert_that(npc0.efficiency).is_equal_approx(EfficiencyFormulas.BASE_NPC_EFFICIENCY, 0.0001)

	assert_that(npc1.food_modifier).is_equal_approx(2.0, 0.0001)
	assert_that(npc1.efficiency).is_equal_approx(1.0, 0.0001)

	assert_that(npc2.food_modifier).is_equal_approx(1.0, 0.0001)
	assert_that(npc2.efficiency).is_equal_approx(EfficiencyFormulas.BASE_NPC_EFFICIENCY, 0.0001)

# ---- AC-4 edge: unknown npc_id — no error ------------------------------------

func test_food_signal_unknown_npc_no_error() -> void:
	var arr := _make_npc_system()
	var mock_food: _MockFoodSystem = arr[1]
	mock_food.emit_food_modifier(&"npc_unknown", 2.0)
	assert_bool(true).is_true()

# ---- AC-5: modifier reset to 1.0 drops efficiency back to base ---------------

func test_food_reset_to_1_drops_efficiency_to_base() -> void:
	var arr := _make_npc_system()
	var npc_sys: NPCSystem = arr[0]
	var mock_food: _MockFoodSystem = arr[1]

	for i in range(2):
		var tile := Vector2i(i, 0)
		npc_sys._house_registry[tile] = NPCSystem._HouseState.new()
		var npc := NPCSystem.NPCInstance.new()
		npc.npc_id = StringName("npc_%d" % i)
		npc.position = tile
		npc.home_base = tile
		npc.state = NPCSystem.TaskState.IDLE
		npc.food_modifier = 2.0
		npc.efficiency = 1.0
		npc_sys.all_npcs[npc.npc_id] = npc

	mock_food.emit_food_modifier(&"npc_0", 1.0)
	mock_food.emit_food_modifier(&"npc_1", 1.0)

	for npc_id: StringName in npc_sys.all_npcs:
		var npc: NPCSystem.NPCInstance = npc_sys.all_npcs[npc_id]
		assert_that(npc.food_modifier).is_equal_approx(1.0, 0.0001)
		assert_that(npc.efficiency).is_equal_approx(EfficiencyFormulas.BASE_NPC_EFFICIENCY, 0.0001)

# ---- AC-6: new NPC defaults to base efficiency (no food yet) -----------------

func test_new_npc_starts_at_base_efficiency() -> void:
	var npc := NPCSystem.NPCInstance.new()
	assert_that(npc.food_modifier).is_equal_approx(1.0, 0.0001)
	assert_that(npc.efficiency).is_equal_approx(EfficiencyFormulas.BASE_NPC_EFFICIENCY, 0.0001)

# ---- AC-7: clamp at boundaries -----------------------------------------------

func test_formula_clamp_negative_result_to_zero() -> void:
	var result := EfficiencyFormulas.calculate_npc_efficiency(-1.0, 1.0, 1.0)
	assert_that(result).is_equal(0.0)

func test_formula_clamp_above_max_to_two() -> void:
	# 0.5 × 1.0 × 2.0 × 3.0 = 3.0 → clamped to 2.0
	var result := EfficiencyFormulas.calculate_npc_efficiency(1.0, 2.0, 3.0)
	assert_that(result).is_equal(2.0)

func test_formula_equipment_five_times_one_clamped() -> void:
	# 0.5 × 1.0 × 1.0 × 5.0 = 2.5 → clamped to 2.0
	var result := EfficiencyFormulas.calculate_npc_efficiency(1.0, 1.0, 5.0)
	assert_that(result).is_equal(2.0)
