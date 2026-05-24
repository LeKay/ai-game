# Story 001: Main Menu Screen

> **Epic**: UI System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-05-14

## Context

**UX Spec**: `design/ux/main-menu.md`
**TR-IDs**: TR-ui-001, TR-ui-002, TR-ui-003, TR-ui-004, TR-ui-005

**ADR Governing Implementation**: ADR-0003: Input Context System (UI_ACTIVE context), ADR-0006: Save/Load Format (WorldSaveManager)

**Engine**: Godot 4.6 | **Risk**: LOW — Godot Control node system is stable and well-documented.

**Control Manifest Rules (this layer)**:
- Required: UI screens use scene-based navigation
- Forbidden: No game state mutation from UI — only trigger events to WorldSaveManager
- Guardrail: Input context must switch to `UI_ACTIVE` when UI is visible

---

## Acceptance Criteria

*From UX spec `design/ux/main-menu.md`:*

- [ ] **AC-1**: Main menu screen loads within 500ms of game launch (engine ready signal)
- [ ] **AC-2**: Main menu layout is functional and readable at 800x600, 1920x1080, and 3440x1440 (21:9)
- [ ] **AC-3**: All focusable buttons are reachable via keyboard (Tab cycling) and gamepad (D-pad/stick)
- [ ] **AC-4**: "Continue" button is disabled (grayed) when no save file exists, enabled when a save file exists
- [ ] **AC-5**: "Settings" button is disabled (grayed) in VS — no interaction
- [ ] **AC-6**: Clicking "New Game" starts a new game scene and destroys the main menu
- [ ] **AC-7**: Clicking "Continue" loads the last save via WorldSaveManager and transitions to game scene
- [ ] **AC-8**: Clicking "Quit" exits the process cleanly (no hang, no crash)
- [ ] **AC-9**: All interactive elements have visible focus indicators when navigated via keyboard or gamepad
- [ ] **AC-10**: "Loading..." state appears within 200ms of clicking "Continue" (after WorldSaveManager.load() begins)
- [ ] **AC-11**: Pressing Escape on the main menu produces no action (main menu is root — no "previous screen" to return to)

---

## Implementation Notes

*Derived from ADR-0003 + ADR-0006 and UX spec `design/ux/main-menu.md`:*

### Scene Structure

Create `res://ui/screens/main_menu.tscn` with root node `Control`:

```
main_menu (Control)
├── background (ColorRect)          — Zone 4: dark gradient
├── title (Label)                   — Zone 1: "From Scratch"
├── menu_buttons (VBoxContainer)    — Zone 2 + 3: button stack
│   ├── new_game_btn (Button)       — New Game
│   ├── continue_btn (Button)       — Continue
│   ├── settings_btn (Button)       — Settings (disabled)
│   └── quit_btn (Button)           — Quit
├── loading_overlay (Panel)         — Loading state (hidden by default)
│   └── loading_label (Label)       — "Loading..."
└── load_failed_overlay (Panel)     — Load failed state (hidden by default)
    ├── try_again_btn (Button)
    └── new_game_from_fail_btn (Button)
```

### Input Context Management

Per ADR-0003, the main menu must be visible and interactive when the game starts:

- On `_ready()`: push `InputContext.UI_ACTIVE` context
- When transitioning to gameplay (New Game / Continue): pop `UI_ACTIVE` context
- Escape produces no action — the main menu is the root screen

### Save File Check

Per ADR-0006, check `WorldSaveManager` for save file existence on menu load:

- If `WorldSaveManager.last_save_is_valid()` returns false/null → disable Continue button
- If save exists → enable Continue button

### Button Behaviors

| Button | On Click |
|--------|----------|
| New Game | Emit `game_started` signal → load game scene → main menu queue-free'd |
| Continue | Show loading overlay → `WorldSaveManager.load_last()` → on success: load game scene; on failure: show load_failed_overlay |
| Settings | No-op (disabled in VS) |
| Quit | Save state (if needed) → `OS.exit()` |

