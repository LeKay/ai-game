# Production Speed Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow players to throttle a production building's effective efficiency via a slider + editable fields, persisted per building.

**Architecture:** A new `target_efficiency` field on `BuildingInstance` (−1 = track max, ≥ 0 = explicit throttle) feeds a `get_effective_efficiency()` helper used by the tick calc. The UI is a new `ProductionSpeedEditor` section shown/hidden by a gear button in the building header. Signals bubble `BuildingDetailView → BuildingsDrawerContent → hud.gd → BuildingRegistry.set_production_speed()`.

**Tech Stack:** GDScript 4.6, GdUnit4 for unit tests, Godot HSlider / LineEdit / VBoxContainer.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `src/gameplay/building_registry.gd:119–175` | Add `target_efficiency` field + `get_effective_efficiency()` + `recalculate_efficiency()` auto-clamp |
| Modify | `src/gameplay/building_registry.gd:1603–1604` | Tick calc uses `get_effective_efficiency()` |
| Modify | `src/gameplay/building_registry.gd:1065–1098` | New `set_production_speed()` public method |
| Modify | `src/gameplay/building_registry.gd:2408–2426` | Serialize `target_efficiency` |
| Modify | `src/gameplay/building_registry.gd:2472–2474` | Deserialize `target_efficiency` |
| Create | `src/ui/edge_drawer/buildings/sections/production_speed_editor.gd` | Slider + LineEdit + rate fields UI |
| Modify | `src/ui/edge_drawer/buildings/views/building_detail_view.gd:74–111` | Gear button + editor node refs |
| Modify | `src/ui/edge_drawer/buildings/views/building_detail_view.gd:16–56` | New `production_speed_changed` signal |
| Modify | `src/ui/edge_drawer/buildings/views/building_detail_view.gd:425–563` | Gear button in header stats |
| Modify | `src/ui/edge_drawer/buildings/views/building_detail_view.gd:272–370` | Wire editor in `refresh()` + show/hide |
| Modify | `src/ui/edge_drawer/buildings/sections/production_section.gd:207,243` | Rate calc uses effective efficiency |
| Modify | `src/ui/edge_drawer/buildings/buildings_drawer_content.gd:14–42` | Forward `production_speed_changed` signal |
| Modify | `src/ui/hud/hud.gd:587–600` | Connect + `_on_production_speed_changed` handler |
| Create | `tests/unit/efficiency/production_speed_test.gd` | Unit tests for backend logic |

---

## Task 1: Backend — `target_efficiency` field + `get_effective_efficiency()` + auto-clamp

**Files:**
- Modify: `src/gameplay/building_registry.gd:119–175` (BuildingInstance inner class)
- Create: `tests/unit/efficiency/production_speed_test.gd`

### What this task does

Adds `target_efficiency: float = -1.0` to `BuildingInstance`. The value −1 means "always use the computed max" (tracks future recalculations automatically). Any value ≥ 0 is an explicit throttle that gets auto-clamped when `recalculate_efficiency()` reduces the max.

Adds an instance method `get_effective_efficiency() -> float` used by the tick loop (Task 2) and UI (Task 5).

- [ ] **Step 1.1: Write failing tests**

Create `tests/unit/efficiency/production_speed_test.gd`:

```gdscript
class_name ProductionSpeedTest
extends GdUnitTestSuite
## Unit tests for production speed throttle (target_efficiency field).


func _make_instance() -> BuildingRegistry.BuildingInstance:
	return BuildingRegistry.BuildingInstance.new(
			"b0", BuildingRegistry.BuildingType.STORAGE_BUILDING, Vector2i(0, 0))


# AC-1: default returns full efficiency
func test_get_effective_efficiency_default_returns_max() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	inst.target_efficiency = -1.0
	assert_float(inst.get_effective_efficiency()).is_equal(0.70)


# AC-2: explicit target returns that value
func test_get_effective_efficiency_returns_target() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	inst.target_efficiency = 0.40
	assert_float(inst.get_effective_efficiency()).is_equal(0.40)


# AC-3: zero target returns zero
func test_get_effective_efficiency_zero_target() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	inst.target_efficiency = 0.0
	assert_float(inst.get_effective_efficiency()).is_equal(0.0)


# AC-4: recalculate_efficiency auto-clamps target when max drops
func test_recalculate_clamps_target_when_max_drops() -> void:
	var inst := _make_instance()
	inst.target_efficiency = 0.50
	# Simulate efficiency dropping below target (no workers, no adjacency)
	inst.recalculate_efficiency([])
	# Base efficiency is 0.25 — target 0.50 should be clamped to 0.25
	assert_float(inst.target_efficiency).is_less_equal(inst.efficiency)


# AC-5: recalculate_efficiency does NOT touch target == -1
func test_recalculate_leaves_sentinel_unchanged() -> void:
	var inst := _make_instance()
	inst.target_efficiency = -1.0
	inst.recalculate_efficiency([])
	assert_float(inst.target_efficiency).is_equal(-1.0)


# AC-6: recalculate_efficiency does NOT clamp target that is still within range
func test_recalculate_does_not_clamp_valid_target() -> void:
	var inst := _make_instance()
	inst.target_efficiency = 0.10  # below base 0.25 — should stay
	inst.recalculate_efficiency([])
	assert_float(inst.target_efficiency).is_equal(0.10)
```

