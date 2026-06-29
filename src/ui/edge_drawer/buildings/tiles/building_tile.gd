class_name BuildingTile extends DrawerTile
## Concrete tile that represents a single placed building instance in the Buildings Drawer.
## Loads its icon, label, and state badge from BuildingRegistry on setup/refresh.

## Maps BuildingInstance.State + cycle flags to badge dot colours.
const STATE_COLORS: Dictionary = {
	"PRODUCING":    Color(0.298, 0.686, 0.314),  ## green
	"OPERATING":    Color(0.298, 0.686, 0.314),  ## green
	"BLOCKED":      Color(1.0, 0.757, 0.027),    ## yellow
	"STALLED":      Color(0.898, 0.239, 0.239),  ## red
	"CONSTRUCTING": Color(1.0, 0.596, 0.0),      ## orange
	"IDLE":         Color(0.6, 0.6, 0.6),         ## gray
}

var _building_id: String = ""


# --- Public API ---------------------------------------------------------------

## Populates the tile from the registry for the given building_id.
## Must be called after the tile has entered the scene tree.
func setup(building_id: String) -> void:
	_building_id = building_id
	var instance := BuildingRegistry.get_building_instance(building_id)
	if instance == null:
		set_label("???")
		return

	# Icon
	var tex := BuildingRegistry.get_building_texture(instance.type)
	if tex != null:
		set_icon_texture(tex)
	else:
		set_icon_glyph("🏗")

	# Label — custom name or default type name
	set_label(BuildingRegistry.get_building_display_name(building_id))

	# Construction state: dim tile and show progress ring placeholder
	if instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
		modulate = Color(1.0, 1.0, 1.0, 0.5)
		var total: int = instance.build_time
		var pct: float = float(instance.accumulated_ticks) / float(total) if total > 0 else 1.0
		set_progress(pct)
	else:
		modulate = Color.WHITE
		set_progress(-1.0)

	_apply_badge(instance)


## Refreshes the badge and construction state without rebuilding the full tile.
func refresh() -> void:
	if _building_id == "":
		return
	var instance := BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return

	if instance.state == BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
		modulate = Color(1.0, 1.0, 1.0, 0.5)
		var total: int = instance.build_time
		var pct: float = float(instance.accumulated_ticks) / float(total) if total > 0 else 1.0
		set_progress(pct)
	else:
		modulate = Color.WHITE
		set_progress(-1.0)

	_apply_badge(instance)


# --- Internals ----------------------------------------------------------------

func _get_state_key(instance: BuildingRegistry.BuildingInstance) -> String:
	match instance.state:
		BuildingRegistry.BuildingInstance.State.CONSTRUCTING:
			return "CONSTRUCTING"
		BuildingRegistry.BuildingInstance.State.OPERATING:
			if BuildingRegistry.is_production_building(instance.type):
				return "PRODUCING" if instance.cycle_running else "IDLE"
			return "OPERATING"
		BuildingRegistry.BuildingInstance.State.BLOCKED:
			return "BLOCKED"
		BuildingRegistry.BuildingInstance.State.DEMOLISHED:
			return "IDLE"
	return "IDLE"


func _apply_badge(instance: BuildingRegistry.BuildingInstance) -> void:
	var key := _get_state_key(instance)
	var color: Color = STATE_COLORS.get(key, Color.GRAY)
	set_badge("●", color)
