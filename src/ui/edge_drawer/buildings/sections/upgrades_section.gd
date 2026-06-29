class_name UpgradesSection extends VBoxContainer
## Displays all available and active upgrades for a single building.
## Active upgrades (already installed) are shown first with a ✓ badge.
## Available upgrades follow — affordable ones are clickable; unaffordable ones
## are disabled with a cost tooltip.
## The section hides itself entirely when no upgrades exist for the building.
## Spec: design/gdd/buildings-drawer.md §5.1 B7

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the player clicks an affordable, non-active upgrade tile.
## Caller (BuildingDetailView / DrawerContent) is responsible for deducting
## resources and calling BuildingRegistry.install_upgrade().
signal upgrade_install_requested(building_id: String, upgrade_id: StringName)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_TEXT_DIM := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_HEADER   := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_SEPARATOR := Color(0.25, 0.26, 0.30, 1.0)

# ── Node refs ─────────────────────────────────────────────────────────────────

var _header: Label
var _flow: TileFlowContainer

# ── State ─────────────────────────────────────────────────────────────────────

var _building_id: String = ""

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

	# ── Separator ─────────────────────────────────────────────────────────────
	var sep := HSeparator.new()
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = COLOR_SEPARATOR
	sep_sb.content_margin_top    = 0
	sep_sb.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_sb)
	add_child(sep)

	# ── Section header ────────────────────────────────────────────────────────
	var pad_h := MarginContainer.new()
	pad_h.add_theme_constant_override("margin_left",  12)
	pad_h.add_theme_constant_override("margin_right", 12)
	pad_h.add_theme_constant_override("margin_top",    8)
	pad_h.add_theme_constant_override("margin_bottom", 0)
	add_child(pad_h)

	_header = Label.new()
	_header.name = "UpgradesHeader"
	_header.text = "Upgrades"  # TODO: localize
	_header.add_theme_font_size_override("font_size", 11)
	_header.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	pad_h.add_child(_header)

	# ── Tile flow ─────────────────────────────────────────────────────────────
	_flow = TileFlowContainer.new()
	_flow.name = "UpgradesFlow"
	add_child(_flow)


# ── Public API ────────────────────────────────────────────────────────────────

## Stores the building id and populates the tile flow for the first time.
func setup(building_id: String) -> void:
	_building_id = building_id
	refresh()


## Re-reads upgrade state from BuildingRegistry and rebuilds all tiles.
## Call this after any install or when the view is brought back into focus.
func refresh() -> void:
	_flow.clear_tiles()

	if _building_id == "":
		visible = false
		return

	var available: Array = BuildingRegistry.get_available_upgrades(_building_id)

	# Separate into active vs. non-active.
	var active_defs:    Array = []
	var inactive_defs:  Array = []
	for def: Dictionary in available:
		var uid: StringName = def.get(&"id", &"")
		if BuildingRegistry.has_upgrade(_building_id, uid):
			active_defs.append(def)
		else:
			inactive_defs.append(def)

	if active_defs.is_empty() and inactive_defs.is_empty():
		visible = false
		return

	visible = true

	# Active upgrades first (already installed — disabled, green badge).
	for def: Dictionary in active_defs:
		_add_upgrade_tile(def, true)

	# Inactive upgrades next (available, may or may not be affordable).
	for def: Dictionary in inactive_defs:
		_add_upgrade_tile(def, false)


## Returns true when the section should be shown (has at least one upgrade entry).
func is_visible_section() -> bool:
	if _building_id == "":
		return false
	var available: Array = BuildingRegistry.get_available_upgrades(_building_id)
	return not available.is_empty()


# ── Private helpers ───────────────────────────────────────────────────────────

## Creates and adds a single UpgradeTile to the flow.
func _add_upgrade_tile(def: Dictionary, is_active: bool) -> void:
	var uid: StringName      = def.get(&"id", &"")
	var display_name: String = def.get(&"display_name", str(uid))  # TODO: localize
	var cost_dict: Dictionary = def.get(&"cost", {})

	var affordable: bool = is_active or _can_afford(cost_dict)

	var tile := UpgradeTile.new()
	if not is_active:
		tile.upgrade_requested.connect(
			func(upgrade_id: StringName) -> void:
				upgrade_install_requested.emit(_building_id, upgrade_id))
	_flow.add_tile(tile)
	tile.setup(uid, is_active, affordable, display_name, cost_dict)


## Returns true if the global inventory holds at least the required quantities.
func _can_afford(cost_dict: Dictionary) -> bool:
	for res_id: StringName in cost_dict:
		var required: int = cost_dict[res_id]
		if InventorySystem.get_global_quantity(res_id) < required:
			return false
	return true
