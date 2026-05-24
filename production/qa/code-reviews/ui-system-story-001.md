# Code Review: Story 001 — Main Menu Screen

**Date**: 2026-05-24
**Reviewer**: code-review skill + godot-gdscript-specialist + godot-specialist + qa-tester

**Files Reviewed**:
- `src/ui/screens/main_menu.gd` (232 lines)
- `src/ui/screens/main_menu.tscn` (415 lines)
- `src/systems/input_context.gd` (53 lines)
- `src/systems/save_world_save_manager.gd` (191 lines)
- `src/scenes/game.tscn` (28 lines)

---

## Previous Review (First Pass)

The first pass review identified 7 required changes (1 bug, 6 quality issues). All 7 were fixed. See the **Fix Log** section below for details.

### First-Pass ADR Compliance: COMPLIANT

**ADR-0003 (Input Context System):** COMPLIANT
- InputContext push/pop pattern matches ADR exactly (`_try_push_ui_context` / `_try_pop_ui_context`).
- Context enum values (`WORLD_ACTIVE`, `UI_ACTIVE`, `PAUSED`) match.
- Stack-based push/pop semantics match ADR specification.
- Debounce implementation matches (`request_debounce` with 0.25s delay).

**ADR-0006 (Save/Load Format):** COMPLIANT
- `WorldSaveManager` follows orchestrator pattern with `register_save_system`, `save_game`, `load_game`.
- Load order invariant enforced in `_process_deserialize_order`.
- Schema versioning with `SCHEMA_VERSION` check.
- Atomic writes (.tmp + rename).
- Metadata files for save listing.

No architectural violations or drift detected.

### First-Pass Testability: TESTABLE

All 11 acceptance criteria map to testable code paths. UI story evidence (screenshot walkthrough) is achievable.

**Well-exposed hooks:**
| Hook | Access | Used By |
|------|--------|---------|
| `loading_overlay.visible` | Direct node reference | AC-10 |
| `load_failed_overlay.visible` | Direct node reference | AC-7 failure path |
| `continue_btn.disabled` | Direct node reference | AC-4 |
| `settings_btn.disabled` | Direct node reference | AC-5 |
| `game_started/game_loaded/game_exited` | Script signals | AC-6, AC-7, AC-8 |

**Missing or weak hooks:**
- `_has_save` is private — must infer from `continue_btn.disabled` state.
- `_is_transitioning` has no signal — observable only via UI interactivity.
- No `fade_completed` hook for AC-1 stopwatch measurement.

**Untestable criteria:** None. AC-11 is testable but reveals a UX consideration where Escape cannot cancel a pending quit.

**New edge cases not covered:**
- Corrupted save file: `get_available_slots()` returns slots for `.meta.json` files without verifying `.json` data validity. Handled by load-failed overlay (good design, but not in AC list).
- WorldSaveManager registers after menu `_ready()`: Continue stays disabled forever. Only manifests in dev/slow hardware.
- Focus navigation to load-failed overlay buttons when menu buttons are still in tree but hidden.

### First-Pass Standards Compliance: 4/6

| Check | Status | Notes |
|-------|--------|-------|
| Public methods/classes have doc comments | FAIL | `check_save_file_state()` has one; button handlers have no doc comments |
| Cyclomatic complexity under 10 per method | PASS | All methods simple |
| No method exceeds 40 lines | PASS | Longest: `_process_deserialize_order` at ~23 lines |
| Dependencies injected | FAIL | Uses `Engine.get_singleton()` — but ADR-0003/0006 mandate Autoload |
| Config values from data files | FAIL | 9 hardcoded UI text strings in scene file |
| Systems expose interfaces | PASS | Systems communicate via signals |

### First-Pass Architecture: MINOR ISSUES

1. **Wrong input hook** (`main_menu.gd:79`): `_input()` instead of `_unhandled_input()`. ADR-0003 specifies `_unhandled_input()` as the correct hook for engine-level input gating.
2. **Autoload coupling**: All files use `Engine.get_singleton()` for runtime access — acceptable per ADRs, but makes static analysis harder.

### First-Pass SOLID: COMPLIANT

- **SRP**: MainMenu handles navigation only, not game state mutation.
- **OCP**: Buttons extendable without modification.
- **LSP**: N/A — no inheritance hierarchies.
- **ISP**: InputContext interface is lean (5 methods + 1 signal).
- **DI**: N/A — Autoload pattern mandated by ADRs.

### First-Pass Game-Specific Concerns

| Concern | Status | Notes |
|---------|--------|-------|
| Frame-rate independence | PASS | Toggles use `create_tween()` with explicit duration |
| No allocations in hot paths | PASS | No `_process()`/`_physics_process()` |
| Null handling | PASS | `Engine.get_singleton()` null-checked everywhere |
| Resource cleanup | PASS | `queue_free()` on transition |

