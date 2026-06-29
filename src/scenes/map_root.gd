class_name MapRoot extends Node2D
## Game world rendering controller.
## Owns the three TileMapLayer visual layers and the WorldGrid data node.
## After generation, syncs all 900 tiles in a single batch set_cell() pass.
## ADR-0004: Grid data is authoritative; TileMapLayer is a pure rendering target.

const _TILE_PANEL_SCENE: PackedScene = preload("res://src/ui/TileInteractionPanel.tscn")


## Owns terrain TileSet construction + tilemap sync (Phase 5 extraction).
var _terrain_renderer: TerrainRenderer

@onready var background_layer: TileMapLayer = $BackgroundLayer
@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var building_slots: TileMapLayer = $BuildingSlots
@onready var grid: WorldGrid = $WorldGrid

@onready var _player: PlayerCharacter = $PlayerCharacter
@onready var _registry: Node = get_node("/root/BuildingRegistry")

var _interaction_panel: TileInteractionPanel = null
var _last_action_tile: Vector2i = Vector2i(-1, -1)
## Last action type the player explicitly confirmed via the tile panel (for shift-click repeat).
var _last_confirmed_action: int = -1



## Owns per-building sprites + status indicators (Phase 5 extraction).
var _building_layer: BuildingIndicatorLayer = null
## World drag/interaction controller (Phase 5, incremental extraction).
var _drag_controller: DragController = null
## Player manual-action feedback (harvest indicators + loot).
var _action_feedback: ActionFeedback = null
## World resource-icon data + display layer.
var _resource_badges: ResourceBadgeLayer = null
## Maps tile → Sprite2D for placed path tiles.
var _path_sprites: Dictionary = {}
## Maps tile → BuildingStatusIndicator for path tiles currently under construction.
var _path_indicators: Dictionary = {}
## Maps tile → Sprite2D ghost overlay shown while seed is growing.
var _growing_sprites: Dictionary = {}
## Maps tile → BuildingStatusIndicator showing seed growth progress.
var _growing_indicators: Dictionary = {}

var _hud: HUD = null
var _map_select_highlight: Sprite2D = null
var _route_lines: RouteLines = null
var _npc_overlay: NpcOverlay = null
## Top-right fertility icons; re-initialized after the overworld start tile generates the map.
var _fertility_indicator: FertilityIndicator = null
## Set when this scene was loaded via tile travel to a non-home coord; triggers visiting HUD mode.
var _visiting_coord: Vector2i = Vector2i(-1, -1)



