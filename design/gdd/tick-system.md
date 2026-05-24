# Tick System

> **Status**: In Design
> **Author**: User + Claude (Sonnet 4.5)
> **Last Updated**: 2026-05-05
> **Implements Pillar**: Pillar 2 (Information Transparency), Pillar 3 (Optimization Over Expansion)
> **Engine**: Godot 4.6 (signal-based event dispatch)

---

## Overview

The Tick System is the foundational time management infrastructure that converts real-time engine delta into discrete, abstract tick units consumed by all time-dependent gameplay systems (production, manual labor, hunger, logistics, day/night cycle). It provides player-controlled time flow through variable speed multipliers (0.5x, 1x, 2x) and full pause/play control, enabling the "meditative planning" gameplay (Pillar 3: Optimization Over Expansion) by freezing time for layout decisions. Every gameplay system that performs work over time (production chains, NPC transport, manual actions) measures duration in ticks rather than seconds, creating a debuggable, deterministic simulation independent of framerate. The system triggers daily events (hunger deduction, NPC spawning checks) when the tick counter reaches 1000 (= 1 day), then resets to 0.

---

## Player Fantasy

In the beginning, you pause because you must — each decision is new, each consequence uncertain, and time control is your safety net against mistakes made in haste. You notice a bottleneck (the bakery idle), slow time to 0.5x, trace the chain backward (mill has no wheat), pause to plan the fix (build storage shed, assign carrier), then unpause and watch the solution take hold. You are learning to read your village's rhythms.

But in time, you pause because you *choose* to — not from fear, but from the quiet pleasure of anticipating needs before they become crises. You see the weaving workshop you're about to build, predict that your new craftsmen will need clothing, study the map while the world stands frozen, and reallocate a wheat field to flax before unpausing. Three days later (at 3x speed), the weavers produce cloth, the craftsmen upgrade to Tier 2, and no bottleneck ever happened — because you saw it coming while time stood still.

This transformation — from reactive pause (diagnosing failures) to proactive pause (planning perfection) — is the emotional arc the Tick System exists to deliver. Early, you pause to survive. Late, you pause to master. The village waits for its founder's deliberate hand, and that patience is your greatest power.

---

## Detailed Design

### Core Rules

1. **Tick Accumulation**
   - Every frame, the Tick System accumulates ticks based on real-time delta and current speed multiplier:
     ```
     raw_ticks = delta_seconds × 10 × speed_multiplier
     tick_delta = min(floor(raw_ticks), MAX_TICKS_PER_FRAME)
     remainder = raw_ticks - tick_delta
     ```
   - The fractional remainder is carried forward to the next frame to ensure exact tick rates over time.
   - If pause state is PAUSED (auto-advance disabled), `tick_delta = 0` (no automatic accumulation).
   - `tick_count` increments by `tick_delta` each frame.

