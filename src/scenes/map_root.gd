class_name MapRoot extends Node2D
## Game world rendering controller.
## Owns the three TileMapLayer visual layers and the WorldGrid data node.
## After generation, syncs all 900 tiles in a single batch set_cell() pass.
## ADR-0004: Grid data is authoritative; TileMapLayer is a pure rendering target.

const _TILE_PANEL_SCENE: PackedScene = preload("res://src/ui/TileInteractionPanel.tscn")

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
]

## Fallback solid colors, one per TileType (EMPTY=0 … IMPASSABLE=5).
const _TERRAIN_FALLBACK_COLORS: Array[Color] = [
	Color(0.76, 0.70, 0.55),  # EMPTY — sandy tan
	Color(0.10, 0.38, 0.10),  # TREE — dark green
	Color(0.45, 0.45, 0.45),  # STONE — medium gray
	Color(0.82, 0.20, 0.25),  # BERRY — red
	Color(0.44, 0.76, 0.28),  # GRASS — light green
	Color(0.08, 0.08, 0.14),  # IMPASSABLE — near-black
]

## Populated by _build_terrain_tileset: atlas column where each TileType starts.
var _terrain_type_offsets: Array[int] = []
## Populated by _build_terrain_tileset: number of variant slots per TileType (always >= 1).
var _terrain_type_variant_counts: Array[int] = []

@onready var background_layer: TileMapLayer = $BackgroundLayer
@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var building_slots: TileMapLayer = $BuildingSlots
@onready var grid: WorldGrid = $WorldGrid

@onready var _player: PlayerCharacter = $PlayerCharacter
@onready var _registry: Node = get_node("/root/BuildingRegistry")

## Tracks each spawned resource icon for per-frame float animation and drag hit-testing.
## One entry per resource instance: {node: Node2D, tile: Vector2i, resource_idx: int,
##   resource_id: StringName, base_pos: Vector2, phase: float}
var _resource_icons: Array = []
var _interaction_panel: TileInteractionPanel = null
var _last_action_tile: Vector2i = Vector2i(-1, -1)
## Frozen at action-start; never overwritten by subsequent tile clicks.
var _active_action_tile: Vector2i = Vector2i(-1, -1)

## Drag state — set while the player holds LMB on a resource icon.
var _drag_icon: Node2D = null          ## the icon node being dragged
var _drag_icon_entry: Dictionary = {}  ## reference into _resource_icons

## Drag visual overlays (AC2: cost label, AC3: path line). Initialized in _ready().
var _drag_cost_label: Label = null
var _drag_energy_label: Label = null
var _drag_path_line: Line2D = null
var _drag_path_dots: Array = []
var _drag_path_dst_marker: Sprite2D = null
var _drag_src_tile: Vector2i = Vector2i(-1, -1)
var _drag_path_phase: float = 0.0
var _drag_hold_timer: float = 0.0      ## LMB hold time accumulated during active world drag
var _drag_collected_count: int = 1     ## total items in current drag batch (1 = only the dragged item)
var _drag_count_label: Label = null    ## "×N" badge shown near cursor when batch > 1

var _inventory_screen: InventoryScreen = null

## Maps building_id → BuildingStatusIndicator node for production buildings.
var _building_indicators: Dictionary[String, BuildingStatusIndicator] = {}
## Maps building_id → Sprite2D for construction skeleton→full transition.
var _building_sprites: Dictionary[String, Sprite2D] = {}
## Maps tile → Sprite2D for placed path tiles.
var _path_sprites: Dictionary = {}

var _hud: HUD = null
var _map_select_highlight: Sprite2D = null
var _route_lines: RouteLines = null
var _npc_overlay: NpcOverlay = null
## Progress indicator shown at the harvested tile while a manual action is in progress.
var _action_indicator: BuildingStatusIndicator = null

## Active pending manual transports (resources in transit after a drag-drop commit).
## Each entry: {icon, icon_entry, source_tile, ticks_total, ticks_elapsed, indicator, on_complete}
var _pending_transports: Array = []

## Pause state captured before a manual action or transport begins, restored when done.
var _was_paused_before_action: bool = false

## Modulate applied to a building sprite while it is still under construction.
const _SKELETON_MODULATE: Color = Color(0.75, 0.88, 1.0, 0.28)

## Storage-drag state — set while a resource is dragged out of a building container.
var _drag_from_container_id: StringName = &""
var _drag_resource_id: StringName = &""
var _drag_from_building_tile: Vector2i = Vector2i(-1, -1)

## Input-buffer-drag state — set while a resource is dragged out of a building input buffer.
var _drag_from_input_building_id: String = ""
## Output-buffer-drag state — set while a resource is dragged out of a building output buffer.
var _drag_from_output_building_id: String = ""

const _PATH_LINE_WIDTH: float = 2.5
const _PATH_DOT_COUNT: int = 5
const _PATH_DOT_RADIUS: int = 3
const _PATH_DST_MARKER_RADIUS: int = 5
const _PATH_DOT_SPEED: float = 80.0
## Action Blue #4A7EA8 — "Available / You can do this" per Art Bible
const _PATH_COLOR_VALID: Color = Color(0.290, 0.494, 0.659, 1.0)
## Error Red #C45A4A per Art Bible
const _PATH_COLOR_INVALID: Color = Color(0.769, 0.353, 0.290, 1.0)
const _HOLD_COLLECT_DELAY: float = 0.5     ## hold time before first batch collect begins
const _HOLD_COLLECT_INTERVAL: float = 0.35 ## interval between subsequent batch collects


func _ready() -> void:
	_setup_tilesets()
	WorldSaveManager.register_world_grid(grid)
	_interaction_panel = _TILE_PANEL_SCENE.instantiate() as TileInteractionPanel
	add_child(_interaction_panel)
	_interaction_panel.world_click_at.connect(_on_panel_world_click)
	_registry.connect("building_placed", _on_building_placed)
	_registry.building_state_changed.connect(_on_building_state_changed)
	_registry.building_construction_complete.connect(_on_building_construction_complete)
	_registry.building_demolished.connect(_on_building_demolished)
	_registry.building_items_dropped.connect(_on_building_items_dropped)
	TickSystem.ticks_advanced.connect(_on_ticks_advanced_indicators)
	_player.init_dependencies(TickSystem, null, grid, null)
	_registry.init_dependencies(grid, _player)
	PathSystem.init_dependencies(grid)
	PathSystem.path_placed.connect(_on_path_placed)
	PathSystem.path_updated.connect(_on_path_updated)
	PathSystem.path_removed.connect(_on_path_removed)
	LogisticsSystem.set_grid_map(grid)
	NPCSystem.set_grid_map(grid)
	if WorldSaveManager.has_pending_load():
		WorldSaveManager.apply_pending_load()
	else:
		grid.generate(randi())
		_registry.place_starter_building(BuildingRegistry.BuildingType.COLLECTION_POINT, Vector2i(12, 12))
	_sync_tilemap()
	_spawn_resource_badges()
	_player.action_started.connect(_on_action_started)
	_player.action_completed.connect(_on_action_completed)
	_player.action_progress_update.connect(_on_action_progress_update)
	_setup_drag_overlays()
	_inventory_screen = InventoryScreen.new()
	_inventory_screen.name = "InventoryScreen"
	add_child(_inventory_screen)
	_setup_map_select_highlight()
	_route_lines = RouteLines.new()
	_route_lines.name = "RouteLines"
	add_child(_route_lines)
	_route_lines.init_dependencies(grid)
	_npc_overlay = NpcOverlay.new()
	_npc_overlay.name = "NpcOverlay"
	add_child(_npc_overlay)
	_npc_overlay.init_dependencies(grid)
	call_deferred(&"_wire_building_detail")
	call_deferred(&"_wire_inventory_hud")


## Creates the cost label (AC2) and path line overlay (AC3) used during drag.
func _setup_drag_overlays() -> void:
	_drag_cost_label = Label.new()
	_drag_cost_label.visible = false
	_drag_cost_label.z_index = 20
	_drag_cost_label.add_theme_font_size_override("font_size", 16)
	_drag_cost_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	_drag_cost_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_drag_cost_label.add_theme_constant_override("outline_size", 3)
	add_child(_drag_cost_label)

	_drag_energy_label = Label.new()
	_drag_energy_label.visible = false
	_drag_energy_label.z_index = 20
	_drag_energy_label.add_theme_font_size_override("font_size", 16)
	_drag_energy_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_drag_energy_label.add_theme_constant_override("outline_size", 3)
	add_child(_drag_energy_label)

	_drag_path_line = Line2D.new()
	_drag_path_line.width = _PATH_LINE_WIDTH
	_drag_path_line.default_color = _PATH_COLOR_VALID
	_drag_path_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_drag_path_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_drag_path_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_drag_path_line.visible = false
	_drag_path_line.z_index = 5
	add_child(_drag_path_line)

	var dot_tex := _make_circle_texture(_PATH_DOT_RADIUS, Color.WHITE)
	for _i in range(_PATH_DOT_COUNT):
		var dot := Sprite2D.new()
		dot.texture = dot_tex
		dot.visible = false
		dot.z_index = 6
		add_child(dot)
		_drag_path_dots.append(dot)

	_drag_path_dst_marker = Sprite2D.new()
	_drag_path_dst_marker.texture = _make_circle_texture(_PATH_DST_MARKER_RADIUS, Color.WHITE)
	_drag_path_dst_marker.visible = false
	_drag_path_dst_marker.z_index = 6
	add_child(_drag_path_dst_marker)

	_drag_count_label = Label.new()
	_drag_count_label.visible = false
	_drag_count_label.z_index = 22
	_drag_count_label.add_theme_font_size_override("font_size", 15)
	_drag_count_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	_drag_count_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_drag_count_label.add_theme_constant_override("outline_size", 4)
	add_child(_drag_count_label)