func _ready() -> void:
	_terrain_renderer = TerrainRenderer.new()
	_terrain_renderer.build_and_assign(background_layer, terrain_layer)
	_building_layer = BuildingIndicatorLayer.new()
	add_child(_building_layer)
	_resource_badges = ResourceBadgeLayer.new()
	_resource_badges.setup(self)
	add_child(_resource_badges)
	_drag_controller = DragController.new()
	_drag_controller.setup(self)
	add_child(_drag_controller)
	_drag_controller.set_badges(_resource_badges)
	_action_feedback = ActionFeedback.new()
	_action_feedback.setup(self, _drag_controller, _resource_badges)
	_drag_controller.set_action(_action_feedback)
	WorldSaveManager.register_world_grid(grid)
	WorldSaveManager.register_player_character(_player)
	var _cam := get_node_or_null("../CameraController") as CameraController
	if _cam != null:
		WorldSaveManager.register_camera_controller(_cam)
	_interaction_panel = _TILE_PANEL_SCENE.instantiate() as TileInteractionPanel
	add_child(_interaction_panel)
	_interaction_panel.world_click_at.connect(_on_panel_world_click)
	_interaction_panel.action_confirmed.connect(func(a: int) -> void: _last_confirmed_action = a)
	_registry.connect("building_placed", _on_building_placed)
	_registry.building_state_changed.connect(_on_building_state_changed)
	_registry.building_construction_complete.connect(_on_building_construction_complete)
	_registry.building_demolished.connect(_on_building_demolished)
	_registry.building_items_dropped.connect(_on_building_items_dropped)
	TickSystem.ticks_advanced.connect(_on_ticks_advanced_indicators)
	_player.init_dependencies(TickSystem, null, grid, null)
	_registry.init_dependencies(grid, _player)
	PathSystem.init_dependencies(grid)
	PathSystem.path_construction_started.connect(_on_path_construction_started)
	PathSystem.path_placed.connect(_on_path_placed)
	PathSystem.path_updated.connect(_on_path_updated)
	PathSystem.path_removed.connect(_on_path_removed)
	LogisticsSystem.set_grid_map(grid)
	NPCSystem.set_grid_map(grid)
	WildSystem.set_grid_map(grid)
	WildSystem.wild_changed.connect(BuildingRegistry.refresh_wild_efficiency)
	_player.seed_planted.connect(_on_seed_planted)
	grid.terrain_growing_started.connect(_on_terrain_growing_started)
	grid.terrain_tile_changed.connect(_on_terrain_tile_changed)
	print("[TRAVELDBG] _ready: pending_switch=%s pending_load=%s current=%s" % [WorldSaveManager.has_pending_map_switch(), WorldSaveManager.has_pending_load(), WorldSaveManager.get_current_map_coord()])
	if WorldSaveManager.has_pending_map_switch():
		# Overworld tile-to-tile travel: this scene was reloaded to swap the active tactical map.
		# The overworld island + globals (time, tech) persist in their autoloads; only the per-map
		# colony is restored or freshly generated for the target tile.
		_apply_pending_map_switch()
	elif WorldSaveManager.has_pending_load():
		WorldSaveManager.apply_pending_load()
		WorldSaveManager.set_current_map_coord(OverworldSystem.get_start_coord())
		_terrain_renderer.sync(grid, background_layer, terrain_layer)
		_resource_badges._spawn_resource_badges()
	else:
		# New game: reset all Autoload state so nothing from a previously loaded save bleeds
		# through. OverworldSystem is reset inside _begin_new_game_start_pick via generate().
		WorldSaveManager.reset_new_game()
		# The player picks a start tile on the overworld first. The tactical map is generated
		# from that tile in _on_new_game_start_selected (deferred so every node's _ready —
		# including the overworld view — has run before the picker opens).
		call_deferred(&"_begin_new_game_start_pick")
	_player.action_started.connect(_action_feedback._on_action_started)
	_player.action_queued.connect(_action_feedback._on_action_queued)
	_player.action_completed.connect(_action_feedback._on_action_completed)
	_player.action_progress_update.connect(_action_feedback._on_action_progress_update)
	_player.action_queue_cleared.connect(_action_feedback._on_action_queue_cleared)
	_player.action_interrupted.connect(_action_feedback._on_action_interrupted)
	_drag_controller._setup_drag_overlays()
	_setup_map_select_highlight()
	_route_lines = RouteLines.new()
	_route_lines.name = "RouteLines"
	add_child(_route_lines)
	_route_lines.init_dependencies(grid)
	_npc_overlay = NpcOverlay.new()
	_npc_overlay.name = "NpcOverlay"
	add_child(_npc_overlay)
	_npc_overlay.init_dependencies(grid)
	var wild_overlay := WildOverlay.new()
	wild_overlay.name = "WildOverlay"
	add_child(wild_overlay)
	wild_overlay.init_dependencies(grid)
	_fertility_indicator = FertilityIndicator.new()
	_fertility_indicator.name = "FertilityIndicator"
	add_child(_fertility_indicator)
	_fertility_indicator.init_dependencies(grid)
	call_deferred(&"_wire_building_detail")
	call_deferred(&"_wire_overworld_travel")


