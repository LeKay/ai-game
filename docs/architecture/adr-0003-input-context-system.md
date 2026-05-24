# ADR-0003: Input Context System and Action Mapping

## Status
Accepted

## Date
2026-05-13

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Input |
| **Knowledge Risk** | MEDIUM — SDL3 backend (4.5), API unchanged; Dual-focus system (4.6) |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/modules/input.md` |
| **Post-Cutoff APIs Used** | None — InputMap and Input singletons are stable since Godot 1.0 |
| **Verification Required** | Test dual-focus behavior: keyboard grab_focus() vs mouse hover are separate in 4.6; verify SDL3 gamepad mapping works with Input.is_action_just_pressed() |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None — lowest infrastructure layer (foundation input) |
| **Enables** | Player Character, Camera, HUD, Building, All UI Systems — every system consumes input |
| **Blocks** | All player-facing interaction systems |
| **Ordering Note** | Must be Accepted before any system that handles input can be implemented |

## Context

### Problem Statement

The game needs a unified input system that maps physical inputs (keyboard, mouse, gamepad) to semantic game actions, manages input context switching (world interaction vs. UI navigation vs. paused), and handles Godot 4.6's dual-focus behavior (separate keyboard/gamepad focus from mouse focus). All gameplay systems need consistent action gating — for example, movement keys should be ignored when the inventory menu is open, but pause toggle must always work.

### Constraints

- **Unified action mapping**: Keyboard/mouse and gamepad inputs must map to the same semantic actions.
- **Context stack**: Input contexts follow a push/pop model — UI menus push UI_ACTIVE, pop restores previous context.
- **Pause is global**: `pause_toggle` always works regardless of context (must be handled at engine level, not in InputContext).
- **Godot 4.6 dual-focus**: Keyboard/gamepad focus and mouse focus are SEPARATE. `grab_focus()` only affects keyboard focus, not mouse hover. Must handle both paths.
- **SDL3 backend** (4.5): Gamepad driver delegated to SDL library — API unchanged, but backend detection and button mapping may differ.
- **Input debouncing**: Rapid presses must not trigger duplicate actions (e.g., double-tapping pause).

### Requirements

- Three contexts: WORLD_ACTIVE, UI_ACTIVE, PAUSED
- Push/pop context stack
- Context transition on UI open/close
- Input debouncing for rapid presses
- Mouse position → world tile coordinate conversion
- Keyboard/mouse + gamepad unified action mapping

## Decision

### Input Context Stack

InputContext is implemented as an **Autoload singleton** (`extends Node`) using a **push/pop stack** for context management. This is consistent with the Autoload decisions in ADR-0001 (TickSystem) and ADR-0002 (ResourceRegistry), providing a unified architectural pattern across all Foundation layer systems.

```
Stack depth: 0 → WORLD_ACTIVE (default)
Stack depth: 1+ → pushed contexts override default
Top of stack determines active context
Pop restores previous context
```

### Why Autoload

Consistency with other Foundation systems. The InputContext is needed from project start, before any scene tree exists. An Autoload provides:
- Always available at any time, even during scene loading
- No dependency injection required for a system that reads input
- Consistent with TickSystem and ResourceRegistry Autoload pattern
- Simplest pattern for a global input gate

### Context Stack Implementation

```gdscript
extends Node

enum Context { WORLD_ACTIVE, UI_ACTIVE, PAUSED }

signal context_changed(new_context: Context)

var _context_stack: Array[Context] = [Context.WORLD_ACTIVE]
var _debounce_timers: Dictionary = {}
const DEBOUNCE_DELAY: float = 0.25  # seconds

func get_current() -> Context:
    return _context_stack.back()

func push_context(ctx: Context) -> void:
    var previous: Context = _context_stack.back()
    _context_stack.append(ctx)
    if ctx != previous:
        context_changed.emit(ctx)

func pop_context() -> void:
    if _context_stack.size() > 1:
        var previous: Context = _context_stack.pop_back()
        var restored: Context = _context_stack.back()
        if restored != previous:
            context_changed.emit(restored)