# ── TileSet construction ──────────────────────────────────────────────────────

## Constructs TileSet resources at runtime.
func _setup_tilesets() -> void:
	var terrain_ts := _build_terrain_tileset()
	background_layer.tile_set = terrain_ts
	terrain_layer.tile_set = terrain_ts
	# BuildingSlots: no visual — TileSet left unset
	# ResourceOverlay TileMapLayer left empty; resources rendered as badge Sprite2D nodes


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
			images.append(_make_solid_tile(tile_px, _TERRAIN_FALLBACK_COLORS[type_idx]))
		for img in images:
			all_images.append(img)
		_terrain_type_variant_counts.append(images.size())

	var total: int = all_images.size()
	var atlas_img := Image.create(tile_px * total, tile_px, false, Image.FORMAT_RGBA8)
	for i in range(total):
		atlas_img.blit_rect(all_images[i], Rect2i(0, 0, tile_px, tile_px), Vector2i(i * tile_px, 0))
	return _make_tileset(atlas_img, total)


## PNG paths for resource overlay icons. Empty string = fall back to solid dot.
## Index order matches _resource_id_to_index: 0=wood, 1=stone, 2=berry, 3=fiber, 4=tool.
const _RESOURCE_PNG: Array[String] = [
	"res://assets/art/tiles/env_tile_resource_wood.png",
	"res://assets/art/tiles/env_tile_resource_stone.png",
	"res://assets/art/tiles/env_tile_resource_berry.png",
	"res://assets/art/tiles/env_tile_resource_fiber.png",
	"res://assets/art/tiles/env_tile_resource_tool.png",
]

## Fallback dot colors when no PNG exists for a resource type.
const _RESOURCE_FALLBACK_COLORS: Array[Color] = [
	Color(0.55, 0.28, 0.08),  # wood — brown
	Color(0.62, 0.62, 0.62),  # stone — light gray
	Color(0.90, 0.12, 0.22),  # berry — bright red
	Color(0.78, 0.88, 0.12),  # fiber — yellow-green
	Color(0.60, 0.45, 0.20),  # tool — warm tan
]

## Used for the fallback resource texture size.
const _RESOURCE_ICON_SCALE: float = 0.55

## Icon size as fraction of tile size, indexed by (resource_count - 1), capped at 4.
const _ICON_SCALE_BY_COUNT: Array[float] = [0.45, 0.40, 0.35, 0.31]


## Generates a single solid-color tile image with a darkened 1px border.
func _make_solid_tile(tile_px: int, c: Color) -> Image:
	var img := Image.create(tile_px, tile_px, false, Image.FORMAT_RGBA8)
	var border_c: Color = c.darkened(0.25)
	for x in range(tile_px):
		for y in range(tile_px):
			img.set_pixel(x, y, border_c if (x == 0 or x == tile_px - 1 or y == 0 or y == tile_px - 1) else c)
	return img



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


# ── Tilemap sync ──────────────────────────────────────────────────────────────

## Batch-syncs all 900 tiles from WorldGrid data to TileMapLayer nodes.
## Called once after generate(). Never called per-frame.
func _sync_tilemap() -> void:
	var empty := WorldGrid.TileType.EMPTY
	for x in range(WorldGrid.GRID_SIZE):
		for y in range(WorldGrid.GRID_SIZE):
			var tile := Vector2i(x, y)
			background_layer.set_cell(tile, 0, _terrain_type_to_atlas(empty, tile))
			var terrain: WorldGrid.TileType = grid.get_terrain(tile)
			if terrain != empty:
				terrain_layer.set_cell(tile, 0, _terrain_type_to_atlas(terrain, tile))


## Returns atlas coords for the given terrain type at a given tile position.
## For types with multiple variants, selects deterministically via a prime-based hash.
func _terrain_type_to_atlas(terrain_type: WorldGrid.TileType, tile: Vector2i) -> Vector2i:
	var type_idx: int = terrain_type as int
	var offset: int = _terrain_type_offsets[type_idx]
	var count: int = _terrain_type_variant_counts[type_idx]
	var variant: int = (tile.x * 7 + tile.y * 13) % count
	return Vector2i(offset + variant, 0)


# ── Resource badges ───────────────────────────────────────────────────────────

## Spawns individual icon nodes for every resource instance at map load.
## Populates _resource_icons with one entry per instance.
func _spawn_resource_badges() -> void:
	var container := Node2D.new()
	container.name = "ResourceBadges"
	container.z_index = 1
	add_child(container)
	for x in range(WorldGrid.GRID_SIZE):
		for y in range(WorldGrid.GRID_SIZE):
			var tile := Vector2i(x, y)
			var resources: Array = grid.get_resources(tile)
			if resources.is_empty():
				continue
			var ids: Array[StringName] = []
			for rd: WorldGrid.ResourceTileData in resources:
				ids.append(rd.resource_id)
			_spawn_badge(tile, ids, container)


## Unified badge builder: creates one independent Node2D per resource instance.
## Each icon node owns its own sprites so drag moves only that icon (satisfies AC1).
## icon_scale_override > 0 bypasses _ICON_SCALE_BY_COUNT.
## pos_seed_offset varies positions so repeated spawns on the same tile don't overlap.
func _spawn_badge(tile: Vector2i, resource_ids: Array[StringName], parent: Node2D,
		icon_scale_override: float = 0.0, pop_in: bool = false, pos_seed_offset: int = 0) -> void:
	var tile_px: int = WorldGrid.TILE_SIZE
	var base_pos: Vector2 = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	var count: int = resource_ids.size()
	var scale_factor: float = icon_scale_override if icon_scale_override > 0.0 else _ICON_SCALE_BY_COUNT[mini(count - 1, _ICON_SCALE_BY_COUNT.size() - 1)]
	var icon_px: int = roundi(tile_px * scale_factor)
	var backdrop_tex := _make_circle_texture(roundi(icon_px * 0.55), Color(0.0, 0.0, 0.0, 0.30))
	var positions: Array = _random_icon_positions(tile, count, icon_px, pos_seed_offset)
	var phase: float = fmod(base_pos.x * 7.0 + base_pos.y * 13.0, TAU)

	for i in range(count):
		var icon_pos: Vector2 = base_pos + positions[i]
		var icon_node := Node2D.new()
		icon_node.position = icon_pos
		if pop_in:
			icon_node.scale = Vector2.ZERO

		var backdrop := Sprite2D.new()
		backdrop.texture = backdrop_tex
		icon_node.add_child(backdrop)

		var icon_spr := Sprite2D.new()
		icon_spr.texture = _load_resource_texture(_resource_id_to_index(resource_ids[i]))
		var tex_size: Vector2 = icon_spr.texture.get_size()
		icon_spr.scale = Vector2(float(icon_px) / tex_size.x, float(icon_px) / tex_size.y)
		icon_node.add_child(icon_spr)

		icon_node.z_index = 2
		parent.add_child(icon_node)
		_resource_icons.append({
			"node": icon_node,
			"tile": tile,
			"resource_idx": i,
			"resource_id": resource_ids[i],
			"base_pos": icon_pos,
			"phase": phase,
		})

		if pop_in:
			var tween := create_tween()
			tween.tween_property(icon_node, "scale", Vector2(1.3, 1.3), 0.12).set_trans(Tween.TRANS_BACK)
			tween.tween_property(icon_node, "scale", Vector2(1.0, 1.0), 0.08)


## Returns count evenly-spaced positions within a tile arranged in a circle.
## Deterministic: same tile+seed_offset always produces the same layout.
## A random angle offset is applied so icons don't always face the same direction.
func _random_icon_positions(tile: Vector2i, count: int, _icon_px: int, seed_offset: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tile) ^ seed_offset
	var spread: float = float(WorldGrid.TILE_SIZE) * 0.28
	var radius: float = spread * 0.7
	var angle_offset: float = rng.randf() * TAU
	var positions: Array = []
	for i in range(count):
		var angle: float = angle_offset + (float(i) / float(count)) * TAU
		positions.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return positions


## Animates all resource icons with a sine-wave vertical float (period: 2.5s, amplitude: 4px).
## Phase is staggered per tile so icons don't bob in lockstep.
## During a drag: dragged icon follows cursor; cost label and path overlay update live.
func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for entry: Dictionary in _resource_icons:
		if entry.get("in_transit", false):
			continue
		var icon_node: Node2D = entry.node as Node2D
		if _drag_icon != null and icon_node == _drag_icon:
			icon_node.global_position = get_global_mouse_position()
			continue
		icon_node.position.y = entry.base_pos.y + sin(t * TAU / 2.5 + entry.phase) * 4.0

	if (_drag_from_container_id != &"" or _drag_from_input_building_id != "" or _drag_from_output_building_id != "") and _drag_icon != null:
		_drag_icon.global_position = get_global_mouse_position()

	if _drag_icon != null:
		_drag_path_phase += delta * _PATH_DOT_SPEED
		if (_drag_from_container_id == &"" and _drag_from_input_building_id == ""
				and _drag_from_output_building_id == ""):
			var cursor_tile: Vector2i = terrain_layer.local_to_map(
				terrain_layer.to_local(get_global_mouse_position()))
			if cursor_tile == _drag_src_tile:
				_drag_hold_timer += delta
				var _hold_threshold: float = (
					_HOLD_COLLECT_DELAY if _drag_collected_count == 1 else _HOLD_COLLECT_INTERVAL
				)
				if _drag_hold_timer >= _hold_threshold:
					_drag_hold_timer -= _hold_threshold
					_try_batch_collect()
			else:
				_drag_hold_timer = 0.0
		if _drag_count_label.visible:
			_drag_count_label.position = get_global_mouse_position() + Vector2(18.0, 10.0)
	_update_drag_overlays()

	for pt: Dictionary in _pending_transports:
		pt.path_phase += delta * _PATH_DOT_SPEED
		_animate_pending_path_overlay(pt)

	_update_map_select_highlight()