- [ ] **Step 1.2: Run tests, confirm they fail**

```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/efficiency/production_speed_test.gd
```

Expected: failures for missing `target_efficiency` field and `get_effective_efficiency()` method.

- [ ] **Step 1.3: Add `target_efficiency` field to BuildingInstance**

In `src/gameplay/building_registry.gd` around line 124, after `var efficiency: float = 1.0`:

```gdscript
	var efficiency: float = 1.0
	## Production speed throttle. -1.0 = always use full computed efficiency (tracks max).
	## 0.0 to <efficiency = explicit throttle; auto-clamped in recalculate_efficiency().
	var target_efficiency: float = -1.0
```

- [ ] **Step 1.4: Add `get_effective_efficiency()` to BuildingInstance**

After `func has_upgrade(upgrade_id: StringName) -> bool:` (around line 153), add:

```gdscript
	## Returns the efficiency used for production — either the computed max (when
	## target_efficiency is the sentinel -1.0) or the player-set throttle.
	func get_effective_efficiency() -> float:
		if target_efficiency < 0.0:
			return efficiency
		return target_efficiency
```

- [ ] **Step 1.5: Update `recalculate_efficiency()` to auto-clamp**

Replace the existing `recalculate_efficiency()` body (around line 159–165) with:

```gdscript
	func recalculate_efficiency(assigned_workers: Array) -> void:
		var worker_eff: float = 0.0
		for worker in assigned_workers:
			worker_eff += worker.efficiency
		var resource_tiles: int = adjacency_tile_count if (ADJACENCY_REQUIREMENTS.has(type) and not ADJACENCY_PLACEMENT_ONLY.has(type)) else 0
		efficiency = EfficiencyFormulas.calculate_building_efficiency(
				resource_tiles, worker_eff, upgrade_bonus, water_bonus)
		# If an explicit throttle now exceeds the new max, clamp it down.
		if target_efficiency >= 0.0 and target_efficiency > efficiency:
			target_efficiency = efficiency
```

- [ ] **Step 1.6: Run tests, confirm they pass**

```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/efficiency/production_speed_test.gd
```

Expected: all 6 tests PASS.

- [ ] **Step 1.7: Commit**

```bash
git add src/gameplay/building_registry.gd tests/unit/efficiency/production_speed_test.gd
git commit -m "feat(efficiency): add target_efficiency throttle field to BuildingInstance"
```

---

## Task 2: Backend — `set_production_speed()` + tick calc + serialization

**Files:**
- Modify: `src/gameplay/building_registry.gd` (public method, tick calc, serialize, deserialize)

- [ ] **Step 2.1: Write failing tests for set_production_speed**

Add to `tests/unit/efficiency/production_speed_test.gd`:

```gdscript
## Minimal BuildingRegistry for set_production_speed tests.
func _make_registry_with_instance(inst: BuildingRegistry.BuildingInstance) -> BuildingRegistry:
	var reg := BuildingRegistry.new()
	reg._npc_system = null
	reg._tick_system = null
	reg._inventory_system = null
	reg._all_buildings[inst.building_id] = inst
	return reg


# AC-7: set_production_speed at max stores sentinel
func test_set_production_speed_at_max_stores_sentinel() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	var reg := _make_registry_with_instance(inst)
	reg.set_production_speed("b0", 0.70)
	assert_float(inst.target_efficiency).is_equal(-1.0)


# AC-8: set_production_speed above max clamps and stores sentinel
func test_set_production_speed_above_max_clamps_to_sentinel() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	var reg := _make_registry_with_instance(inst)
	reg.set_production_speed("b0", 0.99)
	assert_float(inst.target_efficiency).is_equal(-1.0)


# AC-9: set_production_speed below max stores value
func test_set_production_speed_below_max_stores_value() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	var reg := _make_registry_with_instance(inst)
	reg.set_production_speed("b0", 0.40)
	assert_float(inst.target_efficiency).is_equal_approx(0.40, 0.001)


# AC-10: set_production_speed zero stores zero
func test_set_production_speed_zero_stores_zero() -> void:
	var inst := _make_instance()
	inst.efficiency = 0.70
	var reg := _make_registry_with_instance(inst)
	reg.set_production_speed("b0", 0.0)
	assert_float(inst.target_efficiency).is_equal(0.0)
```

