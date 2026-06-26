class_name NpcGrid extends VBoxContainer
## Reusable NPC tile grid — renders one block per NPC.
## Feed data via populate(). No coupling to NPCSystem.
## Mirrors ItemGrid's tile pattern but displays NPC identity and state.

signal npc_clicked(npc_id: StringName)

const BLOCK_WIDTH  := 72
const BLOCK_HEIGHT := 100
const BLOCK_GAP    := 8
const ICON_SIZE    := 40

## XP progress bar colours (Experience System). Amber while levelling, gold at max level.
const COLOR_XP_BAR_BG   := Color("#2A2A2A")
const COLOR_XP_BAR_FILL := Color("#D4A85C")
const COLOR_XP_BAR_MAX  := Color("#E8C860")
## Level badge colours.
const COLOR_BADGE_BG   := Color(0.0, 0.0, 0.0, 0.65)
const COLOR_BADGE_TEXT := Color("#E8C860")

const COLOR_BLOCK_BG     := UiPalette.BLOCK_BG
const COLOR_BLOCK_BORDER := UiPalette.BLOCK_BORDER
const COLOR_HOVER_BORDER := UiPalette.HOVER_BORDER
const COLOR_TEXT_DIM     := UiPalette.TEXT_DIM

## TaskState index → display label.
const STATE_LABELS: Array[String] = [
	"Idle",        # 0 IDLE
	"Travelling",  # 1 TRAVEL_TO_BUILDING
	"Working",     # 2 WORK_AT_BUILDING
	"Returning",   # 3 TRAVEL_TO_STORAGE
	"Depositing",  # 4 DEPOSIT
	"Returning",   # 5 RETURN_TO_BASE
	"Waiting",     # 6 WAITING
]

## TaskState index → color.
const STATE_COLORS: Array[Color] = [
	Color("#808080"),  # 0 IDLE — gray
	Color("#D4A85C"),  # 1 TRAVEL_TO_BUILDING — amber
	Color("#4CAF50"),  # 2 WORK_AT_BUILDING — green
	Color("#D4A85C"),  # 3 TRAVEL_TO_STORAGE — amber
	Color("#4CAF50"),  # 4 DEPOSIT — green
	Color("#D4A85C"),  # 5 RETURN_TO_BASE — amber
	Color("#E05555"),  # 6 WAITING — red
]

## Set before adding to scene tree to centre tiles horizontally.
var center: bool = false

var _flow:          HFlowContainer
var _empty_label:   Label
var _warn_popup:    PanelContainer
var _warn_lbl:      Label

## Signature of the last populated data. populate() is a no-op when the incoming
## data is identical, so the residential house's per-tick refresh does not tear
## down and rebuild tiles under the cursor (which would reset hover highlight and
## drop the warning popup — flicker that only "recovered" on mouse motion).
var _last_signature: String = ""


func _ready() -> void:
	_build_warn_popup()
	_flow = HFlowContainer.new()
	_flow.name = "NpcFlow"
	_flow.add_theme_constant_override("h_separation", BLOCK_GAP)
	_flow.add_theme_constant_override("v_separation", BLOCK_GAP)
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.alignment = FlowContainer.ALIGNMENT_CENTER if center else FlowContainer.ALIGNMENT_BEGIN
	add_child(_flow)

	_empty_label = Label.new()
	_empty_label.name                 = "EmptyLabel"
	_empty_label.text                 = "No workers recruited yet"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.visible = false
	add_child(_empty_label)


func _build_warn_popup() -> void:
	_warn_popup = PanelContainer.new()
	_warn_popup.name         = "NpcGridWarnPopup"
	_warn_popup.visible      = false
	_warn_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn_popup.z_index      = 100
	# top_level = true: renders in the same canvas coordinate space as sibling Controls
	# (global_position units) but is excluded from VBoxContainer layout — no lazy
	# root.add_child() needed, which would trigger scene-tree revalidation and cause
	# mouse_exited to fire on the hovered tile, leading to flicker.
	_warn_popup.top_level = true
	var s := StyleBoxFlat.new()
	s.bg_color               = Color(0.12, 0.12, 0.12, 0.95)
	s.set_border_width_all(1)
	s.border_color           = Color(0.45, 0.45, 0.45, 1.0)
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_left   = 8.0
	s.content_margin_right  = 8.0
	s.content_margin_top    = 6.0
	s.content_margin_bottom = 6.0
	_warn_popup.add_theme_stylebox_override("panel", s)
	_warn_lbl = Label.new()
	_warn_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn_lbl.add_theme_font_size_override("font_size", 12)
	_warn_lbl.add_theme_color_override("font_color", Color(0.95, 0.87, 0.6))
	_warn_popup.add_child(_warn_lbl)
	add_child(_warn_popup)


