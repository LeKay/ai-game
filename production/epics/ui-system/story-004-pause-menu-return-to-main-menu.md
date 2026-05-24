# Story 004: Pause Menu & Return to Main Menu

> **Epic**: UI System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-05-14

## Context

**UX Spec**: `design/ux/pause-menu.md` (TBD — deferred to MVP, basic behavior designed below)
**TR-IDs**: TR-ui-008, TR-ui-009

**ADR Governing Implementation**: ADR-0003: Input Context System (PAUSED context, stack-based restoration), ADR-0006: Save/Load Format (save-on-exit to main menu)

**Engine**: Godot 4.6 | **Risk**: LOW — Godot Control node system is stable.

**Control Manifest Rules (this layer)**:
- Required: UI screens use scene-based navigation
- Forbidden: No game state mutation from UI — only trigger events to WorldSaveManager
- Guardrail: Input context must switch to `UI_ACTIVE` when UI is visible; `PAUSED` when pause overlay is active

---

## Acceptance Criteria

- [ ] **AC-PAUSE-01**: Pressing Escape / Start button pauses the game and opens the pause menu overlay
- [ ] **AC-PAUSE-02**: Pause menu is a non-modal overlay (game world still visible behind, dimmed)
- [ ] **AC-PAUSE-03**: "Resume" button returns to gameplay, restoring the previous input context
- [ ] **AC-PAUSE-04**: "Return to Main Menu" button saves current game state (if any progress made), transitions to main menu, and pops all input contexts
- [ ] **AC-PAUSE-05**: All pause menu buttons are reachable via keyboard (Tab) and gamepad (D-pad) navigation
- [ ] **AC-PAUSE-06**: Escape on the pause menu does NOT dismiss it — Escape is the pause toggle; a dedicated "Back"/"Resume" button handles dismissal
- [ ] **AC-PAUSE-07**: If no save file existed before pausing (new game, no progress saved), "Return to Main Menu" does not attempt a save — it goes straight to main menu

---

## Implementation Notes

*Derived from ADR-0003 (Input Context stack) + ADR-0006 (Save/Load):*

### Scene Structure

Create `res://ui/screens/pause_menu.tscn` — loaded as an overlay on top of the game scene:

```
pause_menu (Control)
├── overlay (ColorRect)           — semi-transparent dark dim
│   └── dim_color: #000000 with 50% color_modulate
├── menu_panel (Control)          — centered card
│   ├── title (Label)             — "Paused"
│   └── menu_buttons (VBoxContainer)
│       ├── resume_btn (Button)   — Resume
│       ├── main_menu_btn (Button) — Return to Main Menu
│       └── quit_btn (Button)     — Quit to Desktop
└── progress_indicator (Label)    — "No save yet" (visible when AC-PAUSE-07 applies)
```

### Input Context Management

Per ADR-0003, the pause system uses the context stack:

- When pause is triggered: `InputContext.push_context(InputContext.PAUSED)`
- On Resume: `InputContext.pop_context()` — restores the previous context (WORLD_ACTIVE or UI_ACTIVE if a UI screen was open before pause)
- On Return to Main Menu / Quit: `InputContext.clear_stack()` → `InputContext.push_context(InputContext.UI_ACTIVE)`

The pause menu overlay must have `pause_mode = PAUSE_MODE_STOP` on its root so it can intercept the pause toggle input action without consuming the game's pause input.

### Pause Toggle Input

The pause toggle is a global input action (e.g., `ui_cancel` / Escape / Start):

- When pressed during gameplay: toggle pause state
- If game is unpooled → push PAUSED context, show overlay
- If game is paused → pop context, hide overlay (Resume)
- Escape on the pause menu itself does NOT toggle — it is consumed by the "Resume" button's default action

### Save on Return to Main Menu

Per ADR-0006:

- "Return to Main Menu" checks if any game state was created
- If yes: emit `save_requested` signal → `WorldSaveManager.save()` → on completion: load main menu scene
- If no progress made (new game, never triggered a save): skip save, transition directly to main menu
- Show progress indicator ("No save yet") when save will be skipped

### Visual Design

- **Overlay dim**: `#000000` at 50% opacity
- **Menu panel**: `#3A3A3A` fill, rounded corners
- **Title**: `#F0EDE6`, ~24px Silkscreen, centered
- **Buttons**: Same style as main menu buttons (`#5A5A5A` fill, `#E8E4DC` text; hover `#4A7EA8`)
- **Focus indicator**: 2px `#D4A85C` golden outline ring (same as main menu)
- **Transition**: Fade in/out, 200ms, ease-out

---

## Out of Scope

*Handled by other stories or deferred to MVP:*

- Quit to desktop confirmation dialog (deferred)
- Audio mixing changes while paused (deferred — audio continues playing)
- Pause menu key binding customization (Story 003 — deferred)
- In-game save slot selection (deferred to MVP)
- "Are you sure you want to quit?" confirmation (deferred)

---

## QA Test Cases

**Story Type**: UI
**Evidence required**: `production/qa/evidence/pause-menu-evidence.md` — screenshot walkthrough

- **AC-PAUSE-01**: Pause toggle
  - Setup: Game running, HUD visible
  - Verify: Escape / Start opens pause overlay; game pauses
  - Pass condition: Pause overlay visible, game paused
- **AC-PAUSE-02**: Overlay appearance
  - Setup: Pause menu open
  - Verify: Game world visible behind overlay, dimmed
  - Pass condition: Overlay is non-modal, world visible through dim
- **AC-PAUSE-03**: Resume
  - Setup: Pause menu open
  - Verify: Resume closes overlay, restores input context
  - Pass condition: Game unpaused, input context matches pre-pause state
- **AC-PAUSE-04**: Return to Main Menu
  - Setup: Pause menu open, save file exists
  - Verify: Game saved, main menu loaded
  - Pass condition: Main menu displayed, save file updated
- **AC-PAUSE-05**: Keyboard/gamepad navigation
  - Setup: Pause menu open
  - Verify: Tab cycles Resume → Main Menu → Quit; gamepad D-pad same order
  - Pass condition: All buttons focusable, focus indicator visible
- **AC-PAUSE-06**: Escape on pause menu
  - Setup: Pause menu open
  - Verify: Escape does nothing (menu stays open)
  - Pass condition: Pause menu remains open after Escape
- **AC-PAUSE-07**: No-save return
  - Setup: New game, no save file existed before, open pause menu
  - Verify: "No save yet" indicator shown; Return to Main Menu skips save
  - Pass condition: No save file created, main menu loads

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/pause-menu-evidence.md` — screenshot walkthrough of all 7 acceptance criteria

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (Main Menu must exist as transition target), Input Context System (ADR-0003), Save/Load System (ADR-0006)
- Unlocks: None — pause menu is self-contained presentation layer
