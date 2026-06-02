class_name MapRoot extends Node2D
## Game world rendering controller.
## Owns the three TileMapLayer visual layers and the WorldGrid data node.
## After generation, syncs all 900 tiles in a single batch set_cell() pass.
## ADR-0004: Grid data is authoritative; TileMapLayer is a pure rendering target.

const WORLD_SEED: int = 42  # TODO: replace with dynamic seed before release
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

var _inventory_screen: InventoryScreen = null

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


func _ready() -> void:
	_setup_tilesets()
	grid.generate(WORLD_SEED)
	_sync_tilemap()
	_spawn_resource_badges()
	_interaction_panel = _TILE_PANEL_SCENE.instantiate() as TileInteractionPanel
	add_child(_interaction_panel)
	_interaction_panel.world_click_at.connect(_on_panel_world_click)
	_registry.connect("building_placed", _on_building_placed)
	_player.init_dependencies(TickSystem, null, grid, null)
	_registry.init_dependencies(grid, _player)
	_registry.place_starter_building(1, Vector2i(12, 12))  # 1 = BuildingType.STORAGE_BUILDING
	_player.action_started.connect(_on_action_started)
	_player.action_completed.connect(_on_action_completed)
	_setup_drag_overlays()
	_inventory_screen = InventoryScreen.new()
	_inventory_screen.name = "InventoryScreen"
	add_child(_inventory_screen)
	call_deferred(&"_wire_inventory_hud")
	call_deferred(&"_wire_building_detail")


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
	var count: int = mini(resource_ids.size(), _ICON_SCALE_BY_COUNT.size())
	var scale_factor: float = icon_scale_override if icon_scale_override > 0.0 else _ICON_SCALE_BY_COUNT[count - 1]
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
		var icon_node: Node2D = entry.node as Node2D
		if _drag_icon != null and icon_node == _drag_icon:
			icon_node.global_position = get_global_mouse_position()
			continue
		icon_node.position.y = entry.base_pos.y + sin(t * TAU / 2.5 + entry.phase) * 4.0

	if (_drag_from_container_id != &"" or _drag_from_input_building_id != "" or _drag_from_output_building_id != "") and _drag_icon != null:
		_drag_icon.global_position = get_global_mouse_position()

	if _drag_icon != null:
		_drag_path_phase += delta * _PATH_DOT_SPEED
	_update_drag_overlays()


## Updates cost label (AC2) and path line overlay (AC3) each frame during an active drag.
func _update_drag_overlays() -> void:
	if _drag_icon == null:
		_drag_cost_label.visible = false
		_drag_energy_label.visible = false
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
	_drag_cost_label.text = "⏱️%d" % preview.tick_cost
	_drag_cost_label.position = cursor_world + Vector2(16.0, -32.0)
	_drag_cost_label.visible = true

	_drag_energy_label.text = "⚡%d" % preview.energy_cost
	var insufficient: bool = preview.get(&"energy_insufficient", false)
	_drag_energy_label.add_theme_color_override(
		"font_color",
		Color(0.769, 0.353, 0.290) if insufficient else Color(1.0, 1.0, 0.8)
	)
	var tick_w: float = _drag_cost_label.get_minimum_size().x
	_drag_energy_label.position = cursor_world + Vector2(16.0 + tick_w + 6.0, -32.0)
	_drag_energy_label.visible = true

	if not grid.is_in_bounds(hovered_tile) or _drag_src_tile == Vector2i(-1, -1):
		_drag_path_line.visible = false
		_drag_path_dst_marker.visible = false
		for dot: Sprite2D in _drag_path_dots:
			dot.visible = false
		return

	var passable: bool = grid.is_passable(hovered_tile)
	var not_full: bool = grid.get_resources(hovered_tile).size() < WorldGrid.MAX_RESOURCES_PER_TILE
	var valid: bool = passable and not_full
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
	var has_energy: bool = _player.get_current_energy() >= base_cost
	var is_food: bool = PlayerCharacter.FOOD_ENERGY.has(_drag_resource_id)
	var energy_insufficient: bool = not has_energy and not is_food
	var tick_cost: int = base_cost * (15 if (not has_energy and is_food) else 5)
	var energy_cost: int = base_cost if has_energy else 0

	_drag_cost_label.text = "⏱️%d" % tick_cost
	_drag_cost_label.position = cursor_world + Vector2(16.0, -32.0)
	_drag_cost_label.visible = true

	_drag_energy_label.text = "⚡%d" % energy_cost
	_drag_energy_label.add_theme_color_override(
		"font_color",
		Color(0.769, 0.353, 0.290) if energy_insufficient else Color(1.0, 1.0, 0.8)
	)
	var tick_w: float = _drag_cost_label.get_minimum_size().x
	_drag_energy_label.position = cursor_world + Vector2(16.0 + tick_w + 6.0, -32.0)
	_drag_energy_label.visible = true

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
		valid = (grid.is_passable(hovered_tile)
			and grid.get_resources(hovered_tile).size() < WorldGrid.MAX_RESOURCES_PER_TILE)

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
	_drag_icon.queue_free()
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
				if InventorySystem.try_deposit(inst.assigned_container_id, res_id, 1) == InventoryContainer.DepositResult.SUCCESS:
					get_viewport().set_input_as_handled()
					return
		elif grid.is_passable(target_tile) \
				and grid.get_resources(target_tile).size() < WorldGrid.MAX_RESOURCES_PER_TILE:
			grid.add_resource_to_tile(target_tile, res_id, true)
			_spawn_badge(target_tile, [res_id], self, 0.0, true, Time.get_ticks_msec())
			get_viewport().set_input_as_handled()
			return
	_registry.receive_output_to_buffer(building_id, res_id, 1)
	get_viewport().set_input_as_handled()


