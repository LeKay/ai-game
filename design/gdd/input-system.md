# Input System

> **Status**: Designed
> **Author**: User + Claude (Sonnet 4.5)
> **Last Updated**: 2026-05-05
> **Implements Pillar**: Pillar 2 (Information Transparency)

## Overview

The Input System is the hardware-to-software bridge that converts raw keyboard, mouse, and (future) gamepad inputs into gameplay-meaningful events consumed by the Player Character System, Camera System, UI Systems, and Settings System. It provides a centralized input abstraction layer where physical key presses (`W`, `A`, `S`, `D`, `Space`, `Escape`) and mouse actions (click position, scroll wheel delta) are translated into semantic actions (`move_up`, `move_left`, `confirm`, `cancel`, `pause_toggle`). All gameplay systems subscribe to input events rather than polling hardware directly, enabling rebindable controls (Settings System can remap `W` → `↑` without touching gameplay code), input buffering during pause states, and clean separation between "what hardware did the player touch" and "what did the player intend to do."

For the player, the Input System is invisible when functioning correctly — they press `W` and the character moves up; they click a tree and the Manual Labor action starts. Its design serves **Pillar 2 (Information Transparency)** by ensuring input feedback is immediate and unambiguous (no mystery lag, no dropped inputs), and supports the game's **Submission aesthetic** (relaxation) by keeping controls simple and responsive rather than demanding complex combos or precise timing. The system distinguishes **UI input** (mouse clicks on buttons, menu navigation) from **world input** (WASD movement, tile clicks for harvesting), allowing the UI layer to consume mouse clicks without triggering world actions underneath.

## Player Fantasy

The Input System has no player fantasy — it exists to be invisible. When controls work perfectly, you don't think about them. You think "walk here" and press `W`, and the character walks. You think "chop that tree" and click it, and your character moves to chop it. The system succeeds when the gap between intent and action disappears.

The only time you notice the Input System is when it fails: a dropped click, a sluggish response, a key that doesn't register. Good input design is the absence of friction — the feeling that the game responds to your thoughts, not your fingers.

This is infrastructure, not experience. The fantasy belongs to what the input enables: the satisfaction of efficient village management (**Pillar 3**), the clarity of visible production chains (**Pillar 2**), the meditative flow of planning while paused (**Submission aesthetic**). The Input System's job is to stay out of the way.

## Detailed Design

### Core Rules

**1. Input Channels**

The Input System recognizes three hardware input channels:
- **Keyboard:** WASD movement, action keys (Space, E, Q, etc.), UI shortcuts (Escape, Tab, 1-9 hotkeys)
- **Mouse:** Position (screen coordinates), Left/Right/Middle clicks, scroll wheel delta
- **Gamepad:** (Future — not in Vertical Slice) D-pad, face buttons, analog sticks, triggers

**2. Action Mapping**

Physical inputs are mapped to semantic **Actions** via a configuration file (`input_map.cfg` or engine-native input map):

**Movement Actions:**
| Action ID | Default Keyboard | Default Mouse | Description |
|-----------|------------------|---------------|-------------|
| `move_up` | W | — | Move player character north |
| `move_down` | S | — | Move player character south |
| `move_left` | A | — | Move player character west |
| `move_right` | D | — | Move player character east |

**World Interaction Actions:**
| Action ID | Default Keyboard | Default Mouse | Description |
|-----------|------------------|---------------|-------------|
| `interact` | E | Left Click (world tile) | Harvest resource, open NPC menu, activate building |
| `cancel_action` | Escape | Right Click | Cancel queued manual action, deselect |
| `open_build_menu` | B | — | Open building placement UI |

**Camera Actions:**
| Action ID | Default Keyboard | Default Mouse | Description |
|-----------|------------------|---------------|-------------|
| `camera_pan` | Arrow keys | Middle Mouse Drag | Move camera viewport |
| `camera_zoom` | — | Scroll Wheel Up/Down | Zoom camera toward/away from cursor (normalized delta) |

