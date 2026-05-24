# Story 005: UI — Food Status Display

> **Epic**: Hunger System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: UI — ADR-0010
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/hunger-system.md`
**Requirements**:
- UI-1 through UI-4 (all HUD UI elements)

**ADR Governing Implementation**: ADR-0010: Hunger System and Debuff Stacking
**ADR Decision Summary**: HungerSystem emits `hunger_display_updated(fed, food_available, food_required)` and `hunger_state_changed(multiplier)` signals. The HUD System subscribes to these signals to update food status display. Food status is displayed near the energy bar or in the resource summary. Debuff indicator is secondary to energy bar. Food breakdown tooltip shows on hover.

**Engine**: Godot 4.6 | **Risk**: LOW (Control nodes, signals)
**Engine Notes**: Godot 4.6 dual-focus system (mouse + keyboard/gamepad focus are separate). HUD must handle both input paths. HUD System is read-only — it consumes signals and read methods but owns no game state.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/hunger-system.md`, scoped to this story:*

- [ ] **AC-UI-1** GIVEN the HUD is rendered WHEN the village has food remaining THEN a food status indicator displays "X days of food remaining" near the energy bar or resource summary, using `HungerSystem.get_days_of_food_remaining()`
- [ ] **AC-UI-2** GIVEN the village is HUNGRY WHEN the HUD is rendered THEN a debuff indicator displays "HUNGRY — actions slowed (2× tick cost)" as a secondary element below the energy bar
- [ ] **AC-UI-3** GIVEN the food status indicator is hovered WHEN the tooltip opens THEN it shows "N NPCs need N food units today. Total: X food units." with food unit breakdown (1 berry = 1 unit, 1 bread = 2 units)
- [ ] **AC-UI-4** GIVEN a day transition completes WHEN food was consumed THEN a brief HUD flash displays "Day N: consumed X food units (Y berries, 0 deficit)" for 3 seconds

---

## Implementation Notes

*Derived from ADR-0010 and GDD Implementation Guidelines:*

**UI elements (from GDD UI Requirements):**

| ID | Element | Description |
|----|---------|-------------|
| UI-1 | Food status indicator | Small text near energy bar or resource summary: "3 days of food remaining" or "⚠️ Low food" when ≤ 1 day |
| UI-2 | Debuff indicator | When HUNGRY: "HUNGRY — actions slowed (2× tick cost)". Not at player eye level — secondary to energy bar |
| UI-3 | Food breakdown (tooltip) | Hovering the food status shows: "N NPCs need N food units today. Total: X food units." (1 berry = 1 unit, 1 bread = 2 units) |
| UI-4 | Day transition food log (optional) | After day transition, brief HUD flash: "Day 2: consumed 2 food units (2 berries, 0 deficit)" |

**HUD wiring (from ADR-0010):**
```
# HUD System — _ready():
func _ready() -> void:
    HungerSystem.hunger_state_changed.connect(_on_hunger_state_changed)
    HungerSystem.hunger_display_updated.connect(_on_hunger_display_updated)

# _on_hunger_state_changed(multiplier: float) -> void:
#   Update debuff indicator visibility and text
#   If multiplier == 2.0 → show "HUNGRY" indicator
#   If multiplier == 1.0 → hide "HUNGRY" indicator

# _on_hunger_display_updated(fed: bool, food_available: int, food_required: int) -> void:
#   Update food status text
#   days = get_days_of_food_remaining(food_available, food_required)
#   Show "X days of food remaining" or "⚠️ Low food"
#   Update tooltip data

# On day transition:
#   Show brief flash message for 3 seconds
#   "Day N: consumed X food units (Y berries, 0 deficit)"
```

**Status tiers (from GDD Visual/Audio Requirements):**
```
# Food status display:
if days >= 5:      → "Food: X days remaining" (normal)
if days == 2:      → "Food: X days remaining" (normal)
if days == 1:      → "⚠️ Low food: 1 day remaining"
if days == 0:      → "⚠️ No food remaining!"
if days >= 9999:   → "Unlimited" (0 NPCs)
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Daily consumption logic (the UI only displays the result, not the consumption itself)
- Story 002: Debuff stacking logic (the UI displays the current debuff state, not the stacking math)
- Story 003: Consumption priority (how food is deducted is not visible to the player)

---

## QA Test Cases

**AC-UI-1**: Food status indicator displays correctly
  - Setup: Day 5, 2 NPCs, 30 food units in storage (15 days remaining)
  - Verify: HUD displays "Food: 15 days remaining" near energy bar or resource summary
  - When: food drops to 1 unit (0.5 days → floors to 0)
  - Verify: HUD displays "⚠️ No food remaining!"
  - When: food drops to 2 units (1 day)
  - Verify: HUD displays "⚠️ Low food: 1 day remaining"
  - When: 0 NPCs (no food requirement)
  - Verify: HUD displays "Unlimited"
  - Pass condition: Status text updates on `hunger_display_updated` signal, displays correct tier

**AC-UI-2**: Debuff indicator shows when HUNGRY
  - Setup: Village enters HUNGRY state (food runs out, day transition fires)
  - Verify: "HUNGRY — actions slowed (2× tick cost)" appears below energy bar
  - When: village refeeds and day transition fires (FED state)
  - Verify: Debuff indicator disappears
  - Pass condition: Indicator visibility is tied to `HungerSystem.hunger_debuff_active`, text is accurate

**AC-UI-3**: Food breakdown tooltip
  - Setup: Hover over food status indicator
  - Verify: Tooltip shows "2 NPCs need 2 food units today. Total: 30 food units."
  - Verify: Tooltip includes breakdown: "(1 berry = 1 unit, 1 bread = 2 units)"
  - When: food composition changes (berries added, bread consumed)
  - Verify: Tooltip updates to reflect current totals
  - Pass condition: Tooltip data is accurate and updates on `hunger_display_updated`

**AC-UI-4**: Day transition food log flash
  - Setup: Day transition fires, village consumed 2 berries, 0 deficit
  - Verify: Brief flash appears: "Day 2: consumed 2 food units (2 berries, 0 deficit)"
  - Verify: Flash persists for ~3 seconds then fades
  - When: village is HUNGRY (deficit > 0)
  - Verify: Flash includes deficit: "Day 3: consumed 2 food units (2 berries, 1 deficit)"
  - When: 0 NPCs (no consumption)
  - Verify: No flash (nothing was consumed)
  - Pass condition: Flash appears on successful day transition with consumption, content is accurate

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/hunger-ui-evidence.md` — screenshot-based evidence with sign-off

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (HungerSystem must exist and emit signals), Story 002 (debuff indicator requires debuff state)
- Unlocks: None — this is the final story for the Hunger System epic