## Opens the overworld as a blocking start picker on a new game. Deferred from _ready so the
## overworld view node is fully ready. Falls back to the center land tile if the view is absent.
## Shows a loading state for one frame before generate() runs so the player sees feedback.
func _begin_new_game_start_pick() -> void:
	_set_hud_visible(false)
	var ow_view := get_node_or_null("../OverworldLayer/OverworldView")
	if ow_view != null and ow_view.has_method("open_for_loading"):
		ow_view.open_for_loading()
		await get_tree().process_frame
		OverworldSystem.start_selected.connect(_on_new_game_start_selected, CONNECT_ONE_SHOT)
		OverworldSystem.generate(randi())
	else:
		OverworldSystem.start_selected.connect(_on_new_game_start_selected, CONNECT_ONE_SHOT)
		OverworldSystem.generate(randi())
		var center := Vector2i(OverworldSystem.OVERWORLD_SIZE / 2, OverworldSystem.OVERWORLD_SIZE / 2)
		OverworldSystem.select_start(center)


## Shows/hides the gameplay HUD (CanvasLayer in the "hud" group). Hidden while the player has not
## yet chosen a settlement, so the start picker is clean.
func _set_hud_visible(is_visible: bool) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud") as CanvasLayer
	if hud != null:
		hud.visible = is_visible


## Generates the tactical map from the chosen overworld start tile and finishes new-game setup.
func _on_new_game_start_selected(coord: Vector2i) -> void:
	OverworldSystem.generate_tactical_map(grid, coord)
	WildSystem.initialize_for_new_map()
	_terrain_renderer.sync(grid, background_layer, terrain_layer)
	_resource_badges._spawn_resource_badges()
	# FertilityIndicator snapshots get_fertility() at init; the grid was empty then, so
	# re-snapshot now that the chosen tile's map (and its fertilities) exists.
	if _fertility_indicator != null:
		_fertility_indicator.init_dependencies(grid)
	WorldSaveManager.set_current_map_coord(coord)
	_set_hud_visible(true)  # settlement chosen — bring the gameplay HUD back


## Connects the overworld view's double-click travel signal. Deferred so the sibling
## OverworldLayer/OverworldView node is present and ready.
func _wire_overworld_travel() -> void:
	var ow_view := get_node_or_null("../OverworldLayer/OverworldView")
	if ow_view == null or not ow_view.has_signal("map_opened"):
		push_warning("[MapRoot] OverworldView/map_opened not found — tile travel not wired")
		return
	# String-based connect: ow_view is statically typed Node, which doesn't declare map_opened,
	# so ow_view.map_opened.connect(...) resolves unreliably. connect() by name is dynamic.
	if not ow_view.is_connected("map_opened", Callable(self, "travel_to")):
		ow_view.connect("map_opened", Callable(self, "travel_to"))
	print("[TRAVELDBG] _wire_overworld_travel: connected=%s" % ow_view.is_connected("map_opened", Callable(self, "travel_to")))
	if _hud != null:
		_hud.set_overworld_view(ow_view)


## Switches the active tactical map to another overworld tile (double-click travel). Snapshots the
## current colony into memory, stages the target, and reloads the scene — the rebuilt MapRoot then
## restores or generates the target map in _apply_pending_map_switch(). Reload gives correct visual
## teardown for free and reuses the proven load-reconstruction path.
func travel_to(coord: Vector2i) -> void:
	print("[TRAVELDBG] travel_to(%s) current=%s selectable=%s" % [coord, WorldSaveManager.get_current_map_coord(), OverworldSystem.is_selectable(coord)])
	if not OverworldSystem.is_selectable(coord):
		return
	if coord == WorldSaveManager.get_current_map_coord():
		return
	WorldSaveManager.snapshot_current_map_state()
	WorldSaveManager.request_map_switch(coord)
	# The main menu launches the game by instancing game.tscn and add_child'ing it to root (it is
	# never the SceneTree.current_scene), so reload_current_scene() would miss it. Rebuild the
	# GameWorld subtree directly instead. Deferred so we aren't restructuring the tree mid-signal.
	_reload_game_scene.call_deferred()


