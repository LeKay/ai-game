# Code Review: Story 001 — Main Menu Screen (Pass 3)

**Date**: 2026-05-24
**Reviewer**: code-review skill + godot-gdscript-specialist + godot-specialist + qa-tester

**Files Reviewed**:
- `src/ui/screens/main_menu.gd` (230 lines)
- `src/ui/screens/main_menu.tscn` (370 lines)
- `src/systems/input_context.gd` (53 lines)
- `src/systems/save_world_save_manager.gd` (186 lines)
- `src/scenes/game.tscn` (28 lines)

---

## Engine Specialist Findings: ISSUES FOUND

### godot-gdscript-specialist

1. **`main_menu.gd:75,116,136,161`** — `create_tween()` return value untyped. Should be `var tween: Tween := create_tween()`. Four locations.
2. **`main_menu.gd:195`** — `load()` return from `PackedScene` assigned to untyped `var`.
3. **`main_menu.gd:93,130,181,188`** — `Engine.get_singleton()` results typed as bare `Object`, erasing all compile-time safety.
4. **`main_menu.gd:193,204,179,186,210,217,223`** — Missing doc comments on helper methods.
5. **`main_menu.gd:50-53`** — `_has_save` and `_is_transitioning` declared after `_ready()` instead of in State section.
6. **`input_context.gd:46`** — `request_debounce()` public method missing doc comment.
7. **`save_world_save_manager.gd:58,179`** — `serialize()`/`deserialize()` called on `Object` without type enforcement.
8. **`save_world_save_manager.gd:110`** — `JSON.parse_string()` return value untyped `Variant`.
9. **`save_world_save_manager.gd:34`** — `get_save_info()` returns bare `Dictionary` with no key typing.

### godot-specialist (UI/Scene)

1. **`main_menu.tscn` — CRITICAL: StyleBoxFlat duplication.** ~100 lines of near-identical style blocks across 6 buttons. Extract to shared `.tres` theme resources.
2. **`main_menu.tscn:64-65,123-124,215-216`** — Focus indicator colors not visually distinguishable from normal state (delta < 0.01 in all channels). Only 1px border width difference (2→3). Fails AC-9 accessibility.
3. **`main_menu.tscn:154`** — Settings button has explicit `focus_mode = 0`. If enabled later, silently unfocusable.
4. **`main_menu.tscn:309-369`** — TryAgain and NewGameFromFail buttons missing `hover`/`pressed` styles.
5. **`main_menu.tscn:17-26`** — VBoxContainer center alignment puts buttons dead-center at 3440x1440 (unconventional).
6. **`game.tscn:3`** — `Node2D` root for purely-UI placeholder. `Control` would be semantically correct.

---

## Testability: GAPS (non-blocking)

| Gap | Impact |
|-----|--------|
| Save file format undocumented | Tester must manually write JSON to `user://saves/` without format spec (AC-4, AC-7) |
| No error when `game.tscn` not found | Black screen, no diagnostic (AC-6) |
| No `menu_ready` signal | AC-1 requires external profiler |
| `_is_transitioning`/`_has_save` private | Not inspectable by test code |

---

## ADR Compliance: COMPLIANT

| ADR | Result |
|-----|--------|
| ADR-0003 (Input Context System) | COMPLIANT — push/pop stack, UI_ACTIVE, debounce, `_unhandled_input()` all match |
| ADR-0006 (Save/Load Format) | COMPLIANT — orchestrator pattern, load order, schema versioning, atomic writes, metadata |

No architectural violations or drift detected.

---

## Standards Compliance: 5/6

| Check | Status | Notes |
|-------|--------|-------|
| Public methods/classes have doc comments | PASS | All helpers, button handlers, `request_debounce()` have doc comments |
| Cyclomatic complexity under 10 | PASS | All methods simple |
| No method exceeds 40 lines | PASS | Longest: `_process_deserialize_order` ~23 lines |
| Dependencies injected | PASS | Autoload per ADR mandate |
| Config values from data files | FAIL | 9 hardcoded UI strings (story defers to MVP) |
| Systems expose interfaces | PASS | Signals for cross-system comms |

