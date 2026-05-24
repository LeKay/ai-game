# Sprint 1 — 2026-05-20 to 2026-06-19

## Sprint Goal
Implement Foundation layer systems (Tick, Resource, Input) to establish the simulation backbone — enabling all Core gameplay systems to build on stable interfaces.

## Capacity
- Total days: 40 (8 weeks, 5 days/week)
- Buffer (20%): 8 days reserved for unplanned work
- Available: 32 days

## Tasks

### Must Have (Critical Path)
| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|-------------|-------------------|
| TICK-01 | Tick System: Time accumulation core (Story 001) | gameplay-programmer | 3 | None | Autoload singleton accumulates time; 1000 ticks/day; correct float-to-int conversion with remainder carry; `ticks_advanced` signal fires |
| TICK-02 | Tick System: Speed modes + pause state machine (Story 002) | gameplay-programmer | 2 | TICK-01 | `SPEED_OPTIONS` enforced; `set_speed()` idempotent; `set_pause()` calls `set_process()` |
| TICK-03 | Tick System: Manual action tick advancement (Story 003) | gameplay-programmer | 1 | TICK-02 | `advance_ticks_manual(cost)` bypasses pause; speed multiplier does NOT affect manual cost; day transition runs inside manual path |
| TICK-04 | Tick System: Day-transition signal + auto-pause (Story 004) | gameplay-programmer | 2 | TICK-03 | `day_transition(1)` fires; `tick_count` resets to 0; auto-pause via `set_pause(true)`; `get_current_day()` returns correct value |
| TICK-05 | Tick System: Save and load tick state (Story 005) | gameplay-programmer | 1 | TICK-04 | `serialize()`/`deserialize()` round-trip preserves all 5 fields; missing keys trigger fail-fast; determinism guarantee |
| RES-01 | Resource System: JSON file loading + registry schema (Story 001) | gameplay-programmer | 2 | None | `FileAccess.open()` null-check (Godot 4.4+); `JSON.parse()` error handling; `_registry_version` stored; `_ResourceDefinition` inner class defined |
| RES-02 | Resource System: Schema validation + fail-fast (Story 002) | gameplay-programmer | 1 | RES-01 | Missing required fields halt load with `push_error()`; invalid category defaults with `push_warning()`; `max_charge <= 0.0` caught |
| RES-03 | Resource System: Dictionary cache + O(1) lookup API (Story 003) | gameplay-programmer | 2 | RES-02 | `_definitions: Dictionary[StringName, _ResourceDefinition]`; `get_definition()` returns null for unknown; `is_valid_id()` returns bool; O(1) performance verified |
| RES-04 | Resource System: Category enum + filtering (Story 004) | gameplay-programmer | 1 | RES-03 | `enum ResourceCategory { CONSUMABLE, PRODUCTION_GOOD }`; `get_all_by_category()` returns fresh Array; caller mutation doesn't affect cache |
| RES-05 | Resource System: Version migration + deprecated handling (Story 005) | gameplay-programmer | 1 | RES-04 | Forward version migration applies defaults; downgrade blocks load with error; deprecated resources remain in cache; `push_warning()` for migration |
| INP-01 | Input System: InputContext stack + action dispatch (Story 001) | gameplay-programmer | 3 | None | `Context` enum; `push_context()`/`pop_context()` stack semantics; `context_changed` signal; global actions bypass context; `_unhandled_input()` integration |
| INP-02 | Input System: Debounce system (Story 002) | gameplay-programmer | 1 | INP-01 | `request_debounce(action)` per-StringName; `DEBOUNCE_DELAY = 0.25s`; independent timers per action; rapid spam handled |
| INP-03 | Input System: Action rebinding + persistence (Story 003) | gameplay-programmer | 2 | INP-01 | `rebind_action()` modifies InputMap; conflict detection; swap_bindings; `keybindings.cfg` persistence; missing/corrupted file → defaults + warning |
| INP-04 | Input System: Context transition on UI open/close (Story 004) | gameplay-programmer | 2 | INP-01 | push_context(UI_ACTIVE) on UI open; pop_context() on UI close; `context_changed` fires; stack depth warning > 3; nested menus supported |
| INP-05 | Input System: PAUSED/UI_ACTIVE input discard (Story 005) | gameplay-programmer | 1 | INP-04 | PAUSED discards all non-pause actions; UI_ACTIVE discards non-UI; global actions always pass; Control node click doesn't reach world tile |

### Should Have
| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|-------------|-------------------|
| TICK-06 | Tick System HUD integration (play/pause button) | ui-programmer | 2 | TICK-02 | HUD top band displays tick speed; click cycles 0.5x→1x→2x→0.5x; play/pause toggles RUNNING↔PAUSED |
| RES-06 | Resource System: Example resource definitions (Wood, Stone, Berry) | gameplay-programmer | 1 | RES-04 | 3 Vertical Slice resources defined in JSON with all required fields |

### Nice to Have
| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|-------------|-------------------|
| INP-06 | Input System: Gamepad support (basic navigation) | ui-programmer | 2 | INP-01 | Gamepad d-pad navigates main menu (if existing); A button confirms; documented in input-system story |

## Carryover from Previous Sprint
| Task | Reason | New Estimate |
|------|--------|-------------|
| — | First sprint, no carryover | — |

## Risks
| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Tick System float precision issues at boundary crossings | Medium | High | Use float accumulator (per ADR-0001), not integer; test with edge cases (1000.5 ticks → 1000 tick, 0.5 remainder) |
| ResourceRegistry startup timing conflicts with other Autoloads | Medium | Medium | Lock in load order from ADR-0006; test load sequence explicitly |
| Input System context stack interacts with UI framework unexpectedly | Medium | Medium | Test context transitions with existing UX specs (main-menu, HUD); defer Gamepad to Nice to Have if needed |
| Single developer bottleneck — all Foundation stories on one person | High | Low | All 3 systems are independent; developer can choose which to work on next |

## Dependencies on External Factors
- ADR-0001 (Tick System) must be Accepted before Tick System stories begin
- ADR-0002 (Resource Data Registry) must be Accepted before Resource System stories begin
- ADR-0003 (Input Context System) must be Accepted before Input System stories begin
- ADR-0006 (Save/Load) establishes load-order invariant that ResourceRegistry must follow
- HUD integration (TICK-06) depends on existing HUD UX spec being finalized

## Definition of Done for this Sprint
- [ ] All Must Have tasks completed
- [ ] All tasks pass acceptance criteria
- [ ] QA plan exists (`production/qa/qa-plan-sprint-001.md`)
- [ ] All Logic stories have passing unit tests in `tests/unit/`
- [ ] Smoke check passed (`/smoke-check sprint`)
- [ ] QA sign-off report: APPROVED or APPROVED WITH CONDITIONS (`/team-qa sprint`)
- [ ] No S1 or S2 bugs in delivered features
- [ ] Design documents updated for any deviations
- [ ] Code reviewed and merged

> ✅ **QA Plan**: `production/qa/qa-plan-sprint-001-2026-05-20.md` is complete.
> Run `/smoke-check sprint` before QA hand-off. Run `/team-qa sprint` for sign-off.
