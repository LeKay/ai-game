# Story 003: Action Rebinding and Persistence

> **Epic**: Input System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: N/A

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-input-001` (rebinding aspect)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: Godot InputMap used for action definitions — rebinding modifies InputMap at runtime. Settings System calls InputSystem.rebind_action(action_id, new_key). Bindings persisted to user://settings/keybindings.cfg. Reset to defaults available.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: InputMap.rename_action() and InputMap.action_add_event() are stable APIs (pre-4.4). FileAccess for config persistence — return type bool in Godot 4.4+ (verify at compile time).

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern for Foundation systems
- Required: StringName constants for all action IDs
- Guardrail: Performance budget 0.001ms per context check

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- **GIVEN** player remaps `move_up` from `W` to `↑` in Settings, **WHEN** player presses `↑`, **THEN** `on_action_pressed("move_up")` fires (W no longer triggers movement)
- **GIVEN** player rebinds `pause_toggle` to a key already bound to `camera_pan`, **WHEN** prompted "Override binding?", **THEN** if yes: swap bindings; if no: cancel rebind, preserve existing
- **GIVEN** keybindings.cfg is missing or corrupted, **WHEN** game loads, **THEN** default bindings are restored, warning logged, player sees "Keybindings reset" notification
- InputSystem.rebind_action(action_id, new_key) modifies InputMap
- Validation: prevent binding two actions to the same key (conflict detection)
- Persistence: bindings saved to user://settings/keybindings.cfg
- InputSystem.reset_bindings() restores all defaults
- Corrupted/missing keybindings.cfg → load defaults with warning

---

## Implementation Notes

*Derived from ADR-0003 Implementation Guidelines:*

- Use Godot InputMap API for runtime modification:
  - `InputMap.action_erase_events(action)` — remove all existing events for action
  - `InputMap.action_add_event(action, event)` — add new InputEventKey
  - `InputMap.get_action_list(action)` — get all events bound to an action (for display)
- `rebind_action(action_id: StringName, new_key: InputEventKey) -> bool`:
  - Check if new_key is already bound to another action (conflict detection)
  - If conflict: return false with conflicting action_id
  - If no conflict: erase old events, add new event
  - Returns true on success
- `swap_bindings(action_a: StringName, action_b: StringName)` — swap all events between two actions
- `reset_bindings()`: erase all custom bindings, reload defaults from project InputMap
- Persist to `user://settings/keybindings.cfg` using ConfigFile or JSON:
  - Key format: `[action_id] = key_code_string`
  - On load: validate each key_code against InputEventKey.valid_keys
  - Invalid key: skip with warning, keep default binding
  - Missing file or corrupt data: load defaults
- Default bindings defined as constants in input_actions.gd

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Core context stack and dispatch (rebinding depends on this)
- Settings System UI for rebinding (owned by Settings System GDD)
- Gamepad button rebinding (future, not in Vertical Slice)
- Rebinding UI key hints in HUD (owned by HUD System)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

- **AC-1**: Rebinding an action to a new key works
  - Given: move_up is bound to Key.W
  - When: rebind_action("move_up", new InputEventKey with Key.UP) is called
  - Then: Key.W no longer triggers move_up; Key.UP triggers move_up
  - Edge cases: multi-key bindings (e.g., Ctrl+S) — all old keys removed, new key added

- **AC-2**: Conflict detection — rebinding to already-used key
  - Given: move_up bound to W, camera_pan bound to ↑
  - When: rebind_action("move_up", Key.UP) is called
  - Then: returns false with conflict on camera_pan
  - Edge cases: rebind to same key action → no-op, returns true

- **AC-3**: Swap bindings on confirm
  - Given: conflict detected (as above)
  - When: swap_bindings("move_up", "camera_pan") is called
  - Then: move_up now bound to ↑, camera_pan now bound to W
  - Edge cases: source and target are the same action → no-op

- **AC-4**: Persistence and recovery
  - Given: bindings saved to keybindings.cfg
  - When: game restarts, load_bindings() called
  - Then: all custom bindings restored from file
  - Edge cases: missing file → defaults loaded; corrupt JSON → defaults loaded with warning; invalid key code → that binding skipped with warning

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/input/rebinding_test.gd` — must exist and pass

**Status**: [x] Created — `tests/unit/input/rebinding_test.gd` (12 tests, all ACs covered)

---

## Dependencies

- Depends on: Story 001 must be DONE
- Unlocks: None

## Completion Notes
**Completed**: 2026-05-28
**Criteria**: 8/8 passing (all ACs + edge cases covered)
**Deviations**:
- ADVISORY: `push_warning` for corrupt/invalid key paths not directly asserted in tests — binding state is verified; warning emission is untested
- ADVISORY: `rebind_action` erases gamepad events — intentional for current PC-first scope, documented with code comment
**Test Evidence**: Logic — `tests/unit/input/rebinding_test.gd` (12 tests)
**Code Review**: Complete (all findings fixed — false-positive save/load test, multi-key edge case, typed Arrays, redundant casts, warning message improvements)
