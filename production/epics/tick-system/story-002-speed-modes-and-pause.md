# Story 002: Speed Modes and Pause State Machine

> **Epic**: Tick System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/tick-system.md`
**Requirement**: `TR-tick-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001: Tick System Design and Time Management
**ADR Decision Summary**: Speed multiplier is stored as `speed_multiplier: float` constrained to `SPEED_OPTIONS = [0.5, 1.0, 2.0]`. Pause state is `is_paused: bool`; when true, `set_process(false)` is called to stop `_process()` entirely (zero CPU cost). Both changes emit corresponding signals.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: `set_process(bool)` is stable since Godot 1.0. Idempotent state changes must not re-emit signals. No post-cutoff APIs used.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern
- Forbidden: OS-level clock; hardcoded speed values outside SPEED_OPTIONS constant
- Guardrail: Pause state change must call `set_process()` — no manual guard variables in `_process()`

---

## Acceptance Criteria

*From GDD `design/gdd/tick-system.md`:*

- [ ] **AC-1**: Given game is PAUSED, when no player action occurs, then `tick_count` does not change and `ticks_advanced` does not fire
- [ ] **AC-2**: Given game is RUNNING at 2x speed, when 50 real seconds elapse, then 1000 ticks accumulate (2× the 1x rate)
- [ ] **AC-3**: Given game is RUNNING at 0.5x speed, when 200 real seconds elapse, then 1000 ticks accumulate (0.5× the 1x rate)
- [ ] **AC-4**: Given speed changes are called with rapid succession (multiple per frame), then `speed_changed` fires only once per actual change and not for duplicate values
- [ ] **AC-5**: Given pause is toggled 5+ times in 1 second, then `tick_count` remains stable (zero increment) during all PAUSED frames
- [ ] **AC-6**: Given `set_pause(true)` is called when already PAUSED, then no `pause_state_changed` event fires (idempotent)
- [ ] **AC-7**: Given `set_speed(1.5)` is called (invalid value), then speed clamps to nearest valid option and `speed_changed` fires with the clamped value

---

## Implementation Notes

*Derived from ADR-0001 Implementation Guidelines:*

Add to the TickSystem Autoload (extends Story 001 skeleton):

```gdscript
const SPEED_OPTIONS: Array[float] = [0.5, 1.0, 2.0]

var speed_multiplier: float = 1.0
var is_paused: bool = true  # Start paused — player resumes intentionally

signal speed_changed(new_speed: float)
signal pause_state_changed(is_paused: bool)

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

Key invariant: `set_process(false)` when paused means `_process()` never runs — no guard needed inside `_process()` beyond the early-return that Story 001 already has.

Speed changes take effect the next frame (`speed_multiplier` is read at the start of `_process()`). The current frame's `tick_delta` is already computed when `set_speed()` is called — do not recalculate.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: The actual `_process()` accumulation formula (tick_remainder, tick_delta)
- Story 003: `advance_ticks_manual()` — manual actions while paused
- Story 004: Day transition triggered by `_accumulate_ticks()`

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: PAUSED = no tick accumulation
  - Given: `TickSystem` is paused (`is_paused = true`)
  - When: `_process(10.0)` is simulated (would be 100 ticks at 1x if running)
  - Then: tick_count unchanged; `ticks_advanced` not emitted
  - Edge cases: Pause mid-session with non-zero remainder — remainder not lost but no accumulation occurs

- **AC-2**: 2x speed doubles accumulation rate
  - Given: `TickSystem` RUNNING, `set_speed(2.0)` called, tick_count = 0
  - When: 50 seconds simulated
  - Then: tick_count == 1000 (±1 frame)

- **AC-3**: 0.5x speed halves accumulation rate
  - Given: `TickSystem` RUNNING, `set_speed(0.5)` called, tick_count = 0
  - When: 200 seconds simulated
  - Then: tick_count == 1000 (±1 frame)

- **AC-4**: No duplicate speed_changed signals
  - Given: speed_multiplier == 1.0
  - When: `set_speed(1.0)` called three times in a row
  - Then: `speed_changed` emits zero times (same value = no-op)

- **AC-5**: Pause stability under rapid toggle
  - Given: `TickSystem` toggled pause/unpause 10 times rapidly (simulated in test)
  - When: `_process(1.0)` called during each PAUSED frame
  - Then: tick_count increments only during RUNNING frames

- **AC-6**: Idempotent pause — `set_pause(true)` when already paused
  - Given: `is_paused == true`
  - When: `set_pause(true)` called
  - Then: `pause_state_changed` not emitted; `is_paused` still true

- **AC-7**: Invalid speed clamps to nearest valid
  - Given: current speed = 1.0
  - When: `set_speed(1.5)` called
  - Then: `speed_multiplier` == 1.0 OR 2.0 (nearest valid); `speed_changed` emits once with clamped value
  - Edge cases: `set_speed(0.0)` → clamps to 0.5; `set_speed(99.0)` → clamps to 2.0

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/tick/speed_pause_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (TickSystem Autoload skeleton + `_process()` accumulation exists)
- Unlocks: Story 003 (Manual Advancement uses `is_paused`), Story 004 (Day Transition)

---

## Completion Notes
**Completed**: 2026-05-22
**Criteria**: 7/7 passing
**Deviations**:
- ADVISORY: Story manifest version "Not yet created"; current control-manifest.md is 2026-05-14 (lean mode — no architectural conflicts found)
- ADVISORY: `SPEED_OPTIONS` is hardcoded as `const` (line 19) rather than `@export` or Resource — violates "gameplay values must be data-driven" standard. Should be addressed before Story 003+.
**Test Evidence**: `tests/unit/tick/speed_pause_test.gd` — 10/10 tests pass (499ms)
**Code Review**: Completed — /code-review verdict: APPROVED WITH SUGGESTIONS (2 advisory gaps: `get_process()` state not directly asserted, MAX_TICKS_PER_FRAME clamping untested)