## Frees the live GameWorld subtree and instances a fresh game.tscn under the same parent. The
## rebuilt MapRoot then applies the pending map switch in _ready.
func _reload_game_scene() -> void:
	var game_root: Node = get_parent()
	var holder: Node = game_root.get_parent()
	var scene_path: String = game_root.scene_file_path
	if scene_path.is_empty():
		scene_path = "res://src/scenes/game.tscn"
	holder.remove_child(game_root)
	game_root.queue_free()
	var fresh: Node = (load(scene_path) as PackedScene).instantiate()
	holder.add_child(fresh)


## Restores a previously visited tile's colony, or generates a fresh, bare map on first visit
## (no starter Collection Point — only the chosen start tile gets one). Runs in _ready after a
## travel-triggered scene reload.
func _apply_pending_map_switch() -> void:
	var coord: Vector2i = WorldSaveManager.consume_pending_map_switch()
	print("[TRAVELDBG] _apply_pending_map_switch coord=%s has_state=%s" % [coord, WorldSaveManager.has_map_state(coord)])
	if WorldSaveManager.has_map_state(coord):
		WorldSaveManager.restore_map_state(coord)
	else:
		# First visit: clear the previous tile's colony (the per-map autoloads survive the reload)
		# before laying down fresh terrain. No starter Collection Point here — only the chosen
		# start tile gets one; travelled-to maps start bare.
		WorldSaveManager.reset_map_state()
		OverworldSystem.generate_tactical_map(grid, coord)
		WildSystem.initialize_for_new_map()
	_terrain_renderer.sync(grid, background_layer, terrain_layer)
	_resource_badges._spawn_resource_badges()
	if _fertility_indicator != null:
		_fertility_indicator.init_dependencies(grid)
	var home_coord: Vector2i = OverworldSystem.get_start_coord()
	if coord != home_coord and home_coord != Vector2i(-1, -1):
		_visiting_coord = coord
		TickSystem.set_pause(true)
	elif coord == home_coord:
		TickSystem.set_pause(false)


## Animates all resource icons with a sine-wave vertical float (period: 2.5s, amplitude: 4px).
## Phase is staggered per tile so icons don't bob in lockstep.
## During a drag: dragged icon follows cursor; cost label and path overlay update live.
func _process(_delta: float) -> void:
	_update_map_select_highlight()


func _setup_map_select_highlight() -> void:
	_map_select_highlight = Sprite2D.new()
	_map_select_highlight.texture = TextureFactory.tile_highlight(
		WorldGrid.TILE_SIZE, Color(0.29, 0.49, 0.66, 0.22), Color(0.29, 0.49, 0.66, 0.85))
	_map_select_highlight.visible = false
	_map_select_highlight.z_index = 4
	add_child(_map_select_highlight)


func _update_map_select_highlight() -> void:
	if _hud == null or not _hud.is_map_select_active():
		_map_select_highlight.visible = false
		return
	var world_pos: Vector2 = get_global_mouse_position()
	var tile: Vector2i = grid.world_to_tile(world_pos)
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


## Wires Buildings Drawer drag signals and route-lines to this scene.
## BuildingDetailPanel has been replaced by BuildingsDrawer (CanvasLayer).
## Drag signals are forwarded through BuildingsDrawerContent → BuildingDetailView.
func _wire_building_detail() -> void:
	var hud: HUD = get_tree().get_first_node_in_group(&"hud") as HUD
	_hud = hud
	if hud == null:
		push_warning("[MapRoot] HUD not found — drag signals not wired")
		return
	hud.set_route_lines(_route_lines)
	var drawer: BuildingsDrawer = hud.get_node_or_null("BuildingsDrawer") as BuildingsDrawer
	if drawer == null:
		push_warning("[MapRoot] BuildingsDrawer not found in HUD — storage drag not wired")
	else:
		_drag_controller.set_buildings_drawer(drawer)
		var detail_view: BuildingDetailView = drawer._content._detail_view
		if detail_view != null:
			detail_view.storage_drag_started.connect(_drag_controller._on_storage_drag_started)
			detail_view.input_drag_started.connect(_drag_controller._on_input_drag_started)
			detail_view.output_drag_started.connect(_drag_controller._on_output_drag_started)
	if _visiting_coord != Vector2i(-1, -1):
		_apply_visiting_hud_mode()


