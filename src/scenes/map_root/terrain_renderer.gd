class_name TerrainRenderer
## Builds the terrain TileSet at runtime and batch-syncs WorldGrid data into the
## background / terrain TileMapLayers.
##
## Extracted from MapRoot (Phase 5 god-object decomposition). MapRoot owns the
## TileMapLayer nodes and the WorldGrid; this helper owns only the tileset
## construction and the atlas-variant bookkeeping. ADR-0004: grid data is
## authoritative, the TileMapLayer is a pure rendering target.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 5).

## PNG variant lists per terrain TileType index (EMPTY=0 … IMPASSABLE=5).
## Empty inner array = no assets yet, falls back to solid color placeholder.
## Multiple paths = variants; one is chosen deterministically per tile position.
const _TERRAIN_PNG_VARIANTS: Array = [
	[  # EMPTY — 16 sand variants
		"res://assets/art/tiles/env_tile_empty_01.png",
		"res://assets/art/tiles/env_tile_empty_02.png",
		"res://assets/art/tiles/env_tile_empty_03.png",
		"res://assets/art/tiles/env_tile_empty_04.png",
		"res://assets/art/tiles/env_tile_empty_05.png",
		"res://assets/art/tiles/env_tile_empty_06.png",
		"res://assets/art/tiles/env_tile_empty_07.png",
		"res://assets/art/tiles/env_tile_empty_08.png",
		"res://assets/art/tiles/env_tile_empty_09.png",
		"res://assets/art/tiles/env_tile_empty_10.png",
		"res://assets/art/tiles/env_tile_empty_11.png",
		"res://assets/art/tiles/env_tile_empty_12.png",
		"res://assets/art/tiles/env_tile_empty_13.png",
		"res://assets/art/tiles/env_tile_empty_14.png",
		"res://assets/art/tiles/env_tile_empty_15.png",
		"res://assets/art/tiles/env_tile_empty_16.png",
	],
	[  # TREE — 16 variants
		"res://assets/art/tiles/env_tile_tree_01.png",
		"res://assets/art/tiles/env_tile_tree_02.png",
		"res://assets/art/tiles/env_tile_tree_03.png",
		"res://assets/art/tiles/env_tile_tree_04.png",
		"res://assets/art/tiles/env_tile_tree_05.png",
		"res://assets/art/tiles/env_tile_tree_06.png",
		"res://assets/art/tiles/env_tile_tree_07.png",
		"res://assets/art/tiles/env_tile_tree_08.png",
		"res://assets/art/tiles/env_tile_tree_09.png",
		"res://assets/art/tiles/env_tile_tree_10.png",
		"res://assets/art/tiles/env_tile_tree_11.png",
		"res://assets/art/tiles/env_tile_tree_12.png",
		"res://assets/art/tiles/env_tile_tree_13.png",
		"res://assets/art/tiles/env_tile_tree_14.png",
		"res://assets/art/tiles/env_tile_tree_15.png",
		"res://assets/art/tiles/env_tile_tree_16.png",
	],  # TREE
	[  # STONE — 16 rock variants
		"res://assets/art/tiles/env_tile_stone_01.png",
		"res://assets/art/tiles/env_tile_stone_02.png",
		"res://assets/art/tiles/env_tile_stone_03.png",
		"res://assets/art/tiles/env_tile_stone_04.png",
		"res://assets/art/tiles/env_tile_stone_05.png",
		"res://assets/art/tiles/env_tile_stone_06.png",
		"res://assets/art/tiles/env_tile_stone_07.png",
		"res://assets/art/tiles/env_tile_stone_08.png",
		"res://assets/art/tiles/env_tile_stone_09.png",
		"res://assets/art/tiles/env_tile_stone_10.png",
		"res://assets/art/tiles/env_tile_stone_11.png",
		"res://assets/art/tiles/env_tile_stone_12.png",
		"res://assets/art/tiles/env_tile_stone_13.png",
		"res://assets/art/tiles/env_tile_stone_14.png",
		"res://assets/art/tiles/env_tile_stone_15.png",
		"res://assets/art/tiles/env_tile_stone_16.png",
	],  # STONE
	[  # BERRY — 16 bush variants
		"res://assets/art/tiles/env_tile_berry_01.png",
		"res://assets/art/tiles/env_tile_berry_02.png",
		"res://assets/art/tiles/env_tile_berry_03.png",
		"res://assets/art/tiles/env_tile_berry_04.png",
		"res://assets/art/tiles/env_tile_berry_05.png",
		"res://assets/art/tiles/env_tile_berry_06.png",
		"res://assets/art/tiles/env_tile_berry_07.png",
		"res://assets/art/tiles/env_tile_berry_08.png",
		"res://assets/art/tiles/env_tile_berry_09.png",
		"res://assets/art/tiles/env_tile_berry_10.png",
		"res://assets/art/tiles/env_tile_berry_11.png",
		"res://assets/art/tiles/env_tile_berry_12.png",
		"res://assets/art/tiles/env_tile_berry_13.png",
		"res://assets/art/tiles/env_tile_berry_14.png",
		"res://assets/art/tiles/env_tile_berry_15.png",
		"res://assets/art/tiles/env_tile_berry_16.png",
	],  # BERRY
	[  # GRASS — 16 tall grass variants
		"res://assets/art/tiles/env_tile_grass_01.png",
		"res://assets/art/tiles/env_tile_grass_02.png",
		"res://assets/art/tiles/env_tile_grass_03.png",
		"res://assets/art/tiles/env_tile_grass_04.png",
		"res://assets/art/tiles/env_tile_grass_05.png",
		"res://assets/art/tiles/env_tile_grass_06.png",
		"res://assets/art/tiles/env_tile_grass_07.png",
		"res://assets/art/tiles/env_tile_grass_08.png",
		"res://assets/art/tiles/env_tile_grass_09.png",
		"res://assets/art/tiles/env_tile_grass_10.png",
		"res://assets/art/tiles/env_tile_grass_11.png",
		"res://assets/art/tiles/env_tile_grass_12.png",
		"res://assets/art/tiles/env_tile_grass_13.png",
		"res://assets/art/tiles/env_tile_grass_14.png",
		"res://assets/art/tiles/env_tile_grass_15.png",
		"res://assets/art/tiles/env_tile_grass_16.png",
	],  # GRASS
	[],  # IMPASSABLE
	[  # WHEAT — 16 wheat-field variants (generated via PixelLab /create-tileset)
		"res://assets/art/tiles/env_tile_wheat_01.png",
		"res://assets/art/tiles/env_tile_wheat_02.png",
		"res://assets/art/tiles/env_tile_wheat_03.png",
		"res://assets/art/tiles/env_tile_wheat_04.png",
		"res://assets/art/tiles/env_tile_wheat_05.png",
		"res://assets/art/tiles/env_tile_wheat_06.png",
		"res://assets/art/tiles/env_tile_wheat_07.png",
		"res://assets/art/tiles/env_tile_wheat_08.png",
		"res://assets/art/tiles/env_tile_wheat_09.png",
		"res://assets/art/tiles/env_tile_wheat_10.png",
		"res://assets/art/tiles/env_tile_wheat_11.png",
		"res://assets/art/tiles/env_tile_wheat_12.png",
		"res://assets/art/tiles/env_tile_wheat_13.png",
		"res://assets/art/tiles/env_tile_wheat_14.png",
		"res://assets/art/tiles/env_tile_wheat_15.png",
		"res://assets/art/tiles/env_tile_wheat_16.png",
	],  # WHEAT
	[  # CLAY — 16 clay-pit variants (generated via PixelLab /create-tileset)
		"res://assets/art/tiles/env_tile_clay_01.png",
		"res://assets/art/tiles/env_tile_clay_02.png",
		"res://assets/art/tiles/env_tile_clay_03.png",
		"res://assets/art/tiles/env_tile_clay_04.png",
		"res://assets/art/tiles/env_tile_clay_05.png",
		"res://assets/art/tiles/env_tile_clay_06.png",
		"res://assets/art/tiles/env_tile_clay_07.png",
		"res://assets/art/tiles/env_tile_clay_08.png",
		"res://assets/art/tiles/env_tile_clay_09.png",
		"res://assets/art/tiles/env_tile_clay_10.png",
		"res://assets/art/tiles/env_tile_clay_11.png",
		"res://assets/art/tiles/env_tile_clay_12.png",
		"res://assets/art/tiles/env_tile_clay_13.png",
		"res://assets/art/tiles/env_tile_clay_14.png",
		"res://assets/art/tiles/env_tile_clay_15.png",
		"res://assets/art/tiles/env_tile_clay_16.png",
	],  # CLAY
	[],  # WATER — no assets yet, falls back to solid blue (tileset follow-up via PixelLab)
	[],  # COAST — no assets yet, falls back to lighter blue (tileset follow-up via PixelLab)
]