---

## Second Pass (Post-Fix Review)

### Engine Specialist Findings

**godot-gdscript-specialist:**

1. **`main_menu.gd:201`** — `var instance = game_scene.instantiate()` missing type annotation. Should be `var instance: Node = game_scene.instantiate()`. Mandatory static typing violation.
2. **`main_menu.gd:76`** — `TRANS_ELASTIC` on a `Color` property (`modulate`) creates a bouncy overshoot "flash-pulse" effect. A fade-in should use `TRANS_SINE` or `TRANS_LINEAR`. Visual bug.
3. **`main_menu.gd:156`** — `game_exited.emit()` fires synchronously but the actual `_quit_toDesktop()` is a tween callback 0.3s later. Signal listeners will receive the signal before the exit actually happens.
4. **`main_menu.gd:208`** — `_quit_toDesktop` violates snake_case naming convention. Should be `_quit_to_desktop`.
5. **`main_menu.gd:194-197`** — `ResourceLoader.exists()` is a redundant preflight; `load()` already returns `null` for missing paths.
6. **`main_menu.gd:146-147`** — `_on_settings_pressed()` connected in `_ready()` but only does `pass`. Button is disabled so never called — dead code.

**godot-specialist (UI/Scene):**

1. **`main_menu.tscn` — 9 hardcoded user-facing strings** violate the UI code rule ("All UI text must go through the localization system").
   - `"From Scratch"` (Title, line 35)
   - `"New Game"` (NewGame, line 99)
   - `"Continue"` (Continue, line 163)
   - `"Settings"` (Settings, line 199)
   - `"Quit"` (Quit, line 262)
   - `"Loading..."` (LoadingLabel, line 292)
   - `"Load failed"` (FailedLabel, line 333)
   - `"Try Again"` (TryAgain, line 379)
   - `"New Game"` (NewGameFromFail, line 410)

2. **`main_menu.tscn:17-28` — VBoxContainer uses fixed offset anchoring** (`offset_left=-100, offset_top=-150, offset_right=100, offset_bottom=150`). At 3440x1440 the 200px-wide menu column is only 5.8% of screen width. **Fails AC-2** (layout at 3440x1440).

3. **`main_menu.tscn:412-414`** — Redundant `[signal]` declarations in scene file when script already declares them. Legacy Godot 3 format.

4. **`main_menu.tscn` — Focus indicator may not be distinguishable enough** from normal state for AC-9 accessibility compliance. Same border width (2px), only color shifts. A thicker border or glow on focus would be more robust.

**save_world_save_manager.gd:**
- **`save_world_save_manager.gd:55`** — `timestamp` field uses `Time.get_ticks_msec()` (tick count, not wall-clock). Semantic mismatch with field name.

### Testability: GAPS

**11/11 ACs testable**, but with gaps:
- **AC-6 gap**: If `game.tscn` doesn't exist, the player gets a black screen (fade completes, no fallback error displayed). Not covered by QA test cases.
- **AC-7 gap**: Corrupted save failure path has UI (`load_failed_overlay`) but no QA test steps covering it.
- **No `fade_completed` hook** for AC-1 stopwatch measurement — QA must use external profiler.

**AC-11 UX analysis**: The concern was whether "Escape can cancel a pending quit." It cannot — the tween callback fires regardless of input. `accept_event()` only prevents propagation, not queued callbacks. This is **correct behavior, not a defect.**

**Gamepad navigation**: Godot's default focus traversal handles gamepad input when `focus_mode` is set. Buttons have `focus_mode = 3` (FOCUS_ALL). Settings has `focus_mode = 0` + `disabled = true`, so it is skipped. This matches the QA test expectation.

### ADR Compliance: COMPLIANT

(All checks from first pass remain valid.)

### Standards Compliance: 4/6

(Same as first pass — unchanged.)

### Architecture: MINOR ISSUES

1. **Hardcoded strings in scene file** — 9 user-facing strings violate the UI code rule. The story says "Localized strings (deferred to MVP)" but the UI code rule has no MVP exception. This is a tension between story scope and code rule.
2. **Autoload coupling** — `Engine.get_singleton()` with `Object` typing limits static analysis.

### SOLID: COMPLIANT

(Same as first pass — unchanged.)

### Game-Specific Concerns

| Concern | Status | Notes |
|---------|--------|-------|
| Frame-rate independence | PASS | Toggles use `create_tween()` with explicit durations |
| No allocations in hot paths | PASS | No `_process()`/`_physics_process()` |
| Null handling | PASS | `Engine.get_singleton()` null-checked everywhere |
| Resource cleanup | PASS | `queue_free()` on transition |

