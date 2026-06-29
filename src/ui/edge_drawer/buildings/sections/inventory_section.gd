class_name InventorySection extends VBoxContainer
## Displays the contents of a storage building's InventoryContainer
## inside the Buildings Drawer.
## Spec: design/gdd/buildings-drawer.md §5.1 B4

# ── Signals ───────────────────────────────────────────────────────────────────

## Forwarded from child ItemTiles — emitted when the player taps a stored item.
signal storage_drag_started(resource_id: StringName, container_id: StringName, tile_pos: Vector2i)

# ── Constants ─────────────────────────────────────────────────────────────────

const COLOR_TEXT     := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_TEXT_DIM := Color(0.55, 0.55, 0.60, 1.0)

# ── Node refs ─────────────────────────────────────────────────────────────────

var _flow: TileFlowContainer
var _empty_label: Label

# ── State ─────────────────────────────────────────────────────────────────────

var _building_id: String = ""
var _container_id: StringName = &""
## Cache of active ItemTiles keyed by resource_id for efficient refresh.
var _item_tiles: Dictionary[StringName, ItemTile] = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

	# ── Header ────────────────────────────────────────────────────────────────
	var pad_h := MarginContainer.new()
	pad_h.add_theme_constant_override("margin_left",   12)
	pad_h.add_theme_constant_override("margin_right",  8)
	pad_h.add_theme_constant_override("margin_top",    6)
	pad_h.add_theme_constant_override("margin_bottom", 4)
	add_child(pad_h)

	var section_label := Label.new()
	section_label.name = "SectionLabel"
	section_label.text = "Storage"  # TODO: localize
	section_label.add_theme_font_size_override("font_size", 12)
	section_label.add_theme_color_override("font_color", COLOR_TEXT)
	pad_h.add_child(section_label)

	# ── Tile flow ─────────────────────────────────────────────────────────────
	_flow = TileFlowContainer.new()
	_flow.name = "TileFlow"
	add_child(_flow)

	# ── Empty state label ─────────────────────────────────────────────────────
	_empty_label = Label.new()
	_empty_label.name = "EmptyLabel"
	_empty_label.text = "Empty"  # TODO: localize
	_empty_label.add_theme_font_size_override("font_size", 11)
	_empty_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false

	var pad_e := MarginContainer.new()
	pad_e.add_theme_constant_override("margin_left",   12)
	pad_e.add_theme_constant_override("margin_right",  12)
	pad_e.add_theme_constant_override("margin_top",    4)
	pad_e.add_theme_constant_override("margin_bottom", 8)
	pad_e.add_child(_empty_label)
	add_child(pad_e)


# ── Public API ────────────────────────────────────────────────────────────────

## Loads storage data for [param building_id] and builds the initial tile layout.
func setup(building_id: String) -> void:
	_building_id = building_id
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance != null:
		_container_id = instance.assigned_container_id
	_rebuild_tiles()
	# Subscribe to live inventory changes so the display tracks every consume/deposit.
	if not InventorySystem.storage_changed.is_connected(_on_storage_changed):
		InventorySystem.storage_changed.connect(_on_storage_changed)


## Refreshes item counts from the InventorySystem container — call on tick advance
## or when [signal InventorySystem.storage_changed] fires for [member _container_id].
func refresh() -> void:
	if _container_id == &"":
		return
	var container: InventoryContainer = InventorySystem.get_container(_container_id)
	if container == null:
		return

	# Collect current non-empty resources.
	var current: Dictionary[StringName, int] = {}
	for slot: InventorySlot in container.slots:
		if slot.resource_id != &"" and slot.quantity > 0:
			current[slot.resource_id] = current.get(slot.resource_id, 0) + slot.quantity

	# Detect whether tile set needs a full rebuild (new or removed resources).
	var existing_keys: Array[StringName] = _item_tiles.keys()
	var current_keys: Array[StringName] = current.keys()
	existing_keys.sort()
	current_keys.sort()
	if existing_keys != current_keys:
		_rebuild_tiles_from(current)
		return

	# Fast path: only update quantities.
	for res_id: StringName in _item_tiles:
		_item_tiles[res_id].update_quantity(current.get(res_id, 0))

	_empty_label.visible = current.is_empty()


# ── Private helpers ───────────────────────────────────────────────────────────

## Full rebuild — used on first load and when the resource set changes.
func _rebuild_tiles() -> void:
	if _container_id == &"":
		return
	var container: InventoryContainer = InventorySystem.get_container(_container_id)
	if container == null:
		return

	var current: Dictionary[StringName, int] = {}
	for slot: InventorySlot in container.slots:
		if slot.resource_id != &"" and slot.quantity > 0:
			current[slot.resource_id] = current.get(slot.resource_id, 0) + slot.quantity
	_rebuild_tiles_from(current)


## Creates ItemTiles from a pre-aggregated {resource_id → quantity} dict.
func _rebuild_tiles_from(contents: Dictionary[StringName, int]) -> void:
	_flow.clear_tiles()
	_item_tiles.clear()

	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	var tile_pos: Vector2i = instance.tile if instance != null else Vector2i.ZERO

	for res_id: StringName in contents:
		var tile := ItemTile.new()
		tile.storage_drag_started.connect(_on_storage_drag_started)
		_flow.add_tile(tile)
		tile.setup(res_id, contents[res_id], "storage", str(_container_id), tile_pos)
		_item_tiles[res_id] = tile

	_empty_label.visible = contents.is_empty()


# ── Signal forwarding ─────────────────────────────────────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if InventorySystem.storage_changed.is_connected(_on_storage_changed):
			InventorySystem.storage_changed.disconnect(_on_storage_changed)


func _on_storage_changed(container_id: StringName) -> void:
	if container_id == _container_id:
		refresh()


func _on_storage_drag_started(res_id: StringName, cid: StringName, tp: Vector2i) -> void:
	storage_drag_started.emit(res_id, cid, tp)
