class_name ProgressionTreeScreen extends CanvasLayer
## Player-facing Progression Tree overlay. Renders the ProgressionSystem node graph as
## a radial, pannable/zoomable tree and reports node clicks back to the system. It is a
## pure renderer of unlock state (see .claude/rules/ui-code.md) — clicking a node calls
## ProgressionSystem.unlock(); the resulting node_unlocked signal drives the reveal.
##
## STEP 1: graph visualization + dynamic reveal only. No content is gated yet.
## Pan/zoom is applied directly to the world Node2D transform (a Camera2D does not affect
## nodes inside a CanvasLayer). The UX spec will refine art/feel before final polish.
##
## See design/quick-specs/progression-tree-2026-06-19.md (Visual Implementation).

const EDGE_WIDTH: float = 3.0
const EDGE_COLOR_UNLOCKED := Color("#C8C0A8")
const EDGE_COLOR_PENDING := Color(0.45, 0.45, 0.5, 0.7)
## Synthetic root connectors (Hearth → a node with only cross-category prerequisites)
## are drawn thinner and dimmer so every strand visibly starts at the center without
## competing with the real same-category edges.
const CONNECTOR_WIDTH: float = 1.6
const CONNECTOR_COLOR := Color(0.5, 0.5, 0.55, 0.4)
const BG_COLOR := Color(0.05, 0.06, 0.08, 0.92)
const ZOOM_STEP: float = 1.1

## Emitted when the overlay opens / closes (any path: button, Esc). Lets the HUD hide its edge
## drawers while the full-screen tree is up.
signal opened()
signal closed()

## Fill color per branch — drives node + unlocked-edge tinting.
const BRANCH_COLORS: Dictionary = {
	&"core": Color("#B5894E"),
	&"food": Color("#6FA84A"),
	&"materials": Color("#8A6A45"),
	&"crafting": Color("#5A7FA8"),
	&"textiles": Color("#A85A9C"),
}

var _world: Node2D
var _edges_root: Node2D
var _nodes_root: Node2D
var _background: ColorRect
var _title_label: Label
var _points_label: Label
## Transient feedback shown when an unlock is rejected for lack of progression points.
var _hint_label: Label
var _hint_tween: Tween

var _node_buttons: Dictionary = {}   # StringName -> ProgressionNodeButton
var _edge_records: Array[Dictionary] = []  # { line, from, to, from_pos, to_pos }
var _visible_nodes: Dictionary = {}  # StringName -> true (currently revealed)

var _panning: bool = false
var _did_initial_center: bool = false


func _ready() -> void:
	layer = 20  # above the HUD (layer 10)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while the game is paused
	_build_ui()
	_build_graph()
	if not ProgressionSystem.node_unlocked.is_connected(_on_node_unlocked):
		ProgressionSystem.node_unlocked.connect(_on_node_unlocked)
	if not ProgressionSystem.points_changed.is_connected(_on_points_changed):
		ProgressionSystem.points_changed.connect(_on_points_changed)
	_on_points_changed(ProgressionSystem.progression_points)


func _exit_tree() -> void:
	if ProgressionSystem.node_unlocked.is_connected(_on_node_unlocked):
		ProgressionSystem.node_unlocked.disconnect(_on_node_unlocked)
	if ProgressionSystem.points_changed.is_connected(_on_points_changed):
		ProgressionSystem.points_changed.disconnect(_on_points_changed)


# --- Open / close ------------------------------------------------------------

func open() -> void:
	visible = true
	_refresh_all(false)
	if not _did_initial_center:
		_center_on_root()
		_did_initial_center = true
	opened.emit()


func close() -> void:
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = BG_COLOR
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_background.gui_input.connect(_on_background_gui_input)
	add_child(_background)

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	_edges_root = Node2D.new()
	_edges_root.name = "Edges"
	_world.add_child(_edges_root)

	_nodes_root = Node2D.new()
	_nodes_root.name = "Nodes"
	_world.add_child(_nodes_root)

	_build_top_bar()
	_build_hint_label()


func _build_hint_label() -> void:
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.offset_top = 56
	_hint_label.offset_bottom = 84
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color("#E86A5A"))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = false
	add_child(_hint_label)


func _build_top_bar() -> void:
	var bar := Control.new()
	bar.name = "TopBar"
	bar.anchor_right = 1.0
	bar.offset_bottom = 44
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.1, 0.1, 0.12, 0.9)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bar_bg)

	_title_label = Label.new()
	_title_label.text = "Progression Tree"
	_title_label.position = Vector2(16, 0)
	_title_label.offset_bottom = 44
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color("#F0EDE6"))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)

	_points_label = Label.new()
	_points_label.name = "PointsLabel"
	_points_label.text = "✦ 0"
	_points_label.tooltip_text = "Progression points — spend 1 to unlock a node"
	_points_label.anchor_left = 1.0
	_points_label.anchor_right = 1.0
	_points_label.offset_left = -150
	_points_label.offset_right = -64
	_points_label.offset_bottom = 44
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_points_label.add_theme_font_size_override("font_size", 18)
	_points_label.add_theme_color_override("font_color", Color("#E8C15A"))
	_points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_points_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = "Close (Esc)"
	close_btn.custom_minimum_size = Vector2(40, 32)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -52
	close_btn.offset_top = 6
	close_btn.offset_right = -12
	close_btn.offset_bottom = 38  # 6 + 32 (min height); without this the offset-derived height is negative
	close_btn.pressed.connect(close)
	bar.add_child(close_btn)


