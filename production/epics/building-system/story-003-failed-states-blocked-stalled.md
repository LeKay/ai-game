# Story 003: Failed States — BLOCKED and STALLED

> **Epic**: Building System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration — ADR-0008
> **Manifest Version**: N/A — control manifest not yet created

## Context

**GDD**: `design/gdd/building-system.md`
**Requirements**:
- `TR-build-004` (Production cycle tick advancement — BLOCKED state when inputs unavailable)
- `TR-build-005` (NPC assignment slot — BLOCKED when no NPC assigned)

**ADR Governing Implementation**: ADR-0008: Building Placement and Production System Architecture
**ADR Decision Summary**: BLOCKED state entered when `try_start_production_cycle()` returns BLOCKED_NO_INPUT, BLOCKED_NO_NPC, BLOCKED_NO_CARRIER, or similar. "No carrier assigned" (input or output) is an explicit BLOCKED reason alongside missing NPC/resource. Auto-recovery: building re-checks on every `on_ticks_advanced()` event and transitions back to OPERATING when the condition resolves. STALLED state entered when a production cycle completes and the output carrier cannot collect — either `output_carrier_id == null` or the output buffer is full. Output held in `buffered_output` indefinitely, never discarded. Auto-recovery: carrier arrives and calls `collect_output()`, building transitions back to OPERATING. Visual distinction: BLOCKED = yellow indicator, tooltip shows missing input/carrier. STALLED = red pulsing indicator, tooltip shows "No output carrier" or "Output buffer full." Mid-cycle block rule: current production cycle completes — building already committed. `on_container_removed` signal from InventorySystem triggers BLOCKED for affected buildings.

**Engine**: Godot 4.6 | **Risk**: LOW (state transitions, signal subscription)
**Engine Notes**: No post-cutoff APIs. State enum already defined in ADR-0008. `stalled_output` field is `Array[ResourcePin]`. `building_state_changed` signal with reason string for HUD consumption.

**Control Manifest Rules (this layer)**: N/A — control manifest not yet created

---

## Acceptance Criteria

*From GDD `design/gdd/building-system.md`, scoped to this story:*

- [ ] **AC-10** GIVEN a production building in OPERATING state WITH inputs available WHEN the next tick cycle fires THEN `try_start_production_cycle()` is called, inputs are deducted, and the production cycle begins (state remains OPERATING, sub-phase = PRODUCE)
- [ ] **AC-11** GIVEN a production building is in BLOCKED state WHEN the missing input is provided THEN on the next tick cycle `try_start_production_cycle()` succeeds and the building transitions back to OPERATING with the production cycle starting automatically — no player action required
- [ ] **AC-12** GIVEN a production building has no NPC assigned WHEN it enters OPERATING state THEN it enters IDLE sub-phase, does NOT start a production cycle, and the building shows BLOCKED on the next tick cycle (missing NPC)
- [ ] **AC-12b** GIVEN a production building has no input carrier assigned WHEN it tries to start a production cycle THEN it enters BLOCKED state with reason "No carrier assigned (inputs)" and waits until an input carrier is configured via the Transportation Management UI
- [ ] **AC-12c** GIVEN a production building has no output carrier assigned WHEN a production cycle completes THEN it enters STALLED state with reason "No output carrier" — output held in `buffered_output` indefinitely, never discarded
- [ ] **AC-13** GIVEN a production building completes a cycle and the output carrier is unavailable or not assigned WHEN the cycle completes THEN the building enters STALLED state, the `buffered_output` field stores the production output, `building_stalled` signal is emitted with reason, and the output is never discarded
- [ ] **AC-14** GIVEN a production building is in STALLED state WHEN the output carrier arrives and calls `collect_output()` THEN the output buffer is cleared, the building transitions back to OPERATING with `building_destalled` signal emitted, and the next production cycle can begin
- [ ] **AC-23** GIVEN a storage building (Storage Area or Storage Building) WHEN it transitions to OPERATING THEN it never enters BLOCKED or STALLED — these failure states apply only to production buildings

---

## Implementation Notes

*Derived from ADR-0008 Implementation Guidelines:*

