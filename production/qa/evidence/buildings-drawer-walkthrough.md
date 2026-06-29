# Buildings Drawer — Manual Walkthrough Checklist

**Date:** 2026-06-26
**Implementation:** Buildings Drawer UI (docs/superpowers/specs/2026-06-26-buildings-drawer-ui-design.md)
**Status:** ⏳ Pending verification in Godot

## How to use this checklist
Open the game in Godot, play in the editor (F5). Work through each item below.
Mark each ✅ (pass), ❌ (fail), or ⚠️ (partial/concern) with a note.

---

## Phase A: Edge Drawer Base Behaviour

- [ ] **A1** Tasks tab: hover shows ~12px tab peek (NO panel open on hover)
- [ ] **A2** Tasks tab: click pins panel open; click again closes
- [ ] **A3** Tasks tab: click outside panel closes it (click passes through to map)
- [ ] **A4** Tasks tab: ESC closes when pinned; game receives ESC when closed
- [ ] **A5** Transport tab: same behaviour as A1–A4
- [ ] **A6** Transport tab: route create/edit/delete still works end-to-end
- [ ] **A7** Tab order on right edge (top→bottom): Tasks (104px), Buildings (212px), Transport (320px)

## Phase B: Buildings Drawer

- [ ] **B1** Buildings tab appears between Tasks and Transport tabs
- [ ] **B2** Buildings tab: click opens list of placed buildings as tiles
- [ ] **B3** Buildings list: "+" tile is first
- [ ] **B4** Buildings list: Shelter/Path/Road tiles are NOT shown
- [ ] **B5** Buildings list: im-Bau tile shows progress ring + dimmed modulate
- [ ] **B6** "+" tile click opens BuildPickerView (with ← Back row at top)
- [ ] **B7** BuildPickerView: only buildable types shown
- [ ] **B8** BuildPickerView: click a type → drawer closes + build mode activated
- [ ] **B9** "← Back" in BuildPickerView returns to building list

## Phase B: Detail View

- [ ] **B10** Click a building tile → Detail View opens
- [ ] **B11** Detail view: correct asset/texture shown (or glyph fallback)
- [ ] **B12** Detail view: correct name, Efficiency %, Utilization %
- [ ] **B13** Detail view: "← Back" returns to list
- [ ] **B14** Detail view rename: click ✏️ → LineEdit appears; Enter submits; ESC cancels
- [ ] **B15** Detail view rename: persistence (name stays after close/reopen)
- [ ] **B16** Worker tile: assigned NPC shown correctly
- [ ] **B17** Worker tile: click assigned NPC → NPC detail panel opens
- [ ] **B18** Worker tile "+": click opens free-NPC picker; assign works
- [ ] **B19** Worker tile: disabled with tooltip when no free NPCs

## Phase B: Production Section

- [ ] **B20** Production section shows input tiles → "→" → output tiles
- [ ] **B21** Input/output tile quantities match actual building buffers
- [ ] **B22** Daily rate label is plausible ("~N glyph/day")
- [ ] **B23** ⚙️ hidden when building has only 1 recipe
- [ ] **B24** ⚙️ visible when building has multiple recipes
- [ ] **B25** Click ⚙️ → recipe picker shows; click recipe → switches; body returns
- [ ] **B26** Storage building shows Inventory section (NOT production section)
- [ ] **B27** Drag-out: drag item tile → drag signal emitted (check via DragController)

## Phase B: Transport Section

- [ ] **B28** Transport section shows incoming/outgoing route tiles
- [ ] **B29** Empty incoming/outgoing still shows sub-header + "+" tile
- [ ] **B30** Click "+" in incoming → route editor opens with building as destination
- [ ] **B31** Click "+" in outgoing → route editor opens with building as source
- [ ] **B32** Route editor save → route created, list refreshes
- [ ] **B33** Route editor cancel → returns to route list
- [ ] **B34** Map-select round-trip: click map button in editor → drawer hides → pick building → editor returns with building filled

## Phase B: Upgrades Section

- [ ] **B35** Upgrades section hidden when no upgrades available
- [ ] **B36** Active upgrades shown first with ✓ overlay
- [ ] **B37** Available affordable upgrade: click installs it immediately
- [ ] **B38** Available unaffordable upgrade: disabled with cost tooltip

## Phase C: Old Panel Removed

- [ ] **C1** Click building on map → Buildings Drawer opens (NOT old centered modal)
- [ ] **C2** Old BuildingDetailPanel is completely gone (no modal appears)
- [ ] **C3** Inventory screen has no "Buildings" tab

## Regressions

- [ ] **R1** Tasks drawer content unchanged (task cards, complete button, points badge)
- [ ] **R2** Transport drawer content unchanged (routes list, edit/delete/create)
- [ ] **R3** NPC detail panel still opens from Buildings drawer worker tile
- [ ] **R4** Day transition: all drawers close + re-open after "Next Day"
- [ ] **R5** Progression tree overlay: drawers hide while tree is open
- [ ] **R6** Overworld map: drawers hide while map is open

---

## Known Issues / Notes

*(fill in during testing)*

---

## Sign-off

- Tester: ___
- Date: ___
- Godot version: 4.6
