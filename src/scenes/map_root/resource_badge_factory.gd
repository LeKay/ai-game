class_name ResourceBadgeFactory
## Builds the world-space resource badge icon nodes (black backdrop + scaled
## resource sprite) and their deterministic in-tile layout.
##
## Extracted from MapRoot (Phase 5). Pure construction: returns unparented nodes,
## so the caller owns positioning, z-index, parenting, the `_resource_icons`
## bookkeeping and any pop-in tween (those need MapRoot's Node/scene context).
## Previously the icon construction was duplicated between MapRoot._spawn_badge and
## MapRoot._make_resource_icon_node.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 5).

## Icon size as fraction of tile size, indexed by (resource_count - 1), capped at 4.
const ICON_SCALE_BY_COUNT: Array[float] = [0.45, 0.40, 0.35, 0.31]
## Fallback resource badge texture size as a fraction of tile size.
const _RESOURCE_ICON_SCALE: float = 0.55


## Builds an icon Node2D (black circular backdrop + scaled resource sprite),
## unparented and centered at its own origin. Caller sets position/z-index/parent.
static func build_icon_node(res_id: StringName, icon_px: int) -> Node2D:
	var icon_node := Node2D.new()

	var backdrop := Sprite2D.new()
	backdrop.texture = TextureFactory.circle(roundi(icon_px * 0.55), Color(0.0, 0.0, 0.0, 0.30))
	icon_node.add_child(backdrop)

	var spr := Sprite2D.new()
	spr.texture = ResourceRegistry.get_icon_texture(res_id, roundi(float(icon_px) * 0.5))
	var tex_size: Vector2 = spr.texture.get_size()
	spr.scale = Vector2(float(icon_px) / tex_size.x, float(icon_px) / tex_size.y)
	icon_node.add_child(spr)

	return icon_node


## Resource world-badge texture (data-driven via ResourceRegistry), with a colored
## circle fallback sized for the badge.
static func world_texture(res_id: StringName) -> Texture2D:
	var radius: int = roundi(WorldGrid.TILE_SIZE * _RESOURCE_ICON_SCALE) / 2
	return ResourceRegistry.get_world_icon_texture(res_id, radius)


## Icon pixel size for a badge holding `count` resources (capped at 4 entries).
static func icon_px_for_count(count: int) -> int:
	var scale: float = ICON_SCALE_BY_COUNT[mini(count - 1, ICON_SCALE_BY_COUNT.size() - 1)]
	return roundi(WorldGrid.TILE_SIZE * scale)


## Returns `count` evenly-spaced offsets within a tile arranged in a circle.
## Deterministic: same tile+seed_offset always produces the same layout. A random
## angle offset is applied so icons don't always face the same direction.
## (`_icon_px` is accepted for call-site compatibility but unused.)
static func icon_positions(tile: Vector2i, count: int, _icon_px: int, seed_offset: int = 0) -> Array:
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