**Time Control Actions:**
| Action ID | Default Keyboard | Default Mouse | Description |
|-----------|------------------|---------------|-------------|
| `pause_toggle` | Space | — | Toggle between PAUSED and RUNNING (Tick System) |
| `speed_decrease` | , (Comma) | — | Cycle speed down (2x → 1x → 0.5x) |
| `speed_increase` | . (Period) | — | Cycle speed up (0.5x → 1x → 2x) |

**UI Actions:**
| Action ID | Default Keyboard | Default Mouse | Description |
|-----------|------------------|---------------|-------------|
| `ui_confirm` | Enter | Left Click (UI button) | Confirm dialog, activate button |
| `ui_cancel` | Escape | — | Close menu, cancel dialog |
| `hotbar_slot_1` to `_9` | 1-9 | — | Activate hotbar slot (future feature) |

**3. Input Events**

The Input System broadcasts events to subscribed systems:
- **`on_action_pressed(action_id: String)`** — Fires once when key/button is first pressed
- **`on_action_released(action_id: String)`** — Fires once when key/button is released
- **`on_action_held(action_id: String, duration_ms: int)`** — Fires every frame while key/button is held (duration increments)
- **`on_mouse_moved(screen_pos: Vector2, world_pos: Vector2)`** — Fires when mouse cursor moves (provides both screen-space and world-space coordinates)
- **`on_scroll(delta: float)`** — Fires when scroll wheel moves (positive = up, negative = down)

**4. Input Contexts**

The system operates in one of three **Input Contexts** at any time, which filter which actions are processed:
- **WORLD_ACTIVE:** Player can move, interact with world, control camera. UI hotkeys ignored (except pause).
- **UI_ACTIVE:** UI consumes mouse/keyboard input. WASD movement disabled. Escape closes menus.
- **PAUSED:** Only pause/unpause and UI navigation allowed. WASD, world clicks ignored.

Context transitions:
| From | To | Trigger |
|------|-----|---------|
| WORLD_ACTIVE | UI_ACTIVE | Player opens menu (Escape, B, Tab, etc.) |
| UI_ACTIVE | WORLD_ACTIVE | Player closes menu (Escape, click outside) |
| Any | PAUSED | Player presses Space (pause toggle) while in WORLD_ACTIVE |
| PAUSED | WORLD_ACTIVE | Player presses Space again |

**5. Input Buffering**

When an action is pressed during a context where it's ignored (e.g., WASD during UI_ACTIVE), the input is **discarded**, not buffered. This prevents accidental world actions when closing menus.

**Exception:** `pause_toggle` is always processed regardless of context (global action).

**6. Rebinding**

The Settings System can remap actions to different keys/buttons:
- Rebind interface: `InputSystem.rebind_action(action_id: String, new_key: KeyCode)`
- Validation: Prevent binding two actions to the same key (warn user, require override confirmation)
- Persistence: Rebinds saved to `user://settings/keybindings.cfg`
- Reset to defaults: `InputSystem.reset_bindings()`

### States and Transitions

The Input System has three states corresponding to Input Contexts:

| State | Active Actions | Mouse Behavior | Escape Key |
|-------|----------------|----------------|------------|
| **WORLD_ACTIVE** | Movement, world interaction, camera control, pause | Clicks interact with world tiles (harvesting, building placement) | Opens pause menu (transitions to UI_ACTIVE) |
| **UI_ACTIVE** | UI navigation, confirm/cancel | Clicks interact with UI elements only, world clicks ignored | Closes active menu (transitions back to WORLD_ACTIVE) |
| **PAUSED** | Pause toggle only | Clicks ignored (world frozen) | No effect (already paused, use Space to unpause) |

**State Diagram:**
```
WORLD_ACTIVE <--Escape/B--> UI_ACTIVE
     |                          |
  Space (pause)             Space* (deferred until menu closes)
     |                          |
     v                          v
   PAUSED <---Space (unpause)--- PAUSED
```

**Notes:**
- Space during UI_ACTIVE does NOT transition directly to PAUSED. Instead, the pause toggle is queued and applied when the menu closes (UI_ACTIVE → WORLD_ACTIVE → PAUSED). This prevents the "double-pause bug" where pausing while a menu is open freezes the game before the player can close the menu.

### Interactions with Other Systems

