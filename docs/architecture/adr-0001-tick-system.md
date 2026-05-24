# ADR-0001: Tick System Design and Time Management

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
| **Post-Cutoff APIs Used** | None — all APIs used are stable since Godot 1.0 |
| **Verification Required** | Test tick accumulation accuracy across frame rates (30fps, 60fps, 144fps); verify manual action tick advancement works in paused state; verify save/load restores exact tick_remainder |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None — lowest infrastructure layer |
| **Enables** | Production System, Manual Labor System, Hunger System, NPC System, Save/Load System, Day/Night Cycle System, HUD System |
| **Blocks** | All time-dependent gameplay systems |
| **Ordering Note** | Must be Accepted before any downstream system GDD can be fully implemented |

## Context

### Problem Statement

The game requires a deterministic, frame-rate-independent time system that converts real-time engine delta into discrete tick units consumed by all gameplay systems. The system must support player-controlled time flow (0.5x, 1x, 2x speed multipliers and pause/play) and deliver the "meditative planning" fantasy (Pillar 3: Optimization Over Expansion) by freezing time for layout decisions.

### Constraints

- **Deterministic**: Given identical input (delta values, speed changes, manual actions), tick_count must always reach the same value at the same frame.
- **Frame-rate independent**: 100 real seconds at 1x must always equal 1000 ticks, regardless of FPS.
- **Lag-resistant**: Must clamp tick_delta per frame to prevent multi-day time jumps from lag spikes (alt-tab, frame drops).
- **Pause semantics**: PAUSED = no automatic accumulation, but manual actions can advance time.
- **Godot 4.6**: Must use Godot 4.6 best practices for time management (no deprecated APIs).
- **No external time sources**: Must not use OS-level clock (prone to system time changes); only use engine-provided delta.

### Requirements

- Accumulate ticks each frame based on delta_seconds × speed_multiplier
- Carry fractional remainder across frames for exact tick rates
- Support 3 speed states: 0.5x, 1x, 2x (3x deferred)
- Manual action tick advancement (bypasses accumulation formula)
- Day transition at tick_count >= 1000
- Broadcast events to subscribed systems via signals

## Decision

The Tick System will be implemented as an **Autoload singleton (`TickSystem`)** that inherits from `Node`. It uses `Node._process(delta)` for automatic tick accumulation and provides an `advance_ticks_manual()` method for intentional player actions.

### Resolving Open Question #1 (architecture.md)

The master architecture.md lists "Autoload vs scene-instanced singletons" as Open Question #1. This ADR answers it by choosing Autoload. The alternative (scene-instanced + dependency injection) was raised for testability concerns, but for this project's scale (single-player, ~11 Vertical Slice systems, no scene reloading) the Autoload pattern is simpler and testability can be handled via standalone instances and mocks in unit tests. The decision stands.

### Why an Autoload

The Tick System is the foundational time infrastructure that ALL gameplay systems depend on. An Autoload provides:
- Guaranteed single instance across all scenes
- Accessible from any system without explicit dependency injection
- Always runs (not tied to any specific scene lifecycle)
- Natural home for the `_process()` loop

Given that this is a single-player game with no scene reloading that would destroy the Autoload, the Autoload lifecycle matches the Tick System's "always alive" requirement.

### Time Accumulation Logic

