## GdUnit4 integration test suite for Building System Story 001:
## Placement and Construction.
##
## Tests wire BuildingRegistry with real WorldGrid, InventorySystem, and
## PlayerCharacter instances without relying on Autoload singletons.

extends GdUnitTestSuite

const WorldGridScript    := preload("res://src/systems/world_grid.gd")
const BuildingRegScript  := preload("res://src/gameplay/building_registry.gd")
const InventoryScript    := preload("res://src/systems/inventory/inventory_system.gd")
const PlayerCharScript   := preload("res://src/systems/player_character.gd")

# ---- Test fixtures ----------------------------------------------------------

var _registry: BuildingRegScript
var _grid: WorldGridScript
var _inventory: InventoryScript
var _player: PlayerCharScript

## Shared container used in resource-cost tests.
const SUPPLY_CONTAINER: StringName = &"test_supply"


func before_each() -> void:
	# Build WorldGrid without the scene tree (_init_arrays replaces _ready).
	_grid = WorldGridScript.new()
	_grid._init_arrays()
	auto_free(_grid)

	# Real InventorySystem instance (not registered as Autoload).
	_inventory = InventoryScript.new()
	auto_free(_inventory)

	# PlayerCharacter needs its own _ready() to initialise _energy_pool.
	_player = PlayerCharScript.new()
	add_child(_player)
	auto_free(_player)

	# BuildingRegistry — bypass Engine.get_singleton() by injecting directly.
	_registry = BuildingRegScript.new()
	auto_free(_registry)
	_registry._inventory_system = _inventory
	_registry._tick_system = null  # tick system not needed for placement tests
	_registry.init_dependencies(_grid, _player)


# ---- Helper: seed a container with resources --------------------------------

func _seed_resources(resource_id: StringName, quantity: int) -> void:
	if _inventory.get_container(SUPPLY_CONTAINER) == null:
		_inventory.create_container(SUPPLY_CONTAINER, "Supply", 999)
	_inventory.try_deposit(SUPPLY_CONTAINER, resource_id, quantity)


# ---- Storage Area: instant OPERATING ----------------------------------------

func test_storage_area_placed_enters_operating_immediately() -> void:
	# Arrange
	var tile := Vector2i(5, 5)

	# Act
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)

	# Assert
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance("0")
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


func test_storage_area_creates_inventory_container() -> void:
	# Arrange
	var tile := Vector2i(3, 3)

	# Act
	_registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)

	# Assert
	var expected_id: StringName = StringName("storage_%d_%d" % [tile.x, tile.y])
	assert_bool(_inventory.get_container(expected_id) != null).is_true()
	assert_int(_inventory.get_capacity(expected_id)).is_equal(50)


# ---- Storage Building: CONSTRUCTING state -----------------------------------

func test_storage_building_enters_constructing_state() -> void:
	# Arrange
	_seed_resources(&"wood", 8)
	_seed_resources(&"stone", 2)
	var tile := Vector2i(7, 7)

	# Act
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_BUILDING, tile)

	# Assert
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.SUCCESS)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance("0")
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.CONSTRUCTING)


func test_storage_building_transitions_to_operating_after_build_time() -> void:
	# Arrange
	_seed_resources(&"wood", 8)
	_seed_resources(&"stone", 2)
	var tile := Vector2i(7, 7)
	_registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_BUILDING, tile)
	var instance: BuildingRegScript.BuildingInstance = _registry.get_building_instance("0")

	# Act — advance exactly build_time ticks
	_registry._on_ticks_advanced(120)

	# Assert
	assert_int(instance.state).is_equal(BuildingRegScript.BuildingInstance.State.OPERATING)


# ---- Placement blocking -----------------------------------------------------

func test_placement_blocked_by_impassable_tile() -> void:
	# Arrange
	var tile := Vector2i(10, 10)
	_grid._terrain[tile.x][tile.y] = WorldGridScript.TileType.IMPASSABLE

	# Act
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)

	# Assert
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.BLOCKED_BY_IMPASSABLE)


func test_placement_blocked_by_existing_building() -> void:
	# Arrange
	var tile := Vector2i(11, 11)
	_grid._buildings[tile.x][tile.y] = "pre_existing"

	# Act
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)

	# Assert
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.BLOCKED_BY_BUILDING)


