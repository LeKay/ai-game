class_name StyleFactory
## Stateless builders for the repeated StyleBoxFlat / control constructions that
## were duplicated across UI panels and grids.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 4).


## Builds a horizontal separator styled with a flat colour bar (no content margins).
## Caller is responsible for adding it to a parent.
static func separator(color: Color = UiPalette.SEPARATOR) -> HSeparator:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", style)
	return sep


## Builds an icon-block style: filled background with a coloured border.
static func block(bg: Color, border: Color, border_width: int = 1, corner_radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style
