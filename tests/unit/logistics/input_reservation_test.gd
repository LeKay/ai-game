## GdUnit4 test suite — BuildingRegistry production input-buffer reservation API.
##
## Mirrors InventoryContainer reservations but at the per-resource input slot
## level used by production buildings. Prevents the same lockup pattern: a route
## that picks up cargo destined for a production building's input slot must hold
## that slot against other routes / player drags filling it in transit.
##
## Tests use a Mill (LUMBERJACK_HUT recipe has wood→plank). We pick a recipe
## with input_capacity > 0 so the slot can actually be "filled".

extends GdUnitTestSuite

const BuildingRegScript := preload("res://src/gameplay/building_registry.gd")
const WorldGridScript   := preload("res://src/systems/world_grid.gd")
const InventoryScript   := preload("res://src/systems/inventory/inventory_system.gd")
const PlayerCharScript  := preload("res://src/systems/player_character.gd")

const HOLDER_A := &"route_a"
const HOLDER_B := &"route_b"

var _registry: BuildingRegScript
var _grid: WorldGridScript
var _inventory: InventoryScript
var _player: PlayerCharScript


func before_test() -> void:
	_grid = WorldGridScript.new()
	_grid._init_arrays()
	auto_free(_grid)
	_inventory = InventoryScript.new()
	auto_free(_inventory)
	_player = PlayerCharScript.new()
	add_child(_player)
	auto_free(_player)
	_registry = BuildingRegScript.new()
	auto_free(_registry)
	_registry._inventory_system = _inventory
	_registry._tick_system = null
	_registry.init_dependencies(_grid, _player)
	ProgressionSystem.unlock_all()


func after_test() -> void:
	ProgressionSystem.reset_to_initial()


## Builds a Sawmill (wood input, capacity 10) and returns its building_id.
func _build_sawmill_at(tile: Vector2i) -> String:
	if _inventory.get_container(&"test_supply") == null:
		_inventory.create_container(&"test_supply", "Supply", 9999)
	_inventory.try_deposit(&"test_supply", &"wood", 8)
	_inventory.try_deposit(&"test_supply", &"stone", 3)
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.SAWMILL, tile)
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	var bid: String = str(_registry.get_building_count() - 1)
	_registry.complete_construction_manually(bid)
	return bid


# ---------------------------------------------------------------------------
# reserve_input_slot
# ---------------------------------------------------------------------------

func test_input_reservation_reserve_succeeds_when_slot_empty() -> void:
	var bid: String = _build_sawmill_at(Vector2i(5, 5))
	var ok: bool = _registry.reserve_input_slot(bid, &"wood", HOLDER_A, 3)
	assert_bool(ok).is_true()
	assert_int(_registry.get_input_reserved(bid, &"wood")).is_equal(3)


func test_input_reservation_blocks_foreign_deposit_at_capacity() -> void:
	# SAWMILL input_capacity is 10 (PRODUCTION_TABLE). Reserve 10 → is_input_full true.
	var bid: String = _build_sawmill_at(Vector2i(6, 6))
	_registry.reserve_input_slot(bid, &"wood", HOLDER_A, 10)
	assert_bool(_registry.is_input_full(bid, &"wood")).is_true()


func test_input_reservation_release_frees_slot() -> void:
	var bid: String = _build_sawmill_at(Vector2i(7, 7))
	_registry.reserve_input_slot(bid, &"wood", HOLDER_A, 10)
	_registry.release_input_reservation(bid, HOLDER_A)
	assert_bool(_registry.is_input_full(bid, &"wood")).is_false()
	assert_int(_registry.get_input_reserved(bid, &"wood")).is_equal(0)


func test_input_reservation_holder_replaces_own_previous_reservation() -> void:
	var bid: String = _build_sawmill_at(Vector2i(8, 8))
	_registry.reserve_input_slot(bid, &"wood", HOLDER_A, 4)
	_registry.reserve_input_slot(bid, &"wood", HOLDER_A, 2)
	assert_int(_registry.get_input_reserved(bid, &"wood")).is_equal(2)


func test_input_reservation_receive_with_matching_holder_consumes_reservation() -> void:
	var bid: String = _build_sawmill_at(Vector2i(9, 9))
	_registry.reserve_input_slot(bid, &"wood", HOLDER_A, 5)
	# Fill the unreserved portion first (buffer=5, reserved=5 → is_input_full).
	_registry.receive_input_from_world(bid, &"wood", 5)
	assert_bool(_registry.is_input_full(bid, &"wood")).is_true()
	# Holder's deposit still fits — consumes reservation.
	var ok: bool = _registry.receive_input_from_world(bid, &"wood", 5, HOLDER_A)
	assert_bool(ok).is_true()
	assert_int(_registry.get_input_reserved(bid, &"wood")).is_equal(0)


func test_input_reservation_foreign_deposit_blocked_when_only_reserved_space_left() -> void:
	var bid: String = _build_sawmill_at(Vector2i(10, 10))
	_registry.reserve_input_slot(bid, &"wood", HOLDER_A, 5)
	# 5 free unreserved + 5 reserved = 10 cap. Filling 5 makes foreigners see full.
	_registry.receive_input_from_world(bid, &"wood", 5)
	# Foreign attempt for 1 more must fail.
	var ok: bool = _registry.receive_input_from_world(bid, &"wood", 1)
	assert_bool(ok).is_false()


func test_input_reservation_release_unknown_holder_is_noop() -> void:
	var bid: String = _build_sawmill_at(Vector2i(11, 11))
	_registry.release_input_reservation(bid, &"never_reserved")
	assert_int(_registry.get_input_reserved(bid, &"wood")).is_equal(0)


# is_input_full with holder_id excludes the holder's own reservation — otherwise the
# holder would see "full" the instant it reserves the last free slot and never deliver.
func test_input_reservation_is_input_full_excludes_own_reservation_for_holder() -> void:
	var bid: String = _build_sawmill_at(Vector2i(12, 12))
	# Simulate the bug scenario: 8 wood buffered, carrier reserves the remaining 2.
	_registry.receive_input_from_world(bid, &"wood", 8)
	_registry.reserve_input_slot(bid, &"wood", HOLDER_A, 2)

	# Without holder context: total occupancy reaches capacity → full.
	assert_bool(_registry.is_input_full(bid, &"wood")).is_true()
	# Foreign holder: also sees full (HOLDER_A's reservation counts as foreign).
	assert_bool(_registry.is_input_full(bid, &"wood", &"other_route")).is_true()
	# The holder itself: own reservation is excluded → only 8 used, 2 cap left → not full.
	assert_bool(_registry.is_input_full(bid, &"wood", HOLDER_A)).is_false()