# --- Graph construction ------------------------------------------------------

func _build_graph() -> void:
	# Edges first so they render under the node buttons. Cross-category edges are
	# intentionally NOT drawn — the dependency still exists in ProgressionSystem (it
	# drives reveal/unlock), it is just kept invisible so each strand stays tidy.
	for edge: Dictionary in ProgressionSystem.get_edges():
		if _is_drawable_edge(edge["from"], edge["to"]):
			_add_edge_record(edge["from"], edge["to"], false)

	# Nodes whose every prerequisite is cross-category have no visible parent after the
	# filter above. Per design, connect each to the central Hearth with a subtle
	# connector so all four strands visibly originate at the center.
	for node_id: StringName in ProgressionSystem.get_all_node_ids():
		var pn: ProgressionTreeNode = ProgressionSystem.get_progression_node(node_id)
		if pn.branch == ProgressionSystem.CORE_BRANCH or pn.prerequisites.is_empty():
			continue
		if not _has_drawable_parent(node_id):
			_add_edge_record(ProgressionSystem.ROOT_NODE_ID, node_id, true)

	for node_id: StringName in ProgressionSystem.get_all_node_ids():
		var pn: ProgressionTreeNode = ProgressionSystem.get_progression_node(node_id)
		var btn := ProgressionNodeButton.new()
		_nodes_root.add_child(btn)
		btn.setup(node_id, pn.display_name, pn.icon, _branch_color(pn.branch))
		# Tooltip lists exactly what this node unlocks (data-driven from ProgressionSystem).
		btn.tooltip_text = ProgressionSystem.get_node_unlock_description(node_id)
		# Center the node button on its computed position.
		btn.position = ProgressionSystem.get_node_position(node_id) - ProgressionNodeButton.NODE_SIZE * 0.5
		btn.visible = false
		btn.node_clicked.connect(_on_node_clicked)
		_node_buttons[node_id] = btn


## Creates a Line2D + edge record (hidden until refreshed). `is_connector` marks a
## synthetic Hearth→orphan link, which is styled thinner/dimmer.
func _add_edge_record(from_id: StringName, to_id: StringName, is_connector: bool) -> void:
	var line := Line2D.new()
	line.width = CONNECTOR_WIDTH if is_connector else EDGE_WIDTH
	line.default_color = CONNECTOR_COLOR if is_connector else EDGE_COLOR_PENDING
	line.antialiased = true
	line.visible = false
	_edges_root.add_child(line)
	_edge_records.append({
		"line": line,
		"from": from_id,
		"to": to_id,
		"from_pos": ProgressionSystem.get_node_position(from_id),
		"to_pos": ProgressionSystem.get_node_position(to_id),
		"connector": is_connector,
	})


func _branch_color(branch: StringName) -> Color:
	return BRANCH_COLORS.get(branch, Color(0.4, 0.45, 0.5))


## True if the node has at least one prerequisite whose edge would be drawn (same
## category, or a core→category link). False means it is an orphan after filtering.
func _has_drawable_parent(node_id: StringName) -> bool:
	for prereq: StringName in ProgressionSystem.get_progression_node(node_id).prerequisites:
		if _is_drawable_edge(prereq, node_id):
			return true
	return false


## An edge is drawn only within a single category, or when it joins the central core to
## a category root. Edges between two different (non-core) categories are suppressed so
## the graph reads as clean radial strands; the prerequisite still gates logically.
func _is_drawable_edge(from_id: StringName, to_id: StringName) -> bool:
	var a: StringName = ProgressionSystem.get_progression_node(from_id).branch
	var b: StringName = ProgressionSystem.get_progression_node(to_id).branch
	if a == b:
		return true
	return a == ProgressionSystem.CORE_BRANCH or b == ProgressionSystem.CORE_BRANCH


# --- State refresh + reveal --------------------------------------------------

## Re-syncs every node/edge to the current ProgressionSystem state. When `animate` is
## true, nodes/edges that became visible since the last refresh fade/grow in.
func _refresh_all(animate: bool) -> void:
	for node_id: StringName in _node_buttons:
		var btn: ProgressionNodeButton = _node_buttons[node_id]
		var now_visible: bool = ProgressionSystem.is_visible(node_id)
		var was_visible: bool = _visible_nodes.has(node_id)
		btn.set_state(_state_for(node_id))
		btn.visible = now_visible
		if now_visible and not was_visible and animate:
			_play_node_reveal(btn)

	for rec: Dictionary in _edge_records:
		_refresh_edge(rec, animate)

	_visible_nodes.clear()
	for node_id: StringName in _node_buttons:
		if ProgressionSystem.is_visible(node_id):
			_visible_nodes[node_id] = true


