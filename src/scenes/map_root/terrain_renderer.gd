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
		"res://assets/art/tiles/empty/env_tile_empty_01.png",
		"res://assets/art/tiles/empty/env_tile_empty_02.png",
		"res://assets/art/tiles/empty/env_tile_empty_03.png",
		"res://assets/art/tiles/empty/env_tile_empty_04.png",
		"res://assets/art/tiles/empty/env_tile_empty_05.png",
		"res://assets/art/tiles/empty/env_tile_empty_06.png",
		"res://assets/art/tiles/empty/env_tile_empty_07.png",
		"res://assets/art/tiles/empty/env_tile_empty_08.png",
		"res://assets/art/tiles/empty/env_tile_empty_09.png",
		"res://assets/art/tiles/empty/env_tile_empty_10.png",
		"res://assets/art/tiles/empty/env_tile_empty_11.png",
		"res://assets/art/tiles/empty/env_tile_empty_12.png",
		"res://assets/art/tiles/empty/env_tile_empty_13.png",
		"res://assets/art/tiles/empty/env_tile_empty_14.png",
		"res://assets/art/tiles/empty/env_tile_empty_15.png",
		"res://assets/art/tiles/empty/env_tile_empty_16.png",
	],
	[  # TREE — 16 variants
		"res://assets/art/tiles/tree/env_tile_tree_01.png",
		"res://assets/art/tiles/tree/env_tile_tree_02.png",
		"res://assets/art/tiles/tree/env_tile_tree_03.png",
		"res://assets/art/tiles/tree/env_tile_tree_04.png",
		"res://assets/art/tiles/tree/env_tile_tree_05.png",
		"res://assets/art/tiles/tree/env_tile_tree_06.png",
		"res://assets/art/tiles/tree/env_tile_tree_07.png",
		"res://assets/art/tiles/tree/env_tile_tree_08.png",
		"res://assets/art/tiles/tree/env_tile_tree_09.png",
		"res://assets/art/tiles/tree/env_tile_tree_10.png",
		"res://assets/art/tiles/tree/env_tile_tree_11.png",
		"res://assets/art/tiles/tree/env_tile_tree_12.png",
		"res://assets/art/tiles/tree/env_tile_tree_13.png",
		"res://assets/art/tiles/tree/env_tile_tree_14.png",
		"res://assets/art/tiles/tree/env_tile_tree_15.png",
		"res://assets/art/tiles/tree/env_tile_tree_16.png",
	],  # TREE
	[  # STONE — 16 rock variants
		"res://assets/art/tiles/stone/env_tile_stone_01.png",
		"res://assets/art/tiles/stone/env_tile_stone_02.png",
		"res://assets/art/tiles/stone/env_tile_stone_03.png",
		"res://assets/art/tiles/stone/env_tile_stone_04.png",
		"res://assets/art/tiles/stone/env_tile_stone_05.png",
		"res://assets/art/tiles/stone/env_tile_stone_06.png",
		"res://assets/art/tiles/stone/env_tile_stone_07.png",
		"res://assets/art/tiles/stone/env_tile_stone_08.png",
		"res://assets/art/tiles/stone/env_tile_stone_09.png",
		"res://assets/art/tiles/stone/env_tile_stone_10.png",
		"res://assets/art/tiles/stone/env_tile_stone_11.png",
		"res://assets/art/tiles/stone/env_tile_stone_12.png",
		"res://assets/art/tiles/stone/env_tile_stone_13.png",
		"res://assets/art/tiles/stone/env_tile_stone_14.png",
		"res://assets/art/tiles/stone/env_tile_stone_15.png",
		"res://assets/art/tiles/stone/env_tile_stone_16.png",
	],  # STONE
	[  # BERRY — 16 bush variants
		"res://assets/art/tiles/berry/env_tile_berry_01.png",
		"res://assets/art/tiles/berry/env_tile_berry_02.png",
		"res://assets/art/tiles/berry/env_tile_berry_03.png",
		"res://assets/art/tiles/berry/env_tile_berry_04.png",
		"res://assets/art/tiles/berry/env_tile_berry_05.png",
		"res://assets/art/tiles/berry/env_tile_berry_06.png",
		"res://assets/art/tiles/berry/env_tile_berry_07.png",
		"res://assets/art/tiles/berry/env_tile_berry_08.png",
		"res://assets/art/tiles/berry/env_tile_berry_09.png",
		"res://assets/art/tiles/berry/env_tile_berry_10.png",
		"res://assets/art/tiles/berry/env_tile_berry_11.png",
		"res://assets/art/tiles/berry/env_tile_berry_12.png",
		"res://assets/art/tiles/berry/env_tile_berry_13.png",
		"res://assets/art/tiles/berry/env_tile_berry_14.png",
		"res://assets/art/tiles/berry/env_tile_berry_15.png",
		"res://assets/art/tiles/berry/env_tile_berry_16.png",
	],  # BERRY
	[  # GRASS — 16 tall grass variants
		"res://assets/art/tiles/grass/env_tile_grass_01.png",
		"res://assets/art/tiles/grass/env_tile_grass_02.png",
		"res://assets/art/tiles/grass/env_tile_grass_03.png",
		"res://assets/art/tiles/grass/env_tile_grass_04.png",
		"res://assets/art/tiles/grass/env_tile_grass_05.png",
		"res://assets/art/tiles/grass/env_tile_grass_06.png",
		"res://assets/art/tiles/grass/env_tile_grass_07.png",
		"res://assets/art/tiles/grass/env_tile_grass_08.png",
		"res://assets/art/tiles/grass/env_tile_grass_09.png",
		"res://assets/art/tiles/grass/env_tile_grass_10.png",
		"res://assets/art/tiles/grass/env_tile_grass_11.png",
		"res://assets/art/tiles/grass/env_tile_grass_12.png",
		"res://assets/art/tiles/grass/env_tile_grass_13.png",
		"res://assets/art/tiles/grass/env_tile_grass_14.png",
		"res://assets/art/tiles/grass/env_tile_grass_15.png",
		"res://assets/art/tiles/grass/env_tile_grass_16.png",
	],  # GRASS
	[],  # IMPASSABLE
	[  # WHEAT — 16 wheat-field variants (generated via PixelLab /create-tileset)
		"res://assets/art/tiles/wheat/env_tile_wheat_01.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_02.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_03.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_04.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_05.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_06.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_07.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_08.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_09.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_10.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_11.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_12.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_13.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_14.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_15.png",
		"res://assets/art/tiles/wheat/env_tile_wheat_16.png",
	],  # WHEAT
	[  # CLAY — 16 clay-pit variants (generated via PixelLab /create-tileset)
		"res://assets/art/tiles/clay/env_tile_clay_01.png",
		"res://assets/art/tiles/clay/env_tile_clay_02.png",
		"res://assets/art/tiles/clay/env_tile_clay_03.png",
		"res://assets/art/tiles/clay/env_tile_clay_04.png",
		"res://assets/art/tiles/clay/env_tile_clay_05.png",
		"res://assets/art/tiles/clay/env_tile_clay_06.png",
		"res://assets/art/tiles/clay/env_tile_clay_07.png",
		"res://assets/art/tiles/clay/env_tile_clay_08.png",
		"res://assets/art/tiles/clay/env_tile_clay_09.png",
		"res://assets/art/tiles/clay/env_tile_clay_10.png",
		"res://assets/art/tiles/clay/env_tile_clay_11.png",
		"res://assets/art/tiles/clay/env_tile_clay_12.png",
		"res://assets/art/tiles/clay/env_tile_clay_13.png",
		"res://assets/art/tiles/clay/env_tile_clay_14.png",
		"res://assets/art/tiles/clay/env_tile_clay_15.png",
		"res://assets/art/tiles/clay/env_tile_clay_16.png",
	],  # CLAY
	[],  # WATER — no assets yet, falls back to solid blue (tileset follow-up via PixelLab)
	[],  # COAST — no assets yet, falls back to lighter blue (tileset follow-up via PixelLab)
	[  # IRON — 16 iron-pit variants (generated via PixelLab /create-tileset)
		"res://assets/art/tiles/iron/env_tile_iron_01.png", "res://assets/art/tiles/iron/env_tile_iron_02.png",
		"res://assets/art/tiles/iron/env_tile_iron_03.png", "res://assets/art/tiles/iron/env_tile_iron_04.png",
		"res://assets/art/tiles/iron/env_tile_iron_05.png", "res://assets/art/tiles/iron/env_tile_iron_06.png",
		"res://assets/art/tiles/iron/env_tile_iron_07.png", "res://assets/art/tiles/iron/env_tile_iron_08.png",
		"res://assets/art/tiles/iron/env_tile_iron_09.png", "res://assets/art/tiles/iron/env_tile_iron_10.png",
		"res://assets/art/tiles/iron/env_tile_iron_11.png", "res://assets/art/tiles/iron/env_tile_iron_12.png",
		"res://assets/art/tiles/iron/env_tile_iron_13.png", "res://assets/art/tiles/iron/env_tile_iron_14.png",
		"res://assets/art/tiles/iron/env_tile_iron_15.png", "res://assets/art/tiles/iron/env_tile_iron_16.png",
	],  # IRON
	[  # COPPER — 16 copper-pit variants
		"res://assets/art/tiles/copper/env_tile_copper_01.png", "res://assets/art/tiles/copper/env_tile_copper_02.png",
		"res://assets/art/tiles/copper/env_tile_copper_03.png", "res://assets/art/tiles/copper/env_tile_copper_04.png",
		"res://assets/art/tiles/copper/env_tile_copper_05.png", "res://assets/art/tiles/copper/env_tile_copper_06.png",
		"res://assets/art/tiles/copper/env_tile_copper_07.png", "res://assets/art/tiles/copper/env_tile_copper_08.png",
		"res://assets/art/tiles/copper/env_tile_copper_09.png", "res://assets/art/tiles/copper/env_tile_copper_10.png",
		"res://assets/art/tiles/copper/env_tile_copper_11.png", "res://assets/art/tiles/copper/env_tile_copper_12.png",
		"res://assets/art/tiles/copper/env_tile_copper_13.png", "res://assets/art/tiles/copper/env_tile_copper_14.png",
		"res://assets/art/tiles/copper/env_tile_copper_15.png", "res://assets/art/tiles/copper/env_tile_copper_16.png",
	],  # COPPER
	[  # TIN — 16 tin-pit variants
		"res://assets/art/tiles/tin/env_tile_tin_01.png", "res://assets/art/tiles/tin/env_tile_tin_02.png",
		"res://assets/art/tiles/tin/env_tile_tin_03.png", "res://assets/art/tiles/tin/env_tile_tin_04.png",
		"res://assets/art/tiles/tin/env_tile_tin_05.png", "res://assets/art/tiles/tin/env_tile_tin_06.png",
		"res://assets/art/tiles/tin/env_tile_tin_07.png", "res://assets/art/tiles/tin/env_tile_tin_08.png",
		"res://assets/art/tiles/tin/env_tile_tin_09.png", "res://assets/art/tiles/tin/env_tile_tin_10.png",
		"res://assets/art/tiles/tin/env_tile_tin_11.png", "res://assets/art/tiles/tin/env_tile_tin_12.png",
		"res://assets/art/tiles/tin/env_tile_tin_13.png", "res://assets/art/tiles/tin/env_tile_tin_14.png",
		"res://assets/art/tiles/tin/env_tile_tin_15.png", "res://assets/art/tiles/tin/env_tile_tin_16.png",
	],  # TIN
	[  # SILVER — 16 silver-pit variants
		"res://assets/art/tiles/silver/env_tile_silver_01.png", "res://assets/art/tiles/silver/env_tile_silver_02.png",
		"res://assets/art/tiles/silver/env_tile_silver_03.png", "res://assets/art/tiles/silver/env_tile_silver_04.png",
		"res://assets/art/tiles/silver/env_tile_silver_05.png", "res://assets/art/tiles/silver/env_tile_silver_06.png",
		"res://assets/art/tiles/silver/env_tile_silver_07.png", "res://assets/art/tiles/silver/env_tile_silver_08.png",
		"res://assets/art/tiles/silver/env_tile_silver_09.png", "res://assets/art/tiles/silver/env_tile_silver_10.png",
		"res://assets/art/tiles/silver/env_tile_silver_11.png", "res://assets/art/tiles/silver/env_tile_silver_12.png",
		"res://assets/art/tiles/silver/env_tile_silver_13.png", "res://assets/art/tiles/silver/env_tile_silver_14.png",
		"res://assets/art/tiles/silver/env_tile_silver_15.png", "res://assets/art/tiles/silver/env_tile_silver_16.png",
	],  # SILVER
	[  # GOLD — 16 gold-pit variants
		"res://assets/art/tiles/gold/env_tile_gold_01.png", "res://assets/art/tiles/gold/env_tile_gold_02.png",
		"res://assets/art/tiles/gold/env_tile_gold_03.png", "res://assets/art/tiles/gold/env_tile_gold_04.png",
		"res://assets/art/tiles/gold/env_tile_gold_05.png", "res://assets/art/tiles/gold/env_tile_gold_06.png",
		"res://assets/art/tiles/gold/env_tile_gold_07.png", "res://assets/art/tiles/gold/env_tile_gold_08.png",
		"res://assets/art/tiles/gold/env_tile_gold_09.png", "res://assets/art/tiles/gold/env_tile_gold_10.png",
		"res://assets/art/tiles/gold/env_tile_gold_11.png", "res://assets/art/tiles/gold/env_tile_gold_12.png",
		"res://assets/art/tiles/gold/env_tile_gold_13.png", "res://assets/art/tiles/gold/env_tile_gold_14.png",
		"res://assets/art/tiles/gold/env_tile_gold_15.png", "res://assets/art/tiles/gold/env_tile_gold_16.png",
	],  # GOLD
	[  # GEMSTONE — 16 gemstone-pit variants
		"res://assets/art/tiles/gemstone/env_tile_gemstone_01.png", "res://assets/art/tiles/gemstone/env_tile_gemstone_02.png",
		"res://assets/art/tiles/gemstone/env_tile_gemstone_03.png", "res://assets/art/tiles/gemstone/env_tile_gemstone_04.png",
		"res://assets/art/tiles/gemstone/env_tile_gemstone_05.png", "res://assets/art/tiles/gemstone/env_tile_gemstone_06.png",
		"res://assets/art/tiles/gemstone/env_tile_gemstone_07.png", "res://assets/art/tiles/gemstone/env_tile_gemstone_08.png",
		"res://assets/art/tiles/gemstone/env_tile_gemstone_09.png", "res://assets/art/tiles/gemstone/env_tile_gemstone_10.png",
		"res://assets/art/tiles/gemstone/env_tile_gemstone_11.png", "res://assets/art/tiles/gemstone/env_tile_gemstone_12.png",
		"res://assets/art/tiles/gemstone/env_tile_gemstone_13.png", "res://assets/art/tiles/gemstone/env_tile_gemstone_14.png",
		"res://assets/art/tiles/gemstone/env_tile_gemstone_15.png", "res://assets/art/tiles/gemstone/env_tile_gemstone_16.png",
	],  # GEMSTONE
	[  # FLAX — 16 opaque flax-field variants
		"res://assets/art/tiles/flax/env_tile_flax_01.png", "res://assets/art/tiles/flax/env_tile_flax_02.png",
		"res://assets/art/tiles/flax/env_tile_flax_03.png", "res://assets/art/tiles/flax/env_tile_flax_04.png",
		"res://assets/art/tiles/flax/env_tile_flax_05.png", "res://assets/art/tiles/flax/env_tile_flax_06.png",
		"res://assets/art/tiles/flax/env_tile_flax_07.png", "res://assets/art/tiles/flax/env_tile_flax_08.png",
		"res://assets/art/tiles/flax/env_tile_flax_09.png", "res://assets/art/tiles/flax/env_tile_flax_10.png",
		"res://assets/art/tiles/flax/env_tile_flax_11.png", "res://assets/art/tiles/flax/env_tile_flax_12.png",
		"res://assets/art/tiles/flax/env_tile_flax_13.png", "res://assets/art/tiles/flax/env_tile_flax_14.png",
		"res://assets/art/tiles/flax/env_tile_flax_15.png", "res://assets/art/tiles/flax/env_tile_flax_16.png",
	],  # FLAX
	[  # HOPS — 16 opaque hops-field variants
		"res://assets/art/tiles/hops/env_tile_hops_01.png", "res://assets/art/tiles/hops/env_tile_hops_02.png",
		"res://assets/art/tiles/hops/env_tile_hops_03.png", "res://assets/art/tiles/hops/env_tile_hops_04.png",
		"res://assets/art/tiles/hops/env_tile_hops_05.png", "res://assets/art/tiles/hops/env_tile_hops_06.png",
		"res://assets/art/tiles/hops/env_tile_hops_07.png", "res://assets/art/tiles/hops/env_tile_hops_08.png",
		"res://assets/art/tiles/hops/env_tile_hops_09.png", "res://assets/art/tiles/hops/env_tile_hops_10.png",
		"res://assets/art/tiles/hops/env_tile_hops_11.png", "res://assets/art/tiles/hops/env_tile_hops_12.png",
		"res://assets/art/tiles/hops/env_tile_hops_13.png", "res://assets/art/tiles/hops/env_tile_hops_14.png",
		"res://assets/art/tiles/hops/env_tile_hops_15.png", "res://assets/art/tiles/hops/env_tile_hops_16.png",
	],  # HOPS
	[  # GRAPES — 16 opaque vineyard variants
		"res://assets/art/tiles/grapes/env_tile_grapes_01.png", "res://assets/art/tiles/grapes/env_tile_grapes_02.png",
		"res://assets/art/tiles/grapes/env_tile_grapes_03.png", "res://assets/art/tiles/grapes/env_tile_grapes_04.png",
		"res://assets/art/tiles/grapes/env_tile_grapes_05.png", "res://assets/art/tiles/grapes/env_tile_grapes_06.png",
		"res://assets/art/tiles/grapes/env_tile_grapes_07.png", "res://assets/art/tiles/grapes/env_tile_grapes_08.png",
		"res://assets/art/tiles/grapes/env_tile_grapes_09.png", "res://assets/art/tiles/grapes/env_tile_grapes_10.png",
		"res://assets/art/tiles/grapes/env_tile_grapes_11.png", "res://assets/art/tiles/grapes/env_tile_grapes_12.png",
		"res://assets/art/tiles/grapes/env_tile_grapes_13.png", "res://assets/art/tiles/grapes/env_tile_grapes_14.png",
		"res://assets/art/tiles/grapes/env_tile_grapes_15.png", "res://assets/art/tiles/grapes/env_tile_grapes_16.png",
	],  # GRAPES
	[  # SAND — 16 opaque beach-sand variants
		"res://assets/art/tiles/sand/env_tile_sand_01.png", "res://assets/art/tiles/sand/env_tile_sand_02.png",
		"res://assets/art/tiles/sand/env_tile_sand_03.png", "res://assets/art/tiles/sand/env_tile_sand_04.png",
		"res://assets/art/tiles/sand/env_tile_sand_05.png", "res://assets/art/tiles/sand/env_tile_sand_06.png",
		"res://assets/art/tiles/sand/env_tile_sand_07.png", "res://assets/art/tiles/sand/env_tile_sand_08.png",
		"res://assets/art/tiles/sand/env_tile_sand_09.png", "res://assets/art/tiles/sand/env_tile_sand_10.png",
		"res://assets/art/tiles/sand/env_tile_sand_11.png", "res://assets/art/tiles/sand/env_tile_sand_12.png",
		"res://assets/art/tiles/sand/env_tile_sand_13.png", "res://assets/art/tiles/sand/env_tile_sand_14.png",
		"res://assets/art/tiles/sand/env_tile_sand_15.png", "res://assets/art/tiles/sand/env_tile_sand_16.png",
	],  # SAND
	[  # OLIVE — 16 transparent olive-grove overlays (composited over EMPTY/sand)
		"res://assets/art/tiles/olive/env_tile_olive_01.png", "res://assets/art/tiles/olive/env_tile_olive_02.png",
		"res://assets/art/tiles/olive/env_tile_olive_03.png", "res://assets/art/tiles/olive/env_tile_olive_04.png",
		"res://assets/art/tiles/olive/env_tile_olive_05.png", "res://assets/art/tiles/olive/env_tile_olive_06.png",
		"res://assets/art/tiles/olive/env_tile_olive_07.png", "res://assets/art/tiles/olive/env_tile_olive_08.png",
		"res://assets/art/tiles/olive/env_tile_olive_09.png", "res://assets/art/tiles/olive/env_tile_olive_10.png",
		"res://assets/art/tiles/olive/env_tile_olive_11.png", "res://assets/art/tiles/olive/env_tile_olive_12.png",
		"res://assets/art/tiles/olive/env_tile_olive_13.png", "res://assets/art/tiles/olive/env_tile_olive_14.png",
		"res://assets/art/tiles/olive/env_tile_olive_15.png", "res://assets/art/tiles/olive/env_tile_olive_16.png",
	],  # OLIVE
	[  # BEES — 16 transparent flower overlays (honey source, composited over EMPTY/sand)
		"res://assets/art/tiles/bees/env_tile_bees_01.png", "res://assets/art/tiles/bees/env_tile_bees_02.png",
		"res://assets/art/tiles/bees/env_tile_bees_03.png", "res://assets/art/tiles/bees/env_tile_bees_04.png",
		"res://assets/art/tiles/bees/env_tile_bees_05.png", "res://assets/art/tiles/bees/env_tile_bees_06.png",
		"res://assets/art/tiles/bees/env_tile_bees_07.png", "res://assets/art/tiles/bees/env_tile_bees_08.png",
		"res://assets/art/tiles/bees/env_tile_bees_09.png", "res://assets/art/tiles/bees/env_tile_bees_10.png",
		"res://assets/art/tiles/bees/env_tile_bees_11.png", "res://assets/art/tiles/bees/env_tile_bees_12.png",
		"res://assets/art/tiles/bees/env_tile_bees_13.png", "res://assets/art/tiles/bees/env_tile_bees_14.png",
		"res://assets/art/tiles/bees/env_tile_bees_15.png", "res://assets/art/tiles/bees/env_tile_bees_16.png",
	],  # BEES
	[  # MARBLE — 16 transparent marble-outcrop overlays ("like stone")
		"res://assets/art/tiles/marble/env_tile_marble_01.png", "res://assets/art/tiles/marble/env_tile_marble_02.png",
		"res://assets/art/tiles/marble/env_tile_marble_03.png", "res://assets/art/tiles/marble/env_tile_marble_04.png",
		"res://assets/art/tiles/marble/env_tile_marble_05.png", "res://assets/art/tiles/marble/env_tile_marble_06.png",
		"res://assets/art/tiles/marble/env_tile_marble_07.png", "res://assets/art/tiles/marble/env_tile_marble_08.png",
		"res://assets/art/tiles/marble/env_tile_marble_09.png", "res://assets/art/tiles/marble/env_tile_marble_10.png",
		"res://assets/art/tiles/marble/env_tile_marble_11.png", "res://assets/art/tiles/marble/env_tile_marble_12.png",
		"res://assets/art/tiles/marble/env_tile_marble_13.png", "res://assets/art/tiles/marble/env_tile_marble_14.png",
		"res://assets/art/tiles/marble/env_tile_marble_15.png", "res://assets/art/tiles/marble/env_tile_marble_16.png",
	],  # MARBLE
	[  # AMBER — UI resource icon composited over a grass tile (dedicated overlay art rejected)
		"res://assets/ui/icons/resources/amber.png",
	],  # AMBER
	[  # PEARL — UI resource icon composited over a water tile (dedicated overlay art rejected)
		"res://assets/ui/icons/resources/pearl.png",
	],  # PEARL
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
	Color(0.49, 0.32, 0.26),  # IRON — rusty brown
	Color(0.72, 0.45, 0.20),  # COPPER — orange-bronze
	Color(0.62, 0.64, 0.67),  # TIN — dull pewter gray
	Color(0.78, 0.80, 0.85),  # SILVER — bright pale silver
	Color(0.90, 0.75, 0.20),  # GOLD — rich gold
	Color(0.40, 0.75, 0.78),  # GEMSTONE — gem teal
	Color(0.62, 0.72, 0.86),  # FLAX — pale blue-grey flax bloom
	Color(0.56, 0.74, 0.36),  # HOPS — yellow-green hop bines
	Color(0.42, 0.16, 0.42),  # GRAPES — deep purple vineyard
	Color(0.90, 0.84, 0.62),  # SAND — pale beach sand
	Color(0.36, 0.46, 0.24),  # OLIVE — muted olive green
	Color(0.96, 0.82, 0.28),  # BEES — flower yellow
	Color(0.88, 0.88, 0.90),  # MARBLE — near-white stone
	Color(0.86, 0.52, 0.16),  # AMBER — warm amber orange
	Color(0.94, 0.92, 0.86),  # PEARL — iridescent off-white
]