## Resolves an input-buffer drag on LMB release.
## Drops on passable tile → places resource badge. Otherwise → returns to input buffer.
func _finish_input_drag() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = grid.world_to_tile(world_pos)
	var res_id: StringName = _drag_resource_id
	var building_id: String = _drag_from_input_building_id
	_drag_icon.queue_free()
	_drag_icon = null
	_drag_from_input_building_id = ""
	_drag_resource_id = &""
	_drag_from_building_tile = Vector2i(-1, -1)
	_drag_src_tile = Vector2i(-1, -1)
	if grid.is_in_bounds(target_tile) and grid.is_passable(target_tile) \
			and grid.get_resources(target_tile).size() < WorldGrid.MAX_RESOURCES_PER_TILE:
		grid.add_resource_to_tile(target_tile, res_id, true)
		_spawn_badge(target_tile, [res_id], self, 0.0, true, Time.get_ticks_msec())
	else:
		_registry.receive_input_from_world(building_id, res_id, 1)
	get_viewport().set_input_as_handled()


## Resolves a storage drag on LMB release.
## Drops on valid tile → places resource. Invalid → returns to source container.
func _finish_storage_drag() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = grid.world_to_tile(world_pos)
	var res_id: StringName = _drag_resource_id
	var container_id: StringName = _drag_from_container_id

	_drag_icon.queue_free()
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
			if target_cid != &"" and target_cid != container_id:
				if InventorySystem.try_deposit(target_cid, res_id, 1) == InventoryContainer.DepositResult.SUCCESS:
					get_viewport().set_input_as_handled()
					return
			elif target_cid == &"":
				# Production building (e.g. LUMBER_CAMP) — resource was already consumed from
				# source container in _on_storage_drag_started; route directly to input_buffer.
				if _registry.receive_input_from_world(building_id, res_id, 1):
					get_viewport().set_input_as_handled()
					return
			# Same container or deposit failed — fall through to return resource
		elif grid.add_resource_to_tile(target_tile, res_id, true):
			_spawn_badge(target_tile, [res_id], self, 0.0, true, Time.get_ticks_msec())
			get_viewport().set_input_as_handled()
			return

	InventorySystem.try_deposit(container_id, res_id, 1)
	get_viewport().set_input_as_handled()