## Applies the "visiting" HUD bar for a non-home tile. Called from _wire_building_detail so
## _hud is guaranteed to be set first.
func _apply_visiting_hud_mode() -> void:
	if _fertility_indicator != null:
		_fertility_indicator.visible = false
	var home_coord := OverworldSystem.get_start_coord()
	_hud.enter_visiting_mode(_visiting_coord, func() -> void: travel_to(home_coord))


# ── Tile interaction input ────────────────────────────────────────────────────


## Handles a confirmed right-click on a valid grid tile.
## Opens the Tile Interaction Panel for harvestable terrain or CONSTRUCTING buildings.
## Shift+right-click repeats the last confirmed action on a matching tile without the panel.
func _on_tile_clicked(tile: Vector2i, screen_pos: Vector2) -> void:
	if Input.is_key_pressed(KEY_SHIFT) and _last_confirmed_action >= 0:
		var terrain: WorldGrid.TileType = grid.get_terrain(tile)
		var primary: int = _terrain_to_action(terrain)
		var clear: int = _terrain_to_clear_action(terrain)
		if _last_confirmed_action == primary or _last_confirmed_action == clear:
			_player.try_start_action(_last_confirmed_action, tile)
			return

	var building_id: String = grid.get_building(tile)
	if building_id != "":
		var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_instance_at_tile(tile)
		if instance != null and instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
			_last_action_tile = tile
			_interaction_panel.show_at(screen_pos, PlayerCharacter.ManualActionType.CONSTRUCT_BUILDING, tile)
		return
	if PathSystem.is_constructing(tile):
		_last_action_tile = tile
		_interaction_panel.show_at(screen_pos, PlayerCharacter.ManualActionType.CONSTRUCT_PATH, tile)
		return
	if PathSystem.has_path(tile):
		return
	var terrain: WorldGrid.TileType = grid.get_terrain(tile)
	var action_type: int = _terrain_to_action(terrain)
	if action_type < 0:
		return
	_last_action_tile = tile
	_interaction_panel.show_at(screen_pos, action_type, tile)


## Handles a world-area click emitted by the panel's ClickGuard.
## Any click outside the panel closes it — the user can right-click again to open a new one.
func _on_panel_world_click(_screen_pos: Vector2) -> void:
	_interaction_panel.close()


## Spawns a dimmed Sprite2D and a construction progress indicator when a path tile starts building.
func _on_path_construction_started(tile: Vector2i) -> void:
	var tile_px: int = WorldGrid.TILE_SIZE
	var center: Vector2 = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	var sprite := Sprite2D.new()
	sprite.texture = load(PathSystem.get_texture_path(tile))
	sprite.position = center
	sprite.z_index = 1
	sprite.modulate = Color(0.9, 0.8, 0.35, 0.5)
	add_child(sprite)
	_path_sprites[tile] = sprite

	var indicator := BuildingStatusIndicator.new()
	indicator.position = center + Vector2(tile_px * 0.32, tile_px * 0.32)
	indicator.z_index = 3
	add_child(indicator)
	indicator.set_construction_progress(0.0)
	_path_indicators[tile] = indicator