## Overlay TileTypes whose background cell must show a non-sand base under the (transparent)
## overlay sprite. Unlisted types render on the default EMPTY (sand) base — matching how
## tree/stone overlays already composite over sand. (ADR-0015 addendum.)
const _TERRAIN_BASE_TYPE: Dictionary = {
	WorldGrid.TileType.AMBER: WorldGrid.TileType.GRASS,
	WorldGrid.TileType.PEARL: WorldGrid.TileType.WATER,
}

## Atlas column where each TileType starts (populated by build_and_assign).
var _terrain_type_offsets: Array[int] = []
## Number of variant slots per TileType, always >= 1 (populated by build_and_assign).
var _terrain_type_variant_counts: Array[int] = []
## Number of columns in the wrapped 2D atlas (populated by _build_terrain_tileset).
var _atlas_cols: int = 1

## Max atlas columns; 128 * 64px = 8192px wide, safely under the GPU texture-size limit
## (commonly 16384). The atlas wraps into multiple rows once the variant count exceeds this.
const _MAX_ATLAS_COLS: int = 128


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
			var terrain: WorldGrid.TileType = grid.get_terrain(tile)
			# Transparent overlays (olive/bees/pearl) need their own base under them;
			# everything else composites over sand (EMPTY), matching tree/stone overlays.
			var base: int = _TERRAIN_BASE_TYPE.get(terrain, empty)
			background_layer.set_cell(tile, 0, _terrain_type_to_atlas(base, tile))
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
	# Wrap the atlas into a 2D grid so neither dimension exceeds the GPU texture-size
	# limit. A single horizontal row would overflow once enough biome variants exist.
	var cols: int = maxi(1, mini(total, _MAX_ATLAS_COLS))
	var rows: int = maxi(1, ceili(float(total) / float(cols)))
	_atlas_cols = cols
	var atlas_img := Image.create(tile_px * cols, tile_px * rows, false, Image.FORMAT_RGBA8)
	for i in range(total):
		var dest := Vector2i((i % cols) * tile_px, (i / cols) * tile_px)
		atlas_img.blit_rect(all_images[i], Rect2i(0, 0, tile_px, tile_px), dest)
	return _make_tileset(atlas_img, total)


func _make_tileset(img: Image, tile_count: int) -> TileSet:
	var tile_size := Vector2i(WorldGrid.TILE_SIZE, WorldGrid.TILE_SIZE)
	var texture := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = tile_size
	for i in range(tile_count):
		source.create_tile(Vector2i(i % _atlas_cols, i / _atlas_cols))
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
	var index: int = offset + variant
	return Vector2i(index % _atlas_cols, index / _atlas_cols)
