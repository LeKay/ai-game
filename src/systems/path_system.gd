extends Node
## PathSystem — Autoload singleton for auto-tiling path placement.
## Maintains the path data layer and resolves tile variants from 4-bit neighbor bitmasks.
## Autoload: registered as "PathSystem" in project.godot.
## ADR: paths overlay on EMPTY terrain tiles, cost 0.5 movement vs 1.0 open ground.

## Bitmask bits — N=1, E=2, S=4, W=8.
const BITMASK_N: int = 1
const BITMASK_E: int = 2
const BITMASK_S: int = 4
const BITMASK_W: int = 8

## Sentinel passed through BuildingGrid so InventoryScreen can distinguish path clicks.
const PATH_SENTINEL: int = -100
## Ticks required for a player to manually build one path tile.
const PATH_CONSTRUCTION_TICKS: int = 120
## Energy the player spends to build one path tile.
const PATH_ENERGY_COST: int = 10

enum PathPlacementResult {
	SUCCESS,
	BLOCKED_BY_BOUNDS,
	BLOCKED_BY_IMPASSABLE,
	BLOCKED_BY_BUILDING,
	BLOCKED_BY_RESOURCE,
	ALREADY_HAS_PATH,
	ALREADY_CONSTRUCTING,
}

## 4-bit bitmask → texture asset path.
## Dead-ends (1,2,4,8) and isolated (0) fall back to the nearest-matching available tile.
const PATH_TEXTURES: Dictionary = {
	0:  "res://assets/art/tiles/path/env_tile_path_nesw.png",  # isolated — fallback
	1:  "res://assets/art/tiles/path/env_tile_path_ns.png",    # N dead-end
	2:  "res://assets/art/tiles/path/env_tile_path_ew.png",    # E dead-end
	3:  "res://assets/art/tiles/path/env_tile_path_ne.png",    # NE corner
	4:  "res://assets/art/tiles/path/env_tile_path_ns.png",    # S dead-end
	5:  "res://assets/art/tiles/path/env_tile_path_ns.png",    # NS straight
	6:  "res://assets/art/tiles/path/env_tile_path_se.png",    # SE corner
	7:  "res://assets/art/tiles/path/env_tile_path_nes.png",   # NES T-junction
	8:  "res://assets/art/tiles/path/env_tile_path_ew.png",    # W dead-end
	9:  "res://assets/art/tiles/path/env_tile_path_nw.png",    # NW corner
	10: "res://assets/art/tiles/path/env_tile_path_ew.png",    # EW straight
	11: "res://assets/art/tiles/path/env_tile_path_new.png",   # NEW T-junction
	12: "res://assets/art/tiles/path/env_tile_path_sw.png",    # SW corner
	13: "res://assets/art/tiles/path/env_tile_path_nsw.png",   # NSW T-junction
	14: "res://assets/art/tiles/path/env_tile_path_esw.png",   # ESW T-junction
	15: "res://assets/art/tiles/path/env_tile_path_nesw.png",  # NESW crossroads
}

## Emitted when construction begins on a path tile (tile is not yet passable).
signal path_construction_started(tile: Vector2i)
## Emitted when a path tile finishes construction and becomes passable.
signal path_placed(tile: Vector2i)
## Emitted when an existing path tile's bitmask changes (neighbor added or removed).
signal path_updated(tile: Vector2i)
## Emitted when a path tile is removed.
signal path_removed(tile: Vector2i)

var _grid: WorldGrid = null
## Vector2i → true for every tile that has a completed path.
var _paths: Dictionary = {}
## Vector2i → elapsed ticks for tiles currently under construction.
var _constructing: Dictionary = {}


## Called from MapRoot._ready() after WorldGrid is available.
func init_dependencies(grid: WorldGrid) -> void:
	_grid = grid


## Returns true if tile has a completed (passable) path.
func has_path(tile: Vector2i) -> bool:
	return _paths.has(tile)


## Returns true if tile has a path under construction (not yet passable).
func is_constructing(tile: Vector2i) -> bool:
	return _constructing.has(tile)