**BLOCKED state transitions (from ADR-0008):**
```
elif building.state == OPERATING:
    if building.needs_production_cycle():
        result = building.try_start_production_cycle()
        if result in [BLOCKED_NO_INPUT, BLOCKED_NO_NPC, BLOCKED_NO_CARRIER]:
            building.state = BLOCKED
            match result:
                BLOCKED_NO_NPC:
                    missing = "No NPC assigned"
                BLOCKED_NO_CARRIER:
                    missing = "No carrier assigned (inputs)"
                BLOCKED_NO_INPUT:
                    missing = "Missing: " + building.missing_input_name()
                _:
                    missing = "Unknown"
            building.emit_signal("building_blocked", building.building_id, missing)
            sync_visual_to_state(building)
        elif result == SUCCESS:
            pass  # production cycle running, state stays OPERATING
```

**STALLED state transitions (from ADR-0008):**
```
if building.is_production_complete():
    building.buffered_output = building._current_production_output  # always base_output
    emit_signal("production_output_ready", building.building_id, building.buffered_output)
    # STALLED if no output carrier is assigned or buffer is already occupied
    if building.output_carrier_id == null or building.output_buffer_full():
        building.state = STALLED
        building.emit_signal("building_stalled", building.building_id, "no_output_carrier")
        sync_visual_to_state(building)
        # Output is NEVER discarded — stored in buffered_output until carrier collects
    else:
        building.accumulated_ticks = 0
        sync_visual_to_state(building)

# Auto-recovery from STALLED: carrier calls collect_output()
func collect_output(building_id: String) -> Array:
    var building := all_buildings_map.get(building_id)
    if building == null or building.state != STALLED:
        return []
    var output := building.buffered_output.duplicate()
    building.buffered_output.clear()
    building.state = OPERATING
    building.accumulated_ticks = 0
    building.emit_signal("building_destalled", building.building_id)
    sync_visual_to_state(building)
    return output
```

**Auto-recovery from BLOCKED (on every tick cycle):**
```
# The tick loop checks needs_production_cycle() for OPERATING buildings.
# For BLOCKED buildings, it checks if conditions improved:
elif building.state == BLOCKED:
    if building.can_resume_production():
        # Inputs now available — attempt to start cycle
        result = building.try_start_production_cycle()
        if result == SUCCESS:
            building.state = OPERATING
            building.emit_signal("building_unblocked", building.building_id)
            sync_visual_to_state(building)
        # If still BLOCKED, stay in BLOCKED (check again next tick)
```

**Auto-recovery from STALLED (on next production cycle):**
```
# When a STALLED building's production cycle would restart:
elif building.state == STALLED:
    # Check if storage has space (it always does — we have stalled_output)
    result = building.attempt_deposit_output()
    if result == SUCCESS:
        building.state = OPERATING
        building.stalled_output.clear()
        building.emit_signal("building_destalled", building.building_id)
        sync_visual_to_state(building)
    # If still full (edge case: another building filled it), stay STALLED
```

**Orphaned container handling (from ADR-0008 signals):**
```
# BuildingRegistry subscribes to InventorySystem.on_container_removed:
func _on_container_removed(container_id: StringName) -> void:
    for building in all_buildings:
        if building.assigned_container_id == container_id:
            # This building's storage was demolished
            if building.state == OPERATING or building.state == BLOCKED:
                building.assigned_container_id = null
                building.state = BLOCKED
                building.emit_signal("building_blocked", building.building_id, "Storage demolished")
                building.emit_signal("building_container_removed", building.building_id)
```

**Mid-cycle block rule (from GDD Rule 7):**
```
# If inputs become unavailable mid-cycle (storage demolished, resource consumed by another building):
# The current production cycle COMPLETES — building already consumed inputs.
# On the NEXT cycle start (after deposit succeeds or stalls), the building
# checks inputs again and enters BLOCKED if they're missing.
# Implementation: try_start_production_cycle() is only called when
# building.needs_production_cycle() returns true — i.e., when no cycle is running.
# Mid-cycle input removal is handled naturally: the running cycle completes,
# deposit happens, then the next needs_production_cycle() check fails inputs → BLOCKED.
```

