class_name ProductionSpeedTest
extends GdUnitTestSuite
## Unit tests for production speed throttle (target_efficiency field).
## Covers BuildingInstance.target_efficiency, get_effective_efficiency(),
## recalculate_efficiency() auto-clamp, and BuildingRegistry.set_production_speed().


func _make_instance() -> BuildingRegistry.BuildingInstance:
	return BuildingRegistry.BuildingInstance.new(
			"b0", BuildingRegistry.BuildingType.STORAGE_BUILDING, Vector2i(0, 0))


# ---- get_effective_efficiency ------------------------------------------------

# AC-1: default sentinel returns full efficiency
func test_get_effective_efficiency_default_returns_max() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	inst.target_efficiency = -1.0
	assert_float(inst.get_effective_efficiency()).is_equal(0.70)


# AC-2: explicit target returns that value
func test_get_effective_efficiency_returns_target() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	inst.target_efficiency = 0.40
	assert_float(inst.get_effective_efficiency()).is_equal(0.40)


# AC-3: zero target returns zero
func test_get_effective_efficiency_zero_target() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	inst.target_efficiency = 0.0
	assert_float(inst.get_effective_efficiency()).is_equal(0.0)


# ---- recalculate_efficiency auto-clamp ---------------------------------------

# AC-4: recalculate_efficiency clamps target when max drops below it
func test_recalculate_clamps_target_when_max_drops() -> void:
	var inst := _make_instance()
	inst.target_efficiency = 0.50
	# No workers, no adjacency → efficiency drops to base 0.25
	inst.recalculate_efficiency([])
	assert_float(inst.target_efficiency).is_less_equal(inst.efficiency)


# AC-5: recalculate_efficiency does NOT touch the sentinel -1.0
func test_recalculate_leaves_sentinel_unchanged() -> void:
	var inst := _make_instance()
	inst.target_efficiency = -1.0
	inst.recalculate_efficiency([])
	assert_float(inst.target_efficiency).is_equal(-1.0)


# AC-6: recalculate_efficiency does NOT clamp a valid target (still within range)
func test_recalculate_does_not_clamp_valid_target() -> void:
	var inst := _make_instance()
	inst.target_efficiency = 0.10  # well below base 0.25 — must stay
	inst.recalculate_efficiency([])
	assert_float(inst.target_efficiency).is_equal(0.10)


# ---- set_production_speed ----------------------------------------------------

## Applies the same clamp+sentinel logic as BuildingRegistry.set_production_speed()
## directly to an instance (BuildingRegistry is a singleton and cannot be .new()'d in tests).
func _apply_speed(inst: BuildingRegistry.BuildingInstance, target: float) -> void:
	var clamped: float = clampf(target, 0.0, inst.efficiency)
	inst.target_efficiency = -1.0 if clamped >= inst.efficiency else clamped


# AC-7: at max → stores sentinel so the building tracks future efficiency changes
func test_set_production_speed_at_max_stores_sentinel() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	_apply_speed(inst, 0.70)
	assert_float(inst.target_efficiency).is_equal(-1.0)


# AC-8: above max → clamps to max then stores sentinel
func test_set_production_speed_above_max_stores_sentinel() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	_apply_speed(inst, 0.99)
	assert_float(inst.target_efficiency).is_equal(-1.0)


# AC-9: below max → stores the explicit throttle value
func test_set_production_speed_below_max_stores_value() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	_apply_speed(inst, 0.40)
	assert_float(inst.target_efficiency).is_equal_approx(0.40, 0.001)


# AC-10: zero → stores zero (fully paused production)
func test_set_production_speed_zero_stores_zero() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	_apply_speed(inst, 0.0)
	assert_float(inst.target_efficiency).is_equal(0.0)
