extends Node
## WildSystem — Autoload. Tracks "wild" (game) living in forests.
## A forest is a 4-connected component of TREE tiles. A forest of at least
## FOREST_MIN_TILES tiles can host wild groups, capacity = size / TILES_PER_GROUP.
## Wild spawns and moves once per day (TickSystem.day_transition). All wild behaviour
## is gated by the map's "wild" fertility. ADR-0015 (Map Fertility System).
##
## WorldGrid is injected via set_grid_map() (it is not an Autoload). Group state is
## serialized; forests are recomputed from terrain on load (decision 2026-06-18).

# ---- Signals ----------------------------------------------------------------

## Emitted whenever the set of wild groups changes (daily update, terrain change, load).
signal wild_changed()

# ---- Tuning -----------------------------------------------------------------

const FOREST_MIN_TILES: int = 10   ## minimum contiguous tree tiles for wild to appear
const TILES_PER_GROUP: int = 10    ## one wild group capacity per this many tiles
const SPAWN_CHANCE: float = 0.10   ## per eligible under-capacity forest, per day
const MOVE_CHANCE: float = 0.50    ## per group, per day

# ---- State ------------------------------------------------------------------

var _grid: Node = null
## Array of forests; each forest is an Array[Vector2i] of its TREE tiles.
var _forests: Array = []
## tile (Vector2i) → forest index into _forests.
var _tile_forest: Dictionary = {}
## Wild group positions — one entry per group (each a TREE tile coordinate).
var _groups: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()

# ---- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	_rng.randomize()
	TickSystem.day_transition.connect(_on_day_transition)
	# Save/load is driven by WorldSaveManager.SAVE_SYSTEMS / LOAD_ORDER (WildSystem is listed there).


## Injects the WorldGrid and connects terrain-change recomputation. Does NOT seed wild —
## call initialize_for_new_map() after grid.generate(), or deserialize() on load.
func set_grid_map(grid: Node) -> void:
	_grid = grid
	if _grid != null and _grid.has_signal("terrain_tile_changed"):
		if not _grid.terrain_tile_changed.is_connected(_on_terrain_tile_changed):
			_grid.terrain_tile_changed.connect(_on_terrain_tile_changed)


## Recomputes forests and seeds one wild group per eligible forest.
## Call once after a fresh grid.generate() on a new game.
func initialize_for_new_map() -> void:
	_groups.clear()
	_recompute_forests()
	if _grid != null and _grid.has_fertility(&"wild"):
		for idx in range(_forests.size()):
			var forest: Array = _forests[idx]
			if forest.size() >= FOREST_MIN_TILES:
				_groups.append(forest[_rng.randi_range(0, forest.size() - 1)])
	wild_changed.emit()

# ---- Daily simulation -------------------------------------------------------

func _on_day_transition(_day: int) -> void:
	if _grid == null or not _grid.has_fertility(&"wild"):
		return
	_recompute_forests()
	_prune_groups()
	_spawn_groups()
	_move_groups()
	wild_changed.emit()


## Removes groups whose tile is no longer part of an eligible forest (trees cleared).
func _prune_groups() -> void:
	var kept: Array[Vector2i] = []
	for g: Vector2i in _groups:
		var idx: int = _tile_forest.get(g, -1)
		if idx == -1:
			continue
		if _forests[idx].size() < FOREST_MIN_TILES:
			continue
		kept.append(g)
	_groups = kept


## Each eligible, under-capacity forest has SPAWN_CHANCE to gain a new group.
func _spawn_groups() -> void:
	for idx in range(_forests.size()):
		var forest: Array = _forests[idx]
		if forest.size() < FOREST_MIN_TILES:
			continue
		if _count_groups_in_forest(idx) >= forest.size() / TILES_PER_GROUP:
			continue
		if _rng.randf() < SPAWN_CHANCE:
			_groups.append(forest[_rng.randi_range(0, forest.size() - 1)])