```gdscript
extends Node

const TICKS_PER_DAY: int = 1000
const TICKS_PER_SECOND_BASE: float = 10.0
const MAX_TICKS_PER_FRAME: int = 100
const SPEED_OPTIONS: Array[float] = [0.5, 1.0, 2.0]

var tick_remainder: float = 0.0
var tick_count: int = 0
var current_day: int = 1
var speed_multiplier: float = 1.0
var is_paused: bool = true

signal ticks_advanced(delta_ticks: int)
signal day_transition(days_elapsed: int)
signal speed_changed(new_speed: float)
signal pause_state_changed(is_paused: bool)

func _process(delta: float) -> void:
	if is_paused:
		return
	
	if delta < 0.0:
		delta = 0.0
	
	var raw_ticks: float = delta * TICKS_PER_SECOND_BASE * speed_multiplier
	raw_ticks += tick_remainder
	
	var tick_delta: int = clampi(int(raw_ticks), 0, MAX_TICKS_PER_FRAME)
	tick_remainder = fmod(raw_ticks, 1.0)
	
	if tick_delta > 0:
		_accumulate_ticks(tick_delta)

func _advance_days() -> int:
	var days := 0
	while tick_count >= TICKS_PER_DAY:
		tick_count -= TICKS_PER_DAY
		current_day += 1
		days += 1
	return days

func _accumulate_ticks(ticks: int) -> void:
	tick_count += ticks
	var days := _advance_days()
	if days > 0:
		day_transition.emit(days)
	ticks_advanced.emit(ticks)

func advance_ticks_manual(cost: int) -> void:
	if cost < 0:
		return
	tick_count += cost
	var days := _advance_days()
	if days > 0:
		day_transition.emit(days)
	ticks_advanced.emit(cost)

func set_speed(multiplier: float) -> void:
	var clamped: float = SPEED_OPTIONS.front()
	for s in SPEED_OPTIONS:
		if absf(s - multiplier) < 0.01:
			clamped = s
			break
	if clamped != speed_multiplier:
		speed_multiplier = clamped
		speed_changed.emit(speed_multiplier)

func set_pause(paused: bool) -> void:
	if paused != is_paused:
		is_paused = paused
		set_process(not is_paused)
		pause_state_changed.emit(is_paused)
```

### Key Interfaces

**Signals (broadcast by TickSystem):**
- `ticks_advanced(delta_ticks: int)` — fires each frame when ticks accumulate (not fired when paused, except for manual actions)
- `day_transition(days_elapsed: int)` — fires once per day boundary crossing with the total number of days advanced
- **Signal ordering**: `day_transition` always fires before `ticks_advanced` within the same accumulation batch, so subscribers can read the updated `current_day` when processing `ticks_advanced`.
- **Emission pattern**: `day_transition` fires once after the while loop completes, with `days_elapsed` set to the actual number of days crossed (not `1` per iteration). This reduces signal overhead and matches the `days_elapsed: int` semantic.
- `speed_changed(new_speed: float)` — fires when speed changes
- `pause_state_changed(is_paused: bool)` — fires when pause/unpause

**Methods (called by other systems):**
- `advance_ticks_manual(cost: int) -> void` — advance by a specific tick amount
- `set_speed(multiplier: float) -> void` — change speed multiplier
- `set_pause(paused: bool) -> void` — toggle pause state

**Queries (polled by UI):**
- `get_tick_count() -> int`
- `get_current_day() -> int`
- `get_speed_multiplier() -> float`
- `is_paused() -> bool`

## Alternatives Considered

### Alternative A: Timer-Based (one-shot timers at fixed intervals)

**Description**: Use Godot's `Timer` node with `wait_time` set to produce ticks at fixed intervals. Connect the Timer's `timeout` signal.

**Pros**: No `_process()` overhead; Godot-native pattern; simple.

**Cons**: Cannot handle variable speed multipliers (changing `wait_time` every frame is wasteful); manual action advancement is awkward (requires stopping/restarting timers); no fractional remainder accumulation — loses precision over time; doesn't scale to 2x speed (would need multiple timers); pauses break timer state.

**Rejection Reason**: Cannot satisfy variable speed + manual action + precision requirements in a single clean implementation.

### Alternative B: Custom Thread

**Description**: Run a dedicated thread function with a tight loop accumulating ticks and emitting signals via `call_deferred()`.

**Pros**: Completely decoupled from frame rate; predictable accumulation.

**Cons**: Requires thread-safe signal emission (`call_deferred` or mutex); Godot's signal system is not thread-safe; adds complexity for no meaningful benefit (the game is single-player, not real-time server); cannot access any Godot scene tree nodes directly; violates Godot's threading model where only the main thread touches the scene tree.

**Rejection Reason**: Thread safety concerns and Godot's single-threaded scene model make this over-engineered. `_process()` with delta is the correct Godot pattern for time accumulation.

### Alternative C: Input-Driven Tick (no continuous loop)

**Description**: Only advance ticks in response to player input or explicit system requests. No `_process()` accumulator.

**Pros**: Zero overhead when idle; simple.

**Cons**: Violates the GDD's requirement for automatic time flow during play; production timers would not advance; NPCs would not work; fundamentally breaks the game's time model.

**Rejection Reason**: The game requires continuous time flow during RUN state — input-driven only is incompatible with the design.

## Consequences

