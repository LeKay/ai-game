class_name BuildingIndicatorLayer extends Node2D
## Owns the per-building world sprites and their BuildingStatusIndicator badges.
##
## Extracted from MapRoot (Phase 5 god-object decomposition). MapRoot forwards the
## BuildingRegistry signals (placed / construction-complete / demolished /
## state-changed / ticks-advanced) to this layer; the layer owns the visual nodes
## as its own children and reads live state from the BuildingRegistry autoload.
## Path-network updates stay in MapRoot (it owns PathSystem coordination).
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 5).

## Tint applied to a building sprite while it is still under construction.
const _SKELETON_MODULATE: Color = Color(0.75, 0.88, 1.0, 0.28)

var _building_sprites: Dictionary[String, Sprite2D] = {}
var _building_indicators: Dictionary[String, BuildingStatusIndicator] = {}


## Spawns the building sprite and, for buildings that construct or produce, a
## status indicator. Construction-stage buildings start tinted.
func add_building(building_id: String, type: int, tile: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(_building_texture_path(type))
	var tile_px: int = WorldGrid.TILE_SIZE
	sprite.position = Vector2(tile) * tile_px + Vector2(tile_px, tile_px) * 0.5
	sprite.z_index = 2

	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	if instance != null and instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
		sprite.modulate = _SKELETON_MODULATE
	_building_sprites[building_id] = sprite
	add_child(sprite)

	var build_time: int = BuildingRegistry.BUILD_TIME.get(type, 0)
	if build_time > 0 or BuildingRegistry.is_production_building(type):
		var indicator := BuildingStatusIndicator.new()
		indicator.position = sprite.position + Vector2(tile_px * 0.32, tile_px * 0.32)
		indicator.z_index = 3
		add_child(indicator)
		_building_indicators[building_id] = indicator
		refresh(building_id)


## Fades a finished building sprite from its construction tint to full color.
func complete_construction(building_id: String) -> void:
	var sprite: Sprite2D = _building_sprites.get(building_id)
	if sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Removes the building's sprite + indicator. Returns the building's tile so the
## caller can refresh the path network, or Vector2i(-1, -1) if it was unknown.
func remove_building(building_id: String) -> Vector2i:
	var tile := Vector2i(-1, -1)
	var sprite: Sprite2D = _building_sprites.get(building_id)
	if sprite != null:
		var tile_px: int = WorldGrid.TILE_SIZE
		tile = Vector2i((sprite.position - Vector2(tile_px, tile_px) * 0.5) / tile_px)
		sprite.queue_free()
		_building_sprites.erase(building_id)
	var indicator: BuildingStatusIndicator = _building_indicators.get(building_id)
	if indicator != null:
		indicator.queue_free()
		_building_indicators.erase(building_id)
	return tile


## Re-syncs every indicator from live BuildingRegistry state. Called each tick.
func refresh_all() -> void:
	for building_id: String in _building_indicators:
		refresh(building_id)


## Re-syncs one building's indicator from its live BuildingRegistry instance.
func refresh(building_id: String) -> void:
	var indicator: BuildingStatusIndicator = _building_indicators.get(building_id)
	if indicator == null:
		return
	var instance: BuildingRegistry.BuildingInstance = BuildingRegistry.get_building_instance(building_id)
	if instance == null:
		return

	if instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
		var progress: float = float(instance.accumulated_ticks) / float(instance.build_time) \
			if instance.build_time > 0 else 0.0
		indicator.set_construction_progress(progress)
		indicator.show()
		return

	# Show upgrade-install progress using the same construction ring.
	var player: PlayerCharacter = get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	if player != null \
			and player.get_active_action_id() == PlayerCharacter.ManualActionType.INSTALL_UPGRADE \
			and player.get_active_building_id() == building_id:
		indicator.set_construction_progress(player.get_action_progress())
		indicator.show()
		return

	# Show crafting progress on the bench storage building being used.
	if CraftingRegistry.is_crafting() and CraftingRegistry.get_crafting_building_id() == building_id:
		indicator.set_progress(CraftingRegistry.get_crafting_progress())
		indicator.show()
		return

	if not BuildingRegistry.is_production_building(instance.type):
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


func _building_has_valid_input(instance: BuildingRegistry.BuildingInstance) -> bool:
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	var inputs: Array = recipe.get("inputs", [])
	for input_spec: Dictionary in inputs:
		var resource_id: StringName = input_spec["resource_id"]
		var needed: float = input_spec.get("charge_cost", float(input_spec.get("quantity", 0)))
		if instance.input_buffer.get(resource_id, 0.0) < needed:
			return false
	return not inputs.is_empty()


func _building_texture_path(type: int) -> String:
	return BuildingRegistry.BUILDING_TEXTURES.get(type, "res://assets/art/tiles/bld_tile_storage.png")