- [ ] **Step 2.2: Run tests, confirm they fail**

```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/efficiency/production_speed_test.gd
```

Expected: 4 new failures for missing `set_production_speed` / missing `_all_buildings` access.

- [ ] **Step 2.3: Add `set_production_speed()` to BuildingRegistry**

Find the public API section (after `building_state_changed` signal area, around line 1098). Add this method after `upgrade_removed` signal:

```gdscript
## Sets a production speed throttle for [param building_id].
## [param target] is an absolute efficiency value in [0.0, instance.efficiency].
## If target >= current max efficiency, stores the sentinel -1.0 so the
## building automatically tracks future max changes (NPC fed/unassigned etc.).
## Emits building_state_changed so the detail panel refreshes on next tick.
func set_production_speed(building_id: String, target: float) -> void:
	var instance: BuildingInstance = get_building_instance(building_id)
	if instance == null:
		push_warning("[BuildingRegistry] set_production_speed: unknown building %s" % building_id)
		return
	var clamped: float = clampf(target, 0.0, instance.efficiency)
	instance.target_efficiency = -1.0 if clamped >= instance.efficiency else clamped
	building_state_changed.emit(building_id, instance.state, "production_speed")
```

- [ ] **Step 2.4: Update tick calc to use `get_effective_efficiency()`**

In `src/gameplay/building_registry.gd` around line 1603, change:

```gdscript
		instance.production_cycle_duration = EfficiencyFormulas.calculate_effective_cycle_ticks(
				_active_recipe.get("base_cycle_ticks", 0), instance.efficiency)
```

To:

```gdscript
		instance.production_cycle_duration = EfficiencyFormulas.calculate_effective_cycle_ticks(
				_active_recipe.get("base_cycle_ticks", 0), instance.get_effective_efficiency())
```

- [ ] **Step 2.5: Add `target_efficiency` to serialize**

In `src/gameplay/building_registry.gd` around line 2416, after `"efficiency": instance.efficiency,`:

```gdscript
			"efficiency": instance.efficiency,
			"target_efficiency": instance.target_efficiency,
```

- [ ] **Step 2.6: Add `target_efficiency` to deserialize**

In `src/gameplay/building_registry.gd` around line 2473, after `instance.efficiency = bd.get("efficiency", 1.0)`:

```gdscript
		instance.efficiency = bd.get("efficiency", 1.0)
		instance.target_efficiency = bd.get("target_efficiency", -1.0)
```

- [ ] **Step 2.7: Run all efficiency tests**

```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/efficiency/
```

Expected: all 10 tests PASS.

- [ ] **Step 2.8: Commit**

```bash
git add src/gameplay/building_registry.gd tests/unit/efficiency/production_speed_test.gd
git commit -m "feat(efficiency): set_production_speed(), tick throttle, serialization"
```

---

## Task 3: New UI — `ProductionSpeedEditor`

**Files:**
- Create: `src/ui/edge_drawer/buildings/sections/production_speed_editor.gd`

### Layout

```
[✓] [✕]                    Produktion Speed
────────────────────────────────────────────
0%  [══════════●═══════════]  70%
                [52 %]
────────────────────────────────────────────
Verbrauch
  Wood    [3.2] /day     Stone   [1.6] /day
→
Produktion
  Planks  [2.1] /day
```

The editor is hidden by default. `BuildingDetailView` shows/hides it (Task 4).

- [ ] **Step 3.1: Create the file with scaffold + signals**

Create `src/ui/edge_drawer/buildings/sections/production_speed_editor.gd`:

```gdscript
class_name ProductionSpeedEditor extends VBoxContainer
## Speed-throttle editor for production buildings.
## Shows a slider (0 % – building max %) and per-resource rate fields, all kept in sync.
## Emits save_requested(target_efficiency) or cancel_requested().
## BuildingDetailView owns show/hide and signal forwarding.

signal save_requested(target_efficiency: float)
signal cancel_requested()

const COLOR_TEXT     := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_TEXT_DIM := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_ACCENT   := Color(0.30, 0.70, 1.00, 1.0)
const COLOR_SEP      := Color(0.25, 0.26, 0.30, 1.0)

var _building_id: String = ""
var _max_efficiency: float = 1.0
## Working value while the editor is open. Absolute efficiency in [0, _max_efficiency].
var _pending: float = 0.0

var _slider:    HSlider
var _pct_edit:  LineEdit   ## shows/receives percentage integer (no "%" character)
var _max_label: Label      ## right-end label "70%"

## Each entry: {edit: LineEdit, base_qty: float, cycle_ticks: int, is_input: bool}
var _rate_entries: Array[Dictionary] = []

## Guards against re-entrant slider ↔ lineedit ↔ rate-field loops.
var _updating: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	add_child(_build_header_row())
	add_child(_make_sep())
	add_child(_build_slider_block())
	add_child(_make_sep())
	# Rate rows are rebuilt dynamically in setup() — placeholder spacer until then.
	var spacer := Control.new()
	spacer.name = "RateRowsPlaceholder"
	spacer.custom_minimum_size = Vector2(0, 4)
	add_child(spacer)


## Loads data for [param building_id] and syncs all controls.
func setup(building_id: String) -> void:
	_building_id = building_id
	_rebuild_rate_rows()
	_sync_from_instance()


## Called from BuildingDetailView.refresh() when the building's computed max changes.
func update_max(new_max: float) -> void:
	_max_efficiency = maxf(new_max, 0.001)
	_max_label.text = "%d%%" % int(_max_efficiency * 100.0)
	_slider.max_value = _max_efficiency
	if _pending > _max_efficiency:
		_set_pending(_max_efficiency)
```

- [ ] **Step 3.2: Add header row builder**

Append to `production_speed_editor.gd`:

```gdscript
func _build_header_row() -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   8)
	pad.add_theme_constant_override("margin_right",  8)
	pad.add_theme_constant_override("margin_top",    4)
	pad.add_theme_constant_override("margin_bottom", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	pad.add_child(row)

	var save_btn := Button.new()
	save_btn.name = "SaveBtn"
	save_btn.text = "✓"
	save_btn.flat = true
	save_btn.add_theme_font_size_override("font_size", 14)
	save_btn.add_theme_color_override("font_color", Color(0.298, 0.686, 0.314))
	save_btn.tooltip_text = "Save"  # TODO: localize
	save_btn.pressed.connect(_on_save_pressed)
	row.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.text = "✕"
	cancel_btn.flat = true
	cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	cancel_btn.tooltip_text = "Cancel"  # TODO: localize
	cancel_btn.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var title := Label.new()
	title.name = "Title"
	title.text = "Produktion Speed"  # TODO: localize
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(title)

	return pad
```

- [ ] **Step 3.3: Add slider block builder**

Append to `production_speed_editor.gd`:

```gdscript
func _build_slider_block() -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   8)
	pad.add_theme_constant_override("margin_right",  8)
	pad.add_theme_constant_override("margin_top",    6)
	pad.add_theme_constant_override("margin_bottom", 6)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	pad.add_child(vbox)

	# ── Slider row: [0%] [slider] [XX%] ────────────────────────────────────────
	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 6)
	vbox.add_child(slider_row)

	var min_lbl := Label.new()
	min_lbl.text = "0%"
	min_lbl.add_theme_font_size_override("font_size", 11)
	min_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	min_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider_row.add_child(min_lbl)

	_slider = HSlider.new()
	_slider.name = "Slider"
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(_on_slider_changed)
	slider_row.add_child(_slider)

	_max_label = Label.new()
	_max_label.name = "MaxLabel"
	_max_label.text = "100%"
	_max_label.add_theme_font_size_override("font_size", 11)
	_max_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_max_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider_row.add_child(_max_label)

	# ── Center value: [LineEdit] [%] ───────────────────────────────────────────
	var center_row := HBoxContainer.new()
	center_row.add_theme_constant_override("separation", 2)
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(center_row)

	_pct_edit = LineEdit.new()
	_pct_edit.name = "PctEdit"
	_pct_edit.custom_minimum_size = Vector2(48, 0)
	_pct_edit.alignment           = HORIZONTAL_ALIGNMENT_CENTER
	_pct_edit.add_theme_font_size_override("font_size", 13)
	_pct_edit.text_submitted.connect(_on_pct_submitted)
	_pct_edit.focus_exited.connect(_on_pct_focus_exited)
	center_row.add_child(_pct_edit)

	var pct_lbl := Label.new()
	pct_lbl.text = "%"
	pct_lbl.add_theme_font_size_override("font_size", 13)
	pct_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	pct_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_row.add_child(pct_lbl)

	return pad
```

- [ ] **Step 3.4: Add rate rows builder + sync helpers**

Append to `production_speed_editor.gd`:

```gdscript
func _build_rate_row_for(label_text: String, entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl.custom_minimum_size = Vector2(64, 0)
	row.add_child(lbl)

	var edit := LineEdit.new()
	edit.name = "RateEdit"
	edit.custom_minimum_size = Vector2(52, 0)
	edit.alignment           = HORIZONTAL_ALIGNMENT_RIGHT
	edit.add_theme_font_size_override("font_size", 11)
	entry["edit"] = edit
	edit.text_submitted.connect(_on_rate_submitted.bind(entry))
	edit.focus_exited.connect(_on_rate_focus_exited.bind(entry))
	row.add_child(edit)

	var suffix := Label.new()
	suffix.text = "/day"  # TODO: localize
	suffix.add_theme_font_size_override("font_size", 11)
	suffix.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	row.add_child(suffix)

	return row


## Clears existing rate rows and rebuilds them from the active recipe.
func _rebuild_rate_rows() -> void:
	# Remove placeholder / previous rate rows (everything after the second separator).
	var children := get_children()
	var sep_count := 0
	for i: int in range(children.size() - 1, -1, -1):
		var child: Node = children[i]
		if child is HSeparator:
			sep_count += 1
			if sep_count >= 2:
				break
		if sep_count >= 2:
			child.queue_free()

	_rate_entries.clear()

	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return
	var recipe: Dictionary = BuildingRegistry.get_active_recipe(instance)
	if recipe.is_empty():
		return

	var cycle_ticks: int = recipe.get("base_cycle_ticks", 1)
	var ticks_per_day: float = float(TickSystem.TICKS_PER_DAY)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left",   8)
	pad.add_theme_constant_override("margin_right",  8)
	pad.add_theme_constant_override("margin_top",    6)
	pad.add_theme_constant_override("margin_bottom", 6)
	var rate_vbox := VBoxContainer.new()
	rate_vbox.add_theme_constant_override("separation", 4)
	pad.add_child(rate_vbox)
	add_child(pad)

	# ── Input rows ────────────────────────────────────────────────────────────
	var inputs: Array = recipe.get("inputs", [])
	if not inputs.is_empty():
		var in_lbl := Label.new()
		in_lbl.text = "Verbrauch"  # TODO: localize
		in_lbl.add_theme_font_size_override("font_size", 10)
		in_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		rate_vbox.add_child(in_lbl)

	for spec: Dictionary in inputs:
		var res_id: StringName = spec.get("resource_id", &"")
		var qty: int = spec.get("quantity", 1)
		var def: Object = ResourceRegistry.get_definition(res_id)
		var res_name: String = def.display_name if def != null else str(res_id)
		var entry := {"base_qty": float(qty), "cycle_ticks": cycle_ticks,
				"ticks_per_day": ticks_per_day, "is_input": true, "edit": null}
		rate_vbox.add_child(_build_rate_row_for(res_name, entry))
		_rate_entries.append(entry)

	# ── Arrow ─────────────────────────────────────────────────────────────────
	if not inputs.is_empty():
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 14)
		arrow.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		rate_vbox.add_child(arrow)

	# ── Output rows ───────────────────────────────────────────────────────────
	var output: Dictionary = recipe.get("output", {})
	if not output.is_empty():
		var out_lbl := Label.new()
		out_lbl.text = "Produktion"  # TODO: localize
		out_lbl.add_theme_font_size_override("font_size", 10)
		out_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		rate_vbox.add_child(out_lbl)

	for res_id: StringName in output:
		var qty: int = output[res_id]
		var def: Object = ResourceRegistry.get_definition(res_id)
		var res_name: String = def.display_name if def != null else str(res_id)
		var entry := {"base_qty": float(qty), "cycle_ticks": cycle_ticks,
				"ticks_per_day": ticks_per_day, "is_input": false, "edit": null}
		rate_vbox.add_child(_build_rate_row_for(res_name, entry))
		_rate_entries.append(entry)


## Reads the building instance and sets _pending + all controls.
func _sync_from_instance() -> void:
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return
	_max_efficiency = maxf(instance.efficiency, 0.001)
	_slider.max_value = _max_efficiency
	_max_label.text = "%d%%" % int(_max_efficiency * 100.0)
	var start: float = instance.efficiency if instance.target_efficiency < 0.0 \
			else instance.target_efficiency
	_set_pending(start)


## Sets _pending and pushes value to slider, pct edit, and all rate fields.
func _set_pending(value: float) -> void:
	if _updating:
		return
	_updating = true
	_pending = clampf(value, 0.0, _max_efficiency)
	_slider.value = _pending
	_pct_edit.text = str(int(roundf(_pending * 100.0)))
	for entry: Dictionary in _rate_entries:
		var per_day: float = 0.0
		if entry["cycle_ticks"] > 0:
			per_day = entry["base_qty"] * _pending * entry["ticks_per_day"] \
					/ float(entry["cycle_ticks"])
		(entry["edit"] as LineEdit).text = "%.2f" % per_day
	_updating = false
```