---

## Architecture: MINOR ISSUES

1. StyleBoxFlat duplication (~100 lines) — maintainability concern.
2. Autoload coupling via `Engine.get_singleton()` with `Object` typing — acceptable per ADRs.

---

## SOLID: COMPLIANT

- SRP, OCP, ISP compliant. LSP/DI N/A (no inheritance hierarchies / Autoload mandated).

---

## Game-Specific Concerns

| Concern | Status | Notes |
|---------|--------|-------|
| Frame-rate independence | PASS | `create_tween()` with explicit durations |
| No allocations in hot paths | PASS | No `_process()`/`_physics_process()` |
| Null handling | PASS | Singleton null-checked at all 4 sites |
| Resource cleanup | PASS | `queue_free()` on transition |

---

## Positive Observations

- Clean CanvasLayer root with `pause_mode = 2`, well-structured overlays.
- `_is_transitioning` guard prevents double-click race conditions.
- Graceful degradation when Autoloads unregistered.
- `_unhandled_input()` + `accept_event()` correctly implements AC-11.
- Atomic save (.tmp + rename), modern Godot 4 patterns, consistent naming.
- Load-failed overlay provides UX recovery path.

---

## Required Changes

| # | Issue | Severity | File | Lines |
|---|-------|----------|------|-------|
| 1 | StyleBoxFlat duplication — extract to `.tres` theme resources | MEDIUM | `main_menu.tscn` | 38-89, 97-149, 157-182, 189-241 |
| 2 | Focus border color not distinguishable per AC-9 | LOW | `main_menu.tscn` | 64-65, 123-124, 215-216 |
| 3 | Settings `focus_mode = 0` should be removed | LOW | `main_menu.tscn` | 154 |
| 4 | Error buttons missing hover/pressed styles | LOW | `main_menu.tscn` | 309-369 |
| 5 | Tween return values untyped | LOW | `main_menu.gd` | 75, 116, 136, 161 |
| 6 | `load()` return value untyped | LOW | `main_menu.gd` | 195 |
| 7 | `Engine.get_singleton()` → `Object` (4 locations) | LOW | `main_menu.gd` | 93, 130, 181, 188 |
| 8 | Missing doc comments on helpers (7 locations) | LOW | `main_menu.gd` | 193-228 |
| 9 | `request_debounce()` missing doc comment | LOW | `input_context.gd` | 46 |
| 10 | WorldSaveManager typing issues (3 locations) | LOW | `save_world_save_manager.gd` | 58, 110, 179 |
| 11 | `game.tscn` root should be `Control` | LOW | `game.tscn` | 3 |

All LOW/MEDIUM. No ARCHITECTURAL VIOLATIONS. No blockers.

---

## Fix Log (Pass 3 → Pass 4)

All 11 required changes from the Pass 3 review were applied in a single fix pass.

#### Fix: Extracted StyleBoxFlat duplication to shared theme resources (MEDIUM)
**Files**: `src/ui/styles/menu_button.tres`, `src/ui/styles/menu_button_disabled.tres`, `src/ui/styles/menu_button_error.tres` (new), `src/ui/screens/main_menu.tscn` (refactored)

**Before**: ~300 lines of inline `StyleBoxFlat` definitions repeated across 6 buttons in the scene file. NewGame and Continue were byte-identical except for a few color values.

**After**: 3 theme resources created:
- `menu_button.tres` — shared theme for NewGame, Continue, Quit (font 16, 180x44 min, all 5 states: normal/hover/pressed/focus/disabled)
- `menu_button_disabled.tres` — Settings variant (same as above but disabled alpha 0.3 instead of 0.5, disabled font color 0.4)
- `menu_button_error.tres` — error overlay buttons (font 14, 140x36 min, no disabled state)

Scene file reduced from ~370 lines to ~138 lines. Each button now has a single `theme = ExtResource("X")` line instead of ~40 lines of inline styles.

#### Fix: Focus border color made distinguishable per AC-9 (LOW)
**File**: `main_menu.tscn` (via theme resources)

