## Tests for ResourceRegistry.get_perk_eligible_ids_for_group (perk-group filter).
## Spec: docs/superpowers/specs/2026-06-28-perk-good-groups-design.md

extends GdUnitTestSuite

const ResourceRegistry := preload("res://src/systems/resource_registry.gd")

const _FIXTURE := "res://tests/fixtures/perk_group_fixture.json"


func _make_registry() -> ResourceRegistry:
	var reg := ResourceRegistry.new()
	auto_free(reg)
	reg.load_from_file(_FIXTURE)
	return reg


func test_group_1_returns_only_non_deprecated_members() -> void:
	var reg := _make_registry()
	var ids: Array[StringName] = reg.get_perk_eligible_ids_for_group(1)
	assert_array(ids).contains_exactly_in_any_order([&"alpha", &"beta"])


func test_group_2_returns_single_member() -> void:
	var reg := _make_registry()
	var ids: Array[StringName] = reg.get_perk_eligible_ids_for_group(2)
	assert_array(ids).contains_exactly_in_any_order([&"gamma"])


func test_group_0_returns_resources_without_group_assignment() -> void:
	# perk_group == 0 (default) means "not perk-eligible". delta is the only
	# fixture entry without a perk_group field.
	var reg := _make_registry()
	var ids: Array[StringName] = reg.get_perk_eligible_ids_for_group(0)
	assert_array(ids).contains_exactly_in_any_order([&"delta"])


func test_unused_group_returns_empty() -> void:
	var reg := _make_registry()
	var ids: Array[StringName] = reg.get_perk_eligible_ids_for_group(99)
	assert_array(ids).is_empty()