func test_placement_blocked_by_out_of_bounds() -> void:
	# Arrange
	var tile := Vector2i(-1, 0)

	# Act
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)

	# Assert
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.BLOCKED_BY_BOUNDS)


func test_placement_blocked_by_nonclearable_resource() -> void:
	# Arrange
	var tile := Vector2i(12, 12)
	var res := WorldGridScript.ResourceTileData.new(&"stone", false)
	_grid._resources[tile.x][tile.y] = [res]

	# Act
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)

	# Assert
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.BLOCKED_BY_RESOURCE_TILE)


# ---- Energy cost ------------------------------------------------------------

func test_energy_cost_deducted_on_placement() -> void:
	# Arrange — STORAGE_BUILDING costs 8+2=10 resources → floor(10 * 0.10) = 1 energy
	_seed_resources(&"wood", 8)
	_seed_resources(&"stone", 2)
	var energy_before: int = _player.get_current_energy()
	var tile := Vector2i(6, 6)

	# Act
	_registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_BUILDING, tile)

	# Assert
	var energy_after: int = _player.get_current_energy()
	assert_int(energy_after).is_equal(energy_before - 1)


func test_placement_blocked_when_insufficient_energy() -> void:
	# Arrange — drain all energy so placement is impossible
	_seed_resources(&"wood", 8)
	_seed_resources(&"stone", 2)
	# STORAGE_BUILDING energy cost = 1; drain player to 0
	_player._energy_pool.current = 0
	var tile := Vector2i(6, 6)

	# Act
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_BUILDING, tile)

	# Assert
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.INSUFFICIENT_ENERGY)


# ---- Signal emission --------------------------------------------------------

func test_building_placed_signal_emitted() -> void:
	# Arrange
	var tile := Vector2i(2, 2)
	var signal_monitor := monitor_signals(_registry)

	# Act
	_registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)

	# Assert
	assert_signal_emitted(signal_monitor, "building_placed")


func test_construction_complete_signal_emitted_after_ticks() -> void:
	# Arrange
	_seed_resources(&"wood", 8)
	_seed_resources(&"stone", 2)
	var tile := Vector2i(8, 8)
	_registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_BUILDING, tile)
	var signal_monitor := monitor_signals(_registry)

	# Act — advance enough ticks to complete construction
	_registry._on_ticks_advanced(120)

	# Assert
	assert_signal_emitted(signal_monitor, "building_construction_complete")


# ---- Resource handling ------------------------------------------------------

func test_clearable_resource_removed_on_placement() -> void:
	# Arrange
	var tile := Vector2i(4, 4)
	var res := WorldGridScript.ResourceTileData.new(&"wood", true)
	_grid._resources[tile.x][tile.y] = [res]

	# Act
	_registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_AREA, tile)

	# Assert — WorldGrid resource layer cleared
	assert_int(_grid._resources[tile.x][tile.y].size()).is_equal(0)


func test_resources_deducted_from_inventory_on_placement() -> void:
	# Arrange — provide exactly the cost
	_seed_resources(&"wood", 8)
	_seed_resources(&"stone", 2)
	var tile := Vector2i(9, 9)

	# Act
	_registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_BUILDING, tile)

	# Assert — supply container fully consumed
	assert_int(_inventory.get_resource_quantity(SUPPLY_CONTAINER, &"wood")).is_equal(0)
	assert_int(_inventory.get_resource_quantity(SUPPLY_CONTAINER, &"stone")).is_equal(0)


func test_insufficient_resources_blocks_placement() -> void:
	# Arrange — provide only 4 wood, need 8
	_seed_resources(&"wood", 4)
	var tile := Vector2i(13, 13)

	# Act
	var result: int = _registry.initiate_build(BuildingRegScript.BuildingType.STORAGE_BUILDING, tile)

	# Assert
	assert_int(result).is_equal(BuildingRegScript.PlacementResult.INSUFFICIENT_RESOURCES)
	# Grid must remain empty (no partial commit)
	assert_bool(_grid._buildings[tile.x][tile.y] == null).is_true()
