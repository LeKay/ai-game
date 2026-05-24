# ADR-0007: Player Character Energy Model and Manual Action System

## Status
Accepted

## Date
2026-05-13

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | HIGH — 4.4–4.6 beyond LLM training data |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None — all APIs used are stable since Godot 1.0 (`_process`, `_unhandled_input`, `Signal`, `Tween`, `Timer`) |
| **Verification Required** | Verify that `_process()` accumulator for tick-based action progress works correctly at 144fps; verify `Tween` API compatibility for energy bar visual feedback in 4.6 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (tick system — tick accumulation), ADR-0003 (input context — action input gating), ADR-0004 (grid map — Manhattan distance queries), ADR-0005 (inventory system — item deposit) |
| **Enables** | ADR-0008 (building placement + production — building placement is a PC action), ADR-0009 (NPC state machine — PC lockout triggers architect mode), ADR-0010 (hunger system — energy-hunger debuff stacking) |
| **Blocks** | NPC System (architect mode lockout is PC decision), all player-facing gameplay systems |
| **Ordering Note** | Must be Accepted before any player-facing gameplay stories can begin. ADR-0008 and ADR-0009 both depend on this ADR for architect mode transition logic. |

## Context

### Problem Statement

The Player Character is the player's primary interface with the game world. Unlike the NPC System (ADR-0009), the player character has no visible sprite — they act remotely by clicking on world tiles. The system must manage:

1. **Energy pool** — a finite resource (100 max) that limits how many manual actions the player can perform before needing to rest (eat food to refill).
2. **Manual actions** — tile-click initiated harvesting (pick berries, chop tree, mine stone, forage) with discrete energy costs, tick costs, and outputs.
3. **Transport system** — drag-and-drop of resource pins from harvested tiles to storage buildings, with distance-based tick cost and quantity+distance-based energy cost.
4. **Energy depletion penalty** — at 0 Energy, actions cost 2× ticks and produce 50% less output, but the player is never locked out of recovery actions.
5. **Architect Mode** — a one-way transition where the player locks out manual gathering after assigning the first NPC to a building.

The core tension: energy is an hourglass, not a wall. The player should never be blocked from playing, but the depletion penalty makes staying alive at 0 Energy feel costly enough that automation becomes genuinely desirable.

### Constraints

- **Godot 4.6 engine** — all code must use stable APIs; no post-4.3 deprecated patterns.
- **Foundation Autoload pattern** — the Player Character System uses an Autoload singleton (`PlayerCharacter`), consistent with ADR-0001, ADR-0002, ADR-0003, ADR-0005, and ADR-0006.
- **Input context gating** — all player action input must pass through `InputContext` (ADR-0003). The PC System listens to `InputContext._unhandled_input()` for tile clicks and drag events.
- **Tick-based timing** — action durations are measured in tick units (from Tick System, ADR-0001), not frame time. The PC System accumulates ticks via `_process()` delta converted to ticks via `TickSystem.get_tick_rate()`.
- **Single action slot** — the player can only execute one manual action at a time. The action slot is a binary lock: free or occupied.
- **Energy is not a gate** — the player can start any action at 0 Energy (depletion penalty applies). At non-zero energy, actions require `current_energy >= action.energy_cost`.
- **World-scene rendering** — resource pins, action progress bars, drag lines, and energy bar UI are rendered by the PC System via HUD (ADR-0007 does not own rendering nodes; HUD owns all Control nodes).

### Requirements

- Must support 5 manual actions (forage, pick berries, craft tool, chop tree, mine stone) at Vertical Slice scope.
- Must support drag-and-drop transport with real-time cost preview.
- Must communicate energy state to HUD System for bar rendering.
- Must react to `day_transition` signal from Tick System (no-op for PC, but subscribed for notification).
- Must subscribe to NPC System `on_npc_assigned` for architect mode transition.
- Must integrate with Inventory/Storage System for item deposit and food consumption.
- Must perform within 0.5ms/frame during active gameplay (idle < 0.1ms).