| System | Interaction | Data Flow | Interface |
|--------|-------------|-----------|-----------|
| **Player Character** | Processes movement and interaction actions | Input System → Player Character: `on_action_pressed("move_up")`, `on_action_pressed("interact")` | Player Character subscribes to movement/interaction events, translates to character movement/actions |
| **Camera** | Processes pan and zoom actions | Input System → Camera: `on_action_held("camera_pan")`, `on_scroll(delta)` → `camera_zoom` | Camera subscribes to camera actions, updates viewport position/zoom level |
| **Tick System** | Processes time control actions | Input System → Tick System: `on_action_pressed("pause_toggle")`, `on_action_pressed("speed_increase")` | Tick System subscribes to time control events, updates pause state and speed multiplier |
| **UI Systems** | Processes menu navigation and clicks | Input System → UI: `on_action_pressed("ui_confirm")`, `on_mouse_moved(screen_pos)`, `on_action_pressed("ui_cancel")` | UI systems set Input Context to UI_ACTIVE when menu opens, process UI-specific actions |
| **Settings** | Provides rebinding interface | Settings ↔ Input System: `rebind_action()`, `get_current_binding()`, `save_bindings()` | Settings reads current bindings, allows user to remap, saves to config |
| **Building System** | Processes build menu open and placement clicks | Input System → Building: `on_action_pressed("open_build_menu")`, `on_mouse_moved(world_pos)` (for placement preview) | Building System enters placement mode on build menu open, uses mouse world position for preview |
| **Manual Labor** | Processes interaction clicks on harvestable tiles | Input System → Manual Labor: `on_action_pressed("interact")` + `mouse_world_pos` | Manual Labor checks if clicked tile is harvestable, queues action if valid |

## Formulas

The Input System is primarily an event broadcaster and does not perform complex calculations. However, it does apply simple transformations to raw hardware input:

**1. Mouse World Position Conversion**

Convert screen-space mouse coordinates to world-space tile coordinates:

`world_pos = (camera_offset + (screen_pos / camera_zoom)) / tile_size`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| screen_pos | p_screen | Vector2 | (0, 0) to (screen_width, screen_height) | Mouse position in screen pixels |
| camera_offset | c_offset | Vector2 | Unbounded | Camera's top-left corner in world coordinates (pixels) |
| camera_zoom | z | float | 0.5–2.0 | Camera zoom level (1.0 = default) |
| tile_size | ts | int | 8–64 | Tile size in pixels — defined by Grid/Map System, not tunable here |
| world_pos | p_world | Vector2 | Grid bounds (0, 0) to (30, 30) tiles | Mouse position in world tile coordinates |

**Output Range:** (0, 0) to (30, 30) for main map; unbounded for overmap

**Example:**
```
screen_pos = (400, 300) pixels
camera_offset = (0, 0) pixels (camera at map origin)
camera_zoom = 1.0
tile_size = 16 (Grid/Map System definition)
world_pos = ((0 + (400, 300) / 1.0)) / 16 = (400, 300) / 16 = (25.0, 18.75) tiles
→ Player clicks tile at column 25, row 18
```

**Dependency:** `tile_size` value must match the Grid/Map System definition exactly. If the Grid/Map System changes tile size, this formula's output scale changes automatically.

**2. Input Delay (Performance Metric)**

Measure input lag from hardware event to gameplay response:

`input_delay_ms = event_timestamp - hardware_timestamp`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| hardware_timestamp | t_hw | int | 0–unbounded | OS timestamp when key was pressed (milliseconds) |
| event_timestamp | t_event | int | 0–unbounded | Game timestamp when event fired (milliseconds) |
| input_delay_ms | Δt | int | 0–100 | Measured input lag (milliseconds) |

**Output Range:** [0, 16] ms target (1 frame at 60fps); acceptable up to 100ms; above 100ms = perceptible lag

**Example:**
```
hardware_timestamp = 1000ms
event_timestamp = 1008ms
input_delay_ms = 1008 - 1000 = 8ms (half a frame — acceptable)
```

**3. Scroll Wheel Delta Normalization**

Normalize scroll wheel input across different mice/OS settings:

`scroll_delta_normalized = raw_delta × sensitivity`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| raw_delta | δ_raw | float | -10.0 to +10.0 | Raw scroll wheel delta from OS |
| sensitivity | s | float | 0.5–2.0 | User-adjustable scroll sensitivity (tuning knob) |
| scroll_delta_normalized | δ_norm | float | -20.0 to +20.0 | Normalized delta for camera zoom |

**Output Range:** [-20.0, +20.0] — Camera System consumes this value

**Example:**
```
raw_delta = 3.0 (3 notches up)
sensitivity = 1.0 (default)
scroll_delta_normalized = 3.0 × 1.0 = 3.0
```

## Edge Cases

**Input Context Conflicts:**
- **If UI menu opens while WASD is held**: Release all movement inputs immediately (prevent character sliding after menu closes). Broadcast `on_action_released` for active movement keys.
- **If player presses Escape while in PAUSED state**: No effect (Escape opens menus from WORLD_ACTIVE, not PAUSED). Use Space to unpause.
- **If player presses Space while in UI_ACTIVE (menu open)**: Pause is deferred until menu closes (prevents double-pause bug). Queue pause toggle for when context returns to WORLD_ACTIVE.

**Rebinding Edge Cases:**
- **If player rebinds action to already-used key**: Warn "This key is already bound to [other_action]. Override?" If yes: swap bindings (A→B, B→A). If no: cancel rebind.
- **If player rebinds essential action to unmappable key** (e.g., pause to Mouse Button 12 on 3-button mouse): Validation rejects rebind, shows error "Key not available on your hardware."
- **If keybindings.cfg is corrupted or missing**: Load default bindings, log warning, display "Keybindings reset to default" notification on first boot.

**Multi-Input Simultaneity:**
- **If player presses W+A simultaneously** (diagonal movement): Broadcast both `move_up` and `move_left` events. Player Character System resolves diagonal movement (normalize vector).
- **If player holds E (interact) and clicks different tiles rapidly**: Each click fires separate `on_action_pressed("interact")` event. Manual Labor System queues actions (processes one at a time, not simultaneously).
- **If player spams Space (pause toggle) rapidly**: Apply debounce (ignore repeat presses within 200ms of last toggle). Prevents accidental double-pause.

**Mouse Edge Cases:**
- **If mouse moves outside game window**: `on_mouse_moved` stops firing. Last known position held until mouse re-enters. No actions triggered while out-of-window.
- **If player clicks UI button that overlaps world tile**: UI layer consumes click (world tile does NOT receive `interact` event). UI has input priority in UI_ACTIVE context.
- **If scroll wheel delta is 0** (no scroll): No `on_scroll` event fires. Neutral state.

**Hardware Compatibility:**
- **If gamepad is connected but game in Keyboard/Mouse mode**: Gamepad inputs ignored (not bound to actions in Vertical Slice). HUD System displays one-time notification "Gamepad detected but not supported yet" on first connection.
- **If player has non-QWERTY keyboard layout** (AZERTY, Dvorak): Default WASD bindings may feel wrong. Settings System allows rebinding.
- **If mouse has >5 buttons**: Extra buttons (Button4, Button5, etc.) available for binding. Default unbound (no actions assigned).

**Performance Edge Cases:**
- **If input polling causes >16ms lag** (missing 60fps target): Log performance warning, investigate input event queue depth. May indicate event spam (e.g., buggy mouse driver sending 1000 move events/frame).
- **If input event queue exceeds 100 pending events**: Flush oldest 50% of queue, log critical error "Input overload detected." Prevents memory bloat from event backlog.

