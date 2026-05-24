# Story 005: Save and Load Tick State

> **Epic**: Tick System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Integration
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/tick-system.md`
**Requirement**: `TR-tick-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001: Tick System Design and Time Management (primary); ADR-0006: Save and Load Format and Serialization Order (secondary)
**ADR Decision Summary**: Tick state (tick_count, current_day, speed_multiplier, is_paused, tick_remainder) is serialized as a JSON dictionary under the `"tick"` key. Load order places TickSystem first, before all other systems. Exact tick_count and tick_remainder must round-trip correctly to preserve determinism.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: `FileAccess.open()` returns a `FileAccess` object (not bool) — null on failure. This is a breaking change from Godot 4.3. Must null-check the result, not use a bool check. See ADR-0002 notes.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern; JSON save format; load order: TickSystem deserializes first
- Forbidden: circular_serialization; direct_dictionary_access_in_deserialize (use typed accessors)
- Guardrail: tick_remainder must be preserved as float; tick_count must be preserved as int

---

## Acceptance Criteria

*From GDD `design/gdd/tick-system.md`:*

- [ ] **AC-1**: Given game state at `tick_count = 450`, `tick_remainder = 0.73`, `current_day = 7`, `speed_multiplier = 2.0`, `is_paused = true`, when serialized and deserialized, then all five fields are restored exactly
- [ ] **AC-2**: Given save loaded at `tick_count = 999`, `tick_remainder = 0.8`, when game resumes and one frame accumulates, then day transition may fire (state is consistent — accumulation continues from exact saved state)
- [ ] **AC-3**: Given tick state is serialized and immediately deserialized with no game running between, then the deserialized TickSystem behaves identically to the original (determinism guarantee)
- [ ] **AC-4**: Given a save file with a missing or invalid `"tick"` block, then load fails fast with a logged error and the game does not silently start with default tick state

---

## Implementation Notes

*Derived from ADR-0001 and ADR-0006 Implementation Guidelines:*

Add serialization methods to TickSystem:

```gdscript
func serialize() -> Dictionary:
    return {
        "tick_count": tick_count,
        "tick_remainder": tick_remainder,
        "current_day": current_day,
        "speed_multiplier": speed_multiplier,
        "is_paused": is_paused
    }

func deserialize(data: Dictionary) -> void:
    if not data.has_all(["tick_count", "tick_remainder", "current_day",
                         "speed_multiplier", "is_paused"]):
        push_error("TickSystem.deserialize(): missing required keys")
        return
    tick_count = int(data["tick_count"])
    tick_remainder = float(data["tick_remainder"])
    current_day = int(data["current_day"])
    speed_multiplier = float(data["speed_multiplier"])
    is_paused = bool(data["is_paused"])
    set_process(not is_paused)
```

The Save system (ADR-0006) calls `TickSystem.serialize()` as the first entry in the save dictionary (`"tick"` key) and `TickSystem.deserialize()` as the first call during load — before ResourceRegistry, GridMap, and all other systems.

`tick_remainder` is a float — JSON serialization must preserve float precision. Use GDScript's built-in JSON parser which handles this correctly.

Do not call `set_pause()` during `deserialize()` — call `set_process()` directly to avoid emitting `pause_state_changed` during load (subscribers may not be connected yet).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- The WorldSaveManager file I/O (ADR-0006 epic) — this story only implements `serialize()` and `deserialize()` on TickSystem
- Other systems' serialization — this story is limited to the `"tick"` block

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Full tick state round-trips correctly
  - Given: TickSystem with tick_count=450, tick_remainder=0.73, current_day=7, speed_multiplier=2.0, is_paused=true
  - When: `serialize()` called, then `deserialize()` called with the result
  - Then: All five fields match exactly (float equality within 0.0001 tolerance for tick_remainder)
  - Edge cases: tick_count=0; tick_count=999; tick_remainder=0.0; tick_remainder=0.999

- **AC-2**: Resume from near-day-boundary state
  - Given: Loaded state has tick_count=999, tick_remainder=0.8
  - When: One frame simulated at 1x RUNNING (delta=0.1 → raw_ticks=1.0 + 0.8 = 1.8)
  - Then: tick_delta=1, tick_count=1000 → day_transition fires; or tick_count=0 if transition fires in deserialize check — verify correct behavior per ADR

- **AC-3**: Determinism — serialize then deserialize produces identical behavior
  - Given: TickSystem at tick_count=500, tick_remainder=0.5, RUNNING, 1x speed
  - When: Serialized, new TickSystem instance created and deserialized, same frame sequence simulated on both
  - Then: Both instances produce identical tick_count after N frames

- **AC-4**: Invalid save data triggers fail-fast
  - Given: `deserialize({})` called (missing all keys)
  - When: Method executes
  - Then: `push_error()` called; tick_count unchanged; no silent default override

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/tick/save_load_tick_state_test.gd` — must exist and pass

**Status**: COMPLETE — 9/9 tests passing

---

## Completion Notes
**Completed**: 2026-05-23
**Criteria**: 4/4 passing (all automated)
**Deviations**: Advisory — story manifest version was "Not yet created"; current control manifest is 2026-05-14. No rule conflicts.
**Test Evidence**: Integration test at `tests/integration/tick/save_load_tick_state_test.gd` — 9 tests, 0 failures
**Code Review**: Complete (APPROVED WITH SUGGESTIONS)

---

## Dependencies

- Depends on: Story 004 must be DONE (all TickSystem fields are implemented: tick_count, tick_remainder, current_day, speed_multiplier, is_paused)
- Unlocks: Save/Load System epic (WorldSaveManager can now call TickSystem.serialize())