## Decision

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    PlayerCharacter (Autoload)            │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │  EnergyPool   │  │ ActionSlot   │  │ ArchitectMode  │ │
│  │  - current:   │  │  - state:    │  │  - locked:    │ │
│  │    float      │  │    FREE      │  │    bool       │ │
│  │  - max: 100   │  │    WORKING   │  └───────────────┘ │
│  └──────────────┘  │    TRANSPORT │                      │
│                     └──────────────┘  ┌───────────────┐ │
│  ┌──────────────┐                      │  TileActions  │ │
│  │ TickAccumulator│                     │  - forage     │ │
│  │  - action_ticks│                     │  - berries    │ │
│  │  - total_cost  │                     │  - chop       │ │
│  └──────────────┘                      │  - mine       │ │
│                                        │  - craft      │ │
│  ┌──────────────┐                      │  - transport  │ │
│  │ TransportMgr  │                     └───────────────┘ │
│  │  - drag_state │                                        │
│  │  - source_pos │  ┌──────────────┐                       │
│  │  - distance   │  │  GridQuery   │                       │
│  └──────────────┘   │  (via ADR-0004│  ┌──────────────┐    │
│                      │   interface) │  │ Inventory    │    │
│                      └──────────────┘  │  Deposit     │    │
│                                         └──────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Core Design

**PlayerCharacter** is registered as a Godot Autoload (project settings → AutoLoad → `player_character.gd` → Path: `res://src/core/player_character.gd`). This matches the Foundation pattern established in ADR-0001 (TickSystem), ADR-0002 (ResourceRegistry), ADR-0003 (InputContext), ADR-0005 (InventorySystem), and ADR-0006 (WorldSaveManager).

The Autoload receives dependency-injected references to the other Foundation systems:

```gdscript
# Dependency injection via _enter_tree() — Autoloads have ready() signal
# that fires after children are ready but before first frame.
func _enter_tree() -> void:
	var tick := Engine.get_singleton("TickSystem")
	var inventory := Engine.get_singleton("InventorySystem")
	var grid := Engine.get_singleton("GridMap")
	var input_ctx := Engine.get_singleton("InputContext")
```

> **Note**: `Engine.get_singleton()` is the standard Autoload access method in Godot 4.x. The alternative `get_node("/root/Name")` also works but `Engine.get_singleton()` is preferred for type safety and clarity.

### EnergyPool

```
class EnergyPool:
    - current: int       # [0, max], clamped on all operations
    - max: int = 100    # configurable knob
    - depletion_flag: bool  # true when current == 0

    Methods:
    - try_spend(amount: int) -> bool       # check + deduct, returns false if insufficient
    - spend_unchecked(amount: int) -> void  # deduct and clamp to 0 (allowed at 0 Energy)
    - restore(amount: int) -> void         # add and clamp to max
    - get_depletion_modifier() -> DepletionMod  # {tick_multiplier: 2.0, output_multiplier: 0.5}
    - is_depleted() -> bool                 # current == 0
```

**Key rules:**
- `try_spend()` is used during normal operation (energy > 0). If it returns false, the action is blocked.
- `spend_unchecked()` is used at 0 Energy — the action proceeds, energy is deducted to 0 (already there), and depletion modifiers apply.
- `restore()` is called when the player eats food. Clamped to [0, max].
- Energy is deducted at **action start**, not gradually during action execution.

### ActionSlot

```
class ActionSlot:
    enum State { FREE, WORKING, TRANSPORT }

    - state: State
    - current_action: ManualAction?    # action config being executed
    - action_start_tick: int           # tick count when action started
    - total_ticks: int                 # action's tick cost (from config)
    - energy_cost: int                 # action's energy cost (from config)

    Methods:
    - try_start(action: ManualAction, energy: EnergyPool) -> StartResult
    - advance_ticks(ticks: int) -> ProgressUpdate  # called from TickSystem signal handler
    - is_complete() -> bool
    - cancel() -> void                 # abort action (rare — only on fatal errors)

    StartResult:
        - SUCCESS
        - BLOCKED_SLOT                   # another action is running
        - INSUFFICIENT_ENERGY            # energy < action cost (only when energy > 0)
        - ARCHITECT_LOCKED               # architect mode, this is a gathering action
        - TOOL_REQUIRED                  # action needs a tool, none available

    ProgressUpdate:
        - progress: float (0.0–1.0)
        - is_complete: bool
        - effective_tick_cost: int       # with depletion modifiers applied
        - effective_output: int          # with depletion modifiers applied
```

**Tick advancement:** When `ticks_advanced(n)` fires from TickSystem, `ActionSlot.advance_ticks(n)` is called. The accumulator tracks `action_start_tick + accumulated_ticks`. When `accumulated_ticks >= total_ticks`, the action completes.