**Storage buildings never fail (from GDD Rule 5):**
```
# Storage types have no production cycle, so BLOCKED/STALLED don't apply:
if building.type in [STORAGE_AREA, STORAGE_BUILDING]:
    # These buildings transition PLACE → OPERATING and stay there.
    # needs_production_cycle() returns false for storage types.
    # No BLOCKED/STALLED state transitions possible.
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: Production cycle start logic (the input consumption is in this story; cycle duration formulas and distance are Story 002)
- Story 004: NPC assignment workflow (this story handles the case where no NPC is assigned; the assignment UI and NPC System flow is Story 004)
- Story 005: Demolition (this story handles orphaned storage reference via signal; the full demolition flow including NPC release is Story 005)

---

## QA Test Cases

**AC-10**: Production cycle starts with inputs available
  - Given: Lumber Camp in OPERATING state, assigned storage has tool with `current_charge >= charge_cost`, NPC assigned
  - When: tick cycle fires, `needs_production_cycle()` returns true
  - Then: `try_start_production_cycle()` deducts tool charge via `charge_cost`, `production_cycle_ticks = 0`, state = OPERATING (PRODUCE sub-phase)
  - Edge cases: tool charge exactly equal to charge_cost → cycle starts; tool charge below charge_cost → BLOCKED

**AC-11**: BLOCKED → OPERATING auto-recovery
  - Given: Lumber Camp in BLOCKED state (tool `current_charge` below `charge_cost`, e.g., storage has 0 charge on all tools)
  - When: player deposits a fresh tool (full charge) into storage (via player action or another building)
  - Then: next tick cycle, `can_resume_production()` returns true, `try_start_production_cycle()` succeeds, state = OPERATING, `building_unblocked` signal emitted
  - Edge cases: tool deposited but charge still below charge_cost → stays BLOCKED; tool charge meets charge_cost exactly → transitions; multiple cycles of BLOCKED → each tick cycle re-checks

**AC-12**: No NPC = BLOCKED
  - Given: Lumber Camp enters OPERATING state (from CONSTRUCTING completion)
  - When: tick cycle fires, `needs_production_cycle()` returns true
  - Then: `assigned_npc_id == null`, `try_start_production_cycle()` returns BLOCKED, state = BLOCKED, tooltip shows "No NPC assigned"
  - Edge cases: Residential House (doesn't need NPC for production, only for spawning) → never BLOCKED for NPC; production building with NPC later assigned → transitions to OPERATING (AC-11 path)

**AC-12b/12c**: No carrier → BLOCKED / STALLED
  - Given: Lumber Camp with NPC assigned, inputs available, but no output carrier configured
  - When: production cycle completes
  - Then: buffered_output = [5 Wood], state = STALLED, building_stalled signal emitted with reason "no_output_carrier", red indicator shown
  - Given: Lumber Camp with no input carrier configured
  - When: try_start_production_cycle() called
  - Then: returns BLOCKED_NO_CARRIER, state = BLOCKED, tooltip "No carrier assigned (inputs)"

**AC-13**: STALLED when no output carrier
  - Given: Lumber Camp in OPERATING state, production cycle completes, no output carrier assigned
  - When: is_production_complete() fires
  - Then: buffered_output = [5 Wood], state = STALLED, building_stalled signal, red pulsing indicator shown; output NEVER discarded

**AC-14**: STALLED → OPERATING via carrier collect
  - Given: Lumber Camp in STALLED state, buffered_output = [5 Wood]
  - When: output carrier NPC arrives and calls collect_output(building_id)
  - Then: output returned to carrier, buffered_output cleared, state = OPERATING, building_destalled signal emitted
  - Edge cases: collect_output called on non-STALLED building → returns [] (no-op); collect_output while production cycle running → only valid from STALLED state

**AC-23**: Storage buildings can't fail
  - Given: Storage Area in OPERATING state (instant construction, no production cycle)
  - When: any amount of time passes, any number of tick cycles
  - Then: state remains OPERATING, never enters BLOCKED or STALLED
  - Edge cases: Storage Building (120 tick construction, then OPERATING) → never fails; Storage Area with 0 capacity → never fails (it doesn't produce); storage building assigned as storage by production buildings → production building can stall, but the storage building itself never fails

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/building_system/failed_states_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (production cycle start logic must exist before failed states can be tested)
- Unlocks: Story 004 (NPC assignment requires buildings to enter/exit BLOCKED state)