- [ ] **Step 3.5: Add event handlers**

Append to `production_speed_editor.gd`:

```gdscript
func _on_slider_changed(value: float) -> void:
	_set_pending(value)


func _on_pct_submitted(_text: String) -> void:
	_apply_pct_edit()


func _on_pct_focus_exited() -> void:
	_apply_pct_edit()


func _apply_pct_edit() -> void:
	var parsed: float = float(_pct_edit.text.strip_edges()) / 100.0
	if is_nan(parsed):
		_set_pending(_pending)  # restore last valid value
		return
	_set_pending(parsed)


func _on_rate_submitted(_text: String, entry: Dictionary) -> void:
	_apply_rate_edit(entry)


func _on_rate_focus_exited(entry: Dictionary) -> void:
	_apply_rate_edit(entry)


func _apply_rate_edit(entry: Dictionary) -> void:
	var parsed: float = float((entry["edit"] as LineEdit).text.strip_edges())
	if is_nan(parsed) or entry["cycle_ticks"] <= 0 or entry["ticks_per_day"] <= 0.0:
		_set_pending(_pending)  # restore
		return
	# Reverse-calculate efficiency from the entered per-day rate.
	var eff: float = parsed * float(entry["cycle_ticks"]) \
			/ (entry["base_qty"] * entry["ticks_per_day"])
	_set_pending(eff)


func _on_save_pressed() -> void:
	save_requested.emit(_pending)


func _on_cancel_pressed() -> void:
	cancel_requested.emit()


func _make_sep() -> HSeparator:
	var sep := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_SEP
	sb.content_margin_top    = 0
	sb.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sb)
	return sep
```

- [ ] **Step 3.6: Commit**

```bash
git add src/ui/edge_drawer/buildings/sections/production_speed_editor.gd
git commit -m "feat(ui): ProductionSpeedEditor section — slider, rate fields, bidirectional sync"
```

---

## Task 4: BuildingDetailView — gear button + editor wiring

**Files:**
- Modify: `src/ui/edge_drawer/buildings/views/building_detail_view.gd`

- [ ] **Step 4.1: Add signal + node refs**

In `building_detail_view.gd`, add to the signals block (after line 55):

```gdscript
## Emitted when the player saves a production speed change.
## target_efficiency: absolute efficiency value in [0.0, instance.efficiency];
## BuildingRegistry.set_production_speed() converts ≥ max to the sentinel -1.0.
signal production_speed_changed(building_id: String, target_efficiency: float)
```

Add to the node refs block (after `_util_label: Label` around line 86):

```gdscript
var _eff_gear_btn:  Button        ## gear button next to Eff label — production buildings only
var _speed_editor:  ProductionSpeedEditor  ## inline speed-throttle editor
```

- [ ] **Step 4.2: Add gear button to stats column in `_build_header()`**

In `_build_header()` (around line 478, after `stats.add_child(_eff_label)`), wrap the eff label and gear in a row:

Replace the block that creates `_eff_label` and adds it to `stats` (currently just the label at ~line 478–483) with:

```gdscript
	# Eff row: label + gear button
	var eff_row := HBoxContainer.new()
	eff_row.add_theme_constant_override("separation", 4)
	stats.add_child(eff_row)

	_eff_label = Label.new()
	_eff_label.name = "EffLabel"
	_eff_label.add_theme_font_size_override("font_size", 12)
	_eff_label.add_theme_color_override("font_color", COLOR_TEXT)
	_eff_label.text = "Eff: —"
	_eff_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eff_row.add_child(_eff_label)

	_eff_gear_btn = Button.new()
	_eff_gear_btn.name = "EffGearBtn"
	_eff_gear_btn.text = "⚙"
	_eff_gear_btn.flat = true
	_eff_gear_btn.tooltip_text = "Edit production speed"  # TODO: localize
	_eff_gear_btn.add_theme_font_size_override("font_size", 12)
	_eff_gear_btn.visible = false
	_eff_gear_btn.pressed.connect(_open_speed_editor)
	eff_row.add_child(_eff_gear_btn)
```

- [ ] **Step 4.3: Create and wire ProductionSpeedEditor in `_ready()`**

In `_ready()` (around line 130), before `vbox.add_child(_production_section)`:

```gdscript
	_speed_editor = ProductionSpeedEditor.new()
	_speed_editor.name = "ProductionSpeedEditor"
	_speed_editor.visible = false
	_speed_editor.save_requested.connect(_on_speed_save)
	_speed_editor.cancel_requested.connect(_on_speed_cancel)
	vbox.add_child(_speed_editor)
```