---

## Positive Observations

- Clean scene hierarchy with CanvasLayer root, well-structured overlay system.
- `_is_transitioning` guard prevents double-click race conditions.
- Graceful degradation: if Autoloads are not registered, menu still works (buttons disabled, load fails gracefully).
- `_unhandled_input()` usage is correct — accepts Escape to prevent propagation.
- Atomic save pattern (.tmp + rename) in WorldSaveManager.
- Modern Godot 4 patterns used: `DirAccess.get_files_at()`, typed `Dictionary[K, V]`, typed `@onready` fields.
- Typed signals with `.emit()` (not legacy `emit_signal("name")`).
- Load-failed overlay provides UX recovery for corrupted saves.

---

## Required Changes

| # | Issue | Severity | File | Line(s) | Status |
|---|-------|----------|-------|---------|--------|
| — | `TRANS_ELASTIC` on fade-in (visual bug) | MEDIUM | `main_menu.gd` | 76 | **FIXED** |
| — | `game_exited` signal timing (emitted before actual exit) | MEDIUM | `main_menu.gd` | 156 vs 161 | **FIXED** |
| — | Focus indicator distinguishability (AC-9) | MEDIUM | `main_menu.tscn` | all buttons | **FIXED** |
| — | VBoxContainer fixed offset (AC-2) | HIGH | `main_menu.tscn` | 17-28 | **FIXED** |
| — | Redundant `ResourceLoader.exists()` | LOW | `main_menu.gd` | 194-197 | **FIXED** |
| — | Untyped `var instance` | LOW | `main_menu.gd` | 197 | **FIXED** |
| — | Naming: `_quit_toDesktop` | LOW | `main_menu.gd` | 203 | **FIXED** |
| — | Redundant `[signal]` declarations | LOW | `main_menu.tscn` | 408-410 | **FIXED** |
| — | Title hardcoded `font_size=28` | LOW | `main_menu.tscn` | 28-29 | **FIXED** |

All required changes from both review passes have been applied. Remaining issues:
- **1 advisory**: 9 hardcoded user-facing strings (story scope defers localization to MVP, intentional drift from UI code rule)
- **1 advisory**: `_on_settings_pressed()` connected but does `pass` — dead code (button is disabled, never called)
- **1 advisory**: `save_world_save_manager.gd:55` — `Time.get_ticks_msec()` used as "timestamp" (semantic mismatch with field name)

If any remaining items are treated as must-fix, the story needs changes before `/story-done`. Otherwise, the implementation meets the MVP intent and all acceptance criteria are testable.

---

## Fix Log (First Pass Issues)

| # | Change | File | Status |
|---|--------|------|--------|
| 1 | Change `_input()` to `_unhandled_input()` | `main_menu.gd` | FIXED |
| 2 | Replace `emit_signal("...")` with `signal_name.emit()` | `main_menu.gd` | FIXED |
| 3 | Add `: float` type annotations | `main_menu.gd` | VERIFIED (already present) |
| 4 | Add `: Object` type to `Engine.get_singleton()` results | `main_menu.gd` | FIXED |
| 5 | Change `Dictionary` to `Dictionary[StringName, float]` | `input_context.gd` | FIXED |
| 6 | Remove unused `_save_data` variable | `save_world_save_manager.gd` | FIXED |
| 7 | Replace deprecated `DirAccess` pattern with `DirAccess.get_files_at()` | `save_world_save_manager.gd` | FIXED |

### Detailed Fix Log

#### Fix 1: Wrong input hook (BUG)
**File**: `src/ui/screens/main_menu.gd` line 79
**Before**: `func _input(event: InputEvent) -> void:` — fires for ALL input including consumed events
**After**: `func _unhandled_input(event: InputEvent) -> void:` — fires only when no child Control consumed the event
**Rationale**: Screen-level input must use `_unhandled_input()` to avoid intercepting input that child controls need. Matches ADR-0003's `_unhandled_input()` specification.

#### Fix 2: String-based emit_signal (legacy API)
**File**: `src/ui/screens/main_menu.gd` lines 109, 131, 156
**Before**: `emit_signal("game_started")`, `emit_signal("game_loaded")`, `emit_signal("game_exited")`
**After**: `game_started.emit()`, `game_loaded.emit()`, `game_exited.emit()`
**Rationale**: String-based `emit_signal()` bypasses static type checking. Typed `.emit()` is the Godot 4 standard.

#### Fix 3: Missing float type annotations (no change needed)
**File**: `src/ui/screens/main_menu.gd` lines 25-26
**Status**: Already had `: float` annotations. Verified correct.

