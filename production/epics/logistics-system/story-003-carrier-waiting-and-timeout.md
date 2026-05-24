# Story 003: Carrier Waiting and Timeout

> **Epic**: Logistics System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0011: Logistics System — Carrier FSM and Route Architecture
**ADR Decision Summary**: `CARRIER_WAITING_TIMEOUT` constant (default 300 ticks). `wait_ticks` counter in WAITING_SOURCE and WAITING_DESTINATION. If timeout exceeded, carrier returns home and route is deactivated.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None. Simple counter accumulation.

**Control Manifest Rules (Feature Layer)**:
- Required: 4-stage building lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH)
- Required: Production carrier transport — output held in building buffer, carrier calls `collect_output()` and `try_deposit()`
- Required: Carrier travel time formula — `carrier_travel_ticks = floor(distance × ticks_per_tile)`

---

## Acceptance Criteria

*From GDD `design/gdd/logistics-system.md`, scoped to this story:*

- [ ] WAITING_SOURCE polls once per tick for building output; if no item appears within 300 consecutive ticks, carrier enters RETURN_HOME and route transitions to DEACTIVATED
- [ ] WAITING_DESTINATION polls once per tick for free space; if no space opens within 300 consecutive ticks, carrier returns home with item and route transitions to DEACTIVATED
- [ ] When destination frees space while carrier is WAITING_DESTINATION, unload occurs within 1 tick
- [ ] When building produces output while carrier is WAITING_SOURCE, pickup occurs within 1 tick
- [ ] `carrier_waiting_timeout` is configurable (Tuning Knob default 300, safe range 100-1000)
- [ ] Route deactivation on timeout records the reason ("timeout at source" or "timeout at destination") for diagnostics

---

## Implementation Notes

*Derived from ADR-0011 Implementation Guidelines:*

**wait_ticks accumulation** (from ADR-0011 `_process_carrier`):
```
WAITING_SOURCE:
    route.wait_ticks += 1
    if route.wait_ticks >= CARRIER_WAITING_TIMEOUT:
        route.carrier_state = RETURN_HOME
        route.remaining_ticks = calc_travel_time(home_position)
        deactivate_route(route, "timeout at source")
        return
    // Check for buffer output
    if building.has_output_buffer(source_id):
        pickup = min(buffer_amount, carrier_capacity)
        building.collect_output(source_id)
        route.cargo = pickup
        route.cargo_resource = resource_type
        route.carrier_state = TRAVEL_TO_DESTINATION
        route.remaining_ticks = calc_travel_time(destination_building_id)

WAITING_DESTINATION:
    route.wait_ticks += 1
    if route.wait_ticks >= CARRIER_WAITING_TIMEOUT:
        route.carrier_state = RETURN_HOME
        route.remaining_ticks = calc_travel_time(home_position)
        deactivate_route(route, "timeout at destination")
        return
    // Check for free space
    if inv.get_occupied_slots(dest_id) < inv.get_slot_count(dest_id):
        deposit_result = inv.try_deposit(dest_id, cargo_resource, cargo)
        if deposit_result.success:
            route.cargo = 0
            route.carrier_state = RETURN_HOME
            route.remaining_ticks = calc_travel_time(home_position)
```

**Route deactivation on timeout**: The route is set to lifecycle_state = DEACTIVATED, active = false. The route record is preserved (not deleted) so the player can reassign a new NPC. This is consistent with EC-L4 and EC-L5 in the GDD.

**Constant definition**:
```
const CARRIER_WAITING_TIMEOUT: int = 300  # Tuning Knob — safe range 100-1000
```

**Edge case interaction**: WAITING_SOURCE can transition to WAITING_DESTINATION if the carrier picks up an item at the source, travels to destination, and finds it full. The `wait_ticks` counter is reset to 0 when entering WAITING_DESTINATION — source timeout and destination timeout are independent counters.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Route model and slot validation (precondition)
- [Story 002]: Carrier FSM core loop (the state transitions that lead to WAITING_SOURCE/WAITING_DESTINATION)
- [Story 004]: Building status integration (how DEACTIVATED routes affect building status)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**WAITING_SOURCE timeout:**

- **AC-1**: Carrier returns home after 300 ticks with no output
  - Given: Route active, carrier at AT_SOURCE → enters WAITING_SOURCE (buffer empty), wait_ticks = 0
  - When: 299 ticks advance, building never produces
  - Then: state still WAITING_SOURCE, wait_ticks = 299
  - When: 1 more tick advances
  - Then: state = RETURN_HOME, route.lifecycle_state = DEACTIVATED, reason = "timeout at source", remaining_ticks = calc_travel_time(home)
  - Edge cases: Timeout of 1 tick (if CARRIER_WAITING_TIMEOUT = 1) should trigger immediately on first WAITING_SOURCE tick

**WAITING_DESTINATION timeout:**

- **AC-2**: Carrier returns home with item after 300 ticks at full destination
  - Given: Carrier at AT_DESTINATION → enters WAITING_DESTINATION with cargo = 1, wait_ticks = 0
  - When: 299 ticks advance, storage remains full
  - Then: state still WAITING_DESTINATION, wait_ticks = 299, cargo still held by carrier
  - When: 1 more tick advances
  - Then: state = RETURN_HOME, route.lifecycle_state = DEACTIVATED, reason = "timeout at destination"
  - Edge cases: Carrier returns home with item — the item should be handled per EC-L2 (return to source storage on arrival)

**Early resolution:**

- **AC-3**: Destination frees space — unload within 1 tick
  - Given: Carrier WAITING_DESTINATION, wait_ticks = 150, cargo = 1
  - When: Items removed from destination storage (slot opens)
  - Then: Within 1 tick (the same tick the space check occurs), carrier transitions to RETURN_HOME with cargo = 0
  - Edge cases: Space opens and closes again before carrier arrives — carrier still polls next tick and may find it full again

- **AC-4**: Source produces output — pickup within 1 tick
  - Given: Carrier WAITING_SOURCE, wait_ticks = 200, buffer empty
  - When: Building completes production cycle (adds item to buffer)
  - Then: Within 1 tick, carrier picks up item and transitions to TRAVEL_TO_DESTINATION
  - Edge cases: Buffer produces item but carrier_capacity = 0 → pickup = 0, carrier still goes to TRAVEL_TO_DESTINATION (empty-handed)

**Configurability:**

- **AC-5**: Timeout value is a Tuning Knob (default 300, range 100-1000)
  - Given: No routes exist
  - When: CARRIER_WAITING_TIMEOUT is changed to 500
  - Then: All carriers use the new value for both WAITING_SOURCE and WAITING_DESTINATION
  - Edge cases: Setting to 1 means carrier times out after 1 tick of waiting; setting to 1000 means 1000 ticks before timeout

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/logistics/carrier_waiting_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (carrier FSM core loop must establish WAITING_SOURCE/WAITING_DESTINATION states first)
- Unlocks: None (independent feature)