2. **Speed Multipliers**
   - Available speeds: 0.5x, 1x, 2x
   - At 1x speed: 1 real second = 10 ticks (baseline: 1 day = 100 real seconds)
   - At 0.5x: 1 real second = 5 ticks (1 day = 200 real seconds)
   - At 2x: 1 real second = 20 ticks (1 day = 50 real seconds)
   - Speed changes take effect immediately (next frame's accumulation uses new multiplier).

3. **Pause State Machine**
   - **States:** PAUSED (auto-advance disabled), RUNNING (auto-advance enabled)
   - **PAUSED:** Automatic tick accumulation = 0. Manual player actions can still advance ticks explicitly.
   - **RUNNING:** Automatic tick accumulation occurs every frame based on speed multiplier.
   - **Transitions:** Player presses Play/Pause button, OR external event (e.g., tutorial forces pause).

4. **Manual Action Tick Advancement**
   - When the player performs a manual action (e.g., "Chop Tree" costs 80 ticks):
     - `tick_count += action_tick_cost`
     - Tick System broadcasts `ticks_advanced(action_tick_cost)` event
     - **ALL gameplay systems process those ticks** — buildings produce, NPCs move, hunger ticks down
   - This behavior applies regardless of pause state (paused + manual action = world advances by action cost, then re-freezes).
   - Manual actions always cost their full base tick cost regardless of speed multiplier.

5. **Day Transition**
   - When `tick_count >= 1000`:
     - Broadcast `day_transition(1)` event (always exactly 1 day)
     - Game enters PAUSED state automatically
     - Reset `tick_count = 0` — ticks beyond 1000 are discarded
   - **No overflow carry:** Each day is a clean boundary. Excess ticks accumulated past 1000 in one frame are dropped. The MAX_TICKS_PER_FRAME cap (100 ticks) limits discarded ticks to at most 100 per day transition.
   - **Resume:** The Day Overview System (separate system) subscribes to `day_transition`, shows its summary, and calls `set_pause(false)` when the player dismisses it.

6. **Tick Consumer Contract**
   - Gameplay systems subscribe to Tick System events:
     - `ticks_advanced(delta_ticks: int)` — fires every frame when ticks accumulate (paused = no fire)
     - `day_transition(days_elapsed: int)` — fires when day counter increments
     - `speed_changed(new_speed: float)` — fires when player changes speed multiplier
     - `pause_state_changed(is_paused: bool)` — fires when pause/unpause
   - Systems react to events rather than polling `get_tick_count()` every frame (exception: UI systems displaying tick counter can poll for display purposes).

7. **Determinism Guarantee**
   - Tick accumulation is deterministic: given identical input sequence (delta values, speed changes, manual actions), `tick_count` will always reach the same value at the same frame.
   - Fractional remainder carry ensures no drift over long sessions (1000 ticks ALWAYS equals 100 real seconds at 1x speed, ±1 frame).

---

### States and Transitions

| State | Auto-Advance? | Manual Actions? | Speed Multiplier Active? |
|-------|---------------|-----------------|--------------------------|
| **PAUSED** | No | Yes (advances ticks) | No (0x effective speed) |
| **RUNNING** | Yes | Yes | Yes |

**State Transitions:**

| From | To | Trigger | Effect |
|------|-----|---------|--------|
| RUNNING | PAUSED | Player presses Pause button | Auto-advance stops, `pause_state_changed(true)` fires |
| PAUSED | RUNNING | Player presses Play button | Auto-advance resumes, `pause_state_changed(false)` fires |
| Any | Any | Player changes speed (0.5x/1x/2x) | `speed_multiplier` updates, `speed_changed(new_speed)` fires |

**Edge case:** If PAUSED and player performs manual action, state remains PAUSED after action completes (world advances by action cost, then re-freezes).

---

### Interactions with Other Systems

| System | Interaction | Data Flow | Notes |
|--------|-------------|-----------|-------|
| **Production System** | Consumes ticks for production timers | Tick System → Production: `ticks_advanced(delta_ticks)` | Buildings subscribe to event, decrement production timers |
| **Manual Labor System** | Requests tick advancement for player actions | Manual Labor → Tick System: `advance_ticks_manual(cost)` | Player chops tree → Manual Labor calls Tick System to advance 80 ticks |
| **Hunger System** | Triggers daily food deduction | Tick System → Hunger: `day_transition(days_elapsed)` | Hunger deducts `days_elapsed × daily_rate` from all NPCs |
| **Day/Night Cycle System** | Triggers day counter increment | Tick System → Day/Night: `day_transition(days_elapsed)` | Day/Night updates day number, checks for daily events (NPC spawn, merchant arrival) |
| **NPC System** | Consumes ticks for NPC transport timers | Tick System → NPC System: `ticks_advanced(delta_ticks)` | NPCs decrement travel timers based on delta_ticks |
| **Logistics System** (future) | Will absorb NPC transport logic | Not yet active | When designed, NPC System's transport timers will be migrated to Logistics |
| **HUD System** | Displays current tick, day, and speed | HUD → Tick System: `get_tick_count()`, `get_current_day()`, `get_speed_multiplier()` | UI polls for display, does not subscribe to events |
| **Save/Load System** | Serializes tick state | Save/Load ↔ Tick System: Read/write `tick_count`, `current_day`, `speed_multiplier`, `pause_state`, `tick_remainder` | All tick state must be saved to preserve determinism |
| **Player Character System** | Subscribes to `day_transition` for hunger consumption; PC System initiates manual tick advancement | Tick System → Player Character: `day_transition(days_elapsed)` (triggers hunger check); Player Character → Tick System: `advance_ticks_manual(action_tick_cost)` | PC System's `start_action()` (Tick System GDD Interactions table) delegates to `advance_ticks_manual()` — the name difference is intentional: Player Character initiates, Tick System advances |

**Key Interface:**
- **Events (broadcast by Tick System):** `ticks_advanced`, `day_transition`, `speed_changed`, `pause_state_changed`
- **Methods (called by other systems):** `advance_ticks_manual(cost: int)`, `set_speed(multiplier: float)`, `set_pause(paused: bool)`
- **Queries (polled by UI):** `get_tick_count() -> int`, `get_current_day() -> int`, `get_speed_multiplier() -> float`, `is_paused() -> bool`

---

## Formulas

### 1. Tick Accumulation (Clamped)

`tick_delta = min(floor(delta_seconds × 10 × speed_multiplier), MAX_TICKS_PER_FRAME)`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| delta_seconds | δ | float | 0.0–unbounded | Time elapsed since last frame (seconds) |
| speed_multiplier | s | float | {0.5, 1.0, 2.0} | Current simulation speed setting |
| MAX_TICKS_PER_FRAME | — | int | 100 (tuning knob) | Safety cap to prevent multi-day skips |
| tick_delta | Δt | int | 0–100 | Clamped whole ticks to advance this frame |

**Output Range:** [0, 100] ticks — guarantees max 0.1 days per frame (prevents lag-induced time travel)

**Example (normal frame at 1x speed, 60fps):**
```
delta_seconds = 0.0167
speed_multiplier = 1.0
tick_delta = min(floor(0.0167 × 10 × 1.0), 100) = min(0, 100) = 0
```

**Example (lag spike at 3x speed):**
```
delta_seconds = 10.0 (alt-tab for 10 seconds)
speed_multiplier = 2.0
tick_delta = min(floor(10.0 × 10 × 2.0), 100) = min(200, 100) = 100 (clamped)
```

---

### 2. Tick Remainder Accumulation

`remainder = (delta_seconds × 10 × speed_multiplier) - tick_delta`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| delta_seconds | δ | float | 0.0–unbounded | Time elapsed since last frame (seconds) |
| speed_multiplier | s | float | {0.5, 1.0, 2.0} | Current simulation speed setting |
| tick_delta | Δt | int | 0–100 | Whole ticks applied this frame (from Formula 1) |
| remainder | r | float | 0.0–0.999... | Fractional ticks to carry to next frame |

**Output Range:** [0.0, 1.0) — must stay below 1.0 to avoid tick double-counting

**Example (building up to a tick at 1x speed, 60fps):**
```
Frame 1: remainder_old = 0.0, δ = 0.0167 → Δt = 0, remainder_new = 0.167
Frame 2: remainder_old = 0.167, δ = 0.0167 → Δt = 0, remainder_new = 0.334
Frame 6: remainder_old = 0.835, δ = 0.0167 → Δt = 1, remainder_new = 0.002
```

---

### 3. Day Transition

`days_elapsed = floor(tick_count / 1000)`
`tick_count = 0` — overflow ticks beyond 1000 are **discarded**

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| tick_count (before) | t | int | 0–2,147,483,647 | Accumulated ticks before transition |
| days_elapsed | d | int | 0–2,147,483 | Number of complete days to increment |
| tick_count (after) | t' | int | 0 | Always resets to 0 (overflow discarded, never retained) |

**Output Range:**
- `days_elapsed`: [0, 2,147,483] (int32 max allows ~5,881 years of in-game time)
- `tick_count`: [0, 999] — always valid

**Example (normal day transition):**
```
tick_count = 1002
days_elapsed = floor(1002 / 1000) = 1
tick_count = 0  (overflow 2 ticks discarded)
```

**Example (lag-induced overflow, discarded):**
```
tick_count = 950, tick_delta = 100 (clamped from 300)
tick_count = 950 + 100 = 1050 → day transition fires
tick_count reset to 0 (50 overflow ticks discarded)
Day Overview shown, game pauses
```

---

### 4. Real-Time to Tick Conversion

`ticks_per_second = 10 × speed_multiplier`
`day_duration_seconds = 1000 / ticks_per_second`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| speed_multiplier | s | float | {0.5, 1.0, 2.0} | Current simulation speed setting |
| ticks_per_second | — | float | 5.0–20.0 | Tick accumulation rate |
| day_duration_seconds | — | float | 50.0–200.0 | Real-world seconds per in-game day |

**Output Table:**

| Speed | Ticks/Second | Ticks/Minute | In-Game Day Duration (real-time) |
|-------|--------------|--------------|----------------------------------|
| 0.5x  | 5            | 300          | 200 seconds (3m 20s) |
| 1.0x  | 10           | 600          | 100 seconds (1m 40s) |
| 2.0x  | 20           | 1200         | 50 seconds |

---

## Edge Cases

### Critical Edge Cases

- **If delta > 1 second (lag spike)**: Clamp `tick_delta` to MAX_TICKS_PER_FRAME (100 ticks). Prevents multi-day skips and simulation collapse. Player experiences slowdown during lag recovery, not time travel.

- **If manual action performed during PAUSED**: World advances by action tick cost, all systems process those ticks, then time re-freezes. Player can act while planning (Pillar 3: meditative optimization).

- **If tick_count ≥ 1000 (day transition)**: Fire `day_transition(1)`, reset `tick_count = 0`, enter PAUSED state. Ticks beyond 1000 are discarded. The Day Overview System handles the summary UI and resumes the game on player confirmation. Multi-day skips cannot occur due to MAX_TICKS_PER_FRAME cap.

- **If manual action cost > 100 ticks**: Apply full cost (no clamping). MAX_TICKS_PER_FRAME applies only to automatic accumulation, not intentional player actions. May trigger multiple day transitions if cost pushes tick_count past 2000+.

### State Machine Edge Cases

- **If `set_speed()` called mid-frame**: New speed applies next frame. Current frame's `tick_delta` already calculated — do not recalculate. Avoids double-application.

- **If `set_speed(invalid_value)` (e.g., 1.5x or 10x)**: Clamp to nearest valid speed {0.5, 1.0, 2.0}. Fire `speed_changed` with clamped value. Log warning (UI should enforce valid speeds).

- **If `set_pause(true)` called when already PAUSED**: No-op. `pause_state_changed` does not fire (idempotent state changes prevent event spam).

- **If pause toggled rapidly (3+ times per second)**: Each toggle fires `pause_state_changed`. Systems must handle rapid state flips. No tick accumulation during PAUSED frames regardless of toggle frequency.

### Numerical Edge Cases

- **If remainder ≥ 1.0 (floating-point drift)**: Extract whole ticks (`floor(remainder)`), add to `tick_count`, fire `ticks_advanced`. Subtract from `remainder` to restore [0.0, 1.0) range. Corrects precision drift over long sessions without losing ticks.

- **If tick_count > 2,147,483,647 (int32 max)**: Clamp to int32 max, log warning. Unreachable in practice (~5.88 million in-game years at 1x speed), but prevents undefined behavior from save corruption.

- **If delta_seconds = 0.0 (engine stall)**: `tick_delta = 0`, no accumulation, no events fire. Next frame resumes normally. Safe to ignore.

- **If delta_seconds < 0.0 (time reversal from system clock bug)**: Treat as `delta = 0.0`. Log error. Time reversal breaks determinism — freeze is safer than rewind.

### Multi-System Interaction Edge Cases

- **If day transition fires while building mid-production**: Production timers continue unaffected. Building at 500/600 ticks before event remains at 500/600 after. Day boundary is event trigger (hunger, spawns), not simulation reset.

- **If two systems call `set_speed()` simultaneously**: Last call wins (overwrites). Only one `speed_changed` event fires with final value. Log warning if multiple calls detected — design error (UI should be sole speed controller).

- **If 10+ manual actions in one frame**: Process all calls sequentially. Each increments `tick_count` and fires `ticks_advanced(cost)` independently. Day transitions fire once at frame end if `tick_count >= 1000` after all actions. Preserves granularity for tick-listening systems.

### Save/Load Edge Cases

- **If save loaded with tick_count = 999, remainder = 0.8**: Resume accumulation normally. Next frame may trigger day transition if accumulated ticks push count >= 1000. Save/load preserves exact tick state — no special boundary handling.

- **If remainder carry persists after speed change**: Old remainder at 1x speed carries into 0.5x speed regime. Next frame accumulates `tick_delta = floor(delta × 10 × 0.5 + old_remainder)`. May accumulate tick faster than expected due to carried fractional time. Remainder represents real elapsed time — discarding on speed change would lose ticks.

---

## Dependencies

### Upstream (Tick System requires)

None — the Tick System is the lowest infrastructure layer. It depends on no other gameplay system.

### Downstream (systems that depend on Tick System)

| System | Dependency Type | Events / Interface Used |
|--------|-----------------|------------------------|
| **Production System** | Production timers measured in ticks | `ticks_advanced(delta_ticks)` |
| **Manual Labor System** | Player actions advance ticks explicitly | `advance_ticks_manual(cost)` |
| **Hunger System** | Daily food deduction triggered by day boundary | `day_transition(1)` |
| **Day/Night Cycle System** | Day counter increment, daily spawn/event checks | `day_transition(1)` |
| **NPC System** | NPC travel timers measured in ticks | `ticks_advanced(delta_ticks)` |
| **HUD System** | Displays current tick, day number, speed, pause state | `get_tick_count()`, `get_current_day()`, `get_speed_multiplier()`, `is_paused()` |
| **Save/Load System** | Serializes full tick state for save files | Direct read/write of `tick_count`, `current_day`, `speed_multiplier`, `pause_state`, `tick_remainder` |
| **Day Overview System** | Receives day-end signal, displays production/consumption summary | `day_transition(1)` — own system, own GDD |
| **Inventory/Storage System** | In-transit transport timer tracking | `ticks_advanced(delta_ticks)` — Inventory subscribes to decrement `remaining_ticks` on IN_TRANSIT items |

---

## Tuning Knobs

| Knob | Default | Safe Range | Gameplay Effect |
|------|---------|------------|-----------------|
| `TICKS_PER_DAY` | 1000 | 500–2000 | Length of one in-game day in ticks |
| `TICKS_PER_SECOND_BASE` | 10 | 5–20 | Tick accumulation rate at 1x speed |
| `MAX_TICKS_PER_FRAME` | 100 | 50–200 | Safety cap against lag spike time jumps |
| `SPEED_OPTIONS` | [0.5, 1.0, 2.0] | fixed | Available speed multiplier steps |

---

## Visual/Audio Requirements

### Visual

- **Speed indicator** in HUD: three buttons (0.5x / 1x / 2x), active speed highlighted
- **Pause indicator**: visible icon (e.g. pause symbol) when game is in PAUSED state; optional subtle screen vignette
- **Day counter** in HUD: current day number, always visible
- **Day Overview overlay**: owned by the Day Overview System (see separate GDD) — Tick System only auto-pauses and fires the event

### Audio

- **Speed change**: short click sound on each speed multiplier press
- **Day transition**: soft chime or ambient swell when Day Overview appears
- No continuous tick sound — avoids repetitive audio fatigue over long sessions

---

## UI Requirements

All UI listed here is owned by the Tick System (HUD controls). The Day Overview modal is owned by the Day Overview System (separate GDD).

### HUD Controls (always visible)

| Element | Description |
|---------|-------------|
| **Speed buttons** | Three buttons: 0.5x / 1x / 2x. Active speed highlighted. Pressing an active button has no effect. |
| **Pause/Play button** | Toggles PAUSED ↔ RUNNING state. Displays current state (pause icon when running, play icon when paused). |
| **Day counter** | Displays current day number ("Day 12"). Updates on `day_transition`. |
| **Tick progress bar** | Optional: shows tick_count progress from 0–1000 for the current day. Fills over the course of the day, resets to 0 on day transition. |

---

## Acceptance Criteria

### Blocking (must pass before ship)

1. **Given** speed is 1x, **when** 100 real seconds elapse, **then** exactly 1000 ticks have accumulated (±1 frame tolerance)
2. **Given** game is PAUSED, **when** no player action occurs, **then** `tick_count` does not change
3. **Given** game is PAUSED, **when** player performs a manual action costing 80 ticks, **then** `tick_count` increases by 80 and all subscribed systems receive `ticks_advanced(80)`
4. **Given** speed is 2x, **when** player performs a manual action costing 80 ticks, **then** action costs 80 ticks (speed has no effect on manual action cost)
5. **Given** `tick_count` reaches 1000, **then** `day_transition(1)` fires, `tick_count` resets to 0, game enters PAUSED state
6. **Given** a lag spike produces a raw tick_delta > 100, **then** tick_delta is clamped to 100 and no multi-day skip occurs
7. **Given** a save is created at `tick_count = 450`, **when** loaded, **then** game resumes at exactly `tick_count = 450` with identical remainder

### Advisory (quality bar)

8. **Given** speed changes rapidly (multiple calls per frame), **then** no duplicate `speed_changed` events fire
9. **Given** pause is toggled 5+ times in 1 second, **then** `tick_count` remains stable during all PAUSED frames

---

## Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| OQ1 | Should there be a 3x speed option (fast-forward for late-game pacing)? | Currently SPEED_OPTIONS = [0.5, 1.0, 2.0]. 3x was mentioned in the original Overview but not in SPEED_OPTIONS. Adding 3x changes day duration (33.3s) and would make manual actions more efficient (more time per real second to act). | **Deferred — discuss with producer for pacing goals.** |
| OQ2 | Should the tick progress bar (UI section) be mandatory or optional? | UI Requirements lists it as optional. If implemented, it adds a HUD element that tracks day progress — important for pillar 2 transparency but increases UI complexity. | **Deferred to HUD GDD.** |
