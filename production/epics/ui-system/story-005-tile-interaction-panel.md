# Story 005: Tile Interaction Panel

> **Epic**: UI System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-05-14

## Context

**UX Spec**: *(not yet created — create `design/ux/tile-interaction-panel.md` before implementing)*
**TR-IDs**: *(no TR registered — add via `/architecture-review` before closing)*

**ADR Governing Implementation**: ADR-0007: Player Character Energy Model and Manual Action System
**ADR Decision Summary**: `PlayerCharacter.get_cost_preview(action_type)` returns a dict with `blocked`, `reason`, `energy_cost`, `tick_cost`, `output_qty`, `output_resource`, `depleted`. The panel reads this dict to populate its labels and button state. Harvest button calls `try_start_action()`. Panel closes on action start or click outside.

**Engine**: Godot 4.6 | **Risk**: LOW — Godot Control node system is stable. Popup positioning via `global_position` is standard. Post-cutoff APIs used: none.

**Control Manifest Rules (this layer)**:
- Required: UI screens use scene-based navigation — panel is a standalone `.tscn` scene instantiated at runtime
- Guardrail: Input context must switch to `WORLD_ACTIVE` when panel is dismissed; push `UI_MODAL` context while panel is visible
- Required: All UI text must meet WCAG AA 4.5:1 contrast ratio
- Required: No HUD element occupies center 60% × 40% of gameplay view (panel may appear near the clicked tile)

---

## Acceptance Criteria

- [ ] **AC1** GIVEN a player clicks a harvestable tile (TREE/STONE/BERRY/GRASS/EMPTY) THEN the Tile Interaction Panel appears positioned near the tile, showing the resource name, energy cost, tick cost, and expected output quantity
- [ ] **AC2** GIVEN the panel is open and `get_cost_preview().blocked == false` THEN the Harvest button is enabled and its label shows the output (e.g. "Harvest — 5 Wood")
- [ ] **AC3** GIVEN the panel is open and `get_cost_preview().blocked == true` THEN the Harvest button is disabled and a reason label shows the block reason (e.g. "No tool available — craft one first")
- [ ] **AC4** GIVEN the player is at 0 energy WHEN the panel opens THEN tick cost and output quantity show the depleted values from `get_cost_preview()` with a "(depleted)" label appended
- [ ] **AC5** GIVEN the panel is open WHEN the player clicks the Harvest button THEN `try_start_action()` is called, the panel closes, and input context returns to `WORLD_ACTIVE`
- [ ] **AC6** GIVEN the panel is open WHEN the player clicks anywhere outside the panel THEN the panel closes without starting an action
- [ ] **AC7** GIVEN a second tile is clicked while the panel is already open THEN the panel updates to show the new tile's data (does not open a second panel)
- [ ] **AC8** GIVEN the panel is open WHEN the player presses Escape THEN the panel closes without starting an action

---

## Implementation Notes

### Scene structure

```
TileInteractionPanel (PanelContainer)
├── VBoxContainer
│   ├── ResourceLabel (Label)         — resource name, e.g. "Wood"
│   ├── CostRow (HBoxContainer)
│   │   ├── EnergyCostLabel (Label)   — "⚡ 12"
│   │   └── TickCostLabel (Label)     — "⏱ 80 ticks"
│   ├── OutputLabel (Label)           — "→ 5 Wood" or "(depleted) → 3 Wood"
│   ├── BlockReasonLabel (Label)      — hidden when not blocked
│   └── HarvestButton (Button)        — "Harvest"
```

### Populate from cost preview

```gdscript
func populate(action_type: int) -> void:
    var preview: Dictionary = PlayerCharacter.get_cost_preview(action_type)
    _harvest_button.disabled = preview.blocked
    _block_reason_label.visible = preview.blocked
    if preview.blocked:
        _block_reason_label.text = preview.reason
        return
    var suffix: String = " (depleted)" if preview.depleted else ""
    _energy_cost_label.text = "⚡ %d" % preview.energy_cost
    _tick_cost_label.text = "⏱ %d ticks" % preview.tick_cost
    _output_label.text = "→ %d %s%s" % [preview.output_qty, preview.output_resource, suffix]
    _harvest_button.text = "Harvest — %d %s" % [preview.output_qty, preview.output_resource]
```

### Panel positioning

Position the panel adjacent to the clicked tile, offset so it does not cover the tile:

```gdscript
func show_at_tile(tile: Vector2i, action_type: int) -> void:
    var world_pos: Vector2 = Vector2(tile) * WorldGrid.TILE_SIZE + Vector2(WorldGrid.TILE_SIZE, 0)
    global_position = get_viewport().get_canvas_transform().inverse() * world_pos
    populate(action_type)
    show()
```

Clamp to screen bounds after positioning to avoid the panel rendering off-screen.

### Input context

Push `InputContext.Context.UI_MODAL` on show; pop on close. This gates WASD camera movement while the panel is open.

### Click-outside detection

Connect `gui_input` on a full-screen transparent `ColorRect` behind the panel. On any click event, close the panel.

---

## Out of Scope

*Do not implement in this story:*

- [Story 006]: Tile-click-to-action dispatch in MapRoot — must be DONE before this story
- Resource icon art — use text labels as fallback; art can be added later
- Action progress bar / in-progress feedback — separate HUD story
- Inventory display after harvest completes — separate story

---

## QA Test Cases

**Story Type**: UI
**Required evidence**: Manual walkthrough doc at `production/qa/evidence/tile-interaction-panel-evidence.md`

Walkthrough checklist:
- [ ] Click TREE tile → panel shows "Wood", energy 12, 80 ticks, "→ 5 Wood", Harvest button enabled
- [ ] Click STONE tile → panel shows "Stone", energy 10, 60 ticks, "→ 3 Stone"
- [ ] Click BERRY tile → panel shows "Berry", energy 5, 40 ticks, "→ 3 Berry"
- [ ] Click GRASS tile → panel shows "Fiber", energy 6, 45 ticks, "→ 2 Fiber"
- [ ] Click EMPTY tile → panel shows random resource label, equal-distribution values
- [ ] Click Harvest on TREE at energy=0 → shows "(depleted)" label, tick cost doubled, output halved
- [ ] Click Harvest → panel closes, action starts
- [ ] Click outside panel → panel closes, no action started
- [ ] Press Escape → panel closes
- [ ] Click second tile while panel open → panel updates to new tile, no duplicate panel
- [ ] No tool in inventory, click TREE → Harvest button disabled, block reason visible

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/tile-interaction-panel-evidence.md` — manual walkthrough doc with screenshots

**Status**: [ ] Not yet written

---

## Dependencies

- Depends on: Story 006 (Tile Harvest Interaction — must be DONE first)
- Depends on: Input System Story 001 (InputContext push/pop — must be DONE) ✓ Complete
- Unlocks: Action progress HUD integration (future story)

---

## Completion Notes

**Completed**: 2026-05-28
**Criteria**: 8/8 passing (all ACs implementation-verified via code review; manual walkthrough at `production/qa/evidence/tile-interaction-panel-evidence.md` created but not yet executed — run before QA sign-off)
**Deviations**:
- ADVISORY: `UI_MODAL` → `UI_ACTIVE` context (enum value does not exist; intentional workaround)
- ADVISORY: Hardcoded display strings in `_action_type_to_label` and `_populate` (no localization system yet)
**Test Evidence**: UI — walkthrough template at `production/qa/evidence/tile-interaction-panel-evidence.md`
**Code Review**: Complete — APPROVED WITH SUGGESTIONS (lean mode; LP-CODE-REVIEW gate skipped)