func _show_warn(text: String, tile_global_pos: Vector2) -> void:
	_warn_lbl.text       = text
	_warn_popup.position = tile_global_pos + Vector2(0, BLOCK_HEIGHT + 4)
	_warn_popup.visible  = true


func _hide_warn() -> void:
	_warn_popup.visible = false


## Replaces all tiles with a fresh render of `npcs`.
## Each entry must have keys: npc_id (StringName), state (int — NPCSystem.TaskState).
## Optional keys: display_name (String); level (int), xp_into_level (int), xp_span (int)
## for the Experience System badge + bar (xp_span <= 0 renders a "MAX" bar).
func populate(npcs: Array[Dictionary]) -> void:
	# Skip the rebuild when nothing changed — preserves the hovered tile (and its
	# highlight + warning popup) across redundant refreshes such as the residential
	# house's per-tick _refresh_npc_zone.
	var sig := var_to_str(npcs)
	if sig == _last_signature:
		return
	_last_signature = sig

	for child in _flow.get_children():
		child.queue_free()

	if npcs.is_empty():
		_flow.visible        = false
		_empty_label.visible = true
		return

	_flow.visible        = true
	_empty_label.visible = false

	for npc: Dictionary in npcs:
		var display: String = npc.get(&"display_name", "")
		if display == "":
			display = str(npc[&"npc_id"])
		_flow.add_child(_make_block(npc[&"npc_id"], npc[&"state"], display,
				int(npc.get(&"level", 1)),
				int(npc.get(&"xp_into_level", 0)),
				int(npc.get(&"xp_span", 0)),
				npc.get(&"warnings", []),
				str(npc.get(&"job", ""))))


func _make_block(npc_id: StringName, state: int, display_name: String,
		level: int, xp_into_level: int, xp_span: int, warnings: Array = [],
		job: String = "") -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BLOCK_WIDTH, BLOCK_HEIGHT)
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP

	var style := StyleFactory.block(COLOR_BLOCK_BG, COLOR_BLOCK_BORDER, 1, 0)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size   = Vector2(ICON_SIZE, ICON_SIZE)
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_container)

	var icon_lbl := Label.new()
	icon_lbl.text                 = "🧑"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_lbl.add_theme_font_size_override("font_size", 24)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_lbl)

	# Level badge — small "Lv N" chip in the top-left corner of the icon.
	icon_container.add_child(NpcGrid.make_level_badge(level))

	# Warning badge — bottom-right corner of icon area (purely visual, no mouse interaction).
	if not warnings.is_empty():
		icon_container.add_child(_make_warning_badge(warnings))

	var id_lbl := Label.new()
	id_lbl.text                  = display_name
	id_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	id_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	id_lbl.clip_text  = true
	id_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(id_lbl)

	var state_lbl := Label.new()
	state_lbl.text                  = STATE_LABELS[clampi(state, 0, STATE_LABELS.size() - 1)]
	state_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	state_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_lbl.add_theme_font_size_override("font_size", 11)
	state_lbl.add_theme_color_override("font_color",
		STATE_COLORS[clampi(state, 0, STATE_COLORS.size() - 1)])
	state_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(state_lbl)

	# XP progress bar (Experience System F3) — thin bar along the bottom of the tile.
	vbox.add_child(_make_xp_bar(xp_into_level, xp_span))

	var warn_text: String = "" if warnings.is_empty() else "Not consumed:\n" + "\n".join(warnings)
	panel.mouse_entered.connect(func() -> void:
		style.border_color = COLOR_HOVER_BORDER
		if not warn_text.is_empty():
			_show_warn(warn_text, panel.global_position)
	)
	panel.mouse_exited.connect(func() -> void:
		style.border_color = COLOR_BLOCK_BORDER
		_hide_warn()
	)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			npc_clicked.emit(npc_id)
	)

	if job == "":
		return panel

	# Job is rendered *below* the tile (outside the bordered block), not inside it.
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 3)
	wrapper.custom_minimum_size = Vector2(BLOCK_WIDTH, 0)
	wrapper.add_child(panel)

	var job_lbl := Label.new()
	job_lbl.text                  = job
	job_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	job_lbl.custom_minimum_size   = Vector2(BLOCK_WIDTH, 0)
	job_lbl.add_theme_font_size_override("font_size", 11)
	job_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	job_lbl.clip_text   = true
	job_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(job_lbl)
	return wrapper


