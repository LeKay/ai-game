# Evidence: Day Overview Panel (Story 008)

**Story**: production/epics/ui-system/story-008-day-overview-panel.md
**Story Type**: UI
**Date**: <!-- fill in when tested -->
**Tester**: <!-- fill in -->

---

## Walkthrough Checklist

### AC-1: Panel appears with correct day number and NPC count

- [ ] Setup: Run game to day 3 with 2 NPCs; let tick counter reach day transition
- [ ] Verify: Panel appears showing "Tag 4" and "2 Bewohner"
- [ ] Pass: Both values match the actual game state exactly
- [ ] Screenshot: <!-- attach -->

### AC-2: Tageskonsum section shows hunger consumption list

- [ ] Setup: HungerSystem consumes 3 Beeren + 1 Brot on the last day
- [ ] Verify: List shows "Beere ×3" and "Brot ×1" (per display_name from ResourceRegistry)
- [ ] Verify: With 0 NPCs (or no food consumed): shows "Keine Nahrung verbraucht"
- [ ] Pass: No empty list, no duplicates
- [ ] Screenshot: <!-- attach -->

### AC-3: Tagesbilanz section shows signed deltas with correct colors

- [ ] Setup: Deposit 10 Holz (deposit), withdraw 2 Beeren (withdraw) during the day
- [ ] Verify: "+10 Holz" displayed in green; "-2 Beere" displayed in red
- [ ] Verify: With no changes: shows "Keine Änderungen"
- [ ] Pass: Colors and signs are correct
- [ ] Screenshot: <!-- attach -->

### AC-4: Button receives keyboard focus on open

- [ ] Setup: Panel opens (keyboard user — do not click mouse after open)
- [ ] Verify: "Nächster Tag" button is immediately activatable with Enter without pressing Tab
- [ ] Pass: `_next_day_btn.has_focus() == true` immediately after panel opens
- [ ] Note: <!-- result -->

### AC-5: Button closes panel and resumes game

- [ ] Test A (mouse click): Panel open → click "Nächster Tag" → panel disappears, ticks resume
- [ ] Test B (Enter key): Panel open → press Enter → panel disappears, ticks resume
- [ ] Pass A: `visible == false` and `TickSystem.is_paused() == false`
- [ ] Pass B: same
- [ ] Note: <!-- result -->

### AC-6: No double-panel on repeated day_transition signals

- [ ] Setup: Panel already visible
- [ ] Action: Manually emit `TickSystem.day_transition.emit(1)` from the debugger
- [ ] Verify: No second panel layer appears; exactly one panel visible
- [ ] Pass: Single panel only
- [ ] Note: <!-- result -->

---

## Summary

**Verdict**: <!-- PASS / FAIL / PARTIAL -->
**Issues**: <!-- list any found -->
