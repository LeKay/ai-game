class_name TextureFactory
## Stateless factory for procedurally generated textures and images.
##
## Centralises the small image-generation helpers that were previously duplicated
## across MapRoot, NpcOverlay and RouteLines. All methods are pure (no side effects,
## no engine state) and therefore deterministic and unit-testable.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 1).


## Returns an ImageTexture of a solid filled circle with the given radius and color.
## The image is sized radius*2 square; pixels outside the circle are transparent.
static func circle(radius: int, color: Color) -> ImageTexture:
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


## Returns a square Image filled with `color` and a 1px border tinted darker.
## Used for procedural terrain fallback tiles.
static func solid_tile(tile_px: int, color: Color) -> Image:
	var img := Image.create(tile_px, tile_px, false, Image.FORMAT_RGBA8)
	var border_c: Color = color.darkened(0.25)
	for x in range(tile_px):
		for y in range(tile_px):
			var is_edge: bool = x == 0 or x == tile_px - 1 or y == 0 or y == tile_px - 1
			img.set_pixel(x, y, border_c if is_edge else color)
	return img


## Returns a square highlight texture: translucent `fill` with a `border_px` thick
## `border` frame. Used for tile-selection highlights.
static func tile_highlight(size: int, fill: Color, border: Color, border_px: int = 2) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x: int in range(size):
		for y: int in range(size):
			var is_edge: bool = x < border_px or x >= size - border_px or y < border_px or y >= size - border_px
			img.set_pixel(x, y, border if is_edge else fill)
	return ImageTexture.create_from_image(img)