**Energy depletion modifier application:** When `is_depleted()` is true at action start, `effective_tick_cost = base × 2.0` and `effective_output = max(1, ceil(base × 0.5))`. The modified values are set on the `ProgressUpdate` and used by the HUD for progress bar rendering and action completion output.

### ArchitectMode

```
class ArchitectMode:
    - locked: bool = false

    Signal: architect_mode_triggered()

    Methods:
    - on_npc_assigned(npc_id: StringName, building_id: StringName) -> void
    - can_gather(resource_id: StringName) -> bool  # false if locked
    - get_blocked_actions() -> Array[ActionType]     # [CHOP, MINE, BERRIES, FORAGE] when locked

    on_npc_assigned():
        locked = true
        on_architect_mode_triggered.emit()
        # Notify HUD to update available actions
```

This is a one-way, irreversible transition within a session. Once `locked = true`, it never returns to false. The signal triggers the HUD to hide gathering-related UI elements.

### TransportManager

```
class TransportManager:
    enum DragState { IDLE, DRAGGING, SNAP_BACK }

    - state: DragState
    - source_tile: Vector2i?
    - target_building: BuildingSlot?
    - drag_position: Vector2i
    - items: Array[ResourcePin]    # items being transported (1-5)

    Methods:
    - on_drag_start(tile_pos: Vector2i) -> DragStartResult
    - on_drag_update(cursor_pos: Vector2) -> DragPreview
    - on_drag_end(cursor_pos: Vector2) -> TransportResult
    - cancel() -> void

    DragPreview:
        - distance: int              # Manhattan distance to target
        - energy_cost: int           # 2 × quantity + distance
        - tick_cost: int             # 5 × distance
        - valid_target: bool
```

**Transport energy formula:** `energy = 2 × quantity + 1 × distance` (Manhattan distance from source tile to nearest storage building).

**Transport tick formula:** `ticks = 5 × distance`.

**Transport ownership handoff:** TransportManager handles the drag-and-drop UI
(cost preview, valid-target highlight, pin animation). Upon valid drop,
TransportManager calls `InventorySystem.start_transport()` which creates the
IN_TRANSIT state tracked by ADR-0005's transit_items registry. The tick countdown
for transit is handled by InventorySystem on `ticks_advanced()` — TransportManager
does not manage IN_TRANSIT state after the deposit call. This keeps the transport
lifecycle in a single system (InventorySystem) and prevents the circular_serialization
forbidden pattern.

### Tick Integration

The Player Character System subscribes to the Tick System's `ticks_advanced(n)` signal. On each fire:

```
ticks_advanced(n):
    if ActionSlot.is_free:
        return  # nothing to accumulate

    accumulated_ticks += n
    if accumulated_ticks >= total_ticks:
        complete_action()
        if is_transport:
            deposit_items()
    # Notify HUD with progress update
    action_progress_update.emit(progress, effective_tick_cost, effective_output)
```

The tick-to-frame conversion happens transparently — the `_process()` accumulator converts `delta * tick_rate` to tick units and calls the appropriate handler.

Signal connections happen in `_enter_tree()`. Since PlayerCharacter is an Autoload
(lifetime = entire project), `_exit_tree()` cleanup is not required. However, if the
script is reloaded in the editor (`@tool`), `_enter_tree()` fires again — guard
reconnections with `is_connected()` checks to prevent duplicate signal handlers.

### Key Interfaces

#### Public API (called by other systems)

```
# Energy queries
get_current_energy() -> int
get_max_energy() -> int
is_depleted() -> bool

# Energy consumption (called by BuildingSystem for placement cost)
consume_energy(amount: int) -> bool
	# Wraps EnergyPool.spend_unchecked() with a pre-check.
	# Returns true if energy was consumed (sufficient), false if insufficient
	# (only when energy > 0 — at 0 energy, actions always succeed).
	# Called during initiate_build() pre-check phase before GridMap and
	# InventorySystem are modified.

# Action queries
get_action_state() -> ActionSlot.State
get_active_action_id() -> ActionType?

# Architect mode
is_architect_mode() -> bool

# Dependency injection (called by WorldSaveManager or scene root)
init_dependencies(tick: Node, inventory: Node, grid: Node, input_ctx: Node)
```

#### Signals emitted