func _state_for(node_id: StringName) -> ProgressionNodeButton.State:
	if ProgressionSystem.is_unlocked(node_id):
		return ProgressionNodeButton.State.UNLOCKED
	if ProgressionSystem.is_available(node_id):
		return ProgressionNodeButton.State.AVAILABLE
	return ProgressionNodeButton.State.LOCKED


## An edge is shown once both its endpoints are visible. It is tinted by whether its
## target is unlocked (solid branch tone) or still pending (dim).
func _refresh_edge(rec: Dictionary, animate: bool) -> void:
	var line: Line2D = rec["line"]
	var from_id: StringName = rec["from"]
	var to_id: StringName = rec["to"]
	var should_show: bool = ProgressionSystem.is_visible(from_id) and ProgressionSystem.is_visible(to_id)
	var was_shown: bool = line.visible

	if not should_show:
		line.visible = false
		return

	var target_unlocked: bool = ProgressionSystem.is_unlocked(to_id)
	if rec.get("connector", false):
		# Connectors stay subtle in every state — they are layout aids, not strand links.
		line.default_color = CONNECTOR_COLOR
	else:
		line.default_color = _branch_color(ProgressionSystem.get_progression_node(to_id).branch) \
				if target_unlocked else EDGE_COLOR_PENDING
	line.visible = true

	if not was_shown and animate:
		_play_edge_reveal(rec)
	else:
		line.clear_points()
		line.add_point(rec["from_pos"])
		line.add_point(rec["to_pos"])


func _play_node_reveal(btn: ProgressionNodeButton) -> void:
	btn.modulate.a = 0.0
	btn.scale = Vector2(0.85, 0.85)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(btn, "modulate:a", 1.0, ProgressionSystem.reveal_anim_duration)
	tween.tween_property(btn, "scale", Vector2.ONE, ProgressionSystem.reveal_anim_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Animates an edge "growing" from its prerequisite toward the new node.
func _play_edge_reveal(rec: Dictionary) -> void:
	var line: Line2D = rec["line"]
	var from_pos: Vector2 = rec["from_pos"]
	var to_pos: Vector2 = rec["to_pos"]
	line.clear_points()
	line.add_point(from_pos)
	line.add_point(from_pos)
	var tween := create_tween()
	tween.tween_method(
		func(t: float) -> void:
			line.set_point_position(1, from_pos.lerp(to_pos, t)),
		0.0, 1.0, ProgressionSystem.reveal_anim_duration)


# --- Input: node clicks + pan/zoom -------------------------------------------

func _on_node_clicked(node_id: StringName) -> void:
	# unlock() returns false when the node is already unlocked, not yet available, or
	# the player cannot afford it. Only the affordability case warrants feedback — an
	# available node the player simply lacks the points for.
	if ProgressionSystem.unlock(node_id):  # node_unlocked signal triggers the reveal
		return
	if ProgressionSystem.is_available(node_id) and not ProgressionSystem.can_afford(node_id):
		var cost: int = ProgressionSystem.get_node_cost(node_id)
		_flash_hint("Need %d progression point%s" % [cost, "" if cost == 1 else "s"])


func _on_node_unlocked(_node_id: StringName) -> void:
	_refresh_all(true)


func _on_points_changed(total: int) -> void:
	if _points_label != null:
		_points_label.text = "✦ %d" % total


## Briefly fades a centered message in/out near the top bar to explain a rejected unlock.
func _flash_hint(text: String) -> void:
	if _hint_label == null:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_label.text = text
	_hint_label.modulate.a = 0.0
	_hint_label.visible = true
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint_label, "modulate:a", 1.0, 0.15)
	_hint_tween.tween_interval(1.4)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 0.4)
	_hint_tween.tween_callback(func() -> void: _hint_label.visible = false)


func _on_background_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(_background.get_local_mouse_position(), ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(_background.get_local_mouse_position(), 1.0 / ZOOM_STEP)
		return

	var mg := event as InputEventMagnifyGesture
	if mg != null:
		# Mac trackpad pinch — use background-local mouse pos as pivot (gesture.position
		# is viewport-space; _zoom_at expects the same space as _world.position).
		_zoom_at(_background.get_local_mouse_position(), mg.factor)
		return

	var mm := event as InputEventMouseMotion
	if mm != null and _panning:
		_world.position += mm.relative


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Scales the world around a screen-space pivot, clamped to [zoom_min, zoom_max].
func _zoom_at(pivot: Vector2, factor: float) -> void:
	var old_scale: float = _world.scale.x
	var new_scale: float = clampf(old_scale * factor, ProgressionSystem.zoom_min, ProgressionSystem.zoom_max)
	if is_equal_approx(new_scale, old_scale):
		return
	_world.position = pivot - (pivot - _world.position) * (new_scale / old_scale)
	_world.scale = Vector2(new_scale, new_scale)


## Centers the view on the root node (the Hearth at world origin).
func _center_on_root() -> void:
	_world.scale = Vector2.ONE
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_world.position = viewport_size * 0.5