func is_context_active(ctx: Context) -> bool:
    return _context_stack.back() == ctx

func request_debounce(action: StringName) -> bool:
    if _debounce_timers.has(action):
        var elapsed: float = Time.get_ticks_msec() / 1000.0 - _debounce_timers[action]
        if elapsed < DEBOUNCE_DELAY:
            return true  # still debounced
    _debounce_timers[action] = Time.get_ticks_msec() / 1000.0
    return false
```

### Action Mapping

The project uses **Godot 4.6's native InputMap** for action definitions, with actions configured in the Godot editor's Input Map settings. Actions are declared as StringName constants in a shared GDScript:

```gdscript
# constants/input_actions.gd
static var MOVE_UP := &"move_up"
static var MOVE_DOWN := &"move_down"
static var MOVE_LEFT := &"move_left"
static var MOVE_RIGHT := &"move_right"
static var INTERACT := &"interact"
static var CANCEL_ACTION := &"cancel_action"
static var OPEN_BUILD_MENU := &"open_build_menu"
static var PAUSE_TOGGLE := &"pause_toggle"
static var SPEED_INCREASE := &"speed_increase"
static var SPEED_DECREASE := &"speed_decrease"
static var UI_CONFIRM := &"ui_confirm"
static var UI_CANCEL := &"ui_cancel"
```

This avoids string literals in input queries and enables IDE refactoring of action names.

### Input Dispatch Flow

The InputContext integrates with Godot's input dispatch via `_unhandled_input()`.

**Critical detail**: `_unhandled_input()` only receives events NOT consumed by Control nodes. Mouse clicks on UI buttons, typed text in RichTextLabel, and gamepad navigation that matches a Control node's `shortcut` are consumed by the Control node's focus system and NEVER reach `_unhandled_input()`. The Autoload's `_unhandled_input()` is therefore the correct place for game-level input gating, not UI input.

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    var ctx: Context = get_current()

    # Global actions always pass through (keyboard/gamepad only —
    # mouse clicks on UI Control nodes are consumed before reaching here)
    if _is_global_action(event):
        InputDispatcher.dispatch(event)
        return

    # Context-gated actions
    if ctx == Context.PAUSED:
        # Only allow pause-related actions in PAUSED
        if _is_pause_action(event):
            InputDispatcher.dispatch(event)
        return

    if ctx == Context.WORLD_ACTIVE:
        InputDispatcher.dispatch(event)
        return

    if ctx == Context.UI_ACTIVE:
        # All UI actions are consumed by Control nodes (not unhandled).
        # If an unhandled event reaches here, it's a non-UI action
        # (e.g., WASD pressed while inventory is open) — discard it.
        return
```

### Godot 4.6 Dual-Focus Handling

The InputContext does **not** manage dual-focus directly — that is the responsibility of the HUD/Presentation layer. However, the InputContext ADR establishes the contract:

**Rule**: InputContext treats keyboard/gamepad input and mouse input as equivalent for context gating. The `get_current()` context determines which actions are allowed, regardless of input method. Dual-focus (visual feedback, grab_focus behavior) is handled separately by the UI system.

**InputContext is dual-focus agnostic**: It only asks "what context am I in?" and "is this action allowed?" The answer is the same for keyboard and mouse. The HUD system is responsible for managing keyboard vs. mouse visual feedback independently.

### Decebounce Mechanism

Debounce is implemented as a simple timer-based gate. When an action is requested:
1. Check if the same action was requested within `DEBOUNCE_DELAY` (default 0.25s)
2. If yes, return true (debounced — discard input)
3. If no, record the timestamp and return false (action proceeds)

Debounce timers are keyed by action name (StringName) and stored in a Dictionary. Timers persist until the game ends (no cleanup needed for Vertical Slice).

### Architecture Diagram