## Each group has MOVE_CHANCE to step to a random adjacent tree tile (stays in-forest).
func _move_groups() -> void:
	for i in range(_groups.size()):
		if _rng.randf() >= MOVE_CHANCE:
			continue
		var g: Vector2i = _groups[i]
		var neighbors: Array[Vector2i] = []
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = g + off
			if _grid.is_in_bounds(n) and _grid.get_terrain(n) == WorldGrid.TileType.TREE:
				neighbors.append(n)
		if not neighbors.is_empty():
			_groups[i] = neighbors[_rng.randi_range(0, neighbors.size() - 1)]

# ---- Forest analysis --------------------------------------------------------

## Flood-fills all 4-connected TREE components into _forests / _tile_forest.
func _recompute_forests() -> void:
	_forests.clear()
	_tile_forest.clear()
	if _grid == null:
		return
	var visited: Dictionary = {}
	for x in range(WorldGrid.GRID_SIZE):
		for y in range(WorldGrid.GRID_SIZE):
			var t := Vector2i(x, y)
			if visited.has(t):
				continue
			if _grid.get_terrain(t) != WorldGrid.TileType.TREE:
				continue
			var comp: Array[Vector2i] = []
			var queue: Array[Vector2i] = [t]
			visited[t] = true
			while not queue.is_empty():
				var cur: Vector2i = queue.pop_back()
				comp.append(cur)
				for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cur + off
					if not _grid.is_in_bounds(n) or visited.has(n):
						continue
					if _grid.get_terrain(n) != WorldGrid.TileType.TREE:
						continue
					visited[n] = true
					queue.append(n)
			var idx: int = _forests.size()
			_forests.append(comp)
			for c: Vector2i in comp:
				_tile_forest[c] = idx


func _on_terrain_tile_changed(_tile: Vector2i) -> void:
	if _grid == null:
		return
	_recompute_forests()
	_prune_groups()
	wild_changed.emit()


func _count_groups_in_forest(idx: int) -> int:
	var c: int = 0
	for g: Vector2i in _groups:
		if _tile_forest.get(g, -1) == idx:
			c += 1
	return c

# ---- Query API --------------------------------------------------------------

## Returns the forest index whose TREE tiles include tile, or -1.
func get_forest_id_at(tile: Vector2i) -> int:
	return _tile_forest.get(tile, -1)


## True when at least one forest adjacent to (8-neighbour) tile holds a wild group.
## Used by BuildingRegistry to gate Hunting Lodge placement.
func forest_has_wild_adjacent(tile: Vector2i) -> bool:
	return count_groups_adjacent(tile) > 0


## Number of wild groups across the distinct forests adjacent (8-neighbour) to tile.
## Drives Hunting Lodge efficiency.
func count_groups_adjacent(tile: Vector2i) -> int:
	if _grid == null:
		return 0
	var seen: Dictionary = {}
	for n: Vector2i in _grid.get_neighbors(tile, true):
		var idx: int = _tile_forest.get(n, -1)
		if idx != -1:
			seen[idx] = true
	var total: int = 0
	for idx: int in seen:
		total += _count_groups_in_forest(idx)
	return total


## Returns a copy of all wild group tile positions (for the deer overlay).
func get_group_tiles() -> Array[Vector2i]:
	return _groups.duplicate()

# ---- Serialization ----------------------------------------------------------

func serialize() -> Dictionary:
	var arr: Array = []
	for g: Vector2i in _groups:
		arr.append({"x": g.x, "y": g.y})
	return {"groups": arr}


func deserialize(data: Dictionary) -> void:
	_recompute_forests()
	_groups.clear()
	for e: Dictionary in data.get("groups", []):
		var t := Vector2i(e.get("x", -1), e.get("y", -1))
		if _grid != null and _grid.is_in_bounds(t):
			_groups.append(t)
	wild_changed.emit()