## Wires BuildingDetailPanel.storage_drag_started to this scene.
func _wire_building_detail() -> void:
	var hud: HUD = get_tree().get_first_node_in_group(&"hud") as HUD
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
		var hit := _hit_test_resource_icon(world_pos)
		if hit.is_empty():
			# No resource icon hit — check if tile has a building.
			var click_tile: Vector2i = terrain_layer.local_to_map(terrain_layer.to_local(world_pos))
			if (click_tile.x >= 0 and click_tile.y >= 0
					and click_tile.x < WorldGrid.GRID_SIZE and click_tile.y < WorldGrid.GRID_SIZE):
				var building_id: String = grid.get_building(click_tile)
				if building_id != "":
					var hud: HUD = get_tree().get_first_node_in_group(&"hud") as HUD
					if hud != null:
						hud.open_building_detail(building_id)
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

		var result: int = _player.try_commit_relocation(target_tile, grid)
		match result:
			PlayerCharacter.RelocationResult.SUCCESS, \
			PlayerCharacter.RelocationResult.SUCCESS_LOW_ENERGY:
				var src_tile: Vector2i = _drag_icon_entry.tile
				var src_idx: int = _drag_icon_entry.resource_idx
				var tile_px: int = WorldGrid.TILE_SIZE
				var new_base: Vector2 = Vector2(target_tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
				_drag_icon_entry.tile = target_tile
				# Resource was appended to end of target array by move_one_resource.
				_drag_icon_entry.resource_idx = grid.get_resources(target_tile).size() - 1
				_drag_icon_entry.base_pos = new_base
				_drag_icon.position = new_base
				_reset_drag_icon_visuals(_drag_icon)
				# Indices for remaining entries on the source tile are shifted by remove_at.
				for entry: Dictionary in _resource_icons:
					if entry.tile == src_tile and entry.resource_idx > src_idx:
						entry.resource_idx -= 1
				var move_dist: int = (abs(target_tile.x - src_tile.x)
					+ abs(target_tile.y - src_tile.y))
				var tick_mult: int = 15 if result == PlayerCharacter.RelocationResult.SUCCESS_LOW_ENERGY else 5
				TickSystem.advance_ticks_manual(maxi(1, move_dist) * tick_mult)
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
	var icon_node: Node2D = _drag_icon
	var tween := create_tween()
	tween.tween_property(icon_node, "position", _drag_icon_entry.base_pos, 0.18).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void: _reset_drag_icon_visuals(icon_node))


func _reset_drag_icon_visuals(icon_node: Node2D) -> void:
	icon_node.modulate.a = 1.0
	icon_node.scale = Vector2(1.0, 1.0)
	icon_node.z_index = 0


## Handles a confirmed left-click on a valid grid tile.
## Maps terrain type to ManualActionType and opens the Tile Interaction Panel.
func _on_tile_clicked(tile: Vector2i, screen_pos: Vector2) -> void:
	var terrain: WorldGrid.TileType = grid.get_terrain(tile)
	var action_type: int = _terrain_to_action(terrain)
	if action_type < 0:
		return
	_last_action_tile = tile
	_interaction_panel.show_at(screen_pos, action_type)