## Updates cost label (AC2) and path line overlay (AC3) each frame during an active drag.
func _update_drag_overlays() -> void:
	if _drag_icon == null:
		_drag_cost_label.visible = false
		_drag_energy_label.visible = false
		_drag_count_label.visible = false
		_drag_path_line.visible = false
		_drag_path_dst_marker.visible = false
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	if _drag_from_container_id != &"" or _drag_from_input_building_id != "" or _drag_from_output_building_id != "":
		_update_storage_drag_overlays()
		return

	var cursor_world: Vector2 = get_global_mouse_position()
	var hovered_tile: Vector2i = grid.world_to_tile(cursor_world)
	var preview: Dictionary = _player.get_relocation_preview(hovered_tile)
	_drag_cost_label.text = "⏱️%d" % (preview.tick_cost * _drag_collected_count)
	_drag_cost_label.position = cursor_world + Vector2(16.0, -32.0)
	_drag_cost_label.visible = true

	_drag_energy_label.visible = false

	if not grid.is_in_bounds(hovered_tile) or _drag_src_tile == Vector2i(-1, -1):
		_drag_path_line.visible = false
		_drag_path_dst_marker.visible = false
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	var passable: bool = grid.is_passable(hovered_tile)
	var valid: bool = passable
	var path_color: Color = _PATH_COLOR_VALID if valid else _PATH_COLOR_INVALID
	var tile_px: float = float(WorldGrid.TILE_SIZE)
	var half: float = tile_px * 0.5
	var src_center: Vector2 = Vector2(_drag_src_tile) * tile_px + Vector2(half, half)
	var dst_center: Vector2 = Vector2(hovered_tile) * tile_px + Vector2(half, half)

	var path: Array[Vector2] = []
	path.append(src_center)
	var corner := Vector2(dst_center.x, src_center.y)
	if corner != src_center and corner != dst_center:
		path.append(corner)
	path.append(dst_center)

	_drag_path_line.clear_points()
	for pt: Vector2 in path:
		_drag_path_line.add_point(pt)
	_drag_path_line.default_color = path_color
	_drag_path_line.visible = true

	var dot_color: Color = path_color
	dot_color.a = 1.0
	_drag_path_dst_marker.position = dst_center
	_drag_path_dst_marker.modulate = dot_color
	_drag_path_dst_marker.visible = true

	var path_len: float = _path_length(path)
	if path_len < 1.0:
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	var spacing: float = path_len / float(_PATH_DOT_COUNT)
	var phase_wrapped: float = fmod(_drag_path_phase, path_len)
	for i in range(_PATH_DOT_COUNT):
		var dot: Sprite2D = _drag_path_dots[i]
		var t: float = fmod(phase_wrapped + float(i) * spacing, path_len)
		dot.position = _point_along_path(path, t)
		dot.modulate = dot_color
		dot.visible = true


func _update_storage_drag_overlays() -> void:
	var cursor_world: Vector2 = get_global_mouse_position()
	var hovered_tile: Vector2i = grid.world_to_tile(cursor_world)

	# ── Cost labels ──────────────────────────────────────────────────────────
	var dist: int = (abs(hovered_tile.x - _drag_from_building_tile.x)
		+ abs(hovered_tile.y - _drag_from_building_tile.y))
	var base_cost: int = maxi(1, dist)
	var tick_cost: int = base_cost * 5

	_drag_cost_label.text = "⏱️%d" % tick_cost
	_drag_cost_label.position = cursor_world + Vector2(16.0, -32.0)
	_drag_cost_label.visible = true

	_drag_energy_label.visible = false

	# ── Path line + dots ─────────────────────────────────────────────────────
	if not grid.is_in_bounds(hovered_tile) or _drag_from_building_tile == Vector2i(-1, -1):
		_drag_path_line.visible = false
		_drag_path_dst_marker.visible = false
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	var building_on_tile: String = grid.get_building(hovered_tile)
	var valid: bool
	if building_on_tile != "":
		var inst: BuildingRegistry.BuildingInstance = _registry.get_building_instance(building_on_tile)
		if inst != null and inst.assigned_container_id != &"":
			valid = inst.assigned_container_id != _drag_from_container_id
		else:
			var allowed: Array = BuildingRegistry.INPUT_RESOURCES.get(
				inst.type if inst != null else -1, [])
			valid = _drag_resource_id in allowed
	else:
		valid = grid.is_passable(hovered_tile)

	var path_color: Color = _PATH_COLOR_VALID if valid else _PATH_COLOR_INVALID
	var tile_px: float = float(WorldGrid.TILE_SIZE)
	var half: float = tile_px * 0.5
	var src_center: Vector2 = Vector2(_drag_from_building_tile) * tile_px + Vector2(half, half)
	var dst_center: Vector2 = Vector2(hovered_tile) * tile_px + Vector2(half, half)

	var path: Array[Vector2] = []
	path.append(src_center)
	var corner := Vector2(dst_center.x, src_center.y)
	if corner != src_center and corner != dst_center:
		path.append(corner)
	path.append(dst_center)

	_drag_path_line.clear_points()
	for pt: Vector2 in path:
		_drag_path_line.add_point(pt)
	_drag_path_line.default_color = path_color
	_drag_path_line.visible = true

	var dot_color: Color = path_color
	dot_color.a = 1.0
	_drag_path_dst_marker.position = dst_center
	_drag_path_dst_marker.modulate = dot_color
	_drag_path_dst_marker.visible = true

	var path_len: float = _path_length(path)
	if path_len < 1.0:
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	var spacing: float = path_len / float(_PATH_DOT_COUNT)
	var phase_wrapped: float = fmod(_drag_path_phase, path_len)
	for i in range(_PATH_DOT_COUNT):
		var dot: Sprite2D = _drag_path_dots[i]
		var t: float = fmod(phase_wrapped + float(i) * spacing, path_len)
		dot.position = _point_along_path(path, t)
		dot.modulate = dot_color
		dot.visible = true


## Called when the player presses LMB on an item in a building's storage grid.
## Removes 1 unit from the container and begins the drag.
func _on_storage_drag_started(resource_id: StringName, container_id: StringName, building_tile: Vector2i) -> void:
	if InventorySystem.try_consume(container_id, resource_id, 1) != InventoryContainer.ConsumeResult.SUCCESS:
		return

	var icon_px: int = roundi(WorldGrid.TILE_SIZE * _ICON_SCALE_BY_COUNT[0])
	var icon_node := Node2D.new()

	var backdrop := Sprite2D.new()
	backdrop.texture = _make_circle_texture(roundi(icon_px * 0.55), Color(0.0, 0.0, 0.0, 0.30))
	icon_node.add_child(backdrop)

	var icon_spr := Sprite2D.new()
	var idx: int = _resource_id_to_index(resource_id)
	icon_spr.texture = _load_resource_texture(maxi(idx, 0))
	var tex_size: Vector2 = icon_spr.texture.get_size()
	icon_spr.scale = Vector2(float(icon_px) / tex_size.x, float(icon_px) / tex_size.y)
	icon_node.add_child(icon_spr)

	icon_node.z_index = 20
	icon_node.modulate.a = 0.85
	icon_node.position = get_global_mouse_position()
	add_child(icon_node)

	_drag_icon = icon_node
	_drag_icon_entry = {}
	_drag_from_container_id = container_id
	_drag_resource_id = resource_id
	_drag_from_building_tile = building_tile
	_drag_src_tile = Vector2i(-1, -1)
	_drag_path_phase = 0.0


## Begins a drag of a resource out of a building's input buffer.
func _on_input_drag_started(resource_id: StringName, building_id: String, building_tile: Vector2i) -> void:
	if not _registry.remove_from_input(building_id, resource_id, 1):
		return
	var icon_px: int = roundi(WorldGrid.TILE_SIZE * _ICON_SCALE_BY_COUNT[0])
	var icon_node := Node2D.new()
	var backdrop := Sprite2D.new()
	backdrop.texture = _make_circle_texture(roundi(icon_px * 0.55), Color(0.0, 0.0, 0.0, 0.30))
	icon_node.add_child(backdrop)
	var icon_spr := Sprite2D.new()
	var idx: int = _resource_id_to_index(resource_id)
	icon_spr.texture = _load_resource_texture(maxi(idx, 0))
	var tex_size: Vector2 = icon_spr.texture.get_size()
	icon_spr.scale = Vector2(float(icon_px) / tex_size.x, float(icon_px) / tex_size.y)
	icon_node.add_child(icon_spr)
	icon_node.z_index = 20
	icon_node.modulate.a = 0.85
	icon_node.position = get_global_mouse_position()
	add_child(icon_node)
	_drag_icon = icon_node
	_drag_icon_entry = {}
	_drag_from_container_id = &""
	_drag_resource_id = resource_id
	_drag_from_building_tile = building_tile
	_drag_from_input_building_id = building_id
	_drag_src_tile = Vector2i(-1, -1)
	_drag_path_phase = 0.0