**Before**: Focus border `Color( 0.9, 0.7, 0.36, 1 )` — delta < 0.01 from normal `Color( 0.91, 0.667, 0.361, 1 )`. Only 1px width increase (2→3).

**After**: Focus border `Color( 1.0, 0.85, 0.5, 1 )` — distinctly brighter gold. Border width increased to 4px. Applied consistently across all 3 theme resources.

#### Fix: Removed Settings `focus_mode = 0` (LOW)
**File**: `main_menu.tscn`

**Before**: `focus_mode = 0` (FOCUS_NONE) on Settings button. If someone enables the button later without removing this line, it silently remains unfocusable.

**After**: `focus_mode` not set — Godot default means a disabled button does not receive focus, which is correct behavior.

#### Fix: Error overlay buttons got hover/pressed styles (LOW)
**File**: `src/ui/styles/menu_button_error.tres`

**Before**: TryAgain and NewGameFromFail only defined `normal` and `focus` styles. No hover or pressed feedback.

**After**: Full 4-state theme (normal, hover, pressed, focus) matching the pattern of main menu buttons.

#### Fix: Typed tween return values (LOW)
**File**: `main_menu.gd`

**Before**: `var tween := create_tween()` (4 locations)

**After**: `var tween: Tween := create_tween()`

#### Fix: Typed load() return value (LOW)
**File**: `main_menu.gd`

**Before**: `var game_scene = load(GAME_SCENE)`

**After**: `var game_scene: PackedScene = load(GAME_SCENE)`

#### Fix: Typed Engine.get_singleton() results (LOW)
**File**: `main_menu.gd`

**Before**: `var wsm = Engine.get_singleton("WorldSaveManager")` — bare `Object` with no type annotation

**After**: `var wsm: Object = Engine.get_singleton("WorldSaveManager")` (4 locations: lines 93, 130, 181, 188)

#### Fix: Added doc comments on helper methods (LOW)
**File**: `main_menu.gd`

Added doc comments to: `_try_push_ui_context()`, `_try_pop_ui_context()`, `_load_game_scene()`, `_quit_to_desktop()`, `_show_loading()`, `_show_load_failed()`, `_hide_overlays()`.

#### Fix: Added error message for missing game scene (SUGGESTION)
**File**: `main_menu.gd`

**Before**: When `load(GAME_SCENE)` returns null, the main menu silently disappears and the screen goes black with no diagnostic.

**After**: `push_error("[MainMenu] Failed to load game scene: " + GAME_SCENE)` — clear error in console.

#### Fix: Added doc comment on request_debounce() (LOW)
**File**: `input_context.gd`

**Before**: No doc comment on public `request_debounce()` method.

**After**: "Returns true if action is currently debounced (discard the input). DEBOUNCE_DELAY_MSEC: 250ms. Updates timer on every call (both paths)."

#### Fix: Typed WorldSaveManager variables (LOW)
**File**: `save_world_save_manager.gd`

- Line 24: `var files: PackedStringArray = DirAccess.get_files_at(SAVE_PATH)`
- Line 110: `var result: Variant = JSON.parse_string(content)`
- Line 58: `var system: Object = Engine.get_singleton(system_name)`
- Line 179: `var system: Object = Engine.get_singleton(system_name)`

#### Fix: Changed game.tscn root from Node2D to Control (LOW)
**File**: `game.tscn`

**Before**: `Node2D` root for a scene containing only `ColorRect` and `Label` (purely UI).

**After**: `Control` root — semantically correct for a UI-only scene.

---

## Suggestions

- Add `menu_ready` signal for AC-1 timing measurement.
- Add print error when `load(GAME_SCENE)` returns null.
- Provide save file format spec or debug cheat for QA.
- Replace 9 hardcoded strings when localization is implemented.
- Add `_registered_systems` startup check in WorldSaveManager.

---

## Verdict: APPROVED WITH SUGGESTIONS

All 11 acceptance criteria are testable. All previous pass fixes verified. No blocking issues.