## Handles a world-area click emitted by the panel's ClickGuard.
## Valid tile → update panel in place (AC7); invalid/out-of-bounds → close (AC6).
func _on_panel_world_click(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var tile: Vector2i = terrain_layer.local_to_map(terrain_layer.to_local(world_pos))
	if tile.x < 0 or tile.y < 0 or tile.x >= WorldGrid.GRID_SIZE or tile.y >= WorldGrid.GRID_SIZE:
		_interaction_panel.close()
		return
	var terrain: WorldGrid.TileType = grid.get_terrain(tile)
	var action_type: int = _terrain_to_action(terrain)
	if action_type < 0:
		_interaction_panel.close()
		return
	_last_action_tile = tile
	_interaction_panel.show_at(screen_pos, action_type)


## Advances ticks manually when a player action starts (TickSystem stays paused otherwise).
func _on_action_started(_action_id: int, tick_cost: int) -> void:
	TickSystem.advance_ticks_manual(tick_cost)


## Spawns floating text and a loot-icon badge on the harvested tile.
func _on_action_completed(_action_id: int, output: Array) -> void:
	if _last_action_tile == Vector2i(-1, -1):
		return
	var world_pos: Vector2 = grid.tile_to_world(_last_action_tile)
	for item: Dictionary in output:
		var qty: int = item.get("quantity", 0)
		var resource_id: StringName = item.get("resource_id", &"")
		if qty <= 0 or resource_id == &"" or _resource_id_to_index(resource_id) < 0:
			continue
		_spawn_pickup_float(world_pos, "+%d %s" % [qty, str(resource_id)])
		var ids: Array[StringName] = []
		for _i in range(mini(qty, _ICON_SCALE_BY_COUNT.size())):
			ids.append(resource_id)
		_spawn_badge(_last_action_tile, ids, self, 0.0, true, Time.get_ticks_msec())


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


## Attempts to deposit the currently-dragged resource into a building's storage container.
## Pays energy proportional to drag distance. Snaps back if deposit fails or energy is short.
func _try_deposit_to_building(target_tile: Vector2i, building_id: String) -> void:
	var instance: Object = _registry.get_building_instance(building_id)
	var container_id: StringName = instance.assigned_container_id if instance != null else &""
	var src_tile: Vector2i = _drag_icon_entry.tile
	var src_idx: int = _drag_icon_entry.resource_idx
	var res_id: StringName = _drag_icon_entry.resource_id
	var dist: int = abs(target_tile.x - src_tile.x) + abs(target_tile.y - src_tile.y)
	var cost: int = maxi(1, dist)

	if container_id == &"":
		# Production building (e.g. LUMBER_CAMP) — route to input_buffer instead of a container.
		var allowed: Array = BuildingRegistry.INPUT_RESOURCES.get(
			instance.type if instance != null else -1, [])
		if not res_id in allowed:
			_player.cancel_relocation()
			_snap_back_drag_icon()
			_drag_icon = null
			_drag_icon_entry = {}
			_drag_src_tile = Vector2i(-1, -1)
			return
		var has_energy_prod := _player.get_current_energy() >= cost
		var is_food_prod := PlayerCharacter.FOOD_ENERGY.has(res_id)
		if not has_energy_prod and not is_food_prod:
			_player.cancel_relocation()
			_snap_back_drag_icon()
			_drag_icon = null
			_drag_icon_entry = {}
			_drag_src_tile = Vector2i(-1, -1)
			return
		if has_energy_prod:
			_player.consume_energy(cost)
		grid.remove_one_resource(src_tile, src_idx)
		_registry.receive_input_from_world(building_id, res_id, 1)
		_drag_icon.queue_free()
		_resource_icons.erase(_drag_icon_entry)
		for entry: Dictionary in _resource_icons:
			if entry.tile == src_tile and entry.resource_idx > src_idx:
				entry.resource_idx -= 1
		TickSystem.advance_ticks_manual(cost * (5 if has_energy_prod else 15))
		_player.cancel_relocation()
		_drag_icon = null
		_drag_icon_entry = {}
		_drag_src_tile = Vector2i(-1, -1)
		return

	var has_energy := _player.get_current_energy() >= cost
	var is_food := PlayerCharacter.FOOD_ENERGY.has(res_id)

	if not has_energy and not is_food:
		_player.cancel_relocation()
		_snap_back_drag_icon()
		_drag_icon = null
		_drag_icon_entry = {}
		_drag_src_tile = Vector2i(-1, -1)
		return

	if has_energy:
		_player.consume_energy(cost)

	var deposit_result: int = InventorySystem.try_deposit(container_id, res_id, 1)
	if deposit_result == InventoryContainer.DepositResult.SUCCESS:
		grid.remove_one_resource(src_tile, src_idx)
		_drag_icon.queue_free()
		_resource_icons.erase(_drag_icon_entry)
		for entry: Dictionary in _resource_icons:
			if entry.tile == src_tile and entry.resource_idx > src_idx:
				entry.resource_idx -= 1
		TickSystem.advance_ticks_manual(cost * (5 if has_energy else 15))
	else:
		_snap_back_drag_icon()
	_player.cancel_relocation()
	_drag_icon = null
	_drag_icon_entry = {}
	_drag_src_tile = Vector2i(-1, -1)


## Spawns the building visual sprite when BuildingRegistry confirms placement.
func _on_building_placed(_building_id: String, type: int, tile: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(_building_texture_path(type))
	var tile_px: int = WorldGrid.TILE_SIZE
	sprite.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	sprite.z_index = 2
	add_child(sprite)


func _building_texture_path(type: int) -> String:
	return BuildingRegistry.BUILDING_TEXTURES.get(type, "res://assets/art/tiles/bld_tile_storage.png")


## Connects inventory screen signals to the HUD storage panel after all _ready() calls complete.
## Deferred so the HUD CanvasLayer has added itself to the "hud" group first.
func _wire_inventory_hud() -> void:
	var hud: HUD = get_tree().get_first_node_in_group(&"hud") as HUD
	if hud == null:
		push_warning("[MapRoot] HUD not found in group 'hud' — inventory↔HUD signals not wired")
		return
	_inventory_screen.inventory_opened.connect(hud.hide_storage_panel)
	_inventory_screen.inventory_closed.connect(hud.show_storage_panel)


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