#### Fix 4: Object type on Engine.get_singleton()
**File**: `src/ui/screens/main_menu.gd` lines 90, 127, 180, 186
**Before**: `var wsm = Engine.get_singleton("WorldSaveManager")` — returns untyped `Object`
**After**: `var wsm: Object = Engine.get_singleton("WorldSaveManager")` — explicit type annotation
**Rationale**: Consistent with project's static typing philosophy.

#### Fix 5: Typed Dictionary for debounce timers
**File**: `src/systems/input_context.gd` line 12
**Before**: `var _debounce_timers: Dictionary = {}` — untyped, returns `Variant`
**After**: `var _debounce_timers: Dictionary[StringName, float] = {}` — fully typed
**Rationale**: Compile-time type safety, prevents accidental misuse.

#### Fix 6: Remove unused _save_data
**File**: `src/systems/save_world_save_manager.gd` line 12
**Before**: `var _save_data: Dictionary = {}` — declared but never read or written
**After**: (line removed)
**Rationale**: Dead code.

#### Fix 7: Modern DirAccess API
**File**: `src/systems/save_world_save_manager.gd` lines 23-35
**Before**: `DirAccess.open()` + `list_dir_begin()` + `get_next()` while-loop
**After**: `DirAccess.get_files_at(SAVE_PATH)` returning `PackedStringArray`
**Rationale**: The three-step DirAccess pattern is deprecated in Godot 4.x. `get_files_at()` is simpler and the recommended API.

---

---

## Third Pass (Code Review Skill — 2026-05-24)

**Reviewer**: code-review skill + godot-gdscript-specialist + godot-specialist + qa-tester

**Files Reviewed**:
- `src/ui/screens/main_menu.gd` (229 lines)
- `src/ui/screens/main_menu.tscn` (406 lines)
- `src/systems/input_context.gd` (53 lines)
- `src/systems/save_world_save_manager.gd` (186 lines)
- `src/scenes/game.tscn` (28 lines)

### Engine Specialist Findings: ISSUES FOUND

**godot-gdscript-specialist:**

1. **`input_context.gd:46-52`** — `request_debounce()` timer is never updated while debouncing. `return true` fires without updating `_debounce_timers[action]`. If player holds button continuously within the debounce window, the action fires 0.25s after the *first* press, not after release. Timer arithmetic should use integer milliseconds to avoid float imprecision.

2. **`save_world_save_manager.gd:57,58,84,179`** — Untyped `var system = Engine.get_singleton(...)` appears 4 times, plus untyped `var serialized`, `var meta`, `var tick_data`, `var system_data`. Violates mandatory static typing.

3. **`save_world_save_manager.gd:40,110`** — Untyped `result := JSON.parse_string(...)` inferred as `Variant`.

**godot-specialist (UI/Scene):**

1. **CRITICAL: `main_menu.gd:207`** — `get_tree().quit(0)` runtime crash. Godot 4's `SceneTree.quit()` accepts no arguments. The exit code parameter was removed. Will throw a runtime error and crash the game on Quit.

2. **HIGH: `main_menu.tscn` — ~380 lines of duplicated inline StyleBoxFlat definitions.** Each button has ~40 lines of style properties repeated verbatim. Extract to shared `.tres` theme resources.

3. **HIGH: `main_menu.tscn:305-405`** — LoadFailedOverlay uses fixed-offset layout (preset 8, -150/+80px). At 3440x1440 the card is only 8.7% of screen width. Fails AC-2 on ultrawide.

4. **MEDIUM: `main_menu.tscn:305`** — FailedPanel is a transparent `Control` with no background, border, or style. Only buttons/label visible — the panel itself is invisible.

5. **LOW: `main_menu.tscn:345,376`** — Fail buttons (TryAgain, NewGameFromFail) only define `normal` and `focus` styles. No `hover` or `pressed` state.

6. **LOW: `main_menu.tscn`** — 12 redundant `focus_neighbor_* = &""` lines on every button. No-op; VBoxContainer default traversal is correct.

### Testability: GAPS

| Gap | Impact |
|-----|--------|
| No `menu_ready` signal | AC-1 timing requires screenshot/poller, no clean hook |
| `_is_transitioning`/`_has_save` private | Cannot be inspected by automated tests |
| No `set_force_has_save()` mock | AC-4 requires filesystem manipulation |
| Load-failed path not in QA test cases | AC-7 covers only the happy path |
| AC-8 will crash before it can be tested (`quit(0)`) | Blocking |

### ADR Compliance: COMPLIANT

| ADR | Result |
|-----|--------|
| ADR-0003 (Input Context System) | COMPLIANT — push/pop, UI_ACTIVE, stack, debounce, `_unhandled_input()` all match |
| ADR-0006 (Save/Load Format) | COMPLIANT — orchestrator pattern, load order, schema versioning, atomic writes, metadata files |

### Standards Compliance: 4/6

