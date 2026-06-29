class_name RouteTile extends DrawerTile
## Tile widget that represents a single transport route inside TransportSection.
## Shows carrier glyph + item icon, a "From → To" label, and an items/day badge.
## Spec: design/gdd/buildings-drawer.md §5.1 B6

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the player taps this tile; parent should open RouteEditorView in edit mode.
signal edit_requested(route_id: StringName)

# ── State ─────────────────────────────────────────────────────────────────────

var _route_id: StringName = &""

# ── Public API ────────────────────────────────────────────────────────────────

## Populates all tile fields from [param route] and connects the press action.
func setup(route: LogisticsRoute) -> void:
	_route_id = route.id

	# ── Icon: item texture (or glyph fallback) ────────────────────────────────
	var item_id: StringName = route.source_item_id
	if item_id != &"":
		var tex: Texture2D = ResourceRegistry.get_icon_texture(item_id, 28)
		if tex != null:
			set_icon_texture(tex)
		else:
			set_icon_glyph(ResourceRegistry.get_glyph(item_id))
	else:
		set_icon_glyph("📦")

	# ── Label: throughput (x/day) or building names as fallback ──────────────
	if route.stats_data_available and route.stats_items_last_day > 0:
		set_label("%d/day" % route.stats_items_last_day)  # TODO: localize
	else:
		set_label("-/day")  # TODO: localize

	# ── Badge: hidden (throughput now shown in label) ─────────────────────────
	set_badge("", Color.WHITE)

	# ── State ─────────────────────────────────────────────────────────────────
	if not route.active:
		set_state(TileState.DISABLED)
	else:
		set_state(TileState.NORMAL)

	# ── Press → edit ─────────────────────────────────────────────────────────
	if pressed.is_connected(_on_pressed):
		pressed.disconnect(_on_pressed)
	pressed.connect(_on_pressed)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _short_name(building_id: StringName) -> String:
	if building_id == &"":
		return "?"  # TODO: localize
	var full: String = BuildingRegistry.get_building_display_name(str(building_id))
	# Truncate to 4 chars to keep the "A→B" label compact inside the tile.
	if full.length() > 4:
		return full.substr(0, 4)
	return full


func _on_pressed() -> void:
	edit_requested.emit(_route_id)