### Visual Design

- **Background**: Solid dark gradient `#3A3A3A` → `#2A2A2A` (VS only; diorama deferred to MVP)
- **Title**: `#F0EDE6` fill, `#D4A85C` outline, ~20px Silkscreen, centered ~20% from top
- **Buttons**: `#5A5A5A` fill, `#E8E4DC` text; hover: `#4A7EA8` fill, `#F0EDE6` text
- **Disabled buttons**: muted fill + reduced opacity
- **Focus indicator**: 2px `#D4A85C` golden outline ring
- **Transitions**: Fade in/out from/to black, 300ms, ease-out

---

## Out of Scope

*Handled by neighbouring stories or deferred to MVP:*

- Settings modal (deferred to MVP — `design/ux/main-menu.md` § Entry & Exit Points)
- Background diorama animation (deferred to MVP)
- Localized strings (deferred to MVP)
- HUD overlay during gameplay (Story 002 — separate screen)
- Pause menu (Story 004 — separate screen)

---

## QA Test Cases

**Story Type**: UI
**Evidence required**: `production/qa/evidence/main-menu-evidence.md`

- **AC-1**: Load time
  - Setup: Launch game fresh
  - Verify: Main menu visible within 500ms of window appearing
  - Pass condition: Time from engine ready signal to first rendered main menu frame ≤ 500ms

- **AC-2**: Layout at multiple resolutions
  - Setup: Run at 800x600, 1920x1080, 3440x1440
  - Verify: All buttons fully visible, title centered, no text overflow, buttons stack vertically
  - Pass condition: Zero clipping, zero overlap, zero text overflow at all resolutions

- **AC-3**: Keyboard navigation
  - Setup: Main menu loaded
  - Verify: Tab cycles through New Game → Continue → Quit; Settings skipped (disabled)
  - Pass condition: Focus indicator visible on each button in order

- **AC-4**: Continue button state
  - Setup A: No save file exists → Load main menu
  - Verify A: Continue button is disabled (grayed, not focusable)
  - Setup B: Save file exists → Load main menu
  - Verify B: Continue button is enabled and focusable
  - Pass condition: Both states behave correctly

- **AC-5**: Settings button disabled
  - Setup: Main menu loaded
  - Verify: Settings button is visually muted, not focusable, no click response
  - Pass condition: Zero interaction possible with Settings

- **AC-6**: New Game scene transition
  - Setup: Main menu loaded, New Game clicked
  - Verify: Main menu is queue-freed, game scene loads
  - Pass condition: No main menu nodes remain in scene tree after transition

- **AC-7**: Continue loads save
  - Setup: Save file exists, Continue clicked
  - Verify: WorldSaveManager.load_last() called, game scene loads with restored state
  - Pass condition: Save state correctly restored in game scene

- **AC-8**: Quit exits cleanly
  - Setup: Main menu loaded, Quit clicked
  - Verify: Process exits within 1s
  - Pass condition: No hang, no crash, no error dialog (unless save needed)

- **AC-9**: Focus indicators
  - Setup: Navigate via Tab and D-pad
  - Verify: 2px golden outline ring visible on all focusable buttons at all times
  - Pass condition: Focus indicator visible on every focusable element

- **AC-10**: Loading state
  - Setup: Save exists, Continue clicked
  - Verify: Loading overlay becomes visible within 200ms
  - Pass condition: loading_overlay.visible == true within 200ms of click

- **AC-11**: Escape no action
  - Setup: Main menu loaded
  - Verify: Pressing Escape produces no scene change, no dismissal, no state change
  - Pass condition: Nothing happens — main menu remains fully functional

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/main-menu-evidence.md` — screenshot walkthrough of all 11 acceptance criteria

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Save/Load System (WorldSaveManager must be operational — ADR-0006), Input System (InputContext must support `UI_ACTIVE` — ADR-0003)
- Unlocks: Story 002 (HUD — builds on the input context established here), Story 004 (Pause → Return to Main Menu)
