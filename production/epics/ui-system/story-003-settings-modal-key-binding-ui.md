# Story 003: Settings Modal & Key Binding UI

> **Epic**: UI System
> **Status**: Ready (deferred to MVP)
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-05-14

## Context

**UX Spec**: `design/ux/settings.md` (TBD — deferred to MVP)
**TR-IDs**: TR-ui-006, TR-ui-007

**ADR Governing Implementation**: ADR-0003: Input Context System (UI_ACTIVE context)

**Engine**: Godot 4.6 | **Risk**: LOW — Godot Control node system is stable.

**Control Manifest Rules (this layer)**:
- Required: UI screens use scene-based navigation
- Forbidden: No game state mutation from UI — only trigger events to WorldSaveManager
- Guardrail: Input context must switch to `UI_ACTIVE` when UI is visible

---

## Acceptance Criteria

*From UX spec `design/ux/settings.md` (deferred to MVP):*

- [ ] **AC-SET-01**: Settings modal opens/closes with a dedicated input action
- [ ] **AC-SET-02**: Key rebinding UI displays current binding and accepts new input
- [ ] **AC-SET-03**: Changes persist across sessions via save system (deferred in VS)
- [ ] **AC-SET-04**: Settings modal is accessible via keyboard and gamepad navigation
- [ ] **AC-SET-05**: Settings modal can be dismissed via Escape (returning to previous screen)

---

## Implementation Notes

**This story is DEFERRED to MVP.**

For the vertical slice, the Settings button exists on the main menu but is disabled and non-interactive (per Story 001). A placeholder `settings_modal.tscn` scene may be created in `res://ui/screens/` with a basic structure for future implementation:

```
settings_modal (Control)
├── overlay (ColorRect)         — semi-transparent backdrop
├── modal_panel (Panel)         — centered settings window
│   ├── title (Label)           — "Settings"
│   └── tab_container (TabContainer)
│       ├── input_tab (Control)
│       │   └── keybind_list (VBoxContainer)
│       └── audio_tab (Control)
│           └── slider_row (HBoxContainer)
└── close_btn (Button)          — "Back" / X
```

No signal wiring, no functional behavior, no test evidence required.

---

## Out of Scope

*Handled by MVP or other stories:*

- Actual key rebinding logic (deferred)
- Audio volume controls (deferred)
- Graphics/display settings (deferred)
- Save/load of settings data (deferred to Save/Load System)
- Settings modal input context management (deferred)

---

## QA Test Cases

**Story Type**: UI (deferred)
**Evidence required**: `production/qa/evidence/settings-evidence.md` — TBD when implemented

- **AC-SET-01**: Settings modal open/close
  - Setup: TBD
  - Verify: TBD
  - Pass condition: TBD

---

## Test Evidence

**Story Type**: UI (deferred)
**Required evidence**: `production/qa/evidence/settings-evidence.md` — TBD when implemented

**Status**: [ ] Not yet created (deferred to MVP)

---

## Dependencies

- Depends on: Story 001 (Main Menu — Settings button placeholder)
- Unlocks: None in VS; unlocks MVP Settings implementation