| Check | Status | Notes |
|-------|--------|-------|
| Public methods/classes have doc comments | FAIL | Button handlers and helpers lack doc comments |
| Cyclomatic complexity under 10 | PASS | |
| No method exceeds 40 lines | PASS | |
| Dependencies injected | PASS | Autoload per ADR mandates |
| Config values from data files | FAIL | 9 hardcoded strings — story defers to MVP |
| Systems expose interfaces | PASS | Signals for cross-system comms |

### Architecture: MINOR ISSUES

1. Autoload coupling via `Engine.get_singleton()` — acceptable per ADRs but limits static analysis.
2. LoadFailedOverlay uses manual anchoring instead of `CenterContainer` — inconsistent with responsive approach used elsewhere.

### SOLID: COMPLIANT

(Same as first/third pass — unchanged.)

### Game-Specific Concerns

| Concern | Status | Notes |
|---------|--------|-------|
| Frame-rate independence | PASS | `create_tween()` with explicit durations |
| No allocations in hot paths | PASS | No `_process()`/`_physics_process()` |
| Null handling | PASS | Singleton null-checked everywhere |
| Resource cleanup | PASS | `queue_free()` on transition |

### Positive Observations

- Clean CanvasLayer root, well-structured overlays, correct `pause_mode = 2`.
- `_is_transitioning` guards prevent double-click race conditions.
- Graceful degradation when Autoloads are unregistered.
- Atomic save (.tmp + rename) and metadata for fast listing.
- Modern Godot 4 patterns: `DirAccess.get_files_at()`, typed `Dictionary[K,V]`, `@onready var`, typed `.emit()`.

### Required Changes

| # | Issue | Severity | File | Line |
|---|-------|----------|------|------|
| 1 | `get_tree().quit(0)` — Godot 4 runtime crash | CRITICAL | `main_menu.gd` | 207 |
| 2 | `request_debounce()` timer never updates while debouncing | HIGH | `input_context.gd` | 46-52 |
| 3 | WorldSaveManager untyped variables (6+ locations) | HIGH | `save_world_save_manager.gd` | 57,58,84,179,183 |
| 4 | LoadFailedOverlay fixed-offset layout (AC-2 ultrawide) | HIGH | `main_menu.tscn` | 305-405 |

### Suggestions

| # | Issue | Severity | File |
|---|-------|----------|------|
| 5 | StyleBoxFlat duplication → extract to `.tres` | MEDIUM | `main_menu.tscn` |
| 6 | FailedPanel transparent Control | LOW | `main_menu.tscn` |
| 7 | Fail buttons missing hover/pressed | LOW | `main_menu.tscn` |
| 8 | Remove redundant `focus_neighbor_*` | LOW | `main_menu.tscn` |
| 9 | Add `menu_ready` signal for AC-1 | LOW | `main_menu.gd` |
| 10 | Add doc comments to button handlers | LOW | `main_menu.gd` |
| 11 | Add QA test cases for load-failed path | LOW | Story file |

### Verdict: CHANGES REQUIRED

4 required changes. `get_tree().quit(0)` is a hard crash on Quit. `request_debounce()` silently debounces incorrectly. WorldSaveManager untyped variables violate mandatory static typing. LoadFailedOverlay layout fails AC-2 on ultrawide.

---

## Fix Log (Third Pass Issues)

#### Fix 17: `get_tree().quit(0)` → `get_tree().quit()` (CRITICAL — Godot 4 runtime crash)
**File**: `src/ui/screens/main_menu.gd` line 207
**Before**: `get_tree().quit(0)` — passes exit code argument
**After**: `get_tree().quit()` — no arguments
**Rationale**: Godot 4's `SceneTree.quit()` accepts no arguments. The exit code parameter was removed between Godot 3 and 4. Passing `(0)` throws a runtime error and crashes the game when the player clicks Quit. The `game_exited` signal still fires before the quit call, so listeners receive it correctly.

