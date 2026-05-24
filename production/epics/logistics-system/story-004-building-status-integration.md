# Story 004: Building Status Integration

> **Epic**: Logistics System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0011: Logistics System — Carrier FSM and Route Architecture, ADR-0008: Building Placement and Production System
**ADR Decision Summary**: Logistics System drives building status through BuildingRegistry API. Status writes during `_advance_tick()` step 3 (after building production step 2). States: BLOCKED (no input carrier), STALLED (no output carrier or destination full), OPERATING (normal). On route deletion/deactivation, corresponding slot is freed and building status may degrade.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None. Cross-system via `Engine.get_singleton("BuildingRegistry")`.

**Control Manifest Rules (Feature Layer)**:
- Required: 4-stage building lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH)
- Required: Single gate placement validation via GridMap.validate_placement()
- Required: Production carrier transport — output buffered, carrier collects and deposits
- Forbidden: Never use TileMap for rendering — always TileMapLayer

---

## Acceptance Criteria

*From GDD `design/gdd/logistics-system.md`, scoped to this story:*

- [ ] Building with no carrier on output slot that completes a production cycle transitions to STALLED
- [ ] Building with no carrier on any input slot transitions to BLOCKED
- [ ] Building with assigned carriers that are functioning transitions to OPERATING
- [ ] When a route is deleted or deactivated, the corresponding slot is freed and building status re-evaluated (may transition to BLOCKED or STALLED)
- [ ] When output carrier is assigned but destination is full (WAITING_DESTINATION), building transitions to STALLED
- [ ] Building status is updated during the tick processing loop (step 3, after building production in step 2) to prevent race conditions

---

## Implementation Notes

*Derived from ADR-0011 Implementation Guidelines:*

**Status update function** (from ADR-0011):
```
func _update_building_status(route: LogisticsRoute):
    var br = Engine.get_singleton("BuildingRegistry")
    match route.carrier_state:
        IDLE, TRAVEL_TO_SOURCE, TRAVEL_TO_DESTINATION, RETURN_HOME:
            // Carrier in transit — building stays at current status
            pass
        WAITING_DESTINATION:
            // Destination full — building is STALLED
            br.set_status(route.destination_building_id,
                BuildingRegistry.Status.STALLED)
        _:
            // Active transit — building OPERATING
            br.set_status(route.destination_building_id,
                BuildingRegistry.Status.OPERATING)

func _on_route_active_changed(route: LogisticsRoute):
    var br = Engine.get_singleton("BuildingRegistry")
    if not route.active:
        if route.route_type == RouteType.INPUT:
            br.set_status(route.destination_building_id,
                BuildingRegistry.Status.BLOCKED)
        elif route.route_type == RouteType.OUTPUT:
            br.set_status(route.source_building_id,
                BuildingRegistry.Status.STALLED)
    else:
        // Carrier active — building system evaluates production independently
        pass
```

**Slot freeing on route deletion** (from GDD Core Rules 6): When a route is deleted or deactivated, the corresponding slot is freed. If this causes the building to lose all its input carriers, the building transitions to BLOCKED. If the building loses all output carriers, it transitions to STALLED once the buffer fills (not immediately — the buffer must fill first).

**Important distinction**: When an OUTPUT carrier route is deactivated, the building doesn't immediately go STALLED. It only goes STALLED when the output buffer fills (production cycle completes but nothing collects). This is a nuance from the GDD: "If the building loses all output carriers, it transitions to STALLED once the buffer fills."

**Tick ordering for status writes**: Status writes execute during `_advance_tick()` step 3, after building production completes (step 2). This prevents race conditions where the carrier sees stale building state.

**BuildingRegistry API** (from ADR-0008):
```
BuildingRegistry.Status = { OPERATING, BLOCKED, STALLED, CONSTRUCTING, DEMOLISHED }
```

**Multiple routes per building**: A building can have both an INPUT route and an OUTPUT route. Each route independently affects status. If the INPUT route is active (carrier assigned and functioning), the building is not BLOCKED. If the OUTPUT route is active, the building is not STALLED. Both must be true for OPERATING.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Route model and slot validation (the routes that drive status)
- [Story 002]: Carrier FSM core loop (the carrier states that map to status)
- [Story 006]: Visual rendering of status indicators (route lines and building colors)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**Status transitions:**

- **AC-1**: Building with no output carrier goes STALLED after production completes
  - Given: Lumber Camp in OPERATING state, completes production cycle (buffer has 5 Wood), OUTPUT route exists but carrier is IDLE (just assigned, hasn't started trip)
  - When: Production cycle completes, buffer has output, carrier hasn't arrived yet
  - Then: If carrier is already AT_SOURCE or TRAVEL_TO_DESTINATION (in transit) → building stays OPERATING (carrier is actively collecting)
  - Then: If carrier is IDLE and hasn't started TRAVEL_TO_SOURCE → building transitions to STALLED
  - Edge cases: Carrier in TRAVEL_TO_SOURCE (en route) — is this STALLED or OPERATING? Per ADR-0011, carriers in transit show OPERATING status; only WAITING_DESTINATION triggers STALLED

- **AC-2**: Building with no input carrier transitions to BLOCKED
  - Given: Sawmill needs input (wood), has an INPUT route with assigned carrier
  - When: Route is deleted (player removes route)
  - Then: Building immediately transitions to BLOCKED (no free input)
  - Edge cases: Route PAUSED (not deleted) — should the building go BLOCKED? Per ADR-0011 _on_route_active_changed, inactive routes cause BLOCKED regardless of paused/deactivated distinction

- **AC-3**: DESTINATION full → STALLED
  - Given: Carrier in WAITING_DESTINATION state, destination storage full
  - When: Carrier state is WAITING_DESTINATION
  - Then: Destination building transitions to STALLED
  - Edge cases: If destination is a production building (not storage), it goes STALLED because its own input isn't draining (carrier can't deliver)

- **AC-4**: Route deletion frees slot
  - Given: Building "sawmill" has 1 INPUT route active
  - When: Route is deleted
  - Then: Slot freed, building immediately re-evaluated, if no other input carrier → BLOCKED
  - Edge cases: Route deactivated (not deleted) — same behavior per _on_route_active_changed

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/logistics/building_status_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (route model), Story 002 (carrier FSM states)
- Unlocks: Story 006 (visualization uses building status values)
