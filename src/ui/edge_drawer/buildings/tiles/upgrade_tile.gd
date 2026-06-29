class_name UpgradeTile extends DrawerTile
## Tile widget representing a single building upgrade inside UpgradesSection.
## Shows the upgrade name, a ✓ badge when active, and a cost tooltip when not affordable.
## Spec: design/gdd/buildings-drawer.md §5.1 B7

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the player clicks an affordable, non-active upgrade tile.
signal upgrade_requested(upgrade_id: StringName)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_BADGE_ACTIVE := Color(0.298, 0.686, 0.314)  # green check
const DEFAULT_ICON := "⚒"

# ── State ─────────────────────────────────────────────────────────────────────

var _upgrade_id: StringName = &""
var _is_affordable: bool = false
var _is_active: bool = false


# ── Public API ────────────────────────────────────────────────────────────────

## Configures the tile for the given upgrade.
## [param upgrade_id]   — the upgrade's StringName id (from BuildingRegistry.BUILDING_UPGRADES)
## [param is_active]    — true if the upgrade is already installed on the building
## [param is_affordable]— true if the player has sufficient resources to install it
## [param display_name] — human-readable upgrade name  # TODO: localize
## [param cost_dict]    — Dictionary {resource_id: quantity} used for the tooltip
func setup(
		upgrade_id: StringName,
		is_active: bool,
		is_affordable: bool,
		display_name: String,
		cost_dict: Dictionary) -> void:
	_upgrade_id   = upgrade_id
	_is_active    = is_active
	_is_affordable = is_affordable

	set_icon_glyph(DEFAULT_ICON)
	set_label(display_name)

	if is_active:
		# Already installed — show green checkmark badge, disable interaction.
		set_badge("✓", COLOR_BADGE_ACTIVE)
		set_state(TileState.NORMAL)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif is_affordable:
		# Available and affordable — normal clickable tile.
		set_badge("", Color.WHITE)
		set_state(TileState.NORMAL)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = ""
	else:
		# Available but not affordable — disabled with cost tooltip.
		set_badge("", Color.WHITE)
		set_state(TileState.DISABLED)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = _build_cost_tooltip(cost_dict)

	# Connect click only once, guard with _is_affordable at emit time.
	if not pressed.is_connected(_on_tile_pressed):
		pressed.connect(_on_tile_pressed)


# ── Handlers ──────────────────────────────────────────────────────────────────

func _on_tile_pressed() -> void:
	if _is_active or not _is_affordable:
		return
	upgrade_requested.emit(_upgrade_id)


# ── Helpers ───────────────────────────────────────────────────────────────────

## Builds a human-readable cost string, e.g. "Requires: 10× Wood, 5× Stone".
func _build_cost_tooltip(cost_dict: Dictionary) -> String:
	if cost_dict.is_empty():
		return ""
	var parts: Array[String] = []
	for res_id: StringName in cost_dict:
		var qty: int = cost_dict[res_id]
		parts.append("%d× %s" % [qty, str(res_id).capitalize()])  # TODO: localize
	return "Requires: " + ", ".join(parts)  # TODO: localize