## Validates placement without mutating state. Safe to call before init_dependencies.
func validate_placement(tile: Vector2i) -> PathPlacementResult:
	if _grid == null:
		return PathPlacementResult.BLOCKED_BY_BOUNDS
	if not _grid.is_in_bounds(tile):
		return PathPlacementResult.BLOCKED_BY_BOUNDS
	if not _grid.is_passable(tile):  # IMPASSABLE or WATER
		return PathPlacementResult.BLOCKED_BY_IMPASSABLE
	if _grid.get_terrain(tile) != WorldGrid.TileType.EMPTY:
		return PathPlacementResult.BLOCKED_BY_RESOURCE
	if _grid.get_building(tile) != "":
		return PathPlacementResult.BLOCKED_BY_BUILDING
	if has_path(tile):
		return PathPlacementResult.ALREADY_HAS_PATH
	if is_constructing(tile):
		return PathPlacementResult.ALREADY_CONSTRUCTING
	return PathPlacementResult.SUCCESS


## Begins construction of a path tile. Returns true on success.
## Emits path_construction_started; path_placed fires when construction completes.
func initiate_path(tile: Vector2i) -> bool:
	if validate_placement(tile) != PathPlacementResult.SUCCESS:
		return false
	_constructing[tile] = 0
	path_construction_started.emit(tile)
	return true


## Finalizes construction of a path tile started by initiate_path(). Called by PlayerCharacter.
## Returns true on success.
func complete_construction(tile: Vector2i) -> bool:
	if not _constructing.has(tile):
		return false
	_constructing.erase(tile)
	_paths[tile] = true
	path_placed.emit(tile)
	_notify_cardinal_neighbors(tile)
	return true


## Places a path tile instantly (used by deserialize / editor tools). Returns true on success.
## Emits path_placed for this tile, then path_updated for all 4 cardinal neighbors that have paths.
func place_path(tile: Vector2i) -> bool:
	if validate_placement(tile) != PathPlacementResult.SUCCESS:
		return false
	_paths[tile] = true
	path_placed.emit(tile)
	_notify_cardinal_neighbors(tile)
	return true


## Removes a path tile. Returns true if a path was present.
func remove_path(tile: Vector2i) -> bool:
	if not has_path(tile):
		return false
	_paths.erase(tile)
	path_removed.emit(tile)
	_notify_cardinal_neighbors(tile)
	return true


## Emits path_updated for all 4 cardinal neighbors that have paths.
## Call this when a building is placed next to existing paths.
func update_neighbors(tile: Vector2i) -> void:
	_notify_cardinal_neighbors(tile)


## Returns the asset path for the correct path tile variant at tile.
func get_texture_path(tile: Vector2i) -> String:
	return PATH_TEXTURES.get(compute_bitmask(tile), PATH_TEXTURES[15])


## Returns the 4-bit connection bitmask for a tile.
## A direction bit is set when that neighbor has a path OR a building.
func compute_bitmask(tile: Vector2i) -> int:
	var bitmask: int = 0
	if _connects(tile + Vector2i(0, -1)):
		bitmask |= BITMASK_N
	if _connects(tile + Vector2i(1, 0)):
		bitmask |= BITMASK_E
	if _connects(tile + Vector2i(0, 1)):
		bitmask |= BITMASK_S
	if _connects(tile + Vector2i(-1, 0)):
		bitmask |= BITMASK_W
	return bitmask


func _connects(neighbor: Vector2i) -> bool:
	if _grid == null or not _grid.is_in_bounds(neighbor):
		return false
	return has_path(neighbor) or is_constructing(neighbor) or _grid.get_building(neighbor) != ""


func _notify_cardinal_neighbors(tile: Vector2i) -> void:
	for offset: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Vector2i = tile + offset
		if has_path(n):
			path_updated.emit(n)


# ── Save / Load ────────────────────────────────────────────────────────────────

## Serializes all placed path tiles as an array of {x, y} dictionaries.
func serialize() -> Array:
	var result: Array = []
	for tile: Vector2i in _paths:
		result.append({"x": tile.x, "y": tile.y})
	return result


## Restores path tiles from a serialized snapshot.
## Repopulates the full path set first, then emits path_placed for each tile so the
## renderer can spawn sprites with bitmasks that already see every neighbor.
func deserialize(snapshots: Array) -> void:
	_paths.clear()
	for snap: Dictionary in snapshots:
		var tile := Vector2i(int(snap.get("x", 0)), int(snap.get("y", 0)))
		_paths[tile] = true
	for tile: Vector2i in _paths:
		path_placed.emit(tile)