- [ ] **Step 4.4: Add show/hide helpers + handlers**

Append to `building_detail_view.gd`:

```gdscript
# ── Production speed editor ───────────────────────────────────────────────────

func _open_speed_editor() -> void:
	var instance: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(_building_id)
	if instance == null:
		return
	_speed_editor.setup(_building_id)
	_speed_editor.visible   = true
	_eff_gear_btn.visible   = false
	_production_section.visible = false


func _on_speed_save(target_efficiency: float) -> void:
	production_speed_changed.emit(_building_id, target_efficiency)
	_close_speed_editor()


func _on_speed_cancel() -> void:
	_close_speed_editor()


func _close_speed_editor() -> void:
	_speed_editor.visible       = false
	_production_section.visible = true
	# Gear is re-shown by next refresh() call.
	refresh()
```

- [ ] **Step 4.5: Update `refresh()` to pass max to editor and show/hide gear**

In `refresh()`, in the `else` branch (non-storage buildings, around line 313), after setting `_eff_label.text`:

```gdscript
		_eff_label.text = "Eff: %d%%" % int(instance.efficiency * 100.0)  # TODO: localize
		# Show gear only for production buildings when the editor is not already open.
		var is_prod: bool = BuildingRegistry.is_production_building(instance.type)
		_eff_gear_btn.visible = is_prod and not _speed_editor.visible
		if _speed_editor.visible:
			_speed_editor.update_max(instance.efficiency)
```

- [ ] **Step 4.6: Commit**

```bash
git add src/ui/edge_drawer/buildings/views/building_detail_view.gd
git commit -m "feat(ui): gear button + ProductionSpeedEditor wired into BuildingDetailView"
```

---

## Task 5: ProductionSection — use effective efficiency for rate display

**Files:**
- Modify: `src/ui/edge_drawer/buildings/sections/production_section.gd:186–254`

The rate labels (input ~line 207, output ~line 243) currently use `instance.efficiency`. They must use the throttled value so the displayed rates match actual throughput.

- [ ] **Step 5.1: Update input rate calc**

In `_rebuild_tiles()`, around line 207, change:

```gdscript
			var per_day: float = float(spec_qty) * instance.efficiency * ticks_per_day / float(cycle_ticks)
```

To:

```gdscript
			var per_day: float = float(spec_qty) * instance.get_effective_efficiency() * ticks_per_day / float(cycle_ticks)
```

- [ ] **Step 5.2: Update output rate calc**

Around line 243–244, change:

```gdscript
			var per_day: float = (float(base_qty) * instance.efficiency) \
					* ticks_per_day / float(cycle_ticks)
```

To:

```gdscript
			var per_day: float = (float(base_qty) * instance.get_effective_efficiency()) \
					* ticks_per_day / float(cycle_ticks)
```

- [ ] **Step 5.3: Run full test suite**

```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/ --continue
```

Expected: all existing tests PASS (no regressions).

- [ ] **Step 5.4: Commit**

```bash
git add src/ui/edge_drawer/buildings/sections/production_section.gd
git commit -m "fix(ui): production rate labels use throttled effective efficiency"
```

---

## Task 6: Signal forwarding — BuildingsDrawerContent + hud.gd

**Files:**
- Modify: `src/ui/edge_drawer/buildings/buildings_drawer_content.gd:14–92`
- Modify: `src/ui/hud/hud.gd:587–600` (connect) + new handler

- [ ] **Step 6.1: Add forwarding signal to BuildingsDrawerContent**

In `buildings_drawer_content.gd`, add after `signal upgrade_install_requested` (around line 41):

```gdscript
## Forwarded from BuildingDetailView — player saved a production speed change.
signal production_speed_changed(building_id: String, target_efficiency: float)
```

- [ ] **Step 6.2: Wire detail view signal in `_ready()`**

In `buildings_drawer_content.gd _ready()`, after `_detail_view.upgrade_install_requested.connect(...)` (around line 92):

```gdscript
	_detail_view.production_speed_changed.connect(
		func(bid: String, eff: float) -> void:
			production_speed_changed.emit(bid, eff))
```

- [ ] **Step 6.3: Connect in hud.gd**

In `hud.gd`, after line 596 (`_buildings_drawer._content.recipe_changed.connect(...)`):

```gdscript
	_buildings_drawer._content.production_speed_changed.connect(_on_production_speed_changed)
```

- [ ] **Step 6.4: Add handler in hud.gd**

After `_on_recipe_changed()` (around line 955), add:

```gdscript
func _on_production_speed_changed(building_id: String, target_efficiency: float) -> void:
	BuildingRegistry.set_production_speed(building_id, target_efficiency)
```