```
┌─────────────────────────────────────────────┐
│  Godot InputMap (editor-configured)         │
│  move_up, interact, pause_toggle, ...       │
└────────────────────┬────────────────────────┘
                     │ Input.is_action_just_pressed(action)
                     ▼
┌─────────────────────────────────────────────┐
│  _unhandled_input(event: InputEvent)         │
│  (on InputContext Autoload)                 │
│                                             │
│  1. Is this a global action? → yes → pass   │
│  2. Get current context from stack top      │
│  3. Is action allowed in this context?      │
│     - WORLD_ACTIVE: all non-UI actions      │
│     - UI_ACTIVE: UI actions only            │
│     - PAUSED: pause actions only            │
│  4. Is action debounced? → yes → discard    │
│  5. Dispatch to InputDispatcher             │
└────────────────────┬────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│  InputDispatcher (module)                   │
│                                             │
│  Routes actions to subscribed systems:      │
│  ├── PlayerCharacter (move, interact)        │
│  ├── CameraController (pan, zoom)            │
│  ├── TickSystem (pause, speed)               │
│  └── UI systems (confirm, cancel)            │
└─────────────────────────────────────────────┘
```

### Key Interfaces

**Methods (called by other systems):**
```gdscript
func get_current() -> Context
    # Returns the active context (top of stack).
    # Default: WORLD_ACTIVE.

func push_context(ctx: Context) -> void
    # Push a new context onto the stack.
    # Call when opening a menu/screen.
    # Fires context_changed signal if context actually changes.

func pop_context() -> void
    # Pop the top context, restoring the previous one.
    # Call when closing a menu/screen.
    # Fires context_changed signal if context actually changes.
    # No-op if stack has only 1 element.

func request_debounce(action: StringName) -> bool
    # Returns true if action is currently debounced (discard).
    # Call BEFORE dispatching the action.
    # DEBOUNCE_DELAY: 0.25s.

func is_context_active(ctx: Context) -> bool
    # Quick check: is the given context at the top of the stack?
```

**Signals:**
```gdscript
signal context_changed(new_context: Context)
    # Fired by push_context/pop_context when the active context changes.
    # Consumers (HUD, PlayerCharacter) can react to context transitions.
```

**Global action handling:**
- `pause_toggle` and `speed_increase`/`speed_decrease` are treated as **global** — they always pass through `_unhandled_input()` regardless of context.
- This is implemented in the global action check (`_is_global_action`), not delegated to individual systems.

## Alternatives Considered

### Alternative A: Scene-Instanced InputContext with Dependency Injection

**Description**: InputContext is a node in a root `World.tscn` scene. All systems receive a reference via `_enter_tree()` lookup or explicit dependency injection.

**Pros**: Testable in isolation (can instantiate World.tscn with mocked systems); no Autoload coupling; explicit dependency ownership.

**Cons**: Requires a root scene (World.tscn) — adds complexity for minimal benefit; dependency injection overhead across 11+ systems; harder to access from signal handlers that don't have explicit references; inconsistent with TickSystem and ResourceRegistry Autoload pattern.

**Rejection Reason**: For this project's scale (single-player, no scene reloading, ~11 systems), the Autoload pattern is simpler and the testability benefit of scene-instancing is marginal. Consistency with other Foundation systems is more valuable.

### Alternative B: Custom Input Mapping File (input_map.cfg)

**Description**: Define action mappings in a project-local config file (INI/JSON) rather than Godot's native InputMap. Parse at startup and route inputs through a custom dispatcher.

**Pros**: Fully data-driven; keybindings can be saved to disk without accessing Godot editor; supports per-profile mapping.

**Cons**: Godot 4.6 already has robust InputMap with editor UI; reinventing keybinding storage conflicts with Godot's built-in settings system; custom mapping file duplicates Godot's functionality; Godot's event system already converts hardware input → action events.

**Rejection Reason**: Godot's InputMap is a mature, well-tested system that handles all the project's needs. A custom mapping would add maintenance burden without meaningful benefits for the Vertical Slice scope.

### Alternative C: Context Switch via Signal Only (No Stack)

**Description**: Single active context with on/off signals. Push → emit `context_active`, Pop → emit `context_inactive`. No stack — just one current context.

**Pros**: Simpler implementation; no stack management.

**Cons**: Cannot handle nested UI (modal dialog on top of inventory). Pressing ESC on modal would close modal AND the inventory. No way to restore previous context.