```
# Energy state changes
energy_changed(current: int, max: int)
energy_depletion_changed(is_depleted: bool)

# Action lifecycle
action_started(action_id: ActionType, tick_cost: int)
action_completed(action_id: ActionType, output: Array[ResourcePin])
action_failed(action_id: ActionType, reason: String)
action_progress_update(progress: float, effective_tick_cost: int, effective_output: int)

# Transport
transport_started(source: Vector2i, destination: Vector2i, quantity: int)
transport_completed(source: Vector2i, destination: Vector2i)
transport_cancelled(source: Vector2i)

# Architect mode
architect_mode_triggered()

# Energy consumption (player eating)
food_consumed(food_type: StringName, energy_restored: int)
```

#### Signals subscribed to

```
# From TickSystem
ticks_advanced(n: int)              # advance action tick accumulator
day_transition(days: int)           # no-op for PC (subscribe for notification only)
pause_state_changed(paused: bool)   # freeze/unfreeze action accumulator

# From InputContext (via _unhandled_input)
# Tile click → action initiation
# Drag start/update/end → transport flow

# From NPC System
# Signal contract: npc_id: StringName, building_id: StringName
# ADR-0009 must define this signal with this exact signature.
# Subscription may fire before ADR-0009 is implemented — safe in Godot
# (unconnected signals are no-ops), but wire up once ADR-0009 exists.
on_npc_assigned(npc_id, building_id)  # trigger architect mode

# From InventorySystem (indirect — via deposit)
# Storage full notification → cancel transport
```

## Alternatives Considered

### Alternative A: World-Scene Root Node (not Autoload)

**Description**: Create a `PlayerCharacter` node under the world scene root. Pass references via `add_child()` or scene tree navigation. Dependency injection via `_enter_tree()` walking the scene tree.

**Pros**:
- Testable in isolation (no Autoload dependency)
- No global state — cleaner separation
- Easier to mock in unit tests

**Cons**:
- Inconsistent with all Foundation ADRs (0001–0006) which use Autoload
- Requires every scene that needs PC access to walk the tree or receive a reference
- PlayerCharacter needs to be ready before any system that depends on it

**Rejection Reason**: The project has already committed to the Autoload singleton pattern for all 6 Foundation systems. Introducing a non-Autoload Foundation system would create an inconsistent pattern requiring a new architectural precedent. ADR-0007 follows the established convention.

### Alternative B: Event Bus Pattern

**Description**: Instead of direct Autoload references and signal connections, use a central event bus for all PC-to-system communication. Systems subscribe to event topics.

**Pros**:
- Loose coupling — no direct references between systems
- Easier to swap implementations

**Cons**:
- Opaque dependency graph — hard to trace data flow
- String-typed event names are error-prone (typos, dead events)
- Performance overhead of event lookup per tick
- Violates the spirit of ADR-0001's signal-based dispatch (which uses typed signals, not a string bus)