## Begins a drag of a resource out of a building's output buffer.
func _on_output_drag_started(resource_id: StringName, building_id: String, building_tile: Vector2i) -> void:
	if not _registry.remove_from_output(building_id, resource_id, 1):
		return
	var icon_px: int = roundi(WorldGrid.TILE_SIZE * _ICON_SCALE_BY_COUNT[0])
	var icon_node := Node2D.new()
	var backdrop := Sprite2D.new()
	backdrop.texture = _make_circle_texture(roundi(icon_px * 0.55), Color(0.0, 0.0, 0.0, 0.30))
	icon_node.add_child(backdrop)
	var icon_spr := Sprite2D.new()
	var idx: int = _resource_id_to_index(resource_id)
	icon_spr.texture = _load_resource_texture(maxi(idx, 0))
	var tex_size: Vector2 = icon_spr.texture.get_size()
	icon_spr.scale = Vector2(float(icon_px) / tex_size.x, float(icon_px) / tex_size.y)
	icon_node.add_child(icon_spr)
	icon_node.z_index = 20
	icon_node.modulate.a = 0.85
	icon_node.position = get_global_mouse_position()
	add_child(icon_node)
	_drag_icon = icon_node
	_drag_icon_entry = {}
	_drag_from_container_id = &""
	_drag_resource_id = resource_id
	_drag_from_building_tile = building_tile
	_drag_from_output_building_id = building_id
	_drag_src_tile = Vector2i(-1, -1)
	_drag_path_phase = 0.0


## Resolves an output-buffer drag on LMB release.
## Drops on passable tile → places resource badge. Drops on storage → deposits.
## Otherwise → returns to output buffer.
func _finish_output_drag() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = grid.world_to_tile(world_pos)
	var res_id: StringName = _drag_resource_id
	var building_id: String = _drag_from_output_building_id
	var from_tile: Vector2i = _drag_from_building_tile
	var icon_node: Node2D = _drag_icon
	_drag_icon = null
	_drag_from_output_building_id = ""
	_drag_resource_id = &""
	_drag_from_building_tile = Vector2i(-1, -1)
	_drag_src_tile = Vector2i(-1, -1)
	if grid.is_in_bounds(target_tile):
		var target_building_id: String = grid.get_building(target_tile)
		if target_building_id != "":
			var inst: BuildingRegistry.BuildingInstance = _registry.get_building_instance(target_building_id)
			if inst != null and inst.assigned_container_id != &"":
				if InventorySystem.get_occupied_slots(inst.assigned_container_id) < InventorySystem.get_capacity(inst.assigned_container_id):
					var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
					var target_cid: StringName = inst.assigned_container_id
					_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
						if InventorySystem.try_deposit(target_cid, res_id, 1) != InventoryContainer.DepositResult.SUCCESS:
							_registry.receive_output_to_buffer(building_id, res_id, 1)
						icon_node.queue_free()
					)
					get_viewport().set_input_as_handled()
					return
		elif grid.is_passable(target_tile):
			var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
			_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
				if grid.add_resource_to_tile(target_tile, res_id, true):
					_spawn_badge(target_tile, [res_id], self, 0.0, true, Time.get_ticks_msec())
				else:
					_registry.receive_output_to_buffer(building_id, res_id, 1)
				icon_node.queue_free()
			)
			get_viewport().set_input_as_handled()
			return
	icon_node.queue_free()
	_registry.receive_output_to_buffer(building_id, res_id, 1)
	get_viewport().set_input_as_handled()


## Resolves an input-buffer drag on LMB release.
## Drops on passable tile → places resource badge. Otherwise → returns to input buffer.
func _finish_input_drag() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = grid.world_to_tile(world_pos)
	var res_id: StringName = _drag_resource_id
	var building_id: String = _drag_from_input_building_id
	var from_tile: Vector2i = _drag_from_building_tile
	var icon_node: Node2D = _drag_icon
	_drag_icon = null
	_drag_from_input_building_id = ""
	_drag_resource_id = &""
	_drag_from_building_tile = Vector2i(-1, -1)
	_drag_src_tile = Vector2i(-1, -1)
	if grid.is_in_bounds(target_tile) and grid.is_passable(target_tile):
		var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
		_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
			if grid.add_resource_to_tile(target_tile, res_id, true):
				_spawn_badge(target_tile, [res_id], self, 0.0, true, Time.get_ticks_msec())
			else:
				_registry.receive_input_from_world(building_id, res_id, 1)
			icon_node.queue_free()
		)
	else:
		icon_node.queue_free()
		_registry.receive_input_from_world(building_id, res_id, 1)
	get_viewport().set_input_as_handled()


## Resolves a storage drag on LMB release.
## Drops on valid tile → places resource. Invalid → returns to source container.
func _finish_storage_drag() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = grid.world_to_tile(world_pos)
	var res_id: StringName = _drag_resource_id
	var container_id: StringName = _drag_from_container_id
	var from_tile: Vector2i = _drag_from_building_tile
	var icon_node: Node2D = _drag_icon
	_drag_icon = null
	_drag_from_container_id = &""
	_drag_resource_id = &""
	_drag_from_building_tile = Vector2i(-1, -1)
	_drag_src_tile = Vector2i(-1, -1)

	if grid.is_in_bounds(target_tile):
		var building_id: String = grid.get_building(target_tile)
		if building_id != "":
			var inst: BuildingRegistry.BuildingInstance = _registry.get_building_instance(building_id)
			var target_cid: StringName = inst.assigned_container_id if inst != null else &""
			if target_cid != &"" and target_cid != container_id \
					and InventorySystem.get_occupied_slots(target_cid) < InventorySystem.get_capacity(target_cid):
				var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
				_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
					if InventorySystem.try_deposit(target_cid, res_id, 1) != InventoryContainer.DepositResult.SUCCESS:
						InventorySystem.try_deposit(container_id, res_id, 1)
					icon_node.queue_free()
				)
				get_viewport().set_input_as_handled()
				return
			elif target_cid == &"":
				# Production building — route to input_buffer.
				var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
				_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
					if not _registry.receive_input_from_world(building_id, res_id, 1):
						InventorySystem.try_deposit(container_id, res_id, 1)
					icon_node.queue_free()
				)
				get_viewport().set_input_as_handled()
				return
			# Same container or would-be-full — fall through to return resource
		elif grid.is_passable(target_tile):
			var ticks_needed: int = _calc_drag_ticks(from_tile, target_tile, res_id)
			_park_panel_icon_pending(icon_node, from_tile, target_tile, ticks_needed, func() -> void:
				if grid.add_resource_to_tile(target_tile, res_id, true):
					_spawn_badge(target_tile, [res_id], self, 0.0, true, Time.get_ticks_msec())
				else:
					InventorySystem.try_deposit(container_id, res_id, 1)
				icon_node.queue_free()
			)
			get_viewport().set_input_as_handled()
			return

	icon_node.queue_free()
	InventorySystem.try_deposit(container_id, res_id, 1)
	get_viewport().set_input_as_handled()


## Applies tick cost for a successful building-panel drag.
func _pay_drag_cost(from_tile: Vector2i, to_tile: Vector2i, _res_id: StringName) -> void:
	var dist: int = abs(to_tile.x - from_tile.x) + abs(to_tile.y - from_tile.y)
	var base_cost: int = maxi(1, dist)
	TickSystem.advance_ticks_manual(base_cost * 5)


## Returns the tick duration for a building-panel drag from from_tile to to_tile.
## Does NOT advance ticks (caller starts pending transport).
func _calc_drag_ticks(from_tile: Vector2i, to_tile: Vector2i, _res_id: StringName) -> int:
	var dist: int = abs(to_tile.x - from_tile.x) + abs(to_tile.y - from_tile.y)
	var base_cost: int = maxi(1, dist)
	return base_cost * 5


