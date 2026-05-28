# Grid/Map System

> **Status**: In Design
> **Author**: User + Claude
> **Last Updated**: 2026-05-08
> **Implements Pillar**: Pillar 2 (Information Transparency), Pillar 3 (Optimization Over Expansion)

## Overview

The Grid/Map System is the spatial foundation of the game world — a procedurally generated tile grid that serves as the canvas for all gameplay. It generates a finite world (30×30 tiles for the Vertical Slice) using noise-based algorithms that place resource nodes (trees, stone outcrops, grassy meadows, berry bushes) in clusters and patterns that mirror natural landscapes. Each tile carries a type (empty, resource, impassable) and the grid exposes simple queries — `get_tile(x, y)`, `get_tiles_in_radius(center, radius)` — used by every other system for placement validation, pathfinding distance, and resource discovery. The grid is layer-based: a base terrain layer, a resource overlay layer, and a building layer, allowing independent updates without invalidating the whole map.

For the player, the map is the first thing they see and the thing they spend the most time looking at. The satisfying moment of scanning a newly generated landscape and mentally planning where to build — the ridge for housing, the forest edge for the lumber camp, the open meadow for fields — is the spatial equivalent of reading a chessboard. The world is different every game, but it always feels *right* — dense enough to sustain growth, open enough to allow room to breathe.

## Player Fantasy

This is the moment the map stops being blank ground and starts being *potential*. You see a cluster of trees near a grassy patch and think: "A woodcutter's hut goes here, and the workers sleep nearby." The world didn't hand you a blueprint — it handed you raw material, and your mind does the rest. The first time this happens, it's quiet: no fanfare, no arrow pointing the way. Just the faint thrill of seeing a pattern in the noise and recognizing it as *your* pattern.

This feeling compounds. You notice stone outcrops you would have missed yesterday. You think in layers instinctively — terrain first, resources second, building placement third. The map doesn't change; *you* do. This is earned perception — not just earned automation, but earned eyes. Every glance makes the landscape more legible, every decision reveals a new relationship between terrain, resources, and the chains you're trying to build.

By the time your village runs without you, you've internalized every ridge, every resource cluster, every bottleneck. You don't look at the map anymore — you *inhabit* it. And when something breaks, you close your eyes and can still see it perfectly, because the map isn't something on screen. It's in your head.