### Positive
- **Deterministic**: Fractional remainder carry ensures no drift over time
- **Godot-idiomatic**: Uses `_process(delta)` which is the standard Godot pattern for time-dependent logic
- **Signal-based**: Subsystems react via signals, not polling (except UI queries)
- **Lag-resistant**: MAX_TICKS_PER_FRAME cap prevents time jumps
- **Simple**: Single Node with clean state machine — easy to debug
- **Efficient pause**: `set_process(false)` when paused — `_process()` stops entirely, zero CPU cost

### Negative
- **Autoload coupling**: TickSystem as Autoload creates a global dependency — any system can reference it without explicit wiring. This reduces testability in isolation. Mitigated by documenting this as the intended pattern for infrastructure singletons.
- **Autoload registration risk**: If a developer opens the project and the Autoload is not registered in project settings, `TickSystem` will be null everywhere. Mitigation: include the Autoload registration in the project.godot template file.

### Risks
- **Signal spam**: `ticks_advanced` fires every frame with delta_ticks. For 10 subscribed systems, that's signal invocations every frame. At 60fps with 1x speed, ticks only fire ~10x/sec (since floor(0.0167 × 10) = 0 most frames), so actual rate is ~100 callable invocations/sec for 10 subscribers — acceptable.
- **Day transition signal flooding**: The while loop handles multi-day crossings (e.g., from a large manual action cost). `day_transition` fires once after the loop with the total days crossed. The MAX_TICKS_PER_FRAME cap (100) vs TICKS_PER_DAY (1000) ensures at most 1 day per frame from automatic accumulation, but `advance_ticks_manual()` accepts arbitrary costs so multi-day crossings are possible there. The post-loop emission pattern keeps signal overhead minimal regardless of days crossed.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| tick-system.md | Tick accumulation formula: `raw_ticks = delta × 10 × speed_multiplier` | Implemented in `_process()` with remainder carry |
| tick-system.md | Speed multipliers: 0.5x, 1x, 2x | `SPEED_OPTIONS` array with clamped `set_speed()` |
| tick-system.md | Pause state machine (PAUSED/RUNNING) | `is_paused` flag gates `_process()` accumulation; `set_process()` toggled on pause |
| tick-system.md | Manual action tick advancement | `advance_ticks_manual()` method, bypasses `_process()` |
| tick-system.md | Day transition at 1000 ticks | `while tick_count >= TICKS_PER_DAY` in accumulator |
| tick-system.md | Tick consumer contract (signal-based) | Four signals: `ticks_advanced`, `day_transition`, `speed_changed`, `pause_state_changed` |
| tick-system.md | Determinism guarantee | Fractional remainder carry; no OS clock usage |
| game-concept.md | Tick-based time system (Pillar 3) | Core infrastructure enabling pause, speed control, day boundaries |

## Performance Implications
- **CPU**: Minimal — `_process()` does ~5 floating-point ops per frame when running. Signal emission adds O(N) where N = subscribed systems. At 60fps with 1x speed, ticks fire ~10x/sec, so ~100 calls/sec for 10 subscribers. When paused, `_process()` is disabled entirely via `set_process(false)`.
- **Memory**: Negligible — ~5 float/int variables + 4 signal definitions.
- **Load Time**: None — Autoload loads once at project start.
- **Network**: N/A (single-player only).

## Migration Plan

No migration needed — this is a new system. The Autoload must be registered in project settings (Project → Settings → Autoload) with the name `TickSystem` and the scene path pointing to the TickSystem scene/script. This should be included in the project.godot template to prevent deployment risk.

## Validation Criteria
- [ ] 100 real seconds at 1x speed = 1000 ticks (±1 frame) at any stable FPS
- [ ] Pause state = zero automatic tick accumulation
- [ ] Manual action of 80 ticks advances time while paused
- [ ] Lag spike producing 1000+ raw ticks clamps to 100 tick_delta
- [ ] Day transition at exactly 1000 ticks (tick_count wraps via subtraction, remainder preserved, e.g. 1050 → 50; current_day increments; day_transition emits once with days_elapsed=1)
- [ ] Large manual action crossing multiple days emits day_transition once with total days (e.g., advance_ticks_manual(2500) from 0 → days_elapsed=2, tick_count=500)
- [ ] Save/load restores exact tick_count and tick_remainder
- [ ] `set_process(false)` when paused — verified via profiler (zero _process calls)

## Related Decisions
- ADR-0002: Resource Data Registry (tick system must serialize its state)
- ADR-0005: Inventory and Item State Machine (tick system broadcasts tick events that inventory subscribes to)