## Called when a path tile finishes construction or is restored from a save.
## Tweens the sprite to full opacity, removes the progress indicator, and
## re-draws the final bitmask texture. For save-load restores, creates the sprite fresh.
func _on_path_placed(tile: Vector2i) -> void:
	var tile_px: int = WorldGrid.TILE_SIZE
	var existing: Sprite2D = _path_sprites.get(tile)
	if existing != null:
		existing.texture = load(PathSystem.get_texture_path(tile))
		var tween := create_tween()
		tween.tween_property(existing, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var indicator: BuildingStatusIndicator = _path_indicators.get(tile)
		if indicator != null:
			indicator.queue_free()
			_path_indicators.erase(tile)
		return
	var sprite := Sprite2D.new()
	sprite.texture = load(PathSystem.get_texture_path(tile))
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


## Removes a path sprite (and any lingering construction indicator) when demolished.
func _on_path_removed(tile: Vector2i) -> void:
	var sprite: Sprite2D = _path_sprites.get(tile)
	if sprite != null:
		sprite.queue_free()
		_path_sprites.erase(tile)
	var indicator: BuildingStatusIndicator = _path_indicators.get(tile)
	if indicator != null:
		indicator.queue_free()
		_path_indicators.erase(tile)


## Spawns the building visual sprite when BuildingRegistry confirms placement.
func _on_building_placed(building_id: String, type: int, tile: Vector2i) -> void:
	_building_layer.add_building(building_id, type, tile)
	PathSystem.update_neighbors(tile)


func _on_building_construction_complete(building_id: String, _type: int) -> void:
	_building_layer.complete_construction(building_id)


func _on_building_items_dropped(tile: Vector2i, items: Dictionary) -> void:
	var seed_base: int = Time.get_ticks_msec()
	var i: int = 0
	for res_id: StringName in items:
		var qty: int = items[res_id]
		for _j in range(qty):
			if grid.add_resource_to_tile(tile, res_id, true):
				_resource_badges._spawn_badge(tile, [res_id], self, 0.0, true, seed_base + i * 37)
			i += 1


func _on_building_demolished(building_id: StringName) -> void:
	var tile: Vector2i = _building_layer.remove_building(str(building_id))
	if tile != Vector2i(-1, -1):
		PathSystem.update_neighbors(tile)
		_player.cancel_actions_at_tile(tile)


func _on_building_state_changed(building_id: String, _new_state: int, _reason: String) -> void:
	_building_layer.refresh(building_id)


func _on_ticks_advanced_indicators(_delta: int) -> void:
	_building_layer.refresh_all()
	for tile: Vector2i in _growing_indicators:
		(_growing_indicators[tile] as BuildingStatusIndicator).set_progress(grid.get_growth_progress(tile))
	_drag_controller._advance_pending_transports(_delta)
	for tile: Vector2i in _path_indicators:
		var indicator: BuildingStatusIndicator = _path_indicators[tile]
		indicator.set_construction_progress(_player.get_active_progress_for_tile(tile))



## Called when the player finishes a PLANT_SEED action.
## Translates seed_type StringName to a TileType and asks the grid to start growth.
func _on_seed_planted(seed_type: StringName, tile: Vector2i) -> void:
	var target_type: WorldGrid.TileType
	match seed_type:
		&"tree_seed":  target_type = WorldGrid.TileType.TREE
		&"grass_seed": target_type = WorldGrid.TileType.GRASS
		&"berry_seed": target_type = WorldGrid.TileType.BERRY
		&"wheat_seed": target_type = WorldGrid.TileType.WHEAT
		_:
			push_warning("[MapRoot] unknown seed_type: %s" % str(seed_type))
			return
	grid.plant_seed(tile, target_type)


## Spawns a semi-transparent ghost sprite over a growing tile.
func _on_terrain_growing_started(tile: Vector2i, target_type: int) -> void:
	if _growing_sprites.has(tile):
		return
	var tex: Texture2D = _terrain_renderer.get_terrain_texture(target_type as WorldGrid.TileType)
	if tex == null:
		return
	var tile_px: int = WorldGrid.TILE_SIZE
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.4)
	sprite.z_index = 1
	add_child(sprite)
	_growing_sprites[tile] = sprite

	# Same progress ring used by buildings / manual actions, tracking growth time.
	var indicator := BuildingStatusIndicator.new()
	indicator.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5 \
		+ Vector2(tile_px * 0.32, tile_px * 0.32)
	indicator.z_index = 3
	indicator.set_progress(grid.get_growth_progress(tile))
	add_child(indicator)
	_growing_indicators[tile] = indicator