**Save/Load Edge Cases:**
- **If save has invalid keybindings** (action mapped to KeyCode that doesn't exist): Reset that specific binding to default, log warning, preserve other valid bindings.
- **If save has action with no binding** (e.g., `move_up` unmapped): Force default binding on load, notify player "Missing keybinding restored: W → move_up."

## Dependencies

**Upstream (depends on):**
- None — Input System is a Foundation layer system with zero dependencies

**Downstream (depended on by):**
- **Player Character System** — Processes movement (`move_up`, `move_down`, `move_left`, `move_right`) and interaction (`interact`) actions
- **Camera System** — Processes pan (`camera_pan`), zoom (`camera_zoom` via scroll), events
- **Tick System** — Processes time control (`pause_toggle`, `speed_increase`, `speed_decrease`) actions
- **UI Systems** — Processes UI navigation (`ui_confirm`, `ui_cancel`), mouse clicks, menu open/close (`Escape`, `B`, etc.)
- **Settings System** — Reads/writes keybindings, provides rebind UI
- **Building System** — Processes build menu open (`open_build_menu`), placement clicks (via `interact` + mouse world position)
- **Manual Labor System** — Processes harvest/gather clicks (via `interact` + mouse world position)
- **HUD System** — Displays keybinding hints (e.g., "Press B to build", "[Space] Pause")

**Interface Stability:**
- Action IDs (`move_up`, `pause_toggle`, etc.) are PERMANENT — never rename (breaks keybinding saves)
- Event signatures (`on_action_pressed(action_id)`) are stable — systems rely on this interface
- New actions can be added without breaking existing bindings
- Input Contexts (WORLD_ACTIVE, UI_ACTIVE, PAUSED) are core states — do not add new contexts without reviewing all dependent systems

## Tuning Knobs

| Knob | Type | Safe Range | Effect | Notes |
|------|------|------------|--------|-------|
| **scroll_sensitivity** | float | 0.5–2.0 | Scroll wheel zoom speed | Lower = finer control. Higher = faster zoom. Default: 1.0 |
| **pause_debounce_ms** | int | 100–500 ms | Minimum time between pause toggles | Prevents accidental double-pause. Default: 200ms |
| **input_queue_max** | int | 50–200 | Max pending input events before flush | Higher = more tolerance for lag spikes. Lower = faster flush. Default: 100 |
| **mouse_edge_pan_threshold** | int | 0–50 pixels | Distance from screen edge to trigger camera pan | 0 = disabled. Higher = larger edge zone. Default: 20px |
| **diagonal_movement_enabled** | bool | true/false | Allow W+A simultaneous press for diagonal movement | true = more fluid. false = lock to cardinal directions. Default: true |

**What breaks if tuned incorrectly:**
- `scroll_sensitivity > 5.0`: Camera zoom becomes hypersensitive, uncontrollable
- `pause_debounce_ms < 50`: Player can accidentally triple-pause by holding Space too long
- `input_queue_max > 500`: Memory bloat, event processing lag accumulates
- `mouse_edge_pan_threshold > 100`: Most of screen triggers edge pan, unusable

## Visual/Audio Requirements

The Input System is pure infrastructure and has no direct visual or audio components. It exists to translate hardware events into semantic actions for other systems to consume.

**No visual output** — Input System does not render anything to screen. Visual feedback for input (key hints, button prompts, rebinding UI) is owned by the **HUD System** and **Settings System**.

**No audio output** — Input System does not play sounds. Audio feedback for actions (button clicks, pause sound effects) is owned by the systems that consume the input events (e.g., UI System plays click SFX when `ui_confirm` fires).

## UI Requirements

The Input System provides data to UI systems but does not own any UI elements itself. UI for input-related features is divided among downstream systems:

**Keybinding Hints (HUD System):**
- Display context-sensitive key hints in bottom-right corner (e.g., "[E] Interact", "[Space] Pause", "[B] Build")
- Update hints dynamically when input context changes (WORLD_ACTIVE shows game controls, UI_ACTIVE shows menu controls)
- Show remapped keys if player has rebound controls (e.g., if `interact` is rebound to `F`, show "[F] Interact")

**Rebinding UI (Settings System):**
- Settings menu includes "Controls" tab with scrollable list of all actions and their current bindings
- Each action shows: Action name (e.g., "Move Up"), current key (e.g., "W"), "Rebind" button
- Clicking "Rebind" shows "Press any key..." prompt, captures next key press, validates it (conflict check, hardware availability), applies or cancels
- Conflict resolution: If rebinding to already-used key, show modal dialog: "This key is bound to [other_action]. Swap bindings? [Yes/No]"
- "Reset to Defaults" button restores all keybindings to initial state

**Input Context Indicator (HUD System):**
- Optional debug display showing current context (WORLD_ACTIVE, UI_ACTIVE, PAUSED) — only visible if debug HUD enabled
- For player-facing UI: No explicit context indicator needed (UI context is obvious from visible menu, pause is indicated by pause overlay)

**Scroll Sensitivity Slider (Settings System):**
- Settings menu includes "Scroll Sensitivity" slider (range 0.5–2.0, default 1.0)
- Live preview: Moving slider immediately adjusts `scroll_sensitivity` tuning knob (player can test zoom feel in real-time)
- Label shows current value (e.g., "Scroll Sensitivity: 1.2")

**Diagonal Movement Toggle (Settings System):**
- Settings menu includes "Allow Diagonal Movement" checkbox (default: ON)
- Tooltip explains: "When enabled, pressing two movement keys simultaneously (e.g., W+A) moves diagonally. When disabled, only cardinal directions (N/S/E/W) are allowed."

**Input Debug Panel (optional, HUD System):**
- Developer-only overlay showing:
  - Last 10 input events with timestamps (e.g., "152.340s: on_action_pressed(move_up)")
  - Current input context (WORLD_ACTIVE / UI_ACTIVE / PAUSED)
  - Input queue depth (current / max)
  - Mouse position (screen space + world space)
- Toggled via debug key (e.g., F3), not exposed to players in release build

## Acceptance Criteria

- **GIVEN** the game is in WORLD_ACTIVE context, **WHEN** player presses `W`, **THEN** `on_action_pressed("move_up")` event fires, Player Character System receives event and moves character north
- **GIVEN** player is holding `W` (moving north), **WHEN** player opens menu (presses Escape), **THEN** context switches to UI_ACTIVE, `on_action_released("move_up")` fires, character stops moving
- **GIVEN** the game is PAUSED, **WHEN** player presses WASD or clicks world tile, **THEN** no movement or interaction events fire (inputs ignored in PAUSED context)
- **GIVEN** player clicks a UI button, **WHEN** there is a world tile beneath the button, **THEN** only the UI button receives the click (world tile does NOT trigger `interact` event)
- **GIVEN** player remaps `move_up` from `W` to `↑` in Settings, **WHEN** player presses `↑`, **THEN** `on_action_pressed("move_up")` fires (W no longer triggers movement)
- **GIVEN** player rebinds `pause_toggle` to a key already bound to `camera_pan`, **WHEN** prompted "Override binding?", **THEN** if yes: swap bindings; if no: cancel rebind, preserve existing
- **GIVEN** keybindings.cfg is missing or corrupted, **WHEN** game loads, **THEN** default bindings are restored, warning logged, player sees "Keybindings reset" notification
- **GIVEN** player spams Space key 10 times in 1 second, **WHEN** debounce is active (200ms), **THEN** only first press registers, subsequent presses within 200ms ignored (no double-pause bug)
- **GIVEN** player presses W+A simultaneously, **WHEN** diagonal movement enabled, **THEN** both `move_up` and `move_left` events fire, Player Character moves diagonally (normalized vector)
- **GIVEN** scroll wheel delta is 3.0, scroll_sensitivity is 1.5, **WHEN** player scrolls, **THEN** `on_scroll(4.5)` event fires (3.0 × 1.5 = 4.5)

## Open Questions

None at this time. Input System design is complete for Vertical Slice.

**Pending decisions:**
- **3x speed option:** The Tick System GDD (OQ1) leaves 3x speed open. If adopted, this GDD's speed cycling (lines 62-63) must be updated. Currently cycling through 0.5x, 1x, 2x only.

**Future considerations (post-Vertical Slice):**
- **Gamepad support** (MVP or Core Experience): Define gamepad action mappings, analog stick dead zones, vibration API. Requires gamepad-specific input contexts (e.g., GAMEPAD_WORLD vs KEYBOARD_WORLD)?
- **Touch support** (if targeting mobile/tablet): Touch gesture recognition (tap, swipe, pinch-zoom) requires new input channel and event types. Likely separate system (Touch Input System) that wraps this one.
- **Input recording/replay** (for tutorials or bug reproduction): Add `record_input()` / `replay_input()` API. Requires serializing timestamped event stream.
- **Accessibility: customizable hold duration** (for players with motor impairments): Add `hold_duration_threshold` tuning knob (default 500ms, allow 200ms–2000ms range). Requires `on_action_held` to respect this threshold.