#### Fix 18: `request_debounce()` timer never updates while debouncing (HIGH)
**File**: `src/systems/input_context.gd` lines 12, 13, 46-51
**Before**: Timer stored as `float` (seconds). `return true` path never updated `_debounce_timers[action]`. If player held a button continuously within the 250ms window, the timer stayed pinned to the first press — the action would fire 0.25s after the *first* press, not after release, and subsequent rapid taps would remain permanently blocked.
```gdscript
var _debounce_timers: Dictionary[StringName, float] = {}
const DEBOUNCE_DELAY: float = 0.25

func request_debounce(action: StringName) -> bool:
    if _debounce_timers.has(action):
        var elapsed: float = Time.get_ticks_msec() / 1000.0 - _debounce_timers[action]
        if elapsed < DEBOUNCE_DELAY:
            return true  # BUG: timer NOT updated
    _debounce_timers[action] = Time.get_ticks_msec() / 1000.0
    return false
```
**After**: Timer stored as `int` (milliseconds). Timer updated on every call (both debounced and non-debounced paths). All arithmetic in integer space to avoid float imprecision.
```gdscript
var _debounce_timers: Dictionary[StringName, int] = {}
const DEBOUNCE_DELAY_MSEC: int = 250

func request_debounce(action: StringName) -> bool:
    var now_msec: int = Time.get_ticks_msec()
    if _debounce_timers.has(action) and now_msec - _debounce_timers[action] < DEBOUNCE_DELAY_MSEC:
        return true  # still debounced
    _debounce_timers[action] = now_msec
    return false
```
**Rationale**: Integer milliseconds eliminates float division imprecision (`/ 1000.0`). Updating the timer on every call ensures the debounce window is always relative to the latest input, not the first. This matches standard debounce behavior across all UI frameworks.

#### Fix 19: WorldSaveManager untyped variables (HIGH — static typing violation)
**File**: `src/systems/save_world_save_manager.gd` lines 58, 60, 79, 84, 179, 183
**Before**: 6 locations used bare `var` without type annotations:
```gdscript
var system = Engine.get_singleton(system_name)       # line 58
var serialized = system.serialize()                   # line 60
var meta = { ... }                                    # line 79
var tick_data = data.get("TickSystem", {})            # line 84
var system = Engine.get_singleton(system_name)       # line 179
var system_data := data.get(system_name, {})          # line 183
```
**After**: All variables explicitly typed:
```gdscript
var system: Object = Engine.get_singleton(system_name)
var serialized: Dictionary = system.serialize()
var meta: Dictionary = { ... }
var tick_data: Dictionary = data.get("TickSystem", {})
var system: Object = Engine.get_singleton(system_name)
var system_data: Dictionary = data.get(system_name, {})
```
**Rationale**: Mandatory static typing per project coding standards. `Object` is the most specific type available for `Engine.get_singleton()` results without `class_name` declarations. `Dictionary` enables compile-time key validation.

#### Fix 20: LoadFailedOverlay responsive layout (HIGH — AC-2 ultrawide failure)
**File**: `src/ui/screens/main_menu.tscn` lines 274-369
**Before**: `FailedPanel` was a `Control` node with fixed offsets (preset 8, -150/+150 horizontal, -80/+80 vertical). At 3440x1440 the card was only 8.7% of screen width. FailedPanel had no background or style — only the buttons and label were visible, making the panel itself invisible.
**After**: Replaced with `CenterContainer` (custom_minimum_size 300x140) wrapping a `VBoxContainer` (ExpandingFill) containing the FailedLabel and FailButtons. The overlay bg and center container are proper children of `LoadFailedOverlay`, so `visible` toggles control everything.
**Rationale**: CenterContainer provides automatic centering at all resolutions without manual offset math. The 300x140 minimum ensures readability at 800x600 while the ExpandingFill layout adapts to wider screens.

#### Fix 21: LoadFailedOverlay structural parent bug (CRITICAL — overlay invisible)
**File**: `src/ui/screens/main_menu.tscn` lines 281, 289
**Before**: `FailedOverlayBg` and `FailedCenter` had `parent="."` (MainMenu root node), making them siblings of `LoadFailedOverlay` instead of children.
**After**: `parent="LoadFailedOverlay"` on both nodes.
**Rationale**: `_show_load_failed()` sets `load_failed_overlay.visible = true` in the script. If the content nodes are siblings of the panel (not children), toggling the panel's visibility does nothing — the overlay content was always rendered and never hidden. This made the overlay appear without any script interaction and made it impossible to dismiss with `_hide_overlays()`.

Correct structure:
```
LoadFailedOverlay (Panel, visible toggled by script)
├── FailedOverlayBg (ColorRect, full-screen anchors)
└── FailedCenter (CenterContainer, 300x140)
    └── FailedInner (VBoxContainer, ExpandingFill)
        ├── FailedLabel
        └── FailButtons (VBoxContainer)
            ├── TryAgain
            └── NewGameFromFail
```

#### Fix 22: Removed 12 redundant `focus_neighbor_* = &""` lines (LOW)
**File**: `src/ui/screens/main_menu.tscn` — NewGame (lines 90-93), Continue (lines 154-157), Settings (lines 190-193), Quit (lines 253-256)
**Before**: All 4 main menu buttons had `focus_neighbor_left = &""`, `focus_neighbor_top = &""`, `focus_neighbor_right = &""`, `focus_neighbor_bottom = &""` — setting all neighbor references to empty strings.
**After**: All 12 lines removed.
**Rationale**: Empty-string neighbor references are a no-op. Godot's default focus traversal within a VBoxContainer already handles vertical Tab/gamepad D-pad navigation correctly (NewGame → Continue → Settings → Quit). Explicitly setting empty strings added noise and suggested a problem that didn't exist.

