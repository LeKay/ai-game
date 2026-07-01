class_name RouteEditorView extends Control
## Thin wrapper around the existing RouteEditor that embeds it inside the Buildings Drawer.
## Forwards RouteEditor signals upward and exposes a clean setup API so TransportSection
## can open the editor in "new route" or "edit existing route" mode without knowing
## RouteEditor internals.
## Spec: design/gdd/buildings-drawer.md §5.1 B6

# ── Signals ───────────────────────────────────────────────────────────────────

## Forwarded from RouteEditor.save_requested — player confirmed a new route.
signal route_create_requested(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName)
## Forwarded from RouteEditor.update_requested — player saved edits to an existing route.
signal route_update_requested(route_id: StringName, changes: Dictionary)
## Forwarded from RouteEditor.delete_requested — player confirmed route deletion.
signal route_delete_requested(route_id: StringName)
## Forwarded from RouteEditor.cancel_requested — player dismissed the editor.
signal cancelled()
## Forwarded from RouteEditor.map_select_requested — player wants to pick a building on the map.
signal map_select_requested(step: String)
## Forwarded from RouteEditor.carrier_hover_changed — drives the map route-line filter.
signal carrier_hover_changed(npc_id: StringName)

# ── Node refs ─────────────────────────────────────────────────────────────────

var _editor: RouteEditor

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   12)
	margin.add_theme_constant_override("margin_right",  12)
	margin.add_theme_constant_override("margin_top",     8)
	margin.add_theme_constant_override("margin_bottom",  8)
	add_child(margin)

	_editor = RouteEditor.new()
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_editor)
	_connect_editor_signals()


# ── Public API ────────────────────────────────────────────────────────────────

## Opens the editor for a brand-new route with [param building_id] pre-filled.
## [param role] must be "from" (building is the source) or "to" (building is the destination).
func setup(building_id: String, role: String) -> void:
	var from_id: StringName = &""
	var to_id:   StringName = &""
	if role == "from":
		from_id = StringName(building_id)
	elif role == "to":
		to_id = StringName(building_id)
	_editor.init_new(from_id, to_id)


## Opens the editor in edit mode for an existing [param route].
func setup_edit(route: LogisticsRoute) -> void:
	_editor.init_existing(route, false)


## Completes a map-select round trip: forwards the result into the inner RouteEditor.
## Called by TransportSection after the player picks a building on the map.
func resume_map_select(step: String, building_id: StringName) -> void:
	_editor.resume_map_select(step, building_id)


# ── Signal wiring ─────────────────────────────────────────────────────────────

func _connect_editor_signals() -> void:
	_editor.save_requested.connect(
		func(from_id: StringName, to_id: StringName, npc_id: StringName, item_id: StringName) -> void:
			route_create_requested.emit(from_id, to_id, npc_id, item_id)
	)
	_editor.update_requested.connect(
		func(route_id: StringName, changes: Dictionary) -> void:
			route_update_requested.emit(route_id, changes)
	)
	_editor.delete_requested.connect(
		func() -> void:
			# RouteEditor.delete_requested carries no payload — the route ID is tracked by the
			# editor's internal _route reference. We surface the ID via the editor's _route field.
			# Access it safely; if _route is null, the signal is a no-op.
			var route: LogisticsRoute = _editor._route
			if route != null:
				route_delete_requested.emit(route.id)
	)
	_editor.cancel_requested.connect(func() -> void: cancelled.emit())
	_editor.map_select_requested.connect(func(step: String) -> void: map_select_requested.emit(step))
	_editor.carrier_hover_changed.connect(func(npc_id: StringName) -> void: carrier_hover_changed.emit(npc_id))
	_editor.edit_requested.connect(
		func() -> void:
			# edit_requested on a locked card means "switch this card to editing mode".
			# In the embedded context we just unlock the editor in place.
			var route: LogisticsRoute = _editor._route
			if route != null:
				_editor.init_existing(route, false)
	)