## Updates the terrain TileMapLayer when a tile's terrain type changes (e.g. seed grows).
## Also removes any ghost sprite for that tile.
func _on_terrain_tile_changed(tile: Vector2i) -> void:
	var terrain: WorldGrid.TileType = grid.get_terrain(tile)
	if terrain == WorldGrid.TileType.EMPTY:
		terrain_layer.erase_cell(tile)
	else:
		terrain_layer.set_cell(tile, 0, _terrain_renderer._terrain_type_to_atlas(terrain, tile))
	var ghost: Sprite2D = _growing_sprites.get(tile)
	if ghost != null:
		ghost.queue_free()
		_growing_sprites.erase(tile)
	var growth_indicator: BuildingStatusIndicator = _growing_indicators.get(tile)
	if growth_indicator != null:
		growth_indicator.queue_free()
		_growing_indicators.erase(tile)


## Maps WorldGrid.TileType to the correct ManualActionType.
## Returns -1 for IMPASSABLE and any unknown types.
func _terrain_to_action(terrain: WorldGrid.TileType) -> int:
	match terrain:
		WorldGrid.TileType.TREE:        return PlayerCharacter.ManualActionType.CHOP_TREE
		WorldGrid.TileType.STONE:       return PlayerCharacter.ManualActionType.MINE_STONE
		WorldGrid.TileType.BERRY:       return PlayerCharacter.ManualActionType.PICK_BERRIES
		WorldGrid.TileType.GRASS:       return PlayerCharacter.ManualActionType.HARVEST_FIBER
		WorldGrid.TileType.WHEAT:       return PlayerCharacter.ManualActionType.HARVEST_WHEAT
		WorldGrid.TileType.CLAY:        return PlayerCharacter.ManualActionType.MINE_CLAY
		WorldGrid.TileType.IRON:        return PlayerCharacter.ManualActionType.MINE_IRON
		WorldGrid.TileType.COPPER:      return PlayerCharacter.ManualActionType.MINE_COPPER
		WorldGrid.TileType.TIN:         return PlayerCharacter.ManualActionType.MINE_TIN
		WorldGrid.TileType.SILVER:      return PlayerCharacter.ManualActionType.MINE_SILVER
		WorldGrid.TileType.GOLD:        return PlayerCharacter.ManualActionType.MINE_GOLD
		WorldGrid.TileType.GEMSTONE:    return PlayerCharacter.ManualActionType.MINE_GEMSTONE
		WorldGrid.TileType.FLAX:        return PlayerCharacter.ManualActionType.HARVEST_FLAX
		WorldGrid.TileType.HOPS:        return PlayerCharacter.ManualActionType.HARVEST_HOPS
		WorldGrid.TileType.GRAPES:      return PlayerCharacter.ManualActionType.HARVEST_GRAPES
		WorldGrid.TileType.OLIVE:       return PlayerCharacter.ManualActionType.HARVEST_OLIVES
		WorldGrid.TileType.BEES:        return PlayerCharacter.ManualActionType.HARVEST_HONEY
		WorldGrid.TileType.SAND:        return PlayerCharacter.ManualActionType.GATHER_SAND
		WorldGrid.TileType.MARBLE:      return PlayerCharacter.ManualActionType.MINE_MARBLE
		WorldGrid.TileType.AMBER:       return PlayerCharacter.ManualActionType.MINE_AMBER
		WorldGrid.TileType.EMPTY:       return PlayerCharacter.ManualActionType.FORAGE
		WorldGrid.TileType.IMPASSABLE:  return -1
		_:                              return -1


## Maps WorldGrid.TileType to the clear ManualActionType for that terrain (−1 if none).
func _terrain_to_clear_action(terrain: WorldGrid.TileType) -> int:
	match terrain:
		WorldGrid.TileType.TREE:  return PlayerCharacter.ManualActionType.CLEAR_TREE
		WorldGrid.TileType.STONE: return PlayerCharacter.ManualActionType.CLEAR_STONE
		WorldGrid.TileType.BERRY: return PlayerCharacter.ManualActionType.CLEAR_BERRY
		WorldGrid.TileType.GRASS: return PlayerCharacter.ManualActionType.CLEAR_GRASS
		WorldGrid.TileType.WHEAT: return PlayerCharacter.ManualActionType.CLEAR_WHEAT
		_: return -1