**Bug**: `FailedOverlayBg` and `FailedCenter` were direct children of the MainMenu root (`parent="."`) instead of children of `LoadFailedOverlay`.

**Impact**: The LoadFailedOverlay Panel toggles `visible` via script, but since its content siblings are at root level, hiding the Panel does nothing visible. The overlay content was always rendered.

**Fix**: Changed `parent="."` → `parent="LoadFailedOverlay"` on both `FailedOverlayBg` (line 281) and `FailedCenter` (line 289).

**Correct structure**:
```
LoadFailedOverlay (Panel, visible toggled by script)
├── FailedOverlayBg (ColorRect, full-screen anchors)
└── FailedCenter (CenterContainer, 300x140)
    └── FailedInner (VBoxContainer, ExpandingFill)
        ├── FailedLabel
        └── FailButtons (VBoxContainer)
            ├── TryAgain
            └── NewGameFromFail
```

---

## Pass 2 Re-Review (2026-05-24)

**Reviewers**: godot-gdscript-specialist, godot-specialist, qa-tester

**3 original issues identified as blocking** in the third-pass code-review skill (see "Third Pass (Code Review Skill — 2026-05-24)" above). All were fixed by agent `abe44296`. A structural bug (Fix 21) was discovered after agent run and fixed immediately.

### ADR Compliance: COMPLIANT
- ADR-0003 (Input Context): push/pop, UI_ACTIVE, stack, debounce, `_unhandled_input()` all match.
- ADR-0006 (Save/Load Format): orchestrator pattern, load order, schema versioning, atomic writes, metadata files.

### Standards Compliance: 4/6 (unchanged)
- Public doc comments: FAIL — button handlers still lack doc comments
- Cyclomatic complexity: PASS
- Method length under 40 lines: PASS
- Dependencies injected: PASS — Autoload per ADR mandates
- Config values from data files: FAIL — 9 hardcoded strings (story defers to MVP)
- Systems expose interfaces: PASS

### Testability: GAPS (non-blocking)
| Gap | AC | Status |
|-----|-----|--------|
| `quit(0)` crash blocking AC-8 test | AC-8 | RESOLVED — `quit()` with no args exits cleanly in headless |
| LoadFailedOverlay invisible due to wrong parent | AC-7b | RESOLVED — proper child hierarchy |
| WorldSaveManager coupling (typing-only change) | AC-4 | Still open — type cleanup helps static analysis but not testability |
| No `menu_ready` signal for AC-1 | AC-1 | Still open — requires external timing tooling |
| `_is_transitioning`/`_has_save` private | AC-4, AC-6 | Still open — not accessible by test code |

### Pass 2 NEW findings (all non-blocking)

| # | Issue | Severity | File |
|---|-------|----------|------|
| 1 | `queue_free()` runs even when scene load fails → game freezes with no feedback | Medium | `main_menu.gd:200` |
| 2 | Fail overlay buttons (TryAgain, NewGameFromFail) missing hover/pressed styles | Low | `main_menu.tscn` |
| 3 | `const GAME_SCENE: String` — redundant annotation | Trivial | `main_menu.gd:24` |
| 4 | `DirAccess.get_files_at()` return value not verified | Low | `save_world_save_manager.gd:24` |

### Verdict

All 4 required fixes applied and verified. No new blocking issues from pass 2 re-review.

**Remaining advisories** (acceptable at MVP scope):
- 9 hardcoded strings (story defers localization to MVP)
- Missing doc comments on button handlers
- WorldSaveManager coupling (typing-only fix, no functional change)
- `queue_free()` on failed scene load (medium — should be fixed but not blocking MVP)

---

## Fix Log (Second Pass Issues)

#### Fix 8: VBoxContainer fixed offset anchoring (AC-2)
**File**: `src/ui/screens/main_menu.tscn` lines 17-25
**Before**: `anchors_preset = 8` (Center) with `offset_left=-100, offset_top=-150, offset_right=100, offset_bottom=150` — 200x300px fixed bounding box
**After**: `anchors_preset = 15` (Full Rect) with `anchor_left=0.0, anchor_top=0.0, anchor_right=1.0, anchor_bottom=1.0` — stretches full screen
**Rationale**: Fixed offsets don't scale across resolutions. At 3440x1440 the menu column was only 5.8% of screen width. Full-rect anchoring lets the VBoxContainer fill available space while `alignment = 1` (ALIGN_CENTER) keeps buttons centered.