## Returns the list of resource display-names that an NPC failed to consume at the last day
## transition. Empty when everything was consumed or no day has passed yet.
static func build_npc_warnings(npc_id: StringName, npc: Object) -> Array:
	var out: Array = []
	var food: StringName = HungerSystem.get_assigned_food(npc_id)
	if food != &"" and not HungerSystem.was_food_consumed(npc_id):
		var fdef: Object = ResourceRegistry.get_definition(food)
		out.append(fdef.display_name if fdef != null else str(food))
	if npc == null:
		return out
	for perk: Dictionary in npc.perks:
		if bool(perk.get(&"active", true)):
			continue
		var good: StringName = perk.get(&"good", &"")
		if good == &"":
			continue
		# Only warn when the player INTENDED the perk active (assigned >= required) but the good
		# couldn't be consumed. A perk set to 0 (or otherwise under-assigned) is intentionally
		# disabled — it consumes nothing by design and must not be reported as undersupplied.
		var required: int = int(PerkRegistry.get_def(perk.get(&"perk_id", &"")).get("required", 1))
		var assigned: int = int(perk.get(&"amount", 1))
		if assigned < required:
			continue
		var gdef: Object = ResourceRegistry.get_definition(good)
		out.append(gdef.display_name if gdef != null else str(good))
	return out


## Builds the "Lv N" badge anchored to the top-left of the icon area.
static func make_level_badge(level: int) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)

	var style := StyleBoxFlat.new()
	style.bg_color                   = COLOR_BADGE_BG
	style.corner_radius_top_left     = 3
	style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left  = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left   = 3
	style.content_margin_right  = 3
	style.content_margin_top    = 1
	style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text         = "Lv %d" % level
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COLOR_BADGE_TEXT)
	badge.add_child(lbl)
	return badge


## Warning badge at bottom-right of the icon area (level badge is top-left — maximises separation).
## No background; amber ⚠ symbol with a faint dark drop-shadow StyleBox for legibility.
func _make_warning_badge(warnings: Array) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-right of icon_container (ICON_SIZE × ICON_SIZE = 40 × 40). Badge is ~14 px square.
	badge.position = Vector2(ICON_SIZE - 14, ICON_SIZE - 14)

	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.0, 0.0, 0.0, 0.55)
	style.corner_radius_top_left     = 3
	style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left  = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left   = 1
	style.content_margin_right  = 1
	style.content_margin_top    = 0
	style.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text         = "⚠"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#FFD740"))
	badge.add_child(lbl)
	return badge


## Builds the thin XP progress bar (Experience System F3). xp_span <= 0 → full "MAX" bar (gold).
func _make_xp_bar(xp_into_level: int, xp_span: int) -> Control:
	var outer := Control.new()
	outer.custom_minimum_size = Vector2(BLOCK_WIDTH - 16, 5)
	outer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color        = COLOR_XP_BAR_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_child(bg)

	var is_max: bool = xp_span <= 0
	var ratio: float = 1.0 if is_max else clampf(float(xp_into_level) / float(xp_span), 0.0, 1.0)

	var fill := ColorRect.new()
	fill.color         = COLOR_XP_BAR_MAX if is_max else COLOR_XP_BAR_FILL
	fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	fill.anchor_left   = 0.0
	fill.anchor_top    = 0.0
	fill.anchor_right  = ratio
	fill.anchor_bottom = 1.0
	fill.offset_right  = 0.0
	outer.add_child(fill)

	if is_max:
		outer.tooltip_text = "MAX level"
	else:
		outer.tooltip_text = "%d / %d XP" % [xp_into_level, xp_span]
	return outer