## Parks a building-panel drag icon at the target tile and registers a pending transport.
## The icon stays at target_tile with a progress circle until ticks_needed elapse,
## then on_complete is called (responsible for the actual data change and icon.queue_free).
func _park_panel_icon_pending(icon: Node2D, from_tile: Vector2i, target_tile: Vector2i,
		ticks_needed: int, on_complete: Callable) -> void:
	var tile_px: int = WorldGrid.TILE_SIZE
	icon.position = Vector2(target_tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	icon.modulate.a = 1.0
	icon.scale = Vector2(1.0, 1.0)
	icon.z_index = 2
	var indicator: BuildingStatusIndicator = _spawn_transport_indicator(target_tile)
	var path_overlay: Dictionary = _spawn_pending_path_overlay(from_tile, target_tile)
	if _pending_transports.is_empty() and _action_indicator == null:
		_was_paused_before_action = TickSystem.is_paused()
	_pending_transports.append({
		"icon": icon, "icon_entry": {}, "source_tile": from_tile,
		"target_tile": target_tile,
		"ticks_total": ticks_needed, "ticks_elapsed": 0,
		"indicator": indicator,
		"path_overlay": path_overlay, "path_phase": 0.0,
		"on_complete": on_complete,
	})
	TickSystem.set_pause(false)


func _setup_map_select_highlight() -> void:
	_map_select_highlight = Sprite2D.new()
	_map_select_highlight.texture = _make_tile_highlight_texture()
	_map_select_highlight.visible = false
	_map_select_highlight.z_index = 4
	add_child(_map_select_highlight)


func _make_tile_highlight_texture() -> ImageTexture:
	var size: int = WorldGrid.TILE_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var fill := Color(0.29, 0.49, 0.66, 0.22)
	var border := Color(0.29, 0.49, 0.66, 0.85)
	for x: int in range(size):
		for y: int in range(size):
			img.set_pixel(x, y, border if (x < 2 or x >= size - 2 or y < 2 or y >= size - 2) else fill)
	return ImageTexture.create_from_image(img)


func _update_map_select_highlight() -> void:
	if _hud == null or not _hud.is_map_select_active():
		_map_select_highlight.visible = false
		return
	var world_pos: Vector2 = get_global_mouse_position()
	var tile: Vector2i = terrain_layer.local_to_map(terrain_layer.to_local(world_pos))
	if tile.x < 0 or tile.y < 0 or tile.x >= WorldGrid.GRID_SIZE or tile.y >= WorldGrid.GRID_SIZE:
		_map_select_highlight.visible = false
		return
	var building_id: String = grid.get_building(tile)
	if building_id == "":
		_map_select_highlight.visible = false
		return
	var tile_px: int = WorldGrid.TILE_SIZE
	_map_select_highlight.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	_map_select_highlight.visible = true


## Wires BuildingDetailPanel.storage_drag_started to this scene.
func _wire_building_detail() -> void:
	var hud: HUD = get_tree().get_first_node_in_group(&"hud") as HUD
	_hud = hud
	if hud == null:
		push_warning("[MapRoot] HUD not found — storage drag not wired")
		return
	var panel: BuildingDetailPanel = hud.get_node_or_null("BuildingDetailPanel") as BuildingDetailPanel
	if panel == null:
		push_warning("[MapRoot] BuildingDetailPanel not found in HUD — storage drag not wired")
		return
	panel.storage_drag_started.connect(_on_storage_drag_started)
	panel.input_drag_started.connect(_on_input_drag_started)
	panel.output_drag_started.connect(_on_output_drag_started)


func _path_length(path: Array[Vector2]) -> float:
	var total: float = 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total


func _point_along_path(path: Array[Vector2], t: float) -> Vector2:
	var remaining: float = t
	for i in range(path.size() - 1):
		var seg_len: float = path[i].distance_to(path[i + 1])
		if remaining <= seg_len or i == path.size() - 2:
			return path[i].lerp(path[i + 1], clampf(remaining / seg_len, 0.0, 1.0))
		remaining -= seg_len
	return path[path.size() - 1]


## Returns an ImageTexture of a solid filled circle with the given radius and color.
func _make_circle_texture(radius: int, color: Color) -> ImageTexture:
	var size: int = radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for px in range(size):
		for py in range(size):
			var dx: int = px - radius
			var dy: int = py - radius
			if dx * dx + dy * dy <= radius * radius:
				img.set_pixel(px, py, color)
	return ImageTexture.create_from_image(img)


## Loads the icon PNG for a resource index. Falls back to a colored circle if the asset is missing.
func _load_resource_texture(idx: int) -> Texture2D:
	var path: String = _RESOURCE_PNG[idx]
	if path != "" and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	var radius: int = roundi(WorldGrid.TILE_SIZE * _RESOURCE_ICON_SCALE) / 2
	return _make_circle_texture(radius, _RESOURCE_FALLBACK_COLORS[idx])


## Maps resource_id to _RESOURCE_PNG index. Returns -1 for unknown IDs.
func _resource_id_to_index(resource_id: StringName) -> int:
	match resource_id:
		&"wood":  return 0
		&"stone": return 1
		&"berry": return 2
		&"fiber": return 3
		&"tool":  return 4
		_: return -1


# ── Tile interaction input ────────────────────────────────────────────────────

## Catches LMB release during a storage drag regardless of UI layering.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _drag_from_output_building_id != "":
		_finish_output_drag()
	elif _drag_from_input_building_id != "":
		_finish_input_drag()
	elif _drag_from_container_id != &"":
		_finish_storage_drag()


## Handles mouse input for both right-click tile interaction and LMB resource drag.
## Consumes the event so UI layers above are not re-notified.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton

	# ── Right-click: tile interaction panel ──────────────────────────────────
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var world_pos: Vector2 = get_global_mouse_position()
		var tile: Vector2i = terrain_layer.local_to_map(terrain_layer.to_local(world_pos))
		if tile.x < 0 or tile.y < 0 or tile.x >= WorldGrid.GRID_SIZE or tile.y >= WorldGrid.GRID_SIZE:
			return
		_on_tile_clicked(tile, get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
		return

	# ── LMB press: begin resource relocation drag or open building detail ────
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		var world_pos: Vector2 = get_global_mouse_position()

		# In map-select mode all other clicks are blocked; route to HUD.
		if _hud != null and _hud.is_map_select_active():
			var sel_tile: Vector2i = terrain_layer.local_to_map(terrain_layer.to_local(world_pos))
			var sel_building: String = ""
			if sel_tile.x >= 0 and sel_tile.y >= 0 and sel_tile.x < WorldGrid.GRID_SIZE and sel_tile.y < WorldGrid.GRID_SIZE:
				sel_building = grid.get_building(sel_tile)
			_hud.notify_building_selected_in_map_select(StringName(sel_building))
			get_viewport().set_input_as_handled()
			return

		var hit := _hit_test_resource_icon(world_pos)
		if hit.is_empty():
			# No resource icon hit — check if tile has a building.
			var click_tile: Vector2i = terrain_layer.local_to_map(terrain_layer.to_local(world_pos))
			if (click_tile.x >= 0 and click_tile.y >= 0
					and click_tile.x < WorldGrid.GRID_SIZE and click_tile.y < WorldGrid.GRID_SIZE):
				var building_id: String = grid.get_building(click_tile)
				if building_id != "":
					if _hud != null:
						_hud.open_building_detail(building_id)
						get_viewport().set_input_as_handled()
						return
			return
		var icon_node: Node2D = hit.node as Node2D
		var res_tile: Vector2i = hit.tile
		var res_idx: int = hit.resource_idx
		var res_id: StringName = hit.resource_id
		if not _player.try_start_relocation(res_tile, res_idx, res_id):
			return
		_drag_icon = icon_node
		_drag_icon_entry = hit
		_drag_src_tile = res_tile
		_drag_path_phase = 0.0
		_drag_hold_timer = 0.0
		_drag_collected_count = 1
		icon_node.modulate.a = 0.7
		icon_node.scale = Vector2(1.2, 1.2)
		icon_node.z_index = 10
		get_viewport().set_input_as_handled()
		return

	# ── LMB release: commit or cancel drag ───────────────────────────────────
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		if _drag_icon == null:
			return
		var world_pos: Vector2 = get_global_mouse_position()
		var target_tile: Vector2i = terrain_layer.local_to_map(terrain_layer.to_local(world_pos))

		# If the target tile has a storage building, deposit instead of relocate.
		var building_id: String = grid.get_building(target_tile)
		if building_id != "":
			_try_deposit_to_building(target_tile, building_id)
			get_viewport().set_input_as_handled()
			return

		var result: int = _player.try_commit_relocation(target_tile, grid, true)
		match result:
			PlayerCharacter.RelocationResult.SUCCESS:
				var src_tile: Vector2i = _drag_icon_entry.tile
				var src_idx: int = _drag_icon_entry.resource_idx
				var move_dist: int = abs(target_tile.x - src_tile.x) + abs(target_tile.y - src_tile.y)
				var ticks_needed: int = maxi(1, move_dist) * 5
				# Remove resource from grid immediately so it is in transit.
				grid.remove_one_resource(src_tile, src_idx)
				for entry: Dictionary in _resource_icons:
					if entry.tile == src_tile and entry.resource_idx > src_idx:
						entry.resource_idx -= 1
				# Park icon at source; mark in-transit so it cannot be re-dragged.
				_drag_icon_entry.in_transit = true
				_drag_icon.position = _drag_icon_entry.base_pos
				_reset_drag_icon_visuals(_drag_icon)
				var indicator: BuildingStatusIndicator = _spawn_transport_indicator(src_tile)
				var path_overlay: Dictionary = _spawn_pending_path_overlay(src_tile, target_tile)
				var c_icon: Node2D = _drag_icon
				var c_entry: Dictionary = _drag_icon_entry
				var c_src_tile: Vector2i = src_tile
				var c_target_tile: Vector2i = target_tile
				var c_res_id: StringName = _drag_icon_entry.resource_id
				var c_tile_px: int = WorldGrid.TILE_SIZE
				# All batch extras are transported (no energy gate).
				var c_total_items: int = _drag_collected_count
				if _pending_transports.is_empty() and _action_indicator == null:
					_was_paused_before_action = TickSystem.is_paused()
				_pending_transports.append({
					"icon": c_icon,
					"icon_entry": c_entry,
					"source_tile": src_tile,
					"target_tile": c_target_tile,
					"ticks_total": ticks_needed * c_total_items,
					"ticks_elapsed": 0,
					"indicator": indicator,
					"path_overlay": path_overlay,
					"path_phase": 0.0,
					"on_complete": func() -> void:
						var size_before: int = grid.get_resources(c_target_tile).size()
						var placed_count: int = 0
						for _pi in range(c_total_items):
							if grid.add_resource_to_tile(c_target_tile, c_res_id, true):
								placed_count += 1
							else:
								break
						var new_base: Vector2 = (Vector2(c_target_tile) * float(c_tile_px)
							+ Vector2(c_tile_px, c_tile_px) * 0.5)
						# First item — update the dragged icon entry.
						if placed_count >= 1:
							c_entry.tile = c_target_tile
							c_entry.resource_idx = size_before
							var c_scatter: Array = _random_icon_positions(c_target_tile, 1,
								roundi(float(c_tile_px) * _ICON_SCALE_BY_COUNT[0]),
								Time.get_ticks_msec())
							c_entry.base_pos = new_base + c_scatter[0]
							c_icon.position = c_entry.base_pos
							c_entry.in_transit = false
						else:
							if grid.add_resource_to_tile(c_src_tile, c_res_id, true):
								c_entry.tile = c_src_tile
								c_entry.resource_idx = grid.get_resources(c_src_tile).size() - 1
								c_entry.in_transit = false
							else:
								_resource_icons.erase(c_entry)
								c_icon.queue_free()
						# Extra items that reached target — spawn new badges.
						for pi in range(1, placed_count):
							var ids_e: Array[StringName] = [c_res_id]
							_spawn_badge(c_target_tile, ids_e, self, 0.0, false,
								Time.get_ticks_msec() + pi * 31)
							_resource_icons.back().resource_idx = size_before + pi
						# Extra items that couldn't be placed — restore to source.
						var failed_extras: int = c_total_items - maxi(placed_count, 1)
						var seed_off: int = Time.get_ticks_msec()
						for ri in range(failed_extras):
							if grid.add_resource_to_tile(c_src_tile, c_res_id, true):
								var ids_r: Array[StringName] = [c_res_id]
								_spawn_badge(c_src_tile, ids_r, self, 0.0, true, seed_off + ri * 41)
								_resource_icons.back().resource_idx = grid.get_resources(c_src_tile).size() - 1
				})
				TickSystem.set_pause(false)
			PlayerCharacter.RelocationResult.SNAP_BACK_SAME_TILE:
				_snap_back_drag_icon()
			_:
				# All SNAP_BACK_* and NOT_DRAGGING cases.
				_snap_back_drag_icon()
		_drag_icon = null
		_drag_icon_entry = {}
		_drag_src_tile = Vector2i(-1, -1)
		get_viewport().set_input_as_handled()


## Hit-tests _resource_icons against a world position.
## Returns a Dictionary with node/tile/resource_idx/resource_id, or empty if no hit.
func _hit_test_resource_icon(world_pos: Vector2) -> Dictionary:
	var tile_pos: Vector2i = terrain_layer.local_to_map(terrain_layer.to_local(world_pos))
	var tap_radius: float = WorldGrid.TILE_SIZE * 0.5
	var best_dist: float = tap_radius
	var best: Dictionary = {}
	for entry: Dictionary in _resource_icons:
		if entry.tile != tile_pos:
			continue
		if entry.get("in_transit", false):
			continue
		var icon_node: Node2D = entry.node as Node2D
		var dist: float = icon_node.global_position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = entry
	return best


func _cancel_drag_visual() -> void:
	if _drag_icon == null:
		return
	_snap_back_drag_icon()
	_drag_icon = null
	_drag_icon_entry = {}
	_drag_src_tile = Vector2i(-1, -1)


func _snap_back_drag_icon() -> void:
	if _drag_icon == null:
		return
	_restore_batch_extras()
	var icon_node: Node2D = _drag_icon
	var tween := create_tween()
	tween.tween_property(icon_node, "position", _drag_icon_entry.base_pos, 0.18).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void: _reset_drag_icon_visuals(icon_node))


func _reset_drag_icon_visuals(icon_node: Node2D) -> void:
	icon_node.modulate.a = 1.0
	icon_node.scale = Vector2(1.0, 1.0)
	icon_node.z_index = 2


## During a world drag, auto-collects one additional matching resource from the source tile.
## Called from _process on a timer while LMB is held. The collected icon flies to the cursor
## and is freed; the grid resource is removed immediately (items restored on snap-back).
func _try_batch_collect() -> void:
	if _drag_icon == null or _drag_src_tile == Vector2i(-1, -1):
		return
	var res_id: StringName = _drag_icon_entry.resource_id
	var src_tile: Vector2i = _drag_src_tile
	var target_entry: Dictionary = {}
	for entry: Dictionary in _resource_icons:
		if entry.get("node") == _drag_icon_entry.get("node"):
			continue  # skip the icon currently being dragged
		if entry.tile != src_tile:
			continue
		if entry.resource_id != res_id:
			continue
		if entry.get("in_transit", false):
			continue
		target_entry = entry
		break
	if target_entry.is_empty():
		return
	var icon_node: Node2D = target_entry.node as Node2D
	var res_idx: int = target_entry.resource_idx
	grid.remove_one_resource(src_tile, res_idx)
	for other: Dictionary in _resource_icons:
		if other.tile == src_tile and other.resource_idx > res_idx:
			other.resource_idx -= 1
	target_entry.in_transit = true
	var cursor_pos: Vector2 = _drag_icon.global_position
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(icon_node, "global_position", cursor_pos, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(icon_node, "modulate:a", 0.0, 0.18)
	tween.tween_property(icon_node, "scale", Vector2(0.4, 0.4), 0.22)
	var cap_entry: Dictionary = target_entry
	var cap_node: Node2D = icon_node
	tween.chain().tween_callback(func() -> void:
		_resource_icons.erase(cap_entry)
		cap_node.queue_free()
	)
	_drag_collected_count += 1
	_drag_count_label.text = "×%d" % _drag_collected_count
	_drag_count_label.visible = true


## Restores any batch-collected extras to the source tile when a drag is cancelled/snapped back.
## Resets batch state. Called from _snap_back_drag_icon before the snap animation begins.
func _restore_batch_extras() -> void:
	var extra_count: int = _drag_collected_count - 1
	_drag_collected_count = 1
	_drag_hold_timer = 0.0
	if extra_count <= 0 or _drag_src_tile == Vector2i(-1, -1) or _drag_icon_entry.is_empty():
		return
	var res_id: StringName = _drag_icon_entry.resource_id
	for i in range(extra_count):
		if grid.add_resource_to_tile(_drag_src_tile, res_id, true):
			var ids_r: Array[StringName] = [res_id]
			_spawn_badge(_drag_src_tile, ids_r, self, 0.0, true, Time.get_ticks_msec() + i * 37)
			_resource_icons.back().resource_idx = grid.get_resources(_drag_src_tile).size() - 1


## Creates a standalone resource icon Node2D at the tile's centre without registering it
## in _resource_icons. Used for batch transport visual proxies.
func _make_resource_icon_node(tile: Vector2i, res_id: StringName) -> Node2D:
	var tile_px: int = WorldGrid.TILE_SIZE
	var icon_px: int = roundi(float(tile_px) * _ICON_SCALE_BY_COUNT[0])
	var icon_node := Node2D.new()
	icon_node.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	icon_node.z_index = 2
	var backdrop := Sprite2D.new()
	backdrop.texture = _make_circle_texture(roundi(icon_px * 0.55), Color(0.0, 0.0, 0.0, 0.30))
	icon_node.add_child(backdrop)
	var spr := Sprite2D.new()
	spr.texture = _load_resource_texture(_resource_id_to_index(res_id))
	var tex_size: Vector2 = spr.texture.get_size()
	spr.scale = Vector2(float(icon_px) / tex_size.x, float(icon_px) / tex_size.y)
	icon_node.add_child(spr)
	add_child(icon_node)
	return icon_node


## Handles a confirmed left-click on a valid grid tile.
## Maps terrain type to ManualActionType and opens the Tile Interaction Panel.
func _on_tile_clicked(tile: Vector2i, screen_pos: Vector2) -> void:
	if grid.get_building(tile) != "" or PathSystem.has_path(tile):
		return
	var terrain: WorldGrid.TileType = grid.get_terrain(tile)
	var action_type: int = _terrain_to_action(terrain)
	if action_type < 0:
		return
	_last_action_tile = tile
	_interaction_panel.show_at(screen_pos, action_type)


## Handles a world-area click emitted by the panel's ClickGuard.
## Any click outside the panel closes it — the user can right-click again to open a new one.
func _on_panel_world_click(_screen_pos: Vector2) -> void:
	_interaction_panel.close()


## Unpauses the tick system and spawns a progress circle at the harvested tile.
func _on_action_started(_action_id: int, _tick_cost: int) -> void:
	_active_action_tile = _last_action_tile
	if _pending_transports.is_empty() and _action_indicator == null:
		_was_paused_before_action = TickSystem.is_paused()
	TickSystem.set_pause(false)
	_spawn_action_indicator(_active_action_tile)


func _spawn_action_indicator(tile: Vector2i) -> void:
	if _action_indicator != null:
		_action_indicator.queue_free()
		_action_indicator = null
	var tile_px: int = WorldGrid.TILE_SIZE
	var indicator := BuildingStatusIndicator.new()
	indicator.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5 \
		+ Vector2(tile_px * 0.32, tile_px * 0.32)
	indicator.z_index = 3
	add_child(indicator)
	_action_indicator = indicator


func _on_action_progress_update(progress: float, _tick_cost: int, _output: int) -> void:
	if _action_indicator != null:
		_action_indicator.set_progress(progress)


## Spawns floating text and a loot-icon badge on the harvested tile.
## For CLEAR_* actions: removes terrain, clears all resource icons, then spawns loot.
func _on_action_completed(action_id: int, output: Array) -> void:
	if _pending_transports.is_empty():
		TickSystem.set_pause(_was_paused_before_action)
	if _action_indicator != null:
		_action_indicator.queue_free()
		_action_indicator = null
	if _active_action_tile == Vector2i(-1, -1):
		return

	var is_clear: bool = action_id in [
		PlayerCharacter.ManualActionType.CLEAR_TREE,
		PlayerCharacter.ManualActionType.CLEAR_STONE,
		PlayerCharacter.ManualActionType.CLEAR_BERRY,
		PlayerCharacter.ManualActionType.CLEAR_GRASS,
	]

	if is_clear:
		var tile := _active_action_tile
		var to_remove: Array = []
		for entry: Dictionary in _resource_icons:
			if entry.tile == tile:
				(entry.node as Node2D).queue_free()
				to_remove.append(entry)
		for entry: Dictionary in to_remove:
			_resource_icons.erase(entry)
		grid.clear_terrain_tile(tile)
		terrain_layer.set_cell(tile, -1, Vector2i(-1, -1))
		var world_pos: Vector2 = grid.tile_to_world(tile)
		for item: Dictionary in output:
			var qty: int = item.get("quantity", 0)
			var resource_id: StringName = item.get("resource_id", &"")
			if qty <= 0 or resource_id == &"" or _resource_id_to_index(resource_id) < 0:
				continue
			_spawn_pickup_float(world_pos, "+%d %s" % [qty, str(resource_id)])
			var ids: Array[StringName] = []
			for _i in range(qty):
				grid.add_resource_to_tile(tile, resource_id, true)
				ids.append(resource_id)
			_spawn_badge(tile, ids, self, 0.0, true, Time.get_ticks_msec())
		return

	var world_pos: Vector2 = grid.tile_to_world(_active_action_tile)
	for item: Dictionary in output:
		var qty: int = item.get("quantity", 0)
		var resource_id: StringName = item.get("resource_id", &"")
		if qty <= 0 or resource_id == &"" or _resource_id_to_index(resource_id) < 0:
			continue
		_spawn_pickup_float(world_pos, "+%d %s" % [qty, str(resource_id)])
		var existing_count: int = grid.get_resources(_active_action_tile).size()
		var ids: Array[StringName] = []
		for _i in range(qty):
			grid.add_resource_to_tile(_active_action_tile, resource_id, true)
			ids.append(resource_id)
		var prev_len: int = _resource_icons.size()
		_spawn_badge(_active_action_tile, ids, self, 0.0, true, Time.get_ticks_msec())
		for j in range(prev_len, _resource_icons.size()):
			_resource_icons[j].resource_idx = existing_count + (j - prev_len)


func _spawn_pickup_float(world_pos: Vector2, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = world_pos + Vector2(-32.0, -48.0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.94, 0.93, 0.9, 1))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 52.0, 1.4)
	tween.tween_property(label, "modulate:a", 0.0, 1.4)
	tween.finished.connect(label.queue_free)


## Attempts to deposit the currently-dragged resource (and any batch extras) into a building.
## Pays energy per item. Restores unpayable extras to the source tile immediately.
func _try_deposit_to_building(target_tile: Vector2i, building_id: String) -> void:
	var instance: Object = _registry.get_building_instance(building_id)
	var container_id: StringName = instance.assigned_container_id if instance != null else &""
	var src_tile: Vector2i = _drag_icon_entry.tile
	var src_idx: int = _drag_icon_entry.resource_idx
	var res_id: StringName = _drag_icon_entry.resource_id
	var dist: int = abs(target_tile.x - src_tile.x) + abs(target_tile.y - src_tile.y)
	var cost: int = maxi(1, dist)

	if container_id == &"":
		# Production building — route to input_buffer.
		var allowed: Array = BuildingRegistry.INPUT_RESOURCES.get(
			instance.type if instance != null else -1, [])
		if not res_id in allowed:
			_player.cancel_relocation()
			_snap_back_drag_icon()
			_drag_icon = null
			_drag_icon_entry = {}
			_drag_src_tile = Vector2i(-1, -1)
			return
		# All batch extras are transported (no energy gate).
		var cp_total: int = _drag_collected_count
		_drag_collected_count = 1
		if _pending_transports.is_empty() and _action_indicator == null:
			_was_paused_before_action = TickSystem.is_paused()
		# Remove main item from grid and start pending transport.
		grid.remove_one_resource(src_tile, src_idx)
		for entry: Dictionary in _resource_icons:
			if entry.tile == src_tile and entry.resource_idx > src_idx:
				entry.resource_idx -= 1
		_drag_icon_entry.in_transit = true
		_drag_icon.position = _drag_icon_entry.base_pos
		_reset_drag_icon_visuals(_drag_icon)
		var indicator_prod: BuildingStatusIndicator = _spawn_transport_indicator(src_tile)
		var path_overlay_prod: Dictionary = _spawn_pending_path_overlay(src_tile, target_tile)
		var cp_icon: Node2D = _drag_icon
		var cp_entry: Dictionary = _drag_icon_entry
		var cp_bid: String = building_id
		var cp_res: StringName = res_id
		_pending_transports.append({
			"icon": cp_icon, "icon_entry": cp_entry, "source_tile": src_tile,
			"target_tile": target_tile,
			"ticks_total": cost * 5,
			"ticks_elapsed": 0, "indicator": indicator_prod,
			"path_overlay": path_overlay_prod, "path_phase": 0.0,
			"on_complete": func() -> void:
				_registry.receive_input_from_world(cp_bid, cp_res, cp_total)
				_resource_icons.erase(cp_entry)
				cp_icon.queue_free()
		})
		_player.cancel_relocation()
		_drag_icon = null
		_drag_icon_entry = {}
		_drag_src_tile = Vector2i(-1, -1)
		TickSystem.set_pause(false)
		return

	# Pre-check: container must have space for at least 1 item.
	if InventorySystem.get_occupied_slots(container_id) >= InventorySystem.get_capacity(container_id):
		_snap_back_drag_icon()
		_player.cancel_relocation()
		_drag_icon = null
		_drag_icon_entry = {}
		_drag_src_tile = Vector2i(-1, -1)
		return

	# All batch extras are transported (no energy gate).
	var cs_total: int = _drag_collected_count
	_drag_collected_count = 1
	if _pending_transports.is_empty() and _action_indicator == null:
		_was_paused_before_action = TickSystem.is_paused()
	# Remove main item from grid and start pending transport.
	grid.remove_one_resource(src_tile, src_idx)
	for entry: Dictionary in _resource_icons:
		if entry.tile == src_tile and entry.resource_idx > src_idx:
			entry.resource_idx -= 1
	_drag_icon_entry.in_transit = true
	_drag_icon.position = _drag_icon_entry.base_pos
	_reset_drag_icon_visuals(_drag_icon)
	var indicator_stor: BuildingStatusIndicator = _spawn_transport_indicator(src_tile)
	var path_overlay_stor: Dictionary = _spawn_pending_path_overlay(src_tile, target_tile)
	var cs_icon: Node2D = _drag_icon
	var cs_entry: Dictionary = _drag_icon_entry
	var cs_cid: StringName = container_id
	var cs_res: StringName = res_id
	var cs_src: Vector2i = src_tile
	_pending_transports.append({
		"icon": cs_icon, "icon_entry": cs_entry, "source_tile": src_tile,
		"target_tile": target_tile,
		"ticks_total": cost * 5,
		"ticks_elapsed": 0, "indicator": indicator_stor,
		"path_overlay": path_overlay_stor, "path_phase": 0.0,
		"on_complete": func() -> void:
			for _di in range(cs_total):
				var dep: int = InventorySystem.try_deposit(cs_cid, cs_res, 1)
				if dep != InventoryContainer.DepositResult.SUCCESS:
					# Container full during transit — put excess back on world grid.
					if grid.add_resource_to_tile(cs_src, cs_res, true):
						var ids_fb: Array[StringName] = [cs_res]
						_spawn_badge(cs_src, ids_fb, self, 0.0, true, Time.get_ticks_msec() + _di * 37)
						_resource_icons.back().resource_idx = grid.get_resources(cs_src).size() - 1
			_resource_icons.erase(cs_entry)
			cs_icon.queue_free()
	})
	_player.cancel_relocation()
	_drag_icon = null
	_drag_icon_entry = {}
	_drag_src_tile = Vector2i(-1, -1)
	TickSystem.set_pause(false)


## Spawns a Sprite2D for a newly placed path tile.
func _on_path_placed(tile: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(PathSystem.get_texture_path(tile))
	var tile_px: int = WorldGrid.TILE_SIZE
	sprite.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	sprite.z_index = 1
	add_child(sprite)
	_path_sprites[tile] = sprite


## Updates path sprite texture when neighbor connections change.
func _on_path_updated(tile: Vector2i) -> void:
	var sprite: Sprite2D = _path_sprites.get(tile)
	if sprite == null:
		return
	sprite.texture = load(PathSystem.get_texture_path(tile))


## Removes a path sprite when a path tile is demolished.
func _on_path_removed(tile: Vector2i) -> void:
	var sprite: Sprite2D = _path_sprites.get(tile)
	if sprite != null:
		sprite.queue_free()
		_path_sprites.erase(tile)


## Spawns the building visual sprite when BuildingRegistry confirms placement.
func _on_building_placed(building_id: String, type: int, tile: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(_building_texture_path(type))
	var tile_px: int = WorldGrid.TILE_SIZE
	sprite.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	sprite.z_index = 2

	var instance: BuildingRegistry.BuildingInstance = _registry.get_building_instance(building_id)
	if instance != null and instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
		sprite.modulate = _SKELETON_MODULATE
	_building_sprites[building_id] = sprite

	add_child(sprite)

	var build_time: int = BuildingRegistry.BUILD_TIME.get(type, 0)
	if build_time > 0 or BuildingRegistry.PRODUCTION_TABLE.has(type):
		var indicator := BuildingStatusIndicator.new()
		indicator.position = sprite.position + Vector2(tile_px * 0.32, tile_px * 0.32)
		indicator.z_index = 3
		add_child(indicator)
		_building_indicators[building_id] = indicator
		_refresh_indicator(building_id)

	PathSystem.update_neighbors(tile)


func _on_building_construction_complete(building_id: String, _type: int) -> void:
	var sprite: Sprite2D = _building_sprites.get(building_id)
	if sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_building_items_dropped(tile: Vector2i, items: Dictionary) -> void:
	var seed_base: int = Time.get_ticks_msec()
	var i: int = 0
	for res_id: StringName in items:
		var qty: int = items[res_id]
		for _j in range(qty):
			if grid.add_resource_to_tile(tile, res_id, true):
				_spawn_badge(tile, [res_id], self, 0.0, true, seed_base + i * 37)
			i += 1


func _on_building_demolished(building_id: StringName) -> void:
	var id: String = str(building_id)
	var sprite: Sprite2D = _building_sprites.get(id)
	if sprite != null:
		var tile_px: int = WorldGrid.TILE_SIZE
		var tile := Vector2i((sprite.position - Vector2(tile_px, tile_px) * 0.5) / tile_px)
		sprite.queue_free()
		_building_sprites.erase(id)
		PathSystem.update_neighbors(tile)
	var indicator: BuildingStatusIndicator = _building_indicators.get(id)
	if indicator != null:
		indicator.queue_free()
		_building_indicators.erase(id)


func _on_building_state_changed(building_id: String, _new_state: int, _reason: String) -> void:
	_refresh_indicator(building_id)


func _on_ticks_advanced_indicators(_delta: int) -> void:
	for building_id: String in _building_indicators:
		_refresh_indicator(building_id)
	_advance_pending_transports(_delta)


func _refresh_indicator(building_id: String) -> void:
	var indicator: BuildingStatusIndicator = _building_indicators.get(building_id)
	if indicator == null:
		return
	var instance: BuildingRegistry.BuildingInstance = _registry.get_building_instance(building_id)
	if instance == null:
		return

	if instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
		var progress: float = float(instance.accumulated_ticks) / float(instance.build_time) \
			if instance.build_time > 0 else 0.0
		indicator.set_construction_progress(progress)
		indicator.show()
		return

	if not BuildingRegistry.PRODUCTION_TABLE.has(instance.type):
		indicator.hide()
		return

	indicator.show()
	if instance.cycle_running:
		var duration: int = instance.production_cycle_duration
		indicator.set_progress(float(instance.production_cycle_ticks) / float(duration) \
			if duration > 0 else 1.0)
	elif _building_has_valid_input(instance):
		indicator.set_progress(0.0)
	else:
		indicator.set_idle()


## Advances all pending manual transports and completes any that have finished.
func _advance_pending_transports(delta: int) -> void:
	if _pending_transports.is_empty():
		return
	var completed: Array = []
	for pt: Dictionary in _pending_transports:
		pt.ticks_elapsed += delta
		var progress: float = minf(float(pt.ticks_elapsed) / float(pt.ticks_total), 1.0)
		if is_instance_valid(pt.indicator):
			pt.indicator.set_progress(progress)
		if pt.ticks_elapsed >= pt.ticks_total:
			completed.append(pt)
	for pt: Dictionary in completed:
		_pending_transports.erase(pt)
		if is_instance_valid(pt.indicator):
			pt.indicator.queue_free()
		_free_pending_path_overlay(pt.get("path_overlay", {}))
		var icon_entry: Dictionary = pt.get("icon_entry", {})
		if not icon_entry.is_empty() and pt.has("target_tile"):
			# World drag: tween icon from source to destination, then commit.
			var icon: Node2D = pt.icon
			var tile_px: int = WorldGrid.TILE_SIZE
			var to_tile: Vector2i = pt.target_tile
			var new_pos: Vector2 = Vector2(to_tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
			var tween: Tween = create_tween()
			tween.tween_property(icon, "position", new_pos, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_callback(pt.on_complete)
		else:
			pt.on_complete.call()
	if _pending_transports.is_empty() and _action_indicator == null:
		TickSystem.set_pause(_was_paused_before_action)


## Spawns a progress circle indicator at the given tile for a pending transport.
func _spawn_transport_indicator(tile: Vector2i) -> BuildingStatusIndicator:
	var tile_px: int = WorldGrid.TILE_SIZE
	var indicator := BuildingStatusIndicator.new()
	indicator.position = (Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
		+ Vector2(tile_px * 0.32, tile_px * 0.32))
	indicator.z_index = 15
	add_child(indicator)
	indicator.set_progress(0.0)
	return indicator


## Spawns a persistent path line + animated dots for a pending transport.
## Returns a Dictionary with line, dots, dst_marker, path_points, path_len.
func _spawn_pending_path_overlay(from_tile: Vector2i, to_tile: Vector2i) -> Dictionary:
	var tile_px: float = float(WorldGrid.TILE_SIZE)
	var half: float = tile_px * 0.5
	var src_center: Vector2 = Vector2(from_tile) * tile_px + Vector2(half, half)
	var dst_center: Vector2 = Vector2(to_tile) * tile_px + Vector2(half, half)
	var path: Array[Vector2] = []
	path.append(src_center)
	var corner := Vector2(dst_center.x, src_center.y)
	if corner != src_center and corner != dst_center:
		path.append(corner)
	path.append(dst_center)
	var path_len: float = _path_length(path)
	var line := Line2D.new()
	line.width = _PATH_LINE_WIDTH
	line.default_color = _PATH_COLOR_VALID
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 5
	add_child(line)
	for pt: Vector2 in path:
		line.add_point(pt)
	var dots: Array = []
	for _i in range(_PATH_DOT_COUNT):
		var dot := Sprite2D.new()
		dot.texture = _make_circle_texture(_PATH_DOT_RADIUS, Color.WHITE)
		dot.modulate = _PATH_COLOR_VALID
		dot.z_index = 6
		add_child(dot)
		dots.append(dot)
	var dst_marker := Sprite2D.new()
	dst_marker.texture = _make_circle_texture(_PATH_DST_MARKER_RADIUS, Color.WHITE)
	dst_marker.modulate = _PATH_COLOR_VALID
	dst_marker.position = dst_center
	dst_marker.z_index = 6
	add_child(dst_marker)
	return {
		"line": line, "dots": dots, "dst_marker": dst_marker,
		"path_points": path, "path_len": path_len,
	}


## Updates animated dot positions for an active pending transport overlay.
func _animate_pending_path_overlay(pt: Dictionary) -> void:
	var overlay: Dictionary = pt.get("path_overlay", {})
	if overlay.is_empty():
		return
	var path: Array[Vector2] = overlay.path_points
	var path_len: float = overlay.path_len
	if path_len < 1.0:
		return
	var spacing: float = path_len / float(_PATH_DOT_COUNT)
	var phase_wrapped: float = fmod(pt.path_phase, path_len)
	for i in range(_PATH_DOT_COUNT):
		var dot: Sprite2D = overlay.dots[i]
		var t: float = fmod(phase_wrapped + float(i) * spacing, path_len)
		dot.position = _point_along_path(path, t)


## Frees all nodes belonging to a pending transport path overlay.
func _free_pending_path_overlay(overlay: Dictionary) -> void:
	if overlay.is_empty():
		return
	if is_instance_valid(overlay.get("line")):
		overlay.line.queue_free()
	for dot in overlay.get("dots", []):
		if is_instance_valid(dot):
			dot.queue_free()
	if is_instance_valid(overlay.get("dst_marker")):
		overlay.dst_marker.queue_free()


## Returns true if instance.input_buffer satisfies all input requirements for
## one production cycle. Mirrors BuildingDetailPanel._has_valid_input.
func _building_has_valid_input(instance: BuildingRegistry.BuildingInstance) -> bool:
	var table_entry: Dictionary = BuildingRegistry.PRODUCTION_TABLE.get(instance.type, {})
	for input_spec: Dictionary in table_entry.get("inputs", []):
		var resource_id: StringName = input_spec["resource_id"]
		var needed: float = input_spec.get("charge_cost", float(input_spec.get("quantity", 0)))
		if instance.input_buffer.get(resource_id, 0.0) < needed:
			return false
	return not table_entry.get("inputs", []).is_empty()


func _building_texture_path(type: int) -> String:
	return BuildingRegistry.BUILDING_TEXTURES.get(type, "res://assets/art/tiles/bld_tile_storage.png")


## Connects inventory screen signals to the HUD storage panel after all _ready() calls complete.
## Deferred so the HUD CanvasLayer has added itself to the "hud" group first.
func _wire_inventory_hud() -> void:
	if _hud == null:
		push_warning("[MapRoot] HUD not found in group 'hud' — inventory↔HUD signals not wired")
		return



## Maps WorldGrid.TileType to the correct ManualActionType.
## Returns -1 for IMPASSABLE and any unknown types.
func _terrain_to_action(terrain: WorldGrid.TileType) -> int:
	match terrain:
		WorldGrid.TileType.TREE:        return PlayerCharacter.ManualActionType.CHOP_TREE
		WorldGrid.TileType.STONE:       return PlayerCharacter.ManualActionType.MINE_STONE
		WorldGrid.TileType.BERRY:       return PlayerCharacter.ManualActionType.PICK_BERRIES
		WorldGrid.TileType.GRASS:       return PlayerCharacter.ManualActionType.HARVEST_FIBER
		WorldGrid.TileType.EMPTY:       return PlayerCharacter.ManualActionType.FORAGE
		WorldGrid.TileType.IMPASSABLE:  return -1
		_:                              return -1