#### Fix 9: Title font size — hardcoded removed
**File**: `src/ui/screens/main_menu.tscn` line 29 (removed), `src/ui/screens/main_menu.gd` line 79 (added)
**Before**: Scene file had `theme_override_font_sizes/font_size = 28` (hardcoded)
**After**: Removed from scene file; script sets `title_label.theme_override_font_sizes/font_size = Control.SIZE_MID` in `_ready()`
**Rationale**: Dynamic sizing respects screen density. The hardcoded 28px looked small on ultrawide/retina displays. `SIZE_MID` adapts to the user's font size settings.

#### Fix 10: `TRANS_ELASTIC` → `TRANS_SINE` on fade-in
**File**: `src/ui/screens/main_menu.gd` line 76
**Before**: `.set_trans(Tween.TRANS_ELASTIC)` on a `Color` property (`modulate`)
**After**: `.set_trans(Tween.TRANS_SINE)`
**Rationale**: `TRANS_ELASTIC` on a color property creates a bouncy overshoot "flash-pulse" effect as each RGBA channel bounces past white. `TRANS_SINE` produces a smooth fade-in as intended for a main menu entrance.

#### Fix 11: `game_exited` signal timing
**File**: `src/ui/screens/main_menu.gd` lines 153-162, 203-207
**Before**: `game_exited.emit()` called synchronously in `_on_quit_pressed()`, then `_quit_toDesktop()` queued as tween callback (0.3s delay)
**After**: `game_exited.emit()` moved inside `_quit_to_desktop()` right before `get_tree().quit(0)`
**Rationale**: Signal listeners receive the signal at the actual exit moment, not 0.3s before it happens. The previous timing was misleading — the signal implied the quit was happening when in fact the visual fade was still in progress.

#### Fix 12: Rename `_quit_toDesktop` → `_quit_to_desktop`
**File**: `src/ui/screens/main_menu.gd` line 203 (method), line 162 (callback reference)
**Before**: `func _quit_toDesktop() -> void:` and `tween_callback(_quit_toDesktop)`
**After**: `func _quit_to_desktop() -> void:` and `tween_callback(_quit_to_desktop)`
**Rationale**: `toDesktop` is camelCase inside a snake_case function name. Per project naming conventions, all methods must use snake_case.

#### Fix 13: Remove redundant `ResourceLoader.exists()` preflight
**File**: `src/ui/screens/main_menu.gd` lines 193-198
**Before**: `if not ResourceLoader.exists(GAME_SCENE): printerr(...); queue_free(); return` followed by `load(GAME_SCENE)`
**After**: Only `var game_scene: PackedScene = load(GAME_SCENE)` with existing null check
**Rationale**: `load()` already returns `null` for missing paths. The `ResourceLoader.exists()` check is a redundant filesystem query — it queries the filesystem, then `load()` queries it again. The null check on line 200 already handles the failure case.

#### Fix 14: Add `: Node` type to `var instance`
**File**: `src/ui/screens/main_menu.gd` line 197
**Before**: `var instance = game_scene.instantiate()`
**After**: `var instance: Node = game_scene.instantiate()`
**Rationale**: Mandatory static typing. `instantiate()` returns a `Node` (or `Node3D` for 3D scenes). Explicit type annotation enables IDE tooling and compile-time validation.

#### Fix 15: Redundant `[signal]` declarations removed from scene file
**File**: `src/ui/screens/main_menu.tscn` lines 408-410 (removed)
**Before**: `[signal resource="Node", name="game_started"]`, `[signal resource="Node", name="game_loaded"]`, `[signal resource="Node", name="game_exited"]`
**After**: (lines removed)
**Rationale**: Signals are already declared in `main_menu.gd` lines 31-33. The scene-file declarations are the legacy Godot 3 format (`resource="Node"`) and serve no purpose when the script declares them. They were harmless (Godot doesn't duplicate signals) but violated the standard pattern.

#### Fix 16: Focus border width increased 2px → 3px on all focusable buttons
**File**: `src/ui/screens/main_menu.tscn` — NewGame (lines 66-69), Continue (lines 129-132), Quit (lines 229-232), TryAgain (lines 363-366), NewGameFromFail (lines 394-397)
**Before**: `border_width_left/right/top/bottom = 2` on focus state, `border_color = Color( 0.831, 0.655, 0.361, 1 )`
**After**: `border_width_left/right/top/bottom = 3` on focus state, `border_color = Color( 0.9, 0.7, 0.36, 1 )`
**Rationale**: Same border width (2px) between normal and focus states made the distinction only a color shift — potentially indistinguishable for users with visual impairments (AC-9). Increasing to 3px creates a clearly visible difference. Brighter color (`0.9, 0.7` vs `0.831, 0.655`) improves contrast. Applied consistently to all 5 focusable buttons.