- [ ] **Step 6.5: Commit**

```bash
git add src/ui/edge_drawer/buildings/buildings_drawer_content.gd src/ui/hud/hud.gd
git commit -m "feat(ui): wire production_speed_changed signal from detail view to BuildingRegistry"
```

---

## Task 7: Manual QA walkthrough

**Files:**
- Create: `production/qa/evidence/production-speed-editor-walkthrough.md`

- [ ] **Step 7.1: Run the project in Godot**

Open the project in Godot 4.6 and start the game (F5).

- [ ] **Step 7.2: Open a production building**

Place or select a Lumber Camp (or any production building with a worker). Open the Buildings Drawer → tap the building tile → detail view opens.

- [ ] **Step 7.3: Verify gear button appears**

Next to "Eff: XX%", the ⚙ button should be visible. It should NOT appear for storage buildings.

- [ ] **Step 7.4: Open editor and verify layout**

Tap ⚙. Verify:
- "Produktion Speed" section appears
- ✓ and ✕ buttons visible top-left
- Slider spans 0% to current max (e.g., 70%)
- Center LineEdit shows current efficiency (e.g., "70")
- Verbrauch / Produktion rows show correct per-day rates

- [ ] **Step 7.5: Test slider → fields sync**

Drag slider left to ~50%. Verify: LineEdit updates to "50", rate fields update to half their previous values.

- [ ] **Step 7.6: Test LineEdit → slider sync**

Type "30" in the center field, press Enter. Verify: slider moves to 30%, rate fields update.

- [ ] **Step 7.7: Test rate field → slider sync**

Edit one consumption or production rate field. Enter a value and confirm (Enter or click away). Verify: slider and center field move to reflect the reverse-calculated efficiency.

- [ ] **Step 7.8: Test save persists**

Set slider to ~40%. Press ✓. Re-open the building detail. Re-open the editor. Verify slider starts at ~40%.

- [ ] **Step 7.9: Test cancel discards**

Open editor, move slider to 10%. Press ✕. Re-open editor. Verify it still shows the previously saved value (not 10%).

- [ ] **Step 7.10: Test auto-clamp when max drops**

With target set to 50% and max at 70%: remove the worker (unassign NPC). Max should drop to 25% (base only). Open editor — verify slider now shows 25% max and pending value is clamped to 25%.

- [ ] **Step 7.11: Test "track max" behavior**

Set slider all the way to max (70%). Save. Remove then re-add a worker (efficiency changes to e.g. 80%). Open editor — verify pending value is 80% (tracked the new max, not frozen at old 70%).

- [ ] **Step 7.12: Write evidence doc**

Create `production/qa/evidence/production-speed-editor-walkthrough.md` with:
- Date
- Steps tested (checkmarks for each above step)
- Any deviations or edge cases observed
- Screenshot paths if taken

- [ ] **Step 7.13: Final commit**

```bash
git add production/qa/evidence/production-speed-editor-walkthrough.md
git commit -m "qa: production speed editor manual walkthrough evidence"
```

---

## Self-Review

### Spec coverage

| Requirement | Task |
|-------------|------|
| Gear button next to Eff label | Task 4.2 |
| Opens "Produktion Speed" section | Task 4.3–4.4 |
| Slider 0% to max (current efficiency) | Task 3.3 |
| Min/max labels at ends | Task 3.3 |
| Editable center field shows current set value | Task 3.3 |
| Editable consumption/production fields | Task 3.4 |
| Multiple inputs/outputs supported | Task 3.4 (loops over all) |
| Rate fields affect slider (reverse-calc) | Task 3.5 |
| Save ✓ / Cancel ✕ buttons | Task 3.2 |
| Persisted per building | Task 2.5–2.6 |
| If at max → tracks new max | Task 2.3 (sentinel -1) |
| If set below max → clamps when max drops below it | Task 1.5 |
| ProductionSection rate display uses throttled value | Task 5 |
| Signal chain: Detail → DrawerContent → HUD → Registry | Task 6 |

### Placeholder scan

No TBDs, no "similar to Task N" references. All code blocks are complete.

### Type consistency

- `target_efficiency: float` — consistent across Tasks 1–6
- `get_effective_efficiency() -> float` — defined Task 1, used Tasks 2, 5
- `set_production_speed(building_id: String, target: float)` — defined Task 2, called Task 6
- `ProductionSpeedEditor` — created Task 3, referenced Task 4
- `production_speed_changed(building_id: String, target_efficiency: float)` — defined Task 4, forwarded Task 6
- `update_max(new_max: float)` — defined Task 3, called Task 4.5