## Fallback solid colors, one per TileType (EMPTY=0 … IMPASSABLE=5).
const _TERRAIN_FALLBACK_COLORS: Array[Color] = [
	Color(0.76, 0.70, 0.55),  # EMPTY — sandy tan
	Color(0.10, 0.38, 0.10),  # TREE — dark green
	Color(0.45, 0.45, 0.45),  # STONE — medium gray
	Color(0.82, 0.20, 0.25),  # BERRY — red
	Color(0.44, 0.76, 0.28),  # GRASS — light green
	Color(0.08, 0.08, 0.14),  # IMPASSABLE — near-black
	Color(0.83, 0.66, 0.20),  # WHEAT — golden amber
	Color(0.66, 0.40, 0.22),  # CLAY — reddish earthen brown
	Color(0.18, 0.45, 0.70),  # WATER — blue
	Color(0.25, 0.62, 0.88),  # COAST — lighter ocean blue
]

## Atlas column where each TileType starts (populated by build_and_assign).
var _terrain_type_offsets: Array[int] = []
## Number of variant slots per TileType, always >= 1 (populated by build_and_assign).
var _terrain_type_variant_counts: Array[int] = []


## Builds the terrain TileSet and assigns it to both layers.
## BuildingSlots stays unset (no visual); ResourceOverlay rendered as badge nodes.
func build_and_assign(background_layer: TileMapLayer, terrain_layer: TileMapLayer) -> void:
	var terrain_ts := _build_terrain_tileset()
	background_layer.tile_set = terrain_ts
	terrain_layer.tile_set = terrain_ts