**Rejection Reason**: Typed signals (per ADR-0001's `tick_event_dispatch` interface) are safer and faster than a string-based event bus. The project's Foundation systems already use typed signals for inter-system communication.

## Consequences

### Positive

- **Consistent with Foundation pattern** — Autoload singleton matches ADR-0001 through ADR-0006, reducing cognitive load.
- **Clear single action slot** — the binary free/occupied model prevents action queue complexity at VS scope.
- **Energy as hourglass, not wall** — never blocking the player at 0 Energy preserves the meditative feel.
- **Architect mode as one-way gate** — reinforces the game's core fantasy (manual → automated) without requiring a state reset.
- **Tick-based timing decouples from framerate** — action durations are deterministic regardless of frame rate.

### Negative

- **Autoload global state** — the PC System is a global singleton, which makes isolated unit testing harder. Tests must mock or stub the Autoload.
- **Tight coupling to Tick System** — the PC action accumulator depends on tick accumulation. If the Tick System changes its signal format, the PC System must change too.
- **No action queuing** — the single action slot means players can't queue actions. This is intentional at VS scope but will feel limiting in Core Experience.
- **Architect mode is irreversible** — players who want to return to manual labor cannot. This is by design but may frustrate some players.

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Performance at high tick rates | If 144fps + fast-forward, `ticks_advanced()` fires very frequently. The accumulator must be efficient. | Use accumulator pattern (accumulate fractional ticks, process on integer boundary). Filter HUD updates to reduce signal spam. |
| Energy economy imbalance | If 100 Energy is too high or too low, the manual → automated transition feels wrong. | All energy values are tuning knobs. Playtest the energy drain rate with spreadsheet model before finalizing. |
| Drag-and-drop input conflicts | Tile clicks and drag operations share the same input stream. Distinguishing them can be fragile. | Use a minimum drag threshold (e.g., 5px cursor movement before entering DRAGGING state). Short taps = click, long + move = drag. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| player-character-system.md | Rule 2: Energy pool (100 max, never negative, clamped) | EnergyPool class with current/max fields, clamp on all operations |
| player-character-system.md | Rule 3: 5 manual actions with discrete costs | ActionSlot with ManualAction config, 5 action types in TileActions |
| player-character-system.md | Rule 4: Drag-and-drop transport, distance-based costs | TransportManager class with energy/tick formulas matching GDD |
| player-character-system.md | Rule 5: 0 Energy depletion (2× ticks, 50% output) | EnergyPool.get_depletion_modifier() returning {2.0, 0.5} |
| player-character-system.md | Rule 6: Food-to-energy refill (berry +10, bread +25) | EnergyPool.restore() + food_consumed signal |
| player-character-system.md | Rule 9: Architect Mode (one-way lockout after first NPC) | ArchitectMode class with irreversible locked flag and on_npc_assigned signal subscription |
| player-character-system.md | Formula 1-3: Transport costs | TransportManager implements `2 × quantity + distance` energy and `5 × distance` ticks |
| hunger-system.md | Formula 2: Combined debuff stacking | EnergyPool + HungerSystem read both multipliers independently |

## Performance Implications

- **CPU**: 0.5ms/frame during active action (tick accumulator + HUD signal). Idle: < 0.1ms (only signal subscription overhead). At 144fps with fast-forward, `ticks_advanced()` fires frequently — accumulator pattern prevents per-frame processing.
- **Memory**: Minimal — EnergyPool (~16 bytes), ActionSlot (~64 bytes), TransportManager (~128 bytes). No persistent data structures at VS scope.
- **Load Time**: Zero — no resources to load. Pure GDScript class.
- **Network**: N/A — single-player game.

## Migration Plan

This ADR creates a new Foundation system. No migration from existing code is needed — the Player Character System has not yet been implemented. Implementation should begin after ADR-0001 (Tick System) is accepted, as the PC System depends on it for tick accumulation.

### Implementation Order

1. **EnergyPool** — standalone, no dependencies. Unit testable immediately.
2. **ActionSlot** — depends on EnergyPool. Unit testable with mock EnergyPool.
3. **ArchitectMode** — depends on NPC System signal. Testable with mocked signal.
4. **TransportManager** — depends on GridMap for distance queries. Requires ADR-0004.
5. **PlayerCharacter (integration)** — ties all classes together. Requires all Foundation dependencies.

## Validation Criteria

| # | Criteria | Method |
|---|----------|--------|
| 1 | Energy pool clamps to [0, 100] on all operations | Automated: unit test EnergyPool with restore(200) → assert current = 100 |
| 2 | At 0 Energy, actions start but cost 2× ticks and produce 50% output | Automated: set energy = 0, start action with base_cost = 80, assert effective = 160 |
| 3 | Energy depletion does NOT block Pick Berries (recovery action) | Automated: energy = 0, attempt berry action → assert SUCCESS (not BLOCKED) |
| 4 | Architect mode locks all gathering after first NPC assignment | Automated: mock NPC signal, assert can_gather() returns false for CHOP/MINE/BERRIES |
| 5 | Transport energy formula: `2 × quantity + distance` | Automated: 3 items, distance 12 → assert energy_cost = 18 |
| 6 | Transport tick formula: `5 × distance` | Automated: distance 12 → assert tick_cost = 60 |
| 7 | Action cannot start during another action | Automated: start action, attempt another → assert BLOCKED_SLOT |
| 8 | Day transition does not interrupt running action | Automated: start action, fire day_transition → assert action continues |

## Related Decisions

- ADR-0001: Tick System Design and Time Management (tick accumulation, signals)
- ADR-0003: Input Context System and Action Mapping (input gating, context stack)
- ADR-0004: Grid Map Data Model and TileMapLayer Rendering (Manhattan distance queries)
- ADR-0005: Inventory and Item State Machine (item deposit, storage queries)
- ADR-0006: Save and Load Format and Serialisation Order (PC state serialization)
- GDD: design/gdd/player-character-system.md (full mechanical specification)
- GDD: design/gdd/hunger-system.md (combined debuff stacking)
