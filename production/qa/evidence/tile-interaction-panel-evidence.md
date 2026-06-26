# QA Evidence: Tile Interaction Panel

**Story**: ui-system/story-005-tile-interaction-panel.md  
**Story Type**: UI  
**Date**: *(fill in when walkthrough is run)*  
**Tester**: *(fill in)*  
**Build**: *(git commit hash)*

---

## Walkthrough Checklist

Mark each item [x] when confirmed passing, or [FAIL] with a note.

### AC1 — Panel appears with correct data

- [ ] Click TREE tile → panel shows "Wood", Energy: 12, 80 ticks, "-> 5 Wood", Harvest enabled
- [ ] Click STONE tile → panel shows "Stone", Energy: 10, 60 ticks, "-> 3 Stone"
- [ ] Click BERRY tile → panel shows "Berry", Energy: 5, 40 ticks, "-> 3 Berry"
- [ ] Click GRASS tile → panel shows "Fiber", Energy: 6, 45 ticks, "-> 2 Fiber"
- [ ] Click EMPTY tile → panel shows "Forage", Energy: 8, 50 ticks, "-> 1 random"

### AC2 — Harvest button enabled when not blocked

- [ ] Click any non-blocked tile → Harvest button is enabled and label shows correct output

### AC3 — Harvest button disabled when blocked

- [ ] Remove all tools from inventory, click TREE tile → Harvest button disabled, BlockReasonLabel visible with "No tool available — craft one first"
- [ ] BlockReasonLabel is hidden on unblocked tiles

### AC4 — Depleted energy shows depletion suffix

- [ ] Use actions until energy reaches 0, click TREE tile → tick cost is doubled (160), output halved (3), label shows "(depleted)"
- [ ] Harvest button text reflects depleted output quantity

### AC5 — Harvest button executes action and closes panel

- [ ] Panel open on TREE tile → click Harvest → action starts (progress indicator visible), panel closes
- [ ] Input context returns to WORLD_ACTIVE after close (camera panning works again)

### AC6 — Click outside panel closes panel

- [ ] Panel open → click IMPASSABLE tile or area outside world grid → panel closes, no action started
- [ ] Input context returns to WORLD_ACTIVE after close

### AC7 — Second tile click updates panel in place

- [ ] Panel open on TREE tile → click STONE tile → panel updates to show Stone data, no second panel opened
- [ ] Panel remains at new position (near STONE tile)

### AC8 — Escape closes panel

- [ ] Panel open → press Escape → panel closes, no action started
- [ ] Input context returns to WORLD_ACTIVE after close

---

## Panel Position and Bounds

- [ ] Panel appears adjacent to clicked tile (offset right), not overlapping tile center
- [ ] Clicking a tile near the right edge of the screen → panel clamped to stay within viewport
- [ ] Clicking a tile near the bottom edge → panel clamped above viewport bottom

---

## Notes / Deviations

*(Record any unexpected behavior or deviations from the acceptance criteria here)*

---

## Verdict

- [ ] **PASS** — all blocking criteria met
- [ ] **FAIL** — issue(s) noted above