## Batch-syncs all GRID_SIZE² tiles from WorldGrid data into the layers.
## Call once after grid.generate(); never per-frame.
func sync(grid: WorldGrid, background_layer: TileMapLayer, terrain_layer: TileMapLayer) -> void:
	var empty := WorldGrid.TileType.EMPTY
	for x in range(WorldGrid.GRID_SIZE):
		for y in range(WorldGrid.GRID_SIZE):
			var tile := Vector2i(x, y)
			background_layer.set_cell(tile, 0, _terrain_type_to_atlas(empty, tile))
			var terrain: WorldGrid.TileType = grid.get_terrain(tile)
			if terrain != empty:
				terrain_layer.set_cell(tile, 0, _terrain_type_to_atlas(terrain, tile))


## Builds the terrain TileSet as a flat horizontal atlas.
## Each TileType occupies one or more consecutive columns — one per loaded variant PNG.
## Types with no PNG fall back to a single solid color slot.
## Populates _terrain_type_offsets and _terrain_type_variant_counts for use in sync.
func _build_terrain_tileset() -> TileSet:
	var tile_px: int = WorldGrid.TILE_SIZE
	_terrain_type_offsets.clear()
	_terrain_type_variant_counts.clear()
	var all_images: Array[Image] = []

	for type_idx in range(_TERRAIN_FALLBACK_COLORS.size()):
		_terrain_type_offsets.append(all_images.size())
		var variants: Array = _TERRAIN_PNG_VARIANTS[type_idx]
		var images: Array[Image] = []
		for path: String in variants:
			if path != "" and ResourceLoader.exists(path):
				var tex := load(path) as Texture2D
				if tex != null:
					var img: Image = tex.get_image()
					img.resize(tile_px, tile_px, Image.INTERPOLATE_NEAREST)
					images.append(img)
		if images.is_empty():
			images.append(TextureFactory.solid_tile(tile_px, _TERRAIN_FALLBACK_COLORS[type_idx]))
		for img in images:
			all_images.append(img)
		_terrain_type_variant_counts.append(images.size())

	var total: int = all_images.size()
	var atlas_img := Image.create(tile_px * total, tile_px, false, Image.FORMAT_RGBA8)
	for i in range(total):
		atlas_img.blit_rect(all_images[i], Rect2i(0, 0, tile_px, tile_px), Vector2i(i * tile_px, 0))
	return _make_tileset(atlas_img, total)


func _make_tileset(img: Image, tile_count: int) -> TileSet:
	var tile_size := Vector2i(WorldGrid.TILE_SIZE, WorldGrid.TILE_SIZE)
	var texture := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = tile_size
	for i in range(tile_count):
		source.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = tile_size
	ts.add_source(source, 0)
	return ts


## Returns a Texture2D for the given terrain type, for use in ghost-sprite overlays.
## Uses the first available variant PNG; returns null if only a fallback color exists.
func get_terrain_texture(terrain_type: WorldGrid.TileType) -> Texture2D:
	var type_idx: int = terrain_type as int
	if type_idx < 0 or type_idx >= _TERRAIN_PNG_VARIANTS.size():
		return null
	var variants: Array = _TERRAIN_PNG_VARIANTS[type_idx]
	for path: String in variants:
		if path != "" and ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## Returns atlas coords for the given terrain type at a given tile position.
## For types with multiple variants, selects deterministically via a prime-based hash.
func _terrain_type_to_atlas(terrain_type: WorldGrid.TileType, tile: Vector2i) -> Vector2i:
	var type_idx: int = terrain_type as int
	var offset: int = _terrain_type_offsets[type_idx]
	var count: int = _terrain_type_variant_counts[type_idx]
	var variant: int = (tile.x * 7 + tile.y * 13) % count
	return Vector2i(offset + variant, 0)