**What it serves:** Pillar 2 (Information Transparency — the map is legible, not mysterious) and Pillar 3 (Optimization Over Expansion — mastery comes from reading what's there, not from seeking new territory). Ties directly to the "From Scratch" identity — every decision begins with seeing raw potential and transforming it into something built.

## Detailed Design

### Core Rules

**1. Grid Data Model**

The grid is a fixed-size 2D array (`GRID_SIZE × GRID_SIZE`, 30×30 for Vertical Slice) organized into three conceptual layers. Each layer is a separate 2D array with independent mutability rules.

**Layer structure:**

| Layer | What It Stores | Mutability | Write Access |
|-------|---------------|------------|--------------|
| **TerrainLayer** | Base terrain type: `EMPTY`, `TREE`, `STONE`, `BERRY`, `GRASS`, `IMPASSABLE` | Write-once at generation | MapGenerator only (set during `_ready()`) |
| **ResourceLayer** | Resource tile data: `resource_id`, `clearable` (whether the resource can be removed for building) | Mutable | MapGenerator (generation), Building System (clear on placement), dedicated buildings (replant) |
| **BuildingLayer** | Building instance on tile: `building_id` or `null` | Mutable | Building System (place/remove) |

**Tile data model per layer:**

```
TerrainLayer[c][r]: TileType (enum — single value per tile)
ResourceLayer[c][r]: { resource_id: String, clearable: bool }? (null = no resource)
BuildingLayer[c][r]: String? (building_id or null)
```

**Composite tile view** (read-only, for rendering and UI):
```
TileView = { terrain: TileType, resource: ResourceTileData?, building_id: String? }
```

**2. Procedural Generation Pipeline**

The MapGenerator creates the grid in 5 steps:

**Step 1 — Perlin Noise Sampling**

Create two `PerlinNoise` instances with configurable seeds and sample each tile:

```gdscript
var elevation_noise := FastNoise.new()
elevation_noise.noise_type = FastNoise.TYPE_PERLIN
elevation_noise.seed = terrain_seed
elevation_noise.octaves = 4
elevation_noise.persistence = 0.5
elevation_noise.lacunarity = 2.0
elevation_noise.scale = Vector2(9.0, 9.0)

var moisture_noise := FastNoise.new()
moisture_noise.noise_type = FastNoise.TYPE_PERLIN
moisture_noise.seed = terrain_seed + 1
moisture_noise.octaves = 3
moisture_noise.persistence = 0.5
moisture_noise.lacunarity = 2.0
moisture_noise.scale = Vector2(9.0, 9.0)
```

Each call to `elevation_noise.get_noise_2d(x, y)` and `moisture_noise.get_noise_2d(x, y)` returns a float in `[-1.0, 1.0]`. Normalize to `[0.0, 1.0]` via `(value + 1.0) / 2.0`.

**Step 2 — Threshold Segmentation**

Combine elevation and moisture into terrain type using thresholds:

| Elevation | Moisture | Tile Type | Resource? | Target % |
|-----------|----------|-----------|-----------|----------|
| Low (< 0.15) | Any | `IMPASSABLE` | No | ~15% |
| Low-Mid (0.15–0.30) | Low (< 0.5) | `BERRY` | Yes (berries) | ~15% |
| Low-Mid (0.15–0.30) | High (≥ 0.5) | `GRASS` | Yes (fiber) | ~15% |
| Mid (0.30–0.55) | Any | `EMPTY` | No | ~20% |
| High-Mid (0.55–0.75) | Any | `TREE` | Yes (wood) | ~15% |
| High (> 0.75) | Any | `STONE` | Yes (stone) | ~20% |

**Step 3 — Smoothing Pass (2 iterations)**

For each tile, count 8-way neighbor types. With 60% probability, replace the tile with the most common neighbor type. This creates blobby, natural-looking clusters without eliminating small valid patches.

**Step 4 — Cluster Cleanup**

Flood-fill connected components. Destroy any cluster smaller than 3 tiles by converting it to `EMPTY`. Rationale: a 1–2 tile resource cluster is unusable — no worker can harvest meaningfully from it, and it wastes visual space.

**Step 5 — Minimum Count Verification**

After generation, verify minimum resource counts. If insufficient, regenerate with a different seed (max 5 attempts, then force-fix by converting `EMPTY` tiles to required resources).

**Map persistence:** Each game has exactly one map. There is no "Regenerate Map" feature for player use — the generated layout is final. This preserves the "earned perception" fantasy: you learn the map you have, not optimize for a better one.

Minimum counts (Vertical Slice): `TREE ≥ 8`, `STONE ≥ 4`, `BERRY ≥ 6`, `GRASS ≥ 6`.

**3. TileMapLayer Rendering Architecture**

The grid renders via Godot 4.6 `TileMapLayer` nodes — one per visual layer. `TileMap` is deprecated since Godot 4.3; do not use it.

**Scene tree:**
```
MapRoot (Node2D)
├── TerrainLayer (TileMapLayer) — terrain tiles
├── ResourceOverlay (TileMapLayer) — resource indicator tiles
└── BuildingSlots (TileMapLayer) — 1×1 placement slots (visual only)
```

**Tile size: 48×48 pixels.** This gives a 1440×1440 pixel map viewport, fitting on 1920×1080 with UI overhead. Camera zoom range: 0.75×–1.25×.

**Terrain tiles use atlas tiles** (shared texture, single draw call per TileSet). Buildings are NOT represented as tiles — they are instantiated `PackedScene` nodes placed at tile grid positions. This gives full per-building logic (scripts, signals, animations) while keeping tile-based placement validation.

**4. Building Placement Validation**

A single gate function is the source of truth for all placement decisions:

```
func validate_placement(x, y, building_id) -> PlacementResult:
    if out_of_bounds(x, y):          return BLOCKED_BY_BOUNDS
    if is_impassable(x, y):          return BLOCKED_BY_IMPASSABLE
    if has_building(x, y):           return BLOCKED_BY_BUILDING
    if has_resource(x, y):
        if not resource_tile_is_clearable(x, y):
            return BLOCKED_BY_RESOURCE_TILE  // e.g., Stone is not clearable
    return SUCCESS
```

`PlacementResult` is an enum: `SUCCESS`, `BLOCKED_BY_BOUNDS`, `BLOCKED_BY_IMPASSABLE`, `BLOCKED_BY_BUILDING`, `BLOCKED_BY_RESOURCE_TILE`.

**Resource tile clearability:** Not all resource tiles can be cleared. Clearable resource tiles (tree, berry, grass) are removed when a building is placed on them. Non-clearable resource tiles (stone) cannot be removed — buildings cannot be placed on them. The clearable flag is determined by the resource type and stored in the ResourceLayer data model. Resources are infinite Anno-style spatial anchors: a tile either has a resource or it does not. Resources do not regrow, replenish, or change state after generation — placement on a resource tile permanently removes it.

The UI queries this function for ghost-building preview (green = success, red = blocked with tooltip showing reason). The Building System calls it before every placement. The Camera System can use it for hover validation.

**5. Grid Query API**

The Grid class exposes these public methods. All access is bounds-checked; out-of-bounds queries raise a fatal assertion (should never happen with proper input handling).

**Core queries:**

| Method | Returns | Description |
|--------|---------|-------------|
| `get_terrain(x, y)` | `TileType` | Base terrain type |
| `get_resource(x, y)` | `ResourceTileData?` | Resource data or null |
| `get_building(x, y)` | `String?` | Building ID or null |
| `is_passable(x, y)` | `bool` | False only for `IMPASSABLE` |
| `get_tile_view(x, y)` | `TileView` | Composite read-only snapshot of all layers |

**Spatial queries:**

| Method | Returns | Description |
|--------|---------|-------------|
| `get_tiles_in_radius(cx, cy, radius)` | `Array[Vector2i]` | All valid tile coords within radius (square bounding box). **IMPORTANT:** This is a square bounding box, NOT a circular radius. Callers requiring a true CIRCULAR radius must post-filter results by `euclidean_distance(center, tile) <= radius`. The square approach is faster for initial filtering — most irrelevant tiles are eliminated by the square check, then callers apply the circular filter to the remaining subset. |
| `get_neighbors(x, y, diagonals)` | `Array[Vector2i]` | 4 or 8 adjacent tiles |
| `find_nearest(x, y, resource_id, max_radius)` | `Vector2i?` | Closest tile with matching resource (Manhattan distance, expanding radius) |
| `find_tiles_by_predicate(predicate_fn)` | `Array[Vector2i]` | All tile coords matching the predicate function |

**Mutations (write operations):**

| Method | Returns | Description |
|--------|---------|-------------|
| `place_building(x, y, building_id)` | `PlacementResult` | Validate placement + update BuildingLayer |
| `remove_building(x, y)` | `bool` | Remove building, return success |
| `harvest_resource(x, y, amount)` | `int` | Remove `amount` from resource, return actual yielded |

**Distance calculations:**

| Method | Returns | Description |
|--------|---------|-------------|
| `distance_between(a, b, metric)` | `float` | Manhattan (default) or Euclidean distance between two tile coords |

**Manhattan distance** (`|x1 - x2| + |y1 - y2|`) is the default and primary distance metric. It maps to grid-based movement (each tile crossed = 1 step) and is used by Logistics System for transport time calculations. Euclidean is available for radius queries where circular proximity matters (e.g., Anno-style resource tile in radius).

**6. Tile Size and Coordinate Conversion**

Tile size: **48×48 pixels**. World pixel coordinates convert to tile coordinates via:

```
tile_x = floor(pixel_x / TILE_SIZE)
tile_y = floor(pixel_y / TILE_SIZE)
pixel_x = tile_x * TILE_SIZE + TILE_SIZE / 2  (center of tile)
```

Mouse-to-tile conversion (used by Input System → Manual Labor / Building):
```
world_pos = camera_offset + (screen_pos / camera_zoom)
tile_coord = Vector2i(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))
```

**7. Engine Integration (Godot 4.6)**

- **TileMapLayer**: One node per visual layer (`TerrainLayer`, `ResourceOverlay`, `BuildingSlots`). Each has a `TileSet` with `tile_size = Vector2i(48, 48)`.
- **PerlinNoise**: Godot 4.6 native class. `PerlinNoise.get_noise_2d(x, y)` returns `float` in `[-1.0, 1.0]`. Scale set to `Vector2(MAP_SIZE, MAP_SIZE) × noise_scale`.
- **Building scenes**: Each building is a `PackedScene` instantiated at tile center position (`tile_coord * TILE_SIZE + TILE_SIZE/2`).

**Data ownership (critical):** The Grid class is the sole owner of all tile data (TerrainLayer, ResourceLayer, BuildingLayer arrays). TileMapLayer nodes are pure rendering targets with no independent state. All game state queries use Grid methods. `TileMapLayer.get_cell()` is NEVER called from gameplay code — this is a hard constraint.

**Data flow (unidirectional):**
1. On generation: Grid fills arrays → Grid calls `TileMapLayer.set_cell()` for every tile in one batch.
2. On building placement: Grid updates BuildingLayer → instantiates PackedScene.
3. On building removal: Grid updates BuildingLayer → calls `building_instance.queue_free()`.
4. On resource tile clear: Grid updates ResourceLayer → calls `TileMapLayer.set_cell()` for that tile.
5. **Reads never go the other direction.** Any code reading `TileMapLayer.get_cell()` to determine game state is a bug.

**Depth sorting:** All game objects that need proper depth ordering (buildings, characters, items) must be children of a `YSort` node (`y_sort_enabled = true` on `Node2D`). Direct children of `MapRoot` do NOT receive Y-sorting. This is a non-negotiable pattern for top-down 2D rendering in Godot 4.

- **Performance**: 30×30 grid = 900 tiles. All queries are O(n) in query size, bounded by grid dimensions. No optimization needed for Vertical Slice.

### States and Transitions

The Grid/Map System itself has no simulation states — it is a data registry and spatial query layer. However, individual **tiles** have state transitions (resources are cleared or added, buildings are placed and removed).

**Tile State Transitions (ResourceLayer):**

| State | Description | Transition Trigger |
|-------|-------------|-------------------|
| **Present** | Resource tile has a resource | Set during generation |
| **Not present** | Resource removed from tile | Building placement on clearable resource tile |

Resources are infinite Anno-style spatial anchors — a tile either has a resource or it does not. Resources never regrow, replenish, or change state after generation.

**Tile State Transitions (BuildingLayer):**

| State | Description | Transition Trigger |
|-------|-------------|-------------------|
| **Empty** (null) | No building on tile | Default state |
| **Occupied** (building_id set) | Building placed on tile | `place_building()` succeeds |
| **Demolished** (null) | Building removed | `remove_building()` succeeds |

**Terrain Layer is immutable after generation.** No state transitions apply. This is an enforced invariant — any code path attempting to modify TerrainLayer after `_ready()` raises an assertion.

### Interactions with Other Systems

| System | Interaction | Data Flow | Interface |
|--------|-------------|-----------|-----------|
| **Building System** | Validates placement before construction | Building System → Grid: `validate_placement()`, `place_building()` | Grid provides PlacementResult; Building System reads result and shows green/red preview |
| **Manual Labor** | Harvests resources from tiles | Manual Labor → Grid: `harvest_resource(x, y, amount)` | Grid deducts amount from ResourceLayer, returns actual yielded amount |
| **Camera System** | Displays grid, converts mouse to tile coords | Camera → Grid: `get_tile_view()`, `is_passable()` (for hover) | Grid returns TileView; Camera uses tile→pixel conversion for snapping |
| **Logistics System** | Calculates NPC transport distance | Logistics → Grid: `distance_between()`, `get_tiles_in_radius()` | Grid returns tile distance (Manhattan) and radius tiles for path planning |
| **HUD System** | Displays tile info on hover | HUD → Grid: `get_tile_view(x, y)` | Grid returns composite TileView for tooltip display |
| **Production System** | Checks if building has resource tiles in radius (Anno-style) | Production → Grid: `get_tiles_in_radius()` + post-filter by `euclidean_distance <= resource_radius` + filter `has_resource()` | Returns tiles within CIRCULAR radius that match required resource type. Buildings stop producing when no matching resource tiles exist in radius. Square bounding box is used for initial filtering, then callers apply Euclidean distance check. |

## Formulas

### 1. Tile-to-Pixel Coordinate Conversion

Convert tile coordinates to world pixel coordinates and back. This is the bridge between gameplay logic (which operates in tile space) and rendering/input (which operates in pixel space).

**The `tile_to_pixel` formula is defined as:**

`pixel_coord = tile_coord * TILE_SIZE + TILE_SIZE / 2`

**The `pixel_to_tile` formula is defined as:**

`tile_coord = floor(pixel_coord / TILE_SIZE)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| TILE_SIZE | — | int | 32–96 | Pixel size of one tile (tuning knob, default 48) |
| tile_coord | t | Vector2i | (0, 0) to (GRID_SIZE-1, GRID_SIZE-1) | Tile position in grid space |
| pixel_coord | p | Vector2 | (0, 0) to (MAP_PIXEL_WIDTH, MAP_PIXEL_HEIGHT) | Position in world pixel space |
| floor | ⌊⌋ | function | — | Floor function — rounds down to nearest integer |

**Output Range:**
- `tile_coord`: [0, 29] per axis (Vertical Slice)
- `pixel_coord`: [24, 1416] per axis (tile 0 center = 24px, tile 29 center = 1416px; map spans 1440px total)

**Example (tile → pixel):**
```
tile_coord = Vector2i(5, 12)
TILE_SIZE = 48
pixel_coord = (5, 12) * 48 + 24 = (240 + 24, 576 + 24) = (264, 600)
```

**Example (pixel → tile):**
```
pixel_coord = Vector2(264, 600)
TILE_SIZE = 48
tile_coord = floor(264/48, 600/48) = floor(5.5, 12.5) = Vector2i(5, 12)
```

**Example (mouse world position → tile):**
```
screen_pos = (400, 300) pixels
camera_offset = Vector2(0, 0) (camera centered on map origin)
camera_zoom = 1.0
world_pos = camera_offset + (screen_pos / camera_zoom) = (400, 300)
tile_size = 48
tile_coord = floor(400/48, 300/48) = floor(8.33, 6.25) = Vector2i(8, 6)
```

---

### 2. Manhattan Distance

Calculate distance between two tiles for logistics transport time and building placement radius checks. Manhattan distance is the primary metric because NPC movement is grid-based (each tile crossed = 1 step).

**The `manhattan_distance` formula is defined as:**

`d_manhattan = |x1 - x2| + |y1 - y2|`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| x1, y1 | p1 | int | 0–29 | Source tile coordinates |
| x2, y2 | p2 | int | 0–29 | Destination tile coordinates |
| |·| | ��� | Absolute value function |
| d_manhattan | d | int | 0–58 | Distance in tile steps |

**Output Range:** [0, 58] (0 = same tile, 58 = opposite corners (0,0) to (29,29) of 30×30 grid)

**Example:**
```
Tile A = (3, 7), Tile B = (18, 22)
d_manhattan = |3 - 18| + |7 - 22| = 15 + 15 = 30 tiles

Logistics System uses: transport_time_ticks = d_manhattan * TICKS_PER_TILE
```

---

### 3. Euclidean Distance

Calculate straight-line distance between two tiles. Used for Anno-style resource tile "in radius" checks (is a berry bush within 5 tiles of the lumber camp?).

**The `euclidean_distance` formula is defined as:**

`d_euclidean = sqrt((x1 - x2)^2 + (y1 - y2)^2)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| x1, y1 | p1 | int | 0–29 | Source tile coordinates |
| x2, y2 | p2 | int | 0–29 | Destination tile coordinates |
| sqrt | — | function | — | Square root function |
| d_euclidean | d | float | 0.0–40.72 | Distance in tiles (continuous) |

**Output Range:** [0.0, 40.72] (sqrt(29^2 + 29^2) ≈ 40.72 for corner-to-corner (0,0) to (29,29))

**Example:**
```
Tile A = (0, 0), Tile B = (5, 5)
d_euclidean = sqrt(25 + 25) = sqrt(50) ≈ 7.07 tiles

Production System checks: if d_euclidean <= RESOURCE_RADIUS, tile provides resource.
```

---

### 4. Resource Cluster Probability (Procedural Generation)

The probability that a tile at position (x, y) has a specific resource type, derived from combined noise values. This is a design-time formula used to tune noise parameters so the generated map has the right resource density.

**The `noise_to_terrain` formula is defined as:**

```
# Configure PerlinNoise instances (properties, not method parameters)
var elevation_noise := FastNoise.new()
elevation_noise.noise_type = FastNoise.TYPE_PERLIN
elevation_noise.seed = elevation_seed
elevation_noise.octaves = 4
elevation_noise.persistence = 0.5
elevation_noise.lacunarity = 2.0
elevation_noise.scale = Vector2(9.0, 9.0)

var moisture_noise := FastNoise.new()
moisture_noise.noise_type = FastNoise.TYPE_PERLIN
moisture_noise.seed = elevation_seed + 1
moisture_noise.octaves = 3
moisture_noise.persistence = 0.5
moisture_noise.lacunarity = 2.0
moisture_noise.scale = Vector2(9.0, 9.0)

# Sample noise
elevation = elevation_noise.get_noise_2d(x, y)
moisture = moisture_noise.get_noise_2d(x, y)

elev_norm = (elevation + 1.0) / 2.0    → range [0.0, 1.0]
mois_norm = (moisture + 1.0) / 2.0    → range [0.0, 1.0]

if elev_norm < 0.15:      terrain = IMPASSABLE
elif elev_norm < 0.30:    terrain = (mois_norm < 0.5) ? BERRY : GRASS
elif elev_norm < 0.55:    terrain = EMPTY
elif elev_norm < 0.75:    terrain = TREE
else:                     terrain = STONE
```

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| elevation | e | float | -1.0–1.0 | Raw Perlin noise value at (x, y) |
| moisture | m | float | -1.0–1.0 | Raw Perlin noise value at (x, y) |
| elev_norm | e' | float | 0.0–1.0 | Normalized elevation |
| mois_norm | m' | float | 0.0–1.0 | Normalized moisture |
| terrain | t | enum | 6 values | Assigned tile type |

**Noise parameters (Vertical Slice defaults):**
| Parameter | Elevation | Moisture |
|-----------|-----------|----------|
| seed | 42 | 43 |
| octaves | 4 | 3 |
| persistence | 0.5 | 0.5 |
| lacunarity | 2.0 | 2.0 |
| scale | Vector2(9.0, 9.0) | Vector2(9.0, 9.0) |

**Scaling note:** `scale = MAP_SIZE / desired_cluster_size`. For 30×30 grid and ~4–6 tile clusters: scale ≈ 30/5 = 6.0. The default of 9.0 produces slightly tighter clusters (~3 tiles avg). Tuning knob.

---

### 5. Smoothing Pass Selection

After noise sampling, the smoothing pass determines each tile's final type based on its neighbors. This creates the blobby, natural-looking clusters characteristic of noise-based generation.

**The `smooth_tile` formula is defined as:**

```
For each tile at (x, y):
    1. Count neighbors of each type (8-way adjacency)
    2. neighbor_count[type] = { IMPASSABLE: n1, BERRY: n2, ... }
    3. dominant_type = argmax(neighbor_count) (most frequent neighbor type)
    4. r = random_float()  // [0.0, 1.0)
    5. if r < 0.6:
           tile[x][y] = dominant_type    // 60% chance: adopt neighbor type
       else:
           tile[x][y] stays unchanged     // 40% chance: keep current type
```

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| neighbor_count | n | map | 0–8 per type | Count of each tile type in 8-neighbor radius |
| dominant_type | d | enum | 6 values | The tile type with highest neighbor count |
| r | r | float | 0.0–1.0 | Random value for probabilistic adoption |
| adoption_probability | p | float | 0.0–1.0 | Fraction of tiles that adopt dominant type (default 0.6) |

**Output:** Each tile has 60% chance of matching its most common neighbor, 40% chance of retaining its original type. Running 2 iterations produces well-clustered results with some scattered outlier tiles (natural-looking noise).

---

### 6. Transport Time (used by Logistics System, defined here for reference)

Calculate how many ticks an NPC carrier needs to transport a resource between two tiles.

**The `transport_time` formula is defined as:**

`transport_ticks = ceil(d_manhattan * TICKS_PER_TILE * (1 - road_bonus))`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| d_manhattan | d | int | 1–58 | Tile distance (from Formula 2) |
| TICKS_PER_TILE | tpt | int | 1–50 | Ticks to cross one tile (tuning knob, default 5) |
| road_bonus | rb | float | 0.0–0.5 | Fractional time reduction from road tiles (0 = no road, 0.5 = 50% faster) |
| transport_ticks | T | int | 1–2900 | Total transport time in ticks |

**Output Range:** [5, 2900] ticks (1 tile at 5 ticks/tile = 5 ticks minimum; 58 tiles at 5 ticks/tile = 290 ticks maximum; at road_bonus = 0.5: 58 × 5 × 0.5 = 145 ticks). Result is rounded up (`ceil`) to avoid sub-tick precision.

**Example:**
```
Lumber camp at (3, 7), storage at (18, 22)
d_manhattan = 30 (from Formula 2 example)
TICKS_PER_TILE = 5, road_bonus = 0.0 (no roads on this route)
transport_ticks = ceil(30 * 5 * 1.0) = 150 ticks

With roads reducing bonus to 0.3:
transport_ticks = ceil(30 * 5 * 0.7) = ceil(105.0) = 105 ticks (30% time savings)

With fractional result:
d_manhattan = 7, TICKS_PER_TILE = 5, road_bonus = 0.4
transport_ticks = ceil(7 * 5 * 0.6) = ceil(21.0) = 21 ticks
```

## Edge Cases

### Grid Boundary Edge Cases

- **If coordinate is out of bounds** (x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE): Every public query method raises a fatal assertion. The grid cannot safely handle out-of-bounds access — callers must validate before calling. This is a contract: the Grid System is not responsible for checking bounds; callers are. UI systems (hover, building preview) must clamp mouse positions to grid bounds before querying.

- **If `get_tiles_in_radius` extends beyond grid bounds**: Clip the bounding box to grid limits. The method returns only valid tile coordinates within the intersection of the requested radius and the grid boundary. No error — silently omits out-of-bounds tiles. This is intentional: a tree at the map edge has fewer neighbors, and systems querying its radius should simply not receive non-existent tiles.

- **If GRID_SIZE changes between Vertical Slice (30) and MVP (50)**: The grid is instantiated at startup with the configured size. No runtime resizing. Save/load code must handle both sizes (grid dimensions are serialized alongside data).

### Procedural Generation Edge Cases

- **If all 5 seed attempts fail minimum resource counts**: Force-fix by converting `EMPTY` tiles nearest to existing resource clusters to required resource types. This preserves natural-looking generation while guaranteeing the map is playable (player is not spawned on a barren map with no resources). Log warning: "Map generation forced-fix on attempt N — resource density below minimum."

- **If a critical resource cluster is exactly 3 tiles (smallest valid)**: Cluster is kept. The cleanup threshold of 3 means the player will have at least 3 harvestable units of each resource type — sufficient for Vertical Slice progression. For MVP (50×50), increase minimum cluster size to 5.

- **If smoothing pass eliminates all tiles of a certain type** (extremely unlikely but possible with adversarial noise): Force-regenerate with different seed. Never accept a map with zero instances of a required resource type.

- **If a resource tile is cleared during active production** (e.g., building is placed on a resource tile while Production System checks "berries in radius"): The production system re-evaluates the radius on the next tick cycle. No rollback — if the building has no valid resource tiles in radius, it stops producing. This is expected behavior: building on a resource tile removes it, and buildings require resource tiles to persist in radius.

### Map Loading Edge Cases

- **If a loaded save has a building_id that no longer exists** (building was deprecated or removed between game versions): The building instance is destroyed on load. Resource tiles beneath the building are restored to their pre-building state (cleared, no resource). UI notification: "Building [id] removed — no longer available."

### Building Placement Edge Cases

- **If player attempts placement on a tile that transitions from valid to invalid between validation and commit** (race condition between `validate_placement` and `place_building`): `place_building` calls `validate_placement` internally as a final check. If validation now fails (another system occupied the tile), placement returns `BLOCKED_BY_*` with the current blocking reason. Atomic validate-then-place — no gap.

- **If building occupies a tile that has resources** (building built on top of a berry bush): The resource is removed entirely. This is the expected behavior — you build on cleared land, not on active resources. The player loses the buried resource. Tooltip on placement: "Builds on this tile, removing [resource]."

- **If building placement fails but ghost preview lingers** (UI shows green ghost on a tile that just became blocked by another system): Grid System does not own UI state. The Building System (or HUD System) must refresh the ghost preview on every input event and on `on_ticks_advanced`. If a ghost preview becomes stale, that is a consuming system's bug, not a Grid System bug.

### Map Loading Edge Cases

- **If a loaded save has resource coordinates outside the current grid size** (save from 50×50 MVP loaded in 30×30 Vertical Slice, or vice versa): Tiles outside the current grid bounds are discarded. Log warning. This should not happen in normal play (grid size is a project-level constant, not a save variable), but is a safety net for modding or testing scenarios.

- **If a loaded save has resource coordinates outside the current grid size** (save from 50×50 MVP loaded in 30×30 Vertical Slice, or vice versa): Tiles outside the current grid bounds are discarded. Log warning. This should not happen in normal play (grid size is a project-level constant, not a save variable), but is a safety net for modding or testing scenarios.

### Query Edge Cases

- **If `find_nearest` reaches max_radius with no match**: Returns `null`. Caller must handle the "not found" case (e.g., Building System shows "No resource in range" in tooltip).

- **If `get_tiles_in_radius` returns 0 tiles** (radius = 0, or all tiles in radius are out of bounds): Returns empty array. Callers must handle the empty case (not an error — an empty ring is a valid query result).

- **If `harvest_resource` is called on a non-resource tile** (EMPTY, IMPASSABLE): Returns 0 immediately, no state mutation. Caller receives yield = 0 with no side effects.

### Rendering Edge Cases

- **If TileMapLayer has no TileSet assigned**: Godot 4.6 renders an empty layer (nothing visible). No error, no crash. However, the grid data model is independent of rendering — the grid still has correct data. This is a setup/initialization bug, caught during level design. If a tile is queried but the corresponding TileMapLayer cell is unpopulated, the data model is authoritative — the renderer should match. Mismatches are rendering bugs, not data bugs.

## Dependencies

### Upstream (Grid/Map System depends on)

| System | Dependency Type | Notes |
|--------|----------------|-------|
| **Resource System** | Hard — resource type definitions | Grid's ResourceLayer stores `resource_id` strings that reference the Resource System registry. Grid does not define resource types itself. |

### Downstream (systems that depend on Grid/Map System)

| System | Dependency Type | Interface Used | Notes |
|--------|----------------|----------------|-------|
| **Building System** | Hard | `validate_placement()`, `place_building()`, `remove_building()`, `get_tile_view()` | Cannot place buildings without grid validation. Building System is the primary writer to BuildingLayer. |
| **Camera System** | Hard | `get_tile_view()`, `get_terrain()`, coordinate conversion | Camera renders the grid and converts viewport to tile space. Without grid, camera has nothing to display. |
| **Manual Labor System** | Hard | `harvest_resource()`, `get_resource()`, `get_terrain()` | Player harvests by clicking tiles → Input System → Manual Labor queries Grid for tile type and resource data. |
| **Production System** | Soft | `get_tiles_in_radius()`, `get_terrain()` | Anno-style: checks if required resource tiles exist within building radius. |
| **Logistics System** | Hard | `distance_between()`, `get_tiles_in_radius()` | Calculates NPC transport time using Manhattan distance. Finds nearest resource/building tiles. |
| **HUD System** | Soft | `get_tile_view()` | Shows hover tooltips with tile info (terrain type, resource, building). |
| **Day Overview System** | Soft | `get_tiles_in_radius()` | May show resource distribution overview on day transition. |
| **Input System** | Soft | N/A (Input System feeds INTO Grid consumers) | Input System's mouse world position conversion feeds into Grid-consuming systems, not Grid directly. |

### Bidirectional Consistency

Grid → Building System: Building System GDD must validate placement through Grid's `validate_placement()` — never check blocking rules in isolation.

Grid → Logistics System: Logistics System GDD must use `distance_between()` (Manhattan metric) for transport time — not raw coordinate differences.

Grid → Production System: Production System GDD must use Euclidean distance for "resource in radius" checks (Anno-style), not Manhattan.

Grid → Resource System: Grid's `resource_id` strings reference the Resource System registry. Bidirectionally consistent.

## Tuning Knobs

| Knob | Default | Safe Range | Effect | What breaks if misconfigured |
|------|---------|------------|--------|------------------------------|
| `GRID_SIZE` | 30 | 20–100 | Map dimensions (GRID_SIZE × GRID_SIZE tiles) | Below 20: too cramped, not enough room for meaningful optimization. Above 60: camera becomes unusable at 48px tiles without zoom/scroll. |
| `TILE_SIZE` | 48 | 32–96 px | Pixel dimensions of each tile | Below 32: buildings unreadable. Above 64: map doesn't fit on 1080p screen without scrolling. |
| `noise_scale` | 9.0 | 4.0–20.0 | Perlin noise scale factor (inverse of cluster size) | Low = huge monolithic clusters (one half of map is all trees). High = pixelated noise, no cluster feeling, unusable for planning. |
| `noise_octaves` | 4 | 2–8 | Number of noise layers combined | Low = flat, boring terrain. High = chaotic, no dominant terrain types. |
| `smoothing_probability` | 0.6 | 0.3–0.85 | Chance tile adopts dominant neighbor type per pass | Below 0.3: barely any smoothing, noisy map. Above 0.85: over-smoothed, all tiles become uniform after 2 passes. |
| `smoothing_iterations` | 2 | 1–4 | Number of smoothing pass iterations | 1 = some clumping but lots of outliers. 3–4 = very clean clusters but may eliminate small resource patches. |
| `min_cluster_size` | 3 | 2–10 | Minimum connected component size before deletion | Below 2: meaningless 1-tile clusters clutter map. Above 10: most clusters destroyed, sparse map with lots of empty space. |
| `min_resource_counts` | TREE: 8, STONE: 4, BERRY: 6, GRASS: 6 | 3–20 per type | Minimum guaranteed resource tiles per type | Too low: player struggles to start (not enough wood to build first house). Too high: no challenge finding resources, early game trivial. |
| `resource_radius` | 5 | 3–10 tiles | Anno-style: tiles within this radius of building provide resources | Too small: buildings need to be everywhere (spread too thin). Too large: radius checks return too many tiles, performance hit at 100+ buildings. |
| `TICKS_PER_TILE` | 5 | 1–20 | Transport ticks per tile crossed (used by Logistics) | Below 1: instant transport, no spatial strategy. Above 15: short-distance transport takes forever, player frustration. |
| `road_bonus` | 0.0 | 0.0–0.5 | Fractional reduction in transport time for road tiles | 0: roads have no effect (why build them?). 0.5+: roads are too powerful, all routes converge on roads. Enforced by UI — value is clamped to [0.0, 0.5] on the settings slider. No runtime clamp in formula. |
| `seed` | 42 | 0–999999 | Procedural generation seed | Changing seed regenerates entire map. Same seed = identical map (deterministic). |
| `_ICON_SCALE_BY_COUNT` | [0.60, 0.40, 0.35, 0.31] | 0.20–0.70 per slot | Icon size as fraction of tile width, indexed by resource count (1–4) | Too small: icons unreadable. Too large: icons overlap even with maximum scatter spread; also clip outside tile at high counts. |
| `badge_float_amplitude` | 4 px | 1–8 px | Vertical bob range of the floating badge animation | Too small: animation imperceptible. Too large: icons feel frantic; can visually overlap adjacent tile content. |
| `badge_float_period` | 2.5 s | 1.5–5.0 s | Full cycle duration of the floating animation | Too short: animation feels jittery. Too long: nearly imperceptible movement. |
| `badge_scatter_spread` | 0.28 × tile_px | 0.15–0.40 × tile_px | Maximum offset of a resource icon from the tile centre | Too small: all icons stack on top of each other regardless of min separation. Too large: icons drift visibly outside the tile bounds. |
| `badge_min_separation` | 0.85 × icon_px | 0.5–1.2 × icon_px | Minimum centre-to-centre distance between icons on the same tile | Below 0.5: icons visually overlap. Above 1.0: at high counts the rejection sampler fails to place all icons within spread; fallback stacks them. |
| `backdrop_opacity` | 0.30 | 0.15–0.60 | Alpha of the black per-icon backdrop circle | Too low: backdrop invisible, icons blend into terrain. Too high: backdrop dominates, icons hard to distinguish from terrain layer. |

**Cross-knob interactions:**
- `GRID_SIZE × TILE_SIZE`: Together determine total map pixel dimensions. `GRID_SIZE × TILE_SIZE` should not exceed ~1600px per axis at default zoom (fits 1080p with UI). At 30×48 = 1440px — safe. At 50×48 (MVP) = 2400px — requires camera zoom or scrolling.
- `noise_scale × GRID_SIZE`: The effective cluster size in tiles = `GRID_SIZE / noise_scale`. At 30/9.0 ≈ 3.3 tiles per cluster. At 50/9.0 ≈ 5.5 tiles. Increase noise_scale with GRID_SIZE to maintain similar cluster density.
- `smoothing_probability × smoothing_iterations`: Combined effect is multiplicative. High probability + high iterations = over-smoothed even if each individual value is in safe range. Default (0.6 × 2) is well-balanced. Avoid combinations above 0.7 × 3. Note: at 0.6 × 2, ~84% of original noise diversity is lost — maps are very smooth and homogenized. For more varied terrain, use 0.5 × 2 or 0.6 × 1.

## Visual/Audio Requirements

### Visual

The Grid/Map System is the most prominent visual element in the game — it IS the screen the player sees. Visual requirements are divided by layer:

**Terrain Layer (TileMapLayer — atlas tiles):**
- Base ground textures: green grass, brown dirt, dark green forest floor, blue water (for IMPASSABLE tiles if any represent water)
- Earthy, muted palette aligned with "Functional Clarity" art direction
- High contrast between adjacent terrain types (grass vs forest vs stone)
- Each terrain type has a distinct silhouette and color — identifiable from across the map
- Test: "Can I identify a terrain type from across the room without zooming in?"

**Resource Overlay Layer (Sprite2D badges — not TileMapLayer):**
- Resources are rendered as floating badge nodes, not TileMapLayer atlas tiles. The `ResourceOverlay` TileMapLayer node remains in the scene but has no TileSet assigned and renders nothing.
- Each resource on a tile is displayed as one icon Sprite2D with its own circular black backdrop (opacity 30%) behind it, providing contrast against any terrain.
- When a tile holds multiple resources (up to 4), the icons are scattered randomly within the tile bounds. Scatter positions are deterministic per tile (seeded by tile coordinate hash) with a minimum separation of 85% of icon width to avoid excessive overlap.
- Icon size scales with the number of resources on the tile: 1 → 60%, 2 → 40%, 3 → 35%, 4 → 31% of tile width. All icons on a tile use the same scale.
- All badges animate with a continuous sine-wave vertical float (amplitude ±4 px, period 2.5 s). Each tile's badge has a unique phase offset (derived from tile position) so icons across the map do not bob in lockstep.
- Resources use slightly saturated colors vs terrain (actionable = higher saturation)

**Building Slots Layer (TileMapLayer — simple 1×1 indicator tiles):**
- Empty tiles: no overlay (just terrain)
- Occupied tiles: 1×1 placeholder tile (slightly darker ground or subtle border)
- Building preview (ghost): semi-transparent green (valid placement) or red (invalid), shown via Building System using Grid validation

**Building Scenes (PackedScene instances, NOT tiles):**
- Each building is a full scene with sprites, animations, and effects
- Buildings have a consistent medieval style (timber frame, thatched roof)
- Building height/depth consistent across all types (no building occupies more than 1 tile footprint in VS)
- Production buildings have visual progress indicators (smoke, moving parts) — deferred to Building System VFX

### Audio

- **No ambient audio per tile** — the grid itself has no audio
- **Building placement**: short thud/hammer SFX (deferred to Building System)
- **Resource harvest**: rustle/clink SFX (deferred to Manual Labor System)
- **No continuous environmental audio** from the grid layer — ambient audio is handled by the Audio System, not the Grid System

## UI Requirements

The Grid/Map System itself has no UI — it is a data and rendering layer. UI for grid interaction is owned by consuming systems. However, the Grid defines requirements for how grid data is presented.

**Tile Hover/Tooltip (HUD System):**
- When mouse hovers over a tile, HUD System queries `get_tile_view(x, y)` and displays:
  - Terrain type name (e.g., "Forest", "Stone Outcrop")
  - Resource info if present (e.g., "Berries: 5 remaining")
  - Building info if present (e.g., "Lumber Yard (NPC assigned)")
  - Distance from player character (if player has selected unit)
- Tooltip updates every frame during mouse movement (poll, not event-driven)
- Tooltip is hidden when mouse is outside grid bounds

**Building Placement Preview (Building System):**
- When player holds build menu open and moves mouse, Building System queries `validate_placement(x, y)` each frame
- If result is SUCCESS: show semi-transparent green building ghost on tile
- If result is BLOCKED: show semi-transparent red building ghost + tooltip with reason ("Impassable terrain", "Resource tile occupied", "Building already here")
- Ghost disappears when build menu is closed or mouse leaves grid
- Ghost snapping: ghost is always centered on tile center (`tile_coord * TILE_SIZE + TILE_SIZE/2`)

**Resource Radius Indicator (Production System):**
- When viewing a building's production panel, show a circle (or diamond for Manhattan metric) around the building indicating the resource radius
- Tiles within radius that have matching resource types are highlighted (subtle glow or border)
- Tiles within radius without matching resources are dimmed
- Radius size configurable via `resource_radius` tuning knob

**Minimap (optional, HUD System):**
- Top-right corner: small overview of entire grid (30×30 reduced to ~80×80 pixels)
- Color-coded by terrain type
- Building positions shown as small dots
- Viewport rectangle shown as white outline (shows current camera position)
- Implemented as a second TileMapLayer with simplified tiles, not a render texture

**📌 UX Flag — Grid/Map System**: This system has UI requirements defined above (hover tooltips, placement preview, radius indicator, minimap). In Phase 4 (Pre-Production), run `/ux-design` to create UX specs for the minimap and placement preview interactions **before** writing epics. Stories that reference these UI elements should cite `design/ux/[screen].md`, not the GDD directly.

## Acceptance Criteria

### Core Grid Operations (Blocking)

1. **GIVEN** the grid is initialized with GRID_SIZE = 30, **WHEN** `get_terrain(15, 15)` is called, **THEN** the returned value is one of `TileType` enum values (`EMPTY`, `TREE`, `STONE`, `BERRY`, `GRASS`, `IMPASSABLE`)
2. **GIVEN** the grid is generated with seed 42 producing `TerrainLayer_A` and `ResourceLayer_A`, **WHEN** the grid is regenerated with seed 42 producing `TerrainLayer_B` and `ResourceLayer_B`, **THEN** `TerrainLayer_A` equals `TerrainLayer_B` tile-for-tile and `ResourceLayer_A` equals `ResourceLayer_B` tile-for-tile (same `resource_id`, `clearable` per tile)
3. **GIVEN** a tile at (5, 5) with TREE type and `clearable = true`, **WHEN** a building is placed on this tile, **THEN** ResourceLayer[5][5] becomes null (resource cleared) and BuildingLayer[5][5] is set to the building_id
4. **GIVEN** the grid contains at least 8 TREE tiles, 4 STONE tiles, 6 BERRY tiles, and 6 GRASS tiles, **WHEN** generation completes, **THEN** all minimum count checks pass

### Placement Validation (Blocking)

5. **GIVEN** an EMPTY tile at (10, 10) with no building, **WHEN** `validate_placement(10, 10, "lumber_yard")` is called, **THEN** result is SUCCESS
6. **GIVEN** an IMPASSABLE tile at (2, 2), **WHEN** `validate_placement(2, 2, "lumber_yard")` is called, **THEN** result is BLOCKED_BY_IMPASSABLE
7. **GIVEN** a tile at (7, 3) with a building already placed, **WHEN** `validate_placement(7, 3, "lumber_yard")` is called, **THEN** result is BLOCKED_BY_BUILDING
8. **GIVEN** coordinates (-1, 5), **WHEN** `validate_placement(-1, 5, "lumber_yard")` is called, **THEN** result is BLOCKED_BY_BOUNDS
9. **GIVEN** a stone resource tile (STONE terrain type) at (5, 5), **WHEN** `validate_placement(5, 5, "lumber_yard")` is called, **THEN** result is BLOCKED_BY_RESOURCE_TILE (stone is not clearable)
10. **GIVEN** a tree resource tile (TREE terrain type, clearable = true) at (5, 5) with no building, **WHEN** `validate_placement(5, 5, "lumber_yard")` is called, **THEN** result is SUCCESS (tree is clearable)
11. **GIVEN** `validate_placement` returns SUCCESS, **WHEN** `place_building(10, 10, "lumber_yard")` is called, **THEN** BuildingLayer[10][10] is set to "lumber_yard" and `get_building(10, 10)` returns "lumber_yard"

### Coordinate Conversion (Blocking)

12. **GIVEN** TILE_SIZE = 48, **WHEN** converting tile (5, 12) to pixel coordinates, **THEN** result is (264, 600) (center of tile)
13. **GIVEN** TILE_SIZE = 48, **WHEN** converting pixel (400, 300) to tile coordinates, **THEN** result is (8, 6)
14. **GIVEN** screen_pos = (400, 300), camera_offset = (0, 0), camera_zoom = 1.0, TILE_SIZE = 48, **WHEN** converting through world position, **THEN** result is Vector2i(8, 6)

### Spatial Queries (Blocking)

15. **GIVEN** center (15, 15) and radius 1, **WHEN** `get_tiles_in_radius(15, 15, 1)` is called, **THEN** returns exactly 9 tiles (3×3 square: 15±1 on each axis)
16. **GIVEN** tile A at (0, 0) and tile B at (5, 5), **WHEN** `distance_between(A, B, "manhattan")` is called, **THEN** returns 10 (|0-5| + |0-5| = 10)
17. **GIVEN** tile A at (0, 0) and tile B at (3, 4), **WHEN** `distance_between(A, B, "euclidean")` is called, **THEN** the result is within epsilon of 5.0 (i.e., `abs(result - 5.0) < 0.001`)
18. **GIVEN** a grid with TREE tiles at positions `[(0,3), (5,5), (2,7), (10,0), (3,3), (8,8), (1,1), (15,15)]` AND a valid `max_radius` of 30 (sufficient to reach all tiles), **WHEN** `find_nearest(0, 0, "wood", 30)` is called, **THEN** the result is `Vector2i(0, 3)` (closest TREE tile by Manhattan distance from (0, 0))

### Resource Harvesting (Blocking)

19. **GIVEN** a TREE resource tile at (x, y) with `resource_id = "wood"` and `clearable = true`, **WHEN** `validate_placement(x, y, "lumber_yard")` succeeds and `place_building(x, y, "lumber_yard")` is called, **THEN** ResourceLayer[x][y] becomes null (resource cleared) and the tile can accept a building
20. **GIVEN** a STONE resource tile at (x, y) with `resource_id = "stone"` and `clearable = false`, **WHEN** `validate_placement(x, y, "lumber_yard")` is called, **THEN** result is `BLOCKED_BY_RESOURCE_TILE` (stone cannot be cleared)
21. **GIVEN** a BERRY resource tile at (x, y) with `resource_id = "berry"` and `clearable = true`, **WHEN** a building is placed on this tile, **THEN** ResourceLayer[x][y] becomes null (resource cleared)

### Generation Edge Cases (Blocking)

22. **GIVEN** a grid where `TerrainLayer` has only 2 `STONE` tiles (below the minimum of 4), **WHEN** minimum count verification runs and determines regeneration would not help, **THEN** the system converts `EMPTY` tiles adjacent to existing `STONE` tiles to `STONE` until the count reaches at least 4
23. **GIVEN** a generated map where exactly two TREE tiles at `(3, 3)` and `(3, 4)` are adjacent (forming a connected component of size 2), and all other TREE tiles are at positions `[(10,10), (11,10), (12,10), (10,11), (10,12), (15,15), (16,15), (15,16)]` (forming clusters of size 3+), **WHEN** cluster cleanup runs with `min_cluster_size = 3`, **THEN** only tiles `(3, 3)` and `(3, 4)` are converted to `EMPTY`, and no other tiles are modified

### Query Edge Cases (Blocking)

24. **GIVEN** `find_nearest(0, 0, "stone", 5)` with no stone tiles within radius 5, **WHEN** the method returns, **THEN** result is null (not an error, not empty array)
25. **GIVEN** `get_tiles_in_radius(0, 0, 5)` at the map corner, **WHEN** called, **THEN** returns only tiles within grid bounds (no out-of-bounds tiles in result)

### Performance (Advisory)

26. **GIVEN** a full 30×30 grid with 100 buildings placed, **WHEN** `get_tiles_in_radius(15, 15, 10)` is called, **THEN** execution completes in < 1ms
27. **GIVEN** 50 `get_tile_view()` calls per frame at 60fps, **THEN** grid query overhead is < 0.1ms total (does not impact frame budget)

### Open Questions

**Resolved for Vertical Slice:**
- ✅ Tile size: 48×48 pixels (confirmed with screen real estate analysis)
- ✅ Distance metric: Manhattan as default, Euclidean for Anno-style radius checks
- ✅ Rendering: TileMapLayer for terrain/resources, PackedScene for buildings (not Scene Tiles)
- ✅ Grid size: 30×30 for VS, 50×50 for MVP (separate instantiation, no runtime resize)
- ✅ Resource model: Infinite Anno-style (no amount tracking). Resource tiles are spatial anchors — either present or cleared. Stone = not clearable. Tree/Berry/Grass = clearable, permanently removed when a building is placed on them.
- ✅ Building footprint: 1 tile × 1 tile for VS
- ✅ Map persistence: Single map per game — no regeneration feature. The generated layout is final.
