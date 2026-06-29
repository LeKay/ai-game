class_name NpcsDrawerContent extends DrawerContentBase
## Content node for the NPCs (Workers) Drawer.
## Manages a two-view stack — NpcListView ↔ NpcDetailView — exactly like BuildingsDrawerContent.
##
## See: buildings_drawer_content.gd (structural template).

## Emitted when the tab badge text / colour should update (number of recruited workers).
signal badge_updated(badge_text: String, badge_color: Color)
## Emitted when the focused worker changes: the detail view's npc_id, or &"" when back on the list.
## Drives the map route-line filter (highlight the focused worker's routes).
signal npc_focus_changed(npc_id: StringName)

const BADGE_COLOR := Color(0.298, 0.686, 0.314)   ## green — matches buildings badge

var _list_view:    NpcListView
var _detail_view:  NpcDetailView
var _current_view: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_list_view = NpcListView.new()
	_list_view.name = "NpcListView"
	_list_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_list_view)
	_list_view.npc_tile_pressed.connect(_on_npc_pressed)
	_list_view.close_pressed.connect(func() -> void: request_close.emit())

	_detail_view = NpcDetailView.new()
	_detail_view.name = "NpcDetailView"
	_detail_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_view.visible = false
	add_child(_detail_view)
	_detail_view.back_pressed.connect(func() -> void: _show_view(_list_view))
	_detail_view.close_pressed.connect(func() -> void: request_close.emit())

	_show_view(_list_view)

	var npc_sys: Node = NPCSystem
	if npc_sys != null:
		npc_sys.npc_recruited.connect(_on_roster_changed.unbind(2))
		npc_sys.npc_removed.connect(_on_roster_changed.unbind(1))
		npc_sys.npc_released.connect(_on_roster_changed.unbind(1))
		npc_sys.npc_assigned.connect(_on_roster_changed.unbind(2))
		npc_sys.npc_returned_home.connect(_on_roster_changed.unbind(1))
		npc_sys.npc_renamed.connect(_on_roster_changed.unbind(2))
		npc_sys.npc_xp_gained.connect(_on_roster_changed.unbind(4))
		npc_sys.npc_leveled_up.connect(_on_roster_changed.unbind(2))
	_emit_badge()


# --- DrawerContentBase API ----------------------------------------------------

func refresh() -> void:
	_list_view.refresh()
	if _current_view == _detail_view:
		_detail_view.refresh()
	_emit_badge()


func on_drawer_opened() -> void:
	_list_view.refresh()
	_emit_badge()


func on_drawer_closed() -> void:
	_detail_view.cancel_editors()
	if _current_view != _list_view:
		_show_view(_list_view)


func wants_escape_handled() -> bool:
	return _current_view == _detail_view and _detail_view.wants_escape()


func handle_escape() -> bool:
	if _current_view == _detail_view:
		return _detail_view.handle_escape()
	return false


# --- Public API ---------------------------------------------------------------

## Opens (or switches to) the detail view for the given worker.
func open_for_npc(npc_id: StringName) -> void:
	_detail_view.setup(npc_id)
	_show_view(_detail_view)
	npc_focus_changed.emit(npc_id)


# --- View management ----------------------------------------------------------

func _show_view(view: Control) -> void:
	if _current_view == view:
		return
	if _current_view == _detail_view:
		_detail_view.cancel_editors()
	if _current_view != null:
		_current_view.visible = false
	_current_view = view
	if _current_view != null:
		_current_view.visible = true
	if view == _list_view:
		_list_view.refresh()
		npc_focus_changed.emit(&"")


# --- Badge --------------------------------------------------------------------

func _on_roster_changed() -> void:
	if _current_view == _list_view:
		_list_view.refresh()
	_emit_badge()


func _emit_badge() -> void:
	var npc_sys: Node = NPCSystem
	var count: int = npc_sys.all_npcs.size() if npc_sys != null else 0
	var text  := str(count) if count > 0 else ""
	badge_updated.emit(text, BADGE_COLOR)


func _on_npc_pressed(npc_id: StringName) -> void:
	_detail_view.setup(npc_id)
	_show_view(_detail_view)
	npc_focus_changed.emit(npc_id)