**Rejection Reason**: The game will have nested UI (inventory → item description → building placement preview). A stack is necessary for correct context restoration.

## Consequences

### Positive
- **Context safety**: Stack-based push/pop prevents context confusion. Nested menus restore correctly.
- **Global actions**: Pause/speed controls always work, even in UI.
- **Debounce**: Simple timer-based debounce prevents double-pause and rapid-fire actions.
- **Dual-focus agnostic**: InputContext doesn't care about input method — only context and action allow/deny. Visual feedback is handled separately.
- **StringName actions**: IDE refactoring-safe; no typos in action names.
- **Consistent with ADR-0001/0002**: All Foundation systems use Autoload pattern.

### Negative
- **Autoload coupling**: InputContext as Autoload means any system can call it without explicit wiring. Mitigated by its read-only nature (gating, not mutation).
- **String-based action lookup**: `Input.is_action_just_pressed(action_string)` uses string comparison at runtime. StringName constants minimize this cost.
- **Debounce is coarse**: 0.25s debounce applies to ALL actions. Per-action debounce granularity would be better but adds complexity.

### Risks
- **SDL3 gamepad inconsistency**: Button mapping may differ from expectations due to SDL3 backend. Mitigation: test gamepad support when building for PC.
- **Stack imbalance**: If a developer forgets to call `pop_context()`, contexts accumulate and cannot be popped. Mitigation: log a warning on `push_context` when stack depth exceeds 3.
- **Pause in UI**: The GDD states pause toggle is deferred until menu closes rather than immediate when UI is open. If design changes to "pause always works in UI", the global action handling must be updated.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| input-system.md | Unified action mapping: keyboard+mouse + gamepad (TR-input-001) | Godot InputMap with StringName action constants; Input.is_action_just_pressed() abstracts hardware |
| input-system.md | Input context switching: WORLD_ACTIVE/UI_ACTIVE/PAUSED (TR-input-002) | Context enum + stack-based push/pop |
| input-system.md | Context transition on UI open/close (TR-input-003) | push_context() on UI open, pop_context() on UI close; context_changed signal for reaction |
| input-system.md | Input debouncing for rapid presses (TR-input-004) | request_debounce() timer-based gate (0.25s default) |
| input-system.md | Mouse position → world tile coordinate conversion (TR-input-005) | Delegated to CameraController.get_tile_at_screen() — InputContext provides context gating for the result |

## Performance Implications
- **CPU**: Negligible — `_unhandled_input()` fires only for unhandled events (typically tens per second). Context check: O(1) stack peek. Debounce: Dictionary lookup + float comparison.
- **Memory**: 3 Context enums + stack (max depth ~5) + debounce Dictionary. < 1 KB.
- **Load Time**: None — no initialization cost.
- **Network**: N/A (single-player only).

## Migration Plan

This is a new system — no migration from existing code. The Autoload must be registered in project settings with the name `InputContext` and the path pointing to the InputContext scene/script.

## Validation Criteria
- [ ] `get_current()` returns `WORLD_ACTIVE` by default
- [ ] `push_context(UI_ACTIVE)` followed by `get_current()` returns `UI_ACTIVE`
- [ ] `pop_context()` after one push restores `WORLD_ACTIVE`
- [ ] `push_context(UI_ACTIVE)` → `push_context(PAUSED)` → `pop_context()` → `get_current()` returns `WORLD_ACTIVE`
- [ ] `request_debounce("pause_toggle")` called twice within 0.25s returns (true, false)
- [ ] `context_changed` signal fires on context transition
- [ ] `context_changed` signal does NOT fire on push/pop when context doesn't change
- [ ] Global actions (pause_toggle) pass through even when UI_ACTIVE

## Related Decisions
- ADR-0001: Tick System (InputContext calls TickSystem.advance_ticks_manual() for player actions)
- ADR-0002: Resource Data Registry (no direct dependency — InputContext reads no game data)
- ADR-0004: Grid Map Data Model (CameraController screen→tile uses InputContext to verify WORLD_ACTIVE)
