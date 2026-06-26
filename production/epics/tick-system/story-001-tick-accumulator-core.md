# Story 001: Tick Accumulator Core

> **Epic**: Tick System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/tick-system.md`
**Requirement**: `TR-tick-001`, `TR-tick-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001: Tick System Design and Time Management
**ADR Decision Summary**: The Tick System is an Autoload singleton (`TickSystem`) using `_process(delta)` for automatic tick accumulation. Each frame: `raw_ticks = delta × 10 × speed_multiplier`, clamped to MAX_TICKS_PER_FRAME (100), with fractional remainder carried forward. Signals are emitted to subscribers; UI may poll query methods.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: All APIs used (`_process`, `Node`, signals, `clampi`, `fmod`, `floor`) are stable since Godot 1.0. No post-cutoff APIs. Verification required: test accumulation accuracy at 30fps, 60fps, 144fps.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern for all Foundation systems
- Forbidden: OS-level clock usage — use engine delta only; hardcoded resource definitions
- Guardrail: Performance budget 0.1ms per `_process()` call

---

## Acceptance Criteria

*From GDD `design/gdd/tick-system.md`:*

- [ ] **AC-1**: Given speed is 1x and the game is RUNNING, when 100 real seconds elapse at any stable FPS (30/60/144), then exactly 1000 ticks have accumulated (±1 frame tolerance)
- [ ] **AC-2**: Given a lag spike where raw delta produces more than 100 raw ticks in a single frame, then tick_delta is clamped to 100 and at most 100 ticks accumulate that frame
- [ ] **AC-3**: Given tick_delta > 0, then `ticks_advanced(tick_delta)` signal fires with the correct count each frame ticks accumulate
- [ ] **AC-4**: Given the fractional remainder from one frame is 0.7, when the next frame accumulates 0.5 raw ticks, then the combined value produces 1 whole tick (remainder carry prevents drift)

---

## Implementation Notes

*Derived from ADR-0001 Implementation Guidelines:*

Create `src/systems/tick_system.gd` as an Autoload singleton named `TickSystem`:

```gdscript
extends Node

const TICKS_PER_DAY: int = 1000
const TICKS_PER_SECOND_BASE: float = 10.0
const MAX_TICKS_PER_FRAME: int = 100

var tick_remainder: float = 0.0
var tick_count: int = 0

signal ticks_advanced(delta_ticks: int)

func _process(delta: float) -> void:
	if is_paused:
		return
	if delta < 0.0:
		delta = 0.0
	var raw_ticks: float = delta * TICKS_PER_SECOND_BASE * speed_multiplier
	raw_ticks += tick_remainder
	var tick_delta: int = clampi(floori(raw_ticks), 0, MAX_TICKS_PER_FRAME)
	tick_remainder = fmod(raw_ticks, 1.0)
	if tick_delta > 0:
		_accumulate_ticks(tick_delta)
```

The remainder is computed with `fmod(raw_ticks, 1.0)` — not `raw_ticks - tick_delta` — to avoid floating-point drift accumulation over long sessions.

If `tick_remainder >= 1.0` due to float precision drift: extract whole ticks (`floori(tick_remainder)`), add to tick_count, fire `ticks_advanced`, and restore remainder to `[0.0, 1.0)` range.

Register `TickSystem` as an Autoload in `project.godot` (Project → Settings → Autoload, name `TickSystem`, path to the scene/script).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: Speed multiplier switching and pause state machine (`is_paused`, `speed_multiplier` variables + state transitions)
- Story 003: `advance_ticks_manual()` method
- Story 004: Day transition logic (`while tick_count >= TICKS_PER_DAY`)

*Stub these as variables/constants only — do not implement their logic in this story.*

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Tick accumulation rate — 1x speed, 100 seconds = 1000 ticks
  - Given: `TickSystem` is RUNNING at 1x speed, tick_count = 0, tick_remainder = 0.0
  - When: 100 frames are simulated with delta = 1.0 second each (total 100s)
  - Then: tick_count == 1000 (±1 tick tolerance for floating-point frame boundary)
  - Edge cases: repeat at simulated 30fps (delta=0.0333), 60fps (delta=0.0167), 144fps (delta=0.00694)

- **AC-2**: Lag spike clamping
  - Given: `TickSystem` is RUNNING at 1x speed
  - When: `_process(10.0)` is called (10 second lag spike)
  - Then: tick_delta == 100 (clamped from 100 raw), tick_count increases by exactly 100
  - Edge cases: delta=0.0 produces tick_delta=0; delta=1.0 at 2x produces raw=20, tick_delta=20 (under cap)

- **AC-3**: ticks_advanced signal fires with correct count
  - Given: A subscriber connects to `ticks_advanced`
  - When: `_process(1.0)` at 1x speed produces tick_delta=10
  - Then: Subscriber receives exactly one emission with value 10
  - Edge cases: tick_delta=0 (no signal emitted); tick_delta=100 (signal fires with 100)

- **AC-4**: Remainder carry prevents drift
  - Given: tick_remainder = 0.7
  - When: next frame has raw_ticks = 0.5 (delta=0.05 at 1x)
  - Then: combined raw_ticks = 1.2, tick_delta = 1, new tick_remainder = 0.2
  - Edge cases: remainder = 0.999 carries correctly into next tick; remainder never reaches 1.0 from fmod

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/tick/tick_accumulator_test.gd` — must exist and pass

**Status**: [x] Created and passing — 15/15 tests

---

## Dependencies

- Depends on: None (this is the first story; creates the TickSystem Autoload skeleton)
- Unlocks: Story 002 (Speed Modes and Pause), Story 003 (Manual Advancement), Story 004 (Day Transition)

## Completion Notes
**Completed**: 2026-05-23
**Criteria**: 4/4 passing
**Deviations**: Advisory — implementation bundled Stories 002, 003, and 004 stubs into the same file (intentional Foundation system consolidation, no scope creep)
**Test Evidence**: Unit test at `tests/unit/tick/tick_accumulator_test.gd` — 15/15 passing
**Code Review**: Skipped — Lean mode
